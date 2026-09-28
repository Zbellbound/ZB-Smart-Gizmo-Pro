# Copyright Peter Zbel - Zbellbound.com
# ZB Smart Gizmo Pro

module Zbellbound::SmartGizmoPro
  # Per-instance custom gizmo orientation ("Align Gizmo XY to Face" / "Align
  # Gizmo X to Edge" / "Reset Gizmo Orientation to Object Axes"). Object/local
  # orientation normally follows a Group or ComponentInstance's own definition
  # axes -- geometry modeled at an angle and grouped afterward keeps whatever
  # axes it happened to have at grouping time, not the angle it visibly sits
  # at. These commands let the gizmo instead follow the visible geometry,
  # without changing the object's real axes, its transformation, or its
  # geometry in any way.
  #
  # Stored as two unit direction vectors (X and Z only -- Y is never stored,
  # always rederived as Z.cross(X)) in a dedicated attribute dictionary on the
  # INSTANCE itself, never the ComponentDefinition, so two instances of the
  # same shared component can each carry their own gizmo orientation, and
  # resetting or changing one never affects the other.
  #
  # The vectors are stored in the instance's own LOCAL (untransformed/
  # definition) space, not world space, specifically so a later move, rotate,
  # or non-uniform scale of the instance carries the custom orientation along
  # automatically: every read re-applies the instance's CURRENT
  # transformation and re-orthonormalizes from scratch, rather than trusting
  # a stale world-space direction. Deriving Y fresh on every read (never
  # storing or transforming it) is also what keeps the reconstructed basis
  # right-handed even when the instance has since been mirrored.
  module CustomOrientation
    DICTIONARY_NAME = 'zb_smart_gizmo_pro_orientation'.freeze
    X_KEY = 'local_x'.freeze
    Z_KEY = 'local_z'.freeze

    # Below this length (in whatever units the caller is working in -- these
    # vectors are always unit-length going in, so this is really a ratio),
    # a vector is treated as degenerate/collapsed by every check here. Far
    # larger than float noise on purpose: the concern is "did this collapse
    # under scaling or projection", not sub-epsilon precision.
    MIN_LENGTH = 1.0e-6

    def self.stored?(entity)
      return false unless entity.respond_to?(:attribute_dictionary)

      !entity.attribute_dictionary(DICTIONARY_NAME, false).nil?
    end

    # Returns [x, y, z] (Geom::Vector3d, unit length, mutually orthogonal,
    # right-handed: x.cross(y) == z) reconstructed from the stored local
    # vectors and entity.transformation -- i.e. in WORLD space, for the
    # gizmo's own on-screen axes -- or nil if nothing valid is stored, in
    # which case the caller falls back to the entity's native axes. Never
    # raises: any malformed or corrupted stored data (a foreign write, a
    # future format change) is treated the same as "nothing stored" rather
    # than crashing the gizmo.
    def self.world_axes_for(entity)
      local_x = read_vector(entity, X_KEY)
      local_z = read_vector(entity, Z_KEY)
      return nil unless local_x && local_z

      tr = entity.transformation
      orthonormal_basis(safe_transform(local_x, tr), safe_transform(local_z, tr))
    end

    # Same reconstruction, but WITHOUT applying entity.transformation --
    # i.e. still in the entity's own raw LOCAL/definition space. Smart
    # Scale's structural frame detection mutates that raw local geometry
    # directly (never entity.transformation itself), so it needs the custom
    # basis expressed in that same untransformed space to stay consistent
    # with what the gizmo is showing. nil under the same conditions as
    # world_axes_for.
    def self.local_axes_for(entity)
      local_x = read_vector(entity, X_KEY)
      local_z = read_vector(entity, Z_KEY)
      return nil unless local_x && local_z

      orthonormal_basis(local_x, local_z)
    end

    # x may be nil (a collapsed/absent read); z must already be a valid unit
    # vector or this returns nil entirely -- there is no meaningful basis
    # without a usable Z.
    def self.orthonormal_basis(x, z)
      return nil unless z

      x = x && orthogonalize(x, z)
      # A collapsed x (extreme shear/non-uniform scale, or simply absent)
      # still gets a valid, deterministic one rather than leaving the caller
      # without a basis at all -- the user explicitly aligned Z; silently
      # losing X entirely would be a worse surprise than picking an
      # arbitrary (but stable and reproducible) one perpendicular to it.
      x ||= arbitrary_perpendicular(z)
      [x, z.cross(x), z]
    end
    private_class_method :orthonormal_basis

    # Persists world_x/world_z (unit vectors in WORLD space, already
    # orthogonal to each other) as local vectors relative to entity's
    # CURRENT transformation. Pure attribute I/O only -- wrapping this in one
    # SketchUp Undo operation is the caller's responsibility. Returns false
    # (nothing written) if either vector collapses converting into local
    # space, which the caller should treat as a failed alignment.
    def self.store!(entity, world_x, world_z)
      inverse = entity.transformation.inverse
      local_x = safe_transform(world_x, inverse)
      local_z = safe_transform(world_z, inverse)
      return false unless local_x && local_z

      entity.set_attribute(DICTIONARY_NAME, X_KEY, local_x.to_a)
      entity.set_attribute(DICTIONARY_NAME, Z_KEY, local_z.to_a)
      true
    end

    # Removes only this dictionary -- never native axes, geometry, or any
    # other attribute dictionary the entity may carry. Returns false when
    # nothing was stored, so the caller can skip opening an Undo operation
    # for a no-op reset.
    def self.reset!(entity)
      return false unless stored?(entity)

      # Entity#delete_attribute(dict_name) with no key removes the whole
      # named dictionary. entity.attribute_dictionaries.delete would need
      # the actual AttributeDictionary object, not its name -- deliberately
      # not used here, to avoid an extra attribute_dictionary(name) lookup
      # for the one thing this method already knows how to do directly.
      entity.delete_attribute(DICTIONARY_NAME)
      true
    end

    # A deterministic vector perpendicular to `vector` (unit length), used
    # whenever no better candidate (a real boundary edge, or a projection
    # that didn't collapse) is available. Never returns a degenerate vector
    # for any valid non-zero input.
    def self.arbitrary_perpendicular(vector)
      reference = vector.parallel?(X_AXIS) ? Y_AXIS : X_AXIS
      orthogonalize(reference, vector) || Y_AXIS
    end

    # Removes any component of `vector` along `along` (assumed unit length)
    # and normalizes what remains. nil if that collapses too far to
    # normalize safely -- i.e. `vector` was effectively parallel to `along`.
    def self.orthogonalize(vector, along)
      scale = vector.dot(along)
      projected = Geom::Vector3d.new(vector.x - (along.x * scale), vector.y - (along.y * scale),
                                      vector.z - (along.z * scale))
      return nil if projected.length < MIN_LENGTH

      projected.normalize
    end

    def self.read_vector(entity, key)
      return nil unless entity.respond_to?(:get_attribute)

      raw = entity.get_attribute(DICTIONARY_NAME, key)
      return nil unless raw.is_a?(Array) && raw.length == 3
      return nil unless raw.all? { |component| component.is_a?(Numeric) }

      vector = Geom::Vector3d.new(*raw)
      vector.length < MIN_LENGTH ? nil : vector.normalize
    rescue StandardError
      nil
    end
    private_class_method :read_vector

    # Applies the LINEAR part of `transformation` to `vector` (Vector3d#
    # transform ignores translation) and normalizes -- nil if it collapsed
    # (e.g. an extreme non-uniform scale squashing a direction to ~zero)
    # rather than returning a garbage near-zero-length vector. Public: also
    # used directly by overlay.rb's face/edge-alignment math (a normal or an
    # edge direction pulled out of a raytest path is exactly this same
    # "transform, then normalize-or-nil" operation).
    def self.safe_transform(vector, transformation)
      transformed = vector.transform(transformation)
      transformed.length < MIN_LENGTH ? nil : transformed.normalize
    rescue StandardError
      nil
    end
  end
end
