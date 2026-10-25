/*  cli.x -- x2c command-line parsing and presentation.

    Copyright (c) 2026 Gary William Flake.

    Each option is one table row: the commands that accept it, its
    spellings, its help text, and the request field it sets. Parsing and
    help read the same rows.
*/

#pragma once
#include "sourceview.x"

/** Holds one compiler command and its command-specific inputs and options.
    `List`s produced by `CliRequest.parse` preserve CLI order. Copies are
    shallow: request storage and referenced canonical values keep their
    producing `Scope` and pool lifetimes.
*/
typedef struct CliRequest {
  Symbol command, List inputs, run_args, include_dirs, package_dirs, cpp_args;
  List cc_args, ld_args, native_modules, extensions;
  // Package roots for generated registration units during collection.
  Map collection_packages;
  String out_dir, dep_file, dep_target, manifest;
  String target, profile, output, build_dir, label, state_seed;
  String cc, meta_cc, ar, compile_commands, sha256, index, Symbol kind;
  String diagnostics_file, Symbol color_mode;
  // The one --dump-* option in force, or 0. Each prints and stops.
  Symbol dump;
  int jobs, debugging, verbose, dry_run, quiet, plain, no_deps;
  int no_phony_deps, compile_only, kind_explicit, save_temps, no_cpp;
  // The translation error limit; 0 reports every recoverable error.
  int max_errors;
  int source_map, source_facts, live_symbols, cpp_symbols;
  int force, rebuild, clean;
  // Repository build controls: a warning fails its unit; no .xi is read.
  int fatal_warnings, no_interfaces;
  SourceView sources;
} *CliRequest;

/** Describes one target kind: its spelling on the command line and in a
    manifest, the noun a report uses, and the default output file name
    around the target's name.
*/
typedef struct TargetKind {
  Symbol kind, String spelling, noun, prefix, suffix;
} TargetKind;

#include "system-macros.x"

#include <ctype.h>
#include <errno.h>
#include <limits.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "buffer.x"
#include "report.x"
#include "utils.x"

/* cli command reports. */

static macro Stmt $fail.cli_command_unknown(Expr $first) =>
  Diagnostics.driver_error(%"unknown command or global option '$($first)'");

static macro Stmt $fail.cli_operand_required(Expr $name) =>
  Diagnostics.driver_error(%"$($name) requires exactly one operand");

static macro Stmt $fail.cli_operands_forbidden(Expr $name) =>
  Diagnostics.driver_error(%"$($name) accepts no operands");

static macro Stmt $fail.cli_help_unknown(Expr $name) =>
  Diagnostics.driver_error(%"unknown help command '$($name)'");

static macro Stmt $fail.cli_option_value_forbidden(Expr $arg) =>
  Diagnostics.driver_error(%"option takes no value '$($arg)'");

static macro Stmt $fail.cli_option_value_required(Expr $arg) =>
  Diagnostics.driver_error(%"option requires a value '$($arg)'");

static macro Stmt $fail.cli_color_invalid(Expr $value) =>
  Diagnostics.driver_error(%"invalid color mode '$($value)'");

static macro Stmt $fail.cli_target_unknown(Expr $value) =>
  Diagnostics.driver_error(%"unknown target kind '$($value)'");

static macro Stmt $fail.cli_value_invalid(Expr $noun, Expr $value) =>
  Diagnostics.driver_error(%"invalid $($noun) '$($value)'");

static macro Stmt $fail.cli_dependency_owned(Expr $value) =>
  Diagnostics.driver_error(%"C dependency option is driver-owned '$($value)'");

static macro Stmt $fail.cli_native_unsupported(Expr $arg) =>
  Diagnostics.driver_error(%"unsupported package native argument '$($arg)'");

static macro Stmt $fail.cli_option_unknown(Expr $arg) =>
  Diagnostics.driver_error(%"unknown option '$($arg)'");

module {
  "parsing.x",
  "responses.x",
  "help.x",
  "requests.x",
}
