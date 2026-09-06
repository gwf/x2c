/*  test-varops.x -- Var conversion, operation, and truth contracts */

#include <float.h>
#include <limits.h>
#include <math.h>

#include "test-support.x"
$(import "test-macros.xmacro")


static Var numeric_value_for_tag(Symbol tag, int value) {
  switch (tag) {
    case <i8>:   return Var.new(<i8>, value);
    case <u8>:   return Var.new(<u8>, value);
    case <i16>:  return Var.new(<i16>, value);
    case <u16>:  return Var.new(<u16>, value);
    case <i32>:  return Var.new(<i32>, value);
    case <u32>:  return Var.new(<u32>, (uint) value);
    case <i48>:  return Var.new(<i48>, (long) value);
    case <u48>:  return Var.new(<u48>, (ulong) value);
    case <long>:  return Var.box_long((long) value);
    case <ulong>:  return Var.box_ulong((ulong) value);
    case <llong>: return Var.box_long_long((long long) value);
    case <ullong>: return Var.box_ulong_long((unsigned long long) value);
    case <f32>:  return Var.new(<f32>, (double) value);
    case <f64>:  return Var.new(<f64>, (double) value);
    case <ldouble>: return Var.box_long_double((long double) value);
  }
  return void;
}


static long double converted_test_value(Var value) {
  return value.convert(<ldouble>).long_double_value();
}


static Var immediate_value(int index, int value) {
  switch (index) {
    case 0: return Var.new(<i8>, value);
    case 1: return Var.new(<u8>, value);
    case 2: return Var.new(<i16>, value);
    case 3: return Var.new(<u16>, value);
    case 4: return Var.new(<i32>, value);
    case 5: return Var.new(<u32>, (uint) value);
    case 6: return Var.new(<f32>, (double) value);
    case 7: return Var.new(<f64>, (double) value);
  }
  return void;
}


static Symbol promoted_tag(int left, int right) {
  if (left == 7 || right == 7) return <f64>;
  if (left == 6 || right == 6) return <f32>;
  if (left == 5 || right == 5) return <u32>;
  return <i32>;
}


static int numeric_rank(Symbol tag) {
  switch (tag) {
    case <i8>: case <u8>: return 1;
    case <i16>: case <u16>: return 2;
    case <i32>: case <u32>: return 3;
    case <i48>: case <u48>: return 4;
    case <long>: case <ulong>: return 5;
    case <llong>: case <ullong>: return 6;
    case <f32>: return 7;
    case <f64>: return 8;
    case <ldouble>: return 9;
  }
  return 0;
}


static int numeric_unsigned(Symbol tag) {
  return tag == <u8> || tag == <u16> || tag == <u32> ||
         tag == <u48> || tag == <ulong> || tag == <ullong>;
}


static int numeric_bits(Symbol tag) {
  switch (tag) {
    case <i8>: case <u8>: return 8;
    case <i16>: case <u16>: return 16;
    case <i32>: case <u32>: case <f32>: return 32;
    case <i48>: case <u48>: return 48;
    case <long>: case <ulong>: return sizeof(long) * CHAR_BIT;
    case <llong>: case <ullong>: return sizeof(long long) * CHAR_BIT;
    case <f64>: return 64;
    case <ldouble>: return sizeof(long double) * CHAR_BIT;
  }
  return 0;
}


static Symbol integer_family_tag(int rank, int unsigned_value) {
  if (rank <= 3) return unsigned_value ? <u32> : <i32>;
  if (rank == 4) return unsigned_value ? <u48> : <i48>;
  if (rank == 5) return unsigned_value ? <ulong> : <long>;
  return unsigned_value ? <ullong> : <llong>;
}


static Symbol expected_numeric_tag(Symbol left, Symbol right) {
  int left_rank = numeric_rank(left), right_rank = numeric_rank(right);
  if (left_rank >= 7 || right_rank >= 7)
    return left_rank >= right_rank ? left : right;
  if (left_rank < 3) {
    left = <i32>;
    left_rank = 3;
  }
  if (right_rank < 3) {
    right = <i32>;
    right_rank = 3;
  }
  int left_unsigned = numeric_unsigned(left);
  int right_unsigned = numeric_unsigned(right);
  if (left_unsigned == right_unsigned)
    return integer_family_tag(
      left_rank >= right_rank ? left_rank : right_rank, left_unsigned);
  Symbol unsigned_tag = left_unsigned ? left : right;
  Symbol signed_tag = left_unsigned ? right : left;
  int unsigned_rank = numeric_rank(unsigned_tag);
  int signed_rank = numeric_rank(signed_tag);
  if (unsigned_rank >= signed_rank)
    return integer_family_tag(unsigned_rank, 1);
  if (numeric_bits(signed_tag) > numeric_bits(unsigned_tag))
    return integer_family_tag(signed_rank, 0);
  return integer_family_tag(signed_rank, 1);
}


static void var_numeric_metadata_is_canonical(void) {
  Symbol tags[] = {
    <i8>, <u8>, <i16>, <u16>, <i32>, <u32>, <i48>, <u48>,
    <long>, <ulong>, <llong>, <ullong>, <f32>, <f64>, <ldouble>
  };
  int count = sizeof(tags) / sizeof(tags[0]);
  for (int i = 0; i < count; i++) {
    X2CVarNumericInfo info;
    EXPECT_TRUE(Var.numeric_info(tags[i], &info));
    EXPECT_TRUE(info.tag == tags[i]);
    EXPECT_INT_EQ(info.rank, numeric_rank(tags[i]));
    EXPECT_INT_EQ(info.bits, numeric_bits(tags[i]));
    EXPECT_INT_EQ(info.unsigned_value, numeric_unsigned(tags[i]));
    EXPECT_INT_EQ(info.floating, numeric_rank(tags[i]) >= 7);
  }

  Symbol special[] = { <nan>, <-inf>, <+inf> };
  for (int i = 0; i < 3; i++) {
    X2CVarNumericInfo info;
    EXPECT_TRUE(Var.numeric_info(special[i], &info));
    EXPECT_TRUE(info.tag == <f64>);
    EXPECT_TRUE(info.floating);
    EXPECT_FALSE(info.unsigned_value);
    EXPECT_INT_EQ(info.bits, 64);
    EXPECT_INT_EQ(info.rank, 8);
  }

  X2CVarNumericInfo untouched = {
    .tag = <string>, .floating = 7, .unsigned_value = 8,
    .bits = 9, .rank = 10
  };
  EXPECT_FALSE(Var.numeric_info(<string>, &untouched));
  EXPECT_TRUE(untouched.tag == <string>);
  EXPECT_INT_EQ(untouched.floating, 7);
  EXPECT_INT_EQ(untouched.unsigned_value, 8);
  EXPECT_INT_EQ(untouched.bits, 9);
  EXPECT_INT_EQ(untouched.rank, 10);
  EXPECT_FALSE(Var.numeric_info(<i32>, NULL));

  for (int rank = 1; rank <= 6; rank++) {
    EXPECT_TRUE(Var.integer_tag(rank, 0) == integer_family_tag(rank, 0));
    EXPECT_TRUE(Var.integer_tag(rank, 1) == integer_family_tag(rank, 1));
  }
  EXPECT_TRUE(Var.integer_tag(7, 0) == 0);
}


static Symbol expected_shift_tag(Symbol tag) {
  return numeric_rank(tag) < 3 ? <i32> : tag;
}


static void var_numeric_conversion_matrix(void) {
  $test.scoped();
  Symbol tags[] = {
    <i8>, <u8>, <i16>, <u16>, <i32>, <u32>, <i48>, <u48>,
    <long>, <ulong>, <llong>, <ullong>, <f32>, <f64>, <ldouble>
  };
  int count = sizeof(tags) / sizeof(tags[0]);
  for (int source_index = 0; source_index < count; source_index++) {
    Var source = numeric_value_for_tag(tags[source_index], 3);
    for (int target_index = 0; target_index < count; target_index++) {
      Var converted = source.convert(tags[target_index]);
      EXPECT_TRUE(converted is tags[target_index]);
      EXPECT_TRUE(converted_test_value(converted) == 3.0L);
    }
  }
}


static void var_numeric_conversion_boundaries(void) {
  $test.scoped();
  Var out = Var.convert(300, <u8>);
  EXPECT_INT_EQ(out.uchar(), 44);
  out = Var.convert(-1, <u8>);
  EXPECT_INT_EQ(out.uchar(), 255);
  Var negative_i8 = Var.new(<i8>, -1);
  out = negative_i8.convert(<i16>);
  EXPECT_INT_EQ(out.short(), -1);
  out = negative_i8.convert(<long>);
  EXPECT_TRUE(out.long_value() == -1);
  out = negative_i8.convert(<ulong>);
  EXPECT_TRUE(out.ulong_value() == ULONG_MAX);
  Var u48_sign_bit = Var.new(<u48>, 1ul << 47);
  out = u48_sign_bit.convert(<i48>);
  EXPECT_TRUE(out.integer() == -(1L << 47));
  out = Var.convert(3.75, <i32>);
  EXPECT_INT_EQ(out.int(), 3);
  out = Var.convert(-0.5, <u8>);
  EXPECT_INT_EQ(out.uchar(), 0);

  int caught = 0;
  try Var.convert(Var.new(<f64>, 0.0 / 0.0), <i32>);
  catch %(conv-range *): caught++;
  try Var.convert(void, <i32>);
  catch %(void-op *): caught++;
  List detail = NULL;
  try Var.convert(%"text", <i32>);
  catch %(no-convert *cause): { caught++; detail = cause; }
  List cause = detail.assoc(<cause>);
  EXPECT_TRUE(cause.car() == <bad-types>);
  EXPECT_STR_EQ(cause.repr(), "(bad-types (source string))");

  try Var.convert(3, <void>);
  catch %(bad-target *): caught++;
  try Var.convert(3, <unknown>);
  catch %(bad-target *): caught++;
  EXPECT_INT_EQ(caught, 5);

  Var text = %"same";
  out = text.convert(<string>);
  EXPECT_TRUE(out === text);

  Var integer = 42, floating = 8.75;
  EXPECT_TRUE(integer.convert(<f64>).floating() == 42.0);
  EXPECT_INT_EQ(floating.convert(<i32>).integer(), 8);

  Var nan = Var.new(<f64>, 0.0 / 0.0);
  Var posinf = Var.new(<f64>, 1.0 / 0.0);
  Var neginf = Var.new(<f64>, -1.0 / 0.0);
  EXPECT_TRUE(nan.convert(<f64>) is <nan>);
  EXPECT_TRUE(nan.convert(<f32>).floating() != nan.convert(<f32>).floating());
  EXPECT_TRUE(posinf.convert(<ldouble>).long_double_value() == 1.0L / 0.0L);
  EXPECT_TRUE(neginf.convert(<f32>).floating() == -1.0 / 0.0);
  EXPECT_TRUE(Var.new(<f64>, -0.0).convert(<f32>).floating() == 0.0);
  EXPECT_TRUE(
    Var.new(<f64>, -DBL_MAX).convert(<ldouble>).long_double_value() ==
    (long double) -DBL_MAX);

  caught = 0;
  try Var.box_long_double(ldexpl(1.0L, 64)).convert(<ullong>);
  catch %(conv-range *): caught++;
  try Var.box_long_double(-ldexpl(1.0L, 64)).convert(<llong>);
  catch %(conv-range *): caught++;
  EXPECT_INT_EQ(caught, 2);
}


static void var_numeric_exact_floating_boundaries(void) {
  $test.scoped();
  unsigned long long rounding_value = (1ull << 63) + (1ull << 39) + 1ull;
  Var wide = Var.box_ulong_long(rounding_value);
  Var converted = wide.convert(<f32>);
  float expected = (float) rounding_value;
  EXPECT_TRUE(Var.decode_f32(converted) == expected);

  Var operated = wide.binary(<+>, Var.new(<f32>, 0.0));
  EXPECT_TRUE(operated is <f32>);
  EXPECT_TRUE(Var.decode_f32(operated) == expected);

  unsigned long long lower_value = (1ull << 53) + 3ull;
  Var lower = Var.box_ulong_long(lower_value);
  Var upper = Var.new(<f64>, (double) (lower_value + 1ull));
  EXPECT_TRUE(lower < upper);
  EXPECT_TRUE(upper > lower);
}


static void var_arithmetic_pair_matrix(void) {
  Symbol ops[] = { <+>, <->, <*>, </> };
  int expected[] = { 14, 10, 24, 6 };
  for (int op_index = 0; op_index < 4; op_index++) {
    for (int left = 0; left < 8; left++) {
      for (int right = 0; right < 8; right++) {
        Var result = Var.binary(
          immediate_value(left, 12), ops[op_index],
          immediate_value(right, 2));
        EXPECT_TRUE(result is promoted_tag(left, right));
        EXPECT_TRUE(converted_test_value(result) == expected[op_index]);
      }
    }
  }
}


static void var_integral_pair_matrix(void) {
  Symbol ops[] = { <%>, <&>, <|>, <^>, <"<<">, <">>"> };
  int expected[] = { 0, 0, 14, 14, 48, 3 };
  for (int op_index = 0; op_index < 6; op_index++) {
    for (int left = 0; left < 6; left++) {
      for (int right = 0; right < 6; right++) {
        Var result = Var.binary(
          immediate_value(left, 12), ops[op_index],
          immediate_value(right, 2));
        Symbol tag = op_index >= 4
                   ? promoted_tag(left, left) : promoted_tag(left, right);
        EXPECT_TRUE(result is tag);
        EXPECT_TRUE(converted_test_value(result) == expected[op_index]);
      }
    }
  }
}


static void var_all_family_arithmetic_matrix(void) {
  $test.scoped();
  Symbol tags[] = {
    <i8>, <u8>, <i16>, <u16>, <i32>, <u32>, <i48>, <u48>,
    <long>, <ulong>, <llong>, <ullong>, <f32>, <f64>, <ldouble>
  };
  Symbol ops[] = { <+>, <->, <*>, </> };
  int expected[] = { 14, 10, 24, 6 }, count = sizeof(tags) / sizeof(tags[0]);
  for (int op_index = 0; op_index < 4; op_index++) {
    for (int left = 0; left < count; left++) {
      for (int right = 0; right < count; right++) {
        Var result = Var.binary(
          numeric_value_for_tag(tags[left], 12), ops[op_index],
          numeric_value_for_tag(tags[right], 2));
        EXPECT_TRUE(result is expected_numeric_tag(tags[left], tags[right]));
        EXPECT_TRUE(converted_test_value(result) == expected[op_index]);
      }
    }
  }
}


static void var_all_family_integral_matrix(void) {
  $test.scoped();
  Symbol tags[] = {
    <i8>, <u8>, <i16>, <u16>, <i32>, <u32>,
    <i48>, <u48>, <long>, <ulong>, <llong>, <ullong>
  };
  Symbol ops[] = { <%>, <&>, <|>, <^>, <"<<">, <">>"> };
  int expected[] = { 0, 0, 14, 14, 48, 3 };
  int count = sizeof(tags) / sizeof(tags[0]);
  for (int op_index = 0; op_index < 6; op_index++) {
    for (int left = 0; left < count; left++) {
      for (int right = 0; right < count; right++) {
        Var result = Var.binary(
          numeric_value_for_tag(tags[left], 12), ops[op_index],
          numeric_value_for_tag(tags[right], 2));
        Symbol expected_tag = op_index >= 4
                            ? expected_shift_tag(tags[left])
                            : expected_numeric_tag(tags[left], tags[right]);
        EXPECT_TRUE(result is expected_tag);
        EXPECT_TRUE(converted_test_value(result) == expected[op_index]);
      }
    }
  }
}


static void var_operation_edges_and_status(void) {
  $test.scoped();
  int caught = 0;
  try Var.binary(10, </>, 0);
  catch %(div-zero *): caught++;
  try Var.binary(1, <"<<">, 32);
  catch %(bad-shift *): caught++;
  try Var.binary(1, <">>">, -1);
  catch %(bad-shift *): caught++;
  try Var.binary(1.0, <%>, 2);
  catch %(bad-types *): caught++;
  try Var.binary(%"x", <unknown>, 2);
  catch %(bad-op *): caught++;

  Var result = Var.binary(Var.box_long(1), <+>, 2);
  EXPECT_TRUE(result is <long>);
  EXPECT_TRUE(converted_test_value(result) == 3.0L);

  try Var.binary(void, <+>, 2);
  catch %(void-op *): caught++;
  try Var.binary(1, <unknown>, 2);
  catch %(bad-op *): caught++;

  result = Var.binary(Var.new(<i32>, INT_MAX), <+>, 1);
  EXPECT_INT_EQ(result.int(), INT_MIN);
  result = Var.binary(Var.new(<i32>, INT_MIN), </>, -1);
  EXPECT_INT_EQ(result.int(), INT_MIN);
  result = Var.binary(Var.new(<i32>, INT_MIN), <%>, -1);
  EXPECT_INT_EQ(result.int(), 0);
  result = Var.binary(-8, <">>">, 2);
  EXPECT_INT_EQ(result.int(), -2);

  result = Var.binary(Var.new(<i48>, (1L << 47) - 1), <+>, 1);
  EXPECT_TRUE(result is <i48>);
  EXPECT_TRUE(result.integer() == -(1L << 47));
  result = Var.binary(Var.new(<u48>, (1UL << 48) - 1), <+>, 1);
  EXPECT_TRUE(result is <u48>);
  EXPECT_TRUE(result.integer() == 0);
  result = Var.binary(Var.box_long(LONG_MAX), <+>, 1);
  EXPECT_TRUE(result is <long>);
  EXPECT_TRUE(result.long_value() == LONG_MIN);
  result = Var.binary(Var.box_ulong(ULONG_MAX), <+>, 1);
  EXPECT_TRUE(result is <ulong>);
  EXPECT_TRUE(result.ulong_value() == 0);
  result = Var.binary(Var.box_long_long(LLONG_MAX), <+>, 1);
  EXPECT_TRUE(result is <llong>);
  EXPECT_TRUE(result.long_long_value() == LLONG_MIN);
  result = Var.binary(Var.box_ulong_long(ULLONG_MAX), <+>, 1);
  EXPECT_TRUE(result is <ullong>);
  EXPECT_TRUE(result.ulong_long_value() == 0);

  result = Var.binary(Var.box_long(LONG_MIN), </>, -1);
  EXPECT_TRUE(result.long_value() == LONG_MIN);
  result = Var.binary(Var.box_long(LONG_MIN), <%>, -1);
  EXPECT_TRUE(result.long_value() == 0);
  try Var.binary(Var.box_long(1), <"<<">, 64);
  catch %(bad-shift *): caught++;
  result = Var.binary(Var.box_long(1), <"<<">, 63);
  EXPECT_TRUE(result.long_value() == LONG_MIN);

  result = Var.binary(Var.new(<i48>, 1), <+>, Var.new(<u32>, UINT_MAX));
  EXPECT_TRUE(result is <i48>);
  result = Var.binary(Var.box_long(1), <+>, Var.new(<u48>, 2UL));
  EXPECT_TRUE(result is <long>);
  result = Var.binary(Var.box_long_long(1), <+>, Var.box_ulong(2));
  EXPECT_TRUE(result is <ullong>);
  EXPECT_INT_EQ(caught, 8);
}


static void var_invalid_encoding_status_is_atomic(void) {
  $test.scoped();
  Var malformed_immediate = (Var) { .u64 = 0x8002000800000000ul };
  Var malformed_special = (Var) { .u64 = 0x8003000100000001ul };
  Var null_array = (Var) { .u64 = 0x0008000000000000ul };
  Var null_map = (Var) { .u64 = 0x0009000000000006ul };
  Var owned = Var.box_long(7);
  Var retagged = owned;
  retagged.u64 = (retagged.u64 & ~0x7ul) | 0x6ul;
  EXPECT_FALSE(Var.encoding_valid(malformed_immediate));
  EXPECT_FALSE(Var.encoding_valid(malformed_special));
  EXPECT_FALSE(Var.encoding_valid(null_array));
  EXPECT_FALSE(Var.encoding_valid(null_map));
  EXPECT_FALSE(Var.encoding_valid(retagged));

  int caught = 0;
  try Var.convert(malformed_immediate, <i32>);
  catch %(bad-enc *): caught++;
  try malformed_special.truthy();
  catch %(bad-enc *): caught++;
  try null_array.truthy();
  catch %(bad-enc *): caught++;
  try null_map.truthy();
  catch %(bad-enc *): caught++;
  try Var.binary(retagged, <+>, 1);
  catch %(bad-enc *): caught++;

  Var lhs = 5, before = lhs;
  try Var.update(&lhs, <unknown>, malformed_immediate);
  catch %(bad-enc *): caught++;
  EXPECT_TRUE(lhs === before);
  lhs = malformed_special;
  unsigned long before_bits = lhs.u64;
  try Var.postfix(&lhs, <unknown>);
  catch %(bad-enc *): caught++;
  EXPECT_TRUE(lhs.u64 == before_bits);
  EXPECT_INT_EQ(caught, 7);
}


static void var_truth_and_generic_predicates(void) {
  $test.scoped();
  int truth = Var.truthy(0);
  EXPECT_FALSE(truth);
  EXPECT_FALSE(Var.new(<f64>, -0.0).truthy());
  EXPECT_TRUE(Var.new(<f64>, 0.0 / 0.0).truthy());
  EXPECT_FALSE(((Var) {0}).truthy());
  EXPECT_FALSE(Var.new(<symbol>, 0ul).truthy());
  Var empty_string = (String) NULL;
  Var text = %"x";
  Var empty_list = (List) NULL;
  Var list = %(1);
  Var empty_array = %[];
  Var array = %[1];
  Var empty_map = %{};
  Var map = %{ a: 1 };
  EXPECT_FALSE(empty_string.truthy());
  EXPECT_TRUE(text.truthy());
  EXPECT_FALSE(empty_list.truthy());
  EXPECT_TRUE(list.truthy());
  EXPECT_FALSE(empty_array.truthy());
  EXPECT_TRUE(array.truthy());
  EXPECT_FALSE(empty_map.truthy());
  EXPECT_TRUE(map.truthy());

  Block empty_block = Block.new(sizeof(int));
  Block full_block = Block.new(sizeof(int));
  int one = 1;
  full_block.append(&one, 1);
  Bytes empty_bytes = Bytes.new(sizeof(char));
  Bytes full_bytes = Bytes.new(sizeof(char));
  char byte = 'x';
  full_bytes = full_bytes.append(&byte, 1);
  Buffer empty_buffer = Buffer.new(0), full_buffer = Buffer.new(0);
  full_buffer.write("x");
  EXPECT_FALSE(Var.new(<block>, empty_block).truthy());
  EXPECT_TRUE(Var.new(<block>, full_block).truthy());
  EXPECT_FALSE(Var.new(<bytes>, empty_bytes).truthy());
  EXPECT_TRUE(Var.new(<bytes>, full_bytes).truthy());
  EXPECT_FALSE(Var.new(<buffer>, empty_buffer).truthy());
  EXPECT_TRUE(Var.new(<buffer>, full_buffer).truthy());
  int caught = 0;
  try void.truthy();
  catch %(void-op *): caught = 1;
  EXPECT_TRUE(caught);

  EXPECT_INT_EQ(Var.binary(1, <&&>, %"x").int(), 1);
  EXPECT_INT_EQ(Var.binary(0, <||>, %"").int(), 0);
  EXPECT_INT_EQ(Var.binary(3, <==>, 3).int(), 1);
  EXPECT_INT_EQ(Var.binary(3, <!=>, 4).int(), 1);
  EXPECT_INT_EQ(Var.binary(3, <===>, 3).int(), 1);
  EXPECT_INT_EQ(Var.binary(3, <!==>, 4).int(), 1);
  EXPECT_INT_EQ(Var.binary(3, <"<">, 4).int(), 1);
  EXPECT_INT_EQ(Var.binary(3, <"<=">, 3).int(), 1);
  EXPECT_INT_EQ(Var.binary(4, <">">, 3).int(), 1);
  EXPECT_INT_EQ(Var.binary(4, <">=">, 4).int(), 1);
  EXPECT_INT_EQ(Var.binary(%"same", <==>, %"same").int(), 1);
  EXPECT_INT_EQ(Var.binary(%"a", <"<">, %"b").int(), 1);

  Symbol numeric_tags[] = {
    <i8>, <u8>, <i16>, <u16>, <i32>, <u32>, <i48>, <u48>,
    <long>, <ulong>, <llong>, <ullong>, <f32>, <f64>, <ldouble>
  };
  int numeric_count = sizeof(numeric_tags) / sizeof(numeric_tags[0]);
  for (int i = 0; i < numeric_count; i++) {
    EXPECT_FALSE(numeric_value_for_tag(numeric_tags[i], 0).truthy());
    EXPECT_TRUE(numeric_value_for_tag(numeric_tags[i], 1).truthy());
  }

  Array iter_values = %[7];
  struct Iter iter_storage;
  Iter iter = iter_values.iter(&iter_storage);
  Var boxed_iter = iter;
  EXPECT_TRUE(boxed_iter.truthy());
  EXPECT_TRUE(boxed_iter.truthy());
  EXPECT_INT_EQ(iter.next().int(), 7);
  EXPECT_TRUE(boxed_iter.truthy());
  empty_buffer.free();
  full_buffer.free();
}


static void var_updates_preserve_tags_and_atomicity(void) {
  $test.scoped();
  Var value = Var.new(<u8>, 255), result = Var.update(&value, <+>, 1);
  EXPECT_TRUE(value is <u8>);
  EXPECT_INT_EQ(value.uchar(), 0);
  EXPECT_TRUE(result === value);

  Var old = Var.postfix(&value, <++>);
  EXPECT_INT_EQ(old.uchar(), 0);
  EXPECT_INT_EQ(value.uchar(), 1);
  old = Var.postfix(&value, <-->);
  EXPECT_INT_EQ(old.uchar(), 1);
  EXPECT_INT_EQ(value.uchar(), 0);

  value = Var.new(<i32>, 7);
  Var before = value;
  int caught = 0;
  try Var.update(&value, <+>, Var.new(<f64>, 0.0 / 0.0));
  catch %(conv-range *): caught++;
  EXPECT_TRUE(value === before);

  try Var.update(&value, <==>, 7);
  catch %(bad-op *): caught++;
  EXPECT_TRUE(value === before);

  Var void_value = void;
  try Var.postfix(&void_value, <unknown>);
  catch %(void-op *): caught++;
  EXPECT_TRUE(void_value is void);
  EXPECT_INT_EQ(caught, 3);

  Symbol tags[] = {
    <i8>, <u8>, <i16>, <u16>, <i32>, <u32>, <i48>, <u48>,
    <long>, <ulong>, <llong>, <ullong>, <f32>, <f64>, <ldouble>
  };
  int count = sizeof(tags) / sizeof(tags[0]);
  for (int i = 0; i < count; i++) {
    value = numeric_value_for_tag(tags[i], 12);
    result = Var.update(&value, <+>, 2);
    EXPECT_TRUE(value is tags[i]);
    EXPECT_TRUE(result is tags[i]);
    EXPECT_TRUE(converted_test_value(value) == 14.0L);
    old = Var.postfix(&value, <-->);
    EXPECT_TRUE(old is tags[i]);
    EXPECT_TRUE(converted_test_value(old) == 14.0L);
    EXPECT_TRUE(value is tags[i]);
    EXPECT_TRUE(converted_test_value(value) == 13.0L);
  }
}


static void var_same_tag_updates_preserve_contract(void) {
  $test.scoped();
  Var value = Var.new(<i32>, INT_MAX), result = Var.update(&value, <+>, 1);
  EXPECT_TRUE(value is <i32>);
  EXPECT_INT_EQ(value.int(), INT_MIN);
  EXPECT_TRUE(result === value);

  value = Var.new(<u32>, UINT_MAX);
  Var one = Var.new(<u32>, 1u);
  result = Var.update(&value, <+>, one);
  EXPECT_TRUE(value is <u32>);
  EXPECT_INT_EQ(value.uint(), 0);
  EXPECT_TRUE(result === value);

  value = Var.new(<i32>, INT_MIN);
  result = Var.update(&value, </>, -1);
  EXPECT_INT_EQ(value.int(), INT_MIN);
  Var before = value;
  int caught = 0;
  try Var.update(&value, </>, 0);
  catch %(div-zero *): caught++;
  EXPECT_TRUE(value === before);

  value = 1;
  result = Var.update(&value, <"<<">, 31);
  EXPECT_INT_EQ(value.int(), INT_MIN);
  before = value;
  try Var.update(&value, <"<<">, 32);
  catch %(bad-shift *): caught++;
  EXPECT_TRUE(value === before);
  EXPECT_INT_EQ(caught, 2);

  value = Var.new(<f32>, 1.5);
  Var f32_rhs = Var.new(<f32>, 0.5);
  result = Var.update(&value, <+>, f32_rhs);
  EXPECT_TRUE(value is <f32>);
  EXPECT_TRUE(value.float() == 2.0f);
  EXPECT_TRUE(result === value);

  value = Var.new(<f64>, 1.5);
  Var f64_rhs = Var.new(<f64>, 0.5);
  result = Var.update(&value, <+>, f64_rhs);
  EXPECT_TRUE(value is <f64>);
  EXPECT_TRUE(value.floating() == 2.0);
  EXPECT_TRUE(result === value);

  Var nan = Var.new(<f64>, 0.0 / 0.0);
  result = Var.update(&value, <+>, nan);
  EXPECT_TRUE(value.is_floating());
  EXPECT_TRUE(isnan(value.floating()));
  EXPECT_TRUE(result === value);

  Var alias = 9;
  result = Var.update(&alias, <+>, 1);
  EXPECT_INT_EQ(alias.int(), 10);
  EXPECT_TRUE(result === alias);

  Var mixed = 7, u16_rhs = Var.new(<u16>, 2);
  result = Var.update(&mixed, <+>, u16_rhs);
  EXPECT_TRUE(mixed is <i32>);
  EXPECT_INT_EQ(mixed.int(), 9);
  EXPECT_TRUE(result === mixed);
}


static void var_typed_native_update_adapters(void) {
  $test.scoped();
  volatile char i8 = 3;
  volatile signed char signed_i8 = -4;
  volatile uchar u8 = 3;
  volatile short i16 = 3;
  volatile ushort u16 = 3;
  volatile int i32 = 3;
  volatile uint u32 = 3;
  volatile long native_long = 3;
  volatile ulong native_ulong = 3;
  volatile long long native_long_long = 3;
  volatile unsigned long long native_ulong_long = 3;
  volatile float f32 = 3.0f;
  volatile double f64 = 3.0;
  volatile long double native_long_double = 3.0L;
  Var two = 2;

  EXPECT_INT_EQ(x2c_var_update_i8(&i8, <+>, two), 5);
  EXPECT_INT_EQ(x2c_var_update_schar(&signed_i8, </>, two), -2);
  EXPECT_INT_EQ(x2c_var_update_u8(&u8, <+>, two), 5);
  EXPECT_INT_EQ(x2c_var_update_i16(&i16, <+>, two), 5);
  EXPECT_INT_EQ(x2c_var_update_u16(&u16, <+>, two), 5);
  EXPECT_INT_EQ(x2c_var_update_i32(&i32, <+>, two), 5);
  EXPECT_INT_EQ(x2c_var_update_u32(&u32, <+>, two), 5);
  EXPECT_TRUE(x2c_var_update_long(&native_long, <+>, two) == 5);
  EXPECT_TRUE(x2c_var_update_ulong(&native_ulong, <+>, two) == 5);
  EXPECT_TRUE(x2c_var_update_long_long(&native_long_long, <+>, two) == 5);
  EXPECT_TRUE(x2c_var_update_ulong_long(&native_ulong_long, <+>, two) == 5);
  EXPECT_TRUE(x2c_var_update_f32(&f32, <+>, two) == 5.0f);
  EXPECT_TRUE(x2c_var_update_f64(&f64, <+>, two) == 5.0);
  EXPECT_TRUE(
    x2c_var_update_long_double(&native_long_double, <+>, two) == 5.0L);
  EXPECT_INT_EQ(i8, 5);
  EXPECT_INT_EQ(signed_i8, -2);
  EXPECT_INT_EQ(u8, 5);
  EXPECT_INT_EQ(i16, 5);
  EXPECT_INT_EQ(u16, 5);
  EXPECT_INT_EQ(i32, 5);
  EXPECT_INT_EQ(u32, 5);
  EXPECT_TRUE(native_long == 5 && native_ulong == 5);
  EXPECT_TRUE(native_long_long == 5 && native_ulong_long == 5);
  EXPECT_TRUE(f32 == 5.0f && f64 == 5.0 && native_long_double == 5.0L);
}



void varops_suite(void) {
  $test.run(var_numeric_metadata_is_canonical);
  $test.run(var_numeric_conversion_matrix);
  $test.run(var_numeric_conversion_boundaries);
  $test.run(var_numeric_exact_floating_boundaries);
  $test.run(var_arithmetic_pair_matrix);
  $test.run(var_integral_pair_matrix);
  $test.run(var_all_family_arithmetic_matrix);
  $test.run(var_all_family_integral_matrix);
  $test.run(var_operation_edges_and_status);
  $test.run(var_invalid_encoding_status_is_atomic);
  $test.run(var_truth_and_generic_predicates);
  $test.run(var_updates_preserve_tags_and_atomicity);
  $test.run(var_same_tag_updates_preserve_contract);
  $test.run(var_typed_native_update_adapters);
}
