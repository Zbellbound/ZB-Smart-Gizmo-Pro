module Zbellbound::SmartGizmoPro
  module TT
    module_function

    def object_id_hex(object)
      format('0x%016x', object.object_id)
    end

    module Length
      module_function

      def snap(value, increment)
        amount = value.to_f
        step = increment.to_f
        return amount if step <= 0.0

        (amount / step).round * step
      end
    end

    module Locale
      module_function

      def float_to_string(value, precision = 2)
        format("%.#{precision}f", value.to_f).sub(/\.?0+$/, '')
      end
    end

    module SketchUp
      COLOR_ALPHA = :color_alpha

      module_function

      def support?(feature)
        feature == COLOR_ALPHA
      end
    end

    module Point3d
      module_function

      def between?(point1, point2, test_point, tolerance = 0.001)
        segment_length = point1.distance(point2)
        return point1.distance(test_point) <= tolerance if segment_length <= tolerance

        distance_sum = point1.distance(test_point) + test_point.distance(point2)
        (distance_sum - segment_length).abs <= tolerance
      end
    end

    module Geom3d
      module_function

      def circle(center, normal, radius, segments = 24)
        axis = normal.clone
        axis.length = 1.0 if axis.valid?
        start = perpendicular_vector(axis)
        start.length = radius
        points = [center.offset(start)]
        step = 360.degrees / segments.to_i
        rotation = Geom::Transformation.rotation(center, axis, step)
        segments.to_i.times { points << points.last.transform(rotation) }
        points.pop
        points
      end

      def circle2d(center, xaxis, radius, segments = 24)
        axis = xaxis.clone
        axis.length = radius
        points = [center.offset(axis)]
        step = 360.degrees / segments.to_i
        rotation = Geom::Transformation.rotation(center, Z_AXIS, step)
        segments.to_i.times { points << points.last.transform(rotation) }
        points.pop
        points
      end

      def arc_segments(angle, max_segments = 64)
        max = [max_segments.to_i, 4].max
        fraction = angle.to_f.abs / 360.degrees.to_f
        [[(max * fraction).ceil, 2].max, max].min
      end

      def arc(center, start_vector, normal, radius, start_angle, end_angle, segments)
        axis = normal.clone
        axis.length = 1.0 if axis.valid?
        base = start_vector.clone
        base.length = radius
        total_angle = end_angle.to_f - start_angle.to_f
        steps = [segments.to_i, 1].max
        start_rotation = Geom::Transformation.rotation(center, axis, start_angle)
        step_rotation = Geom::Transformation.rotation(center, axis, total_angle / steps.to_f)
        point = center.offset(base).transform(start_rotation)
        arc_points = [point]
        steps.times { arc_points << arc_points.last.transform(step_rotation) }
        arc_points
      end

      def perpendicular_vector(vector)
        reference = vector.parallel?(Z_AXIS) ? X_AXIS : Z_AXIS
        perpendicular = vector * reference
        if perpendicular.length == 0
          reference = Y_AXIS
          perpendicular = vector * reference
        end
        perpendicular.length = 1.0
        perpendicular
      end
      private_class_method :perpendicular_vector
    end
  end

  module ShapeGeom
    extend self

    def rectangle_points(origin = ORIGIN, width, height)
      rect = [
        Geom::Point3d.new(origin.x - width / 2.0, origin.y - height / 2.0, 0), 
        Geom::Point3d.new(origin.x + width / 2.0, origin.y - height / 2.0, 0), 
        Geom::Point3d.new(origin.x + width / 2.0, origin.y + height / 2.0, 0), 
        Geom::Point3d.new(origin.x - width / 2.0, origin.y + height / 2.0, 0) 
      ]

      rect
    end 
    
    def circle_line_width(center, radius, sides, size = 2)
      outer = circle_points(center, radius + (size / 2.0), sides)
      inner = circle_points(center, radius - (size / 2.0), sides)

      Geom.tesselate(outer, inner.reverse)
    end

    def line_width(line, size = 2, sides = 6)
      raise "Size must be > 1" if size < 2

      pts = []
      p_start, p_end = line
      vec_edge = p_start.vector_to(p_end)
      vec_cr = Z_AXIS.cross(vec_edge)
      vec_cr.length = size / 2.0
      
      # body
      pts << p_start.offset(vec_cr)
      
      angle = 360.0 / (sides * 2)
      trans = Geom::Transformation.rotation(p_start, Z_AXIS, angle.degrees)
      1.upto(sides) { pts << pts.last.transform(trans) }
      pts << pts.last.offset(vec_edge)
      
      trans = Geom::Transformation.rotation(p_end, Z_AXIS, angle.degrees)
      1.upto(sides) { pts << pts.last.transform(trans) }

      pts
    end

    def square_points(origin, size)
      rectangle_points(origin, size, size)
    end

    def square_uvs
      [
        Geom::Point3d.new(0, 0, 0),
        Geom::Point3d.new(1, 0, 0), 
        Geom::Point3d.new(1, 1, 0), 
        Geom::Point3d.new(0, 1, 0)
      ].reverse
    end

    def screen_points(points, view)
      points.map do |pt|
        screen_pt = view.screen_coords(pt)
        screen_pt.z = 0
        screen_pt
      end
    end

    def circle_points(center = ORIGIN, radius = 1, sides = 24)
      vecx = X_AXIS.clone
      vecx.length = radius
      circle = [center.offset(vecx)]
      tr = Geom::Transformation.rotation(center, Z_AXIS, (360.0 / sides).degrees)
      0.upto(sides - 1) { circle.push(circle.last.transform(tr)) }
    
      circle
    end

    def circle_uvs(sides = 24)
      circle = [ORIGIN.offset(X_AXIS)]
      tr = Geom::Transformation.rotation(ORIGIN, Z_AXIS, (360 / sides).degrees)
      0.upto(sides - 1) { circle.push(circle.last.transform(tr)) }
      uvs = circle.map { |pt| pt.offset(X_AXIS + Y_AXIS).to_a.map { |i| i / 2.0 } }

      uvs.reverse
    end

    def create_box(center, d)
      x, y, z = center.to_a
      half_d = d / 2.0

      vertices = [
        [x - half_d, y - half_d, z + half_d], # bottom-back-left
        [x - half_d, y - half_d, z - half_d], # bottom-front-left
        [x + half_d, y - half_d, z - half_d], # bottom-front-right
        [x + half_d, y - half_d, z + half_d], # bottom-back-right
        [x - half_d, y + half_d, z + half_d], # top-back-left
        [x - half_d, y + half_d, z - half_d], # top-front-left
        [x + half_d, y + half_d, z - half_d], # top-front-right
        [x + half_d, y + half_d, z + half_d]  # top-back-right
      ]

      faces = [
        [vertices[0], vertices[1], vertices[2], vertices[3]], # bottom
        [vertices[4], vertices[5], vertices[6], vertices[7]], # top
        [vertices[0], vertices[4], vertices[7], vertices[3]], # back
        [vertices[1], vertices[5], vertices[4], vertices[0]], # left
        [vertices[2], vertices[6], vertices[5], vertices[1]], # front
        [vertices[3], vertices[7], vertices[6], vertices[2]]  # right
      ]

      faces
    end
  end

  # Shared click-vs-drag detection for handle classes that track
  # @interacting/@pt_mouse/@pt_screen_start/@time_down (MoveGizmo,
  # RotateGizmo, ScaleGizmo). Included rather than module_function, since
  # it reads instance state, unlike TT/ShapeGeom above.
  module ClickDetection
    def clicked?(x, y, _view)
      return false unless @interacting
      return true if @pt_mouse.nil?
      return true if @pt_screen_start.distance([x, y]) < 5 && Time.now - @time_down < 0.5

      false
    end
  end

  # Shared callback-registration setters, identical across Manipulator,
  # PlaneMoveGizmo, Axis, MoveGizmo, RotateGizmo, and ScaleGizmo. Deliberately
  # limited to these 4 simple setters -- active?/mouse_active? are NOT
  # included here since Axis#active? composes its child gizmos'
  # (@move_gizmo/@rotate_gizmo/@scale_gizmo) state while the other classes
  # check their own @interacting flag directly; those are not the same
  # shape and must stay defined per-class.
  #
  # Note: PlaneMoveGizmo has no on_click support (drag-only, no
  # @callback_click reader anywhere in that class) -- including on_click
  # here adds an unused setter to that one class. Harmless (nothing calls
  # it), but noted for clarity.
  module TransformCallbacks
    def on_click(&block)
      @callback_click = block
    end

    def on_transform(&block)
      @callback = block
    end

    def on_transform_start(&block)
      @callback_start = block
    end

    def on_transform_end(&block)
      @callback_end = block
    end
  end
end
