/*  test-lambda.x -- unit tests for lambdas */

#include "test-support.x"
$(import "test-macros.xmacro")

typedef struct LambdaCaptureProbe {
  int value, order;
} *LambdaCaptureProbe;

static int _lambda_capture_events, _lambda_live_global = 5;
static int _lambda_block_cleanup;

static inline Var LambdaCaptureProbe.var(LambdaCaptureProbe probe) {
  _lambda_capture_events = _lambda_capture_events * 10 + probe.order;
  return Var.new(<p48>, probe);
}

static inline LambdaCaptureProbe Var.lambdacaptureprobe(Var value) {
  return value.pointer();
}

protocol Var(LambdaCaptureProbe) as void *;

static Func _lambda_add_to(int bias) {
  return %!(int value) => value + bias + _lambda_live_global;
}

static Func _lambda_nested(int first) {
  return %!(int second) => %!(int value) => value + first + second;
}

static Func _lambda_noncapturing_factory(void) {
  return %!(int value) => value + 1;
}

static Func _lambda_func_passthrough(Func function) {
  return function;
}

static Func _lambda_reference_factory(int &outer) {
  return %!(int &value) using &outer => ++value + ++outer;
}

static Func _lambda_mutable_parameter(int value) {
  return %!() using &value => ++value;
}

static void _lambda_mutable_siblings(
  int value, Func *writer, Func *reader) {
  *writer = %!() using &value => ++value;
  *reader = %!() using &value => value;
}

static Func _lambda_nested_mutable(int value) {
  Func factory = %!() using &value => %!() using &value => ++value;
  return factory();
}

static Func _lambda_nested_mutable_parameter(void) {
  Func factory = %!(int value) => %!() using &value => ++value;
  return factory(40);
}

static Func _lambda_deferred_mutable(void) {
  int value = 1;
  defer value++;
  return %!() using &value => ++value;
}

typedef struct LambdaReferencePair {
  int left, right;
} LambdaReferencePair;

typedef struct LambdaMutableAggregate {
  int values[2];
} LambdaMutableAggregate;

typedef int LambdaReferenceInt;

static int _lambda_reference_order;

static int _lambda_mutable_order;

static int _lambda_record_mutable_order(int order) {
  _lambda_mutable_order = _lambda_mutable_order * 10 + order;
  return order;
}

static int _lambda_initialize_reference(int &value) {
  return value = 41;
}

static int _lambda_reference_index(void) {
  _lambda_reference_order = _lambda_reference_order * 10 + 2;
  return 1;
}

static Var _lambda_forward_reference(Func function,
                                     LambdaReferencePair &pair) {
  return function(pair);
}

static Var _lambda_call_reference_callback(
  Var (*callback)(int &), int &value) {
  return callback(value);
}

static int _lambda_callback_first = 40, _lambda_callback_second = 40;

static int _lambda_call_first(int (*callback)(int &)) {
  return callback(_lambda_callback_first);
}

static int _lambda_call_second(int (*callback)(int &)) {
  return callback(_lambda_callback_second);
}

static void lambda_nullary_returns_int_as_var(void) {
  Var r = (%!() => 42)();
  EXPECT_INT_EQ(r.int(), 42);
}

static void lambda_unary_identity(void) {
  Var r = (%!(x) => x)(123);
  EXPECT_INT_EQ(r.int(), 123);
}

static void lambda_typed_parameters_convert_from_var(void) {
  Var identity = (%!(int x) => x)(41);
  Var first = (%!(int a, int b) => a)(1, 2);
  EXPECT_INT_EQ(identity.int(), 41);
  EXPECT_INT_EQ(first.int(), 1);
}

static void lambda_capture_is_a_scalar_snapshot_and_global_is_live(void) {
  int bias = 3;
  Func local = %!(int value) => value + bias;
  bias = 100;
  Func returned = _lambda_add_to(4);
  _lambda_live_global = 7;
  EXPECT_INT_EQ(local(5).integer(), 8);
  EXPECT_INT_EQ(returned(5).integer(), 16);
  _lambda_live_global = 5;
}

static void lambda_captures_once_in_first_use_order(void) {
  struct LambdaCaptureProbe first_value = { 3, 1 };
  struct LambdaCaptureProbe second_value = { 4, 2 };
  LambdaCaptureProbe first = &first_value, second = &second_value;
  _lambda_capture_events = 0;
  Func sum = %!() => first.value + second.value + first.value;
  EXPECT_INT_EQ(_lambda_capture_events, 12);
  first_value.value = 5;
  _lambda_capture_events = 0;
  EXPECT_INT_EQ(sum().integer(), 14);
  EXPECT_INT_EQ(_lambda_capture_events, 0);
}

static void lambda_nested_capture_returns_callable_func(void) {
  Func middle = _lambda_nested(10);
  Func inner = middle(20);
  EXPECT_INT_EQ(inner(12).integer(), 42);
}

static void lambda_noncapturing_func_is_reused_and_func_passes_through(void) {
  ScopeStats before = Scope.stats();
  Func first = _lambda_noncapturing_factory();
  Func second = _lambda_noncapturing_factory();
  Func direct = %!(int value) => value * 2;
  Func passed = _lambda_func_passthrough(direct);
  Func parameter = _lambda_func_passthrough(
    %!(int value) => value - 1
  );
  ScopeStats after = Scope.stats();
  EXPECT_PTR_EQ(first, second);
  EXPECT_PTR_EQ(passed, direct);
  EXPECT_INT_EQ(first(41).integer(), 42);
  EXPECT_INT_EQ(direct(21).integer(), 42);
  EXPECT_INT_EQ(parameter(43).integer(), 42);
  EXPECT_INT_EQ(after.allocation_calls, before.allocation_calls);

  int bias = 2;
  Func captured = %!(int value) => value + bias;
  EXPECT_PTR_EQ(_lambda_func_passthrough(captured), captured);
  EXPECT_INT_EQ(captured(40).integer(), 42);
}

static void lambda_capture_allocates_only_at_construction(void) {
  int captured = 3;
  ScopeStats before = Scope.stats();
  Func fn = %!() => captured;
  ScopeStats constructed = Scope.stats();
  Var result = fn();
  ScopeStats applied = Scope.stats();
  EXPECT_INT_EQ(constructed.allocation_calls, before.allocation_calls + 1);
  EXPECT_INT_EQ(result.integer(), 3);
  EXPECT_INT_EQ(applied.allocation_calls, constructed.allocation_calls);
}

static void lambda_func_arguments_convert_in_source_order(void) {
  struct LambdaCaptureProbe first_value = { 3, 1 };
  struct LambdaCaptureProbe second_value = { 4, 2 };
  LambdaCaptureProbe first = &first_value, second = &second_value;
  int bias = 1;
  Func sum = %!(LambdaCaptureProbe left, LambdaCaptureProbe right) =>
    left.value + right.value + bias;
  _lambda_capture_events = 0;
  EXPECT_INT_EQ(sum(first, second).integer(), 8);
  EXPECT_INT_EQ(_lambda_capture_events, 12);
}

static void lambda_reference_parameters_alias_their_arguments(void) {
  int immediate_value = 3;
  Var immediate = (%!(int &value) => ++value)(immediate_value);
  EXPECT_INT_EQ(immediate.integer(), 4);
  EXPECT_INT_EQ(immediate_value, 4);
  EXPECT_INT_EQ(
    _lambda_call_reference_callback(
      (%!(int &value) => ++value), immediate_value).integer(),
    5
  );
  EXPECT_INT_EQ(immediate_value, 5);

  int outer = 10, argument = 1;
  Func returned = _lambda_reference_factory(outer);
  Var result = returned(argument);
  EXPECT_INT_EQ(result.integer(), 13);
  EXPECT_INT_EQ(argument, 2);
  EXPECT_INT_EQ(outer, 11);

  int effects = 0, caught = 0;
  try returned(argument + ++effects);
  catch %(bad-types *): caught = 1;
  EXPECT_TRUE(caught);
  EXPECT_INT_EQ(effects, 0);
}

static void lambda_reference_parameters_adapt_to_native_results(void) {
  _lambda_callback_first = _lambda_callback_second = 40;
  int expression = _lambda_call_first(%!(int &value) => ++value);
  int block = _lambda_call_second(%!(int &value) => {
    return ++value;
  });
  EXPECT_INT_EQ(expression, 41);
  EXPECT_INT_EQ(_lambda_callback_first, 41);
  EXPECT_INT_EQ(block, 41);
  EXPECT_INT_EQ(_lambda_callback_second, 41);
}

static void lambda_reference_parameters_preserve_lvalues(void) {
  int output;
  int assigned = 42;
  Func initialize = %!(int &value) => value = assigned;
  EXPECT_INT_EQ(initialize(output).integer(), 42);
  EXPECT_INT_EQ(output, 42);

  LambdaReferencePair pairs[2] = { { 1, 2 }, { 3, 4 } };
  int increment = 1;
  Func update = %!(LambdaReferencePair &pair) => pair.right += increment;
  _lambda_reference_order = 0;
  Var updated = update(pairs[_lambda_reference_index()]);
  EXPECT_INT_EQ(updated.integer(), 5);
  EXPECT_INT_EQ(pairs[1].right, 5);
  EXPECT_INT_EQ(_lambda_reference_order, 2);
  EXPECT_INT_EQ(_lambda_forward_reference(update, pairs[0]).integer(), 3);
  EXPECT_INT_EQ(pairs[0].right, 3);

  int values[2] = { 1, 4 }, index = 0, zero = 0;
  Func ordered = %!(int &left, int &right) =>
    ++left * 10 + ++right + zero;
  EXPECT_INT_EQ(
    ordered(values[index++], values[index++]).integer(), 25
  );
  EXPECT_INT_EQ(index, 2);
  EXPECT_INT_EQ(values[0], 2);
  EXPECT_INT_EQ(values[1], 5);
}

static void lambda_const_reference_accepts_mutable_and_const_sources(void) {
  int zero = 0;
  Func read = %!(const int &value) => value + zero;
  int mutable_value = 7;
  const int constant_value = 9;
  EXPECT_INT_EQ(read(mutable_value).integer(), 7);
  EXPECT_INT_EQ(read(constant_value).integer(), 9);

  int increment = 1;
  Func mutate = %!(int &value) => value += increment;
  int caught = 0;
  try mutate(constant_value);
  catch %(bad-types *): caught = 1;
  EXPECT_TRUE(caught);

  int pointee = 12, *pointer = &pointee;
  Func unsafe = %!(const int *&value) => *value + zero;
  caught = 0;
  try unsafe(pointer);
  catch %(bad-types *): caught = 1;
  EXPECT_TRUE(caught);

  int one = 1;
  Func alias = %!(LambdaReferenceInt &value) => value += increment;
  EXPECT_INT_EQ(alias(one).integer(), 2);
  EXPECT_INT_EQ(one, 2);
}

static Func _lambda_reference_snapshot(int &value) => %!() => value;

static void lambda_snapshots_ignore_shared_siblings(void) {
  int value = 1;
  Func before = %!() => value;
  Func writer = %!() using &value => ++value;
  Func after = %!() => value;
  Func reader = %!() using &value => value;
  Func parameter = _lambda_reference_snapshot(value);
  value = 2;
  EXPECT_INT_EQ(before().integer(), 1);
  EXPECT_INT_EQ(after().integer(), 1);
  EXPECT_INT_EQ(parameter().integer(), 1);
  EXPECT_INT_EQ(reader().integer(), 2);
  EXPECT_INT_EQ(writer().integer(), 3);
  EXPECT_INT_EQ(reader().integer(), 3);
  EXPECT_INT_EQ(value, 3);
}

static void lambda_capture_clauses_keep_shadowing_and_omit_unused(void) {
  ScopeStats before = Scope.stats();
  int unused, outer = 4;
  Func constant = %!() using &unused, &unused => 42;
  Func parameter = %!(int outer) using &outer => ++outer;
  Func local = %!() using &outer => {
    int outer = 7;
    return ++outer;
  };
  EXPECT_INT_EQ(Scope.stats().allocation_calls, before.allocation_calls);
  EXPECT_INT_EQ(constant().integer(), 42);
  EXPECT_INT_EQ(parameter(9).integer(), 10);
  EXPECT_INT_EQ(local().integer(), 8);
  EXPECT_INT_EQ(outer, 4);
  before = Scope.stats();
  int value = 1;
  Func duplicate = %!() using &value, &value => ++value;
  ScopeStats constructed = Scope.stats();
  EXPECT_INT_EQ(constructed.allocation_calls, before.allocation_calls + 2);
  EXPECT_INT_EQ(duplicate().integer(), 2);
  EXPECT_INT_EQ(Scope.stats().allocation_calls, constructed.allocation_calls);
}

static void lambda_snapshot_contents_remain_mutable(void) {
  int value = 1;
  int *const pointer = &value;
  Array array = %[3], original_array = array;
  Map map = %{key: 5}, original_map = map;
  Func mutate = %!() => {
    ++*pointer;
    array[0] = array[0] + 1;
    map[<key>] = map[<key>] + 1;
    return *pointer + array[0] + map[<key>];
  };
  array = %[20];
  map = %{key: 30};
  EXPECT_INT_EQ(mutate().integer(), 12);
  EXPECT_INT_EQ(value, 2);
  EXPECT_INT_EQ(original_array[0].integer(), 4);
  EXPECT_INT_EQ(original_map[<key>].integer(), 6);
  EXPECT_INT_EQ(array[0].integer(), 20);
  EXPECT_INT_EQ(map[<key>].integer(), 30);
}

static void lambda_snapshot_dynamic_arguments_use_values(void) {
  int value = 1;
  Func apply = %!(Func target) => target(value);
  Func identity = %!(int argument) => argument;
  Func increment = %!(int &argument) => ++argument;
  value = 2;
  EXPECT_INT_EQ(apply(identity).integer(), 1);
  int rejected = 0;
  try apply(increment);
  catch %(bad-types *): rejected = 1;
  EXPECT_TRUE(rejected);
  EXPECT_INT_EQ(value, 2);
}

static void lambda_mutable_capture_is_shared_and_factory_local(void) {
  Func writer, reader;
  ScopeStats before = Scope.stats();
  _lambda_mutable_siblings(4, &writer, &reader);
  EXPECT_INT_EQ(Scope.stats().allocation_calls,
                before.allocation_calls + 3);
  EXPECT_INT_EQ(reader().integer(), 4);
  EXPECT_INT_EQ(writer().integer(), 5);
  EXPECT_INT_EQ(reader().integer(), 5);

  Func first = _lambda_mutable_parameter(10);
  Func second = _lambda_mutable_parameter(20);
  EXPECT_INT_EQ(first().integer(), 11);
  EXPECT_INT_EQ(first().integer(), 12);
  EXPECT_INT_EQ(second().integer(), 21);

  Func nested = _lambda_nested_mutable(30);
  EXPECT_INT_EQ(nested().integer(), 31);
  EXPECT_INT_EQ(nested().integer(), 32);

  Func nested_parameter = _lambda_nested_mutable_parameter();
  EXPECT_INT_EQ(nested_parameter().integer(), 41);
  EXPECT_INT_EQ(nested_parameter().integer(), 42);
}

static void lambda_mutable_capture_preserves_operations(void) {
  int value = 1;
  Func assign = %!() using &value => value = 4;
  Func compound = %!() using &value => value += 3;
  Func prefix = %!() using &value => ++value;
  Func postfix = %!() using &value => value++;
  Func address = %!() using &value => &value;
  EXPECT_INT_EQ(assign().integer(), 4);
  EXPECT_INT_EQ(compound().integer(), 7);
  EXPECT_INT_EQ(prefix().integer(), 8);
  EXPECT_INT_EQ(postfix().integer(), 8);
  EXPECT_INT_EQ(value, 9);
  int *escaped = address().pointer();
  *escaped = 12;
  EXPECT_INT_EQ(value, 12);

  int output;
  Func initialize = %!() using &output => _lambda_initialize_reference(output);
  EXPECT_INT_EQ(initialize().integer(), 41);
  EXPECT_INT_EQ(output, 41);

  LambdaReferencePair pair = { 2, 3 };
  Func member = %!() using &pair => pair.right += pair.left;
  EXPECT_INT_EQ(member().integer(), 5);
  EXPECT_INT_EQ(pair.right, 5);

  volatile int qualified = 5;
  Func qualify = %!() using &qualified => ++qualified;
  EXPECT_INT_EQ(qualify().integer(), 6);
  EXPECT_INT_EQ(qualified, 6);

  LambdaMutableAggregate aggregate = { { 3, 4 } };
  Func indexed = %!() using &aggregate => ++aggregate.values[1];
  EXPECT_INT_EQ(indexed().integer(), 5);
  EXPECT_INT_EQ(aggregate.values[1], 5);
}

static void lambda_mutable_capture_preserves_declarations(void) {
  _lambda_mutable_order = 0;
  int first = _lambda_record_mutable_order(1),
      value = _lambda_record_mutable_order(2),
      third = _lambda_record_mutable_order(3);
  Func increment = %!() using &value => ++value;
  EXPECT_INT_EQ(_lambda_mutable_order, 123);
  EXPECT_INT_EQ(first, 1);
  EXPECT_INT_EQ(third, 3);
  EXPECT_INT_EQ(increment().integer(), 3);
  EXPECT_INT_EQ(value, 3);

  int (left, right) = %(5 7);
  Func destructured = %!() using &left => left += right;
  EXPECT_INT_EQ(destructured().integer(), 12);
  EXPECT_INT_EQ(left, 12);

  Func assign_destructured = %!() using &left, &right => (left, right) = %(8 9);
  assign_destructured();
  EXPECT_INT_EQ(left, 8);
  EXPECT_INT_EQ(right, 9);

  Func deferred = _lambda_deferred_mutable();
  EXPECT_INT_EQ(deferred().integer(), 3);
}

static void lambda_macro_mutable_capture_uses_same_lowering(void) {
  int value = 6;
  Func source = %!() using &value => ++value;
  Func constructed = $test.incrementing_lambda(value);
  EXPECT_INT_EQ(source().integer(), 7);
  EXPECT_INT_EQ(constructed().integer(), 8);
  EXPECT_INT_EQ(value, 8);
}

static void lambda_mutable_capture_allocation_behavior(void) {
  ScopeStats before = Scope.stats();
  Func mutable = _lambda_mutable_parameter(1);
  ScopeStats constructed = Scope.stats();
  EXPECT_INT_EQ(constructed.allocation_calls,
                before.allocation_calls + 2);
  EXPECT_INT_EQ(mutable().integer(), 2);
  EXPECT_INT_EQ(Scope.stats().allocation_calls,
                constructed.allocation_calls);

  int outer = 3;
  before = Scope.stats();
  Func reference = _lambda_reference_factory(outer);
  constructed = Scope.stats();
  EXPECT_INT_EQ(constructed.allocation_calls,
                before.allocation_calls + 1);
  int argument = 4;
  EXPECT_INT_EQ(reference(argument).integer(), 9);
  EXPECT_INT_EQ(outer, 4);
}

static void lambda_block_body_returns_var_or_null(void) {
  Var explicit = (%!(int value) => {
    int doubled = value * 2;
    if (doubled == 42) return doubled;
    return 0;
  })(21);
  Var bare = (%!(int stop) => {
    if (stop) return;
    return 1;
  })(1);
  Var fallthrough = (%!() => {})();
  EXPECT_INT_EQ(explicit.integer(), 42);
  EXPECT_TRUE(bare.is_null());
  EXPECT_TRUE(fallthrough.is_null());

  Func dynamic_fallthrough = %!() => {};
  EXPECT_TRUE(dynamic_fallthrough().is_null());
  Func dynamic_bare = %!() => { return; };
  EXPECT_TRUE(dynamic_bare().is_null());
}

static void _lambda_effect(int *count) { (*count)++; }

static void _lambda_call_native(int *count, void (*callback)(int *)) {
  callback(count);
}

static void lambda_effect_only_calls_return_null(void) {
  int count = 0;
  Var direct = (%!(int *value) => _lambda_effect(value))(&count);
  EXPECT_TRUE(direct.is_null());
  EXPECT_INT_EQ(count, 1);

  Func native = _lambda_effect;
  EXPECT_TRUE(native(&count).is_null());
  EXPECT_INT_EQ(count, 2);

  int *target = &count;
  Func expression = %!() => _lambda_effect(target);
  EXPECT_TRUE(expression().is_null());
  EXPECT_INT_EQ(count, 3);
  Func block = %!() => {
    defer _lambda_effect(target);
    _lambda_effect(target);
  };
  EXPECT_TRUE(block().is_null());
  EXPECT_INT_EQ(count, 5);

  _lambda_call_native(&count, %!(int *value) => _lambda_effect(value));
  EXPECT_INT_EQ(count, 6);
}

static void lambda_explicit_void_result_remains_void(void) {
  Var direct = (%!() => { return void; })();
  EXPECT_TRUE(direct is void);
  Func dynamic = %!() => { return void; };
  int caught = 0;
  try dynamic();
  catch %(bad-result *): caught = 1;
  EXPECT_TRUE(caught);
}

static void lambda_block_body_preserves_closures_and_transfer(void) {
  int bias = 2;
  _lambda_block_cleanup = 0;
  Func add = %!(int value) => {
    defer _lambda_block_cleanup++;
    int result = value + bias;
    return result;
  };
  EXPECT_INT_EQ(add(40).integer(), 42);
  EXPECT_INT_EQ(_lambda_block_cleanup, 1);

  Func outer = %!(int value) => {
    int local = value + bias;
    return %!() using &local => {
      return ++local;
    };
  };
  Func inner = outer(38);
  EXPECT_INT_EQ(inner().integer(), 41);
  EXPECT_INT_EQ(inner().integer(), 42);

  Func fail = %!() => {
    defer _lambda_block_cleanup++;
    raise %(invariant);
  };
  int caught = 0;
  try fail();
  catch %(invariant): caught = 1;
  EXPECT_TRUE(caught);
  EXPECT_INT_EQ(_lambda_block_cleanup, 2);
}

static void lambda_block_body_lifts_for_callbacks(void) {
  List values = %(1 2 3);
  List selected = values.filter(%!(Var value) => {
    return value.int() > 1;
  });
  int bias = 10;
  Func add = %!(Var value) => {
    return value.int() + bias;
  };
  List mapped = selected.map(add);
  EXPECT_INT_EQ(mapped.len(), 2);
  EXPECT_INT_EQ(mapped[0].int(), 12);
  EXPECT_INT_EQ(mapped[1].int(), 13);
}

static void lambda_macro_block_uses_source_lowering(void) {
  int source_bias = 2, macro_bias = 2;
  Func source = %!(int value) => {
    int result = value + source_bias;
    if (result) return result;
    return;
  };
  Func constructed = $test.block_lambda(macro_bias);
  source_bias = macro_bias = 9;
  EXPECT_INT_EQ(source(40).integer(), 42);
  EXPECT_INT_EQ(constructed(40).integer(), 42);
  EXPECT_TRUE(source(-2).is_null());
  EXPECT_TRUE(constructed(-2).is_null());
}

static void lambda_list_map(void) {
  List seq = %(1 2 3), mapped = seq.map(%!(x) => x + 1);
  EXPECT_INT_EQ(mapped.len(), 3);
  EXPECT_INT_EQ(mapped[0].int(), 2);
  EXPECT_INT_EQ(mapped[1].int(), 3);
  EXPECT_INT_EQ(mapped[2].int(), 4);
}

static void lambda_list_foldl(void) {
  List seq = %(1 2 3);
  Var sum = seq.foldl(0, %!(acc, x) => acc + x);
  EXPECT_INT_EQ(sum.int(), 6);
}

static void lambda_list_map2(void) {
  List left = %(1 2 3);
  List right = %(4 5 6);
  List sums = left.map2(right, %!(l, r) => l + r);
  EXPECT_INT_EQ(sums.len(), 3);
  EXPECT_INT_EQ(sums[0].int(), 5);
  EXPECT_INT_EQ(sums[1].int(), 7);
  EXPECT_INT_EQ(sums[2].int(), 9);
}

void lambda_suite(void) {
  $test.run(lambda_nullary_returns_int_as_var);
  $test.run(lambda_unary_identity);
  $test.run(lambda_typed_parameters_convert_from_var);
  $test.run(lambda_capture_is_a_scalar_snapshot_and_global_is_live);
  $test.run(lambda_captures_once_in_first_use_order);
  $test.run(lambda_nested_capture_returns_callable_func);
  $test.run(lambda_noncapturing_func_is_reused_and_func_passes_through);
  $test.run(lambda_capture_allocates_only_at_construction);
  $test.run(lambda_func_arguments_convert_in_source_order);
  $test.run(lambda_reference_parameters_alias_their_arguments);
  $test.run(lambda_reference_parameters_adapt_to_native_results);
  $test.run(lambda_reference_parameters_preserve_lvalues);
  $test.run(lambda_const_reference_accepts_mutable_and_const_sources);
  $test.run(lambda_snapshots_ignore_shared_siblings);
  $test.run(lambda_capture_clauses_keep_shadowing_and_omit_unused);
  $test.run(lambda_snapshot_contents_remain_mutable);
  $test.run(lambda_snapshot_dynamic_arguments_use_values);
  $test.run(lambda_mutable_capture_is_shared_and_factory_local);
  $test.run(lambda_mutable_capture_preserves_operations);
  $test.run(lambda_mutable_capture_preserves_declarations);
  $test.run(lambda_macro_mutable_capture_uses_same_lowering);
  $test.run(lambda_mutable_capture_allocation_behavior);
  $test.run(lambda_block_body_returns_var_or_null);
  $test.run(lambda_effect_only_calls_return_null);
  $test.run(lambda_explicit_void_result_remains_void);
  $test.run(lambda_block_body_preserves_closures_and_transfer);
  $test.run(lambda_block_body_lifts_for_callbacks);
  $test.run(lambda_macro_block_uses_source_lowering);
  $test.run(lambda_list_map);
  $test.run(lambda_list_foldl);
  $test.run(lambda_list_map2);
}
