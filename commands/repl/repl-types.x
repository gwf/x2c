/*  repl-types.x -- native playground session contracts

    Copyright (c) 2026 Gary William Flake.
*/
#pragma once
#include "frontend.x"

/** One retained native program and the declarations compiled with it. */
typedef struct ReplProgram {
  String directory, module, header;
  List roots, exports, cc_args, ld_args;
  Map symbols, addresses, descriptions, sources, dependencies, macros;
  void *handle;
} *ReplProgram;

/** Live native bindings and immutable source descriptions in one worker. */
typedef struct ReplSession {
  Compiler compiler;
  Frontend frontend;
  ReplProgram program;
  Map names, addresses, descriptions, internal;
  Array declarations, cleanups;
  Scope storage;
  int inspect_depth, inspect_limit;
} *ReplSession;

/** A submission result; native values are rendered before leaving their entry. */
typedef struct ReplResult {
  Symbol status;
  String name, message, source, formatted, artifact;
  List diagnostics, cause, syntax;
} ReplResult;

/** Sorted completion candidates replacing one byte range. */
typedef struct ReplCompletion {
  size_t start, end;
  List candidates;
} ReplCompletion;
