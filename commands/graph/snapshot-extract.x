/*  snapshot-extract.x -- owned facts from bound compiler units

    Copyright (c) 2026 Gary William Flake
*/

#pragma once
#include "frontend.x"
#include "targets.x"
#include "datum.x"
#include "json.x"

String snapshot_text(Var value);

static typedef struct SnapshotExtract {
  Compiler c;
  String domain, unit, unit_id;
  Array entities, edges, files;
  Map bindings, type_ids, records, types;
} SnapshotExtract;

static Map _sx_location(SnapshotExtract &s, int origin) {
  List location = s.c.origin_location(origin);
  Map result = {"file": s.unit, "line": 0, "column": 0};
  if (location) {
    result["file"] = location.assoc(<file>);
    result["line"] = location.assoc(<line>);
    result["column"] = location.assoc(<column>);
  }
  return result;
}

/* Source wrappers carry locations rather than indexes into a closed unit. */
static Var _sx_portable(SnapshotExtract &s, Var value) {
  if (value is not <list>) {
    if (value is <token>) return s.c.freeze_declaration_syntax(value);
    return value;
  }
  List node = value;
  match (node) {
    case %(at ?(int origin) ?inner): {
      List place = s.c.origin_location(origin);
      List location = place ? %(source $(place.assoc(<file>))
        $(place.assoc(<line>)) $(place.assoc(<column>))
        $(place.assoc(<length>)) $(place.assoc(<position>))) : NULL;
      return %(at $location $(_sx_portable(s, inner)));
    }
    case %(cache ?(int id)):
      return s.c.freeze_declaration_syntax(node);
  }
  Array children = [];
  foreach (Var child, node) children.push(_sx_portable(s, child));
  return children.list_free();
}

static String _sx_ast(SnapshotExtract &s, Var value) =>
  snapshot_text(_sx_portable(s, value));

static Map _sx_entity(
  SnapshotExtract &s, String id, String kind, String name, String owner) {
  Map entity = {"id": id, "name": name, "kind": kind,
    "domain": s.domain, "unit": s.unit, "file": s.unit,
    "owner": owner, "visibility": "public", "origin": "source",
    "source": "", "declaration": "", "ast": "",
    "declared_type": "", "resolved_type": "", "definition": 0};
  s.entities.push(entity);
  s.records[id] = entity;
  return entity;
}

static void _sx_edge(
  SnapshotExtract &s, String from, String to, String kind, int origin) {
  Map edge = _sx_location(s, origin);
  edge["from"] = from;
  edge["to"] = to;
  edge["kind"] = kind;
  edge["domain"] = s.domain;
  edge["unit"] = s.unit;
  Map entity = s.records[from];
  edge["origin"] = origin ? "source" : "unlocated";
  if (!origin && entity && entity.getdefault("line", 0).int()) {
    edge["file"] = entity["file"];
    edge["line"] = entity["line"];
    edge["column"] = entity["column"];
    edge["origin"] = entity["origin"];
  }
  edge["resolved"] = to != "" ? 1 : 0;
  s.edges.push(edge);
}

static List _sx_declaration(SnapshotExtract &s, List binding) {
  Var row = s.c.source_definitions[binding];
  if (row is <list>) return row;
  Var key = s.c.semantic_binding_facts()[%(src-key $binding)];
  if (key is <list>) return s.c.source_declarations[key];
  return NULL;
}

static void _sx_declaration_source(
  SnapshotExtract &s, Map entity, List declaration) {
  match (declaration) case %(?file ?begin ?end ?): {
    String path = file, text = s.c.source_texts[path];
    entity["file"] = path;
    entity["offset"] = begin;
    entity["origin"] = "source";
    if (text) {
      entity["source_spelling"] =
        String.new_len(text + begin.int(), end.int() - begin.int());
      int line = 1, column = 1;
      for (int i = 0; i < begin.int(); i++) {
        if (text[i] == '\n') { line++; column = 1; }
        else column++;
      }
      entity["line"] = line;
      entity["column"] = column;
    }
  }
}

static void _sx_span(
  SnapshotExtract &s, Map entity, List key, List binding) {
  _sx_declaration_source(s, entity, _sx_declaration(s, binding));
  Var span = s.c.semantic_binding_facts()[%(definition-span $key)];
  match (span) case %(?start ?end ?): {
    Token tokens = s.c.tokenizer.tokens;
    Token first = tokens + start.int();
    Token last = tokens + end.int() - 1;
    int begin = first.pos, finish = last.pos + last.len, local = begin;
    String file = s.c.text_source(begin, local);
    entity["file"] = file ? Path.absolute(file) : s.unit;
    entity["source"] = String.new_len(s.c.text + begin, finish - begin);
    entity["offset"] = local;
    int line = first.line;
    if (s.c.line_markers) (void) s.c.token_source(first, line);
    entity["line"] = line;
    entity["column"] = s.c.token_column(first);
    entity["definition"] = 1;
    entity["origin"] = "source";
  }
}

static void _sx_types(SnapshotExtract &s, Map entity, Type type) {
  if (!type) return;
  Type plain = type.is_typedef() ? type.cdr() : type;
  String declared = _sx_ast(s, plain);
  String resolved = _sx_ast(s, s.c.sym.normalize_declared_type(plain));
  entity["declared_type"] = declared;
  entity["declaration"] = _sx_ast(s, plain.declaration_ast(NULL));
  entity["resolved_type"] = resolved;
  s.types[%"$(s.domain)::$(s.unit)::$declared"] = resolved;
}

static String _sx_type(SnapshotExtract &s, Type type) {
  if (!type) return "";
  Type base = type.base_type();
  if (!base) return "";
  if (base.is_typedef()) base = base.cdr();
  String key = _sx_ast(s, base);
  if (s.type_ids.contains(key)) return s.type_ids[key];
  String name = key;
  match (base) {
    case %(?(String spelling)): name = spelling;
    case %((!or struct union enum) ?tag *):
      name = tag is <list> ? Ast.binding_spelling(tag) : tag.str();
  }
  List binding = s.c.sym.lookup(base, NULL);
  List declaration = _sx_declaration(s, binding);
  String owner_file = s.unit;
  if (declaration) owner_file = declaration.car();
  else if (base.is_aggregate_tag()) {
    List fields = s.c.sym.field_order(base);
    foreach (List field, fields ? fields.cdr() : NULL) {
      if (field.car() is not <string>) continue;
      List field_binding = s.c.sym.lookup(%(@base $(field.car())), NULL);
      List field_source = _sx_declaration(s, field_binding);
      if (field_source) { owner_file = field_source.car(); break; }
    }
  }
  String id = %"$(s.domain)::$owner_file::type::$key";
  Map entity = _sx_entity(s, id, "type", name, s.unit_id);
  entity["origin"] = "external";
  entity["file"] = owner_file;
  _sx_declaration_source(s, entity, declaration);
  if (binding) entity["binding"] = snapshot_text(binding);
  _sx_types(s, entity, base);
  s.type_ids[key] = id;
  _sx_edge(s, s.unit_id, id, "contains", 0);
  Type alias = s.c.sym.get(base);
  if (alias && alias.is_typedef()) {
    _sx_types(s, entity, alias.cdr());
    _sx_type_edge(s, id, alias.cdr(), "aliases", 0);
  }
  return id;
}

static void _sx_type_edge(
  SnapshotExtract &s, String from, Type type, String kind, int origin) {
  if (!type) return;
  String target = _sx_type(s, type);
  _sx_edge(s, from, target, kind, origin);
  List parameters;
  Type result, resolved = s.c.sym.normalize_declared_type(type);
  if ((resolved.is_pointer() || kind == "parameter") &&
      resolved.function_parts(parameters, result)) {
    foreach (Type parameter, parameters)
      _sx_type_edge(s, from, parameter, "callback", origin);
    _sx_type_edge(s, from, result, "callback", origin);
  }
}

static Map _sx_binding(
  SnapshotExtract &s, List binding, Type type, String kind, String owner) {
  if (s.bindings.contains(binding)) return s.records[s.bindings[binding]];
  String name = Ast.binding_spelling(binding);
  String emitted = s.c.emitted_binding_name(binding);
  Var method = s.c.semantic_binding_facts()[%(method $binding)];
  match (method) case %(?owner_name ?member): name = %"$owner_name.$member";
  String id = %"$owner::$kind::$emitted";
  if (s.records.contains(id)) id = %"$id::$(binding.cadr())";
  Map entity = _sx_entity(s, id, kind, name, owner);
  entity["binding"] = snapshot_text(binding);
  entity["emitted_name"] = emitted;
  entity["visibility"] = project_visibility(s.c, type, binding).str();
  entity["origin"] = project_origin(s.c, binding).str();
  _sx_types(s, entity, type);
  _sx_span(s, entity, binding, binding);
  entity["declaration"] = _sx_ast(s, type.declaration_ast(binding));
  s.bindings[binding] = id;
  _sx_edge(s, owner, id, "contains", 0);
  return entity;
}

static void _sx_fields(SnapshotExtract &s, Type aggregate, String owner) {
  List fields = s.c.sym.field_order(aggregate);
  foreach (List row, fields ? fields.cdr() : NULL) {
    (String name, Type type) = row;
    if (!name) name = %"<anonymous-$(s.entities.len())>";
    String id = %"$owner::field::$name";
    if (s.records.contains(id)) continue;
    Map field = _sx_entity(s, id, "field", name, owner);
    field["definition"] = 1;
    List binding = s.c.sym.lookup(%(@aggregate $name), NULL);
    _sx_declaration_source(s, field, _sx_declaration(s, binding));
    _sx_types(s, field, type);
    field["declaration"] = _sx_ast(s, type.declaration_ast(binding));
    _sx_edge(s, owner, id, "contains", 0);
    Type resolved = s.c.sym.normalize_declared_type(type);
    String kind = resolved.is_pointer() || resolved.is_reference()
                ? "field-pointer" : "field-value";
    _sx_type_edge(s, id, type, kind, 0);
    if (s.c.sym.get(%(@aggregate delegate $name)))
      _sx_type_edge(s, owner, type, "delegates", 0);
  }
}

static void _sx_aggregate(SnapshotExtract &s, Type base, List declaration) {
  List node;
  $ast.walk(base, node) match (node) {
    case %((!or ?kind struct union enum) ?tag ?body): {
      Type type = $(kind, tag);
      String id = _sx_type(s, type);
      Map entity = s.records[id];
      entity["origin"] = "source";
      entity["definition"] = 1;
      entity["ast"] = _sx_ast(s, declaration);
      _sx_span(s, entity, declaration, NULL);
      _sx_fields(s, type, id);
    }
  }
}

static void _sx_declarations(
  SnapshotExtract &s, Var value, String owner, int top_level) {
  if (value is not <list>) return;
  List node = Ast.without_origin(value);
  match (node) {
    case %(function ?base (!set ?target (bind ?binding ?mods)) ?body): {
      Type type = %(declare $base (bindings $target)).type_from_ast();
      Map entity = _sx_binding(s, binding, type, "function", owner);
      entity["definition"] = 1;
      entity["ast"] = _sx_ast(s, node);
      entity["declaration"] = _sx_ast(s, %(declare $base (bindings $target)));
      _sx_span(s, entity, binding, binding);
      _sx_declarations(s, body, entity["id"], 0);
      return;
    }
    case %((!or ?kind typedef declare) ?base (bindings *rows)): {
      _sx_aggregate(s, base, node);
      foreach (List row, rows) {
        List target = row;
        match (row) case %(op = ?left ?): target = left;
        match (target) case %(bind ?binding ?mods): {
          Type type = %(declare $base (bindings $target)).type_from_ast();
          if (kind == <typedef>) {
            String name = s.c.emitted_binding_name(binding);
            String id = _sx_type(s, $(name));
            Map entity = s.records[id];
            entity["name"] = Ast.binding_spelling(binding);
            entity["binding"] = snapshot_text(binding);
            entity["definition"] = 1;
            entity["origin"] = "source";
            entity["owner"] = owner;
            entity["ast"] = _sx_ast(s, node);
            _sx_types(s, entity, type);
            entity["declaration"] = _sx_ast(s, node);
            _sx_span(s, entity, node, binding);
            s.bindings[binding] = id;
            _sx_type_edge(s, id, type, "aliases", 0);
          }
          else if (top_level || type.is_function()) {
            Map entity = _sx_binding(s, binding, type,
              type.is_function() ? "function" : "global", owner);
            if (entity["ast"] == "") entity["ast"] = _sx_ast(s, node);
            _sx_span(s, entity, node, binding);
            if (type.is_function() || type.contains(<extern>))
              entity["definition"] = 0;
          }
        }
      }
      return;
    }
  }
  foreach (Var child, node) _sx_declarations(s, child, owner, top_level);
}

/* A referenced declaration remains visible even without its implementation. */
static String _sx_reference(
  SnapshotExtract &s, List binding, Type type, String owner) {
  if (s.bindings.contains(binding)) return s.bindings[binding];
  if (project_automatic(s.c, binding)) return "";
  if (!type) {
    Var key = s.c.semantic_binding_facts()[%(src-key $binding)];
    match (key) case %(?symbols ?name): type = symbols.map()[name];
  }
  Map entity = _sx_binding(s, binding, type,
    type.is_function() ? "function" : "global", s.unit_id);
  entity["definition"] = 0;
  return entity["id"];
}

static String _sx_field(SnapshotExtract &s, Type receiver, String member) {
  Type aggregate = s.c.sym.aggregate_of(receiver);
  if (!aggregate) return "";
  String owner = _sx_type(s, aggregate);
  _sx_fields(s, aggregate, owner);
  String id = %"$owner::field::$member";
  return s.records.contains(id) ? id : "";
}

static void _sx_walk(
  SnapshotExtract &s, Var value, String owner, int origin, String access) {
  if (value is not <list>) return;
  List node = value;
  match (node) {
    case %(at ?(int at) ?inner): {
      _sx_walk(s, inner, owner, at, access); return;
    }
    case %(expr ?type ?inner): {
      Map temporary = {};
      _sx_types(s, temporary, type);
      _sx_type_edge(s, owner, type, "body-type", origin);
      _sx_walk(s, inner, owner, origin, access);
      return;
    }
    case %(ident ?binding): {
      Type type = NULL;
      Var source = s.c.semantic_binding_facts()[%(src-key $binding)];
      match (source) case %(?symbols ?key): type = symbols.map()[key];
      String to = _sx_reference(s, binding, type, owner);
      if (to != "") _sx_edge(s, owner, to, "references", origin);
      return;
    }
    case %(call ?callee (args *arguments)): {
      List binding;
      Symbol kind = project_callee(s.c, callee, binding);
      String to = kind == <direct>
        ? _sx_reference(s, binding, project_expression_type(callee), owner)
        : "";
      _sx_edge(s, owner, to, "calls", origin);
      Map edge = s.edges[s.edges.len() - 1];
      edge["target_name"] = binding
        ? s.c.emitted_binding_name(binding) : "<computed>";
      edge["indirect"] = kind != <direct> ? 1 : 0;
      _sx_walk(s, callee, owner, origin, "reads");
      foreach (Var argument, arguments)
        _sx_walk(s, argument, owner, origin, "reads");
      return;
    }
    case %(op (!or . ->) (expr ?type ?base) (?(String member))): {
      String field = _sx_field(s, type, member);
      _sx_edge(s, owner, field, access, origin);
      _sx_type_edge(s, owner, type, "representation", origin);
      _sx_walk(s, base, owner, origin, "reads");
      return;
    }
    case %(op = ?left ?right): {
      _sx_walk(s, left, owner, origin, "writes");
      _sx_walk(s, right, owner, origin, "reads"); return;
    }
    case %(op ?operator ?left ?right)
      if (operator.symbol().compound_operator()): {
      _sx_walk(s, left, owner, origin, "mutates");
      _sx_walk(s, right, owner, origin, "reads"); return;
    }
    case %((!or op postfix) (!or ++ --) ?operand): {
      _sx_walk(s, operand, owner, origin, "mutates"); return;
    }
    case %((!or index getindex) ?base *indices): {
      _sx_walk(s, base, owner, origin,
        access == "reads" ? "reads" : "mutates");
      foreach (Var index, indices) _sx_walk(s, index, owner, origin, "reads");
      return;
    }
    case %((!or sizeof alignof) ?operand): {
      operand = Ast.without_origin(operand);
      match (operand) case %(parens ?inner): operand = inner;
      Type type = project_expression_type(operand);
      match (operand) case %(decl *parts):
        type = %(declare @parts).type_from_ast();
      if (type) _sx_type_edge(s, owner, type, "representation", origin);
    }
    case %(offsetof ?type ?):
      _sx_type_edge(s, owner, type, "representation", origin);
    case %(function *): return;
  }
  foreach (Var child, node) _sx_walk(s, child, owner, origin, access);
}

static void _sx_function_types(SnapshotExtract &s, Map entity) {
  String text = entity["declared_type"];
  Var value;
  unsigned cursor = 0;
  if (!text || text == "" || !datum_read(text, cursor, value)) return;
  Type type = value;
  List params;
  Type result;
  if (!type.function_parts(params, result)) return;
  foreach (Type param, params)
    _sx_type_edge(s, entity["id"], param, "parameter", 0);
  _sx_type_edge(s, entity["id"], result, "result", 0);
}

static void _sx_bodies(SnapshotExtract &s, List ast) {
  foreach (List node, ast) {
    node = Ast.without_origin(node);
    match (node) {
      case %(function ? (bind ?binding ?) ?body):
        _sx_walk(s, body, s.bindings[binding], 0, "reads");
      default: _sx_walk(s, node, s.unit_id, 0, "reads");
    }
  }
  for (size_t i = 0, count = s.entities.len(); i < count; i++) {
    Map entity = s.entities[i];
    if (entity["kind"] == "function") _sx_function_types(s, entity);
  }
}

static void _sx_protocols(SnapshotExtract &s) {
  foreach (Var (key, value), s.c.adoptions) {
    (void) key;
    match (value) case %(adopt ?base ?participant *): {
      String from = _sx_type(s, participant);
      _sx_type_edge(s, from, base, "conforms", 0);
      List conformance = s.c.conforms[$(base, participant)];
      if (!conformance) continue;
      match (conformance.last()) case %(members *members):
        foreach (List member, members) {
          match (member) case %(? ?status ?selected ?type *): {
            if (selected is not <string> || status == <no-member>) continue;
            List binding = s.c.sym.lookup($(selected), NULL);
            if (!binding) continue;
            String target = _sx_reference(s, binding, type, from);
            if (target != "") _sx_edge(s, from, target, "implements", 0);
          }
        }
    }
  }
}

Map graph_snapshot_extract(ParsedUnit *parsed, String domain) {
  Compiler c = parsed.compiler;
  String unit = Path.absolute(c.filename);
  SnapshotExtract s = {c, domain, unit, %"$domain::$unit",
    [], [], [], {}, {}, {}, {}};
  Map unit_entity = _sx_entity(s, s.unit_id, "unit", unit, "");
  unit_entity["definition"] = 1;
  _sx_declarations(s, parsed.ast, s.unit_id, 1);
  _sx_bodies(s, parsed.ast);
  _sx_protocols(s);
  foreach (Var (path, text), c.source_texts) {
    s.files.push({"path": path, "text": text});
    String id = %"$(s.unit_id)::file::$path";
    Map file = _sx_entity(s, id, "file", path, s.unit_id);
    file["file"] = path;
    file["definition"] = 1;
    _sx_edge(s, s.unit_id, id, "contains", 0);
  }
  return {"entities": s.entities, "edges": s.edges,
    "files": s.files, "types": s.types};
}

/* Relink references to declarations against the selected target universe. */
void graph_snapshot_resolve(Map snapshot) {
  Array entities = snapshot["entities"], edges = snapshot["edges"];
  Map by_id = {}, publics = {}, links = snapshot.getdefault("links", {});
  foreach (Map entity, entities) {
    Map previous = by_id[entity["id"]];
    if (previous && previous["definition"].int()) continue;
    by_id[entity["id"]] = entity;
    if (entity["visibility"] != "public" || !entity["definition"].int())
      continue;
    String key = %"$(entity["domain"])::$(entity["emitted_name"])";
    if (entity["kind"] != "function" && entity["kind"] != "global")
      continue;
    Array candidates = publics.getdefault(key, NULL);
    if (!candidates) publics[key] = candidates = [];
    candidates.push(entity);
  }
  Array unique = [];
  Array ids = [];
  foreach (String id, by_id.keys()) ids.push(id);
  foreach (String id, ids.sort()) unique.push(by_id[id]);
  snapshot["entities"] = unique;
  foreach (Map prior, unique) {
    if (prior["definition"].int() || prior["visibility"] != "public")
      continue;
    if (prior["kind"] != "function" && prior["kind"] != "global")
      continue;
    String domain = prior["domain"], name = prior["emitted_name"];
    Array domains = [domain], dependencies = links.getdefault(domain, NULL);
    if (dependencies) foreach (Var dependency, dependencies)
      if (!domains.list().contains(dependency)) domains.push(dependency);
    Map found = NULL;
    int count = 0;
    foreach (String selected, domains) {
      Array candidates = publics.getdefault(%"$selected::$name", NULL);
      if (candidates) foreach (Map candidate, candidates) {
        found = candidate;
        count++;
      }
    }
    if (count == 1) prior["canonical"] = found["id"];
    else prior["resolution"] = count ? "ambiguous" : "external";
  }
  foreach (Map edge, edges) {
    String kind = edge["kind"];
    if (kind != "calls" && kind != "references" && kind != "implements")
      continue;
    Map prior = by_id[edge["to"]];
    if (!prior || prior["definition"].int()) continue;
    String canonical = prior.getdefault("canonical", NULL);
    if (canonical) {
      edge["to"] = canonical;
      edge["resolved"] = 1;
    }
    else {
      edge["resolved"] = 0;
      edge["target_name"] = prior["emitted_name"];
      edge["reason"] = prior.getdefault("resolution", "external");
    }
  }
}
