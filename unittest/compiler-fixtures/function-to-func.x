#include "x2c.x"

typedef long (*BinaryFunction)(long, long);
typedef Var (*ReferenceFunction)(int &);

static long add(long left, long right) {
  return left + right;
}

static long subtract(long left, long right) {
  return left - right;
}

static Var increment(int &value) {
  return ++value;
}

static Func global_add = add;
static int pointer_evaluations;

static BinaryFunction evaluated_pointer(void) {
  pointer_evaluations++;
  return add;
}

static Var call(Func function, long left, long right) {
  return function(left, right);
}

static Func return_direct(void) {
  return add;
}

static Func return_pointer(BinaryFunction function) {
  return function;
}

static Func return_noncapturing_lambda(void) {
  return %!(long value) => value + 1;
}

static Func passthrough(Func function) {
  return function;
}

int main(void) {
  ScopeStats before = Scope.stats();
  Func direct = add;
  Func addressed = &add;
  Func returned = return_direct();
  Func assigned = NULL;
  assigned = subtract;
  Func subtract_again = subtract;
  Func lambda_first = return_noncapturing_lambda();
  Func lambda_second = return_noncapturing_lambda();
  Func direct_lambda = %!(long value) => value * 2;
  Func parameter_lambda = passthrough(%!(long value) => value - 1);
  ScopeStats after = Scope.stats();

  if (direct != global_add || addressed != direct || returned != direct)
    return 1;
  if (assigned != subtract_again) return 2;
  if (lambda_first != lambda_second) return 3;
  if (passthrough(direct_lambda) != direct_lambda) return 4;
  if (call(add, 20, 22).integer() != 42) return 5;
  if (direct(20, 22).integer() != 42) return 6;
  if (assigned(20, 7).integer() != 13) return 7;
  if (lambda_first(41).integer() != 42) return 8;
  if (direct_lambda(21).integer() != 42) return 9;
  if (parameter_lambda(43).integer() != 42) return 10;
  if (after.allocation_calls != before.allocation_calls) return 11;

  BinaryFunction selected = add;
  Func snapshot = selected;
  selected = subtract;
  if (snapshot(20, 22).integer() != 42) return 12;
  if (call(selected, 20, 7).integer() != 13) return 13;

  Func pointer_assignment = NULL;
  pointer_assignment = selected;
  Func pointer_return = return_pointer(selected);
  Func conditional = pointer_evaluations ? subtract : add;
  if (pointer_assignment(20, 7).integer() != 13) return 14;
  if (pointer_return(20, 7).integer() != 13) return 15;
  if (conditional(20, 22).integer() != 42) return 23;

  BinaryFunction chosen = subtract;
  Func dereferenced = *chosen;
  if (dereferenced(20, 7).integer() != 13) return 24;
  Func sequenced = ((void) 0, add);
  if (sequenced(20, 22).integer() != 42) return 25;
  Func parenthesized = (*chosen);
  if (parenthesized(20, 7).integer() != 13) return 26;
  Func readdressed = &*chosen;
  if (readdressed(20, 7).integer() != 13) return 27;

  pointer_evaluations = 0;
  Func evaluated = evaluated_pointer();
  if (pointer_evaluations != 1) return 16;
  if (evaluated(19, 23).integer() != 42) return 17;

  BinaryFunction absent = NULL;
  before = Scope.stats();
  Func missing = absent;
  Func typed_null = (BinaryFunction) NULL;
  after = Scope.stats();
  if (missing || typed_null) return 18;
  if (after.allocation_calls != before.allocation_calls) return 19;

  ReferenceFunction reference_pointer = increment;
  Func reference = reference_pointer;
  int value = 40;
  if (reference(value).integer() != 41 || value != 41) return 20;

  int bias = 2;
  Func captured = %!(long value) => value + bias;
  if (passthrough(captured) != captured) return 21;
  if (captured(40).integer() != 42) return 22;

  printf("42 13 42 41\n");
  return 0;
}
