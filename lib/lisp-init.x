/*  lisp-init.x -- native standard algorithms for every Lisp session

    Copyright (c) 2026 Gary William Flake

    `etc/init.xlisp` binds these operations by name through the `Lisp`
    native target table, so a compile-time session and a runtime `Lisp.new`
    session share them. Each follows the Lisp definition it replaced: nil is
    the empty `List`, truth is any other value, and a list walk reads through
    `lisp_car` and `lisp_cdr` so a nonlist operand raises `<bad-types>`. A
    `String` or `List` operand reads through `_string` or `_list`, which
    raise `<bad-types>` for another tag as the Func adapter does.
*/

#pragma once
$(import "private-keywords.xmacro")
#include "x2c.x"
#include "lisp.x"

static int _nil(Var value) => value == %();

static Var _truth(int x) {
  if (x) return <true>;
  return %();
}

static String _string(Var value, String operation) {
  if (value is not <string>)
    raise %(bad-types (operation $operation) (actual ${value.tag()})
                       (want string));
  return value;
}

static List _list(Var value, String operation) {
  if (value is not <list>)
    raise %(bad-types (operation $operation) (actual ${value.tag()})
                       (want list));
  return value;
}

/* Returns the last element of `values`, or nil when it is nil. */
Var lisp_last(Var values) {
  if (_nil(values)) return values;
  while (!_nil(lisp_cdr(values))) values = lisp_cdr(values);
  return lisp_car(values);
}

/* Returns the value of the last argument, or nil without arguments. */
Var lisp_begin(List values) => lisp_last(values);

/* Returns the first tail of `values` whose head equals `value`, or nil. */
Var lisp_member(Var value, Var values) {
  while (!_nil(values) && lisp_car(values) != value)
    values = lisp_cdr(values);
  return values;
}

/* Returns the first pair in `pairs` whose head equals `key`, or nil.
    Elements that are not pairs are skipped.
*/
Var lisp_assoc(Var key, Var pairs) {
  for (; !_nil(pairs); pairs = lisp_cdr(pairs)) {
    Var pair = lisp_car(pairs);
    if (pair is <list> && !pair.is_nil() && lisp_car(pair) == key)
      return pair;
  }
  return %();
}

static Var _append2(Var left, Var right) {
  List items = NULL;
  for (; !_nil(left); left = lisp_cdr(left))
    items = cons(lisp_car(left), items);
  if (!items) return right;
  List tail = _list(right, "append");
  foreach (Var value, items) tail = cons(value, tail);
  return tail;
}

/* Concatenates its list arguments; the last is shared, not copied. */
Var lisp_append(List lists) {
  if (!lists) return %();
  List reversed = List.reverse(lists);
  Var result = reversed.car();
  foreach (Var left, reversed.cdr())
    result = _append2(left, result);
  return result;
}

/* Returns true when `value` is nil and nil otherwise. */
Var lisp_not(Var value) => _truth(_nil(value));

/* `null?`, the same test as `not` under its own identity. */
Var lisp_null(Var value) => _truth(_nil(value));

Var lisp_sub(Var a, Var b) => a.binary(<->, b);
Var lisp_mul(Var a, Var b) => a.binary(<*>, b);
Var lisp_div(Var a, Var b) => a.binary(</>, b);
Var lisp_mod(Var a, Var b) => a.binary(<%>, b);

Var lisp_caar(Var v) => lisp_car(lisp_car(v));
Var lisp_cadr(Var v) => lisp_car(lisp_cdr(v));
Var lisp_cdar(Var v) => lisp_cdr(lisp_car(v));
Var lisp_cddr(Var v) => lisp_cdr(lisp_cdr(v));
Var lisp_caaar(Var v) => lisp_car(lisp_car(lisp_car(v)));
Var lisp_caadr(Var v) => lisp_car(lisp_car(lisp_cdr(v)));
Var lisp_cadar(Var v) => lisp_car(lisp_cdr(lisp_car(v)));
Var lisp_caddr(Var v) => lisp_car(lisp_cdr(lisp_cdr(v)));
Var lisp_cdaar(Var v) => lisp_cdr(lisp_car(lisp_car(v)));
Var lisp_cdadr(Var v) => lisp_cdr(lisp_car(lisp_cdr(v)));
Var lisp_cddar(Var v) => lisp_cdr(lisp_cdr(lisp_car(v)));
Var lisp_cdddr(Var v) => lisp_cdr(lisp_cdr(lisp_cdr(v)));

/* Returns the bindings of `pat` against `input`, or nil when `input` is
    not a `List` or does not match.
*/
Var lisp_match(Var input, Var pat) {
  if (input is not <list>) return %();
  List list = input;
  return list.match(pat);
}

/* Returns the value bound to `name` in match `bindings`. */
Var lisp_bound(Var bindings, Var name) =>
  lisp_cadr(lisp_assoc(name, bindings));

/* Replaces a whole match of `pat` by `template`, and otherwise every
    matching sublist.
*/
Var lisp_search_replace(Var input, Var pat, Var template) {
  List list = _list(input, "search-replace");
  if (_nil(lisp_match(input, pat)))
    return list.search_replace(pat, template);
  return lisp_match_replace(list, pat, template);
}

/* Returns true when `value` is a pattern binder: a symbol spelled `?`
    or `*` followed by at least one character.
*/
Var lisp_binder(Var value) {
  if (value.kind() != <symbol> && value.tag() != <lsym>) return %();
  String name = value.str();
  return _truth(name.len() > 1 && (name[0] == '?' || name[0] == '*'));
}

/* Returns the binders of `pat` in order, repeats included. */
Var lisp_binders(Var pat) {
  if (pat is not <list>) {
    if (_nil(lisp_binder(pat))) return %();
    return Var.cons(pat, NULL);
  }
  List reversed = NULL;
  for (Var parts = pat; !_nil(parts); parts = lisp_cdr(parts)) {
    List binders = lisp_binders(lisp_car(parts));
    foreach (Var binder, binders) reversed = cons(binder, reversed);
  }
  return reversed.reverse();
}

/* Returns `let` rows binding each of `binders` to its value in the match
    bindings named by `bindings`.
*/
Var lisp_binder_lets(Var bindings, Var binders) {
  List reversed = NULL;
  for (; !_nil(binders); binders = lisp_cdr(binders)) {
    Var name = lisp_car(binders);
    reversed = cons(%($name (bound $bindings (quote $name))), reversed);
  }
  return reversed.reverse();
}

/* Concatenates its `String` arguments; no arguments gives "". */
Var lisp_string_append_all(List strings) {
  Var text = %"";
  foreach (Var s, strings)
    text = lisp_string_append(text, _string(s, "string-append"));
  return text;
}
