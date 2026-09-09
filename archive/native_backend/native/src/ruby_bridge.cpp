#include <ruby.h>

#include <string>

namespace scaleplusplus_native {
struct ScaleResult {
  bool valid;
  double sx;
  double sy;
  double sz;
  std::string error;
};

ScaleResult compute_scale(
    double current_x,
    double current_y,
    double current_z,
    double target_value,
    const std::string& axis,
    const std::string& mode);
}  // namespace scaleplusplus_native

static VALUE rb_compute_scale(VALUE self, VALUE current_x, VALUE current_y, VALUE current_z,
                              VALUE target_value, VALUE axis, VALUE mode) {
  scaleplusplus_native::ScaleResult result = scaleplusplus_native::compute_scale(
      NUM2DBL(current_x),
      NUM2DBL(current_y),
      NUM2DBL(current_z),
      NUM2DBL(target_value),
      StringValueCStr(axis),
      StringValueCStr(mode));

  VALUE hash = rb_hash_new();
  rb_hash_aset(hash, ID2SYM(rb_intern("valid")), result.valid ? Qtrue : Qfalse);
  rb_hash_aset(hash, ID2SYM(rb_intern("sx")), rb_float_new(result.sx));
  rb_hash_aset(hash, ID2SYM(rb_intern("sy")), rb_float_new(result.sy));
  rb_hash_aset(hash, ID2SYM(rb_intern("sz")), rb_float_new(result.sz));
  rb_hash_aset(hash, ID2SYM(rb_intern("error")),
               result.error.empty() ? Qnil : rb_utf8_str_new_cstr(result.error.c_str()));
  return hash;
}

extern "C" void Init_scaleplusplus_native() {
  VALUE module = rb_define_module("ScalePlusPlusNative");
  rb_define_singleton_method(module, "compute_scale", RUBY_METHOD_FUNC(rb_compute_scale), 6);
}
