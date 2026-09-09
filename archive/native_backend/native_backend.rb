# Copyright Peter Zbel - Zbellbound.com
# ZB Smart Gizmo

module ZBSmart::Gizmo
  module NativeScaleBackend
    module_function

    def available?
      load_native_extension unless defined?(@load_attempted) && @load_attempted
      defined?(::ScalePlusPlusNative) && ::ScalePlusPlusNative.respond_to?(:compute_scale)
    end

    def compute_scale(current_x, current_y, current_z, target_value, axis, mode)
      load_native_extension unless defined?(@load_attempted) && @load_attempted

      if available?
        result = ::ScalePlusPlusNative.compute_scale(
          current_x.to_f,
          current_y.to_f,
          current_z.to_f,
          target_value.to_f,
          axis.to_s,
          mode.to_s
        )
        normalize_result(result)
      else
        ruby_compute_scale(current_x, current_y, current_z, target_value, axis, mode)
      end
    rescue StandardError => e
      {
        valid: false,
        sx: 1.0,
        sy: 1.0,
        sz: 1.0,
        error: e.message
      }
    end

    def ruby_compute_scale(current_x, current_y, current_z, target_value, axis, mode)
      dims = {
        'x' => current_x.to_f,
        'y' => current_y.to_f,
        'z' => current_z.to_f
      }
      target = target_value.to_f
      axis_key = axis.to_s.downcase
      mode_key = mode.to_s.downcase

      return invalid_result('Target dimension must be greater than zero.') unless finite_positive?(target)
      return invalid_result('Axis must be x, y, or z.') unless dims.key?(axis_key)
      return invalid_result('Mode must be axis or uniform.') unless %w[axis uniform].include?(mode_key)

      dims.each do |name, value|
        return invalid_result("Current #{name.upcase} dimension is not finite.") unless finite_number?(value)
      end

      if mode_key == 'uniform'
        dims.each do |name, value|
          return invalid_result("Current #{name.upcase} dimension must be greater than zero for uniform scaling.") unless finite_positive?(value)
        end
      else
        return invalid_result("Current #{axis_key.upcase} dimension must be greater than zero.") unless finite_positive?(dims[axis_key])
      end

      reference = dims[axis_key]
      factor = target / reference
      return invalid_result('Computed scale factor is not finite.') unless finite_number?(factor)

      if mode_key == 'axis'
        sx = axis_key == 'x' ? factor : 1.0
        sy = axis_key == 'y' ? factor : 1.0
        sz = axis_key == 'z' ? factor : 1.0
      else
        sx = factor
        sy = factor
        sz = factor
      end

      result = {
        valid: true,
        sx: sx,
        sy: sy,
        sz: sz,
        error: nil
      }
      normalize_result(result)
    end

    def normalize_result(result)
      hash = result.respond_to?(:to_h) ? result.to_h : {}
      normalized = {
        valid: !!hash[:valid],
        sx: hash[:sx].to_f,
        sy: hash[:sy].to_f,
        sz: hash[:sz].to_f,
        error: hash[:error]
      }

      unless normalized[:valid]
        normalized[:sx] = 1.0
        normalized[:sy] = 1.0
        normalized[:sz] = 1.0
      end

      return invalid_result('Computed scale factors are not finite.') unless [normalized[:sx], normalized[:sy], normalized[:sz]].all? { |value| finite_number?(value) }

      normalized
    end

    def load_native_extension
      @load_attempted = true

      binary_path =
        if RUBY_PLATFORM.include?('darwin')
          File.join(PATH, 'native', 'mac', 'scaleplusplus_native.bundle')
        elsif RUBY_PLATFORM.include?('mswin') || RUBY_PLATFORM.include?('mingw')
          File.join(PATH, 'native', 'win', 'scaleplusplus_native.so')
        end

      return unless binary_path && File.exist?(binary_path)

      require binary_path
      @native_loaded = true
    rescue LoadError
      @native_loaded = false
    end

    def invalid_result(message)
      {
        valid: false,
        sx: 1.0,
        sy: 1.0,
        sz: 1.0,
        error: message
      }
    end

    def finite_positive?(value)
      finite_number?(value) && value.positive?
    end

    def finite_number?(value)
      value.is_a?(Numeric) && value.finite?
    end
  end
end
