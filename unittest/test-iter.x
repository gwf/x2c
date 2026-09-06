/*  test-iter.x -- unit tests for iterator helpers */

#include "test-support.x"
$(import "test-macros.xmacro")

#include <limits.h>

static int map_call_count = 0;
static int next_call_count = 0;
static int scan_call_count = 0;
static Var double_value(Var value) {
  map_call_count++;
  return value * 2;
}

static Var add_values(Var acc, Var item) {
  return acc + item;
}

static Var counted_add(Var acc, Var item) {
  scan_call_count++;
  return acc + item;
}

static int greater_than_one(Var value) {
  return value > 1;
}

static Var pair_sum(Var left, Var right) {
  return left + right;
}

typedef Var (*IterUnaryFunction)(Var);
typedef Var (*IterBinaryFunction)(Var, Var);
typedef int (*IterPredicateFunction)(Var);

static Var _iter_no_arguments(void) {
  return 1;
}

static Var _iter_reference_argument(int &value) {
  return value;
}

static Var _iter_reference_pair(int &left, int &right) {
  return left + right;
}

static long _iter_long_value(long value) {
  return value + 1;
}

static long _iter_long_pair(long left, long right) {
  return left + right;
}

static Var _iter_truthy_string(Var value) {
  return value > 1 ? %"yes" : NULL;
}

static Var _iter_raise(Var value) {
  raise %(invariant (value $value));
}

static Var _iter_void_result(Var value) {
  (void) value;
  return void;
}

static Iter _iter_return_captured_map(Iter source, int bias, Iter dest) {
  return source.map((%!(Var value) => value + bias), dest);
}

static Iter _iter_return_dynamic_map(Iter source, Iter dest) {
  IterUnaryFunction fn = double_value;
  return source.map(fn, dest);
}

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

static void iter_map_lazy(void) {
  $test.scoped();
  map_call_count = 0;
  struct Iter src_storage, mapped_storage;
  Iter src = range(0, 4, 1, &src_storage);
  Iter mapped = src.map(double_value, &mapped_storage);
  Var first = mapped.next();
  EXPECT_INT_EQ(map_call_count, 1);
  EXPECT_INT_EQ(first.int(), 0);
  Var second = mapped.next();
  EXPECT_INT_EQ(map_call_count, 2);
  EXPECT_INT_EQ(second.int(), 2);
}

static void iter_func_callbacks(void) {
  $test.scoped();
  IterUnaryFunction unary_pointer = double_value;
  IterBinaryFunction binary_pointer = add_values;
  IterPredicateFunction predicate_pointer = greater_than_one;
  int bias = 1, threshold = 1, floor = 0, high = 2;
  Func captured_unary = %!(Var value) => value + bias;
  Func captured_binary =
    %!(Var left, Var right) => left + right + bias;
  Func captured_predicate = %!(Var value) => value > threshold;
  Func captured_all = %!(Var value) => value > floor;
  Func captured_find = %!(Var value) => value > high;

  EXPECT_TRUE(range(1, 3, 1).map(unary_pointer).list() == %(2 4 6));
  EXPECT_TRUE(range(1, 3, 1).map(captured_unary).list() == %(2 3 4));
  EXPECT_TRUE(range(1, 3, 1).filter(predicate_pointer).list() == %(2 3));
  EXPECT_TRUE(range(1, 3, 1).filter(captured_predicate).list() == %(2 3));
  EXPECT_TRUE(range(1, 3, 1).filter(_iter_truthy_string).list() == %(2 3));

  EXPECT_TRUE(
    range(1, 3, 1).zip_with(range(10, 12, 1), pair_sum).list() ==
      %(11 13 15));
  EXPECT_TRUE(
    range(1, 3, 1).zip_with(range(10, 12, 1), binary_pointer).list() ==
      %(11 13 15));
  EXPECT_TRUE(
    range(1, 3, 1).zip_with(range(10, 12, 1), captured_binary).list() ==
      %(12 14 16));
  EXPECT_TRUE(
    range(1, 3, 1).map2(range(10, 12, 1), binary_pointer).list() ==
      %(11 13 15));
  EXPECT_TRUE(
    range(1, 3, 1).map2(range(10, 12, 1), captured_binary).list() ==
      %(12 14 16));

  EXPECT_TRUE(range(1, 3, 1).scan(0, binary_pointer).list() == %(1 3 6));
  EXPECT_TRUE(range(1, 3, 1).scan(0, captured_binary).list() == %(2 5 9));
  EXPECT_INT_EQ(range(1, 3, 1).reduce(binary_pointer, void).int(), 6);
  EXPECT_INT_EQ(range(1, 3, 1).reduce(captured_binary, void).int(), 8);
  EXPECT_INT_EQ(range(1, 3, 1).foldl(0, binary_pointer).int(), 6);
  EXPECT_INT_EQ(range(1, 3, 1).foldl(0, captured_binary).int(), 9);

  EXPECT_TRUE(range(1, 3, 1).any(predicate_pointer));
  EXPECT_TRUE(range(1, 3, 1).any(captured_predicate));
  EXPECT_FALSE(range(1, 3, 1).all(predicate_pointer));
  EXPECT_TRUE(range(1, 3, 1).all(captured_all));
  EXPECT_INT_EQ(range(1, 3, 1).find(predicate_pointer).int(), 2);
  EXPECT_INT_EQ(range(1, 3, 1).find(captured_find).int(), 3);
}

static void iter_func_failures_and_empty_sources(void) {
  $test.scoped();
  Func wrong_arity = _iter_no_arguments;
  int arity_caught = 0;

  try range(1, 2, 1).map(wrong_arity).next();
  catch %(bad-arity *): arity_caught++;
  try range(1, 2, 1).filter(wrong_arity).next();
  catch %(bad-arity *): arity_caught++;
  try range(1, 2, 1).zip_with(range(3, 4, 1), wrong_arity).next();
  catch %(bad-arity *): arity_caught++;
  try range(1, 2, 1).map2(range(3, 4, 1), wrong_arity).next();
  catch %(bad-arity *): arity_caught++;
  try range(1, 2, 1).scan(0, wrong_arity).next();
  catch %(bad-arity *): arity_caught++;
  try range(1, 2, 1).reduce(wrong_arity, void);
  catch %(bad-arity *): arity_caught++;
  try range(1, 2, 1).foldl(0, wrong_arity);
  catch %(bad-arity *): arity_caught++;
  try range(1, 2, 1).any(wrong_arity);
  catch %(bad-arity *): arity_caught++;
  try range(1, 2, 1).all(wrong_arity);
  catch %(bad-arity *): arity_caught++;
  try range(1, 2, 1).find(wrong_arity);
  catch %(bad-arity *): arity_caught++;
  EXPECT_INT_EQ(arity_caught, 10);

  EXPECT_TRUE(range(1, 0, 1).map(wrong_arity).next() is void);
  EXPECT_TRUE(range(1, 0, 1).filter(wrong_arity).next() is void);
  EXPECT_TRUE(
    range(1, 0, 1).zip_with(range(1, 2, 1), wrong_arity).next() is void);
  EXPECT_TRUE(
    range(1, 0, 1).map2(range(1, 2, 1), wrong_arity).next() is void);
  EXPECT_TRUE(range(1, 0, 1).scan(0, wrong_arity).next() is void);
  EXPECT_TRUE(range(1, 0, 1).reduce(wrong_arity, void) is void);
  EXPECT_INT_EQ(range(1, 0, 1).foldl(7, wrong_arity).int(), 7);
  EXPECT_FALSE(range(1, 0, 1).any(wrong_arity));
  EXPECT_TRUE(range(1, 0, 1).all(wrong_arity));
  EXPECT_TRUE(range(1, 0, 1).find(wrong_arity) is void);

  Func reference_unary = _iter_reference_argument;
  Func reference_binary = _iter_reference_pair;
  Func numeric_unary = _iter_long_value;
  Func numeric_binary = _iter_long_pair;
  int reference_caught = 0, conversion_caught = 0;
  try range(1, 2, 1).map(reference_unary).next();
  catch %(bad-types *): reference_caught++;
  try range(1, 2, 1).reduce(reference_binary, void);
  catch %(bad-types *): reference_caught++;
  try %("text").iter().map(numeric_unary).next();
  catch %(no-convert *): conversion_caught++;
  try %("text" "more").iter().reduce(numeric_binary, void);
  catch %(no-convert *): conversion_caught++;
  EXPECT_INT_EQ(reference_caught, 2);
  EXPECT_INT_EQ(conversion_caught, 2);

  int transferred = 0, bad_result_caught = 0;
  try range(76, 76, 1).map(_iter_raise).next();
  catch %(invariant (value ?value)): transferred = value.int() == 76;
  try range(1, 1, 1).map(_iter_void_result).next();
  catch %(bad-result *): bad_result_caught = 1;
  EXPECT_TRUE(transferred);
  EXPECT_TRUE(bad_result_caught);
}

static void iter_func_lifetimes_and_allocations(void) {
  $test.scoped();
  struct Iter captured_source_storage, captured_map_storage;
  Iter captured_source = range(1, 2, 1, &captured_source_storage);
  Iter captured = _iter_return_captured_map(
    captured_source, 4, &captured_map_storage);
  EXPECT_INT_EQ(captured.next().int(), 5);
  EXPECT_INT_EQ(captured.next().int(), 6);

  struct Iter dynamic_source_storage, dynamic_map_storage;
  Iter dynamic_source = range(1, 2, 1, &dynamic_source_storage);
  Iter dynamic = _iter_return_dynamic_map(
    dynamic_source, &dynamic_map_storage);
  EXPECT_INT_EQ(dynamic.next().int(), 2);
  EXPECT_INT_EQ(dynamic.next().int(), 4);

  struct Iter source_storage, map_storage, filter_storage;
  Iter source = range(0, 3, 1, &source_storage);
  Iter mapped = source.map(double_value, &map_storage);
  Iter filtered = mapped.filter(greater_than_one, &filter_storage);
  ScopeStats before = Scope.stats();
  Var value;
  int count = 0;
  while (filtered.try_next(&value)) count++;
  ScopeStats after = Scope.stats();
  EXPECT_INT_EQ(count, 3);
  EXPECT_INT_EQ(after.allocation_calls, before.allocation_calls);
}

static void iter_immediate_fluent_chains(void) {
  $test.scoped();
  map_call_count = 0;
  List values = range(0, 3, 1)
    .map(double_value).filter(greater_than_one).list();
  EXPECT_INT_EQ(values.len(), 3);
  EXPECT_INT_EQ(values[0].int(), 2);
  EXPECT_INT_EQ(values[1].int(), 4);
  EXPECT_INT_EQ(values[2].int(), 6);
  EXPECT_INT_EQ(map_call_count, 4);

  Var total = range(1, 3, 1)
    .map2(range(10, 12, 1), pair_sum).sum();
  EXPECT_INT_EQ(total.int(), 39);
}

static void iter_zip_and_unzip(void) {
  $test.scoped();
  struct Iter a_storage, b_storage, zipped_storage;
  Iter a = range(0, 2, 1, &a_storage);
  Iter b = range(10, 12, 1, &b_storage);
  Iter zipped = a.zip(b, &zipped_storage);
  Var v = zipped.next();
  List pair = v;
  EXPECT_INT_EQ(pair.car().int(), 0);
  EXPECT_INT_EQ(pair.cdr().car().int(), 10);
  struct Iter zfu_left_storage, zfu_right_storage, zfu_zip_storage, columns_storage;
  UnzipShared unzip_shared;
  Iter zfu_left = range(0, 2, 1, &zfu_left_storage);
  Iter zfu_right = range(10, 12, 1, &zfu_right_storage);
  Iter zipped_for_unzip = zfu_left.zip(zfu_right, &zfu_zip_storage);
  Iter columns = zipped_for_unzip.unzip(&unzip_shared, &columns_storage);
  Var col0_var = columns.next(), col1_var = columns.next();
  EXPECT_TRUE(columns.next() is void);
  struct Iter col0_storage, col1_storage;
  Iter col0 = col0_var.iter(&col0_storage);
  Iter col1 = col1_var.iter(&col1_storage);
  EXPECT_INT_EQ(col0.next().int(), 0);
  EXPECT_INT_EQ(col1.next().int(), 10);
  EXPECT_INT_EQ(col0.next().int(), 1);
  EXPECT_INT_EQ(col1.next().int(), 11);
  EXPECT_INT_EQ(col0.next().int(), 2);
  EXPECT_INT_EQ(col1.next().int(), 12);
  EXPECT_TRUE(col0.next() is void);
  EXPECT_TRUE(col1.next() is void);
}

static void iter_unzip_bounds_consumed_buffers(void) {
  $test.scoped();
  int count = 600;
  struct Iter left_storage, right_storage, zip_storage, columns_storage;
  UnzipShared shared;
  Iter left = range(0, count - 1, 1, &left_storage);
  Iter right = range(count, 2 * count - 1, 1, &right_storage);
  Iter zipped = left.zip(right, &zip_storage);
  Iter columns = zipped.unzip(&shared, &columns_storage);
  Var first_var = columns.next(), second_var = columns.next();
  struct Iter first_storage, second_storage;
  Iter first = first_var.iter(&first_storage);
  Iter second = second_var.iter(&second_storage);
  Var value;
  int seen = 0;
  while (first.try_next(&value)) {
    EXPECT_INT_EQ(value.int(), seen);
    seen++;
  }
  EXPECT_INT_EQ(seen, count);
  EXPECT_TRUE(shared.buffers[0].len() < 256);
  EXPECT_INT_EQ(shared.buffers[1].len(), count);

  seen = 0;
  while (second.try_next(&value)) {
    EXPECT_INT_EQ(value.int(), count + seen);
    seen++;
  }
  EXPECT_INT_EQ(seen, count);
  EXPECT_TRUE(shared.buffers[0].len() < 256);
  EXPECT_TRUE(shared.buffers[1].len() < 256);
}


static void iter_rejects_invalid_ranges_and_unzip_rows(void) {
  $test.scoped();
  int caught = 0;

  struct Iter range_storage;
  try range(0, 4, 0, &range_storage);
  catch %(bad-arg *): caught++;

  List scalar = %(1);
  struct Iter scalar_source, scalar_columns, scalar_column;
  UnzipShared scalar_shared;
  Iter columns = scalar.iter(&scalar_source).unzip(
    &scalar_shared, &scalar_columns
  );
  Iter column = columns.next().iter(&scalar_column);
  try column.next();
  catch %(bad-types *): caught++;
  EXPECT_INT_EQ(scalar_shared.buffers[0].len(), 0);
  EXPECT_INT_EQ(scalar_shared.buffers[1].len(), 0);

  List short_pair = %((1));
  struct Iter pair_source, pair_columns, pair_column;
  UnzipShared pair_shared;
  columns = short_pair.iter(&pair_source).unzip(&pair_shared, &pair_columns);
  column = columns.next().iter(&pair_column);
  try column.next();
  catch %(bad-arg *): caught++;
  EXPECT_INT_EQ(pair_shared.buffers[0].len(), 0);
  EXPECT_INT_EQ(pair_shared.buffers[1].len(), 0);

  EXPECT_INT_EQ(caught, 3);
}

static void iter_chain_unique(void) {
  $test.scoped();
  Var one = 1, two = 2, three = 3, four = 4;
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
  struct Iter left_storage, right_storage, chain_storage;
  Iter left = range(0, 1, 1, &left_storage);
  Iter right = Iter.repeat(four, 2, &right_storage);
  Iter chained = left.chain(right, &chain_storage);
  EXPECT_INT_EQ(chained.next().int(), 0);
  EXPECT_INT_EQ(chained.next().int(), 1);
  EXPECT_VAR_EQ(chained.next(), four);
  EXPECT_VAR_EQ(chained.next(), four);
  EXPECT_TRUE(chained.next() is void);
}

static void iter_enumerate_repeat_head(void) {
  $test.scoped();
  struct Iter enum_base_storage, enum_storage;
  Iter enumerated = range(5, 7, 1, &enum_base_storage).enumerate(
    100, &enum_storage);
  Var item = enumerated.next();
  List pair = item;
  EXPECT_INT_EQ(pair.car().int(), 100);
  EXPECT_INT_EQ(pair.cdr().car().int(), 5);
  pair = enumerated.next();
  EXPECT_INT_EQ(pair.car().int(), 101);
  EXPECT_INT_EQ(pair.cdr().car().int(), 6);
  pair = enumerated.next();
  EXPECT_INT_EQ(pair.car().int(), 102);
  EXPECT_INT_EQ(pair.cdr().car().int(), 7);
  EXPECT_TRUE(enumerated.next() is void);
  Var nine = 9;
  struct Iter repeat_storage;
  Iter repeated = Iter.repeat(nine, 3, &repeat_storage);
  EXPECT_INT_EQ(repeated.next().int(), 9);
  EXPECT_INT_EQ(repeated.next().int(), 9);
  EXPECT_INT_EQ(repeated.next().int(), 9);
  EXPECT_TRUE(repeated.next() is void);
  struct Iter head_base_storage, head_storage;
  Iter head = range(0, 4, 1, &head_base_storage).head(
    2, &head_storage);
  EXPECT_INT_EQ(head.next().int(), 0);
  EXPECT_INT_EQ(head.next().int(), 1);
  EXPECT_TRUE(head.next() is void);
}

static void iter_accumulate_and_aggregates(void) {
  $test.scoped();
  Var zero = 0;
  struct Iter acc_base_storage, acc_storage;
  Iter acc = range(1, 5, 1, &acc_base_storage).accumulate(
    zero, &acc_storage);
  EXPECT_INT_EQ(acc.next().int(), 1);
  EXPECT_INT_EQ(acc.next().int(), 3);
  EXPECT_INT_EQ(acc.next().int(), 6);
  EXPECT_INT_EQ(acc.next().int(), 10);
  EXPECT_INT_EQ(acc.next().int(), 15);
  EXPECT_TRUE(acc.next() is void);

  Var half = 0.5;
  struct Iter float_base_storage, float_storage;
  Iter floats = range(1, 3, 1, &float_base_storage).accumulate(
    half, &float_storage);
  Var running = floats.next();
  EXPECT_TRUE(running is <f64>);
  EXPECT_TRUE(running.double() == 1.5);
  running = floats.next();
  EXPECT_TRUE(running.double() == 3.5);
  running = floats.next();
  EXPECT_TRUE(running.double() == 6.5);
  EXPECT_TRUE(floats.next() is void);

  struct Iter reduce_storage;
  Iter reduce_iter = range(1, 5, 1, &reduce_storage);
  Var reduced = reduce_iter.reduce(add_values, void);
  EXPECT_INT_EQ(reduced.int(), 15);

  Var ten = 10;
  struct Iter reduce_init_storage;
  Iter reduce_init_iter = range(1, 5, 1, &reduce_init_storage);
  Var reduced_with_init = reduce_init_iter.reduce(add_values, ten);
  EXPECT_INT_EQ(reduced_with_init.int(), 25);

  struct Iter sum_storage;
  Iter sum_iter = range(1, 5, 1, &sum_storage);
  EXPECT_INT_EQ(sum_iter.sum().int(), 15);

  struct Iter product_storage;
  Iter product_iter = range(1, 5, 1, &product_storage);
  EXPECT_INT_EQ(product_iter.product().int(), 120);

  struct Iter count_storage;
  Iter count_iter = range(1, 5, 1, &count_storage);
  EXPECT_INT_EQ(count_iter.count(), 5);

  struct Iter max_storage;
  Iter max_iter = range(1, 5, 1, &max_storage);
  EXPECT_INT_EQ(max_iter.max().int(), 5);

  struct Iter min_storage;
  Iter min_iter = range(1, 5, 1, &min_storage);
  EXPECT_INT_EQ(min_iter.min().int(), 1);

  Array empty = %[];
  struct Iter empty_reduce_storage;
  Iter empty_reduce = empty.iter(&empty_reduce_storage);
  EXPECT_TRUE(empty_reduce.reduce(add_values, void) is void);
  struct Iter arr_sum_storage, arr_prod_storage, arr_count_storage,
               arr_max_storage, arr_min_storage;
  EXPECT_INT_EQ(empty.iter(&arr_sum_storage).sum().int(), 0);
  EXPECT_INT_EQ(empty.iter(&arr_prod_storage).product().int(), 1);
  EXPECT_INT_EQ(empty.iter(&arr_count_storage).count(), 0);
  EXPECT_TRUE(empty.iter(&arr_max_storage).max() is void);
  EXPECT_TRUE(empty.iter(&arr_min_storage).min() is void);

}

static void iter_aggregates_preserve_var_semantics(void) {
  $test.scoped();
  Array floats = %[
    ${Var.new(<f32>, 1.25)}, ${Var.new(<f64>, 2.5)},
    ${Var.box_long_double(3.0L)}
  ];
  struct Iter sum_storage;
  Var sum = floats.iter(&sum_storage).sum();
  EXPECT_TRUE(sum is <ldouble>);
  EXPECT_TRUE(sum.long_double_value() == 6.75L);

  Array products = %[${Var.box_long_double(1.5L)}, ${Var.new(<ulong>, 2)}];
  struct Iter product_storage;
  Var product = products.iter(&product_storage).product();
  EXPECT_TRUE(product is <ldouble>);
  EXPECT_TRUE(product.long_double_value() == 3.0L);

  unsigned long long wide_value = (unsigned long long) LONG_MAX + 1ULL;
  Array wide = %[${Var.box_ulong_long(wide_value)}, ${Var.box_ulong_long(2)}];
  struct Iter wide_sum_storage;
  Var wide_sum = wide.iter(&wide_sum_storage).sum();
  EXPECT_TRUE(wide_sum is <ullong>);
  EXPECT_TRUE(wide_sum.ulong_long_value() == wide_value + 2);

  Array negatives = %[
    ${Var.new(<f64>, -4.5)}, ${Var.new(<f64>, -2.25)},
    ${Var.new(<f64>, -3.0)}
  ];
  struct Iter max_storage, min_storage;
  EXPECT_TRUE(negatives.iter(&max_storage).max().floating() == -2.25);
  EXPECT_TRUE(negatives.iter(&min_storage).min().floating() == -4.5);

  Array strings = %[ "z", "a", "m" ];
  struct Iter string_max_storage, string_min_storage;
  EXPECT_STR_EQ(strings.iter(&string_max_storage).max().string(), "z");
  EXPECT_STR_EQ(strings.iter(&string_min_storage).min().string(), "a");

  Var integer = 7;
  Var string = %"seven";
  Var expected_max = integer > string ? integer : string;
  Var expected_min = integer < string ? integer : string;
  Array mixed = %[$integer, $string];
  struct Iter mixed_max_storage, mixed_min_storage;
  EXPECT_VAR_EQ(mixed.iter(&mixed_max_storage).max(), expected_max);
  EXPECT_VAR_EQ(mixed.iter(&mixed_min_storage).min(), expected_min);
}

static void iter_scan_and_array_collector(void) {
  $test.scoped();
  scan_call_count = 0;
  struct Iter source_storage, scan_storage;
  Iter scanned = range(1, 3, 1, &source_storage).scan(
    10, counted_add, &scan_storage);
  EXPECT_INT_EQ(scan_call_count, 0);
  EXPECT_INT_EQ(scanned.next().int(), 11);
  EXPECT_INT_EQ(scan_call_count, 1);
  EXPECT_INT_EQ(scanned.next().int(), 13);
  EXPECT_INT_EQ(scanned.next().int(), 16);
  EXPECT_INT_EQ(scan_call_count, 3);
  EXPECT_TRUE(scanned.next() is void);
  EXPECT_INT_EQ(scan_call_count, 3);

  struct Iter collect_source_storage;
  Array values = range(-1, 1, 1, &collect_source_storage).array();
  EXPECT_INT_EQ(values.len(), 3);
  EXPECT_INT_EQ(values[0].int(), -1);
  EXPECT_INT_EQ(values[1].int(), 0);
  EXPECT_INT_EQ(values[2].int(), 1);

  struct Iter empty_source_storage, empty_scan_storage;
  Iter empty_scan = range(1, 0, 1, &empty_source_storage).scan(
    7, counted_add, &empty_scan_storage);
  Array empty = empty_scan.array();
  EXPECT_INT_EQ(empty.len(), 0);

  struct Iter null_source_storage, null_scan_storage;
  EXPECT_TRUE(range(0, 0, 1, &null_source_storage).scan(
    0, NULL, &null_scan_storage) == NULL);
}

static void iter_fold_predicates_and_zip_with(void) {
  $test.scoped();
  Var zero = 0;
  struct Iter fold_base_storage;
  Var sum = range(0, 4, 1, &fold_base_storage).foldl(zero, add_values);
  EXPECT_INT_EQ(sum.int(), 10);
  struct Iter any_base_storage;
  EXPECT_TRUE(range(0, 4, 1, &any_base_storage).any(greater_than_one));
  struct Iter all_base_storage;
  EXPECT_FALSE(range(0, 2, 1, &all_base_storage).all(greater_than_one));
  struct Iter empty_base_storage, empty_head_storage;
  Iter empty = range(0, 0, 1, &empty_base_storage).head(
    0, &empty_head_storage);
  EXPECT_TRUE(empty.all(greater_than_one));
  struct Iter head_base_storage, head_storage;
  EXPECT_TRUE(range(0, 0, 1, &head_base_storage)
    .head(0, &head_storage).all(NULL));
  struct Iter find_base_storage;
  Var found = range(0, 4, 1, &find_base_storage).find(greater_than_one);
  EXPECT_INT_EQ(found.int(), 2);
  struct Iter find_void_base_storage;
  EXPECT_TRUE(range(0, 1, 1, &find_void_base_storage).find(NULL) is void);
  struct Iter any_void_base_storage;
  EXPECT_FALSE(range(0, 1, 1, &any_void_base_storage).any(NULL));
  struct Iter zip_left_storage, zip_right_storage, zip_storage;
  Iter zipped = range(1, 4, 1, &zip_left_storage).zip_with(
    range(10, 13, 1, &zip_right_storage),
    NULL, &zip_storage);
  Var first = zipped.next();
  (int first_left, int first_right) = first;
  EXPECT_INT_EQ(first_left, 1);
  EXPECT_INT_EQ(first_right, 10);
  struct Iter sum_left_storage, sum_right_storage, sum_zip_storage;
  Iter summed = range(1, 4, 1, &sum_left_storage).map2(
    range(10, 13, 1, &sum_right_storage),
    pair_sum, &sum_zip_storage);
  Var sum_first = summed.next();
  EXPECT_INT_EQ(sum_first.int(), 11);
  struct Iter null_left_storage, null_right_storage, null_zip_storage;
  EXPECT_TRUE(
    range(0, 1, 1, &null_left_storage).map2(
      range(0, 1, 1, &null_right_storage),
      NULL, &null_zip_storage) == NULL);
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
  $test.run(iter_map_lazy);
  $test.run(iter_func_callbacks);
  $test.run(iter_func_failures_and_empty_sources);
  $test.run(iter_func_lifetimes_and_allocations);
  $test.run(iter_immediate_fluent_chains);
  $test.run(iter_zip_and_unzip);
  $test.run(iter_unzip_bounds_consumed_buffers);
  $test.run(iter_rejects_invalid_ranges_and_unzip_rows);
  $test.run(iter_chain_unique);
  $test.run(iter_enumerate_repeat_head);
  $test.run(iter_accumulate_and_aggregates);
  $test.run(iter_aggregates_preserve_var_semantics);
  $test.run(iter_scan_and_array_collector);
  $test.run(iter_fold_predicates_and_zip_with);
  $test.run(iter_var_iter_into);
  $test.run(iter_descending_range);
  $test.run(iter_range_boundaries);
}
