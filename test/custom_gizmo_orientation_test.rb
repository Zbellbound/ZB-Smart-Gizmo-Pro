require 'minitest/autorun'
require_relative 'support/fixtures'

# Coverage for custom per-instance gizmo orientation ("Align Gizmo XY to
# Face" / "Align Gizmo X to Edge" / "Reset Gizmo Orientation to Object
# Axes"): geometry modeled at an angle and grouped afterward keeps the
# axes it happened to have at grouping time, not the angle it visibly
# sits at -- these commands let the gizmo instead follow the visible
# geometry, without changing the object's real axes, transformation, or
# geometry.
#
# Two layers, matching custom_orientation.rb's own split:
# * CustomOrientationTest drives Zbellbound::SmartGizmoPro::CustomOrientation
#   directly (storage, reconstruction, per-instance isolation,
#   transformation-following, mirrored/non-uniform scale) -- pure Geom/
#   attribute-dictionary math, no overlay or picking involved.
# * CustomGizmoOrientationTest drives the real GizmoOverlay methods
#   (apply_face_alignment/apply_edge_alignment/reset_gizmo_orientation/
#   gizmo_state_for_current_selection) and the real OrientationPickerTool,
#   the same way the rest of this suite drives GizmoOverlay's other
#   context-menu actions and gestures directly rather than simulating real
#   mouse events end to end.
class CustomOrientationTest < Minitest::Test
  P = Zbellbound::SmartGizmoPro
  CO = Zbellbound::SmartGizmoPro::CustomOrientation

  def group
    TestFixtures.group_box
  end

  def test_nothing_stored_returns_nil_for_both_reconstructions
    g = group
    refute CO.stored?(g)
    assert_nil CO.world_axes_for(g)
    assert_nil CO.local_axes_for(g)
  end

  def test_store_and_reconstruct_round_trip_under_identity_transformation
    g = group
    world_x = Geom::Vector3d.new(1, 0, 0)
    world_z = Geom::Vector3d.new(0, 0, 1)

    assert CO.store!(g, world_x, world_z)
    assert CO.stored?(g)

    x, y, z = CO.world_axes_for(g)
    assert_in_delta 1.0, x.dot(world_x), 1e-9
    assert_in_delta 1.0, z.dot(world_z), 1e-9
    assert_in_delta 1.0, y.dot(Geom::Vector3d.new(0, 1, 0)), 1e-9
    assert_in_delta 1.0, x.cross(y).dot(z), 1e-9, 'must be right-handed: x.cross(y) == z'
  end

  def test_reconstruction_follows_a_subsequent_move_and_rotation
    g = group
    assert CO.store!(g, Geom::Vector3d.new(1, 0, 0), Geom::Vector3d.new(0, 0, 1))

    g.transformation = Geom::Transformation.rotation(ORIGIN, Z_AXIS, 90.degrees) *
                        Geom::Transformation.translation(Geom::Vector3d.new(500.mm, 200.mm, 0))

    x, y, z = CO.world_axes_for(g)
    # A 90-degree rotation about Z turns local +X into world +Y; +Z is
    # unaffected by a rotation about its own axis.
    assert_in_delta 1.0, x.dot(Geom::Vector3d.new(0, 1, 0)), 1e-6
    assert_in_delta 1.0, z.dot(Geom::Vector3d.new(0, 0, 1)), 1e-6
    assert_in_delta 1.0, x.cross(y).dot(z), 1e-9
  end

  def test_local_axes_for_ignores_the_instance_transformation
    g = group
    # Stored while the transformation is identity, so world == local here...
    assert CO.store!(g, Geom::Vector3d.new(1, 0, 0), Geom::Vector3d.new(0, 0, 1))
    # ...then the transformation changes AFTER storing: local_axes_for must
    # still return the original untransformed vectors, unlike world_axes_for.
    g.transformation = Geom::Transformation.rotation(ORIGIN, Z_AXIS, 30.degrees)

    x, _y, z = CO.local_axes_for(g)
    assert_in_delta 1.0, x.dot(Geom::Vector3d.new(1, 0, 0)), 1e-6
    assert_in_delta 1.0, z.dot(Geom::Vector3d.new(0, 0, 1)), 1e-6

    world_x, = CO.world_axes_for(g)
    refute_in_delta 1.0, world_x.dot(Geom::Vector3d.new(1, 0, 0)), 1e-3,
      'world_axes_for, unlike local_axes_for, DOES reflect the transformation change'
  end

  def test_two_instances_of_the_same_shared_definition_are_independent
    definition = TestFixtures.ordinary_component.definition
    one = Sketchup::ComponentInstance.new(definition)
    two = Sketchup::ComponentInstance.new(definition)

    assert CO.store!(one, Geom::Vector3d.new(0, 1, 0), Geom::Vector3d.new(0, 0, 1))

    assert CO.stored?(one)
    refute CO.stored?(two), "storing on one instance of a shared component must not affect another"
    assert_nil CO.world_axes_for(two)

    assert CO.reset!(one)
    refute CO.stored?(one)
  end

  def test_mirrored_instance_still_reconstructs_a_valid_right_handed_orthonormal_basis
    g = group
    assert CO.store!(g, Geom::Vector3d.new(1, 0, 0), Geom::Vector3d.new(0, 0, 1))

    # A mirror (negative X scale) -- e.g. SketchUp's own "Flip Along" red.
    g.transformation = Geom::Transformation.scaling(1.0, 1.0, 1.0) # sanity baseline
    g.transformation = Geom::Transformation.new(
      Geom::Vector3d.new(-1, 0, 0), Geom::Vector3d.new(0, 1, 0), Geom::Vector3d.new(0, 0, 1), ORIGIN
    )

    x, y, z = CO.world_axes_for(g)
    assert_in_delta 1.0, x.length, 1e-9
    assert_in_delta 1.0, y.length, 1e-9
    assert_in_delta 1.0, z.length, 1e-9
    assert_in_delta 0.0, x.dot(z), 1e-9
    assert_in_delta 0.0, x.dot(y), 1e-9
    assert_in_delta 1.0, x.cross(y).dot(z), 1e-6, 'must stay right-handed even when the instance is mirrored'
  end

  def test_non_uniformly_scaled_instance_still_reconstructs_orthonormal_axes
    g = group
    assert CO.store!(g, Geom::Vector3d.new(1, 0, 0), Geom::Vector3d.new(0, 0, 1))
    g.transformation = Geom::Transformation.scaling(ORIGIN, 3.0, 0.2, 7.0)

    x, y, z = CO.world_axes_for(g)
    assert_in_delta 1.0, x.length, 1e-9
    assert_in_delta 1.0, z.length, 1e-9
    assert_in_delta 0.0, x.dot(z), 1e-9
    assert_in_delta 1.0, x.cross(y).dot(z), 1e-6
  end

  def test_corrupted_or_malformed_stored_data_falls_back_to_nil_instead_of_raising
    g = group
    g.set_attribute(CO::DICTIONARY_NAME, CO::X_KEY, 'not-an-array')
    g.set_attribute(CO::DICTIONARY_NAME, CO::Z_KEY, [1, 2]) # wrong length
    assert_nil CO.world_axes_for(g)
    assert_nil CO.local_axes_for(g)

    g.set_attribute(CO::DICTIONARY_NAME, CO::X_KEY, [0, 0, 0]) # zero vector
    g.set_attribute(CO::DICTIONARY_NAME, CO::Z_KEY, [0, 0, 1])
    assert_nil CO.world_axes_for(g), 'a zero-length stored vector must be treated as absent'
  end

  def test_reset_removes_only_this_dictionary
    g = group
    g.set_attribute('SomeOtherExtension', 'k', 'v')
    refute CO.reset!(g), 'resetting when nothing is stored is a no-op'

    assert CO.store!(g, Geom::Vector3d.new(1, 0, 0), Geom::Vector3d.new(0, 0, 1))
    assert CO.reset!(g)
    refute CO.stored?(g)
    assert_equal 'v', g.get_attribute('SomeOtherExtension', 'k'), "another extension's own data must survive a reset"
  end

  def test_arbitrary_perpendicular_is_never_degenerate_for_any_axis
    [X_AXIS, Y_AXIS, Z_AXIS, Geom::Vector3d.new(1, 1, 1).normalize].each do |axis|
      perp = CO.arbitrary_perpendicular(axis)
      assert_in_delta 1.0, perp.length, 1e-9
      assert_in_delta 0.0, perp.dot(axis), 1e-9
    end
  end
end

class CustomGizmoOrientationTest < Minitest::Test
  P = Zbellbound::SmartGizmoPro
  CO = Zbellbound::SmartGizmoPro::CustomOrientation
  L = Sketchup::Licensing

  def setup
    @model = Sketchup::Model.new
    P::PLUGIN.test_smart_scale_enabled = false
    P::PLUGIN.test_gizmo_orientation = P::GLOBAL_ORIENTATION
    UI.last_messagebox_text = nil
    UI.started_timers = []
    UI.timer_blocks = []
    L.reset!
  end

  def teardown
    L.reset!
  end

  def select(entity)
    @model.selection.instance_variable_set(:@list, [entity])
  end

  def build_overlay_with(entity)
    select(entity)
    TestHarness.build_overlay(model: @model, selection: @model.selection)
  end

  # A square, planar face in LOCAL space, normal +Z, whose boundary runs at
  # 45 degrees to the group's own local X/Y axes -- exactly the "modeled at
  # an angle, then grouped" scenario this whole feature targets, so a
  # correct alignment is visibly different from the object's native axes
  # even when the group's own transformation is plain (untranslated,
  # unrotated).
  def build_diamond_top_face
    d = 10 * Math.sqrt(0.5)
    p0 = Geom::Point3d.new(0, 0, 5)
    p1 = Geom::Point3d.new(d, d, 5)
    p2 = Geom::Point3d.new(0, 2 * d, 5)
    p3 = Geom::Point3d.new(-d, d, 5)
    edges = [Sketchup::Edge.new(p0, p1), Sketchup::Edge.new(p1, p2),
             Sketchup::Edge.new(p2, p3), Sketchup::Edge.new(p3, p0)]
    [Sketchup::Face.new(edges, Geom::Vector3d.new(0, 0, 1)), p0, p1, p2, p3]
  end

  def operation_starts
    @model.operation_log.select { |entry| entry[0] == :start }
  end

  # -- Face alignment -----------------------------------------------------

  def test_align_face_stores_the_normal_as_z_and_the_nearest_edge_as_x
    g = TestFixtures.group_box
    g.transformation = Geom::Transformation.rotation(ORIGIN, Z_AXIS, 40.degrees) *
                        Geom::Transformation.translation(Geom::Vector3d.new(1.m, 0, 0))
    overlay = build_overlay_with(g)
    face, p0, p1, = build_diamond_top_face
    hit_position = Geom::Point3d.new((p0.x + p1.x) / 2.0, (p0.y + p1.y) / 2.0, p0.z).transform(g.transformation)

    assert overlay.apply_face_alignment(g, [g, face], hit_position)

    assert CO.stored?(g)
    world_x, _y, world_z = CO.world_axes_for(g)
    expected_z = Geom::Vector3d.new(0, 0, 1).transform(g.transformation).normalize
    expected_x = p0.vector_to(p1).transform(g.transformation).normalize
    assert_in_delta 1.0, world_z.dot(expected_z), 1e-6
    assert_in_delta 1.0, world_x.dot(expected_x), 1e-6
    refute_in_delta 1.0, world_x.dot(g.transformation.xaxis), 1e-2,
      'the diamond face sits at 45 degrees to the native axes -- alignment must actually differ from them'

    assert_equal P::LOCAL_ORIENTATION, P::PLUGIN.gizmo_orientation, 'a successful face align switches to Object orientation'
    assert_equal 1, operation_starts.length
    assert_equal %i[start commit], @model.operation_log.map(&:first)
  end

  def test_align_face_prefers_the_boundary_edge_nearest_the_clicked_point
    g = TestFixtures.group_box
    overlay = build_overlay_with(g)
    face, p0, p1, p2, = build_diamond_top_face

    overlay.apply_face_alignment(g, [g, face], Geom::Point3d.new((p1.x + p2.x) / 2.0, (p1.y + p2.y) / 2.0, p1.z))

    world_x, = CO.world_axes_for(g)
    expected = p1.vector_to(p2).normalize
    assert_in_delta 1.0, world_x.dot(expected), 1e-6,
      'clicking nearer the p1-p2 edge must pick that edge, not the one nearer p0'
  end

  def test_face_alignment_does_not_move_rotate_scale_or_otherwise_touch_the_geometry
    g = TestFixtures.group_box
    original_transformation = g.transformation.to_a
    original_bounds = [g.bounds.min.to_a, g.bounds.max.to_a]
    overlay = build_overlay_with(g)
    face, p0, p1, = build_diamond_top_face

    overlay.apply_face_alignment(g, [g, face], p0.vector_to(p1).length.zero? ? p0 : Geom::Point3d.new((p0.x + p1.x) / 2, (p0.y + p1.y) / 2, p0.z))

    assert_equal original_transformation, g.transformation.to_a
    assert_equal original_bounds, [g.bounds.min.to_a, g.bounds.max.to_a]
  end

  # -- Edge alignment -------------------------------------------------------

  def test_align_edge_preserves_the_current_custom_z_and_only_changes_x
    g = TestFixtures.group_box
    overlay = build_overlay_with(g)
    face, p0, p1, = build_diamond_top_face
    overlay.apply_face_alignment(g, [g, face], Geom::Point3d.new((p0.x + p1.x) / 2, (p0.y + p1.y) / 2, p0.z))
    _x_before, _y_before, z_before = CO.world_axes_for(g)

    other_edge = Sketchup::Edge.new(Geom::Point3d.new(0, 0, 5), Geom::Point3d.new(0, 10, 5)) # local +Y
    assert overlay.apply_edge_alignment(g, [g, other_edge])

    world_x, _y, world_z = CO.world_axes_for(g)
    assert_in_delta 1.0, world_z.dot(z_before), 1e-9, 'Z must be unchanged by an edge-align'
    assert_in_delta 1.0, world_x.dot(Geom::Vector3d.new(0, 1, 0)), 1e-6
  end

  def test_align_edge_without_a_prior_face_align_preserves_the_native_z
    g = TestFixtures.group_box
    g.transformation = Geom::Transformation.rotation(ORIGIN, Y_AXIS, 15.degrees)
    overlay = build_overlay_with(g)
    edge = Sketchup::Edge.new(Geom::Point3d.new(0, 0, 0), Geom::Point3d.new(1, 0, 0))

    assert overlay.apply_edge_alignment(g, [g, edge])

    _x, _y, world_z = CO.world_axes_for(g)
    assert_in_delta 1.0, world_z.dot(g.transformation.zaxis), 1e-6
  end

  def test_align_edge_accepts_an_individual_segment_of_a_curve
    g = TestFixtures.group_box
    overlay = build_overlay_with(g)
    curve_segment = Sketchup::Edge.new(Geom::Point3d.new(0, 0, 0), Geom::Point3d.new(1, 0, 0))
    curve_segment.curve = Object.new # merely flagged as part of a Curve/ArcCurve

    assert overlay.apply_edge_alignment(g, [g, curve_segment]),
      'a single straight segment of a curve is still a valid, usable edge direction'
  end

  def test_align_edge_rejects_an_edge_parallel_to_the_current_z_with_no_model_change
    g = TestFixtures.group_box
    overlay = build_overlay_with(g)
    face, p0, p1, = build_diamond_top_face
    overlay.apply_face_alignment(g, [g, face], Geom::Point3d.new((p0.x + p1.x) / 2, (p0.y + p1.y) / 2, p0.z))
    before_x, before_y, before_z = CO.world_axes_for(g)
    log_before = @model.operation_log.dup

    vertical_edge = Sketchup::Edge.new(Geom::Point3d.new(2, 3, 0), Geom::Point3d.new(2, 3, 5)) # parallel to native Z
    refute overlay.apply_edge_alignment(g, [g, vertical_edge])

    refute_nil UI.last_messagebox_text
    assert_equal log_before, @model.operation_log, 'a rejected edge must not open an Undo operation'
    after_x, after_y, after_z = CO.world_axes_for(g)
    assert_in_delta 1.0, before_x.dot(after_x), 1e-9
    assert_in_delta 1.0, before_y.dot(after_y), 1e-9
    assert_in_delta 1.0, before_z.dot(after_z), 1e-9
  end

  # -- Reset ----------------------------------------------------------------

  def test_reset_removes_only_the_custom_orientation_and_is_a_no_op_when_absent
    g = TestFixtures.group_box
    overlay = build_overlay_with(g)
    g.set_attribute('SomeOtherExtension', 'k', 'v')

    overlay.reset_gizmo_orientation
    assert_empty @model.operation_log, 'resetting when nothing is stored must not open an Undo operation'

    face, p0, p1, = build_diamond_top_face
    overlay.apply_face_alignment(g, [g, face], Geom::Point3d.new((p0.x + p1.x) / 2, (p0.y + p1.y) / 2, p0.z))
    assert CO.stored?(g)

    overlay.reset_gizmo_orientation
    refute CO.stored?(g)
    assert_equal 'v', g.get_attribute('SomeOtherExtension', 'k')
    assert_equal %i[start commit start commit], @model.operation_log.map(&:first)
  end

  # -- Picker completion: finish_orientation_picker / deferred restore -----
  #
  # Regression coverage for the bug where the gizmo stayed hidden after a
  # successful face/edge pick until the user made one extra click. Root
  # cause: SketchUp delivers the ToolsObserver#onActiveToolChanged
  # notification that clears @native_tool_override asynchronously, not
  # synchronously inside pop_tool -- so recomputing gizmo visibility right
  # after popping the picker tool could still see it as hidden.
  # finish_orientation_picker always pops the tool immediately but defers
  # the actual restore to a zero-delay UI.start_timer (UI.timer_blocks in
  # this test double), by which point that notification, if any, has
  # already been delivered.

  def push_fake_picker(overlay, entity, mode = :face)
    tool = P::OrientationPickerTool.new(overlay, mode, entity)
    @model.tools.push_tool(tool)
    tool
  end

  def test_a_successful_face_pick_exits_the_picker_and_schedules_a_gizmo_restore
    g = TestFixtures.group_box
    overlay = build_overlay_with(g)
    overlay.enabled = true
    push_fake_picker(overlay, g, :face)
    overlay.instance_variable_set(:@native_tool_override, true)
    face, p0, p1, = build_diamond_top_face

    assert overlay.apply_face_alignment(g, [g, face], Geom::Point3d.new((p0.x + p1.x) / 2, (p0.y + p1.y) / 2, p0.z))
    overlay.finish_orientation_picker(@model.active_view)

    assert_nil @model.tools.active_tool, 'the picker tool must be popped immediately, not deferred'
    assert overlay.instance_variable_get(:@native_tool_override), 'the actual restore is deferred, not inline'
    assert_equal 1, UI.timer_blocks.length, 'exactly one deferred restore is scheduled'

    UI.timer_blocks.last.call

    refute overlay.instance_variable_get(:@native_tool_override), 'the deferred restore clears the override'
    assert overlay.active_gizmo, 'the gizmo must be visible again without any further click'
  end

  def test_a_successful_edge_pick_exits_the_picker_and_schedules_a_gizmo_restore
    g = TestFixtures.group_box
    overlay = build_overlay_with(g)
    overlay.enabled = true
    push_fake_picker(overlay, g, :edge)
    overlay.instance_variable_set(:@native_tool_override, true)
    edge = Sketchup::Edge.new(Geom::Point3d.new(0, 0, 0), Geom::Point3d.new(1, 0, 0))

    assert overlay.apply_edge_alignment(g, [g, edge])
    overlay.finish_orientation_picker(@model.active_view)

    assert_nil @model.tools.active_tool
    assert_equal 1, UI.timer_blocks.length

    UI.timer_blocks.last.call

    refute overlay.instance_variable_get(:@native_tool_override)
    assert overlay.active_gizmo
  end

  def test_the_selected_object_remains_selected_through_the_whole_picker_flow
    g = TestFixtures.group_box
    overlay = build_overlay_with(g)
    push_fake_picker(overlay, g, :face)
    face, p0, p1, = build_diamond_top_face

    overlay.apply_face_alignment(g, [g, face], Geom::Point3d.new((p0.x + p1.x) / 2, (p0.y + p1.y) / 2, p0.z))
    overlay.finish_orientation_picker(@model.active_view)
    UI.timer_blocks.last.call

    assert_equal [g], @model.selection.to_a, 'the picker flow must never change the selection'
  end

  def test_esc_restores_the_gizmo_immediately_without_changing_orientation_or_undo
    g = TestFixtures.group_box
    overlay = build_overlay_with(g)
    overlay.enabled = true
    tool = push_fake_picker(overlay, g, :face)
    overlay.instance_variable_set(:@native_tool_override, true)
    refute CO.stored?(g)

    tool.onCancel(0, @model.active_view)

    assert_nil @model.tools.active_tool, 'Esc must pop the picker immediately'
    assert_empty @model.operation_log, 'Esc must never open an Undo operation'
    assert overlay.instance_variable_get(:@native_tool_override), 'the restore is still deferred at this point'

    UI.timer_blocks.last.call

    refute CO.stored?(g), 'Esc must not create a custom orientation'
    refute overlay.instance_variable_get(:@native_tool_override), 'Esc must restore the gizmo without a further click'
    assert overlay.active_gizmo
  end

  def test_finishing_the_picker_never_opens_an_additional_undo_operation
    g = TestFixtures.group_box
    overlay = build_overlay_with(g)
    push_fake_picker(overlay, g, :face)
    face, p0, p1, = build_diamond_top_face

    overlay.apply_face_alignment(g, [g, face], Geom::Point3d.new((p0.x + p1.x) / 2, (p0.y + p1.y) / 2, p0.z))
    log_after_align = @model.operation_log.dup

    overlay.finish_orientation_picker(@model.active_view)
    UI.timer_blocks.last.call

    assert_equal log_after_align, @model.operation_log,
      'popping the picker and restoring the gizmo must never start a second Undo operation'
  end

  def test_a_stale_deferred_restore_is_ignored_and_only_the_latest_one_applies
    g = TestFixtures.group_box
    overlay = build_overlay_with(g)
    push_fake_picker(overlay, g, :face)
    overlay.instance_variable_set(:@native_tool_override, true)

    overlay.finish_orientation_picker(@model.active_view)
    stale_block = UI.timer_blocks.last

    push_fake_picker(overlay, g, :face)
    overlay.instance_variable_set(:@native_tool_override, true)
    overlay.finish_orientation_picker(@model.active_view)
    fresh_block = UI.timer_blocks.last
    refute_same stale_block, fresh_block

    stale_block.call
    assert overlay.instance_variable_get(:@native_tool_override), 'a superseded restore must be a no-op'

    fresh_block.call
    refute overlay.instance_variable_get(:@native_tool_override), 'the latest scheduled restore still applies'
  end

  def test_a_deferred_restore_is_ignored_once_the_overlay_has_moved_to_another_model
    g = TestFixtures.group_box
    overlay = build_overlay_with(g)
    original_model = @model
    push_fake_picker(overlay, g, :face)
    overlay.instance_variable_set(:@native_tool_override, true)

    overlay.finish_orientation_picker(original_model.active_view)
    block = UI.timer_blocks.last

    overlay.instance_variable_set(:@model, Sketchup::Model.new)

    block.call
    assert overlay.instance_variable_get(:@native_tool_override),
      'a restore scheduled for a since-abandoned model must not fire against the new one'
  end

  # -- gizmo_state_for_current_selection / Global-mode isolation -----------

  def test_object_mode_uses_custom_axes_when_stored_and_native_axes_otherwise
    g = TestFixtures.group_box
    g.transformation = Geom::Transformation.rotation(ORIGIN, Z_AXIS, 40.degrees)
    overlay = build_overlay_with(g)
    P::PLUGIN.test_gizmo_orientation = P::LOCAL_ORIENTATION

    native = overlay.gizmo_state_for_current_selection
    assert_in_delta 1.0, native[:axes][1].dot(g.transformation.xaxis), 1e-6

    face, p0, p1, = build_diamond_top_face
    overlay.apply_face_alignment(g, [g, face], Geom::Point3d.new((p0.x + p1.x) / 2, (p0.y + p1.y) / 2, p0.z))

    custom = overlay.gizmo_state_for_current_selection
    world_x, = CO.world_axes_for(g)
    assert_in_delta 1.0, custom[:axes][1].dot(world_x), 1e-6
    refute_in_delta 1.0, custom[:axes][1].dot(g.transformation.xaxis), 1e-2
  end

  def test_global_orientation_ignores_any_stored_custom_orientation
    g = TestFixtures.group_box
    overlay = build_overlay_with(g)
    face, p0, p1, = build_diamond_top_face
    overlay.apply_face_alignment(g, [g, face], Geom::Point3d.new((p0.x + p1.x) / 2, (p0.y + p1.y) / 2, p0.z))
    assert CO.stored?(g), 'sanity: a custom orientation is stored'

    P::PLUGIN.test_gizmo_orientation = P::GLOBAL_ORIENTATION
    state = overlay.gizmo_state_for_current_selection
    assert_in_delta 1.0, state[:axes][1].dot(@model.axes.xaxis), 1e-9
    assert_in_delta 1.0, state[:axes][3].dot(@model.axes.zaxis), 1e-9
  end

  # -- Undo/Redo: fresh read every time, exactly like every other setting ---

  def test_gizmo_axes_immediately_reflect_an_undo_or_redo_of_the_stored_orientation
    g = TestFixtures.group_box
    overlay = build_overlay_with(g)
    P::PLUGIN.test_gizmo_orientation = P::LOCAL_ORIENTATION
    face, p0, p1, = build_diamond_top_face
    overlay.apply_face_alignment(g, [g, face], Geom::Point3d.new((p0.x + p1.x) / 2, (p0.y + p1.y) / 2, p0.z))
    aligned_x = overlay.gizmo_state_for_current_selection[:axes][1]

    # Simulates "the user pressed Ctrl+Z": the attribute write is undone.
    g.delete_attribute(CO::DICTIONARY_NAME)
    reverted_x = overlay.gizmo_state_for_current_selection[:axes][1]
    assert_in_delta 1.0, reverted_x.dot(g.transformation.xaxis), 1e-6

    # Simulates "the user pressed Ctrl+Y" (redo): the attribute reappears.
    CO.store!(g, aligned_x, Geom::Vector3d.new(0, 0, 1))
    redone_x = overlay.gizmo_state_for_current_selection[:axes][1]
    assert_in_delta 1.0, redone_x.dot(aligned_x), 1e-6
  end

  # -- Shared component: a second instance is unaffected --------------------

  def test_a_shared_components_second_instance_is_unaffected_by_aligning_the_first
    component = TestFixtures.ordinary_component
    definition = component.definition
    second = Sketchup::ComponentInstance.new(definition)

    overlay = build_overlay_with(component)
    face, p0, p1, = build_diamond_top_face
    assert overlay.apply_face_alignment(component, [component, face],
      Geom::Point3d.new((p0.x + p1.x) / 2, (p0.y + p1.y) / 2, p0.z))

    assert CO.stored?(component)
    refute CO.stored?(second), "aligning one instance's gizmo must never affect another instance of the same component"

    overlay_two = build_overlay_with(second)
    state_two = overlay_two.gizmo_state_for_current_selection
    P::PLUGIN.test_gizmo_orientation = P::LOCAL_ORIENTATION
    state_two = overlay_two.gizmo_state_for_current_selection
    assert_in_delta 1.0, state_two[:axes][1].dot(second.transformation.xaxis), 1e-6
  end

  # -- Licensing --------------------------------------------------------------

  def test_face_and_edge_alignment_and_reset_are_all_refused_when_unlicensed
    g = TestFixtures.group_box
    overlay = build_overlay_with(g)
    face, p0, p1, = build_diamond_top_face
    edge = Sketchup::Edge.new(Geom::Point3d.new(0, 0, 0), Geom::Point3d.new(1, 0, 0))

    TestLicense.unlicensed do
      refute overlay.apply_face_alignment(g, [g, face], Geom::Point3d.new((p0.x + p1.x) / 2, (p0.y + p1.y) / 2, p0.z))
      refute overlay.apply_edge_alignment(g, [g, edge])
    end
    refute CO.stored?(g)
    assert_empty @model.operation_log, 'a refused alignment must not open an Undo operation'

    assert overlay.apply_face_alignment(g, [g, face], Geom::Point3d.new((p0.x + p1.x) / 2, (p0.y + p1.y) / 2, p0.z))
    assert CO.stored?(g)
    TestLicense.unlicensed { overlay.reset_gizmo_orientation }
    assert CO.stored?(g), 'a refused reset must not remove the stored orientation'
  end

  def test_the_context_menu_items_carry_the_same_license_gate_as_every_other_gizmo_action
    g = TestFixtures.group_box
    overlay = build_overlay_with(g)
    overlay.display_authorized = true
    overlay.define_singleton_method(:gizmo_hovering?) { |*| true }
    picker_calls = []
    overlay.define_singleton_method(:start_orientation_picker) { |mode| picker_calls << mode }
    reset_calls = []
    overlay.define_singleton_method(:reset_gizmo_orientation) { reset_calls << true }

    menu = FakeMenuForOrientationTest.new
    overlay.getMenu(menu, 0, 0, 0, @model.active_view)

    TestLicense.unlicensed do
      menu.items['Align Gizmo XY to Face...'].call
      menu.items['Align Gizmo X to Edge...'].call
      menu.items['Reset Gizmo Orientation to Object Axes'].call
    end
    assert_empty picker_calls
    assert_empty reset_calls
    refute_nil UI.last_messagebox_text

    UI.last_messagebox_text = nil
    TestLicense.with_state(L::LICENSED) do
      menu.items['Align Gizmo XY to Face...'].call
      menu.items['Align Gizmo X to Edge...'].call
      menu.items['Reset Gizmo Orientation to Object Axes'].call
    end
    assert_equal %i[face edge], picker_calls
    assert_equal [true], reset_calls
    assert_nil UI.last_messagebox_text
  end

  class FakeMenuForOrientationTest
    attr_reader :items

    def initialize
      @items = {}
    end

    def add_item(name, &block)
      @items[name] = block
      name
    end

    def set_validation_proc(_id, &_block); end
    def add_separator; end
  end
end

# -- OrientationPickerTool: ownership/type filtering and Esc, in isolation ----
class OrientationPickerToolTest < Minitest::Test
  P = Zbellbound::SmartGizmoPro

  class FakePickModel
    attr_reader :pops

    def initialize(hit)
      @hit = hit
      @pops = 0
    end

    def raytest(_ray, _include_hidden)
      @hit
    end

    def tools
      self
    end

    def pop_tool
      @pops += 1
    end
  end

  class FakePickView
    attr_reader :model

    def initialize(model)
      @model = model
    end

    def pickray(_x, _y)
      :ray
    end
  end

  def spy_overlay
    calls = []
    overlay = Object.new
    overlay.define_singleton_method(:apply_face_alignment) { |*a| calls << [:face, *a]; true }
    overlay.define_singleton_method(:apply_edge_alignment) { |*a| calls << [:edge, *a]; true }
    # The real GizmoOverlay#finish_orientation_picker pops the tool itself
    # (see the production method) -- reproduced minimally here so this
    # spy still exercises exactly what OrientationPickerTool is required to
    # call on every exit path (success or Esc), without pulling in the real
    # overlay's deferred-refresh machinery, which is covered separately
    # against the real GizmoOverlay below.
    overlay.define_singleton_method(:finish_orientation_picker) { |view| view.model.tools.pop_tool }
    [overlay, calls]
  end

  def test_a_pick_belonging_to_a_different_object_is_ignored_and_the_picker_stays_active
    overlay, calls = spy_overlay
    target = Object.new
    other = Object.new
    face = Object.new
    model = FakePickModel.new([ORIGIN, [other, face]])
    tool = P::OrientationPickerTool.new(overlay, :face, target)

    tool.onLButtonUp(0, 10, 10, FakePickView.new(model))

    assert_empty calls
    assert_equal 0, model.pops, 'a mismatched pick must not pop the picker -- the user can try again'
  end

  def test_a_pick_of_the_wrong_leaf_type_is_ignored
    overlay, calls = spy_overlay
    target = Object.new
    edge = Sketchup::Edge.new(ORIGIN, Geom::Point3d.new(1, 0, 0))
    model = FakePickModel.new([ORIGIN, [target, edge]]) # an edge, but mode is :face

    P::OrientationPickerTool.new(overlay, :face, target).onLButtonUp(0, 1, 1, FakePickView.new(model))

    assert_empty calls
    assert_equal 0, model.pops
  end

  def test_a_missed_pick_is_ignored
    overlay, calls = spy_overlay
    model = FakePickModel.new(nil)

    P::OrientationPickerTool.new(overlay, :face, Object.new).onLButtonUp(0, 1, 1, FakePickView.new(model))

    assert_empty calls
    assert_equal 0, model.pops
  end

  def test_a_valid_face_pick_hands_off_to_the_overlay_and_pops_the_picker
    overlay, calls = spy_overlay
    target = Object.new
    face = Sketchup::Face.new([], Geom::Vector3d.new(0, 0, 1))
    model = FakePickModel.new([Geom::Point3d.new(1, 2, 3), [target, face]])

    P::OrientationPickerTool.new(overlay, :face, target).onLButtonUp(0, 1, 1, FakePickView.new(model))

    assert_equal 1, calls.length
    assert_equal :face, calls.first[0]
    assert_same target, calls.first[1]
    assert_equal 1, model.pops
  end

  def test_a_valid_edge_pick_hands_off_to_the_overlay_and_pops_the_picker
    overlay, calls = spy_overlay
    target = Object.new
    edge = Sketchup::Edge.new(ORIGIN, Geom::Point3d.new(1, 0, 0))
    model = FakePickModel.new([Geom::Point3d.new(0.5, 0, 0), [target, edge]])

    P::OrientationPickerTool.new(overlay, :edge, target).onLButtonUp(0, 1, 1, FakePickView.new(model))

    assert_equal 1, calls.length
    assert_equal :edge, calls.first[0]
    assert_equal 1, model.pops
  end

  def test_escape_pops_the_picker_and_changes_nothing
    overlay, calls = spy_overlay
    model = FakePickModel.new(nil)
    tool = P::OrientationPickerTool.new(overlay, :face, Object.new)

    tool.onCancel(0, FakePickView.new(model))

    assert_empty calls
    assert_equal 1, model.pops
  end

  def test_double_click_is_swallowed_so_the_target_never_enters_edit_mode
    overlay, = spy_overlay
    tool = P::OrientationPickerTool.new(overlay, :face, Object.new)
    assert_equal true, tool.onLButtonDoubleClick(0, 1, 1, nil)
  end
end
