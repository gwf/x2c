#include "x2c.x"
#include "fields.x"

typedef struct Record { int first, second; Map left, right; } Record;

static Record *visit(Record *record, int *count) {
  (*count)++;
  return record;
}

macro Stmt $copy_pair(Expr $to, Expr $from) {
  $copy_fields($to, $from, first, second);
}

int main(void) {
  Record source = { .first = 7, .second = 9 }, target = {0};
  int reads = 0, writes = 0;
  $copy_fields(visit(&target, &writes), visit(&source, &reads), first, second);
  if (target.first != 7 || target.second != 9 || reads != 2 || writes != 2)
    return 1;

  $copy_pair(visit(&target, &writes), visit(&source, &reads));
  if (target.first != 7 || target.second != 9 || reads != 4 || writes != 4)
    return 5;

  int value = 0;
  $set_fields(visit(&target, &writes), ++value, first, second);
  if (target.first != 1 || target.second != 2 || value != 2 || writes != 6)
    return 2;

  $set_fields(target, {}, left, right);
  target.left["left"] = 42;
  if (target.left == target.right || target.right.len()) return 3;

  $copy_fields(visit(&target, &writes), visit(&source, &reads));
  $set_fields(visit(&target, &writes), ++value);
  if (reads != 4 || writes != 6 || value != 2) return 4;
  return 0;
}
