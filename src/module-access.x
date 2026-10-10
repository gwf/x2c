/* module-access.x -- declaration ownership and module lookup */
#pragma once
#include "compiler.x"
#include "module-tree.x"
#include "utils.x"

void Compiler.configure_module(Compiler c, String filename) {
  if (!c.module_tree) c.module_tree = ModuleTree.new(c);
  String path = c.canonical_path(filename);
  c.module_owner = c.module_tree.owner(path);
  c.merge_translation_dependencies(c.module_tree.ownership_dependencies(path));
}

List Compiler.module_ancestors(Compiler c) =>
  c.module_tree && c.module_owner
    ? c.module_tree.ancestors(c.module_owner) : NULL;

List Compiler.module_include_dirs(Compiler c, String path) {
  Array dirs = [];
  if (!c.module_tree) c.module_tree = ModuleTree.new(c);
  foreach (String owner, c.module_tree.ancestors(path)) {
    String dir = Path.dirname(owner);
    if (!(dir in dirs)) dirs.push(dir);
  }
  return dirs.list_free();
}

int Compiler.module_accessible(Compiler c, String owner) {
  foreach (String ancestor, c.module_ancestors())
    if (ancestor == owner) return 1;
  return 0;
}

static String Compiler._module_spelling(Compiler c, String name) {
  if (!c.module_owner)
    c.report_error(<parse>, "module declaration has no owning module", c.token, NULL);
  String prefix = c.module_tree.entry(c.module_owner).prefix;
  if (c.package) prefix = c.package_spelling(prefix);
  if (name.startswith(prefix)) return name;
  c.sym.set(%("module-private" $name),
    %(${home_portable_path(c.module_owner)}));
  String spelling = %"${c.module_tree.entry(c.module_owner).prefix}$name";
  if (c.package) spelling = c.package_spelling(spelling);
  c.sym.set(%("module-source" $spelling), %($name));
  return spelling;
}

String Compiler._module_type_spelling(Compiler c, String name) {
  c.sym.check_module_type_spelling(name);
  String spelling = c._module_spelling(name);
  c.sym.set(%("module-tag" $spelling), %(generated));
  c.sym.set(%("module-owner" $spelling),
    %(${home_portable_path(c.module_owner)}));
  return spelling;
}

void Compiler.check_module_binding(Compiler c, String spelling, Token origin) {
  List owner = c.sym.get_exact(%("module-owner" $spelling));
  if (!owner && !c.sym.get_exact(%($spelling)))
    owner = c.sym.get_exact(%("module-private" $spelling));
  if (!owner || c.module_accessible(c.canonical_path(home_absolute_path(owner.car()))))
    return;
  c.report_error(<type>, %"module-private declaration '$spelling' is not accessible",
    origin, %("module: ${owner.car()}"));
}

List Compiler.module_declared_key(Compiler c, List context, List key) {
  if (!c.source_module || !c.sym.at_file_scope()) return key;
  if (context && context !== %(typedef)) return key;
  match (key) {
    case %(?(String name)): {
      if (context == %(typedef) &&
          c.sym.get_exact(%("module-opaque" $name))) return key;
      if (!context) {
        List prior = c.sym.get_exact(%("declaration-module" $name));
        if (prior == %(${home_portable_path(c.module_owner)}) &&
            !c.sym.get_exact(%("module-owner" $name)))
          c.report_error(<type>, %"declaration visibility disagrees for '$name'",
            c.token, NULL);
      }
      return %(${c._module_spelling(name)});
    }
    case %((!set ?tag (!or struct union enum)) ?(String name)): {
      if (c.sym.get_exact(%("module-layout" $tag $name))) return key;
      return %($tag ${c._module_spelling(name)});
    }
  }
  return key;
}

List Compiler.module_retry_key(Compiler c, List key) {
  foreach (String owner, c.module_ancestors()) {
    String prefix = c.module_tree.entry(owner).prefix;
    if (c.package) prefix = c.package_spelling(prefix);
    List retry = NULL;
    match (key) {
      case %(?(String name)): retry = %("$prefix$name");
      case %((!set ?tag (!or typedef struct union enum)) ?(String name)):
        retry = %($tag "$prefix$name");
    }
    if (retry && c.sym.get_exact(retry)) return retry;
  }
  return NULL;
}

List Compiler.module_reference_key(Compiler c, List key) {
  List exact = c.sym.get_exact(key);
  if (exact && exact != %(typedef @{key})) return key;
  List module_key = c.module_retry_key(key);
  return module_key ? module_key : key;
}

void Compiler.record_module_declaration(Compiler c, List syntax) {
  if (c.source_module && !c.module_owner)
    c.report_error(<parse>, "module declaration has no owning module", c.token, NULL);
  match (syntax) {
    case %(seq *rows):
      foreach (List row, rows) c.record_module_declaration(row);
    case %(function ?type (!set ?target (bind ?binding *)) *): {
      if (!c.source_module && !type.type().is_static())
        c._check_public_module_type(
          %(declare $type (bindings $target)).type_from_ast());
      c._record_module_binding(type, binding);
    }
    case %((!or typedef declare) ?type (bindings *rows)):
      foreach (List row, rows) {
        match (row) case %(op = ?declaration ?): row = declaration;
        match (row) case %(bind ?binding *): {
          if (!c.source_module && !type.type().is_static())
            c._check_public_module_type(
              %(declare $type (bindings $row)).type_from_ast());
          c._record_module_binding(type, binding);
        }
      }
  }
}

static void Compiler._record_module_binding(
  Compiler c, List type, List binding) {
  if (c.source_module && type.type().is_static())
    c.report_error(<parse>, "module and static visibility cannot be combined", c.token, NULL);
  String name = binding_identity_spelling(binding);
  if (!name) return;
  if (c.source_module && c.sym.get_exact(%("module-opaque" $name))) return;
  if (!c.source_module) {
    if (c.module_owner) {
      List private_key = c.module_retry_key(%($name));
      List owner = private_key
        ? c.sym.get_exact(%("module-owner" ${private_key.last()})) : NULL;
      if (owner == %(${home_portable_path(c.module_owner)}) &&
          private_key.last() != name)
        c.report_error(<type>, %"declaration visibility disagrees for '$name'",
          c.token, NULL);
      c.sym.set(%("declaration-module" $name),
        %(${home_portable_path(c.module_owner)}));
    }
    return;
  }
  List owner = %(${home_portable_path(c.module_owner)});
  c.sym.set(%("module-owner" $name), owner);
}

static void Compiler._check_public_module_type(Compiler c, Var type) {
  if (type is <string>) {
    List owner = c.sym.get_exact(%("module-owner" $type));
    if (owner)
      c.report_error(<type>, %"public signature uses module-private type '$type'",
        c.token, NULL);
  }
  else if (type is <list>)
    foreach (Var child, type.list()) c._check_public_module_type(child);
}

int Compiler.module_row_accessible(Compiler c, List key, Map rows) {
  match (key)
    case %((!set ?tag (!or struct union)) ?(String spelling) *): {
      Var layout = rows[%("module-layout" $tag $spelling)];
      if (layout is <list> && !c.module_accessible(
          c.canonical_path(home_absolute_path(layout.list().car())))) return 0;
    }
  String name = NULL;
  match (key) {
    case %(?(String spelling)): name = spelling;
    case %((!or self typedef struct union enum) ?(String spelling)):
      name = spelling;
  }
  if (!name) return 1;
  Var record = rows[%("module-owner" $name)];
  if (record is not <list>) return 1;
  return c.module_accessible(c.canonical_path(home_absolute_path(record.list().car())));
}

List Compiler.parse_module_members(Compiler c) {
  c.next();
  c.expect(<"{">);
  Array members = [];
  if (!c.test(<"}">)) {
    for (;;) {
      if (c.peek(0) != <lit-char*>)
        c.report_error(<parse>, "expected module member path", c.token, NULL);
      members.push(String.new_len(c.token.text + 1, c.token.len - 2).unescape());
      c.next();
      if (c.test(<"}">)) break;
      c.expect(<,>);
      if (c.test(<"}">)) break;
    }
  }
  List paths = members.list_free();
  if (c.layout && c.peek(0) == <;> && !c.token.len) c.next();
  if (!c.shallow) {
    Map visited = {};
    Array effects = [];
    foreach (String path, c.module_tree.entry(c.canonical_path(c.filename)).members)
      c.module_member_effects(path, visited, effects);
    c.install_compile_time_effects(effects.list_free());
  }
  return %(module-members $paths);
}
