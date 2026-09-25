/*  targets.x -- stable project-call target resolution */

#pragma once

#include "compiler.x"

#pragma private

#include <string.h>

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

List project_call_target(
  Compiler compiler, Map definitions, Var value, String &name,
  List *arguments) {
  name = NULL;
  if (arguments) *arguments = NULL;
  if (value is not <list>) return NULL;
  List node = value;
  match (node) {
    case %((!or expr at) ? ?inner):
      return project_call_target(
        compiler, definitions, inner, name, arguments
      );
    case %((!or stmnt parens) ?inner):
      return project_call_target(
        compiler, definitions, inner, name, arguments
      );
    case %(call
           (expr ?
             (ident (!set ?binding (binding ? ?spelling))))
           (!set ?call_arguments (args *))): {
      if (arguments) *arguments = call_arguments;
      if (compiler.semantic_binding_facts().contains(
            %(automatic $binding)
          )) {
        name = "computed";
        return %(computed);
      }
      String emitted = compiler.emitted_binding_name(binding);
      if (!emitted || !strlen(emitted)) emitted = spelling.str();
      name = emitted;
      return definitions.contains(binding)
           ? definitions[binding].list() : %(public $emitted);
    }
    case %(call ? (!set ?call_arguments (args *))): {
      if (arguments) *arguments = call_arguments;
      name = "computed";
      return %(computed);
    }
  }
  return NULL;
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
