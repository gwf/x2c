// A template local passed to a nested macro's Name hole is that
// expansion's local, so the nested macro can assign it.
#include "x2c.x"

macro Statement $set(Type $type, name $target) {
  typedef $type S;
  S value = (S) 5;
  $target = value;
}

macro Decorator $bump(Block $target, name $counter) {
  $target
  $counter = $counter + 1;
}

macro Unit $outer(Type $type, name $get) {
  typedef $type S;
  S $get(void) {
    S value = 0;
    $set(S, value);
    $bump(value) { value = value * 2; }
    return value;
  }
}

$outer(int, int_get);
$outer(long, long_get);

int main(void) {
  printf("%d %ld\n", int_get(), long_get());
  return int_get() == 11 && long_get() == 11 ? 0 : 1;
}
