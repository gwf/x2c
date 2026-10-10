/*  meta-sdk.x -- the compiler's answers to `lib/meta.x` operations

    Copyright (c) 2026 Gary William Flake.

    Compile-time code asks the compiler about syntax, types, names, and
    source through the operations `lib/meta.x` declares, and the built-in
    macros ask through their own entries here. A native operation has no
    Compiler parameter, so each answer reads the running call's
    `MetaContext`, which the evaluations in `macros.x` install for their
    extent. An operation that cannot answer reports at the active
    invocation and never returns.
*/

#pragma once
#include "compiler.x"

/** What the running compile-time call answers from. `expander` is the
    compiler of the active macro expansion, `definition_file` the source of
    its definition, `captures` its complete captured syntax by identity, and
    `has_bindings` whether it bound captured values. `evaluator` is the
    compiler evaluating Lisp and `site` where that evaluation stands, which
    a nested import changes without an expansion. Each evaluation installs
    its part with `$let`, so a captured entry is valid only while its
    expansion is active. */
typedef struct MetaContext {
  Compiler expander, evaluator;
  String definition_file;
  Map captures;
  int has_bindings;
  Token site;
} MetaContext;

#include "grammar.x"
#include "macros.x"
#include "meta.x"
#include <limits.h>
#include <stdint.h>
#include <sys/stat.h>

/* Compile-time SDK rejection messages and notes. */

static macro Stmt $report.sdk.fields_type(Expr $value) =>
  _sdk_reject_value(
    "Type.fields requires a struct or union Type", $value);

static macro Stmt $report.sdk.fields_complete(Expr $value) =>
  _sdk_reject_value(
    "Type.fields requires a complete struct or union Type", $value);

static macro Stmt $report.sdk.binding_spelling(Expr $syntax) =>
  _sdk_reject_value(
    "Code.binding_spelling requires an identifier spelling", $syntax);

static macro Stmt $report.sdk.binding_syntax(Expr $syntax) =>
  _sdk_reject_value(
    "Code.binding_spelling requires binding syntax", $syntax);

static macro Stmt $report.sdk.binding_known(Expr $value) =>
  MetaContext.reject(
    "Code.binding_spelling requires a known binding",
    %("binding: ${$value.repr()}"));

static macro Stmt $report.sdk.binding_identifier(Expr $syntax) =>
  _sdk_reject_value(
    "Code.binding_spelling requires an identifier or binding", $syntax);

static macro Stmt $report.sdk.identifier(Expr $spelling) =>
  _sdk_reject_value(
    "x2c.ident requires an identifier spelling", $spelling);

static macro Stmt $report.sdk.unique_stem(Expr $stem) =>
  _sdk_reject_value(
    "_x2c.name.unique requires an identifier stem", $stem);

static macro Stmt $report.sdk.parameter_missing(
  Expr $function, Expr $wanted) =>
  MetaContext.reject(
    %"Code.parameter cannot find '${$wanted}'",
    %("function: ${Code.name($function).repr()}"));

static macro Stmt $report.sdk.symbol_set_value(Expr $value) =>
  MetaContext.reject(
    "_x2c.symbol-set requires Symbols", %("value:" ${$value.repr()}));

static macro Stmt $report.sdk.symbol_set_duplicate(
  Expr $values, Expr $duplicate) =>
  MetaContext.reject(
    "_x2c.symbol-set requires distinct Symbols",
    %("symbol:" ${$values[$duplicate].repr()}));

static macro Stmt $report.sdk.native_declarations() =>
  MetaContext.reject(
    "native module sources declare no meta function",
    %("declare each exported function with a bodyless meta prototype"));

static macro Stmt $report.sdk.source_capture(Expr $value) =>
  MetaContext.reject(
    "Code.source_text requires complete captured syntax",
    active.has_bindings ? NULL : %("value: ${$value.repr()}"));

static macro Stmt $report.sdk.embed_path_empty() =>
  MetaContext.reject("x2c.embed.text requires a non-empty path", NULL);

static macro Stmt $report.sdk.embed_literal(Expr $requested) =>
  _sdk_reject_value(
    "x2c.embed.text requires a String or captured String literal",
    $requested);

static macro Stmt $report.sdk.embed_read(Expr $c, Expr $path) =>
  $c._embed_reject("cannot read embedded text", $path);

static macro Stmt $report.sdk.embed_nul(Expr $c, Expr $path) =>
  $c._embed_reject("embedded text contains an embedded NUL", $path);

static macro Stmt $report.sdk.embed_size(Expr $c, Expr $path) =>
  $c._embed_reject("embedded text exceeds the String size limit", $path);

static macro Stmt $report.sdk.embed_file(Expr $c, Expr $path) =>
  $c._embed_reject("embedded text is not a regular file", $path);

static macro Stmt $report.sdk.embed_open(Expr $c, Expr $path) =>
  $c._embed_reject("cannot open embedded text", $path);

static macro Stmt $report.sdk.invocation_missing() =>
  MetaContext.reject(
    "x2c invocation location used outside macro expansion", NULL);

static macro Stmt $report.sdk.notes_string(Expr $operation, Expr $note) =>
  _sdk_reject_value(%"${$operation} notes must be Strings", $note);

static macro Stmt $report.sdk.expansion_required(Expr $operation) =>
  MetaContext.reject(%"${$operation} used outside macro expansion", NULL);

static macro Expression $report.sdk.path_notes(Expr $c, Expr $path) =>
  %("path: ${$c.display_path($path)}");

static macro Expression $report.sdk.value_notes(Expr $value) =>
  %("value: ${$value.repr()}");

// the running call

static MetaContext active;

/** Returns the context of the running compile-time call, which an
    evaluation changes with `$let` for its own extent. */
MetaContext *MetaContext.current(void) => &active;

/** Returns the compiler running the current compile-time call. A slot
    function compiled into the compiler reads its facts through it. */
Compiler Compiler.expanding(void) =>
  active.expander ? active.expander : active.evaluator;

/** Tests type ancestry through the active symbol table. */
int Type.is_named(Type type, String name) {
  _sdk_guard("Type.is_named");
  return active.expander.sym.is_named_value_type(type, name);
}

/** Resolves numeric typedefs through the active symbol table. */
Type Type.numeric(Type type) {
  _sdk_guard("Type.numeric");
  return active.expander.sym.resolve_numeric_type(type);
}

/** Tests the text forms accepted by string arithmetic. */
int Type.is_text(Type type) {
  _sdk_guard("Type.is_text");
  return active.expander.sym.is_string_type(type) ||
    type.canonicalize().is_char_pointer_like();
}

/** Answers `Type.aggregate`, declared in `lib/meta.x`. */
Type Type.aggregate(Type type) {
  _sdk_guard("Type.aggregate");
  return active.expander.sym.aggregate_of(type);
}

/** Answers `Type.marked_fields`, declared in `lib/meta.x`. */
List Type.marked_fields(Type aggregate, Symbol mark) {
  _sdk_guard("Type.marked_fields");
  return active.expander.sym.marked_fields(aggregate, mark);
}

/** Answers `Type.resolve_member`, declared in `lib/meta.x`. */
List Type.resolve_member(Type type, String name, int call) {
  _sdk_guard("Type.resolve_member");
  return active.expander.resolve_postfix_member(type, %($name), <.>, call);
}

/** Selects a callable protocol member in the current compilation context.
    The member's own implementation receives no recursive selection. */
Code Type.protocol_member(Type type, String name) {
  _sdk_guard("Type.protocol_member");
  List resolved = active.expander.resolve_protocol_member(type, name);
  if (!resolved) return NULL;
  (List binding, Type signature) = resolved;
  return $!($signature){ $binding };
}

/** Answers `Type.getter`, declared in `lib/meta.x`, with the getter that
    bracket admission selected. */
Code Type.getter(Type type) {
  _sdk_guard("Type.getter");
  Compiler c = active.expander;
  List resolved = c._nominal_getindex(type);
  if (!resolved) resolved = c.resolve_protocol_member(type, "getindex");
  if (!resolved) return NULL;
  (List binding, Type signature) = resolved;
  return $!($signature){ $binding };
}

/** Answers `Type.update_helper`, declared in `lib/meta.x`. */
String Type.update_helper(Type type) {
  _sdk_guard("Type.update_helper");
  Type scalar = active.expander.sym.resolve_numeric_type(type);
  return scalar ? scalar.var_numeric_update_helper() : NULL;
}

// syntax queries

/** Answers the compiler-backed captured-code type query. */
Type Code.type(Code value) {
  _sdk_guard("Code.type");
  match (value) {
    case %(expr ?matched_type ?): {
      Type type = matched_type;
      if (type === %(<macro-expr>))
        type = active.expander.resolve_expression(value, active.site).cadr();
      return type.canonicalize();
    }
    case %(param ? ?):  return value.type_from_ast().canonicalize();
    case %((!or declare decl typedef) *):
      return value.type_from_ast().canonicalize();
  }
  List binding = NULL;
  if (binding_identity_try_parts(value, NULL, NULL)) binding = value;
  else
    match (value) {
      case $source_identifier_content(%((!set ?captured (*)) *)):
        binding = captured;
      case %(bind (!set ?captured (*)) *): binding = captured;
    }
  if (binding) return _sdk_binding_type(binding).canonicalize();
  return List.type(value).canonicalize();
}

/** Reads a constant through the compiler's existing constant decoder. */
Var Code.value(Code code) {
  _sdk_guard("Code.value");
  Compiler compiler = Compiler.expanding();
  match (code) {
    case %(expr ? (macro-value ?definition)):
      code = compiler.capture_macro_value(definition);
  }
  Var value = compiler.folded_constant(code);
  if (value is void)
    MetaContext.reject("captured code is not a compile-time constant", NULL);
  return value;
}

/** Answers `Code.call_in_order`, declared in `lib/meta.x`. The call binds
    its temporaries here, so the result is a carrier that binds no
    further. */
Code Code.call_in_order(Code member, List arguments, Type type) {
  _sdk_guard("Code.call_in_order");
  List call = active.expander.call_in_order(member, arguments);
  return Code.lowered(%(expr $type $call));
}

/** Answers `Code.lowered`, declared in `lib/meta.x`, with the carrier
    `Compiler.take_code_value` consumes. */
Code Code.lowered(Code code) => %(code-value "lowered" $code ());

/** Answers `Code.exits`, declared in `lib/meta.x`. */
int Code.exits(Code statement) {
  _sdk_guard("Code.exits");
  return reference_guard_exits(statement);
}

/** Answers `Code.convert`, declared in `lib/meta.x`. */
Code Code.convert(Code value, Type target) {
  _sdk_guard("Code.convert");
  return active.expander.convert_expression(value, target);
}

/** Answers `Code.format`, declared in `lib/meta.x`. */
String Code.format(Code value) {
  _sdk_guard("Code.format");
  return active.expander.printf_static_format(value);
}

/** Answers `Code.is_static_pattern`, declared in `lib/meta.x`. */
int Code.is_static_pattern(Code pattern) {
  _sdk_guard("Code.is_static_pattern");
  return active.expander.match_pattern_is_static(pattern);
}

/** Answers `Code.promoted`, declared in `lib/meta.x`. */
Code Code.promoted(Code value) {
  _sdk_guard("Code.promoted");
  return active.expander.promote_string_literal(value);
}

/* Default holes retain the macro's declared capture names and cardinality. */
static List _rewrite_holes(Macro shape, List supplied) {
  if (supplied) return supplied;
  Array holes = [];
  foreach (List parameter, shape.assoc(<parameters>).list()) {
    String binder = parameter.assoc(<binder>).str();
    String prefix = parameter.assoc(<sequence>).int() ? "*" : "?";
    holes.push(Atom.intern(prefix + binder[1:]));
  }
  return holes.list_free();
}

/* One rule row for each of `kinds`. */
static Code _rewrite_registration(
  Code function, List shape, List holes, Symbol point, List kinds) {
  String name = Code.name(function);
  Array rows = [];
  foreach (Var kind, kinds)
    rows.push(%(rewrite $point $kind $name $shape $holes));
  return %((code-value "bound" $function ${rows.list_free()}));
}

/* A function pattern is keyed by the return type it spells, or by `<any>`
   when a hole stands there. */
static Var _function_rule_key(Var type) => _ground(type) ? type : <any>;

static int _ground(Var pattern) {
  if (pattern is not <list>)
    return !pattern.is_binder() && !pattern.is_match_op();
  foreach (Var part, pattern.list()) if (!_ground(part)) return 0;
  return 1;
}

/* A Unit macro whose body is its one `Function` hole matches every
   function definition. */
static int _function_hole(Macro shape) {
  List parameters = shape.assoc(<parameters>);
  if (parameters.len() != 1 ||
      parameters.car().list().assoc(<kind>) != <function>)
    return 0;
  match (shape.assoc(<template>)) case %(seq ?only): return only.is_binder();
  return 0;
}

/* The operators an operator position names: one operator, or each of
   `(!or OP...)`, any of them quoted. */
static List _rule_operators(Var position) {
  List operators = %($position);
  match (position) case %((!quote !or) *choices): operators = choices;
  Array found = [];
  foreach (Var operator, operators) {
    match (operator) case %((!quote !quote) ?quoted): operator = quoted;
    found.push(operator);
  }
  return found.list_free();
}

/* Whether an operator pattern types its operation, `type`, or one of
   `operands` with `Var` or an alias of it, which selects the dynamic
   operations. */
static int _rule_dynamic(Var type, List operands) {
  if (_rule_var(type)) return 1;
  foreach (Var operand, operands) {
    match (operand) case %((!quote !and) ?inner): operand = inner;
    match (operand) case %(expr ?operand_type *):
      if (_rule_var(operand_type)) return 1;
  }
  return 0;
}

static int _rule_var(Var type) =>
  type is <list> && active.expander.sym.is_var_type(type);

/* The dynamic family's keys for `operators` in `form`, `op` or `postfix`. */
static List _rule_dynamic_kinds(List operators, Symbol form) {
  Array kinds = [];
  foreach (Symbol operator, operators)
    kinds.push(
      form == <postfix> ? %(postfix $operator ("Var")) : %($operator ("Var")));
  return kinds.list_free();
}

/* `holes` with a receiver hole `(expr MARK *)` matching any receiver. */
static List _unmarked(List holes, Symbol mark) {
  Array kept = [];
  foreach (Var hole, holes)
    kept.push(hole == %(expr $mark *) ? %(expr ? *) : hole);
  return kept.list_free();
}

/** Answers `Code.register_rewrite`, declared in `lib/meta.x`: the
    pattern's form selects the family and its keys. A function rule is
    keyed by return type, which `Compiler.normalize` dispatches once per
    definition before its body lowers. */
Code Code.register_rewrite(Code function, List pattern, List holes) {
  _sdk_guard("Code.register_rewrite");
  Macro shape = NULL;
  match (pattern) case %(macrodef *): {
    shape = pattern;
    if (!holes && _function_hole(shape))
      return _rewrite_registration(
        function, shape, %((!and ?function (function *))), <function>,
        %(any));
    holes = _rewrite_holes(shape, holes);
    pattern = shape.pattern(holes);
  }
  Symbol point = 0;
  List kinds = NULL;
  match (pattern) {
    case %(expr ? (index ? ?)): { point = <access>; kinds = %(read); }
    case %(expr ?type (op ?position ?left ?right)): {
      kinds = _rule_operators(position);
      Symbol operator = kinds.car();
      point = operator.is_assignment_op() ? 0 : <binary>;
      match (left) case %(expr ? (index ? ?)):
        if (operator.is_assignment_op()) point = <access>;
      if (_rule_dynamic(type, %($left $right))) {
        point = <binary>;
        kinds = _rule_dynamic_kinds(kinds, <op>);
      }
    }
    case %(expr ? (op ((!quote !quote) (!or ++ --)) (expr ? (index ? ?)))):
      { point = <access>; kinds = %(prefix); }
    case %(expr ? (postfix ? (expr ? (index ? ?)))):
      { point = <access>; kinds = %(postfix); }
    case %(expr ?type ((!set ?form (!or op postfix)) ?position ?operand)):
      if (_rule_dynamic(type, %($operand))) {
        point = <unary>;
        kinds = _rule_dynamic_kinds(_rule_operators(position), form);
      }
    case %(expr ? (call (expr ? (op ((!quote !quote) .)
            ((!quote !and) (expr ?type *)) ?)) ?)): {
      point = <member>;
      kinds = %($type);
      if (type is <symbol>) holes = _unmarked(holes, type);
    }
    case %(expr ? (call (expr ? (ident (binding ? ?(String callee)))) ?)):
      { point = <call>; kinds = %($callee); }
    case %(expr ? ((!set ?head (!or array map)) *)):
      { point = <literal>; kinds = %($head); }
    case %((!quote !or) ((!set ?head (!or switch try raise)) *) *):
      { point = <node>; kinds = %($head); }
    case %((!set ?head (!or switch try raise)) *):
      { point = <node>; kinds = %($head); }
    case %(!or (api-source ? ? (function ?type *)) (function ?type *)):
      { point = <function>; kinds = %(${_function_rule_key(type)}); }
  }
  if (!point) MetaContext.reject("unsupported rewrite pattern", NULL);
  return _rewrite_registration(
    function, shape ? shape : pattern, holes, point, kinds);
}

/** Adds post-initialization block items while the declaration owner retains
    the original declarators, their type identity, and initialization order. */
Code Code.register_after_initialization(Code c, Macro shape, List holes) {
  _sdk_guard("Code.register_after_initialization");
  holes = _rewrite_holes(shape, holes);
  List pattern = shape.pattern(holes);
  match (pattern) case %(declare *):
    return _rewrite_registration(c, shape, holes, <decl>, %(init));
  MetaContext.reject("after-initialization requires a declaration pattern", NULL);
}

static Type _sdk_binding_type(List binding) =>
  active.expander.semantic_binding_facts()[%(type $binding)];

/** Returns an expression reading each binding `declaration` declares. */
List builtin_foreach_bindings(List declaration) {
  Array result = [];
  match (declaration)
    case %((!or declare decl typedef) ? (bindings *bindings)):
      foreach (List binding, bindings) {
        List bound = binding;
        match (binding) case %(op = ?target ?): bound = target;
        match (bound) {
          case %(bind (!set ?identity (binding ? ?)) *): {
            List type = _sdk_binding_type(identity);
            result.push(%(expr $type (ident $identity)));
          }
          case %(bind ?name ?mods): {
            List row = %(
              declare ${declaration.cadr()}
                (bindings (bind $name $mods))
            );
            result.push(%(expr ${row.type_from_ast()} (ident $name)));
          }
        }
      }
  return result.list_free();
}

/** Returns the typed expression naming the function `name`, or an empty
    List when no function of that name is visible. This reads the symbol
    table only, so any compile-time Lisp evaluation may call it, including
    one outside a macro expansion. */
List builtin_foreach_reference(String name) {
  Compiler c = active.evaluator;
  if (!c) raise %(bad-state (operation "_x2c.function.reference"));
  Type type = NULL;
  List binding = c.sym.lookup(%($name), type);
  if (!binding || !type || !type.is_function()) return %();
  return %(expr $type (ident $binding));
}

// type queries

/** Answers `Type.element`, declared in `lib/meta.x`. */
Type Type.element(Type type) =>
  type.canonicalize().dereference().canonicalize();

/** Answers `Type.parameters`, declared in `lib/meta.x`. */
List Type.parameters(Type type) {
  type = type.canonicalize();
  while (type.is_pointer() || type.is_array()) type = type.dereference();
  return type.match_replace(%((func ?params) *), <?params>);
}

/** Answers `Type.return_type`, declared in `lib/meta.x`. */
Type Type.return_type(Type type) =>
  type.canonicalize().apply().canonicalize();

/** Answers `x2c.type.parts`, declared in `lib/meta.x`. */
List x2c_type_parts(List value) => Type.parts(value);

/** Answers `x2c.type.resolve`, declared in `lib/meta.x`. */
List x2c_type_resolve(List value) => Type.resolve(value);

/** Answers `x2c.source.text`, declared in `lib/meta.x`. */
String x2c_source_text(Var value) => Code.source_text(value);

/** Answers `Type.reverse_name`, declared in `lib/meta.x`. */
String Type.reverse_name(String base, String participant) {
  _sdk_guard("Type.reverse_name");
  return active.expander.reverse_converter_spelling(base, "", participant);
}

/** Answers `Type.resolve`, declared in `lib/meta.x`. */
Type Type.resolve(Type type) {
  _sdk_guard("Type.resolve");
  return active.expander.sym.resolve_key(type).type_from_ast();
}

/** Answers `Type.layout`, declared in `lib/meta.x`. */
List Type.layout(Type type) {
  _sdk_guard("Type.layout");
  return active.expander.sym.field_order(type.resolve()).cdr();
}

/** Answers `Type.is_value`, declared in `lib/meta.x`. */
int Type.is_value(Type type) {
  _sdk_guard("Type.is_value");
  type = type.canonicalize();
  match (type) case %((bitfield ?) *rest): type = rest;
  foreach (String name, %("Symbol" "Var" "Atom" "String" "List"))
    if (active.expander.sym.is_named_value_type(type, name)) return 1;
  return active.expander.sym.resolve_key(type).is_number();
}

/** Answers `Type.tag_name`, declared in `lib/meta.x`. */
Symbol Type.tag_name(String name) {
  _sdk_guard("Type.tag_name");
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

/** Answers `Type.members`, declared in `lib/meta.x`. */
List Type.members(Type type) {
  Type resolved = type.resolve();
  if (resolved.car() != <enum>)
    _sdk_reject_value("Type.members requires an enum Type", type);
  Array rows = [];
  foreach (List member, resolved.last()) rows.push(_enum_member(member));
  return rows.list_free();
}

/* One enum member's `(NAME VALUE)` row: no value, a literal's spelling,
   or the initializer's expression. */
static List _enum_member(List member) {
  match (member) {
    case %(op = (?name) (expr ? (literal ? ?text))): return %($name $text);
    case %(op = (?name) (?text)): return %($name $text);
    case %(op = (?name) ?value): return %($name $value);
    case %(?name): return %($name ());
  }
  _sdk_reject_value("Type.members found an unreadable member", member);
  return %();
}

/** Answers `Type.fields`, declared in `lib/meta.x`. */
List Type.fields(Type type) {
  _sdk_guard("Type.fields");
  Type resolved = active.expander.sym.resolve_key(type.canonicalize());
  if (!resolved || !resolved.is_aggregate_tag())
    $report.sdk.fields_type(type);
  List metadata = active.expander.sym.field_order(resolved);
  if (!metadata)
    $report.sdk.fields_complete(type);
  Array named = [];
  foreach (List row, metadata.cdr()) if (row.car()) named.push(row);
  return named.list_free();
}

// names and functions

/** Answers `Code.binding_spelling`, declared in `lib/meta.x`. */
String Code.binding_spelling(Var syntax) {
  _sdk_guard("Code.binding_spelling");
  if (syntax is <string>) {
    String spelling = syntax;
    if (spelling.is_identifier()) return spelling;
    $report.sdk.binding_spelling(syntax);
  }
  if (syntax is not <list> || syntax.is_nil())
    $report.sdk.binding_syntax(syntax);
  List value = syntax;
  match (value)
    case %(expr ? (!set ?content (? *))): value = content;
  match (value) {
    case $source_identifier_content(%((!set ?captured (*)))):
      value = captured;
    case %(bind (!set ?captured (*)) ?): value = captured;
  }
  match (value)
    case %((!is ?name type string)): return name;
  return _binding_spelling(value, syntax);
}

static String _binding_spelling(List value, Var syntax) {
  int identity = 0, String spelling = NULL;
  match (value)
    case %(binding ?id (!is ? type string)):
      if (!id.is_integer() || id.integer() > INT_MAX)
        $report.sdk.binding_known(value);
  if (!binding_identity_try_parts(value, identity, spelling))
    $report.sdk.binding_identifier(syntax);
  Var registered =
    active.expander.semantic_binding_facts()[%(known $identity)];
  if (registered is not <string> || registered.string() != spelling)
    $report.sdk.binding_known(value);
  return spelling;
}

/** Answers `x2c.ident`, declared in `lib/meta.x`. */
List x2c_ident(String spelling) {
  _sdk_guard("x2c.ident");
  if (!spelling.is_identifier())
    $report.sdk.identifier(spelling);
  return %("x2c.ident" $spelling);
}

/** Returns a fresh binding whose spelling starts with `stem`. */
Var builtin_foreach_unique(String stem) {
  _sdk_guard("_x2c.name.unique");
  if (!stem.is_identifier())
    $report.sdk.unique_stem(stem);
  String spelling = active.expander.fresh_name(%"macro_$stem");
  return active.expander.sym.introduce(spelling);
}

/** Answers `x2c.meta.definition.hashes`, declared in `lib/meta.x`. */
Map x2c_meta_definition_hashes(void) {
  _sdk_guard("x2c.meta.definition.hashes");
  Compiler c = active.expander;
  Map hashes = {};
  foreach (String name, c.meta_calls.keys())
    hashes[name] = c.meta_hashes[name];
  return hashes;
}

/* Imported functions refer to their provider's shared definition hash.
   Fully parsed copies retain their own hashes and precise references. */
static Map _sdk_linked_hashes(void) {
  _sdk_guard("_x2c.meta.linked.hashes");
  Compiler c = active.expander;
  Map rows = {};
  c.add_linked_meta_provider_hashes(rows);
  foreach (Var (name, source), c.project_meta)
    match (source) case %(? ?provider): {
      Map hashes = c.meta_provider_hashes(provider);
      rows[name] = %(${hashes[name]} $provider);
    }
  foreach (String name, c.meta_calls.keys())
    rows[name] = %(${c.meta_hashes[name]} ${c.meta_calls[name]});
  return rows;
}

/* The prelude components' interface records, which `src/collect.x` links
   into the compiler it is translated into. */
static Map _sdk_linked_prelude(void) {
  _sdk_guard("_x2c.prelude.linked");
  return active.expander.linked_prelude_records();
}

/** Answers `Code.name`, declared in `lib/meta.x`. */
String Code.name(Code function) {
  List identity = function.match_replace(
    %(function ? (bind ?binding ?) ?), <?binding>);
  return Code.binding_spelling(identity);
}

/** Answers `Code.body`, declared in `lib/meta.x`. */
List Code.body(Code function) {
  match (function) case %(function ? ? (block *body)): return body;
  return %();
}

/** Answers `Code.arguments`, declared in `lib/meta.x`. */
List Code.arguments(Code parameters) {
  match (parameters) case %(params *items): parameters = items;
  match (parameters) case %((param (void) (bind () ?))): return %();
  Array arguments = [];
  foreach (List parameter, parameters)
    match (parameter)
      case %(param ? (bind ?identity *)):
        arguments.push(%(expr () (ident $identity)));
  return arguments.list_free();
}

/** Answers `Code.parameter`, declared in `lib/meta.x`. */
Code Code.parameter(Code function, String wanted) {
  List parameters = function.match_replace(
    %(function ? (bind ? ((fnmod (params *bound)) *)) ?), %(*bound));
  foreach (List parameter, parameters) {
    match (parameter) {
      case %(param ? (bind ?identity *)):
        if (Code.binding_spelling(identity) == wanted) {
          Type type = parameter.type_from_ast().canonicalize();
          return %(expr $type (ident $identity));
        }
    }
  }
  $report.sdk.parameter_missing(function, wanted);
}

/** Returns the `Func` signature of the function syntax `syntax`. A native
    binding stores the same signature as an ordinary Func adapter. */
List binding_native_type(List syntax) {
  match (syntax)
    case %(function ?rtype ?declarator ?):
      return active.expander.func_signature(
        %(declare $rtype (bindings $declarator)).type_from_ast());
  return active.expander.func_signature(Code.type(syntax));
}

/** Returns `values`, such as a Lisp-built signature, as a cached literal
    of the expanding unit. */
List binding_literal_list(List values) =>
  active.expander.cache_literal_list(values);

static Var _sdk_symbol_set(List values) {
  _sdk_guard("_x2c.symbol-set");
  foreach (Var value, values)
    if (value is not <symbol>)
      $report.sdk.symbol_set_value(value);
  int duplicate = -1;
  List expression = active.expander.symbol_set_expression(values, duplicate);
  if (duplicate >= 0)
    $report.sdk.symbol_set_duplicate(values, duplicate);
  return expression;
}

static List _sdk_meta_targets(void) => Compiler.native_meta_targets(NULL);

/* A native module's entry exports the prototypes its own sources declare,
   and a module that declares none is a mistake. */
static List _sdk_meta_declared(List paths) {
  List rows = Compiler.native_meta_targets(paths);
  if (!rows)
    $report.sdk.native_declarations();
  return rows;
}

// source and literals

/** Answers `Code.source_text`, declared in `lib/meta.x`. */
String Code.source_text(Var value) {
  match (value) case %((text ?(String text)) (file ?) (syntax ?)): return text;
  _sdk_guard("Code.source_text");
  Var stored = void;
  if (!active.captures ||
      !active.captures.try_get(((ulong) value.u64), stored))
    $report.sdk.source_capture(value);
  List source = stored;
  int begin = source.caddr(), end = source.last();
  return String.new_len(active.expander.text + begin, end - begin);
}

/** Answers `x2c.embed.text`, declared in `lib/meta.x`. */
String x2c_embed_text(Var requested) {
  _sdk_guard("x2c.embed.text");
  Compiler c = active.expander;
  String source_file = active.definition_file, requested_path = NULL;
  if (requested is <string>) requested_path = requested;
  else requested_path = _embed_literal(requested, source_file);
  if (!requested_path.len())
    $report.sdk.embed_path_empty();
  String path = c._embed_path(source_file, requested_path);
  String text = c.sources ? c._embed_source(path) : c._embed_file(path);
  c.deps.merge_translation_dependency(path, "%08x".printf(text.hash()));
  return text;
}

static String Compiler._embed_path(
  Compiler c, String source_file, String requested) {
  if (requested[0] == '/') return c.canonical_path(requested);
  String base = Path.dirname(c.source_path(source_file));
  return c.canonical_path(%"$base/$requested");
}

static String _embed_literal(Var requested, String &source_file) {
  Var stored = void, syntax = requested;
  match (requested)
    case %((text ?) (file ?(String file)) (syntax ?carried)): {
      syntax = carried;
      stored = %(source $file);
    }
  if (stored is void && active.captures)
    active.captures.try_get(((ulong) requested.u64), stored);
  String requested_path = NULL;
  if (stored is void || !_literal_string(syntax, requested_path))
    $report.sdk.embed_literal(requested);
  List source = stored;
  source_file = source.cadr();
  return requested_path;
}

static String Compiler._embed_source(Compiler c, String path) {
  String text;
  if (!c.read_source(path, text))
    $report.sdk.embed_read(c, path);
  return text;
}

static String Compiler._embed_file(Compiler c, String path) {
  File file = c._open_embed_file(path);
  String text = NULL;
  try text = file.string_close();
  catch %(io-fail *): $report.sdk.embed_read(c, path);
  catch %(bad-arg *):
    $report.sdk.embed_nul(c, path);
  catch %(size-limit *):
    $report.sdk.embed_size(c, path);
  return text;
}

static File Compiler._open_embed_file(Compiler c, String path) {
  struct stat info;
  if (!stat(path, &info) && !S_ISREG(info.st_mode))
    $report.sdk.embed_file(c, path);
  File file = NULL;
  try file = path.open("r");
  catch %((!or not-found io-fail) *):
    $report.sdk.embed_open(c, path);
  if (file.stat(&info) || !S_ISREG(info.st_mode)) {
    file.close();
    $report.sdk.embed_file(c, path);
  }
  if ((uintmax_t) info.st_size >= INT_MAX) {
    file.close();
    $report.sdk.embed_size(c, path);
  }
  return file;
}

static void Compiler._embed_reject(Compiler c, String message, String path) {
  MetaContext.reject(message, $report.sdk.path_notes(c, path));
}

static int _literal_string(Var syntax, String &value) {
  match (syntax)
    case %(expr ? ${$source_literal_content(%(? ?source))}): {
      if (source is not <string>) break;
      String text = source;
      int quoted = text.len() >= 2 && text[0] == '"' &&
        text[text.len() - 1] == '"';
      int percent_quoted = text.len() >= 3 && text[0] == '%' &&
        text[1] == '"' && text[text.len() - 1] == '"';
      if (quoted || percent_quoted) {
        value = text.parse();
        return 1;
      }
    }
  return 0;
}

// invocations and diagnostics

/** Returns the location of the active macro invocation. */
List builtin_class_location(void) {
  if (!active.expander || !active.site)
    $report.sdk.invocation_missing();
  return active.expander.token_location(active.site);
}

/** Answers `x2c.invocation.file`, declared in `lib/meta.x`. */
String x2c_invocation_file(void) =>
  builtin_class_location().assoc(<file>);

/** Answers `x2c.invocation.line`, declared in `lib/meta.x`. */
int x2c_invocation_line(void) =>
  builtin_class_location().assoc(<line>);

/** Answers `x2c.invocation.column`, declared in `lib/meta.x`. */
int x2c_invocation_column(void) =>
  builtin_class_location().assoc(<column>);

/** Answers `x2c.diagnostic.fail`, declared in `lib/meta.x`. */
void x2c_diagnostic_fail(String message, List notes) {
  _sdk_check_notes("x2c.diagnostic.fail", notes);
  MetaContext.reject(message, notes);
}

/** Answers `x2c.diagnostic.fail.at`, declared in `lib/meta.x`. */
void x2c_diagnostic_fail_at(
  Var node, Symbol category, String message, List notes) {
  _sdk_check_notes("x2c.diagnostic.fail.at", notes);
  active.expander.report_meta_error(
    node, category, message, active.site, notes, 1);
}

/** Answers `x2c.diagnostic.error.at`, declared in `lib/meta.x`. */
void x2c_diagnostic_error_at(
  Var node, Symbol category, String message, List notes) {
  _sdk_check_notes("x2c.diagnostic.error.at", notes);
  active.expander.report_meta_error(
    node, category, message, active.site, notes, 0);
}

/** A warning reports where it is raised and returns, so a macro can keep
   expanding. Failure stays separate because it never returns. */
void x2c_diagnostic_warn(String message, List notes) {
  _sdk_check_notes("x2c.diagnostic.warn", notes);
  active.expander.report_warning(
    <macro>, message, active.expander.token, notes);
}

static void _sdk_check_notes(String operation, List notes) {
  _sdk_guard(operation);
  foreach (Var note, notes)
    if (note is not <string>)
      $report.sdk.notes_string(operation, note);
}

// ancestry and placement

/** Answers `x2c.enclosing`, declared in `lib/meta.x`. */
Code x2c_enclosing(Symbol what) {
  _sdk_guard("x2c.enclosing");
  if (!(what in %<<declarator statement function unit>>))
    _sdk_reject_value(
      "x2c.enclosing names declarator, statement, function, or unit", what);
  return active.expander.enclosing(what);
}

/** Answers `x2c.place`, declared in `lib/meta.x`. */
void x2c_place(List where, Code code) {
  _sdk_guard("x2c.place");
  active.expander.place(where, code);
}

// meta parameter descriptions

/** Returns what a `meta` parameter declared `TypeInfo` receives for the
    captured syntax `value`: `((name N) (kind K) (type T) (fields F)
    (methods M))`.
    `T` is the canonical type of `value` and `N` its name, or "" when it has
    none. `K` is `struct`, `union`, `enum`, `pointer`, `scalar`, or `other`,
    `F` lists the `(name type)` rows of a struct or union's named fields,
    and `M` the names of its direct dotted methods. */
List meta_type_description(Var value) {
  Type type = Code.type(value);
  Type shape = Type.resolve(type);
  String name = "";
  match (type) {
    case %(?(String own)): name = own;
    case %((!or struct union enum) ?(String own)): name = own;
    default:
      if (_symbol_words(type) && !type.is_pointer()) {
        Array words = [];
        foreach (Var word, type) words.push(word.str());
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
  foreach (String member, c.postfix_completions(type, <.>))
    match (c.resolve_postfix_member(type, %($member), <.>, 1))
      case %(method * *): methods.push(member);
  return %((name $name) (kind $kind) (type $type) (fields $fields)
           (methods ${methods.list_free()}));
}

/* Whether the type `type` is spelled by keywords alone, such as `(int)`. */
static int _symbol_words(List type) {
  foreach (Var word, type) if (word is not <symbol>) return 0;
  return type != NULL;
}

/** Returns what a `meta` parameter declared `Source` receives for the
    captured syntax `value`: `((text T) (file F) (syntax value))`, where `T`
    is the text the developer wrote and `F` the file it is in. */
List meta_source_description(Var value) {
  String text = Code.source_text(value);
  List source = active.captures[((ulong) value.u64)];
  return %((text $text) (file ${source.cadr()}) (syntax $value));
}

// built-in algorithm operations

/** Returns `expression` with the iterator chain `foreach` reads completed. */
List builtin_foreach_complete(List expression) {
  _sdk_guard("private foreach iterator completion");
  return active.expander.complete_iter_chain(expression);
}

// rejection

/** Reports `message` and `notes` at the active invocation and never
    returns, so the rejected operation's caller cannot continue with a
    missing answer. With no active invocation it is a bad state. */
void MetaContext.reject(String message, List notes) {
  Compiler c = active.evaluator;
  if (c) c.report_error(<macro>, message, active.site, notes);
  raise %(bad-state (operation "x2c SDK rejection") (reason $message));
}

// SDK operations reject use outside an active expansion.
static void _sdk_guard(String operation) {
  if (!active.expander)
    $report.sdk.expansion_required(operation);
}

static void _sdk_reject_value(String message, Var value) {
  MetaContext.reject(message, $report.sdk.value_notes(value));
}

// lisp primitives

/** Binds the internal primitives the compile-time SDK library wraps into
    `lisp`, under their `_x2c.` names. */
void Compiler.bind_sdk_primitives(Lisp lisp) {
  $lisp.bind(lisp, "_x2c.meta.linked.hashes", _sdk_linked_hashes);
  $lisp.bind(lisp, "_x2c.prelude.linked", _sdk_linked_prelude);
  $lisp.bind(lisp, "_x2c.function.reference", builtin_foreach_reference);
  $lisp.bind(lisp, "_x2c.function.native-type", binding_native_type);
  $lisp.bind(lisp, "_x2c.literal.list", binding_literal_list);
  $lisp.bind(lisp, "_x2c.native-meta.targets", _sdk_meta_targets);
  $lisp.bind(lisp, "_x2c.native-meta.declared", _sdk_meta_declared);
  $lisp.bind(lisp, "_x2c.symbol-set", _sdk_symbol_set);
}
