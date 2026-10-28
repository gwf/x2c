/*  meta-native.x -- meta functions and the native code they call

    Copyright (c) 2026 Gary William Flake.

    A bodied `meta` function runs at compile time through a stub that calls
    its compiled copy, and a bodyless `meta` prototype binds a native
    function that the compiler links, a selected native module defines, or
    a linked package supplies. This unit owns those bindings, the region
    summaries a native signature implies, and the native modules, which a
    request loads once per process and never unloads.
*/

#pragma once
#include "compiler/compiler.x"

// The optional modules whose `meta` targets the runtime inventory binds.
#include "diff.x"
#include "digest.x"
#include "json.x"
#include "list-selectors.x"
#include "process.x"
#include "regex.x"
#include "typed-array.x"
#include "typed-list.x"
#include "typed-map.x"
#include "grammar.x"
#include "macros/macros.x"
#include "meta-group/meta-group.x"
#include "meta-sdk/meta-sdk.x"
#include "meta.x"
#include "stage.x"
#include "utils.x"
#include <dlfcn.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* meta-native diagnostics. */

static macro Stmt $fail.meta_native_meta_decl(Expr $c, Expr $site) =>
  $c.report_error(
    <parse>,
    "meta requires a function or one initialized static value",
    $site, NULL);

static macro Stmt $fail.meta_native_meta_storage(
  Expr $c, Expr $site, Expr $name) =>
  $c.report_error(
    <parse>,
    "a meta value must have file-static storage",
    $site, %("declaration: '$($name)'"));

static macro Stmt $fail.meta_native_call_deferred(Expr $c, Expr $site) =>
  $c.report_error(
    <meta-later>,
    "this meta call is left for the translation",
    $site, NULL);

static macro Stmt $fail.meta_native_call_target(Expr $c, Expr $site) =>
  $c.report_error(
    <macro>,
    "explicit meta call cannot be resolved",
    $site, %("only a call to a meta function runs at compile time"));

static macro Stmt $fail.meta_native_call_binding(
  Expr $c, Expr $site, Expr $name) =>
  $c.report_error(
    <macro>,
    "explicit meta call cannot be resolved",
    $site, %("no binding for $($name)"));

static macro Stmt $fail.meta_native_meta_name(Expr $c, Expr $site) =>
  $c.report_error(
    <parse>,
    "native meta function requires one direct name",
    $site, NULL);

static macro Stmt $fail.meta_native_meta_signature(
  Expr $c, Expr $site, Expr $n) =>
  $c.report_error(
    <type>,
    "native meta function declaration does not match its target",
    $site, %("name: $($n.name)" "signature: $($n.signature.repr())"));

static macro Stmt $fail.meta_native_meta_lifetime(
  Expr $c, Expr $site, Expr $name, Expr $signature) =>
  $c.report_error(
    <type>,
    "unproved native meta lifetime",
    $site, %("name: $($name)" "signature: $($signature.repr())"
    "it might return or keep its argument; ownership cannot be inferred"));

static macro Stmt $fail.meta_native_package_platform(
  Expr $c, Expr $site, Expr $name, Expr $module) =>
  $c.report_error(
    <driver>,
    "native modules are not supported on this platform",
    $site, %("package: $($name)" "module: $($module)"));

static macro Stmt $fail.meta_native_package_compiler(
  Expr $c, Expr $site, Expr $name, Expr $module) =>
  $c.report_error(
    <driver>,
    %"package '$($name)' was built by another compiler; rebuild it",
    $site, %("module: $($module)"));

static macro Stmt $fail.meta_native_outside_compilation(Expr $name) =>
  MetaContext.reject(%"$($name) used outside compilation", NULL);

static macro Stmt $warn.meta_native_function_hidden(
  Expr $c, Expr $site, Expr $binding) =>
  $c.report_warning(
    <native>, "the compiler's own function hides a native module's",
    $site, %("name: $($binding.name)"));

static macro Stmt $fail.meta_native_module_invalid(Expr $path) =>
  Diagnostics.driver_error(%"not an x2c native module: $($path)");

static macro Stmt $fail.meta_native_module_compiler(Expr $path) =>
  Diagnostics.driver_error(
    %"native module '$($path)' was built by another compiler; rebuild it");

static macro Stmt $fail.meta_native_compiler_read(Expr $path) =>
  Diagnostics.driver_error(
    %"cannot read the running compiler to check native module '$($path)'");

static macro Stmt $fail.meta_native_module_read(Expr $path, Expr $cause) =>
  Diagnostics.driver_error(%"cannot read native module '$($path)': $($cause)");

static macro Stmt $fail.meta_native_module_load(Expr $path, Expr $cause) =>
  Diagnostics.driver_error(%"cannot load native module '$($path)': $($cause)");

module {
  "modules.x",
  "linked.x",
  "functions.x",
  "calls.x",
  "bindings.x",
}
