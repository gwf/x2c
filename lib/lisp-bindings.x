/*  lisp-bindings.x -- native functions a Lisp session can call

    Copyright (c) 2026 Gary William Flake

    These macros bind a native function into a runtime `Lisp` session under
    a Lisp name, one at a time or as a named group. The function stays an
    ordinary native function: native code calls it directly, and the
    session calls it through a fresh `Func` that carries its signature.
    `lisp/lisp.x` includes this file, so every unit sees the macros.
*/

#pragma once

#include "x2c.x"

/* The C-only declaration of the runtime target table, which reaches the
   Lisp unit without entering any x2c interface. */
meta static List _lisp_native_declarations(void) =>
  %((preproc "extern Map lisp_native_targets(void);"));

/** Declares `lisp_native_targets` to the C compiler alone. */
macro Unit $lisp.native.declarations() { @_lisp_native_declarations() }
