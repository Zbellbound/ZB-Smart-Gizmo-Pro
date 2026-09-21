require 'minitest/autorun'
require_relative 'support/sketchup_stubs'

# Coverage for the About dialog's installed-version display
# (Zbellbound::SmartGizmoPro.open_about, zb_smart_gizmo_pro/loader.rb), opened from
# Extensions > ZB Smart Gizmo Pro > Settings > About -- the same single
# menu item/dialog as before this feature, just showing PLUGIN_VERSION
# on its first line now.
#
# loader.rb can't be loaded wholesale in this test environment (real
# menu/extension-registration side effects -- see loader_manual_html_
# test.rb's comment), so open_about's own source is extracted verbatim
# (by exact indentation, not hand-copied) and class_eval'd onto a
# minimal stand-in module exposing PLUGIN_NAME/PLUGIN_VERSION -- the
# same technique LoaderManualHtmlTest#manual_html and Preferences
# NamespaceTest#preferences_module already use. This tests the REAL
# production method body: any future edit to open_about automatically
# flows into what these assertions see.
class AboutVersionDisplayTest < Minitest::Test
  LOADER_PATH = File.expand_path('../zb_smart_gizmo_pro/loader.rb', __dir__)

  def loader_source
    @loader_source ||= File.read(LOADER_PATH)
  end

  def open_about_source
    match = /^ {6}def self\.open_about\r?\n(.*?)^ {6}end\r?\n/m.match(loader_source)
    raise 'open_about method not found in loader.rb -- extraction regex or indentation changed' unless match

    match[1]
  end

  # Builds a fresh stand-in module with the given PLUGIN_NAME/
  # PLUGIN_VERSION and the REAL open_about body class_eval'd onto it, so
  # each test can exercise a different "installed version" without any
  # of them leaking into each other.
  def about_module(name: 'ZB Smart Gizmo Pro', version: '1.5.4')
    host = Module.new
    host.class_eval(<<~RUBY)
      PLUGIN_NAME = #{name.inspect}
      PLUGIN_VERSION = #{version.inspect}

      def self.open_about
      #{open_about_source}end
    RUBY
    host
  end

  def setup
    UI.last_messagebox_text = nil
  end

  # -- 1/2. About uses PLUGIN_NAME and PLUGIN_VERSION -----------------------

  def test_about_uses_plugin_name_and_plugin_version
    about_module.open_about

    assert_includes UI.last_messagebox_text, 'ZB Smart Gizmo Pro'
    assert_includes UI.last_messagebox_text, '1.5.4'
    assert_match(/\AZB Smart Gizmo Pro 1\.5\.4\b/, UI.last_messagebox_text,
      'the version must appear on the first line, right after PLUGIN_NAME')
  end

  # A DEV build only ever changes PLUGIN_VERSION (never PLUGIN_NAME) --
  # confirms the exact "ZB Smart Gizmo Pro 1.5.4 DEV" wording a DEV package
  # produces, built purely from the two constants.
  def test_about_shows_a_dev_labelled_version_when_plugin_version_carries_one
    about_module(version: '1.5.4 DEV').open_about

    assert_equal "ZB Smart Gizmo Pro 1.5.4 DEV\n\nDeveloper: Peter Zbel\nWebsite: www.zbellbound.com",
      UI.last_messagebox_text
  end

  def test_about_shows_the_plain_production_version_with_no_dev_wording
    about_module(version: '1.5.4').open_about

    assert_equal "ZB Smart Gizmo Pro 1.5.4\n\nDeveloper: Peter Zbel\nWebsite: www.zbellbound.com",
      UI.last_messagebox_text
    refute_match(/DEV/, UI.last_messagebox_text)
  end

  # -- 3. No version number is hardcoded in loader.rb ------------------------

  def test_open_about_body_contains_no_hardcoded_version_literal
    refute_match(/\d+\.\d+\.\d+/, open_about_source,
      'open_about must build its text from PLUGIN_VERSION, never a literal version number')
    assert_includes open_about_source, '#{PLUGIN_VERSION}',
      'open_about must interpolate PLUGIN_VERSION, not a hardcoded string'
  end

  def test_no_plugin_version_assignment_exists_in_loader_rb
    refute_match(/PLUGIN_VERSION\s*=\s*['"]/, loader_source,
      'PLUGIN_VERSION must only ever be assigned in zb_smart_gizmo_pro.rb, never in loader.rb')
  end

  # -- 4. PLUGIN_NAME and PLUGIN_ID remain unchanged -------------------------

  def test_plugin_name_and_plugin_id_are_unchanged
    source = File.read(File.expand_path('../zb_smart_gizmo_pro.rb', __dir__))

    assert_match(/^\s*PLUGIN_NAME\s*=\s*'ZB Smart Gizmo Pro'\.freeze\s*$/, source)
    assert_match(/^\s*PLUGIN_ID\s*=\s*'zb_smart_gizmo_pro'\.freeze\s*$/, source)
  end

  # -- 5. Persisted preferences remain under the existing section -----------
  # (Full 13-key coverage already lives in preferences_namespace_test.rb;
  # this pins that open_about's change didn't touch that mechanism at all.)

  def test_read_default_and_write_default_still_use_plugin_name_exclusively
    calls = loader_source.scan(/Sketchup\.(?:read|write)_default\(([^,]+),/)
    refute_empty calls
    calls.each do |(section_arg)|
      assert_equal 'PLUGIN_NAME', section_arg.strip
    end
  end

  # -- 6. About shows the correct version after a version change ------------

  def test_about_text_tracks_a_changed_plugin_version
    about_module(version: '1.5.3').open_about
    assert_includes UI.last_messagebox_text, 'ZB Smart Gizmo Pro 1.5.3'

    UI.last_messagebox_text = nil
    about_module(version: '1.5.4').open_about
    assert_includes UI.last_messagebox_text, 'ZB Smart Gizmo Pro 1.5.4'
    refute_includes UI.last_messagebox_text, '1.5.3'
  end

  # -- 7. The production version --------------------------------------------

  def test_the_production_version_is_exactly_1_5_4_with_no_build_label
    source = File.read(File.expand_path('../zb_smart_gizmo_pro.rb', __dir__))
    assigned = source.scan(/^\s*PLUGIN_VERSION\s*=\s*'([^']+)'\.freeze\s*$/).flatten

    assert_equal ['1.5.4'], assigned, 'PLUGIN_VERSION is assigned exactly once, to exactly 1.5.4'
    assert_match(/\A\d+\.\d+\.\d+\z/, assigned.first, 'a production version carries no DEV/RC label')
    assert_operator Gem::Version.new(assigned.first), :>, Gem::Version.new('1.5.3')
    assert_match(/extension\.version\s*=\s*PLUGIN_VERSION/, source, 'the extension registers this exact version')
  end

  # -- Preserves Developer/Website info; single dialog, no functional change -

  def test_developer_and_website_lines_are_preserved
    about_module.open_about

    assert_includes UI.last_messagebox_text, 'Developer: Peter Zbel'
    assert_includes UI.last_messagebox_text, 'Website: www.zbellbound.com'
  end

  def test_open_about_is_a_single_ui_messagebox_call
    assert_equal 1, open_about_source.scan(/UI\.messagebox/).length,
      'must remain exactly one dialog, not an additional command/dialog'
  end
end
