/*  types.x -- compile-time SDK types

    Copyright (c) 2026 Gary William Flake.
*/

static macro Stmt $fail.meta_sdk_fields_type(Expr $value) =>
  _reject_value(
    "Type.fields requires a struct or union Type", $value);

static macro Stmt $fail.meta_sdk_fields_complete(Expr $value) =>
  _reject_value(
    "Type.fields requires a complete struct or union Type", $value);

static macro Stmt $fail.meta_sdk_members_type(Expr $value) =>
  _reject_value("Type.members requires an enum Type", $value);

static macro Stmt $fail.meta_sdk_members_entry(Expr $value) =>
  _reject_value("Type.members found an unreadable member", $value);

/** Tests type ancestry through the active symbol table. */
int Type.is_named(Type type, String name) {
  _require_expansion("Type.is_named");
  return active.expander.sym.is_named_value_type(type, name);
}

/** Resolves numeric typedefs through the active symbol table. */
Type Type.numeric(Type type) {
  _require_expansion("Type.numeric");
  return active.expander.sym.resolve_numeric_type(type);
}

/** Tests the text forms accepted by string arithmetic. */
int Type.is_text(Type type) {
  _require_expansion("Type.is_text");
  return active.expander.sym.is_string_type(type) ||
    type.canonicalize().is_char_pointer_like();
}

/** Implements `Type.aggregate`, declared in `lib/meta.x`. */
Type Type.aggregate(Type type) {
  _require_expansion("Type.aggregate");
  return active.expander.sym.aggregate_of(type);
}

/** Implements `Type.marked_fields`, declared in `lib/meta.x`. */
List Type.marked_fields(Type aggregate, Symbol mark) {
  _require_expansion("Type.marked_fields");
  return active.expander.sym.marked_fields(aggregate, mark);
}

/** Implements `Type.resolve_member`, declared in `lib/meta.x`. */
List Type.resolve_member(Type type, String name, int call) {
  _require_expansion("Type.resolve_member");
  return active.expander.resolve_postfix_member(type, $(name), <.>, call);
}

/** Selects a callable protocol member in the current compilation context.
    The member's own implementation receives no recursive selection.
*/
Code Type.protocol_member(Type type, String name) {
  _require_expansion("Type.protocol_member");
  List resolved = active.expander.resolve_protocol_member(type, name);
  if (!resolved) return NULL;
  (List binding, Type signature) = resolved;
  return $!($signature){ $binding };
}

/** Implements `Type.getter`, declared in `lib/meta.x`, with the getter that
    bracket admission selected.
*/
Code Type.getter(Type type) {
  _require_expansion("Type.getter");
  Compiler c = active.expander;
  List resolved = _x2c_nominal_getindex(c, type);
  if (!resolved) resolved = c.resolve_protocol_member(type, "getindex");
  if (!resolved) return NULL;
  (List binding, Type signature) = resolved;
  return $!($signature){ $binding };
}

/** Implements `Type.update_helper`, declared in `lib/meta.x`. */
String Type.update_helper(Type type) {
  _require_expansion("Type.update_helper");
  Type scalar = active.expander.sym.resolve_numeric_type(type);
  return scalar ? scalar.var_numeric_update_helper() : NULL;
}

// type queries

/** Implements `Type.element`, declared in `lib/meta.x`. */
Type Type.element(Type t) => t.canonicalize().dereference().canonicalize();

/** Implements `Type.parameters`, declared in `lib/meta.x`. */
List Type.parameters(Type type) {
  type = type.canonicalize();
  while (type.is_pointer() || type.is_array()) type = type.dereference();
  return type.match_replace(%((func ?params) *), <?params>);
}

/** Implements `Type.return_type`, declared in `lib/meta.x`. */
Type Type.return_type(Type type) =>
  type.canonicalize().apply().canonicalize();

/** Implements `Type.reverse_name`, declared in `lib/meta.x`. */
String Type.reverse_name(String base, String participant) {
  _require_expansion("Type.reverse_name");
  return active.expander.reverse_converter_spelling(base, "", participant);
}

/** Implements `Type.layout`, declared in `lib/meta.x`. */
List Type.layout(Type type) {
  _require_expansion("Type.layout");
  return active.expander.sym.field_order(type.resolve()).cdr();
}

/** Implements `Type.is_value`, declared in `lib/meta.x`. */
int Type.is_value(Type type) {
  _require_expansion("Type.is_value");
  type = type.canonicalize();
  if (type ~= %((bitfield ?) *rest)) type = rest;
  foreach (String name in %("Symbol" "Var" "Atom" "String" "List"))
    if (active.expander.sym.is_named_value_type(type, name)) return 1;
  return active.expander.sym.resolve_key(type).is_number();
}

/** Implements `Type.tag_name`, declared in `lib/meta.x`. */
Symbol Type.tag_name(String name) {
  _require_expansion("Type.tag_name");
  String file = active.expander.source_path(active.expander.filename);
  file = active.expander.display_path(file);
  String identity = %"$file:$name";
  unsigned hash = identity.hash();
  const char *alphabet = "abcdefghijklmnopqrstuvwxyz*+?!-";
  char encoded[9] = { 'c' };
  for (int i = 1; i < 8; i++) {
    encoded[i] = alphabet[hash % 31];
    hash /= 31;
  }
  return Symbol.new(encoded);
}

/** Implements `Type.members`, declared in `lib/meta.x`. */
List Type.members(Type type) {
  Type resolved = type.resolve();
  if (resolved.car() != <enum>)
    $fail.meta_sdk_members_type(type);
  Array rows = [];
  foreach (List member in resolved.last()) rows.push(_enum_member(member));
  return rows.list_free();
}

// meta parameter descriptions

/** Returns what a `meta` parameter declared `TypeInfo` receives for the
    captured syntax `value`: `((name N) (kind K) (type T) (fields F)
    (methods M))`.
    `T` is the canonical type of `value` and `N` its name, or "" when it has
    none. `K` is `struct`, `union`, `enum`, `pointer`, `scalar`, or `other`,
    `F` lists the `(name type)` rows of a struct or union's named fields,
    and `M` the names of its direct dotted methods.
*/
List MetaContext.type_description(Var value) {
  Type type = Code.type(value);
  Type shape = Type.resolve(type);
  String name = "";
  match (type) {
    case %(?(String own)): name = own;
    case %((!or struct union enum) ?(String own)): name = own;
    default:
      if (_symbol_words(type) && !type.is_pointer()) {
        Array words = [];
        foreach (Symbol word in type) words.push(word.str());
        name = " ".join(words);
      }
  }
  Var kind = <other>;
  List fields = %();
  match (shape) {
    case %((!or struct union enum) *): kind = shape.car();
    default:
      if (shape.is_pointer()) kind = <pointer>;
      else if (_symbol_words(shape)) kind = <scalar>;
  }
  if (kind == <struct> || kind == <union>) fields = Type.fields(type);
  Compiler c = active.expander;
  Array methods = [];
  foreach (String member in c.postfix_completions(type, <.>))
    match (c.resolve_postfix_member(type, $(member), <.>, 1))
      case %(method * *): methods.push(member);
  return %((name $name) (kind $kind) (type $type) (fields $fields)
           (methods $(methods.list_free())));
}

/** Implements `Type.resolve`, declared in `lib/meta.x`. */
Type Type.resolve(Type type) {
  _require_expansion("Type.resolve");
  return active.expander.sym.resolve_key(type).type_from_ast();
}

/** Implements `Type.fields`, declared in `lib/meta.x`. */
List Type.fields(Type t) {
  _require_expansion("Type.fields");
  Type resolved = active.expander.sym.resolve_key(t.canonicalize());
  /* is_aggregate_tag rejects an empty resolved Type. */
  if (!resolved.is_aggregate_tag())
    $fail.meta_sdk_fields_type(t);
  List metadata = active.expander.sym.field_order(resolved);
  if (!metadata)
    $fail.meta_sdk_fields_complete(t);
  Array named = [];
  foreach (List row in metadata.cdr()) if (row.car()) named.push(row);
  return named.list_free();
}

// compile-time SDK types

/* One enum member's `(NAME VALUE)` row: no value, a literal's spelling,
   or the initializer's expression. */
static List _enum_member(List member) {
  match (member) {
    case %(op = (?name) (expr ? (literal ? ?text))): return $(name, text);
    case %(op = (?name) (?text)): return $(name, text);
    case %(op = (?name) ?value): return $(name, value);
    case %(?name): return %($name ());
  }
  $fail.meta_sdk_members_entry(member);
  return %();
}

/* Whether the type `type` is spelled by keywords alone, such as `(int)`. */
static int _symbol_words(List type) {
  foreach (Var word in type) if (word is not <symbol>) return 0;
  return type != NULL;
}
