/*  type.x -- x2c semantic types

    Copyright (c) 2025 Gary William Flake

    Converts compiler declaration syntax to semantic types and owns the
    translation unit's Var registrations. Structural Type operations live
    in lib/type.x.
*/

#pragma once
#include "ast.x"
#include "meta.x"
#include "../lib/type.x"

#include "grammar.x"
#include "ast-rewrite.x"

/* types from declarations

   `_from_ast` converts any node inside a declaration AST. `context` is the
   base Type that a declarator's modifiers apply to. */

/** Returns the semantic `Type` represented by a complete `(declare ...)` AST.
    A declaration with one binding is unwrapped to that binding's `Type`;
    multiple bindings return their `Type`s in source order.
*/
Type List.type_from_ast(List ast) {
  List type = _from_ast(ast, NULL);
  match (type) case %((*)): return type.car();
  return type;
}

/* Each declaration form has its own case; any other node is a modifier
   chain or converts its children. A nested declaration, such as a struct
   field that is a pointer, converts the same way. */
static List _from_ast(List node, List context) {
  if (!node) return node;
  match (node) {
    // Initializers do not contribute to the declared Type.
    case $source_operator_content(%(= (!set ?binding (bind *)) ?)):
      return _from_ast(binding, context);
    case %(declare ?source_type ?bindings):
      return _from_declarators(_without_leading_text(source_type), bindings);
    case %(typedef ?source_type ?bindings):
      return _from_declarators(source_type, bindings);
    case %(bind ? ?mods): return _from_bind(mods, context);
    case %(params *items): return _from_items(items, context);
    case %(bindings *items): return _from_items(items, context);
    case %(fields *fields): return _from_fields(fields, context);
    case %(fnmod *params): return %(func @{_from_ast(params, NULL)});
    case %(param ?type ?mods): return _from_ast(mods, type);
    // Binding identity is AST metadata; semantic Types retain the spelling.
    case %(binding ? ?spelling): return %($spelling);
    // An integer literal, such as an array bound, keeps only its spelling.
    case %(expr (int) ${$source_literal_content(%(? ?value))}):
      return %($value);
    case %(expr *): return _from_items(node, context);
    case %(struct *): return _from_aggregate(node, <struct>);
    case %(union *): return _from_aggregate(node, <union>);
  }
  return _from_modifiers(node, context);
}

/* A modifier chain in source order: pointer marks, qualifiers, storage
   classes, `inline`, and nested pointer, array, function, and bitfield
   declarators, then the Type they modify. A node that starts with no
   modifier converts its children. */
static List _from_modifiers(List node, List context) {
  Array modifiers = NULL;
  List rest = node;
  while (rest) {
    Var modifier = rest.car();
    if (modifier is <symbol>) {
      if (!_modifier_symbol(modifier)) break;
    }
    else if (modifier is <list>) {
      if (!_nested_declarator(modifier)) break;
      modifier = _from_ast(modifier, context);
    }
    else break;
    if (!modifiers) modifiers = [];
    modifiers.push(modifier);
    rest = rest.cdr();
  }
  if (modifiers) return modifiers.list_free().append(_from_ast(rest, context));
  return _from_items(node, context);
}

static int _modifier_symbol(Symbol prefix) =>
  prefix == <*> || prefix == <&> || prefix == <opt-ref> || prefix == <^> ||
  prefix.is_type_qualifier() || prefix.is_storage_class() ||
  prefix.is_inline();

static int _nested_declarator(Type nested) =>
  nested.is_pointer() || nested.is_array() || nested.is_function() ||
  nested.is_bitfield();

/* Converts each List child of `items`; a node with no changed child returns
   itself. */
static List _from_items(List items, List context) {
  List child;
  $ast.rewrite_children(items, child, _from_ast(child, context));
}

// declaration forms

static List _from_declarators(List source_type, List bindings) =>
  _from_ast(bindings, _from_ast(source_type, NULL));

/* (bind ?ident ?mods): a declarator modifier is never a named type, so all
   of its source attribute text, `("__attribute__((unused))")`, drops. */
static List _from_bind(List mods, List context) {
  Array typed = [];
  foreach (Var item, mods)
    if (!_is_source_text(item)) typed.push(item);
  return context.type()._modify(_from_ast(typed.list_free(), context));
}

/* A static assertion among the fields, under any origin wrappers, declares
   no field. */
static List _from_fields(List fields, List context) {
  Array types = [];
  foreach (List field, fields) {
    List declaration = Ast.without_origin(field);
    if (declaration.car() != <c-assert>) types.push(_from_ast(field, context));
  }
  return types.list_free();
}

/* (struct tag) stays as written, (struct (fields)) converts its fields, and
   (struct tag (fields)) drops its body; a union converts the same way. */
static List _from_aggregate(List node, Var head) {
  if (node.type().is_aggregate_tag()) return node;
  if (!node.type().is_aggregate_tag_body()) {
    List fields = _from_ast(node.cadr(), NULL).flatten();
    return %( $head $fields );
  }
  return %( $head ${node.cadr()} );
}

/* Source specifier text, `("_Noreturn")` or `("__attribute__((unused))")`,
   is written before a declaration's type and is no part of it. A named type
   is spelled the same way and is the type's last item, so only an item
   before it is text. */
static List _without_leading_text(List items) {
  List rest = items;
  while (rest.cdr() && !_is_source_text(rest.car())) rest = rest.cdr();
  if (!rest.cdr()) return items;
  Array typed = [];
  size_t index = 0, last = items.len() - 1;
  foreach (Var item, items)
    if (index++ == last || !_is_source_text(item)) typed.push(item);
  return typed.list_free();
}

static int _is_source_text(Var item) =>
  item is <list> && car(item) is <string>;

static Type Type._modify(Type type, List mods) => %( @mods @type );

/* declarations from types

   Synthesized compiler declarations go through here so pointer, array,
   qualifier, and function-pointer precedence matches parsed source. */

/** Returns `(base modifiers)` for reconstructing a declaration of `type`,
    through `type_declaration_parts` in `lib/meta.x`, which a project's
    helper shares. */
List Type.declaration_parts(Type type) => type_declaration_parts(type);

/** Returns a complete `(declare ...)` AST for `type` and `binding`.
    A `NULL` binding produces an abstract declaration.
*/
List Type.declaration_ast(Type type, List binding) {
  List (base, mods) = type.declaration_parts();
  return %(declare $base (bindings (bind $binding $mods)));
}

/** Returns a complete `(param ...)` AST for `type` and `binding`.
    A `NULL` binding produces an unnamed parameter.
*/
List Type.parameter_ast(Type type, List binding) {
  List (base, mods) = type.declaration_parts();
  return %(param $base (bind $binding $mods));
}

// var tags

/* Only the leaf unit `src/type-ledger.x` imports the Var tag ledger, so it
   defines these two tables' accessors and includes this unit. */
// lint: allow src-forward-declaration FI-6: leaf ledger binding
Map Type.builtin_var_tags(void);
// lint: allow src-forward-declaration FI-6: leaf ledger binding
Map Type.var_tag_rows(void);

/* Source-declared rows are rebuilt for each translation unit because their
   canonical Type keys and converter names may belong to that unit's pools;
   end_unit drops the table before those pools are released. */
static Map declared_typetags = NULL;

/** Returns the unit-local `Var` tag for `type`, falling back to its fixed
    tag.
*/
Symbol Type.var_tag(Type type) {
  if (!type) return 0;
  if (declared_typetags != NULL) {
    Var row = declared_typetags[type.canonicalize()];
    if (row is not void) return row.list().car();
  }
  return type.fixed_var_tag();
}

/** Returns the process-lifetime `Var` tag fixed for `type`, or zero. */
Symbol Type.fixed_var_tag(Type type) {
  if (!type) return 0;
  Symbol scalar = type.scalar_tag();
  if (scalar) return scalar;
  Var vtag = Type.builtin_var_tags()[type.canonicalize()];
  return vtag is <symbol> ? vtag : 0;
}

/** Returns the unit-local forward `Var` converter for the canonical form of
    `type`, or `NULL`.
*/
String Type.var_converter(Type type) {
  if (declared_typetags == NULL || !type) return NULL;
  Var row = declared_typetags[type.canonicalize()];
  if (row is void) return NULL;
  return row.list().cadr();
}

/** Reads the encoding row of `tag` into `top`, `mask`, and `bottom` and
    reports whether one exists. A tag whose decoded form carries a validity
    clause, an immediate width, or a user registration has no constant row.
*/
int Type.var_tag_row(
  Symbol tag, unsigned long &top, unsigned long &mask, unsigned long &bottom) {
  Var row = Type.var_tag_rows()[tag];
  if (row is void) return 0;
  List fields = row;
  top = fields.car();
  mask = fields.cadr();
  bottom = fields.caddr();
  return 1;
}

/** Registers one named type's unit-local `Var` tag and exact forward
    converter. The first row for a canonical `Type` wins. A `NULL` type,
    name, or converter, or no active unit, leaves the table unchanged.
*/
void Type.register_var_tag(Type t, String name, String converter) {
  if (declared_typetags == NULL || !t || !name || !converter) return;
  Type key = t.canonicalize();
  Var row = declared_typetags[key];
  if (row is void)
    declared_typetags[key] = %( ${name.lower().symbol()} $converter );
}

/** Replaces a registered type's inferred `Var` tag with `tag`, or with the
    fixed tag of `representation` when `tag` is zero. Missing rows and
    untagged representations leave the table unchanged.
*/
void Type.register_var_adoption(Type type, Type representation, Symbol tag) {
  if (declared_typetags == NULL || !type) return;
  Type key = type.canonicalize();
  Var row = declared_typetags[key];
  if (!tag && representation) tag = representation.fixed_var_tag();
  if (row is void || !tag) return;
  declared_typetags[key] = %($tag ${row.list().cadr()});
}

/** Starts an empty set of source-declared `Var` rows for one translation
    unit.
*/
void Type.begin_unit(void) {
  declared_typetags = {};
}

/** Ends the source-declared `Var`-row lifetime before the unit `Scope` is
    released.
*/
void Type.end_unit(void) {
  declared_typetags = NULL;
}
