/*  test-map.x -- unit tests for map implementation */

#include <string.h>

#include "test-support.x"
$(import "test-macros.xmacro")


typedef struct MapProbe {
  unsigned long value;
} MapProbe;

static int map_probe_hash_calls;

static unsigned _map_probe_hash(Var value) {
  map_probe_hash_calls++;
  MapProbe *probe = value;
  return probe.value;
}

static int _map_probe_equal(Var a, Var b) {
  MapProbe *left = a, *right = b;
  return left.value == right.value;
}

static void map_empty_literal_identity(void) {
  $test.scoped();
  Map first = %{}, second = %{};

  EXPECT_NOT_NULL(first);
  EXPECT_NOT_NULL(second);
  EXPECT_FALSE(first === second);
  EXPECT_INT_EQ(first.len(), 0);
  EXPECT_INT_EQ(second.len(), 0);
  first[<answer>] = 42;
  EXPECT_INT_EQ(first.len(), 1);
  EXPECT_INT_EQ(first[<answer>].int(), 42);
  EXPECT_INT_EQ(second.len(), 0);
}

static void map_set_get_updates(void) {
  $test.scoped();
  Map map = %{};
  map.set(<a>, 1);
  map.set(<b>, 2);
  EXPECT_INT_EQ(map.len(), 2);
  EXPECT_INT_EQ(map.get(<a>).int(), 1);
  EXPECT_INT_EQ(map.get(<b>).int(), 2);
  map.set(<a>, 42);
  EXPECT_INT_EQ(map.get(<a>).int(), 42);
}

static void map_void_writes_transfer_before_mutation(void) {
  $test.scoped();
  Map map = %{};
  int caught = 0;

  try map.set(void, 1);
  catch %(void-op *): caught++;
  try map.set(<key>, void);
  catch %(void-op *): caught++;
  try map.setindex(void, 1);
  catch %(void-op *): caught++;
  try map.setdefault(<missing>, void);
  catch %(void-op *): caught++;
  try Map.set(NULL, <key>, 1);
  catch %(bad-arg *): caught++;
  EXPECT_INT_EQ(caught, 5);
  EXPECT_INT_EQ(map.len(), 0);
}

static void map_delete_and_len(void) {
  $test.scoped();
  Map map = %{<a>: 10, <b>: 20};
  EXPECT_INT_EQ(map.len(), 2);
  Var removed = map.del(<a>);
  EXPECT_INT_EQ(removed.int(), 10);
  EXPECT_INT_EQ(map.len(), 1);
  EXPECT_TRUE(map[<a>] is void);
}

static void map_update_counted_pairs(void) {
  $test.scoped();
  Map map = %{};
  Var alpha = <alpha>, beta = <beta>, ten = 10, twenty = 20;
  map.update_n(2, alpha, ten, beta, twenty);
  EXPECT_INT_EQ(map.len(), 2);
  EXPECT_INT_EQ(map[<alpha>].integer(), 10);
  EXPECT_INT_EQ(map[<beta>].integer(), 20);
}

static void map_update_avoids_growth(void) {
  $test.scoped();
  Map map = %{};
  map[<key>] = 1;
  unsigned capacity = map.capacity;
  map[<key>] = 2;
  EXPECT_INT_EQ(map.capacity, capacity);
  EXPECT_INT_EQ(map.len(), 1);
  EXPECT_INT_EQ(map[<key>].integer(), 2);

  map[<other>] = 3;
  EXPECT_TRUE(map.capacity > capacity);
  EXPECT_INT_EQ(map.len(), 2);
  EXPECT_INT_EQ(map[<key>].integer(), 2);
  EXPECT_INT_EQ(map[<other>].integer(), 3);
}

static void map_updateindex_hashes_existing_key_once(void) {
  $test.scoped();
  VarMethods methods = {
    .hash = _map_probe_hash,
    .equal = _map_probe_equal
  };
  EXPECT_TRUE(x2c_try_register_descriptor(%"mprobe", methods));

  MapProbe probe = { .value = 17 };
  Var key = Var.new(%"mprobe", &probe);
  Map map = %{};
  map[key] = 10;
  map_probe_hash_calls = 0;
  Var result = map.updateindex(key, <+>, 3);
  EXPECT_INT_EQ(map_probe_hash_calls, 1);
  EXPECT_INT_EQ(result.integer(), 13);
  EXPECT_INT_EQ(map[key].integer(), 13);
}

static void map_reports_exhausted_probe_invariant(void) {
  $test.scoped();
  Map map = %{};
  Var key = <probe-key>;
  unsigned hash = key.hash(), fake = hash ^ 2;
  if (!fake) fake = hash ^ 4;
  unsigned *hashes = map.hashes;
  unsigned start = hash & map.mask;
  hashes[start] = fake;
  hashes[start ^ 1] = fake;
  int caught = 0;
  try map.set(key, 1);
  catch %(invariant *): caught = 1;
  EXPECT_TRUE(caught);
  EXPECT_INT_EQ(map.len(), 0);
}


static void map_growth_preserves_entries(void) {
  $test.scoped();
  Map map = %{};
  for (int i = 0; i < 128; i++) {
    Var key = i + 1000, val = i * 7;
    map[key] = val;
  }
  EXPECT_INT_EQ(map.len(), 128);
  for (int i = 0; i < 128; i++) {
    Var key = i + 1000;
    EXPECT_INT_EQ(map[key].integer(), i * 7);
  }

  for (int i = 0; i < 128; i += 3) {
    Var key = i + 1000, out;
    EXPECT_TRUE(map.try_del(key, &out));
    EXPECT_INT_EQ(out.integer(), i * 7);
  }

  Map copy = map.copy();
  EXPECT_TRUE(map.equal(copy));
  EXPECT_INT_EQ(map.compare(copy), 0);
  Map merged = %{ extra: 1 };
  merged.merge(map);
  EXPECT_INT_EQ(merged.len(), map.len() + 1);
  for (int i = 1; i < 128; i += 3) {
    Var key = i + 1000;
    EXPECT_INT_EQ(merged[key].integer(), i * 7);
  }
}

static void _find_colliding_keys(
  Var *keys, int count, unsigned mask, unsigned bucket) {
  int found = 0;
  for (int candidate = 0; found < count; candidate++) {
    Var key = candidate;
    if ((key.hash() & mask) == bucket) keys[found++] = key;
  }
}

static void map_collision_backshift_and_reuse(void) {
  $test.scoped();
  Var keys[4];
  _find_colliding_keys(keys, 4, 7, 7);

  for (int removed = 0; removed < 3; removed++) {
    Map map = Map.new_capacity(8);
    for (int i = 0; i < 3; i++) map[keys[i]] = i + 10;
    EXPECT_INT_EQ(map.capacity, 8);

    Var out;
    EXPECT_TRUE(map.try_del(keys[removed], &out));
    EXPECT_INT_EQ(out.integer(), removed + 10);
    EXPECT_FALSE(map.contains(keys[removed]));
    for (int i = 0; i < 3; i++) {
      if (i != removed) EXPECT_INT_EQ(map[keys[i]].integer(), i + 10);
    }

    map[keys[3]] = removed + 20;
    EXPECT_INT_EQ(map[keys[3]].integer(), removed + 20);
    EXPECT_INT_EQ(map.len(), 3);
  }
}

static void map_reference_model_churn(void) {
  $test.scoped();
  Map map = %{};
  int present[32] = { 0 }, values[32] = { 0 };
  unsigned state = 0x13579bdu;

  for (int step = 0; step < 1000; step++) {
    state = state * 1664525u + 1013904223u;
    int index = (state >> 8) & 31;
    Var key = index;
    if ((state & 3) != 0) {
      int value = (state >> 16) & 0x7fff;
      map[key] = value;
      present[index] = 1;
      values[index] = value;
    }
    else {
      Var out;
      int removed = map.try_del(key, &out);
      EXPECT_INT_EQ(removed, present[index]);
      if (present[index]) EXPECT_INT_EQ(out.integer(), values[index]);
      present[index] = 0;
    }

    if (step % 25 == 0) {
      int expected_len = 0;
      for (int i = 0; i < 32; i++) {
        Var expected_key = i, out;
        EXPECT_INT_EQ(map.contains(expected_key), present[i]);
        EXPECT_INT_EQ(map.try_get(expected_key, &out), present[i]);
        if (present[i]) {
          EXPECT_INT_EQ(out.integer(), values[i]);
          expected_len++;
        }
      }
      EXPECT_INT_EQ(map.len(), expected_len);
    }
  }
}

static void map_stable_traversal_visits_every_entry(void) {
  $test.scoped();
  Map map = %{};
  int seen[64] = { 0 };
  for (int i = 0; i < 64; i++) map[i] = i * 11;

  unsigned cursor = 0;
  int count = 0;
  Var key, val;
  while (map.try_next(&cursor, &key, &val)) {
    int index = key.integer();
    EXPECT_TRUE(index >= 0 && index < 64);
    if (index >= 0 && index < 64) {
      EXPECT_FALSE(seen[index]);
      EXPECT_INT_EQ(val.integer(), index * 11);
      seen[index] = 1;
    }
    count++;
  }
  EXPECT_INT_EQ(count, 64);
  for (int i = 0; i < 64; i++) EXPECT_TRUE(seen[i]);
}

static int _compare_sign(int value) {
  return (value > 0) - (value < 0);
}

static void map_compare_structural_laws(void) {
  $test.scoped();
  Map a = %{}, b = %{};
  Array akey = %[1, 2], bkey = %[1, 2];
  a[akey] = 10;
  b[bkey] = 10;
  EXPECT_INT_EQ(a.compare(b), 0);
  EXPECT_INT_EQ(b.compare(a), 0);

  Map pairs_a = %{}, pairs_b = %{};
  Array a1 = %[7], a2 = %[7], b1 = %[7], b2 = %[7];
  pairs_a[a1] = 1;
  pairs_a[a2] = 2;
  pairs_b[b2] = 2;
  pairs_b[b1] = 1;
  EXPECT_INT_EQ(pairs_a.compare(pairs_b), 0);
  EXPECT_INT_EQ(pairs_b.compare(pairs_a), 0);

  Map low = %{}, middle = %{}, high = %{};
  low[%[9]] = 1;
  middle[%[9]] = 2;
  high[%[9]] = 3;
  EXPECT_TRUE(low.compare(middle) < 0);
  EXPECT_TRUE(middle.compare(high) < 0);
  EXPECT_TRUE(low.compare(high) < 0);
  EXPECT_INT_EQ(_compare_sign(low.compare(middle)),
                -_compare_sign(middle.compare(low)));

  Map inner_a = %{ key: 5 };
  Map inner_b = %{ key: 5 };
  Map outer_a = %{};
  Map outer_b = %{};
  outer_a[inner_a] = 8;
  outer_b[inner_b] = 8;
  EXPECT_INT_EQ(outer_a.compare(outer_b), 0);
  EXPECT_INT_EQ(outer_b.compare(outer_a), 0);
}

static void map_setdefault_behavior(void) {
  $test.scoped();
  Map map = %{};
  Var key = <foo>, defv = 123, v1 = map.setdefault(key, defv);
  EXPECT_VAR_EQ(v1, defv);
  EXPECT_INT_EQ(map.len(), 1);
  // Calling again with a different default must not overwrite
  Var v2 = map.setdefault(key, 999);
  EXPECT_VAR_EQ(v2, defv);
  EXPECT_INT_EQ(map.len(), 1);
  Var v3 = map.setdefault(key, void);
  EXPECT_VAR_EQ(v3, defv);
  EXPECT_INT_EQ(map.len(), 1);
}

static void map_getdefault_behavior(void) {
  $test.scoped();
  Map map = %{};
  Var key = <bar>;
  // Absent key returns default without inserting
  Var v7 = 7, gd = map.getdefault(key, v7);
  EXPECT_VAR_EQ(gd, v7);
  EXPECT_INT_EQ(map.len(), 0);
  // After manual set, getdefault returns stored value
  Var v5 = 5;
  map[key] = v5;
  Var v9 = 9, gd2 = map.getdefault(key, v9);
  EXPECT_VAR_EQ(gd2, v5);
  EXPECT_INT_EQ(map.len(), 1);
}

static void map_hash_equal_and_compare(void) {
  $test.scoped();

  Map a = %{}, b = %{};
  Var ka = <a>, kb = <b>, one = 1, two = 2;

  a[ka] = one;
  a[kb] = two;

  // Insert in different order.
  b[kb] = two;
  b[ka] = one;

  unsigned ha = a.var().hash(), hb = b.var().hash();

  EXPECT_TRUE(a.equal(b));
  EXPECT_INT_EQ(a.compare(b), 0);
  EXPECT_TRUE(a == b);
  EXPECT_TRUE(a !== b);
  EXPECT_INT_EQ(a.var().compare(b), 0);
  EXPECT_TRUE(ha != 0);
  EXPECT_TRUE(hb != 0);
  EXPECT_TRUE(a.contains(ka));
  EXPECT_FALSE(a.contains(<missing>));

  a[<c>] = 3;
  EXPECT_TRUE(a.var().hash() == ha);

  Map c = %{}, d = %{};
  c[ka] = one;
  d[kb] = one;
  EXPECT_TRUE(c.compare(d) < 0);
  EXPECT_TRUE(d.compare(c) > 0);

}

static void map_mutable_keys_use_identity(void) {
  $test.scoped();

  Map map = %{};
  Array a = %[1, 2], b = %[1, 2];
  Var va = a, vb = b;
  unsigned hash_before = va.hash();

  map[va] = %"left";
  map[vb] = %"right";

  EXPECT_TRUE(va == vb);
  EXPECT_TRUE(va !== vb);
  EXPECT_INT_EQ(va.compare(vb), 0);
  EXPECT_INT_EQ(map.len(), 2);
  EXPECT_TRUE(map[va] == %"left");
  EXPECT_TRUE(map[vb] == %"right");

  a.push(3);
  EXPECT_TRUE(va.hash() == hash_before);
  EXPECT_TRUE(map[va] == %"left");
  EXPECT_TRUE(map[vb] == %"right");

}

static void map_typed_empty_keys(void) {
  $test.scoped();

  Map map = %{};
  String empty_string = NULL;
  List empty_list = NULL;
  Var string_key = empty_string, list_key = empty_list;

  map[string_key] = 1;
  map[list_key] = 2;

  EXPECT_TRUE(string_key.hash() != 0);
  EXPECT_TRUE(list_key.hash() != 0);
  EXPECT_TRUE(string_key != list_key);
  EXPECT_INT_EQ(map.len(), 2);
  EXPECT_INT_EQ(map[string_key].integer(), 1);
  EXPECT_INT_EQ(map[list_key].integer(), 2);

}

static void map_null_pair_status_iteration(void) {
  $test.scoped();
  Map map = %{};
  Var null = (Var) { .u64 = 0 };
  map[null] = null;

  unsigned cursor = 0;
  Var key = void, val = void;
  EXPECT_TRUE(map.try_next(&cursor, &key, &val));
  EXPECT_INT_EQ(key.u64, 0);
  EXPECT_INT_EQ(val.u64, 0);
  EXPECT_FALSE(map.try_next(&cursor, &key, &val));

  struct Iter storage;
  Iter iter = map.iter(&storage);
  Var yielded;
  EXPECT_TRUE(iter.try_next(&yielded));
  EXPECT_INT_EQ(yielded.u64, 0);
  EXPECT_FALSE(iter.try_next(&yielded));

  struct Iter key_storage;
  Iter map_keys = map.keys(&key_storage);
  Var yielded_key;
  EXPECT_TRUE(map_keys.try_next(&yielded_key));
  EXPECT_INT_EQ(yielded_key.u64, 0);
  EXPECT_FALSE(map_keys.try_next(&yielded_key));

  struct Iter pair_storage;
  Iter pairs = map.enumerate(&pair_storage);
  Var pair_var;
  EXPECT_TRUE(pairs.try_next(&pair_var));
  List pair = pair_var;
  Var (pair_key, pair_value) = pair;
  EXPECT_INT_EQ(pair_key.u64, 0);
  EXPECT_INT_EQ(pair_value.u64, 0);
  EXPECT_FALSE(pairs.try_next(&pair_var));

  Map copy = map.copy();
  EXPECT_INT_EQ(copy.len(), 1);
  EXPECT_TRUE(copy.try_get(null, &val));
  EXPECT_INT_EQ(val.u64, 0);
  EXPECT_TRUE(map.equal(copy));
  EXPECT_INT_EQ(map.compare(copy), 0);

  Map merged = %{};
  merged.merge(map);
  EXPECT_TRUE(merged.try_get(null, &val));
  EXPECT_INT_EQ(val.u64, 0);
}


/* The three iterators walk the same entries: values, keys, and pairs. */
static void map_iterates_values_keys_and_pairs(void) {
  Map map = %{"a": 1, "b": 2, "c": 3};
  long values = 0, keys = 0, pair_keys = 0, pair_values = 0;
  int counted = 0;

  foreach(Var value, map) values += value.integer();

  struct Iter key_storage;
  foreach(Var key, map.keys(&key_storage)) keys += key.str().len();

  struct Iter pair_storage;
  foreach(Var entry, map.enumerate(&pair_storage)) {
    List pair = entry;
    (String pair_key, long pair_value) = pair;
    pair_keys += pair_key.len();
    pair_values += pair_value;
    counted++;
  }

  EXPECT_INT_EQ(counted, 3);
  EXPECT_INT_EQ(values, 6);
  EXPECT_INT_EQ(keys, 3);
  EXPECT_INT_EQ(pair_keys, keys);
  EXPECT_INT_EQ(pair_values, values);
}

void map_suite(void) {
  $test.run(map_iterates_values_keys_and_pairs);
  $test.run(map_empty_literal_identity);
  $test.run(map_set_get_updates);
  $test.run(map_void_writes_transfer_before_mutation);
  $test.run(map_delete_and_len);
  $test.run(map_update_counted_pairs);
  $test.run(map_update_avoids_growth);
  $test.run(map_updateindex_hashes_existing_key_once);
  $test.run(map_reports_exhausted_probe_invariant);
  $test.run(map_growth_preserves_entries);
  $test.run(map_collision_backshift_and_reuse);
  $test.run(map_reference_model_churn);
  $test.run(map_stable_traversal_visits_every_entry);
  $test.run(map_setdefault_behavior);
  $test.run(map_getdefault_behavior);
  $test.run(map_hash_equal_and_compare);
  $test.run(map_compare_structural_laws);
  $test.run(map_mutable_keys_use_identity);
  $test.run(map_typed_empty_keys);
  $test.run(map_null_pair_status_iteration);
}
