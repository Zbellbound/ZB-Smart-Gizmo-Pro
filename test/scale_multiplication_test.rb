require 'minitest/autorun'
require 'stringio'
require_relative 'support/fixtures'

# "xN" Scale multiplication -- the companion feature to "/N" Scale
# division (see scale_division_and_dimension_display_test.rb): typing
# "x2"/"X2"/"x1.5" etc. in Measurements after a Scale drag or click, or
# in the click-activated Scale dialog, multiplies the CURRENTLY
# DISPLAYED dimension by that factor -- see GizmoOverlay#parse_scale_
# multiplication_ratio, reused by both parse_scale_user_text (plain
# Scale) and parse_smart_scale_ratio (Smart Scale).
#
# Deliberately a SEPARATE parser/pattern from the Ctrl-drag Move
# external-array's own "xN"/"Nx" (CTRL_DRAG_ARRAY_X_PREFIX_PATTERN/
# _SUFFIX_PATTERN, parse_ctrl_drag_external_array_count, gated behind
# @ctrl_array_session -- a Move-only session flag this file's parser
# never reads or touches): "x2" means "multiply the Scale dimension" in
# Scale context and "create an external copy array" in Move context,
# decided purely by which code path is reading the text.
class ScaleMultiplicationTest < Minitest::Test
  def setup
    @model = Sketchup::Model.new
    Zbellbound::SmartGizmoPro::PLUGIN.test_smart_scale_enabled = false
    Zbellbound::SmartGizmoPro::PLUGIN.test_gizmo_orientation = Zbellbound::SmartGizmoPro::GLOBAL_ORIENTATION
    UI.last_messagebox_text = nil
    UI.last_inputbox_args = nil
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

  def with_inputbox_result(result)
    original = UI.method(:inputbox)
    UI.define_singleton_method(:inputbox) do |*args|
      self.last_inputbox_args = args
      result
    end
    yield
  ensure
    UI.define_singleton_method(:inputbox, original)
  end

  # -- x2, X2, x1.5: multiplies the currently displayed dimension --------

  def test_x2_doubles_the_current_scale_dimension
    instance = TestFixtures.ordinary_component
    before_z = axis_dimension(instance, :z)

    drive_then_type(instance, ratio: 1.0, text: 'x2')

    after_z = axis_dimension(instance, :z)
    assert_in_delta before_z * 2.0, after_z, 1e-6
  end

  def test_uppercase_X2_is_accepted
    instance = TestFixtures.ordinary_component
    before_z = axis_dimension(instance, :z)

    drive_then_type(instance, ratio: 1.0, text: 'X2')

    after_z = axis_dimension(instance, :z)
    assert_in_delta before_z * 2.0, after_z, 1e-6
  end

  def test_x1_point_5_multiplies_accurately
    instance = TestFixtures.ordinary_component
    before_z = axis_dimension(instance, :z)

    drive_then_type(instance, ratio: 1.0, text: 'x1.5')

    after_z = axis_dimension(instance, :z)
    assert_in_delta before_z * 1.5, after_z, 1e-6
  end

  def test_x3_from_a_non_trivial_ratio
    instance = TestFixtures.ordinary_component
    before_z = axis_dimension(instance, :z)

    drive_then_type(instance, ratio: 0.5, text: 'x3')

    after_z = axis_dimension(instance, :z)
    assert_in_delta before_z * 1.5, after_z, 1e-6, 'ratio 0.5 then x3 must land on ratio 1.5'
  end

  # -- Invalid multiplication input: rejected safely, geometry untouched --

  def test_invalid_multiplication_inputs_are_rejected_without_changing_geometry
    ['x0', 'x-2', 'x', 'X', 'xabc', 'x2.5.5', '2x'].each do |text|
      instance = TestFixtures.ordinary_component
      before_z = axis_dimension(instance, :z)
      UI.last_messagebox_text = nil

      drive_then_type(instance, ratio: 2.0, text: text)

      after_z = axis_dimension(instance, :z)
      assert_in_delta before_z * 2.0, after_z, 1e-6,
        "#{text.inspect} must leave the drag's own ratio-2.0 result untouched, not apply a bogus multiplier"
      refute_nil UI.last_messagebox_text, "#{text.inspect} must show a message"
    end
  end

  def test_multiplication_is_rejected_for_a_non_single_axis_scale_handle
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

    overlay.onUserText('x2', @model.active_view)

    refute_nil UI.last_messagebox_text, 'a physical dimension is not meaningful for a uniform scale handle'
  end

  # -- "/2" is unaffected by adding "xN" -----------------------------------

  def test_slash_2_still_halves_the_current_scale_dimension
    instance = TestFixtures.ordinary_component
    before_z = axis_dimension(instance, :z)

    drive_then_type(instance, ratio: 2.0, text: '/2')

    after_z = axis_dimension(instance, :z)
    assert_in_delta before_z, after_z, 1e-6
  end

  # -- Repeated operations use the current result --------------------------

  def test_repeated_slash_2_then_x2_then_x3_use_the_current_result
    instance = TestFixtures.ordinary_component(x_size: 10.mm, y_size: 10.mm, z_size: 1000.mm)
    TestUnits.unit = 'mm'
    TestUnits.precision = 0

    select(instance)
    overlay = build_overlay
    origin = instance.bounds.min
    TestHarness.drive_scale_drag(overlay, axis_id: :z, ratio: 1.0, origin: origin)

    # TestHarness.drive_scale_drag hardcodes its own data[4] (reference
    # length) to a fixed 1 inch for simplicity -- fine for the ratio-only
    # tests above, but this test asserts on the literal displayed
    # dimension across a chain of re-edits, so correct the reference to
    # this fixture's true 1000mm dimension, matching what a real
    # single-axis Scale gizmo click/drag would actually provide.
    data = overlay.instance_variable_get(:@last_transform)[2]
    data[4] = 1000.mm

    overlay.onUserText('/2', @model.active_view) # 1000 -> 500
    assert_equal '500', Sketchup.last_vcb_value

    overlay.onUserText('x2', @model.active_view) # 500 -> 1000
    assert_equal '1000', Sketchup.last_vcb_value

    overlay.onUserText('x3', @model.active_view) # 1000 -> 3000
    assert_equal '3000', Sketchup.last_vcb_value
  end

  # -- Click-dialog Scale supports x2 ---------------------------------------

  def test_click_dialog_accepts_x2
    instance = TestFixtures.ordinary_component
    before_z = axis_dimension(instance, :z)
    select(instance)
    overlay = build_overlay
    gizmo = TestHarness.gizmo_of(overlay)
    gizmo.bounds = instance.bounds
    callback_click = gizmo.instance_variable_get(:@callback_click)

    with_inputbox_result(['x2']) do
      callback_click.call([:scale, instance.bounds.min, 1, [false, false, true]])
    end

    assert_nil UI.last_messagebox_text
    after_z = axis_dimension(instance, :z)
    assert_in_delta before_z * 2.0, after_z, 1e-6
  end

  # -- Undo: single clean operation -----------------------------------------

  def test_multiplication_re_edit_is_a_single_undo_operation
    instance = TestFixtures.ordinary_component
    select(instance)
    overlay = build_overlay
    origin = instance.bounds.min
    TestHarness.drive_scale_drag(overlay, axis_id: :z, ratio: 1.0, origin: origin)

    starts_before, commits_before, = operation_counts
    overlay.onUserText('x2', @model.active_view)
    starts_after, commits_after, aborts_after = operation_counts

    assert_equal starts_before + 1, starts_after
    assert_equal commits_before + 1, commits_after
    assert_equal 0, aborts_after
  end

  # -- Ruby Console stays empty in production --------------------------------

  def test_multiplication_produces_no_console_output
    instance = TestFixtures.ordinary_component
    select(instance)
    overlay = build_overlay
    origin = instance.bounds.min
    TestHarness.drive_scale_drag(overlay, axis_id: :z, ratio: 1.0, origin: origin)

    original_stderr = $stderr
    $stderr = StringIO.new
    begin
      overlay.onUserText('x2', @model.active_view)
      captured = $stderr.string
    ensure
      $stderr = original_stderr
    end

    assert_empty captured
  end

  def test_invalid_multiplication_produces_no_console_output
    instance = TestFixtures.ordinary_component
    select(instance)
    overlay = build_overlay
    origin = instance.bounds.min
    TestHarness.drive_scale_drag(overlay, axis_id: :z, ratio: 1.0, origin: origin)

    original_stderr = $stderr
    $stderr = StringIO.new
    begin
      overlay.onUserText('x0', @model.active_view)
      captured = $stderr.string
    ensure
      $stderr = original_stderr
    end

    assert_empty captured
  end

  # -- No crossover with the Move Ctrl-drag external array parser ----------

  def test_scale_x2_never_reads_or_touches_the_move_array_session
    instance = TestFixtures.ordinary_component
    select(instance)
    overlay = build_overlay
    origin = instance.bounds.min
    TestHarness.drive_scale_drag(overlay, axis_id: :z, ratio: 1.0, origin: origin)

    refute overlay.instance_variable_get(:@ctrl_array_session),
      '@ctrl_array_session must be untouched (nil) by a Scale gesture -- it is Move-only'

    before_z = axis_dimension(instance, :z)
    overlay.onUserText('x2', @model.active_view)

    assert_in_delta before_z * 2.0, axis_dimension(instance, :z), 1e-6
    refute overlay.instance_variable_get(:@ctrl_array_session),
      'Scale multiplication must never set the Move-only Ctrl-drag array session'
  end
end
