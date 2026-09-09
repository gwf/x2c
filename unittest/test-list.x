/*  test-list.x -- unit tests for list operations */

#include "list-selectors.x"
#include "test-support.x"
#include <limits.h>

static int expect_list_ints(
  const char *label, List lst, const int *values, int count) {
  if (!lst && count == 0) return 1;
  if (!EXPECT_NOT_NULL(lst)) return 0;
  if (!EXPECT_INT_EQ(lst.len(), count)) return 0;
  for (int i = 0; i < count; i++)
    if (!EXPECT_INT_EQ(lst.getindex(i).integer(), values[i]))
      return 0;
  return 1;
}

static void list_canonical_identity(void) {
  Var leaf = 42L;
  List tail1 = cons(leaf, NULL), tail2 = cons(leaf, NULL);
  EXPECT_TRUE(tail1 === tail2);

  Var head = <node>;
  List outer1 = cons(head, tail1), outer2 = cons(head, tail2);
  EXPECT_TRUE(outer1 === outer2);
  EXPECT_TRUE(outer1 == outer2);
  EXPECT_INT_EQ(sizeof(struct List), 16);
}

static void list_nil_is_native_zero(void) {
  List empty = %();
  Var boxed = empty;

  EXPECT_NULL(empty);
  EXPECT_TRUE(empty == nil);
  EXPECT_TRUE(boxed is <list>);
  EXPECT_NULL(boxed.list());
}

static void list_builders_and_indexing(void) {
  Var one = 1L, two = 2L, three = 3L, four = 4L;
  List seq = %( $one $two $three $four );
  const int raw[] = { 1, 2, 3, 4 };
  if (!expect_list_ints("seq", seq, raw, 4)) return;
  EXPECT_INT_EQ(seq.last().integer(), 4);
  EXPECT_INT_EQ(seq.index(3L), 2);
  EXPECT_INT_EQ(seq.nth_cdr(2).car().integer(), 3);
  EXPECT_NULL(seq.nth_cdr(9));
  EXPECT_INT_EQ(seq.getindex(-1).integer(), 4);
  EXPECT_TRUE(seq.getindex(9) is void);
  EXPECT_INT_EQ(seq.get(1L).integer(), 2);
  EXPECT_INT_EQ(seq.get(seq.len() - 1).integer(), 4);
}

static void list_counted_values_are_boxed(void) {
  List values = List.list_n(3, 1, 2, %"three");
  EXPECT_INT_EQ(values.len(), 3);
  EXPECT_INT_EQ(values[0].int(), 1);
  EXPECT_INT_EQ(values[1].int(), 2);
  EXPECT_STR_EQ(values[2].string(), "three");
}


static void list_constructor_failures_transfer(void) {
  int caught = 0;
  try cons(void, NULL);
  catch %(void-op *): caught++;
  try List.list_n(2, 1, void);
  catch %(void-op *): caught++;
  try %(1 2 3).subseq(0, 2, 0);
  catch %(bad-arg *): caught++;
  try %(1 2 3).getslice(0, 2, 0);
  catch %(bad-arg *): caught++;
  try List.pool_release();
  catch %(bad-state *): caught++;
  EXPECT_INT_EQ(caught, 5);

  EXPECT_TRUE(List.list_n(2, 1, 2) == %(1 2));
}

static void list_append_concat_reverse(void) {
  Var one = 1L, two = 2L, three = 3L, four = 4L, five = 5L;
  List left = %( $one $two );
  List mid = %( $three );
  List right = %( $four $five );
  List appended = left.append(mid);
  const int append_vals[] = { 1, 2, 3 };
  expect_list_ints("left.append(mid)", appended, append_vals, 3);
  List combined = List.concat_n(3, left, mid, right);
  const int combined_vals[] = { 1, 2, 3, 4, 5 };
  if (!expect_list_ints("left.concat(mid, right)", combined, combined_vals, 5))
    return;
  List reversed = combined.reverse();
  const int reversed_vals[] = { 5, 4, 3, 2, 1 };
  expect_list_ints("combined.reverse()", reversed, reversed_vals, 5);
  EXPECT_NULL(((List)NULL).reverse());
  EXPECT_TRUE(List.concat_n(0) == NULL);
}

static void list_head_tail_and_slicing(void) {
  Var one = 1L, two = 2L, three = 3L, four = 4L, five = 5L, six = 6L;
  List seq = %( $one $two $three $four $five $six ), head = seq.head(3);
  const int head_vals[] = { 1, 2, 3 };
  expect_list_ints("seq.head(3)", head, head_vals, 3);
  List tail = seq.tail(2);
  const int tail_vals[] = { 5, 6 };
  expect_list_ints("seq.tail(2)", tail, tail_vals, 2);
  List subseq = seq.subseq(1, 5, 2);
  const int subseq_vals[] = { 2, 4 };
  List neg_subseq = seq.subseq(-4, -1, 2);
  const int neg_vals[] = { 3, 5 };
  List slice = seq.getslice(2, 5, 1);
  const int slice_vals[] = { 3, 4, 5 };
  List slice_neg = seq.getslice(5, 1, -2);
  const int slice_neg_vals[] = { 6, 4 };
  EXPECT_NULL(seq.head(0));
  EXPECT_TRUE(seq.head(8) == seq);
  EXPECT_TRUE(seq.tail(20) == seq);
  expect_list_ints("seq.subseq(1,5,2)", subseq, subseq_vals, 2);
  expect_list_ints("seq.subseq(-4,-1,2)", neg_subseq, neg_vals, 2);
  EXPECT_NULL(seq.subseq(4, 2, 1));
  expect_list_ints("seq.getslice(2,5,1)", slice, slice_vals, 3);
  expect_list_ints("seq.getslice(5,1,-2)", slice_neg, slice_neg_vals, 2);
  EXPECT_NULL(seq.getslice(1, 4, -1));
}

static void list_full_slice_preserves_active_owner(void) {
  volatile int seed = 91700;
  List active = cons(seed, cons(seed + 1, cons(seed + 2, NULL)));
  EXPECT_TRUE(active.getslice(0, active.len(), 1) === active);

  Pool detached = List.pool_retain_named("detached-full-slice");
  List borrowed = cons(seed + 3, cons(seed + 4, cons(seed + 5, NULL)));
  detached = List.pool_detach();
  List copied = borrowed.getslice(0, borrowed.len(), 1);
  EXPECT_TRUE(copied !== borrowed);
  EXPECT_INT_EQ(copied.compare(borrowed), 0);
  Pool.release(detached);
  EXPECT_INT_EQ(copied.car().integer(), seed + 3);
  EXPECT_INT_EQ(copied.len(), 3);
}

static void list_flatten_variants(void) {
  Var one = 1, two = 2, three = 3, four = 4, five = 5;
  List inner = %( $one $two );
  List single = %( $inner );
  List flattened = single.flatten();
  List empty = NULL;
  List tail_inner = %( $four );
  List nested_tail = %( $tail_inner $five );
  List deep = %( $inner $three $nested_tail );
  const int flat_all_vals[] = { 1, 2, 3, 4, 5 };
  List flattened_all = deep.flatten_all();
  EXPECT_TRUE(flattened == inner);
  EXPECT_NULL(empty.flatten());
  expect_list_ints("deep.flatten_all()", flattened_all, flat_all_vals, 5);
  EXPECT_NULL(empty.flatten_all());
}

static Var add_one(Var value) {
  int next = value.integer() + 1L;
  return next;
}

static Var sum_pair(Var acc, Var value) {
  int total = acc.integer() + value.integer();
  return total;
}

static int greater_than_two(Var value) {
  return value.integer() > 2;
}

static Var add_pairwise(Var left, Var right) {
  int total = left.integer() + right.integer();
  return total;
}

typedef Var (*ListUnaryFunction)(Var);
typedef Var (*ListBinaryFunction)(Var, Var);
typedef int (*ListPredicateFunction)(Var);

static Var _list_truthy_string(Var value) {
  return value.integer() > 2 ? %"yes" : NULL;
}

static Var _list_no_arguments(void) {
  return 1;
}

static Var _list_reference_argument(int &value) {
  return value;
}

static long _list_long_value(long value) {
  return value + 1;
}

static int _list_predicate_calls;

static int _list_counted_greater_than_two(Var value) {
  _list_predicate_calls++;
  return value.integer() > 2;
}

static void list_fold_and_predicates(void) {
  List numbers = %(1 2 3 4);
  Var sum = numbers.foldl(0, sum_pair);
  EXPECT_INT_EQ(sum.integer(), 10);
  EXPECT_TRUE(numbers.any(greater_than_two));
  EXPECT_FALSE(numbers.all(greater_than_two));
  EXPECT_FALSE(numbers.any(NULL));
  List empty = NULL;
  EXPECT_TRUE(empty.all(greater_than_two));
  EXPECT_TRUE(empty.all(NULL));
  EXPECT_TRUE(empty.any(greater_than_two) == 0);
  Var found = numbers.find(greater_than_two);
  EXPECT_INT_EQ(found.integer(), 3);
  EXPECT_TRUE(numbers.find(NULL) is void);
  EXPECT_INT_EQ(numbers.foldl(99, NULL).integer(), 99);
  EXPECT_INT_EQ(numbers.foldl(void, NULL).integer(), 1);
  EXPECT_INT_EQ(numbers.reduce(NULL).integer(), 1);
  EXPECT_TRUE(empty.foldl(void, sum_pair) is void);
  EXPECT_TRUE(empty.reduce(sum_pair) is void);
}

/* All five predicate APIs accept the same named int-returning function. */
static void list_predicate_shape_is_shared(void) {
  List numbers = %(1 2 3 4);
  EXPECT_TRUE(numbers.filter(greater_than_two) == %(3 4));
  EXPECT_INT_EQ(numbers.find(greater_than_two).integer(), 3);
  EXPECT_TRUE(numbers.any(greater_than_two));
  EXPECT_FALSE(numbers.all(greater_than_two));
  struct Iter source_storage, filter_storage;
  Iter kept = numbers.iter(&source_storage)
    .filter(greater_than_two, &filter_storage);
  EXPECT_TRUE(kept.list() == %(3 4));
}

static int reject_three(Var value) {
  if (value.integer() == 3) raise %(bad-arg (owner "reject_three"));
  return 1;
}

static void list_filter_transfers_predicate_error(void) {
  int caught = 0;
  try %(1 2 3 4).filter(reject_three);
  catch %(bad-arg *): caught++;
  EXPECT_INT_EQ(caught, 1);
  EXPECT_TRUE(%(1 2).filter(reject_three) == %(1 2));
}

static void list_map2_zip_and_sublis(void) {
  List left = %(1 2 3);
  List right = %(4 5 6);
  List sums = left.map2(right, add_pairwise);
  const int expected_sums[] = { 5, 7, 9 };
  if (!expect_list_ints("left.map2(right)", sums, expected_sums, 3)) return;
  EXPECT_NULL(left.map2(right, NULL));
  List zipped = left.zip_with(right, NULL);
  if (!EXPECT_INT_EQ(zipped.len(), 3)) return;
  EXPECT_INT_EQ(zipped.getindex(0).car().integer(), 1);
  EXPECT_INT_EQ(zipped.getindex(2).cadr().integer(), 6);
  List alist = %((alpha 1) (beta 2));
  List tree = %(alpha (gamma (beta delta)) beta);
  List rewritten = List.sublis(alist, tree);
  Var expected_one = 1, expected_two = 2;
  (Var first, List middle, Var last) = rewritten;
  (Symbol gamma, List inner) = middle;
  (Var two, Symbol delta) = inner;
  EXPECT_TRUE(first == expected_one);
  EXPECT_TRUE(gamma == <gamma>);
  EXPECT_TRUE(two == expected_two);
  EXPECT_TRUE(delta == <delta>);
  EXPECT_TRUE(last == expected_two);
  expect_list_ints("zip sums", sums, expected_sums, 3);
}

static void list_map_and_unpack(void) {
  Var zero = 0L, one = 1L, two = 2L;
  List seq = %( $zero $one $two ), mapped = seq.map(add_one);
  const int map_vals[] = { 1, 2, 3 };
  if (!expect_list_ints("seq.map(add_one)", mapped, map_vals, 3)) return;
  List empty = NULL;
  List outer = %( $seq $mapped );
  List first = NULL, second = NULL;
  Var v0 = void, v1 = void, v2 = void;
  EXPECT_NULL(empty.map(add_one));
  EXPECT_INT_EQ(outer.unpack_n(2, &first, &second), 2);
  EXPECT_TRUE(first == seq);
  EXPECT_TRUE(second == mapped);
  first = second = NULL;
  EXPECT_INT_EQ(outer.unpack_n(1, &first), 1);
  EXPECT_TRUE(first == seq);
  EXPECT_TRUE(second == NULL);
  if (!EXPECT_INT_EQ(seq.unpack_vars_n(3, &v0, &v1, &v2), 3)) return;
  EXPECT_INT_EQ(v0.integer(), 0);
  EXPECT_INT_EQ(v2.integer(), 2);
  v0 = v1 = v2 = void;
  EXPECT_INT_EQ(seq.unpack_vars_n(2, &v0, &v1), 2);
  Var (seq0, seq1) = seq;
  EXPECT_VAR_EQ(v0, seq0);
  EXPECT_VAR_EQ(v1, seq1);
  EXPECT_TRUE(v2 is void);

  Var null = (Var) { .u64 = 0 };
  List counted = List.list_n(4, 1, null, 2, 3);
  EXPECT_INT_EQ(counted.len(), 4);
  EXPECT_TRUE(counted.cadr().is_null());
}

static void list_func_callbacks(void) {
  List values = %(1 2 3 4), right = %(10 20 30);
  ListUnaryFunction unary_pointer = add_one;
  ListBinaryFunction binary_pointer = add_pairwise;
  ListPredicateFunction predicate_pointer = greater_than_two;
  int bias = 2, threshold = 2;
  Func captured_unary = %!(Var value) => value + bias;
  Func captured_binary =
    %!(Var left, Var right) => left + right + bias;
  Func captured_predicate =
    %!(Var value) => value.integer() > threshold;

  EXPECT_TRUE(values.map(unary_pointer) == %(2 3 4 5));
  EXPECT_TRUE(values.map(captured_unary) == %(3 4 5 6));
  EXPECT_INT_EQ(values.foldl(0, binary_pointer).integer(), 10);
  EXPECT_INT_EQ(values.foldl(0, captured_binary).integer(), 18);
  EXPECT_INT_EQ(values.reduce(binary_pointer).integer(), 10);
  EXPECT_INT_EQ(values.reduce(captured_binary).integer(), 16);
  EXPECT_INT_EQ(values.find(predicate_pointer).integer(), 3);
  EXPECT_INT_EQ(values.find(captured_predicate).integer(), 3);
  EXPECT_TRUE(values.any(predicate_pointer));
  EXPECT_TRUE(values.any(captured_predicate));
  EXPECT_FALSE(values.all(predicate_pointer));
  EXPECT_FALSE(values.all(captured_predicate));
  EXPECT_TRUE(values.filter(predicate_pointer) == %(3 4));
  EXPECT_TRUE(values.filter(captured_predicate) == %(3 4));
  EXPECT_TRUE(values.filter(_list_truthy_string) == %(3 4));
  EXPECT_TRUE(values.zip_with(right, add_pairwise) == %(11 22 33));
  EXPECT_TRUE(values.zip_with(right, binary_pointer) == %(11 22 33));
  EXPECT_TRUE(values.zip_with(right, captured_binary) == %(13 24 35));
  EXPECT_TRUE(values.map2(right, add_pairwise) == %(11 22 33));
  EXPECT_TRUE(values.map2(right, binary_pointer) == %(11 22 33));
  EXPECT_TRUE(values.map2(right, captured_binary) == %(13 24 35));

  _list_predicate_calls = 0;
  EXPECT_TRUE(values.any(_list_counted_greater_than_two));
  EXPECT_INT_EQ(_list_predicate_calls, 3);
  _list_predicate_calls = 0;
  EXPECT_INT_EQ(
    values.find(_list_counted_greater_than_two).integer(), 3);
  EXPECT_INT_EQ(_list_predicate_calls, 3);
  _list_predicate_calls = 0;
  EXPECT_FALSE(values.all(_list_counted_greater_than_two));
  EXPECT_INT_EQ(_list_predicate_calls, 1);

  ScopeStats before = Scope.stats();
  EXPECT_INT_EQ(values.foldl(0, sum_pair).integer(), 10);
  ScopeStats after = Scope.stats();
  EXPECT_INT_EQ(after.allocation_calls, before.allocation_calls);
}

static void list_func_rejects_invalid_callbacks_on_invocation(void) {
  List values = %(1 2), empty = NULL;
  Func wrong_arity = _list_no_arguments;
  Func reference = _list_reference_argument;
  Func numeric = _list_long_value;
  int arity_caught = 0, reference_caught = 0, conversion_caught = 0;

  try values.filter(wrong_arity);
  catch %(bad-arity *): arity_caught++;
  try values.map(reference);
  catch %(bad-types *): reference_caught++;
  try %("text").map(numeric);
  catch %(no-convert *): conversion_caught++;
  EXPECT_INT_EQ(arity_caught, 1);
  EXPECT_INT_EQ(reference_caught, 1);
  EXPECT_INT_EQ(conversion_caught, 1);

  EXPECT_NULL(empty.map(wrong_arity));
  EXPECT_INT_EQ(empty.foldl(7, wrong_arity).integer(), 7);
  EXPECT_TRUE(empty.reduce(wrong_arity) is void);
  EXPECT_TRUE(%(1).reduce(wrong_arity) == 1);
  EXPECT_TRUE(empty.find(wrong_arity) is void);
  EXPECT_FALSE(empty.any(wrong_arity));
  EXPECT_TRUE(empty.all(wrong_arity));
  EXPECT_NULL(empty.zip_with(values, wrong_arity));
  EXPECT_NULL(values.zip_with(empty, wrong_arity));
  EXPECT_NULL(empty.map2(values, wrong_arity));
  EXPECT_NULL(values.map2(empty, wrong_arity));
  EXPECT_NULL(empty.filter(wrong_arity));
}

static void list_literal_integers(void) {
  List literal = %(1 -2 3);
  const int expected[] = { 1, -2, 3 };
  expect_list_ints("%(1 -2 3)", literal, expected, 3);
  List neg_only = %(-5);
  EXPECT_INT_EQ(neg_only.car().integer(), -5);
}

static void list_assoc_hash_equal(void) {
  Var one = 1L, two = 2L, nine = 9L;
  List pair1 = %(alpha $one);
  List pair2 = %(beta $two);
  List assoc = %( $pair1 $pair2 );
  Var fetched = assoc.assoc(<beta>);
  List empty = NULL;
  List assoc_copy = %( $pair1 $pair2 );
  List different = %( $pair1 ${%(beta $nine)} );
  EXPECT_INT_EQ(fetched.integer(), 2);
  EXPECT_TRUE(assoc.assoc(<missing>) is void);
  EXPECT_INT_EQ(assoc.get(<alpha>).integer(), 1);
  EXPECT_TRUE(assoc.get(<missing>) is void);
  EXPECT_INT_EQ(empty.hash(), 0);
  EXPECT_TRUE(assoc.hash() != 0);
  EXPECT_TRUE(assoc == assoc_copy);
  EXPECT_TRUE(assoc != different);

  Map keyed = %{};
  keyed[assoc] = 77;
  EXPECT_INT_EQ(keyed[assoc_copy].integer(), 77);
  EXPECT_INT_EQ(assoc.hash(), assoc_copy.hash());
}

static void list_array_conversion_boundaries(void) {
  Array values = %[1, 2, 3];
  List list = values.list_free();
  Array roundtrip = list.array();

  EXPECT_TRUE(list == %(1 2 3));
  EXPECT_INT_EQ(roundtrip.len(), 3);
  EXPECT_INT_EQ(roundtrip[0].integer(), 1);
  EXPECT_INT_EQ(roundtrip[2].integer(), 3);
  EXPECT_NULL(((List) NULL).head(3));
  EXPECT_NULL(((List) NULL).tail(3));
  EXPECT_TRUE(list.head(3) == list);
  EXPECT_TRUE(list.head(30) == list);
  EXPECT_TRUE(list.tail(3) == list);
  EXPECT_TRUE(list.tail(30) == list);
  EXPECT_NULL(list.tail(0));
  EXPECT_TRUE(list.getindex(-4) is void);
  EXPECT_INT_EQ(list.getindex(-3).integer(), 1);
  EXPECT_INT_EQ(list.getindex(-1).integer(), 3);

  roundtrip.free();
}

static void list_array_list_free_consumes_the_receiver(void) {
  ScopeStats before = Scope.stats();
  Array values = %[1, 2, 3];
  EXPECT_TRUE(values.list_free() == %(1 2 3));
  // An empty Array converts to nil and is released just the same, so the live
  // allocation count returns to where it started either way. Cons cells live
  // in the List pool, not in a Scope.
  Array empty = %[];
  EXPECT_NULL(empty.list_free());
  EXPECT_INT_EQ(Scope.stats().live_allocations, before.live_allocations);
}

static int keep_even(Var value) {
  return !(value.integer() & 1);
}

static void list_large_operations_are_iterative(void) {
  int count = 50000;
  Array values = %[];
  for (int i = 0; i < count; i++) values.push(i);
  List source = values.list_free();

  List appended = source.append(%(50000));
  List mapped = source.map(add_one);
  List filtered = source.filter(keep_even);
  List sliced = source.getslice(7, count - 3, 7);
  struct Iter storage;
  List collected = source.iter(&storage).list();

  EXPECT_INT_EQ(appended.len(), count + 1);
  EXPECT_INT_EQ(appended.last().integer(), count);
  EXPECT_INT_EQ(mapped.len(), count);
  EXPECT_INT_EQ(mapped.last().integer(), count);
  EXPECT_INT_EQ(filtered.len(), count / 2);
  EXPECT_INT_EQ(filtered.last().integer(), count - 2);
  EXPECT_INT_EQ(sliced.car().integer(), 7);
  EXPECT_INT_EQ(sliced.last().integer(), 49994);
  EXPECT_TRUE(collected == source);
}

static void list_sort_orders_values(void) {
  List empty = NULL;
  EXPECT_NULL(empty.sort());

  List single = %(42);
  EXPECT_TRUE(single.sort() == single);

  List nums = %(3 1 2), sorted_nums = nums.sort();
  const int sorted_vals[] = { 1, 2, 3 };
  expect_list_ints("nums.sort()", sorted_nums, sorted_vals, 3);
  EXPECT_TRUE(nums == %(3 1 2));

  List syms = %(b a c);
  EXPECT_TRUE(syms.sort() == %(a b c));

  List lol = %((2) (1 2) (1 1));
  EXPECT_TRUE(lol.sort() == %((1 1) (1 2) (2)));

  List mixed = %(b 2 a 1);
  EXPECT_TRUE(mixed.sort() == %(1 2 a b));

}

static void list_sort_callbacks_preserve_source(void) {
  List values = %((2 first) (1 low) (2 second));
  List ascending = values.sort_by(%!(List row) => row.car());
  EXPECT_TRUE(ascending == %((1 low) (2 first) (2 second)));
  List descending = values.sort_with(
    %!(List left, List right) => right.car().compare(left.car()));
  EXPECT_TRUE(descending == %((2 first) (2 second) (1 low)));
  EXPECT_TRUE(values == %((2 first) (1 low) (2 second)));
  List empty = NULL, single = %(1);
  EXPECT_NULL(empty.sort_by(NULL));
  EXPECT_TRUE(single.sort_with(NULL) == single);
}

static void list_unique_removes_duplicates(void) {
  List empty = NULL;
  EXPECT_NULL(empty.unique());

  List single = %(42);
  EXPECT_TRUE(single.unique() == single);

  List nums = %(3 1 2 1 3 3 2), unique_nums = nums.unique();
  const int expected_nums[] = { 3, 1, 2 };
  if (!expect_list_ints("nums.unique()", unique_nums, expected_nums, 3))
    return;
  EXPECT_TRUE(nums == %(3 1 2 1 3 3 2));
  EXPECT_TRUE(unique_nums.unique() == unique_nums);

  List mixed = %(a 1 a 1 b 1);
  EXPECT_TRUE(mixed.unique() == %(a 1 b));

  List lol = %((1 2) (1 2) (2) (1 2) (2));
  EXPECT_TRUE(lol.unique() == %((1 2) (2)));

}

static void list_intern_preserves_map_identity(void) {
  Map m1 = %{}, m2 = %{};

  List l1 = cons(m1, NULL), l2 = cons(m2, NULL);

  EXPECT_TRUE(m1 !== m2);
  EXPECT_TRUE(m1.equal(m2));
  EXPECT_TRUE(m1.var() == m2.var());
  EXPECT_TRUE(m1.var() !== m2.var());
  EXPECT_INT_EQ(m1.var().compare(m2.var()), 0);

  // List interning preserves distinct identities for mutable elements,
  // even when their contents compare equal.
  EXPECT_TRUE(l1 !== l2);
  EXPECT_TRUE(car(l1) === m1);
  EXPECT_TRUE(car(l2) === m2);

  Map keyed = %{};
  keyed[l1] = 88;
  m1[<changed>] = 1;
  EXPECT_INT_EQ(keyed[l1].integer(), 88);
  EXPECT_TRUE(cons(m1, NULL) == l1);

}

static void list_pool_lifetime_boundary(void) {
  volatile int seed = 9300;
  Pool pool = List.pool_retain();
  if (!EXPECT_NOT_NULL(pool)) return;

  List garbage = cons(seed + 1, cons(seed + 2, NULL));
  List survivor = List.promote(cons(seed + 3, cons(seed + 4, NULL)));
  ScopeStats during = Scope.stats();
  EXPECT_INT_EQ(garbage.len(), 2);

  List.pool_release();
  ScopeStats after = Scope.stats();
  EXPECT_TRUE(after.live_allocations < during.live_allocations);
  EXPECT_INT_EQ(survivor.car().integer(), seed + 3);
  EXPECT_TRUE(survivor == cons(seed + 3, cons(seed + 4, NULL)));
}

static void list_optional_compound_selectors(void) {
  List value = %(((a b) c) ((d e) f) g h i);
  EXPECT_TRUE(value.caaar() == <a>);
  EXPECT_TRUE(value.cdaar() == %(b));
  EXPECT_TRUE(value.cadddr() == <h>);
  EXPECT_TRUE(value.cddddr() == %(i));

  Var boxed = value;
  EXPECT_TRUE(boxed.caaadr() == <d>);
  EXPECT_TRUE(boxed.cdaadr() == %(e));
  EXPECT_TRUE(boxed.cadddr() == <h>);
  EXPECT_TRUE(boxed.cddddr() == %(i));
}

$(import "test-macros.xmacro")

void list_suite(void) {
  $test.run(list_canonical_identity);
  $test.run(list_nil_is_native_zero);
  $test.run(list_builders_and_indexing);
  $test.run(list_counted_values_are_boxed);
  $test.run(list_constructor_failures_transfer);
  $test.run(list_append_concat_reverse);
  $test.run(list_head_tail_and_slicing);
  $test.run(list_full_slice_preserves_active_owner);
  $test.run(list_flatten_variants);
  $test.run(list_fold_and_predicates);
  $test.run(list_predicate_shape_is_shared);
  $test.run(list_filter_transfers_predicate_error);
  $test.run(list_map2_zip_and_sublis);
  $test.run(list_map_and_unpack);
  $test.run(list_func_callbacks);
  $test.run(list_func_rejects_invalid_callbacks_on_invocation);
  $test.run(list_literal_integers);
  $test.run(list_assoc_hash_equal);
  $test.run(list_array_conversion_boundaries);
  $test.run(list_array_list_free_consumes_the_receiver);
  $test.run(list_sort_orders_values);
  $test.run(list_sort_callbacks_preserve_source);
  $test.run(list_unique_removes_duplicates);
  $test.run(list_intern_preserves_map_identity);
  $test.run(list_pool_lifetime_boundary);
  $test.run(list_optional_compound_selectors);
  $test.run(list_large_operations_are_iterative);
}
