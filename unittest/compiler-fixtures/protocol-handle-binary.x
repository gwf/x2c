#include "x2c.x"

/* A handle participant's member takes a `long` operand, so `+` converts
   the other operand to `long` and calls the member, as `+=` does, even
   when that operand is an untyped macro. A typedef that inherits the
   adoption calls the same member. Arithmetic on a pointer that adopts
   nothing stays native C. */
#define STEP 3

typedef struct Acc { long n; } *Acc;

Acc acc_new(long n) {
  Acc a = xmalloc(sizeof(struct Acc));
  a.n = n;
  return a;
}

Acc Acc.add(Acc a, long b) => acc_new(a.n + b);

typedef struct Base { int z; } *Base;

protocol Base(T) {
  T T.add(T, long);
}

protocol Base(Acc);

typedef Acc Ledger;

int main(void) {
  Acc a = acc_new(5);
  Acc b = a + 1;
  Acc s = a + STEP;
  Ledger l = acc_new(7);
  Ledger m = l + 2;
  int values[] = {10, 20, 30};
  int *p = values;
  printf("%ld %ld %ld %d\n", b.n, s.n, m.n, *(p + 1));
  return 0;
}
