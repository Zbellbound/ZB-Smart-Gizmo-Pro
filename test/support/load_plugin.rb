require_relative 'sketchup_stubs'

module Zbellbound
  module SmartGizmoPro
    PLUGIN = self

    PLUGIN_NAME = 'ZB Smart Gizmo Pro Test'.freeze
    DEBUG_MODE = false

    GLOBAL_ORIENTATION = 0
    LOCAL_ORIENTATION = 1

    class << self
      attr_accessor :test_smart_scale_enabled
      attr_accessor :test_gizmo_orientation
    end

    self.test_smart_scale_enabled = false
    self.test_gizmo_orientation = GLOBAL_ORIENTATION

    def self.smart_scale_enabled?
      !!test_smart_scale_enabled
    end

    def self.gizmo_orientation
      test_gizmo_orientation
    end

    def self.active_overlay(_model = nil)
      nil
    end

    def self.gizmo_size
      150
    end

    def self.pivot_size
      6
    end

    # Real loader.rb's DEFAULT_SCALE_INPUT_UNIT/#scale_input_unit -- the
    # unit a *typed*, unitless number in a Scale expression is interpreted
    # as (a separate, independently-configurable preference from the
    # model's own display units). This test double was missing entirely
    # until it surfaced a real NoMethodError while testing the click
    # dialog's now-bare-number default (Defect 1) being fed back through
    # parse_scale_length -- production never hit this because loader.rb is
    # always loaded there; only this minimal test harness (utils.rb +
    # overlay.rb only, see the requires below) was missing it.
    class << self
      attr_accessor :test_scale_input_unit
    end
    self.test_scale_input_unit = 'mm'

    def self.scale_input_unit
      test_scale_input_unit
    end
  end
end

root = File.expand_path('../../zb_smart_gizmo_pro', __dir__)
require File.join(root, 'utils.rb')
require File.join(root, 'overlay.rb')
