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

/** Returns `cdr(car(value))`. */
inline Self List.cdar(Self value) => cdr(car(value));
/** Returns `car(car(car(value)))`. */
inline Var List.caaar(List value) => car(car(car(value)));
/** Returns `car(car(cdr(value)))`. */
inline Var List.caadr(List value) => car(car(cdr(value)));
/** Returns `car(cdr(car(value)))`. */
inline Var List.cadar(List value) => car(cdr(car(value)));
/** Returns `cdr(car(car(value)))`. */
inline Self List.cdaar(Self value) => cdr(car(car(value)));
/** Returns `cdr(car(cdr(value)))`. */
inline Self List.cdadr(Self value) => cdr(car(cdr(value)));
/** Returns `cdr(cdr(car(value)))`. */
inline Self List.cddar(Self value) => cdr(cdr(car(value)));
/** Returns `cdr(cdr(cdr(value)))`. */
inline Self List.cdddr(Self value) => cdr(cdr(cdr(value)));

/** Returns `car(car(car(car(value))))`. */
inline Var List.caaaar(List value) => car(car(car(car(value))));
/** Returns `car(car(car(cdr(value))))`. */
inline Var List.caaadr(List value) => car(car(car(cdr(value))));
/** Returns `car(car(cdr(car(value))))`. */
inline Var List.caadar(List value) => car(car(cdr(car(value))));
/** Returns `car(car(cdr(cdr(value))))`. */
inline Var List.caaddr(List value) => car(car(cdr(cdr(value))));
/** Returns `car(cdr(car(car(value))))`. */
inline Var List.cadaar(List value) => car(cdr(car(car(value))));
/** Returns `car(cdr(car(cdr(value))))`. */
inline Var List.cadadr(List value) => car(cdr(car(cdr(value))));
/** Returns `car(cdr(cdr(car(value))))`. */
inline Var List.caddar(List value) => car(cdr(cdr(car(value))));
/** Returns `car(cdr(cdr(cdr(value))))`. */
inline Var List.cadddr(List value) => car(cdr(cdr(cdr(value))));
/** Returns `cdr(car(car(car(value))))`. */
inline Self List.cdaaar(Self value) => cdr(car(car(car(value))));
/** Returns `cdr(car(car(cdr(value))))`. */
inline Self List.cdaadr(Self value) => cdr(car(car(cdr(value))));
/** Returns `cdr(car(cdr(car(value))))`. */
inline Self List.cdadar(Self value) => cdr(car(cdr(car(value))));
/** Returns `cdr(car(cdr(cdr(value))))`. */
inline Self List.cdaddr(Self value) => cdr(car(cdr(cdr(value))));
/** Returns `cdr(cdr(car(car(value))))`. */
inline Self List.cddaar(Self value) => cdr(cdr(car(car(value))));
/** Returns `cdr(cdr(car(cdr(value))))`. */
inline Self List.cddadr(Self value) => cdr(cdr(car(cdr(value))));
/** Returns `cdr(cdr(cdr(car(value))))`. */
inline Self List.cdddar(Self value) => cdr(cdr(cdr(car(value))));
/** Returns `cdr(cdr(cdr(cdr(value))))`. */
inline Self List.cddddr(Self value) => cdr(cdr(cdr(cdr(value))));

/** Returns `cdr(car(value))` after treating `value` as a `List`. */
inline List Var.cdar(Var value) => cdr(car(value));
/** Returns `car(car(car(value)))` after treating `value` as a `List`. */
inline Var Var.caaar(Var value) => car(car(car(value)));
/** Returns `car(car(cdr(value)))` after treating `value` as a `List`. */
inline Var Var.caadr(Var value) => car(car(cdr(value)));
/** Returns `car(cdr(car(value)))` after treating `value` as a `List`. */
inline Var Var.cadar(Var value) => car(cdr(car(value)));
/** Returns `cdr(car(car(value)))` after treating `value` as a `List`. */
inline List Var.cdaar(Var value) => cdr(car(car(value)));
/** Returns `cdr(car(cdr(value)))` after treating `value` as a `List`. */
inline List Var.cdadr(Var value) => cdr(car(cdr(value)));
/** Returns `cdr(cdr(car(value)))` after treating `value` as a `List`. */
inline List Var.cddar(Var value) => cdr(cdr(car(value)));
/** Returns `cdr(cdr(cdr(value)))` after treating `value` as a `List`. */
inline List Var.cdddr(Var value) => cdr(cdr(cdr(value)));

/** Returns `car(car(car(car(value))))` after treating `value` as a `List`. */
inline Var Var.caaaar(Var value) => car(car(car(car(value))));
/** Returns `car(car(car(cdr(value))))` after treating `value` as a `List`. */
inline Var Var.caaadr(Var value) => car(car(car(cdr(value))));
/** Returns `car(car(cdr(car(value))))` after treating `value` as a `List`. */
inline Var Var.caadar(Var value) => car(car(cdr(car(value))));
/** Returns `car(car(cdr(cdr(value))))` after treating `value` as a `List`. */
inline Var Var.caaddr(Var value) => car(car(cdr(cdr(value))));
/** Returns `car(cdr(car(car(value))))` after treating `value` as a `List`. */
inline Var Var.cadaar(Var value) => car(cdr(car(car(value))));
/** Returns `car(cdr(car(cdr(value))))` after treating `value` as a `List`. */
inline Var Var.cadadr(Var value) => car(cdr(car(cdr(value))));
/** Returns `car(cdr(cdr(car(value))))` after treating `value` as a `List`. */
inline Var Var.caddar(Var value) => car(cdr(cdr(car(value))));
/** Returns `car(cdr(cdr(cdr(value))))` after treating `value` as a `List`. */
inline Var Var.cadddr(Var value) => car(cdr(cdr(cdr(value))));
/** Returns `cdr(car(car(car(value))))` after treating `value` as a `List`. */
inline List Var.cdaaar(Var value) => cdr(car(car(car(value))));
/** Returns `cdr(car(car(cdr(value))))` after treating `value` as a `List`. */
inline List Var.cdaadr(Var value) => cdr(car(car(cdr(value))));
/** Returns `cdr(car(cdr(car(value))))` after treating `value` as a `List`. */
inline List Var.cdadar(Var value) => cdr(car(cdr(car(value))));
/** Returns `cdr(car(cdr(cdr(value))))` after treating `value` as a `List`. */
inline List Var.cdaddr(Var value) => cdr(car(cdr(cdr(value))));
/** Returns `cdr(cdr(car(car(value))))` after treating `value` as a `List`. */
inline List Var.cddaar(Var value) => cdr(cdr(car(car(value))));
/** Returns `cdr(cdr(car(cdr(value))))` after treating `value` as a `List`. */
inline List Var.cddadr(Var value) => cdr(cdr(car(cdr(value))));
/** Returns `cdr(cdr(cdr(car(value))))` after treating `value` as a `List`. */
inline List Var.cdddar(Var value) => cdr(cdr(cdr(car(value))));
/** Returns `cdr(cdr(cdr(cdr(value))))` after treating `value` as a `List`. */
inline List Var.cddddr(Var value) => cdr(cdr(cdr(cdr(value))));
