#include "x2c.x"

typedef unsigned char Byte;
typedef int Int;
struct Item { int number; };

$(import "meta-func-calls.xmacro")

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
