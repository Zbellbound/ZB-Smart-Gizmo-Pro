module Zbellbound::SmartGizmoPro
  class GizmoObserver
    ACTIVATION_DELAYS = [0.0, 0.1, 0.35, 0.75].freeze

    def initialize
      @observed_models = {}
      @activation_generations = {}
      @app_observer = AppObserverBridge.new(self)
      @frame_change_observer = FrameChangeObserverBridge.new(self)
      Sketchup.add_observer(@app_observer)
      Sketchup::Pages.add_frame_change_observer(@frame_change_observer)
    end

    def attach_to_active_model
      attach_observers(Sketchup.active_model)
    end

    def selection_changed(model, selection)
      overlay = PLUGIN.active_overlay(model)
      return unless overlay&.enabled?

      overlay.selection_changed(selection)
    end

    def tool_changed(model, tool_name)
      overlay = PLUGIN.active_overlay(model)
      return unless overlay&.enabled?

      overlay.tool_changed(tool_name)
    end

    def on_transaction(model)
      overlay = PLUGIN.active_overlay(model)
      return unless overlay&.enabled?

      overlay.update_gizmo
    end

    def attach_observers(model)
      return unless model

      key = model.object_id
      unless @observed_models[key]
        model_observer = GizmoModelObserver.new(self, model)
        tools_observer = GizmoToolsOb.new(self, model)
        selection_observer = GizmoSelectionObserver.new(self, model)

        model.add_observer(model_observer)
        model.tools.add_observer(tools_observer)
        model.selection.add_observer(selection_observer)

        @observed_models[key] = {
          model: model_observer,
          tools: tools_observer,
          selection: selection_observer
        }
      else
        # SketchUp on Windows reuses the same Sketchup::Model Ruby object
        # when File→Open loads a different .skp file into the same window.
        # The model's `selection` and `tools` collections are *replaced*
        # by the new file load, so observers attached to the old
        # collections receive no events. Re-attach to the current ones.
        # (model itself is the same Ruby object, so its observer is fine.)
        existing = @observed_models[key]
        model.selection.add_observer(existing[:selection]) if existing[:selection]
        model.tools.add_observer(existing[:tools]) if existing[:tools]
      end

      overlay = ensure_overlay(model)
      activate_overlay(model, overlay)
      queue_overlay_activation(model)
    end

    def ensure_overlay(model)
      return unless model
      overlay = model.overlays.to_a.find { |item| item.is_a?(Zbellbound::SmartGizmoPro::GizmoOverlay) }
      return overlay if overlay

      model.overlays.add(Zbellbound::SmartGizmoPro::GizmoOverlay.new)
    rescue ArgumentError => e
      warn_overlay_issue('ensure overlay', e)
      nil
    end

    def activate_overlay(model, overlay = nil)
      return unless model

      overlay ||= ensure_overlay(model)
      return unless overlay

      overlay.bind_model(model) if overlay.respond_to?(:bind_model)
      overlay.enabled = true unless overlay.enabled?
      overlay.start(model)
      overlay.selection_changed(model.selection)
      model.active_view.invalidate if model.active_view
      overlay
    rescue StandardError => e
      warn_overlay_issue('activate overlay', e)
      nil
    end

    def recreate_overlay(model)
      return unless model

      existing = model.overlays.to_a.find { |overlay| overlay.is_a?(Zbellbound::SmartGizmoPro::GizmoOverlay) }
      model.overlays.remove(existing) if existing
      overlay = model.overlays.add(Zbellbound::SmartGizmoPro::GizmoOverlay.new)
      activate_overlay(model, overlay)
      queue_overlay_activation(model)
    rescue ArgumentError => e
      warn_overlay_issue('recreate overlay', e)
      nil
    end

    def queue_overlay_activation(model)
      return unless model

      key = model.object_id
      generation = @activation_generations.fetch(key, 0) + 1
      @activation_generations[key] = generation

      ACTIVATION_DELAYS.each do |delay|
        UI.start_timer(delay, false) do
          next unless model&.valid?
          next unless @activation_generations[key] == generation

          overlay = ensure_overlay(model)
          if overlay
            activate_overlay(model, overlay)
          else
            recreate_overlay(model)
          end
        end
      end
    end

    def scene_changed(model)
      return unless model

      overlay = ensure_overlay(model)
      activate_overlay(model, overlay)
      queue_overlay_activation(model)
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

    class AppObserverBridge < Sketchup::AppObserver
      def initialize(observer)
        @observer = observer
      end

      def expectsStartupModelNotifications
        true
      end

      def onNewModel(model)
        @observer.attach_observers(model)
      end

      def onOpenModel(model)
        @observer.attach_observers(model)
      end

      def onActivateModel(model)
        @observer.attach_observers(model)
      end
    end

    class FrameChangeObserverBridge
      def initialize(observer)
        @observer = observer
      end

      def frameChange(_from_page, to_page, percent_done)
        return unless percent_done >= 0.999

        model = if to_page.respond_to?(:model)
          to_page.model
        elsif Sketchup.respond_to?(:active_model)
          Sketchup.active_model
        end
        @observer.scene_changed(model) if model
      end
    end

    class GizmoModelObserver < Sketchup::ModelObserver
      def initialize(observer, model)
        @observer = observer
        @model = model
      end

      def onTransactionCommit(_model)
        on_transaction
      end

      def onTransactionRedo(_model)
        on_transaction
      end

      def onTransactionUndo(_model)
        on_transaction
      end

      def on_transaction
        @observer.on_transaction(@model)
      end
    end

    class GizmoSelectionObserver < Sketchup::SelectionObserver
      def initialize(observer, model)
        @observer = observer
        @model = model
      end

      def onSelectionBulkChange(selection)
        selection_changed(selection)
      end

      def onSelectionAdded(selection, _entity)
        selection_changed(selection)
      end

      def onSelectionCleared(selection)
        selection_changed(selection)
      end

      def selection_changed(selection)
        @observer.selection_changed(@model, selection)
      end
    end

    class GizmoToolsOb < Sketchup::ToolsObserver
      def initialize(observer, model)
        @observer = observer
        @model = model
      end

      def onActiveToolChanged(_model, tool_name, _tool_id)
        tool_name = fix_mac_tool_name(tool_name)

        @observer.tool_changed(@model, tool_name)
      end

      def fix_mac_tool_name(tool_name)
        if tool_name == 'eTool'
          tool_name = 'ScaleTool'
        elsif tool_name == 'ool'
          tool_name = 'MoveTool'
        elsif tool_name == 'onentCSTool'
          tool_name = 'ComponentCSTool'
        elsif tool_name == 'PullTool'
          tool_name = 'PushPullTool'
        end
        tool_name
      end
    end
  end
end
