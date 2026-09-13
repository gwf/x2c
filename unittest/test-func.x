/*  test-func.x -- unit tests for the generic native Func binder */

#include "test-support.x"

$(import "../lib/error-private.xmacro")
$error.private.types();

static long _add_longs(long a, long b) {
  return a + b;
}

typedef long (*FuncTestBinary)(long, long);
typedef int (*FuncTestReference)(int &);
typedef Var (*FuncTestIdentity)(Var);
typedef void (*FuncTestVoid)(int);

static long _subtract_longs(long left, long right) {
  return left - right;
}

static Var _identity_var(Var value) {
  return value;
}

static Func _global_add_func = _add_longs;
static int _func_pointer_evaluations;

static FuncTestBinary _evaluated_binary(void) {
  _func_pointer_evaluations++;
  return _add_longs;
}

static Var _call_binary(Func function, long left, long right) {
  return function(left, right);
}

static Func _return_direct_binary(void) {
  return _add_longs;
}

static Func _return_pointer_binary(FuncTestBinary function) {
  return function;
}

static List func_error;

static Symbol _capture_func_error(List errors, Var data) {
  (void) data;
  Var snapshot = Error.snapshot(errors.last());
  func_error = snapshot;
  return <handled>;
}

static Symbol _func_error_code(void) {
  return func_error.assoc(<code>);
}

static void func_new_direct_pointer(void) {
  Func fn = Func.new(
    _add_longs, %((func ((long) (long))) long)
  );
  EXPECT_NOT_NULL(fn);
}

static void func_apply_converts_numeric_arguments(void) {
  Func fn = Func.new(_add_longs,
                     %((func ((long) (long))) long));
  FuncArg argv[2];
  argv[0] = FuncArg.value(Var.new(<i32>, 4));
  argv[1] = FuncArg.value(Var.new(<i32>, 5));
  Var out = Func.apply(fn, 2, argv);
  EXPECT_TRUE(out is <long>);
  EXPECT_INT_EQ(Var.integer(out), 9);
}

static int _side_effect;

static void _bump_counter(int amount) {
  _side_effect += amount;
}

static FuncTestVoid _evaluated_void(void) {
  _func_pointer_evaluations++;
  return _bump_counter;
}

static Var _return_void_var(void) {
  return void;
}

static Var _raising_native(Var value) {
  raise %(observer-p (value $value));
  return value;
}

static Var _transferring_native(Var value) {
  defer _side_effect += 10;
  raise %(format (value $value));
  return void;
}

static Var _nested_transferring_native(Var value) {
  defer _side_effect += 100;
  Func fn = Func.new(
    _transferring_native,
    %((func (("Var"))) "Var")
  );
  FuncArg argv[1] = { FuncArg.value(value) };
  return Func.apply(fn, 1, argv);
}

static Var _retained_slice_native(Var value) {
  raise %(func-note (before $value));
  raise %(format (value $value));
  return void;
}

/* Hand-written in the shape the compiler will generate. */
typedef struct FuncTestContext {
  Var value;
} FuncTestContext;

typedef union FuncAlignedContext {
  max_align_t alignment;
  long value;
} FuncAlignedContext;

static Var _adapt_add_longs(Func fn, const FuncArg *argv) {
  long left = Var.integer(x2c_func_value_argument(fn, argv, 0, <long>));
  long right = Var.integer(x2c_func_value_argument(fn, argv, 1, <long>));
  return Var.new(<long>, _add_longs(left, right));
}

static Var _adapt_add_context(Func fn, const FuncArg *argv) {
  const FuncTestContext *context = fn.context();
  long value = Var.integer(x2c_func_value_argument(fn, argv, 0, <long>));
  return Var.new(<long>, value + context.value.integer());
}

static Var _adapt_context_identity(Func fn, const FuncArg *argv) {
  (void) argv;
  const FuncTestContext *context = fn.context();
  return context.value;
}

static Var _adapt_aligned_context(Func fn, const FuncArg *argv) {
  (void) argv;
  const FuncAlignedContext *context = fn.context();
  return Var.new(<long>, context.value);
}

static Var _adapt_context_transfer(Func fn, const FuncArg *argv) {
  (void) fn.context();
  return _transferring_native(
    x2c_func_value_argument(fn, argv, 0, <var>)
  );
}

static Var _adapt_increment_reference(Func fn, const FuncArg *argv) {
  int *value = x2c_func_reference_argument(fn, argv, 0, %(int));
  return Var.new(<i32>, ++*value);
}

static int _increment_reference(int &value) {
  return ++value;
}

static Var _rest_length(List values) {
  return values.len();
}

static void func_direct_conversion_covers_expected_contexts(void) {
  ScopeStats before = Scope.stats();
  Func direct = _add_longs;
  Func addressed = &_add_longs;
  Func returned = _return_direct_binary();
  Func assigned = NULL;
  assigned = _subtract_longs;
  Func subtract = _subtract_longs;
  ScopeStats after = Scope.stats();

  EXPECT_PTR_EQ(direct, _global_add_func);
  EXPECT_PTR_EQ(addressed, direct);
  EXPECT_PTR_EQ(returned, direct);
  EXPECT_PTR_EQ(assigned, subtract);
  EXPECT_INT_EQ(_call_binary(_add_longs, 20, 22).integer(), 42);
  EXPECT_INT_EQ(direct(20, 22).integer(), 42);
  EXPECT_INT_EQ(assigned(20, 7).integer(), 13);
  EXPECT_INT_EQ(after.allocation_calls, before.allocation_calls);
}

static void func_pointer_conversion_snapshots_and_handles_null(void) {
  FuncTestBinary selected = _add_longs;
  Func snapshot = selected;
  selected = _subtract_longs;
  EXPECT_INT_EQ(snapshot(20, 22).integer(), 42);

  FuncTestIdentity identity_pointer = _identity_var;
  ScopeStats before_identity = Scope.stats();
  Func identity = identity_pointer;
  ScopeStats constructed = Scope.stats();
  Var result = identity(42);
  ScopeStats applied = Scope.stats();
  EXPECT_INT_EQ(
    constructed.allocation_calls, before_identity.allocation_calls + 1
  );
  EXPECT_INT_EQ(result.integer(), 42);
  EXPECT_INT_EQ(applied.allocation_calls, constructed.allocation_calls);
  EXPECT_INT_EQ(_call_binary(selected, 20, 7).integer(), 13);

  Func assigned = NULL;
  assigned = selected;
  Func returned = _return_pointer_binary(selected);
  EXPECT_INT_EQ(assigned(20, 7).integer(), 13);
  EXPECT_INT_EQ(returned(20, 7).integer(), 13);

  _func_pointer_evaluations = 0;
  Func evaluated = _evaluated_binary();
  EXPECT_INT_EQ(_func_pointer_evaluations, 1);
  EXPECT_INT_EQ(evaluated(19, 23).integer(), 42);

  _side_effect = 0;
  _func_pointer_evaluations = 0;
  Func void_function = _evaluated_void();
  Var void_result = void_function(9);
  EXPECT_INT_EQ(_func_pointer_evaluations, 1);
  EXPECT_INT_EQ(_side_effect, 9);
  EXPECT_TRUE(void_result.is_null());

  FuncTestBinary absent = NULL;
  ScopeStats before = Scope.stats();
  Func missing = absent;
  Func typed_null = (FuncTestBinary) NULL;
  ScopeStats after = Scope.stats();
  EXPECT_NULL(missing);
  EXPECT_NULL(typed_null);
  EXPECT_INT_EQ(after.allocation_calls, before.allocation_calls);
}

static void func_pointer_conversion_preserves_references(void) {
  FuncTestReference pointer = _increment_reference;
  Func function = pointer;
  int value = 40;
  EXPECT_INT_EQ(function(value).integer(), 41);
  EXPECT_INT_EQ(value, 41);
}

/* A value already typed FuncAdapter passes through unadapted: the compiler
   leaves it alone and the runtime calls it as written. */
static void func_handwritten_adapter_passes_through(void) {
  Func fn = Func.new(_adapt_add_longs, %((func ((long) (long))) long));
  FuncArg argv[2];
  argv[0] = FuncArg.value(Var.new(<i32>, 4));
  argv[1] = FuncArg.value(Var.new(<i32>, 5));
  Var out = Func.apply(fn, 2, argv);
  EXPECT_INT_EQ(out.integer(), 9);
}

static void func_contexts_are_independent_snapshots(void) {
  List signature = %((func ((long))) long);
  FuncTestContext first_context = { Var.new(<i32>, 3) };
  FuncTestContext second_context = { Var.new(<i32>, 20) };
  Func first = Func.new_context(
    _adapt_add_context, signature, &first_context, sizeof first_context
  );
  Func second = Func.new_context(
    _adapt_add_context, signature, &second_context, sizeof second_context
  );
  first_context.value = Var.new(<i32>, 100);
  second_context.value = Var.new(<i32>, 200);
  FuncArg argv[1] = { FuncArg.value(Var.new(<i32>, 4)) };
  EXPECT_INT_EQ(Func.apply(first, 1, argv).integer(), 7);
  EXPECT_INT_EQ(Func.apply(second, 1, argv).integer(), 24);
}

static void func_zero_context_and_source_checks(void) {
  Func fn = Func.new_context(
    _adapt_add_longs, %((func ((long) (long))) long), NULL, 0
  );
  FuncArg argv[2] = {
    FuncArg.value(Var.new(<i32>, 2)),
    FuncArg.value(Var.new(<i32>, 5))
  };
  EXPECT_INT_EQ(Func.apply(fn, 2, argv).integer(), 7);
  EXPECT_PTR_EQ(fn.context(), NULL);
  int null_caught = 0, source_caught = 0;
  try Func.context(NULL);
  catch %(bad-arg *): null_caught = 1;
  try Func.new_context(
    _adapt_add_context, %((func ((long))) long), NULL,
    sizeof(FuncTestContext)
  );
  catch %(bad-arg *): source_caught = 1;
  EXPECT_TRUE(null_caught);
  EXPECT_TRUE(source_caught);
}

static void func_context_construction_allocates_once(void) {
  FuncTestContext context = { Var.new(<i32>, 3) };
  ScopeStats before = Scope.stats();
  Func fn = Func.new_context(
    _adapt_context_identity, %((func (("Var"))) "Var"),
    &context, sizeof context
  );
  ScopeStats constructed = Scope.stats();
  FuncArg argv[1] = { FuncArg.value(Var.new(<i32>, 4)) };
  Var result = Func.apply(fn, 1, argv);
  ScopeStats applied = Scope.stats();
  EXPECT_INT_EQ(constructed.allocation_calls, before.allocation_calls + 1);
  EXPECT_INT_EQ(result.integer(), 3);
  EXPECT_INT_EQ(applied.allocation_calls, constructed.allocation_calls);
}

static void func_context_is_maximum_aligned(void) {
  FuncAlignedContext context = { .value = 41 };
  Func fn = Func.new_context(
    _adapt_aligned_context, %((func ((void))) long),
    &context, sizeof context
  );
  EXPECT_INT_EQ((uintptr_t) fn.context() % _Alignof(max_align_t), 0);
  EXPECT_INT_EQ(Func.apply(fn, 0, NULL).integer(), 41);
}

static void func_context_apply_keeps_arity_and_transfer(void) {
  FuncTestContext context = { Var.new(<i32>, 1) };
  Func fn = Func.new_context(
    _adapt_context_transfer, %((func (("Var"))) "Var"),
    &context, sizeof context
  );
  FuncArg argv[1] = { FuncArg.value(Var.new(<i32>, 23)) };
  int arity_caught = 0, transfer_caught = 0;
  try Func.apply(fn, 0, NULL);
  catch %(bad-arity *): arity_caught = 1;
  _side_effect = 0;
  try Func.apply(fn, 1, argv);
  catch %(format (value ?value)): transfer_caught = value.integer();
  EXPECT_TRUE(arity_caught);
  EXPECT_INT_EQ(transfer_caught, 23);
  EXPECT_INT_EQ(_side_effect, 10);
}

static void func_reference_argument_checks_carrier_and_type(void) {
  Func fn = Func.new(
    _adapt_increment_reference, %((func ((& int))) int)
  );
  int value = 6;
  FuncArg valid[1] = { FuncArg.reference(&value, %(int)) };
  EXPECT_INT_EQ(Func.apply(fn, 1, valid).integer(), 7);
  EXPECT_INT_EQ(value, 7);

  FuncArg boxed[1] = { FuncArg.value(Var.new(<i32>, 7)) };
  int boxed_caught = 0;
  try Func.apply(fn, 1, boxed);
  catch %(bad-types *): boxed_caught = 1;
  EXPECT_TRUE(boxed_caught);

  FuncArg wrong_type[1] = { FuncArg.reference(&value, %(long)) };
  int type_caught = 0;
  try Func.apply(fn, 1, wrong_type);
  catch %(bad-types *): type_caught = 1;
  EXPECT_TRUE(type_caught);
}

static void func_generated_reference_target_aliases_source(void) {
  Func fn = Func.new(
    _increment_reference, %((func ((& int))) int)
  );
  int value = 10;
  FuncArg argument[1] = { FuncArg.reference(&value, %(int)) };
  EXPECT_INT_EQ(Func.apply(fn, 1, argument).integer(), 11);
  EXPECT_INT_EQ(value, 11);
}

static void func_reference_and_signature_disagreement_fails(void) {
  Func wrong_signature = Func.new(
    _adapt_increment_reference, %((func ((& long))) int)
  );
  long value = 4;
  FuncArg argument[1] = { FuncArg.reference(&value, %(long)) };
  int caught = 0;
  try Func.apply(wrong_signature, 1, argument);
  catch %(bad-types *): caught = 1;
  EXPECT_TRUE(caught);
}

static void func_rest_accepts_values_and_rejects_references(void) {
  Func fn = Func.new_rest(
    _rest_length, %((func (("List"))) "Var")
  );
  FuncArg values[2] = {
    FuncArg.value(Var.new(<i32>, 1)),
    FuncArg.value(Var.new(<i32>, 2))
  };
  EXPECT_INT_EQ(Func.apply(fn, 2, values).integer(), 2);

  int source = 3;
  FuncArg reference[1] = { FuncArg.reference(&source, %(int)) };
  int caught = 0;
  try Func.apply(fn, 1, reference);
  catch %(bad-types *): caught = 1;
  EXPECT_TRUE(caught);
}

/* A value already typed FuncAdapter passes through unadapted, which is how a
   forwarding helper works and how the runtime null guard stays reachable. */
static void func_rejects_null_adapter(void) {
  FuncAdapter absent = NULL;
  int caught = 0;
  try Func.new(absent, %((func (("Var"))) "Var"));
  catch %(bad-sig *): caught = 1;
  EXPECT_TRUE(caught);
}

/* Passing a direct function makes the compiler generate the adapter. */
static void func_generated_target_runs(void) {
  Func fn = Func.new(_add_longs, %((func ((long) (long))) long));
  FuncArg argv[2];
  argv[0] = FuncArg.value(Var.new(<i32>, 20));
  argv[1] = FuncArg.value(Var.new(<i32>, 22));
  Var out = Func.apply(fn, 2, argv);
  EXPECT_INT_EQ(out.integer(), 42);
}

/* A generated adapter is ordinary compiled C, so an Error raised inside the
   target unwinds through it without a landing pad, running its defer. */
static void func_generated_target_transfers_error(void) {
  Func fn = Func.new(_transferring_native, %((func (("Var"))) "Var"));
  FuncArg argv[1];
  argv[0] = FuncArg.value(Var.new(<i32>, 3));
  _side_effect = 0;
  int caught = 0;
  try Func.apply(fn, 1, argv);
  catch %(format *): caught = 1;
  EXPECT_TRUE(caught);
  EXPECT_INT_EQ(_side_effect, 10);
}

static void func_apply_wrong_arity_fails(void) {
  Func fn = Func.new(_add_longs, %((func ((long) (long))) long));
  FuncArg argv[1];
  argv[0] = FuncArg.value(Var.new(<i32>, 4));
  List detail = NULL;
  try Func.apply(fn, 1, argv);
  catch %(bad-arity *cause): detail = cause;
  if (!EXPECT_NOT_NULL(detail)) return;
  EXPECT_INT_EQ(detail.assoc(<expected>).integer(), 2);
  EXPECT_INT_EQ(detail.assoc(<actual>).integer(), 1);
}

static void func_apply_wrong_object_tag_fails(void) {
  Func fn = Func.new(String_lower,
                  %((func (("String"))) "String"));
  FuncArg argv[1];
  argv[0] = FuncArg.value(Var.new(<i32>, 7));
  List detail = NULL;
  try Func.apply(fn, 1, argv);
  catch %(bad-types *cause): detail = cause;
  EXPECT_NOT_NULL(detail);
  EXPECT_INT_EQ(detail.assoc(<index>).integer(), 0);
}

static void func_apply_wrong_symbol_tag_fails(void) {
  Func fn = Func.new(Symbol_str,
                  %((func (("Symbol"))) "String"));
  FuncArg argv[1];
  argv[0] = FuncArg.value(Var.new(<i32>, 7));
  int caught = 0;
  try Func.apply(fn, 1, argv);
  catch %(bad-types *): caught = 1;
  EXPECT_TRUE(caught);
}

static void func_apply_void_argument_fails(void) {
  Func fn = Func.new(_bump_counter, %((func ((int))) void));
  FuncArg argv[1];
  argv[0] = FuncArg.value(void);
  int caught = 0;
  try Func.apply(fn, 1, argv);
  catch %(void-op *): caught = 1;
  EXPECT_TRUE(caught);
}

static void func_apply_conversion_range_fails(void) {
  Func fn = Func.new(_bump_counter, %((func ((int))) void));
  FuncArg argv[1];
  argv[0] = FuncArg.value(Var.new(<f64>, 1.0e300));
  List detail = NULL;
  try Func.apply(fn, 1, argv);
  catch %(conv-range *cause): detail = cause;
  EXPECT_NOT_NULL(detail);
  EXPECT_INT_EQ(detail.assoc(<index>).integer(), 0);
  EXPECT_TRUE(detail.assoc(<cause>) is <list>);
}

static void func_void_result_is_raw_null(void) {
  Func fn = Func.new(
    _bump_counter, %((func ((int))) void)
  );
  _side_effect = 0;
  FuncArg argv[1];
  argv[0] = FuncArg.value(Var.new(<i32>, 5));
  Var out = Func.apply(fn, 1, argv);
  EXPECT_INT_EQ(_side_effect, 5);
  EXPECT_TRUE(out.is_null());
}

static void func_var_result_rejects_void(void) {
  Func fn = Func.new(_return_void_var, %((func ((void))) "Var"));
  int caught = 0;
  try Func.apply(fn, 0, NULL);
  catch %(bad-result *): caught = 1;
  EXPECT_TRUE(caught);
}

static void func_list_argument_round_trips(void) {
  Func fn = Func.new(List_cdr, %((func (("List"))) "List"));
  List pair = %(1 2);
  FuncArg argv[1];
  argv[0] = FuncArg.value(pair);
  Var out = Func.apply(fn, 1, argv);
  EXPECT_VAR_EQ(out, %(2).var());
}

static int _rejects_signature(List signature) {
  int caught = 0;
  try Func.new(_add_longs, signature);
  catch %(bad-sig *): caught = 1;
  return caught;
}

/* Only the signature's shape is checked now: its parameter and result types
   are the compiler's business, since the adapter carries them. */
static void func_bad_signatures_rejected(void) {
  EXPECT_TRUE(_rejects_signature(%(NOPE ((long)) long)));
  EXPECT_TRUE(_rejects_signature(%(FUNC ((class Var)) class Var)));
  EXPECT_TRUE(_rejects_signature(%((func ()) long)));
}

static void func_native_raise_observer_is_safe(void) {
  Symbol previous = Error.policy_get(<observer-p>);
  Error.policy_set(<observer-p>, <ignore>);
  defer Error.policy_set(<observer-p>, previous);
  Func fn = Func.new(
    _raising_native, %((func (("Var"))) "Var")
  );
  FuncArg argv[1];
  argv[0] = FuncArg.value(Var.new(<i32>, 77));
  ErrorHandler handler = Error.push(_capture_func_error, void);
  defer Error.pop(handler);
  Var out = Func.apply(fn, 1, argv);
  EXPECT_INT_EQ(out.integer(), 77);
  EXPECT_INT_EQ(_func_error_code(), <observer-p>);
}

static void func_direct_target_transfers_to_catch(void) {
  Func fn = Func.new(
    _transferring_native,
    %((func (("Var"))) "Var")
  );
  FuncArg argv[1] = { FuncArg.value(Var.new(<i32>, 91)) };
  int returned = 0, caught = 0;
  _side_effect = 0;
  try {
    Func.apply(fn, 1, argv);
    returned = 1;
  }
  catch %(format (value ?value)): {
    caught = value.integer();
  }
  EXPECT_FALSE(returned);
  EXPECT_INT_EQ(caught, 91);
  EXPECT_INT_EQ(_side_effect, 10);
}

static void func_cross_file_target_transfers_to_catch(void) {
  Func fn = Func.new(
    Var_binary,
    %((func (("Var") ("Symbol") ("Var"))) "Var")
  );
  FuncArg argv[3] = {
    FuncArg.value(Var.new(<i32>, 1)),
    FuncArg.value(<not-an-ope>),
    FuncArg.value(Var.new(<i32>, 2))
  };
  int returned = 0, caught = 0;
  try {
    Func.apply(fn, 3, argv);
    returned = 1;
  }
  catch %(bad-op *): caught = 1;
  EXPECT_FALSE(returned);
  EXPECT_TRUE(caught);
}

static void func_nested_targets_share_one_transfer(void) {
  Func fn = Func.new(
    _nested_transferring_native,
    %((func (("Var"))) "Var")
  );
  FuncArg argv[1] = { FuncArg.value(Var.new(<i32>, 37)) };
  int returned = 0, caught = 0;
  _side_effect = 0;
  try {
    Func.apply(fn, 1, argv);
    returned = 1;
  }
  catch %(format (value ?value)): caught = value.integer();
  EXPECT_FALSE(returned);
  EXPECT_INT_EQ(caught, 37);
  EXPECT_INT_EQ(_side_effect, 110);
}


static void func_var_boxes_as_func_tag(void) {
  Func fn = Func.new(_add_longs, %((func ((long) (long))) long));
  Var boxed = Func.var(fn);
  EXPECT_TRUE(boxed is <func>);
  EXPECT_PTR_EQ(boxed.pointer(), fn);
}

$(import "test-macros.xmacro")

void func_suite(void) {
  $test.run(func_new_direct_pointer);
  $test.run(func_apply_converts_numeric_arguments);
  $test.run(func_direct_conversion_covers_expected_contexts);
  $test.run(func_pointer_conversion_snapshots_and_handles_null);
  $test.run(func_pointer_conversion_preserves_references);
  $test.run(func_handwritten_adapter_passes_through);
  $test.run(func_contexts_are_independent_snapshots);
  $test.run(func_zero_context_and_source_checks);
  $test.run(func_context_construction_allocates_once);
  $test.run(func_context_is_maximum_aligned);
  $test.run(func_context_apply_keeps_arity_and_transfer);
  $test.run(func_reference_argument_checks_carrier_and_type);
  $test.run(func_generated_reference_target_aliases_source);
  $test.run(func_reference_and_signature_disagreement_fails);
  $test.run(func_rest_accepts_values_and_rejects_references);
  $test.run(func_rejects_null_adapter);
  $test.run(func_generated_target_runs);
  $test.run(func_generated_target_transfers_error);
  $test.run(func_apply_wrong_arity_fails);
  $test.run(func_apply_wrong_object_tag_fails);
  $test.run(func_apply_wrong_symbol_tag_fails);
  $test.run(func_apply_void_argument_fails);
  $test.run(func_apply_conversion_range_fails);
  $test.run(func_void_result_is_raw_null);
  $test.run(func_var_result_rejects_void);
  $test.run(func_list_argument_round_trips);
  $test.run(func_bad_signatures_rejected);
  $test.run(func_native_raise_observer_is_safe);
  $test.run(func_direct_target_transfers_to_catch);
  $test.run(func_cross_file_target_transfers_to_catch);
  $test.run(func_nested_targets_share_one_transfer);
  $test.run(func_var_boxes_as_func_tag);
}
