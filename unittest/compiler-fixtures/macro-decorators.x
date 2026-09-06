#include "x2c.x"

macro Decorator $field_identity(Field $target) => {
  $target
}

macro Decorator $private_helper(Unit $target) using $helper => {
  $target
  static int $helper = 5;
}

macro Decorator $twice(Statement $target) => {
  $target
  $target
}

macro Decorator $named(Function $function) => {
  printf(
    "%s\n",
    $(x2c.literal.string (x2c.function.name $function))
  );
  $(x2c.function.body $function)...
}

macro Decorator $return_parameter(
  Function $function,
  Name $parameter
) => {
  $(x2c.syntax.type (x2c.function.parameter $function $parameter)) result =
    $(x2c.function.parameter $function $parameter);
  return result;
}

macro Decorator $return_parameter_direct(
  Function $function,
  Name $parameter
) => {
  return $(x2c.function.parameter $function $parameter);
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
