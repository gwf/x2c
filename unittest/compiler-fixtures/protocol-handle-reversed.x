#include "x2c.x"

/* A member whose operand parameter is not the participant takes only a
   right operand, since the operator never commutes: `acc + 1` calls it,
   and `1 + acc` is an error instead of pointer arithmetic. */
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

int main(void) {
  Acc acc = acc_new(5);
  Acc forward = acc + 1;
  Acc reversed = 1 + acc;
  printf("%ld %ld\n", forward.n, reversed.n);
  return 0;
}
