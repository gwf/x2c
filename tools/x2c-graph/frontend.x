/*  frontend.x -- tool-private access to the x2c source parser

    This is deliberately not a compiler API.  It mirrors the ordinary
    snapshot-backed parse path so the graph spike can expose which parts, if
    any, deserve a reusable interface later.
*/

#pragma once
#include "compiler.x"
#include "collect.x"
#include "snapshot.x"
#include "utils.x"

typedef struct Frontend {
  Map globals, function_definitions;
  List include_dirs;
  int gensym;
} *Frontend;

typedef struct ParsedUnit {
  Context context;
  Compiler compiler;
  List ast;
  int source_lines;
} ParsedUnit;

#pragma private

#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

Frontend Frontend.new(List include_dirs) {
  Type.initialize();
  header_symbols_initialize();
  Frontend frontend = Scope.calloc(1, sizeof(struct Frontend));
  String root = x2c_get_root();
  frontend.globals = symbol_snapshot_load(
    %"$root/etc/symbols.xlisp",
    &frontend.function_definitions,
    &frontend.gensym
  );
  header_symbols_open(%"$root/etc/header-symbols.xlisp", frontend.gensym);
  frontend.include_dirs = include_dirs.append(x2c_default_include_dirs());
  return frontend;
}

static int _frontend_read(String filename, String *text) {
  File file = NULL;
  try file = filename.open("r");
  catch %(not-found *): {
    Stderr.printf("x2c-graph: cannot open input: %s\n", filename);
    return 0;
  }
  catch %(io-fail *): {
    Stderr.printf("x2c-graph: cannot open input: %s\n", filename);
    return 0;
  }
  struct stat info;
  if (file.stat(&info) || !S_ISREG(info.st_mode)) {
    file.close();
    Stderr.printf("x2c-graph: input is not a regular file: %s\n", filename);
    return 0;
  }
  try *text = file.string_close();
  catch %(io-fail *): {
    Stderr.printf("x2c-graph: cannot read input: %s\n", filename);
    return 0;
  }
  return 1;
}

static void _frontend_configure_source(Compiler compiler, String filename) {
  char source_path[PATH_MAX], runtime_path[PATH_MAX], lib_path[PATH_MAX];
  String lib = %"${x2c_get_root()}/lib", runtime = %"$lib/x2c.x";
  int source_resolved = realpath(filename, source_path) != NULL;
  int lib_resolved = realpath(lib, lib_path) != NULL;
  compiler.prelude =
    !(source_resolved && realpath(runtime, runtime_path) &&
      !strcmp(source_path, runtime_path));
  int lib_length = lib_resolved ? strlen(lib_path) : 0;
  compiler.runtime_inc =
    !(source_resolved && lib_resolved &&
      !strncmp(source_path, lib_path, lib_length) &&
      source_path[lib_length] == '/');
}

static int _frontend_source_lines(String text) {
  if (!text || !text[0]) return 0;
  int lines = text[strlen(text) - 1] == '\n' ? 0 : 1;
  for (char *ch = text; *ch; ch++)
    if (*ch == '\n') lines++;
  return lines;
}

void ParsedUnit.close(ParsedUnit *unit, Frontend frontend) {
  if (!unit->context) return;
  if (unit->compiler) {
    if (frontend && frontend.gensym < unit->compiler.names.gensym_count)
      frontend.gensym = unit->compiler.names.gensym_count;
    unit->compiler.free_lisp();
  }
  Type.end_unit();
  unit->context.close();
  *unit = (ParsedUnit) { 0 };
}

int Frontend.open(Frontend frontend, String filename, ParsedUnit *unit) {
  *unit = (ParsedUnit) { 0 };
  unit->context = Context.open_isolated_named("x2c graph input");
  Type.begin_unit();
  unit->compiler = Compiler.new();
  Compiler compiler = unit->compiler;
  compiler.filename = filename;
  compiler.include_dirs = frontend.include_dirs;
  _frontend_configure_source(compiler, filename);
  String text = NULL;
  if (!_frontend_read(filename, &text)) {
    unit.close(frontend);
    return 0;
  }
  unit->source_lines = _frontend_source_lines(text);
  compiler.tokenize(text);
  Map globals = frontend.globals.copy();
  compiler.fn_defs = frontend.function_definitions.copy();
  compiler.set_gensym(frontend.gensym);
  globals = compiler.collect_symbols(globals);
  compiler.sym.seed_var_tags(globals);
  unit->ast = compiler.full_parse(globals);
  if (compiler.error_count()) {
    unit.close(frontend);
    return 0;
  }
  return 1;
}
