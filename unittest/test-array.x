/*  test-array.x -- unit tests for array helpers */

#include "test-support.x"
$(import "test-macros.xmacro")
#include <limits.h>
#include <stdint.h>

static int _array_scope_allocation_count(Scope scope) {
  int count = 0;
  for (ScopeAlloc node = scope ? scope.first : NULL; node; node = node.next)
    count++;
  return count;
}


static Var _raise_during_array_map(Var value) {
  (void) value;
  int detail = 73;
  raise %(invariant (value $detail));
}

static Var add_array_values(Var acc, Var value) {
  return acc + value;
}

typedef Var (*ArrayUnaryFunction)(Var);
typedef Var (*ArrayBinaryFunction)(Var, Var);

static Var _array_add_one(Var value) {
  return value + 1;
}

static Var _array_add_pair(Var left, Var right) {
  return left + right;
}

static Var _array_no_arguments(void) {
  return 1;
}

static Var _array_reference_argument(int &value) {
  return value;
}

static long _array_long_value(long value) {
  return value + 1;
}

static Var _raise_during_array_map2(Var left, Var right) {
  (void) left;
  (void) right;
  raise %(invariant (value 74));
}

static void array_empty_literal_identity(void) {
  $test.scoped();
  Array first = %[], second = %[];

  EXPECT_NOT_NULL(first);
  EXPECT_NOT_NULL(second);
  EXPECT_FALSE(first === second);
  EXPECT_INT_EQ(first.len(), 0);
  EXPECT_INT_EQ(second.len(), 0);
  first.push(11);
  EXPECT_INT_EQ(first.len(), 1);
  EXPECT_INT_EQ(first[0].int(), 11);
  EXPECT_INT_EQ(second.len(), 0);
}

static void array_push_pop(void) {
  $test.scoped();
  Array arr = %[];
  arr.push(1);
  arr.push(2);
  EXPECT_INT_EQ(arr.len(), 2);
  EXPECT_INT_EQ(arr[0].int(), 1);
  EXPECT_INT_EQ(arr.take_last().int(), 2);
  EXPECT_INT_EQ(arr.len(), 1);
}

static void array_void_writes_transfer_before_mutation(void) {
  $test.scoped();
  Array array = %[1];
  int caught = 0;

  try array.setindex(0, void);
  catch %(void-op *): caught++;
  try array.push(void);
  catch %(void-op *): caught++;
  try array.unshift(void);
  catch %(void-op *): caught++;
  try array.insert(0, void);
  catch %(void-op *): caught++;
  EXPECT_INT_EQ(caught, 4);
  EXPECT_INT_EQ(array.len(), 1);
  EXPECT_INT_EQ(array[0].int(), 1);
}


static void array_map_transfer_releases_temporary_scope(void) {
  $test.scoped();
  Array values = %[1];
  Scope active = *Scope.top();
  int allocations_before = _array_scope_allocation_count(active);
  int transferred = 0;
  try {
    values.map(_raise_during_array_map);
  }
  catch %(invariant (value ?value)): {
    transferred = value.int() == 73;
  }
  EXPECT_TRUE(transferred);
  EXPECT_INT_EQ(_array_scope_allocation_count(active), allocations_before);
}

static void array_map2_transfer_releases_temporary_scope(void) {
  $test.scoped();
  Array values = %[1];
  Scope active = *Scope.top();
  int allocations_before = _array_scope_allocation_count(active);
  int transferred = 0;
  try values.map2(values, _raise_during_array_map2);
  catch %(invariant (value ?value)): transferred = value.int() == 74;
  EXPECT_TRUE(transferred);
  EXPECT_INT_EQ(_array_scope_allocation_count(active), allocations_before);
}


static void array_reports_slice_domain_failures(void) {
  $test.scoped();
  Array array = %[1];
  int caught = 0;

  try array.getslice(0, 1, 0);
  catch %(bad-arg *): caught = 1;
  EXPECT_TRUE(caught);
}

static void array_counted_update_preserves_values(void) {
  $test.scoped();
  Var one = 1, null = (Var) { .u64 = 0 }, two = 2;
  Array arr = Array.update_n(%[], 3, one, null, two);
  EXPECT_INT_EQ(arr.len(), 3);
  EXPECT_VAR_EQ(arr[0], one);
  EXPECT_TRUE(arr[1].is_null());
  EXPECT_VAR_EQ(arr[2], two);
}

static void array_insert_and_remove(void) {
  $test.scoped();
  Var one = 1, two = 2, three = 3;
  Array arr = Array.update_n(%[], 2, one, three);
  arr.insert(1, two);
  EXPECT_INT_EQ(arr.len(), 3);
  EXPECT_VAR_EQ(arr[1], two);
  Var removed = arr.remove(1);
  EXPECT_VAR_EQ(removed, two);
  EXPECT_INT_EQ(arr.len(), 2);
}

static void array_mixed_mutation_integrity(void) {
  $test.scoped();
  Var number = 7;
  String text = %"mixed";
  Var string = text;
  List pair = %(pair 9);
  Var list = pair;
  Array arr = Array.update_n(%[], 3, number, string, list);

  EXPECT_VAR_EQ(arr.shift(), number);
  EXPECT_VAR_EQ(arr[0], string);
  EXPECT_VAR_EQ(arr[1], list);
  EXPECT_VAR_EQ(arr.insert(1, number), number);
  EXPECT_VAR_EQ(arr[0], string);
  EXPECT_VAR_EQ(arr[1], number);
  EXPECT_VAR_EQ(arr[2], list);
  EXPECT_VAR_EQ(arr.remove(1), number);
  EXPECT_VAR_EQ(arr[0], string);
  EXPECT_VAR_EQ(arr[1], list);

  int len = arr.len();
  EXPECT_TRUE(arr.insert(10, number) is void);
  EXPECT_INT_EQ(arr.len(), len);
  EXPECT_VAR_EQ(arr[0], string);
  EXPECT_VAR_EQ(arr[1], list);

}

static void array_setindex_bounds(void) {
  $test.scoped();
  Array arr = %[];
  String hello = %"hello";
  Var vhello = hello;
  arr.push(vhello);
  String world = %"world";
  Var vworld = world;
  EXPECT_VAR_EQ(arr.setindex(0, vworld), vworld);
  EXPECT_VAR_EQ(arr.getindex(-1), vworld);
  Var one = 1;
  EXPECT_TRUE(arr.setindex(5, one) is void);
}

static void array_getslice_unit_step(void) {
  $test.scoped();
  Var zero = 0, one = 1, two = 2, three = 3, four = 4;
  Array arr = Array.update_n(%[], 5, zero, one, two, three, four);
  Array slice = arr.getslice(1, 3, 1);
  EXPECT_INT_EQ(slice.len(), 2);
  EXPECT_VAR_EQ(slice[0], one);
  EXPECT_VAR_EQ(slice[1], two);
}

static void array_getslice_variable_steps(void) {
  $test.scoped();
  Var zero = 0, one = 1, two = 2, three = 3, four = 4, five = 5;
  Array arr = Array.update_n(%[], 6, zero, one, two, three, four, five);
  Array skip = arr.getslice(0, arr.len(), 2);
  Array reverse = arr.getslice(5, 0, -2);
  EXPECT_INT_EQ(skip.len(), 3);
  EXPECT_VAR_EQ(skip[0], zero);
  EXPECT_VAR_EQ(skip[1], two);
  EXPECT_VAR_EQ(skip[2], four);
  EXPECT_INT_EQ(reverse.len(), 3);
  EXPECT_VAR_EQ(reverse[0], five);
  EXPECT_VAR_EQ(reverse[1], three);
  EXPECT_VAR_EQ(reverse[2], one);
}

static void array_setslice_and_remslice(void) {
  $test.scoped();
  Var zero = 0, one = 1, two = 2, three = 3, four = 4, nine = 9, eight = 8;
  Array arr = Array.update_n(%[], 5, zero, one, two, three, four);
  Array replacement = Array.update_n(%[], 2, nine, eight);
  arr.setslice(1, 3, replacement);
  Array removed = arr.remslice(1, 3);
  EXPECT_INT_EQ(arr.len(), 3);
  EXPECT_VAR_EQ(arr[0], zero);
  EXPECT_VAR_EQ(arr[1], three);
  EXPECT_VAR_EQ(arr[2], four);
  EXPECT_INT_EQ(removed.len(), 2);
  EXPECT_VAR_EQ(removed[0], nine);
  EXPECT_VAR_EQ(removed[1], eight);
}

static void array_splice_and_concat(void) {
  $test.scoped();
  Var zero = 0, one = 1, two = 2, three = 3, five = 5, seven = 7, eight = 8;
  Array arr = Array.update_n(%[], 4, zero, one, two, three);
  Array insert = Array.update_n(%[], 2, seven, eight);
  Array removed = arr.splice(1, 2, insert);
  Array extra = Array.update_n(%[], 1, five);
  Array combined = Array.concat(arr, extra);
  EXPECT_INT_EQ(arr.len(), 4);
  EXPECT_VAR_EQ(arr[0], zero);
  EXPECT_VAR_EQ(arr[1], seven);
  EXPECT_VAR_EQ(arr[2], eight);
  EXPECT_VAR_EQ(arr[3], three);
  EXPECT_INT_EQ(removed.len(), 2);
  EXPECT_VAR_EQ(removed[0], one);
  EXPECT_VAR_EQ(removed[1], two);
  EXPECT_INT_EQ(combined.len(), 5);
  EXPECT_VAR_EQ(combined[4], five);
}

static void array_find_contains_count(void) {
  $test.scoped();
  Var five = 5, six = 6, seven = 7, forty_two = 42;
  Array arr = Array.update_n(%[], 4, five, six, five, seven);
  EXPECT_INT_EQ(Array.find(arr, five), 0);
  EXPECT_INT_EQ(Array.indexof(arr, seven), 3);
  EXPECT_INT_EQ(Array.count(arr, five), 2);
  EXPECT_TRUE(Array.contains(arr, six));
  EXPECT_FALSE(Array.contains(arr, forty_two));
}

static void array_sort_reverse_join(void) {
  $test.scoped();
  Var one = 1, two = 2, three = 3, neg = -4;
  Array numbers = Array.update_n(%[], 4, three, one, two, neg);
  numbers.sort();
  EXPECT_VAR_EQ(numbers[0], neg);
  EXPECT_VAR_EQ(numbers[3], three);
  numbers.reverse();
  EXPECT_VAR_EQ(numbers[0], three);
  EXPECT_VAR_EQ(numbers[1], two);
  EXPECT_VAR_EQ(numbers[2], one);
  EXPECT_VAR_EQ(numbers[3], neg);
  Var word_a = Var.new(<string>, %"a");
  Var word_b = Var.new(<string>, %"b");
  Var word_c = Var.new(<string>, %"c");
  Array words = Array.update_n(%[], 3, word_a, word_b, word_c);
  String joined = Array.join(words, %"-");
  EXPECT_TRUE(joined == %"a-b-c");
}

static void array_heap_push_pop_min_basic(void) {
  $test.scoped();
  Array heap = %[];
  Var zero = 0, one = 1, two = 2, three = 3, four = 4;
  heap.heap_push(four);
  heap.heap_push(one);
  heap.heap_push(three);
  heap.heap_push(two);
  heap.heap_push(zero);
  EXPECT_INT_EQ(heap.len(), 5);
  EXPECT_VAR_EQ(heap.heap_pop(), zero);
  EXPECT_VAR_EQ(heap.heap_pop(), one);
  EXPECT_VAR_EQ(heap.heap_pop(), two);
  EXPECT_VAR_EQ(heap.heap_pop(), three);
  EXPECT_VAR_EQ(heap.heap_pop(), four);
  EXPECT_TRUE(heap.heap_pop() is void);
}


static void array_heapify_basic(void) {
  $test.scoped();
  Var one = 1, two = 2, three = 3, four = 4, five = 5, six = 6;
  Array heap = Array.update_n(%[], 6, six, one, four, three, five, two);
  heap.heapify();
  EXPECT_INT_EQ(heap.len(), 6);
  EXPECT_VAR_EQ(heap.heap_pop(), one);
  EXPECT_VAR_EQ(heap.heap_pop(), two);
  EXPECT_VAR_EQ(heap.heap_pop(), three);
  EXPECT_VAR_EQ(heap.heap_pop(), four);
  EXPECT_VAR_EQ(heap.heap_pop(), five);
  EXPECT_VAR_EQ(heap.heap_pop(), six);
  EXPECT_TRUE(heap.heap_pop() is void);
}

static void array_heap_ops_lists(void) {
  $test.scoped();
  List l0 = %(0), l1 = %(1 0), l2 = %(1 1), l3 = %(2);
  Var v_l0 = l0, v_l1 = l1, v_l2 = l2, v_l3 = l3;
  Array heap = %[];
  heap.heap_push(l2);
  heap.heap_push(l3);
  heap.heap_push(l0);
  heap.heap_push(l1);
  EXPECT_VAR_EQ(heap.heap_pop(), v_l0);
  EXPECT_VAR_EQ(heap.heap_pop(), v_l1);
  EXPECT_VAR_EQ(heap.heap_pop(), v_l2);
  EXPECT_VAR_EQ(heap.heap_pop(), v_l3);
  EXPECT_TRUE(heap.heap_pop() is void);
}

static void array_sort_nested_values(void) {
  $test.scoped();

  List c = %(0), a = %(1 2), b = %(1 3);
  Array lists = %[];
  lists.push(b);
  lists.push(a);
  lists.push(c);
  lists.sort();

  Var vc = c, va = a, vb = b;
  EXPECT_VAR_EQ(lists[0], vc);
  EXPECT_VAR_EQ(lists[1], va);
  EXPECT_VAR_EQ(lists[2], vb);

  Array ac = %[];
  ac.push(0);
  Array aa = %[];
  aa.push(1);
  Array ab = %[];
  ab.push(1);
  ab.push(0);
  Array arrays = %[];
  arrays.push(ab);
  arrays.push(aa);
  arrays.push(ac);
  arrays.sort();

  Var v_ac = ac, v_aa = aa, v_ab = ab;
  EXPECT_VAR_EQ(arrays[0], v_ac);
  EXPECT_VAR_EQ(arrays[1], v_aa);
  EXPECT_VAR_EQ(arrays[2], v_ab);

  lists.free();
  ac.free();
  aa.free();
  ab.free();
  arrays.free();

}

static void array_equal_hash_and_compare_nested(void) {
  $test.scoped();

  Array inner_a = %[1, 2], inner_b = %[1, 2];

  Array a = %[];
  a.push(inner_a);
  Array b = %[];
  b.push(inner_b);

  Var va = a, vb = b;
  EXPECT_TRUE(va == vb);
  EXPECT_TRUE(va !== vb);
  EXPECT_INT_EQ(va.compare(vb), 0);
  EXPECT_TRUE(a !== b);

  Map map = %{};
  Var one = 1;
  map[va] = one;
  EXPECT_VAR_EQ(map[va], one);
  EXPECT_TRUE(map[vb] is void);

}

static void array_reduce_uses_first_value_once(void) {
  $test.scoped();
  Array values = %[2, 3, 4];
  EXPECT_INT_EQ(values.reduce(add_array_values).int(), 9);
  EXPECT_TRUE(Array.reduce(%[], add_array_values) is void);
}

static void array_func_callbacks(void) {
  $test.scoped();
  Array values = %[1, 2, 3], right = %[10, 20];
  ArrayUnaryFunction unary_pointer = _array_add_one;
  ArrayBinaryFunction binary_pointer = _array_add_pair;
  int bias = 1;
  Func captured_unary = %!(Var value) => value + bias;
  Func captured_binary =
    %!(Var left, Var right) => left + right + bias;

  EXPECT_TRUE(values.map(_array_add_one).list() == %(2 3 4));
  EXPECT_TRUE(values.map(unary_pointer).list() == %(2 3 4));
  EXPECT_TRUE(values.map(captured_unary).list() == %(2 3 4));
  EXPECT_TRUE(values.map2(right, _array_add_pair).list() == %(11 22));
  EXPECT_TRUE(values.map2(right, binary_pointer).list() == %(11 22));
  EXPECT_TRUE(values.map2(right, captured_binary).list() == %(12 23));
  EXPECT_INT_EQ(values.reduce(add_array_values).integer(), 6);
  EXPECT_INT_EQ(values.reduce(binary_pointer).integer(), 6);
  EXPECT_INT_EQ(values.reduce(captured_binary).integer(), 8);

  ScopeStats before = Scope.stats();
  EXPECT_INT_EQ(values.reduce(add_array_values).integer(), 6);
  ScopeStats after = Scope.stats();
  EXPECT_INT_EQ(after.allocation_calls, before.allocation_calls);
}

static void array_func_rejects_invalid_callbacks_on_invocation(void) {
  $test.scoped();
  Array values = %[1, 2], empty = %[];
  Func wrong_arity = _array_no_arguments;
  Func reference = _array_reference_argument;
  Func numeric = _array_long_value;
  int arity_caught = 0, reference_caught = 0, conversion_caught = 0;

  try values.map(wrong_arity);
  catch %(bad-arity *): arity_caught++;
  try values.map(reference);
  catch %(bad-types *): reference_caught++;
  try %[ "text" ].map(numeric);
  catch %(no-convert *): conversion_caught++;
  EXPECT_INT_EQ(arity_caught, 1);
  EXPECT_INT_EQ(reference_caught, 1);
  EXPECT_INT_EQ(conversion_caught, 1);

  EXPECT_INT_EQ(empty.map(wrong_arity).len(), 0);
  EXPECT_INT_EQ(empty.map2(values, wrong_arity).len(), 0);
  EXPECT_INT_EQ(values.map2(empty, wrong_arity).len(), 0);
  EXPECT_TRUE(empty.reduce(wrong_arity) is void);
  EXPECT_TRUE(%[1].reduce(wrong_arity) == 1);
}


static void array_sort_callbacks_keep_ties_and_identity(void) {
  $test.scoped();
  Array values = %[];
  values.push(%(2 first));
  values.push(%(1 low));
  values.push(%(2 second));
  int calls = 0;
  Array other = %[3, 1, 2];
  Func key = %!(List row) using &calls, &other => {
    calls++;
    other.sort_with(%!(int left, int right) => right - left);
    return row.car();
  };
  EXPECT_TRUE(values.sort_by(key) == values);
  EXPECT_INT_EQ(calls, 3);
  EXPECT_TRUE(values.list() == %((1 low) (2 first) (2 second)));
  EXPECT_TRUE(other.list() == %(3 2 1));

  Func compare = %!(List left, List right) using &other => {
    other.sort_by(%!(int value) => value);
    return right.car().compare(left.car());
  };
  EXPECT_TRUE(values.sort_with(compare) == values);
  EXPECT_TRUE(values.list() == %((2 first) (2 second) (1 low)));
  EXPECT_TRUE(other.list() == %(1 2 3));
  Array empty = %[], single = %[1];
  EXPECT_TRUE(empty.sort_by(NULL) == empty);
  EXPECT_TRUE(single.sort_with(NULL) == single);
}

static void array_sort_by_releases_scratch(void) {
  $test.scoped();
  Pool pool = List.pool_retain();
  defer List.pool_release();
  Array values = %[3, 2, 1];
  Func key = %!(int value) => value;
  FuncArg arguments[1] = { FuncArg.value(42) };
  key.apply(1, arguments);
  size_t interned = pool.stats().interned;
  Scope active = *Scope.top();
  int allocations = _array_scope_allocation_count(active);
  for (int batch = 0; batch < 3; batch++) {
    for (int index = 0; index < 3; index++)
      values[index] = batch * 10 + 3 - index;
    values.sort_by(key);
    EXPECT_INT_EQ(pool.stats().interned, interned);
    EXPECT_INT_EQ(_array_scope_allocation_count(active), allocations);
    for (int index = 0; index < 3; index++)
      EXPECT_INT_EQ(values[index].integer(), batch * 10 + index + 1);
  }
}

static void array_sort_callbacks_cover_merge_tails(void) {
  $test.scoped();
  Array values = %[];
  for (int index = 0; index < 17; index++)
    values.push(%(${(index * 7) % 5} $index));
  Array by_key = values.copy();
  by_key.sort_by(%!(List row) => row.car());
  values.sort_with(%!(List left, List right) =>
    left.car().compare(right.car()));
  EXPECT_TRUE(values.list() == by_key.list());
  for (int index = 1; index < values.len(); index++) {
    List left = values[index - 1], right = values[index];
    EXPECT_TRUE(left.car() <= right.car());
    if (left.car() == right.car()) EXPECT_TRUE(left.cadr() < right.cadr());
  }
  int calls = 0;
  Array single = %[3];
  single.sort_by(%!(int value) using &calls => { calls++; return value; });
  EXPECT_INT_EQ(calls, 1);
  EXPECT_TRUE(single.list() == %(3));
}

static void array_sort_callback_errors_preserve_elements(void) {
  $test.scoped();
  Array values = %[4, 3, 2, 1];
  int calls = 0, caught = 0;
  Func compare = %!(Var left, Var right) using &calls => {
    if (++calls == 2) raise %(invariant (sort callback));
    return left.compare(right);
  };
  Scope active = *Scope.top();
  int allocations = _array_scope_allocation_count(active);
  try values.sort_with(compare);
  catch %(invariant *): caught++;
  EXPECT_INT_EQ(caught, 1);
  EXPECT_INT_EQ(_array_scope_allocation_count(active), allocations);
  EXPECT_INT_EQ(calls, 2);
  EXPECT_TRUE(values.list() == %(4 3 2 1));

  calls = 0;
  Func key = %!(Var value) using &calls => {
    if (++calls == 3) raise %(invariant (sort key));
    return value;
  };
  allocations = _array_scope_allocation_count(active);
  try values.sort_by(key);
  catch %(invariant *): caught++;
  EXPECT_INT_EQ(caught, 2);
  EXPECT_INT_EQ(_array_scope_allocation_count(active), allocations);
  EXPECT_INT_EQ(calls, 3);
  EXPECT_TRUE(values.list() == %(4 3 2 1));

  Func invalid = %!(Var left, Var right) => "not an integer";
  try values.sort_with(invalid);
  catch %(no-convert *): caught++;
  EXPECT_INT_EQ(caught, 3);
  EXPECT_TRUE(values.list() == %(4 3 2 1));
}

void array_suite(void) {
  $test.run(array_empty_literal_identity);
  $test.run(array_push_pop);
  $test.run(array_void_writes_transfer_before_mutation);
  $test.run(array_map_transfer_releases_temporary_scope);
  $test.run(array_map2_transfer_releases_temporary_scope);
  $test.run(array_reports_slice_domain_failures);
  $test.run(array_counted_update_preserves_values);
  $test.run(array_insert_and_remove);
  $test.run(array_mixed_mutation_integrity);
  $test.run(array_setindex_bounds);
  $test.run(array_getslice_unit_step);
  $test.run(array_getslice_variable_steps);
  $test.run(array_setslice_and_remslice);
  $test.run(array_splice_and_concat);
  $test.run(array_find_contains_count);
  $test.run(array_sort_reverse_join);
  $test.run(array_sort_callbacks_keep_ties_and_identity);
  $test.run(array_sort_callback_errors_preserve_elements);
  $test.run(array_sort_by_releases_scratch);
  $test.run(array_sort_callbacks_cover_merge_tails);
  $test.run(array_heap_push_pop_min_basic);
  $test.run(array_heapify_basic);
  $test.run(array_heap_ops_lists);
  $test.run(array_sort_nested_values);
  $test.run(array_equal_hash_and_compare_nested);
  $test.run(array_reduce_uses_first_value_once);
  $test.run(array_func_callbacks);
  $test.run(array_func_rejects_invalid_callbacks_on_invocation);
}
