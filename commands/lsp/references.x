/*  references.x -- source-binding references and workspace rename edits

    Copyright (c) 2026 Gary William Flake.
*/
#pragma once
#include "analysis.x"

/** Finds references across the selected target's x2c input units. */
Map LspWorkspace.references(
  LspWorkspace w, String path, int offset, int include_declaration) {
  Map query = _reference_query(w, path, offset);
  if (query == NULL) return {"result": []};
  w.close_unit();
  Array locations;
  if (!_reference_locations(w, query, include_declaration, locations))
    return _reference_failure();
  return {"result": locations};
}

/** Returns source edits without changing buffers or files. */
Map LspWorkspace.rename(
  LspWorkspace w, String path, int offset, String new_name) {
  if (!new_name.is_identifier() ||
      scan_keyword_type(new_name, new_name.len()))
    return _rename_failure("x2c lsp: the new name must be an identifier");
  new_name = w.retain(new_name);
  Map query = _reference_query(w, path, offset);
  if (query == NULL)
    return _rename_failure("x2c lsp: this binding has no source range");
  w.close_unit();
  List target = query["target"];
  String file = target[0], root = Path.absolute(".");
  if (file != root && !file.startswith(root == "/" ? "/" : root + "/"))
    return _rename_failure("x2c lsp: the definition is outside the workspace");
  if (query["declaration"].is_null())
    return _rename_failure("x2c lsp: this binding has no identifier range");
  Array locations;
  if (!_reference_locations(w, query, 1, locations))
    return _reference_failure();
  Map changes = {};
  foreach (Map location in locations) {
    String uri = location["uri"];
    Array edits = changes.setdefault(uri, []);
    edits.push({"range": location["range"], "newText": new_name});
  }
  return {"result": {"changes": changes}};
}

/* Export the definition identity and input names before any unit closes.
   Bindings and Type values remain borrowed from their own compiler. */
static Map _reference_query(LspWorkspace w, String path, int offset) {
  List row = w.occurrence(path, offset);
  if (!row) return NULL;
  Var definition = w.unit.compiler.source_definitions[row[3]];
  if (definition is not <list>) return NULL;
  List target = definition;
  Array inputs = [];
  if (w.request.project_manifest()) {
    foreach (String input in w.frontend.request.inputs)
      if (Path.is_x2c_source(input)) inputs.push(Path.absolute(input));
  }
  else inputs.push(path);
  Map query = {"target": $(target[0], target[1], target[2]),
    "declaration": _reference_location(w, target), "inputs": inputs};
  return w.retain(query);
}

/* Exact definition locations identify a binding across independent units.
   A failed parse cannot support a complete references or rename result. */
static int _reference_locations(
  LspWorkspace w, Map query, int include_declaration, Array &locations) {
  locations = [];
  Map seen = {};
  if (include_declaration && !query["declaration"].is_null())
    _reference_add(w, locations, seen, query["declaration"]);
  List target = query["target"];
  foreach (String input in query["inputs"].array()) {
    if (!w.analyze(input)) return 0;
    Compiler c = w.unit.compiler;
    foreach (List row in c.source_occurrences) {
      Var definition = c.source_definitions[row[3]];
      if (definition is not <list> ||
          !_reference_same(definition.list(), target)) continue;
      if (!include_declaration && _reference_same(row, target)) continue;
      Map location = _reference_location(w, row);
      if (location != NULL) _reference_add(w, locations, seen, location);
    }
  }
  return 1;
}

static int _reference_same(List row, List target) =>
  row[0] == target[0] && row[1] == target[1] && row[2] == target[2];

/* Declarator and complex-reference spans include their owner or sigil.
   The lexical identifier at the end is the name a rename replaces. */
static Map _reference_location(LspWorkspace w, List row) {
  String file = row[0], text = w.text(file);
  int first = row[1], after = row[2], start = -1, end = -1;
  Tokenizer tokenizer = Tokenizer.new(text[first:after], <x2c>);
  tokenizer.scan();
  Token token;
  while ((token = tokenizer.next()).type != <eof>)
    if (token.text.is_identifier()) {
      start = first + token.pos;
      end = start + token.len;
    }
  if (start < 0) return NULL;
  return {"uri": lsp_uri(file), "range": lsp_range(text, start, end)};
}

static void _reference_add(
  LspWorkspace w, Array locations, Map seen, Map location) {
  location = w.retain(location);
  String key = w.retain(Var.json(location));
  if (key in seen) return;
  seen[key] = 1;
  locations.push(location);
}

static Map _rename_failure(String message) =>
  {"error": {"code": -32602, "message": message}};

static Map _reference_failure(void) =>
  {"error": {"code": -32803,
    "message": "x2c lsp: cannot analyze every selected target input"}};
