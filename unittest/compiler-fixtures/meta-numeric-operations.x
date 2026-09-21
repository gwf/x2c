/* Native and meta numeric helpers preserve payload tags and boundaries. */
#include "x2c.x"

meta int numeric_Var_box_i8(int unused) {
  (void) unused;
  Var v = Var.box_i8(-7);
  return v.tag() == <i8>
    && v.integer() == -7;
}
meta int numeric_Var_box_u8(int unused) {
  (void) unused;
  Var v = Var.box_u8(255);
  return v.tag() == <u8>
    && v.integer() == 255;
}
meta int numeric_Var_box_i16(int unused) {
  (void) unused;
  Var v = Var.box_i16(-300);
  return v.tag() == <i16>
    && v.integer() == -300;
}
meta int numeric_Var_box_u16(int unused) {
  (void) unused;
  Var v = Var.box_u16(65535);
  return v.tag() == <u16>
    && v.integer() == 65535;
}
meta int numeric_Var_box_i32_bits(int unused) {
  (void) unused;
  Var v = Var.box_i32_bits(0xfffffff9u);
  return v.tag() == <i32>
    && v.integer() == -7;
}
meta int numeric_Var_box_u32(int unused) {
  (void) unused;
  Var v = Var.box_u32(4000000000u);
  return v.tag() == <u32>
    && v.unsigned() == 4000000000u;
}
meta int numeric_Var_box_f32(int unused) {
  (void) unused;
  Var v = Var.box_f32(1.25);
  return v.tag() == <f32>
    && v.decode_f32() == 1.25;
}
meta int numeric_Var_box_f64(int unused) {
  (void) unused;
  Var v = Var.box_f64(1.25);
  return v.tag() == <f64>
    && v.decode_f64() == 1.25;
}
meta int numeric_Var_box_long(int unused) {
  (void) unused;
  Var v = Var.box_long(-7);
  return v.tag() == <long>
    && v.long_value() == -7;
}
meta int numeric_Var_box_ulong(int unused) {
  (void) unused;
  Var v = Var.box_ulong(7);
  return v.tag() == <ulong>
    && v.ulong_value() == 7;
}
meta int numeric_Var_box_long_long(int unused) {
  (void) unused;
  Var v = Var.box_long_long(-7);
  return v.tag() == <llong>
    && v.long_long_value() == -7;
}
meta int numeric_Var_box_ulong_long(int unused) {
  (void) unused;
  Var v = Var.box_ulong_long(7);
  return v.tag() == <ullong>
    && v.ulong_long_value() == 7;
}
meta int numeric_Var_box_long_double(int unused) {
  (void) unused;
  Var v = Var.box_long_double(1.25);
  return v.tag() == <ldouble>
    && v.long_double_value() == 1.25;
}
meta int numeric_Var_custom_descriptor_index(int unused) {
  (void) unused;
  Var a = 7, b = "x";
  return a.custom_descriptor_index() == -1
    && b.custom_descriptor_index() == -1;
}
meta int numeric_Var_decode_f32(int unused) {
  (void) unused;
  Var a = (float) 1.25;
  return a.decode_f32() == 1.25;
}
meta int numeric_Var_decode_f64(int unused) {
  (void) unused;
  Var a = 1.25;
  return a.decode_f64() == 1.25;
}
meta int numeric_Var_encoding_valid(int unused) {
  (void) unused;
  Var a = 7, b = "x", c = 1.25;
  return a.encoding_valid()
    && b.encoding_valid()
    && c.encoding_valid();
}
meta int numeric_Var_fallback_compare(int unused) {
  (void) unused;
  Var a = 7, b = 8;
  return a.fallback_compare(b) < 0
    && a.fallback_compare(a) == 0;
}
meta int numeric_Var_fallback_equal(int unused) {
  (void) unused;
  Var a = 7, b = 8;
  return a.fallback_equal(a)
    && !a.fallback_equal(b);
}
meta int numeric_Var_fallback_hash(int unused) {
  (void) unused;
  Var a = 7, b = 7;
  return a.fallback_hash() == b.fallback_hash();
}
meta int numeric_Var_fallback_repr(int unused) {
  (void) unused;
  Var a = 7;
  return a.fallback_repr().equal("7");
}
meta int numeric_Var_fallback_str(int unused) {
  (void) unused;
  Var a = 7;
  return a.fallback_str().equal("7");
}
meta int numeric_Var_fallback_truth(int unused) {
  (void) unused;
  Var a = 0, b = 7;
  return !a.fallback_truth()
    && b.fallback_truth();
}
meta int numeric_Var_integer_box(int unused) {
  (void) unused;
  Var a = Var.integer_box(<i8>, 255);
  return a.tag() == <i8>
    && a.integer() == -1;
}
meta int numeric_Var_integer_compare(int unused) {
  (void) unused;
  Var a = -1, b = 1u;
  return a.integer_compare(b) < 0
    && b.integer_compare(a) > 0;
}
meta int numeric_Var_integer_floating_compare(int unused) {
  (void) unused;
  Var a = 7, b = 7.5;
  return a.integer_floating_compare(b) < 0;
}
meta int numeric_Var_integer_tag(int unused) {
  (void) unused;
  return Var.integer_tag(1, 0) == <i32>
    && Var.integer_tag(5, 1) == <ulong>;
}
meta int numeric_Var_is_row(int unused) {
  (void) unused;
  Var a = 7, b = (float) 7;
  return a.is_row(0x8002u, 0xffff00000000ul, 0x600000000ul)
    && !b.is_row(0x8002u, 0xffff00000000ul, 0x600000000ul);
}
meta int numeric_Var_known_tag(int unused) {
  (void) unused;
  return Var.known_tag(<i32>)
    && !Var.known_tag(<bogus>);
}
meta int numeric_Var_payload32(int unused) {
  (void) unused;
  Var a = -7;
  return a.payload32() == 0xfffffff9u;
}
meta int numeric_Var_signed_from_bits(int unused) {
  (void) unused;
  return Var.signed_from_bits(255, 8) == -1
    && Var.signed_from_bits(127, 8) == 127;
}
meta int numeric_Var_wide_compare(int unused) {
  (void) unused;
  Var a = 7L, b = 8L, c = 1;
  return a.wide_compare(b) < 0
    && a.wide_compare(c) == 0;
}
meta int numeric_Var_wide_equal(int unused) {
  (void) unused;
  Var a = 7L, b = 7L, c = 7;
  return a.wide_equal(b)
    && !a.wide_equal(c);
}
meta int numeric_Var_wide_hash(int unused) {
  (void) unused;
  Var a = 7L, b = 7L, c = 7;
  return a.wide_hash() == b.wide_hash()
    && c.wide_hash() == 0;
}
meta int numeric_Var_width_mask(int unused) {
  (void) unused;
  return Var.width_mask(0) == 0
    && Var.width_mask(8) == 255
    && Var.width_mask(16) == 65535;
}
static uchar byte_identity(uchar x) => x;
static ushort short_identity(ushort x) => x;
static uint uint_identity(uint x) => x;
int main(int argc, char **argv) {
  (void) argv;
  printf("%d %d\n", $numeric_Var_box_i8(0),
    numeric_Var_box_i8(argc - 1));
  printf("%d %d\n", $numeric_Var_box_u8(0),
    numeric_Var_box_u8(argc - 1));
  printf("%d %d\n", $numeric_Var_box_i16(0),
    numeric_Var_box_i16(argc - 1));
  printf("%d %d\n", $numeric_Var_box_u16(0),
    numeric_Var_box_u16(argc - 1));
  printf("%d %d\n", $numeric_Var_box_i32_bits(0),
    numeric_Var_box_i32_bits(argc - 1));
  printf("%d %d\n", $numeric_Var_box_u32(0),
    numeric_Var_box_u32(argc - 1));
  printf("%d %d\n", $numeric_Var_box_f32(0),
    numeric_Var_box_f32(argc - 1));
  printf("%d %d\n", $numeric_Var_box_f64(0),
    numeric_Var_box_f64(argc - 1));
  printf("%d %d\n", $numeric_Var_box_long(0),
    numeric_Var_box_long(argc - 1));
  printf("%d %d\n", $numeric_Var_box_ulong(0),
    numeric_Var_box_ulong(argc - 1));
  printf("%d %d\n", $numeric_Var_box_long_long(0),
    numeric_Var_box_long_long(argc - 1));
  printf("%d %d\n", $numeric_Var_box_ulong_long(0),
    numeric_Var_box_ulong_long(argc - 1));
  printf("%d %d\n", $numeric_Var_box_long_double(0),
    numeric_Var_box_long_double(argc - 1));
  printf("%d %d\n", $numeric_Var_custom_descriptor_index(0),
    numeric_Var_custom_descriptor_index(argc - 1));
  printf("%d %d\n", $numeric_Var_decode_f32(0),
    numeric_Var_decode_f32(argc - 1));
  printf("%d %d\n", $numeric_Var_decode_f64(0),
    numeric_Var_decode_f64(argc - 1));
  printf("%d %d\n", $numeric_Var_encoding_valid(0),
    numeric_Var_encoding_valid(argc - 1));
  printf("%d %d\n", $numeric_Var_fallback_compare(0),
    numeric_Var_fallback_compare(argc - 1));
  printf("%d %d\n", $numeric_Var_fallback_equal(0),
    numeric_Var_fallback_equal(argc - 1));
  printf("%d %d\n", $numeric_Var_fallback_hash(0),
    numeric_Var_fallback_hash(argc - 1));
  printf("%d %d\n", $numeric_Var_fallback_repr(0),
    numeric_Var_fallback_repr(argc - 1));
  printf("%d %d\n", $numeric_Var_fallback_str(0),
    numeric_Var_fallback_str(argc - 1));
  printf("%d %d\n", $numeric_Var_fallback_truth(0),
    numeric_Var_fallback_truth(argc - 1));
  printf("%d %d\n", $numeric_Var_integer_box(0),
    numeric_Var_integer_box(argc - 1));
  printf("%d %d\n", $numeric_Var_integer_compare(0),
    numeric_Var_integer_compare(argc - 1));
  printf("%d %d\n", $numeric_Var_integer_floating_compare(0),
    numeric_Var_integer_floating_compare(argc - 1));
  printf("%d %d\n", $numeric_Var_integer_tag(0),
    numeric_Var_integer_tag(argc - 1));
  printf("%d %d\n", $numeric_Var_is_row(0),
    numeric_Var_is_row(argc - 1));
  printf("%d %d\n", $numeric_Var_known_tag(0),
    numeric_Var_known_tag(argc - 1));
  printf("%d %d\n", $numeric_Var_payload32(0),
    numeric_Var_payload32(argc - 1));
  printf("%d %d\n", $numeric_Var_signed_from_bits(0),
    numeric_Var_signed_from_bits(argc - 1));
  printf("%d %d\n", $numeric_Var_wide_compare(0),
    numeric_Var_wide_compare(argc - 1));
  printf("%d %d\n", $numeric_Var_wide_equal(0),
    numeric_Var_wide_equal(argc - 1));
  printf("%d %d\n", $numeric_Var_wide_hash(0),
    numeric_Var_wide_hash(argc - 1));
  printf("%d %d\n", $numeric_Var_width_mask(0),
    numeric_Var_width_mask(argc - 1));
  Func byte = byte_identity, short_value = short_identity,
    unsigned_value = uint_identity;
  Var a = byte(257), b = short_value(65537),
    c = unsigned_value(4000000000u);
  printf("%d\n", a.tag() == <u8> && a.integer() == 1
    && b.tag() == <u16> && b.integer() == 1
    && c.tag() == <u32> && c.unsigned() == 4000000000u);
  return 0;
}
