/*  test-context.x -- bounded runtime state and export tests */

#include "typed-array.x"
#include "typed-map.x"
#include "test-support.x"
#include <string.h>

static void context_open_close_restores_scope(void) {
  ScopeStats before = Scope.stats();
  Context context = Context.open_named("test Context");
  EXPECT_PTR_EQ(Context.current(), context);
  char *scratch = Scope.memdup("scratch", 8);
  EXPECT_STR_EQ(scratch, "scratch");
  context.close();
  EXPECT_NULL(Context.current());
  ScopeStats after = Scope.stats();
  EXPECT_INT_EQ(after.live_allocations, before.live_allocations);
  EXPECT_INT_EQ(after.live_scopes, before.live_scopes);
}

static void context_restores_error_state(void) {
  EXPECT_TRUE(Error.policy_get(<context-no>) == <abort>);
  Context context = Context.open();
  Error.policy_set(<context-no>, <ignore>);
  Error.raise(<context-no>, %((value 7)));
  EXPECT_TRUE(Error.policy_get(<context-no>) == <ignore>);
  EXPECT_INT_EQ(Error.count(), 0);
  context.close();
  EXPECT_TRUE(Error.policy_get(<context-no>) == <abort>);
}

static void context_inherited_pools_reuse_ancestor_values(void) {
  String string = String.new("ancestor String");
  List list = %(ancestor value);
  Context context = Context.open();
  EXPECT_PTR_EQ(String.new("ancestor String"), string);
  EXPECT_PTR_EQ(%(ancestor value), list);
  context.close();
  EXPECT_STR_EQ(string, "ancestor String");
  EXPECT_INT_EQ(list.len(), 2);
}

static void _context_raise_outward(void) {
  Context context = Context.open_isolated_named("unwinding Context");
  defer context.close();
  String detail = String.new("private error detail");
  raise %(context-un (detail $detail));
}

static void context_preserves_unhandled_error_for_outer_catch(void) {
  int caught = 0;
  String detail = NULL;
  try {
    _context_raise_outward();
  }
  catch %(context-un (detail ?value)): {
    caught = 1;
    detail = Error.snapshot(value);
  }
  EXPECT_TRUE(caught);
  EXPECT_STR_EQ(detail, "private error detail");
  EXPECT_NULL(Context.current());
}

static void context_exports_nested_builtin_graph(void) {
  Context outer = Context.open_isolated_named("export destination");
  Context inner = Context.open_isolated_named("export source");
  String key = String.new("private map key");
  String text = String.new("private array text");
  List list = %(text $text 29);
  Var wide = Var.box_long(0x123456789L);
  Array array = %[];
  array.push(list);
  array.push(wide);
  Map map = %{};
  map[key] = array;

  Var exported = inner.export(map);
  EXPECT_PTR_EQ(exported.map(), map);
  EXPECT_PTR_EQ(array, map[key].array());
  inner.close();

  String parent_key = String.new("private map key");
  Array result = map[parent_key];
  EXPECT_PTR_EQ(result, array);
  List result_list = result[0];
  EXPECT_STR_EQ(result_list[1].string(), "private array text");
  EXPECT_INT_EQ(result_list[2].integer(), 29);
  EXPECT_INT_EQ(result[1].long_value(), 0x123456789L);
  outer.close();
}

static void context_exports_cyclic_arrays_and_maps(void) {
  Context outer = Context.open_isolated_named("cyclic destination");
  Context inner = Context.open_isolated_named("cyclic source");
  Array array = %[];
  Map map = %{};
  array.push(array);
  array.push(map);
  map[<array>] = array;
  map[<self>] = map;

  Var exported = inner.export(array);
  EXPECT_PTR_EQ(exported.array(), array);
  inner.close();

  EXPECT_PTR_EQ(array[0].array(), array);
  EXPECT_PTR_EQ(array[1].map(), map);
  EXPECT_PTR_EQ(map[<array>].array(), array);
  EXPECT_PTR_EQ(map[<self>].map(), map);
  outer.close();
}

static void context_rehashes_exported_map_keys(void) {
  Context outer = Context.open_isolated_named("Map key destination");
  Context inner = Context.open_isolated_named("Map key source");
  List key = %(private list key);
  Map map = %{};
  map[key] = 47;

  map = inner.export(map);
  inner.close();

  List exported_key = %(private list key);
  EXPECT_INT_EQ(map[exported_key].integer(), 47);
  outer.close();
}

static void context_exports_registered_object(void) {
  EXPECT_TRUE(Test_register_context_probe());

  Context outer = Context.open_isolated_named("custom destination");
  Context inner = Context.open_isolated_named("custom source");
  ContextProbe probe = Scope.malloc(sizeof(struct ContextProbe));
  probe.value = String.new("custom private value");
  probe.exports = 0;
  probe.fail_at = 0;
  Var object = Var.new(<ctxprobe>, probe);
  Var exported = inner.export(object);
  EXPECT_PTR_EQ(exported.pointer(), probe);
  inner.close();
  EXPECT_STR_EQ(probe.value.string(), "custom private value");
  outer.close();
}

static void context_failed_export_restores_container_owner(void) {
  ScopeStats before = Scope.stats();
  Context context = Context.open_isolated_named("failed export source");
  ContextProbe probe = Scope.malloc(sizeof(struct ContextProbe));
  probe.value = String.new("failed private value");
  probe.exports = 1;
  probe.fail_at = 1;
  Map map = %{probe: ${Var.new(<ctxprobe>, probe)}};
  int caught = 0;
  try context.export(map);
  catch %(thread-exp *): caught = 1;
  EXPECT_TRUE(caught);
  EXPECT_TRUE(context.owns(map));
  context.close();
  ScopeStats after = Scope.stats();
  EXPECT_INT_EQ(after.live_allocations, before.live_allocations);
  EXPECT_INT_EQ(after.live_scopes, before.live_scopes);
}

static void context_exports_owned_storage(void) {
  Context outer = Context.open_isolated_named("storage destination");
  Context inner = Context.open_isolated_named("storage source");
  int number = 37;
  Block block = Block.new(sizeof(int));
  block.push(&number);
  Bytes bytes = Bytes.new(sizeof(char));
  bytes = bytes.append("abc", 3);
  Buffer buffer = Buffer.new(0);
  buffer.write("buffer text");
  Array values = %[];
  values.push(block);
  values.push(bytes);
  values.push(buffer);

  values = inner.export(values);
  inner.close();
  EXPECT_INT_EQ(*((int *) values[0].block().bytes), 37);
  EXPECT_TRUE(!memcmp(values[1].bytes(), "abc", 3));
  EXPECT_STR_EQ(values[2].buffer().str(), "buffer text");
  outer.close();
}

static void context_exports_all_packed_containers(void) {
  Context outer = Context.open_isolated_named("packed destination");
  Context inner = Context.open_isolated_named("packed source");
  ArrayChar chars = ArrayChar.new();
  ArrayShort shorts = ArrayShort.new();
  ArrayInt ints = ArrayInt.new();
  ArrayLong longs = ArrayLong.new();
  ArrayFloat floats = ArrayFloat.new();
  ArrayDbl doubles = ArrayDbl.new();
  ArrayString strings = ArrayString.new();
  chars.push(7);
  shorts.push(701);
  ints.push(70001);
  longs.push(7000000001L);
  floats.push(7.25f);
  doubles.push(70.125);
  String array_string = String.printf("packed-array-%d", 704);
  strings.push(array_string);

  MapIntInt integer_map = MapIntInt.new();
  MapLongDouble double_map = MapLongDouble.new();
  MapStringString string_map = MapStringString.new();
  MapStringInt string_int_map = MapStringInt.new();
  integer_map.set(7, 49);
  double_map.set(7000000001L, 7.5);
  String key = String.printf("packed-key-%d", 701);
  String value = String.printf("packed-value-%d", 702);
  String empty_value_key = String.printf("packed-empty-%d", 703);
  string_map.set(key, value);
  string_map.set("", value);
  string_map.set(empty_value_key, "");
  String int_key = String.printf("packed-int-key-%d", 705);
  string_int_map.set(int_key, 71);

  EXPECT_PTR_EQ(inner.export(chars).arraychar(), chars);
  EXPECT_PTR_EQ(inner.export(shorts).arrayshort(), shorts);
  EXPECT_PTR_EQ(inner.export(ints).arrayint(), ints);
  EXPECT_PTR_EQ(inner.export(longs).arraylong(), longs);
  EXPECT_PTR_EQ(inner.export(floats).arrayfloat(), floats);
  EXPECT_PTR_EQ(inner.export(doubles).arraydbl(), doubles);
  EXPECT_PTR_EQ(inner.export(strings).arraystring(), strings);
  EXPECT_PTR_EQ(
    inner.export(integer_map).mapintint(), integer_map
  );
  EXPECT_PTR_EQ(
    inner.export(double_map).maplongdouble(), double_map
  );
  EXPECT_PTR_EQ(
    inner.export(string_map).mapstringstring(), string_map
  );
  EXPECT_PTR_EQ(
    inner.export(string_int_map).mapstringint(), string_int_map
  );
  inner.close();

  EXPECT_INT_EQ(chars[0], 7);
  EXPECT_INT_EQ(shorts[0], 701);
  EXPECT_INT_EQ(ints[0], 70001);
  EXPECT_TRUE(longs[0] == 7000000001L);
  EXPECT_TRUE(floats[0] == 7.25f);
  EXPECT_TRUE(doubles[0] == 70.125);
  EXPECT_PTR_EQ(strings[0], String.new("packed-array-704"));
  EXPECT_INT_EQ(integer_map.get(7), 49);
  EXPECT_TRUE(double_map.get(7000000001L) == 7.5);
  String exported_key = String.new("packed-key-701");
  String exported_value = string_map.get(exported_key);
  EXPECT_PTR_EQ(exported_value, String.new("packed-value-702"));
  EXPECT_PTR_EQ(string_map.get(""), exported_value);
  EXPECT_NULL(string_map.get(String.new("packed-empty-703")));
  EXPECT_INT_EQ(string_int_map.get(String.new("packed-int-key-705")), 71);
  unsigned int_cursor = 0;
  String stored_int_key = NULL;
  int stored_int_value = 0;
  EXPECT_TRUE(string_int_map.try_next(
    &int_cursor, &stored_int_key, &stored_int_value));
  EXPECT_PTR_EQ(stored_int_key, String.new("packed-int-key-705"));

  for (int i = 0; i < 80; i++) {
    chars.push((char) i);
    shorts.push((short) i);
    ints.push(i);
    longs.push(i);
    floats.push((float) i);
    doubles.push((double) i);
    strings.push(String.printf("grown-array-%d", i));
    integer_map.set(i + 100, i);
    double_map.set((long) i + 100, i * 0.5);
    string_map.set(
      String.printf("grown-key-%d", i),
      String.printf("grown-value-%d", i)
    );
    string_int_map.set(String.printf("grown-int-key-%d", i), i);
  }
  EXPECT_TRUE(chars.capacity() >= 81);
  EXPECT_TRUE(shorts.capacity() >= 81);
  EXPECT_TRUE(ints.capacity() >= 81);
  EXPECT_TRUE(longs.capacity() >= 81);
  EXPECT_TRUE(floats.capacity() >= 81);
  EXPECT_TRUE(doubles.capacity() >= 81);
  EXPECT_TRUE(strings.capacity() >= 81);
  EXPECT_TRUE(integer_map.capacity >= 128);
  EXPECT_TRUE(double_map.capacity >= 128);
  EXPECT_TRUE(string_map.capacity >= 128);
  EXPECT_TRUE(string_int_map.capacity >= 128);
  EXPECT_STR_EQ(string_map.get("grown-key-79"), "grown-value-79");
  EXPECT_INT_EQ(string_int_map.get("grown-int-key-79"), 79);
  outer.close();
}

static void context_leaves_borrowed_packed_containers_untouched(void) {
  Context outer = Context.open_isolated_named("packed owner");
  ArrayInt array = ArrayInt.new();
  array.push(31);
  MapStringString map = MapStringString.new();
  map.set("borrowed", "unchanged");
  ArrayString strings = %["borrowed-array"];
  MapStringInt counts = %{"borrowed-map": 41};
  Context inner = Context.open_isolated_named("packed borrower");

  EXPECT_PTR_EQ(inner.export(array).arrayint(), array);
  EXPECT_PTR_EQ(inner.export(map).mapstringstring(), map);
  EXPECT_PTR_EQ(inner.export(strings).arraystring(), strings);
  EXPECT_PTR_EQ(inner.export(counts).mapstringint(), counts);
  inner.close();
  EXPECT_INT_EQ(array[0], 31);
  EXPECT_STR_EQ(map.get("borrowed"), "unchanged");
  EXPECT_STR_EQ(strings[0], "borrowed-array");
  EXPECT_INT_EQ(counts["borrowed-map"], 41);
  outer.close();
}

static void context_string_array_staging_failure_preserves_storage(void) {
  Context outer = Context.open_isolated_named("ArrayString destination");
  Context inner = Context.open_isolated_named("ArrayString source");
  ArrayString strings = %[${String.new("private array String")}];
  Bytes original = strings.bytes;
  size_t capacity = strings.cap;
  strings.cap = SIZE_MAX;
  int caught = 0;

  try inner.export(strings);
  catch %(size-limit *): caught = 1;
  EXPECT_TRUE(caught);
  EXPECT_TRUE(inner.owns(strings));
  EXPECT_PTR_EQ(strings.bytes, original);
  EXPECT_STR_EQ(strings[0], "private array String");
  strings.cap = capacity;
  inner.close();
  outer.close();
}

static void context_string_map_collapse_uses_later_bucket(void) {
  Context outer = Context.open_isolated_named("collapse destination");
  Context inner = Context.open_isolated_named("collapse source");
  String first = String.new("collapse-key-a7");
  String second = String.new("collapse-key-b7");
  String first_value = String.new("collapse-first-value");
  String second_value = String.new("collapse-second-value");
  MapStringString map = MapStringString.new_capacity(8);
  map.set(first, first_value);
  map.set(second, second_value);

  /* Manufacture the defensive case without changing either cached hash.
     Normal interning never creates two equal Strings in one source pool. */
  memcpy(second, first, first.len() + 1);
  String later_value = NULL;
  foreach (String traversed_value, map) later_value = traversed_value;
  int later_is_second = later_value == second_value;

  map = inner.export(map).mapstringstring();
  inner.close();
  EXPECT_INT_EQ(map.len(), 1);
  String collapsed = map.get(String.new("collapse-key-a7"));
  EXPECT_STR_EQ(
    collapsed,
    later_is_second ? "collapse-second-value" : "collapse-first-value"
  );
  outer.close();
}

static void context_exports_void_unchanged(void) {
  Context context = Context.open_isolated_named("void export source");
  EXPECT_TRUE(context.export(void) is void);
  context.close();
}

static void context_exports_long_list_without_c_stack_growth(void) {
  Context outer = Context.open_isolated_named("long List destination");
  Context inner = Context.open_isolated_named("long List source");
  List values = nil;
  for (int i = 0; i < 100000; i++) values = cons(i, values);
  values = inner.export(values);
  inner.close();
  EXPECT_INT_EQ(values.len(), 100000);
  EXPECT_INT_EQ(values.car().int(), 99999);
  EXPECT_INT_EQ(values.last().int(), 0);
  outer.close();
}

$(import "test-macros.xmacro")

void context_suite(void) {
  $test.run(context_open_close_restores_scope);
  $test.run(context_restores_error_state);
  $test.run(context_inherited_pools_reuse_ancestor_values);
  $test.run(context_preserves_unhandled_error_for_outer_catch);
  $test.run(context_exports_nested_builtin_graph);
  $test.run(context_exports_cyclic_arrays_and_maps);
  $test.run(context_rehashes_exported_map_keys);
  $test.run(context_exports_registered_object);
  $test.run(context_failed_export_restores_container_owner);
  $test.run(context_exports_owned_storage);
  $test.run(context_exports_all_packed_containers);
  $test.run(context_leaves_borrowed_packed_containers_untouched);
  $test.run(context_string_array_staging_failure_preserves_storage);
  $test.run(context_string_map_collapse_uses_later_bucket);
  $test.run(context_exports_void_unchanged);
  $test.run(context_exports_long_list_without_c_stack_growth);
}
