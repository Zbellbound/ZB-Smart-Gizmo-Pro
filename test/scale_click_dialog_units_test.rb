require 'minitest/autorun'
require_relative 'support/fixtures'

# Defect 1: the click-activated single-axis Scale dialog (UI.inputbox,
# opened by GizmoOverlay#scale_default_value via the @gizmo.on_click
# handler in bind_gizmo_callbacks) still showed its current/default
# dimension with a unit suffix (e.g. "992mm") after v1.5.1 fixed the
# Measurements/VCB box to show a bare number ("992") for the same
# handle. Root cause: scale_default_value called a separate, older
# formatter (format_length_in_scale_unit, keyed off PLUGIN.
# scale_input_unit -- an unrelated preference for how a *typed*
# unit-less number is interpreted) instead of the VCB's own
# format_scale_display/strip_scale_display_unit_suffix pair. Fixed by
# having scale_default_value call format_scale_display(1.0, reference)
# -- the same helper, reused, not a second formatter.
class ScaleClickDialogUnitsTest < Minitest::Test
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

  # Fires the real on_click callback for a single-axis Scale handle click
  # (the actual code path a user clicking a Scale handle runs), with the
  # (fake) gizmo's bounds set to the instance's own bounds so
  # scale_reference_length -- and therefore scale_default_value -- computes
  # a real reference dimension, matching what a real single-axis Scale
  # handle click provides. Returns [overlay, UI.last_inputbox_args].
  def click_scale_handle(instance, axis_id: :z)
    select(instance)
    overlay = build_overlay
    gizmo = TestHarness.gizmo_of(overlay)
    gizmo.bounds = instance.bounds
    mask = case axis_id
           when :x then [true, false, false]
           when :y then [false, true, false]
           when :z then [false, false, true]
           end
    callback_click = gizmo.instance_variable_get(:@callback_click)
    refute_nil callback_click, 'bind_gizmo_callbacks must have registered an on_click handler'
    UI.last_inputbox_args = nil
    callback_click.call([:scale, instance.bounds.min, 1, mask])
    [overlay, UI.last_inputbox_args]
  end

  # -- Dialog default omits the unit suffix --------------------------------

  def test_click_dialog_default_omits_mm_suffix
    instance = TestFixtures.ordinary_component(x_size: 10.mm, y_size: 10.mm, z_size: 992.mm)
    TestUnits.unit = 'mm'
    TestUnits.precision = 0

    _overlay, args = click_scale_handle(instance, axis_id: :z)
    refute_nil args, 'UI.inputbox must have been called'
    _prompts, defaults, = args
    assert_equal '992', defaults[0]
  end

  def test_click_dialog_default_preserves_decimal_precision
    instance = TestFixtures.ordinary_component(x_size: 10.mm, y_size: 10.mm, z_size: 5.4.mm)
    TestUnits.unit = 'mm'
    TestUnits.precision = 1

    _overlay, args = click_scale_handle(instance, axis_id: :z)
    _prompts, defaults, = args
    assert_equal '5.4', defaults[0]
  end

  def test_click_dialog_default_preserves_decimal_comma_locale
    instance = TestFixtures.ordinary_component(x_size: 10.mm, y_size: 10.mm, z_size: 5.4.mm)
    TestUnits.unit = 'mm'
    TestUnits.precision = 1
    TestUnits.decimal_separator = ','

    _overlay, args = click_scale_handle(instance, axis_id: :z)
    _prompts, defaults, = args
    assert_equal '5,4', defaults[0]
  end

  def test_click_dialog_default_has_no_suffix_for_other_units
    instance = TestFixtures.ordinary_component(x_size: 10.mm, y_size: 10.mm, z_size: 2.0)
    TestUnits.unit = 'in'
    TestUnits.precision = 2

    _overlay, args = click_scale_handle(instance, axis_id: :z)
    _prompts, defaults, = args
    assert_equal '2', defaults[0]
  end

  # -- Uniform/proportional (non-single-axis) handle: unaffected ----------

  def test_click_dialog_default_is_plain_ratio_for_uniform_handle
    instance = TestFixtures.ordinary_component
    select(instance)
    overlay = build_overlay
    gizmo = TestHarness.gizmo_of(overlay)
    gizmo.bounds = instance.bounds
    callback_click = gizmo.instance_variable_get(:@callback_click)

    UI.last_inputbox_args = nil
    callback_click.call([:scale, instance.bounds.min, 1, [true, true, true]])

    _prompts, defaults, = UI.last_inputbox_args
    assert_equal 1.0, defaults[0], 'no single physical dimension is meaningful here -- keep the plain ratio default'
  end

  # -- Measurements-box and click-dialog formatting stay consistent -------

  def test_click_dialog_default_matches_vcb_formatting_for_the_same_handle
    instance = TestFixtures.ordinary_component(x_size: 10.mm, y_size: 10.mm, z_size: 50.8.mm)
    TestUnits.unit = 'mm'
    TestUnits.precision = 1

    overlay, args = click_scale_handle(instance, axis_id: :z)
    _prompts, defaults, = args

    # The VCB (Measurements box) shows the same "current dimension" via
    # format_scale_display(ratio, reference_length) -- a fresh click's
    # ratio is 1.0, so it must format identically to the dialog default
    # for the very same reference length (the instance's own Z size).
    # Not driven via TestHarness.drive_scale_drag here since that helper
    # hardcodes its reference length to 1 inch, unrelated to this
    # instance's actual size -- this test is about the two formatters
    # agreeing for the SAME reference, not about the drag path itself.
    reference = instance.bounds.max.z - instance.bounds.min.z
    vcb_value = overlay.format_scale_display(1.0, reference)

    assert_equal vcb_value, defaults[0]
  end

  # -- Explicit typed units and expressions still parse correctly ---------
  # (parse_scale_user_text/parse_smart_scale_ratio themselves are untouched
  # by this fix -- these pin that scale_default_value's formatting change
  # didn't alter how typed input is interpreted.)

  def test_explicit_typed_unit_values_still_parse_correctly
    overlay = build_overlay
    data = [:scale, ORIGIN.clone, 1.0, [false, false, true], 600.mm, ORIGIN.clone, IDENTITY]

    assert_in_delta 1.5, overlay.parse_scale_user_text('900mm', data), 1e-6
    assert_in_delta 1.100667, overlay.parse_scale_user_text('24in+2in', data), 1e-3
  end

  def test_slash_division_from_the_click_dialog_still_divides_correctly
    instance = TestFixtures.ordinary_component
    select(instance)
    overlay = build_overlay
    gizmo = TestHarness.gizmo_of(overlay)
    gizmo.bounds = instance.bounds
    before_z = instance.bounds.max.z - instance.bounds.min.z

    callback_click = gizmo.instance_variable_get(:@callback_click)
    callback_click.call([:scale, instance.bounds.min, 1, [false, false, true]])

    inputbox_args = UI.last_inputbox_args
    refute_nil inputbox_args, 'UI.inputbox must have been called for the click'

    # Real UI.inputbox always returns nil in this test double (see
    # sketchup_stubs.rb) -- exercise the same parser the callback feeds
    # the typed result through, matching how the existing division tests
    # (scale_division_and_dimension_display_test.rb) drive re-edit text.
    overlay.instance_variable_set(:@last_transform, [IDENTITY, IDENTITY, [:scale, instance.bounds.min, 1.0, [false, false, true], instance.bounds.max.z - instance.bounds.min.z, instance.bounds.min.clone, IDENTITY]])
    Zbellbound::SmartGizmoPro::PLUGIN.test_smart_scale_enabled = false
    overlay.onUserText('/2', @model.active_view)

    after_z = instance.bounds.max.z - instance.bounds.min.z
    assert_in_delta before_z / 2.0, after_z, 1e-6
  end

  # -- No second formatter was introduced -----------------------------------

  def test_format_length_in_scale_unit_was_removed_not_duplicated
    overlay = build_overlay
    refute overlay.respond_to?(:format_length_in_scale_unit),
      'scale_default_value must reuse format_scale_display, not keep a second formatter around'
  end
end
