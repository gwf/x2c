/*  meta-differential.x -- the two forms of a `meta` function answer alike

    Each row prints the answer an explicit `$` call produced during
    translation beside the answer the emitted function produced for the
    same call with a run-time argument, so a disagreement between the
    compile-time form and the run-time form shows up as a pair whose two
    numbers differ. The run-time argument is derived from `argc`, which the
    C compiler cannot fold.
    See `plans/meta-functions.md`.
*/

#include "x2c.x"

$(import "meta-differential.xmacro")

/* `runtime_zero` is zero, and `main` takes it from `argc` so the C
   compiler cannot fold it. Each row passes the compile-time answer and the
   same call through it, so the two columns are the two forms. */
static int runtime_zero = 0;

macro Statement $row(Literal $label, Expr $translated, Expr $run) {
  printf("%-9s %d %d\n", $label, $translated, $run);
}

int main(int argc, char **argv) {
  runtime_zero = argc - 1;
  (void) argv;
  $row("d_cast", $d_cast(100), d_cast(100 + runtime_zero));
  $row("d_short", $d_short(70000), d_short(70000 + runtime_zero));
  $row("d_char", $d_char(0), d_char(0 + runtime_zero));
  $row("d_uchar", $d_uchar(100), d_uchar(100 + runtime_zero));
  $row("d_wrap", $d_wrap(0), d_wrap(0 + runtime_zero));
  $row("d_unsigned", $d_unsigned(2), d_unsigned(2 + runtime_zero));
  $row("d_udiv", $d_udiv(0), d_udiv(0 + runtime_zero));
  $row("d_sdiv", $d_sdiv(0), d_sdiv(0 + runtime_zero));
  $row("d_smod", $d_smod(0), d_smod(0 + runtime_zero));
  $row("d_shift", $d_shift(0), d_shift(0 + runtime_zero));
  $row("d_lshift", $d_lshift(1), d_lshift(1 + runtime_zero));
  $row("d_wide", $d_wide(0), d_wide(0 + runtime_zero));
  $row("d_charlit", $d_charlit(0), d_charlit(0 + runtime_zero));
  $row("d_escape", $d_escape(0), d_escape(0 + runtime_zero));
  $row("d_dtruth", $d_dtruth(0), d_dtruth(0 + runtime_zero));
  $row("d_deq", $d_deq(0), d_deq(0 + runtime_zero));
  $row("d_dcmp", $d_dcmp(0), d_dcmp(0 + runtime_zero));
  $row("d_trunc", $d_trunc(0), d_trunc(0 + runtime_zero));
  $row("d_widen", $d_widen(1), d_widen(1 + runtime_zero));
  $row("d_fsuffix", $d_fsuffix(0), d_fsuffix(0 + runtime_zero));
  $row("d_fhex", $d_fhex(0), d_fhex(0 + runtime_zero));
  $row("d_fround", $d_fround(0), d_fround(0 + runtime_zero));
  $row("d_ternary", $d_ternary(0), d_ternary(0 + runtime_zero));
  $row("d_and", $d_and(0), d_and(0 + runtime_zero));
  $row("d_or", $d_or(0), d_or(0 + runtime_zero));
  $row("d_loop", $d_loop(0), d_loop(0 + runtime_zero));
  $row("d_while", $d_while(0), d_while(0 + runtime_zero));
  $row("d_switch", $d_switch(1), d_switch(1 + runtime_zero));
  $row("d_listget", $d_listget(0), d_listget(0 + runtime_zero));
  $row("d_lambda", $d_lambda(0), d_lambda(0 + runtime_zero));
  return 0;
}
