/*  targets.x -- stable project-call target resolution */

#pragma once

#include "compiler/compiler.x"


Map project_function_targets(Compiler compiler, List ast, String path) {
  Map definitions = {};
  foreach (List node, ast)
    match (node)
      case %(function ?
             (bind (!set ?binding (binding ? ?)) ?)
             ?):
        definitions[binding] = %(
          target $path ${compiler.emitted_binding_name(binding)}
        );
  return definitions;
}

/** Returns whether a binding names an automatic object, such as a local
    function pointer, rather than a definition the program links to. */
int project_automatic(Compiler compiler, List binding) =>
  compiler.semantic_binding_facts().contains(%(automatic $binding));

/** Classifies a callee: `<direct>` when it names a linked definition,
    `<automatic>` when it names an automatic binding, and `<computed>`
    otherwise. `binding` receives the binding a named callee uses. */
Symbol project_callee(Compiler compiler, List callee, List &binding) {
  binding = NULL;
  match (callee)
    case %(expr ? (ident (!set ?named (binding ? ?)))): {
      binding = named;
      return project_automatic(compiler, binding) ? <automatic> : <direct>;
    }
  return <computed>;
}

/** Returns a direct binding's target: its definition in this unit, which
    takes precedence, or the public name it links to. */
List project_binding_target(
  Compiler compiler, Map definitions, List binding) {
  Var local;
  if (definitions.try_get(binding, local)) return local;
  return %(public ${compiler.emitted_binding_name(binding)});
}

/** The node beneath expression, parenthesis, and location shells. */
Var project_peel(Var value) {
  while (1) {
    match (value) {
      case %((!or expr at) ? ?inner): value = inner;
      case %(parens ?inner): value = inner;
      default: return value;
    }
  }
}

List project_call_target(
  Compiler compiler, Map definitions, Var value, String &name,
  List &?arguments) {
  name = NULL;
  if (arguments) arguments = NULL;
  match (project_peel(value)) {
    case %(stmnt ?inner):
      return project_call_target(
        compiler, definitions, inner, name, arguments);
    case %(call ?callee (!set ?call_arguments (args *))): {
      if (arguments) arguments = call_arguments;
      List binding;
      if (project_callee(compiler, callee, binding) != <direct>) {
        name = "computed";
        return %(computed);
      }
      name = compiler.emitted_binding_name(binding);
      return project_binding_target(compiler, definitions, binding);
    }
  }
  return NULL;
}

/** Indexes a public definition's target under its name, so that
    resolve_project_target can find the one definition a name links to. */
void project_add_public(Map publics, List target) {
  match (target)
    case %(target ? ?name):
      publics[name] = cons(target, publics.getdefault(name, NULL));
}

/** Adds `value` to the front of the List stored under `key` unless that
    List already contains it. Returns whether `value` was added. */
int project_add_unique(Map lists, Var key, Var value) {
  List values = lists.getdefault(key, NULL);
  if (values.contains(value)) return 0;
  lists[key] = cons(value, values);
  return 1;
}

/** The storage tier of a definition of `type` bound to `binding`:
    `<static>` for a static private to its file, `<module>` for a static
    that every file of a module unit sees, otherwise `<public>`. A module
    unit spells each file-private static with its file's prefix. */
Symbol project_visibility(Compiler compiler, Type type, List binding) {
  if (!type.is_static()) return <public>;
  List prefixes = compiler.file_prefixes();
  if (!prefixes) return <static>;
  String name = compiler.emitted_binding_name(binding);
  foreach (String prefix, prefixes)
    if (name.startswith(prefix)) return <static>;
  return <module>;
}

/** The display paths of a module unit's files, or NULL for a single-file
    unit. */
Map project_member_files(Compiler compiler) {
  if (!compiler.line_markers) return NULL;
  Map members = {};
  foreach (List row, compiler.line_markers)
    match (row) case %(? ? ?(String member) *):
      members[compiler.display_path(member)] = 1;
  return members;
}

static String _member_file(Compiler compiler, Map members, Var value) {
  if (value is not <list>) return NULL;
  List node = value;
  match (node) case %(at ?origin ?): {
    List location = compiler.origin_location(origin.integer());
    Var file = location ? location.assoc(<file>) : void;
    if (file is <string>) {
      String source = compiler.display_path(file.str());
      if (source in members) return source;
    }
  }
  foreach (Var child, node) {
    String file = _member_file(compiler, members, child);
    if (file) return file;
  }
  return NULL;
}

/** The file of unit `path` that holds `definition`: the file of its first
    node located in one of `members`, the unit's files. A single-file unit,
    or a definition with no such node, gives `path`. Macro templates locate
    their nodes in the files that define them, so other files do not
    count. */
String project_definition_file(
  Compiler compiler, Map members, String path, List definition) {
  if (!members) return path;
  String file = _member_file(compiler, members, definition);
  return file ? file : path;
}

/** Orders `records` by the key `key` builds for each one, keeps the first
    `limit`, and returns them as a List. */
List project_ranked_records(Array records, Func key, int limit) {
  records.sort_by(key);
  if ((int) records.len() > limit)
    records.remslice(limit, records.len()).free();
  return records.list_free();
}

/** Adds `amount` to the count stored under `key`, reading absence as zero. */
void project_count(Map counts, List key, int amount) {
  counts[key] = counts.getdefault(key, 0).int() + amount;
}

List resolve_project_target(List target, Map publics) {
  match (target) {
    case %(target ? ?): return target;
    case %(public ?name): {
      if (!publics.contains(name)) return NULL;
      List targets = publics[name];
      return targets && !targets.cdr() ? targets.car().list() : NULL;
    }
  }
  return NULL;
}

List project_location(Compiler compiler, String path, int origin) {
  List location = compiler.origin_location(origin);
  if (!location) return %(location $path 0 0);
  Var file = location.assoc(<file>);
  String source = file is <string>
                ? compiler.display_path(file.str()) : path;
  int line = location.assoc(<line>).integer();
  int column = location.assoc(<column>).integer();
  return %(location $source $line $column);
}

/** The named parameters in a function's modifiers, in order, as
    `(parameter POSITION BINDING TYPE)` rows. POSITION counts every
    parameter, named or not. */
List project_parameters(List modifiers) {
  Array rows = [];
  match (modifiers)
    case %((fnmod (params *values)) *): {
      int position = 0;
      foreach (Var value, values) {
        match (value)
          case %(param ?type (bind (!set ?binding (binding ? ?)) ?)):
            rows.push(%(parameter $position $binding $type));
        position++;
      }
    }
  return rows.list_free();
}

/** The binding a direct identifier names beneath expression, parenthesis,
    and location wrappers, or NULL. */
List project_direct_binding(Var value) {
  match (project_peel(value))
    case %(ident (!set ?binding (binding ? ?))): return binding;
  return NULL;
}

/** The type of an expression beneath parenthesis and location wrappers, or
    NULL. */
Type project_expression_type(Var value) {
  if (value is not <list>) return NULL;
  List node = value;
  match (node) {
    case %(expr ?type ?): return type;
    case %(parens ?inner): return project_expression_type(inner);
    case %(at ? ?inner): return project_expression_type(inner);
  }
  return NULL;
}
