/*  lisp-bindings.x -- native functions a Lisp session can call

    Copyright (c) 2026 Gary William Flake

    These macros bind a native function into a runtime `Lisp` session under
    a Lisp name, one at a time or as a named group. The function stays an
    ordinary native function: native code calls it directly, and the
    session calls it through a fresh `Func` that carries its signature.
    `lisp/lisp.x` includes this file, so every unit sees the macros.
*/

#pragma once

#include "meta.x"
#include "compiler-meta.x"

/** Binds `function` into the session `lisp` as `name` through a fresh
    `Func` carrying the function's signature. */
macro Stmt $lisp.bind(Expr $lisp, Expr $name, Expr $function) {
  Func callable = Func.new(
    $function, $_x2c_literal_list($Code.native_signature($function)));
  Lisp.bind($lisp, $name, callable);
}

/** Records the decorated function as `name` in the binding group `group`,
    which `$lisp.install` binds into a session. */
macro Decorator $lisp.binding(
  Function $function, Name $group, Literal $name
) {
  @_x2c_binding_record($group, $name, $function)
  @Code.body($function)
}

/** Binds every function recorded in `group` into the session `lisp`. */
macro Stmt $lisp.install(Expr $lisp, Name $group) {
  @_x2c_binding_install($lisp, $group)
}

/* The C-only declaration of the runtime target table, which reaches the
   Lisp unit without entering any x2c interface. */
meta static List _lisp_native_declarations(void) =>
  %((preproc "extern Map lisp_native_targets(void);"));

/** Declares `lisp_native_targets` to the C compiler alone. */
macro Unit $lisp.native.declarations() { @_lisp_native_declarations() }
