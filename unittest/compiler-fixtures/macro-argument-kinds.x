#include "x2c.x"

macro expression $expression_arg(expr $value) => ($value)

macro Unit $type_arg(Type $type) => {
  static $type $(x2c.ident "typed_value") = 1;
}

macro Unit $declaration_arg(Decl $declaration) => {
  $declaration
}

macro Unit $function_arg(Function $definition) => {
  $definition
}

macro Unit $name_arg(Name $name) => {
  static int $name = 4;
}

macro Unit $name_expression(Name $name, Name $reader) => {
  static int $name = 10;
  static int $reader(void) {
    return $name;
  }
}

macro Expression $literal_arg(Literal $value) => ($value)

macro Unit $parameter_arg(Param $parameter) => {
  static int $(x2c.ident "parameter_value")($parameter) {
    return 6;
  }
}

macro Statement $block_arg(Block $item) => {
  $item
}

macro Field $field_arg(Field $field) => {
  $field
}

macro Unit $unit_arg(Unit $item) => {
  $item
}

macro Unit $unit_sequence(Unit $items...) => {
  $items...
}

$type_arg(unsigned long);
$declaration_arg(static int declaration_value = 2);
$function_arg(static int function_value(void) {
  return 3;
});
$name_arg(named_value);
$name_expression(named_expression, read_named_expression);
$parameter_arg(int ignored);
$unit_arg(static int unit_value = 9;);
$unit_sequence();
$unit_sequence(static int unit_sequence_a = 0;,
               static int unit_sequence_b = 0;);

typedef struct KindRecord {
  $field_arg(int field_value;);
} KindRecord;

int main(void) {
  int block_value = 0;
  $block_arg(block_value += 7;);
  KindRecord record = { .field_value = 8 };
  int total = (int) typed_value + declaration_value +
              function_value() + named_value +
              $literal_arg(5) + parameter_value(0) +
              block_value + record.field_value + unit_value +
              named_expression + read_named_expression();
  printf("%d\n", $expression_arg(total));
  return 0;
}
