#include "x2c.x"

macro Statement $keep_block(Block $items...) => {
  $items...
}

macro Statement $discard_block(Block $items...) => {
}

macro Statement $unless(Expr $condition, Block $body) => {
  if (!($condition)) $body
}

macro Field $keep_field(Field $fields...) => {
  $fields...
}

macro Field $discard_field(Field $fields...) => {
}

typedef struct MacroFields {
  $discard_field(int removed;);
  $keep_field(int value;);
} MacroFields;

int main(void) {
  int value = 41;
  $discard_block(printf("discarded\n"););
  $keep_block(value += 1;);
  MacroFields fields = { .value = value };
  $unless(value == 42, printf("wrong\n"););
  $unless(value != 42, printf("%d\n", fields.value););
  return 0;
}
