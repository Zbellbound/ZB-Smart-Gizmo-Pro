require 'minitest/autorun'
require 'stringio'
require_relative 'support/fixtures'

# The real observer.rb subclasses SketchUp's observer classes at load time;
# the shared harness only stubs what the overlay needs.
module Sketchup
  %i[AppObserver ModelObserver SelectionObserver ToolsObserver].each do |name|
    const_set(name, Class.new) unless const_defined?(name)
  end
  unless const_defined?(:Pages)
    module Pages
      def self.add_frame_change_observer(_observer); end
    end
  end
  def self.add_observer(_observer); end unless respond_to?(:add_observer)
  singleton_class.send(:attr_accessor, :active_model) unless respond_to?(:active_model)
end
# SketchUp-provided tool constants the overlay's mouse handlers read.
Object.const_set(:COPY_MODIFIER_MASK, 4) unless Object.const_defined?(:COPY_MODIFIER_MASK)
Object.const_set(:MK_LBUTTON, 1) unless Object.const_defined?(:MK_LBUTTON)
require File.expand_path('../zb_smart_gizmo_pro/observer.rb', __dir__)

# Every route that can activate the gizmo or change the model goes through
# the ONE shared license gate (zb_smart_gizmo_pro/licensing.rb). Proven here
# against the real observer/overlay/loader code with SketchUp's licensing
# stubbed to each state:
#
#  * observer / startup / overlay-start routes are SILENT and inert when
#    unlicensed (no message, no enable, no start, no timers);
#  * toolbar/menu activation is VISIBLE (state-specific message) and keeps the
#    gizmo inactive;
#  * the first gizmo gesture and every model-mutating entry path refuse
#    BEFORE any Undo operation opens, leaving the model untouched;
#  * passive mouse moves never consult the API;
#  * Manual, About and Preferences stay available, and saving Preferences
#    cannot restart an unlicensed overlay.
class LicensingGateTest < Minitest::Test
  L = Sketchup::Licensing
  Licensing = Zbellbound::SmartGizmoPro::Licensing
  P = Zbellbound::SmartGizmoPro
  NOT_LICENSED_MESSAGE = Zbellbound::SmartGizmoPro::Licensing::NOT_LICENSED_MESSAGE
  ROOT = File.expand_path('..', __dir__)

  # ---- test doubles ----------------------------------------------------------

  class FakeOverlayCollection
    include Enumerable

    def initialize(items = [])
      @items = items
    end

    def each(&block)
      @items.each(&block)
    end

    def to_a
      @items.dup
    end

    def add(overlay)
      @items << overlay
      overlay
    end

    def remove(overlay)
      @items.delete(overlay)
    end
  end

  class FakeSelection < Sketchup::Selection
    def add_observer(_observer); end
  end

  class FakeTools
    attr_reader :pushed, :popped

    def initialize
      @pushed = []
      @popped = 0
    end

    def add_observer(_observer); end

    def push_tool(tool)
      @pushed << tool
    end

    def pop_tool
      @popped += 1
    end
  end

  # A model with an overlay collection, for the observer / toggle routes.
  class FakeOverlayModel
    attr_reader :overlays, :selection, :tools, :active_view

    def initialize(overlays = [])
      @overlays = FakeOverlayCollection.new(overlays)
      @selection = FakeSelection.new
      @tools = FakeTools.new
      @active_view = Sketchup::View.new
    end

    def valid?
      true
    end

    def add_observer(_observer); end
  end

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
    L.reset!
    UI.last_messagebox_text = nil
    UI.last_inputbox_args = nil
    UI.started_timers = []
    UI.timer_blocks = []
    Sketchup.active_model = nil
    P::PLUGIN.test_smart_scale_enabled = false
    P::PLUGIN.test_gizmo_orientation = P::GLOBAL_ORIENTATION
    Sketchup.reset_defaults_registry!
  end

  def teardown
    L.reset!
    Sketchup.active_model = nil
  end

  # An overlay whose lifecycle methods just record what the routes asked of
  # it, so a route's own license gate can be observed in isolation.
  def spy_overlay(calls)
    overlay = P::GizmoOverlay.allocate
    # start records the model and the boolean it was handed, and -- like the real
    # one -- records that result as the overlay's display authorization.
    overlay.define_singleton_method(:start) do |model = nil, authorized: nil|
      calls << [:start, model, authorized]
      self.display_authorized = authorized == true
    end
    overlay.define_singleton_method(:bind_model) { |model| calls << [:bind_model, model] }
    overlay.define_singleton_method(:selection_changed) { |_selection| calls << [:selection_changed] }
    overlay.define_singleton_method(:enabled=) do |value|
      calls << [:enabled=, value]
      @enabled = value
    end
    overlay
  end

  def build_observer
    observer = P::GizmoObserver.allocate
    observer.instance_variable_set(:@observed_models, {})
    observer.instance_variable_set(:@activation_generations, {})
    observer
  end

  def with_observer(fake)
    P::PLUGIN.define_singleton_method(:observer) { fake }
    yield
  ensure
    P::PLUGIN.singleton_class.send(:remove_method, :observer)
  end

  # -- Observer / startup routes: silent and inert when unlicensed -------------

  def test_startup_activation_refused_is_silent_and_inert
    calls = []
    overlay = spy_overlay(calls)
    model = FakeOverlayModel.new([overlay])

    result = TestLicense.unlicensed { build_observer.activate_overlay(model, overlay) }

    assert_nil result
    assert_empty calls, 'an unlicensed overlay must never be enabled, bound or started'
    refute overlay.enabled?
    assert_nil UI.last_messagebox_text, 'startup activation must never show a message'
  end

  def test_licensed_activation_enables_and_starts_the_overlay
    calls = []
    overlay = spy_overlay(calls)
    model = FakeOverlayModel.new([overlay])

    result = TestLicense.with_state(L::LICENSED) { build_observer.activate_overlay(model, overlay) }

    assert_same overlay, result
    assert_includes calls, [:enabled=, true]
    assert_includes calls, [:start, model, true]
    assert_nil UI.last_messagebox_text
  end

  def test_an_active_trial_activates_the_overlay
    calls = []
    overlay = spy_overlay(calls)
    model = FakeOverlayModel.new([overlay])
    TestLicense.with_state(L::TRIAL) { build_observer.activate_overlay(model, overlay) }
    assert_includes calls, [:start, model, true]
  end

  def test_every_refusal_state_and_a_failing_lookup_keep_the_overlay_inactive_silently
    [
      { state: L::NOT_LICENSED }, { state: L::EXPIRED }, { state: L::TRIAL_EXPIRED },
      { state: 99, licensed: false }, { state: :nil_license },
      { state: :object_without_licensed }, { raises: RuntimeError.new('boom') }
    ].each do |opts|
      calls = []
      overlay = spy_overlay(calls)
      model = FakeOverlayModel.new([overlay])
      TestLicense.with_state(opts[:state], raises: opts[:raises], licensed: opts[:licensed]) do
        build_observer.activate_overlay(model, overlay)
      end
      assert_empty calls, "#{opts.inspect} must not activate"
      assert_nil UI.last_messagebox_text, "#{opts.inspect} must stay silent"
    end
  end

  def test_no_retry_timers_are_scheduled_when_refused_and_four_when_licensed
    model = FakeOverlayModel.new
    TestLicense.unlicensed { build_observer.queue_overlay_activation(model) }
    assert_empty UI.started_timers

    TestLicense.with_state(L::LICENSED) { build_observer.queue_overlay_activation(model) }
    assert_equal 4, UI.started_timers.length
  end

  def test_scene_change_and_model_events_cannot_activate_an_unlicensed_overlay
    calls = []
    overlay = spy_overlay(calls)
    model = FakeOverlayModel.new([overlay])
    observer = build_observer

    lookups = nil
    TestLicense.unlicensed do
      observer.scene_changed(model)
      observer.attach_observers(model)
      observer.attach_observers(model) # model re-open / File>Open re-attachment branch
      lookups = L.requested_ids.length
    end

    assert_equal 3, lookups, 'one silent lookup per activation cycle'
    assert_empty calls
    assert_empty UI.started_timers
    assert_nil UI.last_messagebox_text
    refute overlay.enabled?
  end

  def test_model_events_activate_a_licensed_overlay_as_before
    calls = []
    overlay = spy_overlay(calls)
    model = FakeOverlayModel.new([overlay])

    TestLicense.with_state(L::LICENSED) { build_observer.attach_observers(model) }

    assert_includes calls, [:start, model, true]
    assert_equal 4, UI.started_timers.length
  end

  def test_activation_rereads_the_license_when_it_returns_and_when_it_lapses
    calls = []
    overlay = spy_overlay(calls)
    model = FakeOverlayModel.new([overlay])
    observer = build_observer

    L.reset!
    L.state = L::NOT_LICENSED
    observer.activate_overlay(model, overlay)
    assert_empty calls

    L.state = L::LICENSED
    observer.activate_overlay(model, overlay)
    assert_includes calls, [:start, model, true]

    calls.clear
    L.state = L::EXPIRED
    observer.activate_overlay(model, overlay)
    assert_empty calls
    assert_equal 3, L.requested_ids.length, 'every activation attempt asks SketchUp again'
  end

  # -- The overlay's own start (SketchUp's Overlay controls, Preferences) -----

  def test_overlay_start_is_gated_silently
    overlay = P::GizmoOverlay.allocate
    reached = Class.new(StandardError)
    overlay.define_singleton_method(:refresh_context) { |*| raise reached }

    lookups = nil
    TestLicense.unlicensed { overlay.start(Sketchup::Model.new); lookups = L.requested_ids.length }
    assert_nil UI.last_messagebox_text, 'start must never show a message'
    refute overlay.display_authorized?, 'a refused start leaves the overlay unauthorized'
    assert_equal 1, lookups, 'a standalone start makes its one silent lookup'

    assert_raises(reached, 'a licensed start proceeds past the gate') do
      TestLicense.with_state(L::LICENSED) { overlay.start(Sketchup::Model.new) }
    end
    assert overlay.display_authorized?

    # A caller that already holds the cycle boolean passes it: no second lookup.
    lookups = nil
    TestLicense.unlicensed { overlay.start(Sketchup::Model.new, authorized: false); lookups = L.requested_ids.length }
    assert_equal 0, lookups
    refute overlay.display_authorized?
  end

  # -- Toolbar and Extensions menu ---------------------------------------------

  def test_toolbar_refusal_shows_the_state_specific_message_and_keeps_the_gizmo_inactive
    {
      L::NOT_LICENSED => Licensing::NOT_LICENSED_MESSAGE,
      L::EXPIRED => Licensing::EXPIRED_MESSAGE,
      L::TRIAL_EXPIRED => Licensing::TRIAL_EXPIRED_MESSAGE
    }.each do |state, message|
      calls = []
      overlay = spy_overlay(calls)
      Sketchup.active_model = FakeOverlayModel.new([overlay])
      UI.last_messagebox_text = nil

      TestLicense.with_state(state) { P.toggle_gizmo }

      assert_equal message, UI.last_messagebox_text
      assert_empty calls, 'a refused toggle must not enable or start the overlay'
      refute overlay.enabled?
    end
  end

  def test_toolbar_with_an_unverifiable_license_says_it_could_not_check
    overlay = spy_overlay([])
    Sketchup.active_model = FakeOverlayModel.new([overlay])
    TestLicense.with_state(raises: RuntimeError.new('offline')) { P.toggle_gizmo }
    assert_equal Licensing::UNVERIFIED_MESSAGE, UI.last_messagebox_text
    refute overlay.enabled?
  end

  def test_toolbar_refusal_switches_off_an_overlay_sketchup_left_enabled
    calls = []
    overlay = spy_overlay(calls)
    overlay.enabled = true
    Sketchup.active_model = FakeOverlayModel.new([overlay])

    TestLicense.unlicensed { P.toggle_gizmo }

    assert_equal NOT_LICENSED_MESSAGE, UI.last_messagebox_text
    refute overlay.enabled?, 'the gizmo must be left inactive'
    refute(calls.any? { |call| call.first == :start })
  end

  def test_toolbar_refusal_does_not_touch_the_observers
    observer_calls = []
    fake_observer = Object.new
    fake_observer.define_singleton_method(:attach_observers) { |m, **kw| observer_calls << [:attach_observers, m, kw] }
    fake_observer.define_singleton_method(:recreate_overlay) { |m, **kw| observer_calls << [:recreate_overlay, m, kw] }
    fake_observer.define_singleton_method(:activate_overlay) { |*a, **kw| observer_calls << [:activate_overlay, *a, kw] }
    fake_observer.define_singleton_method(:cancel_pending_activation) { |m| observer_calls << [:cancel_pending_activation, m] }
    Sketchup.active_model = FakeOverlayModel.new([spy_overlay([])])

    with_observer(fake_observer) { TestLicense.unlicensed { P.toggle_gizmo } }

    assert_empty observer_calls
    assert_equal NOT_LICENSED_MESSAGE, UI.last_messagebox_text
  end

  def test_toolbar_licensed_and_trial_activate_normally_without_any_message
    [L::LICENSED, L::TRIAL].each do |state|
      calls = []
      overlay = spy_overlay(calls)
      Sketchup.active_model = FakeOverlayModel.new([overlay])
      UI.last_messagebox_text = nil

      TestLicense.with_state(state) { P.toggle_gizmo }

      assert_nil UI.last_messagebox_text
      assert overlay.enabled?, "#{state}: the gizmo activates"
      assert_includes calls, [:start, nil, true]
      assert overlay.display_authorized?, "#{state}: the gizmo is authorized to draw"
    end
  end

  def test_toolbar_licensed_path_still_uses_the_observer_when_present
    observer_calls = []
    overlay = spy_overlay([])
    fake_observer = Object.new
    fake_observer.define_singleton_method(:attach_observers) { |m, **kw| observer_calls << [:attach_observers, m, kw] }
    fake_observer.define_singleton_method(:activate_overlay) { |*a, **kw| observer_calls << [:activate_overlay, *a, kw] }
    model = FakeOverlayModel.new([overlay])
    Sketchup.active_model = model

    lookups = nil
    with_observer(fake_observer) { TestLicense.with_state(L::LICENSED) { P.toggle_gizmo; lookups = L.requested_ids.length } }

    assert_equal [[:attach_observers, model, { authorized: true }],
                  [:activate_overlay, model, overlay, { authorized: true }]], observer_calls
    assert_equal 1, lookups, 'the visible check hands its boolean on: one click, one lookup'
  end

  def test_each_toolbar_click_asks_sketchup_again
    calls = []
    overlay = spy_overlay(calls)
    Sketchup.active_model = FakeOverlayModel.new([overlay])

    L.reset!
    L.state = L::NOT_LICENSED
    P.toggle_gizmo
    refute overlay.enabled?

    L.state = L::LICENSED
    P.toggle_gizmo
    assert overlay.enabled?, 'a license obtained since the last click is honored on the next one'
    assert_equal 2, L.requested_ids.length
  end

  # -- Direct overlay routes ----------------------------------------------------

  # An overlay SketchUp has enabled. `authorized` is the most recent silent
  # authorization result the overlay holds: true for an overlay a licensed
  # activation started, false for one SketchUp's own Overlays panel switched on
  # while unlicensed.
  def gesture_overlay(entity, authorized: true)
    @model = Sketchup::Model.new
    @model.selection.instance_variable_set(:@list, [entity])
    overlay = TestHarness.build_overlay(model: @model, selection: @model.selection)
    overlay.instance_variable_set(:@active_gizmo, true)
    overlay.enabled = true
    overlay.display_authorized = authorized
    overlay
  end

  # Runs the block under a license state and returns how many license lookups
  # it made (captured inside the block: the state helper resets the stub after).
  def lookups_during(state = L::NOT_LICENSED, **opts)
    count = nil
    TestLicense.with_state(state, **opts) do
      yield
      count = L.requested_ids.length
    end
    count
  end

  def geometry_snapshot(entity)
    [entity.transformation.to_a, entity.bounds.min.to_a, entity.bounds.max.to_a, @model.active_entities.to_a.length]
  end

  def test_the_first_gizmo_gesture_is_refused_before_the_manipulator_sees_the_click
    group = TestFixtures.group_box
    overlay = gesture_overlay(group)
    gizmo = TestHarness.gizmo_of(overlay)
    downs = []
    gizmo.define_singleton_method(:prepick?) { |*| true }
    gizmo.define_singleton_method(:onLButtonDown) { |*args| downs << args; true }
    before = geometry_snapshot(group)

    TestLicense.unlicensed { overlay.onLButtonDown(0, 10, 10, @model.active_view) }

    assert_empty downs, 'the manipulator must never receive a click from an unlicensed installation'
    assert_equal NOT_LICENSED_MESSAGE, UI.last_messagebox_text
    assert_empty @model.operation_log, 'no Undo operation may be created'
    assert_equal before, geometry_snapshot(group)
  end

  def test_a_licensed_gesture_reaches_the_manipulator_and_shows_nothing
    group = TestFixtures.group_box
    overlay = gesture_overlay(group)
    gizmo = TestHarness.gizmo_of(overlay)
    downs = []
    gizmo.define_singleton_method(:prepick?) { |*| true }
    gizmo.define_singleton_method(:onLButtonDown) { |*args| downs << args; true }

    [L::LICENSED, L::TRIAL].each do |state|
      TestLicense.with_state(state) { overlay.onLButtonDown(0, 10, 10, @model.active_view) }
    end

    assert_equal 2, downs.length
    assert_nil UI.last_messagebox_text
  end

  def test_the_gesture_check_is_reread_each_time
    overlay = gesture_overlay(TestFixtures.group_box)
    gizmo = TestHarness.gizmo_of(overlay)
    downs = []
    gizmo.define_singleton_method(:prepick?) { |*| true }
    gizmo.define_singleton_method(:onLButtonDown) { |*args| downs << args; true }

    L.reset!
    L.state = L::NOT_LICENSED
    overlay.onLButtonDown(0, 10, 10, @model.active_view)
    assert_empty downs
    L.state = L::LICENSED
    overlay.onLButtonDown(0, 10, 10, @model.active_view)
    assert_equal 1, downs.length
    assert_equal 2, L.requested_ids.length
  end

  def test_passive_mouse_moves_never_consult_the_license_api
    group = TestFixtures.group_box
    overlay = gesture_overlay(group)
    gizmo = TestHarness.gizmo_of(overlay)
    gizmo.define_singleton_method(:tooltip) { '' }
    gizmo.define_singleton_method(:mouse_over?) { false }
    gizmo.define_singleton_method(:prepick?) { |*| false }
    gizmo.define_singleton_method(:onMouseMove) { |*| false }

    [L::LICENSED, L::NOT_LICENSED].each do |state|
      L.reset!
      L.state = state
      50.times { |i| overlay.onMouseMove(0, 100 + i, 200 + i, @model.active_view) }
      assert_empty L.requested_ids, 'a passive mouse move must never ask SketchUp about the license'
    end
    assert_nil UI.last_messagebox_text
  end

  def drive_refused_drag(overlay, group)
    before = geometry_snapshot(group)
    TestLicense.unlicensed do
      yield
    end
    assert_equal NOT_LICENSED_MESSAGE, UI.last_messagebox_text
    assert_empty @model.operation_log, 'no Undo operation may be created'
    assert_equal before, geometry_snapshot(group), 'the model must be unchanged'
  end

  def test_a_drag_that_reaches_the_callbacks_anyway_touches_nothing
    group = TestFixtures.group_box
    overlay = gesture_overlay(group)

    drive_refused_drag(overlay, group) do
      TestHarness.drive_move_drag(overlay, vector: Geom::Vector3d.new(500.mm, 0, 0))
    end
    UI.last_messagebox_text = nil
    drive_refused_drag(overlay, group) do
      TestHarness.drive_move_drag(overlay, vector: Geom::Vector3d.new(500.mm, 0, 0), copy: true)
    end
    UI.last_messagebox_text = nil
    drive_refused_drag(overlay, group) do
      TestHarness.drive_scale_drag(overlay, axis_id: :z, ratio: 0.5, origin: group.bounds.min)
    end
  end

  def test_a_click_after_a_refused_gesture_opens_no_dialog
    group = TestFixtures.group_box
    overlay = gesture_overlay(group)
    gizmo = TestHarness.gizmo_of(overlay)
    start_cb = gizmo.instance_variable_get(:@callback_start)
    click_cb = gizmo.instance_variable_get(:@callback_click)
    end_cb = gizmo.instance_variable_get(:@callback_end)

    TestLicense.unlicensed do
      start_cb.call('Move')
      click_cb.call([:move, X_AXIS.clone])
      end_cb.call
    end

    assert_nil UI.last_inputbox_args, 'no numeric input dialog may open for a refused gesture'
    assert_empty @model.operation_log
  end

  def test_a_licensed_drag_still_opens_and_commits_its_operation
    group = TestFixtures.group_box
    overlay = gesture_overlay(group)

    TestLicense.with_state(L::LICENSED) do
      TestHarness.drive_move_drag(overlay, vector: Geom::Vector3d.new(500.mm, 0, 0))
    end

    assert_equal [[:start, 'Transform', true, false, false], [:commit]], @model.operation_log
    assert_nil UI.last_messagebox_text
  end

  # -- Every model-mutating entry path -----------------------------------------

  def test_copy_array_is_refused_without_an_operation_or_a_copy
    group = TestFixtures.group_box
    overlay = gesture_overlay(group)
    before = geometry_snapshot(group)
    step = Geom::Transformation.translation(Geom::Vector3d.new(0, 0, 250.mm))

    TestLicense.unlicensed { overlay.perform_copy_array(step, 3) }

    assert_equal NOT_LICENSED_MESSAGE, UI.last_messagebox_text
    assert_empty @model.operation_log
    assert_equal before, geometry_snapshot(group)
    assert_equal [group], @model.selection.to_a
  end

  def test_copy_array_still_works_when_licensed
    group = TestFixtures.group_box
    overlay = gesture_overlay(group)
    step = Geom::Transformation.translation(Geom::Vector3d.new(0, 0, 250.mm))

    TestLicense.with_state(L::LICENSED) { overlay.perform_copy_array(step, 3) }

    assert_equal 4, @model.selection.to_a.length
    assert_equal [:start, :commit], @model.operation_log.map(&:first)
  end

  def test_ctrl_drag_array_and_typed_edits_are_refused_after_a_licensed_gesture
    group = TestFixtures.group_box
    overlay = gesture_overlay(group)
    TestLicense.with_state(L::LICENSED) do
      TestHarness.drive_move_drag(overlay, vector: Geom::Vector3d.new(200.mm, 0, 0), copy: true)
    end
    refute_nil overlay.instance_variable_get(:@ctrl_array_session), 'the Ctrl-drag array window must be open'
    log_before = @model.operation_log.dup
    selection_before = @model.selection.to_a

    TestLicense.unlicensed do
      overlay.onUserText('/3', @model.active_view)   # internal array
      overlay.onUserText('x3', @model.active_view)   # external array
    end

    assert_equal NOT_LICENSED_MESSAGE, UI.last_messagebox_text
    assert_equal log_before, @model.operation_log, 'a refused array must not open an Undo operation'
    assert_equal selection_before, @model.selection.to_a
  end

  def test_a_typed_re_edit_is_refused_without_an_operation
    group = TestFixtures.group_box
    overlay = gesture_overlay(group)
    TestLicense.with_state(L::LICENSED) do
      TestHarness.drive_move_drag(overlay, vector: Geom::Vector3d.new(200.mm, 0, 0))
    end
    log_before = @model.operation_log.dup
    transformation_before = group.transformation.to_a

    TestLicense.unlicensed { overlay.onUserText('750', @model.active_view) }

    assert_equal NOT_LICENSED_MESSAGE, UI.last_messagebox_text
    assert_equal log_before, @model.operation_log
    assert_equal transformation_before, group.transformation.to_a
  end

  def test_a_typed_smart_scale_re_edit_is_refused_without_an_operation
    P::PLUGIN.test_smart_scale_enabled = true
    @model = Sketchup::Model.new
    instance = TestFixtures.frame_component(@model.active_entities, z_size: 100.0, leg: 10.0)
    @model.selection.instance_variable_set(:@list, [instance])
    overlay = TestHarness.build_overlay(model: @model, selection: @model.selection)
    TestLicense.with_state(L::LICENSED) do
      TestHarness.drive_scale_drag(overlay, axis_id: :z, ratio: 0.5, origin: instance.bounds.min)
    end
    log_before = @model.operation_log.dup
    before = geometry_snapshot(instance)

    TestLicense.unlicensed { overlay.onUserText('0.25', @model.active_view) }

    assert_equal NOT_LICENSED_MESSAGE, UI.last_messagebox_text
    assert_equal log_before, @model.operation_log
    assert_equal before, geometry_snapshot(instance)
  end

  def test_arrow_key_rotation_is_refused_without_an_operation
    group = TestFixtures.group_box
    overlay = gesture_overlay(group)
    overlay.instance_variable_set(:@last_transform, [IDENTITY, IDENTITY, [:rotate, ORIGIN.clone, Z_AXIS.clone, 0.degrees]])
    before = geometry_snapshot(group)

    TestLicense.unlicensed { overlay.apply_rotate_arrow(90, @model.active_view) }

    assert_equal NOT_LICENSED_MESSAGE, UI.last_messagebox_text
    assert_empty @model.operation_log
    assert_equal before, geometry_snapshot(group)
  end

  def test_the_operation_doorway_refuses_before_start_operation_for_every_state
    overlay = gesture_overlay(TestFixtures.group_box)
    [L::NOT_LICENSED, L::EXPIRED, L::TRIAL_EXPIRED].each do |state|
      refute TestLicense.with_state(state) { overlay.start_licensed_operation('Anything') }
    end
    refute TestLicense.with_state(raises: RuntimeError.new('boom')) { overlay.start_licensed_operation('Anything') }
    assert_empty @model.operation_log

    assert TestLicense.with_state(L::TRIAL) { overlay.start_licensed_operation('Anything', false, true) }
    assert_equal [[:start, 'Anything', true, false, true]], @model.operation_log
  end

  def test_no_model_operation_is_opened_anywhere_except_through_the_licensed_doorway
    source = File.read(File.join(ROOT, 'zb_smart_gizmo_pro', 'overlay.rb'))
    direct = source.lines.each_with_index.select do |line, _i|
      line =~ /start_operation/ && line !~ /^\s*#/
    end
    assert_equal 1, direct.length, 'exactly one raw start_operation may exist: inside start_licensed_operation'
    assert_match(/@model\.start_operation\(name, true, next_transparent, transparent\)/, direct.first.first)
  end

  # -- Context menu -------------------------------------------------------------

  def menu_for(overlay)
    overlay.define_singleton_method(:gizmo_hovering?) { |*| true }
    overlay.define_singleton_method(:selected_one_object?) { true }
    menu = FakeMenu.new
    assert overlay.getMenu(menu, 0, 10, 10, @model.active_view)
    menu
  end

  def test_pivot_and_orientation_menu_actions_carry_the_gate_but_preferences_and_hide_do_not
    overlay = gesture_overlay(TestFixtures.group_box)
    pivot_calls = []
    %i[set_pivot_to_selection_center set_pivot_to_model_origin set_pivot_to_object_origin].each do |name|
      overlay.define_singleton_method(name) { pivot_calls << name }
    end
    menu = menu_for(overlay)

    TestLicense.unlicensed do
      menu.items['Reset Pivot To Selection Center'].call
      menu.items['Set Pivot To Model Axes Origin'].call
      menu.items['Set Pivot To Object Origin'].call
      menu.items['Object'].call
    end
    assert_empty pivot_calls
    assert_equal P::GLOBAL_ORIENTATION, P::PLUGIN.gizmo_orientation, 'orientation must not change while unlicensed'
    assert_equal NOT_LICENSED_MESSAGE, UI.last_messagebox_text

    UI.last_messagebox_text = nil
    TestLicense.with_state(L::LICENSED) do
      menu.items['Reset Pivot To Selection Center'].call
      menu.items['Set Pivot To Model Axes Origin'].call
      menu.items['Set Pivot To Object Origin'].call
    end
    assert_equal %i[set_pivot_to_selection_center set_pivot_to_model_origin set_pivot_to_object_origin], pivot_calls
    assert_nil UI.last_messagebox_text
  end

  def test_the_preferences_menu_item_is_never_gated
    overlay = gesture_overlay(TestFixtures.group_box)
    opened = []
    P::PLUGIN.define_singleton_method(:open_preferences) { opened << :preferences }
    menu = menu_for(overlay)

    lookups = lookups_during { menu.items['Preferences...'].call }

    assert_equal [:preferences], opened
    assert_equal 0, lookups
    assert_nil UI.last_messagebox_text
  ensure
    P::PLUGIN.singleton_class.send(:remove_method, :open_preferences)
  end

  # -- Manual, About and Preferences (loader.rb) --------------------------------

  def loader_source
    @loader_source ||= File.read(File.join(ROOT, 'zb_smart_gizmo_pro', 'loader.rb'))
  end

  def method_source(name)
    loader_source[/^ {6}def self\.#{name}\b.*?^ {6}end\r?\n/m]
  end

  def loader_host
    host = Module.new
    host.const_set(:PLUGIN_NAME, 'ZB Smart Gizmo Pro')
    host.const_set(:PLUGIN_VERSION, '1.5.4')
    host.const_set(:Licensing, Licensing)
    host
  end

  def test_about_stays_available_and_never_consults_the_license
    source = method_source('open_about')
    refute_nil source
    host = loader_host
    host.class_eval("class << self\n#{source.gsub(/^ {6}def self\./, '  def ')}\nend")

    lookups = lookups_during { host.open_about }

    assert_equal "ZB Smart Gizmo Pro 1.5.4\n\nDeveloper: Peter Zbel\nWebsite: www.zbellbound.com", UI.last_messagebox_text
    assert_equal 0, lookups
  end

  def test_manual_stays_available_and_never_consults_the_license
    source = method_source('open_manual')
    refute_nil source
    shown = []
    dialog_class = Class.new do
      define_method(:initialize) { |**_options| }
      define_method(:set_html) { |html| shown << [:html, html] }
      define_method(:show) { shown << :show }
    end
    dialog_class.const_set(:STYLE_DIALOG, 0)
    UI.const_set(:HtmlDialog, dialog_class)
    host = loader_host
    host.define_singleton_method(:manual_html) { '<html></html>' }
    host.singleton_class.send(:attr_accessor, :manual_dialog)
    host.class_eval("class << self\n#{source.gsub(/^ {6}def self\./, '  def ')}\nend")

    lookups = lookups_during { host.open_manual }

    assert_equal [[:html, '<html></html>'], :show], shown
    assert_equal 0, lookups
    assert_nil UI.last_messagebox_text
  ensure
    UI.send(:remove_const, :HtmlDialog) if UI.const_defined?(:HtmlDialog, false)
  end

  # The real preference getters/setters/open_preferences, class_eval'd onto a
  # host module -- the same technique preferences_namespace_test.rb uses.
  def preferences_host(active_overlay)
    const_match = /^( {4}OVERLAY_ID.*? {4}LOCAL_ORIENTATION = 1\r?\n)/m.match(loader_source)
    method_match = /^( {6}def self\.gizmo_orientation.*? {6}end\r?\n)\r?\n {6}def self\.manual_html/m.match(loader_source)
    refute_nil const_match
    refute_nil method_match
    host = Module.new
    host.class_eval(<<~RUBY)
      PLUGIN_NAME = 'ZB Smart Gizmo Pro'

      #{const_match[1]}

      class << self
        #{method_match[1].gsub(/^ {6}def self\./, 'def ').gsub(/^ {6}end$/, 'end')}
      end
    RUBY
    host.const_set(:Licensing, Licensing)
    host.define_singleton_method(:active_overlay) { active_overlay }
    host
  end

  SAVED_PREFERENCES = [100, 8, 'cm', 'No', 'Yes', 'No', 'X', 10.0, -45.0, 45.0, 90.0, -90.0].freeze

  def save_preferences_through(host)
    original = UI.method(:inputbox)
    UI.define_singleton_method(:inputbox) { |*_args| SAVED_PREFERENCES }
    yield
    host.open_preferences
  ensure
    UI.define_singleton_method(:inputbox, original)
  end

  def test_preferences_save_but_cannot_restart_an_unlicensed_overlay
    calls = []
    overlay = Object.new
    overlay.define_singleton_method(:start) { |*args| calls << args }
    host = preferences_host(overlay)

    save_preferences_through(host) { L.reset!; L.state = L::NOT_LICENSED }

    assert_equal [[{ authorized: false }]], calls,
                 'saving Preferences hands start the refusal (which starts nothing), never an authorization'
    assert_equal 1, L.requested_ids.length, 'one silent lookup'
    assert_nil UI.last_messagebox_text, 'no message: Preferences stays quiet'
    saved = Sketchup.default_registry['ZB Smart Gizmo Pro']
    assert_equal 100, saved['gizmo_size'], 'the preferences themselves are still saved'
    assert_equal 'cm', saved['scale_input_unit']
    assert_equal false, saved['smart_scale_enabled']
    assert_equal 'x', saved['rotate_arrow_axis']
  end

  def test_preferences_restart_a_licensed_overlay_as_before
    [L::LICENSED, L::TRIAL].each do |state|
      calls = []
      overlay = Object.new
      overlay.define_singleton_method(:start) { |*args| calls << args }
      host = preferences_host(overlay)

      save_preferences_through(host) { L.reset!; L.state = state }

      assert_equal [[{ authorized: true }]], calls, "#{state}: the refresh still runs"
      assert_equal 1, L.requested_ids.length
    end
  end

  def test_preferences_with_no_overlay_never_consults_the_license
    host = preferences_host(nil)
    save_preferences_through(host) { L.reset!; L.state = L::NOT_LICENSED }
    assert_empty L.requested_ids
  end

  # -- Hiding never needs a license -----------------------------------------------

  def showing_overlay(calls)
    overlay = spy_overlay(calls)
    overlay.enabled = true
    overlay.display_authorized = true
    overlay
  end

  def test_toggling_off_hides_immediately_with_no_lookup_and_no_message
    [
      [L::LICENSED, {}], [L::TRIAL, {}], [L::NOT_LICENSED, {}], [L::EXPIRED, {}], [L::TRIAL_EXPIRED, {}],
      [99, { licensed: false }], [:nil_license, {}], [nil, { raises: RuntimeError.new('offline') }]
    ].each do |state, opts|
      overlay = showing_overlay([])
      Sketchup.active_model = FakeOverlayModel.new([overlay])
      UI.last_messagebox_text = nil

      lookups = lookups_during(state, **opts) { P.toggle_gizmo }

      refute overlay.enabled?, "#{state.inspect}: turning OFF must work immediately"
      assert_equal 0, lookups, 'turning OFF must not look the license up'
      assert_nil UI.last_messagebox_text, 'turning OFF must never show a message'
    end
  end

  def test_hide_gizmo_is_unconditional
    [[L::NOT_LICENSED, {}], [nil, { raises: RuntimeError.new('offline') }]].each do |state, opts|
      overlay = showing_overlay([])
      Sketchup.active_model = FakeOverlayModel.new([overlay])

      lookups = lookups_during(state, **opts) { P.hide_gizmo }

      refute overlay.enabled?
      assert_equal 0, lookups
      assert_nil UI.last_messagebox_text
    end
    assert_nil P.hide_gizmo(nil), 'no model: nothing to hide, nothing raised'
  end

  def test_the_hide_menu_item_hides_immediately_with_no_lookup_and_no_message
    [[L::NOT_LICENSED, {}], [L::EXPIRED, {}], [nil, { raises: RuntimeError.new('offline') }], [L::LICENSED, {}]].each do |state, opts|
      @model = Sketchup::Model.new
      overlay = showing_overlay([])
      model = FakeOverlayModel.new([overlay])
      Sketchup.active_model = model
      menu = menu_for(overlay)
      UI.last_messagebox_text = nil

      lookups = lookups_during(state, **opts) { menu.items['Hide'].call }

      refute overlay.enabled?, "#{state.inspect}: Hide must always work"
      assert_equal 0, lookups, 'Hide must not look the license up'
      assert_nil UI.last_messagebox_text, 'Hide must never show a message'
      assert_equal 1, model.tools.popped, 'Hide still leaves the gizmo tool as before'
    end
  end

  def test_hiding_cancels_pending_activation_retries_so_the_gizmo_stays_hidden
    calls = []
    overlay = spy_overlay(calls)
    model = FakeOverlayModel.new([overlay])
    Sketchup.active_model = model
    observer = build_observer

    with_observer(observer) do
      TestLicense.with_state(L::LICENSED) do
        observer.attach_observers(model) # a licensed cycle: enabled, four retries pending
        assert overlay.enabled?
        starts_before = calls.count { |call| call.first == :start }

        P.toggle_gizmo # showing -> hides, cancelling the pending retries

        refute overlay.enabled?
        UI.timer_blocks.each(&:call)
        refute overlay.enabled?, 'a retry from the earlier cycle must not switch the hidden gizmo back on'
        assert_equal starts_before, calls.count { |call| call.first == :start }
      end
    end
  end

  def test_only_turning_on_needs_a_license_and_a_refused_on_leaves_it_off
    overlay = spy_overlay([])
    Sketchup.active_model = FakeOverlayModel.new([overlay])

    TestLicense.unlicensed { P.toggle_gizmo }

    assert_equal NOT_LICENSED_MESSAGE, UI.last_messagebox_text
    refute overlay.enabled?
    refute overlay.display_authorized?
  end

  # -- SketchUp's own Overlays panel -----------------------------------------------

  def draw_recorder(overlay)
    draws = []
    TestHarness.gizmo_of(overlay).define_singleton_method(:draw) { |view| draws << view }
    draws
  end

  def test_an_unlicensed_native_overlay_enable_draws_nothing
    overlay = gesture_overlay(TestFixtures.group_box, authorized: false)
    draws = draw_recorder(overlay)
    lookups = nil

    TestLicense.unlicensed do
      overlay.start # SketchUp's own Overlays panel starting the overlay
      40.times { overlay.draw(@model.active_view) }
      lookups = L.requested_ids.length
    end

    assert_empty draws, 'no gizmo graphics may be drawn for an unlicensed overlay'
    refute overlay.display_authorized?
    assert_equal 1, lookups, 'start makes one silent lookup; draw never asks SketchUp'
    assert_nil UI.last_messagebox_text, 'silent: no message'
  end

  def test_a_never_authorized_overlay_draws_nothing_even_before_any_start
    overlay = gesture_overlay(TestFixtures.group_box, authorized: false)
    draws = draw_recorder(overlay)
    overlay.instance_variable_set(:@display_authorized, nil)

    lookups = lookups_during(L::LICENSED) { 10.times { overlay.draw(@model.active_view) } }

    assert_empty draws
    assert_equal 0, lookups
  end

  def test_an_authorized_overlay_draws_and_draw_never_calls_the_license_api
    overlay = gesture_overlay(TestFixtures.group_box, authorized: true)
    draws = draw_recorder(overlay)

    lookups = lookups_during(L::LICENSED) { 25.times { overlay.draw(@model.active_view) } }

    assert_equal 25, draws.length
    assert_equal 0, lookups, 'draw must not call Sketchup::Licensing, even 25 frames in a row'
  end

  def test_a_lapsed_license_stops_the_next_activation_cycle_drawing
    overlay = gesture_overlay(TestFixtures.group_box, authorized: true)
    draws = draw_recorder(overlay)
    model = FakeOverlayModel.new([overlay])
    observer = build_observer

    TestLicense.unlicensed { observer.scene_changed(model) }
    overlay.draw(@model.active_view)

    refute overlay.display_authorized?
    assert_empty draws, 'the cycle result (false) is what draw follows'
  end

  def test_an_unauthorized_overlay_is_inert_for_mouse_keys_and_the_gizmo_menu
    overlay = gesture_overlay(TestFixtures.group_box, authorized: false)
    gizmo = TestHarness.gizmo_of(overlay)
    downs = []
    gizmo.define_singleton_method(:prepick?) { |*| true }
    gizmo.define_singleton_method(:mouse_over?) { true }
    gizmo.define_singleton_method(:tooltip) { 'Move' }
    gizmo.define_singleton_method(:onMouseMove) { |*| true }
    gizmo.define_singleton_method(:onLButtonDown) { |*args| downs << args; true }
    menu = FakeMenu.new
    menu_shown = nil

    lookups = lookups_during do
      overlay.onMouseMove(0, 5, 5, @model.active_view)
      overlay.onMouseEnter(0, 6, 6, @model.active_view)
      overlay.onLButtonDown(0, 5, 5, @model.active_view)
      overlay.onKeyDown(0x25, 1, 0, @model.active_view)
      menu_shown = overlay.getMenu(menu, 0, 5, 5, @model.active_view)
    end

    assert_empty downs, 'an invisible gizmo must not react to a click'
    assert_equal false, menu_shown
    assert_empty menu.items
    assert_equal 0, lookups, 'inert means no license lookups at all'
    assert_nil UI.last_messagebox_text, 'and no message: an invisible gizmo cannot nag'
  end

  def test_an_unauthorized_overlay_never_leaves_itself_on_the_tool_stack
    overlay = gesture_overlay(TestFixtures.group_box, authorized: false)
    model = FakeOverlayModel.new([overlay])
    overlay.instance_variable_set(:@model, model)
    overlay.instance_variable_set(:@tool_active, true)

    overlay.onMouseMove(0, 5, 5, @model.active_view)

    assert_equal 1, model.tools.popped
  end

  def test_a_later_valid_toolbar_activation_succeeds_after_an_unlicensed_native_enable
    overlay = gesture_overlay(TestFixtures.group_box, authorized: false) # enabled by SketchUp, refused by start
    draws = draw_recorder(overlay)
    starts = []
    overlay.define_singleton_method(:start) do |_model = nil, authorized: nil|
      starts << authorized
      self.display_authorized = authorized == true
    end
    Sketchup.active_model = FakeOverlayModel.new([overlay])
    overlay.draw(@model.active_view)
    assert_empty draws, 'nothing is visible while unauthorized'

    lookups = nil
    TestLicense.with_state(L::LICENSED) do # the license has become valid since
      P.toggle_gizmo
      lookups = L.requested_ids.length
    end

    assert_nil UI.last_messagebox_text
    assert_equal [true], starts, 'the explicit activation authorizes and starts the overlay'
    assert overlay.display_authorized?
    assert_equal 1, lookups, 'a fresh check, made once'
    overlay.draw(@model.active_view)
    assert_equal 1, draws.length, 'and the gizmo is visible again'
  end

  # -- One silent lookup per observer activation cycle -------------------------------

  def test_one_silent_lookup_per_observer_cycle_including_every_retry
    %i[attach_observers scene_changed].each do |entry|
      calls = []
      overlay = spy_overlay(calls)
      model = FakeOverlayModel.new([overlay])
      UI.timer_blocks = []
      lookups = nil
      retry_starts = nil

      TestLicense.with_state(L::LICENSED) do
        build_observer.public_send(entry, model)
        assert_equal 4, UI.timer_blocks.length, "#{entry}: the four retries are scheduled"
        UI.timer_blocks.each(&:call)
        lookups = L.requested_ids.length
        retry_starts = calls.select { |call| call.first == :start }
      end

      assert_equal 1, lookups, "#{entry}: the whole cycle, retries included, costs one lookup"
      assert_equal 5, retry_starts.length, "#{entry}: one immediate start and four retries"
      assert(retry_starts.all? { |call| call.last == true }, 'each start carries the cycle boolean, not a license object')
    end
  end

  def test_an_unauthorized_cycle_costs_one_lookup_and_schedules_nothing
    calls = []
    overlay = spy_overlay(calls)
    model = FakeOverlayModel.new([overlay])

    lookups = lookups_during(L::NOT_LICENSED) { build_observer.scene_changed(model) }

    assert_equal 1, lookups
    assert_empty UI.started_timers
    assert_empty calls
  end

  def test_a_changed_license_is_recognized_by_the_next_cycle
    calls = []
    overlay = spy_overlay(calls)
    model = FakeOverlayModel.new([overlay])
    observer = build_observer
    L.reset!

    L.state = L::LICENSED
    observer.scene_changed(model)
    assert overlay.display_authorized?

    L.state = L::NOT_LICENSED
    observer.scene_changed(model)
    refute overlay.display_authorized?, 'the lapse is recognized on the next cycle'

    L.state = L::TRIAL
    observer.scene_changed(model)
    assert overlay.display_authorized?, 'and so is a license that has returned'

    assert_equal 3, L.requested_ids.length
    assert_equal 3, L.issued.map(&:object_id).uniq.length, 'each cycle received its own license object'
  end

  def test_the_cycle_boolean_is_the_only_thing_carried_between_lookup_and_retries
    observer = build_observer
    observer.scene_changed(FakeOverlayModel.new([spy_overlay([])]))
    (observer.instance_variables - %i[@observed_models @activation_generations @app_observer @frame_change_observer]).each do |name|
      value = observer.instance_variable_get(name)
      refute_kind_of Sketchup::Licensing::ExtensionLicense, value
      refute_kind_of Zbellbound::SmartGizmoPro::Licensing::Result, value
    end
    assert_empty Zbellbound::SmartGizmoPro::Licensing.instance_variables
  end

  # -- Explicit activation and every mutation still ask afresh ------------------------

  def test_each_explicit_activation_and_each_mutation_asks_sketchup_afresh
    group = TestFixtures.group_box
    overlay = gesture_overlay(group, authorized: false)
    overlay.enabled = false
    overlay.define_singleton_method(:start) do |_model = nil, authorized: nil|
      self.display_authorized = authorized == true
    end
    Sketchup.active_model = FakeOverlayModel.new([overlay])
    step = Geom::Transformation.translation(Geom::Vector3d.new(0, 0, 250.mm))
    L.reset!

    L.state = L::NOT_LICENSED
    P.toggle_gizmo # 1: refused activation
    refute overlay.display_authorized?
    L.state = L::LICENSED
    P.toggle_gizmo # 2: activation now succeeds
    assert overlay.display_authorized?
    L.state = L::NOT_LICENSED
    overlay.perform_copy_array(step, 1) # 3: refused mutation
    L.state = L::LICENSED
    overlay.perform_copy_array(step, 1) # 4: allowed mutation
    L.state = L::EXPIRED
    overlay.perform_copy_array(step, 1) # 5: refused again -- the license lapsed since the last one

    assert_equal 5, L.requested_ids.length, 'every explicit activation and every mutation asks SketchUp'
    assert_equal 5, L.issued.map(&:object_id).uniq.length, 'and each receives a brand-new license object'
    assert_equal [:start, :commit], @model.operation_log.map(&:first), 'only the allowed mutation opened an operation'
  end

  # -- Preferences persistence is untouched -------------------------------------

  def test_licensing_never_reads_or_writes_a_preference
    before = Sketchup.default_registry.map { |section, keys| [section, keys.dup] }.to_h
    TestLicense.unlicensed do
      Licensing.check
      Licensing.allowed?
      Licensing.authorize
      build_observer.activate_overlay(FakeOverlayModel.new, spy_overlay([]))
    end
    assert_equal before, Sketchup.default_registry.map { |section, keys| [section, keys.dup] }.to_h
  end

  def test_the_ruby_console_stays_quiet_through_every_gated_route
    out, err = capture_io do
      [L::LICENSED, L::NOT_LICENSED, L::EXPIRED, L::TRIAL_EXPIRED].each do |state|
        calls = []
        overlay = spy_overlay(calls)
        model = FakeOverlayModel.new([overlay])
        Sketchup.active_model = model
        TestLicense.with_state(state) do
          build_observer.attach_observers(model)
          build_observer.scene_changed(model)
          P.toggle_gizmo
        end
      end
    end
    assert_empty out
    assert_empty err
  end
end
