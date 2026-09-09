# Minimal fake SketchUp/Geom Ruby API, just sufficient to load and exercise
# zb_smart_gizmo_pro/utils.rb and zb_smart_gizmo_pro/overlay.rb outside of SketchUp.
#
# Only implements the subset of behavior the plugin code actually touches.
# Not a general-purpose SketchUp API stub.

module Geom
  class Vector3d
    attr_reader :x, :y, :z

    def initialize(x = 0.0, y = 0.0, z = 0.0)
      if x.is_a?(Array)
        @x, @y, @z = x[0].to_f, x[1].to_f, x[2].to_f
      else
        @x, @y, @z = x.to_f, y.to_f, z.to_f
      end
    end

    def length
      Math.sqrt((x * x) + (y * y) + (z * z))
    end

    def length=(new_length)
      current = length
      if current < 1e-12
        @x, @y, @z = new_length.to_f, 0.0, 0.0
      else
        factor = new_length.to_f / current
        @x *= factor
        @y *= factor
        @z *= factor
      end
      new_length
    end

    def valid?
      length > 1e-12
    end

    def clone
      Vector3d.new(x, y, z)
    end

    def reverse
      Vector3d.new(-x, -y, -z)
    end

    def reverse!
      @x = -@x
      @y = -@y
      @z = -@z
      self
    end

    def normalize
      l = length
      l < 1e-12 ? clone : Vector3d.new(x / l, y / l, z / l)
    end

    def normalize!
      l = length
      unless l < 1e-12
        @x /= l
        @y /= l
        @z /= l
      end
      self
    end

    def cross(other)
      Vector3d.new(
        (y * other.z) - (z * other.y),
        (z * other.x) - (x * other.z),
        (x * other.y) - (y * other.x)
      )
    end
    alias * cross

    def dot(other)
      (x * other.x) + (y * other.y) + (z * other.z)
    end
    alias % dot

    def samedirection?(other)
      a = normalize
      b = other.normalize
      a.dot(b) > 0.999999
    end

    def parallel?(other)
      cross(other).length < 1e-9
    end

    def ==(other)
      other.is_a?(Vector3d) &&
        (x - other.x).abs < 1e-9 &&
        (y - other.y).abs < 1e-9 &&
        (z - other.z).abs < 1e-9
    end

    def to_a
      [x, y, z]
    end
  end

  class Point3d
    attr_reader :x, :y, :z

    def initialize(x = 0.0, y = 0.0, z = 0.0)
      if x.is_a?(Array)
        @x, @y, @z = x[0].to_f, x[1].to_f, x[2].to_f
      else
        @x, @y, @z = x.to_f, y.to_f, z.to_f
      end
    end

    def clone
      Point3d.new(x, y, z)
    end

    def vector_to(other)
      Vector3d.new(other.x - x, other.y - y, other.z - z)
    end

    def distance(other)
      vector_to(other).length
    end

    def offset(vector, len = nil)
      v = vector.clone
      v.length = len if len
      Point3d.new(x + v.x, y + v.y, z + v.z)
    end

    def +(vector)
      offset(vector)
    end

    def -(other)
      if other.is_a?(Point3d)
        Vector3d.new(x - other.x, y - other.y, z - other.z)
      else
        offset(other.reverse)
      end
    end

    def transform(transformation)
      transformation.transform_point(self)
    end

    def to_a
      [x, y, z]
    end

    def ==(other)
      other.is_a?(Point3d) &&
        (x - other.x).abs < 1e-9 &&
        (y - other.y).abs < 1e-9 &&
        (z - other.z).abs < 1e-9
    end
  end

  # 4x4 affine transformation, stored row-major (16 floats), acting on
  # homogeneous column vectors: p' = M * p.
  class Transformation
    attr_reader :m

    def initialize(*args)
      if args.empty?
        @m = identity_matrix
      elsif args.length == 1 && args[0].is_a?(Array) && args[0].length == 16
        @m = args[0].dup
      elsif args.length == 1 && args[0].is_a?(Point3d)
        @m = identity_matrix
        set_translation(args[0])
      elsif args.length == 4
        xaxis, yaxis, zaxis, origin = args
        @m = identity_matrix
        set_column(0, xaxis.x, xaxis.y, xaxis.z, 0.0)
        set_column(1, yaxis.x, yaxis.y, yaxis.z, 0.0)
        set_column(2, zaxis.x, zaxis.y, zaxis.z, 0.0)
        set_column(3, origin.x, origin.y, origin.z, 1.0)
      else
        raise ArgumentError, "Unsupported Transformation.new args: #{args.inspect}"
      end
    end

    def self.scaling(*args)
      if args.length == 4 && args[0].is_a?(Point3d)
        origin, sx, sy, sz = args
        tr = allocate
        tr.instance_variable_set(:@m, tr.send(:identity_matrix))
        tr.send(:set_column, 0, sx.to_f, 0.0, 0.0, 0.0)
        tr.send(:set_column, 1, 0.0, sy.to_f, 0.0, 0.0)
        tr.send(:set_column, 2, 0.0, 0.0, sz.to_f, 0.0)
        tx = origin.x - (sx.to_f * origin.x)
        ty = origin.y - (sy.to_f * origin.y)
        tz = origin.z - (sz.to_f * origin.z)
        tr.send(:set_column, 3, tx, ty, tz, 1.0)
        tr
      elsif args.length == 3
        sx, sy, sz = args
        tr = allocate
        tr.instance_variable_set(:@m, tr.send(:identity_matrix))
        tr.send(:set_column, 0, sx.to_f, 0.0, 0.0, 0.0)
        tr.send(:set_column, 1, 0.0, sy.to_f, 0.0, 0.0)
        tr.send(:set_column, 2, 0.0, 0.0, sz.to_f, 0.0)
        tr
      elsif args.length == 1
        s = args[0].to_f
        scaling(s, s, s)
      else
        raise ArgumentError, "Unsupported Transformation.scaling args: #{args.inspect}"
      end
    end

    def self.translation(vector)
      tr = new
      tr.send(:set_column, 3, vector.x, vector.y, vector.z, 1.0)
      tr
    end

    def self.rotation(point, axis, angle)
      a = axis.normalize
      c = Math.cos(angle)
      s = Math.sin(angle)
      t = 1 - c
      x, y, z = a.x, a.y, a.z

      r = [
        [t * x * x + c,     t * x * y - s * z, t * x * z + s * y],
        [t * x * y + s * z, t * y * y + c,     t * y * z - s * x],
        [t * x * z - s * y, t * y * z + s * x, t * z * z + c]
      ]

      tr = allocate
      m = tr.send(:identity_matrix)
      (0..2).each do |row|
        (0..2).each do |col|
          m[(row * 4) + col] = r[row][col]
        end
      end
      tr.instance_variable_set(:@m, m)

      # Compose with translation to/from rotation point: T(p) * R * T(-p)
      to_origin = translation(Vector3d.new(-point.x, -point.y, -point.z))
      from_origin = translation(Vector3d.new(point.x, point.y, point.z))
      from_origin * tr * to_origin
    end

    def origin
      Point3d.new(@m[3], @m[7], @m[11])
    end

    def xaxis
      Vector3d.new(@m[0], @m[4], @m[8]).normalize
    end

    def yaxis
      Vector3d.new(@m[1], @m[5], @m[9]).normalize
    end

    def zaxis
      Vector3d.new(@m[2], @m[6], @m[10]).normalize
    end

    def transform_point(point)
      x = (@m[0] * point.x) + (@m[1] * point.y) + (@m[2] * point.z) + @m[3]
      y = (@m[4] * point.x) + (@m[5] * point.y) + (@m[6] * point.z) + @m[7]
      z = (@m[8] * point.x) + (@m[9] * point.y) + (@m[10] * point.z) + @m[11]
      w = (@m[12] * point.x) + (@m[13] * point.y) + (@m[14] * point.z) + @m[15]
      w = 1.0 if w == 0.0
      Point3d.new(x / w, y / w, z / w)
    end

    def *(other)
      result = Array.new(16, 0.0)
      (0..3).each do |row|
        (0..3).each do |col|
          sum = 0.0
          (0..3).each do |k|
            sum += @m[(row * 4) + k] * other.m[(k * 4) + col]
          end
          result[(row * 4) + col] = sum
        end
      end
      Transformation.new(result)
    end

    def inverse
      # Affine inverse: split into 3x3 linear part R and translation t.
      r = [
        [@m[0], @m[1], @m[2]],
        [@m[4], @m[5], @m[6]],
        [@m[8], @m[9], @m[10]]
      ]
      t = [@m[3], @m[7], @m[11]]

      det = r[0][0] * (r[1][1] * r[2][2] - r[1][2] * r[2][1]) -
            r[0][1] * (r[1][0] * r[2][2] - r[1][2] * r[2][0]) +
            r[0][2] * (r[1][0] * r[2][1] - r[1][1] * r[2][0])
      raise "Transformation is not invertible" if det.abs < 1e-15

      inv_det = 1.0 / det
      ri = Array.new(3) { Array.new(3, 0.0) }
      ri[0][0] = (r[1][1] * r[2][2] - r[1][2] * r[2][1]) * inv_det
      ri[0][1] = (r[0][2] * r[2][1] - r[0][1] * r[2][2]) * inv_det
      ri[0][2] = (r[0][1] * r[1][2] - r[0][2] * r[1][1]) * inv_det
      ri[1][0] = (r[1][2] * r[2][0] - r[1][0] * r[2][2]) * inv_det
      ri[1][1] = (r[0][0] * r[2][2] - r[0][2] * r[2][0]) * inv_det
      ri[1][2] = (r[0][2] * r[1][0] - r[0][0] * r[1][2]) * inv_det
      ri[2][0] = (r[1][0] * r[2][1] - r[1][1] * r[2][0]) * inv_det
      ri[2][1] = (r[0][1] * r[2][0] - r[0][0] * r[2][1]) * inv_det
      ri[2][2] = (r[0][0] * r[1][1] - r[0][1] * r[1][0]) * inv_det

      ti = [
        -((ri[0][0] * t[0]) + (ri[0][1] * t[1]) + (ri[0][2] * t[2])),
        -((ri[1][0] * t[0]) + (ri[1][1] * t[1]) + (ri[1][2] * t[2])),
        -((ri[2][0] * t[0]) + (ri[2][1] * t[1]) + (ri[2][2] * t[2]))
      ]

      m = Array.new(16, 0.0)
      (0..2).each do |row|
        (0..2).each do |col|
          m[(row * 4) + col] = ri[row][col]
        end
        m[(row * 4) + 3] = ti[row]
      end
      m[15] = 1.0
      Transformation.new(m)
    end

    def to_a
      @m.dup
    end

    private

    def identity_matrix
      [1.0, 0.0, 0.0, 0.0,
       0.0, 1.0, 0.0, 0.0,
       0.0, 0.0, 1.0, 0.0,
       0.0, 0.0, 0.0, 1.0]
    end

    def set_column(col, x, y, z, w)
      @m[(0 * 4) + col] = x
      @m[(1 * 4) + col] = y
      @m[(2 * 4) + col] = z
      @m[(3 * 4) + col] = w
    end
  end

  class BoundingBox
    def initialize
      @empty = true
      @min = nil
      @max = nil
    end

    def add(obj)
      points =
        case obj
        when Point3d then [obj]
        when BoundingBox
          obj.empty? ? [] : (0..7).map { |i| obj.corner(i) }
        when Array then obj
        else raise ArgumentError, "Cannot add #{obj.class} to BoundingBox"
        end

      points.each { |p| add_point(p) }
      self
    end

    def empty?
      @empty
    end

    def min
      @min
    end

    def max
      @max
    end

    def center
      Point3d.new((min.x + max.x) / 2.0, (min.y + max.y) / 2.0, (min.z + max.z) / 2.0)
    end

    def corner(i)
      x = (i & 1).zero? ? min.x : max.x
      y = (i & 2).zero? ? min.y : max.y
      z = (i & 4).zero? ? min.z : max.z
      Point3d.new(x, y, z)
    end

    def width
      max.x - min.x
    end

    def height
      max.y - min.y
    end

    def depth
      max.z - min.z
    end

    private

    def add_point(p)
      if @empty
        @min = p.clone
        @max = p.clone
        @empty = false
      else
        @min = Point3d.new([@min.x, p.x].min, [@min.y, p.y].min, [@min.z, p.z].min)
        @max = Point3d.new([@max.x, p.x].max, [@max.y, p.y].max, [@max.z, p.z].max)
      end
    end
  end

  def self.tesselate(outer, _inner = [])
    outer
  end
end

IDENTITY = Geom::Transformation.new
ORIGIN = Geom::Point3d.new(0, 0, 0)
X_AXIS = Geom::Vector3d.new(1, 0, 0)
Y_AXIS = Geom::Vector3d.new(0, 1, 0)
Z_AXIS = Geom::Vector3d.new(0, 0, 1)

# SketchUp extends Array with index-named accessors (used as `@axes.x` etc
# throughout gizmo.rb, where @axes is a 3-element array of Axis objects).
class Array
  def x
    self[0]
  end

  def y
    self[1]
  end

  def z
    self[2]
  end
end

# SketchUp extends Numeric with unit-conversion helpers. Internal length
# unit is always inches.
class Numeric
  def mm
    self / 25.4
  end

  def cm
    self / 2.54
  end

  def m
    self / 0.0254
  end

  def inch
    to_f
  end
  alias in inch

  def feet
    to_f * 12.0
  end
  alias ft feet

  def degrees
    to_f * Math::PI / 180.0
  end

  def radians
    to_f
  end

  # Real SketchUp API: converts a plain number (assumed inches, the
  # internal length unit) into a Length. Used throughout overlay.rb for
  # parsed/accumulated scale expressions (e.g. `total.to_l`).
  def to_l
    Length.new(to_f)
  end
end

# Test-only model units configuration, standing in for what a real
# SketchUp model's Model Info > Units page controls. Adjustable per test
# so specs can confirm Length#to_s / Sketchup.format_length actually
# react to the model's configured unit, precision, and decimal
# separator (locale), rather than a value baked into production code.
module TestUnits
  class << self
    attr_accessor :unit, :precision, :decimal_separator
  end

  self.unit = 'mm'
  self.precision = 2
  self.decimal_separator = '.'

  def self.reset!
    self.unit = 'mm'
    self.precision = 2
    self.decimal_separator = '.'
  end

  INCHES_PER_UNIT = {
    'in' => 1.0,
    'ft' => 12.0,
    'mm' => 1.0 / 25.4,
    'cm' => 1.0 / 2.54,
    'm' => 1.0 / 0.0254
  }.freeze

  # Real SketchUp's Decimal-format unit suffix is not always the unit's
  # own name: inches and feet use the quote-mark symbols. Millimeter/
  # centimeter/meter use their plain abbreviation.
  UNIT_SUFFIXES = {
    'mm' => 'mm',
    'cm' => 'cm',
    'm' => 'm',
    'in' => '"',
    'ft' => "'"
  }.freeze

  # Mirrors the real Sketchup.format_length / Length#to_s contract:
  # format using the model's current unit and precision, stripping
  # trailing zeros the way SketchUp's own formatter does (confirmed
  # against ruby.sketchup.com/Sketchup.html#format_length-class_method:
  # "a negative number [precision] will strip trailing zeros").
  def self.format(inches)
    per_unit = INCHES_PER_UNIT.fetch(unit, INCHES_PER_UNIT['mm'])
    value = inches.to_f / per_unit
    text = sprintf('%.*f', precision, value)
    text = text.sub(/0+\z/, '').sub(/\.\z/, '') if text.include?('.')
    text = '0' if text.empty? || text == '-'
    text = text.tr('.', decimal_separator) if decimal_separator != '.'
    "#{text}#{UNIT_SUFFIXES.fetch(unit, unit)}"
  end

  # Maps the test-configured unit to the real, documented Length::*
  # unit constant it corresponds to (ruby.sketchup.com/Length.html),
  # for Model#options['UnitsOptions']['LengthUnit'] to return.
  def self.length_unit_constant
    case unit
    when 'mm' then Length::Millimeter
    when 'cm' then Length::Centimeter
    when 'm' then Length::Meter
    when 'in' then Length::Inches
    when 'ft' then Length::Feet
    else Length::Millimeter
    end
  end
end

# Real SketchUp API: represents a length (always stored internally as
# inches). #to_s "format[s] a length as a String using the current units
# formatting settings for the model" (ruby.sketchup.com/Length.html) --
# stubbed here via TestUnits.format so specs can flip unit/precision/
# separator and confirm the display reacts, without reimplementing
# SketchUp's real formatting engine.
class Length
  # Real SketchUp API: documented format/unit constants (confirmed
  # against ruby.sketchup.com/Length.html), used to interpret
  # Model#options['UnitsOptions']['LengthFormat'/'LengthUnit'] instead
  # of guessing raw indices. Real SketchUp doesn't document their exact
  # integer values ("use string keys instead of numerical indicies" is
  # the guidance for the OPTION NAMES, not these constants) -- stubbed
  # as symbols so production code that compares against these constants
  # by identity works the same regardless of the real underlying value.
  Decimal = :decimal
  Architectural = :architectural
  Engineering = :engineering
  Fractional = :fractional

  Inches = :inches
  Feet = :feet
  Millimeter = :millimeter
  Centimeter = :centimeter
  Meter = :meter
  Yard = :yard

  include Comparable

  def initialize(inches)
    @inches = inches.to_f
  end

  def to_f
    @inches
  end

  def to_l
    self
  end

  def to_s
    TestUnits.format(@inches)
  end

  def <=>(other)
    to_f <=> other.to_f
  end

  def positive?
    @inches.positive?
  end

  def abs
    Length.new(@inches.abs)
  end

  def +(other)
    Length.new(to_f + other.to_f)
  end

  def -(other)
    Length.new(to_f - other.to_f)
  end

  def *(scalar)
    Length.new(to_f * scalar.to_f)
  end

  # Real SketchUp Length#/ always yields a plain (dimensionless) number
  # -- production code only ever divides a Length by a reference length
  # to get a scale ratio, never expecting another Length back.
  def /(other)
    to_f / other.to_f
  end

  def coerce(other)
    [Length.new(other.to_f), self]
  end
end

# Real SketchUp API: parses a length expression string (e.g. "600mm",
# "24in", "6'-2\"") into a Length, in whatever unit the text specifies.
# A bare number with no unit suffix is interpreted in the model's
# current unit, matching real SketchUp's String#to_l. Raises
# ArgumentError for anything unparseable (production code relies on
# this -- see the `rescue ArgumentError` in onUserText/
# parse_scale_length_expression).
class String
  LENGTH_SUFFIX_INCHES = {
    'mm' => 1.0 / 25.4,
    'cm' => 1.0 / 2.54,
    'm' => 1.0 / 0.0254,
    'in' => 1.0,
    '"' => 1.0,
    'ft' => 12.0,
    "'" => 12.0
  }.freeze

  def to_l
    text = strip
    match = /\A([+-]?[\d.]+)\s*("|'|[a-zA-Z]*)\z/.match(text)
    raise ArgumentError, "Invalid length: #{self}" unless match

    number = Float(match[1])
    suffix = match[2].downcase
    per_unit = if suffix.empty?
      TestUnits::INCHES_PER_UNIT.fetch(TestUnits.unit, 1.0)
    else
      String::LENGTH_SUFFIX_INCHES[suffix]
    end
    raise ArgumentError, "Invalid length: #{self}" unless per_unit

    Length.new(number * per_unit)
  rescue ArgumentError
    raise
  rescue StandardError
    raise ArgumentError, "Invalid length: #{self}"
  end
end

module Sketchup
  # Test-double-only recording of the last VCB label/value production
  # code set, so specs can assert on exactly what's shown to the user
  # (e.g. the formatted Scale dimension) without a real Measurements box.
  class << self
    attr_accessor :last_vcb_label, :last_vcb_value
  end

  class Color
    def initialize(*args); end
  end

  # Real SketchUp API: a single named attribute dictionary attached to an
  # Entity, as returned by Entity#attribute_dictionary /
  # #attribute_dictionaries. Only implements the subset actually used:
  # #[]/#[]=, #each_pair, #name.
  class AttributeDictionary
    attr_reader :name

    def initialize(name)
      @name = name
      @data = {}
    end

    def [](key)
      @data[key]
    end

    def []=(key, value)
      @data[key] = value
    end

    def each_pair(&block)
      @data.each_pair(&block)
    end
    alias each each_pair

    def keys
      @data.keys
    end

    def to_h
      @data.dup
    end

    def ==(other)
      other.is_a?(AttributeDictionary) && other.name == @name && other.to_h == to_h
    end

    def initialize_copy(other)
      super
      @data = other.to_h
    end
  end

  # Real SketchUp API base class for every entity (Vertex, Drawingelement
  # subclasses, ComponentDefinition, ...). attribute_dictionary(y),
  # attribute_dictionaries, set_attribute and get_attribute are all
  # documented directly on Entity, not on Drawingelement.
  class Entity
    def initialize
      @attribute_dictionaries = {}
      @deleted = false
    end

    def valid?
      !@deleted
    end

    def deleted?
      @deleted
    end

    def delete!
      @deleted = true
    end

    # Real SketchUp API: #erase! is documented on Drawingelement (not
    # Entity), but the stub's deletion bookkeeping lives on Entity, so it's
    # aliased here rather than duplicated on Drawingelement.
    alias erase! delete!

    def attribute_dictionary(name, create = false)
      return @attribute_dictionaries[name] if @attribute_dictionaries[name]
      return nil unless create

      @attribute_dictionaries[name] = AttributeDictionary.new(name)
    end

    def attribute_dictionaries
      return nil if @attribute_dictionaries.empty?

      @attribute_dictionaries.values
    end

    def set_attribute(dict_name, key, value)
      dict = attribute_dictionary(dict_name, true)
      dict[key] = value
    end

    def get_attribute(dict_name, key, default_value = nil)
      dict = @attribute_dictionaries[dict_name]
      return default_value unless dict

      value = dict[key]
      value.nil? ? default_value : value
    end

    # Test-only convenience: bulk-load a whole dictionary from a plain
    # Hash, so fixtures don't need to call set_attribute key by key.
    def set_test_attribute_dictionary(name, hash)
      dict = AttributeDictionary.new(name)
      hash.each { |k, v| dict[k] = v }
      @attribute_dictionaries[name] = dict
    end
  end

  class Vertex < Entity
    attr_accessor :position

    def initialize(position)
      super()
      @position = position
    end
  end

  # Real SketchUp API base class for Edge/Face/ComponentInstance/Group/etc.
  # bounds/casts_shadows/hidden/layer/material/receives_shadows/visible
  # are all documented directly on Drawingelement, so every subclass gets
  # them for free here rather than each redefining its own. glued_to is
  # documented on ComponentInstance/Group specifically, but is harmless
  # and simpler to share here since copy_array_selection_issue only ever
  # checks it via respond_to?.
  class Drawingelement < Entity
    attr_accessor :material, :layer, :glued_to
    attr_writer :name

    def initialize
      super()
      @name = ''
      @hidden = false
      @casts_shadows = true
      @receives_shadows = true
      @glued_to = nil
    end

    def name
      @name
    end

    def hidden?
      @hidden
    end

    def hidden=(value)
      @hidden = value
    end

    def visible?
      !@hidden
    end

    def visible=(value)
      @hidden = !value
    end

    def casts_shadows?
      @casts_shadows
    end

    def casts_shadows=(value)
      @casts_shadows = value
    end

    def receives_shadows?
      @receives_shadows
    end

    def receives_shadows=(value)
      @receives_shadows = value
    end
  end

  # No #copy, #transform!, or #explode here on purpose: the real
  # SketchUp Ruby API defines none of those on Edge (nor on Face,
  # ComponentInstance, or the shared Drawingelement base -- #copy exists
  # only on Group). The copy-array feature is scoped to Group/
  # ComponentInstance precisely because there is no documented, generic
  # duplication primitive for loose geometry.
  class Edge < Drawingelement
    attr_accessor :curve

    def initialize(p1, p2)
      super()
      @start = Vertex.new(p1)
      @end = Vertex.new(p2)
      @curve = nil
    end

    def vertices
      [@start, @end]
    end

    def bounds
      bb = Geom::BoundingBox.new
      bb.add(@start.position)
      bb.add(@end.position)
      bb
    end
  end

  class Face < Drawingelement
  end

  class Entities
    include Enumerable

    attr_reader :parent

    def initialize(parent = nil)
      @list = []
      @parent = parent
    end

    def <<(entity)
      @list << entity
      entity
    end

    def each(&block)
      @list.each(&block)
    end

    def grep(klass)
      @list.select { |e| e.is_a?(klass) }
    end

    def transform_entities(transformation, entities)
      Array(entities).each do |e|
        e.transformation = transformation * e.transformation if e.respond_to?(:transformation=)
      end
      true
    end

    def transform_by_vectors(vertices, vectors)
      vertices.each_with_index do |v, i|
        vec = vectors[i]
        v.position = Geom::Point3d.new(v.position.x + vec.x, v.position.y + vec.y, v.position.z + vec.z)
      end
      true
    end

    # Wraps `list` in a new Group appended to this Entities collection,
    # mirroring Sketchup::Entities#add_group. Used by the PRE-EXISTING
    # Ctrl-drag single-copy feature in overlay.rb (on_transform_end),
    # not by copy-array. The test fixtures never track which Entities
    # collection an instance "lives in", so unlike the real API this
    # doesn't need to remove `list` from elsewhere first.
    def add_group(list)
      definition = ComponentDefinition.new
      Array(list).each { |e| definition.entities << e }
      group = Group.new(definition)
      @list << group
      group
    end

    # Real Sketchup::Entities#add_instance(definition, transform). Places
    # a bare new ComponentInstance of `definition` at `transform` -- no
    # name/material/layer/attributes copying happens here, matching the
    # real API exactly; callers (copy_array's duplicate_component_instance)
    # are responsible for copying those across explicitly.
    def add_instance(definition, transform)
      instance = ComponentInstance.new(definition)
      instance.transformation = Geom::Transformation.new(transform.to_a)
      @list << instance
      instance
    end
  end

  class ComponentDefinition < Entity
    attr_reader :entities, :instances

    def initialize(name = nil)
      super()
      @name = name
      @entities = Entities.new(self)
      @instances = []
    end

    def bounds
      bb = Geom::BoundingBox.new
      @entities.grep(Edge).each do |e|
        e.vertices.each { |v| bb.add(v.position) }
      end
      @entities.grep(ComponentInstance).each do |ci|
        0.upto(7) { |i| bb.add(ci.bounds.corner(i)) }
      end
      bb
    end

    def invalidate_bounds
      nil
    end

    # Recursively duplicates this definition's entities into a fresh,
    # independent ComponentDefinition -- used by Group#copy (real API,
    # Group-specific) so array copies of a Group don't alias the
    # original's geometry. A nested Group child uses its own #copy; a
    # nested plain ComponentInstance has no #copy (matching the real
    # API), so it's duplicated the same way duplicate_component_instance
    # does in production: a fresh instance of the SAME shared definition
    # (plain instances share definitions; only Group has a private one),
    # with transformation/metadata/attributes copied across manually.
    def deep_copy
      new_def = ComponentDefinition.new(@name)
      @entities.each do |e|
        case e
        when Edge
          new_edge = Edge.new(e.vertices[0].position.clone, e.vertices[1].position.clone)
          new_edge.curve = e.curve
          new_def.entities << new_edge
        when Group
          new_def.entities << e.copy
        when ComponentInstance
          new_def.entities << ComponentDefinition.duplicate_plain_instance(e)
        end
      end
      new_def
    end

    def self.duplicate_plain_instance(source)
      dup = ComponentInstance.new(source.definition)
      dup.transformation = Geom::Transformation.new(source.transformation.to_a)
      dup.name = source.name
      dup.material = source.material
      dup.layer = source.layer
      dup.hidden = source.hidden?
      dup.casts_shadows = source.casts_shadows?
      dup.receives_shadows = source.receives_shadows?
      source.attribute_dictionaries&.each do |dictionary|
        dictionary.each_pair { |key, value| dup.set_attribute(dictionary.name, key, value) }
      end
      dup
    end
  end

  class ComponentInstance < Drawingelement
    attr_accessor :transformation
    attr_reader :definition

    def initialize(definition)
      super()
      @definition = definition
      @transformation = Geom::Transformation.new
      @locked = false
      definition.instances << self
    end

    def locked?
      @locked
    end

    def locked=(value)
      @locked = value
    end

    def bounds
      local_bb = @definition.bounds
      bb = Geom::BoundingBox.new
      return bb if local_bb.empty?

      0.upto(7) { |i| bb.add(local_bb.corner(i).transform(@transformation)) }
      bb
    end

    # Real Sketchup::ComponentInstance#make_unique: a no-op when this
    # instance's definition already has exactly one instance; otherwise
    # creates a genuinely independent copy of the definition's geometry
    # for this instance only, leaving every other instance (and its
    # geometry) attached to the original definition, untouched. Reuses
    # ComponentDefinition#deep_copy -- the same real duplication Group#copy
    # uses -- rather than shallow-copying entity references into the new
    # definition, which would leave the "unique" copy's Edge/Vertex
    # objects aliased to the original's (a real bug this stub used to
    # have: mutating the "unique" copy's geometry also mutated the
    # original's, since both definitions held the exact same Vertex
    # objects).
    def make_unique
      if @definition.instances.length > 1
        new_def = @definition.deep_copy
        @definition.instances.delete(self)
        @definition = new_def
        new_def.instances << self
      end
      self
    end

    def transform!(transformation)
      @transformation = transformation * @transformation
      self
    end

    # Moves this instance's direct children into whatever Entities
    # collection is exploding it, positioned by this instance's own
    # transformation, and invalidates the instance itself. Returns the
    # resulting entities, mirroring Sketchup::Drawingelement#explode.
    def explode
      return false unless valid?

      result = @definition.entities.to_a.map do |child|
        case child
        when Edge
          new_edge = Edge.new(child.vertices[0].position.transform(@transformation),
                               child.vertices[1].position.transform(@transformation))
          new_edge.curve = child.curve
          new_edge
        when ComponentInstance
          child.transform!(@transformation)
          child
        end
      end.compact

      delete!
      result
    end
  end

  # Real Sketchup::Group#copy: "defined specifically on the Group class,
  # not inherited from a parent class" (confirmed against
  # ruby.sketchup.com). ComponentInstance itself has no #copy -- see
  # duplicate_component_instance in overlay.rb for how a plain instance
  # is duplicated instead, via Entities#add_instance.
  class Group < ComponentInstance
    def entities
      definition.entities
    end

    def copy
      dup_instance = self.class.new(@definition.deep_copy)
      dup_instance.transformation = Geom::Transformation.new(@transformation.to_a)
      dup_instance.name = name
      dup_instance.material = material
      dup_instance.layer = layer
      dup_instance.hidden = hidden?
      dup_instance.casts_shadows = casts_shadows?
      dup_instance.receives_shadows = receives_shadows?
      attribute_dictionaries&.each do |dictionary|
        dictionary.each_pair { |key, value| dup_instance.set_attribute(dictionary.name, key, value) }
      end
      dup_instance
    end
  end

  class Selection
    include Enumerable

    def initialize(entities = [])
      @list = entities
    end

    def to_a
      @list.dup
    end

    def each(&block)
      @list.each(&block)
    end

    def length
      @list.length
    end

    def clear
      @list = []
    end

    def add(entities)
      Array(entities).each { |e| @list << e unless @list.include?(e) }
      true
    end

    def remove(entities)
      Array(entities).each { |e| @list.delete(e) }
      true
    end

    def contains?(entity)
      @list.include?(entity)
    end

    def empty?
      @list.empty?
    end

    def [](i)
      @list[i]
    end
  end

  class View
    def invalidate
      nil
    end

    def tooltip=(_value)
      nil
    end
  end

  class ModelAxes
    def xaxis
      Geom::Vector3d.new(1, 0, 0)
    end

    def yaxis
      Geom::Vector3d.new(0, 1, 0)
    end

    def zaxis
      Geom::Vector3d.new(0, 0, 1)
    end

    def origin
      Geom::Point3d.new(0, 0, 0)
    end

    def to_a
      [origin, xaxis, yaxis, zaxis]
    end
  end

  class Model
    attr_accessor :selection
    attr_reader :operation_log

    def initialize
      @selection = Selection.new
      @view = View.new
      @operation_log = []
    end

    def axes
      ModelAxes.new
    end

    def active_view
      @view
    end

    def active_entities
      @active_entities ||= Entities.new
    end

    # Real Sketchup::Model#options['UnitsOptions'] exposes the model's
    # Units settings (Window > Model Info > Units). Built fresh from
    # TestUnits on every call, so a spec can flip TestUnits.unit/
    # precision mid-test and see it reflected immediately, the same way
    # editing Model Info would. SuppressUnitsDisplay is always false
    # here -- production code must never read (or write) it to get a
    # bare number; that option is untouched by design.
    def options
      {
        'UnitsOptions' => {
          'LengthUnit' => TestUnits.length_unit_constant,
          'LengthFormat' => Length::Decimal,
          'LengthPrecision' => TestUnits.precision,
          'SuppressUnitsDisplay' => false
        }
      }
    end

    # Real Sketchup::Model#start_operation(op_name, disable_ui = false,
    # next_transparent = false, transparent = false). `transparent` (the
    # 4th positional arg) merges this operation backward into whatever
    # operation is currently on top of the undo stack -- logged here (not
    # otherwise modeled) so tests can confirm production code requests
    # that merge for the Ctrl-drag array re-edit path.
    def start_operation(op_name, disable_ui = false, next_transparent = false, transparent = false)
      @operation_log << [:start, op_name, disable_ui, next_transparent, transparent]
    end

    def commit_operation
      @operation_log << [:commit]
    end

    def abort_operation
      @operation_log << [:abort]
    end
  end

  class Overlay
    attr_accessor :enabled

    def initialize
      @enabled = false
    end

    def enabled?
      @enabled
    end
  end

  # Real Sketchup.read_default/write_default are backed by persistent,
  # OS-level storage (Windows registry under the extension's own key,
  # macOS preferences domain) keyed by [section][key] -- NOT anything
  # model- or session-specific, and NOT scoped by which .rbz happens to
  # be installed. A later reinstall of an extension that reads/writes
  # the same section sees whatever a previous install already wrote
  # there; a DIFFERENT section starts fresh, seeing only the caller's
  # own `default` argument. Modeled here as a plain in-memory registry so
  # specs can prove which section string an extension's settings
  # actually live under -- e.g. that a DEV-labelled build still reads
  # the same section a differently-labelled production build wrote to,
  # while a build using a distinct DEV label as the section would not.
  @default_registry = Hash.new { |hash, key| hash[key] = {} }

  class << self
    attr_accessor :default_registry
  end

  # Test-only: clears all simulated persisted defaults, so specs don't
  # leak state into each other. Call in setup, not because production
  # ever does this (there's no equivalent real operation).
  def self.reset_defaults_registry!
    self.default_registry = Hash.new { |hash, key| hash[key] = {} }
  end

  def self.read_default(section, key, default)
    store = default_registry[section.to_s]
    store.key?(key.to_s) ? store[key.to_s] : default
  end

  def self.write_default(section, key, value)
    default_registry[section.to_s][key.to_s] = value
  end

  def self.vcb_label=(value)
    self.last_vcb_label = value
  end

  def self.vcb_value=(value)
    self.last_vcb_value = value
  end
  def self.send_action(_action); end

  # Real Sketchup.format_length(number, precision = nil): "formats a
  # number as a length using the current units settings" (confirmed
  # against ruby.sketchup.com/Sketchup.html#format_length-class_method).
  # `number` is a plain Float in inches, same as Length#to_f -- accepts
  # either here since production code passes both.
  def self.format_length(number, _precision = nil)
    TestUnits.format(number.to_f)
  end
end

module UI
  class << self
    attr_accessor :last_messagebox_text
    attr_accessor :last_inputbox_args
  end

  def self.start_timer(_delay, _repeat = false)
    nil
  end

  # Real UI.messagebox just shows a dialog and returns a button code; it
  # has no test-observable return value. Capturing the text here is a
  # test-double-only convenience so specs can assert on the message
  # actually shown to the user, not a claim about production behavior.
  def self.messagebox(text, *_rest)
    self.last_messagebox_text = text
    nil
  end

  # Real UI.inputbox shows a modal dialog and returns the user's typed
  # values (or false if cancelled); there is no way to drive that
  # modally from a test. Recording the raw call arguments here is a
  # test-double-only convenience so specs can assert on exactly what
  # prompts/defaults/list/title production code builds, without
  # asserting anything about real dialog behavior. Always returns nil,
  # matching "user cancelled", so callers exercised in tests exit
  # cleanly via their own `next unless result` guard.
  def self.inputbox(*args)
    self.last_inputbox_args = args
    nil
  end

  def self.scale_factor
    1.0
  end
end
