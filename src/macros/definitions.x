/*  definitions.x -- macro definitions, quotations and holes */

/* macro definitions

   Reading a definition takes its result kind, name, signature holes, and
   body. Its signature is visible before the body is read, so the body can
   invoke the macro it defines. */

/* One definition while it is read. `nested` marks a definition inside a
   template, which stays syntax until the template's expansion binds it.
   `locals` holds the template's own declarations, newest first under
   `<order>`, and `captures` the outer names a local macro's body reads. */
static typedef struct Definition {
  Compiler c, Token start;
  Atom name, Symbol kind;
  List target, parameters, template, fresh, captures, pattern, rebuild, type;
  List origin, String file, Map locals, Array using;
  int anonymous, local, nested, quotation, leaf, storage;
} Definition;

/* macro categories

   Every syntactic category a definition names, as a hole kind, a result
   kind, or a decorator target, with the kinds each spelling selects.
   Spellings match without regard to case. `named` marks the row whose
   spelling names its hole or result kind in diagnostics. */

static typedef struct MacroCategory {
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
  $let(c.macro_holes, {}) {
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

static Symbol _result_kind_token(Compiler c, Token token) {
  const MacroCategory *category = _category(token.text);
  if (!category || !category.result)
    $fail.macros_macro_unknown_kind(c, token, token.text);
  return category.result;
}

static void _naming(Definition &d) {
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

static Symbol _target_kind(Definition &d) {
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
static void _announce(Definition &d) {
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
static void _body(Definition &d) {
  Compiler c = d.c;
  $let(c.shallow, 0)
  $let(c.return_type, NULL)
  $let(c.runtime_literals, c.runtime_literals || d.anonymous)
  $let(c.local_macro_captures, d.local ? {} : NULL)
  $let(c.local_macro_capture_scopes, c.sym.scope_count()) {
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
static List _recorded(Map m) {
  Var order = m != NULL ? m[<order>] : void;
  return order is <list> ? order.list().reverse() : NULL;
}

/* definition templates

   Finishing a definition turns its body into the stored template, derives
   the rows an invocation needs, and makes the `macrodef` visible. */

/* Turns the body into the stored template, then derives the fresh rows
   and pattern an invocation needs. Parsed literal names carry
   definition-only identities, so the template stores binders instead and
   each expansion allocates one fresh identity per literal spelling. */
static void _finish(Definition &d) {
  d.template = _slot_binders(_wrap(d));
  Map bindings = {};
  if (_target_kind(d) == <unit>) _constructed_names(d, bindings);
  Array locals = _local_binders(d, bindings);
  d.template = _replace_bindings(d.template, bindings);
  _check_kinds(d);
  d.fresh = _fresh_rows(d, locals);
  d.pattern = _invocation_pattern(d);
  Map uses = _binder_uses(d.template);
  if (!(void *) uses) return;
  d.rebuild = %(${_rebuild_template(d)} ${_rebuild_keys(d, uses)});
  d.leaf = !d.nested && _uses_holes_once(d, uses);
}

/* A Function decorator's body becomes a function with the target's return
   type and declarator, and an Expression decorator's body a parenthesized
   expression. */
static List _wrap(Definition &d) {
  List replacement = d.template;
  if (d.kind != <decorator>) return replacement;
  Symbol target = _target_kind(d);
  if (target == <expr>) return %(expr (<macro-expr>) (parens $replacement));
  if (target != <function>) return replacement;
  Var return_binder = _hole_key(d.target, "return");
  Var declarator_binder = _hole_key(d.target, "declarator");
  match (replacement)
    case %(seq *body):
      return %(
        seq
          (function $return_binder $declarator_binder (block @body))
      );
  return replacement;
}

/* Each nested `(macro-bind BINDER)` slot becomes its binder. A whole slot
   keeps a List shell: `expr` for an expression, `macro-bind` otherwise. */
static List _slot_binders(List replacement) {
  match (replacement) case %(macro-bind ?): return replacement;
  List bindings;
  Var expression_slot = %(
    expr (<macro-expr>) (macro-bind ?binder)
  );
  if (replacement.try_match(expression_slot, bindings))
    return replacement.search_replace(%(macro-bind ?binder), <?binder>);
  return replacement.search_replace(
    %(!or
      (expr (<macro-expr>) (macro-bind ?binder))
      (macro-bind ?binder)),
    <?binder>
  );
}

/* A Unit target requires construction, which each Name hole's value
   carries. */
static void _constructed_names(Definition &d, Map bindings) {
  Var required = _hole_key(d.target, "construction");
  foreach (List parameter, d.parameters)
    if (parameter.assoc(<kind>) == <name>) {
      Var name = Macro.binder(parameter.assoc(<binder>), "value", 0);
      bindings[name] = %($required $name);
    }
}

/* Binds each template local to its binder and returns the locals that get
   fresh names. A tag the template only references keeps its public
   spelling. */
static Array _local_binders(Definition &d, Map bindings) {
  Array fresh = [];
  foreach (Var identity, _recorded(d.locals)) {
    if (%(provisional $identity) in d.locals) {
      bindings[identity] = d.locals[identity];
      continue;
    }
    bindings[identity] = _local_binder(
      identity, %(tag-local $identity) in d.locals);
    fresh.push(identity);
  }
  return fresh;
}

static void _check_kinds(Definition &d) {
  foreach (List hole, d.parameters)
    if (!hole.assoc(<kind>)) {
      String hole_spelling = hole.assoc(<binder>).str()[1:];
      $fail.macros_hole_untyped(d.c, d.start, hole_spelling);
    }
}

/* Each `using` hole and each template local gets a fresh name per
   expansion; the last field marks the names compile-time Lisp reads. */
static List _fresh_rows(Definition &d, Array locals) {
  Array fresh = [];
  foreach (Var binder, d.using.list_free())
    fresh.push(%($binder ${binder.str()[1:]} 1));
  foreach (Var identity, locals) {
    Var spelling = d.locals[identity];
    Atom binder = _local_binder(
      identity, %(tag-local $identity) in d.locals);
    fresh.push(%($binder $spelling 0));
  }
  return fresh.list_free();
}

/* The number of uses of each binder in a template, or NULL when the
   template can apply templates: it holds a slot, a nested invocation or
   definition, or a Macro value. Such a template has no rebuild row, so a
   definition holds no second copy of another definition. */
static Map _binder_uses(List template) {
  Map uses = {};
  List syntax;
  $ast.walk(template, syntax) {
    match (syntax)
      case %((!or macro-invoke macro-slot meta-call tpl-call macro-value
                  "x2c.template" macrodef syntax-recipe declaration-recipe)
             *):
        return NULL;
    foreach (Var item, syntax)
      if (item.is_binder()) uses[item] = uses.getdefault(item, 0) + 1;
  }
  return uses;
}

/* The template a rebuild fills. An Expr hole's binder stands for its whole
   expression, without the `(expr (<macro-expr>) ...)` shell, and no
   template-origin wrapper remains, because a rebuild opens no invocation. */
static List _rebuild_template(Definition &d) {
  Map expressions = {};
  foreach (List hole, d.parameters)
    if (hole.assoc(<kind>) == <expr>)
      expressions[_hole_key(hole, "expression")] = 1;
  return _rebuild_syntax(d.template, expressions);
}

static Var _rebuild_syntax(Var syntax, Map expressions) {
  if (syntax is not <list> || syntax.is_nil()) return syntax;
  match (syntax) {
    case %(at m-origin ?node): return _rebuild_syntax(node, expressions);
    case %(expr (<macro-expr>) ?binder):
      if (binder in expressions) return binder;
  }
  List child;
  $ast.rewrite_children(
    syntax.list(), child, _rebuild_syntax(child, expressions));
}

/* For each hole, the target's last, the binders of the projections the
   template uses, in capture-row order: source, value, expression, and
   splice, then a Function value's return type and declarator. `?` marks a
   projection the template does not use. */
static List _rebuild_keys(Definition &d, Map uses) {
  List holes = d.target ? d.parameters.append(%(${d.target})) : d.parameters;
  Array keys = [];
  foreach (List hole, holes) {
    Array used = [];
    foreach (String projection,
             %("source" "value" "expression" "splice" "return" "declarator"))
      used.push(_used(uses, hole, projection, <?>));
    keys.push(used.list_free());
  }
  return keys.list_free();
}

/* Whether the template uses each hole, the target's included, at most
   once. A leaf template applies no templates and uses each hole once, so
   its application cannot recurse or multiply the applications its
   arguments hold. A definition inside a template is never a leaf, because
   its template can hold the enclosing template's holes. */
static int _uses_holes_once(Definition &d, Map uses) {
  List holes = d.target ? cons(d.target, d.parameters) : d.parameters;
  foreach (List hole, holes) {
    int count = 0;
    foreach (String projection,
             %("source" "value" "expression" "splice" "member" "return"
               "declarator" "construction"))
      count += uses.getdefault(_hole_key(hole, projection), 0).int();
    if (count > 1) return 0;
  }
  return 1;
}

/* Makes the finished definition visible in place of its signature. */
static List _publish(Definition &d) {
  List node = _definition_node(d);
  $let(d.c.token, d.start) _show(d, node);
  return node;
}

/* A named local macro is visible in its scope, and a global one unless a
   template holds it. */
static void _show(Definition &d, List node) {
  if (d.local && !d.anonymous) d.c.sym.define_macro(d.name, node);
  else if (!d.local && !d.nested) d.c.publish_macro_definition_node(node);
}

static List _definition_node(Definition &d) {
  Compiler c = d.c;
  List definition = %(
    macrodef
    (name ${d.name})
    (kind ${d.kind})
    (target ${_target_kind(d)})
    (targetp ${d.target})
    (parameters ${d.parameters})
    (fresh ${d.fresh})
    (captures ${d.captures})
    (pattern ${d.pattern})
    (template ${d.template})
    (rebuild ${d.rebuild})
    (leaf ${d.leaf})
    (origin ${d.origin})
    (file ${d.file})
    (builtin ${c.builtin_defs})
    (local ${d.local})
    (static ${d.storage})
  );
  return definition;
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

static Token _hole_name_token(Compiler c, Symbol prefix) {
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

static List _record_hole(
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
  foreach (List parameter, parameters)
    rows.push(_hole_record(c, _hole_name(parameter)));
  return rows.list_free();
}

static Atom _hole_name(List hole) {
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

static const MacroCategory *_category(String spelling) {
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
    foreach (Var directive, c.leading_preproc()) items.push(directive);
    if (c.peek(0) == <"}">) break;
    items.push(c.parse_top_level());
  }
  return items.list_free();
}

static int _legacy_expression_body(Compiler c) {
  if (c.peek(0) != <(>) return 0;
  Token after = c.token.after_group();
  return after.type != <;> && !_extends_expression(after);
}

/* A leading parenthesized group is the complete legacy expression body when
   the following token cannot extend that expression. A semicolon always
   selects the canonical form. */
static int _extends_expression(Token token) {
  Symbol type = token.type;
  return type.binary_precedence() || type.is_assignment_op() ||
         type in operand_continuations ||
         (type == <ident> && (token.text == "is" || token.text == "in"));
}

/* After a complete operand, a postfix operator, a brace initializer, the
   conditional, or a comma continues the expression. */
static const SymbolSet operand_continuations =
  %<<"[" "(" "{" "->" "." "++" "--" "?" ",">>;

/* template holes

   A named hole, Lisp slot, or computed call fills a syntax role. `$` inserts
   one value and `@` splices a sequence. The first role an untyped hole fills
   gives it its kind. */

/** Parses a macro hole or Lisp slot for `role` while reading a template.
    Returns role-shaped syntax containing `(macro-bind ...)` or
    `(macro-slot ...)`, or NULL when ordinary grammar owns the current tokens;
    successful parsing advances the cursor.
*/
List Compiler.try_parse_macro_slot(Compiler c, Symbol role) {
  if (!c.macro_holes) return NULL;
  if (c.peek(0) == <@> && !c.peek_macro_hole())
    return _meta_call_slot(c, role);
  String name;
  if (role != <expression> && role != <statement> &&
      c.peek(0) == <$> && _scan_name(c, name).type == <(> &&
      !c.peek_macro_hole() && !_peek_invocation(c))
    return _meta_call_slot(c, role);
  if (c.peek(0) == <"$("> || c.peek(0) == <"@(">)
    return _lisp_slot(c, role);
  return _hole_slot(c, role);
}

/* The callable supplies syntax in the requested insertion position. */
static List _meta_call_slot(Compiler c, Symbol role) {
  int sequence = c.peek(0) == <@>;
  if (sequence && !(role in sequence_roles))
    $fail.macros_splice_position(c, c.token);
  if (!sequence && (role == <block> || role in declaration_roles))
    return NULL;
  List definition = _peek_invocation(c);
  if (sequence && definition && _result_kind(definition) != <expression>)
    return _target_at(c, _slot_position(role), 1);
  List call = c.try_parse_macro_expression();
  return %(macro-slot $sequence $call);
}

/* A result macro keeps the ordinary position's kind and decorator rules. */
static Symbol _slot_position(Symbol role) =>
  role in %<<unit block field enumerator map-entry>> ? role : <expression>;

/* A Lisp slot fills a declaration slot only when @ splices it. A block
   item that continues into a declaration, and a statement, keep the
   ordinary grammar. */
static List _lisp_slot(Compiler c, Symbol role) {
  int splice = c.peek(0) == <"@(">;
  if (splice && !(role in sequence_roles))
    $fail.macros_splice_position(c, c.token);
  if (role in declaration_roles && !splice) return NULL;
  if (!splice && role == <block> && c.macro_lisp_starts_declaration())
    return NULL;
  if (role == <statement>) return NULL;
  if (role == <expression>) return c.parse_macro_lisp_expression();
  return _parse_lisp_slot(c, role);
}

/* A hole fills a slot whose role its kind accepts. A sequence hole of no
   kind takes the slot's kind. */
static List _hole_slot(Compiler c, Symbol role) {
  List hole = c.peek_macro_hole();
  if (!hole ||
      (role == <argument> && !hole.assoc(<sequence>).int()) ||
      (role == <statement> && c.after_hole().type == <(>)) return NULL;
  if (role == <expression> && hole.assoc(<sequence>).int())
    $fail.macros_splice_expr(c, c.token);
  if (!(role in untyped_roles)) {
    Symbol kind = hole.assoc(<kind>);
    if (!kind && c.peek(0) != <@> && c.peek(0) != <"@{"> &&
        !_quoted_role(c, role))
      return NULL;
    if (kind && !_kind_accepts_role(kind, role)) return NULL;
  }
  List syntax = _parse_hole(c, role);
  return syntax && role == <expression>
       ? %(expr (<macro-expr>) $syntax) : syntax;
}

static const SymbolSet declaration_roles =
  %<<field enumerator map-entry unit>>;

static const SymbolSet sequence_roles =
  %<<argument block field enumerator map-entry param unit catch match-row
     decl-row>>;

static const SymbolSet untyped_roles = %<<expression argument type>>;

static const SymbolSet quoted_roles = %<<statement block name param>>;

/** Returns the registered hole descriptor for a named or expression hole.
    `$NAME` and `${expression}` insert one value; `@NAME` and `@{expression}`
    splice a sequence. Returns NULL without consuming a non-hole spelling.
*/
List Compiler.peek_macro_hole(Compiler c) {
  Symbol prefix = c.peek(0);
  if (prefix == <"@{">) return _expression_hole(c, c.token);
  if (prefix != <$> && prefix != <@>) return NULL;
  if (c.peek(1) == <"{">) return _expression_hole(c, c.token);
  if (c.peek(1) != <ident>) return NULL;
  Token name = Token.skip_trivia(c.token + 1);
  List hole = _hole_record(c, Atom.intern(name.text));
  return hole ? hole : _quoted_hole(c, name.text, c.token);
}

/** Returns the token after the named or expression hole at the cursor.
    Consumes neither its `$` or `@` prefix nor its optional braces.
*/
Token Compiler.after_hole(Compiler c) {
  if (c.peek(0) == <"@{">) return c.token.after_group();
  Token next = Token.skip_trivia(c.token + 1);
  return next.type == <"{"> ? next.after_group()
                           : Token.skip_trivia(next + 1);
}

/* quotations

   `$!( expression )`, `$!{ items }`, and `$!Kind{ ... }` are anonymous
   macros applied where they are written. A `$name` in the body names the
   visible local `name`: its first use declares a hole, and the quotation
   applies to that local's value. An `@name` splices the local's sequence.
   `${expression}` and `@{expression}` declare hidden locals before building
   the code, for singular and sequence insertion. A typed
   quotation, `$!T{ expression }` or `$!(T){ expression }`, builds its code
   where it is written (see "typed quotations"), and so do
   `$!Type{ type-name }` and `$!Param{ parameter }`. */

/** Parses a quotation at `$!` into the code it builds from the locals its
    body names. */
List Compiler.parse_macro_quotation(Compiler c) {
  Token start = c.token;
  c.expect(<$>);
  c.expect(<!>);
  int typed = _typed_quotation(c);
  Symbol kind = typed || c.peek(0) == <(> ? <expression> : <block-item>;
  if (!typed && c.peek(0) == <ident>) {
    kind = _quotation_kind(c, c.token);
    c.next();
  }
  c.sym.push_new_scope();
  defer c.sym.pop_scope();
  Map holes = {};
  List locals = NULL, type = NULL;
  if (typed) {
    if (c.macro_holes && %(quotation) in c.macro_holes)
      $fail.macros_typed_quotation_nested(c, start);
    if (c.macro_holes) $fail.macros_typed_quotation(c, start);
    if (c.peek(0) == <(>) locals = _expression_holes(c, holes);
    type = _quoted_type(c, holes);
  }
  if (!c.macro_holes) locals = locals.append(_expression_holes(c, holes));
  List built = _quotation(c, start, kind, holes, type);
  if (typed && !(%(dynamic) in holes) && c.folded_constant(built) is not void)
    return built;
  return locals
       ? %(expr ("List") (parens (block @locals (stmnt $built))))
       : built;
}

/* The kind a quotation builds: one a result kind names, or a type or one
   parameter, which only a hole kind names. */
static Symbol _quotation_kind(Compiler c, Token token) {
  const MacroCategory *category = _category(token.text);
  if (category && (category.hole == <type> || category.hole == <param>))
    return category.hole;
  return _result_kind_token(c, token);
}

/* Whether the quotation after `$!` states its type: `T{` where the
   identifier `T` names no kind, or a group that a brace follows. A type
   keyword such as `int` is an identifier here. */
static int _typed_quotation(Compiler c) {
  if (c.token.text.is_identifier())
    return c.peek(1) == <"{"> && !_category(c.token.text);
  return c.peek(0) == <(> && c.token.after_group().type == <"{">;
}

/* Declares a hidden local for each `${expression}` or `@{expression}` in
   the body, in source order, and records its name under the sigil's position.
   A nested quotation's holes are its own, and `case ${$name(...)}` is
   a macro pattern. */
static List _expression_holes(Compiler c, Map holes) {
  Token saved = c.token, close = c.token.group_close();
  Array locals = [];
  Symbol last = 0;
  for (Token t = Token.skip_trivia(saved + 1); t < close;
       t = Token.skip_trivia(t + 1)) {
    Token brace = t + 1, next = Token.skip_trivia(brace);
    if (t.type == <$> && next.type == <!>) {
      next = Token.skip_trivia(next + 1);
      if (next.text.is_identifier()) next = Token.skip_trivia(next + 1);
      t = next.group_close();
      Token typed = next.after_group();
      if (next.type == <(> && typed.type == <"{">) t = typed.group_close();
    }
    else if ((t.type == <@> || t.type == <$>) && brace.type == <"{"> &&
             (last != <case> || Token.skip_trivia(brace + 1).type != <$>)) {
      c.token = brace;
      locals.push(_hole_local(c, holes, t.pos));
      t = brace.group_close();
    }
    last = t.type;
  }
  c.token = saved;
  return locals.list_free();
}

/* The declaration of the hidden local that `{expression}` at the cursor
   initializes. The local takes the expression's type, and the quotation
   boxes its value, so an expression without an x2c type reports where it
   is written. */
static List _hole_local(Compiler c, Map holes, int position) {
  c.expect(<"{">);
  Token origin = c.token;
  List value = c.parse_expression();
  if (!value.cadr()) $fail.expressions_var_unresolved(c, origin);
  c.expect(<"}">);
  String name = c.fresh_name("hole");
  holes[%(expression $position)] = name;
  Var constant = c.folded_constant(value);
  if (constant is void) holes[%(dynamic)] = 1;
  else holes[%(constant $name)] = constant;
  return c.bind_syntax(
    %(declare ${value.cadr()}
      (bindings (op = (bind ${c.sym.introduce(name)} ()) $value))),
    <block>, c.return_type);
}

/* Returns NULL if the quotation registered no expression at this offset. */
static List _expression_hole(Compiler c, Token prefix) {
  Var name;
  if (!c.macro_holes ||
      !c.macro_holes.try_get(%(expression ${prefix.pos}), name))
    return NULL;
  List hole = _hole_record(c, Atom.intern(name));
  return hole ? hole : _quoted_hole(c, name, prefix);
}

/* The expression that computes a typed quotation's type: the identifier at
   the cursor, or the group there, which holds a type or a `$name` local or
   `${expression}` hole whose value is the type. */
static List _quoted_type(Compiler c, Map holes) {
  if (c.peek(0) != <(>) return _quoted_type_name(c);
  c.expect(<(>);
  Token origin = c.token;
  List type = NULL;
  if (c.peek(0) == <$>) {
    Var name = c.peek(1) == <"{">
             ? holes[%(expression ${c.token.pos})]
             : Token.skip_trivia(c.token + 1).text;
    c.token = c.after_hole();
    type = _checked_type(
      c,
      c.resolve_expression(%(expr () (ident ${name.str()})), origin), origin);
  }
  else type = _quoted_type_name(c);
  c.expect(<)>);
  return type;
}

/* The `Type` expression `type`, which a `meta` function checks names its
   type with a String before a typed quotation inserts it:
   `type_name_error(type) ? (x2c_diagnostic_fail(...), type) : type`. */
static List _checked_type(Compiler c, List type, Token origin) {
  if (!c.meta_body) return type;
  List error = _runtime_call(c, "type_name_error", %($type), origin);
  List fail = _runtime_call(
    c, "x2c_diagnostic_fail", %($error (expr ("List") (nil))), origin);
  return c.resolve_expression(
    %(expr () (op ? $error
      (expr ("Type") ${source_commas_content(%($fail $type))}) $type)),
    origin);
}

static List _quoted_type_name(Compiler c) {
  Type parsed = NULL;
  c.parse_type_operand(&parsed);
  return c.cache_literal_list(parsed);
}

static List _quotation(
  Compiler c, Token start, Symbol kind, Map holes, List type) {
  Definition d = {
    .c = c, .start = start, .kind = kind, .anonymous = 1, .local = 1,
    .quotation = 1, .type = type};
  _naming(d);
  d.nested = !!c.macro_holes;
  Map enclosing = c.macro_holes;
  $let(c.macro_holes, holes) {
    d.locals = {};
    c.macro_holes[%(locals)] = d.locals;
    if (enclosing != NULL) c.macro_holes[%(enclosing)] = enclosing;
    c.macro_holes[%(quotation)] = 1;
    d.using = [];
    _announce(d);
    _body(d);
  }
  _finish(d);
  List built = _construction(d, holes);
  if (built) return built;
  /* Each local supplies one hole, a sequence included, so the quotation
     builds its pending invocation with the values already grouped. */
  List values = %(expr ("List") (nil));
  foreach (List hole, d.parameters.reverse())
    values = _quoted_cons(
      c, %(expr () (ident ${_hole_name(hole).str()})), values, start);
  List definition = c.capture_macro_value(_publish(d));
  List empty = %(expr ("List") (nil));
  return _quoted_cons(
    c, $!String{ ${"x2c.template"} }, _quoted_cons(
      c, definition, _quoted_cons(c, values, empty, start), start), start);
}

/* `head` consed onto the List expression `tail`. */
static List _quoted_cons(
  Compiler c, List head, List tail, Token origin) {
  List value = c.convert_expression(
    c.resolve_expression(head, origin), %("Var"));
  return %(expr ("List") (cons $value $tail));
}

/* A quotation whose template applies no other template builds its syntax
   where it is written (see "quoted syntax"). Any other quotation, or one
   whose template uses a projection only an expansion makes, returns NULL
   and keeps its definition. */
static List _construction(Definition &d, Map holes) {
  Compiler c = d.c;
  if (d.type) return _typed_construction(d, holes);
  if (d.kind == <type> || d.kind == <param>) return _part_construction(d);
  if (!d.rebuild || d.nested || d.kind == <decl-unit> || c.runtime_literals)
    return NULL;
  Map keys = {}, file_locals = {};
  _file_scope_locals(%(${d.template}), file_locals);
  Array fresh = [];
  foreach (List row, d.fresh) {
    Var binder = row.car();
    keys[binder] = 1;
    fresh.push(%($binder ${row.cadr()} ${binder in file_locals ? 1 : 0}));
  }
  foreach (List hole, d.parameters)
    foreach (Symbol projection, %(source value expression splice member))
      keys[_hole_key(hole, projection)] = %($hole $projection);
  /* Cached pattern literals retain their values across producer sessions. */
  List quoted = %(
    "x2c.quoted" ${fresh.list_free()}
    ${c.freeze_declaration_syntax(_macro_value_names(d.template))}
  );
  List cells = _built_cells(c, quoted, keys, d.start);
  return cells ? %(expr ("List") $cells) : NULL;
}

/* The List cells that build `items`: constant syntax from the literal
   cache, and a hole for each projection `keys` maps. NULL for a binder a
   quotation cannot project where it is written. */
static List _built_cells(
  Compiler c, List items, Map keys, Token start) {
  if (!items) return %(nil);
  List tail = _built_cells(c, items.cdr(), keys, start);
  List head = tail ? _built_item(c, items.car(), keys, start) : NULL;
  return head ? c.literal_cell(head, tail) : NULL;
}

/* An Expr hole's expression in an expression position replaces its whole
   shell, which a rebuild leaves out. */
static List _built_item(
  Compiler c, Var item, Map keys, Token start) {
  Var row;
  if (item.is_binder() && keys.try_get(item, row))
    return row is <list> ? _built_hole(c, row, 0, start)
                         : c.cache_literal_var(item);
  if (item.is_binder() && item.str()[1:].startswith("__macro_")) return NULL;
  if (item is not <list> || item.is_nil()) return c.cache_literal_var(item);
  match (item) {
    case %(at m-origin ?node): item = %("x2c.at" $node);
    case %(expr (<macro-expr>) ?binder):
      if (keys.try_get(binder, row) && row is <list>)
        match (row) case %((macro-param ? (kind expr) ?) expression):
          return _built_hole(c, row, 1, start);
  }
  List cells = _built_cells(c, item, keys, start);
  return cells ? %(expr ("List") $cells) : NULL;
}

/* `("x2c.hole" HOLE PROJECTION VALUE)`, where VALUE is the hole's local
   and HOLE keeps only the hole's kind and cardinality. */
static List _built_hole(
  Compiler c, List row, int shell, Token start) {
  (List hole, Symbol projection) = row;
  List local = c.convert_expression(
    c.resolve_expression(
      %(expr () (ident ${_hole_name(hole).str()})), start), %("Var"));
  List cells = c.literal_cell(local, %(nil));
  Symbol selected = shell ? <shell> : projection;
  List shape = %(
    macro-param
    (kind ${hole.assoc(<kind>)})
    (sequence ${hole.assoc(<sequence>)})
  );
  foreach (Var constant, %($selected $shape "x2c.hole"))
    cells = c.literal_cell(c.cache_literal_var(constant), cells);
  return %(expr ("List") $cells);
}

/* typed quotations

   `$!T{ expression }`, where `T` names no kind, and
   `$!(T){ expression }` build `(expr T CONTENT)` where they are written,
   from the template a rebuild fills: constant syntax from the literal
   cache, and each hole's value inserted as a rebuild inserts it. A typed
   quotation binds nothing, so it may declare no name and apply no
   template. */

static List _typed_construction(Definition &d, Map holes) {
  Compiler c = d.c;
  Map keys = _written_keys(d);
  match (d.rebuild.car()) case %(expr ? *content):
    return c.literal_cell(
      c.cache_literal_var(<expr>),
      c.literal_cell(d.type, _typed_cells(c, content, keys, d.start)));
  /* The rebuild template of an expression that is one hole is empty; the
     definition's template names the hole, which `Macro.typed` inserts. */
  List hole = keys[d.template.last()].list().car();
  // Constant interpolation uses the same constructor without a runtime local.
  Var type = c.folded_constant(d.type), constant;
  if (type is <list> &&
      holes.try_get(%(constant ${_hole_name(hole).str()}), constant))
    return c.cache_literal_list(Macro.typed(type, constant));
  List callee = c.resolve_expression(
    %(expr () (ident "Macro_typed")), d.start);
  List value = _hole_value(c, hole, d.start);
  return c.resolve_expression(
    %(expr ("List") (call $callee (args ${d.type} $value))), d.start);
}

/* `$!Type{ type-name }` and `$!Param{ parameter }` build their List where
   they are written, as a typed quotation builds its expression. */
static List _part_construction(Definition &d) {
  Map keys = _written_keys(d);
  match (d.rebuild.car()) case %(macro-bind ?binder):
    return _typed_hole(d.c, keys[binder], d.start);
  return %(expr ("List") ${_typed_cells(d.c, d.rebuild.car(), keys, d.start)});
}

/* The hole projections a quotation built where it is written fills. Such a
   quotation binds nothing, so it may declare no name and apply no
   template. */
static Map _written_keys(Definition &d) {
  if (!d.rebuild || d.fresh) $fail.macros_typed_quotation(d.c, d.start);
  Map keys = {};
  foreach (List hole, d.parameters)
    foreach (Symbol projection, %(source value expression splice member))
      keys[_hole_key(hole, projection)] = %($hole $projection);
  return keys;
}

/* The List cells that build `items`. A sequence or splice hole
   contributes its items to the List that holds it. */
static List _typed_cells(
  Compiler c, List items, Map keys, Token start) {
  if (!items) return %(nil);
  List tail = _typed_cells(c, items.cdr(), keys, start);
  Var item = items.car(), row;
  if (item is <list> && !item.is_nil())
    return c.literal_cell(
      %(expr ("List") ${_typed_cells(c, item, keys, start)}), tail);
  if (!item.is_binder() || !item.str()[1:].startswith("__macro_"))
    return c.literal_cell(c.cache_literal_var(item), tail);
  if (!keys.try_get(item, row)) $fail.macros_typed_quotation(c, start);
  (List hole, Symbol projection) = row.list();
  List value = _typed_hole(c, row, start);
  if (projection == <splice> || hole.assoc(<sequence>).int())
    value = %(splice $value);
  return c.literal_cell(value, tail);
}

/* One use of a hole: its local, which `Macro.inserted` lifts in an
   expression hole, makes an identifier where code takes an expression, and
   makes a spelling in a Name hole's member position. A Name hole that
   declares inserts the name `Macro.declared` makes. An expression sequence
   lifts each item as `Macro.inserted_items` does. A type inserts its
   syntax once it is checked, and other syntax inserts as it is. */
static List _typed_hole(Compiler c, List row, Token start) {
  (List hole, Symbol projection) = row;
  List local = _hole_value(c, hole, start);
  Symbol kind = hole.assoc(<kind>);
  int lifts = kind == <expr>;
  int expression = projection == <expression>;
  if (kind == <type>) return _checked_type(c, local, start);
  if (hole.assoc(<sequence>).int())
    return lifts ? _runtime_call(c, "Macro_inserted_items", %($local), start)
                 : local;
  if (kind == <name> && projection == <value>)
    return _runtime_call(c, "Macro_declared", %($local), start);
  if (!lifts && !expression && kind != <name>) return local;
  return _runtime_call(
    c, "Macro_inserted",
    %($local ${$!int{ $lifts }} ${$!int{ $expression }}), start);
}

static List _runtime_call(
  Compiler c, String name, List arguments, Token start) {
  List callee = c.resolve_expression(%(expr () (ident $name)), start);
  return c.resolve_expression(
    %(expr () (call $callee (args @arguments))), start);
}

static List _hole_value(Compiler c, List hole, Token start) =>
  c.resolve_expression(%(expr () (ident ${_hole_name(hole).str()})), start);

/* A quotation's hole takes its kind from a name position, or from a
   parameter or statement position where it stands alone, which no
   annotation can give it. A hole that a declarator follows is a parameter's
   type, and one that an operator, `;`, or a postfix form follows is an
   expression. */
static int _quoted_role(Compiler c, Symbol role) {
  if (!(%(quotation) in c.macro_holes) || !(role in quoted_roles)) return 0;
  if (role == <name>) return 1;
  Token after = c.after_hole();
  if (role == <param>)
    return after.type == <,> || after.type == <)> || after.type == <"}">;
  return after.type != <;> && !_extends_expression(after);
}

/* A `$name` or `@name` in a quotation's body that names a visible local
   declares a singular or sequence hole. A local declared `Type` fills a type
   hole, which no position can tell from a statement before a name. */
static List _quoted_hole(
  Compiler c, String spelling, Token prefix) {
  if (!c.macro_holes || !(%(quotation) in c.macro_holes)) return NULL;
  Type type = NULL;
  List local = c.sym.lookup(%($spelling), type);
  if (!local || !c.sym.binding_is_local(local)) return NULL;
  Symbol kind = c.sym.is_named_value_type(type, "Type") ? <type> : 0;
  int sequence = prefix.type == <@> || prefix.type == <"@{">;
  List hole = _record_hole(c, spelling, kind, sequence);
  Var quoted = c.macro_holes[%(quoted)];
  c.macro_holes[%(quoted)] =
    cons(hole, quoted is <list> ? quoted.list() : NULL);
  return hole;
}

/* A quotation's holes in the order its body first names them. */
static List _quoted_holes(Compiler c) {
  Var quoted = c.macro_holes[%(quoted)];
  return quoted is <list> ? quoted.list().reverse() : NULL;
}

/* Consumes a hole filling `role` and returns its projection. */
module List _parse_hole(Compiler c, Symbol role) {
  Token token = c.token;
  List hole = c.peek_macro_hole();
  if (!hole) _unbound(c, _hole_name_token(c, token.type).text, token);
  c.token = c.after_hole();
  Atom name = _hole_name(hole);
  int sequence = token.type == <@> ||
                 token.type == <"@{">;
  if (sequence != hole.assoc(<sequence>).int())
    _cardinality_error(c, name.str(), sequence, token);
  if (sequence && !(role in sequence_roles))
    $fail.macros_splice_position(c, c.token);
  Symbol inferred = _role_kind(role), kind = hole.assoc(<kind>);
  if (!kind) {
    hole = hole.search_replace(%(kind ?prior), %(kind $inferred));
    c.macro_holes[name] = hole;
  }
  else if (!_kind_accepts_role(kind, role)) {
    String spelling = name.str();
    $fail.macros_hole_ambiguous(
      c, token, spelling, _kind_spelling(kind), _kind_spelling(inferred));
  }
  String projection = _hole_projection(c, hole, role, sequence);
  return %(macro-bind ${_hole_key(hole, projection)});
}

static void _cardinality_error(
  Compiler c, String spelling, int sequence, Token token) {
  $fail.macros_hole_cardinality(c, token, sequence, spelling);
}

static Symbol _role_kind(Symbol role) {
  if (role == <expression> || role == <argument>) return <expr>;
  return role == <statement> ? <block> : role;
}

/* A decorator's Unit target projects its source; a sequence, a type, or
   a captures list projects its splice; other holes project their
   expression or value. */
static String _hole_projection(
  Compiler c, List hole, Symbol role, int sequence) {
  Var binder = hole.assoc(<binder>);
  if (%(source $binder) in c.macro_holes) return "source";
  if (sequence || role == <type> || role == <captures>) return "splice";
  return role in %(expression argument expr) ? "expression" : "value";
}

static const SymbolSet value_kinds = %<<expr name literal>>;

static int _kind_accepts_role(Symbol kind, Symbol role) {
  Symbol expected = role == <statement> ? <block> : role;
  if (expected == <expression> || expected == <argument>)
    return kind in value_kinds;
  return kind == expected ||
    (expected == <field> && kind == <decl>) ||
    (expected == <block> && kind == <decl>) ||
    (expected == <unit> &&
     (kind == <decl> || kind == <function> || kind == <named-type>));
}

/** Returns whether tokens after a Lisp form or explicit meta call continue
    a declaration. The balanced argument group is inspected without moving
    the compiler cursor; a visible source macro retains its own grammar.
*/
int Compiler.macro_lisp_starts_declaration(Compiler c) {
  Token opening = c.token;
  if (opening.type == <$>) {
    if (_peek_invocation(c)) return 0;
    String name;
    opening = _scan_name(c, name);
    if (opening.type != <(>) return 0;
  }
  Token token = opening.after_group();
  return token.type == <$> || token.type == <ident> ||
         token.type == <*> || token.type == <(>;
}

/** Parses a member name in a template. A singular `Name` hole there
    supplies the spelling it captured, without hygienic renaming.
*/
List Compiler.try_parse_macro_member(Compiler c) {
  List hole = c.peek_macro_hole();
  List slot = c.try_parse_macro_slot(<name>);
  // A quotation's first use of a hole gives the hole its kind.
  if (hole) hole = _hole_record(c, _hole_name(hole));
  if (!slot || !hole || hole.assoc(<kind>) != <name> ||
      hole.assoc(<sequence>).int())
    return slot;
  return %(macro-bind ${_hole_key(hole, "member")});
}

/* A Lisp slot carries its form and the construction binders its Unit holes
   need. A slot inside a Unit decorator also carries the target's. */
static List _parse_lisp_slot(Compiler c, Symbol role) {
  int sequence = c.peek(0) == <"@(">;
  String form = _lisp_form(c);
  Var target = c.macro_holes[%(target)];
  List construction = _lisp_construction(c, form);
  if (target is <list>) {
    Var required = _hole_key(target, "construction");
    if (role == <name>)
      construction = construction.append(%((target $required)));
    else if (role == <unit>) construction = construction.append(%($required));
  }
  return %(
    macro-slot $sequence $form
    @construction
  );
}

/* The construction binder of each Unit hole the form names, once each. */
static List _lisp_construction(Compiler c, String form) {
  Tokenizer tokenizer = Tokenizer.new(form, <macro-lisp>);
  tokenizer.scan();
  Array construction = [];
  Map seen = {};
  Token token = tokenizer.next();
  while (token && token.type != <eof>) {
    if (token.type == <$>) {
      Token name = tokenizer.next();
      if (name && name.type == <ident>)
        _unit_construction(c, name, construction, seen);
      token = name;
    }
    token = tokenizer.next();
  }
  return construction.list_free();
}

static void _unit_construction(
  Compiler c, Token name, Array construction, Map seen) {
  List hole = _hole_record(c, Atom.intern(name.text));
  if (!hole || hole.assoc(<kind>) != <unit>) return;
  Var binder = _hole_key(hole, "construction");
  if (binder in seen) return;
  seen[binder] = 1;
  construction.push(binder);
}

/* template binders

   Each hole projection has a binder whose prefix gives its cardinality, and
   each declaration a template makes has a binder numbered in the order the
   template declares it. */

module Atom _hole_key(List hole, String projection) =>
  Macro.binder(hole.assoc(<binder>), projection, hole.assoc(<sequence>));

/* A template binder names one lexical declaration, including its namespace.
   Its ordinal keeps same-spelled declarations distinct within a template. */
static Atom _local_binder(Var identity, int tag) {
  int number = 0;
  (void) Ast.try_binding(identity, number, NULL);
  int ordinal = INT_MAX - number;
  return Atom.intern(%"?__macro_${tag ? "tag" : "local"}_${ordinal}");
}

/* Introduces one declaration in the current lexical scope. */
static List _definition_local(Compiler c, String spelling, int tag) {
  Map locals = c.macro_definition_locals();
  Var order = locals[<order>];
  int identity = INT_MAX - (order is <list> ? order.list().len() : 0);
  List introduced = Ast.binding(identity, spelling);
  c.set_fact(%(known $identity), spelling);
  locals[<order>] = cons(introduced, order is <list> ? order : NULL);
  locals[introduced] = spelling;
  if (tag) locals[%(tag-local $introduced)] = 1;
  return introduced;
}

/** Returns the current declaration's definition-local identity. An active
    macro-definition locals map is required. */
List Compiler.macro_introduced_name(Compiler c, String spelling) {
  Map locals = c.macro_definition_locals();
  List current = c.sym.current_binding(%($spelling));
  if (current && current in locals) return current;
  return _definition_local(c, spelling, 0);
}

/** Returns a template's local binding for tag `name` of `kind`, or NULL
    when it names a visible public tag. A tag the template defines or
    declares is a template local, apart from ordinary names of the same
    spelling. A tag it only references keeps its public spelling unless the
    template later defines or declares it.
*/
List Compiler.macro_tag_name(
  Compiler c, Symbol kind, String name, int definition) {
  Map locals = c.macro_definition_locals();
  List key = %(tag $name);
  List current = c.sym.current_binding(key);
  if (current && current in locals) {
    if (definition) locals.del(%(provisional $current));
    return current;
  }
  if (!definition) {
    List visible = c.sym.lookup(key, NULL);
    if (visible && visible in locals) return visible;
    /* A name the body passed to a nested macro's Name hole is the body's
       own in every namespace, including the tag that macro declares. */
    Var named = locals[%(name-argument $name)];
    if (named is <list>) return named;
    if (c.sym.get_exact(%($kind $name))) return NULL;
  }
  List local = _definition_local(c, name, 1);
  c.sym.bind_identity(%(tag), local, %($kind $local));
  if (!definition) locals[%(provisional $local)] = 1;
  return local;
}

/* Replaces each binder or binding identity that `bindings` maps. A List
   none of whose children change stays the same List, and only a changed
   List is copied. */
module Var _replace_bindings(Var value, Map bindings) {
  Var replacement;
  if (value is not <list> || value.is_nil())
    return value.is_binder() && bindings.try_get(value, replacement)
      ? replacement : value;
  if (Ast.try_binding(value, NULL, NULL) &&
      bindings.try_get(value, replacement))
    return replacement;
  List original = value;
  Array items = NULL;
  for (List cursor = original; cursor; cursor = cursor.cdr()) {
    Var child = cursor.car(), item = _replace_bindings(child, bindings);
    if (!(void *) items && item !== child) {
      items = [];
      for (List prefix = original; prefix != cursor; prefix = prefix.cdr())
        items.push(prefix.car());
    }
    if ((void *) items) items.push(item);
  }
  return (void *) items ? items.list_free().var() : value;
}

/* invocation patterns

   An invocation's capture rows match the definition's pattern: an `args`
   row per parameter, a decorator's target row, and a Name row for each
   fresh name compile-time Lisp reads. Each row binds only the projections
   the template uses. */

static List _invocation_pattern(Definition &d) {
  Map binders = {};
  _template_binders(d.template, binders);
  Array arguments = [];
  foreach (List parameter, d.parameters)
    arguments.push(_capture_pattern(parameter, binders));
  List invocation = d.kind == <decorator>
    ? %(
      target (args @{arguments.list_free()})
      ${_capture_pattern(d.target, binders)}
    ) : %(args @{arguments.list_free()});
  List captures = _fresh_patterns(d.fresh, binders);
  return captures ? invocation.append(%((fresh @captures))) : invocation;
}

static void _template_binders(Var value, Map binders) {
  if (value.is_binder()) {
    binders[value] = 1;
    return;
  }
  if (value is not <list>) return;
  foreach (Var child, value.list()) _template_binders(child, binders);
}

static List _fresh_patterns(List fresh, Map binders) {
  Array fresh_patterns = [];
  foreach (Var row, fresh) {
    Var (binder, spelling, lisp) = row;
    (void) spelling;
    if (lisp.int())
      fresh_patterns.push(_capture_pattern(_hole(binder, <name>, 0), binders));
  }
  return fresh_patterns.list_free();
}

/* A hole has source, value, expression, and splice projections. A singular
   Function hole also has return and declarator projections, while a Unit hole
   may carry construction requirements. The stored Match pattern binds only
   projections used by the template; the author binder exposes the captured
   value to compile-time Lisp. */
static List _capture_pattern(List hole, Map binders) {
  Var author = hole.assoc(<binder>);
  int sequence = hole.assoc(<sequence>);
  Var one = sequence ? <*>.var() : <?>.var();
  Var source = _used(binders, hole, "source", one);
  Var value = _used(binders, hole, "value", one);
  Var expression = _used(binders, hole, "expression", one);
  Var splice = _used(binders, hole, "splice", <*>);
  if (!sequence && hole.assoc(<kind>) == <function>)
    value = %(
      !and $value
      (function
        ${_used(binders, hole, "return", <?>)}
        ${_used(binders, hole, "declarator", <?>)}
        ?)
    );
  List trailing = NULL;
  if (hole.assoc(<kind>) == <unit>) trailing = _unit_trailing(hole, binders);
  return _capture_layout(
    sequence,
    %(!and (source $author) (source $source)),
    sequence ? %(!and (value $value) (value $expression) (value $splice))
             : %(value $value),
    %(expression $expression), %(splice $splice), trailing);
}

/* The binder of a projection the template uses, or `otherwise`. */
static Var _used(Map binders, List hole, String projection, Var otherwise) {
  Var binder = _hole_key(hole, projection);
  return binder in binders ? binder : otherwise;
}

/* A Unit hole's row carries its construction binder when the template
   reads the hole or its construction. */
static List _unit_trailing(List hole, Map binders) {
  Var author = hole.assoc(<binder>);
  Var construction = _hole_key(hole, "construction");
  int used = author in binders || construction in binders;
  foreach (String role, %("source" "value" "splice"))
    used |= _hole_key(hole, role) in binders;
  return used ? %($construction) : NULL;
}

/* A scalar capture has source, value, expression, and splice fields; a
   sequence capture has source and value. Any Unit construction requirements
   follow. Patterns and rows share this layout. */
module List _capture_layout(
  int sequence, List source, List value, List expression, List splice,
  List trailing) =>
  sequence ? %(capture $source $value @trailing)
           : %(capture $source $value $expression $splice @trailing);
