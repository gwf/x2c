/*  test-var.x -- unit tests for Var helpers and tagging */

#include <float.h>
#include <limits.h>
#include <math.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>
#include <sys/types.h>
#include <time.h>

#include "test-support.x"
$(import "test-macros.xmacro")

static double absd(double value) { return value < 0 ? -value : value; }

#define EXPECT_DOUBLE_NEAR(expr, actual, expected, tol) \
  Test_expect(expr, absd((actual) - (expected)) <= (tol), __FILE__, __LINE__)

typedef struct DispatchFixture {
  long value;
} DispatchFixture;

static int dispatch_truth_calls = 0;
static List var_runtime_errors;


static Symbol _capture_var_runtime_error(List errors, Var data) {
  (void) data;
  Var snapshot = Error.snapshot(errors);
  var_runtime_errors = snapshot;
  return <handled>;
}


static Symbol _var_runtime_error_code(void) {
  return var_runtime_errors.last().list().assoc(<code>);
}


static String dispatch_fixture_str(Var value) {
  return %"custom-str";
}

static String dispatch_fixture_str_replacement(Var value) {
  return %"custom-str-replaced";
}

static String dispatch_fixture_repr(Var value) {
  return %"custom-repr";
}

static Buffer dispatch_fixture_write_repr(Var value, Buffer out) {
  return out.write("custom-stream-repr");
}

static Buffer dispatch_fixture_write_str(Var value, Buffer out) {
  return out.write("custom-stream-str");
}

static unsigned dispatch_fixture_hash(Var value) {
  DispatchFixture *fixture = value.pointer();
  return fixture.value;
}

static int dispatch_fixture_equal(Var a, Var b) {
  DispatchFixture *left = a.pointer(), *right = b.pointer();
  return left.value == right.value;
}

static int dispatch_fixture_compare(Var a, Var b) {
  DispatchFixture *left = a.pointer(), *right = b.pointer();
  if (left.value == right.value) return 0;
  return left.value < right.value ? -1 : 1;
}

static int dispatch_fixture_truth(Var value) {
  dispatch_truth_calls++;
  DispatchFixture *fixture = value.pointer();
  return fixture && fixture.value != 0;
}

static int dispatch_fixture_false(Var value) {
  (void)value;
  return 0;
}

static int dispatch_fixture_next(Iter iter, Var *out) {
  if (iter.state.int() == 0) return 0;
  iter.state = 0;
  *out = iter.obj;
  return 1;
}

static Iter dispatch_fixture_iter(Var value, Iter dest) {
  return Iter.init(dest, value, dispatch_fixture_next, 1);
}


static void expect_stream_repr(Var value) {
  Buffer out = Buffer.new(0);
  value.write_repr(out);
  EXPECT_STR_EQ(out.str_free(), value.repr());
}


static void var_integer_construction(void) {
  Var vi = 123, vu = (unsigned short)65535, neg = -42;
  EXPECT_TRUE(Var.tag(vi) == <i32>);
  EXPECT_TRUE(Var.kind(vi) == <integer>);
  EXPECT_TRUE(Var.is_integer(vi));
  EXPECT_INT_EQ(Var.integer(vi), 123);
  EXPECT_INT_EQ(Var.int(vi), 123);
  EXPECT_INT_EQ(Var.integer(vu), 65535);
  EXPECT_INT_EQ(Var.ushort(vu), 65535);
  EXPECT_INT_EQ(Var.integer(neg), -42);
}

static void var_floating_construction(void) {
  double high = 3.5;
  Var vf = high;
  float low = 1.25f;
  Var f32 = low;
  EXPECT_TRUE(Var.tag(vf) == <f64>);
  EXPECT_TRUE(Var.kind(vf) == <floating>);
  EXPECT_DOUBLE_NEAR("Var.floating(vf)", Var.floating(vf), 3.5, 1e-9);
  EXPECT_DOUBLE_NEAR("Var.double(vf)", Var.double(vf), 3.5, 1e-9);
  EXPECT_DOUBLE_NEAR("Var.floating(f32)", Var.floating(f32), 1.25, 1e-6);
}

static void var_terminal_and_f64_escape(void) {
  Var negative_max = Var.new(<f64>, -DBL_MAX);
  Var positive_max = Var.new(<f64>, DBL_MAX);

  EXPECT_TRUE(VAR_NULL_BITS == 0ul);
  EXPECT_TRUE(VAR_VOID_BITS == ~0ul);
  EXPECT_TRUE(void.u64 == VAR_VOID_BITS);
  EXPECT_TRUE(void is void);
  EXPECT_TRUE(void.kind() == <void>);
  EXPECT_TRUE(negative_max.u64 == 0x8003000400000000ul);
  EXPECT_TRUE(negative_max is <f64>);
  EXPECT_FALSE(negative_max is void);
  EXPECT_TRUE(negative_max.floating() == -DBL_MAX);
  EXPECT_TRUE(positive_max.floating() == DBL_MAX);
}


static void var_construction_and_void_dispatch_transfer(void) {
  Symbol unsupported = Symbol.new("unsupported");
  int caught = 0;

  try Var.new(unsupported, NULL);
  catch %(bad-target *): caught++;
  try Var.new(<u8>, 256);
  catch %(conv-range *): caught++;
  try Var.new(<symbol>, 1ul << 51);
  catch %(conv-range *): caught++;
  try Var.new(<array>, NULL);
  catch %(bad-arg *): caught++;
  Symbol custom = Symbol.new("misaligned");
  EXPECT_TRUE(Var.register_object_tag(custom) >= 0);
  VarMethods methods = {0};
  EXPECT_TRUE(x2c_try_register_tagged_descriptor(
    custom, %"Example.FullQualifiedClass", methods));
  x2c_register_tagged_descriptor(
    custom, %"Example.FullQualifiedClass", methods);
  EXPECT_FALSE(x2c_try_register_descriptor(
    %"Example.FullQualifiedClass", methods));
  unsigned char bytes[16], *misaligned = bytes;
  while (((uintptr_t) misaligned & 0x7) == 0) misaligned++;
  try Var.new(custom, misaligned);
  catch %(bad-enc *): caught++;

  try void.hash();
  catch %(void-op *): caught++;
  try void.compare(1);
  catch %(void-op *): caught++;
  struct Iter storage;
  try void.iter(&storage);
  catch %(void-op *): caught++;
  EXPECT_INT_EQ(caught, 8);
}

static void var_void_equality_and_rendering(void) {
  Var absent = void, one = 1;

  EXPECT_TRUE(absent.equal(void));
  EXPECT_TRUE(absent.fallback_equal(void));
  EXPECT_TRUE(absent.same(void));
  EXPECT_FALSE(absent.equal(one));
  EXPECT_FALSE(one.equal(absent));
  EXPECT_FALSE(absent.fallback_equal(one));
  EXPECT_FALSE(one.fallback_equal(absent));
  EXPECT_FALSE(absent.same(one));
  EXPECT_FALSE(one.same(absent));

  EXPECT_TRUE(absent == void);
  EXPECT_FALSE(absent != void);
  EXPECT_TRUE(absent === void);
  EXPECT_FALSE(absent !== void);
  EXPECT_FALSE(absent == one);
  EXPECT_TRUE(absent != one);
  EXPECT_FALSE(absent === one);
  EXPECT_TRUE(absent !== one);

  EXPECT_TRUE(Var.binary(absent, <==>, void).int());
  EXPECT_FALSE(Var.binary(absent, <!=>, void).int());
  EXPECT_TRUE(Var.binary(absent, <===>, void).int());
  EXPECT_FALSE(Var.binary(absent, <!==>, void).int());
  EXPECT_FALSE(Var.binary(absent, <==>, one).int());
  EXPECT_TRUE(Var.binary(absent, <!=>, one).int());
  EXPECT_FALSE(Var.binary(absent, <===>, one).int());
  EXPECT_TRUE(Var.binary(absent, <!==>, one).int());
  EXPECT_FALSE(Var.binary(one, <==>, absent).int());
  EXPECT_TRUE(Var.binary(one, <!=>, absent).int());
  EXPECT_FALSE(Var.binary(one, <===>, absent).int());
  EXPECT_TRUE(Var.binary(one, <!==>, absent).int());

  EXPECT_STR_EQ(absent.str(), "void");
  EXPECT_STR_EQ(absent.repr(), "void");
  Buffer display = Buffer.new(0), readable = Buffer.new(0);
  absent.write_str(display);
  absent.write_repr(readable);
  EXPECT_STR_EQ(display.str_free(), "void");
  EXPECT_STR_EQ(readable.str_free(), "void");
}

static void var_typed_empty_representation(void) {
  String empty_string = NULL;
  List empty_list = NULL;
  Var string_var = empty_string;
  Var list_var = empty_list;
  Var signed_zero = Var.new(<i8>, 0);
  Var unsigned_zero = Var.new(<u8>, 0);

  EXPECT_TRUE(string_var is <string>);
  EXPECT_TRUE(list_var is <list>);
  EXPECT_NULL(string_var.string());
  EXPECT_NULL(list_var.list());
  EXPECT_TRUE(string_var.repr() == %"\"\"");
  EXPECT_TRUE(string_var.u64 != list_var.u64);
  EXPECT_TRUE(string_var.hash() != 0);
  EXPECT_TRUE(list_var.hash() != 0);
  EXPECT_TRUE(signed_zero.u64 != unsigned_zero.u64);
  EXPECT_TRUE(signed_zero.hash() != 0);
  EXPECT_TRUE(unsigned_zero.hash() != 0);
}

static void var_mutable_container_roundtrip(void) {
  $test.scoped();
  Array array = %[];
  Map map = %{};
  Var array_var = array, map_var = map;

  EXPECT_TRUE(array_var is <array>);
  EXPECT_TRUE(map_var is <map>);
  EXPECT_PTR_EQ(array_var.array(), array);
  EXPECT_PTR_EQ(map_var.map(), map);
  EXPECT_NOT_NULL(array_var.array());
  EXPECT_NOT_NULL(map_var.map());
  array_var.array().push(7);
  map_var.map()[<key>] = 9;
  EXPECT_INT_EQ(array.len(), 1);
  EXPECT_INT_EQ(array[0].int(), 7);
  EXPECT_INT_EQ(map.len(), 1);
  EXPECT_INT_EQ(map[<key>].int(), 9);
}

static void var_pointer_and_object(void) {
  String text = %"hello";
  Var vstr = text, raw = (void *) text;
  String *slot = &text;
  Var ref = slot;
  int roundtrip_len = (*(&text)).len();
  EXPECT_PTR_EQ(Var.pointer(vstr), text);
  EXPECT_TRUE(Var.kind(vstr) == <object>);
  EXPECT_TRUE(raw.kind() == <pointer>);
  EXPECT_TRUE(ref.kind() == <reference>);
  EXPECT_TRUE(Var.is_object(vstr));
  EXPECT_TRUE(Var.is_reference(ref));
  EXPECT_INT_EQ(roundtrip_len, 5);
}

static void var_symbol_handling(void) {
  Symbol sym = <alpha>;
  Var vsym = sym, expected = sym;
  EXPECT_TRUE(Var.tag(vsym) == <symbol>);
  EXPECT_TRUE(vsym.kind() == <symbol>);
  EXPECT_INT_EQ(Var.integer(vsym), sym);
  EXPECT_TRUE(Var.symbol(vsym) == sym);
  EXPECT_TRUE(Var.equal(vsym, expected));
}

static void var_equality_and_hash(void) {
  Var a = 17, b = 17, c = 18;
  unsigned ha = Var.hash(a), hb = Var.hash(b);
  EXPECT_TRUE(Var.equal(a, b));
  EXPECT_TRUE(!Var.equal(a, c));
  EXPECT_TRUE(ha == hb);
  EXPECT_TRUE(ha != 0);
}

static void var_helper_accessors(void) {
  Var vchar = 'A';
  Var vshort = (short)32000;
  Var vuint = (unsigned)4100;
  Var vf = 9.0;
  Var coerced = 11L;
  Var copy = vshort;
  EXPECT_INT_EQ(Var.char(vchar), 'A');
  EXPECT_INT_EQ(Var.short(vshort), 32000);
  EXPECT_INT_EQ(Var.uint(vuint), 4100u);
  EXPECT_TRUE(copy.u64 == vshort.u64);
  EXPECT_TRUE(Var.tag(coerced) == <long>);
  EXPECT_TRUE(coerced.long() == 11L);
  EXPECT_DOUBLE_NEAR("Var.double(vf)", Var.double(vf), 9.0, 1e-9);
}

/* A Var argument unboxes at a math.h call through the prelude prototype. */
static void var_unboxes_at_math_call(void) {
  Var ratio = 2.5;
  EXPECT_DOUBLE_NEAR("sin(ratio)", sin(ratio), sin(2.5), 1e-12);
  EXPECT_DOUBLE_NEAR("pow(ratio, 2)", pow(ratio, 2), 6.25, 1e-12);
}

static void var_scalar_reader_conversion(void) {
  $test.scoped();
  // the reported crossing: a char box read through int() and double()
  Var letter = 'n';
  EXPECT_INT_EQ(letter.int(), 110);
  EXPECT_TRUE(letter.double() == 110.0);

  // every integer-named reader from a floating source agrees with
  // explicit Var.convert plus the raw payload reader for its target
  Var negative = -3.75, positive = 200.5;
  EXPECT_INT_EQ(negative.char(), (char) negative.convert(<i8>).integer());
  EXPECT_INT_EQ(positive.uchar(), (uchar) positive.convert(<u8>).integer());
  EXPECT_INT_EQ(negative.short(), (short) negative.convert(<i16>).integer());
  EXPECT_INT_EQ(positive.ushort(),
                (ushort) positive.convert(<u16>).integer());
  EXPECT_INT_EQ(negative.int(), (int) negative.convert(<i32>).integer());
  EXPECT_TRUE(positive.uint() == (uint) positive.convert(<u32>).integer());
  EXPECT_TRUE(positive.unsigned() ==
              (unsigned) positive.convert(<u32>).integer());
  EXPECT_TRUE(negative.long() == negative.convert(<long>).long_value());
  EXPECT_TRUE(positive.ulong() == positive.convert(<ulong>).ulong_value());
  EXPECT_TRUE(negative.long_long() ==
              negative.convert(<llong>).long_long_value());
  EXPECT_TRUE(positive.ulong_long() ==
              positive.convert(<ullong>).ulong_long_value());

  // every floating-named reader from an integer source
  Var count = 42, wide = Var.box_long(1L << 40);
  EXPECT_TRUE(count.float() == (float) count.convert(<f32>).floating());
  EXPECT_TRUE(count.double() == count.convert(<f64>).floating());
  EXPECT_TRUE(count.long_double() ==
              count.convert(<ldouble>).long_double_value());
  EXPECT_TRUE(wide.double() == wide.convert(<f64>).floating());

  // retained direct branches agree with Var.convert at their signed,
  // unsigned, and width boundaries
  Var u8max = Var.new(<u8>, 255);
  EXPECT_INT_EQ(u8max.char(), (char) u8max.convert(<i8>).integer());
  Var u32max = Var.new(<u32>, UINT_MAX);
  EXPECT_TRUE(u32max.long() == u32max.convert(<long>).long_value());
  Var u48top = Var.new(<u48>, (1ul << 48) - 1);
  EXPECT_TRUE(u48top.ulong() == u48top.convert(<ulong>).ulong_value());
  Var u64max = Var.box_ulong(ULONG_MAX);
  EXPECT_TRUE(u64max.long_long() == u64max.convert(<llong>).long_long_value());
  Var f32val = Var.new(<f32>, (double) 1.25f);
  EXPECT_TRUE(f32val.long_double() ==
              f32val.convert(<ldouble>).long_double_value());

  // a nonnumeric source and an unrepresentable floating-to-integer
  // reader raise the existing conversion causes
  int caught = 0;
  Var text = %"text";
  try text.int();
  catch %(no-convert *): caught++;
  try text.double();
  catch %(no-convert *): caught++;
  Var nan = Var.new(<f64>, 0.0 / 0.0);
  try nan.int();
  catch %(conv-range *): caught++;
  Var huge = 4.0e9;
  try huge.int();
  catch %(conv-range *): caught++;
  EXPECT_INT_EQ(caught, 4);
}

static void var_compare_numeric_total_order(void) {
  Var small = Var.new(<i8>, 1);
  Var wide = Var.new(<i48>, 1L);
  Var dbl = 1.0;
  Var neg_wide = Var.new(<i48>, (long) -1);
  Var zero = 0;
  Var neginf = -1.0 / 0.0;
  Var posinf = 1.0 / 0.0;
  Var nan = 0.0 / 0.0;

  EXPECT_TRUE(Var.tag(neginf) == <-inf>);
  EXPECT_TRUE(Var.tag(posinf) == <+inf>);
  EXPECT_TRUE(Var.tag(nan) == <nan>);
  EXPECT_INT_EQ(Var.integer(neg_wide), -1);

  EXPECT_TRUE(Var.compare(dbl, wide) < 0);
  EXPECT_TRUE(Var.compare(wide, small) < 0);

  EXPECT_TRUE(Var.compare(neginf, zero) < 0);
  EXPECT_TRUE(Var.compare(zero, posinf) < 0);
  EXPECT_TRUE(Var.compare(posinf, nan) < 0);

}

static void var_compare_cross_type_groups(void) {
  $test.scoped();
  Var number = 1, sym = <alpha>, str = %"alpha";
  Array arr = %[];
  arr.push(1);
  List lst = %(1);

  EXPECT_TRUE(Var.compare(number, sym) < 0);
  EXPECT_TRUE(Var.compare(sym, str) < 0);
  EXPECT_TRUE(Var.compare(str, arr) < 0);
  EXPECT_TRUE(Var.compare(arr, lst) < 0);

  Array a = %[];
  a.push(1); a.push(2);
  Array b = %[];
  b.push(1); b.push(3);
  EXPECT_TRUE(Var.compare(a, b) < 0);
  EXPECT_TRUE(Var.compare(b, a) > 0);

  List la = %(1 2), lb = %(1 3);
  EXPECT_TRUE(Var.compare(la, lb) < 0);
  EXPECT_TRUE(Var.compare(lb, la) > 0);

}

static void var_equality_and_identity_operators(void) {
  $test.scoped();

  Array a = %[];
  a.push(1);
  a.push(2);
  Array b = a.copy();

  Var va = a, vb = b;

  EXPECT_TRUE(va == vb);
  EXPECT_TRUE(Var.equal(va, vb));
  EXPECT_INT_EQ(Var.compare(va, vb), 0);
  EXPECT_FALSE(Var.same(va, vb));
  EXPECT_FALSE(va === vb);
  EXPECT_TRUE(va !== vb);
  EXPECT_TRUE(va === a);
  EXPECT_FALSE(vb === a);
  EXPECT_TRUE(a === va);
  EXPECT_FALSE(a === vb);
  EXPECT_TRUE(a !== vb);
  EXPECT_FALSE(a === b);
  EXPECT_TRUE(a !== b);

  int x = 3, y = 3, z = 4;
  EXPECT_TRUE(x === y);
  EXPECT_FALSE(x === z);
  EXPECT_TRUE(x !== z);

}

static void var_comparison_operators(void) {
  $test.scoped();

  Var v = 10, w = 20;

  EXPECT_TRUE(v == 10);
  EXPECT_FALSE(v == 11);
  EXPECT_TRUE(v != 11);
  EXPECT_FALSE(v != 10);
  EXPECT_TRUE(10 == v);
  EXPECT_FALSE(11 == v);
  EXPECT_TRUE(11 != v);
  EXPECT_FALSE(10 != v);

  EXPECT_TRUE(v < 11);
  EXPECT_TRUE(v <= 10);
  EXPECT_TRUE(v <= 11);
  EXPECT_TRUE(v > 9);
  EXPECT_TRUE(v >= 10);
  EXPECT_TRUE(v >= 9);
  EXPECT_TRUE(v < w);
  EXPECT_TRUE(w > v);
  EXPECT_TRUE(9 < v);
  EXPECT_TRUE(10 <= v);
  EXPECT_TRUE(11 > v);
  EXPECT_TRUE(10 >= v);

  Var sa = %"a", sb = %"b";
  EXPECT_TRUE(sa < sb);
  EXPECT_TRUE(sb > sa);

  Array a = %[1, 2], b = %[1, 3];
  Var va = a, vb = b;
  EXPECT_TRUE(va < vb);

  Array c = %[1, 2];
  Var vc = c;
  EXPECT_TRUE(va == vc);
  EXPECT_FALSE(va != vc);
  EXPECT_INT_EQ(Var.compare(va, vc), 0);
  EXPECT_FALSE(va === vc);
  EXPECT_TRUE(va !== vc);
  EXPECT_TRUE(va === a);
  EXPECT_FALSE(vc === a);

  EXPECT_TRUE(v === 10);
  EXPECT_FALSE(v === 11);
  EXPECT_TRUE(10 === v);
  EXPECT_FALSE(11 === v);
  EXPECT_TRUE(11 !== v);

}

static void var_compare_strict_encodings(void) {
  Var u = Var.new(<u8>, 1), i = Var.new(<i8>, 1);
  EXPECT_FALSE(Var.equal(u, i));
  EXPECT_TRUE(Var.compare(u, i) != 0);
  EXPECT_INT_EQ(Var.compare(u, i), -Var.compare(i, u));

  Var zp = Var.new(<f64>, 0.0);
  double negzero = -0.0;
  Var zn = Var.new(<f64>, negzero);
  EXPECT_FALSE(Var.equal(zp, zn));
  EXPECT_TRUE(Var.compare(zp, zn) != 0);
  EXPECT_INT_EQ(Var.compare(zp, zn), -Var.compare(zn, zp));

}

static void var_unsigned_char_accessor(void) {
  Var value = Var.new(<u8>, 255);
  EXPECT_INT_EQ(value.uchar(), 255);
}

static void var_source_conversion_matrix(void) {
  $test.scoped();

  char i8 = 'A';
  uchar u8 = UCHAR_MAX;
  short i16 = SHRT_MIN;
  ushort u16 = USHRT_MAX;
  int i32 = INT_MIN;
  uint u32 = UINT_MAX;
  float f32 = 1.25f;
  double f64 = -3.5;
  Symbol symbol = <matrix>;
  String string = %"matrix";
  List list = %(1 2);

  Var vi8 = i8, vu8 = u8, vi16 = i16, vu16 = u16;
  Var vi32 = i32, vu32 = u32, vf32 = f32, vf64 = f64;
  Var vsymbol = symbol, vstring = string, vlist = list;

  EXPECT_TRUE(vi8 is <i8>);
  EXPECT_INT_EQ(vi8.char(), i8);
  EXPECT_TRUE(vu8 is <u8>);
  EXPECT_INT_EQ(vu8.uchar(), u8);
  EXPECT_TRUE(vi16 is <i16>);
  EXPECT_INT_EQ(vi16.short(), i16);
  EXPECT_TRUE(vu16 is <u16>);
  EXPECT_INT_EQ(vu16.ushort(), u16);
  EXPECT_TRUE(vi32 is <i32>);
  EXPECT_INT_EQ(vi32.int(), i32);
  EXPECT_TRUE(vu32 is <u32>);
  EXPECT_TRUE(vu32.uint() == u32);
  EXPECT_TRUE(vf32 is <f32>);
  EXPECT_DOUBLE_NEAR("vf32.floating()", vf32.floating(), f32, 1e-6);
  EXPECT_TRUE(vf64 is <f64>);
  EXPECT_DOUBLE_NEAR("vf64.floating()", vf64.floating(), f64, 1e-9);
  EXPECT_TRUE(vsymbol is <symbol>);
  EXPECT_TRUE(vsymbol.symbol() == symbol);
  EXPECT_TRUE(vstring is <string>);
  EXPECT_PTR_EQ(vstring.string(), string);
  EXPECT_TRUE(vlist is <list>);
  EXPECT_PTR_EQ(vlist.list(), list);

}

static void var_byte_pointer_roundtrips(void) {
  unsigned char bytes[16] = {0};
  for (int i = 0; i < 8; i++) {
    void *raw = bytes + i;
    signed char *signed_bytes = (signed char *) raw;
    unsigned char *unsigned_bytes = (unsigned char *) raw;
    Var vraw = raw, vsigned = signed_bytes, vunsigned = unsigned_bytes;

    EXPECT_TRUE(vraw is <p48>);
    EXPECT_PTR_EQ(vraw.pointer(), raw);
    EXPECT_TRUE(vsigned is <i8*>);
    EXPECT_PTR_EQ(vsigned.pointer(), signed_bytes);
    EXPECT_TRUE(vunsigned is <u8*>);
    EXPECT_PTR_EQ(vunsigned.pointer(), unsigned_bytes);
  }
}

static void var_catalog_tag_roundtrips(void) {
  long slot = 0;
  void *pointer = &slot;
  Symbol symbol = <catalog>, *symbol_pointer = &symbol;
  Var context = Var.new(<context>, pointer);
  Var context_pointer = Var.new(<context*>, &pointer);
  Var pipe = Var.new(<pipe>, pointer);
  Var pipe_pointer = Var.new(<pipe*>, &pointer);
  Var symbol_reference = symbol_pointer;

  EXPECT_TRUE(context is <context>);
  EXPECT_PTR_EQ(context.pointer(), pointer);
  EXPECT_TRUE(context_pointer is <context*>);
  EXPECT_PTR_EQ(context_pointer.pointer(), &pointer);
  EXPECT_TRUE(pipe is <pipe>);
  EXPECT_PTR_EQ(pipe.pointer(), pointer);
  EXPECT_TRUE(pipe_pointer is <pipe*>);
  EXPECT_PTR_EQ(pipe_pointer.pointer(), &pointer);
  EXPECT_TRUE(symbol_reference is <symbol*>);
  EXPECT_PTR_EQ(symbol_reference.pointer(), symbol_pointer);
  EXPECT_TRUE(Var.known_tag(<context>));
  EXPECT_FALSE(Var.known_tag(<clock>));
  EXPECT_FALSE(Var.known_tag(<defer>));
  EXPECT_FALSE(Var.known_tag(<module>));
  EXPECT_FALSE(Var.known_tag(<not-a-buil>));
}

static void var_explicit_i48_boundaries(void) {
  long minimum = -(1L << 47), maximum = (1L << 47) - 1;
  unsigned long unsigned_maximum = (1UL << 48) - 1;
  Var vminimum = Var.new(<i48>, minimum);
  Var vmaximum = Var.new(<i48>, maximum);
  Var vunsigned = Var.new(<u48>, unsigned_maximum);

  EXPECT_TRUE(vminimum is <i48>);
  EXPECT_TRUE(vminimum.integer() == minimum);
  EXPECT_TRUE(vmaximum is <i48>);
  EXPECT_TRUE(vmaximum.integer() == maximum);
  EXPECT_TRUE(vunsigned is <u48>);
  EXPECT_TRUE((unsigned long)vunsigned.integer() == unsigned_maximum);
}

static void var_numeric_parse_is_exact(void) {
  Var integer_zero = Var.parse(%"0", <int>);
  Var floating_zero = Var.parse(%"0", <double>);
  Var integer = Var.parse(%"  2147483647  ", <int>);
  Var floating = Var.parse(%"  1.25  ", <float>);

  EXPECT_TRUE(integer_zero is <i32>);
  EXPECT_INT_EQ(integer_zero.int(), 0);
  EXPECT_TRUE(floating_zero is <f64>);
  EXPECT_TRUE(floating_zero.floating() == 0.0);
  EXPECT_TRUE(integer is <i32>);
  EXPECT_INT_EQ(integer.int(), INT_MAX);
  EXPECT_TRUE(floating is <f64>);
  EXPECT_DOUBLE_NEAR("floating.floating()", floating.floating(), 1.25, 1e-9);
  EXPECT_TRUE(Var.parse(%"", <int>) is void);
  EXPECT_TRUE(Var.parse(%"   ", <double>) is void);
  EXPECT_TRUE(Var.parse(%"nope", <int>) is void);
  EXPECT_TRUE(Var.parse(%"42junk", <int>) is void);
  EXPECT_TRUE(Var.parse(%"1.5junk", <double>) is void);
  EXPECT_TRUE(Var.parse(%"2147483648", <int>) is void);
  EXPECT_TRUE(Var.parse(%"-2147483649", <int>) is void);
  EXPECT_TRUE(Var.parse(%"1e400", <double>) is void);
  EXPECT_TRUE(Var.parse(%"1e-400", <float>) is void);
}


static void var_wide_scalar_roundtrips(void) {
  $test.scoped();
  Var long_min = Var.box_long(LONG_MIN);
  Var long_max = Var.box_long(LONG_MAX);
  Var ulong_max = Var.box_ulong(ULONG_MAX);
  Var long_long_min = Var.box_long_long(LLONG_MIN);
  Var long_long_max = Var.box_long_long(LLONG_MAX);
  Var ulong_long_max = Var.box_ulong_long(ULLONG_MAX);
  Var long_double_value = Var.box_long_double(1.25L);

  EXPECT_TRUE(long_min is <long>);
  EXPECT_TRUE(long_min.kind() == <integer>);
  EXPECT_TRUE(long_min.long_value() == LONG_MIN);
  EXPECT_TRUE(long_max.long_value() == LONG_MAX);
  EXPECT_TRUE(ulong_max is <ulong>);
  EXPECT_TRUE(ulong_max.ulong_value() == ULONG_MAX);
  EXPECT_TRUE(long_long_min is <llong>);
  EXPECT_TRUE(long_long_min.long_long_value() == LLONG_MIN);
  EXPECT_TRUE(long_long_max.long_long_value() == LLONG_MAX);
  EXPECT_TRUE(ulong_long_max is <ullong>);
  EXPECT_TRUE(ulong_long_max.ulong_long_value() == ULLONG_MAX);
  EXPECT_TRUE(long_double_value is <ldouble>);
  EXPECT_TRUE(long_double_value.kind() == <floating>);
  EXPECT_TRUE(long_double_value.long_double_value() == 1.25L);
  EXPECT_STR_EQ(Var.box_long(-5).str(), "-5");
  EXPECT_STR_EQ(Var.box_ulong(5).str(), "5");
  EXPECT_STR_EQ(Var.box_long_long(-6).str(), "-6");
  EXPECT_STR_EQ(Var.box_ulong_long(6).str(), "6");
  EXPECT_STR_EQ(long_double_value.str(), "1.250000");
  EXPECT_INT_EQ(sizeof(Var), 8);
}


static void var_native_numeric_names(void) {
  $test.scoped();
  Var values[] = { 1L, 2UL, 3LL, 4ULL, 1.25L };
  Symbol tags[] = { <long>, <ulong>, <llong>, <ullong>, <ldouble> };
  for (int i = 0; i < 5; i++) {
    EXPECT_TRUE(values[i] is tags[i]);
    EXPECT_TRUE(Var.known_tag(tags[i]));
    EXPECT_TRUE(values[i].convert(tags[i]) === values[i]);
  }

  long signed_long = 1, *long_pointer = &signed_long;
  unsigned long unsigned_long = 2, *ulong_pointer = &unsigned_long;
  long long signed_long_long = 3, *llong_pointer = &signed_long_long;
  unsigned long long unsigned_long_long = 4;
  unsigned long long *ullong_pointer = &unsigned_long_long;
  long double floating_long = 1.25L, *ldouble_pointer = &floating_long;
  Var pointers[] = {
    long_pointer, &long_pointer, ulong_pointer, &ulong_pointer,
    llong_pointer, &llong_pointer, ullong_pointer, &ullong_pointer,
    ldouble_pointer, &ldouble_pointer
  };
  Symbol pointer_tags[] = {
    <long*>, <long**>, <ulong*>, <ulong**>, <llong*>, <llong**>,
    <ullong*>, <ullong**>, <ldouble*>, <ldouble**>
  };
  void *addresses[] = {
    long_pointer, &long_pointer, ulong_pointer, &ulong_pointer,
    llong_pointer, &llong_pointer, ullong_pointer, &ullong_pointer,
    ldouble_pointer, &ldouble_pointer
  };
  for (int i = 0; i < 10; i++) {
    EXPECT_TRUE(pointers[i] is pointer_tags[i]);
    EXPECT_TRUE(Var.known_tag(pointer_tags[i]));
    EXPECT_PTR_EQ(pointers[i].pointer(), addresses[i]);
  }

  Symbol former[] = {
    <i64>, <u64>, <i128>, <u128>, <f128>, <i64*>, <i64**>,
    <u64*>, <u64**>, <i128*>, <i128**>, <u128*>, <u128**>,
    <f128*>, <f128**>
  };
  int rejected = 0;
  for (int i = 0; i < 15; i++) {
    Symbol tag = former[i];
    EXPECT_FALSE(Var.known_tag(tag));
    EXPECT_TRUE(Symbol.new(tag.str()) == tag);
    try values[0].convert(tag);
    catch %(bad-target *): rejected++;
  }
  EXPECT_INT_EQ(rejected, 15);
}


/* The collector skips angle includes, so system typedefs reach the
   compiler with no declaration behind them.  The seeded LP64 widths are
   what let each of these box and unbox by value; without them the box
   direction is rejected and the unbox direction silently reads the
   pointer payload.

   Every seed is pinned here, and pinned twice, because a wrong seed is
   silent rather than loud: both directions consult the same entry, so a
   mis-seeded width is self-consistent and truncates with no compiler
   diagnostic and no C warning.  The tag assertion catches a seed that is
   too wide or the wrong signedness; the value is chosen so it cannot
   survive the next narrower tag, which catches a seed that is too
   narrow.  int8_t and uint8_t have nothing below them, so there the tag
   assertion carries the check alone.

   Spelled out rather than driven by a macro: the conversions under test
   are x2c-level, and a macro body only reaches the C preprocessor after
   x2c has already run, so the boxing would never be compiled. */
static void var_system_typedef_roundtrips(void) {
  $test.scoped();
  // 64-bit unsigned seeds: 2^32 and up, so a u32 seed would truncate.
  size_t size_in = 4294967297UL;
  Var size_var = size_in;
  size_t size_out = size_var;
  EXPECT_TRUE(size_var is <ulong>);
  EXPECT_TRUE(size_out == size_in);

  uintptr_t uptr_in = 18446744073709551615UL;
  Var uptr_var = uptr_in;
  uintptr_t uptr_out = uptr_var;
  EXPECT_TRUE(uptr_var is <ulong>);
  EXPECT_TRUE(uptr_out == uptr_in);

  uint64_t u64_in = 9223372036854775809UL;
  Var u64_var = u64_in;
  uint64_t u64_out = u64_var;
  EXPECT_TRUE(u64_var is <ulong>);
  EXPECT_TRUE(u64_out == u64_in);

  // 64-bit signed seeds: negative and past 2^32, so an unsigned seed
  // and an i32 seed both show.
  ssize_t ssize_in = -9007199254740993L;
  Var ssize_var = ssize_in;
  ssize_t ssize_out = ssize_var;
  EXPECT_TRUE(ssize_var is <long>);
  EXPECT_TRUE(ssize_out == ssize_in);

  ptrdiff_t diff_in = -4503599627370497L;
  Var diff_var = diff_in;
  ptrdiff_t diff_out = diff_var;
  EXPECT_TRUE(diff_var is <long>);
  EXPECT_TRUE(diff_out == diff_in);

  intptr_t iptr_in = -2251799813685249L;
  Var iptr_var = iptr_in;
  intptr_t iptr_out = iptr_var;
  EXPECT_TRUE(iptr_var is <long>);
  EXPECT_TRUE(iptr_out == iptr_in);

  int64_t i64_in = -9223372036854775807L;
  Var i64_var = i64_in;
  int64_t i64_out = i64_var;
  EXPECT_TRUE(i64_var is <long>);
  EXPECT_TRUE(i64_out == i64_in);

  off_t off_in = -1099511627777L;
  Var off_var = off_in;
  off_t off_out = off_var;
  EXPECT_TRUE(off_var is <long>);
  EXPECT_TRUE(off_out == off_in);

  time_t time_in = -68719476737L;
  Var time_var = time_in;
  time_t time_out = time_var;
  EXPECT_TRUE(time_var is <long>);
  EXPECT_TRUE(time_out == time_in);

  // 32-bit seeds: past 2^16, so an i16/u16 seed would truncate.
  int32_t i32_in = -2147483647;
  Var i32_var = i32_in;
  int32_t i32_out = i32_var;
  EXPECT_TRUE(i32_var is <i32>);
  EXPECT_TRUE(i32_out == i32_in);

  wchar_t wide_in = 1114111;
  Var wide_var = wide_in;
  wchar_t wide_out = wide_var;
  EXPECT_TRUE(wide_var is <i32>);
  EXPECT_TRUE(wide_out == wide_in);

  uint32_t u32_in = 4294967295U;
  Var u32_var = u32_in;
  uint32_t u32_out = u32_var;
  EXPECT_TRUE(u32_var is <u32>);
  EXPECT_TRUE(u32_out == u32_in);

  // 16-bit seeds: past 2^8, so an i8/u8 seed would truncate.
  int16_t i16_in = -32768;
  Var i16_var = i16_in;
  int16_t i16_out = i16_var;
  EXPECT_TRUE(i16_var is <i16>);
  EXPECT_TRUE(i16_out == i16_in);

  uint16_t u16_in = 65535;
  Var u16_var = u16_in;
  uint16_t u16_out = u16_var;
  EXPECT_TRUE(u16_var is <u16>);
  EXPECT_TRUE(u16_out == u16_in);

  // 8-bit seeds: nothing narrower exists, so the tag carries the check.
  int8_t i8_in = -128;
  Var i8_var = i8_in;
  int8_t i8_out = i8_var;
  EXPECT_TRUE(i8_var is <i8>);
  EXPECT_TRUE(i8_out == i8_in);

  uint8_t u8_in = 255;
  Var u8_var = u8_in;
  uint8_t u8_out = u8_var;
  EXPECT_TRUE(u8_var is <u8>);
  EXPECT_TRUE(u8_out == u8_in);

  /* Var.uint reads the u32 box directly.  The scalar readers follow
     Var.convert for every other numeric tag, so Var.int narrows the same
     u32 payload instead of reading zero (lib/common.x). */
  uint32_t narrow = 7;
  Var narrow_var = narrow;
  EXPECT_INT_EQ(narrow_var.uint(), 7);
  EXPECT_INT_EQ(narrow_var.int(), 7);
  EXPECT_INT_EQ(narrow_var.long(), 7);
}


static void var_wide_value_semantics(void) {
  $test.scoped();
  long precise = 9007199254740993L;
  Var first = Var.box_long(precise);
  Var same_value = Var.box_long(precise);
  Var adjacent = Var.box_long(precise + 1);
  Var negative = Var.box_long_long(-1);
  Var unsigned_value = Var.box_ulong_long(ULLONG_MAX);
  Var first_float = Var.box_long_double(1.25L);
  Var same_float = Var.box_long_double(1.25L);
  Var wide_infinity = Var.box_long_double(1.0L / 0.0L);
  Var wide_nan = Var.box_long_double(0.0L / 0.0L);

  EXPECT_FALSE(first === same_value);
  EXPECT_TRUE(first == same_value);
  EXPECT_TRUE(first.hash() != 0);
  EXPECT_INT_EQ(first.hash(), same_value.hash());
  EXPECT_INT_EQ(first.compare(same_value), 0);
  EXPECT_TRUE(first < adjacent);
  EXPECT_TRUE(adjacent > first);
  EXPECT_TRUE(negative < unsigned_value);
  EXPECT_FALSE(first_float === same_float);
  EXPECT_TRUE(first_float == same_float);
  EXPECT_INT_EQ(first_float.hash(), same_float.hash());
  EXPECT_INT_EQ(first_float.compare(same_float), 0);
  EXPECT_TRUE(first_float < wide_infinity);
  EXPECT_TRUE(wide_infinity < wide_nan);
  EXPECT_TRUE(wide_nan > first_float);

  Map map = %{};
  map[first] = 73;
  EXPECT_INT_EQ(map[same_value].integer(), 73);
  EXPECT_TRUE(map[adjacent] is void);

  Var source_long = precise.var(), explicit_i48 = Var.new(<i48>, (long) 17);
  EXPECT_TRUE(source_long is <long>);
  EXPECT_TRUE(source_long.long_value() == precise);
  EXPECT_TRUE(explicit_i48 is <i48>);
  EXPECT_TRUE(explicit_i48.integer() == 17);
}


static void var_streaming_repr_matches_canonical(void) {
  $test.scoped();
  List list = %(alpha 17 "line\ntext");
  Array array = %[ 1, "two", $list ];
  Map map = %{ key: $array, empty: "" };
  Array simple_array = %[ 1, "two" ], empty_array = %[];
  Map simple_map = %{ key: 1 }, empty_map = %{};
  File file = tmpfile();
  int pointer_value = 0;
  EXPECT_STR_EQ(list.repr(), "(alpha 17 \"line\\ntext\")");
  EXPECT_STR_EQ(simple_array.repr(), "[ 1, \"two\" ]");
  EXPECT_STR_EQ(simple_map.repr(), "{ <key>: 1 }");
  expect_stream_repr(Var.new(<i8>, (signed char) 'A'));
  expect_stream_repr(Var.new(<u8>, (unsigned char) 'B'));
  expect_stream_repr(Var.new(<i16>, (short) -17));
  expect_stream_repr(Var.new(<u16>, (unsigned short) 65535));
  expect_stream_repr(Var.new(<i32>, -17));
  expect_stream_repr(Var.new(<u32>, (unsigned) 17));
  expect_stream_repr(Var.new(<i48>, (long) -17));
  expect_stream_repr(Var.new(<u48>, (unsigned long) 17));
  expect_stream_repr(Var.new(<f32>, (double) 1.25f));
  expect_stream_repr(Var.new(<f64>, 1.25));
  expect_stream_repr(Var.new(<f64>, -1.0 / 0.0));
  expect_stream_repr(Var.new(<f64>, 1.0 / 0.0));
  expect_stream_repr(Var.new(<f64>, 0.0 / 0.0));
  expect_stream_repr(Var.box_long(LONG_MIN));
  expect_stream_repr(Var.box_ulong(ULONG_MAX));
  expect_stream_repr(Var.box_long_long(LLONG_MIN));
  expect_stream_repr(Var.box_ulong_long(ULLONG_MAX));
  expect_stream_repr(Var.box_long_double(1.25L));
  expect_stream_repr(Var.new(<string>, %"quote\"slash\\tab\t"));
  expect_stream_repr(Var.new(<string>, NULL));
  expect_stream_repr(Var.new(<symbol>, <alpha>));
  expect_stream_repr(Var.new(<symbol>, Symbol.new("a.b")));
  expect_stream_repr(Var.new(<symbol>, 0));
  expect_stream_repr(Var.new(<list>, list));
  expect_stream_repr(Var.new(<list>, NULL));
  expect_stream_repr(Var.new(<array>, array));
  expect_stream_repr(Var.new(<array>, empty_array));
  expect_stream_repr(Var.new(<map>, map));
  expect_stream_repr(Var.new(<map>, empty_map));
  expect_stream_repr(Var.new(<file>, file));
  expect_stream_repr(Var.new(<p48>, &pointer_value));
  expect_stream_repr(Var.new(<p48>, NULL));
  expect_stream_repr(void);
  fclose(file);
  empty_array.free();
  simple_array.free();
  array.free();
}


static void var_dense_custom_dispatch(void) {
  VarMethods methods = {
    .str = dispatch_fixture_str,
    .repr = dispatch_fixture_repr,
    .hash = dispatch_fixture_hash,
    .equal = dispatch_fixture_equal,
    .compare = dispatch_fixture_compare,
    .truth = dispatch_fixture_truth,
    .iter = dispatch_fixture_iter
  };
  EXPECT_TRUE(x2c_try_register_descriptor(%"fixture", methods));
  EXPECT_TRUE(Var.known_tag(<fixture>));

  DispatchFixture first = { .value = 7 };
  DispatchFixture same = { .value = 7 };
  DispatchFixture greater = { .value = 9 };
  DispatchFixture zero = { .value = 0 };
  Var a = Var.new(<fixture>, &first);
  Var b = Var.new(<fixture>, &same);
  Var c = Var.new(<fixture>, &greater);
  Var z = Var.new(<fixture>, &zero);

  EXPECT_INT_EQ(sizeof(Var), 8);
  EXPECT_TRUE(a.tag() == <fixture>);
  EXPECT_TRUE(a.kind() == <object>);
  EXPECT_PTR_EQ(a.pointer(), &first);
  EXPECT_STR_EQ(a.str(), "custom-str");
  EXPECT_STR_EQ(a.repr(), "custom-repr");
  Buffer fallback = Buffer.new(0);
  a.write_repr(fallback);
  EXPECT_STR_EQ(fallback.str_free(), "custom-repr");

  methods.write_repr = dispatch_fixture_write_repr;
  x2c_register_descriptor(%"fixture", methods);
  Buffer streamed = Buffer.new(0);
  a.write_repr(streamed);
  EXPECT_STR_EQ(streamed.str_free(), "custom-stream-repr");

  // A descriptor with only str renders through write_str by writing the
  // returned String.
  Buffer str_fallback = Buffer.new(0);
  a.write_str(str_fallback);
  EXPECT_STR_EQ(str_fallback.str_free(), "custom-str");

  methods.write_str = dispatch_fixture_write_str;
  x2c_register_descriptor(%"fixture", methods);
  Buffer str_streamed = Buffer.new(0);
  a.write_str(str_streamed);
  EXPECT_STR_EQ(str_streamed.str_free(), "custom-stream-str");
  // write_str takes precedence over str but leaves Var.str alone.
  EXPECT_STR_EQ(a.str(), "custom-str");
  EXPECT_INT_EQ(a.hash(), 7);
  EXPECT_TRUE(z.hash() != 0);
  EXPECT_TRUE(a == b);
  EXPECT_FALSE(a == c);
  EXPECT_INT_EQ(a.compare(b), 0);
  EXPECT_TRUE(a < c);
  EXPECT_TRUE(c > a);
  EXPECT_TRUE(a.truthy());
  EXPECT_FALSE(z.truthy());
  dispatch_truth_calls = 0;
  EXPECT_FALSE(Var.binary(z, <&&>, a).truthy());
  EXPECT_INT_EQ(dispatch_truth_calls, 2);

  struct Iter storage;
  Iter items = a.iter(&storage);
  EXPECT_TRUE(items.next() === a);
  EXPECT_TRUE(items.next() is void);

  VarMethods str_replacement = {
    .str = dispatch_fixture_str_replacement
  };
  EXPECT_TRUE(x2c_try_register_descriptor(%"fixture", str_replacement));
  EXPECT_STR_EQ(a.str(), "custom-str-replaced");
  EXPECT_STR_EQ(a.repr(), "custom-repr");
  VarMethods truth_replacement = {
    .truth = dispatch_fixture_false
  };
  x2c_register_descriptor(%"fixture", truth_replacement);
  EXPECT_FALSE(a.truthy());
  EXPECT_STR_EQ(a.str(), "custom-str-replaced");
}


static void var_protocol_builtin_dispatch_is_reachable(void) {
  struct Token first_storage = {
    .text = %"same", .type = <ident>,
    .line = 1, .col = 2, .len = 4, .pos = 3
  };
  struct Token equal_storage;
  memcpy(&equal_storage, &first_storage, sizeof(first_storage));
  Token first = &first_storage, equal = &equal_storage;
  Var boxed_first = first, boxed_equal = equal;

  EXPECT_STR_EQ(boxed_first.str(), first.str());
  EXPECT_STR_EQ(boxed_first.repr(), first.repr());
  EXPECT_INT_EQ(boxed_first.hash(), first.hash());
  EXPECT_TRUE(first.equal(equal));
  EXPECT_TRUE(boxed_first.equal(boxed_equal));
  EXPECT_INT_EQ(boxed_first.compare(boxed_first), 0);
  EXPECT_TRUE(boxed_first.truth());
  expect_stream_repr(boxed_first);

  Token empty = NULL;
  Var boxed_empty = empty;
  EXPECT_FALSE(boxed_empty.truth());

  struct Iter boxed_storage;
  Iter boxed = boxed_first.iter(&boxed_storage);
  EXPECT_TRUE(boxed.next() is void);
}


static void var_builtin_dispatch_tags_match_registration(void) {
  String active[] = {
    %"array", %"block", %"buffer", %"bytes", %"file", %"iter",
    %"lambda", %"list", %"map", %"string", %"symbol", %"token"
  };
  int active_count = sizeof(active) / sizeof(active[0]);
  for (int i = 0; i < active_count; i++) {
    x2c_register_type(active[i]);
    EXPECT_TRUE(Var.known_tag(active[i]));
  }

  String reserved[] = {
    %"context", %"error", %"func", %"logger", %"mutex", %"pipe", %"proc",
    %"regexp", %"rope", %"scope", %"slice", %"socket", %"stream",
    %"tensor", %"thread", %"var"
  };
  int reserved_count = sizeof(reserved) / sizeof(reserved[0]);
  for (int i = 0; i < reserved_count; i++) {
    EXPECT_TRUE(Var.known_tag(reserved[i]));
    x2c_register_type(reserved[i]);
    EXPECT_TRUE(Var.known_tag(reserved[i]));
    EXPECT_INT_EQ(Var.register_object_tag(reserved[i]), -1);
  }
}


static void var_clone_wide_copies_wide_boxes(void) {
  $test.scoped();
  long precise = 9007199254740993L;
  Var source = Var.box_long(precise), clone = source.clone_wide();

  EXPECT_FALSE(clone is void);
  EXPECT_TRUE(clone is <long>);
  EXPECT_TRUE(clone.long_value() == precise);
  EXPECT_TRUE(clone == source);
  EXPECT_FALSE(clone === source);

  Var wide_float = Var.box_long_double(1.25L);
  Var float_clone = wide_float.clone_wide();
  EXPECT_TRUE(float_clone is <ldouble>);
  EXPECT_TRUE(float_clone.long_double_value() == 1.25L);
  EXPECT_TRUE(float_clone == wide_float);
  EXPECT_FALSE(float_clone === wide_float);
}


static void var_clone_wide_returns_void_for_narrow_values(void) {
  // The documented contract: a value of another kind returns void without
  // raising. Prove the silence with a capture handler left untouched.
  ErrorHandler handler = Error.push(_capture_var_runtime_error, void);
  var_runtime_errors = NULL;
  Var narrow = 17, text = %"not-wide";

  EXPECT_TRUE(narrow.clone_wide() is void);
  EXPECT_TRUE(text.clone_wide() is void);
  EXPECT_TRUE(void.clone_wide() is void);
  EXPECT_NULL(var_runtime_errors);

  Error.pop(handler);
}


static void var_dense_dispatch_capacity(void) {
  VarMethods methods = {0};
  EXPECT_FALSE(x2c_try_register_descriptor(NULL, methods));
  x2c_register_type(%"token");
  long token_value = 1;
  EXPECT_TRUE(Var.new(<token>, &token_value).truthy());
  EXPECT_FALSE(Var.new(<token>, NULL).truthy());
  // Fill whatever slots remain: runtime modules (the Lisp lsym tag) and
  // earlier suites own an unknown share of the 32.
  int filled = 0;
  for (int i = 0; i < 32; i++) {
    String name = %"dense%02d".printf(i);
    if (!x2c_try_register_descriptor(name, methods)) break;
    filled++;
  }
  EXPECT_TRUE(filled < 32);
  EXPECT_FALSE(x2c_try_register_descriptor(%"overflow", methods));
  int caught = 0;
  try x2c_register_tagged_descriptor(<overflow>, %"Overflow", methods);
  catch %(bad-state *): caught = 1;
  EXPECT_INT_EQ(caught, 1);
  // Tags registered before capacity keep working.
  EXPECT_TRUE(Var.new(<token>, &token_value).truthy());
}

/* Streaming must produce exactly what str produces, for every built-in shape
   and for nesting, or adopting write_str inside a renderer changes output.
   Buffer and Block are Var protocol participants that define str but no
   write_str, so they also prove the String fallback on a real type
   rather than only on a synthetic descriptor. */
static void var_write_str_matches_str(void) {
  Buffer payload = Buffer.new(0);
  payload.write("buffered");
  Block block = Block.new(sizeof(int));
  Var samples[] = {
    payload, block,
    %"plain text", %(1 two "three"), %[4, "five"],
    %{k: 6}, <sym>, Var.box_long(-9), Var.box_ulong(9),
    7, 2.5, void, ((String) NULL)
  };
  for (int i = 0; i < (int) (sizeof samples / sizeof samples[0]); i++) {
    Buffer out = Buffer.new(0);
    samples[i].write_str(out);
    String streamed = out.str_free();
    String direct = samples[i].str();
    if (!direct) EXPECT_TRUE(!streamed || !*streamed);
    else EXPECT_STR_EQ(streamed, direct);
  }
}

/* A nested renderer that adopted write_str must still agree with the String
   each container produced before, including a String element staying unquoted
   in str while a nested List keeps its own layout. */
static void var_nested_write_str_parity(void) {
  Array array = %["text", (a b), {k: 1}, 3];
  Buffer array_out = Buffer.new(0);
  array.write_str(array_out);
  EXPECT_STR_EQ(array_out.str_free(), array.str());

  Map map = %{key: [1, "two"]};
  Buffer map_out = Buffer.new(0);
  map.write_str(map_out);
  EXPECT_STR_EQ(map_out.str_free(), map.str());

  List list = %(outer (inner "quoted") 5);
  Buffer list_out = Buffer.new(1);
  list.write_str(list_out);
  EXPECT_STR_EQ(list_out.str_free(), list.str());

  // An empty or null container streams the same form its str produces,
  // including nested, which is where a divergence would hide.
  Array empties = %[{}, [], ()];
  EXPECT_STR_EQ(empties.str(), "[ { }, [  ], () ]");
  Map empty_nested = %{k: {}};
  EXPECT_STR_EQ(empty_nested.str(), "{ k: { } }");
  Buffer null_map = Buffer.new(0);
  ((Map) NULL).write_str(null_map);
  EXPECT_STR_EQ(null_map.str_free(), ((Map) NULL).str());
  Buffer null_array = Buffer.new(0);
  ((Array) NULL).write_str(null_array);
  EXPECT_STR_EQ(null_array.str_free(), ((Array) NULL).str());
}

/* The display form pads inside parentheses, and that padding is applied to the
   destination Buffer. Streaming a List into an unpadded Buffer must still pad,
   or a List nested in an Array or Map silently loses its spaces. */
static void var_nested_list_keeps_display_padding(void) {
  Array padded = %[1, (a b)];
  EXPECT_STR_EQ(padded.str(), "[ 1, ( a b ) ]");
  Map padded_map = %{k: (a b)};
  EXPECT_STR_EQ(padded_map.str(), "{ k: ( a b ) }");
  EXPECT_STR_EQ(%(a (b c)).str(), "( a ( b c ))");
  Buffer out = Buffer.new(0);
  %(a b).var().write_str(out);
  EXPECT_STR_EQ(out.str_free(), "( a b )");
  // The caller's padding is restored, so a later write is not padded.
  Buffer mixed = Buffer.new(0);
  %(a b).var().write_str(mixed);
  mixed.pad();
  EXPECT_STR_EQ(mixed.str_free(), "( a b )");
  // repr is unaffected and stays unpadded.
  EXPECT_STR_EQ(%(a (b c)).repr(), "(a (b c))");
}

/* Empty and null containers keep the exact spellings they had. */
static void var_empty_container_display_forms(void) {
  EXPECT_STR_EQ(%{}.str(), "{ }");
  EXPECT_STR_EQ(%{}.repr(), "{  }");
  EXPECT_STR_EQ(%[].str(), "[  ]");
  EXPECT_STR_EQ(%().str(), "()");
  // A null Array renders without dereferencing its storage.
  EXPECT_STR_EQ(((Array) NULL).str(), "[  ]");
}

/* Symbol and Atom stream without allocating the String their str returns. */
static void var_symbol_atom_stream_without_allocating(void) {
  Buffer out = Buffer.new(0);
  Symbol.write_str(<spelling>, out);
  EXPECT_STR_EQ(out.str_free(), <spelling>.str());
  // A zero Symbol appends nothing, which str_free reports as no String at
  // all -- the same answer Symbol.str gives it.
  Buffer zero = Buffer.new(0);
  Symbol.write_str(0, zero);
  EXPECT_NULL(zero.str_free());
  EXPECT_NULL(Symbol.str(0));

  Var atom = %(exact-name).car();
  Buffer atom_out = Buffer.new(0);
  Atom.write_str(atom, atom_out);
  EXPECT_STR_EQ(atom_out.str_free(), Atom.str(atom));
}


static void var_recursive_rendering(void) {
  Array array = %[];
  array.push(array);
  String pointer = array.var().pointer_string();
  EXPECT_STR_EQ(array.repr(), %"[ $pointer ]");
  EXPECT_STR_EQ(array.str(), %"[ $pointer ]");
  EXPECT_STR_EQ(array.var().repr(), array.repr());

  Map map = %{};
  map[1] = map;
  pointer = map.var().pointer_string();
  EXPECT_STR_EQ(map.repr(), %"{ 1: $pointer }");
  EXPECT_STR_EQ(map.str(), %"{ 1: $pointer }");

  array.truncate(0);
  List list = %(1 $array);
  array.push(list);
  pointer = list.var().pointer_string();
  EXPECT_STR_EQ(list.repr(), %"(1 [ $pointer ])");
  EXPECT_STR_EQ(list.var().repr(), list.repr());
  EXPECT_TRUE(list.str().contains(pointer));

  // Leave each path before rendering the same child through another edge.
  Array child = %[1, 2];
  Array repeated = %[$child, $child];
  EXPECT_STR_EQ(repeated.repr(), "[ [ 1, 2 ], [ 1, 2 ] ]");
  List repeated_list = %($child $child);
  EXPECT_STR_EQ(repeated_list.repr(), "([ 1, 2 ] [ 1, 2 ])");

  // Exercise the multiline List writer as well as its trial line rendering.
  Array long_cycle = %[];
  List long_list = %("abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyz"
                    "abcdefghijklmnopqrstuvwxyz" $long_cycle);
  long_cycle.push(long_list);
  EXPECT_TRUE(long_list.repr().contains(long_list.var().pointer_string()));
}

static Buffer _rendering_failure(Var value, Buffer out) {
  DispatchFixture *fixture = value.pointer();
  if (fixture.value) raise %(render-err);
  return out.write("ok");
}

static void var_rendering_restores_after_error(void) {
  VarMethods methods = { .write_repr = _rendering_failure };
  EXPECT_TRUE(x2c_try_register_descriptor(%"fixture", methods));
  defer {
    methods.write_repr = dispatch_fixture_write_repr;
    x2c_register_descriptor(%"fixture", methods);
  }
  DispatchFixture fixture = { .value = 1 };
  Var value = Var.new(<fixture>, &fixture);
  Array array = %[$value];
  Map map = %{1: $array};
  List list = %($map);
  Buffer out = Buffer.new(0);
  int caught = 0;
  try list.write_repr(out);
  catch %(render-err): caught = 1;
  EXPECT_INT_EQ(caught, 1);
  fixture.value = 0;
  EXPECT_STR_EQ(list.repr(), "({ 1: [ ok ] })");
  EXPECT_STR_EQ(array.repr(), "[ ok ]");
  EXPECT_STR_EQ(map.repr(), "{ 1: [ ok ] }");
  out.free();
}

void var_suite(void) {
  $test.run(var_recursive_rendering);
  $test.run(var_write_str_matches_str);
  $test.run(var_nested_write_str_parity);
  $test.run(var_nested_list_keeps_display_padding);
  $test.run(var_empty_container_display_forms);
  $test.run(var_symbol_atom_stream_without_allocating);
  $test.run(var_integer_construction);
  $test.run(var_floating_construction);
  $test.run(var_terminal_and_f64_escape);
  $test.run(var_construction_and_void_dispatch_transfer);
  $test.run(var_void_equality_and_rendering);
  $test.run(var_typed_empty_representation);
  $test.run(var_mutable_container_roundtrip);
  $test.run(var_pointer_and_object);
  $test.run(var_symbol_handling);
  $test.run(var_equality_and_hash);
  $test.run(var_helper_accessors);
  $test.run(var_scalar_reader_conversion);
  $test.run(var_unboxes_at_math_call);
  $test.run(var_compare_numeric_total_order);
  $test.run(var_compare_cross_type_groups);
  $test.run(var_equality_and_identity_operators);
  $test.run(var_comparison_operators);
  $test.run(var_compare_strict_encodings);
  $test.run(var_unsigned_char_accessor);
  $test.run(var_source_conversion_matrix);
  $test.run(var_byte_pointer_roundtrips);
  $test.run(var_catalog_tag_roundtrips);
  $test.run(var_explicit_i48_boundaries);
  $test.run(var_numeric_parse_is_exact);
  $test.run(var_wide_scalar_roundtrips);
  $test.run(var_native_numeric_names);
  $test.run(var_system_typedef_roundtrips);
  $test.run(var_wide_value_semantics);
  $test.run(var_clone_wide_copies_wide_boxes);
  $test.run(var_clone_wide_returns_void_for_narrow_values);
  $test.run(var_streaming_repr_matches_canonical);
  $test.run(var_dense_custom_dispatch);
  $test.run(var_rendering_restores_after_error);
  $test.run(var_protocol_builtin_dispatch_is_reachable);
  $test.run(var_dense_dispatch_capacity);
  $test.run(var_builtin_dispatch_tags_match_registration);
}
