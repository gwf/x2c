/*  test-typed-map.x -- native typed Map tests */

#include "typed-map.x"
#include "test-support.x"
$(import "test-macros.xmacro")

/* Mirrors x2c_hash_word as used by lib/typed-map.x. The collision tests below
   choose keys by bucket, so the two must agree. */
static unsigned _test_typed_map_hash(int key) {
  uint64_t word = (unsigned) key;
  word ^= word >> 33;
  word *= 0xff51afd7ed558ccdull;
  word ^= word >> 33;
  word *= 0xc4ceb9fe1a85ec53ull;
  word ^= word >> 33;
  unsigned hash = (unsigned) word;
  return hash ? hash : -1;
}

static void _typed_map_colliding_keys(
  int *keys, int count, unsigned mask, unsigned bucket) {
  int found = 0;
  for (int candidate = 0; found < count; candidate++) {
    if ((_test_typed_map_hash(candidate) & mask) == bucket)
      keys[found++] = candidate;
  }
}

static void typed_map_packs_map_literals(void) {
  $test.scoped();
  MapIntInt counts = %{1: 2, 3: 4};
  MapLongDouble ratios = %{10: 0.5};
  MapIntInt empty = %{};
  Map missing = NULL;
  MapIntInt unpacked = missing;
  MapIntInt refused = MapIntInt.new();
  int caught = 0;

  EXPECT_INT_EQ(counts.len(), 2);
  EXPECT_INT_EQ(counts.get(1), 2);
  EXPECT_INT_EQ(counts.get(3), 4);
  EXPECT_TRUE(ratios.get(10L) == 0.5);
  EXPECT_INT_EQ(empty.len(), 0);
  EXPECT_NULL(unpacked);

  try refused = %{1: "two"};
  catch %(no-convert *): caught++;
  EXPECT_INT_EQ(caught, 1);
  EXPECT_INT_EQ(refused.len(), 0);
}

static void typed_map_empty_native_layout_and_zero_data(void) {
  $test.scoped();
  MapIntInt first = MapIntInt.new(), second = MapIntInt.new();
  MapIntInt reserved = MapIntInt.new_capacity(8);

  EXPECT_NOT_NULL(first);
  EXPECT_NOT_NULL(second);
  /* Two separately built empty maps are distinct objects but equal contents,
     the same split `Map` has: `===` is identity and `==` is structural. */
  EXPECT_FALSE(first === second);
  EXPECT_TRUE(first == second);
  EXPECT_INT_EQ(reserved.capacity, 8);
  EXPECT_INT_EQ(reserved.mask, 7);
  EXPECT_INT_EQ(first.len(), 0);
  EXPECT_INT_EQ(first.capacity, 2);
  EXPECT_INT_EQ(first.mask, 1);
  EXPECT_INT_EQ(first.entries.block().width, sizeof(struct MapIntIntRecord));
  EXPECT_TRUE(sizeof(struct MapIntIntRecord) < 2 * sizeof(Var));
  EXPECT_INT_EQ(sizeof(struct MapIntIntRecord), 2 * sizeof(int));

  first.set(0, 0);
  int out = 71;
  EXPECT_TRUE(first.try_get(0, &out));
  EXPECT_INT_EQ(out, 0);
  EXPECT_INT_EQ(first.len(), 1);
  EXPECT_TRUE(first.truth());
  EXPECT_FALSE(second.truth());
}

static void typed_map_lookup_replace_and_defaults(void) {
  $test.scoped();
  MapIntInt map = MapIntInt.new();
  int out = 91;

  EXPECT_FALSE(map.try_get(4, &out));
  EXPECT_INT_EQ(out, 91);
  EXPECT_INT_EQ(map.getdefault(4, 27), 27);
  EXPECT_INT_EQ(map.len(), 0);
  EXPECT_INT_EQ(map.setdefault(4, 12), 12);
  EXPECT_INT_EQ(map.setdefault(4, 99), 12);
  EXPECT_INT_EQ(map.get(4), 12);
  EXPECT_INT_EQ(map.getindex(4), 12);
  EXPECT_TRUE(map.contains(4));

  unsigned capacity = map.capacity;
  map.set(4, 18);
  EXPECT_INT_EQ(map.capacity, capacity);
  EXPECT_INT_EQ(map.len(), 1);
  EXPECT_INT_EQ(map.getindex(4), 18);
  EXPECT_INT_EQ(map.setindex(4, 21), 21);
  EXPECT_INT_EQ(map.getindex(4), 21);
  map.setindex(5, 31);
  EXPECT_INT_EQ(map.del(5), 31);
  EXPECT_FALSE(map.contains(5));
}

static void typed_map_numeric_updates_and_postfix(void) {
  $test.scoped();
  MapIntInt map = MapIntInt.new();

  EXPECT_INT_EQ(map.updateindex(8, <+>, 5), 5);
  EXPECT_INT_EQ(map.len(), 1);
  EXPECT_INT_EQ(map.updateindex(8, <+>, 3), 8);
  EXPECT_INT_EQ(map.updateindex(8, <*>, 4), 32);
  EXPECT_INT_EQ(map.updateindex(8, <->, 2), 30);
  EXPECT_INT_EQ(map.updateindex(8, </>, 3), 10);
  EXPECT_INT_EQ(map.updateindex(8, <%>, 6), 4);
  EXPECT_INT_EQ(map.updateindex(8, <|>, 8), 12);
  EXPECT_INT_EQ(map.updateindex(8, <&>, 10), 8);
  EXPECT_INT_EQ(map.updateindex(8, <^>, 3), 11);
  EXPECT_INT_EQ(map.updateindex(8, <"<<">, 1), 22);
  EXPECT_INT_EQ(map.updateindex(8, <">>">, 1), 11);
  EXPECT_INT_EQ(map.postfixindex(8, <++>), 11);
  EXPECT_INT_EQ(map.getindex(8), 12);
  EXPECT_INT_EQ(map.postfixindex(8, <-->) , 12);
  EXPECT_INT_EQ(map.getindex(8), 11);
}

static void typed_map_growth_collision_backshift_and_reuse(void) {
  $test.scoped();
  int keys[5];
  _typed_map_colliding_keys(keys, 5, 7, 7);
  MapIntInt map = MapIntInt.new_capacity(8);

  for (int i = 0; i < 3; i++) map.setindex(keys[i], i + 10);
  EXPECT_INT_EQ(map.capacity, 8);

  int out = -1;
  EXPECT_TRUE(map.try_del(keys[1], &out));
  EXPECT_INT_EQ(out, 11);
  EXPECT_FALSE(map.contains(keys[1]));
  EXPECT_INT_EQ(map.getindex(keys[0]), 10);
  EXPECT_INT_EQ(map.getindex(keys[2]), 12);

  map.setindex(keys[3], 30);
  EXPECT_INT_EQ(map.getindex(keys[3]), 30);
  map.setindex(keys[4], 40);
  EXPECT_INT_EQ(map.getindex(keys[4]), 40);

  for (int i = 100; i < 228; i++) map.setindex(i, i * 7);
  EXPECT_TRUE(map.capacity >= 256);
  for (int i = 100; i < 228; i++)
    EXPECT_INT_EQ(map.getindex(i), i * 7);
}

static void typed_map_traversal_copy_merge_and_equal(void) {
  $test.scoped();
  MapIntInt map = MapIntInt.new();
  int seen[64] = { 0 };
  for (int i = 0; i < 64; i++) map.setindex(i, i * 11);

  unsigned cursor = 0;
  int key, val, visited = 0;
  while (map.try_next(&cursor, &key, &val)) {
    EXPECT_TRUE(key >= 0 && key < 64);
    if (key >= 0 && key < 64) {
      EXPECT_FALSE(seen[key]);
      EXPECT_INT_EQ(val, key * 11);
      seen[key] = 1;
    }
    visited++;
  }
  EXPECT_INT_EQ(visited, 64);

  MapIntInt copy = map.copy();
  EXPECT_TRUE(copy.equal(map));
  copy.setindex(0, 999);
  EXPECT_INT_EQ(map.getindex(0), 0);
  EXPECT_FALSE(copy.equal(map));

  MapIntInt other = MapIntInt.new();
  other.setindex(0, 17);
  other.setindex(100, 23);
  EXPECT_TRUE(map.merge(other) == map);
  EXPECT_INT_EQ(map.getindex(0), 17);
  EXPECT_INT_EQ(map.getindex(100), 23);
  unsigned length = map.len();
  EXPECT_TRUE(map.merge(map) == map);
  EXPECT_INT_EQ(map.len(), length);
  EXPECT_TRUE(MapIntInt.merge(NULL, other).equal(other));
}

static void typed_map_missing_and_null_status_paths(void) {
  $test.scoped();
  MapIntInt map = MapIntInt.new(), missing = NULL;
  int out = 73, key = 61, val = 62;
  unsigned cursor = 0;

  EXPECT_FALSE(map.try_get(4, &out));
  EXPECT_INT_EQ(out, 73);
  EXPECT_FALSE(map.try_del(4, &out));
  EXPECT_INT_EQ(out, 73);
  EXPECT_FALSE(map.try_get(4, NULL));
  EXPECT_FALSE(missing.try_get(4, &out));
  EXPECT_FALSE(missing.try_del(4, &out));
  EXPECT_FALSE(missing.try_next(&cursor, &key, &val));
  EXPECT_FALSE(map.try_next(NULL, &key, &val));
  EXPECT_FALSE(map.try_next(&cursor, NULL, &val));
  EXPECT_FALSE(map.try_next(&cursor, &key, NULL));
  EXPECT_INT_EQ(cursor, 0);
  EXPECT_INT_EQ(key, 61);
  EXPECT_INT_EQ(val, 62);
  EXPECT_INT_EQ(missing.len(), 0);
  EXPECT_FALSE(missing.truth());
  EXPECT_TRUE(missing.equal(NULL));
}

static void typed_map_errors_transfer(void) {
  $test.scoped();
  MapIntInt map = MapIntInt.new();
  int caught = 0;
  try map.get(99);
  catch %(bad-arg *): caught++;
  try map.getindex(99);
  catch %(bad-arg *): caught++;
  try map.del(99);
  catch %(bad-arg *): caught++;
  try map.updateindex(99, <*>, 2);
  catch %(bad-arg *): caught++;
  try map.postfixindex(99, <++>);
  catch %(bad-arg *): caught++;
  try MapIntInt.new_capacity(3);
  catch %(bad-arg *): caught++;
  try MapIntInt.set(NULL, 1, 2);
  catch %(bad-arg *): caught++;
  EXPECT_INT_EQ(caught, 7);
}

static void typed_map_independent_key_value_widths(void) {
  $test.scoped();
  MapLongDouble map = MapLongDouble.new();
  long large = 3000000000L;

  EXPECT_INT_EQ(map.entries.block().width,
                sizeof(struct MapLongDoubleRecord));
  EXPECT_INT_EQ(sizeof(struct MapLongDoubleRecord),
                sizeof(long) + sizeof(double));
  EXPECT_TRUE(sizeof(((struct MapLongDoubleRecord *) 0).key) == sizeof(long));
  EXPECT_TRUE(sizeof(((struct MapLongDoubleRecord *) 0).val) ==
              sizeof(double));
  map.setindex(large, 1.25);
  map.setindex(0, 0.0);
  EXPECT_TRUE(map.getindex(large) == 1.25);
  EXPECT_TRUE(map.updateindex(large, <+>, 0.5) == 1.75);
  EXPECT_TRUE(map.postfixindex(large, <++>) == 1.75);
  EXPECT_TRUE(map.getindex(large) == 2.75);
  double out = 19.0;
  EXPECT_TRUE(map.try_del(0, &out));
  EXPECT_TRUE(out == 0.0);
  for (long i = 1; i < 33; i++) map.setindex(i, i * 0.5);
  EXPECT_TRUE(map.capacity >= 64);
  unsigned cursor = 0;
  long key;
  double value, total = 0.0;
  int visited = 0;
  while (map.try_next(&cursor, &key, &value)) {
    total += value;
    visited++;
  }
  EXPECT_INT_EQ(visited, map.len());
  EXPECT_TRUE(total > 260.0);
  MapLongDouble copy = map.copy();
  EXPECT_TRUE(copy.equal(map));
  MapLongDouble other = MapLongDouble.new();
  other.setindex(large, 9.5);
  other.setindex(100L, 4.25);
  map.merge(other);
  EXPECT_TRUE(map.getindex(large) == 9.5);
  EXPECT_TRUE(map.getindex(100L) == 4.25);
}

static void typed_map_interned_string_keys_and_values(void) {
  $test.scoped();
  MapStringString map = MapStringString.new();
  String built = String.new_len("alpha!", 5);
  String out = NULL;

  EXPECT_INT_EQ(map.entries.block().width,
                sizeof(struct MapStringStringRecord));
  map.setindex("alpha", "one");
  map.setindex("beta", "two");
  EXPECT_INT_EQ(map.len(), 2);
  EXPECT_STR_EQ(map.getindex("alpha"), "one");
  EXPECT_STR_EQ(map.getdefault("gamma", "none"), "none");
  EXPECT_TRUE(map.contains("beta"));

  /* A String assembled at run time canonicalizes to the same pointer, so it
     finds the entry stored under the literal. */
  EXPECT_TRUE(map.try_get(built, &out));
  EXPECT_STR_EQ(out, "one");

  /* The empty String is NULL and hashes to zero, the value reserved for an
     empty bucket, so it is the one key that exercises the fallback. */
  map.setindex("", "empty");
  EXPECT_STR_EQ(map.getindex(""), "empty");
  EXPECT_STR_EQ(map.del(""), "empty");
  EXPECT_FALSE(map.contains(""));
  map.setindex("blank", "");
  EXPECT_NULL(map.getindex("blank"));

  EXPECT_STR_EQ(map.updateindex("alpha", <+>, "-two"), "one-two");
  EXPECT_STR_EQ(map.updateindex("gamma", <+>, "three"), "three");
  EXPECT_STR_EQ(map.setdefault("beta", "ignored"), "two");
  EXPECT_STR_EQ(map.del("beta"), "two");
  EXPECT_INT_EQ(map.len(), 3);
}

static void typed_map_string_growth_traversal_and_errors(void) {
  $test.scoped();
  MapStringString map = MapStringString.new();
  int caught = 0;

  for (int i = 0; i < 200; i++) {
    String key = String.printf("key-%d", i);
    map.setindex(key, String.printf("value-%d", i));
  }
  EXPECT_TRUE(map.capacity >= 256);
  EXPECT_INT_EQ(map.len(), 200);
  EXPECT_STR_EQ(map.getindex("key-199"), "value-199");

  unsigned cursor = 0;
  String key = NULL, val = NULL;
  int visited = 0;
  while (map.try_next(&cursor, &key, &val)) {
    EXPECT_TRUE(key.startswith("key-"));
    visited++;
  }
  EXPECT_INT_EQ(visited, 200);

  MapStringString copy = map.copy();
  EXPECT_TRUE(copy.equal(map));
  copy.setindex("key-0", "changed");
  EXPECT_FALSE(copy.equal(map));

  try map.getindex("absent");
  catch %(bad-arg *): caught++;
  try map.postfixindex("key-0", <++>);
  catch %(bad-op *): caught++;
  EXPECT_STR_EQ(map.getindex("key-0"), "value-0");
  try map.postfixindex("key-0", <-->);
  catch %(bad-op *): caught++;
  try map.updateindex("key-0", <*>, "x");
  catch %(bad-op *): caught++;
  try MapStringString.set(NULL, "key", "value");
  catch %(bad-arg *): caught++;
  EXPECT_INT_EQ(caught, 5);
}

static void typed_map_string_int_family(void) {
  $test.scoped();
  MapStringInt counts = %{"alpha": 5, "beta": 7};
  MapStringInt empty = MapStringInt.new(), missing = NULL;
  String built = String.new_len("alpha!", 5);
  int out = 0;

  EXPECT_INT_EQ(counts.entries.block().width,
                sizeof(struct MapStringIntRecord));
  EXPECT_NULL(missing.map());
  EXPECT_STR_EQ(empty.str(), Map.new().str());
  EXPECT_TRUE(missing.compare(empty) < 0);
  EXPECT_TRUE(counts.try_get(built, &out));
  EXPECT_INT_EQ(out, 5);
  EXPECT_INT_EQ(counts["alpha"] += 3, 8);
  EXPECT_INT_EQ(counts["alpha"] *= 4, 32);
  EXPECT_INT_EQ(counts["alpha"] -= 2, 30);
  EXPECT_INT_EQ(counts["alpha"] /= 3, 10);
  EXPECT_INT_EQ(counts["alpha"] %= 6, 4);
  EXPECT_INT_EQ(counts["alpha"] |= 8, 12);
  EXPECT_INT_EQ(counts["alpha"] &= 10, 8);
  EXPECT_INT_EQ(counts["alpha"] ^= 3, 11);
  EXPECT_INT_EQ(counts["alpha"] <<= 1, 22);
  EXPECT_INT_EQ(counts["alpha"] >>= 1, 11);
  EXPECT_INT_EQ(counts["alpha"]++, 11);
  EXPECT_INT_EQ(counts["alpha"]--, 12);
  EXPECT_INT_EQ(counts["alpha"], 11);
  EXPECT_INT_EQ(counts["gamma"] += 13, 13);

  Var boxed = counts;
  EXPECT_TRUE(boxed is <mapstrint>);
  EXPECT_PTR_EQ(boxed.mapstringint(), counts);
  EXPECT_INT_EQ(boxed["beta"].integer(), 7);
  Map ordinary = counts.map();
  EXPECT_INT_EQ(ordinary["gamma"].integer(), 13);

  int visited = 0, total = 0;
  foreach (int value, counts) {
    total += value;
    visited++;
  }
  EXPECT_INT_EQ(visited, 3);
  EXPECT_INT_EQ(total, 31);

  struct Iter key_storage;
  int keys = 0;
  foreach (String key, counts.keys(&key_storage)) {
    EXPECT_TRUE(key == %"alpha" || key == %"beta" || key == %"gamma");
    keys++;
  }
  EXPECT_INT_EQ(keys, 3);
}

static void _expect_typed_map_common(
  Var boxed, Var later, Map ordinary,
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

static void typed_map_common_capabilities_cover_every_family(void) {
  $test.scoped();

  MapIntInt ints = %{1: 2}, later_ints = %{1: 3};
  Map int_map = ints.map();
  Buffer int_str = Buffer.new(0), int_repr = Buffer.new(0);
  ints.write_str(int_str); ints.write_repr(int_repr);
  _expect_typed_map_common(
    ints, later_ints, int_map, ints.str(), ints.repr(),
    int_str, int_repr, ints.compare(later_ints));
  EXPECT_INT_EQ(int_map[1].integer(), 2);
  int_map[1] = 99;
  EXPECT_INT_EQ(ints[1], 2);

  MapLongDouble doubles = %{10L: 2.5};
  MapLongDouble later_doubles = %{10L: 3.5};
  Map double_map = doubles.map();
  Buffer double_str = Buffer.new(0), double_repr = Buffer.new(0);
  doubles.write_str(double_str); doubles.write_repr(double_repr);
  _expect_typed_map_common(
    doubles, later_doubles, double_map, doubles.str(), doubles.repr(),
    double_str, double_repr, doubles.compare(later_doubles));
  EXPECT_TRUE(double_map[10L].double() == 2.5);

  MapStringString strings = %{"alpha": "one"};
  MapStringString later_strings = %{"alpha": "two"};
  Map string_map = strings.map();
  Buffer string_str = Buffer.new(0), string_repr = Buffer.new(0);
  strings.write_str(string_str); strings.write_repr(string_repr);
  _expect_typed_map_common(
    strings, later_strings, string_map, strings.str(), strings.repr(),
    string_str, string_repr, strings.compare(later_strings));
  EXPECT_STR_EQ(string_map["alpha"].string(), "one");

  MapStringInt string_ints = %{"alpha": 1};
  MapStringInt later_string_ints = %{"alpha": 2};
  Map string_int_map = string_ints.map();
  Buffer string_int_str = Buffer.new(0), string_int_repr = Buffer.new(0);
  string_ints.write_str(string_int_str);
  string_ints.write_repr(string_int_repr);
  _expect_typed_map_common(
    string_ints, later_string_ints, string_int_map,
    string_ints.str(), string_ints.repr(),
    string_int_str, string_int_repr,
    string_ints.compare(later_string_ints));
  EXPECT_INT_EQ(string_int_map["alpha"].integer(), 1);
}

static void typed_map_common_capabilities_keep_null_and_float_order(void) {
  $test.scoped();
  MapIntInt missing = NULL, empty = MapIntInt.new();

  EXPECT_NULL(missing.map());
  EXPECT_STR_EQ(missing.str(), ((Map) NULL).str());
  EXPECT_STR_EQ(empty.str(), Map.new().str());
  EXPECT_STR_EQ(missing.repr(), ((Map) NULL).repr());
  EXPECT_TRUE(missing.compare(empty) < 0);
  EXPECT_INT_EQ(missing.compare(NULL), 0);

  MapLongDouble positive_zero = %{1L: 0.0};
  MapLongDouble negative_zero = %{1L: -0.0};
  EXPECT_INT_EQ(positive_zero.compare(negative_zero),
                Var.compare(0.0, -0.0));
  MapLongDouble nan = %{1L: ${0.0 / 0.0}};
  MapLongDouble infinity = %{1L: ${1.0 / 0.0}};
  EXPECT_INT_EQ(nan.compare(infinity),
                Var.compare(0.0 / 0.0, 1.0 / 0.0));
}

/* A generated family iterates the same three ways the Var Map does, and a
   foreach over one binds the native type without crossing Var. */
static void typed_map_iterates_values_keys_and_pairs(void) {
  MapIntInt counts = MapIntInt.new();
  counts.set(1, 10);
  counts.set(2, 20);
  counts.set(3, 30);

  int values = 0, keys = 0, pair_keys = 0, pair_values = 0, counted = 0;
  foreach(int value, counts) values += value;
  foreach(int (key, value), counts) {
    pair_keys += key;
    pair_values += value;
    counted++;
  }

  struct Iter key_storage;
  foreach(Var key, counts.keys(&key_storage)) keys += key.integer();

  EXPECT_INT_EQ(counted, 3);
  EXPECT_INT_EQ(values, 60);
  EXPECT_INT_EQ(keys, 6);
  EXPECT_INT_EQ(pair_keys, 6);
  EXPECT_INT_EQ(pair_values, 60);

  MapStringString names = MapStringString.new();
  names.set(%"ada", %"lovelace");
  names.set(%"grace", %"hopper");
  int lengths = 0;
  foreach(String value, names) lengths += value.len();
  EXPECT_INT_EQ(lengths, 14);

  MapStringInt counts_by_name = %{"ada": 3, "grace": 5};
  int total = 0;
  foreach (int value, counts_by_name) total += value;
  EXPECT_INT_EQ(total, 8);
}

void typed_map_suite(void) {
  $test.run(typed_map_iterates_values_keys_and_pairs);
  $test.run(typed_map_common_capabilities_cover_every_family);
  $test.run(typed_map_common_capabilities_keep_null_and_float_order);
  $test.run(typed_map_packs_map_literals);
  $test.run(typed_map_empty_native_layout_and_zero_data);
  $test.run(typed_map_lookup_replace_and_defaults);
  $test.run(typed_map_numeric_updates_and_postfix);
  $test.run(typed_map_growth_collision_backshift_and_reuse);
  $test.run(typed_map_traversal_copy_merge_and_equal);
  $test.run(typed_map_missing_and_null_status_paths);
  $test.run(typed_map_errors_transfer);
  $test.run(typed_map_independent_key_value_widths);
  $test.run(typed_map_interned_string_keys_and_values);
  $test.run(typed_map_string_growth_traversal_and_errors);
  $test.run(typed_map_string_int_family);
}
