#include "x2c.x"

typedef unsigned char Byte;
typedef int Int;
struct Item { int number; };

meta int narrow(Byte n) => n;
meta Byte byte_result(int n) => n;
meta int mutate(int &n) { n += 3; return n; }
meta int alias(int &a, int &b) { a += 3; return b; }
meta int forward(Func f, int &n) => f(n);
meta Func choose(int *count) {
  *count += 1;
  return %!(int a, int b) => a * 10 + b;
}
meta int next(int *count) { *count += 1; return *count; }

meta int byte_input(int n) {
  Func f = %!(unsigned char a) => a;
  return f(n);
}
meta int float_input(int n) {
  Func f = %!(float a) => a - 16777216;
  return f(n);
}
meta int integer_input(int n) {
  Func f = %!(int a) => a;
  return f(n + 0.5);
}
meta int result_tag(int n) {
  Func f = %!(int a) => (unsigned char) a;
  Var result = f(n);
  return result is <u8> && result.int() == 1;
}
meta int named_input(int n) { Func f = narrow; return f(n); }
meta int named_result(int n) {
  Func f = byte_result;
  Var result = f(n);
  return result is <u8> && result.int() == 1;
}
meta int loaded_input(int n) {
  Func f = narrow;
  Array fs = [f];
  Func loaded = fs[0];
  return loaded(n);
}
meta int parameter_input(int n) {
  Func f = %!(unsigned char a) => a;
  return forward(f, n);
}
meta int reference_read(int n) {
  Func f = %!(int &a) => a;
  return f(n);
}
meta int reference_alias(int n) {
  Func f = alias;
  int result = f(n, n);
  return result * 10 + n;
}
meta int reference_forward(int n) {
  Func f = mutate;
  int result = forward(f, n);
  return result * 10 + n;
}
meta int reference_output(int n) {
  int output;
  Func f = %!(int &a) => a = 41;
  (void) f(output);
  return output + n;
}
meta int reference_qualified(int n) {
  Int value = n;
  Func f = %!(const volatile int &a) => a;
  return f(value);
}
meta int reference_field(int n) {
  struct Cell { int value; } cell = {n};
  Func f = mutate;
  int result = f(cell.value);
  return result * 10 + cell.value;
}
meta int reference_loaded(int n) {
  Func f = mutate;
  Array fs = [f];
  Func loaded = fs[0];
  int result = loaded(n);
  return result * 10 + n;
}
meta int evaluation_order(int n) {
  int count = n;
  int result = choose(&count)(next(&count), next(&count));
  return result * 10 + count;
}
meta int void_value(int n) {
  Func f = %!(Var a) => a.is_void();
  return f(void) + n;
}

meta int pointer_index(int n) {
  int *p = &n;
  Func f = mutate;
  int result = f(p[0]);
  return result * 10 + n;
}
meta int snapshot_after_reference(int n) {
  Func read = %!() => n;
  Func bump = %!(int &a) => ++a;
  (void) bump(n);
  return read().int() * 10 + n;
}
meta int shared_capture(int n) {
  Func read = %!() using &n => n;
  Func bump = %!(int &a) => ++a;
  (void) bump(n);
  return read().int() * 10 + n;
}
meta int array_address(int n) {
  int values[2] = {n, 5};
  int *p = &values[0];
  Func f = alias;
  int result = f(*p, values[0]);
  return result * 10 + values[0];
}
meta int signature_retained(int n) {
  Func f = narrow;
  Array functions = [f];
  Func loaded = functions[0];
  return f.signature().equal(loaded.signature()) + n;
}

meta int prepared_values(int n) {
  Func f = %!(unsigned char a, int b) => a * 10 + b;
  int result = f(n, n = 2);
  return result * 10 + n;
}
meta int prepared_reference(int n) {
  Func f = %!(int &a, int b) => a + b;
  int result = f(n, n = 3);
  return result * 10 + n;
}

/* Assignment reaches a Func the way an initializer does, and a lambda
   constructed as `Func`-typed syntax reaches every destination. */
macro Expression $constructed() =>
  $(quote (expr ("Func")
    (lambda (params) (expr (int) (literal (int) "42")))));
meta Func constructed_result(void) => $constructed();
meta int assigned_named(int n) {
  Func f;
  f = narrow;
  return f(n);
}
meta int assigned_lambda(int n) {
  Func f;
  f = %!(int a) => a * 3;
  return f(n);
}
meta int argument_lambda(int n) => forward(%!(int a) => a - 1, n);
meta int built_init(int n) {
  Func f = $constructed();
  return f().int() + n;
}
meta int built_assigned(int n) {
  Func f;
  f = $constructed();
  return f().int() + n;
}
meta int built_argument(int n) {
  Func f = %!(Func g, int a) => g().int() + a;
  return f($constructed(), n);
}
meta int built_returned(int n) => constructed_result()().int() + n;
meta int built_var(int n) {
  Var v = $constructed();
  Func f = v;
  return f().int() + n;
}

int main(int argc, char **argv) {
  (void) argv;
  int one = argc;
  printf("byte %d %d %d\n", $byte_input(257), byte_input(257),
    byte_input(one + 256));
  printf("float %d %d %d\n", $float_input(16777217), float_input(16777217),
    float_input(one + 16777216));
  printf("integer %d %d %d\n", $integer_input(1), integer_input(1),
    integer_input(one));
  printf("result %d %d %d\n", $result_tag(257), result_tag(257),
    result_tag(one + 256));
  printf("named %d %d %d\n", $named_input(257), named_input(257),
    named_input(one + 256));
  printf("named-result %d %d %d\n", $named_result(257), named_result(257),
    named_result(one + 256));
  printf("loaded %d %d %d\n", $loaded_input(257), loaded_input(257),
    loaded_input(one + 256));
  printf("parameter %d %d %d\n", $parameter_input(257), parameter_input(257),
    parameter_input(one + 256));
  printf("read %d %d %d\n", $reference_read(1), reference_read(1),
    reference_read(one));
  printf("alias %d %d %d\n", $reference_alias(1), reference_alias(1),
    reference_alias(one));
  printf("forward %d %d %d\n", $reference_forward(1), reference_forward(1),
    reference_forward(one));
  printf("output %d %d %d\n", $reference_output(1), reference_output(1),
    reference_output(one));
  printf("qualified %d %d %d\n", $reference_qualified(1),
    reference_qualified(1), reference_qualified(one));
  printf("field %d %d %d\n", $reference_field(1), reference_field(1),
    reference_field(one));
  printf("loaded-ref %d %d %d\n", $reference_loaded(1), reference_loaded(1),
    reference_loaded(one));
  printf("order %d %d %d\n", $evaluation_order(0), evaluation_order(0),
    evaluation_order(one - 1));
  printf("void %d %d %d\n", $void_value(1), void_value(1), void_value(one));
  printf("pointer-index %d %d %d\n", $pointer_index(1), pointer_index(1),
    pointer_index(one));
  printf("snapshot %d %d %d\n", $snapshot_after_reference(1),
    snapshot_after_reference(1), snapshot_after_reference(one));
  printf("shared %d %d %d\n", $shared_capture(1), shared_capture(1),
    shared_capture(one));
  printf("array-address %d %d %d\n", $array_address(1), array_address(1),
    array_address(one));
  printf("signature %d %d %d\n", $signature_retained(1), signature_retained(1),
    signature_retained(one));
  printf("prepared-values %d %d %d\n", $prepared_values(257),
    prepared_values(257), prepared_values(one + 256));
  printf("prepared-ref %d %d %d\n", $prepared_reference(1),
    prepared_reference(1), prepared_reference(one));
  printf("assigned-named %d %d %d\n", $assigned_named(257),
    assigned_named(257), assigned_named(one + 256));
  printf("assigned-lambda %d %d %d\n", $assigned_lambda(1),
    assigned_lambda(1), assigned_lambda(one));
  printf("argument-lambda %d %d %d\n", $argument_lambda(1),
    argument_lambda(1), argument_lambda(one));
  printf("built-init %d %d %d\n", $built_init(1), built_init(1),
    built_init(one));
  printf("built-assigned %d %d %d\n", $built_assigned(1), built_assigned(1),
    built_assigned(one));
  printf("built-argument %d %d %d\n", $built_argument(1), built_argument(1),
    built_argument(one));
  printf("built-returned %d %d %d\n", $built_returned(1), built_returned(1),
    built_returned(one));
  printf("built-var %d %d %d\n", $built_var(1), built_var(1), built_var(one));
  return 0;
}
