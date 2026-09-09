require 'minitest/autorun'
require_relative 'support/sketchup_stubs'

# Guards the exact defect the R1-R3 DEV packages had: every one of this
# extension's persisted settings is stored via Sketchup.read_default/
# write_default(PLUGIN_NAME, key, default) -- PLUGIN_NAME is the
# storage SECTION, not PLUGIN_ID. A DEV build that changes PLUGIN_NAME
# to make itself "unmistakable" in Extension Manager/About silently
# starts reading/writing a DIFFERENT preferences section than
# production, so installing it "over" v1.5.1 loses every existing
# setting instead of reading it. R4 fixes this by keeping PLUGIN_NAME
# ('ZB Smart Gizmo Pro') and PLUGIN_ID ('zb_smart_gizmo_pro') untouched even in
# the staged DEV copy, identifying the DEV build only via PLUGIN_VERSION
# and the About dialog text (both staging-only patches, never committed).
#
# Two layers of proof:
# 1. Static source audit (this file, section "-- Static source audit
#    --"): reads the ACTUAL tracked zb_smart_gizmo_pro.rb/loader.rb source
#    directly off disk and asserts, by exact regex, that every single
#    read_default/write_default call site uses the literal PLUGIN_NAME
#    constant as its section argument -- not a hardcoded string, not
#    PLUGIN_ID, not anything else -- and that PLUGIN_NAME/PLUGIN_ID
#    themselves are exactly 'ZB Smart Gizmo Pro'/'zb_smart_gizmo_pro'. This is
#    what actually gets frozen into any RBZ built from this source, DEV
#    or production.
# 2. Behavioral persistence proof (section "-- Behavioral persistence
#    --"): loader.rb can't be loaded wholesale in this test environment
#    (see loader_manual_html_test.rb's comment -- real menu/extension-
#    registration side effects), so the REAL preference getter/setter
#    method bodies are extracted verbatim from loader.rb (same
#    technique as LoaderManualHtmlTest#manual_html) and class_eval'd
#    onto a minimal stand-in module exposing PLUGIN_NAME. Combined with
#    Sketchup.read_default/write_default now being a real in-memory
#    [section][key] registry (test/support/sketchup_stubs.rb -- upgraded
#    from an inert always-returns-default stub specifically to make
#    this provable), this exercises the REAL production getter/setter
#    logic against pre-populated "already installed" values, proving
#    the DEV build actually reads them back rather than merely
#    asserting on source text.
class PreferencesNamespaceTest < Minitest::Test
  ZB_SMART_GIZMO_PRO_RB_PATH = File.expand_path('../zb_smart_gizmo_pro.rb', __dir__)
  LOADER_PATH = File.expand_path('../zb_smart_gizmo_pro/loader.rb', __dir__)

  ALL_PREFERENCE_KEYS = %w[
    orientation
    gizmo_size
    pivot_size
    scale_input_unit
    smart_scale_enabled
    rotate_arrow_shortcuts_enabled
    rotate_arrow_remember_axis
    rotate_arrow_axis
    rotate_snap_increment
    rotate_left_arrow_step
    rotate_right_arrow_step
    rotate_up_arrow_step
    rotate_down_arrow_step
  ].freeze

  def zb_smart_gizmo_pro_rb_source
    @zb_smart_gizmo_pro_rb_source ||= File.read(ZB_SMART_GIZMO_PRO_RB_PATH)
  end

  def loader_source
    @loader_source ||= File.read(LOADER_PATH)
  end

  # -- Static source audit -------------------------------------------------

  def test_plugin_name_and_plugin_id_are_the_exact_required_literals
    assert_match(/^\s*PLUGIN_NAME\s*=\s*'ZB Smart Gizmo Pro'\.freeze\s*$/, zb_smart_gizmo_pro_rb_source,
      "PLUGIN_NAME must be exactly 'ZB Smart Gizmo Pro' in tracked source -- it is the preferences section")
    assert_match(/^\s*PLUGIN_ID\s*=\s*'zb_smart_gizmo_pro'\.freeze\s*$/, zb_smart_gizmo_pro_rb_source,
      "PLUGIN_ID must be exactly 'zb_smart_gizmo_pro' in tracked source -- it is the install identity")
  end

  def test_every_read_default_call_uses_the_plugin_name_section
    calls = loader_source.scan(/Sketchup\.read_default\(([^,]+),/)
    refute_empty calls, 'expected to find Sketchup.read_default calls in loader.rb'
    calls.each do |(section_arg)|
      assert_equal 'PLUGIN_NAME', section_arg.strip,
        "Sketchup.read_default must be called with the PLUGIN_NAME constant, found #{section_arg.strip.inspect}"
    end
  end

  def test_every_write_default_call_uses_the_plugin_name_section
    calls = loader_source.scan(/Sketchup\.write_default\(([^,]+),/)
    refute_empty calls, 'expected to find Sketchup.write_default calls in loader.rb'
    calls.each do |(section_arg)|
      assert_equal 'PLUGIN_NAME', section_arg.strip,
        "Sketchup.write_default must be called with the PLUGIN_NAME constant, found #{section_arg.strip.inspect}"
    end
  end

  def test_every_known_preference_key_is_both_read_and_written_under_plugin_name
    ALL_PREFERENCE_KEYS.each do |key|
      assert_match(/Sketchup\.read_default\(PLUGIN_NAME,\s*'#{Regexp.escape(key)}'/, loader_source,
        "#{key} must be read via Sketchup.read_default(PLUGIN_NAME, '#{key}', ...)")
      assert_match(/Sketchup\.write_default\(PLUGIN_NAME,\s*'#{Regexp.escape(key)}'/, loader_source,
        "#{key} must be written via Sketchup.write_default(PLUGIN_NAME, '#{key}', ...)")
    end
  end

  def test_no_read_default_or_write_default_call_uses_a_dev_label_or_plugin_id
    refute_match(/Sketchup\.(?:read|write)_default\(PLUGIN_ID,/, loader_source,
      'no preference call may use PLUGIN_ID as the section')
    refute_match(/Sketchup\.(?:read|write)_default\(['"]/, loader_source,
      'no preference call may use a hardcoded string literal (e.g. a DEV label) as the section')
  end

  # -- Behavioral persistence -----------------------------------------------
  #
  # Extracts the real preference getter/setter method bodies from
  # loader.rb (constants block + the gizmo_orientation..parse_boolean_
  # setting method span, verbatim, by exact indentation) and class_eval's
  # them onto a fresh module exposing PLUGIN_NAME -- so any future edit
  # to these methods automatically flows into what these assertions see,
  # the same guarantee LoaderManualHtmlTest already relies on for
  # manual_html.

  def preferences_module
    return @preferences_module if defined?(@preferences_module)

    const_match = /^( {4}OVERLAY_ID.*? {4}LOCAL_ORIENTATION = 1\r?\n)/m.match(loader_source)
    raise 'preference constants block not found -- loader.rb structure changed' unless const_match

    method_match = /^( {6}def self\.gizmo_orientation.*? {6}end\r?\n)\r?\n {6}def self\.manual_html/m.match(loader_source)
    raise 'preference getter/setter methods not found -- loader.rb structure changed' unless method_match

    host = Module.new
    host.class_eval(<<~RUBY)
      PLUGIN_NAME = 'ZB Smart Gizmo Pro'

      #{const_match[1]}

      class << self
        #{method_match[1].gsub(/^ {6}def self\./, 'def ').gsub(/^ {6}end$/, 'end')}
      end
    RUBY
    @preferences_module = host
  end

  def setup
    Sketchup.reset_defaults_registry!
  end

  def test_clean_install_reads_the_documented_defaults
    prefs = preferences_module

    assert_equal 0, prefs.gizmo_orientation, 'orientation'
    assert_equal 80, prefs.gizmo_size, 'gizmo_size'
    assert_equal 6, prefs.pivot_size, 'pivot_size'
    assert_equal 'mm', prefs.scale_input_unit, 'scale_input_unit'
    assert prefs.smart_scale_enabled?, 'smart_scale_enabled'
    assert prefs.rotate_arrow_shortcuts_enabled?, 'rotate_arrow_shortcuts_enabled'
    assert prefs.rotate_arrow_remember_axis?, 'rotate_arrow_remember_axis'
    assert_equal 'z', prefs.rotate_arrow_axis, 'rotate_arrow_axis'
    assert_in_delta 5.0, prefs.rotate_snap_increment, 1e-9, 'rotate_snap_increment'
    assert_in_delta(-90.0, prefs.rotate_left_arrow_step, 1e-9, 'rotate_left_arrow_step')
    assert_in_delta 90.0, prefs.rotate_right_arrow_step, 1e-9, 'rotate_right_arrow_step'
    assert_in_delta 180.0, prefs.rotate_up_arrow_step, 1e-9, 'rotate_up_arrow_step'
    assert_in_delta(-180.0, prefs.rotate_down_arrow_step, 1e-9, 'rotate_down_arrow_step')
  end

  # Simulates "v1.5.1 is already installed and the user customized every
  # setting" by writing directly into the SAME section a DEV build must
  # also use ('ZB Smart Gizmo Pro'), then confirms the real getter methods
  # -- unmodified production code -- read every one of those customized
  # values back, not the documented defaults.
  def test_installing_the_dev_build_over_v151_reads_every_customized_value
    Sketchup.write_default('ZB Smart Gizmo Pro', 'orientation', 1)
    Sketchup.write_default('ZB Smart Gizmo Pro', 'gizmo_size', 220)
    Sketchup.write_default('ZB Smart Gizmo Pro', 'pivot_size', 12)
    Sketchup.write_default('ZB Smart Gizmo Pro', 'scale_input_unit', 'in')
    # Written as false (the opposite of the current default, true) so this
    # assertion can only pass by actually reading the saved value back --
    # not by silently falling through to the default.
    Sketchup.write_default('ZB Smart Gizmo Pro', 'smart_scale_enabled', false)
    Sketchup.write_default('ZB Smart Gizmo Pro', 'rotate_arrow_shortcuts_enabled', false)
    Sketchup.write_default('ZB Smart Gizmo Pro', 'rotate_arrow_remember_axis', false)
    Sketchup.write_default('ZB Smart Gizmo Pro', 'rotate_arrow_axis', 'x')
    Sketchup.write_default('ZB Smart Gizmo Pro', 'rotate_snap_increment', 15.0)
    Sketchup.write_default('ZB Smart Gizmo Pro', 'rotate_left_arrow_step', -45.0)
    Sketchup.write_default('ZB Smart Gizmo Pro', 'rotate_right_arrow_step', 45.0)
    Sketchup.write_default('ZB Smart Gizmo Pro', 'rotate_up_arrow_step', 90.0)
    Sketchup.write_default('ZB Smart Gizmo Pro', 'rotate_down_arrow_step', -90.0)

    prefs = preferences_module

    assert_equal 1, prefs.gizmo_orientation, 'orientation must survive the upgrade'
    assert_equal 220, prefs.gizmo_size, 'gizmo size must survive the upgrade'
    assert_equal 12, prefs.pivot_size, 'pivot size must survive the upgrade'
    assert_equal 'in', prefs.scale_input_unit, 'Scale Input Unit must survive the upgrade'
    refute prefs.smart_scale_enabled?, 'Smart Scale enabled state must survive the upgrade'
    refute prefs.rotate_arrow_shortcuts_enabled?, 'rotation shortcut setting must survive the upgrade'
    refute prefs.rotate_arrow_remember_axis?, 'remembered-axis setting must survive the upgrade'
    assert_equal 'x', prefs.rotate_arrow_axis, 'remembered rotation axis must survive the upgrade'
    assert_in_delta 15.0, prefs.rotate_snap_increment, 1e-9, 'rotation snap increment must survive the upgrade'
    assert_in_delta(-45.0, prefs.rotate_left_arrow_step, 1e-9, 'left arrow-key step must survive the upgrade')
    assert_in_delta 45.0, prefs.rotate_right_arrow_step, 1e-9, 'right arrow-key step must survive the upgrade'
    assert_in_delta 90.0, prefs.rotate_up_arrow_step, 1e-9, 'up arrow-key step must survive the upgrade'
    assert_in_delta(-90.0, prefs.rotate_down_arrow_step, 1e-9, 'down arrow-key step must survive the upgrade')
  end

  # A DEV build that (incorrectly) used its own label as the section
  # would NOT see the same values -- pinning the negative case so this
  # suite would have caught the actual R1-R3 defect.
  def test_a_different_section_name_would_not_see_the_same_values
    Sketchup.write_default('ZB Smart Gizmo Pro', 'gizmo_size', 220)

    wrong_section_value = Sketchup.read_default('ZB Smart Gizmo Pro 1.5.2 DEV – Scale Multiply R3', 'gizmo_size', 150)
    assert_equal 150, wrong_section_value,
      'a build reading a DEV-labelled section would incorrectly fall back to the default instead of the customized 220'
  end

  # Merely calling a getter must never itself persist anything -- reading
  # a preference is not the same as the user changing it, and a DEV
  # build simply starting up (constructing preference dialogs, etc.)
  # must not silently rewrite anything to its default.
  def test_reading_a_preference_does_not_rewrite_it
    Sketchup.write_default('ZB Smart Gizmo Pro', 'gizmo_size', 220)
    prefs = preferences_module

    ALL_PREFERENCE_KEYS.each do |key|
      getter = key.end_with?('enabled') || %w[smart_scale_enabled rotate_arrow_shortcuts_enabled rotate_arrow_remember_axis].include?(key) ? "#{key}?" : key
      getter = 'gizmo_orientation' if key == 'orientation'
      prefs.public_send(getter)
    end

    assert_equal 220, Sketchup.read_default('ZB Smart Gizmo Pro', 'gizmo_size', 999),
      'reading every preference getter must not have rewritten gizmo_size'
    assert_empty Sketchup.default_registry.fetch('ZB Smart Gizmo Pro', {}).keys - %w[gizmo_size],
      'no getter call may write a value that was never explicitly set'
  end
end
