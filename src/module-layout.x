/* module-layout.x -- complete aggregate prerequisites for module emission */
#pragma once
#include "compiler.x"
#include "ast-rewrite.x"
#include "format.x"
#include "generate.x"
#include "utils.x"

static typedef struct Layouts {
  Map bodies, aliases, owners, prefixes, arms, edges, visiting, finished;
  Array order;
} Layouts;

static String _layout_guard(List family) =>
  %"__X2C_LAYOUT_${filename_hash(family.repr())}__";

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

/* Index already bound source nodes. Native directives retain the provider's
   order; source-module includes are supplied by the layout prerequisites. */
static void Layouts.provider(Layouts &layouts, Compiler c, List ast) {
  Array prefix = [];
  List arms = NULL;
  foreach (List node, ast) {
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
        if (type.is_static()) continue;
        List family = _layout_family(type);
        if (kind == <typedef>) {
          List alias_base = base;
          List core = _layout_core(type);
          if (core && core.car() != <enum>)
            alias_base = base.list()[:base.list().len() - core.len()]
              .append(%(${family.car()} ${family.cadr()}));
          if (!core || core.car() != <enum>)
            foreach (List declarator, bindings.list().cdr()) {
              String name = binding_identity_spelling(declarator.cadr());
              if (name)
                layouts.aliases[name] = %(
                  $c (typedef $alias_base (bindings $declarator)));
            }
        }
        if (!family) {
          prefix.push(node);
          continue;
        }
        List body = kind == <typedef> ? node
          : %(declare $base (bindings (bind () ())));
        layouts.bodies[family] = %($c $body);
        layouts.owners[family] = c.canonical_path(c.filename);
        layouts.prefixes[family] = prefix.list();
        layouts.arms[family] = arms;
      }
    }
  }
}

/* Array elements require their aggregate's body. A pointer terminates the
   demand, including a typedef that resolves to an array of pointers. */
static void Layouts.require_type(
  Layouts &layouts, Compiler c, Sym resolver, Type type, Map needed) {
  type = resolver.normalize_declared_type(type).canonicalize();
  while (type.is_array()) type = type.dereference().canonicalize();
  if (type.is_pointer() || type.is_function()) return;
  Type key = resolver.resolve_key(type);
  match (key)
    case %((!set ?kind (!or struct union enum)) ?name): {
      List family = %($kind $name);
      if (family in layouts.bodies) needed[family] = 1;
      else foreach (List row, c.sym.field_order(key).cdr())
        layouts.require_type(c, resolver, row.cadr(), needed);
      return;
    }
  match (key) case %((!or struct union) (fields *rows)):
    foreach (List row, rows) {
      List declaration = Ast.without_origin(row);
      if (declaration.car() == <c-assert>) continue;
      Type field = declaration.type_from_ast();
      layouts.require_type(c, resolver, field, needed);
    }
}

static void Layouts.dependencies(Layouts &layouts) {
  Map aliases = {};
  foreach (Var (name, row), layouts.aliases) {
    List alias = row.list().cadr();
    aliases[%(typedef $name)] = alias.type_from_ast().declared();
  }
  foreach (Var (key, provider), layouts.bodies) {
    (Compiler c, List body) = provider;
    Map needed = {};
    Sym resolver = Sym.new(c);
    resolver.reset_overlay(c.sym.global_symbols(), aliases);
    List family = key;
    foreach (List row, c.sym.field_order(family).cdr())
      layouts.require_type(c, resolver, row.cadr(), needed);
    Array prerequisites = [];
    foreach (List prerequisite, needed.keys()) prerequisites.push(prerequisite);
    layouts.edges[family] = prerequisites.list_free();
  }
}

static void Layouts.visit(Layouts &layouts, List family) {
  if (family in layouts.finished) return;
  if (family in layouts.visiting) {
    Compiler c = layouts.bodies[family].list().car();
    c.report_error(
      <type>, "complete aggregate layout cycle", NULL,
      %($family "provider: ${layouts.owners[family]}"));
  }
  layouts.visiting[family] = 1;
  foreach (List prerequisite, layouts.edges[family].list())
    layouts.visit(prerequisite);
  layouts.visiting.del(family);
  layouts.finished[family] = 1;
  layouts.order.push(family);
}

static String _layout_text(Compiler c, List nodes) =>
  c.code_pretty_string(c.emit(nodes, NULL), c.filename);

/* Public inline bodies capture native state at their authored position.
   Keep them with the prefix, under individual guards, rather than moving
   their native includes ahead of the bodies. */
static List _layout_prefix(Compiler c, List prefix, Map plan) {
  Array nodes = [];
  foreach (List node, prefix) {
    match (node)
      case %(function ?type (bind ?binding *) ?): {
        Type signature = type;
        if (signature.is_inline() && !signature.is_static()) {
          String guard = %"__X2C_LAYOUT_INLINE_${filename_hash(binding.repr())}__";
          plan[%(inline ${c.canonical_path(c.filename)} $binding)] = guard;
          String body = _layout_text(c, c.module_layout_header_prefix(%($node)));
          node = %(preproc ${%"#ifndef $guard\n#define $guard\n$body\n#endif\n"});
        }
      }
    nodes.push(node);
  }
  return c.module_layout_header_prefix(nodes.list_free());
}

static void Layouts.alias(
  Layouts &layouts, String name, Map done, Map visiting, Array text) {
  if (name in done) return;
  if (name in visiting) {
    Compiler c = layouts.aliases[name].list().car();
    c.report_error(<type>, "layout typedef prerequisite cycle", NULL, %($name));
  }
  visiting[name] = 1;
  (Compiler c, List node) = layouts.aliases[name];
  Type type = node.cadr();
  match (type.base_type()) case %(?(String dependency)):
    if (dependency in layouts.aliases)
      layouts.alias(dependency, done, visiting, text);
  visiting.del(name);
  done[name] = 1;
  text.push(_layout_text(c, %( $node )));
}

static String Layouts.alias_text(Layouts &layouts, List body) {
  Map needed = {}, done = {}, visiting = {};
  List node;
  $ast.walk(body, node) {
    match (node) case %((!or typedef declare) ?base *): {
      Type type = base;
      match (type.base_type()) case %(?(String name)):
        if (name in layouts.aliases) needed[name] = 1;
    }
  }
  Array parts = [];
  foreach (String name, needed.keys())
    layouts.alias(name, done, visiting, parts);
  String text = "";
  foreach (String part, parts) text += part;
  return text;
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

/* Render while the bound provider ASTs and their binding facts are alive.
   Consumers export only Strings and keys as their nested Contexts close. */
Map prepare_module_layouts(List providers) {
  Layouts layouts = {
    .bodies = {}, .aliases = {}, .owners = {}, .prefixes = {}, .arms = {},
    .edges = {},
    .visiting = {}, .finished = {}, .order = []};
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
  if (!active.len()) return {};
  Map rendered = {}, plan = {};
  foreach (List family, layouts.order) {
    if (!(family in active)) continue;
    (Compiler c, List body) = layouts.bodies[family];
    String guard = _layout_guard(family);
    String text = "";
    foreach (List dependency, layouts.edges[family].list())
      text += rendered[dependency].string();
    List prefix = layouts.prefixes[family];
    List macros = _layout_macro_names(prefix);
    text += _layout_macro_guards(macros, "push");
    text += _layout_text(c, _layout_prefix(c, prefix, plan));
    text += layouts.alias_text(body);
    text += _layout_text(c, %( $body ));
    for (int i = layouts.arms[family].list().len(); i; i--)
      text += "#endif\n";
    text += _layout_macro_guards(macros.reverse(), "pop");
    rendered[family] = %"#ifndef $guard\n#define $guard\n$text\n#endif\n";
    plan[%(body $family)] = guard;
  }
  foreach (List provider, providers) {
    (Compiler c, List ast) = provider;
    String path = c.canonical_path(c.filename), text = "";
    foreach (List family, layouts.order)
      if (family in active && layouts.owners[family].string() == path)
        text += rendered[family].string();
    if (text.len()) plan[%(prefix $path)] = text;
  }
  return plan;
}

/** Supplies complete definitions before recursive ancestor support includes.
    Language visibility still uses the ordinary symbol ownership records. */
String Compiler.module_layout_prefix(Compiler c) {
  if (!c.module_layout_plan) return NULL;
  Var text;
  return c.module_layout_plan.try_get(
    %(prefix ${c.canonical_path(c.filename)}), text) ? text.string() : NULL;
}

/** Removes only indexed aggregate bodies. Their authoritative definitions
    have already been emitted behind independent layout guards. */
List Compiler.module_layout_node(Compiler c, List node) {
  if (!c.module_layout_plan) return node;
  match (node)
    case %(function ?type (!set ?declarator (bind ?binding *)) ?):
      if (%(inline ${c.canonical_path(c.filename)} $binding)
          in c.module_layout_plan)
        return %(declare (static @type) ${ast_prototype_declarator(declarator)});
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
