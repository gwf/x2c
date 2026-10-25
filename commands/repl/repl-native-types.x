/*  repl-native-types.x -- native declarations for loaded public types

    Copyright (c) 2026 Gary William Flake.
*/
#pragma once
#include "repl-session.x"
#include "ast-rewrite.x"

static typedef struct PromptTypes {
  ReplSession session;
  Map imported, emitted, enumerators;
  Array declarations;
} PromptTypes;

static List _family(Type type) {
  Type base = type.base_type();
  match (base) {
    case %(?(String name)): return %(typedef $name);
    case %((!or ?kind struct union enum) ?name *):
      return %($kind $name);
  }
  return NULL;
}

/* Enumerators are private to each loaded file. Their names cannot leak
   into another file's reconstructed enum or the prompt namespace. */
static Var _enum_expression(PromptTypes &p, Var node) {
  match (node) case %(expr ?type (ident (?(String name)))): {
    List family = _family(type);
    if (family.car() == <enum>) {
      _require_type(p, type);
      Var renamed;
      if (p.enumerators.try_get(%($family $name), renamed))
        return %(expr $type (ident $renamed));
    }
  }
  List child;
  $ast.rewrite_children(node, child, _enum_expression(p, child));
}

static Type _enum_definition(PromptTypes &p, Type family) {
  Compiler c = p.session.compiler;
  List body = c.sym.get(%(@family "enumerators")).caddr();
  foreach (List member, body) {
    List name = member.car() == <op> ? member.caddr() : member;
    p.enumerators[%($family $(name.car()))] =
      c.sym.introduce(c.fresh_name("repl_enumerator"));
  }
  Array members = [];
  foreach (List member, body) {
    List name = member.car() == <op> ? member.caddr() : member;
    List binding = p.enumerators[%($family $(name.car()))];
    members.push(member.car() == <op>
      ? %(op = $binding $(_enum_expression(p, member.cadddr()))) : binding);
  }
  return %(@family $(members.list_free()));
}

/* Collected types carry ordered fields and enum definitions. The same
   layout boundary used for interpreted objects excludes C-owned layouts
   whose attributes collection deliberately does not retain. */
static void _require_type(PromptTypes &p, Type type) {
  foreach (Var modifier, type)
    match (modifier) case %(func (*parameters)):
      foreach (Type parameter, parameters) _require_type(p, parameter);
  Type family = _family(type);
  if (!family || !(family in p.imported) || family in p.emitted) return;
  p.emitted[family] = 1;
  Compiler c = p.session.compiler;
  if (family.car() == <typedef>) {
    Type target = c.sym.get(family);
    Type base = target.base_type();
    if (c.sym.get(%($(family.cadr()) "layout-attribute")))
      raise %(repl (reason $(%"unsupported native layout: $(family.repr())")));
    if (base.car() == <enum> && base.len() == 3)
      target = (Type) Ast.replace_nodes(target,
        {(void *) base: %($(base.car()) $(base.cadr()))});
    List binding = c.sym.reference_global(%($(family.cadr())));
    List declaration = target.declaration_ast(binding);
    declaration = cons(<typedef>, declaration.cdr());
    int named_record = base.is_aggregate_tag() && base.cadr() is <string>;
    if (named_record) p.declarations.push(declaration);
    _require_type(p, target);
    if (!named_record) p.declarations.push(declaration);
    return;
  }
  if (!p.session.lowering.type_layout(family)) {
    if (type.is_pointer() && family.car() != <enum>) {
      p.declarations.push(family.declaration_ast(NULL));
      return;
    }
    raise %(repl (reason $(%"unsupported native layout: $(family.repr())")));
  }
  if (family.car() == <enum>) {
    p.declarations.push(_enum_definition(p, family).declaration_ast(NULL));
    return;
  }
  int anonymous = family.cadr() is <list>;
  if (!anonymous) p.declarations.push(family.declaration_ast(NULL));
  Array fields = [];
  foreach (List row, c.sym.field_order(family).cdr()) {
    (String name, Type member) = row;
    _require_type(p, member);
    fields.push(member.declaration_ast(%($name)));
  }
  Type definition = %(@family (fields @(fields.list_free())));
  if (!anonymous) p.declarations.push(definition.declaration_ast(NULL));
  else {
    List alias = c.sym.introduce(c.fresh_name("repl_type"));
    c.set_fact(%(ntype $alias), family);
    p.declarations.push(%(typedef $definition (bindings (bind $alias ()))));
  }
}

static void _syntax_types(PromptTypes &p, List syntax) {
  List node;
  $ast.walk(syntax, node)
    match (node)
      case %((!or expr declare decl typedef function param cast return
                  offsetof) ?type *):
        if (type is <list>) _require_type(p, type);
}

/** Places required loaded types before the prompt's own declarations.
    Published families are immutable across reload, so their normalized
    identities also deduplicate definitions shared by independent loads. */
void ReplSession.native_type_declarations(ReplSession session, List function) {
  Compiler c = session.compiler;
  PromptTypes types = {.session = session, .imported = {}, .emitted = {},
    .enumerators = {}, .declarations = []};
  defer {
    types.imported.cleanup(); types.emitted.cleanup();
    types.enumerators.cleanup();
  }
  foreach (Var (path, record), session.files) {
    ReplLoadedFile file = record;
    foreach (List family, file.types) types.imported[family] = 1;
  }
  _syntax_types(types, function);
  foreach (List node, c.unit_nodes) _syntax_types(types, node);
  foreach (List node, c.unit_nodes) types.declarations.push(node);
  c.unit_nodes = types.declarations;
}
