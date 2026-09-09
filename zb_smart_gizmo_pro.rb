# Copyright Peter Zbel - Zbellbound.com
# ZB Smart Gizmo Pro

require 'extensions.rb'
require 'sketchup.rb'

module Zbellbound
  module SmartGizmoPro
    PLUGIN = self

    PLUGIN_VENDOR    = 'Zbellbound'.freeze
    PLUGIN_ID        = 'zb_smart_gizmo_pro'.freeze
    PLUGIN_NAME      = 'ZB Smart Gizmo Pro'.freeze
    PLUGIN_VERSION   = '1.5.3'.freeze
    PLUGIN_COPYRIGHT = 'Copyright (c) Peter Zbel / Zbellbound'.freeze
    PLUGIN_CREATOR   = 'Peter Zbel / Zbellbound'.freeze
    PLUGIN_DESC      = 'Interactive transform gizmo overlay for SketchUp with Smart Scale for structured objects.'.freeze
    MINIMUM_VERSION  = 23

    # Production builds must not write to the SketchUp Ruby Console. Internal
    # error-recovery logging (warn_overlay_issue, etc.) checks this flag and
    # stays silent unless it's explicitly flipped to true for local
    # development/debugging. Error handling/recovery itself is unaffected
    # either way -- only whether the diagnostic message is printed.
    DEBUG_MODE = false

    # __FILE__ can carry the wrong encoding on Windows; if the install path
    # contains non-ASCII characters (e.g. in the OS username), passing it
    # straight to File.basename/File.dirname can raise. Force UTF-8 on a
    # duplicate first, per SketchUp's own documented workaround for this.
    UNENCODED_FILE = __FILE__.dup
    UNENCODED_FILE.force_encoding('UTF-8') if UNENCODED_FILE.respond_to?(:force_encoding)

    SUPPORT_NAMESPACE = File.basename(UNENCODED_FILE, '.*').freeze
    PATH_ROOT         = File.dirname(UNENCODED_FILE).freeze
    PATH              = File.join(PATH_ROOT, SUPPORT_NAMESPACE).freeze

    unless file_loaded?(__FILE__)
      extension = SketchupExtension.new(PLUGIN_NAME, 'zb_smart_gizmo_pro/loader')
      extension.version     = PLUGIN_VERSION
      extension.copyright   = PLUGIN_COPYRIGHT
      extension.creator     = PLUGIN_CREATOR
      extension.description = PLUGIN_DESC

      Sketchup.register_extension(extension, true)
      PLUGIN_EX = extension
    end
  end
end

file_loaded(__FILE__)
