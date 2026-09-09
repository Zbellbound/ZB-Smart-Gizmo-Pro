require_relative 'load_plugin'

module Zbellbound::SmartGizmoPro
  # Minimal stand-in for Zbellbound::SmartGizmoPro::Manipulator. Real mouse/axis-drag
  # math lives in gizmo.rb and isn't needed to exercise GizmoOverlay's
  # on_transform / on_transform_end handlers -- tests drive those handlers
  # directly with synthetic (data) tuples, same shape ScaleGizmo produces.
  class FakeManipulator
    include TransformCallbacks

    attr_accessor :bounds, :transformation, :origin

    def initialize
      @bounds = Geom::BoundingBox.new
      @transformation = IDENTITY
      @origin = ORIGIN.clone
    end

    def xaxis=(_v); end
    def yaxis=(_v); end
    def zaxis=(_v); end
    def size=(_v); end

    FakeOriginControl = Struct.new(:size)

    def origin_control
      @origin_control ||= FakeOriginControl.new(0)
    end

    # A minimal stand-in for the three real Axis objects (each of which
    # exposes a #direction) -- needed so axis_id_for_direction (used by
    # the on_click move dialog, e.g. to build the "Number of copies"
    # field) can resolve a clicked direction to :x/:y/:z instead of
    # crashing on `[].x.direction`.
    FakeAxis = Struct.new(:direction)

    def axes
      @axes ||= [FakeAxis.new(X_AXIS), FakeAxis.new(Y_AXIS), FakeAxis.new(Z_AXIS)]
    end

    def on_origin_change(&block)
      @callback_origin = block
    end

    def on_origin_change_end(&block)
      @callback_origin_end = block
    end

    # Real Manipulator#active? reports whether a drag is currently in
    # progress. Tests never call this harness mid-drag (on_transform_end
    # has always already fired), so always-false is accurate for every
    # existing use -- needed for selection_changed's
    # `sync_gizmo_refresh unless @gizmo&.active?` guard.
    def active?
      false
    end
  end
end

module TestHarness
  module_function

  # Builds a GizmoOverlay instance with just enough state wired up to run
  # bind_gizmo_callbacks and drive its on_transform / on_transform_end
  # handlers, bypassing Sketchup::Overlay's real lifecycle (start/enabled=
  # etc.), which the plugin doesn't need for this logic.
  def build_overlay(model:, selection:)
    overlay = Zbellbound::SmartGizmoPro::GizmoOverlay.allocate
    overlay.instance_variable_set(:@model, model)
    overlay.instance_variable_set(:@host_model, model)
    overlay.instance_variable_set(:@selection, selection)
    overlay.instance_variable_set(:@view, model.active_view)
    overlay.instance_variable_set(:@gizmo, Zbellbound::SmartGizmoPro::FakeManipulator.new)
    overlay.instance_variable_set(:@gizmo_model_id, model.object_id)
    overlay.instance_variable_set(:@custom_origin, nil)
    overlay.instance_variable_set(:@copy, false)
    overlay.instance_variable_set(:@last_transform, nil)
    overlay.instance_variable_set(:@refresh_generation, 0)
    overlay.instance_variable_set(:@tool_active, false)
    overlay.bind_gizmo_callbacks
    overlay
  end

  def gizmo_of(overlay)
    overlay.instance_variable_get(:@gizmo)
  end

  # Fires callback_start/callback/callback_end in sequence, the same way
  # ScaleGizmo#onLButtonDown / onMouseMove / onLButtonUp would, for a
  # single-axis scale gesture driven to its final ratio in one mouse-move
  # frame (increment == total, since we start from identity).
  def drive_scale_drag(overlay, axis_id:, ratio:, origin: ORIGIN.clone)
    gizmo = gizmo_of(overlay)
    mask = case axis_id
           when :x then [true, false, false]
           when :y then [false, true, false]
           when :z then [false, false, true]
           end

    start_cb = gizmo.instance_variable_get(:@callback_start)
    transform_cb = gizmo.instance_variable_get(:@callback)
    end_cb = gizmo.instance_variable_get(:@callback_end)

    start_cb&.call('Scale')

    scale_x = axis_id == :x ? ratio : 1.0
    scale_y = axis_id == :y ? ratio : 1.0
    scale_z = axis_id == :z ? ratio : 1.0
    t_total = Geom::Transformation.scaling(origin, scale_x, scale_y, scale_z)
    # Pre-populate the enriched 7-element form (enrich_scale_data is a
    # no-op once data.length > 6) so the smart-scale gesture path doesn't
    # need to reach into a real Manipulator for bounds/anchor/gizmo_tr.
    data = [:scale, origin, ratio, mask, 1.0, origin.clone, IDENTITY]
    transform_cb.call(t_total, t_total, data)

    end_cb&.call
    overlay
  end

  # Fires callback_start/callback/callback_end for a single-axis or
  # plane move gesture driven to its final position in one mouse-move
  # frame (increment == total, since we start from identity) -- the same
  # [:move, v_total] payload shape MoveGizmo#move_event and
  # PlaneMoveGizmo#move_event produce in gizmo.rb. Set `copy: true` to
  # exercise the Ctrl-drag copy branch of on_transform_end.
  def drive_move_drag(overlay, vector:, copy: false)
    gizmo = gizmo_of(overlay)
    start_cb = gizmo.instance_variable_get(:@callback_start)
    transform_cb = gizmo.instance_variable_get(:@callback)
    end_cb = gizmo.instance_variable_get(:@callback_end)

    overlay.instance_variable_set(:@copy, copy)

    start_cb&.call('Move')

    t_total = Geom::Transformation.translation(vector)
    data = [:move, vector.clone]
    transform_cb.call(t_total, t_total, data)

    end_cb&.call
    overlay
  end
end
