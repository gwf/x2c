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
$(import "list-selectors.xmacro")

$selector.cdr(cdar);
$selector.car(caaar);
$selector.car(caadr);
$selector.car(cadar);
$selector.cdr(cdaar);
$selector.cdr(cdadr);
$selector.cdr(cddar);
$selector.cdr(cdddr);
$selector.car(caaaar);
$selector.car(caaadr);
$selector.car(caadar);
$selector.car(caaddr);
$selector.car(cadaar);
$selector.car(cadadr);
$selector.car(caddar);
$selector.car(cadddr);
$selector.cdr(cdaaar);
$selector.cdr(cdaadr);
$selector.cdr(cdadar);
$selector.cdr(cdaddr);
$selector.cdr(cddaar);
$selector.cdr(cddadr);
$selector.cdr(cdddar);
$selector.cdr(cddddr);
