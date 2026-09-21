# Copyright Peter Zbel - Zbellbound.com
# ZB Smart Gizmo Pro

module Zbellbound::SmartGizmoPro
  # The toolbar button and the Extensions-menu item both land here.
  #
  # OFF never needs a license: while the gizmo is showing (enabled AND
  # authorized), a click just hides it -- immediately, with no license lookup
  # and no message. Only turning the gizmo ON is a user-initiated activation,
  # and that gets a fresh, VISIBLE license check every time; the boolean it
  # returns is handed on to the activation below, so one click costs one
  # lookup. A refusal explains why and keeps the gizmo inactive.
  def self.toggle_gizmo
    model = Sketchup.active_model
    return unless model

    overlay = PLUGIN.active_overlay(model)
    if overlay&.enabled? && overlay.display_authorized?
      PLUGIN.hide_gizmo(model)
      return
    end

    unless Licensing.authorize
      if overlay
        overlay.display_authorized = false
        overlay.enabled = false if overlay.enabled?
      end
      model.active_view.invalidate if model.active_view
      return
    end

    observer = PLUGIN.respond_to?(:observer) ? PLUGIN.observer : nil
    observer&.attach_observers(model, authorized: true)
    overlay = PLUGIN.active_overlay(model)
    unless overlay
      observer&.recreate_overlay(model, authorized: true)
      overlay = PLUGIN.active_overlay(model)
      return unless overlay
    end

    unless overlay.enabled? && overlay.display_authorized?
      if observer
        observer.activate_overlay(model, overlay, authorized: true)
      else
        overlay.enabled = true
        overlay.start(authorized: true)
      end
    end
    model.active_view.invalidate if model.active_view
  end

  # Hides the gizmo. Unconditional by design: no license lookup, no message --
  # the toolbar/menu toggle (when the gizmo is showing) and the gizmo's own
  # context-menu Hide command both use this. Any activation retry still
  # pending from an earlier observer cycle is cancelled so it cannot switch
  # the gizmo straight back on.
  def self.hide_gizmo(model = Sketchup.active_model)
    return unless model

    PLUGIN.observer&.cancel_pending_activation(model) if PLUGIN.respond_to?(:observer)
    overlay = PLUGIN.active_overlay(model)
    overlay.enabled = false if overlay&.enabled?
    model.active_view.invalidate if model.active_view
  end

  def self.active_overlay(model = Sketchup.active_model)
    return unless model.respond_to?(:overlays)

    overlay = model.overlays.find { |o| o.is_a?(Zbellbound::SmartGizmoPro::GizmoOverlay) }

    overlay
  end

  class SmartScaleGestureState
    attr_reader :entity, :axis_id, :profile, :reference_length, :vertex_entries,
                :instance_entries, :mask, :ratio, :mode, :original_entity_transformation,
                :anchor_point, :gizmo_transformation, :root_to_solver_transformation

    def initialize(entity:, axis_id:, profile:, reference_length:, vertex_entries:, instance_entries:, mask:,
                   mode: :frame, original_entity_transformation: nil, anchor_point: nil, gizmo_transformation: nil,
                   root_to_solver_transformation: IDENTITY)
      @entity = entity
      @axis_id = axis_id
      @profile = profile
      @reference_length = reference_length
      @vertex_entries = vertex_entries.freeze
      @instance_entries = instance_entries.freeze
      @mask = mask
      @mode = mode
      @original_entity_transformation = original_entity_transformation
      @anchor_point = anchor_point
      @gizmo_transformation = gizmo_transformation
      @root_to_solver_transformation = root_to_solver_transformation
      @ratio = 1.0
    end

    def valid?
      return false unless @entity&.valid?

      vertex_entries.all? { |entry| entry[:vertex].valid? } &&
        instance_entries.all? do |entry|
          entry[:instance].valid? &&
            (!entry[:nested_state] || entry[:nested_state].valid?)
        end
    end

    def matches?(entity, axis_id, mask)
      @entity == entity && @axis_id == axis_id && @mask == mask
    end

    def restore!
      if original_entity_transformation && @entity&.valid?
        @entity.transformation = original_entity_transformation
      end

      entity_vertex_map = Hash.new { |hash, key| hash[key] = { vertices: [], vectors: [] } }

      vertex_entries.each do |entry|
        next unless entry[:vertex].valid?

        current_local = entry[:vertex].position
        target_local = entry[:original_local_point]
        next if current_local == target_local

        entity_vertex_map[entry[:entities]][:vertices] << entry[:vertex]
        entity_vertex_map[entry[:entities]][:vectors] << current_local.vector_to(target_local)
      end

      entity_vertex_map.each do |entities, payload|
        next if payload[:vertices].empty?

        entities.transform_by_vectors(payload[:vertices], payload[:vectors])
      end

      instance_entries.each do |entry|
        entry[:nested_state]&.restore!
        next unless entry[:instance].valid?

        entry[:instance].transformation = entry[:original_transformation]
      end

      @ratio = 1.0
      true
    end

    def ratio=(value)
      @ratio = value.to_f
    end
  end

  module SmartScaleApplier
    module_function

    # Minimum size of the inner stretch zone after scaling, in inches.
    # Previously 0.1mm — far too small to be a meaningful guard against
    # the user collapsing the body to a near-zero sliver. Raised to 5mm
    # as an absolute floor, plus a separate percentage floor in
    # minimum_ratio_for ensures the inner zone never collapses below 5%
    # of its original size, whichever is larger.
    MIN_INNER_OPENING = 5.mm.to_f
    MIN_INNER_RETENTION = 0.05

    def minimum_ratio_for(state)
      return -Float::INFINITY if state.mode == :basic

      profile = state.profile
      old_outer = profile[:max] - profile[:min]
      old_inner = profile[:inner_max] - profile[:inner_min]
      return 1.0 unless old_outer > 0 && old_inner >= 0

      # The inner stretch zone must remain at least MIN_INNER_OPENING wide
      # OR MIN_INNER_RETENTION fraction of its original width, whichever
      # is larger. Without this, users could squash the table body to
      # nothing while the legs collide.
      min_inner = [MIN_INNER_OPENING, old_inner * MIN_INNER_RETENTION].max
      min_ratio = ((old_outer - old_inner) + min_inner) / old_outer.to_f
      min_ratio.positive? ? min_ratio : (min_inner / old_outer.to_f)
    end

    def normalize_ratio(state, ratio)
      factor = ratio.to_f
      return nil unless factor.finite?
      return factor unless state.mode == :frame

      [factor, minimum_ratio_for(state)].max
    end

    def apply!(overlay, state, ratio)
      return false unless state&.valid?

      ratio = normalize_ratio(state, ratio)
      return false unless ratio && ratio.finite?
      return false if state.mode == :basic && ratio == 0.0
      return false unless ratio.positive? || state.mode == :basic

      state.restore!

      if state.mode == :basic
        data = [:scale, nil, ratio, state.mask, state.reference_length, state.anchor_point, state.gizmo_transformation]
        tr = overlay.scale_transformation(state.mask, ratio, data)
        state.entity.transformation = tr * state.original_entity_transformation
        overlay.invalidate_smart_scale_bounds(state)
        state.ratio = ratio
        return true
      end

      profile = state.profile
      old_outer = profile[:max] - profile[:min]
      old_inner = profile[:inner_max] - profile[:inner_min]
      return false unless old_outer > 0 && old_inner > 0

      new_outer = old_outer * ratio
      delta = new_outer - old_outer
      new_inner = old_inner + delta
      return false if new_inner <= 0

      stretch_factor = new_inner / old_inner.to_f
      entity_vertex_map = Hash.new { |hash, key| hash[key] = { vertices: [], vectors: [] } }

      state.vertex_entries.each do |entry|
        next unless entry[:vertex].valid?

        value = overlay.point_axis_value(entry[:original_root_point], state.axis_id)
        new_value = if value <= profile[:inner_min]
          value
        elsif value >= profile[:inner_max]
          value + delta
        else
          offset = value - profile[:inner_min]
          profile[:inner_min] + ((offset / old_inner.to_f) * new_inner)
        end

        target_root = overlay.point_with_axis_value(entry[:original_root_point], state.axis_id, new_value)
        target_local = overlay.transform_solver_point_to_root(target_root, state.root_to_solver_transformation)
        current_local = entry[:vertex].position
        next if current_local == target_local

        entity_vertex_map[entry[:entities]][:vertices] << entry[:vertex]
        entity_vertex_map[entry[:entities]][:vectors] << current_local.vector_to(target_local)
      end

      entity_vertex_map.each do |entities, payload|
        next if payload[:vertices].empty?

        entities.transform_by_vectors(payload[:vertices], payload[:vectors])
      end

      state.instance_entries.each do |entry|
        next unless entry[:instance].valid?

        final_tr = entry[:original_transformation]
        case entry[:kind]
        when :left
          # Keep original transformation.
        when :right
          vector = case state.axis_id
                   when :x then Geom::Vector3d.new(delta, 0, 0)
                   when :y then Geom::Vector3d.new(0, delta, 0)
                   when :z then Geom::Vector3d.new(0, 0, delta)
                   end
          solver_tr = Geom::Transformation.translation(vector)
          root_tr = overlay.transform_solver_transformation_to_root(solver_tr, state.root_to_solver_transformation)
          local_tr = overlay.transform_root_transformation_to_local(root_tr, entry[:path] || [])
          final_tr = local_tr * entry[:original_transformation]
        when :middle
          origin = case state.axis_id
                   when :x then Geom::Point3d.new(profile[:inner_min], 0, 0)
                   when :y then Geom::Point3d.new(0, profile[:inner_min], 0)
                   when :z then Geom::Point3d.new(0, 0, profile[:inner_min])
                   end
          solver_tr = Geom::Transformation.scaling(
            origin,
            state.axis_id == :x ? stretch_factor : 1.0,
            state.axis_id == :y ? stretch_factor : 1.0,
            state.axis_id == :z ? stretch_factor : 1.0
          )
          root_tr = overlay.transform_solver_transformation_to_root(solver_tr, state.root_to_solver_transformation)
          local_tr = overlay.transform_root_transformation_to_local(root_tr, entry[:path] || [])
          final_tr = local_tr * entry[:original_transformation]
        when :full_span
          if entry[:nested_state]
            return false unless apply!(overlay, entry[:nested_state], ratio)
          else
            origin = case state.axis_id
                     when :x then Geom::Point3d.new(profile[:min], 0, 0)
                     when :y then Geom::Point3d.new(0, profile[:min], 0)
                     when :z then Geom::Point3d.new(0, 0, profile[:min])
                     end
            solver_tr = Geom::Transformation.scaling(
              origin,
              state.axis_id == :x ? ratio : 1.0,
              state.axis_id == :y ? ratio : 1.0,
              state.axis_id == :z ? ratio : 1.0
            )
            root_tr = overlay.transform_solver_transformation_to_root(solver_tr, state.root_to_solver_transformation)
            local_tr = overlay.transform_root_transformation_to_local(root_tr, entry[:path] || [])
            final_tr = local_tr * entry[:original_transformation]
          end
        else
          return false
        end

        entry[:instance].transformation = final_tr unless entry[:nested_state]
      end

      overlay.invalidate_smart_scale_bounds(state)
      state.ratio = ratio
      true
    end
  end

  class GizmoOverlay < Sketchup::Overlay
    include ShapeGeom

    LEFT_ARROW_KEY = defined?(VK_LEFT) ? VK_LEFT : 37
    UP_ARROW_KEY = defined?(VK_UP) ? VK_UP : 38
    RIGHT_ARROW_KEY = defined?(VK_RIGHT) ? VK_RIGHT : 39
    DOWN_ARROW_KEY = defined?(VK_DOWN) ? VK_DOWN : 40
    MOVE_TOOL_KEY = 'M'.ord

    MOVE_MODE_LABEL = 'Move'.freeze
    COPY_MODE_LABEL = 'Copy'.freeze
    COPY_ARRAY_MAX_COPIES = 1000
    COPY_ARRAY_COUNT_PATTERN = /\A\s*(\d+)\s*\z/

    # Ctrl-drag internal array: typed into the same Measurements box as an
    # ordinary re-edit distance right after a Ctrl-drag copy, so it must be
    # told apart from a plain distance by shape alone -- a leading or
    # trailing "/" around a whole number, e.g. "/3" or "3/". Two patterns
    # (rather than one with alternation) keep each capture group unambiguous.
    CTRL_DRAG_ARRAY_SLASH_PREFIX_PATTERN = /\A\/\s*(\d+)\s*\z/
    CTRL_DRAG_ARRAY_SLASH_SUFFIX_PATTERN = /\A(\d+)\s*\/\z/

    # Ctrl-drag external array: same Measurements box, same moment, but an
    # "x"/"X" prefix or suffix instead of "/" -- matches SketchUp's own
    # documented external-array (extend-by-repeating) input convention.
    # Case-insensitive so "x3", "X3", "3x", "3X" are all accepted.
    CTRL_DRAG_ARRAY_X_PREFIX_PATTERN = /\A[xX]\s*(\d+)\s*\z/
    CTRL_DRAG_ARRAY_X_SUFFIX_PATTERN = /\A(\d+)\s*[xX]\s*\z/

    # Scale division: typed into the Scale popup/re-edit box (never the
    # Ctrl-drag Measurements box -- that's CTRL_DRAG_ARRAY_SLASH_* above,
    # a completely separate feature/parser). Prefix-only ("/2"), unlike
    # the Ctrl-drag array's "/N or N/", to keep the two "/"-syntaxes
    # visually and behaviorally distinct. Allows a decimal divisor
    # (e.g. "/2.5") since this is a plain arithmetic division of a
    # continuous dimension, not a whole-number copy count.
    SCALE_DIVISION_PATTERN = /\A\/\s*(\d+(?:\.\d+)?)\s*\z/

    # Scale multiplication: same Scale popup/re-edit box as SCALE_
    # DIVISION_PATTERN above, same "/2" companion syntax but with "x"/"X"
    # instead of "/". Deliberately PREFIX-ONLY ("x2"/"X2", not "2x") --
    # unlike CTRL_DRAG_ARRAY_X_PREFIX_PATTERN/_SUFFIX_PATTERN above, which
    # accept both orders for the *Move* Ctrl-drag external-array feature.
    # This is an intentionally different, narrower contract for Scale:
    # "2x" was never a Scale convention and isn't added here. Allows a
    # decimal multiplier (e.g. "x1.5") for the same reason "/2.5" is
    # allowed above -- a continuous-dimension multiply, not a copy count.
    # Parsed only where Scale re-edit text is handled (parse_scale_user_
    # text, parse_smart_scale_ratio) -- never where Ctrl-drag Move array
    # text is handled (@ctrl_array_session's parse_ctrl_drag_external_
    # array_count), so "x2" means "multiply the Scale dimension" in
    # Scale context and "create an external copy array" in Move context,
    # decided purely by which code path is reading the text, with no
    # shared mutable state between the two.
    SCALE_MULTIPLICATION_PATTERN = /\A[xX]\s*(\d+(?:\.\d+)?)\s*\z/

    # Scale's dimension display shows a bare number, no unit suffix --
    # see format_scale_display/strip_scale_display_unit_suffix. These
    # map the model's current Length::* unit (documented on
    # ruby.sketchup.com/Length.html) to the exact trailing text
    # Sketchup.format_length appends for it in Decimal format, so the
    # strip is an exact, known-suffix match rather than a blanket
    # "delete trailing letters". Architectural/Engineering/Fractional
    # formats (feet and inches composed together, e.g. `5' - 6"`) have
    # no single clean trailing token and are deliberately left alone --
    # see strip_scale_display_unit_suffix.
    SCALE_DISPLAY_UNIT_SUFFIX_BY_LENGTH_UNIT = {
      Length::Millimeter => 'mm',
      Length::Centimeter => 'cm',
      Length::Meter => 'm',
      Length::Inches => '"',
      Length::Feet => "'"
    }.freeze

    attr_reader :id, :name, :mouse, :flags
    attr_accessor :active_gizmo

    def initialize
      @id = OVERLAY_ID
      @name = PLUGIN_NAME

      @mouse = [0.0, 0.0]
      @current_tool_name = nil
      @custom_origin = nil
      @last_rotate_axis_id = :z
      @native_tool_override = false
      @needs_gizmo_refresh = false
      @refresh_timer_pending = false
      @refresh_generation = 0
      @tool_active = false
      super(@id, @name)

      refresh_context
    end 

    def bind_model(model)
      return unless model

      @host_model = model
      refresh_context(model)
    end

    def active_gizmo?
      return false if @native_tool_override

      return true if @gizmo&.active?
      return false unless selection_present?

      @active_gizmo || active_itself?
    end

    def description
      OVERLAY_DESCRIPTION
    end

    def active_itself?
      @tool_active == true
    end

    def selection_present?
      @selection && @selection.length > 0
    end

    def gizmo_allowed_for_tool?(tool_name = @current_tool_name)
      tool = tool_name.to_s
      return true if tool.empty?
      return true if active_itself?
      return true if tool == @name
      return true if tool == @id
      return true if tool == self.class.name
      return true if tool == self.class.name.split('::').last

      %w[SelectionTool CameraOrbitTool].include?(tool)
    end

    def refresh_active_gizmo_state
      self.active_gizmo = enabled? && selection_present? && gizmo_allowed_for_tool?
    end

    def edited?
      @last_transform
    end

    def onMouseMove(flags, x, y, view)
      return if inert?
      return if @mouse && @mouse == [x, y]
      return if @native_tool_override
      
      @flags = flags
      @mouse = [x, y]
      return unless enabled?
      return unless active_gizmo? || @gizmo&.active?
      sync_gizmo_refresh
      return unless @gizmo

      handled = false
      if @gizmo.active?
        handled = @gizmo.onMouseMove(flags, x, y, view)
      elsif active_gizmo?
        # Delay for onUserText
        if active_itself? && edited? && (@edit_mouse && @edit_mouse.distance(@mouse) < 10)
          # Do nothing
        else
          handled = @gizmo.onMouseMove(flags, x, y, view)
        end
      end

      tooltip = @gizmo.tooltip
      view.tooltip = tooltip unless tooltip.empty?

      @copy = flags & COPY_MODIFIER_MASK == COPY_MODIFIER_MASK

      if !active_itself?
        @model.tools.push_tool(self) if handled || @gizmo.active? || @gizmo.mouse_over? || @gizmo.prepick?(x, y, view)
      else
        button_down = flags & MK_LBUTTON == MK_LBUTTON
        keep_active = @gizmo.mouse_over? || @gizmo.prepick?(x, y, view) || edited?
        @model.tools.pop_tool unless button_down || @gizmo.active? || keep_active
      end
    rescue StandardError => e
      warn_overlay_issue('handle mouse move', e)
      @model.tools.pop_tool if active_itself?
    end

    def onLButtonDown(flags, x, y, view)
      return if inert?
      return if @native_tool_override

      @flags = flags
      @mouse = [x, y]
      return unless active_gizmo? || active_itself? || @gizmo&.active?
      sync_gizmo_refresh
      prepick = @gizmo.prepick?(x, y, view)
      unless active_gizmo? || prepick
        # The overlay is on the tool stack but the click is neither on a
        # valid gizmo target nor near the gizmo. Without this fallback the
        # click would be swallowed entirely and the user would have to
        # manually switch to the Select tool to pick a new object.
        # Behave like the Select tool: pick the entity under the cursor
        # (or clear on background click), then pop ourselves off the stack
        # so subsequent clicks route to the native Select tool normally.
        if active_itself?
          handle_non_gizmo_selection_click(flags, x, y, view)
          @model.tools.pop_tool
        end
        return
      end

      # First meaningful gizmo interaction: a fresh, visible license check
      # before any gizmo gesture (drag, handle click, pivot drag) can begin.
      # This is the only mouse route into the manipulator, so SketchUp's own
      # Overlay controls cannot bypass it; passive mouse moves never reach
      # here. A refusal explains why and stops the gesture before it starts.
      return unless @gizmo.active? || license_permits_interaction?

      handled = @gizmo.onLButtonDown(flags, x, y, view)
      if !handled && active_itself? && !@gizmo.active? && !prepick
        handle_non_gizmo_selection_click(flags, x, y, view)
        return
      end

      @edit_mouse = nil if handled
      if handled && @gizmo.active? && !active_itself?
        @model.tools.push_tool(self)
      end
      self.active_gizmo = true if handled && @gizmo.active?
    end

    def onLButtonUp(flags, x, y, view)
      return if @native_tool_override

      @flags = flags
      @mouse = [x, y]
      @copy = flags & COPY_MODIFIER_MASK == COPY_MODIFIER_MASK

      @gizmo.onLButtonUp(flags, x, y, view) if active_gizmo? || @gizmo.active?
    end
      
    def update_ui
      return unless active_gizmo?

      if rotate_edit_active?
        Sketchup.set_status_text('Rotate edit: type an angle in Measurements, or use Left/Right/Up/Down for the configured angle presets.')
      else
        Sketchup.set_status_text('Click handles to transform. Drag plane squares for two-axis moves, drag the center dot to move the pivot, and use Measurements for exact values.')
      end
    end

    def onMouseEnter(*args)
      return if inert?
      return unless enabled?
      return if @native_tool_override
      return unless active_gizmo?
      return if active_itself?

      flags, x, y, view = args

      @mouse = [x, y]
      @flags = flags
      sync_gizmo_refresh
      @model.tools.push_tool(self) if @gizmo && @gizmo.prepick?(x, y, view)
    end

    def onMouseLeave(_view); end
    
    def tool_changed(tool_name)
      return unless enabled?

      @current_tool_name = tool_name
      @native_tool_override = !gizmo_allowed_for_tool?(tool_name)

      if @native_tool_override
        self.active_gizmo = false
        @model.tools.pop_tool if active_itself?
      else
        refresh_active_gizmo_state
        @active_gizmo = true if active_itself?
      end

      @model.active_view.invalidate
    end

    def selection_changed(selection)
      @selection = selection if selection
      @refresh_generation += 1
      clear_edit_state
      clear_custom_origin
      schedule_gizmo_refresh
      refresh_active_gizmo_state
      result = nil
      result = sync_gizmo_refresh unless @gizmo&.active?
      queue_gizmo_refresh unless valid_gizmo_refresh_result?(result)
      queue_followup_gizmo_refresh(0.05, @refresh_generation)
      queue_followup_gizmo_refresh(0.15, @refresh_generation)
      @model.tools.pop_tool if active_itself? && !selection_present?
      @model.active_view.invalidate
    end

    def clear_edit_state
      @last_transform = nil
      @last_smart_scale_session = nil
      @edit_mouse = nil

      # A selection-changed notification can be an echo of the Ctrl-drag
      # array feature's own last @selection.clear/@selection.add call
      # (e.g. if SketchUp delivers it on a later tick instead of
      # synchronously) rather than a genuine new selection. Only close the
      # array-input window when the current selection no longer matches
      # what that call itself produced -- see build_ctrl_drag_array_session.
      if @ctrl_array_session && !ctrl_drag_selection_matches?(@selection&.to_a, @ctrl_array_session[:expected_selection])
        @ctrl_array_session = nil
      end

      reset_smart_scale_session
      reset_smart_scale_gesture
    end

    def warn_overlay_issue(action, error)
      return unless DEBUG_MODE

      details = +"[ZB Smart Gizmo Pro] Could not #{action}: #{error.class}: #{error.message}"
      if error.backtrace && !error.backtrace.empty?
        details << "\n"
        details << error.backtrace.join("\n")
      end
      warn(details)
    end

    # Diagnostic for smart-scale drag attempts that couldn't be applied
    # (no usable frame/stretch profile, ratio out of range, etc). This is
    # an expected, non-error outcome -- the caller always falls through to
    # the regular scale transform afterwards -- so it only logs under
    # DEBUG_MODE, same as warn_overlay_issue.
    def smart_scale_log(message)
      return unless DEBUG_MODE

      warn("[ZB Smart Gizmo Pro] Smart Scale: #{message}")
    end

    def reset_smart_scale_gesture
      @smart_scale_gesture = nil
      @smart_scale_gesture_data = nil
      @smart_scale_gesture_states = nil
    end

    def activate_native_move_tool(view)
      clear_edit_state
      @native_tool_override = true
      self.active_gizmo = false
      @model.tools.pop_tool if active_itself?
      Sketchup.send_action('selectMoveTool:')
      view.invalidate
    end

    def schedule_gizmo_refresh
      @needs_gizmo_refresh = true
    end

    def queue_gizmo_refresh
      return if @refresh_timer_pending

      @refresh_timer_pending = true
      UI.start_timer(0, false) do
        @refresh_timer_pending = false
        sync_gizmo_refresh
        @model.active_view.invalidate if @model&.valid?
      end
    end

    def queue_followup_gizmo_refresh(delay, generation)
      UI.start_timer(delay, false) do
        next unless @model&.valid?
        next unless generation == @refresh_generation
        next if @gizmo&.active?

        schedule_gizmo_refresh
        sync_gizmo_refresh
        @model.active_view.invalidate if @model&.active_view
      end
    end

    def gizmo_hovering?(x = nil, y = nil, view = nil)
      return false unless enabled?
      return false if @native_tool_override
      return false unless @gizmo

      target_view = view || @model&.active_view
      return false unless target_view

      mx = x || @mouse&.[](0)
      my = y || @mouse&.[](1)

      hover = @gizmo.mouse_over?
      prepick = mx && my ? @gizmo.prepick?(mx, my, target_view) : false

      hover || prepick
    end

    def handle_non_gizmo_selection_click(flags, x, y, view)
      picked = picked_entity(x, y, view)
      if picked
        if selection_subtract_modifier?(flags)
          @selection.remove(picked) if @selection.contains?(picked)
        elsif selection_toggle_modifier?(flags)
          if @selection.contains?(picked)
            @selection.remove(picked)
          else
            @selection.add(picked)
          end
        elsif selection_add_modifier?(flags)
          @selection.add(picked) unless @selection.contains?(picked)
        else
          @selection.clear
          @selection.add(picked)
        end
      else
        clear_selection_from_background_click unless selection_modifier_active?(flags)
      end
    end

    def selection_add_modifier?(flags)
      flags & COPY_MODIFIER_MASK == COPY_MODIFIER_MASK
    end

    def selection_toggle_modifier?(flags)
      flags & CONSTRAIN_MODIFIER_MASK == CONSTRAIN_MODIFIER_MASK &&
        !selection_add_modifier?(flags)
    end

    def selection_subtract_modifier?(flags)
      flags & CONSTRAIN_MODIFIER_MASK == CONSTRAIN_MODIFIER_MASK &&
        selection_add_modifier?(flags)
    end

    def selection_modifier_active?(flags)
      selection_add_modifier?(flags) || selection_toggle_modifier?(flags) || selection_subtract_modifier?(flags)
    end

    def picked_entity(x, y, view)
      ph = view.pick_helper
      ph.do_pick(x, y)
      picked = ph.best_picked
      return nil unless picked

      return picked if picked.is_a?(Sketchup::Drawingelement)

      nil
    end

    def empty_background_click?(x, y, view)
      ph = view.pick_helper
      ph.do_pick(x, y)
      ph.best_picked.nil?
    end

    def clear_selection_from_background_click
      UI.start_timer(0, false) do
        next unless @model&.valid?
        next unless @selection && @selection.length > 0

        @selection.clear
        @model.active_view.invalidate if @model&.active_view
      end
    end

    def valid_gizmo_refresh_result?(result)
      result && !result[:invalid_selection_state]
    end

    def sync_gizmo_refresh
      return unless @needs_gizmo_refresh
      return if @gizmo&.active?

      refresh_context
      result = update_gizmo if @gizmo
      if valid_gizmo_refresh_result?(result)
        @needs_gizmo_refresh = false
      elsif selection_present?
        queue_gizmo_refresh
      end
      result
    end

    def gizmo_state_for_current_selection
      orientation = PLUGIN.gizmo_orientation

      if orientation == LOCAL_ORIENTATION && selected_one_object?
        object = @selection[0]
        tr = object.transformation
        bb = object.definition.bounds
        axes = [tr.origin, tr.xaxis, tr.yaxis, tr.zaxis]
      else

        bb = Geom::BoundingBox.new
        @model.selection.each do |entity|
          next if entity.respond_to?(:locked?) && entity.locked?

          bb.add(entity.bounds)
        end
        tr = IDENTITY
        axes = @model.axes.to_a
      end

      origin = if @custom_origin
        @custom_origin
      elsif bb.empty?
        # Bounds are empty (e.g. empty group/component just created).
        # Rather than returning invalid_selection_state and leaving the gizmo
        # stranded on the previously selected object, fall back to the object's
        # placement origin so the gizmo repositions immediately on the new
        # selection. In LOCAL mode use the object's transformation origin;
        # otherwise fall back to the model axes origin.
        if orientation == LOCAL_ORIENTATION && selected_one_object?
          @selection[0].transformation.origin
        else
          @model.axes.origin
        end
      else
        bb.center.transform(tr)
      end

      {
        invalid_selection_state: false,
        bounds: bb,
        transformation: tr,
        origin: origin,
        axes: axes,
        bounds_empty: bb.empty?,
        used_fallback_origin: bb.empty? && !@custom_origin
      }
    end

    def update_gizmo
      result = gizmo_state_for_current_selection
      return result if result[:invalid_selection_state]

      @gizmo.bounds = result[:bounds]
      @gizmo.transformation = result[:transformation]
      @gizmo.origin = result[:origin]
      @gizmo.xaxis = result[:axes][1]
      @gizmo.yaxis = result[:axes][2]
      @gizmo.zaxis = result[:axes][3]
      result
    end

    def selected_one_object?
      @selection.length == 1 &&
        (@selection[0].is_a?(Sketchup::Group) || @selection[0].is_a?(Sketchup::ComponentInstance))
    end

    def activate
      @tool_active = true
      reset
      refresh_context
      result = update_gizmo if @gizmo
      if result && result[:invalid_selection_state]
        schedule_gizmo_refresh
        queue_gizmo_refresh
      end
    end

    # @param [Sketchup::View] view
    def deactivate(_view)
      @tool_active = false
      reset
      stop
      # view.invalidate
    end

    # @param [Sketchup::View] view
    def suspend(view)
      @tool_active = false
      view.invalidate
    end

    # @param [Sketchup::View] view
    def resume(view)
      @tool_active = true
      view.invalidate
    end

    def reset
      @last_transform = nil
      @edit_mouse = nil
      @copy = false
      @ctrl_array_session = nil
    end

    def clear_custom_origin
      @custom_origin = nil
    end

    def set_custom_origin(point)
      return unless point

      @custom_origin = point.clone
      update_gizmo
      @model.active_view.invalidate
    end

    def set_pivot_to_selection_center
      clear_custom_origin
      update_gizmo
      @model.active_view.invalidate
    end

    def set_pivot_to_model_origin
      set_custom_origin(@model.axes.origin)
    end

    def set_pivot_to_object_origin
      return unless selected_one_object?

      set_custom_origin(@selection[0].transformation.origin)
    end

    def selected_entities
      @selection.to_a.find_all { |e| 
        !((e.is_a?(Sketchup::Group) || e.is_a?(Sketchup::ComponentInstance)) && e.locked?)
      }
    end

    # The single doorway for the license gate inside the overlay. Visible on
    # refusal (a plain message), fresh on every call, and only ever invoked
    # when an interaction is BEGINNING -- never from a passive mouse-move
    # frame, a draw, or an observer event.
    def license_permits_interaction?
      Licensing.authorize
    end

    # The single doorway to a model operation. Every path that changes the
    # model opens its Undo operation through here, so a refused license
    # leaves the model untouched and creates no Undo entry: the check runs
    # BEFORE start_operation, never after. Takes the same name and the same
    # next_transparent/transparent flags as Sketchup::Model#start_operation
    # (every operation of this extension disables the UI for performance, so
    # that flag is fixed); returns true when the operation was opened and
    # false when it was refused.
    def start_licensed_operation(name, next_transparent = false, transparent = false)
      return false unless license_permits_interaction?

      @model.start_operation(name, true, next_transparent, transparent)
      true
    end

    # The most recent SILENT authorization result, as a plain boolean (never a
    # license object). It is set by every start -- so an unlicensed overlay
    # that SketchUp's own Overlays panel switches on is refused here -- and it
    # is all draw and the passive mouse callbacks consult, so the graphics
    # never call Sketchup::Licensing. Until a start has authorized the overlay
    # it is not authorized: nothing is drawn.
    def display_authorized?
      @display_authorized == true
    end

    def display_authorized=(value)
      @display_authorized = value ? true : false
    end

    # An overlay that is not authorized is inert: it draws nothing, has no
    # hover, tooltip, tool push, key handling or gizmo menu, and never leaves
    # itself on the tool stack. Silent -- no lookup and no message.
    def inert?
      return false if display_authorized?

      @model.tools.pop_tool if @model && active_itself?
      true
    end

    # Starts (or refreshes) the overlay. `authorized` is the boolean result of
    # ONE silent license lookup made by the caller for a whole activation
    # cycle (observer events, retry timers, the toolbar command, Preferences)
    # and passed along for that cycle only. Called without it -- by SketchUp's
    # own Overlay controls -- start makes the one silent lookup itself and
    # silently refuses when unlicensed.
    def start(model = nil, authorized: nil)
      authorized = Licensing.allowed? if authorized.nil?
      self.display_authorized = authorized
      return unless display_authorized?

      refresh_context(model)

      # Always mark refresh needed so the followup timers below have work
      # to do when they fire. Without this, the synchronous update_gizmo
      # call could clear @needs_gizmo_refresh and cause the followups to
      # no-op even when the selection's bounds still aren't settled.
      schedule_gizmo_refresh
      result = update_gizmo

      # Schedule retry refreshes. When start runs from
      # observer.activate_overlay (model open, scene/page change), the
      # immediate update_gizmo above can fire before SketchUp has finished
      # applying the page's saved selection state or finished computing
      # the new entity's bounds — leaving the gizmo stuck at the old
      # position. Followups at 0.05s and 0.2s catch up once the selection
      # has settled.
      #
      # We deliberately do NOT bump @refresh_generation here. The observer
      # calls activate_overlay → start multiple times in rapid succession
      # (via queue_overlay_activation at 0.0/0.1/0.35/0.75s). If start
      # bumped the generation each time, every followup it scheduled
      # would be cancelled by the next start before it could run. The
      # generation is for cancelling followups when the SELECTION changes,
      # which is owned by selection_changed.
      queue_followup_gizmo_refresh(0.05, @refresh_generation)
      queue_followup_gizmo_refresh(0.2, @refresh_generation)

      if result && result[:invalid_selection_state]
        queue_gizmo_refresh
      end

      # Force a view repaint. update_gizmo above correctly repositions
      # @gizmo to the new selection, but on model open the viewport may
      # not naturally repaint right away — the gizmo is correct in
      # memory but the screen still shows the previous frame. Without
      # this invalidate, the user has to move the mouse over the
      # viewport to trigger a redraw, which looks like the gizmo is
      # "stuck" until they hover it.
      @model.active_view.invalidate if @model&.active_view
    end

    def refresh_context(model = nil)
      @model = model || @host_model || Sketchup.active_model
      return unless @model

      @selection = @model.selection
      @view = @model.active_view

      refresh_active_gizmo_state

      @axes = @model.axes.to_a
      if @gizmo.nil? || @gizmo_model_id != @model.object_id
        @gizmo_model_id = @model.object_id
        @gizmo = Zbellbound::SmartGizmoPro::Manipulator.new(*@axes)
        bind_gizmo_callbacks
      end

      @gizmo.size = PLUGIN.gizmo_size
      @gizmo.origin_control.size = PLUGIN.pivot_size
    end

    def bind_gizmo_callbacks
      return unless @gizmo

      @gizmo.on_transform_start do |_action|
        reset_smart_scale_session
        reset_smart_scale_gesture
        # A new drag is "beginning another operation" -- ends any open
        # Ctrl-drag array-input window from a previous copy.
        @ctrl_array_session = nil
        # Every gesture opens its Undo operation through the licensed
        # doorway. The gesture-start check in onLButtonDown normally stops a
        # refused gesture before it reaches here; if this one is refused
        # anyway, the rest of the gesture is dropped -- no frame, click or
        # commit below may touch the model.
        @license_blocked_gesture = !start_licensed_operation('Transform')
      end

      @gizmo.on_transform do |transformation, t_total, data|
        next if @license_blocked_gesture
        next if @selection.empty?

        data = enrich_scale_data(data)
        if data[0] == :scale && smart_scale_supported?(data)
          if smart_scale_multi_selection?
            states = ensure_smart_scale_gesture_states(data)
            if !states.empty? && apply_smart_scale_to_states(states, data[2], data)
              @smart_scale_gesture_data = data.dup
              @smart_scale_gesture_data[2] = data[2]
              @last_transform = [IDENTITY, IDENTITY, @smart_scale_gesture_data]
              update_gizmo
              @model.active_view.invalidate
              next
            end
            smart_scale_log('multi-selection drag preview failed')
          else
            state = ensure_smart_scale_gesture(data)
            state = resolve_smart_scale_state(state, data) if state
            @smart_scale_gesture = state
            if state && SmartScaleApplier.apply!(self, state, data[2])
              @smart_scale_gesture_data = data.dup
              @smart_scale_gesture_data[2] = state.ratio
              @last_transform = [IDENTITY, IDENTITY, @smart_scale_gesture_data]
              update_gizmo
              @model.active_view.invalidate
              next
            end
            smart_scale_log('drag preview failed')
          end
        end
        if data[0] == :scale && !smart_scale_supported?(data)
          @last_smart_scale_session = nil
        end
        # When smart scale was attempted but the gesture state couldn't be
        # built (e.g. object has no usable structure), fall through to the
        # regular scale transform below rather than skipping entirely. The
        # previous `next` here meant the drag silently did nothing.
        remember_rotate_axis(data[2]) if data[0] == :rotate
        @last_transform = [transformation, t_total, data]
        @model.active_entities.transform_entities(transformation, selected_entities)
        @model.active_view.invalidate
      end

      @gizmo.on_transform_end do |_gizmo|
        # A gesture refused at its start opened no operation, so there is
        # nothing to commit and nothing to update.
        if @license_blocked_gesture
          @license_blocked_gesture = false
          next
        end

        # Reset on every transform-end; the copy branch below re-populates
        # it only when this commit actually created a Ctrl-drag copy to
        # divide into an array. Any other commit (plain move, rotate,
        # scale, smart scale) must not leave a stale session behind.
        @ctrl_array_session = nil

        # Multi-selection drag: states cached as @smart_scale_gesture_states.
        if @smart_scale_gesture_states && !@smart_scale_gesture_states.empty?
          @model.commit_operation
          first_state = @smart_scale_gesture_states.first[1]
          @last_smart_scale_session = first_state
          @edit_mouse = @mouse
          Sketchup.vcb_label = 'Scale'
          Sketchup.vcb_value = format_scale_display(first_state.ratio, first_state.reference_length)
          update_gizmo
          @model.active_view.invalidate
          @smart_scale_gesture_states.each { |_e, st| defer_smart_scale_redraw(st) }
          reset_smart_scale_session
          reset_smart_scale_gesture
          next
        end

        if @smart_scale_gesture
          @model.commit_operation
          @last_smart_scale_session = @smart_scale_gesture
          @edit_mouse = @mouse
          Sketchup.vcb_label = 'Scale'
          Sketchup.vcb_value = format_scale_display(@smart_scale_gesture.ratio, @smart_scale_gesture.reference_length)
          update_gizmo
          @model.active_view.invalidate
          defer_smart_scale_redraw(@smart_scale_gesture)
          reset_smart_scale_session
          reset_smart_scale_gesture
          next
        end

        if @copy && !selected_entities.empty?
          tr_new = @last_transform[1]
          original_entities = selected_entities
          @model.active_entities.transform_entities(tr_new.inverse, original_entities)

          # SketchupSuggestions/AddGroup wants groups created empty and populated
          # afterward, but that pattern doesn't fit here: this grouping is a
          # deliberate copy-group/copy/explode trick to duplicate whatever is
          # currently selected (Group/ComponentInstance, loose Edge/Face, or a
          # mix) as one unit, in one native operation.
          #
          # This is NOT identity-safe for loose Edge/Face geometry: SketchUp
          # automatically welds/merges/splits coincident edges and faces on
          # grouping and again on explode, so the exploded copy's Edge/Face
          # objects are not guaranteed to match the originals' count or
          # identity. It IS safe for Group/ComponentInstance children, since
          # explode only unwraps the temporary outer wrapper -- it does not
          # explode THEM. This is exactly why the Ctrl-drag internal array
          # ("/N", built by apply_ctrl_drag_array below) is restricted to
          # Group/ComponentInstance and never reuses this grouping trick for
          # its own intermediate copies -- see duplicate_supported_entity.
          # rubocop:disable SketchupSuggestions/AddGroup
          temp_group = @model.active_entities.add_group(original_entities)
          # rubocop:enable SketchupSuggestions/AddGroup

          instance = temp_group.copy
          instance.transform!(tr_new)

          ents = instance.explode
          temp_group.explode

          ents.delete_if { |e| e.deleted? || !e.is_a?(Sketchup::Drawingelement) }
          @selection.clear
          @selection.add(ents) unless ents.empty?

          # Opens the Ctrl-drag internal-array input window: if the user's
          # very next Measurements entry is "/N" or "N/", onUserText below
          # divides the complete drag distance into an N-copy array instead
          # of treating it as an ordinary re-edit distance. nil (below) for
          # anything other than a plain single-axis/plane move -- e.g. a
          # Ctrl-dragged rotate or scale handle -- which this array feature
          # does not cover.
          @ctrl_array_session = build_ctrl_drag_array_session(original_entities, ents, @last_transform[2], @selection.to_a)
        end

        @model.commit_operation
        if @last_transform && @last_transform[2] && @last_transform[2][0] == :scale
          Sketchup.vcb_label = 'Scale'
          Sketchup.vcb_value = format_scale_display(@last_transform[2][2], @last_transform[2][4])
        end
        update_gizmo
        @edit_mouse = @mouse
        reset_smart_scale_session
        reset_smart_scale_gesture
        @model.active_view.invalidate
      end

      @gizmo.on_click do |data|
        next if @license_blocked_gesture

        action_name, direction = data
        @last_smart_scale_session = nil if action_name == :scale
        move_axis = nil
        if action_name == :move
          move_axis = axis_id_for_direction(direction)
        end

        prompts = ['Enter value:']
        value = case action_name
                when :move
                  0.mm
                when :rotate
                  0
                when :scale
                  scale_default_value(data)
                end
        defaults = [value]
        title = action_name.to_s
        title[0] = title[0].upcase
        case action_name
        when :move, :rotate
          title += if direction.parallel?(@gizmo.axes.x.direction)
            ' X'
          elsif direction.parallel?(@gizmo.axes.y.direction)
            ' Y'
          else
            ' Z'
          end
        when :scale
          marks = data[3]
          title += ' X' if marks.x

          title += ' Y' if marks.y

          title += ' Z' if marks.z
        end

        list = nil
        if action_name == :move && move_axis
          axis_label = move_axis.to_s.upcase
          prompts = ["Distance along #{axis_label}:", "Target world #{axis_label} (optional):", 'Mode:', 'Number of copies:']
          # Always blank: only meaningful in Copy mode, and never
          # prefilled from a previous invocation's value.
          defaults = [0.mm, '', MOVE_MODE_LABEL, '']
          list = ['', '', "#{MOVE_MODE_LABEL}|#{COPY_MODE_LABEL}", '']
        end

        result = list ? UI.inputbox(prompts, defaults, list, title) : UI.inputbox(prompts, defaults, title)
        next unless result

        value = result[0]

        case action_name
        when :move
          if move_axis && result[2] == COPY_MODE_LABEL
            copy_count = parse_copy_array_count(result[3])
            if copy_count.is_a?(Symbol)
              UI.messagebox(copy_array_error_message(copy_count))
              next
            end

            tr = move_dialog_transformation(direction, value, result[1])
            next unless tr

            perform_copy_array(tr, copy_count)
            next
          end

          tr = move_dialog_transformation(direction, value, result[1])
          next unless tr
        when :rotate
          remember_rotate_axis(direction)
          axis = direction.clone
          axis.length = 1.0 if axis.valid?
          angle = value.to_f.degrees
          data = [:rotate, @gizmo.origin.clone, axis, angle]
          tr = rotate_transformation(data[1], data[2], angle)
        when :scale
          data = enrich_scale_data(data)
          if smart_scale_supported?(data)
            next unless start_licensed_operation('Smart Scale')

            begin
              if smart_scale_multi_selection?
                # Multiple objects selected: build a state per entity, apply
                # the same ratio to each independently. Each entity has its
                # own profile and classification.
                states = build_smart_scale_gesture_states_for_selection(data)
                if states.empty?
                  @model.abort_operation
                  UI.messagebox('Smart Scale is not available for this selection.')
                  next
                end

                # Use the first state to parse the ratio (they all share the
                # same axis_id and the user typed one value).
                first_state = states.first[1]
                ratio = parse_smart_scale_ratio(value, first_state, data, default_plain_length: true)
                if ratio.nil? || ratio <= 0
                  @model.abort_operation
                  UI.messagebox('Invalid scale')
                  next
                end

                unless apply_smart_scale_to_states(states, ratio, data)
                  @model.abort_operation
                  UI.messagebox('Smart Scale failed.')
                  next
                end

                # apply_smart_scale_to_states may have resolved (rebuilt)
                # one or more states in place -- re-read the first state
                # from the same array rather than the pre-resolve local,
                # so the VCB/session below reflect what was actually applied.
                first_state = states.first[1]

                @model.commit_operation
                @last_smart_scale_session = first_state
                data = data.dup
                data[2] = ratio
                @last_transform = [IDENTITY, IDENTITY, data]
                @edit_mouse = @mouse
                Sketchup.vcb_label = 'Scale'
                Sketchup.vcb_value = format_scale_display(ratio, first_state.reference_length)
                update_gizmo
                @model.active_view.invalidate
                states.each { |_e, st| defer_smart_scale_redraw(st) }
                next
              end

              state = build_smart_scale_gesture_state(data)
              unless state
                @model.abort_operation
                UI.messagebox('Smart Scale is not available for this selection.')
                next
              end
              state = resolve_smart_scale_state(state, data)
              unless state
                @model.abort_operation
                UI.messagebox('Smart Scale failed.')
                next
              end

              ratio = parse_smart_scale_ratio(value, state, data, default_plain_length: true)
              if ratio.nil? || ratio <= 0
                @model.abort_operation
                UI.messagebox('Invalid scale')
                next
              end

              unless SmartScaleApplier.apply!(self, state, ratio)
                @model.abort_operation
                UI.messagebox('Smart Scale failed.')
                next
              end

              @model.commit_operation
              @last_smart_scale_session = state
              data = data.dup
              data[2] = state.ratio
              @last_transform = [IDENTITY, IDENTITY, data]
              @edit_mouse = @mouse
              Sketchup.vcb_label = 'Scale'
              Sketchup.vcb_value = format_scale_display(state.ratio, state.reference_length)
              update_gizmo
              @model.active_view.invalidate
              defer_smart_scale_redraw(state)
              next
            rescue StandardError => e
              @model.abort_operation
              UI.messagebox("Smart Scale failed.\n\n#{e.message}")
              next
            end
          end
          marks = data[3]
          value = parse_scale_user_text(value, data, default_plain_length: true, relative_base: data[4])
          if value.nil? || value == 0
            UI.messagebox('Invalid scale')
            next
          end
          tr = scale_transformation(marks, value, data)
        end

        @last_transform = [tr, tr, data]
        @model.active_entities.transform_entities(tr, selected_entities)
        if action_name == :rotate
          @edit_mouse = @mouse
          Sketchup.vcb_label = 'Angle'
          Sketchup.vcb_value = Sketchup.format_angle(data[3])
        end
        update_gizmo
        @model.active_view.invalidate
      end

      @gizmo.on_origin_change do |point|
        @custom_origin = point.clone
        @model.active_view.invalidate
      end

      @gizmo.on_origin_change_end do |point|
        @custom_origin = point.clone
        update_gizmo
        @model.active_view.invalidate
      end
    end

    def enrich_scale_data(data)
      return data unless data[0] == :scale
      return data if data.length > 6

      reference = data[4] || scale_reference_length(data[3])
      anchor = data[5] || scale_anchor_point(data[3])
      gizmo_tr = data[6] || scale_gizmo_transformation

      data[0, 4] + [reference, anchor, gizmo_tr]
    end

    def refresh_scale_data(data)
      return data unless data && data[0] == :scale

      marks = data[3]
      reference = scale_reference_length(marks)
      anchor = scale_anchor_point(marks)
      gizmo_tr = scale_gizmo_transformation

      data[0, 4] + [reference, anchor, gizmo_tr]
    end

    def move_dialog_transformation(direction, distance_value, target_value)
      target_text = target_value.to_s.strip
      axis_id = axis_id_for_direction(direction)
      if !target_text.empty? && axis_id
        delta = move_target_delta(axis_id, target_text)
        return nil if delta.nil?

        scene_axis = scene_axis_vector(axis_id)
        return nil unless scene_axis

        translation_for_axis(scene_axis, delta)
      else
        translation_for_axis(direction, distance_value)
      end
    rescue ArgumentError
      UI.messagebox('Invalid move value')
      nil
    end

    def move_target_delta(axis_id, target_text)
      target = target_text.to_l
      scene_axis = scene_axis_vector(axis_id)
      return nil unless scene_axis

      current = current_scene_coordinate(axis_id)
      return nil if current.nil?

      target - current
    rescue ArgumentError
      UI.messagebox("Invalid target #{axis_id.to_s.upcase} coordinate")
      nil
    end

    def current_scene_coordinate(axis_id)
      scene_axis = scene_axis_vector(axis_id)
      return nil unless scene_axis && @gizmo

      scene_origin = @model.axes.origin
      axis = scene_axis.clone
      axis.length = 1.0 if axis.valid?
      scene_origin.vector_to(@gizmo.origin) % axis
    end

    def scene_axis_vector(axis_id)
      case axis_id
      when :x
        @model.axes.xaxis.clone
      when :y
        @model.axes.yaxis.clone
      when :z
        @model.axes.zaxis.clone
      end
    end

    # Parses a plain copy count such as "3" or " 3 " -- no "x" prefix is
    # required or accepted; the field label ("Number of copies") already
    # says what it means. Returns a positive Integer copy count on
    # success, or one of :blank, :invalid, :too_many on failure --
    # distinct symbols so the caller can show a precise validation
    # message without touching the model.
    def parse_copy_array_count(text)
      stripped = text.to_s.strip
      return :blank if stripped.empty?

      match = COPY_ARRAY_COUNT_PATTERN.match(stripped)
      return :invalid unless match

      count = match[1].to_i
      return :invalid if count < 1
      return :too_many if count > COPY_ARRAY_MAX_COPIES

      count
    end

    def copy_array_error_message(reason)
      case reason
      when :too_many
        "Too many copies requested. Maximum is #{COPY_ARRAY_MAX_COPIES}."
      else
        "Enter a whole number from 1 to #{COPY_ARRAY_MAX_COPIES}."
      end
    end

    # Copy array only supports these two container types. There is no
    # documented, generic per-entity duplication primitive in the public
    # SketchUp Ruby API for loose geometry (Edge/Face have no #copy at
    # all), and Sketchup::Group and Sketchup::ComponentInstance do not
    # share a duplication API (only Group defines #copy; a plain
    # ComponentInstance has none) -- see duplicate_supported_entity.
    def copy_array_supported_entity?(entity)
      entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
    end

    # Validates the RAW selection (not selected_entities, which silently
    # drops locked groups/components for ordinary move/rotate/scale) so
    # copy array never silently duplicates a subset of what the user
    # selected. Returns nil if the selection is safe to copy, or a
    # user-facing message describing why it was rejected. Ordinary move
    # is unaffected -- it keeps using selected_entities exactly as
    # before.
    def copy_array_selection_issue(entities)
      return 'Select at least one group or component to create a copy array.' if entities.empty?

      entities.each do |entity|
        unless copy_array_supported_entity?(entity)
          return 'Copy array only supports groups and components -- this selection includes other geometry.'
        end

        if entity.respond_to?(:locked?) && entity.locked?
          return 'Copy array cannot copy a locked group or component. Unlock it first.'
        end

        # glued_to (real, documented on both Group and ComponentInstance)
        # returns the entity this one is glued to, or nil. add_instance
        # does not reproduce a glue-to-face/cut-opening relationship, and
        # Group#copy's handling of it is undocumented, so rather than
        # guess, reject up front for this iteration.
        if entity.respond_to?(:glued_to) && entity.glued_to
          return 'Copy array cannot safely duplicate a component glued to another entity yet. ' \
                 'Unglue it first, or use ordinary Move/Copy for this object.'
        end
      end

      nil
    end

    # Duplicates a single supported entity using its own documented API --
    # Group and ComponentInstance are NOT assumed to share a copy
    # mechanism:
    #
    # - Sketchup::Group#copy is a real, Group-specific method that
    #   returns a full duplicate (transformation, name, material, layer,
    #   attributes) at the same location.
    # - Sketchup::ComponentInstance has no #copy at all. The documented
    #   way to place another instance of the same definition is
    #   Entities#add_instance(definition, transform) -- which copies
    #   only the definition and transformation, nothing else, so every
    #   other property has to be copied across explicitly afterward.
    #
    # In both cases the new copy starts at the ORIGINAL's own complete
    # transformation (preserving rotation/scale/mirroring), and the
    # caller applies the array step as a #transform! delta on top of
    # that -- never recomputed from scratch per axis.
    def duplicate_supported_entity(entity)
      if entity.is_a?(Sketchup::Group)
        entity.copy
      else
        duplicate_component_instance(entity)
      end
    end

    def duplicate_component_instance(instance)
      new_instance = @model.active_entities.add_instance(instance.definition, instance.transformation)
      return nil unless new_instance

      new_instance.name = instance.name
      new_instance.material = instance.material
      new_instance.layer = instance.layer
      new_instance.hidden = instance.hidden?
      new_instance.locked = instance.locked? if new_instance.respond_to?(:locked=)
      new_instance.casts_shadows = instance.casts_shadows? if new_instance.respond_to?(:casts_shadows=)
      new_instance.receives_shadows = instance.receives_shadows? if new_instance.respond_to?(:receives_shadows=)
      copy_attribute_dictionaries(instance, new_instance)
      new_instance
    end

    # add_instance does not copy attribute dictionaries, so every one is
    # copied across explicitly here. Deliberately does NOT rescue
    # set_attribute/each_pair failures: a dictionary or key that can't be
    # written would otherwise commit a copy with silently missing
    # extension/Dynamic Component data -- an apparently successful but
    # degraded result. Any failure here must propagate to the
    # start_operation/rescue in perform_copy_array so the WHOLE array
    # aborts instead of leaving that partial state behind.
    def copy_attribute_dictionaries(source, target)
      dictionaries = source.attribute_dictionaries
      return unless dictionaries

      dictionaries.each do |dictionary|
        dictionary.each_pair do |key, value|
          target.set_attribute(dictionary.name, key, value)
        end
      end
    end

    # Creates `copies` equally-spaced duplicates of the validated
    # selection along `step_transformation`, leaving the original
    # selection completely in place. `step_transformation` is the
    # single-step move transformation already computed by
    # move_dialog_transformation -- it is composed with itself (not
    # recalculated) for each successive copy, so the per-axis distance
    # math lives in exactly one place.
    #
    # The whole array is one undo step: any failure aborts the operation,
    # leaving no partial copies behind. Selection is validated and any
    # unsupported/locked/glued entity rejects the WHOLE operation before
    # start_operation is even called, so no model change ever happens for
    # a selection copy array can't safely handle.
    def perform_copy_array(step_transformation, copies)
      entities = @selection.to_a
      return if copies.to_i < 1

      issue = copy_array_selection_issue(entities)
      if issue
        UI.messagebox(issue)
        return
      end

      return unless start_licensed_operation('Copy Array')

      begin
        new_entities = []
        cumulative = IDENTITY

        copies.to_i.times do
          cumulative = step_transformation * cumulative
          entities.each do |entity|
            copy = duplicate_supported_entity(entity)
            raise 'Could not copy selection' unless copy

            copy.transform!(cumulative)
            new_entities << copy
          end
        end

        @model.commit_operation

        # Selection after a successful array = original selection plus
        # every created copy, so the whole array is immediately visible
        # and actionable. The originals are re-added from `entities`
        # (never touched above) rather than re-read from the model.
        @selection.clear
        @selection.add(entities)
        @selection.add(new_entities) unless new_entities.empty?
      rescue StandardError => e
        @model.abort_operation
        UI.messagebox("Copy array failed.\n\n#{e.message}")
      end

      update_gizmo
      @model.active_view.invalidate
    end

    # Builds the state the Ctrl-drag array feature needs to turn the
    # just-completed copy into an N-copy array later, or nil if this commit
    # isn't one the array feature supports. Shared by both array syntaxes
    # -- internal "/N" (subdivide the dragged distance) and external "xN"
    # (repeat the dragged distance) -- since both operate on the exact same
    # drag: same originals, same endpoint, same fixed vector. Only the
    # position formula applied to that vector differs; see
    # ctrl_drag_array_step_transformation and apply_ctrl_drag_array.
    #
    # - `originals`: the source entities, already back at their pre-drag
    #   transformation (never touched again by the array feature).
    # - `endpoint`: the single copy the Ctrl-drag itself just created, at
    #   the complete dragged distance. Never regenerated or moved by a
    #   later "/N" or "xN" edit, in either mode -- it is always exactly
    #   1x the fixed vector, which is also exactly what both formulas
    #   independently place at "the endpoint's slot" (index N of N for
    #   "/N", index 1 of N for "xN") -- so the two modes agree on this
    #   point by construction, not by special-casing it.
    # - `vector`: the complete drag vector (data[1] from the gizmo's own
    #   [:move, v_total] payload -- see MoveGizmo/PlaneMoveGizmo#move_event
    #   in gizmo.rb), fixed at the moment the mouse was released. Every
    #   later "/N"/"xN" re-edit reinterprets this SAME fixed vector; it is
    #   never recalculated from the current copy position.
    # - `intermediates`: every generated copy other than the endpoint,
    #   from whichever array edit (of either syntax) was applied most
    #   recently, so a later edit knows what to remove before rebuilding.
    #   Empty right after the plain copy, since no array has been
    #   requested yet. (Named for the original "/N" feature, where these
    #   sit between the original and the endpoint; for "xN" they instead
    #   extend beyond the endpoint -- see apply_ctrl_drag_array.)
    # - `mode`: which syntax produced the current `intermediates` --
    #   :internal ("/N") or :external ("xN") -- or nil before either has
    #   been used. Switching syntax (e.g. "/3" then "x3") must replace the
    #   array even when the count is unchanged, since the two modes place
    #   copies at entirely different positions; apply_ctrl_drag_array
    #   compares this alongside `count` for that reason.
    # - `count`: the current total copy count (including the endpoint).
    #   Starts at 1 (just the endpoint) -- matches what "/1" and "x1" both
    #   mean.
    # - `expected_selection`: the exact selection this method's own
    #   @selection.clear/@selection.add call just produced (passed in by
    #   the caller, which reads @selection.to_a right after making that
    #   call). See clear_edit_state and ctrl_drag_selection_matches? for
    #   why this is needed: it is not safe to assume the SelectionObserver
    #   notification for OUR OWN selection change is delivered
    #   synchronously, inside the same call. If SketchUp instead delivers
    #   it on a later tick, clear_edit_state must be able to recognize
    #   that notification as an echo of this same commit -- not a genuine
    #   later selection change -- so it doesn't close the array-input
    #   window before the user ever gets to type "/N" or "xN".
    def build_ctrl_drag_array_session(originals, endpoint, move_data, expected_selection)
      return nil unless move_data && move_data[0] == :move

      vector = move_data[1]
      return nil unless vector.respond_to?(:valid?) && vector.valid?

      {
        originals: originals.dup,
        endpoint: endpoint.dup,
        intermediates: [],
        vector: vector.clone,
        mode: nil,
        count: 1,
        expected_selection: expected_selection.dup
      }
    end

    # Order-independent identity comparison: two entity arrays "match" if
    # they contain the same objects, regardless of @selection's internal
    # ordering (not guaranteed stable across reads in the real API).
    # Entities don't override #==, so #object_id is used directly rather
    # than relying on Array#== / Set, which would fall back to #== anyway.
    def ctrl_drag_selection_matches?(a, b)
      return false unless a && b

      a.map(&:object_id).sort == b.map(&:object_id).sort
    end

    # Recognizes the Ctrl-drag internal-array syntax ("/3", "3/", with
    # optional surrounding whitespace) in Measurements text typed right
    # after a Ctrl-drag copy. Returns:
    #
    # - nil if `text` isn't array syntax at all (no "/" present) -- the
    #   caller falls through to ordinary re-edit distance handling.
    # - a positive Integer copy count (1..COPY_ARRAY_MAX_COPIES) on success.
    # - :invalid or :too_many if a "/" is present but the count is
    #   malformed, zero, negative, non-integer, or over the limit -- these
    #   must never fall through to distance parsing, since e.g. "/2.5" or
    #   "/-2" are not valid lengths either and would otherwise surface a
    #   confusing, unrelated error.
    def parse_ctrl_drag_array_count(text)
      stripped = text.to_s.strip
      return nil unless stripped.include?('/')

      match = CTRL_DRAG_ARRAY_SLASH_PREFIX_PATTERN.match(stripped) ||
              CTRL_DRAG_ARRAY_SLASH_SUFFIX_PATTERN.match(stripped)
      return :invalid unless match

      count = match[1].to_i
      return :invalid if count < 1
      return :too_many if count > COPY_ARRAY_MAX_COPIES

      count
    end

    # Recognizes the Ctrl-drag external-array syntax ("x3", "3x", "X3",
    # "3X", with optional surrounding whitespace) -- SketchUp's own
    # documented external-array (extend-by-repeating) input convention.
    # Same contract as parse_ctrl_drag_array_count: nil if `text` isn't
    # this syntax at all (no "x"/"X" present), a positive Integer count on
    # success, or :invalid/:too_many for a malformed/zero/negative/
    # non-integer/over-limit count that must not fall through to distance
    # parsing.
    def parse_ctrl_drag_external_array_count(text)
      stripped = text.to_s.strip
      return nil unless stripped.match?(/[xX]/)

      match = CTRL_DRAG_ARRAY_X_PREFIX_PATTERN.match(stripped) ||
              CTRL_DRAG_ARRAY_X_SUFFIX_PATTERN.match(stripped)
      return :invalid unless match

      count = match[1].to_i
      return :invalid if count < 1
      return :too_many if count > COPY_ARRAY_MAX_COPIES

      count
    end

    # Applies a Ctrl-drag array edit, in either mode, replacing whatever
    # `intermediates` a previous "/N" or "xN" edit in this same session
    # created -- including a previous edit in the OTHER mode, since
    # switching syntax must replace the array just like re-entering the
    # same syntax with a different count does. The endpoint copy (already
    # placed by the Ctrl-drag itself) is never touched in either mode --
    # see build_ctrl_drag_array_session for why both formulas agree on
    # leaving it exactly where it is.
    #
    # `mode` selects the position formula for indices 1..count:
    #
    # - :internal ("/N"): subdivides the fixed drag distance into `count`
    #   equal spaces. Index i sits at (i/count) of the vector; the
    #   endpoint is index `count` (i.e. the far end, at the full vector) --
    #   so only indices 1...count are generated here.
    # - :external ("xN"): repeats the fixed drag distance `count` times.
    #   Index i sits at i times the vector; the endpoint is index 1 (i.e.
    #   the near end, at exactly one vector) -- so only indices 2..count
    #   are generated here.
    #
    # Both formulas place the endpoint's own index at exactly 1x the
    # vector, matching its actual fixed position, without either branch
    # needing to special-case it.
    #
    # One Undo covers the whole session: this re-edit's own start_operation
    # is `transparent`, so per the documented Model#start_operation
    # signature (op_name, disable_ui, next_transparent, transparent) it
    # merges backward into whatever operation is on top of the undo stack
    # -- the original drag-and-copy commit the first time, and the
    # previous array edit's already-merged operation on every edit after
    # that -- rather than adding a new separate undo entry each time.
    #
    # New intermediates are built and validated to completion BEFORE any
    # old intermediate is erased, so a failure partway through a rebuild
    # (or an invalid count, checked even earlier, before start_operation)
    # never leaves the model in a state missing both the old and the new
    # set -- the existing endpoint and existing intermediates are only
    # ever touched once the replacement set is known to be complete.
    def apply_ctrl_drag_array(count, mode, view)
      session = @ctrl_array_session
      return unless session

      if count.is_a?(Symbol)
        UI.messagebox(copy_array_error_message(count))
        return
      end

      # count == 1 always means "just the endpoint" regardless of which
      # syntax asked for it, so it's a no-op whenever that's already true
      # -- switching syntax at count 1 would otherwise look like a change
      # (mode differs) despite producing an identical, empty result.
      # Above count 1, the two modes disagree on where copies go, so a
      # same-count switch between them must still rebuild.
      return if count == session[:count] && (count == 1 || mode == session[:mode])

      if count > 1
        issue = copy_array_selection_issue(session[:originals])
        if issue
          UI.messagebox(issue)
          return
        end
      end

      return unless start_licensed_operation('Copy Array', false, true)

      begin
        new_intermediates = []
        generated_indices = mode == :external ? (2..count) : (1...count)
        generated_indices.each do |i|
          multiplier = mode == :external ? i.to_f : i.to_f / count
          step_tr = ctrl_drag_array_step_transformation(session[:vector], multiplier)
          session[:originals].each do |entity|
            copy = duplicate_supported_entity(entity)
            raise 'Could not copy selection' unless copy

            copy.transform!(step_tr)
            new_intermediates << copy
          end
        end

        session[:intermediates].each { |e| e.erase! if e.valid? }

        @model.commit_operation

        session[:intermediates] = new_intermediates
        session[:mode] = mode
        session[:count] = count

        @selection.clear
        @selection.add(session[:originals])
        @selection.add(new_intermediates) unless new_intermediates.empty?
        @selection.add(session[:endpoint]) unless session[:endpoint].empty?

        # Refreshed to match this call's own selection mutation, for the
        # same reason build_ctrl_drag_array_session records it: a later
        # selection-changed notification echoing THIS change must not be
        # mistaken for a genuine new selection by clear_edit_state.
        session[:expected_selection] = @selection.to_a
        @ctrl_array_session = session
      rescue StandardError => e
        @model.abort_operation
        UI.messagebox("Copy array failed.\n\n#{e.message}")
        return
      end

      update_gizmo
      view.invalidate
    end

    def ctrl_drag_array_step_transformation(vector, multiplier)
      vec = vector.clone
      vec.length = vector.length * multiplier
      Geom::Transformation.translation(vec)
    end

    def translation_for_axis(direction, distance)
      vec = direction.clone
      if distance.to_f < 0
        vec.reverse!
        vec.length = distance.to_f.abs
      else
        vec.length = distance
      end
      Geom::Transformation.translation(vec)
    end

    def scale_marks(marks, value)
      x, y, z = marks
      scale_x = x ? value : 1.0
      scale_y = y ? value : 1.0
      scale_z = z ? value : 1.0
      
      [scale_x, scale_y, scale_z]
    end

    def scale_transformation(marks, value, data = nil)
      scale_x, scale_y, scale_z = scale_marks(marks, value)
      gizmo_tr = scale_gizmo_transformation(data)

      tr = if single_axis_scale?(marks)
        anchor = scale_anchor_point(marks, data)
        Geom::Transformation.scaling(anchor, scale_x, scale_y, scale_z)
      else
        Geom::Transformation.scaling(scale_x, scale_y, scale_z)
      end

      gizmo_tr * tr * gizmo_tr.inverse
    end

    def scale_gizmo_transformation(data = nil)
      return data[6] if data && data[6].is_a?(Geom::Transformation)

      gx, gy, gz = @gizmo.axes.map do |axis|
        axis.direction
      end
      go = @gizmo.origin
      Geom::Transformation.new(gx, gy, gz, go)
    end

    def scale_anchor_point(marks, data = nil)
      return ORIGIN.clone unless single_axis_scale?(marks)
      return data[5].clone if data && data[5].respond_to?(:clone)
      return ORIGIN.clone unless @gizmo&.bounds && !@gizmo.bounds.empty?

      gizmo_tr = scale_gizmo_transformation(data)
      points = 0.upto(7).map do |i|
        @gizmo.bounds.corner(i).transform(@gizmo.transformation).transform(gizmo_tr.inverse)
      end

      if marks[0]
        Geom::Point3d.new(points.map(&:x).min, 0, 0)
      elsif marks[1]
        Geom::Point3d.new(0, points.map(&:y).min, 0)
      else
        Geom::Point3d.new(0, 0, points.map(&:z).min)
      end
    end

    def single_axis_scale?(marks)
      marks.count(true) == 1
    end

    # The click-activated Scale dialog's default/current-value field. Must
    # match the Measurements/VCB box's own formatting exactly (same model
    # units, precision, rounding, decimal separator, and no unit suffix --
    # e.g. "992" not "992mm") since both show "the current dimension" for
    # the same handle -- so this reuses format_scale_display/
    # strip_scale_display_unit_suffix (a ratio of 1.0 against the current
    # reference length IS the current dimension) rather than a second,
    # separate formatter. PLUGIN.scale_input_unit (format_length_in_
    # scale_unit's old formatter) is a different setting entirely -- how
    # a *typed*, unit-less number is interpreted (parse_scale_length) --
    # not how the dialog's own default is displayed.
    def scale_default_value(data)
      data = enrich_scale_data(data)
      marks = data[3]
      reference = data[4]
      return 1.0 unless single_axis_scale?(marks) && reference && reference > 0

      format_scale_display(1.0, reference)
    end

    def parse_scale_value(input, data)
      marks = data[3]
      return input.to_f unless single_axis_scale?(marks)

      reference = data[4]
      return nil unless reference && reference > 0

      target = parse_scale_length_expression(input)
      return nil unless target && target > 0

      target / reference
    end

    def parse_scale_user_text(input, data, default_plain_length: false, relative_base: nil)
      text = input.to_s.strip
      return nil if text.empty?

      return parse_scale_division_ratio(text, data) if text.start_with?('/')
      return parse_scale_multiplication_ratio(text, data) if text.match?(/\A[xX]/)

      if single_axis_scale?(data[3]) && scale_length_expression?(text)
        reference = relative_base || data[4]
        target = parse_scale_length_expression(text, default_plain_length: default_plain_length, base_length: reference)
        return nil unless target && target > 0
        return nil unless data[4] && data[4] > 0

        target / data[4]
      elsif text.match?(/[a-z"]/i)
        parse_scale_value(text, data)
      else
        value = text.to_f
        value.positive? ? value : nil
      end
    end

    # Divides the CURRENTLY DISPLAYED single-axis Scale dimension by a
    # divisor typed as "/2", "/3", etc. -- e.g. entering "/2" while the
    # displayed dimension reads 600mm results in 300mm. `data[2]` is the
    # ratio already in effect (1 on a fresh handle click -- see
    # ScaleGizmo#onLButtonUp in gizmo.rb -- and kept current by
    # reEdit's plain-scale branch across repeated re-edits), so
    # `data[2] / divisor` is the new ratio without needing to touch
    # `data[4]` (reference) at all: (reference * data[2]) / divisor
    # reduces to reference * (data[2] / divisor).
    #
    # Only meaningful for single-axis scale, matching every other
    # length-expression path above -- returns nil for a multi-axis/
    # uniform scale handle (e.g. a corner or center-scale drag), the
    # same "Invalid scale" outcome that "/2" already produced before
    # this feature existed, so proportional/uniform scale behavior is
    # unchanged.
    def parse_scale_division_ratio(text, data)
      match = SCALE_DIVISION_PATTERN.match(text)
      return nil unless match
      return nil unless single_axis_scale?(data[3])

      divisor = match[1].to_f
      return nil unless divisor.positive?

      current_ratio = data[2].to_f
      return nil unless current_ratio.positive?

      current_ratio / divisor
    end

    # Multiplies the CURRENTLY DISPLAYED single-axis Scale dimension by a
    # factor typed as "x2", "X2", "x1.5", etc. -- the "/2" division
    # feature's companion, same current-ratio-in-effect mechanism
    # (data[2], kept current by reEdit's plain-scale branch and by every
    # successful Smart Scale mutation -- see the `data[2] = state.ratio`
    # assignments elsewhere in this file), so `current_ratio * multiplier`
    # is the new ratio without touching `data[4]` (reference) at all,
    # exactly mirroring parse_scale_division_ratio's own reasoning.
    #
    # Prefix-only ("x2", never "2x") -- SCALE_MULTIPLICATION_PATTERN
    # itself only matches the prefix form, so a suffix like "2x" simply
    # doesn't match here and falls through to whatever the caller does
    # next (parse_scale_user_text's plain-number branch, or "Invalid
    # scale" for parse_smart_scale_ratio), same as any other malformed
    # input -- it is never misread as a Ctrl-drag Move array command,
    # since that's a completely separate parser
    # (parse_ctrl_drag_external_array_count) gated behind a completely
    # separate, Move-only session flag (@ctrl_array_session) that this
    # method never reads or touches.
    #
    # Only meaningful for single-axis scale, matching parse_scale_
    # division_ratio -- returns nil for a multi-axis/uniform scale handle.
    def parse_scale_multiplication_ratio(text, data)
      match = SCALE_MULTIPLICATION_PATTERN.match(text)
      return nil unless match
      return nil unless single_axis_scale?(data[3])

      multiplier = match[1].to_f
      return nil unless multiplier.positive?

      current_ratio = data[2].to_f
      return nil unless current_ratio.positive?

      current_ratio * multiplier
    end

    def parse_smart_scale_ratio(input, state, data, default_plain_length: false)
      return nil unless state

      reference = data[4]
      reference = state.reference_length unless reference && reference.positive?
      return nil unless reference && reference.positive?

      if single_axis_scale?(data[3]) && input.is_a?(Length)
        target = input.to_l
        return nil unless target.positive?

        return target / reference
      end

      text = input.to_s.strip
      return nil if text.empty?

      # "/2" etc: divides the ratio CURRENTLY in effect (data[2], kept in
      # sync with state.ratio after every successful Smart Scale
      # mutation -- see the `data[2] = state.ratio` assignments at each
      # call site), same syntax and same shared parser
      # (parse_scale_division_ratio) as plain Scale's "/N" -- reused, not
      # duplicated. Checked before the length-expression branch since a
      # leading "/" is never a valid length/expression token.
      if single_axis_scale?(data[3]) && text.start_with?('/')
        return parse_scale_division_ratio(text, data)
      end

      # "x2"/"X2" etc: same reasoning as "/2" above, reusing parse_scale_
      # multiplication_ratio (shared with plain Scale, not duplicated).
      # Checked before the length-expression branch for the same reason
      # "/2" is: text.match?(/\A[xX]/) must win over default_plain_length
      # (true for the click-dialog path), or "x2" would otherwise fall
      # into the length-expression branch below and be misread as an
      # invalid length token instead of a multiplier.
      if single_axis_scale?(data[3]) && text.match?(/\A[xX]/)
        return parse_scale_multiplication_ratio(text, data)
      end

      if single_axis_scale?(data[3]) && (scale_length_expression?(text) || default_plain_length)
        target = parse_scale_length_expression(text, default_plain_length: default_plain_length, base_length: reference)
        return nil unless target&.positive?

        return target / reference
      end

      ratio = text.to_f
      return nil unless ratio.positive?

      ratio
    rescue ArgumentError
      nil
    end

    def parse_scale_length(input)
      text = input.to_s.strip
      return nil if text.empty?

      if text.match?(/[a-z"]/i)
        text.to_l
      else
        "#{text}#{PLUGIN.scale_input_unit}".to_l
      end
    rescue ArgumentError
      nil
    end

    def scale_length_expression?(text)
      stripped = text.to_s.strip
      return false if stripped.empty?

      stripped.match?(/\A[+\-]?\s*\d/)
    end

    def parse_scale_length_expression(input, default_plain_length: true, base_length: nil)
      return input.to_l if input.is_a?(Length)

      text = input.to_s.strip
      return nil if text.empty?

      if text.match?(/\A[+\-]/)
        return nil unless base_length

        total = base_length.to_f
      else
        total = 0.0
        text = "+#{text}"
      end

      tokens = text.scan(/[+\-]\s*[^+\-]+/)
      return nil if tokens.empty?

      tokens.each do |token|
        sign = token[0] == '-' ? -1.0 : 1.0
        value_text = token[1..].strip
        return nil if value_text.empty?

        length = if value_text.match?(/[a-z"]/i)
          value_text.to_l
        elsif default_plain_length
          parse_scale_length(value_text)
        else
          nil
        end
        return nil unless length

        total += sign * length.to_f
      end

      total.to_l
    rescue ArgumentError
      nil
    end

    def format_scale_factor(value)
      formatted = value.to_f.round(3)
      formatted = formatted.to_i if formatted == formatted.to_i
      formatted.to_s
    end

    # Scale's Measurements/VCB readout for a single axis-based handle:
    # the resulting physical dimension (reference_length * ratio),
    # formatted with Sketchup.format_length -- the documented API that
    # "formats a number as a length using the current units settings"
    # (ruby.sketchup.com/Sketchup.html#format_length-class_method), so
    # unit, precision, decimal separator, and locale all come from the
    # model's own configuration rather than anything hardcoded here.
    #
    # `reference_length` is nil whenever a single physical dimension
    # isn't meaningful for the current handle/mode (uniform/proportional
    # scale, a corner or center-scale drag, multi-axis marks) --
    # scale_reference_length itself already returns nil for exactly
    # those cases, so callers can pass it straight through unchecked.
    # In that case this falls back to the plain scale factor, same as
    # before this feature existed, rather than inventing a dimension
    # that isn't real.
    def format_scale_display(ratio, reference_length)
      return format_scale_factor(ratio) unless reference_length && reference_length > 0

      formatted = Sketchup.format_length(reference_length.to_f * ratio.to_f)
      strip_scale_display_unit_suffix(formatted)
    end

    # Removes ONLY the trailing unit suffix Sketchup.format_length just
    # appended for the model's current unit (SCALE_DISPLAY_UNIT_SUFFIX_
    # BY_LENGTH_UNIT), so the Measurements box shows a bare dimension
    # (e.g. "992" instead of "992mm") while the actual physical value,
    # rounding, precision, and locale-specific decimal separator all
    # still come entirely from `formatted` -- nothing here recomputes or
    # re-rounds the number itself.
    #
    # Deliberately does NOT touch Model#options['UnitsOptions']
    # ['SuppressUnitsDisplay'] (which would strip units for every other
    # length field in the model, a global side effect) and never runs
    # unless the model's LengthFormat is Decimal, since only Decimal
    # produces a single, unambiguous trailing token -- Architectural/
    # Engineering/Fractional compose feet and inches together (e.g.
    # `5' - 6"`) and are returned unchanged rather than risk mangling
    # them with a guess.
    def strip_scale_display_unit_suffix(formatted)
      units_options = @model&.options&.[]('UnitsOptions')
      return formatted unless units_options
      return formatted unless units_options['LengthFormat'] == Length::Decimal

      suffix = SCALE_DISPLAY_UNIT_SUFFIX_BY_LENGTH_UNIT[units_options['LengthUnit']]
      return formatted unless suffix && formatted.end_with?(suffix)

      formatted.delete_suffix(suffix)
    end

    def scale_reference_length(marks)
      return nil unless single_axis_scale?(marks)
      return nil unless @gizmo&.bounds && !@gizmo.bounds.empty?

      direction = if marks[0]
        @gizmo.axes.x.direction
      elsif marks[1]
        @gizmo.axes.y.direction
      else
        @gizmo.axes.z.direction
      end

      direction = direction.clone
      return nil unless direction.valid?

      direction.length = 1.0
      pts = 0.upto(7).map { |i| @gizmo.bounds.corner(i).transform(@gizmo.transformation) }
      values = pts.map { |pt| (pt.x * direction.x) + (pt.y * direction.y) + (pt.z * direction.z) }

      values.max - values.min
    end

    def smart_scale_enabled?
      return false unless PLUGIN.respond_to?(:smart_scale_enabled?)

      PLUGIN.smart_scale_enabled?
    rescue StandardError => e
      warn_overlay_issue('read smart scale enabled setting', e)
      false
    end

    def smart_scale_axis_id(marks)
      axes = []
      axes << :x if marks&.x
      axes << :y if marks&.y
      axes << :z if marks&.z
      return nil unless axes.length == 1

      axes.first
    end

    def smart_scale_supported?(data)
      return false unless smart_scale_enabled?
      return false unless data && data[0] == :scale
      return false unless smart_scale_eligible_selection?

      !smart_scale_axis_id(data[3]).nil?
    end

    # Smart scale supports either a single selected object, or multiple
    # selected objects of the same type (each one is smart-scaled
    # independently). Used to gate smart_scale_supported?.
    def smart_scale_eligible_selection?
      return false unless @selection
      return false if @selection.empty?

      @selection.to_a.all? do |entity|
        entity.is_a?(Sketchup::ComponentInstance) || entity.is_a?(Sketchup::Group)
      end
    end

    # Returns true if multiple objects are selected, requiring per-entity
    # smart scale application instead of the single-entity path.
    def smart_scale_multi_selection?
      @selection && @selection.length > 1
    end

    def smart_scale_entity
      return nil unless selected_one_object?

      prepare_smart_scale_entity(@selection[0])
    end

    def ensure_component_tree_unique_for_smart_scale(entity, depth = 0)
      return nil unless entity&.valid?
      return entity if depth > 8

      if entity.respond_to?(:make_unique) &&
         entity.respond_to?(:definition) &&
         entity.definition.respond_to?(:instances) &&
         entity.definition.instances.length > 1
        entity.make_unique
      end

      entities = smart_scale_entities(entity)
      return entity unless entities

      child_instances_for_entities(entities).each do |child|
        ensure_component_tree_unique_for_smart_scale(child, depth + 1)
      end

      entity
    end

    def prepare_smart_scale_entity(entity)
      return nil unless entity&.valid?

      if entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
        ensure_component_tree_unique_for_smart_scale(entity)
      end

      entity
    end

    # The final safe point before Smart Scale mutates component-
    # definition geometry (SmartScaleApplier#apply!'s entities.
    # transform_by_vectors call, :frame mode only -- :basic mode only
    # ever sets entity.transformation, never touches shared geometry).
    # Called immediately before every apply! invocation, whether `state`
    # was just built fresh (smart_scale_entity already ran make_unique
    # for it moments ago, so this is then a cheap no-op re-check) or is
    # a cached/reused session or gesture (@last_smart_scale_session,
    # @smart_scale_gesture[_states]) that can outlive some other
    # operation which re-shared this same entity's definition since the
    # state was built. `data` is the same enriched Scale data tuple the
    # caller has in scope (nil where none is available), threaded
    # through to the rebuild below so a rebuilt state doesn't lose
    # anchor_point/gizmo_transformation.
    #
    # ensure_component_tree_unique_for_smart_scale is always safe to
    # call again -- a no-op once the definition already has exactly one
    # instance -- but a cached state's vertex_entries/instance_entries
    # were captured against whatever definition existed at BUILD time.
    # If make_unique now actually swaps entity.definition out from under
    # it, those captured entries point at the old, no-longer-current
    # definition and must not be mutated (they'd be mutating geometry
    # the entity no longer even displays).
    #
    # Whether that swap actually happened is decided by comparing
    # entity.definition.instances.length BEFORE calling
    # ensure_component_tree_unique_for_smart_scale against 1 -- a plain
    # Integer/value comparison, not object identity. An earlier version
    # of this method compared `entity.definition` before/after with
    # #equal? instead; SketchUp's Ruby API does not guarantee that two
    # separate #definition accessor calls return the *same* Ruby wrapper
    # object even when nothing changed underneath (every other identity
    # check in this file already avoids exactly this by using `==`, not
    # `equal?`, e.g. SmartScaleGestureState#matches?), so that comparison
    # could spuriously read as "changed" on every single call -- forcing
    # a rebuild on every Smart Scale mutation, including every frame of
    # a live drag. Rebuilding mid-drag re-baselines "original" vertex
    # positions to whatever the CURRENT (already partially scaled)
    # geometry happened to be at that moment, corrupting the profile and
    # restore!/reapply math into something that no longer respects the
    # true fixed-end/stretch-middle structure -- exactly the "Smart
    # Scale behaves like ordinary Scale" regression this fixes.
    #
    # Returns nil (never the stale state) when the entity's definition
    # WAS actually shared and a valid Smart Scale state could not be
    # rebuilt for the now-unique definition -- callers must treat nil as
    # a hard failure (abort and roll back) rather than proceeding with
    # mismatched state or falling back to ordinary scaling.
    #
    # Never mutates any geometry itself -- SmartScaleApplier.apply! is
    # the only thing that does that, immediately after this returns.
    def resolve_smart_scale_state(state, data = nil)
      return state unless state&.entity&.valid?

      entity = state.entity
      return state unless entity.respond_to?(:definition) && entity.definition.respond_to?(:instances)

      was_shared = entity.definition.instances.length > 1
      ensure_component_tree_unique_for_smart_scale(entity)
      return state unless was_shared

      build_smart_scale_gesture_state_for_entity(entity, state.axis_id, state.mask, data)
    end

    def smart_scale_entities(entity)
      return entity.entities if entity.is_a?(Sketchup::Group)
      return entity.definition.entities if entity.is_a?(Sketchup::ComponentInstance)

      nil
    end

    def smart_scale_vertices(entity)
      entities = smart_scale_entities(entity)
      return [] unless entities

      entities.grep(Sketchup::Edge).reject { |edge| edge.curve }.flat_map(&:vertices).uniq
    end

    def smart_scale_edges(entity)
      entities = smart_scale_entities(entity)
      return [] unless entities

      entities.grep(Sketchup::Edge)
    end

    def child_instances_for_entities(entities)
      return [] unless entities

      groups = entities.grep(Sketchup::Group)
      components = entities.grep(Sketchup::ComponentInstance).reject { |entity| entity.is_a?(Sketchup::Group) }
      groups + components
    end

    def entities_have_raw_geometry?(entities)
      return false unless entities

      !entities.grep(Sketchup::Edge).empty? || !entities.grep(Sketchup::Face).empty?
    end

    def meaningful_smart_scale_part?(instance)
      entities = smart_scale_entities(instance)
      return false unless entities

      entities_have_raw_geometry?(entities) || child_instances_for_entities(entities).empty?
    end

    def collect_nested_smart_scale_instances(entities, axis_id, path = [], root_to_solver_transformation = IDENTITY)
      return [] unless entities

      child_instances_for_entities(entities).flat_map do |instance|
        if meaningful_smart_scale_part?(instance)
          min, max = instance_path_bounds_range(instance, path, axis_id, root_to_solver_transformation)
          [{
            instance: instance,
            path: path.dup,
            original_transformation: instance.transformation.clone,
            min: min,
            max: max
          }]
        else
          collect_nested_smart_scale_instances(
            smart_scale_entities(instance),
            axis_id,
            path + [instance],
            root_to_solver_transformation
          )
        end
      end
    end

    def dynamic_component_observer
      # SketchUp's Dynamic Components extension exposes no public API to force
      # a redraw after an external transform; $dc_observers is the only way to
      # reach it. Access is guarded by defined?/nil checks and rescued below.
      # rubocop:disable SketchupSuggestions/DynamicComponentInternals
      return nil unless defined?($dc_observers) && $dc_observers

      $dc_observers.get_latest_class
      # rubocop:enable SketchupSuggestions/DynamicComponentInternals
    rescue StandardError => e
      warn_overlay_issue('read dynamic component observer', e)
      nil
    end

    def dynamic_component_entity?(entity)
      return false unless entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)

      return true if entity.attribute_dictionary('dynamic_attributes', false)
      return false unless entity.is_a?(Sketchup::ComponentInstance)

      !entity.definition.attribute_dictionary('dynamic_attributes', false).nil?
    rescue StandardError => e
      warn_overlay_issue('detect dynamic component entity', e)
      false
    end

    def redraw_dynamic_components_for_smart_scale(session)
      dc = dynamic_component_observer
      return unless dc && session

      target = if session.respond_to?(:entity)
        session.entity
      else
        session[:entity]
      end
      return unless target
      return unless dynamic_component_entity?(target)
      return unless dc.respond_to?(:redraw)

      # Redraw only the selected top-level Dynamic Component.
      # Nested child instances can still share definitions with sibling copies,
      # so redrawing them individually can leak changes across copied objects.
      dc.redraw(target)
    rescue StandardError => e
      warn_overlay_issue('redraw dynamic components for smart scale', e)
      nil
    end

    def invalidate_smart_scale_bounds(state)
      if state.respond_to?(:entity) && state.entity.respond_to?(:invalidate_bounds)
        state.entity.invalidate_bounds
      end

      entities_parent = if state.respond_to?(:entity)
        smart_scale_entities(state.entity)&.parent
      elsif state.is_a?(Hash)
        state[:entities]&.parent
      end

      if entities_parent.respond_to?(:invalidate_bounds)
        entities_parent.invalidate_bounds
      end

      entries = if state.respond_to?(:instance_entries)
        state.instance_entries
      else
        state[:instances] || []
      end

      entries.each do |entry|
        instance = entry[:instance]
        next unless instance&.valid?
        next unless instance.respond_to?(:definition)
        next unless instance.definition.respond_to?(:invalidate_bounds)

        instance.definition.invalidate_bounds
      rescue StandardError => e
        warn_overlay_issue('invalidate nested smart scale bounds', e)
        next
      end
    rescue StandardError => e
      warn_overlay_issue('invalidate smart scale bounds', e)
      nil
    end

    def point_axis_value(point, axis_id)
      case axis_id
      when :x then point.x
      when :y then point.y
      when :z then point.z
      end
    end

    def point_with_axis_value(point, axis_id, value)
      case axis_id
      when :x then Geom::Point3d.new(value, point.y, point.z)
      when :y then Geom::Point3d.new(point.x, value, point.z)
      when :z then Geom::Point3d.new(point.x, point.y, value)
      end
    end

    def smart_scale_global_orientation?
      PLUGIN.gizmo_orientation == GLOBAL_ORIENTATION
    end

    def smart_scale_solver_axes_transformation
      Geom::Transformation.new(
        @model.axes.xaxis,
        @model.axes.yaxis,
        @model.axes.zaxis,
        @model.axes.origin
      )
    end

    def smart_scale_root_to_solver_transformation(entity, parent_root_to_solver = nil)
      return parent_root_to_solver * entity.transformation if parent_root_to_solver
      return IDENTITY unless smart_scale_global_orientation?

      smart_scale_solver_axes_transformation.inverse * entity.transformation
    end

    def transform_root_point_to_solver(point, root_to_solver_transformation)
      point.transform(root_to_solver_transformation)
    end

    def transform_solver_point_to_root(point, root_to_solver_transformation)
      point.transform(root_to_solver_transformation.inverse)
    end

    def transform_solver_transformation_to_root(transformation, root_to_solver_transformation)
      root_to_solver_transformation.inverse * transformation * root_to_solver_transformation
    end

    def smart_scale_profile(axis_id, vertices)
      values = vertices.map { |vertex| point_axis_value(vertex.position, axis_id) }.uniq.sort
      return nil if values.length < 4

      profile = {
        min: values.first,
        inner_min: values[1],
        inner_max: values[-2],
        max: values.last
      }
      return nil if profile[:inner_min] <= profile[:min]
      return nil if profile[:inner_max] >= profile[:max]
      return nil if profile[:inner_max] <= profile[:inner_min]

      profile
    end

    def smart_scale_profile_from_points(axis_id, points)
      values = points.map { |point| point_axis_value(point, axis_id) }.uniq.sort
      return nil if values.length < 4

      profile = {
        min: values.first,
        inner_min: values[1],
        inner_max: values[-2],
        max: values.last
      }
      return nil if profile[:inner_min] <= profile[:min]
      return nil if profile[:inner_max] >= profile[:max]
      return nil if profile[:inner_max] <= profile[:inner_min]

      # Reject profiles where the second-smallest or second-largest value
      # is too close to the actual extremes. This is the silent failure
      # mode for objects with chamfers, fillets, or thin bevels: the
      # tiny offset between the chamfer and the outer corner gets picked
      # as the entire :left or :right protected zone, leaving 99% of
      # the width to stretch and visibly distorting the edges.
      #
      # A real protected zone (table leg, frame stile) is at least 5%
      # of the total span; anything smaller is geometric noise.
      outer_span = profile[:max] - profile[:min]
      return nil unless outer_span > smart_scale_tolerance

      min_protected_width = outer_span * 0.05
      return nil if (profile[:inner_min] - profile[:min]) < min_protected_width
      return nil if (profile[:max] - profile[:inner_max]) < min_protected_width

      profile
    end

    def smart_scale_profile_from_largest_gap(axis_id, points)
      values = points.map { |point| point_axis_value(point, axis_id) }.uniq.sort
      return nil if values.length < 4

      outer_min = values.first
      outer_max = values.last
      outer_length = outer_max - outer_min
      return nil unless outer_length > smart_scale_tolerance

      best_gap = nil
      best_pair = nil

      1.upto(values.length - 3) do |i|
        gap_start = values[i]
        gap_end = values[i + 1]
        gap = gap_end - gap_start
        next unless gap > smart_scale_tolerance

        if best_gap.nil? || gap > best_gap
          best_gap = gap
          best_pair = [gap_start, gap_end]
        end
      end

      return nil unless best_pair
      return nil if best_gap < (outer_length * 0.1)

      # Reject wildly asymmetric profiles. For symmetric objects (window
      # frames, picture frames, etc.) both protected zones should be
      # roughly equal in width. If one side is more than 3x the other,
      # the "largest gap" is almost certainly an internal void rather
      # than the real inner stretch zone — applying it would translate
      # only one leg while leaving the other rigid, leaving the frame
      # asymmetric after scale. Bail out and let the next strategy try.
      left_zone  = best_pair[0] - outer_min
      right_zone = outer_max - best_pair[1]
      if left_zone > smart_scale_tolerance && right_zone > smart_scale_tolerance
        asymmetry = [left_zone, right_zone].max / [left_zone, right_zone].min
        return nil if asymmetry > 3.0
      end

      {
        min: outer_min,
        inner_min: best_pair[0],
        inner_max: best_pair[1],
        max: outer_max
      }
    end

    # Symmetric-features fallback. Designed for raw-vertex-only objects
    # like window frames where the legs/posts are the same width on
    # both sides. Walks inward from each end of the sorted vertex
    # values, finds the first feature edge on each side, takes the
    # smaller of the two as the protected width, and applies it
    # symmetrically. Guarantees inner_min and inner_max are equidistant
    # from outer_min and outer_max regardless of internal geometry.
    def smart_scale_profile_from_symmetric_features(axis_id, points)
      values = points.map { |point| point_axis_value(point, axis_id) }.uniq.sort
      return nil if values.length < 4

      outer_min = values.first
      outer_max = values.last
      outer_length = outer_max - outer_min
      return nil unless outer_length > smart_scale_tolerance

      # 0.5% of total length acts as a noise floor for "is this a real
      # feature or just a numerical artifact at the edge?"
      noise_floor = outer_length * 0.005

      left_feature  = values.find       { |v| (v - outer_min) > noise_floor }
      right_feature = values.reverse.find { |v| (outer_max - v) > noise_floor }
      return nil unless left_feature && right_feature

      left_width  = left_feature - outer_min
      right_width = outer_max - right_feature

      # Use the smaller of the two so neither side gets stretched into
      # its leg. Guarantees symmetric profile.
      protected_width = [left_width, right_width].min
      return nil unless protected_width > smart_scale_tolerance

      # Don't allow the inner zone to vanish — must be at least 10% of
      # outer length, otherwise this strategy isn't a good fit.
      return nil if (outer_length - 2 * protected_width) < (outer_length * 0.1)

      {
        min: outer_min,
        inner_min: outer_min + protected_width,
        inner_max: outer_max - protected_width,
        max: outer_max
      }
    end

    def smart_scale_profile_from_protected_ends(axis_id, points, allowed: false)
      # Final synthetic-profile fallback. Picks 20% on each end as the
      # "protected" zone and stretches the middle 60%. This is geometry-
      # blind — it doesn't look at where the actual features are — so it
      # often distorts objects whose real protected zones are wider or
      # narrower than 20%.
      #
      # Only run this when the caller explicitly opts in (allowed: true).
      # The previous behavior of running it unconditionally meant ANY
      # object with no clear inner profile got an arbitrary 20/60/20
      # split applied, which silently degraded scale quality for
      # unsuitable selections instead of falling through to :basic mode.
      return nil unless allowed

      values = points.map { |point| point_axis_value(point, axis_id) }.compact
      return nil if values.length < 2

      outer_min, outer_max = values.minmax
      outer_length = outer_max - outer_min
      return nil unless outer_length > smart_scale_tolerance

      protected_width = outer_length * 0.2
      protected_width = [protected_width, outer_length * 0.45].min
      inner_min = outer_min + protected_width
      inner_max = outer_max - protected_width
      return nil unless inner_max > inner_min

      {
        min: outer_min,
        inner_min: inner_min,
        inner_max: inner_max,
        max: outer_max
      }
    end

    def smart_scale_bounds_range(bounds, axis_id, root_to_solver_transformation = IDENTITY)
      values = 0.upto(7).map do |i|
        point_axis_value(transform_root_point_to_solver(bounds.corner(i), root_to_solver_transformation), axis_id)
      end
      [values.min, values.max]
    end

    def transform_point_by_instance_path(point, path)
      path.inject(point.clone) { |pt, instance| pt.transform(instance.transformation) }
    end

    def transform_point_from_root_to_local(point, path)
      path.reverse.inject(point.clone) { |pt, instance| pt.transform(instance.transformation.inverse) }
    end

    def transformation_for_instance_path(path)
      path.inject(IDENTITY) { |tr, instance| tr * instance.transformation }
    end

    def transform_root_transformation_to_local(transformation, path)
      return transformation if path.empty?

      path_tr = transformation_for_instance_path(path)
      path_tr.inverse * transformation * path_tr
    end

    def instance_path_bounds_range(instance, path, axis_id, root_to_solver_transformation = IDENTITY)
      values = 0.upto(7).map do |i|
        point_axis_value(
          transform_root_point_to_solver(transform_point_by_instance_path(instance.bounds.corner(i), path), root_to_solver_transformation),
          axis_id
        )
      end
      [values.min, values.max]
    end

    def smart_scale_axis_transform(axis_id, origin, factor)
      case axis_id
      when :x
        Geom::Transformation.scaling(origin, factor, 1.0, 1.0)
      when :y
        Geom::Transformation.scaling(origin, 1.0, factor, 1.0)
      when :z
        Geom::Transformation.scaling(origin, 1.0, 1.0, factor)
      end
    end

    def smart_scale_tolerance
      0.001
    end

    def smart_scale_profile_from_part_ranges(axis_id, points, ranges)
      values = points.map { |point| point_axis_value(point, axis_id) }.uniq.sort
      return nil if values.length < 4

      outer_min = values.first
      outer_max = values.last
      tol = smart_scale_tolerance
      left_ranges = ranges.select { |min, max| min <= outer_min + tol && max < outer_max - tol }
      right_ranges = ranges.select { |min, max| max >= outer_max - tol && min > outer_min + tol }
      return nil if left_ranges.empty? || right_ranges.empty?

      inner_min = left_ranges.map(&:last).max
      inner_max = right_ranges.map(&:first).min
      return nil if inner_min <= outer_min
      return nil if inner_max >= outer_max
      return nil if inner_max <= inner_min

      {
        min: outer_min,
        inner_min: inner_min,
        inner_max: inner_max,
        max: outer_max
      }
    end

    def classify_smart_scale_range(min, max, profile)
      tol = smart_scale_tolerance
      outer_min = profile[:min]
      outer_max = profile[:max]
      inner_min = profile[:inner_min]
      inner_max = profile[:inner_max]

      return :full_span if min <= outer_min + tol && max >= outer_max - tol
      return :left if max <= inner_min + tol
      return :right if min >= inner_max - tol
      return :middle if min >= inner_min - tol && max <= inner_max + tol

      center = (min + max) / 2.0
      return :left if center <= inner_min
      return :right if center >= inner_max
      return :middle if center > inner_min && center < inner_max

      :unsupported
    end

    def build_smart_scale_gesture_state_for_entity(entity, axis_id, mask, data = nil, depth = 0, parent_root_to_solver = nil)
      root_entities = smart_scale_entities(entity)
      return nil unless root_entities
      root_to_solver_transformation = smart_scale_root_to_solver_transformation(entity, parent_root_to_solver)

      # Reject curved edges (arcs, circles). Their intermediate vertices
      # add many extra values along the scaling axis that distort profile
      # detection, and SmartScaleApplier moves vertices individually with
      # different offsets — that would break the curve definition while
      # leaving the vertex positions stale. Only straight edges contribute
      # to the smart scale gesture.
      edges = root_entities.grep(Sketchup::Edge).reject(&:curve)

      child_instances = collect_nested_smart_scale_instances(root_entities, axis_id, [], root_to_solver_transformation)

      vertex_entries = edges.flat_map(&:vertices).uniq.map do |vertex|
        {
          vertex: vertex,
          entities: root_entities,
          original_local_point: vertex.position.clone,
          original_root_point: transform_root_point_to_solver(vertex.position.clone, root_to_solver_transformation)
        }
      end

      return nil if vertex_entries.empty? && child_instances.empty?

      profile_points = vertex_entries.map { |entry| entry[:original_root_point] }
      child_instances.each do |entry|
        0.upto(7) do |i|
          profile_points << transform_root_point_to_solver(
            transform_point_by_instance_path(entry[:instance].bounds.corner(i), entry[:path] || []),
            root_to_solver_transformation
          )
        end
      end

      profile = smart_scale_profile_from_part_ranges(
        axis_id,
        profile_points,
        child_instances.map { |entry| [entry[:min], entry[:max]] }
      )
      profile ||= smart_scale_profile_from_largest_gap(axis_id, profile_points)
      # Symmetric-features fallback for raw-vertex-only frames (window
      # frames, picture frames, etc.) where the largest gap might be an
      # internal void rather than the inner stretch zone. Guarantees a
      # symmetric profile so both legs translate equally.
      profile ||= smart_scale_profile_from_symmetric_features(axis_id, profile_points)
      profile ||= smart_scale_profile_from_points(axis_id, profile_points)
      # Only invoke the synthetic 20/60/20 fallback when there are child
      # instances to anchor the outer extents in real geometry. For raw
      # vertex-only objects, falling through to nil here lets the code
      # below correctly switch to :basic mode (uniform scale) instead of
      # inventing a profile that distorts the geometry.
      profile ||= smart_scale_profile_from_protected_ends(
        axis_id,
        profile_points,
        allowed: !child_instances.empty?
      )

      if profile.nil? && child_instances.empty? && !vertex_entries.empty?
        reference_length = profile_points.map { |point| point_axis_value(point, axis_id) }.minmax.inject(:-)&.abs
        reference_length = data[4] || scale_reference_length(mask) unless reference_length && reference_length > 0
        return nil unless reference_length && reference_length > 0

        return SmartScaleGestureState.new(
          entity: entity,
          axis_id: axis_id,
          profile: nil,
          reference_length: reference_length,
          vertex_entries: [],
          instance_entries: [],
          mask: mask,
          mode: :basic,
          original_entity_transformation: entity.transformation.clone,
          anchor_point: data && (data[5] || scale_anchor_point(mask, data)),
          gizmo_transformation: data ? (data[6] || scale_gizmo_transformation(data)) : nil,
          root_to_solver_transformation: root_to_solver_transformation
        )
      end

      return nil unless profile

      child_instances.each do |entry|
        kind = classify_smart_scale_range(entry[:min], entry[:max], profile)
        return nil if kind == :unsupported

        entry[:kind] = kind
      end

      frame_like_layout = child_instances.any? { |entry| [:left, :right, :middle].include?(entry[:kind]) }

      # Recursion into :full_span children is disabled — frame math for
      # nested states is incorrect and produces exploded geometry. The
      # else branch in SmartScaleApplier.apply! handles full_span cleanly
      # by uniform scaling, which is the right behavior for most cases.
      _ = frame_like_layout

      reference_length = profile[:max] - profile[:min]
      return nil unless reference_length > 0

      SmartScaleGestureState.new(
        entity: entity,
        axis_id: axis_id,
        profile: profile,
        reference_length: reference_length,
        vertex_entries: vertex_entries,
        instance_entries: child_instances,
        mask: mask,
        root_to_solver_transformation: root_to_solver_transformation
      )
    end

    def build_smart_scale_gesture_state(data)
      return nil unless smart_scale_supported?(data)

      entity = smart_scale_entity
      return nil unless entity&.valid?

      axis_id = smart_scale_axis_id(data[3])
      return nil unless axis_id

      build_smart_scale_gesture_state_for_entity(entity, axis_id, data[3], data)
    end

    # Builds smart scale states for every entity in the selection. Returns
    # an array of [entity, state] pairs, omitting any that couldn't have a
    # state built. Used by the multi-selection scale flow so each entity
    # gets its own profile and classification — the selections may all
    # look similar but they live in different transformations and need
    # independent treatment.
    def build_smart_scale_gesture_states_for_selection(data)
      return [] unless smart_scale_supported?(data)

      axis_id = smart_scale_axis_id(data[3])
      return [] unless axis_id

      results = []
      @selection.to_a.each do |entity|
        prepared = prepare_smart_scale_entity(entity)
        next unless prepared&.valid?
        state = build_smart_scale_gesture_state_for_entity(prepared, axis_id, data[3], data)
        results << [prepared, state] if state
      end
      results
    end

    # Apply a per-entity ratio to multiple states. Returns true if every
    # apply succeeds. Aborts and returns false on first failure so the
    # caller can roll back the operation cleanly.
    def apply_smart_scale_to_states(states, ratio, data = nil)
      return false if states.empty?

      # Resolve every state's uniqueness immediately before mutating,
      # not just once when the states array was originally built --
      # covers both the fresh-build case (cheap no-op) and a cached
      # @smart_scale_gesture_states array reused across multiple drag
      # frames. Mutates `states` in place so callers holding the same
      # array reference (used afterward for the VCB label and deferred
      # redraws) see the resolved states too.
      states.map! { |entity, state| [entity, resolve_smart_scale_state(state, data)] }

      # If resolving uniqueness for ANY entity failed to produce a valid
      # rebuilt state, fail the whole batch before mutating anything --
      # no partial application, no falling back to a stale/mismatched
      # state for that entity.
      return false if states.any? { |_entity, state| state.nil? }

      states.all? do |_entity, state|
        SmartScaleApplier.apply!(self, state, ratio)
      end
    end

    def ensure_smart_scale_gesture(data)
      entity = smart_scale_entity
      axis_id = smart_scale_axis_id(data[3])
      mask = data[3]

      if @smart_scale_gesture&.matches?(entity, axis_id, mask) && @smart_scale_gesture.valid?
        @smart_scale_gesture
      else
        @smart_scale_gesture = build_smart_scale_gesture_state(data)
      end
    end

    # Cached multi-selection version of ensure_smart_scale_gesture. During
    # a drag, the gesture fires many times per second; we only want to
    # rebuild the per-entity states when the selection or axis actually
    # changes, otherwise reuse the cached array. State validity is checked
    # against the first state — they share axis_id and mask, so if one is
    # stale they all are.
    def ensure_smart_scale_gesture_states(data)
      axis_id = smart_scale_axis_id(data[3])
      mask = data[3]
      first_entity = @selection && @selection[0]

      if @smart_scale_gesture_states &&
         !@smart_scale_gesture_states.empty? &&
         @smart_scale_gesture_states.first[1].matches?(first_entity, axis_id, mask) &&
         @smart_scale_gesture_states.all? { |_e, s| s.valid? } &&
         @smart_scale_gesture_states.length == @selection.length
        @smart_scale_gesture_states
      else
        @smart_scale_gesture_states = build_smart_scale_gesture_states_for_selection(data)
      end
    end

    def defer_smart_scale_redraw(state)
      return unless state

      UI.start_timer(0, false) do
        next unless state.valid?

        invalidate_smart_scale_bounds(state)
        update_gizmo if @gizmo && state.entity == smart_scale_entity
        @model.active_view.invalidate if @model&.active_view
      end
    end

    def reset_smart_scale_session
      @smart_scale_session = nil
    end

    def stop
    end

    def onCancel(reason, view)
      if reason == 0 && @gizmo.active?
        selected = @selection.to_a
        @gizmo.cancel
        @model.abort_operation
        reset_smart_scale_session
        reset_smart_scale_gesture
        @ctrl_array_session = nil
        @selection.clear
        @selection.add(selected)
        update_gizmo
        view.invalidate
      end
    end

    def getMenu(menu, _flags, x, y, view)
      return false if inert?
      return false unless gizmo_hovering?(x, y, view)

      ['Global', 'Object'].each_with_index do |name, i|
        cmd = menu.add_item(name) do
          # Gizmo actions from the context menu carry the same fresh license
          # check as a gesture; Preferences and Hide stay ungated.
          next unless license_permits_interaction?

          PLUGIN.gizmo_orientation = i
          update_gizmo
        end
        menu.set_validation_proc(cmd) { PLUGIN.gizmo_orientation == i ? MF_CHECKED : MF_UNCHECKED }
      end
      menu.add_separator
      menu.add_item('Reset Pivot To Selection Center') { set_pivot_to_selection_center if license_permits_interaction? }
      menu.add_item('Set Pivot To Model Axes Origin') { set_pivot_to_model_origin if license_permits_interaction? }
      if selected_one_object?
        menu.add_item('Set Pivot To Object Origin') { set_pivot_to_object_origin if license_permits_interaction? }
      end
      menu.add_separator
      menu.add_item('Preferences...') { PLUGIN.open_preferences }
      menu.add_separator
      # Hide never needs a license: it goes straight to hide_gizmo, with no
      # lookup and no message.
      menu.add_item('Hide') do
        PLUGIN.hide_gizmo
        Sketchup.active_model.tools.pop_tool
      end

      true
    end

    def onUserText(text, view)
      if @ctrl_array_session
        internal_count = parse_ctrl_drag_array_count(text)
        unless internal_count.nil?
          apply_ctrl_drag_array(internal_count, :internal, view)
          return
        end

        external_count = parse_ctrl_drag_external_array_count(text)
        unless external_count.nil?
          apply_ctrl_drag_array(external_count, :external, view)
          return
        end
      end

      return unless edited?

      data = @last_transform[2]
      if data[0] == :scale && smart_scale_supported?(data)
        return unless start_licensed_operation('Smart Scale')

        begin
          state = @last_smart_scale_session
          state = build_smart_scale_gesture_state(data) unless state&.valid?
          state = resolve_smart_scale_state(state, data)
          unless state
            @model.abort_operation
            UI.messagebox('Smart Scale failed.')
            return
          end

          ratio = parse_smart_scale_ratio(text, state, data)
          if ratio.nil? || ratio <= 0
            @model.abort_operation
            UI.messagebox('Invalid scale')
            return
          end

          unless SmartScaleApplier.apply!(self, state, ratio)
            @model.abort_operation
            UI.messagebox('Smart Scale failed.')
            return
          end

          @model.commit_operation
          @last_smart_scale_session = state
          data = data.dup
          data[2] = state.ratio
          @last_transform = [IDENTITY, IDENTITY, data]
          Sketchup.vcb_label = 'Scale'
          Sketchup.vcb_value = format_scale_display(state.ratio, state.reference_length)
          update_gizmo
          view.invalidate
          defer_smart_scale_redraw(state)
          return
        rescue StandardError => e
          @model.abort_operation
          UI.messagebox("Smart Scale failed.\n\n#{e.message}")
          return
        end
      end

      action = data[0]
      case action
      when :move
        value = text.to_l
      when :rotate
        value = text.to_f.degrees
      when :scale
        value = parse_scale_user_text(text, data)
        return UI.messagebox('Invalid scale') if value.nil? || value == 0
      end

      return unless start_licensed_operation('Re-edit')

      reEdit(value)
      @model.commit_operation

      if action == :scale
        Sketchup.vcb_label = 'Scale'
        Sketchup.vcb_value = format_scale_display(data[2], data[4])
      end
      update_gizmo
      view.invalidate
    rescue ArgumentError
      view.tooltip = 'Invalid length'
    end

    def reEdit(value)
      tr, t_total, data = @last_transform
      action = data[0]
      case action
      when :move
        vec = data[1].clone
        vec.length = value
        tr = Geom::Transformation.translation(vec)
      when :rotate
        data = [data[0], data[1], data[2], value]
        tr = rotate_transformation(data[1], data[2], value)
      when :scale
        if smart_scale_supported?(data)
          state = @last_smart_scale_session
          state = build_smart_scale_gesture_state(data) unless state&.valid?
          return unless state

          state = resolve_smart_scale_state(state, data)
          raise ArgumentError, 'Smart Scale failed' unless state

          data = data.dup
          unless SmartScaleApplier.apply!(self, state, value)
            raise ArgumentError, 'Smart Scale failed'
          end

          @last_smart_scale_session = state
          data[2] = state.ratio
          @last_transform = [IDENTITY, IDENTITY, data]
          return
        end
        marks = data[3]
        tr = scale_transformation(marks, value, data)
        # Keeps data[2] (ratio) current so a later "/N" division -- or
        # any other edit that reads "the currently displayed dimension"
        # -- divides from what THIS edit just set, not a stale ratio
        # left over from the drag that started the session.
        data[2] = value
      end

      @model.active_entities.transform_entities(tr * t_total.inverse, selected_entities)
      t_total = tr
      @last_transform = [tr, t_total, data]
    end

    def start_rotate_quick_edit(direction)
      remember_rotate_axis(direction)
      axis = direction.clone
      axis.length = 1.0 if axis.valid?
      data = [:rotate, @gizmo.origin.clone, axis, 0.degrees]
      @model.tools.push_tool(self) unless active_itself?
      self.active_gizmo = true
      @last_transform = [IDENTITY, IDENTITY, data]
      @edit_mouse = @mouse
      Sketchup.vcb_label = 'Angle'
      Sketchup.vcb_value = Sketchup.format_angle(0.degrees)
      Sketchup.set_status_text('Type a rotation in Measurements or use the arrow-key presets.')
      view = @model&.active_view
      view.invalidate if view
    end

    def rotate_edit_active?
      edited? && @last_transform[2][0] == :rotate
    end

    def rotate_arrow_value(key)
      case key
      when LEFT_ARROW_KEY
        PLUGIN.rotate_left_arrow_step
      when RIGHT_ARROW_KEY
        PLUGIN.rotate_right_arrow_step
      when UP_ARROW_KEY
        PLUGIN.rotate_up_arrow_step
      when DOWN_ARROW_KEY
        PLUGIN.rotate_down_arrow_step
      end
    end

    def remember_rotate_axis(direction)
      axis_id = axis_id_for_direction(direction)
      @last_rotate_axis_id = axis_id if axis_id
    end

    def axis_id_for_direction(direction)
      return nil unless @gizmo && direction

      if direction.parallel?(@gizmo.axes.x.direction)
        :x
      elsif direction.parallel?(@gizmo.axes.y.direction)
        :y
      elsif direction.parallel?(@gizmo.axes.z.direction)
        :z
      end
    end

    def direction_for_axis_id(axis_id)
      return nil unless @gizmo

      case axis_id
      when :x
        @gizmo.axes.x.direction.clone
      when :y
        @gizmo.axes.y.direction.clone
      when :z
        @gizmo.axes.z.direction.clone
      when nil
        @gizmo.axes.z.direction.clone
      end
    end

    def rotate_shortcut_axis_id
      if PLUGIN.respond_to?(:rotate_arrow_remember_axis?) &&
         !PLUGIN.rotate_arrow_remember_axis?
        return PLUGIN.rotate_arrow_axis.to_s.downcase.to_sym
      end

      @last_rotate_axis_id
    end

    def rotate_edit_matches_shortcut_axis?
      return true unless PLUGIN.respond_to?(:rotate_arrow_remember_axis?)
      return true if PLUGIN.rotate_arrow_remember_axis?
      return false unless rotate_edit_active?

      data = @last_transform[2]
      axis_id_for_direction(data[2]) == rotate_shortcut_axis_id
    end

    def rotate_shortcut_ready?
      return false unless PLUGIN.rotate_arrow_shortcuts_enabled?
      return false unless enabled?
      return false unless @gizmo
      return false unless @selection && @selection.length > 0
      return false if @gizmo.active?
      return false unless gizmo_hovering?

      !direction_for_axis_id(rotate_shortcut_axis_id).nil?
    end

    def apply_rotate_arrow(value, view)
      return unless rotate_edit_active?

      data = @last_transform[2]
      origin = data[1]
      axis = data[2]
      current_angle = data[3] || 0.degrees
      increment = value.to_f.degrees
      angle = current_angle + increment
      t_increment = rotate_transformation(origin, axis, increment)
      t_total = rotate_transformation(origin, axis, angle)

      return unless start_licensed_operation('Re-edit')

      @model.active_entities.transform_entities(t_increment, selected_entities)
      @model.commit_operation

      @last_transform = [t_increment, t_total, [:rotate, origin, axis, angle]]
      update_gizmo
      @edit_mouse = @mouse
      Sketchup.vcb_label = 'Angle'
      Sketchup.vcb_value = Sketchup.format_angle(angle)
      view.invalidate
    end

    def rotate_transformation(origin, axis, angle)
      rotation_axis = axis.clone
      rotation_axis.length = 1.0 if rotation_axis.valid?
      Geom::Transformation.rotation(origin, rotation_axis, angle)
    end

    def getExtents
      bb = @model.bounds
      
      @model.selection.each do |e|
        bb.add(e.bounds)
      end

      bb
    end

    def onKeyDown(key, _repeat, _flags, view)
      return if inert?

      if key == MOVE_TOOL_KEY
        activate_native_move_tool(view)
        return
      end

      rotate_value = rotate_arrow_value(key)
      if rotate_value
        if rotate_edit_active?
          unless rotate_edit_matches_shortcut_axis?
            start_rotate_quick_edit(direction_for_axis_id(rotate_shortcut_axis_id))
          end
          apply_rotate_arrow(rotate_value, view)
          return
        elsif rotate_shortcut_ready?
          start_rotate_quick_edit(direction_for_axis_id(rotate_shortcut_axis_id))
          apply_rotate_arrow(rotate_value, view)
          return
        end
      end

      if key == COPY_MODIFIER_KEY
        @copy = true
        view.invalidate
      end
    end

    def onKeyUp(key, _repeat, _flags, view)
      if key == COPY_MODIFIER_KEY
        @copy = false
        view.invalidate
      end
    end

    def draw(view)
      # Nothing is drawn unless the most recent silent authorization said yes;
      # draw never asks SketchUp about the license itself.
      return unless display_authorized?
      return if @native_tool_override
      return unless active_gizmo? && @gizmo
      sync_gizmo_refresh

      @gizmo.draw(view) if @gizmo && @selection.length > 0

      draw_origin_bounds(view) if @gizmo.active? && @copy
    end

    def draw_origin_bounds(view)
      color = inverse_color(@model.rendering_options['HighlightColor'].to_a)
      draw_bounds(view, @gizmo.bounds, @gizmo.transformation, color)
    end

    def inverse_color(rgba)
      r, g, b, a = rgba
    
      inverse_r = 255 - r
      inverse_g = 255 - g
      inverse_b = 255 - b
    
      [inverse_r, inverse_g, inverse_b, a]
    end

    def draw_bounds(view, bb, tr = IDENTITY, color = [255, 0, 0])
      return unless bb
      return if bb.empty?

      pts = 0.upto(7).map { |i| bb.corner(i).transform(tr) }
      view.line_width = 2
      view.line_stipple = ''
      view.drawing_color = color
    
      top = [pts[0], pts[2], pts[3], pts[1]]
      bottom = [pts[4], pts[6], pts[7], pts[5]]
      lines = (top + [top[0]]).each_cons(2).to_a
      lines += (bottom + [bottom[0]]).each_cons(2).to_a
      lines += top.zip(bottom)
      
      view.draw(GL_LINES, lines.flatten) 
    end

    def inspect
      name = self.class.name.split('::').last
      module_name = self.class.name.split('::')[-2]
      hex_id = format('0x%x', (object_id << 1))
      "#<#{module_name}::#{name}:#{hex_id}>"
    end
  end
end
