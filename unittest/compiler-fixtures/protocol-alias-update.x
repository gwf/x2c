#include "x2c.x"

/* A typedef that inherits its ancestor's adoption updates through the
   ancestor's members: `+=`, prefix and postfix `++`, and `--` call them
   instead of moving the pointer. */
typedef struct Acc { long n; } *Acc;

Acc acc_new(long n) {
  Acc a = xmalloc(sizeof(struct Acc));
  a.n = n;
  return a;
}

Acc Acc.add(Acc a, long b) => acc_new(a.n + b);

Acc Acc.sub(Acc a, long b) => acc_new(a.n - b);

typedef struct Base { int z; } *Base;

protocol Base(T) {
  T T.add(T, long);
  T T.sub(T, long);
}

protocol Base(Acc);

typedef Acc Ledger;

int main(void) {
  Ledger l = acc_new(5);
  Ledger before = l++;
  ++l;
  l += 10;
  l--;
  printf("%ld %ld\n", before.n, l.n);
  return 0;
}
