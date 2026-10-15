require 'minitest/autorun'
require_relative 'support/fixtures'

# Regression coverage for the Extension Warehouse undo-stack rejection:
# making two copies in Copy mode showed two undo entries ("Transform" and
# "Copy Array"). The whole user action must be ONE undo step -- and it must
# be, WITHOUT relying on SketchUp merging a transparent operation (the stub
# Model models that merge as NOT happening, which is what the reviewer saw).
#
# `@model.undo_stack` is the emulated SketchUp undo stack; Sketchup.undo
# removes exactly the newest entry's entities.
class CopyModeSingleUndoTest < Minitest::Test
  def setup
    @model = Sketchup::Model.new
    Zbellbound::SmartGizmoPro::PLUGIN.test_smart_scale_enabled = false
    Zbellbound::SmartGizmoPro::PLUGIN.test_gizmo_orientation = Zbellbound::SmartGizmoPro::GLOBAL_ORIENTATION
    UI.last_messagebox_text = nil
  end

  def select(*entities)
    @model.selection.instance_variable_set(:@list, entities)
  end

  def overlay
    TestHarness.build_overlay(model: @model, selection: @model.selection)
  end

  def log(kind)
    @model.operation_log.select { |e| e[0] == kind }
  end

  def ctrl_drag_copy(group, vector = Geom::Vector3d.new(3000.mm, 0, 0))
    select(group)
    ov = overlay
    TestHarness.drive_move_drag(ov, vector: vector, copy: true)
    ov
  end

  def session_of(ov)
    ov.instance_variable_get(:@ctrl_array_session)
  end

  def live_copies(group)
    @model.selection.to_a.reject { |e| e.equal?(group) }
  end

  # -- The reviewer's scenario: two copies, then ONE Undo ------------------

  def test_ctrl_drag_then_two_copies_is_a_single_undo_entry
    group = TestFixtures.group_box
    ov = ctrl_drag_copy(group)
    assert_equal 1, @model.undo_stack.length, 'the plain Ctrl-drag copy is one entry'

    ov.onUserText('/2', @model.active_view)

    assert_equal 1, @model.undo_stack.length, 'drag + two copies must be ONE undo entry, not two'
    assert_equal 2, live_copies(group).length

    created = live_copies(group)
    Sketchup.undo

    assert created.none?(&:valid?), 'one Undo must remove every copy'
    assert group.valid?
    assert_in_delta 0, group.transformation.origin.x, 1e-6, 'original restored to its exact prior position'
    assert_empty @model.undo_stack
  end

  def test_external_x_array_is_a_single_undo_entry
    group = TestFixtures.group_box
    ov = ctrl_drag_copy(group, Geom::Vector3d.new(1000.mm, 0, 0))

    ov.onUserText('x3', @model.active_view)

    assert_equal 1, @model.undo_stack.length
    assert_equal 3, live_copies(group).length
    created = live_copies(group)
    Sketchup.undo
    assert created.none?(&:valid?)
    assert_empty @model.undo_stack
  end

  def test_repeated_edits_keep_a_single_undo_entry_and_never_stack_entries
    group = TestFixtures.group_box
    ov = ctrl_drag_copy(group)

    ov.onUserText('/3', @model.active_view)
    ov.onUserText('/4', @model.active_view)
    ov.onUserText('x2', @model.active_view)
    ov.onUserText('/1', @model.active_view)

    assert_equal 1, @model.undo_stack.length
    assert_equal 1, live_copies(group).length, '/1 leaves just the endpoint'
    Sketchup.undo
    assert_empty @model.undo_stack
    assert_equal [group], @model.selection.to_a.select(&:valid?) - live_copies(group)
  end

  def test_result_is_identical_when_transparent_merge_would_have_worked
    @model.transparent_merge = true
    group = TestFixtures.group_box
    ov = ctrl_drag_copy(group)

    ov.onUserText('/3', @model.active_view)

    assert_equal 1, @model.undo_stack.length
    assert_equal 3, live_copies(group).length
  end

  # -- Plain Ctrl-drag copy and the dialog Copy path are unchanged ----------

  def test_plain_ctrl_drag_copy_stays_one_transform_entry
    group = TestFixtures.group_box
    ctrl_drag_copy(group)

    assert_equal ['Transform'], @model.undo_stack.map { |f| f[:name] }
    assert_equal [:start, 'Transform', true, false, false], log(:start).first
  end

  def test_dialog_copy_two_copies_is_one_copy_array_entry
    select(TestFixtures.group_box)
    ov = overlay

    ov.perform_copy_array(Geom::Transformation.translation(Geom::Vector3d.new(500.mm, 0, 0)), 2)

    assert_equal ['Copy Array'], @model.undo_stack.map { |f| f[:name] }
    assert_empty log(:abort)
    assert_equal 3, @model.selection.to_a.length
  end

  # -- Failure / cancel handling -------------------------------------------

  def test_rejected_array_does_not_touch_the_undo_stack
    group = TestFixtures.group_box
    edge = Sketchup::Edge.new(Geom::Point3d.new(0, 0, 0), Geom::Point3d.new(10, 0, 0))
    ov = ctrl_drag_copy(group)
    # An unsupported originals set must be refused BEFORE any undo.
    session_of(ov)[:originals] << edge
    before = @model.undo_stack.dup

    ov.onUserText('/3', @model.active_view)

    assert_equal before, @model.undo_stack, 'a refused array must not undo or add anything'
    refute_nil UI.last_messagebox_text
  end

  def test_invalid_count_does_not_touch_the_undo_stack
    group = TestFixtures.group_box
    ov = ctrl_drag_copy(group)
    before = @model.undo_stack.dup

    ov.onUserText('/0', @model.active_view)

    assert_equal before, @model.undo_stack
    assert_empty log(:abort)
  end

  def test_failed_rebuild_aborts_and_restores_the_single_copy
    group = TestFixtures.group_box
    ov = ctrl_drag_copy(group)
    real = Zbellbound::SmartGizmoPro::GizmoOverlay.instance_method(:duplicate_supported_entity)
    calls = 0
    ov.define_singleton_method(:duplicate_supported_entity) do |entity|
      calls += 1
      raise 'simulated failure' if calls == 2

      real.bind(ov).call(entity)
    end

    ov.onUserText('/3', @model.active_view)

    assert_equal 1, log(:abort).length, 'the failed rebuild is aborted, never committed partially'
    assert_equal 1, @model.undo_stack.length, 'still exactly one undo entry'
    assert_equal 1, session_of(ov)[:count]
    assert_equal 1, session_of(ov)[:endpoint].length
    assert session_of(ov)[:endpoint].all?(&:valid?), 'the original drag copy is restored, not lost'
    assert_in_delta 3000.mm, session_of(ov)[:endpoint].first.transformation.origin.x, 1e-6
    refute_nil UI.last_messagebox_text
  end

  def test_unexpected_undo_target_is_put_back_and_nothing_changes
    group = TestFixtures.group_box
    ov = ctrl_drag_copy(group)
    # Make Sketchup.undo hit some other entry: the tracked copies survive.
    original_undo = Sketchup.method(:undo)
    redo_actions = []
    Sketchup.define_singleton_method(:undo) { nil }
    original_send = Sketchup.method(:send_action)
    Sketchup.define_singleton_method(:send_action) { |a| redo_actions << a }
    begin
      ov.onUserText('/3', @model.active_view)
    ensure
      Sketchup.define_singleton_method(:undo, original_undo)
      Sketchup.define_singleton_method(:send_action, original_send)
    end

    assert_equal ['editRedo:'], redo_actions
    assert_empty log(:abort)
    assert_equal 1, log(:start).length, 'no rebuild operation may start'
    assert_equal false, session_of(ov)[:undo_top_ours]
  end

  def test_selection_failure_after_commit_does_not_abort_dialog_copy
    select(TestFixtures.group_box)
    ov = overlay
    @model.selection.define_singleton_method(:add) { |*_a| raise 'selection add failed' }

    ov.perform_copy_array(Geom::Transformation.translation(Geom::Vector3d.new(100.mm, 0, 0)), 2)

    assert_equal 1, log(:commit).length
    assert_empty log(:abort), 'abort after commit would target the wrong undo entry'
  end

  def test_failure_building_the_ctrl_drag_copy_aborts_the_open_transform
    group = TestFixtures.group_box
    select(group)
    ov = overlay
    @model.active_entities.define_singleton_method(:add_group) { |*_a| raise 'add_group failed' }

    TestHarness.drive_move_drag(ov, vector: Geom::Vector3d.new(300.mm, 0, 0), copy: true)

    assert_empty log(:commit)
    assert_equal 1, log(:abort).length, 'the open Transform operation must be aborted, not left open'
    assert_nil session_of(ov)
    assert_equal [group], @model.selection.to_a
    refute_nil UI.last_messagebox_text
  end

  # -- Undo guard: never undo a user's unrelated operation ------------------

  # An unrelated, earlier operation of the user's own, already on the stack.
  def make_unrelated_entry
    @model.start_operation('Unrelated user edit', true)
    unrelated = TestFixtures.group_box
    @model.commit_operation
    unrelated
  end

  def test_user_undo_of_the_drag_copy_then_array_text_never_undoes_the_unrelated_entry
    unrelated = make_unrelated_entry
    group = TestFixtures.group_box
    ov = ctrl_drag_copy(group)
    entries_before = @model.undo_stack.length # [unrelated, Transform]

    Sketchup.undo # the USER's own Ctrl+Z: removes the drag copy
    assert_equal entries_before - 1, @model.undo_stack.length
    assert unrelated.valid?

    ov.onUserText('/3', @model.active_view)

    assert unrelated.valid?, 'the user\'s unrelated operation must survive'
    assert_equal ['Unrelated user edit'], @model.undo_stack.map { |f| f[:name] }
    assert_equal 1, log(:start).length - 1, 'only the unrelated + drag operations ever started'
    assert_nil session_of(ov), 'the array-input window must close'
  end

  def test_foreign_transaction_disables_the_replace_and_uses_the_fallback
    unrelated = make_unrelated_entry
    group = TestFixtures.group_box
    ov = ctrl_drag_copy(group)

    # e.g. another extension / user action committed after the drag copy.
    @model.start_operation('Other extension', true)
    other = TestFixtures.group_box
    @model.commit_operation
    ov.model_transaction_observed

    ov.onUserText('/2', @model.active_view)

    assert unrelated.valid?
    assert other.valid?, 'the foreign operation on top of the stack must not be undone'
    assert_equal 'Other extension', @model.undo_stack[-2][:name]
    transparent = log(:start).select { |e| e[4] == true }
    assert_equal 1, transparent.length, 'fallback = original transparent Copy Array request'
  end

  def test_own_operations_keep_the_replace_enabled_across_observer_events
    group = TestFixtures.group_box
    ov = ctrl_drag_copy(group)
    ov.model_transaction_observed # event for the drag's own commit arrives late
    refute session_of(ov)[:undo_top_ours]

    ov.onUserText('/2', @model.active_view) # fallback path, still safe

    assert_equal 2, live_copies(group).length
    assert_equal 0, log(:abort).length
  end

  # -- Fallback: a typed distance re-edit now sits on top -------------------

  def test_array_after_a_distance_reedit_uses_the_legacy_transparent_path
    group = TestFixtures.group_box
    ov = ctrl_drag_copy(group)
    ov.onUserText('500mm', @model.active_view) # 'Re-edit' operation now on top
    refute session_of(ov)[:undo_top_ours] if session_of(ov)
    undo_depth = @model.undo_stack.length

    ov.onUserText('/2', @model.active_view)

    transparent = @model.operation_log.select { |e| e[0] == :start && e[4] == true }
    if session_of(ov)
      assert_equal 1, transparent.length, 'must not undo the Re-edit entry; falls back to the old request'
      assert_operator @model.undo_stack.length, :>=, undo_depth
    end
  end
end
