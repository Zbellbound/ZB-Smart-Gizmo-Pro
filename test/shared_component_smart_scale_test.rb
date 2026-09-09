require 'minitest/autorun'
require 'stringio'
require_relative 'support/fixtures'

# Defect 2 (R2 correction) -- Smart Scale changed both a copied
# ComponentInstance AND the original it was copied from (R1's shared-
# geometry bug), fixed by resolve_smart_scale_state: a final, immediate
# pre-mutation uniqueness check/rebuild at every SmartScaleApplier.apply!
# call site.
#
# R1's resolve_smart_scale_state detected "did make_unique just make this
# entity's definition unique" by comparing `entity.definition` before and
# after with Object#equal? (strict Ruby object identity). SketchUp's Ruby
# API does not guarantee that two separate #definition accessor calls
# return the *same* Ruby wrapper object even when nothing changed
# underneath -- every other identity check in this file already avoids
# exactly this by comparing with `==` instead (e.g.
# SmartScaleGestureState#matches?). When that #equal? comparison
# spuriously reads "changed" (which it can, on essentially every call, in
# real SketchUp), resolve_smart_scale_state took its rebuild branch on
# EVERY Smart Scale mutation -- including every frame of a live drag --
# rebuilding vertex_entries with "original_local_point" captured from
# whatever the CURRENT (already partially scaled) geometry happened to be
# at that instant. That corrupts the profile/restore! math: Smart Scale
# stops respecting the true fixed-end/stretch-middle structure and
# degrades into something that looks like an ordinary, non-frame-
# preserving scale -- exactly the reported regression.
#
# Fixed by detecting the uniqueness transition via
# entity.definition.instances.length (a plain Integer/value comparison,
# immune to wrapper-identity churn) BEFORE calling
# ensure_component_tree_unique_for_smart_scale, rather than comparing
# `entity.definition` object identity before/after.
#
# These tests assert on actual GEOMETRY -- specific Z-plane positions
# identifying the fixed leg regions and the stretch-middle region -- not
# just on the overall bounding box or on whether make_unique was called,
# per instruction: a test that only checks the bounding box cannot tell
# true Smart Scale (protected ends + stretched middle) apart from
# ordinary scale (everything scaled uniformly) landing on the same
# overall size by coincidence.
class SharedComponentSmartScaleTest < Minitest::Test
  LEG = 10.0
  Z_SIZE = 100.0

  def setup
    @model = Sketchup::Model.new
    Zbellbound::SmartGizmoPro::PLUGIN.test_smart_scale_enabled = true
    Zbellbound::SmartGizmoPro::PLUGIN.test_gizmo_orientation = Zbellbound::SmartGizmoPro::GLOBAL_ORIENTATION
    UI.last_messagebox_text = nil
    UI.last_inputbox_args = nil
    Sketchup.last_vcb_label = nil
    Sketchup.last_vcb_value = nil
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

  # -- Geometry diagnostics -------------------------------------------------
  #
  # The frame fixture (TestFixtures.build_frame) has exactly 4 distinct Z
  # planes: 0, LEG, Z_SIZE-LEG, Z_SIZE. True Smart Scale frame-mode math
  # (SmartScaleApplier#apply!) leaves every vertex at/under the inner_min
  # plane untouched, translates every vertex at/over inner_max by a single
  # uniform delta (rigid, not stretched), and only interpolates vertices
  # strictly between them -- so after any ratio, the bottom leg's OWN span
  # and the top leg's OWN span must both still read back as exactly LEG,
  # and only the middle span may have changed. Ordinary/ordinary-looking
  # scale would instead move every one of these planes proportionally,
  # collapsing the leg spans too -- the exact failure mode this file
  # verifies against.
  def frame_diagnostics(entity)
    levels = entity.definition.entities.grep(Sketchup::Edge)
                   .flat_map(&:vertices).uniq.map { |v| v.position.z }.uniq.sort
    {
      levels: levels,
      bottom_leg_span: levels[1] - levels[0],
      top_leg_span: levels[3] - levels[2],
      middle_span: levels[2] - levels[1],
      overall: levels[3] - levels[0]
    }
  end

  def assert_frame_preserved(before, after, expected_overall:, tol: 1e-6)
    assert_in_delta LEG, after[:bottom_leg_span], tol,
      "bottom leg must retain its original #{LEG} span -- it changed to #{after[:bottom_leg_span]}, meaning the fixed end was stretched"
    assert_in_delta LEG, after[:top_leg_span], tol,
      "top leg must retain its original #{LEG} span -- it changed to #{after[:top_leg_span]}, meaning the fixed end was stretched"
    assert_in_delta expected_overall, after[:overall], tol,
      "overall dimension must reach the requested size"
    refute_in_delta before[:middle_span], after[:middle_span], tol,
      "the middle/stretch region must actually change -- if it didn't move at all, nothing was scaled"
  end

  # Temporarily makes UI.inputbox return `result` (simulating the user
  # typing something and confirming the dialog) instead of the stub's
  # normal always-nil ("cancelled") behavior, restoring the original
  # after the block -- so this doesn't leak into any other test.
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

  # -- 1/2. Non-shared frame: fixed regions unchanged, middle changes ------

  def test_smart_scale_on_a_non_shared_frame_preserves_fixed_regions
    instance = TestFixtures.frame_component(@model.active_entities, z_size: Z_SIZE, leg: LEG)
    before = frame_diagnostics(instance)
    select(instance)
    overlay = build_overlay

    TestHarness.drive_scale_drag(overlay, axis_id: :z, ratio: 0.5, origin: instance.bounds.min)

    after = frame_diagnostics(instance)
    assert_frame_preserved(before, after, expected_overall: Z_SIZE * 0.5)
  end

  # -- 3/4/5. Copy, Smart Scale only the copy, verify everything -----------

  def test_copy_then_smart_scale_preserves_frame_structure_in_the_copy_only
    original = TestFixtures.frame_component(@model.active_entities, z_size: Z_SIZE, leg: LEG)
    select(original)
    overlay = build_overlay
    TestHarness.drive_move_drag(overlay, vector: Geom::Vector3d.new(200, 0, 0), copy: true)
    copy = @model.selection.to_a.first
    refute_same original, copy
    assert copy.definition.equal?(original.definition), 'a fresh copy must share the original definition'

    original_before = frame_diagnostics(original)
    copy_before = frame_diagnostics(copy)

    select(copy)
    TestHarness.drive_scale_drag(overlay, axis_id: :z, ratio: 0.5, origin: copy.bounds.min)

    original_after = frame_diagnostics(original)
    copy_after = frame_diagnostics(copy)

    # The original's definition and geometry are unchanged.
    assert_equal original_before, original_after, 'the original must be completely unchanged, geometry included'

    # The copy has a unique definition.
    refute copy.definition.equal?(original.definition), 'the copy must have become unique'
    assert_equal 1, copy.definition.instances.length
    assert_equal 1, original.definition.instances.length

    # The copy reaches the requested dimension AND retains true Smart
    # Scale structure -- not just a bounding box that happens to match.
    assert_frame_preserved(copy_before, copy_after, expected_overall: Z_SIZE * 0.5)
  end

  def test_unrelated_unselected_sibling_instance_remains_unchanged_geometrically
    definition = Sketchup::ComponentDefinition.new('SharedFrame')
    TestFixtures.build_frame(definition.entities, 4.0, 4.0, Z_SIZE, LEG)
    original = @model.active_entities.add_instance(definition, Geom::Transformation.new)
    copy = @model.active_entities.add_instance(definition, Geom::Transformation.new)
    sibling = @model.active_entities.add_instance(definition, Geom::Transformation.new)
    assert_equal 3, definition.instances.length

    sibling_before = frame_diagnostics(sibling)
    original_before = frame_diagnostics(original)

    select(copy)
    overlay = build_overlay
    TestHarness.drive_scale_drag(overlay, axis_id: :z, ratio: 0.5, origin: copy.bounds.min)

    assert_equal sibling_before, frame_diagnostics(sibling), 'an unrelated unselected sibling must be geometrically untouched'
    assert_equal original_before, frame_diagnostics(original)
    assert_equal 2, definition.instances.length, 'original and sibling still correctly share the original definition'
  end

  # -- 6. Both the click-dialog path and the drag/Measurements re-edit path -

  def test_click_dialog_path_preserves_frame_structure_on_the_copy
    original = TestFixtures.frame_component(@model.active_entities, z_size: Z_SIZE, leg: LEG)
    select(original)
    overlay = build_overlay
    TestHarness.drive_move_drag(overlay, vector: Geom::Vector3d.new(200, 0, 0), copy: true)
    copy = @model.selection.to_a.first

    copy_before = frame_diagnostics(copy)
    select(copy)
    gizmo = TestHarness.gizmo_of(overlay)
    gizmo.bounds = copy.bounds
    callback_click = gizmo.instance_variable_get(:@callback_click)

    with_inputbox_result(['50in']) do
      callback_click.call([:scale, copy.bounds.min, 1, [false, false, true]])
    end

    assert_nil UI.last_messagebox_text
    copy_after = frame_diagnostics(copy)
    assert_frame_preserved(copy_before, copy_after, expected_overall: 50.0)
  end

  def test_drag_then_measurements_re_edit_path_preserves_frame_structure_on_the_copy
    original = TestFixtures.frame_component(@model.active_entities, z_size: Z_SIZE, leg: LEG)
    select(original)
    overlay = build_overlay
    TestHarness.drive_move_drag(overlay, vector: Geom::Vector3d.new(200, 0, 0), copy: true)
    copy = @model.selection.to_a.first

    copy_before = frame_diagnostics(copy)
    select(copy)
    TestHarness.drive_scale_drag(overlay, axis_id: :z, ratio: 0.8, origin: copy.bounds.min)

    # TestHarness.drive_scale_drag hardcodes its own data[4] (reference
    # length) to a fixed 1 inch for simplicity -- fine for drag-only
    # tests, but onUserText's re-edit reads data[4] straight from
    # @last_transform (falling back to state.reference_length only if
    # data[4] isn't already a positive number), so that stale 1"
    # reference would otherwise leak into this explicit-unit re-edit.
    # Correct it to the fixture's true original dimension, matching what
    # a real single-axis Scale gizmo click/drag actually provides via
    # scale_reference_length.
    stale_data = overlay.instance_variable_get(:@last_transform)[2]
    stale_data[4] = Z_SIZE

    overlay.onUserText('50in', @model.active_view)

    assert_nil UI.last_messagebox_text
    copy_after = frame_diagnostics(copy)
    assert_frame_preserved(copy_before, copy_after, expected_overall: 50.0)
  end

  # -- 7. Repeated "/2" edits keep using correct, fresh Smart Scale state --

  def test_repeated_slash_2_edits_keep_preserving_frame_structure
    original = TestFixtures.frame_component(@model.active_entities, z_size: Z_SIZE, leg: LEG)
    select(original)
    overlay = build_overlay
    TestHarness.drive_move_drag(overlay, vector: Geom::Vector3d.new(200, 0, 0), copy: true)
    copy = @model.selection.to_a.first

    copy_before = frame_diagnostics(copy)
    select(copy)
    TestHarness.drive_scale_drag(overlay, axis_id: :z, ratio: 1.0, origin: copy.bounds.min)

    overlay.onUserText('/2', @model.active_view) # 100 -> 50
    refute_nil overlay.instance_variable_get(:@last_smart_scale_session)
    assert_nil UI.last_messagebox_text
    after_first = frame_diagnostics(copy)
    assert_frame_preserved(copy_before, after_first, expected_overall: 50.0)

    overlay.onUserText('/2', @model.active_view) # 50 -> 25
    assert_nil UI.last_messagebox_text
    after_second = frame_diagnostics(copy)
    assert_frame_preserved(after_first, after_second, expected_overall: 25.0)

    # The original must still be untouched after both re-edits.
    assert_equal Z_SIZE, frame_diagnostics(original)[:overall]
  end

  # -- "xN" Smart Scale multiplication preserves frame structure -----------

  def test_x2_smart_scale_on_a_copy_preserves_frame_structure_and_isolates_the_original
    original = TestFixtures.frame_component(@model.active_entities, z_size: Z_SIZE, leg: LEG)
    select(original)
    overlay = build_overlay
    TestHarness.drive_move_drag(overlay, vector: Geom::Vector3d.new(200, 0, 0), copy: true)
    copy = @model.selection.to_a.first

    original_before = frame_diagnostics(original)
    select(copy)
    TestHarness.drive_scale_drag(overlay, axis_id: :z, ratio: 0.5, origin: copy.bounds.min) # 100 -> 50
    copy_after_half = frame_diagnostics(copy)

    overlay.onUserText('x2', @model.active_view) # 50 -> 100

    assert_nil UI.last_messagebox_text
    assert_equal original_before, frame_diagnostics(original), 'the original must remain unchanged'
    copy_after_double = frame_diagnostics(copy)
    assert_frame_preserved(copy_after_half, copy_after_double, expected_overall: Z_SIZE)
    refute copy.definition.equal?(original.definition), 'the copy must have become unique'
  end

  def test_repeated_slash_2_then_x2_keeps_preserving_frame_structure
    instance = TestFixtures.frame_component(@model.active_entities, z_size: Z_SIZE, leg: LEG)
    select(instance)
    overlay = build_overlay
    before = frame_diagnostics(instance)

    TestHarness.drive_scale_drag(overlay, axis_id: :z, ratio: 1.0, origin: instance.bounds.min)

    overlay.onUserText('/2', @model.active_view) # 100 -> 50
    assert_nil UI.last_messagebox_text
    after_half = frame_diagnostics(instance)
    assert_frame_preserved(before, after_half, expected_overall: Z_SIZE * 0.5)

    overlay.onUserText('x2', @model.active_view) # 50 -> 100
    assert_nil UI.last_messagebox_text
    after_double = frame_diagnostics(instance)
    assert_frame_preserved(after_half, after_double, expected_overall: Z_SIZE)
  end

  def test_invalid_x0_smart_scale_re_edit_aborts_without_changing_geometry
    instance = TestFixtures.frame_component(@model.active_entities, z_size: Z_SIZE, leg: LEG)
    select(instance)
    overlay = build_overlay
    before = frame_diagnostics(instance)
    TestHarness.drive_scale_drag(overlay, axis_id: :z, ratio: 0.5, origin: instance.bounds.min)
    after_half = frame_diagnostics(instance)

    overlay.onUserText('x0', @model.active_view)

    assert_equal 'Invalid scale', UI.last_messagebox_text
    assert_equal after_half, frame_diagnostics(instance), 'x0 must be rejected without any further mutation'
    refute_equal before, frame_diagnostics(instance)
  end

  # -- 8. Normal (non-Smart Scale) behavior is unchanged --------------------

  def test_normal_non_smart_scale_scales_uniformly_and_leaves_sharing_intact
    Zbellbound::SmartGizmoPro::PLUGIN.test_smart_scale_enabled = false
    definition = Sketchup::ComponentDefinition.new('PlainSharedFrame')
    TestFixtures.build_frame(definition.entities, 4.0, 4.0, Z_SIZE, LEG)
    original = @model.active_entities.add_instance(definition, Geom::Transformation.new)
    copy = @model.active_entities.add_instance(definition, Geom::Transformation.new)

    original_before = frame_diagnostics(original)
    select(copy)
    overlay = build_overlay
    TestHarness.drive_scale_drag(overlay, axis_id: :z, ratio: 0.5, origin: copy.bounds.min)

    # Ordinary scale is a per-instance transformation -- the shared
    # DEFINITION's own geometry (what frame_diagnostics inspects) is
    # untouched for both instances; only the instance's overall bounds
    # (its transformation) changes.
    assert_equal original_before, frame_diagnostics(original)
    assert_equal original_before, frame_diagnostics(copy), 'the definition geometry itself is never touched by ordinary scale'
    assert_in_delta Z_SIZE * 0.5, copy.bounds.max.z - copy.bounds.min.z, 1e-6
    assert copy.definition.equal?(original.definition), 'ordinary scale must never trigger a uniqueness conversion'
  end

  # -- 9. Groups still use Smart Scale correctly (geometry-aware) ----------

  def test_group_still_uses_true_smart_scale_geometry
    definition = Sketchup::ComponentDefinition.new('FrameGroupDef')
    TestFixtures.build_frame(definition.entities, 4.0, 4.0, Z_SIZE, LEG)
    group = Sketchup::Group.new(definition)
    @model.active_entities << group
    select(group)
    overlay = build_overlay

    before = frame_diagnostics(group)
    TestHarness.drive_scale_drag(overlay, axis_id: :z, ratio: 0.5, origin: group.bounds.min)
    after = frame_diagnostics(group)

    assert_frame_preserved(before, after, expected_overall: Z_SIZE * 0.5)
    assert_instance_of Sketchup::Group, group, 'must remain a Group, never converted to a component'
  end

  # -- 10. One Undo restores the complete operation --------------------------

  def test_copy_then_smart_scale_is_a_single_undo_operation
    original = TestFixtures.frame_component(@model.active_entities, z_size: Z_SIZE, leg: LEG)
    select(original)
    overlay = build_overlay
    TestHarness.drive_move_drag(overlay, vector: Geom::Vector3d.new(200, 0, 0), copy: true)
    copy = @model.selection.to_a.first

    select(copy)
    starts_before, commits_before, aborts_before = operation_counts
    TestHarness.drive_scale_drag(overlay, axis_id: :z, ratio: 0.5, origin: copy.bounds.min)
    starts_after, commits_after, aborts_after = operation_counts

    assert_equal starts_before + 1, starts_after
    assert_equal commits_before + 1, commits_after
    assert_equal aborts_before, aborts_after
  end

  # -- Single-instance component is not made unique unnecessarily ----------

  def test_single_instance_component_is_not_made_unique_unnecessarily
    instance = TestFixtures.frame_component(@model.active_entities, z_size: Z_SIZE, leg: LEG)
    select(instance)
    overlay = build_overlay
    original_definition = instance.definition

    TestHarness.drive_scale_drag(overlay, axis_id: :z, ratio: 0.5, origin: instance.bounds.min)

    assert instance.definition.equal?(original_definition)
  end

  # -- Multi-selection: each selected copy scales correctly once -----------

  def test_multi_selection_preserves_frame_structure_for_each_selected_copy
    definition = Sketchup::ComponentDefinition.new('MultiSharedFrame')
    TestFixtures.build_frame(definition.entities, 4.0, 4.0, Z_SIZE, LEG)
    selected_a = @model.active_entities.add_instance(definition, Geom::Transformation.new)
    selected_b = @model.active_entities.add_instance(definition, Geom::Transformation.translation(Geom::Vector3d.new(200, 0, 0)))
    sibling = @model.active_entities.add_instance(definition, Geom::Transformation.translation(Geom::Vector3d.new(400, 0, 0)))

    sibling_before = frame_diagnostics(sibling)
    a_before = frame_diagnostics(selected_a)
    b_before = frame_diagnostics(selected_b)

    select(selected_a, selected_b)
    overlay = build_overlay
    TestHarness.drive_scale_drag(overlay, axis_id: :z, ratio: 0.5, origin: selected_a.bounds.min)

    assert_frame_preserved(a_before, frame_diagnostics(selected_a), expected_overall: Z_SIZE * 0.5)
    assert_frame_preserved(b_before, frame_diagnostics(selected_b), expected_overall: Z_SIZE * 0.5)
    assert_equal sibling_before, frame_diagnostics(sibling), 'the unselected sibling must remain untouched'
  end

  # -- Failed scaling rolls back cleanly ------------------------------------

  def test_invalid_scale_after_a_copy_aborts_cleanly_without_partial_mutation
    original = TestFixtures.frame_component(@model.active_entities, z_size: Z_SIZE, leg: LEG)
    select(original)
    overlay = build_overlay
    TestHarness.drive_move_drag(overlay, vector: Geom::Vector3d.new(200, 0, 0), copy: true)
    copy = @model.selection.to_a.first

    original_before = frame_diagnostics(original)
    copy_before = frame_diagnostics(copy)

    select(copy)
    overlay2 = build_overlay
    overlay2.instance_variable_set(:@last_transform, [IDENTITY, IDENTITY,
      [:scale, copy.bounds.min, 1.0, [false, false, true], Z_SIZE, copy.bounds.min.clone, IDENTITY]])

    starts_before, commits_before, aborts_before = operation_counts
    overlay2.onUserText('not-a-length', @model.active_view)
    starts_after, commits_after, aborts_after = operation_counts

    assert_equal 'Invalid scale', UI.last_messagebox_text
    assert_equal original_before, frame_diagnostics(original)
    assert_equal copy_before, frame_diagnostics(copy), 'no partial mutation on an aborted scale'
    assert_equal starts_before + 1, starts_after
    assert_equal commits_before, commits_after
    assert_equal aborts_before + 1, aborts_after
  end

  # -- 11. Ruby Console stays empty in production ---------------------------

  def test_copy_then_smart_scale_produces_no_console_output
    original = TestFixtures.frame_component(@model.active_entities, z_size: Z_SIZE, leg: LEG)
    select(original)
    overlay = build_overlay
    TestHarness.drive_move_drag(overlay, vector: Geom::Vector3d.new(200, 0, 0), copy: true)
    copy = @model.selection.to_a.first
    select(copy)

    original_stderr = $stderr
    $stderr = StringIO.new
    begin
      TestHarness.drive_scale_drag(overlay, axis_id: :z, ratio: 0.5, origin: copy.bounds.min)
      overlay.onUserText('/2', @model.active_view)
      captured = $stderr.string
    ensure
      $stderr = original_stderr
    end

    assert_empty captured
  end
end
