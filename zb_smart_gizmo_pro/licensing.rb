# frozen_string_literal: true

module Zbellbound
  module SmartGizmoPro
    # The Extension Warehouse license gate, decided by ExtensionLicense#licensed?
    # alone (state only picks the refusal wording). ZB Smart Gizmo Pro is sold
    # exclusively through the SketchUp Extension Warehouse, so the only source
    # of truth is SketchUp's own Sketchup::Licensing API -- there is no
    # Zbellbound account, activation server, product key, network call or local
    # preference behind this. Nothing is stored: every check asks SketchUp
    # again (the documented contract -- a license may be granted, renewed or
    # revoked at any time), and no ExtensionLicense object is ever kept.
    #
    # WHERE this runs (never as the only check at SketchUp startup, when
    # SketchUp skips automatic license fetching):
    # * silently (allowed?) for every automatic activation route -- the
    #   observer's model-open / scene-change activation, the overlay's own
    #   start, and the post-Preferences refresh. No message is ever shown for
    #   these, so nothing appears while SketchUp is loading a model.
    # * visibly (authorize) for the toolbar/menu command and at the start of
    #   every gizmo gesture and model-changing operation, so a refusal always
    #   tells the user why and leaves the model untouched.
    # Manual, About and Preferences are separate commands and are not gated.
    module Licensing
      # User-facing text only: never a license state code, the identifier
      # below, an exception class or a backtrace.
      TRIAL_EXPIRED_MESSAGE =
        'Your ZB Smart Gizmo Pro trial has ended. To keep using it, purchase a license ' \
        'from the SketchUp Extension Warehouse.'
      EXPIRED_MESSAGE =
        'Your ZB Smart Gizmo Pro license has expired. To keep using it, renew it ' \
        'from the SketchUp Extension Warehouse.'
      NOT_LICENSED_MESSAGE =
        'ZB Smart Gizmo Pro needs a valid Extension Warehouse license. Purchase it, or start ' \
        'the free trial, from the SketchUp Extension Warehouse.'
      UNVERIFIED_MESSAGE =
        'ZB Smart Gizmo Pro could not check its license. Sign in to SketchUp, then update the ' \
        'license from Extension Manager and try again.'

      # ok      - true when the gizmo may activate / be used
      # message - the concise, user-facing reason when it may not; nil when ok
      Result = Struct.new(:ok, :message)

      # Asks SketchUp -- fresh, every time -- whether this installation may
      # run. ExtensionLicense#licensed? is the ONLY authority, exactly as
      # SketchUp's licensing guide specifies: it is true for a valid license
      # and for a running trial, and false otherwise. #state is informational
      # and is used solely to choose which refusal message the user reads, so
      # a state that contradicts licensed? can never grant access.
      #
      # Anything unexpected refuses: a nil license, an object without
      # licensed?, licensed? returning anything other than exactly true
      # (nil, a truthy non-boolean), or any raised error. Refusing is always
      # the safe direction -- the user is told how to fix it, and Manual,
      # About and Preferences stay available either way.
      def self.check
        # ZB Smart Gizmo Pro's own Extension Warehouse Unique Identifier,
        # inline as a local string literal: RuboCop-SketchUp's
        # SketchupRequirements/GetExtensionLicense cop refuses a constant here,
        # and an offense in that department is a submission blocker.
        license = Sketchup::Licensing.get_extension_license('29a0b6d0-46a3-4e8d-924f-e1091cf61251')
        return Result.new(true, nil) if license.respond_to?(:licensed?) && license.licensed? == true

        Result.new(false, refusal_message(license))
      rescue StandardError => e
        log_issue("License check failed: #{e.class}: #{e.message}")
        Result.new(false, UNVERIFIED_MESSAGE)
      end

      # Silent form of check, for the automatic activation routes: a fresh
      # lookup, a plain true/false, and never any UI.
      def self.allowed?
        check.ok
      end

      # Visible form of check, for the toolbar/menu command and for every
      # gizmo gesture or model-changing operation: a fresh lookup that, on
      # refusal, tells the user why with a plain message. Returns true/false.
      def self.authorize
        result = check
        UI.messagebox(result.message) unless result.ok
        result.ok
      end

      # Chooses the wording for a refusal already decided by licensed?.
      # An unrecognized, contradictory, missing or raising state simply
      # falls back to "could not check" -- it never changes the verdict.
      def self.refusal_message(license)
        state = license.respond_to?(:state) ? license.state : nil
        case state
        when constant(:TRIAL_EXPIRED) then TRIAL_EXPIRED_MESSAGE
        when constant(:EXPIRED) then EXPIRED_MESSAGE
        when constant(:NOT_LICENSED) then NOT_LICENSED_MESSAGE
        else
          log_issue("Refused; state not recognized: #{state.inspect}")
          UNVERIFIED_MESSAGE
        end
      rescue StandardError => e
        log_issue("License state unreadable: #{e.class}: #{e.message}")
        UNVERIFIED_MESSAGE
      end
      private_class_method :refusal_message

      # Each state constant is read through this so a SketchUp build that
      # does not define one of them degrades to "unknown state" (refused
      # with UNVERIFIED_MESSAGE) instead of raising NameError. Returns a
      # unique sentinel when missing, so `case` can never match it.
      def self.constant(name)
        return Sketchup::Licensing.const_get(name) if Sketchup::Licensing.const_defined?(name)

        Object.new
      end
      private_class_method :constant

      # Diagnostics only, and silent in production: DEBUG_MODE is false in
      # every shipped build, and it is never consulted for the allow/deny
      # decision itself -- there is no debug exemption from licensing.
      def self.log_issue(text)
        warn("[ZB Smart Gizmo Pro] #{text}") if DEBUG_MODE
      end
      private_class_method :log_issue
    end
  end
end
