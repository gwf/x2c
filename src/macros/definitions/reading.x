/*  reading.x -- macro definition reading */

/* macro categories

   Every syntactic category a definition names, as a hole kind, a result
   kind, or a decorator target, with the kinds each spelling selects.
   Spellings match without regard to case. `named` marks the row whose
   spelling names its hole or result kind in diagnostics. */

module typedef struct MacroCategory {
  const char *spelling;
  Symbol hole, result;
  int target, Symbol named;
} MacroCategory;

/** Parses the macro definition at the current token into a `macrodef` `List`.
    A source-level definition is published immediately; a definition inside a
    template remains syntax for later binding at its expansion site.
*/
List Compiler.parse_macro_definition(Compiler c) {
  Definition d = {.c = c, .start = c.token};
  d.storage = c.test(<static>) || c.source_private;
  c.expect(<ident>);
  _head(d);
  _naming(d);
  d.nested = !!c.macro_holes;
  Map enclosing = c.macro_holes;
  // A rejected signature must not leave later declarations as templates.
  with (c.macro_holes = {}) {
    d.locals = {};
    c.macro_holes[%(locals)] = d.locals;
    if (enclosing != NULL) c.macro_holes[%(enclosing)] = enclosing;
    d.using = [];
    _signature(d);
    _arrow(d);
    _announce(d);
    _body(d);
  }
  _finish(d);
  return _publish(d);
}

/* Reads the result kind. A local definition names itself without `$`, and
   an anonymous one has no name to read. */
static void _head(Definition &d) {
  Compiler c = d.c;
  if (c.peek(0) == <$>)
    $fail.macros_macro_result(c, c.token);
  d.anonymous = c.peek(0) == <ident> && c.peek(1) == <(>;
  d.local = d.anonymous || (c.peek(0) == <ident> &&
            c.peek(1) == <ident> && c.peek(2) == <(>);
  if (c.peek(0) != <ident> || (!d.local && c.peek(1) != <$>))
    $fail.macros_macro_kind(c, c.token);
  Token token = c.token;
  c.next();
  d.kind = _result_kind_token(c, token);
}

module Symbol _result_kind_token(Compiler c, Token token) {
  const MacroCategory *category = _category(token.text);
  if (!category || !category.result)
    $fail.macros_macro_unknown_kind(c, token, token.text);
  return category.result;
}

module void _naming(Definition &d) {
  Compiler c = d.c;
  if (d.anonymous) d.name = Atom.intern(c.fresh_name("anonymous_macro"));
  else if (d.local) {
    d.name = Atom.intern(c.token.text);
    c.next();
  }
  else d.name = _name(c);
  String spelling = d.name.str();
  if (d.local && d.name == <with>)
    $fail.macros_name_with(c, d.start);
  if (spelling.startswith("x2c.") && !c.builtin_defs &&
      !Compiler.is_prelude_source(c.source_path(c.filename)))
    $fail.macros_macro_reserved(c, d.start, spelling);
}

/* Reads the parameter holes, then a `using` clause. A decorator's first
   parameter is its target. */
static void _signature(Definition &d) {
  Compiler c = d.c;
  Array params = [];
  c.expect(<(>);
  if (!c.test(<)>)) {
    do _parameter(d, params, _signature_hole(c)); while (c.test(<,>));
    c.expect(<)>);
  }
  d.parameters = params.list_free();
  _check_signature(d);
  if (c.take_word("using")) _using_clause(c, d.using);
  if (c.peek(0) == <:>)
    $fail.macros_macro_kind_order(c, c.token);
}

static void _parameter(Definition &d, Array params, List hole) {
  Compiler c = d.c;
  if (d.kind == <decorator> && !d.target) _take_target(d, hole);
  else params.push(hole);
  if (hole.assoc(<sequence>).int() && c.peek(0) == <,>)
    $fail.macros_hole_final(c, c.token);
}

/* A Unit target's source stays visible to compile-time Lisp, whose
   template slots find the target hole under `(target)`. */
static void _take_target(Definition &d, List hole) {
  Compiler c = d.c;
  if (!_decorator_target(hole.assoc(<kind>)))
    $fail.macros_decorator_kind(c, d.start);
  if (hole.assoc(<sequence>).int())
    $fail.macros_decorator_singular(c, d.start);
  d.target = hole;
  if (hole.assoc(<kind>) != <unit>) return;
  c.macro_holes[%(source ${hole.assoc(<binder>)})] = 1;
  c.macro_holes[%(target)] = hole;
}

/* A local macro produces no file-scope syntax, directly or through the
   target it decorates. */
static void _check_signature(Definition &d) {
  Compiler c = d.c;
  if (d.kind == <decorator> && !d.target)
    $fail.macros_decorator_target_kind(c, d.start);
  if (!d.local) return;
  if (d.kind == <unit> || d.kind == <decl-unit>) {
    String result_spelling = _kind_spelling(d.kind);
    $fail.macros_local_result(c, d.start, result_spelling);
  }
  if (d.kind != <decorator>) return;
  Symbol kind = _target_kind(d);
  if (kind == <function> || kind == <unit> || kind == <named-type>) {
    String target = _kind_spelling(kind);
    $fail.macros_local_target(c, d.start, target);
  }
}

/* An Expression result, or a decorator of an expression, has an `=>`
   body. A Stmt result has a braced body or an `=>` expression statement.
   Every other result has a braced body after an optional `=>`. */
static void _arrow(Definition &d) {
  Compiler c = d.c;
  if (_has_expression_body(d)) {
    if (c.peek(0) == <"{">) _body_error(d);
    c.expect(<=>);
    c.expect(<">">);
    return;
  }
  if (c.peek(0) == <=>) {
    c.expect(<=>);
    c.expect(<">">);
    if (d.kind == <block-item>) return;
  }
  if (c.peek(0) == <(>)
    $fail.macros_macro_paren_body(c, c.token);
  if (c.peek(0) != <"{">) _body_error(d);
}

static int _has_expression_body(Definition &d) =>
  d.kind == <expression> ||
  (d.kind == <decorator> && _target_kind(d) == <expr>);

module Symbol _target_kind(Definition &d) {
  if (!d.target) return 0;
  return d.target.assoc(<kind>);
}

/* Reports the body forms the result kind accepts. */
static void _body_error(Definition &d) {
  String form = _has_expression_body(d) ? "'=> expression;'"
              : d.kind == <block-item> ? "'{ ... }' or '=> expression;'"
              : "'{ ... }'";
  $fail.macros_macro_body(d.c, d.c.token, _kind_spelling(d.kind), form);
}

/* Records where the definition stands and shows its signature, so an
   invocation inside the body names this macro. */
module void _announce(Definition &d) {
  Compiler c = d.c;
  (void) c.record_origin(d.start);
  d.origin = c.token_location(d.start);
  d.file = Compiler.portable_path(c.source_path(c.filename));
  _show(d, _definition_node(d));
}

/* Reads the body in its own scope, with the kinds it infers for the holes.
   A local macro records the outer names its body captures. A `return` in
   the body is typed where the expansion lands, as at file scope; a
   retained rebuild keeps the type a `return` records. Collection reads the
   whole template, initializers included, as the full parse does. */
module void _body(Definition &d) {
  Compiler c = d.c;
  with (c.shallow = 0,
        c.return_type = NULL,
        c.runtime_literals = c.runtime_literals || d.anonymous,
        c.local_macro_captures = d.local ? {} : NULL,
        c.local_macro_capture_scopes = c.sym.scope_count()) {
    c.sym.push_new_scope();
    defer c.sym.pop_scope();
    d.template = _read_body(d);
    if (d.quotation) d.parameters = _quoted_holes(c);
    d.parameters = _parameter_rows(c, d.parameters);
    d.captures = _recorded(c.local_macro_captures);
  }
}

/* A Stmt result's body after `=>` is one arrow statement. */
static List _read_body(Definition &d) {
  Compiler c = d.c;
  if (d.kind == <type> || d.kind == <param>) return _part_body(d);
  if (_has_expression_body(d)) return _expression_body(d);
  if (c.peek(0) == <"{">) return _parse_body(c, _body_kind(d), d.using);
  return _arrow_statement(c, d.anonymous);
}

/* A Stmt arrow's statement is a Stmt macro or decorator invocation, or else
   an expression statement. An anonymous macro's statement omits its `;`,
   which ends the enclosing declaration, and so does a decorator's target
   there. */
module List _arrow_statement(Compiler c, int open) {
  List macro = _target_at(c, <statement>, open);
  if (macro) return macro;
  List expression = c.parse_expression();
  if (!open) c.expect(<;>);
  return %(seq (stmnt $expression));
}

/* The legacy form is parenthesized, and a quotation's body is a
   parenthesized or braced group. The canonical form ends at `;`, which an
   anonymous macro omits. */
static List _expression_body(Definition &d) {
  Compiler c = d.c;
  if (d.quotation || _legacy_expression_body(c)) {
    int braced = d.quotation && c.peek(0) == <"{">;
    c.expect(braced ? <"{"> : <(>);
    List replacement = c.parse_expression();
    c.expect(braced ? <"}"> : <)>);
    return replacement;
  }
  List replacement = c.parse_expression();
  if (!d.anonymous) c.expect(<;>);
  return replacement;
}

/* A Type quotation's body is a type name, and a Param quotation's body is
   one parameter. */
static List _part_body(Definition &d) {
  Compiler c = d.c;
  c.expect(<"{">);
  List body = NULL;
  if (d.kind == <param>) {
    body = c.try_parse_macro_slot(<param>);
    if (!body) body = c.parse_parameter();
  }
  else c.parse_type_operand(&body);
  c.expect(<"}">);
  return body;
}

/* A decorator's body produces what its target is, and a Function or
   Block target's body is block items. */
static Symbol _body_kind(Definition &d) {
  if (d.kind != <decorator>) return d.kind;
  Symbol target = _target_kind(d);
  return target == <function> || target == <block> ? <block-item> : target;
}

/* The entries a map lists under `<order>`, oldest first, or NULL. */
module List _recorded(Map m) {
  Var order = m != NULL ? m[<order>] : void;
  return order is <list> ? order.list().reverse() : NULL;
}

/* signature holes

   A signature declares each hole's binder, its optional kind, and whether
   it takes a sequence. A `using` hole is a Name that compile-time Lisp
   fills with a fresh identifier. */

/* A parameter: an optional kind, `$NAME` or sequence `@NAME`. */
static List _signature_hole(Compiler c) {
  Symbol kind = 0;
  if (c.peek(0) == <ident> && (c.peek(1) == <$> || c.peek(1) == <@>))
    kind = _hole_kind(c);
  int sequence = c.peek(0) == <@>;
  Token token = _hole_name_token(c, sequence ? <@> : <$>);
  return _declare_hole(c, token, kind, sequence);
}

static Symbol _hole_kind(Compiler c) {
  const MacroCategory *category = _category(c.token.text);
  Symbol kind = category ? category.hole : 0;
  if (!kind) {
    String spelling = c.token.text;
    $fail.macros_hole_unknown_kind(c, c.token, spelling);
  }
  c.next();
  return kind;
}

module Token _hole_name_token(Compiler c, Symbol prefix) {
  c.expect(prefix);
  if (c.peek(0) != <ident>)
    $fail.macros_hole_name(c, c.token);
  Token name = c.token;
  c.next();
  return name;
}

static List _declare_hole(
  Compiler c, Token token, Symbol kind, int sequence) {
  String spelling = token.text;
  if (_hole_record(c, Atom.intern(spelling)))
    $fail.macros_hole_duplicate(c, token, spelling);
  return _record_hole(c, spelling, kind, sequence);
}

module List _record_hole(
  Compiler c, String spelling, Symbol kind, int sequence) {
  List hole = _hole(
    Atom.intern(sequence ? %"*$spelling" : %"?$spelling"),
    kind, sequence);
  c.macro_holes[Atom.intern(spelling)] = hole;
  return hole;
}

static void _using_holes(Compiler c, Array binders) {
  do binders.push(_using_hole(c).assoc(<binder>)); while (c.test(<,>));
}

static List _using_hole(Compiler c) =>
  _declare_hole(c, _hole_name_token(c, <$>), <name>, 0);

module List _hole(Atom binder, Symbol kind, int sequence) => %(
    macro-param
    (binder $binder)
    (kind $kind)
    (sequence $sequence)
  );

module List _hole_record(Compiler c, Atom name) {
  Var stored;
  if (!c.macro_holes.try_get(name, stored)) return NULL;
  return stored;
}

/* The final hole records, with the kinds the body inferred. */
static List _parameter_rows(Compiler c, List parameters) {
  Array rows = [];
  foreach (List parameter in parameters)
    rows.push(_hole_record(c, _hole_name(parameter)));
  return rows.list_free();
}

module Atom _hole_name(List hole) {
  String binder = hole.assoc(<binder>).str();
  return Atom.intern(binder[1:]);
}

static const MacroCategory macro_categories[] = {
  { "Expr",          <expr>,       <expression>, 1, <hole> },
  { "Expression",    <expr>,       <expression>, 1, <result> },
  { "Stmt",          <block>,      <block-item>, 1, <both> },
  { "Field",         <field>,      <field>,      1, <both> },
  { "Entry",         <map-entry>,  <map-entry>,  0, <both> },
  { "Enumerator",    <enumerator>, <enumerator>, 0, <both> },
  { "Unit",          <unit>,       <unit>,       1, <both> },
  { "Declaration",   0,            <decl-unit>,  0, <result> },
  { "Decorator",     0,            <decorator>,  0, <result> },
  { "Function",      <function>,   0,            1, <hole> },
  { "NamedType",     <named-type>, 0,            1, <hole> },
  { "Type",          <type>,       0,            0, <hole> },
  { "Decl",          <decl>,       0,            0, <hole> },
  { "DeclaratorRow", <decl-row>,   0,            0, <hole> },
  { "Name",          <name>,       0,            0, <hole> },
  { "Literal",       <literal>,    0,            0, <hole> },
  { "Param",         <param>,      0,            0, <hole> },
  { "Catch",         <catch>,      0,            0, <hole> },
  { "Captures",      <captures>,   0,            0, <hole> },
  { "MatchRow",      <match-row>,  0,            0, <hole> }
};

static const int MACRO_CATEGORY_COUNT =
  (int) (sizeof(macro_categories) / sizeof(macro_categories[0]));

module const MacroCategory *_category(String spelling) {
  String key = spelling.lower();
  for (int i = 0; i < MACRO_CATEGORY_COUNT; i++)
    if (key == String.new(macro_categories[i].spelling).lower())
      return &macro_categories[i];
  return NULL;
}

static int _decorator_target(Symbol hole) {
  for (int i = 0; i < MACRO_CATEGORY_COUNT; i++)
    if (macro_categories[i].hole == hole) return macro_categories[i].target;
  return 0;
}

module String _kind_spelling(Symbol kind) {
  for (int i = 0; i < MACRO_CATEGORY_COUNT; i++) {
    const MacroCategory *category = &macro_categories[i];
    if ((category.hole == kind && category.named != <result>) ||
        (category.result == kind && category.named != <hole>))
      return category.spelling;
  }
  return kind.str().capitalize();
}

/* definition bodies

   A braced body opens with any `using` lines and reads the items its
   result kind produces as a `seq`. */

static List _parse_body(Compiler c, Symbol result_kind, Array using) {
  c.expect(<"{">);
  _parse_body_using(c, using);
  if (result_kind == <block-item>)
    return cons(<seq>, c.parse_block_items(0).cdr());
  if (result_kind == <field>)
    return _closed_seq(
      c, c.peek(0) == <"}"> ? NULL : c.parse_fields(%(struct ())));
  if (result_kind == <enumerator>)
    return _closed_seq(c, c.parse_enumerators(%(enum ())));
  if (result_kind == <map-entry>) return _closed_seq(c, c.parse_map_entries());
  return _closed_seq(c, _unit_items(c));
}

/* `using $name;` makes a fresh private name for each expansion. `using
   name;` keeps the file-scope declaration `name` has where the macro is
   written, wherever the expansion lands. */
static void _parse_body_using(Compiler c, Array binders) {
  while (c.at_word("using") &&
         (c.peek(1) == <$> || c.peek(1) == <ident>)) {
    c.next();
    _using_clause(c, binders);
    c.expect(<;>);
  }
}

/* One `using` list: fresh names, or file-scope names. An Expression
   macro, which has no braced body, writes it after its signature. */
static void _using_clause(Compiler c, Array binders) {
  if (c.peek(0) == <$>) _using_holes(c, binders);
  else _using_names(c);
}

static void _using_names(Compiler c) {
  do {
    String spelling = c.token.text;
    c.expect(<ident>);
    /* A name no x2c declaration supplies is a native name left to C. */
    List binding = c.sym.reference_global(%($spelling));
    c.macro_holes[%(using ${Ast.binding_spelling(binding)})] = binding;
  } while (c.test(<,>));
}

static List _closed_seq(Compiler c, List rows) {
  c.expect(<"}">);
  return %(seq @rows);
}

/* Directives between the items stay in the body. */
static List _unit_items(Compiler c) {
  Array items = [];
  while (c.peek(0) != <"}">) {
    foreach (List directive in c.leading_preproc()) items.push(directive);
    if (c.peek(0) == <"}">) break;
    items.push(c.parse_top_level());
  }
  return items.list_free();
}

static int _legacy_expression_body(Compiler c) {
  if (c.peek(0) != <(>) return 0;
  Token head = c.token, after = head.after_group();
  c.next();
  int type_name = c.test_declaration();
  c.token = head;
  return !type_name && after.type != <;> && !_extends_expression(after);
}

/* A leading parenthesized group is the complete legacy expression body when
   the following token cannot extend that expression. A semicolon always
   selects the canonical form, and a parenthesized type name starts a cast. */
module int _extends_expression(Token token) {
  Symbol type = token.type;
  return type.binary_precedence() || type.is_assignment_op() ||
         type in operand_continuations ||
         (type == <ident> && (token.text == "is" || token.text == "in"));
}

/* After a complete operand, a postfix operator, a brace initializer, the
   conditional, or a comma continues the expression. */
static const SymbolSet operand_continuations =
  %<<"[" "(" "{" "->" "." "++" "--" "?" ",">>;
