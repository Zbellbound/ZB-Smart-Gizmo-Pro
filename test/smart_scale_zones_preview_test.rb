require 'minitest/autorun'
require_relative 'support/fixtures'

# Focused coverage for the Smart Scale Zones visual prototype (Stage 1):
# transient, read-only overlay graphics showing which part of the selected
# object Smart Scale keeps fixed and which part it stretches, the active
# axis/anchored side, the current outline, and the dimension. Nothing here
# renders through GL -- the View test double records every draw call (see
# Sketchup::View#draw_calls in test/support/sketchup_stubs.rb) so the specs
# assert exactly what WOULD be drawn, the same way the rest of this suite
# asserts logic rather than pixels.
class SmartScaleZonesPreviewTest < Minitest::Test
  P = Zbellbound::SmartGizmoPro
  Z_SIZE = 100.0
  LEG = 10.0

  def setup
    @model = Sketchup::Model.new
    P::PLUGIN.test_smart_scale_enabled = true
    P::PLUGIN.test_gizmo_orientation = P::GLOBAL_ORIENTATION
    UI.last_messagebox_text = nil
    @view = @model.active_view
  end

  def select(*entities)
    @model.selection.instance_variable_set(:@list, entities)
  end

  def build_overlay
    TestHarness.build_overlay(model: @model, selection: @model.selection)
  end

  def frame
    TestFixtures.frame_component(@model.active_entities, z_size: Z_SIZE, leg: LEG)
  end

  def gizmo(overlay)
    TestHarness.gizmo_of(overlay)
  end

  def axis_handle(overlay, axis_id)
    gizmo(overlay).axes.find { |a| a.id == axis_id }.scale_gizmo
  end

  def hover(overlay, axis_id)
    axis_handle(overlay, axis_id).mouse_active = true
  end

  def mask_for(axis_id)
    [axis_id == :x, axis_id == :y, axis_id == :z]
  end

  # Starts a real Smart Scale drag through the overlay's own bound
  # callbacks (the same ones ScaleGizmo drives) and leaves it mid-gesture:
  # start + one transform frame, no end -- so the live state can be
  # inspected and the commit/cancel paths exercised separately.
  def begin_drag(overlay, axis_id:, ratio:, origin:)
    gizmo = gizmo(overlay)
    axis_handle(overlay, axis_id).active = true
    gizmo.instance_variable_get(:@callback_start).call('Scale')
    t_total = Geom::Transformation.scaling(origin, axis_id == :x ? ratio : 1.0, axis_id == :y ? ratio : 1.0,
                                           axis_id == :z ? ratio : 1.0)
    data = [:scale, origin, ratio, mask_for(axis_id), 1.0, origin.clone, IDENTITY]
    gizmo.instance_variable_get(:@callback).call(t_total, t_total, data)
  end

  def commit_drag(overlay, axis_id)
    axis_handle(overlay, axis_id).active = false
    gizmo(overlay).instance_variable_get(:@callback_end).call
  end

  def draws(mode = nil)
    calls = @view.draw_calls.to_a.select { |c| c[:type] == :draw }
    mode ? calls.select { |c| c[:mode] == mode } : calls
  end

  def texts
    @view.draw_calls.to_a.select { |c| c[:type] == :text }
  end

  def quad_groups
    draws(GL_QUADS).each_slice(6).map { |six| six.flat_map { |c| c[:points] } }
  end

  def z_range(points)
    zs = points.map(&:z)
    [zs.min, zs.max]
  end

  # -- Values come from the existing Smart Scale state --------------------

  def test_a_hovered_handle_previews_the_state_the_real_builder_produces
    instance = frame
    select(instance)
    overlay = build_overlay
    hover(overlay, :z)

    shown = overlay.smart_scale_zone_state
    real = overlay.build_smart_scale_gesture_state_for_entity(instance, :z, mask_for(:z),
                                                              [:scale, nil, 1.0, mask_for(:z), nil, nil, nil])

    assert_instance_of P::SmartScaleGestureState, shown
    assert_equal real.profile, shown.profile
    assert_equal({ min: 0.0, inner_min: LEG, inner_max: Z_SIZE - LEG, max: Z_SIZE }, shown.profile)
    assert_equal :z, shown.axis_id
  end

  def test_a_live_drag_reuses_the_gesture_the_real_drag_built_rather_than_rebuilding_it
    instance = frame
    select(instance)
    overlay = build_overlay
    begin_drag(overlay, axis_id: :z, ratio: 0.5, origin: instance.bounds.min)

    live = overlay.instance_variable_get(:@smart_scale_gesture)
    refute_nil live
    assert_same live, overlay.smart_scale_zone_state,
      'during a drag the preview must read the real gesture state itself, not a second copy'
    assert_in_delta 0.5, live.ratio, 1e-9
  end

  def test_hovering_repeatedly_does_not_rescan_geometry_each_frame
    instance = frame
    select(instance)
    overlay = build_overlay
    hover(overlay, :z)
    builds = 0
    original = overlay.method(:build_smart_scale_gesture_state_for_entity)
    overlay.define_singleton_method(:build_smart_scale_gesture_state_for_entity) do |*args|
      builds += 1
      original.call(*args)
    end

    5.times { overlay.smart_scale_zone_state }

    assert_equal 1, builds, 'the hover preview must be built once and cached, not per frame'
  end

  # -- Axis colours ---------------------------------------------------------

  def test_axis_colours_are_red_green_blue_for_x_y_z
    overlay = build_overlay
    assert_equal [255, 0, 0, 255], overlay.smart_scale_zone_axis_color(:x).to_a
    assert_equal [0, 128, 0, 255], overlay.smart_scale_zone_axis_color(:y).to_a
    assert_equal [0, 0, 255, 255], overlay.smart_scale_zone_axis_color(:z).to_a
    assert_nil overlay.smart_scale_zone_axis_color(:w)
  end

  def test_drawn_stretch_fill_uses_the_active_axis_colour
    instance = frame
    select(instance)
    overlay = build_overlay
    hover(overlay, :z)

    overlay.draw_smart_scale_zone_preview(@view)

    expected = overlay.smart_scale_zone_axis_color(:z, P::GizmoOverlay::SMART_SCALE_ZONE_FILL_ALPHA)
    assert_equal [0, 0, 255, P::GizmoOverlay::SMART_SCALE_ZONE_FILL_ALPHA], expected.to_a
    assert_includes draws(GL_QUADS).map { |c| c[:color] }, expected
    assert_includes draws(GL_LINES).map { |c| c[:color] }, overlay.smart_scale_zone_axis_color(:z),
      'the anchor line and outline use the opaque axis colour'
  end

  # -- Protected / stretch regions use the existing classification ----------

  def test_hover_draws_protected_ends_and_the_stretch_middle_from_the_profile
    instance = frame
    select(instance)
    overlay = build_overlay
    hover(overlay, :z)

    overlay.draw_smart_scale_zone_preview(@view)

    # Drawn protected ends first (left, right), then the stretch middle.
    left, right, middle = quad_groups
    assert_equal [0.0, LEG], z_range(left)
    assert_equal [LEG, Z_SIZE - LEG], z_range(middle)
    assert_equal [Z_SIZE - LEG, Z_SIZE], z_range(right)
    quad_colors = draws(GL_QUADS).map { |c| c[:color] }
    assert_equal [P::GizmoOverlay::SMART_SCALE_ZONE_PROTECTED_COLOR], quad_colors.first(6).uniq
    assert_equal [P::GizmoOverlay::SMART_SCALE_ZONE_PROTECTED_COLOR], quad_colors[6, 6].uniq
    refute_equal P::GizmoOverlay::SMART_SCALE_ZONE_PROTECTED_COLOR, quad_colors[12]
  end

  def test_plain_geometry_with_no_profile_shows_no_invented_protected_zones
    box = TestFixtures.group_box
    select(box)
    overlay = build_overlay
    hover(overlay, :z)
    state = overlay.smart_scale_zone_state
    assert_equal :basic, state.mode
    assert_nil state.profile

    overlay.draw_smart_scale_zone_preview(@view)

    assert_empty draws(GL_QUADS), ':basic mode scales the whole object -- there is nothing protected to fill'
    refute_empty draws(GL_LINES), 'the anchored side and outline still show'
  end

  # -- Anchor side ------------------------------------------------------------

  def test_the_anchored_side_is_the_minimum_end_with_a_stronger_line
    instance = frame
    select(instance)
    overlay = build_overlay
    hover(overlay, :z)

    overlay.draw_smart_scale_zone_preview(@view)

    strong = draws(GL_LINES).select { |c| c[:width] == 4 }
    assert_equal 1, strong.length
    assert_equal [0.0], strong.first[:points].map(&:z).uniq, 'the fixed end is the profile minimum'
    assert_equal :min, overlay.smart_scale_zone_anchor_side([false, false, true])
  end

  def test_a_multi_axis_mask_is_treated_as_centre_anchored_and_stretches_both_ways
    instance = frame
    select(instance)
    overlay = build_overlay
    assert_equal :center, overlay.smart_scale_zone_anchor_side([true, true, false])

    state = overlay.build_smart_scale_gesture_state_for_entity(instance, :z, mask_for(:z),
                                                               [:scale, nil, 1.0, mask_for(:z), nil, nil, nil])
    state.ratio = 1.5
    live = overlay.smart_scale_zone_live_profile(state, :center)
    delta = Z_SIZE * 0.5
    assert_in_delta(-delta / 2.0, live[:min], 1e-9)
    assert_in_delta Z_SIZE + (delta / 2.0), live[:max], 1e-9

    overlay.define_singleton_method(:smart_scale_zone_anchor_side) { |_mask| :center }
    hover(overlay, :z)
    overlay.draw_smart_scale_zone_preview(@view)
    assert_empty draws(GL_LINES).select { |c| c[:width] == 4 }, 'no single fixed face when the centre is fixed'
  end

  # -- Live preview follows the real solver -------------------------------------

  def test_live_zones_match_the_geometry_the_solver_actually_produced
    instance = frame
    select(instance)
    overlay = build_overlay
    begin_drag(overlay, axis_id: :z, ratio: 0.5, origin: instance.bounds.min)
    state = overlay.instance_variable_get(:@smart_scale_gesture)

    live = overlay.smart_scale_zone_live_profile(state, :min)
    bounds = instance.definition.bounds
    assert_in_delta bounds.max.z, live[:max], 1e-6, 'the live outer end must equal the real mutated bounds'
    assert_in_delta bounds.min.z, live[:min], 1e-6

    top_leg_vertices = instance.definition.entities.grep(Sketchup::Edge).flat_map { |e| [e.start, e.end] }
                               .map { |v| v.position.z }.select { |z| z > live[:inner_max] - 1e-6 }
    assert_in_delta live[:inner_max], top_leg_vertices.min, 1e-6,
      'the protected end starts exactly where the real solver moved it'

    @view.clear_draw_calls
    overlay.draw_smart_scale_zone_preview(@view)
    _left, right, middle = quad_groups
    assert_equal [LEG, live[:inner_max]], z_range(middle)
    assert_equal [live[:inner_max], live[:max]], z_range(right)
  end

  def test_ghost_outline_follows_the_live_entity_bounds
    instance = frame
    select(instance)
    overlay = build_overlay
    begin_drag(overlay, axis_id: :z, ratio: 0.5, origin: instance.bounds.min)

    overlay.draw_smart_scale_zone_preview(@view)

    outline = draws(GL_LINES).select { |c| c[:width] == 2 }
    refute_empty outline
    assert_in_delta instance.bounds.max.z, outline.flat_map { |c| c[:points] }.map(&:z).max, 1e-6
  end

  # -- Dimension text ----------------------------------------------------------------

  def test_dimension_text_is_the_existing_scale_display_formatting
    instance = frame
    select(instance)
    overlay = build_overlay
    begin_drag(overlay, axis_id: :z, ratio: 0.5, origin: instance.bounds.min)
    state = overlay.instance_variable_get(:@smart_scale_gesture)

    overlay.draw_smart_scale_zone_preview(@view)

    assert_equal [overlay.format_scale_display(state.ratio, state.reference_length)], texts.map { |t| t[:text] }
  end

  def test_hover_dimension_is_the_current_size
    instance = frame
    select(instance)
    overlay = build_overlay
    hover(overlay, :z)
    state = overlay.smart_scale_zone_state

    overlay.draw_smart_scale_zone_preview(@view)

    assert_equal [overlay.format_scale_display(1.0, state.reference_length)], texts.map { |t| t[:text] }
  end

  # -- The overlay goes away ------------------------------------------------------------

  def test_nothing_is_drawn_after_the_drag_commits
    instance = frame
    select(instance)
    overlay = build_overlay
    begin_drag(overlay, axis_id: :z, ratio: 0.5, origin: instance.bounds.min)
    refute_nil overlay.smart_scale_zone_state

    commit_drag(overlay, :z)

    assert_nil overlay.smart_scale_zone_state
    @view.clear_draw_calls
    overlay.draw_smart_scale_zone_preview(@view)
    assert_empty @view.draw_calls
  end

  def test_nothing_is_drawn_after_escape_cancels_the_drag
    instance = frame
    select(instance)
    overlay = build_overlay
    begin_drag(overlay, axis_id: :z, ratio: 0.5, origin: instance.bounds.min)
    fake = gizmo(overlay)
    fake.define_singleton_method(:active?) { true }
    fake.define_singleton_method(:cancel) { nil }

    overlay.onCancel(0, @view)
    axis_handle(overlay, :z).active = false

    assert_nil overlay.smart_scale_zone_state
  end

  def test_nothing_is_drawn_after_the_selection_changes
    first = frame
    second = frame
    select(first)
    overlay = build_overlay
    hover(overlay, :z)
    refute_nil overlay.smart_scale_zone_state

    select(second)
    overlay.selection_changed(@model.selection)
    axis_handle(overlay, :z).mouse_active = false

    assert_nil overlay.smart_scale_zone_state
    select(first, second)
    hover(overlay, :z)
    assert_nil overlay.smart_scale_zone_state, 'multi-selection is out of scope for Stage 1'
  end

  def test_an_invalid_entity_hides_the_zones
    instance = frame
    select(instance)
    overlay = build_overlay
    hover(overlay, :z)
    refute_nil overlay.smart_scale_zone_state

    instance.delete!

    assert_nil overlay.smart_scale_zone_state
    overlay.draw_smart_scale_zone_preview(@view) # must not raise
  end

  def test_a_native_tool_or_disabled_smart_scale_hides_the_zones
    instance = frame
    select(instance)
    overlay = build_overlay
    hover(overlay, :z)
    refute_nil overlay.smart_scale_zone_state

    overlay.instance_variable_set(:@native_tool_override, true)
    assert_nil overlay.smart_scale_zone_state
    overlay.instance_variable_set(:@native_tool_override, false)

    P::PLUGIN.test_smart_scale_enabled = false
    assert_nil overlay.smart_scale_zone_state
  end

  def test_other_gizmo_modes_show_no_zones
    instance = frame
    select(instance)
    overlay = build_overlay

    assert_nil overlay.smart_scale_zone_state, 'no scale handle hovered or dragged (e.g. move/rotate hover)'
    overlay.draw_smart_scale_zone_preview(@view)
    assert_empty @view.draw_calls.to_a
  end

  # -- Read-only: no model change, no Undo ----------------------------------------------------

  def test_hovering_and_drawing_create_no_entities_attributes_or_undo_entries
    instance = frame
    select(instance)
    overlay = build_overlay
    hover(overlay, :z)
    entity_count = instance.definition.entities.to_a.length
    top_level = @model.active_entities.to_a.length

    3.times do
      overlay.smart_scale_zone_state
      overlay.draw_smart_scale_zone_preview(@view)
    end

    assert_equal entity_count, instance.definition.entities.to_a.length
    assert_equal top_level, @model.active_entities.to_a.length
    assert_empty instance.attribute_dictionaries.to_a, 'no attributes are written for the preview'
    assert_empty @model.operation_log
  end

  def test_hovering_a_shared_component_does_not_make_it_unique
    original = frame
    twin = @model.active_entities.add_instance(original.definition, Geom::Transformation.new)
    select(original)
    overlay = build_overlay
    hover(overlay, :z)
    definition_before = original.definition

    overlay.smart_scale_zone_state

    assert_same definition_before, original.definition
    assert_equal 2, original.definition.instances.length
    assert_same definition_before, twin.definition
    assert_empty @model.operation_log, 'a hover must not trigger the Undo entry make_unique would create'
  end

  def test_a_full_drag_still_uses_exactly_one_undo_operation
    instance = frame
    select(instance)
    overlay = build_overlay
    hover(overlay, :z)
    overlay.draw_smart_scale_zone_preview(@view)

    begin_drag(overlay, axis_id: :z, ratio: 0.5, origin: instance.bounds.min)
    overlay.draw_smart_scale_zone_preview(@view)
    commit_drag(overlay, :z)

    assert_equal %i[start commit], @model.operation_log.map(&:first)
  end

  # -- Orientation / transformed instances ----------------------------------------------------------

  def test_zones_stay_inside_the_world_bounds_of_a_rotated_and_mirrored_instance
    instance = frame
    instance.transformation = Geom::Transformation.rotation(ORIGIN, Y_AXIS, 90.degrees) *
                              Geom::Transformation.scaling(-1.0, 1.0, 2.0)
    select(instance)
    overlay = build_overlay
    overlay.instance_variable_set(:@native_tool_override, false)
    hover(overlay, :z)
    P::PLUGIN.test_gizmo_orientation = P::LOCAL_ORIENTATION
    refute_nil overlay.smart_scale_zone_state

    overlay.draw_smart_scale_zone_preview(@view)

    bounds = instance.bounds
    tol = 1e-6
    draws(GL_QUADS).flat_map { |c| c[:points] }.each do |pt|
      assert_operator pt.x, :>=, bounds.min.x - tol
      assert_operator pt.x, :<=, bounds.max.x + tol
      assert_operator pt.y, :>=, bounds.min.y - tol
      assert_operator pt.y, :<=, bounds.max.y + tol
      assert_operator pt.z, :>=, bounds.min.z - tol
      assert_operator pt.z, :<=, bounds.max.z + tol
    end
  end

  def test_a_custom_gizmo_orientation_is_respected_by_the_zones
    instance = frame
    select(instance)
    overlay = build_overlay
    P::PLUGIN.test_gizmo_orientation = P::LOCAL_ORIENTATION
    assert P::CustomOrientation.store!(instance, Geom::Vector3d.new(0, 0, 1), Geom::Vector3d.new(1, 0, 0))
    hover(overlay, :z)

    state = overlay.smart_scale_zone_state

    expected_rts = overlay.custom_orientation_solver_transformation(instance)
    assert_equal expected_rts.to_a, state.root_to_solver_transformation.to_a,
      'the zones use the same solver orientation the real drag would'
  end
end
