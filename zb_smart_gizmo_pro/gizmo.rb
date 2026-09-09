# Copyright Peter Zbel - Zbellbound.com
# ZB Smart Gizmo Pro

# @since 2.7.0
module Zbellbound::SmartGizmoPro
  # @since 2.7.0
  class Manipulator
    include TransformCallbacks

    CLR_X_AXIS    = Sketchup::Color.new(255, 0,   0)
    CLR_Y_AXIS    = Sketchup::Color.new(0, 128,   0)
    CLR_Z_AXIS    = Sketchup::Color.new(0, 0, 255)
    CLR_SELECTED  = Sketchup::Color.new(255, 255, 0)
    
    attr_reader(:origin, :axes, :planes)
    attr_reader(:origin_control)
    attr_reader(:bounds, :transformation)
    attr_accessor(:size)
    attr_reader(:callback, :callback_start, :callback_end)
    
    # @param [Geom::Point3d] origin
    # @param [Geom::Vector3d] xaxis
    # @param [Geom::Vector3d] yaxis
    # @param [Geom::Vector3d] zaxis
    #
    # @since 2.7.0
    def initialize(origin, xaxis, yaxis, zaxis)
      # Event callbacks
      @callback = nil
      @callback_start = nil
      @callback_end = nil
      
      @size = 150 # pixels
      
      # Origin
      @origin = origin
      @origin_control = OriginControl.new(self, origin)

      # Bounds
      @bounds = Geom::BoundingBox.new
      
      # Set up axis and events
      @axes = []
      @axes << Zbellbound::SmartGizmoPro::Axis.new(self, @origin, xaxis, CLR_X_AXIS, CLR_SELECTED, :x)
      @axes << Zbellbound::SmartGizmoPro::Axis.new(self, @origin, yaxis, CLR_Y_AXIS, CLR_SELECTED, :y)
      @axes << Zbellbound::SmartGizmoPro::Axis.new(self, @origin, zaxis, CLR_Z_AXIS, CLR_SELECTED, :z)
      @active_axis = nil # Current Axis active due to a mouse down event.
      @mouse_axis = nil  # Current Axis the mouse hovers over.
      @planes = []
      @planes << Zbellbound::SmartGizmoPro::PlaneMoveGizmo.new(self, :xy, @origin, xaxis, yaxis, zaxis, blend_color(CLR_X_AXIS, CLR_Y_AXIS), CLR_SELECTED)
      @planes << Zbellbound::SmartGizmoPro::PlaneMoveGizmo.new(self, :yz, @origin, yaxis, zaxis, xaxis, blend_color(CLR_Y_AXIS, CLR_Z_AXIS), CLR_SELECTED)
      @planes << Zbellbound::SmartGizmoPro::PlaneMoveGizmo.new(self, :xz, @origin, xaxis, zaxis, yaxis, blend_color(CLR_X_AXIS, CLR_Z_AXIS), CLR_SELECTED)
      @active_plane = nil
      @mouse_plane = nil
      
      @axes.each do |axis|
        axis.on_transform_start do |_axis, action_name|
          @callback_start.call(action_name) unless @callback_start.nil?
        end
        axis.on_transform_end do |_axis, action_name|
          @callback_end.call(action_name) unless @callback_end.nil?
        end
        axis.on_transform do |axis, t_increment, t_total, data|
          @origin = axis.origin
          update_axes(axis.origin, axis)
          @callback.call(t_increment, t_total, data) unless @callback.nil?
        end

        axis.on_click do |_axis, data|
          @callback_click.call(data) unless @callback_click.nil?
        end
      end

      @planes.each do |plane|
        plane.on_transform_start do |_plane, action_name|
          @callback_start.call(action_name) unless @callback_start.nil?
        end
        plane.on_transform do |plane_handle, t_increment, t_total, data|
          @origin = plane_handle.origin
          @origin_control.position = @origin
          update_axes(plane_handle.origin, nil)
          @callback.call(t_increment, t_total, data) unless @callback.nil?
        end
        plane.on_transform_end do |_plane, action_name|
          @callback_end.call(action_name) unless @callback_end.nil?
        end
      end

      @origin_control.on_change do |position|
        self.origin = position
        @callback_origin.call(position) unless @callback_origin.nil?
      end

      @origin_control.on_change_end do |position|
        @callback_origin_end.call(position) unless @callback_origin_end.nil?
      end
    end

    # @return [Boolean]
    # @since 2.7.0
    def xaxis=(vector)
      @axes.x.direction = vector
      sync_planes
    end

    # @return [Boolean]
    # @since 2.7.0
    def yaxis=(vector)
      @axes.y.direction = vector if @axes.y
      sync_planes
    end

    # @return [Boolean]
    # @since 2.7.0
    def zaxis=(vector)
      @axes.z.direction = vector if @axes.z
      sync_planes
    end
    
    # @return [Boolean]
    # @since 2.7.0
    def active?
      !@active_axis.nil? || !@active_plane.nil? || @origin_control.active?
    end
    
    def active_gizmo
      return nil unless active?

      return @origin_control if @origin_control.active?
      return @active_plane if @active_plane
      @active_axis.active_gizmo
    end

    # @since 2.7.0
    def tooltip
      return @origin_control.tooltip if @origin_control.mouse_active?

      @planes.each do |plane|
        return plane.tooltip if plane.mouse_active?
      end

      @axes.each do |axis|
        return axis.tooltip if axis.mouse_active?
      end
      ''
    end
    
    # @return [Geom::Vector3d]
    # @since 2.7.0
    def normal
      @axes.z.direction
    end

    def on_origin_change(&block)
      @callback_origin = block
    end

    def on_origin_change_end(&block)
      @callback_origin_end = block
    end
    
    # @param [Geom::Point3d] new_origin
    #
    # @return [Geom::Point3d]
    # @since 2.7.0
    def origin=(new_origin)
      @origin = new_origin
      @axes.each do |axis|
        axis.origin = new_origin
      end
      @planes.each do |plane|
        plane.origin = new_origin
      end

      @origin_control.position = new_origin

      new_origin
    end
    
    # Bounds use for scale 
    attr_writer :bounds

    # Bounds use for scale 
    attr_writer :transformation

    # @param [Integer] flags
    # @param [Integer] x
    # @param [Integer] y
    # @param [Sketchup::View] view
    #
    # @return [Boolean]
    # @since 2.7.0
    def onMouseMove(flags, x, y, view)
      # (!) Hotfix. Some times it appear that button up event is not detected
      #     and the gizmo thinks an axis is active. Some times due to cursor
      #     being released outside SketchUp's viewport or - it appear - with
      #     glitch that occur with quick clicks and released.
      if @active_axis && flags & MK_LBUTTON != MK_LBUTTON
        @active_axis = nil
      end
      @active_plane = nil if @active_plane && flags & MK_LBUTTON != MK_LBUTTON

      if @origin_control.active?
        @origin_control.onMouseMove(flags, x, y, view)
        return true
      elsif @active_plane
        @active_plane.onMouseMove(flags, x, y, view)
        return true
      elsif @active_axis
        @active_axis.onMouseMove(flags, x, y, view)
        return true
      else
        if @origin_control.onMouseMove(flags, x, y, view)
          return true
        end

        if @mouse_plane && @mouse_plane.onMouseMove(flags, x, y, view)
          return true
        else
          @mouse_plane = nil
        end

        @planes.each do |plane|
          if plane.onMouseMove(flags, x, y, view)
            @mouse_plane = plane
            return true
          end
        end

        # Prioritise last axis the mouse hovered over.
        if @mouse_axis && @mouse_axis.onMouseMove(flags, x, y, view)
          return true
        else
          @mouse_axis = nil
        end
        
        # If the mouse doesn't interact with the last axis any more, check the
        # rest.
        @axes.each do |axis|
          if axis.onMouseMove(flags, x, y, view)
            @mouse_axis = axis
            return true
          end
        end
      end
      @mouse_plane = nil
      @mouse_axis = nil
      false
    end
    
    # @param [Integer] flags
    # @param [Integer] x
    # @param [Integer] y
    # @param [Sketchup::View] view
    #
    # @return [Boolean]
    # @since 2.7.0
    def onLButtonDown(flags, x, y, view)
      return true if @origin_control.onLButtonDown(flags, x, y, view)

      @planes.each do |plane|
        if plane.onLButtonDown(flags, x, y, view)
          @active_plane = plane
          return true
        end
      end

      @axes.each do |axis|
        if axis.onLButtonDown(flags, x, y, view)
          @active_axis = axis
          return true 
        end
      end
      false
    end
    
    # @param [Integer] flags
    # @param [Integer] x
    # @param [Integer] y
    # @param [Sketchup::View] view
    #
    # @return [Boolean]
    # @since 2.7.0
    def onLButtonUp(flags, x, y, view)
      if @origin_control.onLButtonUp(flags, x, y, view)
        @active_axis = nil
        @active_plane = nil
        return true
      end

      @planes.each do |plane|
        if plane.onLButtonUp(flags, x, y, view)
          @active_axis = nil
          @active_plane = nil
          return true
        end
      end

      @axes.each do |axis|
        if axis.onLButtonUp(flags, x, y, view)
          @active_axis = nil
          @active_plane = nil
          return true
        end
      end
      false
    end
    
    # @param [Sketchup::View] view
    #
    # @return [Nil]
    # @since 2.7.0
    def draw(view)
      @planes.each do |plane|
        plane.draw(view)
      end

      @axes.each do |axis|
        axis.draw(view)
      end

      @origin_control.draw(view)
     
      nil
    end
    
    # @since 2.7.0
    def mouse_over?
      active? || !@mouse_plane.nil? || !@mouse_axis.nil? || @origin_control.mouse_active?
    end

    def prepick?(x, y, view)
      center = view.screen_coords(@origin)
      radius = (@size + 18) * UI.scale_factor
      center.distance([x, y]) <= radius
    end

    # @since 2.7.0
    def cancel
      @origin_control.cancel
      @planes.each do |plane|
        plane.cancel
      end
      @axes.each do |axis|
        axis.cancel
      end
      reset
    end
    
    private
    
    # @param [Geom::Point3d] origin
    # @param [Zbellbound::SmartGizmoPro::Axis] ignore_axis
    #
    # @return [Nil]
    # @since 2.7.0
    def update_axes(origin, ignore_axis)
      @axes.each do |a|
        next if a == ignore_axis

        a.origin = origin
      end
      @planes.each do |plane|
        plane.origin = origin
      end
      @origin_control.position = origin
      nil
    end

    def sync_planes
      xaxis, yaxis, zaxis = @axes.map(&:direction)
      @planes.each do |plane|
        case plane.id
        when :xy
          plane.uaxis = xaxis
          plane.vaxis = yaxis
          plane.normal = zaxis
        when :yz
          plane.uaxis = yaxis
          plane.vaxis = zaxis
          plane.normal = xaxis
        when :xz
          plane.uaxis = xaxis
          plane.vaxis = zaxis
          plane.normal = yaxis
        end
      end
    end

    def blend_color(*colors)
      values = colors.map(&:to_a)
      red = values.sum { |color| color[0] } / colors.length
      green = values.sum { |color| color[1] } / colors.length
      blue = values.sum { |color| color[2] } / colors.length
      Sketchup::Color.new(red, green, blue)
    end

    # @since 2.7.0
    def reset
      @active_axis = nil
      @active_plane = nil
      @mouse_axis = nil
      @mouse_plane = nil
    end
    
  end # class Manipulator
  
  class OriginControl
    attr_accessor(:position)
    attr_accessor(:size)
    attr_reader(:parent)

    def initialize(parent, position, color = [32, 32, 32], active_color = [255, 180, 0])
      @parent = parent
      @position = position
      @color = color
      @active_color = active_color
      @size = 4
      @selected = false
      @interacting = false
      @ip = Sketchup::InputPoint.new
    end

    def on_change(&block)
      @callback = block
    end

    def on_change_end(&block)
      @callback_end = block
    end

    def active?
      @interacting == true
    end

    def mouse_active?
      @mouse_active == true
    end

    def tooltip
      'Drag pivot'
    end

    def onMouseMove(_flags, x, y, view)
      if @interacting
        @mouse_active = true
        point = pick_position(view, x, y)
        return true unless point

        @position = point
        @callback.call(point) unless @callback.nil?
        view.tooltip = tooltip
        true
      else
        previous = @selected
        @selected = mouse_over?(x, y, view)
        @mouse_active = @selected
        view.invalidate if previous != @selected
      end
    end
  
    def onLButtonDown(_flags, x, y, view)
      @selected = mouse_over?(x, y, view)
      return false unless @selected

      @interacting = true
      point = pick_position(view, x, y)
      if point
        @position = point
        @callback.call(point) unless @callback.nil?
      end
      true
    end
    
    def onLButtonUp(_flags, _x, _y, _view)
      return false unless @interacting

      @interacting = false
      @callback_end.call(@position) unless @callback_end.nil?
      true
    end

    def draw(view)
      view.line_stipple = ''
      view.line_width = 1
      center = view.screen_coords(@position)
      color = (@selected || @interacting) ? @active_color : @color
      view.drawing_color = 'white'
      view.draw2d(GL_POLYGON, ShapeGeom.circle_points(center, (@size + 3) * UI.scale_factor, 16))
      view.drawing_color = color
      view.draw2d(GL_POLYGON, ShapeGeom.circle_points(center, @size * UI.scale_factor, 16))
      view.draw2d(GL_LINE_LOOP, ShapeGeom.circle_points(center, (@size + 5) * UI.scale_factor, 16))
    end

    def cancel
      @selected = false
      @interacting = false
      @mouse_active = false
      @ip.clear
    end

    private

    def mouse_over?(x, y, view)
      center = view.screen_coords(@position)
      radius = (@size + 5) * UI.scale_factor
      center.distance([x, y]) <= radius
    end

    def pick_position(view, x, y)
      @ip.pick(view, x, y)
      return @ip.position if @ip.valid?

      ray = view.pickray(x, y)
      plane = [@position, view.camera.direction]
      Geom.intersect_line_plane(ray, plane)
    end
  end
  
  class PlaneMoveGizmo
    include ShapeGeom
    include TransformCallbacks

    INNER_OFFSET = 24
    OUTER_OFFSET = 54

    attr_accessor(:origin, :uaxis, :vaxis, :normal)
    attr_reader(:parent, :id)

    def initialize(parent, plane_id, origin, uaxis, vaxis, normal, color, active_color)
      @parent = parent
      @id = plane_id
      @origin = origin.clone
      @uaxis = uaxis.clone
      @vaxis = vaxis.clone
      @normal = normal.clone
      @color = color
      @active_color = active_color
      @fill_color_active = Sketchup::Color.new(*color.to_a)
      @fill_color_active.alpha = 96
      @fill_color_inactive = Sketchup::Color.new(*color.to_a)
      @fill_color_inactive.alpha = 48
      @selected = false
      @interacting = false
      @mouse_active = false
      @old_origin = nil
      @screen_point_start = nil
      @u_axis_line = nil
      @v_axis_line = nil
      @u_model_length = nil
      @v_model_length = nil
      @time_down = nil
      @callback = nil
      @callback_start = nil
      @callback_end = nil
    end

    def active?
      @interacting == true
    end

    def mouse_active?
      @mouse_active == true
    end

    def tooltip
      "Move #{@id.to_s.upcase}"
    end

    def onLButtonDown(_flags, x, y, view)
      @selected = mouse_over?(x, y, view)
      return false unless @selected

      @old_origin = @origin.clone
      @screen_point_start = Geom::Point3d.new(x, y, 0)
      @u_model_length = view.pixels_to_model(OUTER_OFFSET, @old_origin)
      @v_model_length = view.pixels_to_model(OUTER_OFFSET, @old_origin)
      @u_axis_line = [@old_origin, @old_origin.offset(@uaxis, @u_model_length)]
      @v_axis_line = [@old_origin, @old_origin.offset(@vaxis, @v_model_length)]
      @time_down = Time.now
      @interacting = true
      # Cached for the duration of this drag -- unit/snap settings can't
      # change mid-gesture, so there's no need to re-fetch them on every
      # onMouseMove tick in move_event below.
      @unit_options = view.model.options['UnitsOptions']
      @callback_start.call(self, 'Move') unless @callback_start.nil?
      true
    end

    def onLButtonUp(_flags, _x, _y, _view)
      return false unless @interacting

      @interacting = false
      @callback_end.call(self, 'Move') unless @callback_end.nil?
      true
    end

    def onMouseMove(_flags, x, y, view)
      if @interacting
        @mouse_active = true
        move_event(x, y, view)
      else
        previous = @selected
        @selected = mouse_over?(x, y, view)
        @mouse_active = @selected
        view.invalidate if previous != @selected
        @selected
      end
    end

    def draw(view)
      return unless draw?

      polygon = screen_polygon(view)
      return if polygon.length < 4

      fill = (@selected || @interacting) ? @fill_color_active : @fill_color_inactive
      outline = (@selected || @interacting) ? @active_color : @color

      view.line_stipple = ''
      view.line_width = 1
      view.drawing_color = fill
      view.draw2d(GL_POLYGON, polygon)
      view.drawing_color = 'white'
      view.draw2d(GL_LINE_LOOP, polygon)
      view.line_width = (@selected || @interacting) ? 2 : 1
      view.drawing_color = outline
      view.draw2d(GL_LINE_LOOP, polygon)
    end

    def cancel
      @selected = false
      @interacting = false
      @mouse_active = false
      @old_origin = nil
      @screen_point_start = nil
      @u_axis_line = nil
      @v_axis_line = nil
      @u_model_length = nil
      @v_model_length = nil
      @time_down = nil
    end

    private

    def draw?
      return true unless @parent.active?

      gizmo = @parent.active_gizmo
      return true if gizmo == self
      return false if gizmo.is_a?(PLUGIN::RotateGizmo)
      return false if gizmo.is_a?(PLUGIN::ScaleGizmo)

      true
    end

    def plane_corners(view)
      inner = view.pixels_to_model(INNER_OFFSET, @origin)
      outer = view.pixels_to_model(OUTER_OFFSET, @origin)

      # inner/outer already reflect the current camera/zoom (they're the
      # output of pixels_to_model), so if they and origin/uaxis/vaxis all
      # match the last computed corners, the result is guaranteed
      # identical -- reuse it instead of rebuilding the 4 corner points.
      cache_key = [@origin.clone, @uaxis.clone, @vaxis.clone, inner, outer]
      if @plane_corners_cache && @plane_corners_cache_key == cache_key
        return @plane_corners_cache.map(&:clone)
      end

      ui = scaled_vector(@uaxis, inner)
      vi = scaled_vector(@vaxis, inner)
      uo = scaled_vector(@uaxis, outer)
      vo = scaled_vector(@vaxis, outer)

      corners = [
        @origin + ui + vi,
        @origin + uo + vi,
        @origin + uo + vo,
        @origin + ui + vo
      ]

      @plane_corners_cache_key = cache_key
      @plane_corners_cache = corners.map(&:clone)
      corners
    end

    def screen_polygon(view)
      plane_corners(view).map do |point|
        screen_point = view.screen_coords(point)
        screen_point.z = 0
        screen_point
      end
    end

    def mouse_over?(x, y, view)
      polygon = screen_polygon(view)
      return false if polygon.length < 4

      point = [x.to_f, y.to_f]
      point_in_triangle?(point, polygon[0], polygon[1], polygon[2]) ||
        point_in_triangle?(point, polygon[0], polygon[2], polygon[3])
    end

    def point_in_triangle?(point, a, b, c)
      p = [point[0], point[1]]
      pa = [a.x.to_f, a.y.to_f]
      pb = [b.x.to_f, b.y.to_f]
      pc = [c.x.to_f, c.y.to_f]

      area = signed_area(pa, pb, pc)
      return false if area.abs < 0.001

      w1 = signed_area(p, pb, pc) / area
      w2 = signed_area(pa, p, pc) / area
      w3 = signed_area(pa, pb, p) / area

      w1 >= 0.0 && w2 >= 0.0 && w3 >= 0.0
    end

    def signed_area(a, b, c)
      ((a[0] * (b[1] - c[1])) + (b[0] * (c[1] - a[1])) + (c[0] * (a[1] - b[1]))) / 2.0
    end

    def move_event(x, y, view)
      return false unless @screen_point_start && @u_axis_line && @v_axis_line

      screen_point = Geom::Point3d.new(x, y, 0)
      delta = @screen_point_start.vector_to(screen_point)
      u_distance, v_distance = plane_distances_from_screen_delta(delta, view)
      return false unless u_distance && v_distance

      if @unit_options['LengthSnapEnabled']
        snap_length = @unit_options['LengthSnapLength']
        u_distance = snap_signed_length(u_distance, snap_length)
        v_distance = snap_signed_length(v_distance, snap_length)
      end

      destination = @old_origin.offset(@uaxis, u_distance).offset(@vaxis, v_distance)

      v_increment = @origin.vector_to(destination)
      v_total = @old_origin.vector_to(destination)
      @origin = destination

      formatted = [u_distance, v_distance].map { |length| length.to_l.to_s }
      Sketchup.vcb_label = "#{@id.to_s.upcase} Move"
      Sketchup.vcb_value = formatted.join(', ')
      view.tooltip = "#{tooltip}: #{formatted.join(', ')}"

      t_increment = Geom::Transformation.translation(v_increment)
      t_total = Geom::Transformation.translation(v_total)
      data = [:move, v_total]

      @callback.call(self, t_increment, t_total, data) unless @callback.nil?
      true
    end

    def plane_distances_from_screen_delta(delta, view)
      u_screen = screen_points(@u_axis_line, view)
      v_screen = screen_points(@v_axis_line, view)
      u_vector = u_screen[0].vector_to(u_screen[1])
      v_vector = v_screen[0].vector_to(v_screen[1])

      determinant = (u_vector.x * v_vector.y) - (u_vector.y * v_vector.x)
      return [nil, nil] if determinant.abs < 0.001

      u_factor = ((delta.x * v_vector.y) - (delta.y * v_vector.x)) / determinant
      v_factor = ((u_vector.x * delta.y) - (u_vector.y * delta.x)) / determinant
      [@u_model_length * u_factor, @v_model_length * v_factor]
    end

    def snap_signed_length(length, snap_length)
      sign = length < 0 ? -1 : 1
      sign * TT::Length.snap(length.abs, snap_length)
    end

    def scaled_vector(axis, length)
      vector = axis.clone
      vector.length = length.abs
      vector.reverse! if length < 0
      vector
    end
  end

	 # @since 2.7.0
  class Axis
    include TransformCallbacks

    attr_reader(:origin, :direction)
    attr_reader(:parent, :id)
    
    # @param [Geom::Point3d] origin
    # @param [Geom::Vector3d] direction
    # @param [Sketchup::Color] color
    # @param [Sketchup::Color] active_color
    #
    # @since 2.7.0
    def initialize(parent, origin, direction, color, active_color, axis_id)
      @id = axis_id
      @parent = parent
      @origin = origin.clone
      @direction = direction.clone
      @color = color
      @active_color = active_color
      
      # Event callbacks
      @callback = nil
      @callback_start = nil
      @callback_end = nil
      
      # MoveGizmo
      @move_gizmo = MoveGizmo.new(self, origin, direction, color, active_color)
      @move_gizmo.on_transform_start do |_gizmo, action_name|
        @callback_start.call(self, action_name) unless @callback_start.nil?
      end
      @move_gizmo.on_transform do |gizmo, t_increment, t_total, data|
        @origin = gizmo.origin
        @parent.origin_control.position = @origin

        @rotate_gizmo.origin = gizmo.origin
        @scale_gizmo.origin = gizmo.origin
        @callback.call(self, t_increment, t_total, data) unless @callback.nil?
      end
      @move_gizmo.on_transform_end do |_gizmo, action_name|
        @callback_end.call(self, action_name) unless @callback_end.nil?
      end
      # on click
      @move_gizmo.on_click do |_gizmo, data|
        @callback_click.call(self, data) unless @callback_click.nil?
      end

      # RotateGizmo
      @rotate_gizmo = RotateGizmo.new(self, origin, direction, color, active_color)
      @rotate_gizmo.on_transform_start do |_gizmo, action_name|
        @callback_start.call(self, action_name) unless @callback_start.nil?
      end
      @rotate_gizmo.on_transform do |_gizmo, t_increment, t_total, data|
        xaxis, yaxis, zaxis = @parent.axes.map(&:direction)
        @parent.xaxis = xaxis.transform(t_increment)
        @parent.yaxis = yaxis.transform(t_increment)
        @parent.zaxis = zaxis.transform(t_increment)

        @callback.call(self, t_increment, t_total, data) unless @callback.nil?
      end
      @rotate_gizmo.on_transform_end do |_gizmo, action_name|
        @callback_end.call(self, action_name) unless @callback_end.nil?
      end
      # on click
      @rotate_gizmo.on_click do |_gizmo, data|
        @callback_click.call(self, data) unless @callback_click.nil?
      end

      # ScaleGizmo
      @scale_gizmo = ScaleGizmo.new(self, origin, direction, color, active_color)
      @scale_gizmo.on_transform_start do |_gizmo, action_name|
        @callback_start.call(self, action_name) unless @callback_start.nil?
      end
      @scale_gizmo.on_transform do |_gizmo, t_increment, t_total, data|
        @callback.call(self, t_increment, t_total, data) unless @callback.nil?
      end
      @scale_gizmo.on_transform_end do |_gizmo, action_name|
        @callback_end.call(self, action_name) unless @callback_end.nil?
      end
      # on click
      @scale_gizmo.on_click do |_gizmo, data|
        @callback_click.call(self, data) unless @callback_click.nil?
      end
    end
    
    # @return [String]
    # @since 2.7.0
    def inspect
      hex_id = TT.object_id_hex(self)
      "#<#{self.class.name}:#{hex_id} #{@direction}>"
    end

    # @return [Boolean]
    # @since 2.7.0
    def active?
      @move_gizmo.active? || @rotate_gizmo.active? || @scale_gizmo.active?
    end
    
    def active_gizmo
      return @move_gizmo if @move_gizmo.active?
      return @rotate_gizmo if @rotate_gizmo.active?
      return @scale_gizmo if @scale_gizmo.active?

      nil
    end

    # @since 2.7.0
    def tooltip
      if @move_gizmo.mouse_active?
        @move_gizmo.tooltip
      elsif @rotate_gizmo.mouse_active?
        @rotate_gizmo.tooltip
      elsif @scale_gizmo.mouse_active?
        @scale_gizmo.tooltip
      else
        ''
      end
    end
    
    # @return [Boolean]
    # @since 2.7.0
    def mouse_active?
      @mouse_active == true
    end
    
    # @param [Geom::Point3d] new_origin
    #
    # @return [Geom::Point3d]
    # @since 2.7.0
    def origin=(new_origin)
      @origin = new_origin.clone
      @move_gizmo.origin = @origin
      @rotate_gizmo.origin = @origin
      @scale_gizmo.origin = @origin
    end

    # @param [Geom::Vector3d] vector
    #
    # @return [Geom::Vector3d]
    # @since 2.7.0
    def direction=(vector)
      @direction = vector.clone
      @move_gizmo.direction = @direction.clone
      @rotate_gizmo.direction = @direction.clone
      @scale_gizmo.direction = @direction.clone
    end
    
    # @param [Integer] flags
    # @param [Integer] x
    # @param [Integer] y
    # @param [Sketchup::View] view
    #
    # @return [Boolean]
    # @since 2.7.0
    def onLButtonDown(flags, x, y, view)
      camera = view.camera
      perpendicular = !camera.perspective? && camera.direction.perpendicular?(@direction)
      can_move = !(@rotate_gizmo.active? || @scale_gizmo.active?)
      can_rotate = !(@move_gizmo.active? || @scale_gizmo.active?) && !perpendicular
      can_scale  = !(@move_gizmo.active? || @rotate_gizmo.active?)
      if can_move && @move_gizmo.onLButtonDown(flags, x, y, view)
        true
      elsif can_rotate && @rotate_gizmo.onLButtonDown(flags, x, y, view)
        true
      elsif can_scale && @scale_gizmo.onLButtonDown(flags, x, y, view)
        true
      else
        false
      end
    end
    
    # @param [Integer] flags
    # @param [Integer] x
    # @param [Integer] y
    # @param [Sketchup::View] view
    #
    # @return [Boolean]
    # @since 2.7.0
    def onLButtonUp(flags, x, y, view)
      can_move   = !(@rotate_gizmo.active? || @scale_gizmo.active?)
      can_rotate = !(@move_gizmo.active? || @scale_gizmo.active?)
      can_scale  = !(@move_gizmo.active? || @rotate_gizmo.active?)
      if can_move && @move_gizmo.onLButtonUp(flags, x, y, view)
        true
      elsif can_rotate && @rotate_gizmo.onLButtonUp(flags, x, y, view)
        true
      elsif can_scale && @scale_gizmo.onLButtonUp(flags, x, y, view)
        true
      elsif @interacting
        # (!) ...
        @callback_end.call(self) unless @callback_end.nil?
        @interacting = false
        true
      else
        @interacting = false
        false
      end
    end
    
    # @param [Integer] flags
    # @param [Integer] x
    # @param [Integer] y
    # @param [Sketchup::View] view
    #
    # @return [Boolean]
    # @since 2.7.0
    def onMouseMove(flags, x, y, view)
      camera = view.camera
      perpendicular = !camera.perspective? && camera.direction.perpendicular?(@direction)
      if @interacting
        # (!) ...
        @mouse_active = true
        true
      else
        can_move   = !(@rotate_gizmo.active? || @scale_gizmo.active?)
        can_rotate = !(@move_gizmo.active? || @scale_gizmo.active?) && !perpendicular
        can_scale  = !(@move_gizmo.active? || @rotate_gizmo.active?)
        if can_move && @move_gizmo.onMouseMove(flags, x, y, view)
          @mouse_active = true
          view.invalidate unless @move_gizmo.active?
          return true
        elsif can_rotate && @rotate_gizmo.onMouseMove(flags, x, y, view)
          @mouse_active = true
          view.invalidate unless @rotate_gizmo.active?
          return true
        elsif can_scale && @scale_gizmo.onMouseMove(flags, x, y, view)
          @mouse_active = true
          view.invalidate unless @scale_gizmo.active?
          return true
        end
        @mouse_active = false
        false
      end
    end
    
    # @param [Sketchup::View] view
    #
    # @return [Nil]
    # @since 2.7.0
    def draw(view)
      @move_gizmo.draw(view)
      @rotate_gizmo.draw(view)
      @scale_gizmo.draw(view)
    end

    # @since 2.7.0
    def cancel
      @move_gizmo.cancel
      @rotate_gizmo.cancel
      @scale_gizmo.cancel
    end
    
  end # class Axis
  
	 # @since 2.7.0
  class MoveGizmo
    include ClickDetection
    include ShapeGeom
    include TransformCallbacks

    attr_accessor(:origin, :direction)
    
    # @param [Geom::Point3d] origin
    # @param [Geom::Vector3d] direction
    # @param [Sketchup::Color] color
    # @param [Sketchup::Color] active_color
    #
    # @since 2.7.0
    def initialize(parent, origin, direction, color, active_color)
      @parent = parent
      @origin = origin.clone
      @direction = direction.clone
      @color = color
      @active_color = active_color
      
      @selected = false
      @interacting = false
      
      # Cache of the axis origin and orientation. Cached on onLButtonDown
      @old_origin = nil
      @old_vector = nil
      @old_axis = nil # [pt1, pt2]
      
      # User InputPoint
      @ip = Sketchup::InputPoint.new
      
      @pt_start = nil # Startpoint - IP projected to selected axis
      @pt_screen_start = nil # Screen projection of @pt_start
      
      @pt_mouse = nil # Mouse Point3d - projected to selected axis
      @pt_screen_mouse = nil
      
      # Event callbacks
      @callback = nil
      @callback_start = nil
      @callback_end = nil
    end

    # @return [Boolean]
    # @since 2.7.0
    def active?
      @interacting == true
    end

    # @return [Boolean]
    # @since 2.7.0
    def mouse_active?
      @mouse_active == true
    end
    
    # @since 2.7.0
    def tooltip
      'Move'
    end
    
    # @param [Integer] flags
    # @param [Integer] x
    # @param [Integer] y
    # @param [Sketchup::View] view
    #
    # @return [Boolean]
    # @since 2.7.0
    def onLButtonDown(_flags, x, y, view)
      if @selected
        @interacting = true

        # Cache the origin for use in onMouseMove to work out the distance
        # moved.
        @old_origin = @origin.clone
        @old_axis = [@origin, @origin.offset(@direction, 10)] # Line (3D)

        # Get input point closest to the selected axis
        ip = view.inputpoint(x, y)
        @pt_start = ip.position.project_to_line([@origin, @direction])

        # Project to screen axis
        screen_point = Geom::Point3d.new(x, y, 0)
        screen_axis = screen_points(@old_axis, view)
        @pt_screen_start = screen_point.project_to_line(screen_axis)
        @time_down = Time.now

        # Cached for the duration of this drag -- unit/snap settings can't
        # change mid-gesture, so there's no need to re-fetch them on every
        # onMouseMove tick in move_event below.
        @unit_options = view.model.options['UnitsOptions']

        @callback_start.call(self, 'Move') unless @callback_start.nil?
        true
      else
        false
      end
    end
    
    # @param [Integer] flags
    # @param [Integer] x
    # @param [Integer] y
    # @param [Sketchup::View] view
    #
    # @return [Boolean]
    # @since 2.7.0
    def onLButtonUp(_flags, x, y, view)
      if @interacting
        # on click
        # check point distance: @pt_start, @pt_mouse
        if clicked?(x, y, view)
          @callback_click.call(self, [:move, @direction]) unless @callback_click.nil?
        end

        @ip.clear
        @callback_end.call(self, 'Move') unless @callback_end.nil?
        @interacting = false
        true
      else
        @interacting = false
        false
      end
    end
    
    # @param [Integer] flags
    # @param [Integer] x
    # @param [Integer] y
    # @param [Sketchup::View] view
    #
    # @return [Boolean]
    # @since 2.7.0
    def onMouseMove(_flags, x, y, view)
      if @interacting
        @mouse_active = true
        move_event(x, y, view) # return true
      else
        @selected = mouse_over?(x, y, view)
        @mouse_active = @selected
      end
    end

    def draw?
      if @parent.parent.active?
        # find active axis
        axis = @parent.parent.axes.find do |axis|
          axis.active?
        end

        return false if axis && axis.active_gizmo.is_a?(PLUGIN::ScaleGizmo)
      end

      true
    end
    
    # @param [Sketchup::View] view
    #
    # @return [Nil]
    # @since 2.7.0
    def draw(view)
      return unless draw?

      # In parallel projection, an axis whose direction is parallel to the
      # camera projects to a single screen point. The two segment endpoints
      # land on the exact same pixel, so v = p2 - p1 has zero x/y components.
      # draw_arrow2D then tries to compute a perpendicular normal from a zero
      # vector, which raises a RuntimeError and stops ALL subsequent draw calls
      # in the same frame — causing every arrow to disappear, not just this one.
      # Skip drawing entirely for any axis that has no 2D screen extent.
      camera = view.camera
      return if !camera.perspective? && camera.direction.parallel?(@direction)

      # Arrow Body
      segment = modelspace_segment(view)
      segment2d = segment.map { |point| view.screen_coords(point) }
      view.line_stipple = ''
      view.line_width = 3
      view.drawing_color = 'white'
      view.draw2d(GL_LINES, segment2d)
      view.line_width = @selected ? 3 : 2
      view.drawing_color = @selected ? @active_color : @color
      view.draw2d(GL_LINES, segment2d)
      
      # Draw a simple arrowhead.
      draw_arrow(segment, view, @selected ? @active_color : @color)
    end

    def draw_arrow(line, view, color)
      p1 = view.screen_coords(line[0])
      p2 = view.screen_coords(line[1])
      draw_arrow2D([p1, p2], view, color)
    end   

    def draw_arrow2D(line, view, color, size = 14)
      p1, p2 = line

      v = p2 - p1
      return unless v.valid?

      unit = v.clone
      unit.length = size * UI.scale_factor
      normal = Geom::Vector3d.new(-unit.y, unit.x, 0)
      normal.length = size * 0.35 * UI.scale_factor
      back = p2 - unit
      neck = p2 - unit.clone.tap { |vec| vec.length = size * 0.45 * UI.scale_factor }
      p3 = back + normal
      p4 = neck
      p5 = back - normal
      points = [p2, p3, p4, p5]

      view.line_stipple = ''
      view.line_width = 2
      view.drawing_color = 'white'
      view.draw2d(GL_POLYGON, points)
      view.drawing_color = color
      view.draw2d(GL_POLYGON, points)
      view.draw2d(GL_LINE_LOOP, points)
    end

    # @since 2.7.0
    def cancel
      @selected = false
      @interacting = false
    end
    
    private
    
    # @param [Sketchup::View] view
    #
    # @return [Array<Array<Geom::Point3d>>]
    # @since 2.7.0
    def arrow_segments(view)
      base    = view.pixels_to_model(110, @origin) # (!) Make Constant
      tip     = view.pixels_to_model(150, @origin)
      radius  = view.pixels_to_model(10, @origin)
      
      base_pt = ORIGIN.offset(Z_AXIS, base)
      tip_pt  = ORIGIN.offset(Z_AXIS, tip)
      
      # Arrow base.
      circle = TT::Geom3d.circle(base_pt, Z_AXIS, radius, 8)
      
      # Connect base circle to arrow tip.
      segments = []
      circle.each do |point|
        segments << [point, tip_pt]
      end
      
      # Since the segments are drawn with GL_LINE_STRIP we need to manually close
      # the circle to form a loop.
      circle << circle.first
      segments << circle
      
      # Transform the segment into correct model space.
      tr = Geom::Transformation.new(@origin, @direction)
      segments.each do |segment|
        segment.map! { |point| point.transform(tr) }
      end
      
      segments
    end
    
    # @param [Integer] x
    # @param [Integer] y
    # @param [Sketchup::View] view
    #
    # @return [Boolean]
    # @since 2.7.0
    def mouse_over?(x, y, view)
      ph = view.pick_helper
      ph.do_pick(x, y)
      
      segment = modelspace_segment(view)
      result = ph.pick_segment(segment, x, y, 14)
      return true if result
      
      arrow_segments(view).each do |segment|
        result = ph.pick_segment(segment, x, y)
        return true unless result == false
      end

      false
    end

    # @param [Sketchup::View] view
    #
    # @return [Boolean]
    # @since 2.7.0
    def modelspace_segment(view)
      model_length = view.pixels_to_model(110, @origin) # (!) Make Constant
      [@origin, @origin.offset(@direction, model_length)]
    end
    
    # @param [Integer] x
    # @param [Integer] y
    # @param [Sketchup::View] view
    #
    # @return [Boolean]
    # @since 2.7.0
    def move_event(x, y, view)
      # Axis vector
      vector = @old_axis[0].vector_to(@old_axis[1])
      
      # Get mouse point on selected axis
      @ip.pick(view, x, y)
      @pt_mouse = @ip.position.project_to_line(@old_axis)

      # Get axis in screen space
      screen_axis = screen_points(@old_axis, view)
      
      # Calculate the Screen offset distance
      @pt_screen_mouse = Geom::Point3d.new(x, y, 0).project_to_line(screen_axis)
      mouse_distance = @pt_screen_start.distance(@pt_screen_mouse)
      
      if mouse_distance > 0
        # Direction vector
        direction = vector.clone
        
        # Get movement vector in screen space
        v = @pt_screen_start.vector_to(@pt_screen_mouse)
        
        # (!) validate vector.
        screen_v = screen_axis[0].vector_to(screen_axis[1])
        direction.reverse! unless screen_v.samedirection?(v)
        
        # Work out how much in real world distance the offset is.
        screen_distance = v.length
        world_distance = view.pixels_to_model(screen_distance, @old_origin)

        # Use model's snap length settings.
        if @unit_options['LengthSnapEnabled']
          snap_length = @unit_options['LengthSnapLength']
          world_distance = TT::Length.snap(world_distance, snap_length)
        end
        
        # UI Feedback.
        distance_formatted = world_distance.to_l.to_s
        Sketchup.vcb_label = 'Distance'
        Sketchup.vcb_value = distance_formatted
        view.tooltip = "Distance: #{distance_formatted}"
        
        # Offset Origin
        offset = @old_origin.offset(direction, world_distance)
        
        # Global Offset Vectors
        v_increment = @origin.vector_to(offset)
        v_total = @old_origin.vector_to(offset)

        # Move Gizmo Origin
        t_total = Geom::Transformation.new(v_total)
        @origin = @old_origin.transform(t_total)

        data = [:move, v_total]
        
        # Call event with local transformations
        t_increment = Geom::Transformation.new(v_increment)
        t_total = Geom::Transformation.new(v_total)
        @callback.call(self, t_increment, t_total, data) unless @callback.nil?
      end
      true
    end
    
  end # class MoveGizmo
  
  
	 # @since 2.7.0
  class RotateGizmo
    include ClickDetection
    include ShapeGeom
    include TransformCallbacks

    attr_accessor(:origin, :direction)
    
    # @param [Geom::Point3d] origin
    # @param [Geom::Vector3d] direction
    # @param [Sketchup::Color] color
    # @param [Sketchup::Color] active_color
    #
    # @since 2.7.0
    def initialize(parent, origin, direction, color, active_color)
      @parent = parent
      @origin = origin.clone
      @direction = direction.clone
      @color = color
      @active_color = active_color
      @accent_color = Sketchup::Color.new(*color.to_a)
      @accent_color.alpha = 135 if @accent_color.respond_to?(:alpha=)
      @snap_color = Sketchup::Color.new(255, 255, 255)
      @snap_color.alpha = 110 if @snap_color.respond_to?(:alpha=)

      @selected = false
      @interacting = false

      # Cache of the axis origin and orientation. Cached on onLButtonDown
      @old_origin = nil
      @old_vector = nil
      @old_axis = nil # [pt1, pt2]

      # User InputPoint
      @pt_screen_start = nil
      @pt_screen_mouse = nil

      @pt_start = nil
      @pt_mouse = nil

      # Event callbacks
      @callback = nil
      @callback_start = nil
      @callback_end = nil
    end

    # @return [Boolean]
    # @since 2.7.0
    def active?
      @interacting == true
    end

    # @return [Boolean]
    # @since 2.7.0
    def mouse_active?
      @mouse_active == true
    end

    # @since 2.7.0
    def tooltip
      'Rotate'
    end
    
    # @param [Integer] flags
    # @param [Integer] x
    # @param [Integer] y
    # @param [Sketchup::View] view
    #
    # @return [Boolean]
    # @since 2.7.0
    def onLButtonDown(_flags, x, y, view)
      if @selected
        
        # Cache the origin for use in onMouseMove to work out the distance
        # moved.
        @old_origin = @origin.clone
        @old_axis = [@origin.clone, @direction.clone] # Line (3D)
        
        @pt_screen_start = Geom::Point3d.new(x, y, 0)
        @time_down = Time.now

        @pt_screen_mouse = @pt_screen_start.clone
        
        segment = rotation_segment(view)
        @pt_start = project_to_segment(view, x, y, segment)
        if @pt_start
          @pt_mouse = @pt_start.clone
        else
          @pt_mouse = nil
          return true
        end
        
        @last_vector = @origin.vector_to(@pt_start)
        @angle = 0
        @last_angle = 0
        
        @interacting = true
        @callback_start.call(self, 'Rotate') unless @callback_start.nil?
        true
      else
        false
      end
    end
    
    # @param [Integer] flags
    # @param [Integer] x
    # @param [Integer] y
    # @param [Sketchup::View] view
    #
    # @return [Boolean]
    # @since 2.7.0
    def onLButtonUp(_flags, x, y, view)
      if @interacting
        if clicked?(x, y, view)
          @callback_click.call(self, [:rotate, @direction]) unless @callback_click.nil?
        end
        @callback_end.call(self, 'Rotate') unless @callback_end.nil?
        @interacting = false
        true
      else
        @interacting = false
        false
      end
    end
    
    # @param [Integer] flags
    # @param [Integer] x
    # @param [Integer] y
    # @param [Sketchup::View] view
    #
    # @return [Boolean]
    # @since 2.7.0
    def onMouseMove(_flags, x, y, view)
      if @interacting
        @mouse_active = true
        
        segment = rotation_segment(view)
        screen_point = Geom::Point3d.new(x, y, 0)
        
        @pt_mouse = project_to_segment(view, x, y, segment)
        return false unless @pt_mouse
        
        start_vector = @origin.vector_to(@pt_start)
        mouse_vector = @origin.vector_to(@pt_mouse)

        clockwise = (start_vector * mouse_vector % @direction) < 0

        total_angle = start_vector.angle_between(mouse_vector)

        total_angle *= -1 if clockwise

        # Snapping
        a = total_angle
        snap_angle = rotate_snap_angle(view.model)
        if snap_angle
          size = view.pixels_to_model(150, @origin) # Protractor size
          # Closest snap
          diff = a % snap_angle
          nearest_angle = if diff > snap_angle / 2.0
            a + (snap_angle - diff)
                          else
            a - diff
                          end
          # Snapping behaviour depends if the cursor is within the Gizmo radius.
          mouse_ray = view.pickray(x, y)
          plane = [@origin, @direction]
          plane_point = Geom.intersect_line_plane(mouse_ray, plane)
          mouse_plane_vector = @origin.vector_to(plane_point)
          # if mouse_vector.length < size
          if mouse_plane_vector.length < size
            # Within the Gizmo radius - Full snap
            a = nearest_angle
          else
            # Outside the Gizmo radius - Proximity snap
            # rotation = (direction < 0.0) ? -nearest_angle : nearest_angle
            # rotation = (clockwise) ? -nearest_angle : nearest_angle
            rotation = nearest_angle
            tr = Geom::Transformation.rotation(@origin, @direction, rotation)
            line = [@origin, @pt_start.transform(tr)]
            
            nx = view.pixels_to_model(5, @pt_mouse)
            ny = @pt_mouse.project_to_line(line).distance(@pt_mouse)

            a = nearest_angle if ny < nx # Snap!
          end
          # Adjust increment snap.
          total_angle = a if a != total_angle
        end # if snapping
        @angle = total_angle
        
        t_total = Geom::Transformation.rotation(@origin, @direction, total_angle)
        
        increment_angle = total_angle - @last_angle
        t_increment = Geom::Transformation.rotation(@origin, @direction, increment_angle)
        
        angle_formatted = Sketchup.format_angle(total_angle)
        Sketchup.vcb_label = 'Angle'
        Sketchup.vcb_value = angle_formatted
        view.tooltip = "Rotate: #{angle_formatted}"
        
        @pt_screen_mouse = screen_point # (?) Unused?
        @last_angle = total_angle

        data = [:rotate, @parent.origin, @direction, total_angle]
        
        @callback.call(self, t_increment, t_total, data) unless @callback.nil?
        true
      else
        @selected = mouse_over?(x, y, view)
        @mouse_active = @selected
      end
    end
    
    def draw?
      if @parent.parent.active?
        # find active axis
        axis = @parent.parent.axes.find do |axis|
          axis.active?
        end

        if axis && (axis.active_gizmo.is_a?(PLUGIN::MoveGizmo) || axis.active_gizmo.is_a?(PLUGIN::ScaleGizmo))
          return false
        end
      end

      true
    end

    # @param [Sketchup::View] view
    #
    # @return [Nil]
    # @since 2.7.0
    def draw(view)
      return unless draw?

      points = rotation_segment(view)
      screen_pts = screen_points(points, view)
      face_on_ring = face_on_screen_ring(view)
      face_on_model_ring = face_on_model_ring(view)
      
      view.line_stipple = ''
      view.line_width = 3
      view.drawing_color = 'white'

      # Do not draw if the RotateGizmo is active.
      # Only draw if the MoveGizmo and protractor are active.
      d = true 
      if @parent.parent.active? && 
         @parent.parent.active_gizmo.is_a?(PLUGIN::RotateGizmo) &&
         @parent.parent.active_gizmo != self
        d = false
      end

      view.draw2d(GL_LINE_STRIP, screen_pts) if d
      view.draw2d(GL_LINE_STRIP, face_on_ring) if d && face_on_ring
      view.draw(GL_LINE_STRIP, face_on_model_ring) if d && face_on_model_ring
      view.line_stipple = ''
      view.line_width = @selected ? 3 : 2
      view.drawing_color = @selected ? @active_color : @color
      view.draw2d(GL_LINE_STRIP, screen_pts) if d
      view.draw2d(GL_LINE_STRIP, face_on_ring) if d && face_on_ring
      view.draw(GL_LINE_STRIP, face_on_model_ring) if d && face_on_model_ring
      
      if @interacting && @pt_start && @pt_mouse
        angle = @angle

        view.line_stipple = ''
        view.line_width = 1

        # Account for snapping
        start_vector = @origin.vector_to(@pt_start)
        tr = Geom::Transformation.rotation(@origin, @direction, angle)
        mouse_vector = start_vector.transform(tr)
        
        # Start Line
        view.drawing_color = @color
        view.draw2d(GL_LINES, screen_points([@origin, @pt_start], view))
        view.draw(GL_LINES, [@origin, @pt_start])

        
        # End Line
        view.drawing_color = @color
        # view.draw( GL_LINES, [@origin, @pt_mouse] )
        pt2 = @origin.offset(mouse_vector)
        view.draw2d(GL_LINES, screen_points([@origin, pt2], view))
        view.draw(GL_LINES, [@origin, pt2])
        
        # Draw lighter, more product-specific rotate feedback instead of the
        # old large filled wheel.
        snap_angle = rotate_snap_angle(view.model)
        if snap_angle
          tick_outer = view.pixels_to_model(122, @origin)
          tick_inner = view.pixels_to_model(110, @origin)
          tick_sign = angle < 0 ? -1 : 1
          sweep = angle.abs
          tick_count = (sweep / snap_angle).floor
          ticks = []

          if tick_count > 0
            0.upto(tick_count) do |index|
              tick_angle = snap_angle * index * tick_sign
              tr_tick = Geom::Transformation.rotation(@origin, @direction, tick_angle)
              tick_vector = start_vector.transform(tr_tick)
              tick_vector.length = 1.0 if tick_vector.valid?
              next unless tick_vector.valid?

              outer_pt = @origin.offset(tick_vector, tick_outer)
              inner_pt = @origin.offset(tick_vector, tick_inner)
              ticks << inner_pt
              ticks << outer_pt
            end
          end

          unless ticks.empty?
            view.line_width = 1
            view.drawing_color = @snap_color
            view.draw2d(GL_LINES, screen_points(ticks, view))
            view.draw(GL_LINES, ticks)
          end
        end

        segments = TT::Geom3d.arc_segments(angle, 64)

        [84, 98].each do |offset|
          radius = view.pixels_to_model(offset, @origin)
          arc = TT::Geom3d.arc(@origin, start_vector, @direction, radius, 0, angle, segments)
          view.line_width = 1
          view.drawing_color = @accent_color
          view.draw2d(GL_LINE_STRIP, screen_points(arc, view))
          view.draw(GL_LINE_STRIP, arc)
        end

        main_radius = view.pixels_to_model(110, @origin)
        main_arc = TT::Geom3d.arc(@origin, start_vector, @direction, main_radius, 0, angle, segments)
        view.line_width = 3
        view.drawing_color = @color
        view.draw2d(GL_LINE_STRIP, screen_points(main_arc, view))
        view.draw(GL_LINE_STRIP, main_arc)

        end_marker = view.screen_coords(@origin.offset(mouse_vector, main_radius))
        end_marker.z = 0
        halo = ShapeGeom.circle_points(end_marker, 8 * UI.scale_factor, 16)
        core = ShapeGeom.circle_points(end_marker, 4 * UI.scale_factor, 16)
        view.line_width = 1
        view.drawing_color = 'white'
        view.draw2d(GL_POLYGON, halo)
        view.drawing_color = @color
        view.draw2d(GL_LINE_LOOP, halo)
        view.draw2d(GL_POLYGON, core)

      end
    end

    # @since 2.7.0
    def cancel
      @selected = false
      @interacting = false
    end
    
    private
    
    # Return the full orientation of the two lines. Going counter-clockwise.
    #
    # @return [Float]
    # @since 2.7.0
    def full_angle_between(vector1, vector2, normal = Z_AXIS)
      direction = (vector1 * vector2) % normal      
      angle = vector1.angle_between(vector2)
      angle = 360.degrees - angle if direction < 0.0
      angle
    end

    def rotate_snap_angle(model)
      if defined?(Zbellbound::SmartGizmoPro::PLUGIN) &&
         Zbellbound::SmartGizmoPro::PLUGIN.respond_to?(:rotate_snap_increment)
        increment = Zbellbound::SmartGizmoPro::PLUGIN.rotate_snap_increment.to_f
        return increment.degrees if increment.positive?
      end

      unit_options = model.options['UnitsOptions']
      return nil unless unit_options['AngleSnapEnabled']

      snap = unit_options['SnapAngle'].to_f
      snap.positive? ? snap.degrees : nil
    end
    
    # @param [Sketchup::View] view
    #
    # @return [Geom::Point3d, Nil]
    # @since 2.7.0
    def project_to_segment(view, x, y, segment)
      ray = view.pickray(x, y)
      center = @origin
      plane = [center, @direction]
      point_on_plane = Geom.intersect_line_plane(ray, plane)
      return nil unless point_on_plane

      mouse_line = [center, point_on_plane]
      closest_distance = nil
      closest_point = nil
      (0...segment.size - 1).each do |i|
        line = segment[i, 2]
        pt1 = Geom.intersect_line_line(mouse_line, line)
        next unless pt1
        next unless TT::Point3d.between?(line[0], line[1], pt1)

        vector_to_segment = center.vector_to(pt1)
        vector_to_mouse = center.vector_to(point_on_plane)
        next unless vector_to_mouse.samedirection?(vector_to_segment)

        distance = center.distance(pt1)
        if closest_distance.nil? || distance < closest_distance
          closest_distance = distance
          closest_point = pt1
        end
      end
      closest_point
    rescue ArgumentError => e
      warn("[ZB Smart Gizmo Pro] RotateGizmo#project_to_segment failed: #{e.class}: #{e.message}") if DEBUG_MODE
      raise
    end
    
    # @param [Sketchup::View] view
    #
    # @return [Array<Array<Geom::Point3d>>]
    # @since 2.7.0
    def rotation_segment(view, pixel_radius = @parent.parent.size)
      radius = view.pixels_to_model(pixel_radius, @origin)

      # `radius` already reflects the current camera/zoom/projection (it's
      # the output of pixels_to_model), so if origin/direction/radius all
      # match the last computed segment, the circle geometry is guaranteed
      # identical -- reuse it instead of re-running 64 rotations/transforms.
      # Callers get their own cloned points each time, same as a fresh build.
      cache_key = [@origin.clone, @direction.clone, radius]
      if @rotation_segment_cache && @rotation_segment_cache_key == cache_key
        return @rotation_segment_cache.map(&:clone)
      end

      segments = TT::Geom3d.circle(@origin, @direction, radius, 64)
      # Since the segments are drawn with GL_LINE_STRIP we need to manually close
      # the circle to form a loop.
      segments << segments.first

      @rotation_segment_cache_key = cache_key
      @rotation_segment_cache = segments.map(&:clone)
      segments
    end

    # @param [Integer] x
    # @param [Integer] y
    # @param [Sketchup::View] view
    #
    # @return [Boolean]
    # @since 2.7.0
    def mouse_over?(x, y, view)
      center = view.screen_coords(@origin)
      ring = rotation_segment(view)
      ring_edge = view.screen_coords(ring.first)
      radius = center.distance(ring_edge)
      distance = center.distance([x, y])
      aperture = 18 * UI.scale_factor
      return false if distance < (radius - aperture)
      return false if distance > (radius + aperture)

      ph = view.pick_helper
      ph.do_pick(x, y)
      result = ph.pick_segment(ring, x, y, aperture)
      return true unless result == false

      false
    end

    def face_on_screen_ring(view)
      return nil unless face_on_parallel_projection?(view)

      center = view.screen_coords(@origin)
      radius = 60.0
      points = ShapeGeom.circle_points(center, radius, 64)
      points << points.first unless points.empty?
      points
    end

    def face_on_model_ring(view)
      return nil unless face_on_parallel_projection?(view)

      radius = view.pixels_to_model(60, @origin)
      offset = view.pixels_to_model(2, @origin)
      camera_direction = view.camera.direction.clone
      return nil unless camera_direction.valid?

      camera_direction.length = offset
      center = @origin.offset(camera_direction.reverse)
      points = TT::Geom3d.circle(center, @direction, radius, 64)
      points << points.first unless points.empty?
      points
    end

    def face_on_parallel_projection?(view)
      camera = view.camera
      return false unless camera && camera.respond_to?(:direction)
      return false if camera.perspective?

      camera_direction = camera.direction.clone
      return false unless camera_direction.valid?

      camera_direction.length = 1.0
      axis_direction = @direction.clone
      return false unless axis_direction.valid?

      axis_direction.length = 1.0
      # `%` is the dot product on Geom::Vector3d. The original `*` is the
      # cross product, which returns a Vector3d — calling `.abs` on a
      # vector raises NoMethodError when the axis points at the camera and
      # the cross product collapses to Vector3d(0, 0, 0). For unit vectors
      # the dot product gives cos(angle) directly: ±1 when parallel, 0
      # when perpendicular, so .abs of the scalar is what we actually want.
      alignment = camera_direction.parallel?(axis_direction) ? (camera_direction % axis_direction).abs : 0.0
      alignment > 0.999
    end
    
  end # class RotateGizmo
  
  
	 # @since 2.7.0
  class ScaleGizmo
    include ClickDetection
    include ShapeGeom
    include TransformCallbacks

    SIZE = 170
    MIN_SIZE = 95
    MAX_SIZE = 220
    
    attr_accessor(:origin, :direction)
    
    # @param [Geom::Point3d] origin
    # @param [Geom::Vector3d] direction
    # @param [Sketchup::Color] color
    # @param [Sketchup::Color] active_color
    #
    # @since 2.7.0
    def initialize(parent, origin, direction, color, active_color)
      @parent = parent
      @origin = origin.clone
      @direction = direction.clone
      @color = color
      @active_color = active_color
      
      @selected = false
      @interacting = false
      
      # Cache of the axis origin and orientation. Cached on onLButtonDown
      @old_origin = nil
      @old_vector = nil
      @old_axis = nil # [pt1, pt2]
      
      # User InputPoint
      @pt_screen_start = nil
      @pt_screen_mouse = nil
      
      @pt_start = nil
      @pt_mouse = nil
      
      # Event callbacks
      @callback = nil
      @callback_start = nil
      @callback_end = nil
    end

    # @return [Boolean]
    # @since 2.7.0
    def active?
      @interacting == true
    end

    # @return [Boolean]
    # @since 2.7.0
    def mouse_active?
      @mouse_active == true
    end
    
    # @since 2.7.0
    def tooltip
      'Scale'
    end
    
    # @param [Integer] flags
    # @param [Integer] x
    # @param [Integer] y
    # @param [Sketchup::View] view
    #
    # @return [Boolean]
    # @since 2.7.0
    def onLButtonDown(_flags, x, y, view)
      if @selected
        # Cache the origin for use in onMouseMove to work out the distance
        # moved.
        @old_origin = @origin.clone
        @old_axis = [@origin.clone, @direction.clone] # Line (3D)
        
        @pt_screen_start = Geom::Point3d.new(x, y, 0)
        @time_down = Time.now
        # @pt_screen_mouse = @pt_screen_start.clone
        
        # Find the closest point on the segments from where the mouse is.
        segments = gripper_segments(view)
        @pt_start = project_to_segment(view, x, y, segments, 10.0)
        return true unless @pt_start
        
        # @last_vector = @origin.vector_to( @pt_start )
        @last_scale = 1.0
        
        @interacting = true
        @callback_start.call(self, 'Scale') unless @callback_start.nil?
        true
      else
        false
      end
    end
    
    # @param [Integer] flags
    # @param [Integer] x
    # @param [Integer] y
    # @param [Sketchup::View] view
    #
    # @return [Boolean]
    # @since 2.7.0
    def onLButtonUp(flags, x, y, view)
      result = if @interacting
        if clicked?(x, y, view)
          mask = scale_mask(@parent, flags)
          data = [:scale, @parent.origin, 1, mask]
          @callback_click.call(self, data) unless @callback_click.nil?
        end

        @callback_end.call(self, 'Scale') unless @callback_end.nil?
        @interacting = false
        true
      else
        @interacting = false
        false
      end

      @pt_mouse = nil
      result
    end
    
    # @param [Integer] flags
    # @param [Integer] x
    # @param [Integer] y
    # @param [Sketchup::View] view
    #
    # @return [Boolean]
    # @since 2.7.0
    def onMouseMove(flags, x, y, view)
      if @interacting
        @mouse_active = true
        
        segments = gripper_segments(view)

        @pt_mouse = project_to_segment(view, x, y, segments)
        return false unless @pt_mouse
        
        start_vector = @origin.vector_to(@pt_start)
        mouse_vector = @origin.vector_to(@pt_mouse)
        
        # Prevent scaling in negative direction.
        negative = false
        if mouse_vector.valid? && mouse_vector.samedirection?(@direction)
          # mouse_vector.length = 0
          # @pt_mouse = @origin.clone
          negative = true
        end
        
        total_scale = mouse_vector.length / start_vector.length
        return if total_scale.abs < 0.1

        total_scale = -total_scale if negative

        increment_scale = if @last_scale == 0
          0
                          else
          total_scale / @last_scale
                          end

        # Increment
        scaling = scale_array(@parent, increment_scale, flags)
        t_increment = Geom::Transformation.scaling(*scaling)
        
        # Total
        scaling = scale_array(@parent, total_scale, flags)
        t_total = Geom::Transformation.scaling(*scaling)
        
        @last_scale = total_scale
        
        scale_formatted = TT::Locale.float_to_string(total_scale, 2)
        Sketchup.vcb_label = 'Scale'
        Sketchup.vcb_value = scale_formatted
        view.tooltip = "Scale: #{scale_formatted}"

        mask = scale_mask(@parent, flags)
        data = [:scale, @parent.origin, total_scale, mask]
        
        # Convert the local scaling transformation into global transformation.
        gizmo = @parent.parent
        gx, gy, gz = gizmo.axes.map do |axis|
          axis.direction
        end
        go = gizmo.origin
        gizmo_tr = Geom::Transformation.new(gx, gy, gz, go)
        
        t_increment = gizmo_tr * t_increment * gizmo_tr.inverse
        t_total     = gizmo_tr * t_total * gizmo_tr.inverse
        
        @callback.call(self, t_increment, t_total, data) unless @callback.nil?
        true
      else
        @selected = mouse_over?(x, y, view)
        @mouse_active = @selected
      end
    end
    
    # @return [Array]
    # @since 2.7.0
    def scale_array(axis, scale, flags)
      origin_pt = ORIGIN.clone
      if flags & CONSTRAIN_MODIFIER_MASK == CONSTRAIN_MODIFIER_MASK
        [origin_pt, scale, scale, scale]
      else
        case axis.id
        when :x
          [origin_pt, scale, 1, 1]
        when :y
          [origin_pt, 1, scale, 1]
        when :z
          [origin_pt, 1, 1, scale]
        end
      end
    end

    # @return [Array]
    # @since 2.7.0
    def scale_mask(axis, flags)
      if flags & CONSTRAIN_MODIFIER_MASK == CONSTRAIN_MODIFIER_MASK
        [true, true, true]
      else
        case axis.id
        when :x
          [true, false, false]
        when :y
          [false, true, false]
        when :z
           [false, false, true]
        end
      end
    end

    def get_size(view, direction)
      bb = @parent.parent.bounds
      tr = @parent.parent.transformation
      min_size = view.pixels_to_model(MIN_SIZE, @origin)
      base_size = view.pixels_to_model(SIZE, @origin)
      max_size = view.pixels_to_model(MAX_SIZE, @origin)

      if bb.empty?
        base_size
      else
        pts = 0.upto(7).map { |i| bb.corner(i).transform(tr) }
        axis_extent =
        if direction.parallel?(tr.xaxis)
          pts[0].distance(pts[1]) * 0.5
        elsif direction.parallel?(tr.yaxis)
          pts[0].distance(pts[2]) * 0.5
        elsif direction.parallel?(tr.zaxis)
          pts[0].distance(pts[4]) * 0.5
        else
          base_size
        end

        [[axis_extent, min_size].max, max_size].min
      end
    end
    
    def draw?
      if @parent.parent.active?
        # find active axis
        axis = @parent.parent.axes.find do |axis|
          axis.active?
        end

        if axis && (axis.active_gizmo.is_a?(PLUGIN::MoveGizmo) || axis.active_gizmo.is_a?(PLUGIN::RotateGizmo))
          return false
        end
      end

      true
    end

    # @param [Sketchup::View] view
    #
    # @return [Nil]
    # @since 2.7.0
    def draw(view)
      return unless draw?

      size = get_size(view, @direction)

      pt = @pt_mouse || @origin.offset(@direction.reverse, size)
      
      pt1 =  view.screen_coords(@origin)
      pt2 =  view.screen_coords(pt)
      
      color = @selected ? @active_color : @color
      view.drawing_color = 'white'
      view.line_stipple = '.'
      view.line_width = 3
      view.draw2d(GL_LINE_STRIP, pt1, pt2)

      view.drawing_color = color
      view.line_stipple = '.'
      view.line_width = @selected ? 3 : 2
      view.draw2d(GL_LINE_STRIP, pt1, pt2)

      view.line_stipple = ''
      diamond = diamond_points(pt2, 7 * UI.scale_factor)
      inner_diamond = diamond_points(pt2, 4 * UI.scale_factor)
      view.drawing_color = 'white'
      view.draw2d(GL_POLYGON, diamond)
      view.drawing_color = color
      view.draw2d(GL_LINE_LOOP, diamond)
      view.draw2d(GL_POLYGON, inner_diamond)
      
    end

    # @since 2.7.0
    def cancel
      @selected = false
      @interacting = false
      @pt_mouse = nil
    end
    
    private

    
    # @param [Sketchup::View] view
    #
    # @return [Geom::Point3d, Nil]
    # @since 2.7.0
    def project_to_segment(view, x, y, segments, aperture = nil)
      # Get a ray from the cursor which projects into the model.
      ray = view.pickray(x, y)
      # Find the closest intersecting with the segments.
      line = segments
      pt1, pt2 = Geom.closest_points(line, ray)
      # If an aperture is given it must be within the given range from the
      # pickray.
      if aperture
        vector_between = pt1.vector_to(pt2)
        pick_aperture = view.pixels_to_model(aperture / 2.0, pt1)
        return nil unless vector_between.length <= pick_aperture
      end
      # Return point on segment.
      pt1
    end
    
    # @param [Sketchup::View] view
    #
    # @return [Array<Array<Geom::Point3d>>]
    # @since 2.7.0
    def gripper_segments(view)
      size = get_size(view, @direction)

      pt1 = @origin.clone
      pt2 = @origin.offset(@direction.reverse, size)
      
      [pt1, pt2]
    end
    
    # @param [Integer] x
    # @param [Integer] y
    # @param [Sketchup::View] view
    #
    # @return [Boolean]
    # @since 2.7.0
    def mouse_over?(x, y, view)
      ph = view.pick_helper
      ph.do_pick(x, y)
      segments = gripper_segments(view)
      result = ph.pick_segment(segments, x, y, 15)
      return true unless result == false

      false
    end

    def diamond_points(center, radius)
      [
        [center.x, center.y - radius, 0],
        [center.x + radius, center.y, 0],
        [center.x, center.y + radius, 0],
        [center.x - radius, center.y, 0]
      ]
    end
    
  end # class ScaleGizmo
end
