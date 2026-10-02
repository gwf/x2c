/*  editor.x -- one-request semantic editor adapter

    Copyright (c) 2026 Gary William Flake

    Uses the ordinary compiler frontend and a separate response file so
    macro output cannot corrupt editor results. A request passes its
    metadata in argv and its source snapshots in files, so no JSON input
    parser is needed. Each process owns one request.
*/

#pragma once

#pragma private

#include "frontend.x"
#include "meta-project.x"
#include "project.x"
#include "sourceview.x"
#include "emit.x"
#include "format.x"
#include "diagnostics.x"
#include "report.x"
#include "utils.x"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// requests

/* One editor query: the file the reply goes to, the document with the
   source snapshots, and what the editor asks, a kind at a byte offset.
   While the reply is built, `needed` holds each file a location in it
   names. */
typedef struct Query {
  String response, source, kind, int offset, SourceView sources;
  Compiler compiler, Map reply, needed;
} Query;

/** Serves one private editor request after process environment initialization.
    Metadata precedes ordinary compiler arguments after `--`; source snapshots
    and the JSON response use separate files. Returns zero for a written
    response and two for a failed request or unsupported configuration.
*/
int editor_request(int argc, char **argv) {
  if (argc < 7) return 2;
  Query q = {
    .response = String.new(argv[1]),
    .source = Path.absolute(String.new(argv[2])),
    .kind = String.new(argv[3]), .offset = atoi(argv[4])};
  int count = atoi(argv[5]);
  if (count < 0 || count > (argc - 7) / 3) return 2;
  int boundary = 6 + count * 3;
  if (strcmp(argv[boundary], "--")) return 2;
  q.sources = _snapshots(argv + 6, count);
  if (q.sources == NULL) return 2;
  // Reuse the private metadata delimiter as the compiler's argv[0].
  argv[boundary] = argv[0];
  return q.serve(q.configure(argc - boundary, argv + boundary));
}

/* Each snapshot is three arguments: the logical path, the file that holds
   its text, and "1" when that text is unsaved. Returns NULL when a
   snapshot cannot be read. */
static SourceView _snapshots(char **argv, int count) {
  SourceView sources = SourceView.new();
  for (int i = 0; i < count; i++) {
    char **row = argv + 3 * i;
    String logical = String.new(row[0]);
    String snapshot = String.new(row[1]), text;
    if (!SourceView.read(NULL, snapshot, text)) return NULL;
    sources.set(logical, text, !strcmp(row[2], "1"));
  }
  return sources;
}

/* Unsaved text cannot reach the host preprocessor, which reads the saved
   files. */
static const char *unsaved_cpp =
  "x2c editor: unsaved sources with native CPP symbol modes are "
  "not supported; syntax highlighting remains available\n";

/* The compiler request the arguments after `--` configure. The snapshots
   are its sources, so an unsaved project manifest selects the target. */
static CliRequest Query.configure(Query &q, int argc, char **argv) {
  char *defaults[] = { argv[0], "build", NULL };
  CliRequest request = argc == 1 ? cli_parse(2, defaults) :
                                 cli_parse(argc, argv);
  request.sources = q.sources;
  if (request.command != <build> && request.command != <translate>)
    _fail("x2c editor: use a build or translate configuration\n");
  if (!request.inputs && request.command == <build>)
    request = _project_target(request, q.source);
  request.sources = q.sources;
  if (q.sources.is_changed(q.source) && _native_cpp(request))
    _fail(unsaved_cpp);
  request.source_facts = 1;
  return request;
}

/* With a project manifest, the request becomes the one selected target
   whose inputs hold `source`. */
static CliRequest _project_target(CliRequest request, String source) {
  String manifest = project_manifest(request);
  if (!manifest) return request;
  request.manifest = manifest;
  CliRequest selected = NULL;
  for (ProjectBuild node = project_plan(request); node; node = node.next)
    foreach (String input, node.request.inputs) {
      if (Path.absolute(input) != source) continue;
      if (selected && selected != node.request)
        _fail("x2c editor: source belongs to multiple selected targets\n");
      selected = node.request;
    }
  if (!selected)
    _fail(
      "x2c editor: this document is not a selected target input; "
      "open its owning source for semantic results or configure "
      "a direct translate command\n");
  return selected;
}

/* Ends a request the adapter does not serve. */
static void _fail(const char *message) {
  fputs(message, stderr);
  exit(2);
}

static int _native_cpp(CliRequest request) =>
  request.live_symbols || request.cpp_symbols;

/* Parses the document as its configured translation would and writes the
   reply, unless the request preprocesses natively and a file the unit
   read is unsaved. */
static int Query.serve(Query &q, CliRequest request) {
  Frontend frontend = Frontend.new(request);
  if (!frontend.preload_macro_libraries()) return 2;
  frontend.prepare_meta(%(${q.source}));
  Context command = Context.open_isolated_named("editor request");
  defer command.close();
  ParsedUnit unit;
  int parsed = frontend.open(q.source, unit);
  defer unit.close();
  q.compiler = unit.compiler;
  if (_native_cpp(request) && _changed_dependency(q.compiler, q.sources)) {
    fputs(unsaved_cpp, stderr);
    return 2;
  }
  return q.write(parsed);
}

/* Whether a file the unit read, or whose text it kept, is unsaved. */
static int _changed_dependency(Compiler c, SourceView sources) {
  foreach (Var path, c.deps.keys()) if (sources.is_changed(path)) return 1;
  foreach (Var path, c.source_texts.keys())
    if (sources.is_changed(path)) return 1;
  return 0;
}

// replies

/* The reply holds the document's diagnostics, the answer to the query when
   the unit parsed, and the text of each file a location names. */
static int Query.write(Query &q, int parsed) {
  File out = fopen(q.response, "w");
  if (!out) return 2;
  q.needed = {};
  q.reply = {file: q.source, diagnostics: q.diagnostics()};
  if (parsed) q.answer();
  q.reply[<sources>] = q.texts();
  fprintf(out, "%s\n", Var.json(q.reply));
  return fclose(out) ? 2 : 0;
}

static Array Query.diagnostics(Query &q) {
  Array diagnostics = [];
  foreach (List entry, q.compiler.diagnostics())
    diagnostics.push(q.diagnostic(entry));
  return diagnostics;
}

static Map Query.diagnostic(Query &q, List entry) {
  match (entry)
    case %((code ?code) (severity ?severity) (message ?message)
           (location ?location) ?): {
      Map diagnostic = q.diagnostic_range(location);
      diagnostic[<message>] = message;
      diagnostic[<code>] = code;
      diagnostic[<severity>] = severity;
      return diagnostic;
    }
  __builtin_unreachable();
}

/* A diagnostic without a location is at the start of the unit's file. */
static Map Query.diagnostic_range(Query &q, List location) {
  match (location)
    case %((file ?file) ? ? (length ?length) (position ?position)): {
      int start = position, width = length;
      return q.location(Path.absolute(file), start, start + width);
    }
  return q.location(Path.absolute(q.compiler.filename), 0, 0);
}

/* A location in the reply. Its file joins `needed`, so the reply carries
   the text its offsets count in. */
static Map Query.location(Query &q, String path, int start, int end) {
  q.needed[path] = 1;
  return {file: path, start: start, end: end};
}

/* Answers a definition or hover query at the narrowest occurrence that
   holds the offset. */
static void Query.answer(Query &q) {
  List row = _occurrence(q.compiler, q.source, q.offset);
  if (!row) return;
  if (q.kind == "definition") q.definition(row);
  else if (q.kind == "hover") q.hover(row);
}

/* The narrowest row that holds `offset`. Each row is
   `(FILE START END BINDING TYPE)`. */
static List _occurrence(Compiler c, String path, int offset) {
  List found = NULL;
  foreach (List row, c.source_occurrences) {
    String file = row[0];
    int start = row[1], end = row[2];
    if (file != path || offset < start || offset >= end) continue;
    if (!found || end - start < found[2].int() - found[1].int()) found = row;
  }
  return found;
}

static void Query.definition(Query &q, List row) {
  List binding = row[3];
  Var value = q.compiler.source_definitions[binding];
  if (value is not <list>) return;
  List target = value;
  q.reply[<definition>] = q.location(target[0], target[1], target[2]);
}

/* The declaration of the occurrence's binding, printed as C, when the
   occurrence has a type. */
static void Query.hover(Query &q, List row) {
  Type type = row[4];
  if (!type) return;
  Compiler c = q.compiler;
  List declaration = type.declaration_ast(row[3]);
  Map hover = q.location(row[0], row[1], row[2]);
  hover[<text>] =
    String.new(c.code_pretty_string(c.emit(%($declaration), NULL), NULL));
  q.reply[<hover>] = hover;
}

/* The text the unit kept of each file a location names. */
static Array Query.texts(Query &q) {
  Array texts = [];
  foreach (Var path, q.needed.keys()) {
    Var text;
    if (q.compiler.source_texts.try_get(path, text))
      texts.push({file: path, text: text});
  }
  return texts;
}
