/*  test-atomic-container.x -- single-call container update ownership */

#include "test-support.x"
$(import "test-macros.xmacro")

static void array_index_numeric_updates(void) {
  $test.scoped();
  Symbol ops[] = {
    <+>, <->, <*> , </>, <%>, <&>, <|>, <^>, <"<<">, <">>">
  };
  int left[] = { 10, 10, 10, 12, 13, 12, 10, 12, 3, 12 };
  int right[] = { 3, 3, 3, 3, 5, 10, 5, 10, 2, 2 };
  int expected[] = { 13, 7, 30, 4, 3, 8, 15, 6, 12, 3 };
  int count = sizeof(ops) / sizeof(ops[0]);
  for (int i = 0; i < count; i++) {
    Array array = %[${left[i]}];
    Var out = array.updateindex(0, ops[i], right[i]);
    EXPECT_INT_EQ(array[0].int(), expected[i]);
    EXPECT_INT_EQ(out.int(), expected[i]);
  }

  Array array = %[${Var.new(<u8>, 4)}, ${Var.new(<i16>, 9)}];
  Var out = array.updateindex(-1, <+>, 3);
  EXPECT_TRUE(array[-1] is <i16>);
  EXPECT_INT_EQ(array[-1].short(), 12);
  EXPECT_TRUE(out is <i16>);

  Var old = array.postfixindex(0, <++>);
  EXPECT_TRUE(old is <u8>);
  EXPECT_INT_EQ(old.uchar(), 4);
  EXPECT_INT_EQ(array[0].uchar(), 5);
  old = array.postfixindex(0, <-->);
  EXPECT_INT_EQ(old.uchar(), 5);
  EXPECT_INT_EQ(array[0].uchar(), 4);
}


static void array_index_failures_are_atomic(void) {
  $test.scoped();
  Array array = %[${Var.new(<i32>, 12)}];
  Var before = array[0];
  int caught = 0;
  try array.updateindex(4, <+>, 1);
  catch %(bad-arg *): caught++;
  EXPECT_TRUE(array[0] === before);

  try array.updateindex(0, </>, 0);
  catch %(div-zero *): caught++;
  EXPECT_TRUE(array[0] === before);

  try array.updateindex(0, <"<<">, 32);
  catch %(bad-shift *): caught++;
  EXPECT_TRUE(array[0] === before);

  try array.updateindex(0, <+>, Var.new(<f64>, 0.0 / 0.0));
  catch %(conv-range *): caught++;
  EXPECT_TRUE(array[0] === before);

  try array.updateindex(0, <==>, 1);
  catch %(bad-op *): caught++;
  EXPECT_TRUE(array[0] === before);

  try array.updateindex(0, <+>, void);
  catch %(void-op *): caught++;

  try Array.updateindex(NULL, 0, <+>, 1);
  catch %(bad-arg *): caught++;
  EXPECT_TRUE(array[0] === before);
  EXPECT_INT_EQ(caught, 7);
}


static void map_index_updates_and_failures(void) {
  $test.scoped();
  Symbol ops[] = {
    <+>, <->, <*> , </>, <%>, <&>, <|>, <^>, <"<<">, <">>">
  };
  int left[] = { 10, 10, 10, 12, 13, 12, 10, 12, 3, 12 };
  int right[] = { 3, 3, 3, 3, 5, 10, 5, 10, 2, 2 };
  int expected[] = { 13, 7, 30, 4, 3, 8, 15, 6, 12, 3 };
  int count = sizeof(ops) / sizeof(ops[0]);
  for (int i = 0; i < count; i++) {
    Map numbers = %{"value": ${left[i]}};
    Var result = numbers.updateindex(%"value", ops[i], right[i]);
    EXPECT_INT_EQ(numbers[%"value"].int(), expected[i]);
    EXPECT_INT_EQ(result.int(), expected[i]);
  }

  Map map = %{};
  Var key = %(arbitrary key);
  map[key] = Var.new(<i8>, 9);
  Var out = map.updateindex(key, <*>, 3);
  EXPECT_TRUE(map[key] is <i8>);
  EXPECT_INT_EQ(map[key].char(), 27);
  EXPECT_TRUE(out is <i8>);

  Var old = map.postfixindex(key, <++>);
  EXPECT_INT_EQ(old.char(), 27);
  EXPECT_INT_EQ(map[key].char(), 28);
  old = map.postfixindex(key, <-->);
  EXPECT_INT_EQ(old.char(), 28);
  EXPECT_INT_EQ(map[key].char(), 27);

  Var before = map[key], missing = %"missing";
  int caught = 0;
  try map.updateindex(missing, <->, 1);
  catch %(bad-arg *): caught++;
  EXPECT_FALSE(map.contains(missing));
  EXPECT_TRUE(map[key] === before);

  try map.updateindex(key, </>, 0);
  catch %(div-zero *): caught++;
  EXPECT_TRUE(map[key] === before);

  try Map.updateindex(NULL, key, <+>, 1);
  catch %(bad-arg *): caught++;

  try map.updateindex(void, <+>, 1);
  catch %(void-op *): caught++;

  try map.updateindex(key, <+>, void);
  catch %(void-op *): caught++;
  EXPECT_TRUE(map[key] === before);

  try map.updateindex(key, <%>, 0);
  catch %(div-zero *): caught++;
  EXPECT_TRUE(map[key] === before);
  map[key] = Var.new(<string>, %"text");
  before = map[key];
  try map.updateindex(key, <->, 1);
  catch %(bad-types *): caught++;
  EXPECT_TRUE(map[key] === before);
  EXPECT_INT_EQ(caught, 7);
}


static void map_additive_initialization(void) {
  $test.scoped();
  Map counts = %{};
  Array identity_object = %[1];
  Var object = identity_object;

  Var first = counts[object] += 1;
  EXPECT_INT_EQ(counts.len(), 1);
  EXPECT_INT_EQ(first.int(), 1);
  EXPECT_INT_EQ(counts[object].int(), 1);

  Var second = counts[object] += Var.new(<u8>, 2);
  EXPECT_INT_EQ(counts.len(), 1);
  EXPECT_TRUE(second is <i32>);
  EXPECT_INT_EQ(second.int(), 3);
  EXPECT_INT_EQ(counts[object].int(), 3);
  Array equal_but_distinct = %[1];
  EXPECT_FALSE(counts.contains(equal_but_distinct));

  Var narrow_key = %"narrow", narrow = counts[narrow_key] += Var.new(<u8>, 4);
  EXPECT_TRUE(narrow is <u8>);
  EXPECT_TRUE(counts[narrow_key] is <u8>);
  EXPECT_INT_EQ(counts[narrow_key].uchar(), 4);

  Map source = %{"value": ${Var.new(<f64>, 1.5)}};
  Var copied = x2c_map_updateindex_from_map(
    counts, %"copied", <+>, source, %"value"
  );
  EXPECT_TRUE(copied is <f64>);
  EXPECT_TRUE(copied.double() == 1.5);
  EXPECT_TRUE(counts[%"copied"] is <f64>);
  EXPECT_TRUE(counts[%"copied"].double() == 1.5);

  Var absent = %"absent";
  int caught = 0;
  try counts.updateindex(absent, <->, 1);
  catch %(bad-arg *): caught++;
  EXPECT_FALSE(counts.contains(absent));

  try counts.updateindex(absent, <+>, Var.new(<string>, %"text"));
  catch %(bad-arg *): caught++;
  EXPECT_FALSE(counts.contains(absent));

  try counts.updateindex(absent, <+>, void);
  catch %(void-op *): caught++;
  EXPECT_FALSE(counts.contains(absent));
  EXPECT_INT_EQ(caught, 3);
}


static void string_updates_are_checked_and_canonical(void) {
  $test.scoped();
  String out = String.add(%"left", %"right");
  EXPECT_TRUE(out == %"leftright");
  out = String.add(NULL, %"right");
  EXPECT_TRUE(out == %"right");
  out = String.add(%"left", NULL);
  EXPECT_TRUE(out == %"left");
  out = String.add(NULL, NULL);
  EXPECT_NULL(out);

  Var value = Var.new(<string>, %"hello");
  Var result = value.binary(<+>, Var.new(<string>, %" world"));
  EXPECT_TRUE(result is <string>);
  EXPECT_TRUE(result.string() == %"hello world");
  result = Var.update(&value, <+>, Var.new(<string>, %" world"));
  EXPECT_TRUE(value is <string>);
  EXPECT_TRUE(value.string() == %"hello world");
  Var before = value;
  int caught = 0;
  try Var.update(&value, <+>, 1);
  catch %(bad-types *): caught = 1;
  EXPECT_TRUE(value === before);
  EXPECT_TRUE(caught);

  String native = %"native";
  native += %" string";
  EXPECT_TRUE(native == %"native string");
}


static void cross_container_updates_capture_source_first(void) {
  $test.scoped();
  Array dst_array = %[10, 2], src_array = %[3];
  Map dst_map = %{"dst": 20}, src_map = %{"src": 4};

  EXPECT_INT_EQ(
    x2c_array_updateindex_from_array(dst_array, 0, <+>, src_array, 0).int(), 13
  );
  EXPECT_INT_EQ(
    x2c_array_updateindex_from_map(
      dst_array, 0, <*>, src_map, %"src"
    ).int(), 52
  );
  EXPECT_INT_EQ(
    x2c_map_updateindex_from_array(
      dst_map, %"dst", <->, src_array, 0
    ).int(), 17
  );
  EXPECT_INT_EQ(
    x2c_map_updateindex_from_map(
      dst_map, %"dst", </>, src_map, %"src"
    ).int(), 4
  );

  Array alias_array = %[5];
  EXPECT_INT_EQ(
    x2c_array_updateindex_from_array(
      alias_array, 0, <+>, alias_array, 0
    ).int(), 10
  );
  Map alias_map = %{"same": 7};
  EXPECT_INT_EQ(
    x2c_map_updateindex_from_map(
      alias_map, %"same", <+>, alias_map, %"same"
    ).int(), 14
  );

  Array strings = %[${Var.new(<string>, %"a")}, ${Var.new(<string>, %"b")}];
  EXPECT_TRUE(
    x2c_array_updateindex_from_array(
      strings, 0, <+>, strings, 1
    ).string() == %"ab"
  );
}



void atomic_container_suite(void) {
  $test.run(array_index_numeric_updates);
  $test.run(array_index_failures_are_atomic);
  $test.run(map_index_updates_and_failures);
  $test.run(map_additive_initialization);
  $test.run(string_updates_are_checked_and_canonical);
  $test.run(cross_container_updates_capture_source_first);
}
