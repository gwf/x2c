/*  twice.x -- two counted loops, verified and ordinary.

    `twice` needs only its invariant and one intermediate assertion.
    `product` multiplies by repeated addition, so its back edge needs one
    ring identity the entailment prover will not find; the companion helper
    in `twice.proofs.x` supplies it. Invariants and assertions are pure
    propositions over program variables: each named variable contributes its
    own ownership frame, and `<name>_v` is its value at that point.
*/

#include "x2c.x"
$(import "../src/cstar.xmacro")

#include <stdio.h>

$cstar.verify("fact(0i <= n && n <= 100i)", "fact(__return == n + n)")
static int twice(int n) {
  int r = 0;
  int i = 0;
  $cstar.invariant(
    "typeof(n, Tint) && typeof(r, Tint) && typeof(i, Tint) && "
    "0i <= i && i <= n && r == i + i && "
    "0i <= n && n <= 100i && n == n__pre"
  )
  while (i < n) {
    r = r + 2;
    i = i + 1;
    $cstar.assert(
      "typeof(n, Tint) && typeof(r, Tint) && typeof(i, Tint) && "
      "0i <= i && i <= n && r == i + i && "
      "0i <= n && n <= 100i && n == n__pre"
    );
  }
  return r;
}

$cstar.verify(
  "fact(1i <= x && x <= 100i && 1i <= y && y <= 100i)",
  "fact(__return == x * y)"
)
static int product(int x, int y) {
  int r = 0;
  $cstar.invariant(
    "typeof(x, Tint) && typeof(y, Tint) && typeof(r, Tint) && "
    "0i <= x && x <= x__pre && y == y__pre && "
    "1i <= x__pre && x__pre <= 100i && 1i <= y__pre && y__pre <= 100i && "
    "r + x * y__pre == x__pre * y__pre"
  )
  while (x > 0) {
    $cstar.helper(twice_step,
      "(r_v + y__pre) + (x_v - 1i) * y__pre == r_v + x_v * y__pre");
    r = r + y;
    x = x - 1;
  }
  return r;
}

int main(void) {
  printf("%d %d %d\n", twice(0), twice(5), product(7, 6));
  return 0;
}
