#include "x2c.x"

// A template's `typeof` of a hole names the argument's type where the
// macro expands, so a method call on the local resolves.
typedef struct Counter { int total; } *Counter;

void Counter.add(Counter counter, int amount) { counter.total += amount; }

static int reads;

static Counter next(Counter counter) {
  reads++;
  return counter;
}

macro Decorator $counted(Stmt $body, Expr $counter, Expr $amount) {
  {
    typeof($counter) owner = $counter;
    owner.add($amount);
    $body
    owner.add($amount);
  }
}

macro Stmt $reset(Expr $counter) {
  typeof_unqual($counter) owner = $counter;
  owner.add(-owner.total);
}

int main(void) {
  struct Counter data = { 0 };
  Counter counter = &data;
  $counted(next(counter), 2) { counter.total += 10; }
  printf("%d %d\n", counter.total, reads);
  const Counter fixed = counter;
  $reset(fixed);
  printf("%d\n", counter.total);
  return 0;
}
