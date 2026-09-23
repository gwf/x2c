// A visible template local passed to a nested macro's Name hole is that
// expansion's local, so the nested macro can assign it. An outer name keeps
// its binding, and a member position receives the written spelling.
#include "x2c.x"

typedef struct { int value; } Cell;
Cell cell = {7};
int counter = 10;

macro Statement $set(Type $type, name $target) {
  typedef $type S;
  S value = (S) 5;
  $target = value;
}

macro Decorator $bump(Block $target, name $counter) {
  $target
  $counter = $counter + 1;
}

macro Expression $field(name $object, name $member) => $object.$member;

macro Unit $box(name $member) {
  struct Box { int $member; };
}

macro Unit $outer(Type $type, name $get, name $count, name $read) {
  static int value = 2;
  $box(value);
  typedef $type S;
  S $get(void) {
    S value = 0;
    $set(S, value);
    $bump(value) { value = value * 2; }
    return value;
  }
  int $count(void) {
    int counter = 1;
    $bump(counter) {}
    return counter;
  }
  int $read(void) {
    struct Box box = {5};
    $bump(counter) {}
    return box.value + value + $field(cell, value) + counter;
  }
}

$outer(int, int_get, int_count, int_read);

int main(void) {
  int get = int_get(), count = int_count(), read = int_read();
  printf("%d %d %d\n", get, count, read);
  return get == 11 && count == 2 && read == 25 ? 0 : 1;
}
