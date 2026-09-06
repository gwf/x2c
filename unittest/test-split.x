/*  test-split.x -- unit tests for eager and lazy String splitting */

#include "test-support.x"

static void expect_split_item(List strings, int index, String expected) {
  EXPECT_TRUE(strings.getindex(index).string() == expected);
}

static List collect_split_cursor(Split cursor) {
  Array items = %[];
  foreach(String item, cursor) items.push(item);
  List result = items.list_free();
  return result;
}

static void expect_cursor_items(Split cursor, List expected) {
  EXPECT_TRUE(collect_split_cursor(cursor) == expected);
}

static List collect_try_next(Split cursor) {
  Array items = %[];
  int position = 0;
  String item;
  while (cursor.try_next(&position, &item)) items.push(item);
  List result = items.list_free();
  return result;
}

static void expect_try_next_items(Split cursor, List expected) {
  EXPECT_TRUE(collect_try_next(cursor) == expected);
}

static void split_eager_and_join(void) {
  String csv = %"a,b,c";
  List parts = csv.split(%",");
  EXPECT_INT_EQ(parts.len(), 3);
  EXPECT_NULL(String.split(NULL, %","));

  List whole = csv.split(NULL);
  EXPECT_INT_EQ(whole.len(), 1);
  EXPECT_TRUE(whole.car().string() == csv);
  EXPECT_TRUE(%"-".join(parts) == %"a-b-c");
  EXPECT_INT_EQ(String.split(NULL, %",").len(), 0);
}

static void split_limits_and_lines(void) {
  List limited = %"a,b,c".split_n(%",", 1);
  EXPECT_INT_EQ(limited.len(), 2);
  expect_split_item(limited, 0, %"a");
  expect_split_item(limited, 1, %"b,c");

  List unsplit = %"a,b".split_n(%",", 0);
  EXPECT_INT_EQ(unsplit.len(), 1);
  expect_split_item(unsplit, 0, %"a,b");

  List adjacent = %"a,,b,".split(%",");
  EXPECT_TRUE(adjacent == %("a" "" "b" ""));
  EXPECT_TRUE(%"a,b".split(NULL) == %("a,b"));
  EXPECT_INT_EQ(String.split_lines(NULL, 0).len(), 0);

  List lines = %"a\r\nb\rc\n\n".split_lines(0);
  EXPECT_INT_EQ(lines.len(), 4);
  expect_split_item(lines, 0, %"a");
  expect_split_item(lines, 1, %"b");
  expect_split_item(lines, 2, %"c");
  expect_split_item(lines, 3, NULL);

  List kept = %"a\r\nb\r".split_lines(1);
  EXPECT_INT_EQ(kept.len(), 2);
  expect_split_item(kept, 0, %"a\r\n");
  expect_split_item(kept, 1, %"b\r");
}

static void split_cursor_semantics(void) {
  expect_cursor_items(%" a  b\tc\n".words(), %("a" "b" "c"));
  expect_cursor_items(%"single".words(), %("single"));
  expect_cursor_items(%" \t\r\n".words(), %());
  expect_cursor_items(String.words(NULL), %());

  expect_cursor_items(%"a::b:".splits(%":"), %("a" "" "b" ""));
  expect_cursor_items(%":a".splits(%":"), %("" "a"));
  expect_cursor_items(%"abc".splits(%"x"), %("abc"));
  expect_cursor_items(%"abc".splits(NULL), %("abc"));
  expect_cursor_items(String.splits(NULL, %":"), %());

  expect_cursor_items(%"a\r\nb\rc\n\n".lines(), %("a" "b" "c" ""));
  expect_cursor_items(%"a\n".lines(), %("a"));
  expect_cursor_items(%"\n".lines(), %(""));
  expect_cursor_items(String.lines(NULL), %());

  EXPECT_TRUE(%"a::b:".splits(%":").iter(NULL) == NULL);
  EXPECT_TRUE(%"a::b:".split(%":") ==
              collect_split_cursor(%"a::b:".splits(%":")));
  EXPECT_TRUE(%"a\r\nb\rc\n\n".split_lines(0) ==
              collect_split_cursor(%"a\r\nb\rc\n\n".lines()));
}

static void split_typed_cursor_semantics(void) {
  expect_try_next_items(%" a  b\tc\n".words(), %("a" "b" "c"));
  expect_try_next_items(%"single".words(), %("single"));
  expect_try_next_items(%" \t\r\n".words(), %());
  expect_try_next_items(%"".words(), %());
  expect_try_next_items(String.words(NULL), %());

  expect_try_next_items(%"a::b:".splits(%":"), %("a" "" "b" ""));
  expect_try_next_items(%":a".splits(%":"), %("" "a"));
  expect_try_next_items(%"abc".splits(%"x"), %("abc"));
  expect_try_next_items(%"abc".splits(NULL), %("abc"));
  expect_try_next_items(%"".splits(%":"), %());
  expect_try_next_items(String.splits(NULL, %":"), %());

  expect_try_next_items(%"a\r\nb\rc\n\n".lines(), %("a" "b" "c" ""));
  expect_try_next_items(%"a\n".lines(), %("a"));
  expect_try_next_items(%"\n".lines(), %(""));
  expect_try_next_items(%"".lines(), %());
  expect_try_next_items(String.lines(NULL), %());

  EXPECT_TRUE(collect_try_next(%" a  b\tc\n".words()) ==
              collect_split_cursor(%" a  b\tc\n".words()));
  EXPECT_TRUE(collect_try_next(%"a::b:".splits(%":")) ==
              collect_split_cursor(%"a::b:".splits(%":")));
  EXPECT_TRUE(collect_try_next(%"a\r\nb\rc\n\n".lines()) ==
              collect_split_cursor(%"a\r\nb\rc\n\n".lines()));
}

static void split_typed_cursor_boundaries(void) {
  Split words = %"one two".words();
  int position = 0;
  String item = %"sentinel";
  EXPECT_TRUE(words.try_next(&position, &item));
  EXPECT_TRUE(item == %"one");
  int after_first = position;
  EXPECT_TRUE(words.try_next(&position, &item));
  EXPECT_TRUE(item == %"two");
  int after_last = position;

  EXPECT_FALSE(words.try_next(&position, &item));
  EXPECT_INT_EQ(position, after_last);
  EXPECT_TRUE(item == %"two");
  EXPECT_FALSE(words.try_next(&position, &item));
  EXPECT_INT_EQ(position, after_last);
  EXPECT_TRUE(item == %"two");
  EXPECT_TRUE(after_first < after_last);

  position = 0;
  EXPECT_TRUE(words.try_next(&position, &item));
  EXPECT_TRUE(item == %"one");
  EXPECT_INT_EQ(position, after_first);

  Split fields = %":".splits(%":");
  position = 0;
  EXPECT_TRUE(fields.try_next(&position, &item));
  EXPECT_TRUE(item == %"");
  EXPECT_TRUE(fields.try_next(&position, &item));
  EXPECT_TRUE(item == %"");
  EXPECT_FALSE(fields.try_next(&position, &item));

  position = 0;
  EXPECT_FALSE(String.words(NULL).try_next(&position, &item));
  EXPECT_FALSE(Split.try_next(NULL, &position, &item));
  EXPECT_FALSE(words.try_next(NULL, &item));
  EXPECT_FALSE(words.try_next(&position, NULL));
  EXPECT_INT_EQ(position, 0);
}

static void split_typed_cursor_independence(void) {
  Split words = %"alpha beta gamma".words();
  int first = 0, second = 0;
  String left, right;

  EXPECT_TRUE(words.try_next(&first, &left));
  EXPECT_TRUE(left == %"alpha");
  EXPECT_TRUE(words.try_next(&second, &right));
  EXPECT_TRUE(right == %"alpha");
  EXPECT_TRUE(words.try_next(&first, &left));
  EXPECT_TRUE(left == %"beta");
  EXPECT_TRUE(right == %"alpha");
  EXPECT_TRUE(words.try_next(&second, &right));
  EXPECT_TRUE(right == %"beta");

  struct Iter storage;
  Iter boxed = words.iter(&storage);
  Var boxed_value;
  EXPECT_TRUE(boxed.try_next(&boxed_value));
  EXPECT_TRUE(boxed_value.string() == %"alpha");
  EXPECT_TRUE(words.try_next(&first, &left));
  EXPECT_TRUE(left == %"gamma");
  EXPECT_TRUE(boxed.try_next(&boxed_value));
  EXPECT_TRUE(boxed_value.string() == %"beta");
  EXPECT_FALSE(words.try_next(&first, &left));
  EXPECT_TRUE(boxed.try_next(&boxed_value));
  EXPECT_TRUE(boxed_value.string() == %"gamma");
  EXPECT_FALSE(boxed.try_next(&boxed_value));

  int pairs = 0;
  Split outer = %"a b".words(), inner = %"1 2 3".words();
  int outer_position = 0;
  String outer_item;
  while (outer.try_next(&outer_position, &outer_item)) {
    int inner_position = 0;
    String inner_item;
    while (inner.try_next(&inner_position, &inner_item))
      if (outer_item && inner_item) pairs++;
  }
  EXPECT_INT_EQ(pairs, 6);
}

static void split_cursor_allocation_and_nesting(void) {
  char raw[] = "cursor_alpha  cursor_beta cursor_alpha";
  Pool pool = String.pool_retain_named("string-cursor-probe");
  String value = String.new(raw);
  int count = 0;
  foreach(String word, value.words()) {
    EXPECT_TRUE(word.len() > 0);
    count++;
  }
  EXPECT_INT_EQ(count, 3);
  PoolStats after_first = Pool.stats(pool);

  count = 0;
  foreach(String word, value.words()) count++;
  EXPECT_INT_EQ(count, 3);
  PoolStats after_repeat = Pool.stats(pool);
  EXPECT_INT_EQ((int) after_repeat.interned, (int) after_first.interned);

  Split cursor = value.words();
  struct Iter first_storage, second_storage;
  Iter first = cursor.iter(&first_storage);
  Iter second = cursor.iter(&second_storage);
  Var item;
  EXPECT_TRUE(first.try_next(&item));
  EXPECT_TRUE(item.string() == %"cursor_alpha");
  EXPECT_TRUE(second.try_next(&item));
  EXPECT_TRUE(item.string() == %"cursor_alpha");
  EXPECT_TRUE(first.try_next(&item));
  EXPECT_TRUE(item.string() == %"cursor_beta");
  EXPECT_TRUE(second.try_next(&item));
  EXPECT_TRUE(item.string() == %"cursor_beta");

  int pairs = 0;
  foreach(String left, %"a b".words())
    foreach(String right, %"1 2".words())
      if (left && right) pairs++;
  EXPECT_INT_EQ(pairs, 4);
  String.pool_release();
}

$(import "test-macros.xmacro")

void split_suite(void) {
  $test.run(split_eager_and_join);
  $test.run(split_limits_and_lines);
  $test.run(split_cursor_semantics);
  $test.run(split_typed_cursor_semantics);
  $test.run(split_typed_cursor_boundaries);
  $test.run(split_typed_cursor_independence);
  $test.run(split_cursor_allocation_and_nesting);
}
