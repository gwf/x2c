#include "x2c.x"

/* The unit's compile-time group holds the helper that discards an
   operator's temporary, for a public function and for a `meta` function
   the translation runs, together with the static `discard` member that
   only the helper calls. */
typedef struct Big { long n; } *Big;

static int discards;

Big big_new(long n) {
  Big b = xmalloc(sizeof(struct Big));
  b.n = n;
  return b;
}

Big Big.add(Big a, Big b) => big_new(a.n + b.n);

static void Big.discard(Big a) {
  discards++;
  xfree(a);
}

typedef struct Base { int z; } *Base;

protocol Base(T) {
  T T.add(T, T);
  void T.discard(T);
}

protocol Base(Big);

long total3(long x, long y, long z) {
  Big a = big_new(x), b = big_new(y), c = big_new(z);
  Big sum = a + b + c;
  return sum.n;
}

meta long folded(long x) {
  Big a = big_new(x), b = big_new(2), c = big_new(3);
  Big sum = a + b + c;
  return sum.n * 10 + discards;
}

int main(void) {
  printf("%ld %ld %d\n", total3(1, 2, 3), $folded(1), discards);
  return 0;
}
