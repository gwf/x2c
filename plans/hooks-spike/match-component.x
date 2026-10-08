/*  match-component.x -- `match` over static patterns as ordinary control flow

    Including this file registers `static_match` for every bound and typed
    `match` statement that follows. When every arm's pattern is in the
    static subset, the match becomes nested `if` tests over the subject's
    List cells inside `switch (0) { default: ... }`: an arm's `break` leaves
    it, a `continue` reaches the enclosing loop, and a failed arm or guard
    falls through to the next arm, as the built-in lowering does. One cursor
    per List depth walks the cells, and each arm declares its binders from
    the cells it read, so no Match runtime call remains. Any other match is
    declined and compiles as before.

    The static subset, by element of a List pattern:
    - a literal Symbol, compared by its bits;
    - any other literal, such as a number, String, or long Atom, compared
      by `==` with the same element of the runtime pattern;
    - `?` and `?name`; a repeated `?name` compares by `==`;
    - a nested List pattern;
    - a typed capture `?(T name)`, and `(!is type T)`;
    - `*` or `*name` as the last element of its List, once per name.
    Interior stars, guard operators other than `!is type`, computed parts,
    macro-valued cases, and arms between preprocessor directives decline.
*/

#pragma once
#include "meta.x"

/* syntax

   The lowering is built as canonical syntax rather than quotations,
   because each quotation lands as a template application and an arm holds
   dozens of steps. A name is a fresh binder, which the returned code's
   effects replace with its binding, or the identifier of a spelling. */

meta static List _smatch_read(Var name) => %(expr () (ident $name));

meta static List _smatch_call(List receiver, String method) =>
  %(expr () (call (expr () (op . $receiver ($method)))
                  (args (expr (void) ()))));

meta static List _smatch_assign(Var name, List value) =>
  %(stmnt (expr () (op = ${_smatch_read(name)} $value)));

meta static List _smatch_declare_as(String type, Var name, List value) =>
  %(declare ($type) (bindings (op = (bind $name ()) $value)));

meta static List _smatch_and(List left, List right) =>
  %(expr () (op && $left $right));

/* `value.u64 == ((Var) symbol).u64`. */
meta static List _smatch_same(List value, Symbol symbol) {
  List boxed = %(expr () (parens (expr ()
    (cast (decl ("Var") (bindings (bind () ())))
          ${x2c_literal_symbol(symbol)}))));
  return %(expr () (op == (expr () (op . $value ("u64")))
                          (expr () (op . $boxed ("u64")))));
}

/* lowering one arm

   An arm lowers to steps in order: `(test EXPRESSION)` rows the subject
   must pass, and statements that move a cursor or declare a binder. A
   binder is declared by its spelling, as the built-in lowering declares
   it, and `binders` holds those declared so far. */

/* Appends the steps that match the List in cursor `depth` against the List
   pattern `pattern`. `constant` reads the same List of the runtime pattern.
   Only `?` and a binder test that an element is present: `car` of an
   empty List is `void`, which no literal, tag, or List test accepts.
   Returns 0 outside the static subset. */
meta static int _smatch_segment(
  List pattern, List constant, int depth, Array cursors, Array steps,
  Array binders) {
  List cursor = _smatch_read(cursors[depth]);
  for (; pattern; pattern = pattern.cdr()) {
    Var part = pattern.car();
    if (part.is_list_binder()) {
      if (pattern.cdr() || part in binders) return 0;
      if (part != <*>) _smatch_declare(part, cursor, steps, binders);
      return 1;
    }
    if (part.is_atom_binder()) steps.push(%(test $cursor));
    List value = _smatch_call(cursor, "car");
    List literal = _smatch_call(constant, "car");
    if (!_smatch_element(part, value, literal, depth, cursors, steps, binders))
      return 0;
    steps.push(_smatch_assign(cursors[depth], _smatch_call(cursor, "cdr")));
    constant = _smatch_call(constant, "cdr");
  }
  steps.push(%(test (expr () (op ! $cursor))));
  return 1;
}

/* Appends the steps that match the Var `value` against the element `part`.
   `literal` reads the same element of the runtime pattern. */
meta static int _smatch_element(
  Var part, List value, List literal, int depth, Array cursors,
  Array steps, Array binders) {
  if (part == <?>) return 1;
  if (part.is_atom_binder()) {
    if (part in binders) {
      List bound = _smatch_read(x2c_ident(part.str()[1:]));
      steps.push(%(test (expr () (op == $value $bound))));
    }
    else _smatch_declare(part, value, steps, binders);
    return 1;
  }
  if (part is <list>)
    return _smatch_list(
      part, value, literal, depth, cursors, steps, binders);
  if (part.is_match_op() || part == <x2c-dyn>) return 0;
  if (part is <symbol>) steps.push(%(test ${_smatch_same(value, part)}));
  else steps.push(%(test (expr () (op == $value $literal))));
  return 1;
}

/* A typed capture tests the tag before it binds; the runtime matcher reads
   `varray` and `vmap` as `array` and `map`. A nested List pattern walks
   the element with the next cursor. */
meta static int _smatch_list(
  List part, List value, List literal, int depth, Array cursors,
  Array steps, Array binders) {
  Var binder = <?>, Symbol tag = 0;
  match (part) {
    case %((!quote !is) ?name type ?(Symbol named)): {
      binder = name;
      tag = named;
    }
    case %((!quote !is) type ?(Symbol named)): tag = named;
  }
  if (tag) {
    if (tag == <varray>) tag = <array>;
    if (tag == <vmap>) tag = <map>;
    List symbol = x2c_literal_symbol(tag);
    steps.push(%(test (expr () (is-symbol $value $symbol))));
    return binder.is_atom_binder() && _smatch_element(
      binder, value, literal, depth, cursors, steps, binders);
  }
  if (part && part.car().is_match_op()) return 0;
  if (cursors.len() == depth + 1)
    cursors.push(x2c_fresh_name(%"cursor${depth + 1}"));
  List list = x2c_literal_symbol(<list>);
  steps.push(%(test (expr () (is-symbol $value $list))));
  steps.push(_smatch_assign(cursors[depth + 1], _smatch_call(value, "list")));
  return _smatch_segment(
    part, _smatch_call(literal, "list"), depth + 1, cursors, steps, binders);
}

/* Appends the declaration of `binder` from `value`. */
meta static void _smatch_declare(
  Var binder, List value, Array steps, Array binders) {
  String type = binder.is_list_binder() ? "List" : "Var";
  steps.push(_smatch_declare_as(type, x2c_ident(binder.str()[1:]), value));
  binders.push(binder);
}

/* `steps` around the statements `inner`, with each run of tests one `if`. */
meta static List _smatch_nest(Array steps, List inner) {
  for (int i = steps.len(); i-- > 0;) {
    List step = steps[i];
    if (step.car() != <test>) {
      inner = cons(step, inner);
      continue;
    }
    List test = step.cadr();
    for (; i > 0 && ((List) steps[i - 1]).car() == <test>; i--)
      test = _smatch_and(((List) steps[i - 1]).cadr(), test);
    inner = %((if $test (block @inner)));
  }
  return %(block @inner);
}

/* The statement the arm `(pattern body)` lowers to, or NULL outside the
   static subset. The default arm's pattern is `(*)`; a guarded body ends
   with its own `break`. */
meta static List _smatch_arm(List row, Atom selected, Array cursors) {
  List pattern = row.car(), body = row.cadr(), inner = %($body (break));
  match (body) case %(guarded ?statement): inner = %($statement);
  if (pattern.car() == <*>) return %(block @inner);
  Var value = x2c_pattern_value(pattern);
  if (value is not <list> || value.list().car().is_match_op()) return NULL;
  Array steps = [_smatch_assign(cursors[0], _smatch_read(selected))];
  Array binders = [];
  if (!_smatch_segment(value, pattern, 0, cursors, steps, binders))
    return NULL;
  return _smatch_nest(steps, inner);
}

// the hook

/* The control flow `node` becomes, or `node` itself. */
meta List static_match(List node) {
  match (node) case %(match ?subject ?cases): {
    Atom selected = x2c_fresh_name("subject");
    Array cursors = [x2c_fresh_name("cursor0")], arms = [];
    foreach (List row, cases) {
      if (row.car() == <preproc>) return node;
      List arm = _smatch_arm(row, selected, cursors);
      if (!arm) return node;
      arms.push(arm);
    }
    Array code = [_smatch_declare_as("List", selected, subject)];
    Array effects = [x2c_effect_name(selected)];
    foreach (Atom cursor, cursors) {
      code.push(_smatch_declare_as("List", cursor, _smatch_read(selected)));
      effects.push(x2c_effect_name(cursor));
    }
    List zero = x2c_literal_int(0);
    code.push(%(switch $zero (block (default) @{arms.list_free()})));
    return x2c_code(%(block @{code.list_free()}), effects.list_free());
  }
  return node;
}

hook <match> static_match;
