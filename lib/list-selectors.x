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

$selectors();
