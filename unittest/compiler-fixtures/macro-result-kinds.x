#include "x2c.x"

macro Expression $expression_result() => (10)

macro Statement $block_result(Expr $target, Expr $amount) => {
  $target += $amount;
}

macro Field $field_result() => {
  int generated_field;
}

macro Unit $unit_result() => {
  static int $(x2c.ident "unit_value") = 12;
}

$unit_result();

typedef struct ResultRecord {
  $field_result();
} ResultRecord;

int main(void) {
  int value = $expression_result();
  $block_result(value, 20);
  ResultRecord record = { 12 };
  (void) record;
  printf("%d\n", value + unit_value);
  return 0;
}
