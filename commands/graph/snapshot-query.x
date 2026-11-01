/*  snapshot-query.x -- queries over retained project analysis

    Copyright (c) 2026 Gary William Flake
*/

#pragma once
#include "json.x"
#include "datum.x"
#include "ast-rewrite.x"

String snapshot_text(Var value);
Var snapshot_value(String text);

typedef struct SnapshotQuery {
  Map snapshot, entities_by_id, reachable, outgoing, incoming, bindings;
  Array entities, edges;
} SnapshotQuery;

static void _sq_error(String reason) {
  raise %(bad-arg (operation "graph query") (reason $reason));
}

static Map _sq_object(Var value, String field) {
  if (value is not <map>) _sq_error(%"$field must be an object");
  return value;
}

static Array _sq_array(Var value, String field) {
  if (value is not <array>) _sq_error(%"$field must be an array");
  return value;
}

static String _sq_string(Var value, String field) {
  if (value is not <string>) _sq_error(%"$field must be a string");
  return value;
}

/* Validate the external query once, before selection can short-circuit.
   Evaluation below relies on these shapes and the existing predicate names. */
static void _sq_keys(Map object, List allowed) {
  foreach (String key, object.keys())
    if (!(key in allowed)) _sq_error(%"unknown query field: $key");
}

static void _sq_integer(Var value, int minimum, String field) {
  if (!value.is_integer() || value.integer() < minimum ||
      value.integer() > INT_MAX)
    _sq_error(%"$field must be an integer at least $minimum");
}

static List _sq_node_fields(void) =>
  %("inside" "callee" "binding" "declared_type" "resolved_type"
    "argument_type");

static void _sq_validate_walk(Map request) {
  if (request.contains("depth")) _sq_integer(request["depth"], 0, "depth");
  if (request.contains("direction")) {
    String direction = _sq_string(request["direction"], "direction");
    if (!(direction in %("in" "out")))
      _sq_error("direction must be in or out");
  }
  if (!request.contains("relations")) return;
  foreach (Var value, _sq_array(request["relations"], "relations")) {
    String relation = _sq_string(value, "relation");
    if (!(relation in %("calls" "references" "contains" "aliases"
          "field-value" "field-pointer" "parameter" "result" "callback"
          "body-type" "reads" "writes" "mutates" "representation"
          "conforms" "delegates" "implements")))
      _sq_error(%"unknown relation: $relation");
  }
}

static void _sq_validate_filter(Map filter, int node) {
  foreach ((String key, Var value) in filter) {
    if (key == "all" || key == "any") {
      foreach (Var child, _sq_array(value, key))
        _sq_validate_filter(_sq_object(child, key), node);
    }
    else if (key == "not")
      _sq_validate_filter(_sq_object(value, key), node);
    else if (!node && key == "reachable_from") {
      Map reach = _sq_object(value, key);
      _sq_keys(reach, %("select" "relations" "direction" "depth"));
      _sq_validate_filter(_sq_object(reach["select"], "select"), 0);
      _sq_validate_walk(reach);
    }
    else {
      List allowed = node ? _sq_node_fields()
        : %("id" "name" "kind" "unit" "file" "domain" "visibility"
            "origin" "owner" "declared_type" "resolved_type" "binding"
            "text");
      if (!(key in allowed)) _sq_error(%"unknown filter: $key");
      String text = _sq_string(value, key);
      if (node && (key in %("declared_type" "resolved_type" "argument_type"))
          && snapshot_value(text) is not <list>)
        _sq_error(%"$key must contain a type List datum");
    }
  }
}

static String _sq_validate_query(Map request) {
  String op = _sq_string(request["op"], "op");
  List fields = NULL;
  switch (op) {
    case "find": fields = %("where"); break;
    case "inspect": fields = %("select" "view"); break;
    case "traverse":
      fields = %("select" "where" "relations" "direction" "depth");
      break;
    case "path":
      fields = %("select" "target" "relations" "direction" "depth");
      break;
    case "match":
      fields = %("select" "where" "pattern" "node_where")
        .append(_sq_node_fields());
      break;
    default: _sq_error(%"unknown operation: $op");
  }
  _sq_keys(request, %("op" "offset" "limit").append(fields));
  if (request.contains("offset")) _sq_integer(request["offset"], 0, "offset");
  if (request.contains("limit")) _sq_integer(request["limit"], 1, "limit");
  if (request.contains("select") ||
      (op in %("inspect" "traverse" "path")))
    _sq_validate_filter(_sq_object(request["select"], "select"), 0);
  if (op == "path")
    _sq_validate_filter(_sq_object(request["target"], "target"), 0);
  if (request.contains("where"))
    _sq_validate_filter(_sq_object(request["where"], "where"), 0);
  if (op == "traverse" || op == "path") _sq_validate_walk(request);
  if (request.contains("view")) {
    String view = _sq_string(request["view"], "view");
    if (!(view in %("summary" "declaration" "source" "typed_ast")))
      _sq_error("view must be summary, declaration, source, or typed_ast");
  }
  if (op == "match") {
    (void) _sq_string(request["pattern"], "pattern");
    Map predicates = {};
    foreach (String field, _sq_node_fields())
      if (request.contains(field)) predicates[field] = request[field];
    _sq_validate_filter(predicates, 1);
    if (request.contains("node_where"))
      _sq_validate_filter(_sq_object(request["node_where"], "node_where"), 1);
  }
  return op;
}

/* sort_by computes each key once and preserves the original records. */
static Array _sq_sorted(Array rows) =>
  rows.copy().sort_by(%!(Var row) => row.json());

static void _sq_append(Map index, String key, Var value) {
  if (!index.contains(key)) index[key] = [];
  index[key].array().push(value);
}

static String _sq_binding_key(Map entity, String binding) =>
  %"$(entity["domain"])::$(entity["unit"])::$binding";

static SnapshotQuery _sq_open(Map snapshot) {
  SnapshotQuery q = {.snapshot = snapshot, .entities_by_id = {},
    .reachable = {}, .bindings = {}, .entities = snapshot["entities"],
    .edges = snapshot["edges"]};
  foreach (Map entity, q.entities) {
    q.entities_by_id[entity["id"]] = entity;
    if (entity.contains("binding"))
      _sq_append(q.bindings, _sq_binding_key(entity, entity["binding"]),
        entity);
  }
  return q;
}

/* Resolved declaration placeholders keep local source evidence while
   semantic selection and traversal use their one known definition. */
static Map _sq_canonical(Map entity, Map by_id) {
  String canonical = entity.getdefault("canonical", NULL);
  return canonical ? by_id[canonical] : entity;
}

static String _sq_canonical_id(String id, Map by_id) =>
  id && by_id.contains(id) ? _sq_canonical(by_id[id], by_id)["id"] : id;

/* Build indexes only for queries which follow relationships. */
static void _sq_index_edges(SnapshotQuery &q) {
  if ((void *) q.outgoing) return;
  q.outgoing = {};
  q.incoming = {};
  foreach (Map edge, _sq_sorted(q.edges)) {
    String from = edge.getdefault("from", NULL);
    String to = edge.getdefault("to", NULL);
    String canonical_from = _sq_canonical_id(from, q.entities_by_id);
    String canonical_to = _sq_canonical_id(to, q.entities_by_id);
    if (canonical_from != from || canonical_to != to) {
      edge = edge.copy();
      edge["from"] = canonical_from;
      edge["to"] = canonical_to;
    }
    if (canonical_from) _sq_append(q.outgoing, canonical_from, edge);
    if (canonical_to) _sq_append(q.incoming, canonical_to, edge);
  }
}

static int _sq_equal(Var left, Var right) => left.json() == right.json();

static int _sq_relation(Map edge, Map request) {
  if (!request.contains("relations")) return edge["kind"] == "calls";
  Array kinds = request["relations"];
  foreach (Var kind, kinds)
    if (kind == edge["kind"]) return 1;
  return 0;
}

static int _sq_inward(Map request) =>
  request.getdefault("direction", "out") == "in";

static int _sq_depth(Map request) =>
  request.getdefault("depth", (int) INT_MAX);

static int _sq_filter(SnapshotQuery &q, Map entity, Map filter);

static Array _sq_select(SnapshotQuery &q, Map selector) {
  Array selected = [];
  Map seen = {};
  foreach (Map original, q.entities) {
    Map entity = selector.contains("id") ? original
      : _sq_canonical(original, q.entities_by_id);
    String id = entity["id"];
    if (seen.contains(id)) continue;
    seen[id] = 1;
    if (_sq_filter(q, entity, selector)) selected.push(entity);
  }
  return selected.sort_by(%!(Map entity) => entity["id"]);
}

/* Each predecessor retains the actual occurrence edge used by this search. */
static Map _sq_walk(
  SnapshotQuery &q, Array starts, Map request, Map predecessors) {
  Array pending = [];
  Map distances = {};
  foreach (Map start, starts) {
    String id = _sq_canonical(start, q.entities_by_id)["id"];
    distances[id] = 0;
    pending.push(id);
  }
  _sq_index_edges(q);
  int inward = _sq_inward(request), limit = _sq_depth(request);
  Map adjacency = inward ? q.incoming : q.outgoing;
  for (int index = 0; index < pending.len(); index++) {
    String id = pending[index];
    int depth = distances[id];
    if (depth == limit) continue;
    if (!adjacency.contains(id)) continue;
    foreach (Map edge, adjacency[id].array()) {
      if (!_sq_relation(edge, request)) continue;
      String source = edge.getdefault(inward ? "to" : "from", NULL);
      String target = edge.getdefault(inward ? "from" : "to", NULL);
      if (!source || !target || source != id ||
          distances.contains(target) ||
          !q.entities_by_id.contains(target)) continue;
      distances[target] = depth + 1;
      if ((void *) predecessors) predecessors[target] =
        {"previous": id, "edge": edge};
      pending.push(target);
    }
  }
  return distances;
}

static int _sq_reachable(SnapshotQuery &q, Map entity, Map request) {
  String key = Var.json(request);
  if (!q.reachable.contains(key)) {
    Map selector = request["select"];
    q.reachable[key] = _sq_walk(q, _sq_select(q, selector), request, NULL);
  }
  return q.reachable[key].map().contains(
    _sq_canonical(entity, q.entities_by_id)["id"]);
}

static int _sq_filter(SnapshotQuery &q, Map entity, Map filter) {
  foreach ((String key, Var value) in filter) {
    if (key == "all" || key == "any") {
      Array filters = value;
      int found = key == "all";
      foreach (Var child, filters) {
        int matches = _sq_filter(q, entity, child);
        if (key == "all" && !matches) { found = 0; break; }
        if (key == "any" && matches) { found = 1; break; }
      }
      if (!found) return 0;
    }
    else if (key == "not") {
      if (_sq_filter(q, entity, value)) return 0;
    }
    else if (key == "text") {
      String source = entity.getdefault("source", "");
      if (!source.contains(value)) return 0;
    }
    else if (key == "reachable_from") {
      if (!_sq_reachable(q, entity, value)) return 0;
    }
    else {
      if (!entity.contains(key) || !_sq_equal(entity[key], value)) return 0;
    }
  }
  return 1;
}

static Map _sq_summary(Map entity) {
  Map result = entity.copy();
  result.del("ast");
  result.del("source");
  return result;
}

static Map _sq_view(SnapshotQuery &q, Map entity, String view) {
  Map result = _sq_summary(entity);
  if (view == "summary") return result;
  String field = view == "typed_ast" ? "ast" : view;
  result[field] = entity.getdefault(field, NULL);
  if (view == "source" && entity["kind"] == "file")
    foreach (Map file, q.snapshot["files"].array())
      if (file["path"] == entity["file"]) result[field] = file["text"];
  return result;
}

static Map _sq_page(Map snapshot, Map request, Array rows) {
  int offset = request.getdefault("offset", 0);
  int limit = request.getdefault("limit", 100);
  Array ordered = _sq_sorted(rows), page = [];
  for (int i = offset; i < ordered.len() && page.len() < limit; i++)
    page.push(ordered[i]);
  return {"snapshot": snapshot["identity"],
    "coverage": snapshot["coverage"], "results": page,
    "total": ordered.len(), "offset": offset, "limit": limit,
    "truncated": Json.bool(offset > 0 ||
      offset + (int64_t) page.len() < ordered.len())};
}

static Array _sq_find(SnapshotQuery &q, Map request) {
  Map where = request.contains("where")
    ? request["where"].map() : {};
  Array rows = [];
  foreach (Map entity, _sq_select(q, where)) rows.push(_sq_summary(entity));
  return rows;
}

static Map _sq_inspect(SnapshotQuery &q, Map request) {
  Array selected = _sq_select(q, request["select"].map());
  Array rows = [];
  String view = request.getdefault("view", "summary");
  foreach (Map entity, selected)
    rows.push(_sq_view(q, entity, selected.len() == 1 ? view : "summary"));
  Map result = _sq_page(q.snapshot, request, rows);
  result["status"] = selected.len() == 1 ? "found"
    : selected.len() ? "ambiguous" : "not-found";
  return result;
}

static Array _sq_traverse(SnapshotQuery &q, Map request) {
  Array starts = _sq_select(q, request["select"].map());
  Map predecessors = {};
  Map distances = _sq_walk(q, starts, request, predecessors);
  Map where = request.contains("where")
    ? request["where"].map() : {};
  Array rows = [];
  foreach ((String id, Var distance) in distances) {
    Map entity = q.entities_by_id[id];
    if (!_sq_filter(q, entity, where)) continue;
    Map row = _sq_summary(entity);
    row["distance"] = distance;
    if (predecessors.contains(id))
      row["via"] = predecessors[id].map()["edge"];
    rows.push(row);
  }
  return rows;
}

static Map _sq_path(SnapshotQuery &q, Map request) {
  Array starts = _sq_select(q, request["select"].map());
  Array targets = _sq_select(q, request["target"].map());
  if (starts.len() != 1 || targets.len() != 1) {
    Map result = _sq_page(q.snapshot, request, []);
    result["status"] = !starts.len() || !targets.len()
      ? "not-found" : "ambiguous";
    Array from = [], to = [];
    foreach (Map entity, starts) from.push(_sq_summary(entity));
    foreach (Map entity, targets) to.push(_sq_summary(entity));
    result["starts"] = from;
    result["targets"] = to;
    return result;
  }
  Map predecessors = {};
  Map distances = _sq_walk(q, starts, request, predecessors);
  String target = _sq_canonical(targets[0], q.entities_by_id)["id"];
  Array rows = [];
  if (distances.contains(target)) {
    List nodes = NULL, edges = NULL;
    for (String id = target; id;) {
      nodes = cons(_sq_summary(q.entities_by_id[id]), nodes);
      if (!predecessors.contains(id)) break;
      Map step = predecessors[id];
      edges = cons(step["edge"], edges);
      id = step["previous"];
    }
    rows.push({"entities": nodes.array(),
               "edges": edges.array()});
  }
  Map result = _sq_page(q.snapshot, request, rows);
  result["status"] = rows.len() ? "found" : "no-recorded-path";
  return result;
}

/* Origins are provenance, not part of the structural pattern. */
static List _sq_structure(List node, Map known) {
  if (known.contains(node)) return known[node];
  List result = node;
  match (node) {
    case %(at ? ?body): result = _sq_structure(body, known);
    case %(src ? ?body): result = _sq_structure(body, known);
    default: {
      Array children = [];
      foreach (Var child, node)
        children.push(child is <list> ? _sq_structure(child, known) : child);
      result = children.list_free();
    }
  }
  known[node] = result;
  return result;
}

static String _sq_resolved(SnapshotQuery &q, Map entity, List type) {
  String declared = snapshot_text(type);
  String key = %"$(entity["domain"])::$(entity["unit"])::$declared";
  Map types = q.snapshot["types"];
  return types.getdefault(key, declared);
}

static int _sq_type_equal(String actual, String wanted) =>
  List.equal(snapshot_value(actual), snapshot_value(wanted));

static int _sq_binding(
  SnapshotQuery &q, Map entity, List node, String wanted) {
  List current;
  $ast.walk(node, current) match (current) {
    case %(binding ? ?name): {
      String key = _sq_binding_key(entity, snapshot_text(current));
      if (!q.bindings.contains(key)) continue;
      foreach (Map candidate, q.bindings[key].array()) {
        Map canonical = _sq_canonical(candidate, q.entities_by_id);
        if (candidate["id"] == wanted || candidate["name"] == wanted ||
            canonical["id"] == wanted || canonical["name"] == wanted)
          return 1;
      }
    }
  }
  return 0;
}

static int _sq_node_where(
  SnapshotQuery &q, Map entity, List node, List parents, Map filter);

static int _sq_node_filter(
  SnapshotQuery &q, Map entity, List node, List parents, Map request) {
  if (request.contains("node_where") &&
      !_sq_node_where(q, entity, node, parents,
        request["node_where"].map())) return 0;
  if (request.contains("inside")) {
    String wanted = request["inside"].str();
    int found = 0;
    foreach (Var head, parents) {
      String name = head.str();
      if (name == wanted || (wanted == "loop" &&
          (name == "for" || name == "while" || name == "do" ||
           name == "foreach"))) { found = 1; break; }
    }
    if (!found) return 0;
  }
  if (request.contains("binding") &&
      !_sq_binding(q, entity, node,
        request["binding"].str())) return 0;
  if (request.contains("callee")) {
    List callee = NULL;
    match (node) {
      case %(call ?function (args *)): callee = function;
      case %(expr ? (call ?function (args *))): callee = function;
    }
    if (!callee || !_sq_binding(q, entity, callee,
          request["callee"].str())) return 0;
  }
  foreach (String field, %("declared_type" "resolved_type")) {
    if (!request.contains(field)) continue;
    List type = NULL;
    match (node) case %(expr ?t ?): type = t;
    if (!type) return 0;
    String actual = field == "resolved_type"
      ? _sq_resolved(q, entity, type) : snapshot_text(type);
    if (!_sq_type_equal(actual, request[field].str())) return 0;
  }
  if (request.contains("argument_type")) {
    List arguments = NULL;
    match (node) {
      case %(call ? (args *args)): arguments = args;
      case %(expr ? (call ? (args *args))): arguments = args;
    }
    int found = 0;
    foreach (List argument, arguments)
      match (argument) case %(expr ?type ?):
        if (_sq_type_equal(_sq_resolved(q, entity, type),
              request["argument_type"].str())) {
          found = 1;
          break;
        }
    if (!found) return 0;
  }
  return 1;
}

/* Node predicates compose independently of entity selection predicates. */
static int _sq_node_where(
  SnapshotQuery &q, Map entity, List node, List parents, Map filter) {
  Map simple = {};
  foreach ((String key, Var value) in filter) {
    if (key == "all" || key == "any") {
      Array filters = value;
      int found = key == "all";
      foreach (Var child, filters) {
        int matches = _sq_node_where(q, entity, node, parents, child);
        if (key == "all" && !matches) { found = 0; break; }
        if (key == "any" && matches) { found = 1; break; }
      }
      if (!found) return 0;
    }
    else if (key == "not") {
      if (_sq_node_where(q, entity, node, parents, value)) return 0;
    }
    else {
      simple[key] = value;
    }
  }
  return _sq_node_filter(q, entity, node, parents, simple);
}

static Map _sq_location(List origin, Map entity) {
  Map row = {"file": entity["file"]};
  match (origin)
    case %(source ?file ?line ?column ?length ?offset): {
      row["file"] = file;
      row["line"] = line;
      row["column"] = column;
      row["length"] = length;
      row["offset"] = offset;
    }
  return row;
}

static void _sq_match_entity(
  SnapshotQuery &q, Map entity, Map request, MatchPlan pattern, Array rows) {
  String text = entity.getdefault("ast", NULL);
  if (!text) return;
  Array pending = [$(snapshot_value(text), (List) NULL, (List) NULL)];
  int ordinal = 0;
  Map structures = {};
  while (pending.len()) {
    List item = pending.take_last();
    List parents = item.cadr(), origin = item.caddr();
    Var raw = item.car();
    if (raw is not <list> || raw.is_nil()) continue;
    List node = raw;
    match (node) {
      case %(at ?location ?body): {
        pending.push($(body, parents, location));
        continue;
      }
      case %(src ?location ?body): {
        pending.push($(body, parents, origin));
        continue;
      }
    }
    List structural = _sq_structure(node, structures), captures;
    int matched = pattern.try_match(structural, captures);
    if (matched < 0) _sq_error("structural matching failed");
    if (matched == 1 &&
        _sq_node_filter(q, entity, structural, parents, request)) {
      Map row = _sq_location(origin, entity), bindings = {};
      foreach (List binding, captures)
        bindings[binding.car().str()] = snapshot_text(binding.cadr());
      row["entity"] = entity["id"];
      row["ordinal"] = ordinal;
      row["ast"] = snapshot_text(structural);
      row["captures"] = bindings;
      rows.push(row);
    }
    ordinal++;
    List ancestors = node.car().is_atom()
      ? cons(node.car(), parents) : parents;
    Array children = [];
    foreach (Var child, node)
      if (child is <list>) children.push($(child, ancestors, origin));
    for (int i = children.len() - 1; i >= 0; i--) pending.push(children[i]);
  }
}

static MatchPlan _sq_prepare_pattern(String text) {
  MatchPlan pattern = MatchPlan.prepare(snapshot_value(text));
  if (pattern.status == <malformed>) {
    pattern.free();
    _sq_error("malformed Match pattern");
  }
  if (pattern.status == <ineligible>) {
    const char *reason = pattern.reason;
    pattern.free();
    MatchPlan.raise_ineligible(reason, "graph query");
  }
  return pattern;
}

static Array _sq_match(
  SnapshotQuery &q, Map request, MatchPlan pattern) {
  Map selector = request.contains("select")
    ? request["select"].map() : {};
  Map where = request.contains("where")
    ? request["where"].map() : {};
  Array rows = [];
  foreach (Map entity, _sq_select(q, selector)) {
    // Whole-unit syntax overlaps the declaration subtrees searched by default.
    if (entity["kind"] == "unit" && !request.contains("select")) continue;
    if (_sq_filter(q, entity, where))
      _sq_match_entity(q, entity, request, pattern, rows);
  }
  return rows;
}

/* A direct name selector denotes one identity. Broader selectors, such as
   kind or an explicit any-set, deliberately select several entities. */
static Map _sq_name_ambiguity(SnapshotQuery &q, Map request) {
  if (!request.contains("select")) return NULL;
  Map selector = request["select"].map();
  if (!selector.contains("name") || selector.contains("id")) return NULL;
  Array candidates = _sq_select(q, selector);
  if (candidates.len() < 2) return NULL;
  Array rows = [];
  foreach (Map entity, candidates) rows.push(_sq_summary(entity));
  Map result = _sq_page(q.snapshot, request, rows);
  result["status"] = "ambiguous";
  return result;
}

/** Executes one data-only query without opening a compiler or source file. */
static Map _sq_execute(SnapshotQuery q, Map request) {
  String op = _sq_validate_query(request);
  MatchPlan pattern = auto op == "match"
    ? _sq_prepare_pattern(request["pattern"]) : NULL;
  q.reachable = {};
  if (op == "traverse" || op == "match") {
    Map ambiguous = _sq_name_ambiguity(q, request);
    if ((void *) ambiguous) return ambiguous;
  }
  Array rows = NULL;
  switch (op) {
    case "find": rows = _sq_find(q, request); break;
    case "inspect": return _sq_inspect(q, request);
    case "traverse": rows = _sq_traverse(q, request); break;
    case "path": return _sq_path(q, request);
    case "match": rows = _sq_match(q, request, pattern); break;
    default: _sq_error(%"unknown operation: $op");
  }
  return _sq_page(q.snapshot, request, rows);
}

/** Executes one query with indexes owned by the caller's lifetime. */
Map graph_snapshot_query(Map snapshot, Map request) =>
  _sq_execute(_sq_open(snapshot), request);

/* Every request owns its parse, reachability cache, Match plan, and reply.
   The session indexes are complete before this isolated lifetime opens. */
static int _sq_serve_request(SnapshotQuery session) {
  auto Context request = Context.open_isolated_named("graph query");
  Map response;
  try {
    String line = Stdin.readline();
    if (!line) return 0;
    Map query = _sq_object(Json.parse(line), "query");
    response = _sq_execute(session, query);
  }
  catch %(io-fail *detail): Error.raise(<io-fail>, detail);
  catch %(*failure): response = {"snapshot": session.snapshot["identity"],
    "coverage": session.snapshot["coverage"], "error": failure.repr()};
  Stdout.printf("%s\n", Var.json(response));
  Stdout.flush();
  return 1;
}

/** Serves ordered JSON lines against one immutable loaded snapshot. */
void graph_snapshot_serve(Map snapshot) {
  SnapshotQuery session = _sq_open(snapshot);
  _sq_index_edges(session);
  Stderr.printf("x2c graph serve: ready %s\n", snapshot["identity"]);
  while (_sq_serve_request(session)) {}
}

/* Only declaration ownership participates in cross-snapshot identity.
   Ambiguous keys are deliberately left unmatched. */
static Map _sq_entity_index(Array entities) {
  Map result = {};
  foreach (Map entity, entities) result[entity["id"]] = entity;
  return result;
}

static String _sq_declaration_key(Map entity, Map entities) {
  Array owners = [];
  String owner = entity.getdefault("owner", NULL);
  while (owner && entities.contains(owner)) {
    Map parent = entities[owner];
    owners.push([parent["kind"], parent["name"],
                 parent.getdefault("namespace", NULL),
                 parent.getdefault("file", NULL)]);
    owner = parent.getdefault("owner", NULL);
  }
  return Var.json([entity.getdefault("domain", NULL),
    entity.getdefault("unit", NULL), entity.getdefault("file", NULL),
    entity["kind"], entity["name"], entity.getdefault("namespace", NULL), owners]);
}

static Map _sq_declarations(Array entities, Map by_id) {
  Map indexed = {};
  foreach (Map entity, entities) {
    if (entity.contains("canonical")) continue;
    String key = _sq_declaration_key(entity, by_id);
    if (indexed.contains(key)) indexed[key] = NULL;
    else indexed[key] = entity;
  }
  return indexed;
}

static Map _sq_signature(Map entity) =>
  {"declared_type": entity.getdefault("declared_type", NULL),
   "resolved_type": entity.getdefault("resolved_type", NULL),
   "visibility": entity.getdefault("visibility", NULL)};

static Map _sq_edge_set(Map snapshot, Map by_id) {
  Map entities = {}, result = {};
  foreach (Map entity, snapshot["entities"].array())
    entities[entity["id"]] =
      _sq_declaration_key(_sq_canonical(entity, by_id), by_id);
  foreach (Map edge, snapshot["edges"].array()) {
    Map relation = edge.copy();
    Var from = edge.getdefault("from", NULL);
    Var to = edge.getdefault("to", NULL);
    relation["from"] = entities.getdefault(from, from);
    relation["to"] = entities.getdefault(to, to);
    relation.del("line");
    relation.del("column");
    relation.del("offset");
    relation.del("length");
    String key = Var.json(relation);
    result[key] = relation;
  }
  return result;
}

/** Compares declared identities and relationships without guessing renames. */
Map graph_snapshot_diff(Map before, Map after) {
  Map old_ids = _sq_entity_index(before["entities"]);
  Map new_ids = _sq_entity_index(after["entities"]);
  Map old = _sq_declarations(before["entities"], old_ids);
  Map current = _sq_declarations(after["entities"], new_ids);
  Array added = [], removed = [], changed = [];
  Array added_edges = [], removed_edges = [];
  foreach (Map entity, before["entities"].array()) {
    if (entity.contains("canonical")) continue;
    String key = _sq_declaration_key(entity, old_ids);
    if (!old.getdefault(key, NULL) || !current.getdefault(key, NULL))
      removed.push(_sq_summary(entity));
    else {
      Map replacement = current[key];
      if (!_sq_equal(_sq_signature(entity), _sq_signature(replacement)))
        changed.push({"before": _sq_summary(entity),
                      "after": _sq_summary(replacement)});
    }
  }
  foreach (Map entity, after["entities"].array()) {
    if (entity.contains("canonical")) continue;
    String key = _sq_declaration_key(entity, new_ids);
    if (!old.getdefault(key, NULL) || !current.getdefault(key, NULL))
      added.push(_sq_summary(entity));
  }
  Map old_edges = _sq_edge_set(before, old_ids);
  Map new_edges = _sq_edge_set(after, new_ids);
  foreach ((String key, Var edge) in old_edges)
    if (!new_edges.contains(key)) removed_edges.push(edge);
  foreach ((String key, Var edge) in new_edges)
    if (!old_edges.contains(key)) added_edges.push(edge);
  return {"before": before["identity"], "after": after["identity"],
    "added": _sq_sorted(added), "removed": _sq_sorted(removed),
    "changed": _sq_sorted(changed), "added_relations": _sq_sorted(added_edges),
    "removed_relations": _sq_sorted(removed_edges)};
}
