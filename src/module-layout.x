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
  Map bodies, variants, aliases, alias_variants, owners, edges;
  Map variant_demands;
  Map fixed_edges, visiting, finished;
  Map private_types, private_bindings, private_constants, used_aliases;
  Array order;
} Layouts;

static String _layout_guard(List family) =>
  %"__X2C_LAYOUT_${filename_hash(family.repr())}__";

static String _layout_header(List family) =>
  %"_x2c_layout_${filename_hash(family.repr())}.h";

static List _layout_family(Type type) {
  match (type.base_type())
    case %((!set ?kind (!or struct union enum)) ?(String name) (*)):
      return %($kind $name);
  return NULL;
}

static List _layout_core(Type type) {
  List core = type.base_type();
  return _layout_family(type) ? core : NULL;
}

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
  Map names = {}, bindings = {}, constants = {};
  if (c.module_owner) foreach (List node, ast)
    match (node) case %((!or typedef declare) ?base (bindings *rows)): {
      Type type = base;
      if (!type.is_static()) continue;
      match (type.base_type())
        case %((!set ?kind (!or struct union enum)) ?(String name) *):
          names[%($kind $name)] = c._layout_file_spelling(name);
      match (type.base_type()) case %(enum ?(String tag) ?members): {
        List family = %(enum ${c._layout_file_spelling(tag)});
        foreach (List member, members) {
          match (member) case %(op = ?target ?): member = target;
          String name = binding_identity_spelling(member);
          if (!name) continue;
          bindings[member] = binding_identity_new(
            member.cadr(), c._layout_file_spelling(name));
          constants[member] = family;
        }
      }
      if (node.car() != <typedef>) continue;
      foreach (List row, rows)
        match (row) case %(bind ?identity *): {
          String name = binding_identity_spelling(identity);
          if (!name) continue;
          String spelling = c._layout_file_spelling(name);
          names[%(typedef $name)] = spelling;
          bindings[identity] = binding_identity_new(
            identity.list().cadr(), spelling);
        }
    }
  String path = c.canonical_path(c.filename);
  l.private_types[path] = names;
  l.private_bindings[path] = bindings;
  l.private_constants[path] = constants;
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
    case %((!set ?kind (!or declare typedef function param expr cast offsetof))
           ?type *rest):
      node = %($kind ${_layout_private_type(type, names)} @rest);
  List child;
  $ast.rewrite_children(
    node, child, _layout_private_node(child, names, bindings));
}

/* Index already bound source nodes. Native directives retain the provider's
   order; source-module includes are supplied by the layout prerequisites. */
static void Layouts.provider(Layouts &l, Compiler c, List ast) {
  String path = c.canonical_path(c.filename);
  Map names = l.private_types[path],
    bindings = l.private_bindings[path];
  Array prefix = [];
  List arms = NULL;
  foreach (List node, ast) {
    node = _layout_private_node(node, names, bindings);
    match (node) {
      case %(preproc ?(String text)): {
        arms = preproc_track_arms(arms, text);
        int angle = 0;
        String target = preproc_include_target(text, angle);
        if (target && is_source_file(target)) {
          String path = c.resolve_source_include(target, angle);
          if (path && c.module_tree.owner(path)) continue;
        }
        if (text.strip(" \t\r\n") != "#pragma once") prefix.push(node);
        continue;
      }
      case %(function *): {
        prefix.push(node);
        continue;
      }
      case %((!set ?kind (!or typedef declare)) ?base ?bindings): {
        Type type = base;
        if (type.is_static() && !c.module_owner) continue;
        List family = _layout_family(type);
        if (kind == <typedef>) {
          List alias_base = base;
          List core = _layout_core(type);
          if (core)
            alias_base = base.list()[:base.list().len() - core.len()]
              .append(%(${family.car()} ${family.cadr()}));
          foreach (List declarator, bindings.list().cdr()) {
            String name = binding_identity_spelling(declarator.cadr());
            if (name)
              {
                List alias = %(typedef $alias_base (bindings $declarator));
                l.aliases[name] = %($c $alias);
                l.alias_variants[name] = cons(
                  %($c $alias ${prefix.list()} $arms),
                  l.alias_variants[name]);
              }
          }
        }
        if (!family) {
          prefix.push(node);
          continue;
        }
        List body = kind == <typedef> ? node
          : %(declare $base (bindings (bind () ())));
        l.bodies[family] = %($c $body);
        l.variants[family] = cons(
          %($c $body ${prefix.list()} $arms), l.variants[family]);
        l.owners[family] = c.canonical_path(c.filename);
      }
    }
  }
}

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
  match (key)
    case %((!set ?kind (!or struct union enum)) ?name): {
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

/* Preserve field conditions beside their demands. Inline anonymous bodies
   retain their bound declaration syntax; semantic types omit directives. */
static void Layouts.require_fields(
  Layouts &l, Compiler c, Sym resolver, List fields, Map needed,
  Array demands, Map recorded, List inherited) {
  Array prefix = [];
  List arms = NULL;
  foreach (List directive, inherited) {
    prefix.push(directive);
    arms = preproc_track_arms(arms, directive.cadr());
  }
  foreach (List field, fields) {
    List declaration = Ast.without_origin(field);
    match (declaration) {
      case %(preproc ?(String text)): {
        String directive = preproc_directive(text);
        if (preproc_conditional_kind(text) || directive.startswith("define") ||
            directive.startswith("undef")) {
          prefix.push(declaration);
          arms = preproc_track_arms(arms, text);
        }
      }
      case %(declare ?base (bindings *declarators)):
        foreach (List declarator, declarators) {
          Type type = %(declare $base (bindings $declarator)).type_from_ast();
          Type element = resolver.normalize_declared_type(type).canonicalize();
          while (element.is_array())
            element = element.dereference().canonicalize();
          if (element.is_pointer() || element.is_function()) continue;
          Type source = base;
          List inline_fields = NULL;
          match (source.base_type()) {
            case %((!or struct union) ? (fields *rows)): inline_fields = rows;
            case %((!or struct union) (fields *rows)): inline_fields = rows;
          }
          if (inline_fields) {
            l.require_fields(
              c, resolver, inline_fields, needed,
              demands, recorded, prefix);
            continue;
          }
          Map selected = {};
          l.require_type(c, resolver, type, selected);
          foreach (List dependency, selected.keys()) {
            needed[dependency] = 1;
            List demand = %($dependency ${prefix.list()} $arms);
            if (!(demand in recorded)) {
              recorded[demand] = 1;
              demands.push(demand);
            }
          }
        }
    }
  }
}

static void Layouts.require_body(
  Layouts &l, Compiler c, Sym resolver, List body, Map needed,
  Array demands) {
  Type type = body.cadr();
  Map recorded = {};
  match (type.base_type())
    case %((!or struct union) ? (fields *fields)):
      l.require_fields(
        c, resolver, fields, needed, demands, recorded, NULL);
}

static void Layouts.dependencies(Layouts &l) {
  Map aliases = {};
  foreach (Var (name, row), l.aliases) {
    List alias = row.list().cadr();
    aliases[%(typedef $name)] = alias.type_from_ast().declared();
    aliases[%($name)] = %(typedef $name);
  }
  foreach (List family, l.bodies.keys()) {
    Map needed = {};
    Map fixed = NULL;
    int unconditional = 1;
    foreach (List variant, l.variants[family].list()) {
      (Compiler owner, List body, List prefix, List arms) = variant;
      Sym resolver = Sym.new(owner);
      resolver.reset_overlay(owner.sym.global_symbols(), aliases);
      Map selected = {};
      Array demands = [];
      l.require_body(owner, resolver, body, selected, demands);
      Map fixed_variant = {};
      foreach (List demand, demands.list())
        if (!demand.caddr().list().len()) fixed_variant[demand.car()] = 1;
      foreach (List prerequisite, selected.keys()) needed[prerequisite] = 1;
      l.variant_demands[variant] = demands.list_free();
      if (!fixed) fixed = fixed_variant;
      else {
        Map intersection = {};
        foreach (List prerequisite, fixed.keys())
          if (prerequisite in fixed_variant) intersection[prerequisite] = 1;
        fixed = intersection;
      }
      if (arms.len()) unconditional = 0;
    }
    Array prerequisites = [];
    foreach (List prerequisite, needed.keys())
      prerequisites.push(prerequisite);
    l.edges[family] = prerequisites.list_free();
    Array fixed_edges = [];
    if (unconditional) foreach (List prerequisite, fixed.keys())
      fixed_edges.push(prerequisite);
    l.fixed_edges[family] = fixed_edges.list_free();
  }
}

static void Layouts.visit(Layouts &l, List family) {
  if (family in l.finished) return;
  if (family in l.visiting) {
    Compiler c = l.bodies[family].list().car();
    c.report_error(
      <type>, "complete aggregate layout cycle", NULL,
      %($family "provider: ${l.owners[family]}"));
  }
  l.visiting[family] = 1;
  foreach (List prerequisite, l.fixed_edges[family].list())
    l.visit(prerequisite);
  l.visiting.del(family);
  l.finished[family] = 1;
  l.order.push(family);
}

static String _layout_text(Compiler c, List nodes) {
  Array support = [];
  foreach (List node, nodes) {
    match (node) case %(typedef ?base ?bindings): {
      Array specifiers = [];
      foreach (Var item, base) if (item != <static>) specifiers.push(item);
      node = %(typedef ${specifiers.list_free()} $bindings);
    }
    support.push(node);
  }
  return c.code_pretty_string(c.emit(support.list_free(), NULL), c.filename);
}

/* Own source guards suppress support bodies during ancestor includes.
   Named aggregate aliases need declarations before those includes even
   when no cross-file complete-layout edge exists. */
static List _layout_forward(Compiler c, List node) {
  Type type = node.cadr();
  if (type.is_static() || type.base_type().car() == <enum>) return NULL;
  List family = _layout_family(type);
  if (family) {
    List core = type.base_type();
    type = type.list()[:type.list().len() - core.len()].append(family);
  }
  Array rows = [];
  foreach (List declarator, node.caddr().list().cdr()) {
    Type alias = %(typedef $type (bindings $declarator)).type_from_ast();
    Type element = c.sym.normalize_declared_type(alias).canonicalize();
    int array = element.is_array();
    while (element.is_array()) element = element.dereference();
    if (!array || element.is_pointer()) rows.push(declarator);
  }
  return rows.len() ? %(typedef $type (bindings @{rows.list_free()})) : NULL;
}

static List _layout_forward_prefix(Compiler c, List prefix) {
  Array nodes = [];
  foreach (List node, prefix) {
    if (node.car() == <typedef>) node = _layout_forward(c, node);
    if (node) nodes.push(node);
  }
  return nodes.list_free();
}

static String Layouts.forwards(
  Layouts &l, Compiler c, List ast, Map plan) {
  Map done = {}, visiting = {};
  Array nodes = [];
  foreach (List node, ast)
    match (node) case %(typedef ?base (bindings *rows)):
      if (!base.list().type().is_static())
        foreach (List row, rows) {
          String name = binding_identity_spelling(row.cadr());
          if (name && name in l.aliases)
            l.alias(name, done, visiting, nodes, plan, 1);
        }
  return _layout_text(c, nodes.list_free());
}

/* Public inline bodies capture native state at their authored position.
   Keep them with the prefix, under individual guards, rather than moving
   their native includes ahead of the bodies. */
static List Layouts.prefix(
  Layouts &l, Compiler c, List prefix, Map plan, List definitions) {
  Array nodes = [];
  foreach (List node, prefix) {
    match (node) case %(typedef ?base *): {
      Type type = base;
      match (type.base_type()) case %(?(String dependency)):
        if (dependency in l.aliases)
          foreach (List prerequisite, l.alias_nodes(node, plan))
            nodes.push(prerequisite);
    }
    match (node)
      case %(function ?type (bind ?binding *) ?): {
        Type signature = type;
        if (signature.is_inline() && !signature.is_static()) {
          String hash = filename_hash(binding.repr());
          String guard = %"__X2C_LAYOUT_INLINE_${hash}__";
          plan[%(inline ${c.canonical_path(c.filename)} $binding)] = guard;
          List header = c.module_layout_header_prefix(%($node), NULL);
          String body = _layout_text(c, header);
          String guarded = %"#ifndef $guard\n#define $guard\n$body\n#endif\n";
          node = %(preproc $guarded);
        }
      }
    nodes.push(node);
  }
  return c.module_layout_header_prefix(nodes.list_free(), definitions);
}

static void Layouts.alias(
  Layouts &l, String name, Map done, Map visiting, Array nodes,
  Map plan, int forwards) {
  if (name in done) return;
  if (name in visiting) {
    Compiler c = l.aliases[name].list().car();
    c.report_error(
      <type>, "layout typedef prerequisite cycle", NULL, %($name));
  }
  visiting[name] = 1;
  String text = "";
  foreach (List variant, l.alias_variants[name].list().reverse()) {
    (Compiler c, List node, List prefix, List arms) = variant;
    Type type = node.cadr();
    match (type.base_type()) case %(?(String dependency)):
      if (dependency in l.aliases)
        l.alias(dependency, done, visiting, nodes, plan, forwards);
    if (forwards) {
      node = _layout_forward(c, node);
      prefix = _layout_forward_prefix(c, prefix);
    }
    if (!node) continue;
    List macros = _layout_macro_names(prefix);
    text += _layout_macro_guards(macros, "push");
    text += _layout_text(c, l.prefix(c, prefix, plan, %($node)));
    for (int i = arms.len(); i; i--) text += "#endif\n";
    text += _layout_macro_guards(macros.reverse(), "pop");
  }
  visiting.del(name);
  done[name] = 1;
  l.used_aliases[name] = 1;
  if (text.len()) {
    String guard = _layout_guard(%(alias $forwards $name));
    String guarded = %"#ifndef $guard\n#define $guard\n$text\n#endif\n";
    nodes.push(%(comment $guarded));
  }
}

static List Layouts.alias_nodes(Layouts &l, List body, Map plan) {
  Map needed = {}, done = {}, visiting = {};
  List node;
  $ast.walk(body, node) {
    match (node) case %((!or typedef declare) ?base *): {
      Type type = base;
      match (type.base_type()) case %(?(String name)):
        if (name in l.aliases) needed[name] = 1;
    }
  }
  Array nodes = [];
  foreach (String name, needed.keys())
    l.alias(name, done, visiting, nodes, plan, 0);
  return nodes.list_free();
}

/* A copied definition's directives must not set source-position macros
   before their authored position. Save explicit define/undef names. */
static List _layout_macro_names(List prefix) {
  Map names = {};
  foreach (List node, prefix) {
    if (node.car() != <preproc>) continue;
    String directive = preproc_directive(node.cadr());
    if (!directive.startswith("define") && !directive.startswith("undef"))
      continue;
    Tokenizer scan = Tokenizer.new(directive, <x2c>);
    scan.scan();
    Token keyword = Token.skip_trivia(scan.tokens);
    Token name = Token.skip_trivia(keyword + 1);
    if (name.type == <ident>) names[name.text] = 1;
  }
  Array found = [];
  foreach (String name, names.keys()) found.push(name);
  return found.list_free();
}

static String _layout_macro_guards(List names, String operation) {
  String text = "";
  foreach (String name, names)
    text += %"#pragma ${operation}_macro(\"$name\")\n";
  return text;
}

/* Array aliases in the preceding prefix need complete elements too. Their
   prerequisites run at that position, inside any preceding native arms.
   The final copy also supplies the body when an earlier arm was inactive. */
static List _layout_prerequisite_prefix(
  Compiler c, List prefix, String prerequisites) {
  Array nodes = [];
  foreach (List node, prefix) {
    if (node.car() == <typedef> && !_layout_forward(c, node))
      nodes.push(%(comment $prerequisites));
    nodes.push(node);
  }
  return nodes.list_free();
}

/* A prerequisite include runs only in its selected native arm. Separate
   visiting and completion guards diagnose active cycles without expanding
   shared dependency paths into repeated generated bodies. */
static String Layouts.render(
  Layouts &l, List family, Map plan) {
  String guard = _layout_guard(family), visiting = %"${guard}_VISITING";
  String text = %"#ifndef $guard\n#ifdef $visiting\n" +
    %"#error complete aggregate layout cycle\n#else\n#define $visiting\n";
  foreach (List variant, l.variants[family].list().reverse()) {
    (Compiler c, List body, List prefix, List arms) = variant;
    String prerequisites = "";
    foreach (List demand, l.variant_demands[variant].list()) {
      (List dependency, List directives, List field_arms) = demand;
      List macros = _layout_macro_names(directives);
      prerequisites += _layout_macro_guards(macros, "push");
      prerequisites += _layout_text(c, directives);
      prerequisites += %"#include \"${_layout_header(dependency)}\"\n";
      for (int i = field_arms.len(); i; i--) prerequisites += "#endif\n";
      prerequisites += _layout_macro_guards(macros.reverse(), "pop");
    }
    List macros = _layout_macro_names(prefix);
    List definitions = %((comment $prerequisites))
      .append(l.alias_nodes(body, plan))
      .append(%($body (preproc ${%"#define $guard"})));
    text += %"#ifndef $guard\n";
    text += _layout_macro_guards(macros, "push");
    List preceding = _layout_prerequisite_prefix(c, prefix, prerequisites);
    List header = l.prefix(c, preceding, plan, definitions);
    text += _layout_text(c, header);
    for (int i = arms.len(); i; i--) text += "#endif\n";
    text += _layout_macro_guards(macros.reverse(), "pop");
    text += "#endif\n";
  }
  text += %"#undef $visiting\n#endif\n#endif\n";
  plan[%(body $family)] = guard;
  return text;
}

/** Renders complete-layout headers while bound providers remain alive.
    Consumers export only Strings and keys as their nested Contexts close. */
Map prepare_module_layouts(List providers) {
  Layouts layouts = {
    .bodies = {}, .variants = {}, .aliases = {}, .alias_variants = {},
    .owners = {},
    .edges = {}, .variant_demands = {}, .fixed_edges = {},
    .visiting = {}, .finished = {}, .order = [],
    .private_types = {}, .private_bindings = {}, .private_constants = {},
    .used_aliases = {}};
  foreach (List provider, providers) {
    (Compiler c, List ast) = provider;
    layouts.private_names(c, ast);
  }
  foreach (List provider, providers) {
    (Compiler c, List ast) = provider;
    layouts.provider(c, ast);
  }
  layouts.dependencies();
  foreach (List family, layouts.bodies.keys()) layouts.visit(family);
  Map active = {};
  foreach (Var (key, dependencies), layouts.edges)
    foreach (List dependency, dependencies.list())
      if (layouts.owners[key] != layouts.owners[dependency]) {
        active[key] = 1;
        active[dependency] = 1;
      }
  int changed;
  do {
    changed = 0;
    foreach (List family, active.keys())
      foreach (List dependency, layouts.edges[family].list())
        if (!(dependency in active)) {
          active[dependency] = 1;
          changed = 1;
        }
  } while (changed);
  Map rendered = {}, plan = {};
  if (active.len()) plan[%(native-projection)] = 1;
  Map family_edges = {};
  foreach (Var (family, dependencies), layouts.fixed_edges) {
    Array edges = [];
    foreach (List dependency, dependencies.list())
      edges.push(%"f_${filename_hash(dependency.repr())}");
    family_edges[%"f_${filename_hash(family.list().repr())}"] = edges;
  }
  plan[%(projection-families)] = family_edges;
  Map aliases = {}, body_families = {};
  foreach (List family, layouts.bodies.keys()) body_families[family] = 1;
  foreach (Var (name, row), layouts.aliases) {
    List alias = row.list().cadr();
    aliases[%(typedef $name)] = alias.type_from_ast().declared();
    aliases[%($name)] = %(typedef $name);
  }
  plan[%(projection-aliases)] = aliases;
  plan[%(projection-bodies)] = body_families;
  foreach (List family, layouts.order) {
    if (!(family in active)) continue;
    rendered[family] = layouts.render(family, plan);
  }
  foreach (List provider, providers) {
    (Compiler c, List ast) = provider;
    String path = c.canonical_path(c.filename), text = "";
    Array files = [];
    Map names = {}, bindings = {};
    Map provider_types = layouts.private_types[path],
      provider_bindings = layouts.private_bindings[path],
      provider_constants = layouts.private_constants[path];
    foreach (Var (key, spelling), provider_types) {
      List family = key;
      if (family.car() == <typedef>
          ? spelling in layouts.used_aliases
          : %(${family.car()} $spelling) in active)
        names[key] = spelling;
    }
    foreach (Var (binding, renamed), provider_bindings)
      if (binding_identity_spelling(renamed) in layouts.used_aliases ||
          (binding in provider_constants &&
            provider_constants[binding] in active))
        bindings[binding] = renamed;
    plan[%(private-types $path)] = names;
    plan[%(private-bindings $path)] = bindings;
    foreach (List family, layouts.order)
      if (family in active && layouts.owners[family].string() == path) {
        String name = _layout_header(family);
        files.push(%($name ${rendered[family]}));
        text += %"#include \"$name\"\n";
      }
    plan[%(files $path)] = files.list_free();
    text += layouts.forwards(c, ast, plan);
    if (text.len()) plan[%(prefix $path)] = text;
  }
  return plan;
}

/** Supplies complete definitions before recursive ancestor support includes.
    Language visibility still uses the ordinary symbol ownership records. */
String Compiler.module_layout_prefix(Compiler c) {
  if (!c.module_layout_plan ||
      %(native-projection) in c.module_layout_plan) return NULL;
  Var text;
  return c.module_layout_plan.try_get(
    %(prefix ${c.canonical_path(c.filename)}), text) ? text.string() : NULL;
}

/** Removes only indexed aggregate bodies. Their authoritative definitions
    have already been emitted behind independent layout guards. */
List Compiler.module_layout_node(Compiler c, List node) {
  if (!c.module_layout_plan) return node;
  String path = c.canonical_path(c.filename);
  Map names = c.module_layout_plan[%(private-types $path)],
    bindings = c.module_layout_plan[%(private-bindings $path)];
  if (names) node = _layout_private_node(node, names, bindings);
  if (%(native-projection) in c.module_layout_plan) return node;
  match (node)
    case %(function ?type (!set ?declarator (bind ?binding *)) ?):
      if (%(inline ${c.canonical_path(c.filename)} $binding)
          in c.module_layout_plan)
        return %(declare (static @type)
          ${ast_prototype_declarator(declarator)});
  match (node)
    case %((!set ?kind (!or typedef declare)) ?base ?bindings): {
      List family = _layout_family(base);
      if (!family || !(%(body $family) in c.module_layout_plan)) return node;
      Type type = base;
      List core = type.base_type();
      List bare = base.list()[:base.list().len() - core.len()].append(family);
      return %($kind $bare $bindings);
    }
  return node;
}


/* A selected native field contributes its actual complete-family demand.
   The native preprocessor removes markers in inactive conditional fields. */
static List Layouts.mark_fields(
  Layouts &l, Compiler c, Sym resolver, List fields) {
  Array marked = [];
  foreach (List field, fields) {
    List declaration = Ast.without_origin(field);
    Map needed = {};
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
          if (id) marked.push(
            %(preproc "#pragma x2c_namespace_require $id"));
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
      marked.push(%(preproc "#pragma x2c_family_require f_$id"));
    }
    marked.push(field);
  }
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
  resolver.reset_overlay(
    c.sym.global_symbols(), c.module_layout_plan[%(projection-aliases)]);
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
    .private_types = {}, .private_bindings = {}, .private_constants = {}};
  layouts.private_names(c, ast);
  String path = c.canonical_path(c.filename);
  return {
    %(private-types $path): layouts.private_types[path],
    %(private-bindings $path): layouts.private_bindings[path]
  };
}
