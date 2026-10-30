/*  completion.x -- compiler completion in a private source overlay

    Copyright (c) 2026 Gary William Flake
*/

#pragma once
#include "analysis.x"

/** Completes a source prefix without publishing the marker or borrowed types. */
Var LspWorkspace.complete(LspWorkspace w, String path, int offset) {
  path = w.retain(path);
  String source = w.retain(w.text(path));
  w.close_unit();
  if (offset < 0 || offset > source.len()) return [];
  CliRequest selected = w.request;
  if (selected.command != <build> && selected.command != <translate>) return [];
  if (!selected.inputs && selected.command == <build>)
    selected = ProjectBuild.owning_target(selected, path);
  if (!selected) {
    w.notice = "x2c lsp: document has no unique selected target; configure a direct translate command";
    return [];
  }
  if (selected.live_symbols || selected.cpp_symbols) {
    w.notice = "x2c lsp: unsaved sources with native CPP symbol modes are not supported; syntax highlighting remains available";
    return [];
  }
  Frontend frontend = Frontend.new(selected);
  Context request = Context.open_isolated_named("language server completion");
  Array items = _lsp_complete(w, frontend, path, source, offset);
  items = request.export(items);
  request.close();
  return items;
}

static Array _lsp_complete(
  LspWorkspace w, Frontend frontend, String path, String source, int offset) {
  int start = offset, end = offset;
  while (start && _lsp_identifier_byte(source[start - 1])) start--;
  while (end < source.len() && _lsp_identifier_byte(source[end])) end++;
  String prefix = source[start:offset];
  String marked = source[:start] + "__x2c_completion__" + source[end:];
  SourceView sources = SourceView.new();
  sources.overlays = w.sources.overlays.copy();
  sources.dirty_paths = w.sources.dirty_paths.copy();
  sources.set(path, marked, 1);
  struct CliRequest configuration = *frontend.request;
  struct Frontend session = *frontend;
  session.request = &configuration;
  Compiler.refresh_source_collections();
  defer Compiler.refresh_source_collections();
  frontend.prepare_meta($(path));
  configuration.sources = sources;
  ParsedUnit unit;
  int opened = Frontend.start(&session, path, unit);
  Array items = [];
  Compiler c = unit.compiler;
  try {
    int marker = opened ? _lsp_completion_marker(c) : -1;
    if (marker >= 0 && !_lsp_meta_completion(c, marker)) {
      c.mark_completion(marker);
      if (unit.collect(&session)) unit.parse();
    }
  }
  catch %(replcomp (kind ?(Symbol role)) (rows ?rows)
                   (keywords ?keywords) *):
    items = _lsp_completion_items(
      role, Error.snapshot(rows), Error.snapshot(keywords), prefix,
      lsp_range(source, start, end));
  catch %((!or incomplete malformed) *): { }
  items = unit.context.export(items);
  unit.close();
  return items;
}

/* Module expansion can move the marker from its document byte offset. */
static int _lsp_completion_marker(Compiler c) {
  for (Token token = c.tokenizer.tokens; token.type != <eof>; token++)
    if (token.type == <ident> && token.text == "__x2c_completion__")
      return token.pos;
  return -1;
}

static int _lsp_identifier_byte(unsigned char byte) =>
  byte == '_' || scan_ascii_alpha(byte) || scan_ascii_digit(byte);

/* Find the enclosing top-level form; the parser owns its meta classification. */
static int _lsp_meta_completion(Compiler c, int offset) {
  Token first = NULL;
  int braces = 0;
  for (Token token = c.tokenizer.tokens; token.type != <eof>; token++) {
    if (token.type == <space> || token.type == <comment> ||
        token.type == <preproc>) continue;
    if (!first) first = token;
    if (token.pos >= offset) break;
    if (token.type == <"{">) braces++;
    else if (token.type == <"}">) {
      if (braces && !--braces) first = NULL;
    }
    else if (!braces && token.type == <;>) first = NULL;
  }
  if (!first) return 0;
  with (c.token = first) { return c.meta_form_is_declaration(); }
}

static Array _lsp_completion_items(
  Symbol role, List rows, List keywords, String prefix, Map range) {
  Map items = {};
  foreach (String word in keywords)
    if (word.startswith(prefix))
      items[word] = _lsp_completion_item(word, 14, range);
  foreach (Var row in rows) {
    String name = NULL;
    Var type = void;
    if (role == <members>) name = row;
    else match (row) case %(?(String spelling) ?semantic): {
      name = spelling;
      type = semantic;
    }
    if (!name || !name.startswith(prefix) || role == <continue>) continue;
    Type semantic = type is <list> ? type : NULL;
    int is_type = type == <typemacro> || (semantic && semantic.is_typedef());
    if (role == <type> && !is_type) continue;
    if ((role == <expr> || role == <statement>) && is_type) continue;
    int kind = role == <members> ? 5 : is_type ? 7 :
      semantic && semantic.is_function() ? 3 : type == <macro> ? 3 : 6;
    items[name] = _lsp_completion_item(name, kind, range);
  }
  Array result = [];
  foreach (String name in items.keys().array().sort()) result.push(items[name]);
  return result;
}

static Map _lsp_completion_item(String name, int kind, Map range) {
  return {"label": name, "kind": kind,
          "textEdit": {"range": range, "newText": name}};
}
