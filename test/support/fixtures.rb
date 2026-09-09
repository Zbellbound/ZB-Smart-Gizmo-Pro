require_relative 'gizmo_harness'

module TestFixtures
  module_function

  # A plain rectangular-box component/group: 12 straight edges, no nested
  # children, no curves. Definition entities live directly on `entities`.
  def build_box(entities, x_size, y_size, z_size)
    hx = x_size / 2.0
    hy = y_size / 2.0

    corners = [
      Geom::Point3d.new(-hx, -hy, 0),
      Geom::Point3d.new(hx, -hy, 0),
      Geom::Point3d.new(hx, hy, 0),
      Geom::Point3d.new(-hx, hy, 0),
      Geom::Point3d.new(-hx, -hy, z_size),
      Geom::Point3d.new(hx, -hy, z_size),
      Geom::Point3d.new(hx, hy, z_size),
      Geom::Point3d.new(-hx, hy, z_size)
    ]

    edges = [
      [0, 1], [1, 2], [2, 3], [3, 0],
      [4, 5], [5, 6], [6, 7], [7, 4],
      [0, 4], [1, 5], [2, 6], [3, 7]
    ]

    edges.each do |a, b|
      entities << Sketchup::Edge.new(corners[a], corners[b])
    end
  end

  # A "turned post" component: geometry made entirely of curved edges (as
  # a lathed/turned leg or baluster would be), no straight edges, no
  # nested children. Mirrors zb_smart_gizmo_pro/overlay.rb's own curved-edge
  # rejection (`edges.reject(&:curve)`), which is real SketchUp behavior
  # for arcs/circles on a turned profile.
  def build_curved_post(entities, x_size, y_size, z_size)
    fake_curve = Object.new # any truthy value stands in for a Sketchup::Curve

    hx = x_size / 2.0
    hy = y_size / 2.0
    steps = 8
    0.upto(steps - 1) do |i|
      t0 = i.to_f / steps
      t1 = (i + 1).to_f / steps
      z0 = t0 * z_size
      z1 = t1 * z_size
      p0 = Geom::Point3d.new(hx * Math.cos(t0 * Math::PI * 2), hy * Math.sin(t0 * Math::PI * 2), z0)
      p1 = Geom::Point3d.new(hx * Math.cos(t1 * Math::PI * 2), hy * Math.sin(t1 * Math::PI * 2), z1)
      edge = Sketchup::Edge.new(p0, p1)
      edge.curve = fake_curve
      entities << edge
    end
  end

  def mark_as_dynamic_component(instance, lenz: nil)
    dict = { '_lenz_access' => 'LIST' }
    dict['lenz'] = lenz if lenz
    instance.set_test_attribute_dictionary('dynamic_attributes', dict)
    instance.definition.set_test_attribute_dictionary('dynamic_attributes', dict)
  end

  # Ordinary (non-DC) component instance: a plain straight-edge box.
  def ordinary_component(x_size: 2.243275, y_size: 1.719255, z_size: 97.755906)
    definition = Sketchup::ComponentDefinition.new('OrdinaryPost')
    build_box(definition.entities, x_size, y_size, z_size)
    Sketchup::ComponentInstance.new(definition)
  end

  # Dynamic Component reproducing the reported bug: a turned/curved post
  # with dynamic_attributes and _lenz_access = LIST, matching the
  # reported bounds.
  def dynamic_component_post(x_size: 2.243275, y_size: 1.719255, z_size: 97.755906)
    definition = Sketchup::ComponentDefinition.new('DCPost')
    build_curved_post(definition.entities, x_size, y_size, z_size)
    instance = Sketchup::ComponentInstance.new(definition)
    mark_as_dynamic_component(instance, lenz: (z_size / 1.0254).to_s)
    instance
  end

  def group_box(x_size: 2.243275, y_size: 1.719255, z_size: 97.755906)
    definition = Sketchup::ComponentDefinition.new('GroupBox')
    build_box(definition.entities, x_size, y_size, z_size)
    Sketchup::Group.new(definition)
  end

  # A "frame"-shaped wireframe: 4 distinct Z levels (0, leg, z_size-leg,
  # z_size), edge loops at each level plus vertical connectors between
  # adjacent levels. build_smart_scale_gesture_state_for_entity's profile
  # detection needs >= 4 distinct axis values to classify an object as
  # :frame mode (protected ends + a stretched middle span) rather than
  # :basic mode (plain uniform instance-transformation scale) -- :frame
  # mode is the one that mutates the component DEFINITION's own geometry
  # (entities.transform_by_vectors), which is why sharing a definition
  # only matters for it, never for :basic mode or a normal (non-Smart
  # Scale) transform.
  def build_frame(entities, x_size, y_size, z_size, leg)
    hx = x_size / 2.0
    hy = y_size / 2.0
    levels = [0.0, leg, z_size - leg, z_size]
    levels.each do |z|
      corners = [
        Geom::Point3d.new(-hx, -hy, z),
        Geom::Point3d.new(hx, -hy, z),
        Geom::Point3d.new(hx, hy, z),
        Geom::Point3d.new(-hx, hy, z)
      ]
      4.times { |i| entities << Sketchup::Edge.new(corners[i], corners[(i + 1) % 4]) }
    end
    0.upto(levels.length - 2) do |li|
      z0 = levels[li]
      z1 = levels[li + 1]
      [[-hx, -hy], [hx, -hy], [hx, hy], [-hx, hy]].each do |x, y|
        entities << Sketchup::Edge.new(Geom::Point3d.new(x, y, z0), Geom::Point3d.new(x, y, z1))
      end
    end
  end

  # A frame-shaped ComponentInstance, added directly to `entities` (the
  # model's active entities by default) so it participates in real
  # Entities#add_instance-style sharing semantics the same way a user's
  # selection would.
  def frame_component(entities, name: 'Frame', x_size: 4.0, y_size: 4.0, z_size: 100.0, leg: 10.0)
    definition = Sketchup::ComponentDefinition.new(name)
    build_frame(definition.entities, x_size, y_size, z_size, leg)
    entities.add_instance(definition, Geom::Transformation.new)
  end
end
