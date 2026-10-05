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

  # -- Regression: legacy Smart Scale must be untouched without a saved zone --

  def add_curve(z_values)
    curve = Object.new
    z_values.each_cons(2) do |a, b|
      edge = Sketchup::Edge.new(Geom::Point3d.new(0, 0, a), Geom::Point3d.new(0, 0, b))
      edge.curve = curve
      @instance.definition.entities << edge
    end
  end

  def curve_zs
    @instance.definition.entities.grep(Sketchup::Edge).select(&:curve).flat_map(&:vertices).map { |v| v.position.z.round(6) }.uniq.sort
  end

  def test_no_saved_zone_matches_legacy_smart_scale_exactly_including_curves
    add_curve([40.0, 50.0, 60.0, 95.0]) # curve vertices never take part in legacy Smart Scale

    state = zone_state
    assert_equal({ min: 0.0, inner_min: LEG, inner_max: Z_SIZE - LEG, max: Z_SIZE }, state.profile)
    assert_equal [0.0, LEG, Z_SIZE - LEG, Z_SIZE], state.vertex_entries.map { |e| e[:original_root_point].z }.uniq.sort
    assert state.vertex_entries.none? { |e| e.key?(:anchor_value) }, 'legacy entries carry no zone anchor'

    scale_z(1.5)

    assert_equal [0.0, LEG, Z_SIZE * 1.5 - LEG, Z_SIZE * 1.5], levels.reject { |z| [40.0, 50.0, 60.0, 95.0].include?(z) }.map { |v| v.round(6) }
    assert_equal [40.0, 50.0, 60.0, 95.0], curve_zs, 'curve geometry is left exactly as legacy left it'
  end

  def test_saved_zone_changes_only_the_zone_path_and_keeps_curves_rigid
    add_curve([40.0, 50.0, 60.0]) # entirely inside the stretch zone
    save_zone(30.0, 20.0)

    scale_z(1.5)

    assert_in_delta 0.0, levels.first, 1e-6
    assert_in_delta 150.0, levels.last, 1e-6
    zs = curve_zs
    assert_in_delta 10.0, zs[1] - zs[0], 1e-6, 'curve is not stretched or split'
    assert_in_delta 10.0, zs[2] - zs[1], 1e-6, 'curve is not stretched or split'
    assert_in_delta 70.0, zs[1], 1e-6, 'curve is carried to where its centre maps in the stretch zone'
  end

  def test_saved_zone_curve_crossing_a_boundary_moves_as_one_unit
    add_curve([70.0, 80.0, 90.0]) # crosses the inner_max boundary at 80
    save_zone(30.0, 20.0)

    scale_z(1.5)

    zs = curve_zs
    assert_equal [120.0, 130.0, 140.0], zs, 'whole curve carried by one offset'
  end

  # -- Grouped door: [protected] | [stretch] | [protected] -------------------

  class DoorFixture
    attr_reader :root, :parts

    # Each part is a rigid child group spanning [z0, z1]; all geometry is
    # inside child groups so the solver treats them as whole entities.
    def initialize(spans)
      root_def = Sketchup::ComponentDefinition.new('Door')
      @parts = {}
      spans.each do |name, (z0, z1)|
        child_def = Sketchup::ComponentDefinition.new(name.to_s)
        TestFixtures.build_box(child_def.entities, 4.0, 4.0, z1 - z0)
        child = Sketchup::Group.new(child_def)
        child.transformation = Geom::Transformation.translation(Geom::Vector3d.new(0, 0, z0))
        root_def.entities << child
        @parts[name] = child
      end
      @root = Sketchup::Group.new(root_def)
    end

    def z_range(name)
      b = @parts[name].bounds
      [b.min.z.round(6), b.max.z.round(6)]
    end

    def height(name)
      lo, hi = z_range(name)
      (hi - lo).round(6)
    end
  end

  def door_setup(spans)
    @door = DoorFixture.new(spans)
    @model.active_entities << @door.root
    @model.selection.instance_variable_set(:@list, [@door.root])
    @instance = @door.root
    @overlay = TestHarness.build_overlay(model: @model, selection: @model.selection)
    @overlay.enabled = true
    @overlay.display_authorized = true
    @door
  end

  DOOR = {
    bottom_rail: [0.0, 10.0], handle: [5.0, 9.0], # handle: nested part in a protected area
    panel: [30.0, 70.0],                          # wholly in the stretch zone
    top_rail: [90.0, 100.0],                      # far protected end
    lock: [82.0, 88.0]                            # wholly in the far protected area
  }.freeze

  def test_grouped_door_without_a_zone_classifies_exactly_like_legacy
    door_setup(DOOR.merge(full: [0.0, 100.0]))
    state = zone_state

    state.instance_entries.each do |e|
      expected = @overlay.classify_smart_scale_range(e[:min], e[:max], state.profile)
      assert_equal expected, e[:kind], 'legacy classifier decides every part when no zone is saved'
    end
    assert_includes state.instance_entries.map { |e| e[:kind] }, :full_span, 'legacy still scales a full-span part'
  end

  # -- Actual selected top-level grouped door: no parent-level scaling --------

  def test_selected_door_group_never_receives_a_uniform_scale_while_a_zone_is_active
    door = door_setup(DOOR)
    TestFixtures.build_frame(door.root.entities, 4.0, 4.0, 100.0, 10.0) # raw door-leaf geometry too
    save_zone(20.0, 20.0)
    scale_calls = []
    @model.active_entities.define_singleton_method(:transform_entities) do |tr, ents|
      scale_calls << [tr, ents]
      super(tr, ents)
    end

    scale_z(1.5)

    assert_empty scale_calls, 'the legacy overall scale transform is never applied to the selected group'
    assert_in_delta 1.0, door.root.transformation.to_a[10], 1e-9, 'parent group stays rigid along the axis'
    assert_in_delta 150.0, door.root.bounds.max.z - door.root.bounds.min.z, 1e-6, 'size still follows the gesture ratio'
    assert_equal [140.0, 150.0], door.z_range(:top_rail)
    assert_equal [0.0, 10.0], door.z_range(:bottom_rail)
  end

  def test_door_gesture_that_cannot_build_a_zone_state_does_not_fall_back_to_a_uniform_scale
    door = door_setup(DOOR)
    save_zone(20.0, 20.0)
    scale_calls = []
    @model.active_entities.define_singleton_method(:transform_entities) { |tr, ents| scale_calls << tr }
    @overlay.define_singleton_method(:build_smart_scale_gesture_state) { |_data| nil }

    scale_z(1.5)

    assert_empty scale_calls, 'an active zone must never degrade to ordinary uniform scaling'
    assert_in_delta 1.0, door.root.transformation.to_a[10], 1e-9
  end

  # -- Nested assemblies: group-in-group, component-in-group, group-in-component --

  def leaf(name, z0, z1)
    d = Sketchup::ComponentDefinition.new(name)
    TestFixtures.build_box(d.entities, 4.0, 4.0, z1 - z0)
    yield d if block_given?
    d
  end

  def place(entities, node, z)
    node.transformation = Geom::Transformation.translation(Geom::Vector3d.new(0, 0, z))
    entities << node
    node
  end

  # Builds root(kind) > wrapper(kind) > {rail, handle, panel, top}; the wrapper
  # carries its own z offset so the child path transform must be composed.
  def nested_assembly(root_kind:, wrapper_kind:, wrapper_z:, spans:)
    wrapper_def = Sketchup::ComponentDefinition.new('Wrapper')
    leaves = spans.to_h do |name, (z0, z1)|
      node = if wrapper_kind == :group
               Sketchup::Group.new(leaf(name.to_s, z0, z1))
             else
               Sketchup::ComponentInstance.new(leaf(name.to_s, z0, z1))
             end
      place(wrapper_def.entities, node, z0 - wrapper_z)
      [name, node]
    end
    wrapper = wrapper_kind == :group ? Sketchup::Group.new(wrapper_def) : Sketchup::ComponentInstance.new(wrapper_def)
    place_root = Sketchup::ComponentDefinition.new('Root')
    place(place_root.entities, wrapper, wrapper_z)
    root = root_kind == :group ? Sketchup::Group.new(place_root) : Sketchup::ComponentInstance.new(place_root)
    @model.active_entities << root
    @model.selection.instance_variable_set(:@list, [root])
    @instance = root
    @overlay = TestHarness.build_overlay(model: @model, selection: @model.selection)
    @overlay.enabled = true
    @overlay.display_authorized = true
    [root, wrapper, leaves]
  end

  def world_z(wrapper, node)
    b = node.bounds
    [b.min, b.max].map { |pt| pt.transform(wrapper.transformation).z.round(6) }
  end

  SPANS = { rail: [0.0, 10.0], handle: [4.0, 8.0], glass: [30.0, 70.0], far: [90.0, 100.0],
            cross: [10.0, 50.0], span_all: [0.0, 100.0] }.freeze


  # -- Recursive zone deformation of a multi-grouped door ----------------------

  # Raw edge-vertex Z values (world/solver space) at ANY nesting depth.
  def raw_zs(entities, composite = nil)
    zs = entities.grep(Sketchup::Edge).flat_map(&:vertices).uniq.map do |v|
      pt = composite ? v.position.transform(composite) : v.position
      pt.z.round(6)
    end
    entities.grep(Sketchup::Group).each do |g|
      tr = composite ? composite * g.transformation : g.transformation
      zs.concat(raw_zs(g.entities, tr))
    end
    zs.uniq.sort
  end

  def span_of(node, composite)
    zs = raw_zs(node.entities, composite * node.transformation)
    [zs.first, zs.last]
  end

  # Group `name` spanning [z0, z1] (world), placed inside a parent whose own
  # origin sits at parent_z0.
  def door_part(entities, name, z0, z1, parent_z0 = 0.0)
    d = Sketchup::ComponentDefinition.new(name.to_s)
    TestFixtures.build_box(d.entities, 4.0, 4.0, z1 - z0)
    g = Sketchup::Group.new(d)
    g.transformation = Geom::Transformation.translation(Geom::Vector3d.new(0, 0, z0 - parent_z0))
    entities << g
    g
  end

  def door_container(entities, name, z0, parent_z0 = 0.0)
    g = Sketchup::Group.new(Sketchup::ComponentDefinition.new(name.to_s))
    g.transformation = Geom::Transformation.translation(Geom::Vector3d.new(0, 0, z0 - parent_z0))
    entities << g
    g
  end

  # root(group, no raw geometry) > leaf > { stiles, rails, panel > bevel,
  # hardware > handle, hardware2 > lock }
  def realistic_door
    root = Sketchup::Group.new(Sketchup::ComponentDefinition.new('Door'))
    leaf = door_container(root.entities, :leaf, 0.0)
    parts = {}
    parts[:stile_l] = door_part(leaf.entities, :stile_l, 0.0, 100.0)
    parts[:stile_r] = door_part(leaf.entities, :stile_r, 0.0, 100.0)
    parts[:bottom] = door_part(leaf.entities, :bottom, 0.0, 10.0)
    parts[:top] = door_part(leaf.entities, :top, 90.0, 100.0)
    parts[:panel] = door_part(leaf.entities, :panel, 30.0, 70.0)
    door_part(parts[:panel].entities, :bevel, 35.0, 65.0, 30.0)
    parts[:hardware] = door_container(leaf.entities, :hardware, 80.0)
    parts[:handle] = door_part(parts[:hardware].entities, :handle, 82.0, 88.0, 80.0)
    parts[:hardware2] = door_container(leaf.entities, :hardware2, 0.0)
    parts[:lock] = door_part(parts[:hardware2].entities, :lock, 4.0, 9.0, 0.0)
    [root, leaf, parts]
  end

  def all_groups(entities, acc = [])
    entities.grep(Sketchup::Group).each { |g| acc << g; all_groups(g.entities, acc) }
    acc
  end

  def select_root(root)
    @model.active_entities << root
    @model.selection.instance_variable_set(:@list, [root])
    @instance = root
    @overlay = TestHarness.build_overlay(model: @model, selection: @model.selection)
    @overlay.enabled = true
    @overlay.display_authorized = true
  end

  def test_multi_grouped_door_recursive_zone_deforms_nested_raw_geometry_without_scaling_instances
    root, leaf, parts = realistic_door
    select_root(root)
    save_zone(20.0, 20.0) # protected 0..20 and 80..100; stretch 20..80
    before_trs = all_groups(root.entities).to_h { |g| [g, g.transformation.to_a.dup] }
    assert_empty root.entities.grep(Sketchup::Edge), 'almost no raw geometry at the top level'

    scale_z(1.5) # stretch band 60 -> 110, delta 50

    before_trs.each { |g, tr| assert_equal tr, g.transformation.to_a, 'no group/component transform changed' }
    assert_in_delta 1.0, root.transformation.to_a[10], 1e-9

    leaf_tr = leaf.transformation
    assert_equal [0.0, 10.0], span_of(parts[:bottom], leaf_tr), 'near protected rail unchanged'
    lock_tr = leaf_tr * parts[:hardware2].transformation
    assert_equal [4.0, 9.0], span_of(parts[:lock], lock_tr), 'nested lock unchanged'
    assert_equal [140.0, 150.0], span_of(parts[:top], leaf_tr), 'far protected rail: same size, moved by the delta'
    handle_tr = leaf_tr * parts[:hardware].transformation
    assert_equal [132.0, 138.0], span_of(parts[:handle], handle_tr), 'handle (2 levels deep) translates rigidly'
    assert_equal [0.0, 150.0], span_of(parts[:stile_l], leaf_tr), 'frame member through the band is stretched'
    assert_equal [0.0, 150.0], span_of(parts[:stile_r], leaf_tr)
    panel = span_of(parts[:panel], leaf_tr)
    assert_in_delta 20.0 + (10.0 * 110.0 / 60.0), panel[0], 1e-6, 'raw panel geometry in the band changed'
    assert_in_delta 20.0 + (50.0 * 110.0 / 60.0), panel[1], 1e-6
    bevel = parts[:panel].entities.grep(Sketchup::Group).first
    bz = raw_zs(bevel.entities, leaf_tr * parts[:panel].transformation * bevel.transformation)
    assert_in_delta 20.0 + (15.0 * 110.0 / 60.0), bz.first, 1e-6, 'doubly nested raw geometry deformed'
    assert_in_delta 20.0 + (45.0 * 110.0 / 60.0), bz.last, 1e-6
  end

  def test_recursive_zone_composes_transforms_for_group_and_component_nesting
    [[:group, :group], [:group, :component], [:component, :group], [:component, :component]].each do |root_kind, wrap_kind|
      setup
      wrap_def = Sketchup::ComponentDefinition.new('Wrap')
      TestFixtures.build_box(wrap_def.entities, 4.0, 4.0, 10.0)
      far_def = Sketchup::ComponentDefinition.new('Far')
      TestFixtures.build_box(far_def.entities, 4.0, 4.0, 10.0)
      far_inst = Sketchup::Group.new(far_def)
      far_inst.transformation = Geom::Transformation.translation(Geom::Vector3d.new(0, 0, 90.0))
      wrap_def.entities << far_inst
      wrapper = wrap_kind == :group ? Sketchup::Group.new(wrap_def) : Sketchup::ComponentInstance.new(wrap_def)
      root_def = Sketchup::ComponentDefinition.new('R')
      root_def.entities << wrapper
      root = root_kind == :group ? Sketchup::Group.new(root_def) : Sketchup::ComponentInstance.new(root_def)
      select_root(root)
      save_zone(20.0, 20.0)

      scale_z(1.5)

      zs = []
      walk = lambda do |entities, tr|
        entities.grep(Sketchup::Edge).flat_map(&:vertices).uniq.each { |v| zs << v.position.transform(tr).z.round(6) }
        entities.select { |e| e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance) }.each do |c|
          walk.call(c.is_a?(Sketchup::Group) ? c.entities : c.definition.entities, tr * c.transformation)
        end
      end
      walk.call(root.is_a?(Sketchup::Group) ? root.entities : root.definition.entities, root.transformation)
      assert_equal [0.0, 10.0, 140.0, 150.0], zs.uniq.sort, "#{root_kind}/#{wrap_kind}: near end fixed, far end carried by the delta"
    end
  end

  # -- Save (editor) -> scale lookup: same entity, axis and orientation key -------

  def save_through_editor(axis_id, inner_min_value)
    hover(axis_id)
    assert @overlay.start_smart_scale_zone_edit(axis_id), "editor opens for #{axis_id}"
    @overlay.set_smart_scale_zone_boundary(:inner_min, inner_min_value)
    assert @overlay.commit_smart_scale_zone_edit(@view), "zone for #{axis_id} was saved"
    @overlay.smart_scale_zone_override(@instance, axis_id)
  end

  def test_zone_saved_by_the_editor_is_found_by_the_scale_gesture_for_every_axis
    { x: 1.0, y: 1.0, z: 30.0 }.each do |axis, value|
      setup
      saved = save_through_editor(axis, value)
      refute_nil saved, "#{axis}: zone stored on the selected instance"
      state = zone_state(axis)
      assert_in_delta saved[0], state.profile[:inner_min] - state.profile[:min], 1e-6, "#{axis}: gesture used the saved zone"
    end
  end

  def test_zone_survives_make_unique_before_the_gesture
    twin = TestFixtures.frame_component(@model.active_entities, z_size: Z_SIZE, leg: LEG)
    twin.instance_variable_set(:@definition, @instance.definition)
    @instance.definition.instances << twin # shared definition: Smart Scale will make_unique this instance
    save_through_editor(:z, 30.0)
    definition_before = @instance.definition

    TestHarness.drive_scale_drag(@overlay, axis_id: :z, ratio: 1.5, origin: @instance.bounds.min)

    refute_equal definition_before, @instance.definition, 'make_unique really swapped the definition'
    assert_equal [30.0, LEG], @overlay.smart_scale_zone_override(@instance, :z)
    state = zone_state
    assert_in_delta 30.0, state.profile[:inner_min] - state.profile[:min], 1e-6, 'zone still drives the gesture'
  end

  def test_zone_is_found_on_a_nested_dynamic_component_selection
    root, dc, = dc_selection_fixture
    select_root(root)
    key = @overlay.smart_scale_zone_attribute_key(root, :z)
    root.set_attribute(P::GizmoOverlay::SMART_SCALE_ZONE_DICTIONARY, key, [20.0, 20.0])
    assert dc.attribute_dictionary('dynamic_attributes', false)

    scale_z(1.5)

    assert_equal [20.0, 20.0], @overlay.smart_scale_zone_override(root, :z)
    state = zone_state
    assert_in_delta 20.0, state.profile[:inner_min] - state.profile[:min], 1e-6
  end

  def dc_selection_fixture
    root = Sketchup::Group.new(Sketchup::ComponentDefinition.new('Cabinet'))
    dc_def = Sketchup::ComponentDefinition.new('DCDoor')
    dc = Sketchup::ComponentInstance.new(dc_def)
    door_part(dc_def.entities, :bottom, 0.0, 10.0)
    door_part(dc_def.entities, :top, 90.0, 100.0)
    root.entities << dc
    dc.set_attribute('dynamic_attributes', 'lenz', 100.0)
    [root, dc]
  end

  def test_zone_is_kept_per_orientation_and_found_again_in_each
    save_through_editor(:z, 30.0)                                   # global
    P::PLUGIN.test_gizmo_orientation = P::LOCAL_ORIENTATION         # object
    assert_nil @overlay.smart_scale_zone_override(@instance, :z), 'object orientation has its own (empty) zone'
    save_through_editor(:z, 40.0)
    P::CustomOrientation.store!(@instance, Geom::Vector3d.new(1, 0, 0), Geom::Vector3d.new(0, 0, 1))
    custom_before = @overlay.smart_scale_zone_override(@instance, :z)
    assert_nil custom_before, 'custom orientation has its own (empty) zone'
    save_through_editor(:z, 50.0)

    assert_equal [50.0, LEG], @overlay.smart_scale_zone_override(@instance, :z)
    P::CustomOrientation.reset!(@instance)
    assert_equal [40.0, LEG], @overlay.smart_scale_zone_override(@instance, :z)
    P::PLUGIN.test_gizmo_orientation = P::GLOBAL_ORIENTATION
    assert_equal [30.0, LEG], @overlay.smart_scale_zone_override(@instance, :z)
  end

  def test_no_saved_zone_is_still_none_for_the_gesture
    assert_nil @overlay.smart_scale_zone_override(@instance, :z)
    assert_equal({ min: 0.0, inner_min: LEG, inner_max: Z_SIZE - LEG, max: Z_SIZE }, zone_state.profile)
  end

  # -- Recursive write-back round trip: rotated / scaled / translated nesting ------

  def xform(translation: [0, 0, 0], rotate: nil, scale: [1.0, 1.0, 1.0])
    tr = Geom::Transformation.translation(Geom::Vector3d.new(*translation))
    tr *= Geom::Transformation.rotation(ORIGIN, rotate[0], rotate[1].degrees) if rotate
    tr * Geom::Transformation.scaling(*scale)
  end

  def box_definition(name, x, y, z)
    d = Sketchup::ComponentDefinition.new(name)
    TestFixtures.build_box(d.entities, x, y, z)
    d
  end

  # root component (raw box) > group A (rotated 90 deg about X, translated)
  #   > component B (non-unit scale) > group C (rotated about Z) ; every level has raw geometry.
  def rotated_scaled_hierarchy
    root_def = box_definition('Root', 4.0, 4.0, 60.0)
    a = Sketchup::Group.new(box_definition('A', 3.0, 3.0, 30.0))
    a.transformation = xform(translation: [5, 0, 2], rotate: [X_AXIS, 90])
    root_def.entities << a
    b = Sketchup::ComponentInstance.new(box_definition('B', 2.0, 2.0, 12.0))
    b.transformation = xform(translation: [1, 1, 1], scale: [2.0, 0.5, 3.0])
    a.entities << b
    c = Sketchup::Group.new(box_definition('C', 1.0, 1.0, 6.0))
    c.transformation = xform(translation: [0.5, 0.2, 1.0], rotate: [Z_AXIS, 45])
    b.definition.entities << c
    root = Sketchup::ComponentInstance.new(root_def)
    root.transformation = xform(translation: [10, 20, 30], rotate: [Z_AXIS, 30])
    [root, a, b, c]
  end

  def all_vertices_with_composite(entities, composite = nil, acc = [])
    entities.grep(Sketchup::Edge).flat_map(&:vertices).uniq.each { |v| acc << [v, composite] }
    entities.select { |e| e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance) }.each do |child|
      inner = child.is_a?(Sketchup::Group) ? child.entities : child.definition.entities
      all_vertices_with_composite(inner, composite ? composite * child.transformation : child.transformation, acc)
    end
    acc
  end

  def world_point(vertex, composite, root)
    pt = composite ? vertex.position.transform(composite) : vertex.position
    pt.transform(root.transformation)
  end

  def roundtrip_check(root, label)
    select_root(root)
    key = @overlay.smart_scale_zone_attribute_key(root, :z)
    root.set_attribute(P::GizmoOverlay::SMART_SCALE_ZONE_DICTIONARY, key, [1.0, 1.0])
    entries = all_vertices_with_composite(root.definition.entities)
    locals = entries.to_h { |v, _| [v, v.position.clone] }
    worlds = entries.map { |v, tr| world_point(v, tr, root) }
    state = zone_state
    refute_nil state, "#{label}: state builds"
    assert_in_delta 1.0, state.profile[:inner_min] - state.profile[:min], 1e-6, "#{label}: the saved zone is applied"
    assert_operator state.vertex_entries.length, :>=, entries.length / 2, "#{label}: nested vertices were collected"
    span = state.profile[:max] - state.profile[:min]

    # ratio 1.0: every raw vertex reproduces its original LOCAL coordinates.
    assert P::SmartScaleApplier.apply!(@overlay, state, 1.0)
    locals.each { |v, pos| assert_in_delta 0.0, v.position.distance(pos), 1e-7, "#{label}: ratio 1.0 round-trips local coordinates" }
    state.restore!

    # small ratio: bounded movement, never a jump.
    ratio = 1.0 + (0.25 / span)
    assert P::SmartScaleApplier.apply!(@overlay, state, ratio)
    moved = 0
    entries.each_with_index do |(v, tr), i|
      d = world_point(v, tr, root).distance(worlds[i])
      moved += 1 if d > 1e-9
      assert_operator d, :<=, 0.25 + 1e-6, "#{label}: no vertex moves further than the 0.25 stretch delta (moved #{d})"
    end
    assert_operator moved, :>, 0, "#{label}: the zone really deformed something"
    state.restore!
    locals.each { |v, pos| assert_in_delta 0.0, v.position.distance(pos), 1e-7, "#{label}: restore returns local coordinates" }
  end

  def test_rotated_translated_nonuniformly_scaled_nesting_round_trips_in_global
    root, = rotated_scaled_hierarchy
    roundtrip_check(root, 'global')
  end

  def test_the_same_hierarchy_round_trips_in_object_orientation
    P::PLUGIN.test_gizmo_orientation = P::LOCAL_ORIENTATION
    root, = rotated_scaled_hierarchy
    roundtrip_check(root, 'object')
  end

  def test_the_same_hierarchy_round_trips_in_a_custom_orientation
    P::PLUGIN.test_gizmo_orientation = P::LOCAL_ORIENTATION
    root, = rotated_scaled_hierarchy
    P::CustomOrientation.store!(root, Geom::Vector3d.new(1, 0, 0), Geom::Vector3d.new(0, 0.6, 0.8))
    roundtrip_check(root, 'custom')
  end

  def test_component_in_component_in_group_round_trips
    inner = Sketchup::ComponentInstance.new(box_definition('Inner', 2.0, 2.0, 20.0))
    inner.transformation = xform(translation: [0, 0, 3], scale: [1.0, 1.0, 0.5])
    mid_def = box_definition('Mid', 3.0, 3.0, 25.0)
    mid = Sketchup::ComponentInstance.new(mid_def)
    mid.transformation = xform(translation: [2, 0, 4], rotate: [Y_AXIS, 90])
    mid_def.entities << inner
    root = Sketchup::Group.new(Sketchup::ComponentDefinition.new('G'))
    root.entities << mid
    TestFixtures.build_box(root.entities, 4.0, 4.0, 50.0)
    select_root(root)
    root.set_attribute(P::GizmoOverlay::SMART_SCALE_ZONE_DICTIONARY, @overlay.smart_scale_zone_attribute_key(root, :z), [1.0, 1.0])
    state = zone_state
    span = state.profile[:max] - state.profile[:min]
    all = all_vertices_with_composite(root.entities)
    before = all.map { |v, tr| (tr ? v.position.transform(tr) : v.position).clone }
    assert P::SmartScaleApplier.apply!(@overlay, state, 1.0 + (0.25 / span))
    all.each_with_index do |(v, tr), i|
      d = (tr ? v.position.transform(tr) : v.position).distance(before[i])
      assert_operator d, :<=, 0.25 + 1e-6, "component in component in group: bounded movement (#{d})"
    end
  end

  def test_real_log_shape_a_quarter_unit_stretch_never_moves_geometry_by_hundreds
    root, = rotated_scaled_hierarchy
    select_root(root)
    root.set_attribute(P::GizmoOverlay::SMART_SCALE_ZONE_DICTIONARY, @overlay.smart_scale_zone_attribute_key(root, :z), [7.811, 10.707])
    entries = all_vertices_with_composite(root.definition.entities)
    worlds = entries.map { |v, tr| world_point(v, tr, root) }
    state = zone_state
    span = state.profile[:max] - state.profile[:min]

    assert P::SmartScaleApplier.apply!(@overlay, state, 1.0 + (0.25 / span))

    entries.each_with_index do |(v, tr), i|
      assert_operator world_point(v, tr, root).distance(worlds[i]), :<=, 0.25 + 1e-6
    end
  end

  def test_a_definition_that_stays_shared_is_deformed_once_not_once_per_instance
    shared_def = box_definition('Panel', 2.0, 2.0, 20.0)
    root_def = box_definition('Root', 4.0, 4.0, 60.0)
    instances = [0.0, 10.0, 20.0].map do |x|
      inst = Sketchup::ComponentInstance.new(shared_def)
      inst.transformation = xform(translation: [x, 0, 5], scale: [1.0, 1.0, 2.0])
      inst.define_singleton_method(:make_unique) { self } # simulate a definition that cannot be made unique
      root_def.entities << inst
      inst
    end
    root = Sketchup::ComponentInstance.new(root_def)
    select_root(root)
    root.set_attribute(P::GizmoOverlay::SMART_SCALE_ZONE_DICTIONARY, @overlay.smart_scale_zone_attribute_key(root, :z), [1.0, 1.0])
    before = shared_def.entities.grep(Sketchup::Edge).flat_map(&:vertices).uniq.to_h { |v| [v, v.position.clone] }

    state = zone_state
    span = state.profile[:max] - state.profile[:min]
    assert_equal state.vertex_entries.map { |e| e[:vertex] }.uniq.length, state.vertex_entries.length, 'no vertex is listed twice'
    assert P::SmartScaleApplier.apply!(@overlay, state, 1.0 + (0.25 / span))

    # scale z = 2 on every instance: a 0.25 world move is at most 0.125 local, once.
    before.each { |v, pos| assert_operator v.position.distance(pos), :<=, 0.125 + 1e-6, 'shared vertex moved exactly once' }
  end

  # -- Solver-space invariants: a mapped point moves ONLY along the zone axis -------

  # root component (raw box) with one nested child per transform, each child
  # inside the previous one, every level carrying raw geometry.
  def nested_chain(xforms, kinds = nil)
    root_def = box_definition('ChainRoot', 4.0, 4.0, 60.0)
    parent_def = root_def
    xforms.each_with_index do |tr, i|
      kind = (kinds && kinds[i]) || (i.even? ? :group : :component)
      defn = box_definition("Chain#{i}", 3.0, 3.0, 24.0 - i)
      node = kind == :group ? Sketchup::Group.new(defn) : Sketchup::ComponentInstance.new(defn)
      node.transformation = tr
      parent_def.entities << node
      parent_def = defn
    end
    root = Sketchup::ComponentInstance.new(root_def)
    root.transformation = xform(translation: [3, -4, 7], rotate: [Z_AXIS, 20])
    root
  end

  def solver_points(root, rts)
    all_vertices_with_composite(root.definition.entities).map do |v, tr|
      (tr ? v.position.transform(tr) : v.position).transform(rts)
    end
  end

  def solver_space_check(root, label, delta = 0.023)
    select_root(root)
    root.set_attribute(P::GizmoOverlay::SMART_SCALE_ZONE_DICTIONARY, @overlay.smart_scale_zone_attribute_key(root, :z), [1.0, 1.0])
    rts = @overlay.smart_scale_root_to_solver_transformation(root)
    entries = all_vertices_with_composite(root.definition.entities)
    locals = entries.map { |v, _| v.position.clone }
    before = solver_points(root, rts)
    state = zone_state
    assert_in_delta 1.0, state.profile[:inner_min] - state.profile[:min], 1e-6, "#{label}: saved zone applied"
    span = state.profile[:max] - state.profile[:min]

    assert P::SmartScaleApplier.apply!(@overlay, state, 1.0), "#{label}: ratio 1.0 applies"
    solver_points(root, rts).each_with_index do |pt, i|
      assert_in_delta 0.0, pt.distance(before[i]), 1e-7, "#{label}: ratio 1.0 is an exact solver-space round trip"
    end

    assert P::SmartScaleApplier.apply!(@overlay, state, 1.0 + (delta / span)), "#{label}: #{delta} stretch applies (not aborted)"
    moved = 0
    solver_points(root, rts).each_with_index do |pt, i|
      along = pt.z - before[i].z
      drift = Math.sqrt(((pt.x - before[i].x)**2) + ((pt.y - before[i].y)**2))
      assert_operator drift, :<, 1e-6, "#{label}: no sideways drift in solver space (#{drift})"
      assert_operator along.abs, :<=, delta + 1e-9, "#{label}: along-axis move bounded by the stretch delta (#{along})"
      moved += 1 if along.abs > 1e-9
    end
    assert_operator moved, :>, 0, "#{label}: the zone really deformed something"
    state.restore!
    entries.each_with_index { |(v, _), i| assert_in_delta 0.0, v.position.distance(locals[i]), 1e-7, "#{label}: restore" }
  end

  def test_solver_space_invariants_hold_for_rotated_mirrored_scaled_and_deep_nesting
    cases = {
      'nested 90-degree rotations' => [xform(translation: [1, 0, 1], rotate: [X_AXIS, 90]), xform(translation: [0, 1, 0], rotate: [Y_AXIS, 90]), xform(rotate: [Z_AXIS, 90])],
      'mirrored instance' => [xform(translation: [2, 0, 3], scale: [-1.0, 1.0, 1.0])],
      'mirrored in z' => [xform(translation: [0, 0, 20], scale: [1.0, 1.0, -1.0])],
      'non-uniform scale' => [xform(translation: [1, 1, 1], scale: [2.0, 0.5, 3.0])],
      'deep nesting' => Array.new(6) { |i| xform(translation: [0.5, 0.25, 1.0 + i], rotate: [Z_AXIS, 15 * (i + 1)]) },
      'combination' => [xform(translation: [1, 0, 2], rotate: [X_AXIS, 90], scale: [1.5, 1.0, 1.0]),
                        xform(translation: [0, 2, 0], scale: [-1.0, 2.0, 0.5]),
                        xform(translation: [1, 1, 1], rotate: [Y_AXIS, 90]),
                        xform(rotate: [Z_AXIS, 33], scale: [1.0, -1.0, 2.0])]
    }
    cases.each do |label, xforms|
      setup
      solver_space_check(nested_chain(xforms), label)
    end
  end

  def test_solver_space_invariants_hold_for_repeated_definitions_made_unique
    shared = box_definition('Repeated', 2.0, 2.0, 18.0)
    root_def = box_definition('RepeatRoot', 4.0, 4.0, 60.0)
    [0.0, 8.0, 16.0].each_with_index do |x, i|
      inst = Sketchup::ComponentInstance.new(shared)
      inst.transformation = xform(translation: [x, 0, 4], rotate: [X_AXIS, 90 * (i % 2)], scale: [1.0, i.zero? ? -1.0 : 1.0, 1.0 + i])
      inst.make_unique
      root_def.entities << inst
    end
    root = Sketchup::ComponentInstance.new(root_def)
    solver_space_check(root, 'repeated definitions')
  end

  def test_solver_space_invariants_hold_in_object_and_custom_orientation
    xforms = [xform(translation: [1, 0, 2], rotate: [X_AXIS, 90]), xform(translation: [0, 1, 0], scale: [-1.0, 1.0, 2.0]), xform(rotate: [Z_AXIS, 40])]
    P::PLUGIN.test_gizmo_orientation = P::LOCAL_ORIENTATION
    solver_space_check(nested_chain(xforms), 'object')
    setup
    P::PLUGIN.test_gizmo_orientation = P::LOCAL_ORIENTATION
    root = nested_chain(xforms)
    P::CustomOrientation.store!(root, Geom::Vector3d.new(1, 0, 0), Geom::Vector3d.new(0, 0.6, 0.8))
    solver_space_check(root, 'custom')
  end

  def test_a_write_the_model_does_not_take_as_computed_aborts_the_zone_gesture_and_restores_everything
    root = nested_chain([xform(translation: [1, 0, 2], rotate: [X_AXIS, 90]), xform(translation: [0, 1, 1])])
    select_root(root)
    root.set_attribute(P::GizmoOverlay::SMART_SCALE_ZONE_DICTIONARY, @overlay.smart_scale_zone_attribute_key(root, :z), [1.0, 1.0])
    child = root.definition.entities.grep(Sketchup::Group).first
    corrupt_once = true
    child.entities.define_singleton_method(:transform_by_vectors) do |vertices, vectors|
      if corrupt_once
        corrupt_once = false
        vectors = vectors.map { |v| Geom::Vector3d.new(v.x + 0.5, v.y, v.z) } # corrupting sideways write
      end
      super(vertices, vectors)
    end
    entries = all_vertices_with_composite(root.definition.entities)
    locals = entries.map { |v, _| v.position.clone }
    state = zone_state
    span = state.profile[:max] - state.profile[:min]
    scale_calls = []
    @model.active_entities.define_singleton_method(:transform_entities) { |tr, _e| scale_calls << tr }

    refute P::SmartScaleApplier.apply!(@overlay, state, 1.0 + (0.5 / span)), 'the corrupted write is refused'

    assert state.aborted, 'the zone gesture is marked aborted'
    entries.each_with_index { |(v, _), i| assert_in_delta 0.0, v.position.distance(locals[i]), 1e-9, 'geometry restored' }
    refute P::SmartScaleApplier.apply!(@overlay, state, 1.2), 'an aborted gesture writes nothing more'
    entries.each_with_index { |(v, _), i| assert_in_delta 0.0, v.position.distance(locals[i]), 1e-9 }
    assert_empty scale_calls
  end

  # -- Batching architecture: one simultaneous write per Entities owner ------------
  # NOTE: the stubs cannot reproduce SketchUp's topology side effects (curve
  # re-fitting, face re-evaluation after each vertex write); these tests pin the
  # write PATTERN that avoids them, not the side effects themselves.

  def instrument_writes(root)
    calls = []
    owners = [root.definition.entities]
    walker = lambda do |entities|
      entities.select { |e| e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance) }.each do |c|
        inner = c.is_a?(Sketchup::Group) ? c.entities : c.definition.entities
        owners << inner
        walker.call(inner)
      end
    end
    walker.call(root.definition.entities)
    owners.each do |entities|
      entities.define_singleton_method(:transform_by_vectors) do |vertices, vectors|
        calls << { owner: entities, vertices: vertices.dup, vectors: vectors.dup }
        super(vertices, vectors)
      end
    end
    calls
  end

  def batching_fixture
    root = nested_chain([xform(translation: [1, 0, 2], rotate: [X_AXIS, 90]), xform(translation: [0, 1, 1], scale: [1.0, 1.0, 2.0]),
                         xform(rotate: [Z_AXIS, 30])])
    select_root(root)
    root.set_attribute(P::GizmoOverlay::SMART_SCALE_ZONE_DICTIONARY, @overlay.smart_scale_zone_attribute_key(root, :z), [1.0, 1.0])
    state = zone_state
    [root, state, state.profile[:max] - state.profile[:min]]
  end

  def test_zero_stretch_performs_no_geometry_write_at_all
    root, state, = batching_fixture
    calls = instrument_writes(root)

    assert P::SmartScaleApplier.apply!(@overlay, state, 1.0)
    assert P::SmartScaleApplier.apply!(@overlay, state, 1.0)

    assert_empty calls, 'ratio 1.0 / stretch delta 0 writes nothing'
  end

  def test_every_frame_writes_each_owner_once_from_the_original_snapshot
    root, state, span = batching_fixture
    calls = instrument_writes(root)

    [1.0 + (2.0 / span), 1.0 + (1.0 / span), 1.0 + (3.0 / span)].each do |ratio|
      calls.clear
      assert P::SmartScaleApplier.apply!(@overlay, state, ratio)

      assert_equal calls.map { |c| c[:owner].object_id }.uniq.length, calls.length, 'at most one batch per owner per frame (no restore pass first)'
      calls.each do |c|
        assert_equal c[:vertices].uniq.length, c[:vertices].length, 'vertices are de-duplicated within a batch'
        assert_equal c[:vertices].length, c[:vectors].length
      end
    end
  end

  def test_returning_to_zero_and_restore_are_single_batches_per_owner
    root, state, span = batching_fixture
    entries = all_vertices_with_composite(root.definition.entities)
    locals = entries.map { |v, _| v.position.clone }
    assert P::SmartScaleApplier.apply!(@overlay, state, 1.0 + (2.0 / span))
    calls = instrument_writes(root)

    assert P::SmartScaleApplier.apply!(@overlay, state, 1.0) # back to zero stretch
    assert_equal calls.map { |c| c[:owner].object_id }.uniq.length, calls.length, 'one restore batch per owner'
    entries.each_with_index { |(v, _), i| assert_in_delta 0.0, v.position.distance(locals[i]), 1e-9 }

    assert P::SmartScaleApplier.apply!(@overlay, state, 1.0 + (2.0 / span))
    calls.clear
    state.restore!
    assert_equal calls.map { |c| c[:owner].object_id }.uniq.length, calls.length, 'abort/cancel restore: one batch per owner'
  end

  def test_a_failed_post_write_verify_batch_restores_and_aborts_without_ordinary_scale
    root, state, span = batching_fixture
    child = root.definition.entities.grep(Sketchup::Group).first
    child_calls = []
    corrupt_once = true
    child.entities.define_singleton_method(:transform_by_vectors) do |vertices, vectors|
      child_calls << vertices.length
      if corrupt_once
        corrupt_once = false
        vectors = vectors.map { |v| Geom::Vector3d.new(v.x + 0.5, v.y, v.z) }
      end
      super(vertices, vectors)
    end
    scale_calls = []
    @model.active_entities.define_singleton_method(:transform_entities) { |tr, _e| scale_calls << tr }
    entries = all_vertices_with_composite(root.definition.entities)
    locals = entries.map { |v, _| v.position.clone }

    refute P::SmartScaleApplier.apply!(@overlay, state, 1.0 + (2.0 / span))

    assert state.aborted
    assert_equal 2, child_calls.length, 'exactly one write batch and one restore batch for the owner'
    entries.each_with_index { |(v, _), i| assert_in_delta 0.0, v.position.distance(locals[i]), 1e-9 }
    assert_empty scale_calls
  end

  def test_every_vertex_of_a_curve_touching_the_stretch_zone_takes_the_same_offset
    arc = Object.new
    ends = [[0.0, 45.0], [0.0, 55.0], [0.0, 65.0], [0.0, 75.0], [0.0, 85.0]]
    ends.each_cons(2) do |a, b|
      edge = Sketchup::Edge.new(Geom::Point3d.new(1, a[0], a[1]), Geom::Point3d.new(1, b[0], b[1]))
      edge.curve = arc
      @instance.definition.entities << edge
    end
    save_zone(30.0, 20.0) # stretch 30..80; the curve crosses the inner_max boundary
    before = @instance.definition.entities.grep(Sketchup::Edge).select(&:curve).flat_map(&:vertices).map { |v| v.position.z }

    scale_z(1.5)

    after = @instance.definition.entities.grep(Sketchup::Edge).select(&:curve).flat_map(&:vertices).map { |v| v.position.z }
    offsets = after.zip(before).map { |a, b| (a - b).round(6) }.uniq
    assert_equal 1, offsets.length, "all curve vertices (ends included) move by one offset: #{offsets}"
  end

  # -- Curves are rigid units: classified from their solver range, never deformed ---

  # An arc-like curve in the XZ plane between two heights (stub curves are plain
  # shared objects; what matters is that its edges share one #curve).
  def add_arc(entities, z0, z1, segments: 4, x_radius: 1.0)
    curve = Object.new
    points = (0..segments).map do |i|
      t = i.to_f / segments
      Geom::Point3d.new(x_radius * Math.sin(Math::PI * t), 0, z0 + ((z1 - z0) * t))
    end
    edges = points.each_cons(2).map do |a, b|
      edge = Sketchup::Edge.new(a, b)
      edge.curve = curve
      entities << edge
      edge
    end
    edges.each_cons(2) { |e1, e2| e2.instance_variable_set(:@start, e1.end) } # consecutive edges share a vertex
    edges
  end

  def arc_vertices(edges)
    edges.flat_map(&:vertices).uniq
  end

  def arc_case(z0, z1, expected_shift, label)
    setup
    edges = add_arc(@instance.definition.entities, z0, z1)
    save_zone(30.0, 20.0) # stretch zone 30..80, delta 50 at ratio 1.5
    verts = arc_vertices(edges)
    before = verts.map { |v| v.position.clone }
    state = zone_state

    assert_equal 1, state.curve_entries.length, "#{label}: one rigid curve unit"
    assert(state.vertex_entries.none? { |e| verts.any? { |v| v.equal?(e[:vertex]) } }, "#{label}: curve vertices are excluded from the stretch batch")

    scale_z(1.5)

    verts.each_with_index do |v, i|
      assert_in_delta before[i].x, v.position.x, 1e-9, "#{label}: no sideways movement"
      assert_in_delta before[i].y, v.position.y, 1e-9, "#{label}: no sideways movement"
      assert_in_delta expected_shift, v.position.z - before[i].z, 1e-6, "#{label}: whole curve moves by one rigid offset"
    end
  end

  def test_curve_classification_before_after_inside_crossing_and_spanning
    arc_case(5.0, 25.0, 0.0, 'arc wholly before the zone')
    arc_case(85.0, 95.0, 50.0, 'arc wholly after the zone')
    arc_case(40.0, 60.0, 20.0, 'arc wholly inside the zone (centre 50 maps to 70)')
    arc_case(20.0, 45.0, 0.0, 'arc crossing inner_min stays with the near end')
    arc_case(60.0, 90.0, 50.0, 'arc crossing inner_max goes with the far end')
    arc_case(20.0, 90.0, 0.0, 'arc spanning both protected ends is unchanged')
  end

  def test_a_vertex_shared_by_a_curve_and_a_straight_edge_belongs_to_the_curve
    edges = add_arc(@instance.definition.entities, 85.0, 95.0)
    shared = edges.last.end
    tail = Sketchup::Edge.new(Geom::Point3d.new(0, 0, 0), Geom::Point3d.new(0, 0, 50))
    tail.instance_variable_set(:@start, shared)
    @instance.definition.entities << tail
    other_end = tail.end
    save_zone(30.0, 20.0)
    state = zone_state

    assert(state.vertex_entries.none? { |e| e[:vertex].equal?(shared) }, 'the shared vertex is not stretched independently')
    assert(state.curve_entries.first[:vertex_entries].any? { |e| e[:vertex].equal?(shared) }, 'the curve unit owns the shared vertex')
    before = shared.position.clone

    scale_z(1.5)

    assert_in_delta 50.0, shared.position.z - before.z, 1e-6, 'moved once, with its curve'
    assert_in_delta before.x, shared.position.x, 1e-9
    refute_nil other_end
  end

  def test_nested_mirrored_and_rotated_curves_move_rigidly_in_solver_space
    {
      'mirrored' => xform(translation: [2, 0, 10], scale: [-1.0, 1.0, 1.0]),
      'rotated' => xform(translation: [0, 2, 5], rotate: [X_AXIS, 90]),
      'mirrored and rotated' => xform(translation: [1, 1, 40], rotate: [Y_AXIS, 90], scale: [1.0, -1.0, 1.0])
    }.each do |label, tr|
      setup
      root_def = box_definition('CurveRoot', 4.0, 4.0, 60.0)
      holder = Sketchup::Group.new(Sketchup::ComponentDefinition.new('Holder'))
      holder.transformation = tr
      curve_edges = add_arc(holder.entities, 0.0, 18.0)
      root_def.entities << holder
      root = Sketchup::ComponentInstance.new(root_def)
      root.transformation = xform(translation: [3, -4, 7], rotate: [Z_AXIS, 20])
      select_root(root)
      root.set_attribute(P::GizmoOverlay::SMART_SCALE_ZONE_DICTIONARY, @overlay.smart_scale_zone_attribute_key(root, :z), [1.0, 1.0])
      rts = @overlay.smart_scale_root_to_solver_transformation(root)
      verts = arc_vertices(curve_edges)
      solver = ->(v) { v.position.transform(holder.transformation).transform(rts) }
      before = verts.map { |v| solver.call(v) }
      state = zone_state
      span = state.profile[:max] - state.profile[:min]

      assert P::SmartScaleApplier.apply!(@overlay, state, 1.0 + (3.0 / span)), "#{label}: applies"

      offsets = verts.each_with_index.map do |v, i|
        now = solver.call(v)
        assert_in_delta before[i].x, now.x, 1e-6, "#{label}: no sideways drift"
        assert_in_delta before[i].y, now.y, 1e-6, "#{label}: no sideways drift"
        (now.z - before[i].z).round(6)
      end
      assert_equal 1, offsets.uniq.length, "#{label}: one rigid offset for the whole curve (#{offsets.uniq})"
      assert_operator offsets.first.abs, :<=, 3.0 + 1e-6, "#{label}: bounded by the stretch delta"
      state.restore!
      verts.each_with_index { |v, i| assert_in_delta 0.0, solver.call(v).distance(before[i]), 1e-6, "#{label}: restore moves the curve back whole" }
    end
  end
end
