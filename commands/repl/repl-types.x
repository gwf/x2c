/*  repl-types.x -- native playground session contracts

    Copyright (c) 2026 Gary William Flake.
*/
#pragma once
#include "frontend.x"

/** One retained native program and the declarations compiled with it. */
typedef struct ReplProgram {
  String directory, module, header;
  List roots, declarations;
  Map symbols, addresses, descriptions, sources, dependencies;
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
  unsigned sequence;
  int inspect_depth, inspect_limit;
} *ReplSession;

/** A submission result; native values are rendered before leaving their entry. */
typedef struct ReplResult {
  Symbol status;
  Var value;
  String name, message, source, formatted;
  List diagnostics, cause, syntax, lowered, removed;
} ReplResult;

/** Sorted completion candidates replacing one byte range. */
typedef struct ReplCompletion {
  size_t start, end;
  List candidates;
} ReplCompletion;
