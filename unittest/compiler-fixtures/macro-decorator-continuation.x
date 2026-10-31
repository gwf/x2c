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
  puts("decorator continuation ok");
  return 0;
}
