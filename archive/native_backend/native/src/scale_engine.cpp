#include <cmath>
#include <string>

namespace scaleplusplus_native {

struct ScaleResult {
  bool valid;
  double sx;
  double sy;
  double sz;
  std::string error;
};

static bool finite_positive(double value) {
  return std::isfinite(value) && value > 0.0;
}

ScaleResult compute_scale(
    double current_x,
    double current_y,
    double current_z,
    double target_value,
    const std::string& axis,
    const std::string& mode) {
  ScaleResult result = {false, 1.0, 1.0, 1.0, ""};

  if (!finite_positive(target_value)) {
    result.error = "Target dimension must be greater than zero.";
    return result;
  }
  if (!std::isfinite(current_x) || !std::isfinite(current_y) || !std::isfinite(current_z)) {
    result.error = "Current dimensions must be finite.";
    return result;
  }
  if (!(axis == "x" || axis == "y" || axis == "z")) {
    result.error = "Axis must be x, y, or z.";
    return result;
  }
  if (!(mode == "axis" || mode == "uniform")) {
    result.error = "Mode must be axis or uniform.";
    return result;
  }

  double reference = 0.0;
  if (axis == "x") {
    reference = current_x;
  } else if (axis == "y") {
    reference = current_y;
  } else {
    reference = current_z;
  }

  if (mode == "uniform") {
    if (!finite_positive(current_x) || !finite_positive(current_y) || !finite_positive(current_z)) {
      result.error = "All current dimensions must be greater than zero for uniform scaling.";
      return result;
    }
  } else if (!finite_positive(reference)) {
    result.error = "Reference dimension must be greater than zero.";
    return result;
  }

  double factor = target_value / reference;
  if (!std::isfinite(factor)) {
    result.error = "Computed scale factor is not finite.";
    return result;
  }

  if (mode == "axis") {
    result.sx = axis == "x" ? factor : 1.0;
    result.sy = axis == "y" ? factor : 1.0;
    result.sz = axis == "z" ? factor : 1.0;
  } else {
    result.sx = factor;
    result.sy = factor;
    result.sz = factor;
  }

  if (!std::isfinite(result.sx) || !std::isfinite(result.sy) || !std::isfinite(result.sz)) {
    result.error = "Computed scale factors are not finite.";
    result.sx = 1.0;
    result.sy = 1.0;
    result.sz = 1.0;
    return result;
  }

  result.valid = true;
  return result;
}

}  // namespace scaleplusplus_native
