#include <string.h>
#include "meta.x"

macro Decorator $repeat(Expr $count) =>
  macro Decorator(Stmt $body) {
    for (int i = 0; i < $count; i++) $body
  };
keyword repeat $repeat;

macro Decorator $configure(Expr $amount) =>
  macro Decorator(Expr $count) =>
    macro Decorator(Stmt $body) {
      for (int i = 0; i < $count; i++) {
        total += $amount;
        $body
      }
    };
keyword configure $configure;

macro Decorator $shadow(Expr $value) =>
  macro Decorator(Expr $value) =>
    macro Decorator(Stmt $body) { total += $value; $body };
keyword shadow $shadow;

macro Decorator $saved(Expr $amount) =>
  macro Decorator(Stmt $body) using $temporary {
    int $temporary = $amount;
    total += $temporary;
    $body
  };
keyword saved $saved;

meta static Macro factory(void) {
  return macro Decorator(Stmt $body) { total++; $body };
}
macro Decorator $native_factory(Expr $ignored) => $factory();
keyword native_factory $native_factory;
macro Stmt $nested_factory(Stmt $body) { native_factory 0 $body }

meta static List identity_macro(List target) { return target; }
macro Decorator $keep(Macro $target) => $identity_macro($target);

$keep()
macro Decorator $guard(Stmt $body) { total++; $body }

meta static List with_action(List action, List body) =>
  %(seq $(Macro_apply(action, %())) $body);

meta static List apply_one(List maker, List value) =>
  Macro_apply(maker, $(value));
macro Stmt $apply(Macro $maker, Expr $value) => $apply_one($maker, $value);

meta static Macro make_action(void) {
  return macro Stmt() { total++; };
}

macro Decorator $as_guard(Macro $action) =>
  macro Decorator(Stmt $body) { @with_action($action, $body) };

macro Stmt $hit() { total++; }

/* Macro-target stacking reduces the closest decorator first; the outer one
   receives the inner result as a Macro. */
meta static String order = "";
meta static List mark_a(List target) { order = order + "a"; return target; }
meta static List mark_b(List target) { order = order + "b"; return target; }
meta static String read_order(void) { return order; }
macro Decorator $tally_a(Macro $target) => $mark_a($target);
macro Decorator $tally_b(Macro $target) => $mark_b($target);

$tally_a() $tally_b()
macro Decorator $stacked(Stmt $body) { total += 10; $body }

int main(void) {
  int total = 0;
  repeat 3 { total++; }
  if (total != 3) return 1;
  configure 2 3 { total++; }
  if (total != 12) return 2;
  $guard() { total += 2; }
  if (total != 15) return 3;
  $as_guard()
  macro Stmt() { total += 4; }
  { total += 5; }
  if (total != 24) return 4;
  $as_guard() $hit
  { total += 6; }
  if (total != 31) return 5;
  shadow 100 2 { total++; }
  if (total != 34) return 6;
  saved 2 { total++; }
  saved 3 { total++; }
  if (total != 41) return 7;
  native_factory 0 { total += 2; }
  $nested_factory(total += 3;);
  if (total != 48) return 8;
  $as_guard() ($make_action())
  { total += 2; }
  $apply(macro Stmt(Expr $n) { total += $n; }, 2);
  if (total != 53) return 10;
  Macro inert = macro Decorator(Stmt $body) { total = 0; $body };
  (void) inert;
  if (total != 53) return 9;
  $stacked() { total++; }
  if (total != 64) return 11;
  /* A Macro-target decorator over a local definition publishes that local.
     A local decorator without explicit parameters is spelled bare. */
  $keep()
  macro Decorator local_guard(Stmt $body) { total += 2; $body }
  local_guard { total++; }
  if (total != 67) return 13;
  $tally_a() $tally_b()
  macro Decorator local_stacked(Stmt $body) { total += 10; $body }
  local_stacked { total++; }
  if (total != 78) return 14;
  /* File-scope collection and parsing each reduce the pair once. */
  if (strncmp($read_order(), "ba", 2) != 0) return 12;
  puts("decorator continuation ok");
  return 0;
}
