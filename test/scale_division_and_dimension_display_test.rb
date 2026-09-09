require 'minitest/autorun'
require 'stringio'
require_relative 'support/fixtures'

# Coverage for two Scale improvements to the axis-based (single-axis)
# Scale handle:
#
# 1. Division input: typing "/2" (etc.) in Measurements after a Scale
#    drag or click divides the CURRENTLY DISPLAYED dimension by that
#    divisor -- see GizmoOverlay#parse_scale_division_ratio, hooked into
#    parse_scale_user_text. This is a completely separate parser/syntax
#    from the Ctrl-drag internal copy-array's own "/N" (see
#    CTRL_DRAG_ARRAY_SLASH_* / parse_ctrl_drag_array_count in overlay.rb
#    and test/ctrl_drag_internal_array_test.rb) -- the two never
#    interact: the Ctrl-drag array's session is only ever built for
#    :move actions, so it's simply absent whenever a :scale re-edit is
#    in progress.
# 2. Dimension display: the Scale VCB now shows the resulting physical
#    dimension (reference_length * ratio, formatted via the documented
#    Sketchup.format_length) instead of a raw unitless ratio -- see
#    GizmoOverlay#format_scale_display.
class ScaleDivisionAndDimensionDisplayTest < Minitest::Test
  def setup
    @model = Sketchup::Model.new
    Zbellbound::SmartGizmoPro::PLUGIN.test_smart_scale_enabled = false
    Zbellbound::SmartGizmoPro::PLUGIN.test_gizmo_orientation = Zbellbound::SmartGizmoPro::GLOBAL_ORIENTATION
    UI.last_messagebox_text = nil
    Sketchup.last_vcb_label = nil
    Sketchup.last_vcb_value = nil
    TestUnits.reset!
  end

  def select(*entities)
    @model.selection.instance_variable_set(:@list, entities)
  end

  def build_overlay
    TestHarness.build_overlay(model: @model, selection: @model.selection)
  end

  def operation_counts
    starts = @model.operation_log.count { |entry| entry[0] == :start }
    commits = @model.operation_log.count { |entry| entry[0] == :commit }
    aborts = @model.operation_log.count { |entry| entry[0] == :abort }
    [starts, commits, aborts]
  end

  # Drives a single-axis Scale drag (reference length fixed at 1 inch by
  # TestHarness.drive_scale_drag), then types `text` into Measurements,
  # matching the real Ctrl-drag-copy-array tests' style of driving
  # on_transform/on_transform_end directly and calling onUserText for
  # the typed follow-up.
  def drive_then_type(entity, ratio:, text:, axis_id: :z)
    select(entity)
    overlay = build_overlay
    origin = entity.bounds.min
    TestHarness.drive_scale_drag(overlay, axis_id: axis_id, ratio: ratio, origin: origin)
    overlay.onUserText(text, @model.active_view)
    overlay
  end

  def axis_dimension(entity, axis_id)
    case axis_id
    when :x then entity.bounds.max.x - entity.bounds.min.x
    when :y then entity.bounds.max.y - entity.bounds.min.y
    when :z then entity.bounds.max.z - entity.bounds.min.z
    end
  end

  # -- /2, /4: halves/quarters the currently displayed dimension --------

  def test_slash_2_halves_the_current_scale_dimension
    instance = TestFixtures.ordinary_component
    before_z = axis_dimension(instance, :z)

    drive_then_type(instance, ratio: 2.0, text: '/2')

    after_z = axis_dimension(instance, :z)
    assert_in_delta before_z, after_z, 1e-6,
      'ratio 2.0 doubled it, then /2 must halve that back to the original'
  end

  def test_slash_4_divides_the_current_scale_dimension_by_four
    instance = TestFixtures.ordinary_component
    before_z = axis_dimension(instance, :z)

    drive_then_type(instance, ratio: 4.0, text: '/4')

    after_z = axis_dimension(instance, :z)
    assert_in_delta before_z, after_z, 1e-6
  end

  def test_slash_3_divides_by_three_from_a_non_trivial_ratio
    instance = TestFixtures.ordinary_component
    before_z = axis_dimension(instance, :z)

    drive_then_type(instance, ratio: 6.0, text: '/3')

    after_z = axis_dimension(instance, :z)
    assert_in_delta before_z * 2.0, after_z, 1e-6, 'ratio 6.0 then /3 must land on ratio 2.0'
  end

  def test_repeated_division_compounds_from_the_latest_state
    instance = TestFixtures.ordinary_component
    before_z = axis_dimension(instance, :z)
    overlay = nil
    select(instance)
    overlay = build_overlay
    origin = instance.bounds.min
    TestHarness.drive_scale_drag(overlay, axis_id: :z, ratio: 8.0, origin: origin)

    overlay.onUserText('/2', @model.active_view) # ratio 8 -> 4
    overlay.onUserText('/2', @model.active_view) # ratio 4 -> 2

    after_z = axis_dimension(instance, :z)
    assert_in_delta before_z * 2.0, after_z, 1e-6,
      'each "/2" must divide the ratio the PREVIOUS edit just set, not the original drag ratio'
  end

  # -- Division respects the active model units --------------------------

  def test_division_result_is_displayed_using_the_active_model_units
    instance = TestFixtures.ordinary_component
    TestUnits.unit = 'cm'
    TestUnits.precision = 1

    drive_then_type(instance, ratio: 2.0, text: '/2')

    assert_equal 'Scale', Sketchup.last_vcb_label
    assert_equal '2.5', Sketchup.last_vcb_value,
      '1 inch = 2.54cm, rounded to the configured precision, no unit suffix'
  end

  def test_division_result_respects_a_different_unit_and_locale
    instance = TestFixtures.ordinary_component
    TestUnits.unit = 'mm'
    TestUnits.precision = 3
    TestUnits.decimal_separator = ','

    drive_then_type(instance, ratio: 2.0, text: '/2')

    assert_equal '25,4', Sketchup.last_vcb_value,
      'the physical value/precision/locale separator must still reflect mm precisely, with no suffix'
  end

  # -- Invalid division input: rejected safely, geometry untouched -------

  def test_invalid_division_inputs_are_rejected_without_changing_geometry
    ['/0', '/-2', '/', '/abc'].each do |text|
      instance = TestFixtures.ordinary_component
      before_z = axis_dimension(instance, :z)
      UI.last_messagebox_text = nil

      drive_then_type(instance, ratio: 2.0, text: text)

      after_z = axis_dimension(instance, :z)
      assert_in_delta before_z * 2.0, after_z, 1e-6,
        "#{text.inspect} must leave the drag's own ratio-2.0 result untouched, not revert or crash"
      refute_nil UI.last_messagebox_text, "#{text.inspect} must show a message"
    end
  end

  def test_division_is_rejected_for_a_non_single_axis_scale_handle
    instance = TestFixtures.ordinary_component
    select(instance)
    overlay = build_overlay
    origin = instance.bounds.min

    gizmo = TestHarness.gizmo_of(overlay)
    start_cb = gizmo.instance_variable_get(:@callback_start)
    transform_cb = gizmo.instance_variable_get(:@callback)
    end_cb = gizmo.instance_variable_get(:@callback_end)
    start_cb&.call('Scale')
    mask = [true, true, true] # uniform/proportional -- not single-axis
    data = [:scale, origin, 2.0, mask, nil, origin.clone, IDENTITY]
    transform_cb.call(IDENTITY, IDENTITY, data)
    end_cb&.call

    overlay.onUserText('/2', @model.active_view)

    refute_nil UI.last_messagebox_text, 'a physical dimension is not meaningful for a uniform scale handle'
  end

  # -- Existing Scale expressions remain unchanged ------------------------

  def test_existing_exact_and_relative_scale_expressions_still_work
    overlay = build_overlay
    data = [:scale, ORIGIN.clone, 1.0, [false, false, true], 600.mm, ORIGIN.clone, IDENTITY]

    assert_in_delta 1.5, overlay.parse_scale_user_text('900mm', data), 1e-6
    assert_in_delta 1.5, overlay.parse_scale_user_text('600mm+300mm', data), 1e-6
    assert_in_delta 1.100667, overlay.parse_scale_user_text('24in+2in', data), 1e-3
    assert_in_delta 1.166667, overlay.parse_scale_user_text('+100mm', data, relative_base: 600.mm), 1e-3
    assert_in_delta 0.833333, overlay.parse_scale_user_text('-100mm', data, relative_base: 600.mm), 1e-3
  end

  def test_existing_plain_ratio_expressions_still_work
    overlay = build_overlay
    data = [:scale, ORIGIN.clone, 1.0, [true, true, true], nil, ORIGIN.clone, IDENTITY]

    assert_in_delta 2.0, overlay.parse_scale_user_text('2', data), 1e-6
    assert_in_delta 0.5, overlay.parse_scale_user_text('0.5', data), 1e-6
  end

  # -- Move-array "/N" (Ctrl-drag internal array) is unaffected -----------

  def test_move_action_ctrl_drag_array_parser_is_untouched_by_scale_division
    overlay = build_overlay

    # parse_ctrl_drag_array_count (the Ctrl-drag "/N" copy-array parser)
    # must still accept exactly what it always has, proving the new
    # Scale-only SCALE_DIVISION_PATTERN/parse_scale_division_ratio are
    # additions, not a shared/modified parser.
    assert_equal 3, overlay.parse_ctrl_drag_array_count('/3')
    assert_equal 3, overlay.parse_ctrl_drag_array_count('3/')
    assert_equal :invalid, overlay.parse_ctrl_drag_array_count('/0')
  end

  # -- Displayed axis Scale values are formatted physical dimensions ------

  def test_plain_scale_drag_displays_a_formatted_dimension_not_a_raw_ratio
    instance = TestFixtures.ordinary_component
    select(instance)
    overlay = build_overlay
    origin = instance.bounds.min

    TestHarness.drive_scale_drag(overlay, axis_id: :z, ratio: 2.0, origin: origin)

    assert_equal 'Scale', Sketchup.last_vcb_label
    assert_equal '50.8', Sketchup.last_vcb_value,
      '1 inch reference * ratio 2.0 = 2in = 50.8mm, shown as a bare number with no unit suffix'
    refute_match(/\A\d+\.\d{4,}\z/, Sketchup.last_vcb_value.to_s,
      'must not be a raw multi-decimal ratio like "4.0005"')
  end

  def test_uniform_scale_drag_falls_back_to_the_plain_ratio_display
    instance = TestFixtures.ordinary_component
    select(instance)
    overlay = build_overlay
    origin = instance.bounds.min

    gizmo = TestHarness.gizmo_of(overlay)
    start_cb = gizmo.instance_variable_get(:@callback_start)
    transform_cb = gizmo.instance_variable_get(:@callback)
    end_cb = gizmo.instance_variable_get(:@callback_end)
    start_cb&.call('Scale')
    data = [:scale, origin, 3.0, [true, true, true], nil, origin.clone, IDENTITY]
    transform_cb.call(IDENTITY, IDENTITY, data)
    end_cb&.call

    assert_equal '3', Sketchup.last_vcb_value,
      'no single physical dimension is meaningful for a uniform-scale handle -- keep the plain ratio, do not invent one'
  end

  # -- No excessive floating-point digits ---------------------------------

  def test_dimension_display_has_no_excessive_floating_point_digits
    instance = TestFixtures.ordinary_component
    select(instance)
    overlay = build_overlay
    origin = instance.bounds.min

    TestHarness.drive_scale_drag(overlay, axis_id: :z, ratio: 1.0001234567, origin: origin)

    value = Sketchup.last_vcb_value.to_s
    decimals = value[/\.(\d+)/, 1]
    refute decimals && decimals.length > TestUnits.precision,
      "expected at most #{TestUnits.precision} decimal digits, got #{value.inspect}"
  end

  # -- Unit suffix removed from the dimension display ---------------------

  def test_992mm_displays_as_bare_992
    instance = TestFixtures.ordinary_component
    select(instance)
    overlay = build_overlay
    origin = instance.bounds.min
    TestUnits.unit = 'mm'
    TestUnits.precision = 0
    # Reference length is fixed at 1 inch by TestHarness.drive_scale_drag,
    # so a ratio of 992mm/25.4 (inches per mm) makes the resulting
    # dimension exactly 992mm.
    ratio = 992.0 / 25.4

    TestHarness.drive_scale_drag(overlay, axis_id: :z, ratio: ratio, origin: origin)

    assert_equal '992', Sketchup.last_vcb_value
  end

  def test_decimal_value_retains_correct_precision_without_suffix
    instance = TestFixtures.ordinary_component
    select(instance)
    overlay = build_overlay
    origin = instance.bounds.min
    TestUnits.unit = 'mm'
    TestUnits.precision = 1

    TestHarness.drive_scale_drag(overlay, axis_id: :z, ratio: 2.0, origin: origin)

    assert_equal '50.8', Sketchup.last_vcb_value
  end

  def test_decimal_comma_formatting_is_preserved_without_suffix
    instance = TestFixtures.ordinary_component
    select(instance)
    overlay = build_overlay
    origin = instance.bounds.min
    TestUnits.unit = 'mm'
    TestUnits.precision = 1
    TestUnits.decimal_separator = ','

    TestHarness.drive_scale_drag(overlay, axis_id: :z, ratio: 2.0, origin: origin)

    assert_equal '50,8', Sketchup.last_vcb_value
  end

  # Inches/feet use the quote-mark symbols ('"'/"'") as their Decimal-
  # format suffix, not letters -- the exact case the "avoid a fragile
  # blanket deletion of letters" caution is about. Confirms the strip
  # still works safely for these, not just the letter-suffixed units.
  def test_other_model_units_are_handled_safely
    instance = TestFixtures.ordinary_component
    select(instance)
    overlay = build_overlay
    origin = instance.bounds.min
    TestUnits.unit = 'in'
    TestUnits.precision = 2

    TestHarness.drive_scale_drag(overlay, axis_id: :z, ratio: 2.0, origin: origin)

    assert_equal '2', Sketchup.last_vcb_value, 'reference 1in * ratio 2.0 = 2in, no trailing quote mark'
  end

  def test_feet_unit_is_handled_safely
    instance = TestFixtures.ordinary_component
    select(instance)
    overlay = build_overlay
    origin = instance.bounds.min
    TestUnits.unit = 'ft'
    TestUnits.precision = 2

    TestHarness.drive_scale_drag(overlay, axis_id: :z, ratio: 24.0, origin: origin)

    assert_equal '2', Sketchup.last_vcb_value, 'reference 1in * ratio 24 = 24in = 2ft, no trailing apostrophe'
  end

  # -- No model unit preference is modified --------------------------------

  def test_stripping_the_suffix_never_modifies_the_models_units_preferences
    instance = TestFixtures.ordinary_component
    select(instance)
    overlay = build_overlay
    origin = instance.bounds.min
    before = @model.options['UnitsOptions'].dup

    TestHarness.drive_scale_drag(overlay, axis_id: :z, ratio: 2.0, origin: origin)

    after = @model.options['UnitsOptions']
    assert_equal before, after
    assert_equal false, after['SuppressUnitsDisplay'],
      'SuppressUnitsDisplay must never be toggled to achieve the bare-number display'
  end

  # -- Undo remains a single operation -------------------------------------

  def test_division_re_edit_is_a_single_undo_operation
    instance = TestFixtures.ordinary_component
    select(instance)
    overlay = build_overlay
    origin = instance.bounds.min
    TestHarness.drive_scale_drag(overlay, axis_id: :z, ratio: 2.0, origin: origin)

    starts_before, commits_before, = operation_counts
    overlay.onUserText('/2', @model.active_view)
    starts_after, commits_after, aborts_after = operation_counts

    assert_equal starts_before + 1, starts_after
    assert_equal commits_before + 1, commits_after
    assert_equal 0, aborts_after
  end

  # -- Ruby Console stays empty in production ------------------------------

  def test_division_produces_no_console_output
    instance = TestFixtures.ordinary_component
    select(instance)
    overlay = build_overlay
    origin = instance.bounds.min
    TestHarness.drive_scale_drag(overlay, axis_id: :z, ratio: 2.0, origin: origin)

    original_stderr = $stderr
    $stderr = StringIO.new
    begin
      overlay.onUserText('/2', @model.active_view)
      captured = $stderr.string
    ensure
      $stderr = original_stderr
    end

    assert_empty captured
  end

  def test_invalid_division_produces_no_console_output
    instance = TestFixtures.ordinary_component
    select(instance)
    overlay = build_overlay
    origin = instance.bounds.min
    TestHarness.drive_scale_drag(overlay, axis_id: :z, ratio: 2.0, origin: origin)

    original_stderr = $stderr
    $stderr = StringIO.new
    begin
      overlay.onUserText('/0', @model.active_view)
      captured = $stderr.string
    ensure
      $stderr = original_stderr
    end

    assert_empty captured
  end
end
