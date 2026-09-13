/*  editor.x -- one-request semantic editor adapter

    Copyright (c) 2026 Gary William Flake

    Uses the ordinary compiler frontend and a separate response file so
    macro output cannot corrupt editor results. Each process owns one request.
*/

#pragma once
#include "frontend.x"
#include "project.x"
#include "sourceview.x"
#include "emit.x"
#include "format.x"
#include "diagnostics.x"
#include "utils.x"

#pragma private

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* The private request uses argv for metadata and separate files for source
   snapshots. Only this response file carries JSON; macros can print freely
   to stdout/stderr without corrupting it. No JSON input parser is needed. */
static void _string(File file, String value) {
  fputc('"', file);
  foreach (int byte, value) {
    unsigned char ch = byte;
    if (ch == '"' || ch == '\\') fprintf(file, "\\%c", ch);
    else if (ch < 32) fprintf(file, "\\u%04x", ch);
    else fputc(ch, file);
  }
  fputc('"', file);
}

static void _location(File file, String path, int start, int end) {
  fputs("\"file\":", file);
  _string(file, path);
  fprintf(file, ",\"start\":%d,\"end\":%d", start, end);
}

static void _diagnostics(File file, Compiler compiler, Map needed) {
  int comma = 0;
  fputs("\"diagnostics\":[", file);
  foreach (List entry, compiler.diagnostics()) {
    Symbol code = entry.assoc(<code>);
    List location = entry.assoc(<location>);
    Var source = location.assoc(<file>);
    String path = source is <string> ? source.string() : compiler.filename;
    Var position = location.assoc(<position>);
    Var width = location.assoc(<length>);
    int start = position is void ? 0 : position.int();
    int length = width is void ? 0 : width.int();
    if (comma++) fputc(',', file);
    fputc('{', file);
    path = SourceView.path(path);
    needed[path] = 1;
    _location(file, path, start, start + length);
    fputs(",\"message\":", file);
    _string(file, entry.assoc(<message>).string());
    fputs(",\"code\":", file);
    _string(file, code.str());
    fputs(",\"severity\":", file);
    _string(file, code == <warning> ? "warning" : "error");
    fputc('}', file);
  }
  fputc(']', file);
}

static List _occurrence(Compiler compiler, String path, int offset) {
  List found = NULL;
  foreach (List row, compiler.source_occurrences) {
    String file = row[0];
    int start = row[1].int(), end = row[2].int();
    if (file != path || offset < start || offset >= end) continue;
    if (!found || end - start < found[2].int() - found[1].int()) found = row;
  }
  return found;
}

static void _query(
  File file, Compiler compiler, String path, String kind, int offset,
  Map needed) {
  List row = _occurrence(compiler, path, offset);
  if (!row) return;
  List binding = row[3];
  Type type = row[4];
  if (kind == "definition") {
    Var value = compiler.source_definitions[binding];
    if (value is not <list>) return;
    List target = value;
    needed[target[0]] = 1;
    fputs(",\"definition\":{", file);
    _location(file, target[0], target[1].int(), target[2].int());
    fputc('}', file);
  }
  else if (kind == "hover" && type) {
    needed[row[0]] = 1;
    List declaration = type.declaration_ast(binding);
    String text = String.new(
      compiler.code_pretty_string(compiler.emit(%($declaration)), NULL));
    fputs(",\"hover\":{", file);
    _location(file, row[0], row[1].int(), row[2].int());
    fputs(",\"text\":", file);
    _string(file, text);
    fputc('}', file);
  }
}

static void _sources(File file, Compiler compiler, Map needed) {
  int comma = 0;
  fputs(",\"sources\":[", file);
  foreach (Var key, needed.keys()) {
    Var text;
    if (!compiler.source_texts.try_get(key, &text)) continue;
    if (comma++) fputc(',', file);
    fputs("{\"file\":", file);
    _string(file, key.string());
    fputs(",\"text\":", file);
    _string(file, text.string());
    fputc('}', file);
  }
  fputc(']', file);
}

static CliRequest _configure(
  int argc, char **argv, SourceView sources, String source) {
  char *defaults[] = { argv[0], "build", NULL };
  CliRequest request = argc == 1 ? cli_parse(2, defaults) :
                                 cli_parse(argc, argv);
  request.sources = sources;
  if (request.command != <build> && request.command != <translate>) {
    fputs("x2c editor: use a build or translate configuration\n", stderr);
    exit(2);
  }
  if (!request.inputs && request.command == <build>) {
    String manifest = project_manifest(request);
    if (manifest) {
      request.manifest = manifest;
      CliRequest selected = NULL;
      ProjectBuild plan = project_plan(request);
      for (ProjectBuild node = plan; node; node = node.next) {
        foreach (String input, node.request.inputs) {
          if (SourceView.path(input) != source) continue;
          if (selected && selected != node.request) {
            fputs("x2c editor: source belongs to multiple selected targets\n",
                  stderr);
            exit(2);
          }
          selected = node.request;
        }
      }
      if (!selected) {
        fputs("x2c editor: this document is not a selected target input; "
              "open its owning source for semantic results or configure "
              "a direct translate command\n", stderr);
        exit(2);
      }
      request = selected;
    }
  }
  request.sources = sources;
  if (sources.is_changed(source) &&
      (request.live_symbols || request.cpp_symbols)) {
    fputs("x2c editor: unsaved sources with native CPP symbol modes are "
          "not supported; syntax highlighting remains available\n", stderr);
    exit(2);
  }
  request.source_facts = 1;
  return request;
}

static int _changed_dependency(Compiler compiler, SourceView sources) {
  foreach (Var path, compiler.deps.keys())
    if (sources.is_changed(path.string())) return 1;
  foreach (Var path, compiler.source_texts.keys())
    if (sources.is_changed(path.string())) return 1;
  return 0;
}

/** Serves one private editor request after process environment initialization.
    Metadata precedes ordinary compiler arguments after `--`; source snapshots
    and the JSON response use separate files. Returns zero for a written
    response and two for a failed request or unsupported configuration.
*/
int editor_request(int argc, char **argv) {
  if (argc < 7) return 2;
  String response = String.new(argv[1]);
  String source = SourceView.path(String.new(argv[2]));
  String kind = String.new(argv[3]);
  int offset = atoi(argv[4]), count = atoi(argv[5]);
  if (count < 0 || count > (argc - 7) / 3) return 2;
  int boundary = 6 + count * 3;
  if (strcmp(argv[boundary], "--")) return 2;
  SourceView sources = SourceView.new();
  for (int index = 0; index < count; index++) {
    int arg = 6 + index * 3;
    String logical = String.new(argv[arg]);
    String snapshot = String.new(argv[arg + 1]), text;
    if (!SourceView.read(NULL, snapshot, &text)) return 2;
    sources.set(logical, text, !strcmp(argv[arg + 2], "1"));
  }
  // Reuse the private metadata delimiter as the compiler's argv[0].
  argv[boundary] = argv[0];
  CliRequest request = _configure(
    argc - boundary, argv + boundary, sources, source);
  Frontend.load_support(request);
  Context command = Context.open_isolated_named("editor request");
  Frontend frontend = Frontend.new(request);
  ParsedUnit unit;
  int parsed = frontend.open(source, &unit);
  if ((request.live_symbols || request.cpp_symbols) &&
      _changed_dependency(unit.compiler, sources)) {
    fputs("x2c editor: unsaved sources with native CPP symbol modes are "
          "not supported; syntax highlighting remains available\n", stderr);
    unit.close();
    command.close();
    return 2;
  }
  File result = fopen(response, "w");
  if (!result) {
    unit.close();
    command.close();
    return 2;
  }
  fputs("{\"file\":", result);
  _string(result, source);
  fputc(',', result);
  Map needed = %{};
  _diagnostics(result, unit.compiler, needed);
  if (parsed) _query(result, unit.compiler, source, kind, offset, needed);
  _sources(result, unit.compiler, needed);
  fputs("}\n", result);
  int failed = fclose(result);
  unit.close();
  command.close();
  return failed ? 2 : 0;
}
