require 'minitest/autorun'
require_relative 'support/fixtures'

# Coverage for custom per-instance gizmo orientation ("Set Gizmo Orientation
# by 3 Points" / "Reset Gizmo Orientation to Object Axes"): geometry modeled
# at an angle and grouped afterward keeps the axes it happened to have at
# grouping time, not the angle it visibly sits at -- these commands let the
# gizmo instead follow the visible geometry, without changing the object's
# real axes, transformation, or geometry.
#
# Two layers, matching custom_orientation.rb's own split:
# * CustomOrientationTest drives Zbellbound::SmartGizmoPro::CustomOrientation
#   directly (storage, reconstruction, per-instance isolation,
#   transformation-following, mirrored/non-uniform scale) -- pure Geom/
#   attribute-dictionary math, no overlay or picking involved.
# * CustomGizmoOrientationTest drives the real GizmoOverlay picker methods
#   (start_point_orientation_picker/complete_point_orientation/
#   reset_gizmo_orientation/gizmo_state_for_current_selection) through its
#   real onMouseMove/onLButtonDown/onLButtonUp/onKeyDown callbacks, using a
#   simulated Sketchup::InputPoint (see test/support/sketchup_stubs.rb)
#   instead of a real inference engine -- the picker never pushes a
#   separate Tool, so this exercises the exact same overlay a live SketchUp
#   session would drive.
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
    overlay = TestHarness.build_overlay(model: @model, selection: @model.selection)
    overlay.enabled = true
    overlay
  end

  def operation_starts
    @model.operation_log.select { |entry| entry[0] == :start }
  end

  # Queues the InputPoint that the NEXT onMouseMove/onLButtonUp pair will
  # resolve to -- entities is the simulated instance_path, root-most first,
  # exactly like a real Sketchup::InputPoint#instance_path.
  def queue_pick(point, entities, valid: true)
    @model.active_view.next_input_point = { position: point, instance_path: entities, valid: valid }
  end

  # One simulated click: queue the pick, then drive the same mouse events a
  # live click would fire (move updates the live InputPoint, down is a
  # no-op passthrough, up commits it) through the overlay's own callbacks --
  # never through a separate pushed Tool.
  def click(overlay, point, entities, valid: true)
    view = @model.active_view
    queue_pick(point, entities, valid: valid)
    overlay.onMouseMove(0, 0, 0, view)
    overlay.onLButtonDown(0, 0, 0, view)
    overlay.onLButtonUp(0, 0, 0, view)
  end

  def press_escape(overlay)
    overlay.onKeyDown(P::GizmoOverlay::ESCAPE_KEY, 1, 0, @model.active_view)
  end

  def press_backspace(overlay)
    overlay.onKeyDown(P::GizmoOverlay::BACKSPACE_KEY, 1, 0, @model.active_view)
  end

  # -- Basic 3-point math ---------------------------------------------------

  def test_three_points_produce_the_expected_orthonormal_right_handed_basis
    g = TestFixtures.group_box
    overlay = build_overlay_with(g)
    overlay.start_point_orientation_picker

    click(overlay, Geom::Point3d.new(0, 0, 0), [g])
    click(overlay, Geom::Point3d.new(10, 0, 0), [g])
    click(overlay, Geom::Point3d.new(3, 5, 0), [g])

    assert CO.stored?(g)
    x, y, z = CO.world_axes_for(g)
    assert_in_delta 1.0, x.dot(Geom::Vector3d.new(1, 0, 0)), 1e-9
    assert_in_delta 1.0, y.dot(Geom::Vector3d.new(0, 1, 0)), 1e-9
    assert_in_delta 1.0, z.dot(Geom::Vector3d.new(0, 0, 1)), 1e-9
    assert_in_delta 1.0, x.cross(y).dot(z), 1e-9, 'must be right-handed: x.cross(y) == z'
    assert_equal P::LOCAL_ORIENTATION, P::PLUGIN.gizmo_orientation,
      'completing all 3 points switches to Object orientation'
    refute overlay.point_orientation_active?
  end

  def test_point_3_selects_the_positive_y_side_and_flips_z_accordingly
    g = TestFixtures.group_box
    overlay = build_overlay_with(g)
    overlay.start_point_orientation_picker
    click(overlay, Geom::Point3d.new(0, 0, 0), [g])
    click(overlay, Geom::Point3d.new(10, 0, 0), [g])
    click(overlay, Geom::Point3d.new(3, -5, 0), [g]) # the OTHER side this time

    _x, y, z = CO.world_axes_for(g)
    assert_in_delta 1.0, y.dot(Geom::Vector3d.new(0, -1, 0)), 1e-9,
      'Y must follow whichever side point 3 was picked on'
    assert_in_delta 1.0, z.dot(Geom::Vector3d.new(0, 0, -1)), 1e-9,
      'Z flips to keep X, Y, Z right-handed for the chosen Y side'
  end

  def test_face_alignment_does_not_move_rotate_scale_or_otherwise_touch_the_geometry
    g = TestFixtures.group_box
    original_transformation = g.transformation.to_a
    original_bounds = [g.bounds.min.to_a, g.bounds.max.to_a]
    overlay = build_overlay_with(g)
    overlay.start_point_orientation_picker

    click(overlay, Geom::Point3d.new(0, 0, 0), [g])
    click(overlay, Geom::Point3d.new(10, 0, 0), [g])
    click(overlay, Geom::Point3d.new(3, 5, 0), [g])

    assert_equal original_transformation, g.transformation.to_a
    assert_equal original_bounds, [g.bounds.min.to_a, g.bounds.max.to_a]
    assert_equal [g], @model.selection.to_a, 'the pivot/selection must never change either'
  end

  # -- Rejections: coincident point 2, collinear point 3 --------------------

  def test_a_second_point_coincident_with_the_first_is_rejected_and_stays_retryable
    g = TestFixtures.group_box
    overlay = build_overlay_with(g)
    overlay.start_point_orientation_picker
    click(overlay, Geom::Point3d.new(0, 0, 0), [g])

    click(overlay, Geom::Point3d.new(0, 0, 0), [g]) # same as point 1
    refute_nil UI.last_messagebox_text
    assert overlay.point_orientation_active?, 'a rejected point 2 must not cancel the whole operation'

    UI.last_messagebox_text = nil
    click(overlay, Geom::Point3d.new(10, 0, 0), [g]) # a valid point 2 now
    click(overlay, Geom::Point3d.new(3, 5, 0), [g])

    assert CO.stored?(g), 'the operation must still complete normally after the retry'
    assert_nil UI.last_messagebox_text
  end

  def test_a_third_point_collinear_with_the_first_two_is_rejected_and_stays_retryable
    g = TestFixtures.group_box
    overlay = build_overlay_with(g)
    overlay.start_point_orientation_picker
    click(overlay, Geom::Point3d.new(0, 0, 0), [g])
    click(overlay, Geom::Point3d.new(10, 0, 0), [g])

    click(overlay, Geom::Point3d.new(5, 0, 0), [g]) # on the X line -- collinear
    refute_nil UI.last_messagebox_text
    refute CO.stored?(g)
    assert overlay.point_orientation_active?, 'a rejected point 3 must not cancel the whole operation'

    UI.last_messagebox_text = nil
    click(overlay, Geom::Point3d.new(3, 5, 0), [g]) # a valid point 3 now

    assert CO.stored?(g), 'the operation must still complete normally after the retry'
    assert_nil UI.last_messagebox_text
  end

  # -- Ownership filtering ---------------------------------------------------

  def test_a_pick_belonging_to_another_object_is_ignored_and_stays_retryable
    g = TestFixtures.group_box
    other = TestFixtures.group_box
    overlay = build_overlay_with(g)
    overlay.start_point_orientation_picker

    click(overlay, Geom::Point3d.new(0, 0, 0), [other]) # wrong object
    assert_nil UI.last_messagebox_text, 'an ownership miss is silent, unlike a geometric rejection'
    assert overlay.point_orientation_active?

    click(overlay, Geom::Point3d.new(0, 0, 0), [g]) # now the right object
    click(overlay, Geom::Point3d.new(10, 0, 0), [g])
    click(overlay, Geom::Point3d.new(3, 5, 0), [g])

    assert CO.stored?(g)
  end

  def test_a_pick_that_resolves_to_no_geometry_at_all_is_ignored
    g = TestFixtures.group_box
    overlay = build_overlay_with(g)
    overlay.start_point_orientation_picker

    click(overlay, Geom::Point3d.new(0, 0, 0), nil) # arbitrary empty-space point
    assert overlay.point_orientation_active?
    refute CO.stored?(g)
  end

  # -- Cancellation (Esc) -----------------------------------------------------

  def test_esc_cancels_the_whole_operation_with_no_undo_and_no_orientation_change
    g = TestFixtures.group_box
    overlay = build_overlay_with(g)
    overlay.start_point_orientation_picker
    click(overlay, Geom::Point3d.new(0, 0, 0), [g])
    click(overlay, Geom::Point3d.new(10, 0, 0), [g])

    press_escape(overlay)

    refute overlay.point_orientation_active?
    refute CO.stored?(g)
    assert_empty @model.operation_log, 'Esc must never open an Undo operation'
  end

  def test_backspace_steps_back_exactly_one_point
    g = TestFixtures.group_box
    overlay = build_overlay_with(g)
    overlay.start_point_orientation_picker
    click(overlay, Geom::Point3d.new(0, 0, 0), [g])
    click(overlay, Geom::Point3d.new(10, 0, 0), [g])

    press_backspace(overlay)
    assert overlay.point_orientation_active?
    # Point 2 was stepped back, not point 1 -- re-picking a DIFFERENT point 2
    # must still work normally.
    click(overlay, Geom::Point3d.new(0, 10, 0), [g])
    click(overlay, Geom::Point3d.new(-5, 3, 0), [g])

    assert CO.stored?(g)
    x, = CO.world_axes_for(g)
    assert_in_delta 1.0, x.dot(Geom::Vector3d.new(0, 1, 0)), 1e-9,
      'the stepped-back-and-repicked point 2 must be the one actually used'
  end

  # -- Reset --------------------------------------------------------------

  def test_reset_removes_only_the_custom_orientation_and_is_a_no_op_when_absent
    g = TestFixtures.group_box
    overlay = build_overlay_with(g)
    g.set_attribute('SomeOtherExtension', 'k', 'v')

    overlay.reset_gizmo_orientation
    assert_empty @model.operation_log, 'resetting when nothing is stored must not open an Undo operation'

    overlay.start_point_orientation_picker
    click(overlay, Geom::Point3d.new(0, 0, 0), [g])
    click(overlay, Geom::Point3d.new(10, 0, 0), [g])
    click(overlay, Geom::Point3d.new(3, 5, 0), [g])
    assert CO.stored?(g)

    overlay.reset_gizmo_orientation
    refute CO.stored?(g)
    assert_equal 'v', g.get_attribute('SomeOtherExtension', 'k')
    assert_equal %i[start commit start commit], @model.operation_log.map(&:first)
  end

  # -- gizmo_state_for_current_selection / Global-mode isolation -----------

  def test_object_mode_uses_custom_axes_when_stored_and_native_axes_otherwise
    g = TestFixtures.group_box
    g.transformation = Geom::Transformation.rotation(ORIGIN, Z_AXIS, 40.degrees)
    overlay = build_overlay_with(g)
    P::PLUGIN.test_gizmo_orientation = P::LOCAL_ORIENTATION

    native = overlay.gizmo_state_for_current_selection
    assert_in_delta 1.0, native[:axes][1].dot(g.transformation.xaxis), 1e-6

    overlay.start_point_orientation_picker
    click(overlay, Geom::Point3d.new(0, 0, 0).transform(g.transformation), [g])
    click(overlay, Geom::Point3d.new(10, 0, 0).transform(g.transformation), [g])
    click(overlay, Geom::Point3d.new(3, 5, 0).transform(g.transformation), [g])

    custom = overlay.gizmo_state_for_current_selection
    world_x, = CO.world_axes_for(g)
    assert_in_delta 1.0, custom[:axes][1].dot(world_x), 1e-6
  end

  def test_global_orientation_ignores_any_stored_custom_orientation
    g = TestFixtures.group_box
    overlay = build_overlay_with(g)
    overlay.start_point_orientation_picker
    click(overlay, Geom::Point3d.new(0, 0, 0), [g])
    click(overlay, Geom::Point3d.new(10, 0, 0), [g])
    click(overlay, Geom::Point3d.new(3, 5, 0), [g])
    assert CO.stored?(g), 'sanity: a custom orientation is stored'

    P::PLUGIN.test_gizmo_orientation = P::GLOBAL_ORIENTATION
    state = overlay.gizmo_state_for_current_selection
    assert_in_delta 1.0, state[:axes][1].dot(@model.axes.xaxis), 1e-9
    assert_in_delta 1.0, state[:axes][3].dot(@model.axes.zaxis), 1e-9
  end

  # -- Mirrored / non-uniform instance --------------------------------------

  def test_a_mirrored_instance_still_reconstructs_a_valid_right_handed_basis_after_3_point_align
    g = TestFixtures.group_box
    overlay = build_overlay_with(g)
    overlay.start_point_orientation_picker
    click(overlay, Geom::Point3d.new(0, 0, 0), [g])
    click(overlay, Geom::Point3d.new(10, 0, 0), [g])
    click(overlay, Geom::Point3d.new(3, 5, 0), [g])
    assert CO.stored?(g)

    g.transformation = Geom::Transformation.new(
      Geom::Vector3d.new(-1, 0, 0), Geom::Vector3d.new(0, 1, 0), Geom::Vector3d.new(0, 0, 1), ORIGIN
    )

    x, y, z = CO.world_axes_for(g)
    assert_in_delta 1.0, x.length, 1e-9
    assert_in_delta 1.0, y.length, 1e-9
    assert_in_delta 1.0, z.length, 1e-9
    assert_in_delta 0.0, x.dot(y), 1e-9
    assert_in_delta 1.0, x.cross(y).dot(z), 1e-6, 'must stay right-handed even when the instance is later mirrored'
  end

  # -- Per-instance persistence: a shared component's second instance -------

  def test_a_shared_components_second_instance_is_unaffected_by_aligning_the_first
    component = TestFixtures.ordinary_component
    definition = component.definition
    second = Sketchup::ComponentInstance.new(definition)

    overlay = build_overlay_with(component)
    overlay.start_point_orientation_picker
    click(overlay, Geom::Point3d.new(0, 0, 0), [component])
    click(overlay, Geom::Point3d.new(10, 0, 0), [component])
    click(overlay, Geom::Point3d.new(3, 5, 0), [component])

    assert CO.stored?(component)
    refute CO.stored?(second), "aligning one instance's gizmo must never affect another instance of the same component"
  end

  # -- Undo -------------------------------------------------------------------

  def test_completing_all_three_points_creates_exactly_one_undo_operation
    g = TestFixtures.group_box
    overlay = build_overlay_with(g)
    overlay.start_point_orientation_picker
    click(overlay, Geom::Point3d.new(0, 0, 0), [g])
    click(overlay, Geom::Point3d.new(10, 0, 0), [g])
    click(overlay, Geom::Point3d.new(3, 5, 0), [g])

    assert_equal 1, operation_starts.length
    assert_equal %i[start commit], @model.operation_log.map(&:first)
  end

  # -- Immediate reactivation, no extra click, no timer machinery -----------

  def test_the_gizmo_reactivates_immediately_after_completion_with_no_extra_click_or_timer
    g = TestFixtures.group_box
    overlay = build_overlay_with(g)
    overlay.start_point_orientation_picker
    click(overlay, Geom::Point3d.new(0, 0, 0), [g])
    click(overlay, Geom::Point3d.new(10, 0, 0), [g])
    click(overlay, Geom::Point3d.new(3, 5, 0), [g])

    refute overlay.point_orientation_active?
    refute overlay.instance_variable_get(:@native_tool_override),
      'no tool-stack transition ever happens for this picker, so nothing needs to be un-hidden'
    assert_equal [g], @model.selection.to_a
    assert_empty UI.started_timers, 'no timer of any kind is used to restore the gizmo'
    assert_empty UI.timer_blocks
  end

  def test_the_gizmo_reactivates_immediately_after_esc_with_no_extra_click_or_timer
    g = TestFixtures.group_box
    overlay = build_overlay_with(g)
    overlay.start_point_orientation_picker
    click(overlay, Geom::Point3d.new(0, 0, 0), [g])

    press_escape(overlay)

    refute overlay.point_orientation_active?
    refute overlay.instance_variable_get(:@native_tool_override)
    assert_equal [g], @model.selection.to_a
    assert_empty UI.started_timers
    assert_empty UI.timer_blocks
  end

  def test_a_right_click_mid_pick_cancels_it_the_same_way_as_esc
    g = TestFixtures.group_box
    overlay = build_overlay_with(g)
    overlay.define_singleton_method(:gizmo_hovering?) { |*| false }
    overlay.start_point_orientation_picker
    click(overlay, Geom::Point3d.new(0, 0, 0), [g])

    overlay.getMenu(FakeMenuForOrientationTest.new, 0, 0, 0, @model.active_view)

    refute overlay.point_orientation_active?
    assert_empty @model.operation_log
  end

  # -- Licensing --------------------------------------------------------------

  def test_completing_all_three_points_is_refused_when_unlicensed_with_no_undo
    g = TestFixtures.group_box
    overlay = build_overlay_with(g)
    overlay.start_point_orientation_picker

    TestLicense.unlicensed do
      click(overlay, Geom::Point3d.new(0, 0, 0), [g])
      click(overlay, Geom::Point3d.new(10, 0, 0), [g])
      click(overlay, Geom::Point3d.new(3, 5, 0), [g])
    end

    refute CO.stored?(g)
    assert_empty @model.operation_log, 'a refused completion must not open an Undo operation'
    refute overlay.point_orientation_active?, 'the session still ends -- retrying the same refusal is pointless'
  end

  def test_reset_is_refused_when_unlicensed
    g = TestFixtures.group_box
    overlay = build_overlay_with(g)
    overlay.start_point_orientation_picker
    click(overlay, Geom::Point3d.new(0, 0, 0), [g])
    click(overlay, Geom::Point3d.new(10, 0, 0), [g])
    click(overlay, Geom::Point3d.new(3, 5, 0), [g])
    assert CO.stored?(g)

    TestLicense.unlicensed { overlay.reset_gizmo_orientation }
    assert CO.stored?(g), 'a refused reset must not remove the stored orientation'
  end

  def test_the_context_menu_item_carries_the_same_license_gate_as_every_other_gizmo_action
    g = TestFixtures.group_box
    overlay = build_overlay_with(g)
    overlay.display_authorized = true
    overlay.define_singleton_method(:gizmo_hovering?) { |*| true }
    picker_calls = []
    overlay.define_singleton_method(:start_point_orientation_picker) { picker_calls << true }
    reset_calls = []
    overlay.define_singleton_method(:reset_gizmo_orientation) { reset_calls << true }

    menu = FakeMenuForOrientationTest.new
    overlay.getMenu(menu, 0, 0, 0, @model.active_view)

    TestLicense.unlicensed do
      menu.items['Set Gizmo Orientation by 3 Points...'].call
      menu.items['Reset Gizmo Orientation to Object Axes'].call
    end
    assert_empty picker_calls
    assert_empty reset_calls
    refute_nil UI.last_messagebox_text

    UI.last_messagebox_text = nil
    TestLicense.with_state(L::LICENSED) do
      menu.items['Set Gizmo Orientation by 3 Points...'].call
      menu.items['Reset Gizmo Orientation to Object Axes'].call
    end
    assert_equal [true], picker_calls
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
