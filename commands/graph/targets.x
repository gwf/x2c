/*  targets.x -- stable project-call target resolution */

#pragma once

#include "compiler.x"

#pragma private

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

List project_call_target(
  Compiler compiler, Map definitions, Var value, String &name,
  List &?arguments) {
  name = NULL;
  if (arguments) arguments = NULL;
  if (value is not <list>) return NULL;
  List node = value;
  match (node) {
    case %((!or expr at) ? ?inner):
      return project_call_target(
        compiler, definitions, inner, name, arguments);
    case %((!or stmnt parens) ?inner):
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
      publics[name] = cons(
        target, publics.contains(name) ? publics[name].list() : NULL);
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
