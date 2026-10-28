/*  references-types.x -- method spellings coupled to a renamed type

    Copyright (c) 2026 Gary William Flake.
*/
#pragma once
#include "analysis.x"

/** Finds C-spelled methods owned by one physical type declaration.
    Bindings and Strings remain borrowed from the current analysis unit.
*/
Array lsp_type_rename_methods(
  Compiler c, List target, String replacement) {
  String owner = _type_rename_spelling(c, target);
  Array methods = [];
  if (!owner) return methods;
  List bindings = c.source_definitions.keys();
  foreach (List binding in bindings) {
    List definition = c.source_definitions[binding];
    Type type = definition[3];
    if (!type.is_function()) continue;
    List source_key = c.fact(%(src-key $binding));
    if (!source_key) continue;
    String spelling = Ast.binding_spelling(binding), member = NULL;
    List method = definition[4];
    if (method) {
      String declared_owner = method.car();
      member = method.cadr();
      String suffix = "_" + member;
      if (!spelling.endswith(suffix)) continue;
      String canonical_owner = spelling[:spelling.len() - suffix.len()];
      if (!_type_rename_owner(c, source_key.car(), declared_owner, target) &&
          !_type_rename_owner(c, source_key.car(), canonical_owner, target))
        continue;
    }
    else {
      String prefix = owner + "_";
      if (!spelling.startswith(prefix) ||
          !_type_rename_owner(c, source_key.car(), owner, target)) continue;
      member = spelling[prefix.len():];
      List selected = NULL;
      c.resolve_postfix_member($(owner), $(member), <.>, 1, selected);
      if (selected != binding) continue;
    }
    String suffix = "_" + member;
    if (!spelling.endswith(suffix)) continue;
    String method_owner = spelling[:spelling.len() - suffix.len()];
    if (!method_owner.endswith(owner)) continue;
    String prefix = method_owner[:method_owner.len() - owner.len()];
    methods.push({"binding": binding, "spelling": spelling, "member": member,
      "replacement": prefix + replacement + suffix});
  }
  return methods;
}

/* A shared underlying C type does not identify a typedef's method owner. */
static String _type_rename_spelling(Compiler c, List target) {
  foreach (List (binding, definition) in c.source_definitions) {
    Type type = definition[3];
    if (type.is_typedef() && _type_rename_same(definition, target))
      return Ast.binding_spelling(binding);
  }
  foreach (List (source_key, definition) in c.source_declarations) {
    Type type = definition[3];
    List key = source_key.cadr();
    if (!type.is_typedef() || !_type_rename_same(definition, target) ||
        key.len() != 1 || key.car() is not <string>) continue;
    List binding = c.sym.lookup(key, NULL);
    if (binding && c.fact(%(src-key $binding)) == source_key)
      return Ast.binding_spelling(binding);
  }
  return NULL;
}

static int _type_rename_owner(
  Compiler c, Map symbols, String owner, List target) {
  Var declaration;
  return c.source_declarations.try_get($(symbols, $(owner)), declaration) &&
         _type_rename_same(declaration, target);
}

static int _type_rename_same(List definition, List target) =>
  definition[0] == target[0] && definition[1] == target[1] &&
  definition[2] == target[2];
