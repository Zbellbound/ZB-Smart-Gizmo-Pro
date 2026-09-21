# SketchUp's own licensing API, stubbed for tests only -- the real
# Sketchup::Licensing exists solely inside SketchUp. Shaped like the documented
# surface (https://ruby.sketchup.com/Sketchup/Licensing.html and
# .../Licensing/ExtensionLicense.html): five state constants, and
# get_extension_license(id) returning an ExtensionLicense with #licensed? and
# #state.
#
# Defaults to LICENSED so every pre-existing test that reaches a gizmo or
# activation route is unaffected; with_license_state below drives the other
# states (and raising) for the licensing tests. Nothing here ships: test
# files are never packaged.
#
# licensed? and state are deliberately independent, so a test can contradict
# them (SketchUp's API makes licensed? the authority and state informational)
# and feed the REAL production module a state that disagrees with licensed? --
# the stub never re-implements the production allow/deny decision.
module Sketchup
  module Licensing
    LICENSED = 0
    EXPIRED = 1
    TRIAL = 2
    TRIAL_EXPIRED = 3
    NOT_LICENSED = 4

    # A temporary object representing the licensing state at the moment it
    # was returned, exactly like the real one.
    ExtensionLicense = Struct.new(:state_value, :licensed_flag, :state_error) do
      # licensed_flag nil means "derive from state" (the realistic default);
      # set it to force any value, including a non-boolean or a callable that
      # raises.
      def licensed?
        return licensed_flag.call if licensed_flag.respond_to?(:call)
        return licensed_flag unless licensed_flag.nil?

        state_value == LICENSED || state_value == TRIAL
      end

      def state
        raise state_error if state_error

        state_value
      end
    end

    class << self
      # Every id this stub was asked about, in order -- lets a test assert the
      # extension asks with its own identifier and how many lookups happened.
      def requested_ids
        @requested_ids ||= []
      end

      # Every license object this stub handed out, in order -- lets a test
      # prove each check received a brand-new object (nothing reused).
      def issued
        @issued ||= []
      end

      attr_writer :state, :raise_with, :licensed_flag, :state_error

      def state
        defined?(@state) && @state ? @state : LICENSED
      end

      def raise_with
        defined?(@raise_with) ? @raise_with : nil
      end

      def licensed_flag
        defined?(@licensed_flag) ? @licensed_flag : nil
      end

      def state_error
        defined?(@state_error) ? @state_error : nil
      end

      def reset!
        @state = LICENSED
        @raise_with = nil
        @licensed_flag = nil
        @state_error = nil
        @requested_ids = []
        @issued = []
      end

      def get_extension_license(id)
        requested_ids << id
        raise raise_with if raise_with
        return nil if state == :nil_license
        return Object.new.tap { |license| issued << license } if state == :object_without_licensed

        ExtensionLicense.new(state, licensed_flag, state_error).tap { |license| issued << license }
      end
    end
  end
end

module TestLicense
  module_function

  # Runs a block with SketchUp reporting the given license state (or raising
  # the given error), then restores the default licensed state.
  def with_state(state = nil, raises: nil, licensed: nil, state_raises: nil)
    Sketchup::Licensing.reset!
    Sketchup::Licensing.state = state if state
    Sketchup::Licensing.raise_with = raises
    Sketchup::Licensing.licensed_flag = licensed
    Sketchup::Licensing.state_error = state_raises
    yield
  ensure
    Sketchup::Licensing.reset!
  end

  # The state a plain unlicensed installation reports.
  def unlicensed(&block)
    with_state(Sketchup::Licensing::NOT_LICENSED, &block)
  end
end
