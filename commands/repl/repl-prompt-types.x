/*  repl-prompt-types.x -- native names for persistent prompt records

    Copyright (c) 2026 Gary William Flake.
*/
#pragma once
#include "repl-types.x"
#include "ast-rewrite.x"

static typedef struct PromptType {
  Type original, family;
  List definition, alias, delegates;
  int origin, lift;
} *PromptType;

static typedef struct PromptTypes {
  Compiler compiler;
  Map definitions, replacements;
  Array ordered;
} PromptTypes;

/** Retains direct prompt record definitions and gives captures native names.
    The caller commits retained declarations only after initialization succeeds.
    Symbol changes participate in its existing semantic transaction. */
List repl_prompt_types(
  ReplSession session, List statements, Array retained) {
  PromptTypes types = {
    .compiler = session.compiler, .definitions = {}, .replacements = {},
    .ordered = []
  };
  defer {
    foreach (Var (_, record), types.definitions) xfree(record.pointer());
    types.definitions.cleanup();
    types.replacements.cleanup();
    types.ordered.free();
  }
  foreach (List statement, statements) _prompt_declarations(types, statement, 0);
  foreach (Var record, types.ordered)
    _prompt_publish(types, record.pointer(), retained);
  Array rewritten = [];
  foreach (List statement, statements)
    rewritten.push(Ast.replace_nodes(statement, types.replacements));
  return rewritten.list_free();
}

/* An unnamed embedded record must keep its body in the native field: a
   typedef followed by no declarator is not a C anonymous member. */
static int _anonymous_field(List declaration) {
  match (declaration)
    case %(declare ? (bindings (bind () ()))): return 1;
  return 0;
}

static void _prompt_fields(PromptTypes &types, List fields, int origin) {
  foreach (List field, fields) {
    int field_origin = origin;
    match (field) case %(at ?(int position) ?inner): {
      field_origin = position;
      field = inner;
    }
    if (field ~= %(seq *items)) {
      _prompt_fields(types, items, field_origin);
      continue;
    }
    match (field) case %(declare ?spec ?):
      _prompt_specifier(types, spec, field_origin, !_anonymous_field(field));
  }
}

static Type _prompt_family(Symbol kind, Var name) {
  String spelling = Ast.binding_spelling(name);
  return $(kind, spelling ? (Var) spelling : name);
}

static void _prompt_specifier(
  PromptTypes &types, List specifier, int origin, int lift) {
  Type base = specifier.type().base_type();
  Symbol kind = 0;
  Var name = void;
  List fields = NULL;
  match (base) case %((!or ?found struct union) ?tag (fields *members)): {
    kind = found;
    name = tag;
    fields = members;
  }
  if (!kind) return;
  Type original = $(kind, name);
  if (original in types.definitions) return;
  Type family = lift ? _prompt_family(kind, name) : original;
  Compiler c = types.compiler;
  if (original != family && c.sym.field_order(family))
    raise %(repl (reason $("a type cannot be redefined: " +
                           Ast.binding_spelling(name))));
  PromptType record = xcalloc(1, sizeof(struct PromptType));
  record.original = original;
  record.family = family;
  record.definition = base;
  record.origin = origin;
  record.lift = lift;
  record.delegates = c.sym.marked_fields(original, <delegate>);
  types.definitions[original] = (void *) record;
  if (original != family) types.replacements[(void *) original] = family;
  if (lift) {
    record.alias = c.sym.introduce(c.fresh_name("repl_type"));
    types.replacements[(void *) base] = family;
  }
  _prompt_fields(types, fields, origin);
  types.ordered.push((void *) record);
}

static void _prompt_declarations(
  PromptTypes &types, List statement, int origin) {
  match (statement) {
    case %(at ?(int position) ?inner):
      _prompt_declarations(types, inner, position);
    case %(seq *items):
      foreach (List item, items) _prompt_declarations(types, item, origin);
    case %(declare ?spec ?): _prompt_specifier(types, spec, origin, 1);
  }
}

static void _prompt_publish(
  PromptTypes &types, PromptType record, Array retained) {
  Compiler c = types.compiler;
  List fields = record.definition.caddr().cdr();
  fields = Ast.replace_nodes(fields, types.replacements);
  Type definition = %(@(record.family) (fields @fields));
  _prompt_bind_fields(c, record.family, fields);
  c.sym.declare_field_order(record.family, fields);
  foreach (List row, record.delegates)
    c.sym.mark_field(record.family, <delegate>, row.car());
  if (record.original != record.family) {
    c.sym.define_global(record.family, definition);
    foreach (String property, %("layout-attribute" "x2c-record")) {
      Type fact = c.sym.get(%(@(record.original) $property));
      if (fact) c.sym.set(%(@(record.family) $property), fact);
    }
  }
  if (!record.lift) return;
  c.set_fact(%(ntype $(record.alias)), record.family);
  List declaration = %(typedef $definition
    (bindings (bind $(record.alias) ())));
  retained.push(record.origin ? %(at $(record.origin) $declaration) : declaration);
}

static void _prompt_bind_fields(Compiler c, Type family, List fields) {
  foreach (List field, fields) {
    field = Ast.without_origin(field);
    match (field) {
      case %(seq *items): _prompt_bind_fields(c, family, items);
      case %(declare ?spec (bindings *rows)):
        foreach (List row, rows) {
          List binding = row.cadr();
          if (Ast.binding_spelling(binding))
            c.sym.bind_identity(family, binding,
              %(declare $spec (bindings $row)));
        }
    }
  }
}
