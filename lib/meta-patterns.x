/*  meta-patterns.x -- static patterns as tests a component writes

    Copyright (c) 2026 Gary William Flake

    A `match` arm or `catch` filter holds its pattern as a bound expression,
    and `x2c_pattern_value` reads it as data. For a pattern in the static
    subset below, `x2c_pattern_steps` writes the tests and binder
    declarations that match a subject against it, and `x2c_pattern_nest`
    makes them one block, so a component lowers the pattern to ordinary
    control flow with no `Match` call. Include this file where such a
    component is written; the compiler links these definitions for its
    own components.
*/

#pragma once
#include "meta.x"

/** Returns `(STEPS BINDERS CURSORS)` that match the List the fresh name
    `subject` holds against the bound List pattern `pattern`, or NULL when
    the pattern is outside the static subset below.

    A step is `(test EXPRESSION)`, which must hold, or a statement that
    moves a cursor or declares a binder; `x2c_pattern_nest` makes a block
    of them. BINDERS lists each named binder the steps declare, in order of
    first appearance, which is the order of `Match` captures; `?name` is
    declared by its spelling as a `Var`, `*name` as a `List`. CURSORS lists
    one fresh name per List depth the steps walk, which the caller declares
    as a `List` before they run. Every pattern names the same cursor at the
    same depth, so patterns tested in turn share the longest CURSORS.

    The static subset, by element of a List pattern:
    - a literal Symbol, compared by its bits;
    - any other literal, such as a number, String, or long Atom, compared
      by `==` with the same element of the List `pattern` builds;
    - `?` and `?name`; a repeated `?name` compares by `==`;
    - a nested List pattern;
    - a typed capture `?(T name)`, and `(!is type T)`;
    - `*` or `*name` as the last element of its List, once per name.
    Interior stars, other guard operators, and computed parts are outside
    it. */
meta List x2c_pattern_steps(List pattern, Atom subject) {
  Var value = x2c_pattern_value(pattern);
  if (value is not <list> || value.list().car().is_match_op()) return NULL;
  Array cursors = [x2c_fresh_name("cursor0")], binders = [];
  Array steps = [_pattern_assign(cursors[0], _pattern_read(subject))];
  if (!_pattern_segment(value, pattern, 0, cursors, steps, binders))
    return NULL;
  return %(${steps.list_free()} ${binders.list_free()}
           ${cursors.list_free()});
}

/** Returns the block that runs the statements `inner` when every test of
    `steps`, from `x2c_pattern_steps`, holds. Each run of tests is one
    `if`, and a failed test leaves the block. */
meta List x2c_pattern_nest(List steps, List inner) {
  if (!steps) return x2c_block_make(inner);
  List step = steps.car();
  if (step.car() != <test>)
    return x2c_block_make(
      cons(step, x2c_pattern_nest(steps.cdr(), inner).cdr()));
  Array tests = [];
  for (; steps && steps.car().list().car() == <test>; steps = steps.cdr())
    tests.push(steps.car().list().cadr());
  List test = tests.take_last(), body = x2c_pattern_nest(steps, inner);
  while (tests.len()) test = %(expr () (op && ${tests.take_last()} $test));
  return x2c_block_make(%((if $test $body)));
}

/* The lowering is built as canonical syntax rather than quotations,
   because each quotation lands as a template application and a pattern
   holds dozens of steps. A name is a fresh name, which the caller's
   effects replace with its binding, or the identifier of a spelling. */

meta static List _pattern_read(Var name) => %(expr () (ident $name));

meta static List _pattern_call(List receiver, String method) =>
  %(expr () (call (expr () (op . $receiver ($method)))
                  (args (expr (void) ()))));

meta static List _pattern_assign(Var name, List value) =>
  %(stmnt (expr () (op = ${_pattern_read(name)} $value)));

/* `value.u64 == ((Var) symbol).u64`. */
meta static List _pattern_same(List value, Symbol symbol) {
  List boxed = %(expr () (parens (expr ()
    (cast (decl ("Var") (bindings (bind () ())))
          ${x2c_literal_symbol(symbol)}))));
  return %(expr () (op == (expr () (op . $value ("u64")))
                          (expr () (op . $boxed ("u64")))));
}

/* Appends the steps that match the List in cursor `depth` against the List
   pattern `pattern`. `constant` builds the same List of the runtime
   pattern. Only `?` and a binder test that an element is present: `car`
   of an empty List is `void`, which no literal, tag, or List test
   accepts. Returns 0 outside the static subset. */
meta static int _pattern_segment(
  List pattern, List constant, int depth, Array cursors, Array steps,
  Array binders) {
  List cursor = _pattern_read(cursors[depth]);
  for (; pattern; pattern = pattern.cdr()) {
    Var part = pattern.car();
    if (part.is_list_binder()) {
      if (pattern.cdr() || part in binders) return 0;
      if (part != <*>) _pattern_declare(part, cursor, steps, binders);
      return 1;
    }
    if (part.is_atom_binder()) steps.push(%(test $cursor));
    List value = _pattern_call(cursor, "car");
    List (literal, rest) = _pattern_parts(constant);
    if (!_pattern_element(
          part, value, literal, depth, cursors, steps, binders))
      return 0;
    steps.push(_pattern_assign(cursors[depth], _pattern_call(cursor, "cdr")));
    constant = rest;
  }
  steps.push(%(test (expr () (op ! $cursor))));
  return 1;
}

/* Appends the steps that match the Var `value` against the element `part`.
   `literal` builds the same element of the runtime pattern. */
meta static int _pattern_element(
  Var part, List value, List literal, int depth, Array cursors,
  Array steps, Array binders) {
  if (part == <?>) return 1;
  if (part.is_atom_binder()) {
    if (part in binders) {
      List bound = _pattern_read(x2c_ident(part.str()[1:]));
      steps.push(%(test (expr () (op == $value $bound))));
    }
    else _pattern_declare(part, value, steps, binders);
    return 1;
  }
  if (part is <list>)
    return _pattern_list(
      part, value, literal, depth, cursors, steps, binders);
  if (part.is_match_op() || part == <x2c-dyn>) return 0;
  if (part is <symbol>) steps.push(%(test ${_pattern_same(value, part)}));
  else steps.push(%(test (expr () (op == $value $literal))));
  return 1;
}

/* A typed capture tests the tag before it binds; the runtime matcher reads
   `varray` and `vmap` as `array` and `map`. A nested List pattern walks
   the element with the next cursor. */
meta static int _pattern_list(
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
    return binder.is_atom_binder() && _pattern_element(
      binder, value, literal, depth, cursors, steps, binders);
  }
  if (part && part.car().is_match_op()) return 0;
  if (cursors.len() == depth + 1)
    cursors.push(x2c_fresh_name(%"cursor${depth + 1}"));
  List list = x2c_literal_symbol(<list>);
  steps.push(%(test (expr () (is-symbol $value $list))));
  steps.push(
    _pattern_assign(cursors[depth + 1], _pattern_call(value, "list")));
  return _pattern_segment(
    part, _pattern_sublist(literal), depth + 1, cursors, steps, binders);
}

/* The element and the rest of the List expression `constant`: the parts
   of a `cons` it builds, or calls that read them from a List built once,
   such as a cached literal. */
meta static List _pattern_parts(List constant) {
  match (_pattern_built(constant))
    case %(cons ?element ?rest): return %($element $rest);
  return %(${_pattern_call(constant, "car")}
           ${_pattern_call(constant, "cdr")});
}

meta static List _pattern_built(List expression) {
  match (expression)
    case %(expr ? ?(List built)): return _pattern_built(built);
  return expression;
}

/* The List expression a static pattern's element `literal` converts to a
   Var, or a call that reads it. */
meta static List _pattern_sublist(List literal) {
  match (literal)
    case %(expr ? (call ? (args (!set ?list (expr ("List") *))))):
      return list;
  return _pattern_call(literal, "list");
}

/* Appends the declaration of `binder` from `value`. */
meta static void _pattern_declare(
  Var binder, List value, Array steps, Array binders) {
  String type = binder.is_list_binder() ? "List" : "Var";
  List name = x2c_ident(binder.str()[1:]);
  steps.push(%(declare ($type) (bindings (op = (bind $name ()) $value))));
  binders.push(binder);
}
