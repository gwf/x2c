#include "x2c.x"

struct BorrowedField { int value; };

meta int *borrow_field(struct BorrowedField *record) {
  return &record->value;
}

meta int pointer_return_probe(int offset) {
  struct BorrowedField record = { .value = 7 + offset };
  int *field = borrow_field(&record);
  struct BorrowedField other = { .value = 100 };
  *borrow_field(&other) += 1;
  *field += 5;
  return record.value + other.value;
}

int main(int argc, char **argv) {
  (void) argv;
  printf("%d %d\n", $pointer_return_probe(0),
         pointer_return_probe(argc - 1));
  return 0;
}
