require 'minitest/autorun'
require_relative 'support/fixtures'

# Regression coverage for the ZB Smart Gizmo Pro Z-axis scaling bug.
#
# Root cause: zb_smart_gizmo_pro/overlay.rb's on_transform handler calls
# `smart_scale_log(...)` whenever a Smart Scale drag can't be applied
# (no usable stretch profile, out-of-range ratio, etc) -- an expected,
# designed-for outcome that's meant to fall through to a normal scale
# transform afterwards. `smart_scale_log` was never defined anywhere in
# the codebase, so that fallthrough raised NoMethodError instead,
# aborting the whole mouse-move event before the fallback transform
# ever ran. Reported symptom: dragging the Z handle on a structured
# Dynamic Component does nothing, while a direct `instance.transform!`
# and other tools (Curic Scale) scale it fine.
class SmartScaleGizmoTest < Minitest::Test
  def setup
    @model = Sketchup::Model.new
    Zbellbound::SmartGizmoPro::PLUGIN.test_smart_scale_enabled = false
    Zbellbound::SmartGizmoPro::PLUGIN.test_gizmo_orientation = Zbellbound::SmartGizmoPro::GLOBAL_ORIENTATION
  end

  def select(*entities)
    @model.selection.instance_variable_set(:@list, entities)
  end

  def build_overlay
    TestHarness.build_overlay(model: @model, selection: @model.selection)
  end

  # -- 1. Ordinary component Z scaling -------------------------------

  def test_ordinary_component_scales_in_z
    instance = TestFixtures.ordinary_component
    select(instance)
    overlay = build_overlay

    before_z = instance.bounds.max.z - instance.bounds.min.z
    origin = instance.bounds.min
    TestHarness.drive_scale_drag(overlay, axis_id: :z, ratio: 1.01, origin: origin)
    after_z = instance.bounds.max.z - instance.bounds.min.z

    assert_in_delta before_z * 1.01, after_z, 1e-6
  end

  def test_ordinary_component_scales_in_z_with_smart_scale_enabled
    Zbellbound::SmartGizmoPro::PLUGIN.test_smart_scale_enabled = true
    instance = TestFixtures.ordinary_component
    select(instance)
    overlay = build_overlay

    before_z = instance.bounds.max.z - instance.bounds.min.z
    origin = instance.bounds.min
    TestHarness.drive_scale_drag(overlay, axis_id: :z, ratio: 1.01, origin: origin)
    after_z = instance.bounds.max.z - instance.bounds.min.z

    assert_in_delta before_z * 1.01, after_z, 1e-6
  end

  # -- 2. Dynamic Component with _lenz_access = LIST -------------------

  def test_dynamic_component_with_lenz_access_list_scales_in_z
    Zbellbound::SmartGizmoPro::PLUGIN.test_smart_scale_enabled = true
    instance = TestFixtures.dynamic_component_post
    select(instance)
    overlay = build_overlay

    before_z = instance.bounds.max.z - instance.bounds.min.z
    origin = instance.bounds.min

    TestHarness.drive_scale_drag(overlay, axis_id: :z, ratio: 1.01, origin: origin)

    after_z = instance.bounds.max.z - instance.bounds.min.z
    assert_in_delta 98.733465, after_z, 1e-3,
      'DC with _lenz_access=LIST must scale exactly like the plain instance.transform! console test'
    assert_in_delta before_z * 1.01, after_z, 1e-6
  end

  def test_dynamic_component_drag_does_not_raise_and_does_not_log_without_debug_mode
    Zbellbound::SmartGizmoPro::PLUGIN.test_smart_scale_enabled = true
    instance = TestFixtures.dynamic_component_post
    select(instance)
    overlay = build_overlay
    origin = instance.bounds.min

    original_stderr = $stderr
    $stderr = StringIO.new
    begin
      TestHarness.drive_scale_drag(overlay, axis_id: :z, ratio: 1.01, origin: origin)
      captured = $stderr.string
    ensure
      $stderr = original_stderr
    end

    assert_empty captured, 'no Ruby Console output expected with DEBUG_MODE off'
  end

  def test_dynamic_component_attributes_are_untouched_by_scaling
    Zbellbound::SmartGizmoPro::PLUGIN.test_smart_scale_enabled = true
    instance = TestFixtures.dynamic_component_post
    select(instance)
    overlay = build_overlay
    origin = instance.bounds.min

    before_attrs = instance.attribute_dictionary('dynamic_attributes', false).dup
    TestHarness.drive_scale_drag(overlay, axis_id: :z, ratio: 1.01, origin: origin)
    after_attrs = instance.attribute_dictionary('dynamic_attributes', false)

    assert_equal before_attrs, after_attrs
  end

  # Any selected Group/ComponentInstance with nothing Smart Scale can
  # build a stretch profile from (no straight edges, no nested children --
  # here, a plain empty component) makes
  # build_smart_scale_gesture_state_for_entity return nil. That's a
  # designed, expected outcome, not the curved-geometry case used above --
  # this pins the general defect class: *any* time the smart-scale
  # gesture can't be built or applied, the handler must fall through
  # cleanly instead of raising.
  def test_gesture_build_failure_falls_back_instead_of_raising
    Zbellbound::SmartGizmoPro::PLUGIN.test_smart_scale_enabled = true
    definition = Sketchup::ComponentDefinition.new('Empty')
    instance = Sketchup::ComponentInstance.new(definition)
    select(instance)
    overlay = build_overlay

    assert_silent_raise do
      TestHarness.drive_scale_drag(overlay, axis_id: :z, ratio: 1.01, origin: ORIGIN.clone)
    end
  end

  # Same defect, multi-selection branch (a separate `smart_scale_log`
  # call site at overlay.rb:898).
  def test_multi_selection_gesture_build_failure_falls_back_instead_of_raising
    Zbellbound::SmartGizmoPro::PLUGIN.test_smart_scale_enabled = true
    empty_a = Sketchup::ComponentInstance.new(Sketchup::ComponentDefinition.new('EmptyA'))
    empty_b = Sketchup::ComponentInstance.new(Sketchup::ComponentDefinition.new('EmptyB'))
    select(empty_a, empty_b)
    overlay = build_overlay

    assert_silent_raise do
      TestHarness.drive_scale_drag(overlay, axis_id: :z, ratio: 1.01, origin: ORIGIN.clone)
    end
  end

  # -- 3. Rotated component axes ---------------------------------------

  def test_rotated_component_scales_along_world_z
    instance = TestFixtures.ordinary_component
    instance.transformation = Geom::Transformation.rotation(ORIGIN, Z_AXIS, 40.degrees)
    select(instance)
    overlay = build_overlay

    before_min = instance.bounds.min
    before_max = instance.bounds.max
    before_z = before_max.z - before_min.z

    origin = before_min
    TestHarness.drive_scale_drag(overlay, axis_id: :z, ratio: 1.01, origin: origin)

    after_z = instance.bounds.max.z - instance.bounds.min.z
    assert_in_delta before_z * 1.01, after_z, 1e-6

    # Rotation about Z is preserved: the instance's own zaxis is still +Z,
    # and its xaxis is still tilted (not snapped back to world X).
    assert_in_delta 1.0, instance.transformation.zaxis.z, 1e-6
    refute_in_delta 1.0, instance.transformation.xaxis.x.abs, 1e-6
  end

  # -- 4. Existing non-uniform transformation ---------------------------

  def test_existing_non_uniform_transformation_is_preserved_and_extended
    instance = TestFixtures.ordinary_component
    instance.transformation = Geom::Transformation.scaling(ORIGIN, 2.0, 1.0, 1.0)
    select(instance)
    overlay = build_overlay

    before_x = instance.bounds.max.x - instance.bounds.min.x
    before_z = instance.bounds.max.z - instance.bounds.min.z

    origin = instance.bounds.min
    TestHarness.drive_scale_drag(overlay, axis_id: :z, ratio: 1.5, origin: origin)

    after_x = instance.bounds.max.x - instance.bounds.min.x
    after_z = instance.bounds.max.z - instance.bounds.min.z

    assert_in_delta before_x, after_x, 1e-6, 'pre-existing non-uniform X scale must be untouched'
    assert_in_delta before_z * 1.5, after_z, 1e-6
  end

  # -- 5. Group scaling ---------------------------------------------------

  def test_group_scales_in_z
    group = TestFixtures.group_box
    select(group)
    overlay = build_overlay

    before_z = group.bounds.max.z - group.bounds.min.z
    origin = group.bounds.min
    TestHarness.drive_scale_drag(overlay, axis_id: :z, ratio: 1.01, origin: origin)
    after_z = group.bounds.max.z - group.bounds.min.z

    assert_in_delta before_z * 1.01, after_z, 1e-6
  end

  def test_group_scales_in_z_with_smart_scale_enabled
    Zbellbound::SmartGizmoPro::PLUGIN.test_smart_scale_enabled = true
    group = TestFixtures.group_box
    select(group)
    overlay = build_overlay

    before_z = group.bounds.max.z - group.bounds.min.z
    origin = group.bounds.min
    TestHarness.drive_scale_drag(overlay, axis_id: :z, ratio: 1.01, origin: origin)
    after_z = group.bounds.max.z - group.bounds.min.z

    assert_in_delta before_z * 1.01, after_z, 1e-6
  end

  # -- 6. Locked object rejection ------------------------------------------

  def test_locked_component_is_not_scaled
    instance = TestFixtures.ordinary_component
    instance.locked = true
    select(instance)
    overlay = build_overlay

    before_z = instance.bounds.max.z - instance.bounds.min.z
    origin = instance.bounds.min
    TestHarness.drive_scale_drag(overlay, axis_id: :z, ratio: 1.01, origin: origin)
    after_z = instance.bounds.max.z - instance.bounds.min.z

    assert_in_delta before_z, after_z, 1e-9, 'locked instance must not be scaled'
  end

  # -- Undo: single clean operation ---------------------------------------

  def test_drag_produces_a_single_clean_undo_operation
    instance = TestFixtures.ordinary_component
    select(instance)
    overlay = build_overlay
    origin = instance.bounds.min

    TestHarness.drive_scale_drag(overlay, axis_id: :z, ratio: 1.01, origin: origin)

    starts = @model.operation_log.count { |entry| entry[0] == :start }
    commits = @model.operation_log.count { |entry| entry[0] == :commit }
    aborts = @model.operation_log.count { |entry| entry[0] == :abort }

    assert_equal 1, starts
    assert_equal 1, commits
    assert_equal 0, aborts
  end

  def test_dc_drag_with_failed_smart_scale_still_produces_a_single_clean_undo_operation
    Zbellbound::SmartGizmoPro::PLUGIN.test_smart_scale_enabled = true
    instance = TestFixtures.dynamic_component_post
    select(instance)
    overlay = build_overlay
    origin = instance.bounds.min

    TestHarness.drive_scale_drag(overlay, axis_id: :z, ratio: 1.01, origin: origin)

    starts = @model.operation_log.count { |entry| entry[0] == :start }
    commits = @model.operation_log.count { |entry| entry[0] == :commit }
    aborts = @model.operation_log.count { |entry| entry[0] == :abort }

    assert_equal 1, starts
    assert_equal 1, commits
    assert_equal 0, aborts
  end

  private

  def assert_silent_raise
    yield
    pass 'no exception raised'
  rescue StandardError => e
    flunk "Expected no exception, but #{e.class} was raised: #{e.message}"
  end
end
