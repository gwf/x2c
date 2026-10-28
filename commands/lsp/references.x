/*  references.x -- source-binding references and workspace rename edits

    Copyright (c) 2026 Gary William Flake.
*/
#pragma once
#include "analysis.x"
#include "references-types.x"

/** Finds references across the selected target's x2c input units. */
Map LspWorkspace.references(
  LspWorkspace w, String path, int offset, int include_declaration) {
  Map query = _reference_query(w, path, offset);
  if (query == NULL) return {"result": []};
  w.close_unit();
  Array locations;
  if (!_reference_locations(w, query, include_declaration, locations, NULL))
    return _reference_failure();
  Array result = [];
  foreach (Map location in locations)
    result.push({"uri": location["uri"], "range": location["range"]});
  return {"result": result};
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
  if (!_rename_type_in_scope(query))
    return {"error": {"code": -32803,
      "message": "x2c lsp: the type's defining file is outside "
                 "the selected source units"}};
  Map selection = query["selection"];
  if (selection == NULL)
    return _rename_failure("x2c lsp: this occurrence has no identifier range");
  String spelling = query["spelling"], selected = selection["spelling"];
  if (!spelling.endswith(selected)) return _rename_spelling_failure();
  String replacement = spelling[:spelling.len() - selected.len()] + new_name;
  Array locations;
  if (!_reference_locations(w, query, 1, locations, replacement))
    return _reference_failure();
  Map changes = {};
  foreach (Map location in locations) {
    String text = location.getdefault("replacement", NULL);
    if (!text) {
      text = _reference_replacement(spelling, replacement, location["spelling"]);
      if (!text) return _rename_spelling_failure();
    }
    String uri = location["uri"];
    Array edits = changes.setdefault(uri, []);
    edits.push({"range": location["range"], "newText": text});
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
  Type declared = target[3];
  List binding = row[3], source_key =
    w.unit.compiler.fact(%(src-key $binding));
  List key = source_key ? source_key.cadr() : NULL;
  Array inputs = [];
  String manifest = w.request.project_manifest();
  if (manifest && w.request.command == <build> && !w.request.inputs) {
    for (ProjectBuild node = ProjectBuild.plan(w.request); node;
         node = node.next)
      foreach (String input in node.request.inputs)
        if (Path.is_x2c_source(input)) inputs.push(Path.absolute(input));
  }
  else if (manifest) {
    foreach (String input in w.frontend.request.inputs)
      if (Path.is_x2c_source(input)) inputs.push(Path.absolute(input));
  }
  else inputs.push(path);
  Map query = {"target": $(target[0], target[1], target[2]),
    "declaration": _reference_location(w, target), "inputs": inputs,
    "selection": _reference_location(w, row),
    "spelling": Ast.binding_spelling(row[3]),
    "external": _reference_external(target),
    "type": declared.is_typedef() ||
            (key ~= %((!or struct union enum) ?))};
  return w.retain(query);
}

static int _rename_type_in_scope(Map query) {
  if (!query["type"]) return 1;
  List target = query["target"];
  foreach (String input in query["inputs"].array())
    if (Path.resolved_absolute(input) == target[0]) return 1;
  return 0;
}

/* External emitted names join ordinary declarations across source units.
   Other bindings retain their physical declaration identity. */
static int _reference_locations(
  LspWorkspace w, Map query, int include_declaration, Array &locations,
  String replacement) {
  locations = [];
  Map seen = {};
  if (include_declaration && !query["declaration"].is_null())
    _reference_add(w, locations, seen, query["declaration"]);
  foreach (String input in query["inputs"].array()) {
    if (!w.analyze(input)) return 0;
    Compiler c = w.unit.compiler;
    Map methods = {};
    if (replacement)
      foreach (Map method, lsp_type_rename_methods(c, query["target"], replacement))
        methods[method["binding"]] = method;
    if (include_declaration)
      foreach ((Var source_key, List declaration) in c.source_declarations) {
        foreach ((Var binding, Map method) in methods)
          if (_reference_method_declaration(c, binding, declaration)) {
            Map location = _reference_method_location(w, method, declaration);
            if (location != NULL) _reference_add(w, locations, seen, location);
          }
        if (!_reference_matches(query, declaration)) continue;
        Map location = _reference_location(w, declaration);
        if (location != NULL) _reference_add(w, locations, seen, location);
      }
    foreach (List row in c.source_occurrences) {
      if (!include_declaration && row[5] == <decl>) continue;
      Var method = methods[row[3]];
      if (method is <map>) {
        Map location = _reference_method_location(w, method.map(), row);
        if (location != NULL) _reference_add(w, locations, seen, location);
      }
      Var definition = c.source_definitions[row[3]];
      if (definition is not <list> ||
          !_reference_matches(query, definition.list())) continue;
      Map location = _reference_location(w, row);
      if (location != NULL) _reference_add(w, locations, seen, location);
    }
  }
  return 1;
}

static int _reference_method_declaration(
  Compiler c, List binding, List declaration) {
  Var definition = c.source_definitions[binding];
  if (definition is not <list>) return 0;
  String external = _reference_external(definition.list());
  return external ? _reference_external(declaration) == external
                  : _reference_same(declaration, definition.list());
}

static Map _reference_method_location(LspWorkspace w, Map method, List row) {
  Map location = _reference_location(w, row);
  if (location == NULL) return NULL;
  String source = location["spelling"], member = method["member"];
  if (!source.endswith("_" + member)) return NULL;
  String replacement = _reference_replacement(
    method["spelling"], method["replacement"], source);
  if (!replacement) return NULL;
  location["replacement"] = replacement;
  return location;
}

static String _reference_replacement(
  String spelling, String replacement, String source) {
  if (!spelling.endswith(source)) return NULL;
  String prefix = spelling[:spelling.len() - source.len()];
  return replacement.startswith(prefix) ? replacement[prefix.len():] : NULL;
}

static String _reference_external(List declaration) {
  Var name = declaration[6];
  return name is <string> ? name.str() : NULL;
}

static int _reference_matches(Map query, List declaration) {
  String external = query["external"];
  return external ? _reference_external(declaration) == external
                  : _reference_same(declaration, query["target"]);
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
  String spelling = NULL;
  while ((token = tokenizer.next()).type != <eof>)
    if (token.text.is_identifier()) {
      start = first + token.pos;
      end = start + token.len;
      spelling = token.text;
    }
  if (start < 0) return NULL;
  return {"uri": lsp_uri(file), "range": lsp_range(text, start, end),
          "spelling": spelling};
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

static Map _rename_spelling_failure(void) =>
  _rename_failure("x2c lsp: the new name must preserve the binding's owner "
                  "and namespace prefixes");

static Map _reference_failure(void) =>
  {"error": {"code": -32803,
    "message": "x2c lsp: cannot analyze every selected target input"}};
