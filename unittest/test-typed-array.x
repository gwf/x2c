/*  test-typed-array.x -- packed numeric Array prototype tests */

#include "typed-array.x"
#include "test-support.x"
$(import "test-macros.xmacro")

static void typed_array_keeps_array_unchanged(void) {
  $test.scoped();
  Array values = %[1, "two"];

  EXPECT_INT_EQ(values.width, sizeof(Var));
  EXPECT_INT_EQ(values.len(), 2);
  EXPECT_INT_EQ(values[0].int(), 1);
  EXPECT_TRUE(values[1].string() == %"two");
}

static void typed_array_packs_array_literals(void) {
  $test.scoped();
  ArrayInt whole = %[1, 2, 3];
  ArrayDbl fractions = %[1, 2.5];
  ArrayInt empty = %[];
  Array source = %[7, 8];
  ArrayLong wide = source;
  Array missing = NULL;
  ArrayInt unpacked = missing;
  ArrayInt refused = ArrayInt.new();
  int caught = 0;

  EXPECT_INT_EQ(whole.width, sizeof(int));
  EXPECT_INT_EQ(whole.len(), 3);
  EXPECT_INT_EQ(whole[2], 3);
  EXPECT_TRUE(fractions[1] == 2.5);
  EXPECT_INT_EQ(empty.len(), 0);
  EXPECT_INT_EQ(source.width, sizeof(Var));
  EXPECT_TRUE(wide[1] == 8L);
  EXPECT_NULL(unpacked);

  try refused = %[1, "two"];
  catch %(no-convert *): caught++;
  EXPECT_INT_EQ(caught, 1);
  EXPECT_INT_EQ(refused.len(), 0);
}

static void typed_array_int_uses_packed_storage(void) {
  $test.scoped();
  ArrayInt values = ArrayInt.new();
  int missing = 73;

  EXPECT_NOT_NULL(values);
  EXPECT_INT_EQ(values.width, sizeof(int));
  EXPECT_FALSE(values.try_get(0, &missing));
  EXPECT_INT_EQ(missing, 73);
  EXPECT_INT_EQ(values.push(10), 10);
  EXPECT_INT_EQ(values.push(20), 20);
  EXPECT_INT_EQ(values.push(30), 30);
  EXPECT_INT_EQ(values.len(), 3);
  EXPECT_INT_EQ(values[2], 30);
  EXPECT_FALSE(values.try_get(3, &missing));
  EXPECT_FALSE(values.try_get(-4, &missing));
  EXPECT_INT_EQ(values.setindex(1, 22), 22);
  EXPECT_INT_EQ(values[1], 22);
  EXPECT_TRUE(values.try_get(1, &missing));
  EXPECT_INT_EQ(missing, 22);
  EXPECT_TRUE(values.try_take_last(&missing));
  EXPECT_INT_EQ(missing, 30);
  EXPECT_INT_EQ(values.take_last(), 22);
  EXPECT_INT_EQ(values.len(), 1);
  EXPECT_FALSE(values.try_take_last(NULL));
}

static void typed_array_native_updates_and_var_transport(void) {
  $test.scoped();
  ArrayInt values = ArrayInt.new();
  values.push(7);
  values.push(12);

  EXPECT_INT_EQ(values[0] += 5, 12);
  EXPECT_INT_EQ(values[1]++, 12);
  EXPECT_INT_EQ(values[1], 13);
  EXPECT_INT_EQ(values[1]--, 13);
  EXPECT_INT_EQ(values[1], 12);

  Var boxed = values;
  EXPECT_TRUE(boxed is <arrayint>);
  EXPECT_INT_EQ(boxed[0].int(), 12);
  EXPECT_INT_EQ((boxed[0] += 3).int(), 15);
  EXPECT_INT_EQ(values[0], 15);
  boxed[1] = 21;
  EXPECT_INT_EQ(values[1], 21);
}

static void typed_array_double_uses_native_values(void) {
  $test.scoped();
  ArrayDbl values = ArrayDbl.new();
  values.push(1.25);
  values.push(2.5);

  EXPECT_INT_EQ(values.width, sizeof(double));
  EXPECT_TRUE(values[0] == 1.25);
  EXPECT_TRUE((values[1] += 0.5) == 3.0);
  EXPECT_TRUE(values[0]++ == 1.25);
  EXPECT_TRUE(values[0] == 2.25);

  Var boxed = values;
  EXPECT_TRUE(boxed is <arraydbl>);
  EXPECT_TRUE(boxed[1].double() == 3.0);
  EXPECT_TRUE((boxed[1] += 0.25).double() == 3.25);
  EXPECT_TRUE(values[1] == 3.25);
}

static void typed_array_additional_scalar_families(void) {
  $test.scoped();

  ArrayChar chars = ArrayChar.new();
  EXPECT_INT_EQ(chars.width, sizeof(char));
  EXPECT_INT_EQ(chars.push('A'), 'A');
  EXPECT_INT_EQ(chars[0] += 2, 'C');
  EXPECT_INT_EQ(chars.len(), 1);
  Var boxed_chars = chars;
  EXPECT_TRUE(boxed_chars is <arraychar>);
  EXPECT_INT_EQ(boxed_chars[0].char(), 'C');
  EXPECT_INT_EQ((boxed_chars[0] += 1).char(), 'D');

  ArrayShort shorts = ArrayShort.new();
  EXPECT_INT_EQ(shorts.width, sizeof(short));
  EXPECT_INT_EQ(shorts.push(30000), 30000);
  EXPECT_INT_EQ(shorts[0] -= 7, 29993);
  EXPECT_INT_EQ(shorts.len(), 1);
  Var boxed_shorts = shorts;
  EXPECT_TRUE(boxed_shorts is <arrayshort>);
  EXPECT_INT_EQ(boxed_shorts[0].short(), 29993);
  EXPECT_INT_EQ((boxed_shorts[0] += 2).short(), 29995);

  ArrayFloat floats = ArrayFloat.new();
  EXPECT_INT_EQ(floats.width, sizeof(float));
  EXPECT_TRUE(floats.push(1.25f) == 1.25f);
  EXPECT_TRUE((floats[0] += 0.5f) == 1.75f);
  EXPECT_INT_EQ(floats.len(), 1);
  Var boxed_floats = floats;
  EXPECT_TRUE(boxed_floats is <arrayfloat>);
  EXPECT_TRUE(boxed_floats[0].float() == 1.75f);
  EXPECT_TRUE((boxed_floats[0] += 0.25f).float() == 2.0f);

  ArrayLong longs = ArrayLong.new();
  EXPECT_INT_EQ(longs.width, sizeof(long));
  EXPECT_TRUE(longs.push(3000000000L) == 3000000000L);
  EXPECT_TRUE((longs[0] += 7L) == 3000000007L);
  EXPECT_INT_EQ(longs.len(), 1);
  Var boxed_longs = longs;
  EXPECT_TRUE(boxed_longs is <arraylong>);
  EXPECT_TRUE(boxed_longs[0].long() == 3000000007L);
  EXPECT_TRUE((boxed_longs[0] += 3L).long() == 3000000010L);
}

static void typed_array_string_family(void) {
  $test.scoped();
  ArrayString words = %["alpha", "beta"];
  ArrayString empty = ArrayString.new(), missing = NULL;
  String built = String.new_len("alpha!", 5);

  EXPECT_INT_EQ(words.width, sizeof(String));
  EXPECT_INT_EQ(words.len(), 2);
  EXPECT_NULL(missing.array());
  EXPECT_STR_EQ(empty.str(), Array.new().str());
  EXPECT_TRUE(missing.compare(empty) < 0);
  EXPECT_PTR_EQ(words[0], built);
  EXPECT_STR_EQ(words[0] += "-one", "alpha-one");
  EXPECT_STR_EQ(words[0], "alpha-one");

  Var boxed = words;
  EXPECT_TRUE(boxed is <arraystr>);
  EXPECT_PTR_EQ(boxed.arraystring(), words);
  EXPECT_STR_EQ(boxed[1].string(), "beta");
  Array ordinary = words.array();
  EXPECT_STR_EQ(ordinary[0].string(), "alpha-one");

  int count = 0;
  String joined = "";
  foreach (String word, words) {
    joined += word;
    count++;
  }
  EXPECT_INT_EQ(count, 2);
  EXPECT_STR_EQ(joined, "alpha-onebeta");

  int caught = 0;
  try words.updateindex(0, <*>, "x");
  catch %(bad-op *): caught++;
  try words.postfixindex(0, <++>);
  catch %(bad-op *): caught++;
  EXPECT_INT_EQ(caught, 2);
  EXPECT_STR_EQ(words[0], "alpha-one");
}

static void typed_array_copy_slice_and_iteration(void) {
  $test.scoped();
  ArrayInt values = ArrayInt.new();
  for (int i = 0; i < 6; i++) values.push(i);

  ArrayInt copy = values.copy();
  EXPECT_NOT_NULL(copy);
  EXPECT_TRUE(copy.equal(values));
  copy[0] = 99;
  EXPECT_INT_EQ(values[0], 0);
  EXPECT_FALSE(copy.equal(values));
  EXPECT_TRUE(values.contains(4));
  EXPECT_FALSE(values.contains(9));

  ArrayInt skip = values.getslice(0, values.len(), 2);
  EXPECT_INT_EQ(skip.len(), 3);
  EXPECT_INT_EQ(skip[0], 0);
  EXPECT_INT_EQ(skip[1], 2);
  EXPECT_INT_EQ(skip[2], 4);

  ArrayInt reverse = values.getslice(5, 0, -2);
  EXPECT_INT_EQ(reverse.len(), 3);
  EXPECT_INT_EQ(reverse[0], 5);
  EXPECT_INT_EQ(reverse[1], 3);
  EXPECT_INT_EQ(reverse[2], 1);

  int total = 0;
  foreach(int value, values) total += value;
  EXPECT_INT_EQ(total, 15);
}

static void _expect_typed_array_common(
  Var boxed, Var later, Array ordinary,
  String direct_str, String direct_repr,
  Buffer streamed_str, Buffer streamed_repr, int comparison) {
  EXPECT_STR_EQ(direct_str, ordinary.str());
  EXPECT_STR_EQ(direct_repr, ordinary.repr());
  EXPECT_STR_EQ(streamed_str.str(), ordinary.str());
  EXPECT_STR_EQ(streamed_repr.str(), ordinary.repr());
  EXPECT_STR_EQ(boxed.str(), ordinary.str());
  EXPECT_STR_EQ(boxed.repr(), ordinary.repr());
  EXPECT_TRUE(comparison < 0);
  EXPECT_TRUE(boxed.compare(later) < 0);

  Buffer boxed_str = Buffer.new(0), boxed_repr = Buffer.new(0);
  EXPECT_TRUE(boxed.write_str(boxed_str) == boxed_str);
  EXPECT_TRUE(boxed.write_repr(boxed_repr) == boxed_repr);
  EXPECT_STR_EQ(boxed_str.str(), ordinary.str());
  EXPECT_STR_EQ(boxed_repr.str(), ordinary.repr());
}

static void typed_array_common_capabilities_cover_every_family(void) {
  $test.scoped();

  ArrayChar chars = %[1, 2], later_chars = %[1, 3];
  int char_cursor = 0; char char_value = 0;
  EXPECT_TRUE(chars.try_next(&char_cursor, &char_value));
  EXPECT_INT_EQ(char_value, 1);
  Array char_array = chars.array();
  Buffer char_str = Buffer.new(0), char_repr = Buffer.new(0);
  chars.write_str(char_str); chars.write_repr(char_repr);
  _expect_typed_array_common(
    chars, later_chars, char_array, chars.str(), chars.repr(),
    char_str, char_repr, chars.compare(later_chars));
  EXPECT_INT_EQ(char_array[1].char(), 2);

  ArrayShort shorts = %[10, 20], later_shorts = %[10, 30];
  int short_cursor = 0; short short_value = 0;
  EXPECT_TRUE(shorts.try_next(&short_cursor, &short_value));
  EXPECT_INT_EQ(short_value, 10);
  Array short_array = shorts.array();
  Buffer short_str = Buffer.new(0), short_repr = Buffer.new(0);
  shorts.write_str(short_str); shorts.write_repr(short_repr);
  _expect_typed_array_common(
    shorts, later_shorts, short_array, shorts.str(), shorts.repr(),
    short_str, short_repr, shorts.compare(later_shorts));
  EXPECT_INT_EQ(short_array[1].short(), 20);

  ArrayInt ints = %[100, 200], later_ints = %[100, 300];
  int int_cursor = 0, int_value = 0;
  EXPECT_TRUE(ints.try_next(&int_cursor, &int_value));
  EXPECT_INT_EQ(int_value, 100);
  Array int_array = ints.array();
  Buffer int_str = Buffer.new(0), int_repr = Buffer.new(0);
  ints.write_str(int_str); ints.write_repr(int_repr);
  _expect_typed_array_common(
    ints, later_ints, int_array, ints.str(), ints.repr(),
    int_str, int_repr, ints.compare(later_ints));
  EXPECT_INT_EQ(int_array[1].integer(), 200);
  int_array[0] = 999;
  EXPECT_INT_EQ(ints[0], 100);

  ArrayLong longs = %[3000000000L, 3000000001L];
  ArrayLong later_longs = %[3000000000L, 3000000002L];
  int long_cursor = 0; long long_value = 0;
  EXPECT_TRUE(longs.try_next(&long_cursor, &long_value));
  EXPECT_TRUE(long_value == 3000000000L);
  Array long_array = longs.array();
  Buffer long_str = Buffer.new(0), long_repr = Buffer.new(0);
  longs.write_str(long_str); longs.write_repr(long_repr);
  _expect_typed_array_common(
    longs, later_longs, long_array, longs.str(), longs.repr(),
    long_str, long_repr, longs.compare(later_longs));
  EXPECT_TRUE(long_array[1].long() == 3000000001L);

  ArrayFloat floats = %[1.5f, 2.5f], later_floats = %[1.5f, 3.5f];
  int float_cursor = 0; float float_value = 0.0f;
  EXPECT_TRUE(floats.try_next(&float_cursor, &float_value));
  EXPECT_TRUE(float_value == 1.5f);
  Array float_array = floats.array();
  Buffer float_str = Buffer.new(0), float_repr = Buffer.new(0);
  floats.write_str(float_str); floats.write_repr(float_repr);
  _expect_typed_array_common(
    floats, later_floats, float_array, floats.str(), floats.repr(),
    float_str, float_repr, floats.compare(later_floats));
  EXPECT_TRUE(float_array[1].float() == 2.5f);

  ArrayDbl doubles = %[1.5, 2.5], later_doubles = %[1.5, 3.5];
  int double_cursor = 0; double double_value = 0.0;
  EXPECT_TRUE(doubles.try_next(&double_cursor, &double_value));
  EXPECT_TRUE(double_value == 1.5);
  Array double_array = doubles.array();
  Buffer double_str = Buffer.new(0), double_repr = Buffer.new(0);
  doubles.write_str(double_str); doubles.write_repr(double_repr);
  _expect_typed_array_common(
    doubles, later_doubles, double_array, doubles.str(), doubles.repr(),
    double_str, double_repr, doubles.compare(later_doubles));
  EXPECT_TRUE(double_array[1].double() == 2.5);

  ArrayString strings = %["alpha", "beta"];
  ArrayString later_strings = %["alpha", "gamma"];
  int string_cursor = 0; String string_value = NULL;
  EXPECT_TRUE(strings.try_next(&string_cursor, &string_value));
  EXPECT_STR_EQ(string_value, "alpha");
  Array string_array = strings.array();
  Buffer string_str = Buffer.new(0), string_repr = Buffer.new(0);
  strings.write_str(string_str); strings.write_repr(string_repr);
  _expect_typed_array_common(
    strings, later_strings, string_array, strings.str(), strings.repr(),
    string_str, string_repr, strings.compare(later_strings));
  EXPECT_STR_EQ(string_array[1].string(), "beta");
}

static void typed_array_common_capabilities_keep_null_and_float_order(void) {
  $test.scoped();
  ArrayInt missing = NULL, empty = ArrayInt.new();
  int cursor = 0, value = 71;

  EXPECT_FALSE(missing.try_next(&cursor, &value));
  EXPECT_FALSE(empty.try_next(&cursor, &value));
  EXPECT_FALSE(empty.try_next(NULL, &value));
  EXPECT_FALSE(empty.try_next(&cursor, NULL));
  EXPECT_INT_EQ(cursor, 0);
  EXPECT_INT_EQ(value, 71);
  EXPECT_NULL(missing.array());
  EXPECT_STR_EQ(missing.str(), ((Array) NULL).str());
  EXPECT_STR_EQ(empty.repr(), Array.new().repr());
  EXPECT_TRUE(missing.compare(empty) < 0);
  EXPECT_INT_EQ(missing.compare(NULL), 0);

  ArrayFloat positive_zero = %[0.0f], negative_zero = %[-0.0f];
  EXPECT_INT_EQ(positive_zero.compare(negative_zero),
                Var.compare(0.0f, -0.0f));
  ArrayDbl nan = %[${0.0 / 0.0}], infinity = %[${1.0 / 0.0}];
  EXPECT_INT_EQ(nan.compare(infinity),
                Var.compare(0.0 / 0.0, 1.0 / 0.0));
}

static void typed_array_int_sequence_mutations(void) {
  $test.scoped();
  ArrayInt values = ArrayInt.new();
  values.push(1);
  values.push(2);
  values.push(3);

  EXPECT_INT_EQ(values.unshift(0), 0);
  EXPECT_INT_EQ(values.insert(-1, 8), 8);
  EXPECT_INT_EQ(values.remove(-2), 3);
  EXPECT_INT_EQ(values.shift(), 0);
  EXPECT_INT_EQ(values.len(), 3);
  EXPECT_INT_EQ(values[0], 1);
  EXPECT_INT_EQ(values[1], 2);
  EXPECT_INT_EQ(values[2], 8);
}

static void typed_array_int_slice_search_and_concat(void) {
  $test.scoped();
  ArrayInt values = ArrayInt.new();
  for (int i = 0; i < 5; i++) values.push(i);

  values.setslice(1, 3, values);
  EXPECT_INT_EQ(values.len(), 8);
  EXPECT_INT_EQ(values[0], 0);
  EXPECT_INT_EQ(values[1], 0);
  EXPECT_INT_EQ(values[5], 4);
  EXPECT_INT_EQ(values[6], 3);
  EXPECT_INT_EQ(values[7], 4);

  ArrayInt removed = values.remslice(6, 2);
  EXPECT_INT_EQ(removed.len(), 4);
  EXPECT_INT_EQ(removed[0], 1);
  EXPECT_INT_EQ(removed[3], 4);
  EXPECT_INT_EQ(values.len(), 4);
  EXPECT_INT_EQ(values[0], 0);
  EXPECT_INT_EQ(values[1], 0);
  EXPECT_INT_EQ(values[2], 3);
  EXPECT_INT_EQ(values[3], 4);

  ArrayInt alias = ArrayInt.new();
  alias.push(1);
  alias.push(2);
  alias.push(3);
  ArrayInt spliced = alias.splice(1, 1, alias);
  EXPECT_INT_EQ(spliced.len(), 1);
  EXPECT_INT_EQ(spliced[0], 2);
  EXPECT_INT_EQ(alias.len(), 5);
  EXPECT_INT_EQ(alias[0], 1);
  EXPECT_INT_EQ(alias[1], 1);
  EXPECT_INT_EQ(alias[2], 2);
  EXPECT_INT_EQ(alias[3], 3);
  EXPECT_INT_EQ(alias[4], 3);

  EXPECT_INT_EQ(alias.find(3), 3);
  EXPECT_INT_EQ(alias.indexof(9), -1);
  EXPECT_INT_EQ(alias.count(1), 2);

  ArrayInt combined = values.concat(alias);
  EXPECT_INT_EQ(combined.len(), 9);
  combined[0] = 99;
  alias[0] = 77;
  EXPECT_INT_EQ(values[0], 0);
  EXPECT_INT_EQ(combined[4], 1);

  EXPECT_TRUE(combined.reverse() == combined);
  EXPECT_INT_EQ(combined[0], 3);
  EXPECT_INT_EQ(combined[8], 99);
}

static void typed_array_double_generated_sequences(void) {
  $test.scoped();
  ArrayDbl values = ArrayDbl.new();
  values.push(1.5);
  values.push(2.5);
  values.push(3.5);
  ArrayDbl replacement = ArrayDbl.new();
  replacement.push(8.5);
  replacement.push(9.5);

  values.setslice(1, 2, replacement);
  EXPECT_INT_EQ(values.len(), 4);
  EXPECT_TRUE(values[0] == 1.5);
  EXPECT_TRUE(values[1] == 8.5);
  EXPECT_TRUE(values[2] == 9.5);
  EXPECT_TRUE(values[3] == 3.5);
  EXPECT_INT_EQ(values.find(9.5), 2);
  EXPECT_INT_EQ(values.count(8.5), 1);

  ArrayDbl combined = values.concat(replacement);
  replacement[0] = 10.5;
  EXPECT_TRUE(combined[4] == 8.5);
  combined.reverse();
  EXPECT_TRUE(combined[0] == 9.5);
  EXPECT_TRUE(combined.shift() == 9.5);
  EXPECT_TRUE(combined.remove(-1) == 1.5);
}

static void typed_array_int_raise_paths_transfer(void) {
  $test.scoped();
  ArrayInt values = ArrayInt.new();
  values.push(10);
  values.push(20);
  int caught = 0;

  try values.getslice(0, 2, 0);
  catch %(bad-arg *detail): {
    caught++;
    EXPECT_INT_EQ(detail.assoc(<step>).integer(), 0);
  }

  ArrayInt empty = ArrayInt.new();
  try empty.take_last();
  catch %(bad-arg *detail): {
    caught++;
    EXPECT_TRUE(detail.assoc(<operation>).symbol() == <take-last>);
  }
  try empty.shift();
  catch %(bad-arg *detail): {
    caught++;
    EXPECT_TRUE(detail.assoc(<operation>).symbol() == <shift>);
  }
  try empty.remove(0);
  catch %(bad-arg *detail): {
    caught++;
    EXPECT_INT_EQ(detail.assoc(<index>).integer(), 0);
  }

  try values.postfixindex(0, <+>);
  catch %(bad-op *detail): {
    caught++;
    EXPECT_TRUE(detail.assoc(<op>).symbol() == <+>);
  }
  EXPECT_INT_EQ(values[0], 10);

  ArrayInt missing = NULL;
  try missing.push(7);
  catch %(bad-arg *detail): {
    caught++;
    EXPECT_TRUE(detail.assoc(<operation>).symbol() == <push>);
    EXPECT_STR_EQ(detail.assoc(<owner>).string(), "ArrayInt");
  }
  EXPECT_INT_EQ(caught, 6);
}

static void typed_array_double_raise_paths_transfer(void) {
  $test.scoped();
  ArrayDbl values = ArrayDbl.new();
  values.push(1.25);
  int caught = 0;

  try values.getslice(0, 1, 0);
  catch %(bad-arg *detail): {
    caught++;
    EXPECT_STR_EQ(detail.assoc(<owner>).string(), "ArrayDbl");
  }

  ArrayDbl empty = ArrayDbl.new();
  try empty.take_last();
  catch %(bad-arg *): caught++;

  try values.postfixindex(0, <*>);
  catch %(bad-op *): caught++;

  ArrayDbl missing = NULL;
  try missing.push(2.5);
  catch %(bad-arg *): caught++;
  EXPECT_INT_EQ(caught, 4);
}

static void typed_array_compound_update_is_native(void) {
  $test.scoped();
  ArrayInt values = ArrayInt.new();
  values.push(20);

  EXPECT_INT_EQ(values[0] += 3, 23);
  EXPECT_INT_EQ(values[0] -= 3, 20);
  EXPECT_INT_EQ(values[0] *= 3, 60);
  EXPECT_INT_EQ(values[0] /= 4, 15);
  EXPECT_INT_EQ(values[0] %= 4, 3);
  EXPECT_INT_EQ(values[0] <<= 4, 48);
  EXPECT_INT_EQ(values[0] >>= 2, 12);
  EXPECT_INT_EQ(values[0] &= 10, 8);
  EXPECT_INT_EQ(values[0] |= 5, 13);
  EXPECT_INT_EQ(values[0] ^= 3, 14);

  // a signed right shift keeps the sign, and overflow wraps rather than
  // trapping, exactly as the boxed path did
  values[0] = -16;
  EXPECT_INT_EQ(values[0] >>= 2, -4);
  values[0] = INT_MAX;
  EXPECT_INT_EQ(values[0] += 1, INT_MIN);
  EXPECT_INT_EQ(values[0] /= -1, INT_MIN);
  EXPECT_INT_EQ(values[0] %= -1, 0);
}

// The one behavior the native path does not keep: a result too wide for a
// narrow element truncates as C does, where boxing raised <conv-range>.
static void typed_array_narrow_update_truncates(void) {
  $test.scoped();
  ArrayChar bytes = ArrayChar.new();
  bytes.push(100);
  ArrayShort shorts = ArrayShort.new();
  shorts.push(30000);

  EXPECT_INT_EQ(bytes[0] += 100, -56);
  EXPECT_INT_EQ(shorts[0] += 30000, -5536);
}

static void typed_array_update_faults_transfer(void) {
  $test.scoped();
  ArrayInt values = ArrayInt.new();
  values.push(7);
  ArrayDbl reals = ArrayDbl.new();
  reals.push(1.5);
  int caught = 0;

  try values[0] /= 0;
  catch %(div-zero *detail): {
    caught++;
    EXPECT_TRUE(detail.assoc(<op>).symbol() == </>);
  }
  try values[0] %= 0;
  catch %(div-zero *): caught++;

  try values[0] <<= 32;
  catch %(bad-shift *detail): {
    caught++;
    EXPECT_INT_EQ(detail.assoc(<count>).integer(), 32);
    EXPECT_INT_EQ(detail.assoc(<width>).integer(), 32);
  }
  try values[0] >>= -1;
  catch %(bad-shift *): caught++;

  // % and the bitwise operators are not defined on a float element
  try reals[0] %= 2.0;
  catch %(bad-types *detail): {
    caught++;
    EXPECT_TRUE(detail.assoc(<op>).symbol() == <%>);
  }

  EXPECT_INT_EQ(caught, 5);
  // every failure raised before storing, so both elements are untouched
  EXPECT_INT_EQ(values[0], 7);
  EXPECT_TRUE(reals[0] == 1.5);
}

void typed_array_suite(void) {
  $test.run(typed_array_keeps_array_unchanged);
  $test.run(typed_array_packs_array_literals);
  $test.run(typed_array_int_uses_packed_storage);
  $test.run(typed_array_native_updates_and_var_transport);
  $test.run(typed_array_double_uses_native_values);
  $test.run(typed_array_additional_scalar_families);
  $test.run(typed_array_string_family);
  $test.run(typed_array_copy_slice_and_iteration);
  $test.run(typed_array_common_capabilities_cover_every_family);
  $test.run(typed_array_common_capabilities_keep_null_and_float_order);
  $test.run(typed_array_int_sequence_mutations);
  $test.run(typed_array_int_slice_search_and_concat);
  $test.run(typed_array_double_generated_sequences);
  $test.run(typed_array_int_raise_paths_transfer);
  $test.run(typed_array_double_raise_paths_transfer);
  $test.run(typed_array_compound_update_is_native);
  $test.run(typed_array_narrow_update_truncates);
  $test.run(typed_array_update_faults_transfer);
}
