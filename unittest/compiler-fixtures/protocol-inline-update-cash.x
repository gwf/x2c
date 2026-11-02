#include "x2c.x"

/* Public inline bodies, which the unit's header carries, call this unit's
   generated update and discard helpers. `protocol-inline-update` calls
   them from another unit. */
typedef struct Cash { long cents; } *Cash;

static int discards;

Cash Cash.new(long cents) {
  Cash cash = xcalloc(1, sizeof(struct Cash));
  cash.cents = cents;
  return cash;
}

Cash Cash.add(Cash a, Cash b) => Cash.new(a.cents + b.cents);

void Cash.discard(Cash cash) {
  discards++;
  xfree(cash);
}

int cash_discards(void) => discards;

typedef struct Arith { int z; } *Arith;

protocol Arith(T) {
  T T.add(T, T);
  void T.discard(T);
}

protocol Arith(Cash);

inline Cash doubled(Cash cash) {
  cash += cash;
  return cash;
}

inline Cash sum3(Cash a, Cash b, Cash c) => a + b + c;
