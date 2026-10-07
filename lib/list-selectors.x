/*  list-selectors.x -- optional compound `List` selectors

    Copyright (c) 2026 Gary William Flake

    The prelude keeps car, cdr, caar, cadr, cddr, and caddr. Include this
    module for the remaining Common Lisp selector spellings through depth 4.
    Names read from right to left: `a` applies car and `d` applies cdr. Every
    step is `nil`-safe, and selected tails share their canonical `List`
    structure.
*/

#pragma once
#include "x2c.x"

/*  list-selectors.x -- compound List selector templates

    One helper builds a selector's car and cdr chain from its spelling, and
    two templates state the List and Var forms by the selector's last step.
*/

/* `value` with the steps `spelling` names applied right to left: `a` is
   car and `d` is cdr. */
meta static List _selector_chain(String spelling, List value) {
  for (int i = spelling.len() - 2; i >= 1; i--)
    value = spelling[i] == 'a' ? $!( car($value) ) : $!( cdr($value) );
  return value;
}

static macro Unit $selector.car(Name $name) {
  /** Returns the element that `$name` selects from `value`. */
  inline Var List.$name(List value) => $_selector_chain($name, value);
  /** Returns the element that `$name` selects from `value` as a `List`. */
  inline Var Var.$name(Var value) => $_selector_chain($name, value);
}

static macro Unit $selector.cdr(Name $name) {
  /** Returns the tail that `$name` selects from `value`. */
  inline Self List.$name(Self value) => $_selector_chain($name, value);
  /** Returns the tail that `$name` selects from `value` as a `List`. */
  inline List Var.$name(Var value) => $_selector_chain($name, value);
}

/* Each of `steps` once with `a` and once with `d` in front. */
meta static List _selector_double(List steps) {
  if (!steps) return NULL;
  String rest = steps.car(), a = %"a$rest", d = %"d$rest";
  return %($a $d @{_selector_double(steps.cdr())});
}

/* The middle of every selector name two to four steps long, shortest
   first: one doubling of `("")` per step. */
meta static List _selector_middles(void) {
  List level = %(""), middles = NULL;
  for (int length = 1; length <= 4; length++) {
    level = _selector_double(level);
    if (length > 1) middles = middles.append(level);
  }
  return middles;
}

/* The List and Var forms of each selector `middles` names, from the
   template `car` or `cdr` for its last step, except the prelude's caar,
   cadr, cddr, and caddr. */
meta static List _selector_units(List middles, Macro car, Macro cdr) {
  if (!middles) return NULL;
  String middle = middles.car();
  List rest = _selector_units(middles.cdr(), car, cdr);
  if (middle in %("aa" "ad" "dd" "add")) return rest;
  String name = %"c${middle}r";
  return %(${middle.startswith("a") ? car(name) : cdr(name)} @rest);
}

meta static List _selector_definitions(Macro car, Macro cdr) =>
  _selector_units(_selector_middles(), car, cdr);

/* Every selector two to four steps long that the prelude does not define. */
static macro Unit $selectors() {
  @_selector_definitions($selector.car, $selector.cdr)
}

$selectors();
