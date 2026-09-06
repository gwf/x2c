// Anonymous aggregates keep the tagless form the source wrote.  The
// compiler's internal gensym key for the missing tag is unit-private
// bookkeeping: emitting it as a C tag made two files compiled in one
// batch share a tag and collide at cc time.
#include "x2c.x"

typedef struct { int a; } AlphaState;
typedef union { int i; unsigned u; } BetaStore;
typedef enum { GAMMA_ONE, GAMMA_TWO } GammaKind;

static int alpha_of(AlphaState *s) { return s->a; }

int main(void) {
  AlphaState alpha = { 7 };
  BetaStore beta;
  beta.i = 3;
  GammaKind kind = GAMMA_TWO;
  printf("%d %d %d\n", alpha_of(&alpha), beta.i, (int) kind);
  return 0;
}
