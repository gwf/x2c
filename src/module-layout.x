/* module-layout.x -- complete aggregate prerequisites for module emission */
#pragma once
#include "compiler.x"
#include "module-tree.x"
#include "ast-rewrite.x"
#include "format.x"
#include "generate.x"
#include "collect.x"
#include "utils.x"

static typedef struct Layouts {
  Map bodies, private_types, private_bindings;
} Layouts;

static String Compiler._layout_file_spelling(Compiler c, String name) =>
  c._layout_provider_spelling(c.canonical_path(c.filename), name);

static String Compiler._layout_provider_spelling(
  Compiler c, String path, String name) {
  String owner = c.module_tree.owner(path);
  String directory = Path.dirname(owner);
  String relative = path[directory.len() + 1:];
  String module = c.module_tree.prefix(owner);
  String identity = %"$module/$relative";
  return %"_x2c_file_${filename_hash(identity)}__$name";
}

static void Layouts.private_names(Layouts &l, Compiler c, List ast) {
  Map names = {}, bindings = {};
  if (c.module_owner) foreach (List node, ast)
    match (node) case %((!or typedef declare) ?base (bindings *rows)): {
      Type type = base;
      if (!type.is_static()) continue;
      match (type.base_type())
        case %((!set ?kind (!or struct union enum)) ?(String name) *):
          if (!c.sym.get_exact(%("module-opaque" $name)))
            names[%($kind $name)] = c._layout_file_spelling(name);
      match (type.base_type()) case %(enum ?(String tag) ?members): {
        (void) tag;
        foreach (List member, members) {
          match (member) case %(op = ?target ?): member = target;
          String name = binding_identity_spelling(member);
          if (!name) continue;
          bindings[member] = binding_identity_new(
            member.cadr(), c._layout_file_spelling(name));
        }
      }
      if (node.car() != <typedef>) continue;
      foreach (List row, rows)
        match (row) case %(bind ?identity *): {
          String name = binding_identity_spelling(identity);
          if (!name || c.sym.get_exact(%("module-opaque" $name))) continue;
          String spelling = c._layout_file_spelling(name);
          names[%(typedef $name)] = spelling;
          bindings[identity] = binding_identity_new(
            identity.list().cadr(), spelling);
        }
    }
  String path = c.canonical_path(c.filename);
  l.private_types[path] = names;
  l.private_bindings[path] = bindings;
}

static Type _layout_private_type(Type type, Map names) {
  if (!type) return type;
  Type base = type.base_type();
  List key = base;
  match (base) {
    case %(?(String name)): key = %(typedef $name);
    case %((!set ?kind (!or struct union enum)) ?(String name) *):
      key = %($kind $name);
  }
  Var spelling;
  if (!names.try_get(key, spelling)) return type;
  List replacement = base.car() is <string> ? %($spelling)
    : cons(base.car(), cons(spelling, base.cddr()));
  return type.list()[:type.list().len() - base.len()].append(replacement);
}

/* Only type positions and exact typedef bindings receive emitted spellings.
   Block-local tags and aliases retain their bound identities. */
static List _layout_private_node(List node, Map names, Map bindings) {
  Var identity;
  if (bindings.try_get(node, identity)) return identity;
  match (node)
    case %((!set ?kind
                  (!or decl declare typedef function param expr cast offsetof))
           ?type *rest):
      node = %($kind ${_layout_private_type(type, names)} @rest);
  List child;
  $ast.rewrite_children(
    node, child, _layout_private_node(child, names, bindings));
}

/* Index already bound source nodes. Native directives retain the provider's
   order; source-module includes are supplied by the layout prerequisites. */
/* Array elements require their aggregate's body. A pointer terminates the
   demand, including a typedef that resolves to an array of pointers. */
static void Layouts.require_type(
  Layouts &l, Compiler c, Sym resolver, Type type, Map needed) {
  type = resolver.normalize_declared_type(type).canonicalize();
  Map private_types = l.private_types[c.canonical_path(c.filename)];
  type = _layout_private_type(type, private_types);
  while (type.is_array()) type = type.dereference().canonicalize();
  if (type.is_pointer() || type.is_function()) return;
  Type key = resolver.resolve_key(type);
  List module_key = c.module_retry_key(key);
  if (module_key) key = module_key;
  match (key)
    case %((!set ?kind (!or struct union enum)) ?(String name) *): {
      List family = %($kind $name);
      if (family in l.bodies) needed[family] = 1;
      else foreach (List row, c.sym.field_order(key).cdr())
        l.require_type(c, resolver, row.cadr(), needed);
      return;
    }
  match (key) case %((!or struct union) (fields *rows)):
    foreach (List row, rows) {
      List declaration = Ast.without_origin(row);
      if (declaration.car() == <c-assert> || declaration.car() == <preproc>)
        continue;
      Type field = declaration.type_from_ast();
      l.require_type(c, resolver, field, needed);
    }
}

/** Rewrites the indexed file-private spellings without moving declarations. */
List Compiler.module_layout_node(Compiler c, List node) {
  if (!c.module_layout_plan) return node;
  String path = c.canonical_path(c.filename);
  Map names = c.module_layout_plan[%(private-types $path)],
    bindings = c.module_layout_plan[%(private-bindings $path)];
  return names ? _layout_private_node(node, names, bindings) : node;
}

/* A selected native field contributes its actual complete-family demand.
   The native preprocessor removes markers in inactive conditional fields. */
static List Layouts.mark_fields(
  Layouts &l, Compiler c, Sym resolver, List fields) {
  Array marked = [];
  foreach (List field, fields) {
    List declaration = Ast.without_origin(field);
    Map needed = {};
    Array demands = [];
    if (declaration.car() == <declare>) {
      Type source = declaration.cadr();
      List core = source.base_type(), replacement = NULL;
      match (core) {
        case %((!set ?tag (!or struct union)) ?name (fields *rows)):
          replacement = %($tag $name
            (fields @{l.mark_fields(c, resolver, rows)}));
        case %((!set ?tag (!or struct union)) (fields *rows)):
          replacement = %($tag
            (fields @{l.mark_fields(c, resolver, rows)}));
      }
      if (replacement) {
        List prefix = source.list()[:source.list().len() - core.len()];
        declaration = %(declare ${prefix.append(replacement)}
          ${declaration.caddr()});
        field = Ast.rewrap_origin(field, declaration);
      } else {
        Map namespaces = declaration_type_namespaces(
          declaration, resolver.unit_symbols());
        foreach (List namespace, namespaces.keys()) {
          String id = c.module_projection_namespace(namespace);
          if (id) demands.push(%"#pragma x2c_namespace_require $id");
        }
        foreach (List row, declaration.caddr().list().cdr()) {
          Type type = %(declare ${declaration.cadr()} (bindings $row))
            .type_from_ast();
          l.require_type(c, resolver, type, needed);
        }
      }
    }
    foreach (List dependency, needed.keys()) {
      String id = filename_hash(dependency.repr());
      demands.push(%"#pragma x2c_family_require f_$id");
    }
    foreach (String demand, demands.sort()) marked.push(%(preproc $demand));
    marked.push(field);
  }
  return marked.list_free();
}

/** Marks a typedef's selected namespace and complete array-element needs. */
List Compiler.module_layout_alias_demands(Compiler c, List node) {
  if (!c.module_layout_plan || node.car() != <typedef>) return NULL;
  String path = c.canonical_path(c.filename);
  Map rows = c.sym.unit_symbols();
  Sym resolver = Sym.new(c);
  resolver.reset_overlay(rows, c.module_layout_plan[%(projection-aliases)]);
  Map namespaces = declaration_type_namespaces(node, rows);
  Array marked = [], demands = [];
  foreach (List namespace, namespaces.keys()) {
    String id = c.module_projection_namespace(namespace);
    if (id) demands.push(%"#pragma x2c_namespace_require $id");
  }
  Map private_types = {}, needed = {};
  private_types[path] = c.module_layout_plan[%(private-types $path)];
  Layouts layouts = {
    .bodies = c.module_layout_plan[%(projection-bodies)],
    .private_types = private_types};
  foreach (List row, node.caddr().list().cdr()) {
    Type type = %(declare ${node.cadr()} (bindings $row)).type_from_ast();
    if (type.is_array()) layouts.require_type(c, resolver, type, needed);
  }
  foreach (List dependency, needed.keys()) {
    String id = filename_hash(dependency.repr());
    demands.push(%"#pragma x2c_family_require f_$id");
  }
  foreach (String demand, demands.sort()) marked.push(%(preproc $demand));
  return marked.list_free();
}

/** Marks conditional complete-field demands in the portable native body.
    Markers refer to already established families and do not bind declarations.
*/
List Compiler.module_layout_demands(Compiler c, List node) {
  if (!c.module_layout_plan) return node;
  String path = c.canonical_path(c.filename);
  Map names = c.module_layout_plan[%(private-types $path)];
  Map private_types = {};
  private_types[path] = names;
  Layouts layouts = {
    .bodies = c.module_layout_plan[%(projection-bodies)],
    .private_types = private_types};
  Sym resolver = Sym.new(c);
  Map rows = c.sym.unit_symbols();
  resolver.reset_overlay(rows, c.module_layout_plan[%(projection-aliases)]);
  match (node) case %((!or typedef declare) ?base ?bindings): {
    Type type = base;
    List core = type.base_type();
    match (core)
      case %((!set ?tag (!or struct union)) ?name (fields *fields)): {
        List marked = layouts.mark_fields(c, resolver, fields);
        List replacement = %($tag $name (fields @marked));
        List prefix = base.list()[:base.list().len() - core.len()];
        return %(${node.car()} ${prefix.append(replacement)} $bindings);
      }
  }
  return node;
}

/* Declaration collection supplies this registry before any implementation is
   bound. Each provider later contributes generated text while its own unit
   is active; the registry retains no compiler, symbol scope, or AST owner. */
static List _registry_namespace(List key, List syntax, Map rows) {
  match (key)
    case %((!set ?kind (!or typedef struct union enum)) ?name *):
      return %($kind $name);
  List family = declaration_type_family(rows, {}, key, syntax);
  return family ? family : key;
}

static String _registry_namespace_id(Compiler c, String path, List key) {
  String logical = c.module_tree.identity(c.canonical_path(home_absolute_path(path)));
  return %"n_${filename_hash(%($logical $key).repr())}";
}

/** Indexes original declaration namespaces and their exact provider edges. */
Map prepare_module_layout_registry(Compiler c, List providers) {
  Map plan = {}, definitions = {}, identities = {}, requirements = {};
  plan[%(native-projection)] = 1;
  plan[%(projection-families)] = {};
  plan[%(projection-bodies)] = {};
  plan[%(projection-aliases)] = {};
  foreach (String provider, providers) {
    String path = c.canonical_path(provider);
    plan[%(files $path)] = %();
  }
  List details = c.declaration_detail_rows(providers);
  Map original = {};
  foreach (List row, details) {
    (Var kind, String path, List key, List syntax, int privacy) = row;
    (void) kind;
    (void) privacy;
    original.setdefault(path, {}).map()[key] = syntax;
  }
  foreach (List row, details) {
    (Var kind, String path, List key, List syntax, int privacy) = row;
    (void) kind;
    String canonical = c.canonical_path(home_absolute_path(path));
    if (!privacy || !c.module_tree.owner(canonical)) continue;
    List namespace = _registry_namespace(key, syntax, original[path]);
    match (namespace)
      case %((!or typedef struct union enum) ?(String name)): {
        if (c.sym.get_exact(%("module-opaque" $name))) continue;
        Map names = plan.setdefault(%(private-types $canonical), {});
        names[namespace] = c._layout_provider_spelling(canonical, name);
      }
  }
  foreach (List row, details) {
    (Var kind, String path, List key, List syntax, int privacy) = row;
    (void) kind;
    (void) privacy;
    List namespace = _registry_namespace(key, syntax, original[path]), emitted = namespace;
    String canonical = c.canonical_path(home_absolute_path(path));
    Map names = plan.getdefault(%(private-types $canonical), {});
    Var spelling;
    if (names.try_get(namespace, spelling))
      emitted = %(${namespace.car()} $spelling);
    String id = _registry_namespace_id(c, path, emitted);
    String identity = %($path $emitted).repr();
    Var previous;
    if (identities.try_get(id, previous) && previous != identity)
      c.report_error(<module>, "module namespace identity collision",
                     NULL, %($previous $identity));
    identities[id] = identity;
    plan[%(namespace $path $key)] = id;
    plan[%(namespace $path $namespace)] = id;
    definitions[%($path $namespace)] = id;
    if (!is_source_file(canonical)) plan[%(namespace-provider $id)] = canonical;
    match (namespace)
      case %((!set ?tag (!or struct union enum)) ?name):
        plan[%(projection-bodies)].map()[emitted] = 1;
    match (key) case %(typedef ?name): {
      Map aliases = plan[%(projection-aliases)];
      aliases[emitted] = _layout_private_type(syntax, names);
      aliases[%(${emitted.cadr()})] = emitted;
    }
  }
  foreach (List row, c.declaration_prerequisite_rows(providers)) {
    (Var kind, String path, List key, String required, List target) = row;
    (void) kind;
    List namespace = _registry_namespace(key, NULL, original.getdefault(path, {}));
    Var consumer, dependency;
    if (!plan.try_get(%(namespace $path $namespace), consumer) ||
        !plan.try_get(%(namespace $required $target), dependency)) continue;
    Array edges = requirements.setdefault(consumer, []);
    if (!(dependency in edges)) edges.push(dependency);
  }
  plan[%(namespace-definitions)] = definitions;
  plan[%(namespace-requires)] = requirements;
  return plan;
}

/** Returns an original provider's namespace vertex before private rewriting. */
String Compiler.module_namespace_id(Compiler c, String path, List key) {
  if (!c.module_layout_plan) return NULL;
  path = home_portable_path(c.canonical_path(home_absolute_path(path)));
  Var id;
  return c.module_layout_plan.try_get(%(namespace $path $key), id) ? id : NULL;
}

/** Retains one active provider's private emitted spellings, without its AST. */
Map capture_module_provider(Compiler c, List ast) {
  Layouts layouts = {
    .private_types = {}, .private_bindings = {}};
  layouts.private_names(c, ast);
  String path = c.canonical_path(c.filename);
  return {
    %(private-types $path): layouts.private_types[path],
    %(private-bindings $path): layouts.private_bindings[path]
  };
}
