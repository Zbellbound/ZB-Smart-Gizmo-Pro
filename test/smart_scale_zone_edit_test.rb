require 'minitest/autorun'
require_relative 'support/fixtures'

# Focused coverage for Smart Scale Zone editing (Stage 2): right-click a
# scale handle -> "Edit Smart Scale Zone" -> two draggable boundaries that
# set the profile's inner_min/inner_max for that one axis, committed as a
# single Undo step and consumed by the existing Smart Scale solver.
# The test View is a side view along +Y (see Sketchup::View#screen_coords):
# screen (x, y) is world (x, z), so a Z boundary at height h sits at screen y = h.
class SmartScaleZoneEditTest < Minitest::Test
  P = Zbellbound::SmartGizmoPro
  Z_SIZE = 100.0
  LEG = 10.0
  GAP = P::GizmoOverlay::SMART_SCALE_ZONE_MIN_GAP

  class FakeMenu
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

  def setup
    @model = Sketchup::Model.new
    P::PLUGIN.test_smart_scale_enabled = true
    P::PLUGIN.test_gizmo_orientation = P::GLOBAL_ORIENTATION
    UI.last_messagebox_text = nil
    @view = @model.active_view
    @instance = TestFixtures.frame_component(@model.active_entities, z_size: Z_SIZE, leg: LEG)
    @model.selection.instance_variable_set(:@list, [@instance])
    @overlay = TestHarness.build_overlay(model: @model, selection: @model.selection)
    @overlay.enabled = true
    @overlay.display_authorized = true
    @overlay.define_singleton_method(:gizmo_hovering?) { |*| true }
  end

  def scale_handle(axis_id)
    TestHarness.gizmo_of(@overlay).axes.find { |a| a.id == axis_id }.scale_gizmo
  end

  def hover(axis_id)
    scale_handle(axis_id).mouse_active = true
  end

  def menu
    FakeMenu.new.tap { |m| @overlay.getMenu(m, 0, 0, 0, @view) }
  end

  def edit_z
    hover(:z)
    menu.items['Edit Smart Scale Zone'].call
    @overlay.smart_scale_zone_edit_session
  end

  def levels
    @instance.definition.entities.grep(Sketchup::Edge).flat_map(&:vertices).uniq.map { |v| v.position.z }.uniq.sort
  end

  def draws(mode = nil)
    calls = @view.draw_calls.to_a.select { |c| c[:type] == :draw }
    mode ? calls.select { |c| c[:mode] == mode } : calls
  end

  def zone_state(axis_id = :z)
    mask = [axis_id == :x, axis_id == :y, axis_id == :z]
    @overlay.build_smart_scale_gesture_state_for_entity(@instance, axis_id, mask, [:scale, nil, 1.0, mask, nil, nil, nil])
  end

  # -- Menu / axis ----------------------------------------------------------

  def test_menu_offers_edit_only_for_the_hovered_scale_handle_and_enters_that_axis
    refute_includes menu.items.keys, 'Edit Smart Scale Zone'

    hover(:x)
    items = menu.items
    assert_includes items.keys, 'Edit Smart Scale Zone'
    items['Edit Smart Scale Zone'].call

    assert_equal :x, @overlay.smart_scale_zone_edit_session[:axis_id]
    assert @overlay.smart_scale_zone_edit_active?
  end

  def test_menu_item_is_absent_when_smart_scale_is_disabled
    P::PLUGIN.test_smart_scale_enabled = false
    hover(:z)

    refute_includes menu.items.keys, 'Edit Smart Scale Zone'
  end

  def test_hover_and_opening_the_menu_create_no_undo_entry
    hover(:z)
    menu

    assert_empty @model.operation_log
    refute @overlay.smart_scale_zone_edit_active?
  end

  # -- No automatic overlay ---------------------------------------------------

  def test_nothing_is_drawn_on_hover_or_during_a_normal_drag
    refute_respond_to @overlay, :draw_smart_scale_zone_preview
    refute_respond_to @overlay, :smart_scale_zone_state

    hover(:z)
    @overlay.draw_smart_scale_zone_edit(@view)
    TestHarness.drive_scale_drag(@overlay, axis_id: :z, ratio: 0.5, origin: @instance.bounds.min)
    @overlay.draw_smart_scale_zone_edit(@view)

    assert_empty @view.draw_calls.to_a
  end

  def test_edit_mode_draws_three_zones_and_two_boundaries
    edit_z
    @overlay.draw_smart_scale_zone_edit(@view)

    assert_equal 18, draws(GL_QUADS).length, '3 slabs of 6 faces: protected | stretch | protected'
    assert_equal 2, draws(GL_LINES).length, 'one outline per draggable boundary'
    middle_zs = draws(GL_QUADS)[12..17].flat_map { |c| c[:points] }.map(&:z)
    assert_equal [LEG, Z_SIZE - LEG], middle_zs.minmax.map(&:round)
  end

  # -- Boundary drag / clamp / crossing ----------------------------------------

  def test_dragging_a_boundary_moves_only_that_boundary
    session = edit_z

    assert_in_delta LEG, session[:inner_min], 1e-9
    @overlay.handle_smart_scale_zone_button_down(0, LEG, @view)
    assert_equal :inner_min, session[:drag]
    @overlay.handle_smart_scale_zone_mouse_move(0, 30.0, @view)
    @overlay.handle_smart_scale_zone_button_up(@view)

    assert_in_delta 30.0, session[:inner_min], 1e-6
    assert_in_delta Z_SIZE - LEG, session[:inner_max], 1e-9
    assert_nil session[:drag]
  end

  def test_boundaries_clamp_inside_the_range_and_cannot_cross
    session = edit_z

    @overlay.set_smart_scale_zone_boundary(:inner_min, -50.0)
    assert_in_delta 0.0, session[:inner_min], 1e-9

    @overlay.set_smart_scale_zone_boundary(:inner_max, 500.0)
    assert_in_delta Z_SIZE, session[:inner_max], 1e-9

    @overlay.set_smart_scale_zone_boundary(:inner_max, 20.0)
    @overlay.set_smart_scale_zone_boundary(:inner_min, 95.0)
    assert_in_delta 20.0 - GAP, session[:inner_min], 1e-9

    @overlay.set_smart_scale_zone_boundary(:inner_max, 0.0)
    assert_in_delta session[:inner_min] + GAP, session[:inner_max], 1e-9
  end

  # -- Esc / Undo -------------------------------------------------------------

  def test_esc_restores_the_previous_zone_with_nothing_written_or_undone
    edit_z
    @overlay.set_smart_scale_zone_boundary(:inner_min, 40.0)

    @overlay.onCancel(0, @view)

    refute @overlay.smart_scale_zone_edit_active?
    assert_nil @overlay.smart_scale_zone_override(@instance, :z)
    assert_empty @model.operation_log
    assert_equal({ min: 0.0, inner_min: LEG, inner_max: Z_SIZE - LEG, max: Z_SIZE }, zone_state.profile)
  end

  def test_commit_is_exactly_one_undo_operation
    edit_z
    @overlay.set_smart_scale_zone_boundary(:inner_min, 40.0)
    @overlay.set_smart_scale_zone_boundary(:inner_max, 80.0)

    @overlay.onKeyDown(P::GizmoOverlay::SMART_SCALE_ZONE_RETURN_KEY, 0, 0, @view)

    assert_equal [[:start, 'Edit Smart Scale Zone', true, false, false], [:commit]], @model.operation_log
    refute @overlay.smart_scale_zone_edit_active?
  end

  def test_committing_an_unchanged_zone_creates_no_undo_entry
    edit_z
    @overlay.commit_smart_scale_zone_edit(@view)

    assert_empty @model.operation_log
    assert_nil @overlay.smart_scale_zone_override(@instance, :z)
  end

  # -- Persistence ------------------------------------------------------------

  def test_the_committed_zone_is_saved_and_reopens_where_it_was_left
    edit_z
    @overlay.set_smart_scale_zone_boundary(:inner_min, 30.0)
    @overlay.commit_smart_scale_zone_edit(@view)

    assert_equal [30.0, LEG], @overlay.smart_scale_zone_override(@instance, :z)
    assert_nil @overlay.smart_scale_zone_override(@instance, :x)

    reopened = edit_z
    assert_in_delta 30.0, reopened[:inner_min], 1e-9
    assert_in_delta Z_SIZE - LEG, reopened[:inner_max], 1e-9
  end

  # -- Solver / orientation -------------------------------------------------------

  def save_zone(lo, hi)
    @instance.set_attribute(P::GizmoOverlay::SMART_SCALE_ZONE_DICTIONARY,
                            @overlay.smart_scale_zone_attribute_key(@instance, :z), [lo, hi])
  end

  def test_the_existing_smart_scale_solver_uses_the_saved_zone
    save_zone(5.0, LEG)

    assert_equal({ min: 0.0, inner_min: 5.0, inner_max: Z_SIZE - LEG, max: Z_SIZE }, zone_state.profile)

    TestHarness.drive_scale_drag(@overlay, axis_id: :z, ratio: 0.5, origin: @instance.bounds.min)

    # The plane at z=10 now lies INSIDE the stretch zone (5..90), so it
    # moves; with the auto profile (10..90) it would have stayed at 10.
    assert_in_delta 0.0, levels[0], 1e-6
    assert_operator levels[1], :<, LEG - 1.0
    assert_in_delta Z_SIZE * 0.5, levels[3], 1e-6
    assert_in_delta LEG, levels[3] - levels[2], 1e-6, 'the max-side protected end is rigid'
  end

  def test_the_zone_follows_the_gizmo_orientation
    save_zone(5.0, LEG)
    P::PLUGIN.test_gizmo_orientation = P::LOCAL_ORIENTATION

    assert_equal({ min: 0.0, inner_min: LEG, inner_max: Z_SIZE - LEG, max: Z_SIZE }, zone_state.profile)
  end
  # -- Wider hit target ---------------------------------------------------------

  def test_a_boundary_can_be_grabbed_from_well_away_but_not_from_far_off
    session = edit_z

    @overlay.handle_smart_scale_zone_button_down(0, LEG + 25.0, @view)
    assert_equal :inner_min, session[:drag], 'a grab 25px from the boundary still hits it'
    @overlay.handle_smart_scale_zone_button_up(@view)

    assert_nil @overlay.smart_scale_zone_boundary_at(0, 50.0, @view), 'mid-gap is not a boundary'
    assert_operator P::GizmoOverlay::SMART_SCALE_ZONE_PICK_RADIUS, :>=, 24
  end

  def test_the_drawn_boundary_stays_slim
    edit_z
    @overlay.draw_smart_scale_zone_edit(@view)

    assert_operator draws(GL_LINES).map { |c| c[:width] }.max, :<=, 4
  end

  # -- Normal Smart Scale drag uses the saved zone --------------------------------

  def scale_z(ratio)
    TestHarness.drive_scale_drag(@overlay, axis_id: :z, ratio: ratio, origin: @instance.bounds.min)
  end

  def test_normal_drag_keeps_protected_widths_and_stretches_only_the_zone
    save_zone(30.0, 20.0) # protected 0..30 and 80..100, stretch 30..80

    scale_z(1.5) # 100 -> 150: stretch zone 50 -> 100

    assert_in_delta 0.0, levels.first, 1e-6
    assert_in_delta 150.0, levels.last, 1e-6
    # Vertices at z=10 stay (protected); z=90 and 100 ride with the end.
    assert_in_delta 10.0, levels[1], 1e-6
    assert_in_delta 140.0, levels[2], 1e-6
    assert_in_delta 150.0, levels[3], 1e-6
    state = zone_state
    assert_in_delta 30.0, state.profile[:inner_min] - state.profile[:min], 1e-6
    assert_in_delta 20.0, state.profile[:max] - state.profile[:inner_max], 1e-6
    assert_in_delta 100.0, state.profile[:inner_max] - state.profile[:inner_min], 1e-6
  end

  def test_repeated_scaling_keeps_using_the_saved_zone
    save_zone(30.0, 20.0)

    scale_z(1.5)
    scale_z(0.8) # 150 -> 120: stretch zone 100 -> 70

    state = zone_state
    assert_in_delta 30.0, state.profile[:inner_min], 1e-6
    assert_in_delta 100.0, state.profile[:inner_max], 1e-6
    assert_in_delta 120.0, state.profile[:max], 1e-6
    assert_in_delta [0.0, 10.0, 110.0, 120.0].sum, levels.sum, 1e-6
  end

  def test_without_a_saved_zone_the_auto_profile_is_unchanged
    assert_nil @overlay.smart_scale_zone_override(@instance, :z)

    scale_z(1.5)

    assert_equal [0.0, LEG, Z_SIZE * 1.5 - LEG, Z_SIZE * 1.5], levels.map { |v| v.round(6) }
  end

  def test_saved_zone_also_drives_x_and_y_in_global_orientation
    [:x, :y].each do |axis|
      model = Sketchup::Model.new
      instance = TestFixtures.frame_component(model.active_entities, z_size: Z_SIZE, leg: LEG)
      # Lay the frame's long (local Z) direction along the world axis.
      rotation = axis == :x ? Geom::Transformation.rotation(ORIGIN, Y_AXIS, 90.degrees) : Geom::Transformation.rotation(ORIGIN, X_AXIS, -90.degrees)
      instance.transformation = rotation
      model.selection.instance_variable_set(:@list, [instance])
      overlay = TestHarness.build_overlay(model: model, selection: model.selection)
      key = overlay.smart_scale_zone_attribute_key(instance, axis)
      instance.set_attribute(P::GizmoOverlay::SMART_SCALE_ZONE_DICTIONARY, key, [30.0, 20.0])

      TestHarness.drive_scale_drag(overlay, axis_id: axis, ratio: 1.5, origin: instance.bounds.min)

      lo = instance.bounds.min
      hi = instance.bounds.max
      span = axis == :x ? hi.x - lo.x : hi.y - lo.y
      assert_in_delta 150.0, span, 1e-3, "#{axis}: overall size follows the ratio"
      mask = [axis == :x, axis == :y, false]
      state = overlay.build_smart_scale_gesture_state_for_entity(instance, axis, mask, [:scale, nil, 1.0, mask, nil, nil, nil])
      assert_in_delta 30.0, state.profile[:inner_min] - state.profile[:min], 1e-3, "#{axis}: protected min end"
      assert_in_delta 20.0, state.profile[:max] - state.profile[:inner_max], 1e-3, "#{axis}: protected max end"
    end
  end

  def test_curved_edge_vertices_ride_with_the_scaling_when_a_zone_is_saved
    arc = Sketchup::Edge.new(Geom::Point3d.new(0, 0, 95.0), Geom::Point3d.new(1, 0, 95.0))
    arc.curve = Object.new
    @instance.definition.entities << arc
    save_zone(30.0, 20.0)

    scale_z(1.5)

    zs = arc.vertices.map { |v| v.position.z }
    assert_in_delta 145.0, zs[0], 1e-6, 'a curve vertex beyond the stretch zone moves with the end'
  end
end
