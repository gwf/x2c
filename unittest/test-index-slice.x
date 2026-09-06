/*  test-index-slice.x -- language-level indexing and slice syntax tests */

#include "test-support.x"
$(import "test-macros.xmacro")

#include <string.h>

static int expect_array_ints(Array array, int *values, int count) {
  if (!EXPECT_INT_EQ(array.len(), count)) return 0;
  for (int i = 0; i < count; i++)
    if (!EXPECT_INT_EQ(array[i].int(), values[i])) return 0;
  return 1;
}

static void normalization_failures_transfer(void) {
  int start = 1, stop = 3, resumed = 0;
  try {
    x2c_normalize_index(0, -1);
    resumed++;
  }
  catch %(bad-arg *): {}
  try {
    x2c_normalize_slice(&start, &stop, 0, 4);
    resumed++;
  }
  catch %(bad-arg *): {}
  try {
    x2c_normalize_slice(NULL, &stop, 1, 4);
    resumed++;
  }
  catch %(bad-arg *): {}
  try {
    x2c_normalize_slice(&start, &stop, 1, -1);
    resumed++;
  }
  catch %(bad-arg *): {}
  EXPECT_INT_EQ(resumed, 0);
  EXPECT_INT_EQ(start, 1);
  EXPECT_INT_EQ(stop, 3);
}

static void collection_index_syntax(void) {
  $test.scoped();

  Array array = %[0, 1, 2, 3, 4];
  List list = %(0 1 2 3 4);
  String string = %"abcde";
  Map map = %{};

  EXPECT_INT_EQ(array[-1].int(), 4);
  EXPECT_INT_EQ(list[-1].int(), 4);
  EXPECT_INT_EQ(string[-1], 'e');
  EXPECT_TRUE(array[9] is void);
  EXPECT_TRUE(list[9] is void);

  map[<answer>] = 42;
  map[%"name"] = %"x2c";
  EXPECT_INT_EQ(map[<answer>].int(), 42);
  EXPECT_TRUE(map[%"name"] == %"x2c");
  EXPECT_TRUE(map[<missing>] is void);

  array[1] = 9;
  EXPECT_INT_EQ(array[1].int(), 9);
  EXPECT_INT_EQ(array.setindex(-1, 8).int(), 8);
  EXPECT_INT_EQ(array[-1].int(), 8);

  // A transient String.malloc buffer is filled through a char *, which is
  // the supported native-write path. Bracket assignment on a String is a
  // compile error; see the string-bracket-assignment compiler fixture.
  String buffer = String.malloc(4);
  strcpy(buffer, "abc");
  char *writable = buffer;
  writable[0] = 'z';
  EXPECT_INT_EQ(buffer[0], 'z');
  EXPECT_INT_EQ(writable[0], 'z');
  String.free(buffer);

}

static void collection_index_boundaries(void) {
  $test.scoped();

  Array array = %[10, 20, 30];
  List list = %(10 20 30);
  String string = %"abc";

  EXPECT_INT_EQ(x2c_normalize_index(0, 0), -1);
  EXPECT_INT_EQ(x2c_normalize_index(0, 3), 0);
  EXPECT_INT_EQ(x2c_normalize_index(2, 3), 2);
  EXPECT_INT_EQ(x2c_normalize_index(-3, 3), 0);
  EXPECT_INT_EQ(x2c_normalize_index(-1, 3), 2);
  EXPECT_INT_EQ(x2c_normalize_index(-4, 3), -1);
  EXPECT_INT_EQ(x2c_normalize_index(3, 3), -1);

  EXPECT_INT_EQ(array[0].int(), 10);
  EXPECT_INT_EQ(array[-3].int(), 10);
  EXPECT_TRUE(array[-4] is void);
  EXPECT_TRUE(array[3] is void);

  EXPECT_INT_EQ(list[0].int(), 10);
  EXPECT_INT_EQ(list[-3].int(), 10);
  EXPECT_TRUE(list[-4] is void);
  EXPECT_TRUE(list[3] is void);

  EXPECT_INT_EQ(string[0], 'a');
  EXPECT_INT_EQ(string[-3], 'a');
  EXPECT_INT_EQ(string[-4], -1);
  EXPECT_INT_EQ(string[3], -1);

}

static void collection_slice_syntax(void) {
  $test.scoped();

  Array array = %[0, 1, 2, 3, 4];
  List list = %(0 1 2 3 4);
  String string = %"abcde";
  int all[] = { 0, 1, 2, 3, 4 };
  int middle[] = { 1, 2, 3 };
  int prefix[] = { 0, 1, 2 };
  int suffix[] = { 2, 3, 4 };
  int stride[] = { 0, 2, 4 };
  int reverse[] = { 4, 3, 2, 1, 0 };
  int stepped[] = { 1, 3 };

  expect_array_ints(array[:], all, 5);
  expect_array_ints(array[1:4], middle, 3);
  expect_array_ints(array[:3], prefix, 3);
  expect_array_ints(array[2:], suffix, 3);
  expect_array_ints(array[::2], stride, 3);
  expect_array_ints(array[::-1], reverse, 5);
  expect_array_ints(array[1:4:2], stepped, 2);

  EXPECT_TRUE(list[:] == %(0 1 2 3 4));
  EXPECT_TRUE(list[1:4] == %(1 2 3));
  EXPECT_TRUE(list[:3] == %(0 1 2));
  EXPECT_TRUE(list[2:] == %(2 3 4));
  EXPECT_TRUE(list[::2] == %(0 2 4));
  EXPECT_TRUE(list[::-1] == %(4 3 2 1 0));
  EXPECT_TRUE(list[1:4:2] == %(1 3));

  EXPECT_TRUE(string[:] == %"abcde");
  EXPECT_TRUE(string[1:4] == %"bcd");
  EXPECT_TRUE(string[:3] == %"abc");
  EXPECT_TRUE(string[2:] == %"cde");
  EXPECT_TRUE(string[::2] == %"ace");
  EXPECT_TRUE(string[::-1] == %"edcba");
  EXPECT_TRUE(string[1:4:2] == %"bd");

}

static void slice_stop_beyond_length_clamps(void) {
  $test.scoped();
  Array a = %[0, 1, 2, 3], b = a[0:5];
  EXPECT_INT_EQ((int) Array.len(b), 4);
  String s = %"abcdefghij", t = s[-100:100];
  EXPECT_INT_EQ(s.len(), t.len());
}

static void slice_negative_step_at_length(void) {
  $test.scoped();
  Array a = %[10, 20, 30], b = a[3:0:-1];
  EXPECT_INT_EQ((int) Array.len(b), 2);
  EXPECT_INT_EQ(b[0].int(), 30);
  EXPECT_INT_EQ(b[1].int(), 20);
}


void index_slice_suite(void) {
  $test.run(normalization_failures_transfer);
  $test.run(collection_index_syntax);
  $test.run(collection_index_boundaries);
  $test.run(collection_slice_syntax);
  $test.run(slice_stop_beyond_length_clamps);
  $test.run(slice_negative_step_at_length);
}
