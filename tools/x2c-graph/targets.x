/*  targets.x -- stable project-call target resolution */

#pragma once

#include "compiler.x"

Map project_function_targets(Compiler compiler, List ast, String path);
List project_call_target(
  Compiler compiler, Map definitions, Var value, String *name);
List resolve_project_target(List target, Map publics);

#pragma private

#include <string.h>

Map project_function_targets(Compiler compiler, List ast, String path) {
  Map definitions = %{};
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
  Compiler compiler, Map definitions, Var value, String *name) {
  *name = NULL;
  if (value is not <list>) return NULL;
  List node = value;
  match (node) {
    case %(expr ? ?inner):
      return project_call_target(compiler, definitions, inner, name);
    case %(parens ?inner):
      return project_call_target(compiler, definitions, inner, name);
    case %(at ? ?inner):
      return project_call_target(compiler, definitions, inner, name);
    case %(call
           (expr ?
             (ident (!set ?binding (binding ? ?spelling))))
           (args *)): {
      if (compiler.semantic_binding_facts().contains(
            %(automatic $binding)
          )) {
        *name = %"computed";
        return %(computed);
      }
      String emitted = compiler.emitted_binding_name(binding);
      if (!emitted || !strlen(emitted)) emitted = spelling.str();
      *name = emitted;
      return definitions.contains(binding)
           ? definitions[binding].list() : %(public $emitted);
    }
    case %(call ? (args *)): {
      *name = %"computed";
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
