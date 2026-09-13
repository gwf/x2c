/*  test-iter.x -- unit tests for iterator helpers */

#include "test-support.x"
$(import "test-macros.xmacro")

#include <limits.h>

static int next_call_count = 0;

static int counted_next(Iter iter, Var *out) {
  int value = iter.state, stop = iter.obj;
  next_call_count++;
  if (value > stop) return 0;
  *out = value;
  iter.state = value + 1;
  return 1;
}

static int void_next(Iter iter, Var *out) {
  (void) iter;
  *out = void;
  return 1;
}


static void iter_rejects_void_from_source(void) {
  struct Iter storage;
  Iter iter = Iter.init(
    &storage, (Var) { .u64 = 0 }, void_next, (Var) { .u64 = 0 }
  );
  Var out = 1;

  int caught = 0;
  try iter.try_next(&out);
  catch %(void-op *): caught = 1;
  EXPECT_TRUE(caught);
  EXPECT_TRUE(iter->next != NULL);
}

static void iter_empty_and_unsupported_status(void) {
  $test.scoped();
  Var out;
  Array empty = %[];
  struct Iter empty_storage;
  Iter empty_iter = empty.iter(&empty_storage);
  EXPECT_FALSE(empty_iter.try_next(&out));

  struct Iter unsupported_storage;
  Iter unsupported = (42).var().iter(&unsupported_storage);
  EXPECT_TRUE(unsupported != NULL);
  EXPECT_FALSE(unsupported.try_next(&out));
  EXPECT_TRUE(unsupported.next() is void);
}

static void iter_exhaustion_is_terminal(void) {
  next_call_count = 0;
  struct Iter storage;
  Iter iter = Iter.init(&storage, 2, counted_next, 0);
  Var out;
  EXPECT_TRUE(iter.try_next(&out));
  EXPECT_INT_EQ(out.int(), 0);
  EXPECT_INT_EQ(next_call_count, 1);
  EXPECT_INT_EQ(iter.next().int(), 1);
  EXPECT_INT_EQ(next_call_count, 2);
  EXPECT_INT_EQ(iter.next().int(), 2);
  EXPECT_INT_EQ(next_call_count, 3);
  EXPECT_FALSE(iter.try_next(&out));
  EXPECT_INT_EQ(next_call_count, 4);
  EXPECT_FALSE(iter.try_next(&out));
  EXPECT_TRUE(iter.next() is void);
  EXPECT_INT_EQ(next_call_count, 4);
}


static void iter_unique_keeps_first_occurrence(void) {
  $test.scoped();
  Var one = 1, two = 2, three = 3;
  Array values = Array.update_n(%[], 5, one, one, two, two, three);
  struct Iter values_iter, uniq_iter;
  Iter uniq = values.iter(&values_iter).unique(&uniq_iter);
  Array collected = Array.new();
  Var next = uniq.next();
  while (next is not void) {
    collected.push(next);
    next = uniq.next();
  }
  EXPECT_INT_EQ(collected.len(), 3);
  EXPECT_VAR_EQ(collected[0], one);
  EXPECT_VAR_EQ(collected[1], two);
  EXPECT_VAR_EQ(collected[2], three);
}

static void iter_rejects_invalid_range(void) {
  $test.scoped();
  int caught = 0;
  struct Iter range_storage;
  try range(0, 4, 0, &range_storage);
  catch %(bad-arg *): caught++;
  EXPECT_INT_EQ(caught, 1);
}

static void iter_var_iter_into(void) {
  $test.scoped();
  Var seven = 7, eight = 8, nine = 9;
  Array arr = Array.update_n(%[], 3, seven, eight, nine);
  struct Iter arr_iter_storage;
  Iter arr_iter = Var.iter(arr, &arr_iter_storage);
  EXPECT_INT_EQ(arr_iter.next().int(), 7);
  EXPECT_INT_EQ(arr_iter.next().int(), 8);
  EXPECT_INT_EQ(arr_iter.next().int(), 9);
  EXPECT_TRUE(arr_iter.next() is void);

  List lst = %(1 2 3);
  struct Iter list_iter_storage;
  Iter list_iter = Var.iter(lst, &list_iter_storage);
  EXPECT_INT_EQ(list_iter.next().int(), 1);
  EXPECT_INT_EQ(list_iter.next().int(), 2);
  EXPECT_INT_EQ(list_iter.next().int(), 3);
  EXPECT_TRUE(list_iter.next() is void);

  String str = %"ab";
  struct Iter str_iter_storage;
  Iter str_iter = Var.iter(str, &str_iter_storage);
  EXPECT_INT_EQ(str_iter.next().int(), 'a');
  EXPECT_INT_EQ(str_iter.next().int(), 'b');
  EXPECT_TRUE(str_iter.next() is void);

  // Ensure iter_into handles iter Vars by returning the underlying iterator.
  struct Iter passthrough_storage;
  Iter base = range(0, 2, 1, &passthrough_storage);
  Iter wrapped = Var.iter(base, &passthrough_storage);
  EXPECT_INT_EQ(wrapped.next().int(), 0);
  EXPECT_INT_EQ(wrapped.next().int(), 1);
  EXPECT_INT_EQ(wrapped.next().int(), 2);
  EXPECT_TRUE(wrapped.next() is void);
}

static void iter_descending_range(void) {
  struct Iter storage;
  Iter values = range(5, 1, -2, &storage);
  EXPECT_INT_EQ(values.next().int(), 5);
  EXPECT_INT_EQ(values.next().int(), 3);
  EXPECT_INT_EQ(values.next().int(), 1);
  EXPECT_TRUE(values.next() is void);
}

static void iter_range_boundaries(void) {
  Var out;
  struct Iter max_storage;
  Iter max_values = range(INT_MAX - 1, INT_MAX, 1, &max_storage);
  EXPECT_TRUE(max_values.try_next(&out));
  EXPECT_INT_EQ(out.int(), INT_MAX - 1);
  EXPECT_TRUE(max_values.try_next(&out));
  EXPECT_INT_EQ(out.int(), INT_MAX);
  EXPECT_FALSE(max_values.try_next(&out));

  struct Iter min_storage;
  Iter min_values = range(INT_MIN + 1, INT_MIN, -1, &min_storage);
  EXPECT_TRUE(min_values.try_next(&out));
  EXPECT_INT_EQ(out.int(), INT_MIN + 1);
  EXPECT_TRUE(min_values.try_next(&out));
  EXPECT_INT_EQ(out.int(), INT_MIN);
  EXPECT_FALSE(min_values.try_next(&out));

  struct Iter crossing_storage;
  Iter crossing = range(0, 5, 2, &crossing_storage);
  EXPECT_INT_EQ(crossing.next().int(), 0);
  EXPECT_INT_EQ(crossing.next().int(), 2);
  EXPECT_INT_EQ(crossing.next().int(), 4);
  EXPECT_FALSE(crossing.try_next(&out));

  struct Iter equal_storage;
  Iter equal = range(7, 7, 3, &equal_storage);
  EXPECT_INT_EQ(equal.next().int(), 7);
  EXPECT_FALSE(equal.try_next(&out));

  struct Iter max_step_storage;
  Iter max_step = range(INT_MIN, INT_MAX, INT_MAX, &max_step_storage);
  EXPECT_INT_EQ(max_step.next().int(), INT_MIN);
  EXPECT_INT_EQ(max_step.next().int(), -1);
  EXPECT_INT_EQ(max_step.next().int(), INT_MAX - 1);
  EXPECT_FALSE(max_step.try_next(&out));

  struct Iter min_step_storage;
  Iter min_step = range(INT_MAX, INT_MIN, INT_MIN, &min_step_storage);
  EXPECT_INT_EQ(min_step.next().int(), INT_MAX);
  EXPECT_INT_EQ(min_step.next().int(), -1);
  EXPECT_FALSE(min_step.try_next(&out));

  struct Iter max_endpoint_storage;
  Iter max_endpoint = range(INT_MAX, INT_MAX, 1, &max_endpoint_storage);
  EXPECT_INT_EQ(max_endpoint.next().int(), INT_MAX);
  EXPECT_FALSE(max_endpoint.try_next(&out));
  EXPECT_FALSE(max_endpoint.try_next(&out));

  struct Iter wrong_storage;
  Iter wrong = range(5, 1, 1, &wrong_storage);
  EXPECT_FALSE(wrong.try_next(&out));
}
void iter_suite(void) {
  $test.run(iter_empty_and_unsupported_status);
  $test.run(iter_exhaustion_is_terminal);
  $test.run(iter_rejects_void_from_source);
  $test.run(iter_unique_keeps_first_occurrence);
  $test.run(iter_rejects_invalid_range);
  $test.run(iter_var_iter_into);
  $test.run(iter_descending_range);
  $test.run(iter_range_boundaries);
}
