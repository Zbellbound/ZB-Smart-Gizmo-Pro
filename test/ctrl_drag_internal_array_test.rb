require 'minitest/autorun'
require 'stringio'
require_relative 'support/fixtures'

# Coverage for the Ctrl-drag internal copy array: Ctrl-drag a Gizmo move
# arrow to create the ordinary single endpoint copy (pre-existing
# behavior, untouched by this feature), then immediately type "/N" (or
# "N/") in Measurements to divide the complete dragged distance into N
# equally spaced copies, replacing the original in place.
#
# The endpoint copy the Ctrl-drag itself created is always copy N of N and
# is never recreated or moved by a "/N" edit -- only the intermediates
# between the original and it are built or rebuilt. Re-entering a
# different "/N" replaces the array rather than adding to it, and (per
# GizmoOverlay#apply_ctrl_drag_array) does so as a transparent operation
# that merges into the undo entry already on top of the stack, so the
# whole session stays a single Undo.
#
# Tests drive the real callbacks (TestHarness.drive_move_drag simulates
# the gizmo's own on_transform_start/on_transform/on_transform_end
# sequence for a Ctrl-held move, the same way the existing smart-scale and
# copy-array tests drive on_transform/on_transform_end) and then call
# GizmoOverlay#onUserText directly with the typed Measurements text, since
# a real Measurements box can't be driven from a test.
class CtrlDragInternalArrayTest < Minitest::Test
  def setup
    @model = Sketchup::Model.new
    Zbellbound::SmartGizmoPro::PLUGIN.test_smart_scale_enabled = false
    Zbellbound::SmartGizmoPro::PLUGIN.test_gizmo_orientation = Zbellbound::SmartGizmoPro::GLOBAL_ORIENTATION
    UI.last_messagebox_text = nil
    UI.last_inputbox_args = nil
  end

  def select(*entities)
    @model.selection.instance_variable_set(:@list, entities)
  end

  def build_overlay
    TestHarness.build_overlay(model: @model, selection: @model.selection)
  end

  def assert_transformation_equal(expected, actual, msg = nil)
    expected.to_a.each_with_index do |value, i|
      assert_in_delta value, actual.to_a[i], 1e-6, msg || "transformation component #{i} mismatch"
    end
  end

  def operation_counts
    starts = @model.operation_log.count { |entry| entry[0] == :start }
    commits = @model.operation_log.count { |entry| entry[0] == :commit }
    aborts = @model.operation_log.count { |entry| entry[0] == :abort }
    [starts, commits, aborts]
  end

  # Selects `entities`, Ctrl-drags them by `vector`, and returns the
  # overlay with the ordinary single endpoint copy already committed --
  # the state the Ctrl-drag array feature builds on.
  def ctrl_drag_copy(entities, vector)
    select(*entities)
    overlay = build_overlay
    TestHarness.drive_move_drag(overlay, vector: vector, copy: true)
    overlay
  end

  def session_of(overlay)
    overlay.instance_variable_get(:@ctrl_array_session)
  end

  # -- Ordinary single Ctrl-drag copy: unaffected by this feature ---------

  def test_ctrl_drag_single_copy_unchanged_without_division_input
    group = TestFixtures.group_box
    overlay = ctrl_drag_copy([group], Geom::Vector3d.new(3000.mm, 0, 0))

    assert group.valid?
    assert_in_delta 0, group.transformation.origin.x, 1e-6, 'original must remain exactly in place'

    selected = @model.selection.to_a
    assert_equal 1, selected.length, 'only the endpoint copy is selected, matching ordinary Ctrl-drag copy'
    assert_in_delta 3000.mm, selected.first.transformation.origin.x, 1e-6
    refute_equal group, selected.first

    starts, commits, aborts = operation_counts
    assert_equal 1, starts
    assert_equal 1, commits
    assert_equal 0, aborts
    refute_nil session_of(overlay), 'the array-input window must be open, ready for a "/N" edit'
  end

  # -- Parsing: /N, N/, whitespace ------------------------------------------

  def test_parse_ctrl_drag_array_count_accepts_slash_prefix_and_suffix
    overlay = build_overlay

    assert_equal 3, overlay.parse_ctrl_drag_array_count('/3')
    assert_equal 3, overlay.parse_ctrl_drag_array_count('3/')
    assert_equal 3, overlay.parse_ctrl_drag_array_count(' /3 ')
    assert_equal 3, overlay.parse_ctrl_drag_array_count(' 3/ ')
    assert_equal 3, overlay.parse_ctrl_drag_array_count('/ 3')
    assert_equal 3, overlay.parse_ctrl_drag_array_count('3 /')
    assert_equal 1, overlay.parse_ctrl_drag_array_count('/1')
    assert_equal 1000, overlay.parse_ctrl_drag_array_count('/1000')
  end

  def test_parse_ctrl_drag_array_count_returns_nil_for_plain_distances
    overlay = build_overlay

    assert_nil overlay.parse_ctrl_drag_array_count('300mm'), 'a plain distance has no "/" and must fall through'
    assert_nil overlay.parse_ctrl_drag_array_count('3')
    assert_nil overlay.parse_ctrl_drag_array_count('')
    assert_nil overlay.parse_ctrl_drag_array_count(nil)
  end

  def test_parse_ctrl_drag_array_count_rejects_malformed_division_input
    overlay = build_overlay

    assert_equal :invalid, overlay.parse_ctrl_drag_array_count('/0')
    assert_equal :invalid, overlay.parse_ctrl_drag_array_count('/-2')
    assert_equal :invalid, overlay.parse_ctrl_drag_array_count('/2.5')
    assert_equal :invalid, overlay.parse_ctrl_drag_array_count('/')
    assert_equal :too_many, overlay.parse_ctrl_drag_array_count('/1001')
  end

  # -- /N creates the correct spacing, reusing the existing endpoint -------

  def test_slash_3_creates_two_intermediates_plus_the_existing_endpoint
    group = TestFixtures.group_box
    overlay = ctrl_drag_copy([group], Geom::Vector3d.new(3000.mm, 0, 0))
    endpoint = @model.selection.to_a.first

    overlay.onUserText('/3', @model.active_view)

    selected = @model.selection.to_a
    assert_equal 4, selected.length, 'original + 2 intermediates + the endpoint'
    assert_includes selected, group
    assert_includes selected, endpoint, 'the endpoint copy must be reused, never recreated'

    xs = selected.map { |e| e.transformation.origin.x }.sort
    assert_in_delta 0, xs[0], 1e-6
    assert_in_delta 1000.mm, xs[1], 1e-6
    assert_in_delta 2000.mm, xs[2], 1e-6
    assert_in_delta 3000.mm, xs[3], 1e-6
  end

  def test_suffix_slash_syntax_produces_the_same_array_as_prefix_syntax
    group = TestFixtures.group_box
    overlay = ctrl_drag_copy([group], Geom::Vector3d.new(3000.mm, 0, 0))

    overlay.onUserText('3/', @model.active_view)

    xs = @model.selection.to_a.map { |e| e.transformation.origin.x }.sort
    assert_equal 4, xs.length
    assert_in_delta 0, xs[0], 1e-6
    assert_in_delta 1000.mm, xs[1], 1e-6
    assert_in_delta 2000.mm, xs[2], 1e-6
    assert_in_delta 3000.mm, xs[3], 1e-6
  end

  def test_slash_1_on_a_fresh_copy_is_a_no_op
    group = TestFixtures.group_box
    overlay = ctrl_drag_copy([group], Geom::Vector3d.new(1000.mm, 0, 0))
    starts_before, commits_before, = operation_counts

    overlay.onUserText('/1', @model.active_view)

    starts_after, commits_after, aborts_after = operation_counts
    assert_equal starts_before, starts_after, '/1 when already at count 1 has nothing to do'
    assert_equal commits_before, commits_after
    assert_equal 0, aborts_after
    assert_equal 1, @model.selection.to_a.length
  end

  def test_slash_1_after_slash_3_removes_the_intermediates
    group = TestFixtures.group_box
    overlay = ctrl_drag_copy([group], Geom::Vector3d.new(3000.mm, 0, 0))
    overlay.onUserText('/3', @model.active_view)
    intermediates = session_of(overlay)[:intermediates].dup
    assert_equal 2, intermediates.length

    overlay.onUserText('/1', @model.active_view)

    assert intermediates.none?(&:valid?), 'the /3 intermediates must be erased'
    selected = @model.selection.to_a
    assert_equal 2, selected.length, 'original + endpoint only'
    assert_equal 0, session_of(overlay)[:intermediates].length
  end

  def test_slash_1000_creates_the_maximum_allowed_copies
    instance = TestFixtures.ordinary_component
    overlay = ctrl_drag_copy([instance], Geom::Vector3d.new(1000.mm, 0, 0))

    overlay.onUserText('/1000', @model.active_view)

    selected = @model.selection.to_a
    assert_equal 1001, selected.length, 'original + 999 intermediates + endpoint'
    xs = selected.map { |e| e.transformation.origin.x }.sort
    assert_in_delta 0, xs[0], 1e-6
    assert_in_delta 1.mm, xs[1], 1e-6
    assert_in_delta 1000.mm, xs[-1], 1e-6
  end

  # -- Invalid input: reject cleanly, touch nothing ------------------------

  def test_invalid_division_inputs_are_rejected_without_touching_the_model
    ['/0', '/-2', '/2.5', '/', '/1001'].each do |text|
      group = TestFixtures.group_box
      overlay = ctrl_drag_copy([group], Geom::Vector3d.new(500.mm, 0, 0))
      UI.last_messagebox_text = nil
      before_count = @model.selection.to_a.length
      starts_before, commits_before, aborts_before = operation_counts

      overlay.onUserText(text, @model.active_view)

      assert_equal before_count, @model.selection.to_a.length, "#{text} must leave the single endpoint copy intact"
      starts_after, commits_after, aborts_after = operation_counts
      assert_equal starts_before, starts_after, "#{text} must not start an operation"
      assert_equal commits_before, commits_after, "#{text} must not commit anything"
      assert_equal aborts_before, aborts_after
      refute_nil UI.last_messagebox_text, "#{text} must show a concise message"
    end
  end

  # -- Directions -----------------------------------------------------------

  def test_array_division_handles_positive_and_negative_directions_on_every_axis
    [
      Geom::Vector3d.new(600.mm, 0, 0),
      Geom::Vector3d.new(-600.mm, 0, 0),
      Geom::Vector3d.new(0, 450.mm, 0),
      Geom::Vector3d.new(0, -450.mm, 0),
      Geom::Vector3d.new(0, 0, 900.mm),
      Geom::Vector3d.new(0, 0, -900.mm)
    ].each do |vector|
      instance = TestFixtures.ordinary_component
      overlay = ctrl_drag_copy([instance], vector)

      overlay.onUserText('/3', @model.active_view)

      copies = @model.selection.to_a.reject { |e| e.equal?(instance) }
      assert_equal 3, copies.length, "for vector #{vector.to_a.inspect}"

      expected = [1, 2, 3].map { |i| ORIGIN.offset(vector, vector.length * i / 3.0) }
      actual = copies.map { |c| c.transformation.origin }.sort_by { |p| p.distance(ORIGIN) }
      expected.sort_by! { |p| p.distance(ORIGIN) }

      actual.each_with_index do |point, i|
        assert_in_delta expected[i].x, point.x, 1e-6
        assert_in_delta expected[i].y, point.y, 1e-6
        assert_in_delta expected[i].z, point.z, 1e-6
      end
    end
  end

  # -- Rotation / scale / mirroring preservation ---------------------------

  def test_array_division_preserves_rotation
    instance = TestFixtures.ordinary_component
    rotation = Geom::Transformation.rotation(ORIGIN, Z_AXIS, 30.degrees)
    instance.transformation = rotation
    overlay = ctrl_drag_copy([instance], Geom::Vector3d.new(600.mm, 0, 0))

    overlay.onUserText('/3', @model.active_view)

    assert_transformation_equal(rotation, instance.transformation, 'original rotation must be untouched')

    step = Geom::Transformation.translation(Geom::Vector3d.new(200.mm, 0, 0))
    copies = @model.selection.to_a.reject { |e| e.equal?(instance) }.sort_by { |c| c.transformation.origin.x }
    assert_equal 3, copies.length
    cumulative = IDENTITY
    copies.each do |copy|
      cumulative = step * cumulative
      assert_transformation_equal(cumulative * rotation, copy.transformation)
    end
  end

  def test_array_division_preserves_non_uniform_scale
    instance = TestFixtures.ordinary_component
    scale = Geom::Transformation.scaling(ORIGIN, 2.0, 1.0, 0.5)
    instance.transformation = scale
    overlay = ctrl_drag_copy([instance], Geom::Vector3d.new(0, 300.mm, 0))

    overlay.onUserText('/2', @model.active_view)

    step = Geom::Transformation.translation(Geom::Vector3d.new(0, 150.mm, 0))
    copies = @model.selection.to_a.reject { |e| e.equal?(instance) }.sort_by { |c| c.transformation.origin.y }
    assert_equal 2, copies.length
    cumulative = IDENTITY
    copies.each do |copy|
      cumulative = step * cumulative
      assert_transformation_equal(cumulative * scale, copy.transformation)
    end
  end

  def test_array_division_preserves_mirroring
    instance = TestFixtures.ordinary_component
    mirror = Geom::Transformation.scaling(ORIGIN, -1.0, 1.0, 1.0)
    instance.transformation = mirror
    overlay = ctrl_drag_copy([instance], Geom::Vector3d.new(100.mm, 0, 0))

    overlay.onUserText('/2', @model.active_view)

    step = Geom::Transformation.translation(Geom::Vector3d.new(50.mm, 0, 0))
    copies = @model.selection.to_a.reject { |e| e.equal?(instance) }.sort_by { |c| c.transformation.origin.x }
    assert_equal 2, copies.length
    cumulative = IDENTITY
    copies.each do |copy|
      cumulative = step * cumulative
      assert_transformation_equal(cumulative * mirror, copy.transformation)
    end
  end

  # -- Multi-selection: relative positions and mixed types -----------------

  def test_array_division_preserves_relative_positions_for_multi_selection
    instance_a = TestFixtures.ordinary_component
    instance_b = TestFixtures.ordinary_component
    instance_b.transformation = Geom::Transformation.translation(Geom::Vector3d.new(80.mm, 0, 0))
    overlay = ctrl_drag_copy([instance_a, instance_b], Geom::Vector3d.new(400.mm, 0, 0))

    overlay.onUserText('/4', @model.active_view)

    a_copies = @model.selection.to_a.select { |e| e.definition.equal?(instance_a.definition) } - [instance_a]
    b_copies = @model.selection.to_a.select { |e| e.definition.equal?(instance_b.definition) } - [instance_b]
    assert_equal 4, a_copies.length
    assert_equal 4, b_copies.length

    ordered_a = a_copies.sort_by { |c| c.transformation.origin.x }
    ordered_b = b_copies.sort_by { |c| c.transformation.origin.x }
    ordered_a.zip(ordered_b).each do |a_copy, b_copy|
      assert_in_delta 80.mm, b_copy.transformation.origin.x - a_copy.transformation.origin.x, 1e-6
    end
  end

  def test_array_division_mixed_group_and_component_instance_selection
    group = TestFixtures.group_box
    instance = TestFixtures.ordinary_component
    overlay = ctrl_drag_copy([group, instance], Geom::Vector3d.new(300.mm, 0, 0))

    overlay.onUserText('/2', @model.active_view)

    selected = @model.selection.to_a
    assert_equal 6, selected.length, '2 originals + (1 intermediate + 1 endpoint) each'
    group_copies = selected.select { |e| e.is_a?(Sketchup::Group) && !e.equal?(group) }
    instance_copies = selected.select do |e|
      e.is_a?(Sketchup::ComponentInstance) && !e.is_a?(Sketchup::Group) && !e.equal?(instance)
    end
    assert_equal 2, group_copies.length, 'the Group must be duplicated via Group#copy'
    assert_equal 2, instance_copies.length, 'the plain ComponentInstance must be duplicated via add_instance'
  end

  # -- Rejection: unsupported / mixed selection ----------------------------

  def test_array_division_rejects_unsupported_geometry_leaving_the_single_copy_intact
    group = TestFixtures.group_box
    edge = Sketchup::Edge.new(Geom::Point3d.new(0, 0, 0), Geom::Point3d.new(10, 0, 0))
    overlay = ctrl_drag_copy([group, edge], Geom::Vector3d.new(500.mm, 0, 0))
    before_count = @model.selection.to_a.length
    starts_before, commits_before, aborts_before = operation_counts

    overlay.onUserText('/3', @model.active_view)

    assert_equal before_count, @model.selection.to_a.length, 'the single Ctrl-drag copy must remain intact'
    starts_after, commits_after, aborts_after = operation_counts
    assert_equal starts_before, starts_after, 'a rejected array must never start an operation'
    assert_equal commits_before, commits_after
    assert_equal aborts_before, aborts_after
    assert_match(/groups and components/i, UI.last_messagebox_text.to_s)
  end

  def test_array_division_rejects_glued_component
    instance = TestFixtures.ordinary_component
    instance.glued_to = Object.new
    overlay = ctrl_drag_copy([instance], Geom::Vector3d.new(500.mm, 0, 0))

    overlay.onUserText('/3', @model.active_view)

    assert_equal 1, @model.selection.to_a.length, 'only the single endpoint copy'
    assert_match(/glued/i, UI.last_messagebox_text.to_s)
  end

  # -- Re-edit: /3 then /4 replaces the array as one merged operation ------

  def test_slash_3_then_slash_4_replaces_the_array_and_never_moves_the_endpoint
    group = TestFixtures.group_box
    overlay = ctrl_drag_copy([group], Geom::Vector3d.new(3000.mm, 0, 0))
    endpoint = @model.selection.to_a.first

    overlay.onUserText('/3', @model.active_view)
    intermediates_after_3 = session_of(overlay)[:intermediates].dup
    assert_equal 2, intermediates_after_3.length

    overlay.onUserText('/4', @model.active_view)

    assert intermediates_after_3.none?(&:valid?), 'the /3 intermediates must be replaced, not kept alongside /4'
    session = session_of(overlay)
    assert_equal 3, session[:intermediates].length, '/4 means 4 total copies -- 3 new intermediates + the endpoint'
    assert_equal endpoint, session[:endpoint].first, 'the same endpoint object must still be tracked'
    assert endpoint.valid?
    assert_in_delta 3000.mm, endpoint.transformation.origin.x, 1e-6, 'the endpoint must never move across re-edits'

    xs = session[:intermediates].map { |e| e.transformation.origin.x }.sort
    assert_in_delta 750.mm, xs[0], 1e-6
    assert_in_delta 1500.mm, xs[1], 1e-6
    assert_in_delta 2250.mm, xs[2], 1e-6

    starts, commits, aborts = operation_counts
    assert_equal 3, starts, 'the initial drag-and-copy, then one start per "/N" edit'
    assert_equal 3, commits
    assert_equal 0, aborts

    transparent_starts = @model.operation_log.count { |e| e[0] == :start && e[4] == true }
    assert_equal 2, transparent_starts,
      'each "/N" re-edit must request a transparent (undo-merging) operation, matching the documented ' \
      'Model#start_operation(op_name, disable_ui, next_transparent, transparent) signature'
  end

  # -- Mid-array failure: build-then-swap, never leaves a gap --------------

  def test_failure_during_an_intermediate_copy_leaves_the_existing_array_intact
    group = TestFixtures.group_box
    overlay = ctrl_drag_copy([group], Geom::Vector3d.new(3000.mm, 0, 0))
    overlay.onUserText('/3', @model.active_view)
    original_intermediates = session_of(overlay)[:intermediates].dup
    assert_equal 2, original_intermediates.length

    real_method = Zbellbound::SmartGizmoPro::GizmoOverlay.instance_method(:duplicate_supported_entity)
    call_count = 0
    overlay.define_singleton_method(:duplicate_supported_entity) do |entity|
      call_count += 1
      raise 'simulated duplication failure' if call_count == 2

      real_method.bind(overlay).call(entity)
    end

    original_stderr = $stderr
    $stderr = StringIO.new
    begin
      overlay.onUserText('/4', @model.active_view)
      captured = $stderr.string
    ensure
      $stderr = original_stderr
    end

    starts, commits, aborts = operation_counts
    assert_equal 1, aborts, 'a mid-array failure must abort, never commit a partial replacement'
    refute_nil UI.last_messagebox_text
    assert_empty captured, 'no Ruby Console output on a mid-array failure'

    session = session_of(overlay)
    assert_equal 3, session[:count], 'count must remain at the pre-failure value'
    assert_equal original_intermediates, session[:intermediates], 'the pre-failure intermediates must still be tracked'
    assert original_intermediates.all?(&:valid?),
      'old intermediates must not be erased until the replacement set is fully built'
  end

  # -- Metadata / attribute preservation ------------------------------------

  def test_array_division_preserves_component_instance_metadata_and_attributes
    instance = TestFixtures.ordinary_component
    instance.name = 'Leg-01'
    instance.material = 'Oak'
    instance.layer = 'Furniture'
    instance.hidden = true
    instance.casts_shadows = false
    instance.receives_shadows = false
    instance.set_test_attribute_dictionary('zb_test', { 'sku' => 'ABC123' })
    overlay = ctrl_drag_copy([instance], Geom::Vector3d.new(300.mm, 0, 0))

    overlay.onUserText('/3', @model.active_view)

    copies = @model.selection.to_a.reject { |e| e.equal?(instance) }
    assert_equal 3, copies.length
    copies.each do |copy|
      assert_equal 'Leg-01', copy.name
      assert_equal 'Oak', copy.material
      assert_equal 'Furniture', copy.layer
      assert_equal true, copy.hidden?
      assert_equal false, copy.casts_shadows?
      assert_equal false, copy.receives_shadows?
      assert_equal 'ABC123', copy.attribute_dictionary('zb_test')['sku']
    end
  end

  def test_array_division_preserves_group_metadata_and_attributes
    group = TestFixtures.group_box
    group.name = 'Frame-Left'
    group.material = 'Steel'
    group.layer = 'Structure'
    group.hidden = true
    group.casts_shadows = false
    group.receives_shadows = false
    group.set_test_attribute_dictionary('zb_test', { 'part' => 'frame' })
    overlay = ctrl_drag_copy([group], Geom::Vector3d.new(0, 300.mm, 0))

    overlay.onUserText('/3', @model.active_view)

    copies = @model.selection.to_a.reject { |e| e.equal?(group) }
    assert_equal 3, copies.length
    copies.each do |copy|
      assert_equal 'Frame-Left', copy.name
      assert_equal 'Steel', copy.material
      assert_equal 'Structure', copy.layer
      assert_equal true, copy.hidden?
      assert_equal false, copy.casts_shadows?
      assert_equal false, copy.receives_shadows?
      assert_equal 'frame', copy.attribute_dictionary('zb_test')['part']
    end
  end

  # -- Array-input window lifecycle -----------------------------------------

  def test_clear_edit_state_ends_the_array_input_window_on_a_real_selection_change
    group = TestFixtures.group_box
    overlay = ctrl_drag_copy([group], Geom::Vector3d.new(300.mm, 0, 0))
    refute_nil session_of(overlay)

    select(TestFixtures.ordinary_component) # a genuinely different selection, as a real click elsewhere would produce
    overlay.clear_edit_state

    assert_nil session_of(overlay), 'clicking elsewhere / a new selection must end the array-input window'
  end

  # -- Real-event ordering: a selection-changed notification is not
  # guaranteed to reach the overlay synchronously, inside the same Ruby
  # call that changed the selection. The Ctrl-drag copy's own
  # @selection.clear/@selection.add (in on_transform_end) must not have
  # its OWN eventual notification mistaken for a genuine later selection
  # change and close the array-input window before the user ever gets to
  # type "/N". clear_edit_state guards against this by comparing the
  # current selection against the snapshot recorded at the moment the
  # session was (re)built -- see build_ctrl_drag_array_session and
  # ctrl_drag_selection_matches?.
  def test_a_delayed_notification_echoing_the_copys_own_selection_change_does_not_close_the_window
    group = TestFixtures.group_box
    overlay = ctrl_drag_copy([group], Geom::Vector3d.new(300.mm, 0, 0))
    refute_nil session_of(overlay)

    # Simulates that delayed notification: selection_changed fires with
    # the SAME selection the copy itself just produced, only after
    # on_transform_end (and the session build inside it) has already
    # returned -- instead of synchronously, mid-call.
    overlay.selection_changed(@model.selection)

    refute_nil session_of(overlay),
      'a notification that only echoes the copy\'s own selection change must not close the window'
  end

  def test_a_delayed_notification_with_a_genuinely_different_selection_still_closes_the_window
    group = TestFixtures.group_box
    overlay = ctrl_drag_copy([group], Geom::Vector3d.new(300.mm, 0, 0))
    refute_nil session_of(overlay)

    other = Sketchup::Selection.new([TestFixtures.ordinary_component])
    overlay.selection_changed(other)

    assert_nil session_of(overlay), 'a real new selection must still close the window even via this path'
  end

  # Confirms the guard also survives across a "/N" edit's own selection
  # mutation (apply_ctrl_drag_array re-records expected_selection), not
  # just the initial copy's.
  def test_a_delayed_notification_after_an_slash_n_edit_does_not_close_the_window
    group = TestFixtures.group_box
    overlay = ctrl_drag_copy([group], Geom::Vector3d.new(300.mm, 0, 0))
    overlay.onUserText('/3', @model.active_view)
    refute_nil session_of(overlay)

    overlay.selection_changed(@model.selection)

    refute_nil session_of(overlay),
      'a delayed echo of the /N edit\'s own selection change must not close the window either'
  end

  def test_reset_ends_the_array_input_window
    group = TestFixtures.group_box
    overlay = ctrl_drag_copy([group], Geom::Vector3d.new(300.mm, 0, 0))
    refute_nil session_of(overlay)

    overlay.reset

    assert_nil session_of(overlay), 'deactivating the tool must end the array-input window'
  end

  def test_starting_a_new_drag_ends_the_array_input_window
    group = TestFixtures.group_box
    overlay = ctrl_drag_copy([group], Geom::Vector3d.new(300.mm, 0, 0))
    refute_nil session_of(overlay)

    TestHarness.drive_move_drag(overlay, vector: Geom::Vector3d.new(50.mm, 0, 0), copy: false)

    assert_nil session_of(overlay), 'beginning another operation must end the array-input window'
  end

  def test_a_plain_move_commit_never_opens_the_array_input_window
    instance = TestFixtures.ordinary_component
    overlay = ctrl_drag_copy([instance], Geom::Vector3d.new(1000.mm, 0, 0))
    overlay.onUserText('/3', @model.active_view) # consume/close this copy's window first

    select(instance)
    TestHarness.drive_move_drag(overlay, vector: Geom::Vector3d.new(200.mm, 0, 0), copy: false)

    assert_nil session_of(overlay), 'an ordinary (non-copy) move must never open the array-input window'
  end

  # -- Never reuses the temporary-grouping trick for array intermediates ---

  # The single Ctrl-drag copy's own wrap/copy/explode trick (add_group +
  # Group#copy + explode) is not identity-safe for loose Edge/Face
  # geometry -- see the comment above add_group in on_transform_end. The
  # array feature must never fall back to it for intermediate copies, even
  # though duplicate_supported_entity/Group#copy already restrict it to
  # Group/ComponentInstance by construction. Stubbing add_group to raise
  # pins that restriction at the integration level, not just by reading
  # the source.
  def test_array_intermediate_creation_never_uses_the_temporary_grouping_trick
    group = TestFixtures.group_box
    overlay = ctrl_drag_copy([group], Geom::Vector3d.new(300.mm, 0, 0))

    @model.active_entities.define_singleton_method(:add_group) do |*_args|
      raise 'add_group must never be called for Ctrl-drag array intermediates'
    end

    overlay.onUserText('/3', @model.active_view)

    assert_equal 4, @model.selection.to_a.length, '/3 must still succeed without ever calling add_group'
  end

  # -- No Ruby Console output on success ------------------------------------

  def test_successful_array_division_produces_no_console_output
    group = TestFixtures.group_box
    overlay = ctrl_drag_copy([group], Geom::Vector3d.new(300.mm, 0, 0))

    original_stderr = $stderr
    $stderr = StringIO.new
    begin
      overlay.onUserText('/3', @model.active_view)
      captured = $stderr.string
    ensure
      $stderr = original_stderr
    end

    assert_empty captured
  end
end
