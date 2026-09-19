/*  meta-differential.x -- the two forms of a `meta` function answer alike

    Each row prints the answer a folded constant call produced beside the
    answer the emitted function produced for the same call with a run-time
    argument, so a disagreement between the compile-time form and the
    run-time form shows up as a pair whose two numbers differ. The run-time
    argument is derived from `argc`, which the C compiler cannot fold.
    See `plans/meta-functions.md`.
*/

#include "x2c.x"

/* Conversion positions: a cast, a declaration, an assignment and a
   return each narrow to the type that was written. */
meta static int d_cast(int n) => (unsigned char) (n + 200);
meta static int d_short(int n) { short s = n; return s; }
meta static int d_char(int n) { char c = 200 + n; return c; }
meta static int d_uchar(int n) { unsigned char c = 0; c = n + 200; return c; }
meta static int d_wrap(int n) { short s = 1; s += 40000 + n; return s; }

/* Unsignedness follows the operand types, so a difference wraps and a
   comparison and a division read the wrapped value as unsigned. */
meta static int d_unsigned(int n) { unsigned u = n; u = u - 5; return u > 100; }
meta static int d_udiv(int n) { unsigned u = n - 5; return (int) (u / 3); }

/* Signed division and remainder truncate toward zero, and a signed right
   shift keeps the sign. */
meta static int d_sdiv(int n) => (n - 7) / 2;
meta static int d_smod(int n) => (n - 7) % 2;
meta static int d_shift(int n) => (n - 8) >> 1;
meta static int d_lshift(int n) => (n + 3) << 3;

/* A product that does not fit an `int` is computed as a `long` and
   truncated by the cast back. */
meta static int d_wide(int n) {
  long w = (long) (n + 100000) * 100000;
  return (int) w;
}

/* A character literal is its code. */
meta static int d_charlit(int n) => 'A' + n;
meta static int d_escape(int n) => '\n' + n;

/* Floating values: truth at zero, equality against an `int`, truncation
   toward zero, and an `int` widening into a division. */
meta static int d_dtruth(int n) { double d = n; if (d) return 1; return 0; }
meta static int d_deq(int n) { double d = 1.0 + n; return d == 1; }
meta static int d_dcmp(int n) { double d = n - 1; return d < 0; }
meta static int d_trunc(int n) { double d = -7.9 + n; return (int) d; }
meta static int d_widen(int n) { double d = n + 1; return (int) (d / 2.0 * 6); }

/* Control flow: a conditional, the short-circuit operators, a loop with
   both of its exits, and a switch. */
meta static int d_ternary(int n) => n ? 10 : 20;
meta static int d_and(int n) => (n + 1) && (n - 1);
meta static int d_or(int n) => n || (n + 2);

meta static int d_loop(int n) {
  int total = 0;
  for (int i = 0; i < 10 + n; i++) {
    if (i == 3) continue;
    if (i == 7) break;
    total += i;
  }
  return total;
}

meta static int d_while(int n) {
  int i = n, total = 0;
  while (i < 5) {
    total = total * 2 + i;
    i++;
  }
  return total;
}

meta static int d_switch(int n) {
  switch (n) {
    case 0: return 100;
    case 1: return 200;
    default: return 300;
  }
}

/* `runtime_zero` is zero, and `main` takes it from `argc` so neither
   compiler can fold it. `$row` prints the folded constant call beside the
   same call through it, so the two columns are the two forms. */
static int runtime_zero = 0;

macro Statement $row(Literal $label, Name $name, Expr $argument) => {
  printf("%-9s %d %d\n", $label, $name($argument), $name($argument + runtime_zero));
}

int main(int argc, char **argv) {
  runtime_zero = argc - 1;
  (void) argv;
  $row("d_cast", d_cast, 100);
  $row("d_short", d_short, 70000);
  $row("d_char", d_char, 0);
  $row("d_uchar", d_uchar, 100);
  $row("d_wrap", d_wrap, 0);
  $row("d_unsigned", d_unsigned, 2);
  $row("d_udiv", d_udiv, 0);
  $row("d_sdiv", d_sdiv, 0);
  $row("d_smod", d_smod, 0);
  $row("d_shift", d_shift, 0);
  $row("d_lshift", d_lshift, 1);
  $row("d_wide", d_wide, 0);
  $row("d_charlit", d_charlit, 0);
  $row("d_escape", d_escape, 0);
  $row("d_dtruth", d_dtruth, 0);
  $row("d_deq", d_deq, 0);
  $row("d_dcmp", d_dcmp, 0);
  $row("d_trunc", d_trunc, 0);
  $row("d_widen", d_widen, 1);
  $row("d_ternary", d_ternary, 0);
  $row("d_and", d_and, 0);
  $row("d_or", d_or, 0);
  $row("d_loop", d_loop, 0);
  $row("d_while", d_while, 0);
  $row("d_switch", d_switch, 1);
  return 0;
}
