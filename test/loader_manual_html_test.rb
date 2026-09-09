require 'minitest/autorun'

# Coverage for the ACTUAL user-facing manual: the embedded HTML string
# Zbellbound::SmartGizmoPro.manual_html (zb_smart_gizmo_pro/loader.rb) renders into a
# UI::HtmlDialog from Extensions > ZB Smart Gizmo Pro > Settings > Manual.
# This is NOT Manual.md -- Manual.md is a repo-only reference, never
# read, required, or packaged by any shipped file (see the 9-entry RBZ
# contents); manual_html is the only thing users actually see.
#
# loader.rb can't be loaded wholesale in this test environment -- its
# top level calls real SketchUp menu/extension-registration APIs
# (UI.menu, Sketchup.register_extension, GizmoObserver.new, ...) that
# the stubs in test/support/sketchup_stubs.rb don't and shouldn't
# model, since that machinery is unrelated to what this file checks.
# Instead, manual_html's own source is extracted verbatim (by exact
# indentation, not hand-copied) and defined on a minimal stand-in module
# that only needs PLUGIN_NAME -- the one thing the heredoc interpolates.
# This tests the REAL production string: any future edit to manual_html
# automatically flows into what these assertions see.
class LoaderManualHtmlTest < Minitest::Test
  LOADER_PATH = File.expand_path('../zb_smart_gizmo_pro/loader.rb', __dir__)

  def manual_html
    return @manual_html if defined?(@manual_html)

    source = File.read(LOADER_PATH)
    match = /^ {6}def self\.manual_html\r?\n(.*?)^ {6}end\r?\n/m.match(source)
    raise 'manual_html method not found in loader.rb -- extraction regex or indentation changed' unless match

    # PLUGIN_NAME and the method must be defined in the SAME class_eval
    # string so the method body's constant lookup (resolved against its
    # lexical scope at definition time) can see PLUGIN_NAME on `host`.
    host = Module.new
    host.class_eval(<<~RUBY)
      PLUGIN_NAME = 'ZB Smart Gizmo Pro'

      def self.manual_html
      #{match[1]}end
    RUBY
    @manual_html = host.manual_html
  end

  def test_manual_html_is_well_formed_and_self_contained
    html = manual_html

    assert_includes html, '<!doctype html>'
    assert_includes html, '<title>ZB Smart Gizmo Pro Manual</title>'
    assert_includes html, '<h1>ZB Smart Gizmo Pro Manual</h1>'
    refute_match(/<link\b/i, html, 'must not depend on an external stylesheet')
    refute_match(%r{<script\b}i, html, 'must not add an external-dependency script')
    refute_match(%r{https?://}, html, 'must not reference a website URL')
    refute_match(/\brepo(sitory)?\b|\bgithub\b|\bbranch\b|\bcommit\b/i, html,
      'must not mention development/repository/release-workflow details')

    # Balanced tags -- a cheap structural sanity check that the large
    # heredoc wasn't left with a dangling <div>/<ul>/<li>.
    %w[div ul li h2 h3].each do |tag|
      opens = html.scan(/<#{tag}(?:\s[^>]*)?>/).length
      closes = html.scan(%r{</#{tag}>}).length
      assert_equal opens, closes, "unbalanced <#{tag}> tags"
    end
  end

  # -- Move / Copy Array ------------------------------------------------

  def test_documents_move_copy_array
    html = manual_html

    assert_match(/Copy Array/i, html)
    assert_match(/choose.*<code>Copy<\/code>/i, html)
    assert_includes html, '<code>3</code>'
    assert_match(/Number of Copies.*opens blank|opens blank/i, html)
    assert_match(/4 objects total|plus the unchanged original/i, html)
    assert_match(/Groups and components only/i, html)
    assert_match(/One Undo removes the whole array/i, html)
  end

  # -- Ctrl-drag internal array ------------------------------------------

  def test_documents_ctrl_drag_internal_array
    html = manual_html

    assert_match(/Ctrl-Drag Copy/i, html)
    assert_match(/Hold <code>Ctrl<\/code>/i, html)
    assert_includes html, '<code>/3</code>'
    assert_includes html, '<code>3/</code>'
    assert_match(/endpoint counts as one of the 3 copies/i, html)
    assert_match(/A different <code>\/N<\/code> replaces the array/i, html)
    assert_match(%r{3000mm.*<code>/3</code>.*1000.*2000.*3000mm}m, html,
      'must show the compact 3000mm drag / /3 -> 1000/2000/3000mm example')
  end

  # -- Ctrl-drag external array ------------------------------------------

  def test_documents_ctrl_drag_external_array
    html = manual_html

    assert_includes html, '<code>x3</code>'
    assert_includes html, '<code>3x</code>'
    assert_includes html, '<code>X3</code>'
    assert_includes html, '<code>3X</code>'
    assert_match(/endpoint counts as copy 1/i, html)
    assert_match(/switching between <code>\/N<\/code> and <code>xN<\/code> replaces it/i, html)
    assert_match(%r{1000mm.*<code>x3</code>.*1000.*2000.*3000mm}m, html,
      'must show the compact 1000mm drag / x3 -> 1000/2000/3000mm example')
  end

  def test_documents_shared_ctrl_drag_array_rules
    html = manual_html

    assert_match(/groups and components only/i, html)
    assert_match(/Esc/i, html)
    assert_match(/One Undo removes the endpoint and every generated copy/i, html)
  end

  # -- Pivot --------------------------------------------------------------

  def test_documents_pivot
    html = manual_html

    assert_match(/<h2>Pivot<\/h2>/, html)
    assert_match(/Reset Pivot To Selection Center/, html)
    assert_match(/Set Pivot To Model Axes Origin/, html)
    assert_match(/Set Pivot To Object Origin/, html)
    assert_match(/Right-click while hovering the gizmo/i, html)
  end

  # -- Arrow-key rotate -----------------------------------------------------

  def test_documents_arrow_key_rotate_mapping
    html = manual_html

    assert_match(/Left.*-90/m, html)
    assert_match(/Right.*\+90/m, html)
    assert_match(/Up.*180/m, html)
    assert_match(/Down.*-180/m, html)
    assert_match(/Fixed Rotate Axis.*defaults to Z/i, html)
  end

  # -- Preferences: rotate snap increment -----------------------------------

  def test_documents_rotate_snap_increment_preference
    html = manual_html

    assert_match(/Rotate snap increment/i, html)
    assert_match(/default.*5/i, html)
  end

  # -- Scale: leading sign clarification ------------------------------------

  def test_documents_scale_leading_sign_behavior
    html = manual_html

    assert_match(/leading.*<code>\+<\/code>.*<code>-<\/code>.*currently shown value/i, html)
    assert_includes html, '<code>600mm+100mm</code>'
    assert_includes html, '<code>24in+2in</code>'
    assert_includes html, '<code>+100</code>'
    assert_includes html, '<code>+100+6+5</code>'
  end

  # -- Scale: dimension display and division --------------------------------

  def test_documents_scale_dimension_display_and_division
    html = manual_html

    assert_match(/resulting real-world dimension/i, html)
    assert_includes html, '<code>50.8</code>'
    refute_includes html, '<code>50.8mm</code>', 'the displayed dimension example must omit the unit suffix'
    assert_includes html, '<code>/2</code>'
    assert_match(/divide the shown dimension in half/i, html)
    assert_match(/unit suffix omitted/i, html)
    assert_includes html, '<code>600mm</code>', 'typed Scale expressions may still use explicit units'
    assert_match(/Not the Ctrl-drag copy array's <code>\/N<\/code>/i, html,
      'must distinguish Scale division from the Ctrl-drag internal copy-array /N syntax'
    )
  end

  # -- Scale: multiplication --------------------------------------------------

  def test_documents_scale_multiplication
    html = manual_html

    assert_includes html, '<code>x2</code>'
    assert_includes html, '<code>X2</code>'
    assert_includes html, '<code>x1.5</code>'
    assert_match(/double the shown dimension/i, html)
    assert_match(/Ctrl-drag Move.*<code>x2<\/code>.*external copy array/i, html,
      'must distinguish Scale multiplication from the Ctrl-drag external copy-array xN syntax'
    )
  end
end
