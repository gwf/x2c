/*  meta-group.x -- a unit's meta group, emitted as C

    Copyright (c) 2026 Gary William Flake.

    A bodied `meta` function a project defines runs as native code: in the
    project's helper program, which the project meta build compiles from
    each unit's `meta` group before translation (`meta-project.x`), or in a
    native module that a session stages in process. This module owns the
    group, from the functions it holds to the C it emits.
*/
#pragma once
#include "compiler.x"

/* In-process staging loads native modules, which these platforms lack. */
#if defined(_WIN32) || defined(__CYGWIN__)
#define X2C_NATIVE_MODULES 0
#else
#define X2C_NATIVE_MODULES 1
#endif

#include "grammar.x"
#include "ast-rewrite.x"
#include "type.x"
#include "generate.x"
#include "macros.x"
#include "utils.x"
#include "toolchain.x"
#include "transform.x"
#include <unistd.h>

// diagnostics

static macro Stmt $fail.meta_group_main_signature(Expr $c, Expr $site) =>
  $c.report_error(
    <type>, "loaded main must take void or (int, char **) and return int",
    $site, NULL);

static macro Stmt $fail.meta_group_function_unavailable(
  Expr $c, Expr $site, Expr $name, Expr $why) {
  $c.report_error(
    <macro>,
    "this function cannot run at compile time",
    $site, %("function: ${$name}" "reason: ${$why}"));
}

// the meta toolchain

/* The C compiler and x2c include directory that build meta code. */
static String meta_cc = NULL, meta_include_dir = NULL;
static Map meta_build_tables = NULL, meta_build_providers = NULL;

module {
  "meta-group/toolchain.x",
  "meta-group/loaded.x",
  "meta-group/selection.x",
  "meta-group/emission.x",
  "meta-group/staging.x",
}
