require 'minitest/autorun'
require 'open3'
require_relative 'support/load_plugin'

# Unit coverage for the Extension Warehouse license gate itself
# (zb_smart_gizmo_pro/licensing.rb): SketchUp's ExtensionLicense#licensed? is
# the ONLY authority; state only picks the refusal wording; anything
# unexpected refuses; nothing is cached; nothing leaks; and no license
# record, signature or foreign listing identifier ever enters the source.
#
# The routes that CALL the gate (observer, toolbar/menu, overlay gestures,
# mutation paths, Preferences) are covered in licensing_gate_test.rb.
class LicensingTest < Minitest::Test
  PRO_UUID = '29a0b6d0-46a3-4e8d-924f-e1091cf61251'.freeze

  # Extension Warehouse listing identifiers of OTHER Zbellbound products
  # (public listing ids, not secrets): they must never appear in this
  # product's shipped source.
  OTHER_LISTING_UUIDS = %w[
    7fa8f280-711c-4fac-9d06-d47eae46a5d2
    8e752bd9-762f-48bd-a725-d5c675dd682c
  ].freeze

  ROOT = File.expand_path('..', __dir__)
  LICENSING_PATH = File.join(ROOT, 'zb_smart_gizmo_pro', 'licensing.rb')
  LOADER_PATH = File.join(ROOT, 'zb_smart_gizmo_pro', 'loader.rb')
  Licensing = Zbellbound::SmartGizmoPro::Licensing
  L = Sketchup::Licensing

  def setup
    L.reset!
    UI.last_messagebox_text = nil
  end

  def teardown
    L.reset!
  end

  def shipped_ruby_files
    [File.join(ROOT, 'zb_smart_gizmo_pro.rb')] + Dir.glob(File.join(ROOT, 'zb_smart_gizmo_pro', '**', '*.rb'))
  end

  def licensing_source
    File.read(LICENSING_PATH)
  end

  # -- What is allowed -------------------------------------------------------

  def test_licensed_permits
    result = TestLicense.with_state(L::LICENSED) { Licensing.check }
    assert result.ok
    assert_nil result.message
  end

  def test_an_active_trial_reported_by_licensed_true_permits
    result = TestLicense.with_state(L::TRIAL) { Licensing.check }
    assert result.ok, 'an active Warehouse trial reports licensed? == true and must be allowed'
    assert_nil result.message
  end

  # -- What is blocked -------------------------------------------------------

  def test_not_licensed_blocks_with_the_license_required_message
    result = TestLicense.with_state(L::NOT_LICENSED) { Licensing.check }
    refute result.ok
    assert_equal Licensing::NOT_LICENSED_MESSAGE, result.message
  end

  def test_expired_blocks_with_the_license_expired_message
    result = TestLicense.with_state(L::EXPIRED) { Licensing.check }
    refute result.ok
    assert_equal Licensing::EXPIRED_MESSAGE, result.message
  end

  def test_trial_expired_blocks_with_the_trial_ended_message
    result = TestLicense.with_state(L::TRIAL_EXPIRED) { Licensing.check }
    refute result.ok
    assert_equal Licensing::TRIAL_EXPIRED_MESSAGE, result.message
  end

  def test_an_unknown_state_blocks_with_the_could_not_verify_message
    result = TestLicense.with_state(99, licensed: false) { Licensing.check }
    refute result.ok
    assert_equal Licensing::UNVERIFIED_MESSAGE, result.message
  end

  def test_a_nil_license_blocks_safely
    result = TestLicense.with_state(:nil_license) { Licensing.check }
    refute result.ok
    assert_equal Licensing::UNVERIFIED_MESSAGE, result.message
  end

  def test_a_raising_license_lookup_blocks_safely
    result = TestLicense.with_state(raises: RuntimeError.new('lookup exploded')) { Licensing.check }
    refute result.ok
    assert_equal Licensing::UNVERIFIED_MESSAGE, result.message
  end

  def test_an_object_without_a_licensed_predicate_blocks
    result = TestLicense.with_state(:object_without_licensed) { Licensing.check }
    refute result.ok
    assert_equal Licensing::UNVERIFIED_MESSAGE, result.message
  end

  def test_licensed_returning_nil_blocks
    # licensed_flag nil means "derive from state" in the stub, so force a nil
    # verdict through a callable instead.
    result = TestLicense.with_state(L::LICENSED, licensed: -> {}) { Licensing.check }
    refute result.ok, 'licensed? returning nil must block even though state says LICENSED'
  end

  def test_licensed_returning_a_truthy_non_boolean_blocks
    [1, 'yes', :true, [true]].each do |truthy|
      result = TestLicense.with_state(L::LICENSED, licensed: -> { truthy }) { Licensing.check }
      refute result.ok, "licensed? returning #{truthy.inspect} is not exactly true and must block"
    end
  end

  def test_a_raising_licensed_predicate_blocks_safely
    result = TestLicense.with_state(L::LICENSED, licensed: -> { raise 'predicate exploded' }) { Licensing.check }
    refute result.ok
    assert_equal Licensing::UNVERIFIED_MESSAGE, result.message
  end

  # -- licensed? is the sole authority; state only picks the wording ---------

  def test_licensed_true_authorizes_even_when_state_says_not_licensed
    result = TestLicense.with_state(L::NOT_LICENSED, licensed: true) { Licensing.check }
    assert result.ok
  end

  def test_licensed_true_authorizes_even_when_state_is_unknown
    result = TestLicense.with_state(99, licensed: true) { Licensing.check }
    assert result.ok
  end

  def test_licensed_false_blocks_even_when_state_says_licensed_or_trial
    [L::LICENSED, L::TRIAL].each do |state|
      result = TestLicense.with_state(state, licensed: false) { Licensing.check }
      refute result.ok, "state #{state} must never override licensed? == false"
      assert_equal Licensing::UNVERIFIED_MESSAGE, result.message
    end
  end

  def test_a_raising_state_still_blocks_and_never_leaks
    result = TestLicense.with_state(L::NOT_LICENSED, state_raises: RuntimeError.new('SECRET state detail')) do
      Licensing.check
    end
    refute result.ok
    assert_equal Licensing::UNVERIFIED_MESSAGE, result.message
    refute_includes result.message, 'SECRET'
  end

  # -- Messages --------------------------------------------------------------

  def test_the_four_messages_are_distinct_plain_and_name_the_product
    messages = [Licensing::TRIAL_EXPIRED_MESSAGE, Licensing::EXPIRED_MESSAGE,
                Licensing::NOT_LICENSED_MESSAGE, Licensing::UNVERIFIED_MESSAGE]
    assert_equal 4, messages.uniq.length
    messages.each do |message|
      assert_includes message, 'ZB Smart Gizmo Pro'
      assert_includes message, 'Extension' # points at the Warehouse / Extension Manager
    end
    assert_includes Licensing::TRIAL_EXPIRED_MESSAGE, 'trial has ended'
    assert_includes Licensing::EXPIRED_MESSAGE, 'expired'
    assert_includes Licensing::NOT_LICENSED_MESSAGE, 'needs a valid Extension Warehouse license'
    assert_includes Licensing::NOT_LICENSED_MESSAGE,
                    'Purchase a license or start the free trial from the SketchUp Extension Warehouse.',
                    'the listing offers a 14-day trial, so the message points at it'
    assert_includes Licensing::UNVERIFIED_MESSAGE, 'could not check its license'
  end

  def test_no_message_leaks_internal_detail
    scenarios = {
      raising_lookup: { raises: RuntimeError.new('SECRET lookup detail at licensing.rb:60') },
      raising_state: { state: L::NOT_LICENSED, state_raises: RuntimeError.new('SECRET state detail') },
      unknown_state: { state: 99, licensed: false },
      not_licensed: { state: L::NOT_LICENSED },
      expired: { state: L::EXPIRED },
      trial_expired: { state: L::TRIAL_EXPIRED }
    }
    scenarios.each do |name, opts|
      result = TestLicense.with_state(opts[:state], raises: opts[:raises], licensed: opts[:licensed],
                                                    state_raises: opts[:state_raises]) { Licensing.check }
      refute result.ok, name.to_s
      refute_match(/SECRET|#{PRO_UUID}|StandardError|RuntimeError|NOT_LICENSED|TRIAL_EXPIRED|licensed\?|\.rb:\d+|backtrace/i,
                   result.message, "#{name}: the message must be plain user-facing text only")
    end
  end

  # -- silent vs visible forms -----------------------------------------------

  def test_allowed_is_silent_even_when_refused
    refute TestLicense.unlicensed { Licensing.allowed? }
    assert_nil UI.last_messagebox_text, 'the silent form must never show a message'
    assert TestLicense.with_state(L::LICENSED) { Licensing.allowed? }
    assert_nil UI.last_messagebox_text
  end

  def test_authorize_shows_the_state_specific_message_only_when_refused
    {
      L::NOT_LICENSED => Licensing::NOT_LICENSED_MESSAGE,
      L::EXPIRED => Licensing::EXPIRED_MESSAGE,
      L::TRIAL_EXPIRED => Licensing::TRIAL_EXPIRED_MESSAGE
    }.each do |state, message|
      UI.last_messagebox_text = nil
      refute TestLicense.with_state(state) { Licensing.authorize }
      assert_equal message, UI.last_messagebox_text
    end

    UI.last_messagebox_text = nil
    assert TestLicense.with_state(L::LICENSED) { Licensing.authorize }
    assert TestLicense.with_state(L::TRIAL) { Licensing.authorize }
    assert_nil UI.last_messagebox_text, 'an allowed check shows nothing'

    UI.last_messagebox_text = nil
    refute TestLicense.with_state(raises: RuntimeError.new('boom')) { Licensing.authorize }
    assert_equal Licensing::UNVERIFIED_MESSAGE, UI.last_messagebox_text
  end

  # -- Identifier, freshness, retention --------------------------------------

  def test_exactly_one_lookup_per_check_with_the_pro_identifier
    TestLicense.with_state(L::LICENSED) do
      Licensing.check
      assert_equal [PRO_UUID], L.requested_ids
    end
  end

  def test_every_check_requests_a_brand_new_license_object
    TestLicense.with_state(L::LICENSED) do
      Licensing.check
      Licensing.allowed?
      Licensing.authorize
      assert_equal [PRO_UUID] * 3, L.requested_ids
      assert_equal 3, L.issued.length
      assert_equal 3, L.issued.map(&:object_id).uniq.length, 'each check must receive its own license object'
    end
  end

  def test_the_license_state_is_reread_on_every_check
    L.reset!
    assert Licensing.check.ok
    L.state = L::NOT_LICENSED
    refute Licensing.check.ok, 'a license that lapsed since the last check must be refused'
    L.state = L::TRIAL
    assert Licensing.check.ok, 'a license that returned since the last check must be honored'
    assert_equal 3, L.requested_ids.length
  end

  def test_nothing_is_retained_between_checks
    TestLicense.with_state(L::LICENSED) { Licensing.check }
    assert_empty Licensing.instance_variables, 'the module must hold no license state'
    assert_empty Licensing.class_variables
    Licensing.constants.each do |name|
      value = Licensing.const_get(name)
      refute_kind_of Sketchup::Licensing::ExtensionLicense, value
      refute_kind_of Licensing::Result, value
    end
  end

  # -- Console silence and the absence of any exemption ----------------------

  def test_the_ruby_console_stays_quiet_in_every_license_state
    scenarios = [
      [L::LICENSED, {}], [L::TRIAL, {}], [L::NOT_LICENSED, {}], [L::EXPIRED, {}], [L::TRIAL_EXPIRED, {}],
      [99, { licensed: false }], [:nil_license, {}], [:object_without_licensed, {}],
      [nil, { raises: RuntimeError.new('boom') }],
      [L::NOT_LICENSED, { state_raises: RuntimeError.new('boom') }]
    ]
    out, err = capture_io do
      scenarios.each do |state, opts|
        TestLicense.with_state(state, **opts) do
          Licensing.check
          Licensing.allowed?
          Licensing.authorize
        end
      end
    end
    assert_empty out
    assert_empty err, 'DEBUG_MODE is off, so no licensing diagnostics may reach the console'
  end

  def test_debug_mode_never_exempts_licensing
    original = Zbellbound::SmartGizmoPro::DEBUG_MODE
    Zbellbound::SmartGizmoPro.send(:remove_const, :DEBUG_MODE)
    Zbellbound::SmartGizmoPro.const_set(:DEBUG_MODE, true)
    result = nil
    capture_io { result = TestLicense.unlicensed { Licensing.check } }
    refute result.ok, 'turning DEBUG_MODE on must not grant access'
    refute_nil result.message
  ensure
    Zbellbound::SmartGizmoPro.send(:remove_const, :DEBUG_MODE)
    Zbellbound::SmartGizmoPro.const_set(:DEBUG_MODE, original)
  end

  # -- Source guarantees -----------------------------------------------------

  def test_the_pro_uuid_is_an_inline_local_literal_passed_to_get_extension_license
    matches = licensing_source.scan(/get_extension_license\('#{Regexp.escape(PRO_UUID)}'\)/)
    assert_equal 1, matches.length, 'the Pro identifier must be passed inline, exactly once'
    refute_match(/^\s*[A-Z_]*(ID|UUID|GUID)[A-Z_]*\s*=\s*'#{Regexp.escape(PRO_UUID)}'/, licensing_source,
                 'RuboCop-SketchUp refuses a constant identifier')
  end

  def test_the_pro_uuid_lives_only_in_the_licensing_file
    holders = shipped_ruby_files.select { |path| File.read(path).include?(PRO_UUID) }
    assert_equal [LICENSING_PATH], holders.map { |path| File.expand_path(path) }
  end

  def test_no_other_zbellbound_listing_identifier_is_used
    shipped_ruby_files.each do |path|
      content = File.read(path)
      OTHER_LISTING_UUIDS.each do |other|
        refute_includes content, other, "#{File.basename(path)} must not carry another product's listing id"
      end
    end
  end

  def test_no_extension_uuid_other_than_the_pro_one_appears_in_shipped_ruby
    shipped_ruby_files.each do |path|
      found = File.read(path).scan(/\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b/i)
      assert_empty found - [PRO_UUID], "#{File.basename(path)} carries an unexpected identifier"
    end
  end

  def test_licensing_uses_no_external_service_local_counter_or_stored_preference
    code = licensing_source.lines.reject { |line| line.strip.start_with?('#') }.join
    refute_match(/Net::HTTP|open-uri|Socket|URI\.|HtmlDialog|Thread|Timeout|Digest|OpenSSL|Base64/, code)
    refute_match(/File\.(read|write|open|exist|binread|readlines)|IO\.|Dir\.|ENV\b|`|system\(|exec\(/, code)
    refute_match(/read_default|write_default|attribute_dictionar|set_attribute|get_attribute/, code,
                 'no trial counter or local preference may sit behind the license')
    refute_match(/\bmachine|fingerprint|hostname|MAC\b|serial|Etc\./i, code)
    refute_match(/\brequire\b|require_relative|\bload\b|\beval\b|instance_eval|class_eval/, code)
  end

  def test_debug_mode_appears_only_as_a_logging_guard_in_the_licensing_code
    code = licensing_source.lines.reject { |line| line.strip.start_with?('#') }
    uses = code.grep(/DEBUG_MODE/)
    assert_equal 1, uses.length
    assert_match(/warn\(.*\) if DEBUG_MODE/, uses.first)
  end

  def test_the_licensing_file_is_loaded_extensionless_before_observer_and_overlay
    source = File.read(LOADER_PATH)
    requires = source.scan(/Sketchup\.require\('([^']+)'\)/).flatten
    assert_includes requires, 'zb_smart_gizmo_pro/licensing'
    assert_operator requires.index('zb_smart_gizmo_pro/licensing'), :<, requires.index('zb_smart_gizmo_pro/observer')
    assert_operator requires.index('zb_smart_gizmo_pro/licensing'), :<, requires.index('zb_smart_gizmo_pro/overlay')
    requires.each { |path| refute_match(/\.(rb|rbe|rbs)\z/, path, 'Sketchup.require paths must be extensionless') }
    refute_match(/require_relative|^\s*load\b|[^.]\brequire\s+['"]/, File.read(LICENSING_PATH))
  end

  def test_the_shipped_file_set_is_exactly_the_runtime_files_plus_licensing
    expected = %w[
      zb_smart_gizmo_pro/Resources/icon.pdf
      zb_smart_gizmo_pro/Resources/icon.png
      zb_smart_gizmo_pro/Resources/icon.svg
      zb_smart_gizmo_pro/gizmo.rb
      zb_smart_gizmo_pro/licensing.rb
      zb_smart_gizmo_pro/loader.rb
      zb_smart_gizmo_pro/observer.rb
      zb_smart_gizmo_pro/overlay.rb
      zb_smart_gizmo_pro/utils.rb
    ]
    actual = Dir.glob(File.join(ROOT, 'zb_smart_gizmo_pro', '**', '*')).select { |p| File.file?(p) }
                .map { |p| p.sub("#{ROOT}/", '') }.sort
    assert_equal expected, actual
    assert File.file?(File.join(ROOT, 'zb_smart_gizmo_pro.rb'))
  end

  # -- No license file or signature anywhere it could be committed/packaged --

  def tracked_files
    output, status = Open3.capture2('git', 'ls-files', chdir: ROOT)
    skip 'git is not available here' unless status.success?
    output.split("\n").reject(&:empty?)
  rescue Errno::ENOENT
    skip 'git is not available here'
  end

  def test_no_lic_file_is_tracked
    lic = tracked_files.select { |path| path =~ /\.lic\z/i }
    assert_empty lic, 'a Warehouse license record must never be committed'
  end

  def test_lic_files_are_git_ignored
    ignore = File.read(File.join(ROOT, '.gitignore'))
    assert_match(/^\*\.lic\s*$/, ignore, '*.lic must be excluded from Git')
    assert_match(/^EW\.lic\s*$/, ignore)
  end

  def test_no_license_record_or_signature_is_present_in_any_tracked_text_file
    tracked_files.each do |path|
      next if path =~ /\.(png|pdf|svg)\z/i

      content = File.read(File.join(ROOT, path), encoding: 'UTF-8', invalid: :replace, undef: :replace)
      refute_match(/^\s*LICENSE\s+trmbldg\b/, content, "#{path} must not contain a Warehouse license record")
      refute_match(/\bsig\s*=\s*"/, content, "#{path} must not contain any license signature, not even a prefix")
      refute_match(/\bcustomer\s*=\s*\S/, content, "#{path} must not contain a license record's customer value")
    end
  end

  def test_the_package_inputs_contain_no_lic_entry
    inputs = Dir.glob(File.join(ROOT, 'zb_smart_gizmo_pro', '**', '*')) + [File.join(ROOT, 'zb_smart_gizmo_pro.rb')]
    assert_empty inputs.select { |path| path =~ /\.lic\z/i }
  end
end
