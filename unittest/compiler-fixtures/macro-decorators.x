#include "x2c.x"

macro Decorator $field_identity(Field $target) {
  $target
}

macro Decorator $private_helper(Unit $target) {
  $target
  static int helper = 5;
}

macro Decorator $twice(Stmt $target) {
  $target
  $target
}

macro Decorator $named(Function $function) {
  printf(
    "%s\n",
    $(x2c.literal.string (Code.name $function))
  );
  @(Code.body $function)
}

macro Decorator $return_parameter(
  Function $function,
  Name $parameter
) {
  $(Code.type (Code.parameter $function $parameter)) result =
    $(Code.parameter $function $parameter);
  return result;
}

macro Decorator $return_parameter_direct(
  Function $function,
  Name $parameter
) {
  return $(Code.parameter $function $parameter);
}

typedef struct DecoratedRecord {
  $field_identity()
  int value;
} DecoratedRecord;

$private_helper()
static int private_value = 3;

$named()
$return_parameter(value)
static int decorated_answer(int value) {
  return 0;
}

$named()
$return_parameter_direct(value)
static int *decorated_pointer(int *value) {
  return value;
}

int main(void) {
  DecoratedRecord record = { 7 };
  int *pointer = decorated_pointer(&record.value);
  int count = 0;
  $twice()
  count++;
  printf(
    "%d %d %d %d\n",
    decorated_answer(record.value), *pointer, count, private_value
  );
  return 0;
}
