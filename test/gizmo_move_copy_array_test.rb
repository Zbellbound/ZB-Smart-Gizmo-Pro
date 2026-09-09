require 'minitest/autorun'
require 'stringio'
require_relative 'support/fixtures'

# Coverage for the native-style Move/Copy array feature: clicking a Gizmo
# move arrow and choosing Copy mode with a plain "Number of copies" count
# creates that many equally-spaced copies of the selection while leaving
# the original in place, restricted to Sketchup::Group and
# Sketchup::ComponentInstance --
# the only two entity types with a documented duplication path in the
# public SketchUp Ruby API (Group#copy; ComponentInstance has none, so
# Entities#add_instance is used instead). Loose geometry (Edge/Face) and
# any other entity type is rejected before start_operation.
#
# Most of these tests drive Zbellbound::SmartGizmoPro::GizmoOverlay#perform_copy_array
# and #parse_copy_array_count directly (the same way the existing
# smart-scale tests drive on_transform/on_transform_end), since a real
# modal UI.inputbox can't be driven from a test. One test (below, "the
# move dialog...") instead fires the registered on_click callback and
# inspects the exact prompts/defaults/list UI.inputbox was called with,
# via the stub's UI.last_inputbox_args -- this is what caught the field
# alignment/default actually reaching the dialog, as opposed to what the
# lower-level parsing methods do in isolation.
class GizmoMoveCopyArrayTest < Minitest::Test
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

  # -- API contract: Group vs ComponentInstance are NOT interchangeable ---
  #
  # Pins the exact defect the earlier implementation had: it called
  # #copy on any Drawingelement, which doesn't exist except on Group.
  # This is a static check of the stub's shape against the real API
  # (confirmed against ruby.sketchup.com/Sketchup/Group.html,
  # ComponentInstance.html, Edge.html, Face.html, Drawingelement.html) --
  # if it's wrong, every functional test below would immediately raise
  # NoMethodError instead of silently passing against an invented method.
  def test_copy_is_defined_only_on_group_not_on_other_drawingelements
    assert Sketchup::Group.method_defined?(:copy),
      'Group must define #copy -- it is the one real, documented duplication method'
    refute Sketchup::ComponentInstance.method_defined?(:copy),
      'ComponentInstance must NOT define #copy -- the real API has none; add_instance is used instead'
    refute Sketchup::Edge.method_defined?(:copy), 'Edge has no #copy in the real SketchUp API'
    refute Sketchup::Face.method_defined?(:copy), 'Face has no #copy in the real SketchUp API'
    refute Sketchup::Drawingelement.method_defined?(:copy), 'Drawingelement has no #copy in the real SketchUp API'
  end

  # -- Copy count parsing (plain number, no "x" prefix) --------------------

  def test_parse_copy_array_count_accepts_plain_whole_numbers
    overlay = build_overlay

    assert_equal 3, overlay.parse_copy_array_count('3')
    assert_equal 1, overlay.parse_copy_array_count('1')
    assert_equal 3, overlay.parse_copy_array_count(' 3 ')
    assert_equal 1000, overlay.parse_copy_array_count('1000')
  end

  def test_parse_copy_array_count_rejects_x_prefixed_input
    overlay = build_overlay

    assert_equal :invalid, overlay.parse_copy_array_count('x3'), 'the "x" prefix is no longer required or accepted'
    assert_equal :invalid, overlay.parse_copy_array_count('X3')
    assert_equal :invalid, overlay.parse_copy_array_count('x 3')
  end

  def test_parse_copy_array_count_rejects_invalid_input_without_raising
    overlay = build_overlay

    assert_equal :blank, overlay.parse_copy_array_count('')
    assert_equal :blank, overlay.parse_copy_array_count('   ')
    assert_equal :blank, overlay.parse_copy_array_count(nil)
    assert_equal :invalid, overlay.parse_copy_array_count('0')
    assert_equal :invalid, overlay.parse_copy_array_count('-3')
    assert_equal :invalid, overlay.parse_copy_array_count('2.5')
    assert_equal :invalid, overlay.parse_copy_array_count('copies')
    assert_equal :too_many, overlay.parse_copy_array_count('1001')
  end

  def test_copy_array_error_message_is_concise
    overlay = build_overlay

    assert_equal 'Enter a whole number from 1 to 1000.', overlay.copy_array_error_message(:blank)
    assert_equal 'Enter a whole number from 1 to 1000.', overlay.copy_array_error_message(:invalid)
    assert_equal 'Too many copies requested. Maximum is 1000.', overlay.copy_array_error_message(:too_many)
  end

  # The "Number of copies" field is blank every time the move dialog
  # opens (no default value, never prefilled from a previous entry) --
  # this pins the exact message shown, and that nothing about the model
  # is touched, when the user submits Copy mode without filling it in.
  def test_copy_array_blank_copies_field_shows_exact_message_and_changes_nothing
    group = TestFixtures.group_box
    select(group)
    overlay = build_overlay

    reason = overlay.parse_copy_array_count('')
    assert_equal :blank, reason
    assert_equal 'Enter a whole number from 1 to 1000.', overlay.copy_array_error_message(reason)

    # perform_copy_array is never reached for this case (the dialog
    # handler shows the message and exits first) -- confirms the state
    # that must hold true beforehand: nothing has started or changed.
    assert_empty @model.operation_log
    assert_equal [group], @model.selection.to_a
  end

  # Drives the actual on_click callback (the real code path a click on a
  # move arrow runs) and inspects exactly what UI.inputbox was called
  # with -- not just what parse_copy_array_count does in isolation. This
  # is the level a field-alignment or stale-default bug would show up at.
  def test_move_dialog_passes_a_blank_plain_number_of_copies_field
    instance = TestFixtures.ordinary_component
    select(instance)
    overlay = build_overlay
    gizmo = TestHarness.gizmo_of(overlay)
    callback_click = gizmo.instance_variable_get(:@callback_click)
    refute_nil callback_click, 'bind_gizmo_callbacks must have registered an on_click handler'

    callback_click.call([:move, X_AXIS])

    args = UI.last_inputbox_args
    refute_nil args, 'UI.inputbox must have been called'
    prompts, defaults, list, _title = args

    copies_index = prompts.index('Number of copies:')
    refute_nil copies_index, 'the dialog must include a "Number of copies:" prompt'

    mode_index = prompts.index('Mode:')
    refute_nil mode_index
    refute_equal mode_index, copies_index, 'Number of copies and Mode must not be the same field'
    assert_equal "#{Zbellbound::SmartGizmoPro::GizmoOverlay::MOVE_MODE_LABEL}|#{Zbellbound::SmartGizmoPro::GizmoOverlay::COPY_MODE_LABEL}",
      list[mode_index], 'sanity check: Mode must be the dropdown field, confirming indices are not swapped'

    assert_equal '', defaults[copies_index], 'the Number of copies default must be exactly an empty string'
    assert_equal '', list[copies_index], 'the Number of copies field must be a plain text field, not a dropdown'

    # Fire it again to prove nothing from the first invocation carries
    # forward -- there is no per-session/per-instance state that could
    # "remember" a previously typed count.
    UI.last_inputbox_args = nil
    callback_click.call([:move, X_AXIS])
    second_prompts, second_defaults, second_list, = UI.last_inputbox_args
    second_index = second_prompts.index('Number of copies:')
    assert_equal '', second_defaults[second_index], 'a second dialog invocation must still default to blank'
    assert_equal '', second_list[second_index]
  end

  # -- Transformation correctness: translation, rotation, scale, mirror ---

  def test_copy_array_translated_group_creates_correct_count_and_spacing
    group = TestFixtures.group_box
    translation = Geom::Transformation.translation(Geom::Vector3d.new(1000.mm, 500.mm, 0))
    group.transformation = translation
    select(group)
    overlay = build_overlay

    step = Geom::Transformation.translation(Geom::Vector3d.new(0, 0, 250.mm))
    overlay.perform_copy_array(step, 3)

    selected = @model.selection.to_a
    assert_equal 4, selected.length, 'original + 3 copies'
    assert group.valid?
    assert_transformation_equal(translation, group.transformation, 'original group must remain exactly in place')

    copies = selected.reject { |e| e.equal?(group) }
    assert_equal 3, copies.length
    assert copies.all? { |c| c.is_a?(Sketchup::Group) }, 'copies of a Group must themselves be Groups'

    cumulative = IDENTITY
    copies.each do |copy|
      cumulative = step * cumulative
      assert_transformation_equal(cumulative * translation, copy.transformation)
    end
  end

  def test_copy_array_supports_negative_direction
    instance = TestFixtures.ordinary_component
    select(instance)
    overlay = build_overlay

    step = Geom::Transformation.translation(Geom::Vector3d.new(-500.mm, 0, 0))
    overlay.perform_copy_array(step, 2)

    copies = @model.selection.to_a.reject { |e| e.equal?(instance) }
    offsets = copies.map { |c| c.transformation.origin.x }.sort
    assert_in_delta(-1000.mm, offsets[0], 1e-6)
    assert_in_delta(-500.mm, offsets[1], 1e-6)
  end

  def test_copy_array_x1_creates_exactly_one_copy
    instance = TestFixtures.ordinary_component
    select(instance)
    overlay = build_overlay

    overlay.perform_copy_array(Geom::Transformation.translation(Geom::Vector3d.new(10.mm, 0, 0)), 1)

    assert_equal 2, @model.selection.to_a.length, 'original + 1 copy'
  end

  def test_copy_array_rotated_component_instance_preserves_rotation
    instance = TestFixtures.ordinary_component
    rotation = Geom::Transformation.rotation(ORIGIN, Z_AXIS, 30.degrees)
    instance.transformation = rotation
    select(instance)
    overlay = build_overlay

    step = Geom::Transformation.translation(Geom::Vector3d.new(500.mm, 0, 0))
    overlay.perform_copy_array(step, 3)

    assert_transformation_equal(rotation, instance.transformation, 'original rotation must be untouched')

    copies = @model.selection.to_a.reject { |e| e.equal?(instance) }
    assert_equal 3, copies.length

    cumulative = IDENTITY
    copies.each do |copy|
      cumulative = step * cumulative
      assert_transformation_equal(cumulative * rotation, copy.transformation,
        'copy transformation must equal original transformation with the array delta applied, preserving rotation')
    end
  end

  def test_copy_array_non_uniformly_scaled_component_preserves_scale
    instance = TestFixtures.ordinary_component
    scale = Geom::Transformation.scaling(ORIGIN, 2.0, 1.0, 0.5)
    instance.transformation = scale
    select(instance)
    overlay = build_overlay

    step = Geom::Transformation.translation(Geom::Vector3d.new(0, 300.mm, 0))
    overlay.perform_copy_array(step, 2)

    copies = @model.selection.to_a.reject { |e| e.equal?(instance) }
    assert_equal 2, copies.length

    cumulative = IDENTITY
    copies.each do |copy|
      cumulative = step * cumulative
      assert_transformation_equal(cumulative * scale, copy.transformation,
        'non-uniform scale must survive the array copy unchanged')
    end
  end

  def test_copy_array_mirrored_component_preserves_mirroring
    instance = TestFixtures.ordinary_component
    mirror = Geom::Transformation.scaling(ORIGIN, -1.0, 1.0, 1.0)
    instance.transformation = mirror
    select(instance)
    overlay = build_overlay

    step = Geom::Transformation.translation(Geom::Vector3d.new(100.mm, 0, 0))
    overlay.perform_copy_array(step, 2)

    copies = @model.selection.to_a.reject { |e| e.equal?(instance) }
    assert_equal 2, copies.length

    cumulative = IDENTITY
    copies.each do |copy|
      cumulative = step * cumulative
      assert_transformation_equal(cumulative * mirror, copy.transformation,
        'mirroring (negative scale) must survive the array copy unchanged')
    end
  end

  # -- Mixed Group + ComponentInstance selection ---------------------------

  def test_copy_array_mixed_group_and_component_instance_selection
    group = TestFixtures.group_box
    instance = TestFixtures.ordinary_component
    group.transformation = Geom::Transformation.translation(Geom::Vector3d.new(0, 0, 0))
    instance.transformation = Geom::Transformation.translation(Geom::Vector3d.new(50.mm, 0, 0))
    select(group, instance)
    overlay = build_overlay

    step = Geom::Transformation.translation(Geom::Vector3d.new(200.mm, 0, 0))
    overlay.perform_copy_array(step, 2)

    selected = @model.selection.to_a
    assert_equal 6, selected.length, '2 originals + (2 originals x 2 copies each)'

    group_copies = selected.select { |e| e.is_a?(Sketchup::Group) && !e.equal?(group) }
    instance_copies = selected.select do |e|
      e.is_a?(Sketchup::ComponentInstance) && !e.is_a?(Sketchup::Group) && !e.equal?(instance)
    end
    assert_equal 2, group_copies.length, 'the Group must be duplicated via Group#copy'
    assert_equal 2, instance_copies.length, 'the plain ComponentInstance must be duplicated via add_instance'

    # The 50mm relative gap between the two originals must hold at every
    # array step -- each entity is transformed independently by the same
    # cumulative delta, not re-anchored to a shared origin.
    cumulative = IDENTITY
    [group_copies, instance_copies].transpose.each do |g_copy, c_copy|
      cumulative = step * cumulative
      assert_in_delta 50.mm, c_copy.transformation.origin.x - g_copy.transformation.origin.x, 1e-6
    end
  end

  # -- Selection validation: reject the WHOLE operation up front ----------

  def test_copy_array_rejects_loose_geometry_selection
    edge = Sketchup::Edge.new(Geom::Point3d.new(0, 0, 0), Geom::Point3d.new(10, 0, 0))
    select(edge)
    overlay = build_overlay

    overlay.perform_copy_array(Geom::Transformation.translation(Geom::Vector3d.new(500.mm, 0, 0)), 3)

    assert_empty @model.operation_log, 'no operation should ever start for an unsupported selection'
    assert_equal [edge], @model.selection.to_a, 'selection must be unchanged'
    assert_match(/groups and components/i, UI.last_messagebox_text.to_s)
  end

  def test_copy_array_rejects_mixed_supported_and_unsupported_selection
    group = TestFixtures.group_box
    edge = Sketchup::Edge.new(Geom::Point3d.new(0, 0, 0), Geom::Point3d.new(10, 0, 0))
    select(group, edge)
    overlay = build_overlay

    overlay.perform_copy_array(Geom::Transformation.translation(Geom::Vector3d.new(500.mm, 0, 0)), 2)

    assert_empty @model.operation_log,
      'a mix of a supported and an unsupported entity must reject the WHOLE operation, not copy the Group alone'
    assert_equal [group, edge], @model.selection.to_a
  end

  def test_copy_array_rejects_locked_group
    group = TestFixtures.group_box
    group.locked = true
    select(group)
    overlay = build_overlay

    overlay.perform_copy_array(Geom::Transformation.translation(Geom::Vector3d.new(500.mm, 0, 0)), 2)

    assert_empty @model.operation_log
    assert_match(/locked/i, UI.last_messagebox_text.to_s)
  end

  def test_copy_array_rejects_glued_component
    instance = TestFixtures.ordinary_component
    instance.glued_to = Object.new # stand-in for a Face it's glued to
    select(instance)
    overlay = build_overlay

    overlay.perform_copy_array(Geom::Transformation.translation(Geom::Vector3d.new(500.mm, 0, 0)), 2)

    assert_empty @model.operation_log
    assert_match(/glued/i, UI.last_messagebox_text.to_s)
  end

  # -- Metadata / attribute preservation ------------------------------------

  def test_copy_array_preserves_component_instance_metadata_and_attributes
    instance = TestFixtures.ordinary_component
    instance.name = 'Leg-01'
    instance.material = 'Oak'
    instance.layer = 'Furniture'
    instance.hidden = true
    instance.casts_shadows = false
    instance.receives_shadows = false
    instance.set_test_attribute_dictionary('zb_test', { 'sku' => 'ABC123' })
    select(instance)
    overlay = build_overlay

    overlay.perform_copy_array(Geom::Transformation.translation(Geom::Vector3d.new(300.mm, 0, 0)), 2)

    copies = @model.selection.to_a.reject { |e| e.equal?(instance) }
    assert_equal 2, copies.length
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

  def test_copy_array_preserves_group_metadata_and_attributes
    group = TestFixtures.group_box
    group.name = 'Frame-Left'
    group.material = 'Steel'
    group.layer = 'Structure'
    group.hidden = true
    group.casts_shadows = false
    group.receives_shadows = false
    group.set_test_attribute_dictionary('zb_test', { 'part' => 'frame' })
    select(group)
    overlay = build_overlay

    overlay.perform_copy_array(Geom::Transformation.translation(Geom::Vector3d.new(0, 300.mm, 0)), 2)

    copies = @model.selection.to_a.reject { |e| e.equal?(group) }
    assert_equal 2, copies.length
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

  # An attribute that can't be copied must never be silently dropped --
  # that would commit an apparently successful array containing a copy
  # with missing extension/Dynamic Component data. It must abort the
  # WHOLE operation instead, exactly like any other mid-array failure.
  # The source dictionary is made to succeed on the first copy and fail
  # on the second, so this pins that a failure partway through a
  # multi-copy array rolls back cleanly, not just a failure on the very
  # first attempt.
  def test_copy_array_aborts_completely_when_an_attribute_cannot_be_copied
    instance = TestFixtures.ordinary_component
    instance.set_test_attribute_dictionary('zb_test', { 'sku' => 'ABC123' })
    dict = instance.attribute_dictionary('zb_test')
    call_count = 0
    dict.define_singleton_method(:each_pair) do |&block|
      call_count += 1
      raise 'simulated attribute write failure' if call_count >= 2

      block.call('sku', 'ABC123')
    end
    select(instance)
    overlay = build_overlay

    original_stderr = $stderr
    $stderr = StringIO.new
    begin
      overlay.perform_copy_array(Geom::Transformation.translation(Geom::Vector3d.new(50.mm, 0, 0)), 3)
      captured = $stderr.string
    ensure
      $stderr = original_stderr
    end

    starts, commits, aborts = operation_counts
    assert_equal 1, starts
    assert_equal 0, commits,
      'an attribute that cannot be copied must abort the whole array, never commit a copy with missing data'
    assert_equal 1, aborts
    assert_equal [instance], @model.selection.to_a,
      'original selection must be restored -- no copies left selected after an abort'
    assert instance.valid?, 'original entity must be untouched'
    assert_equal 'ABC123', instance.attribute_dictionary('zb_test')['sku'],
      "original entity's own attribute data must be untouched by the failed copy attempt"
    refute_nil UI.last_messagebox_text, 'the user must see one concise error message'
    assert_empty captured, 'aborting on an attribute failure must never write to the Ruby Console'
  end

  # -- Undo / abort ------------------------------------------------------------

  def test_copy_array_is_a_single_undo_operation
    instance = TestFixtures.ordinary_component
    select(instance)
    overlay = build_overlay

    overlay.perform_copy_array(Geom::Transformation.translation(Geom::Vector3d.new(10.mm, 0, 0)), 5)

    starts, commits, aborts = operation_counts
    assert_equal 1, starts
    assert_equal 1, commits
    assert_equal 0, aborts
  end

  # Simulates a mid-array failure (first copy succeeds, second fails while
  # computing the next step) to prove a failure aborts the whole operation
  # instead of leaving a partial array. Wraps the step transformation
  # rather than monkey-patching SketchUp API classes.
  class PoisonStepAfterFirstUse
    def initialize(real_transformation)
      @real_transformation = real_transformation
      @calls = 0
    end

    def *(other)
      @calls += 1
      raise 'Simulated mid-array failure' if @calls == 2

      @real_transformation * other
    end
  end

  def test_copy_array_failure_aborts_without_partial_copies
    group = TestFixtures.group_box
    select(group)
    overlay = build_overlay
    real_tr = Geom::Transformation.translation(Geom::Vector3d.new(100.mm, 0, 0))
    poison_step = PoisonStepAfterFirstUse.new(real_tr)

    overlay.perform_copy_array(poison_step, 3)

    starts, commits, aborts = operation_counts
    assert_equal 1, starts
    assert_equal 0, commits
    assert_equal 1, aborts
    assert group.valid?, 'original entity must survive an aborted copy-array operation'
    assert_equal [group], @model.selection.to_a, 'selection must be untouched when the operation aborts'
  end

  # -- No Ruby Console output in production ------------------------------------

  def test_copy_array_produces_no_console_output_on_success
    instance = TestFixtures.ordinary_component
    select(instance)
    overlay = build_overlay
    step = Geom::Transformation.translation(Geom::Vector3d.new(500.mm, 0, 0))

    original_stderr = $stderr
    $stderr = StringIO.new
    begin
      overlay.perform_copy_array(step, 3)
      captured = $stderr.string
    ensure
      $stderr = original_stderr
    end

    assert_empty captured, 'no Ruby Console output expected for a successful copy-array in production'
  end

  def test_copy_array_produces_no_console_output_on_rejection
    edge = Sketchup::Edge.new(Geom::Point3d.new(0, 0, 0), Geom::Point3d.new(10, 0, 0))
    select(edge)
    overlay = build_overlay
    step = Geom::Transformation.translation(Geom::Vector3d.new(500.mm, 0, 0))

    original_stderr = $stderr
    $stderr = StringIO.new
    begin
      overlay.perform_copy_array(step, 3)
      captured = $stderr.string
    ensure
      $stderr = original_stderr
    end

    assert_empty captured, 'no Ruby Console output expected when copy-array rejects an unsupported selection'
  end
end
