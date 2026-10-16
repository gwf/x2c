/*  collect.x -- source-ordered shallow symbol collection and replay

    Raw collection scans includes without running cpp. Each cold walk
    records declaration maps and included paths at their source positions;
    cache and interface replay consume that same order so declaration
    precedence does not depend on whether a file was already collected. A
    translated unit writes its own contribution beside its generated C as a
    `.xi` interface, and the runtime prelude is `lib/x2c.xi`. The compiler's
    own prelude components are linked into it as the records their
    interfaces would hold.
*/

#pragma once
#include "compiler.x"

#include "ast-rewrite.x"
#include "buffer.x"
#include "datum.x"
#include "utils.x"

#include <ctype.h>
#include <errno.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

// diagnostics

static macro Stmt $fail.collect_runtime_read(
  Expr $c, Expr $site, Expr $runtime) {
  $c.report_error(
    <driver>,
    "cannot read runtime source",
    $site, %("path: ${$runtime}"));
}

static macro Stmt $fail.collect_include_read(
  Expr $c, Expr $site, Expr $target, Expr $path) {
  $c.report_error(
    <driver>,
    "cannot read include",
    $site, %("stage: collect" "include: ${$target}" "path: ${$path}"));
}

static macro Stmt $fail.collect_package_unknown(
  Expr $c, Expr $site, Expr $name) {
  $c.report_error(
    <driver>,
    %"unknown package '${$name}'",
    $site, %( "searched: <root>/${$name}/src/${$name}.{x,xp}, <root>/${$name}/${$name}.{x,xp}" ));
}

static macro Stmt $fail.collect_package_read(
  Expr $c, Expr $site, Expr $package, Expr $entry) {
  $c.report_error(
    <driver>,
    %"cannot read package '${$package.package}'",
    $site, %( "path: ${$entry}" ));
}

static macro Stmt $fail.collect_package_prefix(
  Expr $c, Expr $site, Expr $name, Expr $spelling, Expr $unit, Expr $fix) {
  $c.report_error(
    <driver>,
    %"package '${$name}' exposes unprefixed top-level declaration '${$spelling}'",
    $site, %( "'${$unit}' is x2c source outside the package; include it ${$fix}" ));
}

static macro Stmt $fail.collect_module_block(Expr $c, Expr $site) {
  $c.report_error(
    <driver>,
    "malformed module block",
    $site, %("a module block lists member paths as strings, separated by"
    "commas, between braces"));
}

static macro Stmt $fail.collect_module_second(Expr $c, Expr $site) {
  $c.report_error(
    <driver>,
    "a file holds one module block",
    $site, NULL);
}

static macro Stmt $fail.collect_module_member(
  Expr $c, Expr $site, Expr $member, Expr $stem) {
  $c.report_error(
    <driver>,
    %"module member '${$member}' is outside '${$stem}/'",
    $site, %("a member lies under the companion directory of the file that"
    "names it"));
}

static macro Stmt $fail.collect_module_prefix(
  Expr $c, Expr $site, Expr $member, Expr $other) {
  $c.report_error(
    <driver>,
    %"module member '${$member}' takes the static prefix of '${$other}'",
    $site, %("a file's statics take its path with each non-identifier"
    "character made '_' and trailing '_' dropped, then '___'; rename one of"
    "the files"));
}

static macro Stmt $fail.collect_module_read(
  Expr $c, Expr $site, Expr $path) {
  $c.report_error(
    <driver>,
    "cannot read module member",
    $site, %("path: ${$path}"));
}

static macro Stmt $fail.collect_module_cycle(
  Expr $c, Expr $site, Expr $member, Expr $path) {
  $c.report_error(
    <driver>,
    %"module member '${$member}' is already being spliced",
    $site, %("path: ${$path}"));
}

static macro Stmt $fail.collect_interface_write(Expr $c, Expr $site) {
  $c.report_error(
    <emit>,
    "failed to write interface file",
    $site, NULL);
}

static macro Stmt $report.collect_loaded_declaration(
  Expr $c, Expr $site, Expr $name, Expr $path) {
  $c.report_error(
    <type>, %"conflicting native declaration: ${$name}", $site,
    %("provider: ${$path}"));
}

static Scope process_cache_scope = NULL;

/* Paths whose entries a later unit collects again: those collected without
   their declaration defaults while the shared compile-time session was
   being filled, and those a project meta build collected with placeholders
   for its meta calls. */
static Map provisional_entries = NULL;

/* Files collected cold in this process whose entries declare adoptions and
   do not yet record their conformances. */
static Map cold_providers = NULL;

/* Each entry's declared function names; see `_declared_functions`. */
static Map declared_functions = NULL;

/* Interfaces name the same sources many times, so a process hashes each
   source once. */
static Map source_hashes = NULL;

static Map linked_providers = NULL;

/* The record texts this compiler was translated with, by home-portable
   path. */
static Map linked_records = NULL;

module {
  "collect/cache.x",
  "collect/splice.x",
  "collect/walk.x",
  "collect/declarations.x",
  "collect/providers.x",
  "collect/packages.x",
  "collect/interfaces.x",
}
