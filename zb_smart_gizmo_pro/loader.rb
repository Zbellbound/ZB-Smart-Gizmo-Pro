# Copyright Peter Zbel - Zbellbound.com
# ZB Smart Gizmo Pro

module Zbellbound
  module SmartGizmoPro
    OVERLAY_ID = 'zbellbound.smart_gizmo_pro.overlay'.freeze
    OVERLAY_DESCRIPTION = 'Move, rotate, and scale selections from a viewport gizmo.'.freeze
    DEFAULT_GIZMO_SIZE = 80
    DEFAULT_PIVOT_SIZE = 6
    DEFAULT_SCALE_INPUT_UNIT = 'mm'.freeze
    DEFAULT_SMART_SCALE_ENABLED = true
    DEFAULT_ROTATE_ARROW_SHORTCUTS_ENABLED = true
    DEFAULT_ROTATE_ARROW_REMEMBER_AXIS = true
    DEFAULT_ROTATE_ARROW_AXIS = 'z'.freeze
    DEFAULT_ROTATE_SNAP_INCREMENT = 5.0
    DEFAULT_ROTATE_LEFT_ARROW_STEP = -90.0
    DEFAULT_ROTATE_RIGHT_ARROW_STEP = 90.0
    DEFAULT_ROTATE_UP_ARROW_STEP = 180.0
    DEFAULT_ROTATE_DOWN_ARROW_STEP = -180.0
    SCALE_INPUT_UNITS = %w[mm cm m in ft].freeze
    ROTATE_ARROW_AXES = %w[x y z].freeze

    class << self
      attr_accessor :extensions_menu
      attr_accessor :settings_menu
      attr_accessor :toolbar
      attr_accessor :observer
      attr_accessor :manual_dialog
      attr_accessor :toggle_command
    end

    GLOBAL_ORIENTATION = 0
    LOCAL_ORIENTATION = 1

    @extensions_menu ||= UI.menu('Extensions').add_submenu(PLUGIN_NAME)
    @settings_menu ||= @extensions_menu.add_submenu('Settings')

    if Sketchup.version.to_i < MINIMUM_VERSION
      UI.messagebox("#{PLUGIN_NAME} requires SketchUp 2023 or newer.")
    else
      Sketchup.require('zb_smart_gizmo_pro/utils')
      Sketchup.require('zb_smart_gizmo_pro/observer')
      Sketchup.require('zb_smart_gizmo_pro/overlay')
      Sketchup.require('zb_smart_gizmo_pro/gizmo')

      def self.gizmo_orientation
        Sketchup.read_default(PLUGIN_NAME, 'orientation', GLOBAL_ORIENTATION)
      end

      def self.gizmo_orientation=(value)
        Sketchup.write_default(PLUGIN_NAME, 'orientation', value)
      end

      def self.gizmo_size
        value = Sketchup.read_default(PLUGIN_NAME, 'gizmo_size', DEFAULT_GIZMO_SIZE).to_i
        [[value, 80].max, 320].min
      end

      def self.gizmo_size=(value)
        Sketchup.write_default(PLUGIN_NAME, 'gizmo_size', [[value.to_i, 80].max, 320].min)
      end

      def self.pivot_size
        value = Sketchup.read_default(PLUGIN_NAME, 'pivot_size', DEFAULT_PIVOT_SIZE).to_i
        [[value, 4].max, 24].min
      end

      def self.pivot_size=(value)
        Sketchup.write_default(PLUGIN_NAME, 'pivot_size', [[value.to_i, 4].max, 24].min)
      end

      def self.open_preferences
        prompts = [
          'Handle Size (pixels)',
          'Pivot Size (pixels)',
          'Scale Input Unit (mm/cm/m/in/ft)',
          'Smart Scale Mode',
          'Arrow Key Rotate Active',
          'Remember Last Rotate Axis',
          'Fixed Rotate Axis',
          'Rotate Snap Increment (degrees)',
          'Rotate Left Arrow (degrees)',
          'Rotate Right Arrow (degrees)',
          'Rotate Up Arrow (degrees)',
          'Rotate Down Arrow (degrees)'
        ]
        defaults = [
          gizmo_size,
          pivot_size,
          scale_input_unit,
          smart_scale_enabled? ? 'Yes' : 'No',
          rotate_arrow_shortcuts_enabled? ? 'Yes' : 'No',
          rotate_arrow_remember_axis? ? 'Yes' : 'No',
          rotate_arrow_axis.upcase,
          rotate_snap_increment,
          rotate_left_arrow_step,
          rotate_right_arrow_step,
          rotate_up_arrow_step,
          rotate_down_arrow_step
        ]
        lists = [
          '',
          '',
          '',
          'Yes|No',
          'Yes|No',
          'Yes|No',
          'X|Y|Z',
          '',
          '',
          '',
          '',
          ''
        ]
        result = UI.inputbox(prompts, defaults, lists, "#{PLUGIN_NAME} Preferences")
        return unless result

        self.gizmo_size = result[0]
        self.pivot_size = result[1]
        self.scale_input_unit = result[2]
        self.smart_scale_enabled = result[3]
        self.rotate_arrow_shortcuts_enabled = result[4]
        self.rotate_arrow_remember_axis = result[5]
        self.rotate_arrow_axis = result[6]
        self.rotate_snap_increment = result[7]
        self.rotate_left_arrow_step = result[8]
        self.rotate_right_arrow_step = result[9]
        self.rotate_up_arrow_step = result[10]
        self.rotate_down_arrow_step = result[11]

        overlay = active_overlay
        overlay.start if overlay
      end

      def self.scale_input_unit
        value = Sketchup.read_default(PLUGIN_NAME, 'scale_input_unit', DEFAULT_SCALE_INPUT_UNIT).to_s.downcase
        SCALE_INPUT_UNITS.include?(value) ? value : DEFAULT_SCALE_INPUT_UNIT
      end

      def self.scale_input_unit=(value)
        unit = value.to_s.downcase.strip
        unit = DEFAULT_SCALE_INPUT_UNIT unless SCALE_INPUT_UNITS.include?(unit)
        Sketchup.write_default(PLUGIN_NAME, 'scale_input_unit', unit)
      end

      def self.smart_scale_enabled?
        value = Sketchup.read_default(PLUGIN_NAME, 'smart_scale_enabled', DEFAULT_SMART_SCALE_ENABLED)
        parse_boolean_setting(value, DEFAULT_SMART_SCALE_ENABLED)
      end

      def self.smart_scale_enabled=(value)
        Sketchup.write_default(PLUGIN_NAME, 'smart_scale_enabled', parse_boolean_setting(value, DEFAULT_SMART_SCALE_ENABLED))
      end

      def self.rotate_arrow_shortcuts_enabled?
        value = Sketchup.read_default(PLUGIN_NAME, 'rotate_arrow_shortcuts_enabled', DEFAULT_ROTATE_ARROW_SHORTCUTS_ENABLED)
        parse_boolean_setting(value, DEFAULT_ROTATE_ARROW_SHORTCUTS_ENABLED)
      end

      def self.rotate_arrow_shortcuts_enabled=(value)
        Sketchup.write_default(PLUGIN_NAME, 'rotate_arrow_shortcuts_enabled', parse_boolean_setting(value, DEFAULT_ROTATE_ARROW_SHORTCUTS_ENABLED))
      end

      def self.rotate_arrow_remember_axis?
        value = Sketchup.read_default(PLUGIN_NAME, 'rotate_arrow_remember_axis', DEFAULT_ROTATE_ARROW_REMEMBER_AXIS)
        parse_boolean_setting(value, DEFAULT_ROTATE_ARROW_REMEMBER_AXIS)
      end

      def self.rotate_arrow_remember_axis=(value)
        Sketchup.write_default(PLUGIN_NAME, 'rotate_arrow_remember_axis', parse_boolean_setting(value, DEFAULT_ROTATE_ARROW_REMEMBER_AXIS))
      end

      def self.rotate_arrow_axis
        axis = Sketchup.read_default(PLUGIN_NAME, 'rotate_arrow_axis', DEFAULT_ROTATE_ARROW_AXIS).to_s.downcase.strip
        ROTATE_ARROW_AXES.include?(axis) ? axis : DEFAULT_ROTATE_ARROW_AXIS
      end

      def self.rotate_arrow_axis=(value)
        axis = value.to_s.downcase.strip
        axis = DEFAULT_ROTATE_ARROW_AXIS unless ROTATE_ARROW_AXES.include?(axis)
        Sketchup.write_default(PLUGIN_NAME, 'rotate_arrow_axis', axis)
      end

      def self.rotate_snap_increment
        value = Sketchup.read_default(PLUGIN_NAME, 'rotate_snap_increment', DEFAULT_ROTATE_SNAP_INCREMENT).to_f
        value.positive? ? value : DEFAULT_ROTATE_SNAP_INCREMENT
      end

      def self.rotate_snap_increment=(value)
        increment = value.to_f
        increment = DEFAULT_ROTATE_SNAP_INCREMENT unless increment.positive?
        Sketchup.write_default(PLUGIN_NAME, 'rotate_snap_increment', increment)
      end

      def self.rotate_left_arrow_step
        Sketchup.read_default(PLUGIN_NAME, 'rotate_left_arrow_step', DEFAULT_ROTATE_LEFT_ARROW_STEP).to_f
      end

      def self.rotate_left_arrow_step=(value)
        Sketchup.write_default(PLUGIN_NAME, 'rotate_left_arrow_step', value.to_f)
      end

      def self.rotate_right_arrow_step
        Sketchup.read_default(PLUGIN_NAME, 'rotate_right_arrow_step', DEFAULT_ROTATE_RIGHT_ARROW_STEP).to_f
      end

      def self.rotate_right_arrow_step=(value)
        Sketchup.write_default(PLUGIN_NAME, 'rotate_right_arrow_step', value.to_f)
      end

      def self.rotate_up_arrow_step
        Sketchup.read_default(PLUGIN_NAME, 'rotate_up_arrow_step', DEFAULT_ROTATE_UP_ARROW_STEP).to_f
      end

      def self.rotate_up_arrow_step=(value)
        Sketchup.write_default(PLUGIN_NAME, 'rotate_up_arrow_step', value.to_f)
      end

      def self.rotate_down_arrow_step
        Sketchup.read_default(PLUGIN_NAME, 'rotate_down_arrow_step', DEFAULT_ROTATE_DOWN_ARROW_STEP).to_f
      end

      def self.rotate_down_arrow_step=(value)
        Sketchup.write_default(PLUGIN_NAME, 'rotate_down_arrow_step', value.to_f)
      end

      def self.parse_boolean_setting(value, default)
        case value
        when true, false
          value
        when Integer
          !value.zero?
        else
          text = value.to_s.strip.downcase
          return true if %w[true yes y on 1].include?(text)
          return false if %w[false no n off 0].include?(text)

          default
        end
      end

      def self.manual_html
        <<~HTML
          <!doctype html>
          <html lang="en">
          <head>
            <meta charset="utf-8">
            <title>#{PLUGIN_NAME} Manual</title>
            <style>
              :root {
                color-scheme: light;
                --bg: #f4f0e6;
                --panel: #fffdf8;
                --ink: #1f1f1f;
                --muted: #5a554f;
                --line: #d8cfbe;
                --accent: #2f5f73;
                --accent-soft: #e2edf2;
              }
              * { box-sizing: border-box; }
              body {
                margin: 0;
                background: linear-gradient(180deg, #f7f3ea 0%, var(--bg) 100%);
                color: var(--ink);
                font: 14px/1.55 "Segoe UI", Tahoma, sans-serif;
              }
              .wrap {
                max-width: 920px;
                margin: 0 auto;
                padding: 26px 24px 32px;
              }
              .hero {
                background: var(--panel);
                border: 1px solid var(--line);
                border-radius: 14px;
                padding: 22px 24px;
                box-shadow: 0 10px 24px rgba(0, 0, 0, 0.05);
              }
              h1, h2 {
                margin: 0 0 12px;
                line-height: 1.15;
              }
              h1 {
                font-size: 28px;
                color: var(--accent);
              }
              h2 {
                font-size: 18px;
                margin-top: 28px;
              }
              p {
                margin: 0 0 12px;
              }
              .grid {
                display: grid;
                grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
                gap: 14px;
                margin-top: 18px;
              }
              .card {
                background: var(--panel);
                border: 1px solid var(--line);
                border-radius: 12px;
                padding: 14px 16px;
              }
              .card h3 {
                margin: 0 0 8px;
                font-size: 14px;
                text-transform: uppercase;
                letter-spacing: 0.04em;
                color: var(--accent);
              }
              ul {
                margin: 0;
                padding-left: 18px;
              }
              li {
                margin: 0 0 8px;
              }
              .tip {
                background: var(--accent-soft);
                border-left: 4px solid var(--accent);
                border-radius: 10px;
                padding: 12px 14px;
                margin-top: 14px;
              }
              code {
                background: #f1ede3;
                border: 1px solid #e0d7c5;
                border-radius: 6px;
                padding: 1px 5px;
                font-family: Consolas, "Courier New", monospace;
                font-size: 12px;
              }
            </style>
          </head>
          <body>
            <div class="wrap">
              <div class="hero">
                <h1>#{PLUGIN_NAME} Manual</h1>
                <p>#{PLUGIN_NAME} adds an in-viewport move, rotate, and scale gizmo for SketchUp selections. It is designed to stay fast for regular transforms and provide smarter center-stretch behavior when Smart Scale is enabled.</p>
                <div class="tip">
                  Best results: use the gizmo on groups and components. Smart Scale works best on structured objects like tables, frames, cabinets, and nested assemblies where the middle span should stretch more than the detailed ends.
                </div>
              </div>

              <h2>Move</h2>
              <div class="grid">
                <div class="card">
                  <h3>Drag</h3>
                  <ul>
                    <li>Drag an axis arrow to move on one axis.</li>
                    <li>Drag a plane square to move on two axes while locking the third.</li>
                    <li>Drag the center pivot to reposition the gizmo pivot.</li>
                  </ul>
                </div>
                <div class="card">
                  <h3>Click Input</h3>
                  <ul>
                    <li>Click a move arrow for exact input.</li>
                    <li>You can enter a distance or an absolute world target on the active axis.</li>
                    <li>Example: move Z to <code>6000mm</code>.</li>
                  </ul>
                </div>
                <div class="card">
                  <h3>Copy Array</h3>
                  <ul>
                    <li>Click a move arrow, choose <code>Copy</code>, then enter the distance.</li>
                    <li>Enter a plain number such as <code>3</code> for Number of Copies -- this field always opens blank.</li>
                    <li><code>3</code> creates 3 copies plus the unchanged original (4 objects total).</li>
                    <li>Groups and components only. One Undo removes the whole array.</li>
                  </ul>
                </div>
              </div>

              <h2>Ctrl-Drag Copy</h2>
              <p>Hold <code>Ctrl</code> while dragging a move arrow, then release to place an endpoint copy. Immediately typing an array instruction turns it into a full array, spaced by that same drag.</p>
              <div class="grid">
                <div class="card">
                  <h3>Internal Array &mdash; <code>/N</code></h3>
                  <ul>
                    <li><code>/3</code> divides the dragged distance into 3 equal spaces; the endpoint counts as one of the 3 copies.</li>
                    <li><code>3/</code> is also accepted.</li>
                    <li>A different <code>/N</code> replaces the array instead of adding to it.</li>
                  </ul>
                  <div class="tip">Drag <code>3000mm</code>, type <code>/3</code> &rarr; copies at <code>1000</code>, <code>2000</code>, <code>3000mm</code>.</div>
                </div>
                <div class="card">
                  <h3>External Array &mdash; <code>xN</code></h3>
                  <ul>
                    <li><code>x3</code> creates 3 copies at the dragged spacing; the endpoint counts as copy 1.</li>
                    <li><code>3x</code>, <code>X3</code>, and <code>3X</code> are also accepted.</li>
                    <li>A different <code>xN</code> replaces the array; switching between <code>/N</code> and <code>xN</code> replaces it too.</li>
                  </ul>
                  <div class="tip">Drag <code>1000mm</code>, type <code>x3</code> &rarr; copies at <code>1000</code>, <code>2000</code>, <code>3000mm</code>.</div>
                </div>
              </div>
              <div class="card">
                <ul>
                  <li>Array generation supports groups and components only; an unsupported selection shows a message and leaves the single endpoint copy in place.</li>
                  <li>Clicking elsewhere, pressing <code>Esc</code>, starting another drag, or switching tools ends the array input.</li>
                  <li>One Undo removes the endpoint and every generated copy, however many array edits were made to it.</li>
                </ul>
              </div>

              <h2>Rotate</h2>
              <div class="grid">
                <div class="card">
                  <h3>Drag</h3>
                  <ul>
                    <li>Drag a rotate ring to rotate around that axis.</li>
                    <li>Snaps to the Rotate Snap Increment preference (<code>5&deg;</code> by default).</li>
                  </ul>
                </div>
                <div class="card">
                  <h3>Click Input</h3>
                  <ul>
                    <li>Click a rotate ring to enter an exact angle.</li>
                    <li>Set Remember Last Rotate Axis to Yes to make arrow keys use the last rotate ring axis.</li>
                    <li>Set Remember Last Rotate Axis to No to make arrow keys always use the Fixed Rotate Axis from Preferences (defaults to Z).</li>
                  </ul>
                </div>
                <div class="card">
                  <h3>Arrow-Key Steps</h3>
                  <ul>
                    <li>Arrow keys rotate while hovering the gizmo, if enabled.</li>
                    <li><code>Left</code>: <code>-90&deg;</code> &middot; <code>Right</code>: <code>+90&deg;</code></li>
                    <li><code>Up</code>: <code>180&deg;</code> &middot; <code>Down</code>: <code>-180&deg;</code></li>
                    <li>All four step values are configurable in Preferences.</li>
                  </ul>
                </div>
              </div>

              <h2>Scale</h2>
              <div class="grid">
                <div class="card">
                  <h3>Standard Scale</h3>
                  <ul>
                    <li>Drag a scale handle for live scaling.</li>
                    <li>Click a scale handle for exact input.</li>
                    <li>A leading <code>+</code> or <code>-</code> bases the expression on the currently shown value, e.g. <code>+100</code> or <code>+100+6+5</code>.</li>
                    <li>Without a leading sign the expression is an absolute target, e.g. <code>600mm+100mm</code> or <code>24in+2in</code>.</li>
                  </ul>
                </div>
                <div class="card">
                  <h3>Units</h3>
                  <ul>
                    <li>Plain numbers use the configured scale input unit from Preferences.</li>
                    <li>Explicit units always win, for example <code>24in</code> or <code>600mm</code>.</li>
                    <li>Single-axis exact scale anchors from one side instead of scaling from center.</li>
                  </ul>
                </div>
                <div class="card">
                  <h3>Dimension, Division &amp; Multiplication</h3>
                  <ul>
                    <li>A single-axis handle shows the resulting real-world dimension as a number (e.g. <code>50.8</code>), using the model's own unit, precision, and locale, with the unit suffix omitted. Typed Scale expressions can still use explicit units, e.g. <code>600mm</code>.</li>
                    <li>Type <code>/2</code> to divide the shown dimension in half; <code>/3</code>, <code>/4</code>, etc. work the same way.</li>
                    <li>Not the Ctrl-drag copy array's <code>/N</code> -- this divides a Scale dimension, not a dragged copy distance.</li>
                    <li>Type <code>x2</code> (or <code>X2</code>) to double the shown dimension; decimal multipliers such as <code>x1.5</code> work too. Works in ordinary Scale and Smart Scale, from the click dialog or a Measurements re-edit.</li>
                    <li>Quick reference: in Scale, <code>/2</code> halves and <code>x2</code> doubles the current dimension. During a Ctrl-drag Move, <code>x2</code> instead creates an external copy array -- same syntax, different meaning, decided by which handle you're using.</li>
                  </ul>
                </div>
              </div>

              <h2>Smart Scale</h2>
              <div class="card">
                <h3>What It Does</h3>
                <ul>
                  <li>Smart Scale tries to preserve detailed end regions and stretch the middle span.</li>
                  <li>It works best on grouped/component objects such as tables, window frames, cabinet parts, and nested assemblies.</li>
                  <li>Nested group/component structures are supported better than exploded loose geometry.</li>
                  <li>If the object has no useful structure to preserve, scaling may behave more like default scale.</li>
                </ul>
              </div>

              <h2>Pivot</h2>
              <div class="grid">
                <div class="card">
                  <h3>Drag</h3>
                  <ul>
                    <li>Drag the center pivot control to reposition the gizmo origin.</li>
                    <li>Pivot dragging snaps to model geometry using SketchUp's point inference.</li>
                  </ul>
                </div>
                <div class="card">
                  <h3>Right-Click Menu</h3>
                  <ul>
                    <li>Right-click while hovering the gizmo for pivot commands.</li>
                    <li><code>Reset Pivot To Selection Center</code></li>
                    <li><code>Set Pivot To Model Axes Origin</code></li>
                    <li><code>Set Pivot To Object Origin</code> (when exactly one group/component is selected)</li>
                  </ul>
                </div>
              </div>

              <h2>Preferences</h2>
              <div class="card">
                <h3>Available Settings</h3>
                <ul>
                  <li>Handle size and pivot size</li>
                  <li>Scale input unit</li>
                  <li>Smart Scale on or off</li>
                  <li>Rotate snap increment (degrees, default <code>5</code>)</li>
                  <li>Arrow-key rotate on or off</li>
                  <li>Arrow-key rotate remember-last-axis on or off</li>
                  <li>Fixed arrow-key rotate axis: X, Y, or Z</li>
                  <li>Arrow-key rotate step values</li>
                </ul>
              </div>

              <h2>Tips</h2>
              <div class="card">
                <h3>Workflow Notes</h3>
                <ul>
                  <li>Press <code>M</code> to switch to SketchUp's native Move tool and temporarily hide the gizmo.</li>
                  <li>The gizmo is meant to work with selection and orbit workflows, not fight them.</li>
                  <li>If you need the best Smart Scale result, keep the object grouped/componentized instead of exploding it.</li>
                  <li>For background right-click and native double-click behavior, click outside the gizmo itself.</li>
                </ul>
              </div>
            </div>
          </body>
          </html>
        HTML
      end

      def self.open_manual
        if defined?(UI::HtmlDialog)
          self.manual_dialog ||= UI::HtmlDialog.new(
            dialog_title: "#{PLUGIN_NAME} Manual",
            preferences_key: 'zb_smart_gizmo_pro_manual',
            scrollable: true,
            resizable: true,
            width: 900,
            height: 720,
            style: UI::HtmlDialog::STYLE_DIALOG
          )
          manual_dialog.set_html(manual_html)
          manual_dialog.show
        else
          UI.messagebox("#{PLUGIN_NAME}\n\nOpen the Settings > Manual entry on a newer SketchUp version to view the built-in manual.")
        end
      end

      # Built entirely from PLUGIN_NAME/PLUGIN_VERSION (zb_smart_gizmo_pro.rb) --
      # no version literal here, so a future version bump (or a DEV build's
      # PLUGIN_VERSION override, e.g. '1.5.3 DEV') shows up automatically,
      # with no change needed in this file. Developer/website info is
      # unchanged from before this method showed a version at all.
      def self.open_about
      UI.messagebox("#{PLUGIN_NAME} #{PLUGIN_VERSION}\n\nDeveloper: Peter Zbel\nWebsite: www.zbellbound.com")
      end

      def self.command_icon_path
        png = File.join(PATH, 'Resources', 'icon.png')
        svg = File.join(PATH, 'Resources', 'icon.svg')
        pdf = File.join(PATH, 'Resources', 'icon.pdf')
        if RUBY_PLATFORM.include?('darwin')
          return pdf if File.exist?(pdf)
          return svg if File.exist?(svg)
        end

        return svg if File.exist?(svg)
        return png if File.exist?(png)

        png
      end

      def self.build_toggle_command
        return @toggle_command if @toggle_command

        cmd = UI::Command.new("Toggle #{PLUGIN_NAME}") { toggle_gizmo }
        icon_path = command_icon_path
        if File.exist?(icon_path)
          cmd.small_icon = icon_path
          cmd.large_icon = icon_path
        end
        cmd.tooltip = PLUGIN_NAME
        cmd.status_bar_text = 'Toggle the ZB Smart Gizmo Pro overlay.'
        cmd.menu_text = "Toggle #{PLUGIN_NAME}"
        cmd.set_validation_proc do
          overlay = active_overlay
          overlay&.enabled? ? MF_CHECKED : MF_UNCHECKED
        end

        @toggle_command = cmd
      end

      file = __FILE__.dup
      file.force_encoding('UTF-8') if file.respond_to?(:force_encoding)
      unless file_loaded?(file)
        toggle_cmd = build_toggle_command
        extensions_menu.add_item(toggle_cmd)
        settings_menu.add_item('Preferences...') { open_preferences }
        settings_menu.add_item('Manual') { open_manual }
        settings_menu.add_item('About') { open_about }
        self.toolbar ||= UI::Toolbar.new(PLUGIN_NAME)
        toolbar.add_item(toggle_cmd)
        toolbar.show
        @observer = GizmoObserver.new
        @observer.attach_to_active_model

        file_loaded(file)
      end
    end
  end
end
