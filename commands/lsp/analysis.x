/*  analysis.x -- resident editor source units and exported results

    Copyright (c) 2026 Gary William Flake
*/

#pragma once
#include "frontend.x"
#include "meta-project.x"
#include "project/project.x"
#include "sourceview.x"
#include "emit/emit.x"
#include "format.x"
#include "generate/generate.x"
#include "positions.x"

/** Owns process configuration and overlays; one unit borrows their lifetime.
    Analysis Maps contain only exported values, never compiler bindings.
*/
typedef struct LspWorkspace {
  CliRequest request;
  Frontend frontend;
  SourceView sources;
  ParsedUnit unit;
  String path, notice;
  Map analyses, notices;
  int parsed;
} *LspWorkspace;

LspWorkspace LspWorkspace.new(Array arguments) {
  LspWorkspace w = xcalloc(1, sizeof(struct LspWorkspace));
  int count = arguments.len();
  char **argv = xcalloc(count + 3, sizeof(char *));
  argv[0] = "x2c lsp";
  if (!count) argv[1] = "build";
  for (int i = 0; i < count; i++) argv[i + 1] = arguments[i].str();
  w.request = CliRequest.parse(count ? count + 1 : 2, argv);
  w.sources = SourceView.new();
  w.analyses = {};
  w.notices = {};
  w.request.sources = w.sources;
  w.request.source_facts = 1;
  if (w.request.command != <build> && w.request.command != <translate>)
    w.notice = "x2c lsp: use a build or translate configuration";
  return w;
}

/** Promotes a parsed message out of the retained unit into server storage. */
Var LspWorkspace.retain(LspWorkspace w, Var value) =>
  w && w.unit.context ? w.unit.context.export(value) : value;

void LspWorkspace.close_unit(LspWorkspace w) {
  w.unit.close();
  w.path = NULL;
  w.parsed = 0;
}

/** Discards every exported result that read the changed file. */
void LspWorkspace.invalidate(LspWorkspace w, String path) {
  if (w.unit.context) {
    Map analysis = w.analyses[w.path];
    if (path in analysis["reads"].map()) w.close_unit();
  }
  Array removed = [];
  foreach ((Var document, Map analysis) in w.analyses)
    if (path in analysis["reads"].map()) removed.push(document);
  foreach (Var document in removed) w.analyses.del(document);
  Compiler.refresh_source_collections();
}

/** Lists analyzed documents whose read sets contain the changed file. */
Array LspWorkspace.affected(LspWorkspace w, String path) {
  Array documents = [];
  foreach ((Var document, Map analysis) in w.analyses)
    if (path in analysis["reads"].map()) documents.push(document);
  return documents;
}

void LspWorkspace.change(
  LspWorkspace w, String path, String text, int dirty) {
  w.close_unit();
  w.invalidate(path);
  w.sources.set(path, text, dirty);
}

void LspWorkspace.close_document(LspWorkspace w, String path) {
  w.close_unit();
  w.invalidate(path);
  w.sources.unset(path);
  w.analyses.del(path);
}

String LspWorkspace.take_notice(LspWorkspace w) {
  String notice = w.notice;
  w.notice = NULL;
  if (!notice || notice in w.notices) return NULL;
  w.notices[notice] = 1;
  return notice;
}

String LspWorkspace.text(LspWorkspace w, String path) {
  Var text;
  if (w.unit.context && w.unit.compiler.source_texts.try_get(path, text))
    return text;
  String source = "";
  w.sources.read(path, source);
  return source;
}

int LspWorkspace.analyze(LspWorkspace w, String path) {
  if (w.path == path) return w.parsed;
  w.close_unit();
  if (w.request.command != <build> && w.request.command != <translate>)
    return 0;
  CliRequest selected = w.request;
  String manifest = NULL;
  if (!selected.inputs && selected.command == <build>) {
    manifest = selected.project_manifest();
    selected = ProjectBuild.owning_target(selected, path);
  }
  if (!selected) {
    Map reads = {(path): 1};
    if (manifest) reads[Path.absolute(manifest)] = 1;
    w.analyses[path] = {"diagnostics": [], "reads": reads,
                        "definitions": []};
    w.notice = "x2c lsp: document has no unique selected target; configure a direct translate command";
    return 0;
  }
  w.frontend = Frontend.new(selected);
  if (_lsp_native_cpp(w) && w.sources.is_changed(path)) {
    w.notice = "x2c lsp: unsaved sources with native CPP symbol modes are not supported; syntax highlighting remains available";
    return 0;
  }
  w.frontend.prepare_meta($(path));
  w.path = path;
  w.parsed = w.frontend.open(path, w.unit);
  Compiler c = w.unit.compiler;
  if (_lsp_native_cpp(w) && _lsp_changed_dependency(c, w.sources)) {
    w.close_unit();
    w.notice = "x2c lsp: unsaved sources with native CPP symbol modes are not supported; syntax highlighting remains available";
    return 0;
  }
  Map reads = {(path): 1};
  if (manifest) reads[Path.absolute(manifest)] = 1;
  foreach (Var file in c.deps.keys()) reads[Path.absolute(file)] = 1;
  foreach (Var file in c.source_texts.keys()) reads[Path.absolute(file)] = 1;
  Map analysis = {"diagnostics": _lsp_diagnostics(w), "reads": reads,
                  "definitions": _lsp_definitions(w)};
  analysis = w.unit.context.export(analysis);
  w.analyses[path] = analysis;
  return w.parsed;
}

Array LspWorkspace.diagnostics(LspWorkspace w, String path) {
  if (!(path in w.analyses)) w.analyze(path);
  Var analysis = w.analyses[path];
  return analysis is <map> ? analysis.map()["diagnostics"].array() : [];
}

Var LspWorkspace.definition(LspWorkspace w, String path, int offset) {
  if (!w.analyze(path)) return (Var) {0};
  List row = _lsp_occurrence(w.unit.compiler, path, offset);
  if (!row) return (Var) {0};
  Var value = w.unit.compiler.source_definitions[row[3]];
  if (value is not <list>) return (Var) {0};
  List target = value;
  return {uri: lsp_uri(target[0]),
          range: lsp_range(w.text(target[0]), target[1], target[2])};
}

Var LspWorkspace.hover(LspWorkspace w, String path, int offset) {
  if (!w.analyze(path)) return (Var) {0};
  Compiler c = w.unit.compiler;
  List row = _lsp_occurrence(c, path, offset);
  if (!row) return (Var) {0};
  Type type = row[4];
  if (!type) return (Var) {0};
  List declaration = type.declaration_ast(row[3]);
  String text = String.new(c.code_pretty_string(c.emit($(declaration), NULL), NULL));
  return {contents: {language: "c", value: text},
          range: lsp_range(w.text(path), row[1], row[2])};
}

static int _lsp_native_cpp(LspWorkspace w) =>
  w.request.live_symbols || w.request.cpp_symbols;

static int _lsp_changed_dependency(Compiler c, SourceView sources) {
  foreach (Var path in c.deps.keys()) if (sources.is_changed(path)) return 1;
  foreach (Var path in c.source_texts.keys())
    if (sources.is_changed(path)) return 1;
  return 0;
}

static Array _lsp_diagnostics(LspWorkspace w) {
  Array rows = [];
  foreach (List entry in w.unit.compiler.diagnostics()) match (entry)
    case %((code ?code) (severity ?severity) (message ?message)
           (location ?location) ?): {
      Map row = {code: code.str(), message: message,
                 severity: severity == <error> ? 1 : 2,
                 range: _lsp_diagnostic_range(w, location)};
      _lsp_related_diagnostic(w, row, location);
      rows.push(row);
    }
  return rows;
}

static Map _lsp_diagnostic_range(LspWorkspace w, List location) {
  match (location)
    case %((file ?file) ? ? (length ?length) (position ?position)): {
      Compiler c = w.unit.compiler;
      int start = position, width = length;
      if (c.display_path(c.text_source(position, start)) != file)
        start = position;
      if (Path.absolute(file) != w.path)
        return lsp_range(w.text(w.path), 0, 0);
      return lsp_range(w.text(w.path), start, start + width);
    }
  return lsp_range(w.text(w.path), 0, 0);
}

static void _lsp_related_diagnostic(
  LspWorkspace w, Map diagnostic, List location) {
  match (location)
    case %((file ?file) ? ? (length ?length) (position ?position)): {
      String path = Path.absolute(file);
      if (path == w.path) return;
      Compiler c = w.unit.compiler;
      int start = position, width = length;
      if (c.display_path(c.text_source(position, start)) != file)
        start = position;
      diagnostic["relatedInformation"] = [
        {location: {uri: lsp_uri(path),
                    range: lsp_range(w.text(path), start, start + width)},
         message: diagnostic[<message>]}];
    }
}

static List _lsp_occurrence(Compiler c, String path, int offset) {
  List found = NULL;
  foreach (List row in c.source_occurrences) {
    String file = row[0];
    int start = row[1], end = row[2];
    if (file != path || offset < start || offset >= end) continue;
    if (!found || end - start < found[2].int() - found[1].int()) found = row;
  }
  return found;
}

static Array _lsp_definitions(LspWorkspace w) {
  Array rows = [];
  if (!w.parsed) return rows;
  Compiler c = w.unit.compiler;
  foreach (List row in c.definition_rows(w.unit.ast)) match (row) {
    case %(function ?name ?display ? ? ? ? ? ? ? ?span):
      rows.push(_lsp_definition_row(w, name, display, 12, span));
    case %(typedef ?name ? ? ?span):
      rows.push(_lsp_definition_row(w, name, name, 5, span));
  }
  return rows;
}

static Map _lsp_definition_row(
  LspWorkspace w, String name, String display, int kind, List span) {
  int start = 0, end = 0;
  if (span ~= %(?(int first) ?(int last) *)) {
    Token tokens = w.unit.compiler.tokenizer.tokens;
    Token begin = tokens + first, finish = tokens + last;
    start = begin.pos;
    end = finish.pos;
  }
  return {"name": name, "display": display, "kind": kind,
          "range": lsp_range(w.text(w.path), start, end)};
}
