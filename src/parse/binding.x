/*  binding.x -- constructed syntax and statement binding

    Copyright (c) 2025 Gary William Flake.
*/

/* Pushes the items of a `seq`, or any other node itself. */
module void _push_items(Array out, List node) {
  if (node.car() == <seq>)
    foreach (List item in node.cdr()) out.push(item);
  else out.push(node);
}

// constructed syntax

/** Binds parser-shaped `syntax` at `context` into current compiler state.
    `context` is `<unit>`, `<block>`, `<field>`, `<enumerator>`, `<map-entry>`,
    `<statement>`, or `<expression>`.
    The input must evaluate to a nonempty AST `List` valid for the requested
    position. Bindings, types, scopes, and expressions are resolved in source
    order; `return_type` applies only while descendants are bound. This method
    mutates `Sym` and does not open a semantic transaction.
*/
List Compiler.bind_syntax(
  Compiler c, Var syntax, Symbol context, Type return_type) {
  int pending = syntax is <list> && syntax.list().car() == "x2c.template";
  if (_take_staged(c, syntax)) return syntax;
  syntax = c.evaluate_macro_slot(syntax);
  if (_take_staged(c, syntax)) return syntax;
  match (syntax) case %("x2c.quoted" ?(List fresh) ?quoted):
    return c.land_quotation(fresh, quoted, context, return_type);
  if (syntax is not <list>)
    $fail.parse_syntax_expected(c, c.token);
  List input = syntax;
  if (!input) $fail.parse_syntax_expected(c, c.token);
  List enumerator =
    context == <enumerator> ? _bind_enumerator(c, input) : NULL;
  if (enumerator) return enumerator;
  if (context == <map-entry> && input.car() != <seq> &&
      input.car() != Atom.intern("macro-invoke"))
    return c.resolve_map_entry(input, c.token);
  with (c.return_type = return_type) {
    return _bind_form(c, input, context, pending);
  }
}

/* Replaces `syntax` with a staged code value and reports whether that
   value is a retained result, which binds no further. */
static int _take_staged(Compiler c, Var &syntax) {
  Var staged;
  int retained;
  if (!c.macro_application || !c.take_code_value(syntax, staged, retained))
    return 0;
  syntax = staged;
  return retained;
}

/* Publishes a name, a declarator, or an initialized one at an enumerator
   position as an enumerator of the aggregate being bound. Other forms go
   to the dispatcher, so this returns NULL for them. */
static List _bind_enumerator(Compiler c, List input) {
  match (input) {
    case %(!or
           (binding ? (!is ? type string))
           ((!is ? type string))
           ("x2c.ident" (!is ? type string))):
      return _publish_enumerator(c, input, c.aggregate_type, c.token);
    case %(!set ?node
           (bind ? ?)):
      return _publish_enumerator(c, node, c.aggregate_type, c.token);
    case %(!set ?node
           (op =
             (!or
               (binding ? (!is ? type string))
               ((!is ? type string))
               ("x2c.ident" (!is ? type string))
               (bind ? ?))
             ?)):
      return _publish_enumerator(c, node, c.aggregate_type, c.token);
  }
  return NULL;
}

/* Parsed templates and meta functions are the intended producers. There
   is no separate validation pass before or after expansion. The structural
   match below enforces the position: a form that no arm admits there leaves
   the match for `_construction_error`. Existing expression types and
   binding identities are trusted, and strings are never reparsed.

   Binding mutates the current `Sym` in visitation order. Macro invocation
   opens the surrounding `SymTxn`, allowing earlier siblings to be visible to
   later ones while preserving whole-expansion rollback on failure. */
static List _bind_form(
  Compiler c, List input, Symbol context, int pending) {
  Macro caught = $caught;
  int unit = context == <unit>, block = context == <block>;
  int statement = block || context == <statement>;
  match (input) {
    case %(macro-invoke ?def ?args ?site):
      return _bind_invocation(c, def, args, site, context, pending);
    case %(macro-slot ? ? *) if (c.macro_holes): return input;
    case %(code-value ? ? ?):
      return c.bind_code_value(input, context, c.return_type);
    case %(src ? ?syntax):
      return c.bind_syntax(syntax, context, c.return_type);
    case %(api-source ?line ?doc ?syntax) if (unit):
      return _bind_api_source(c, line, doc, syntax);
    case %(named-type ?(String name) ?type) if (unit):
      return _bind_named_type(c, name, type);
    case %(declaration-bundle (rows *rows)) if (unit):
      return _bind_bundle(c, rows);
    case %(syntax-recipe ?callback ?args):
      return _bind_recipe(c, callback, args, context);
    case %(declaration-recipe ?callback ?args) if (unit):
      return _bind_decl_recipe(c, callback, args);
    case %(default-forward ?own ?base ?name *form) if (unit):
      return %(declaration-forward $own $base $name $form $(c.source_private));
    case %(default ?function) if (unit): return _bind_default(c, function);
    case %(declaration-function
             (declare ?type (bindings ?decl)) ?body ?source) if (unit):
      return _bind_collected_function(c, input, type, decl, body, source);
    case %(declaration-initialized ?decl ?source) if (unit):
      return _bind_collected_initializers(c, input, decl, source);
    case %(seq *items): return _bind_items(c, items, context);
    case %(args *args) if (context == <expression>):
      return _bind_args(c, args);
    case %(c-assert ?test ?message) if (unit || block || context == <field>):
      return _bind_assert(c, test, message);
    case %(falias ?decl ?native_syntax) if (unit):
      return _bind_alias(c, decl, native_syntax);
    case %(!set ?expr (expr *)) if (context == <expression>):
      return _resolve(c, expr);
    case %((!or ?tag declare decl typedef)
           ?base (bindings *declarators)):
      return _bind_declaration(c, tag, base, declarators, context);
    case %(dstrdecl ?base (targets *targets) ?source) if (block):
      return _bind_targets(c, base, targets, source);
    case %(dstrdecl (params *parameters) ?source) if (block):
      return _bind_typed_targets(c, parameters, source);
    case %(function ?type
             (bind ?name ((fnmod (params *params)) *mods)) ?body) if (unit):
      return _bind_function(c, type, name, params, mods, body);
    case %(!set ?node ((!or protocol adopt meta-protocol) *)) if (unit):
      return c.publish_protocol_node(node, c.token, NULL);
    case %(!set ?def (macrodef *)): return _bind_macrodef(c, def, context);
    case %(preproc ?(String directive)) if (unit || block):
      return _bind_preproc(c, input);
    case %(at ?origin ?node) if (block): return _bind_item(c, origin, node);
    case %(at ?origin ?node):
      return _anchor(c, origin, c.bind_syntax(node, context, c.return_type));
    case $return_empty() if (statement):
      return c.finish_return_statement(NULL);
    case $return_value(?expr) if (statement):
      return c.finish_return_statement(expr);
    case %((!or break continue default empty)) if (statement): return input;
    case %(case ?expr) if (statement): return %(case $(_resolve(c, expr)));
    case %((!or ?tag goto label) ?name) if (statement):
      return %($tag $name);
    case $expression_statement(?expr) if (statement):
      return _bind_expression_statement(c, expr, context);
    case $deferred(?body) if (statement):
      return %(defer $(_bind_statement(c, body)));
    case $do_loop(?body, ?test) if (statement): return _bind_do(c, body, test);
    case $while_loop(?test, ?body) if (statement):
      return _bind_while(c, test, body);
    case $switched(?expr, ?body) if (statement):
      return _bind_switch(c, expr, body);
    case $if_then(?test, ?ontrue) if (statement):
      return _bind_if(c, test, ontrue);
    case $if_else(?test, ?ontrue, ?onfalse) if (statement):
      return _bind_if_else(c, test, ontrue, onfalse);
    case $for_loop(?init, ?test, ?next, ?body) if (statement):
      return _bind_for(c, init, test, next, body);
    case %(raise ?code (args *details)) if (statement):
      return _bind_raise(c, code, details);
    case %(catchcases ?arms *handler) if (context == <statement>):
      return _bind_catchcases(c, arms, handler);
    case caught(?body, ?cleanup, *arms) if (statement):
      return _bind_try(c, body, input.caddr(), cleanup);
    case $tried(?body, ?cleanup) if (statement):
      return _bind_try(c, body, NULL, cleanup);
    case $matched(?subject, *cases) if (statement):
      return _bind_match(c, subject, cases);
    case $source_block_content(%(*children)) if (statement):
      return _bind_block(c, input);
    case %(group *children) if (statement): return _bind_group(c, children);
  }
  return _construction_error(c);
}

/* Reports a constructed form at a position that does not admit it.
   `report_error` never returns, so a caller may return this call. */
module List _construction_error(Compiler c) {
  $fail.parse_syntax_position(c, c.token);
}

/* A meta call written as a whole statement may return a statement. */
static List _bind_expression_statement(
  Compiler c, List expression, Symbol context) {
  match (expression) case %(expr ? (meta-call *)):
    if (!c.meta_body && !c.macro_holes)
      return c.evaluate_meta_statement(expression, context, c.token);
  return %(stmnt $(_resolve(c, expression)));
}

module List _resolve(Compiler c, List expr) =>
  c.resolve_expression(expr, c.token);

/* A source clause parses, already bound, when the binder reaches it. */
static List _bind_statement(Compiler c, Var stmt) {
  Symbol kind = _source_clause_kind(stmt);
  if (kind) return c.parse_source_clause(kind);
  List bound = c.bind_syntax(stmt, <statement>, c.return_type);
  c.rebound(stmt, bound);
  return bound;
}

static List _bind_clause(Compiler c, Var expr) {
  Symbol kind = _source_clause_kind(expr);
  if (kind) return c.parse_source_clause(kind);
  return _resolve(c, expr);
}

/* A macro invocation expands at the position that holds it. A Macro value
   applied directly stands for one statement or unit item. Inside a
   recovery boundary it owns the transaction that covers the effects its
   producers request; outside one, an error exits and nothing rolls back. */
static List _bind_invocation(
  Compiler c, Var definition, Var arguments, Var invocation, Symbol context,
  int pending) {
  Token site = c.macro_invocation_site(invocation);
  if (invocation != <m-invoke>)
    return c.expand_macro_invocation_node(
      definition, arguments, site, context);
  with (c.macro_application = c.macro_application + 1) {
    SymTxn transaction = { 0 };
    if (c.recovery_depth > 0)
      transaction = c.begin_semantic_transaction();
    defer transaction.rollback();
    List bound = c.expand_macro_invocation_node(
      definition, arguments, site, context);
    transaction.commit();
    if (pending && (context == <block> || context == <statement> ||
                    context == <unit>))
      match (bound) case %(seq ?item): return item;
    return bound;
  }
}

/* An anchor keeps a lone bound item, and a macro's origin marker becomes
   the compiler's current origin. */
static List _anchor(Compiler c, Var origin, List bound) {
  match (bound) case %(seq ?only): bound = only;
  Var anchor = origin == <m-origin> ? c.origin : origin;
  return %(at $anchor $bound);
}

/* An anchored block item is followed by the code placed after it. */
static List _bind_item(Compiler c, Var origin, List node) {
  int anchor = origin == <m-origin> ? c.origin : origin.int();
  c.enter((Ancestor){ .what = <statement>, .origin = anchor });
  List bound =
    _anchor(c, origin, c.bind_syntax(node, <block>, c.return_type));
  List after = c.leave_item();
  return after ? %(seq $bound @after) : bound;
}

// constructed declarations and expressions

/* A statement position admits a sequence of one statement. Elsewhere the
   items bind in order, and a nested sequence contributes its items. */
static List _bind_items(Compiler c, List items, Symbol context) {
  if (context == <statement>) {
    match (items) case %(?only):
      return c.bind_syntax(only, context, c.return_type);
    $fail.parse_statement_single(c, c.token);
  }
  Array bound = [];
  foreach (Var item in items)
    _push_items(bound, c.bind_syntax(item, context, c.return_type));
  return %(seq @(bound.list_free()));
}

static List _bind_args(Compiler c, List arguments) {
  Array bound = [];
  foreach (List argument in arguments) bound.push(_resolve(c, argument));
  return %(args @(bound.list_free()));
}

static List _bind_assert(Compiler c, Var condition, Var message) =>
  %(c-assert $(_resolve(c, condition)) $(_resolve(c, message)));

// constructed statements

/* A source `if`, `while`, `do`, `for`, `match`, or `try` binds here with a
   Token Var into this table for each clause, which the binder parses when it
   reaches it, so its scopes and optional-reference facts govern that parse.
   Syntax from a template or a meta function cannot hold these addresses.
   Each entry's type names its clause. */
static struct Token source_clauses[] = {
  { .type = <test> }, { .type = <then> }, { .type = <else> },
  { .type = <body> }, { .type = <do> },   { .type = <init> },
  { .type = <cond> }, { .type = <next> }, { .type = <arms> },
  { .type = <arm> },  { .type = <try> },  { .type = <catches> },
  { .type = <catch> }, { .type = <finally> }
};

/** The source clause `kind`, which the binder parses when it reaches it. */
Var Compiler.source_clause(Symbol kind) {
  Token clause = source_clauses;
  while (clause.type != kind) clause++;
  return Token.var(clause);
}

// Any value other than a table entry is constructed syntax, kind 0.
static Symbol _source_clause_kind(Var value) {
  if (value is not <token>) return 0;
  Token clause = value;
  Token end =
    source_clauses + sizeof(source_clauses) / sizeof(*source_clauses);
  return clause >= source_clauses && clause < end ? clause.type : 0;
}

/** Binds the source `if`, `while`, `do`, `for`, `match`, or `try` at the
    cursor through the same binders as constructed syntax.
*/
List Compiler.bind_source_statement(Compiler c) {
  Symbol keyword = c.peek(0);
  c.next();
  switch (keyword) {
    case <if>:
      return _bind_if_else(
        c, Compiler.source_clause(<test>), Compiler.source_clause(<then>),
        Compiler.source_clause(<else>));
    case <while>:
      return _bind_while(
        c, Compiler.source_clause(<test>), Compiler.source_clause(<body>));
    case <do>:
      return _bind_do(
        c, Compiler.source_clause(<do>), Compiler.source_clause(<test>));
    case <match>:
      return _bind_match(
        c, Compiler.source_clause(<test>), Compiler.source_clause(<arms>));
    case <try>:
      return _bind_try(
        c, Compiler.source_clause(<try>), Compiler.source_clause(<catches>),
        Compiler.source_clause(<finally>));
  }
  return _bind_for(
    c, Compiler.source_clause(<init>), Compiler.source_clause(<cond>),
    Compiler.source_clause(<next>), Compiler.source_clause(<body>));
}

static List _bind_do(Compiler c, Var body, Var condition) {
  List bound = _bind_statement(c, body);
  return %(do $bound $(_bind_clause(c, condition)));
}

static List _bind_while(Compiler c, Var condition, Var body) {
  List test = _bind_clause(c, condition);
  return %(while $test $(_bind_statement(c, body)));
}

static List _bind_switch(Compiler c, Var expr, Var body) =>
  %(switch $(_resolve(c, expr)) $(_bind_statement(c, body)));

/* Binds the arm where an optional-reference test holds with the reference
   present, and marks it present after the `if` when the other arm cannot
   fall through. */
static List _bind_if(Compiler c, Var condition, Var ontrue) {
  List test = _bind_clause(c, condition);
  int true_is_present = 1;
  List binding = c.optional_reference_test(test, true_is_present);
  List yes = _bind_branch(c, ontrue, binding, true_is_present);
  c.settle_reference(binding, true_is_present, yes, NULL);
  return %(if $test $yes);
}

static List _bind_if_else(
  Compiler c, Var condition, Var ontrue, Var onfalse) {
  List test = _bind_clause(c, condition);
  int true_is_present = 1;
  List binding = c.optional_reference_test(test, true_is_present);
  List yes = _bind_branch(c, ontrue, binding, true_is_present);
  List no = _bind_branch(c, onfalse, binding, !true_is_present);
  c.settle_reference(binding, true_is_present, yes, no);
  // A source `if` without `else` parses no false arm.
  return no ? %(if $test $yes $no) : %(if $test $yes);
}

static List _bind_branch(
  Compiler c, Var arm, List binding, int present) {
  if (!binding) return _bind_statement(c, arm);
  List before = c.present_references();
  if (present) c.mark_reference_present(binding);
  List bound = _bind_statement(c, arm);
  c.restore_reference_presence(before);
  return bound;
}

static List _bind_for(
  Compiler c, Var init, Var condition, Var increment, Var body) {
  c.sym.push_new_scope();
  defer c.sym.pop_scope();
  init = _bind_header(c, init);
  condition = _bind_header(c, condition);
  increment = _bind_header(c, increment);
  return %(for $init $condition $increment $(_bind_statement(c, body)));
}

/* A header clause may be absent. The resolver binds a declaring
   initializer as a block declaration. */
static Var _bind_header(Compiler c, Var clause) {
  Symbol kind = _source_clause_kind(clause);
  if (kind) return c.parse_source_clause(kind);
  return clause is <list> ? _resolve(c, clause) : clause;
}

static List _bind_raise(Compiler c, Var code, List details) {
  Array bound = [];
  foreach (List detail in details) bound.push(_resolve(c, detail));
  return %(raise $(_resolve(c, code)) (args @(bound.list_free())));
}

/* Binds each catch arm's pattern names in a scope of its own. */
static List _bind_catchcases(Compiler c, Var arms, List handler) {
  List handle = handler ? handler.car().list()
    : c.sym.introduce(c.fresh_name("error_handler"));
  /* The lowering declares the handle after its readers bind, so they keep
     its identity rather than reading a template local's source spelling. */
  c.set_fact(%(type $handle), %("ErrorHandler"));
  Array bound = [];
  foreach (Var value in arms.list())
    foreach (List arm in c.evaluate_macro_rows(value)) {
      List pattern = arm.car();
      if (pattern) pattern = _resolve(c, pattern);
      bound.push(c.bind_catch_arm(pattern, arm.cadr(), c.token, handle));
    }
  return %(catchcases $(bound.list_free()) $handle);
}

/** Binds one catch arm's `body` in a scope of its own, with declarations of
    the definite binders of `pattern`, read through `handle`, before it.
    Binder diagnostics use `start`. A source arm's body parses here, and a
    template's declares its binders where its expansion binds it. A parsed
    arm's body already begins with them, so it binds unchanged.
*/
List Compiler.bind_catch_arm(
  Compiler c, List pattern, Var body, Token start, List handle) {
  c.sym.push_new_scope();
  defer c.sym.pop_scope();
  List bindings = NULL;
  if (pattern) {
    _check_binders(c, pattern, start, "catch");
    bindings = c.define_pattern_binders(pattern);
  }
  List statement = _bind_statement(c, body);
  if (_declares_binders(body, bindings))
    return %($pattern $statement);
  return %($pattern (block
    @(c.pattern_binder_declarations(bindings, handle)) $statement));
}

/* Rejects the two ways a match or catch pattern can name a binder it does
   not reliably bind. `role` is the keyword the diagnostics name. */
static void _check_binders(
  Compiler c, List pattern, Token start, String role) {
  List possible = NULL;
  List definite = c.match_pattern_binders(pattern, possible);
  foreach (Atom binder in possible) {
    if (!(binder in definite))
      $fail.parse_binder_unassigned(c, start, role, binder);
    String name = binder.str()[1:];
    foreach (Atom other in possible) {
      if (other == binder || other.str()[1:] != name) continue;
      $fail.parse_binder_conflict(c, start, role, name);
    }
  }
}

/* Whether an arm already carries its ordinary capture declarations: its
   body reads every capture slot, as the declarations do even after a
   rewrite moves a binder into a lambda cell. A nested match or catch reads
   slots of its own. */
static int _declares_binders(List body, List bindings) {
  if (!bindings) return 0;
  Map read = {};
  List node;
  $ast.walk(body, node) match (node) {
    case %(!or (match *) (catchcases *)): continue;
    case %(call "x2c_error_catch_capture" (args ? (expr ? (literal ? ?n)))):
      read[%(catch $n)] = 1;
    case %(?(String slot)): read[slot] = 1;
  }
  int index = 0;
  foreach (List binding in bindings) {
    String n = %"$(index++)";
    String slot = %"_x2c_gensym_match_$(
      binding.car().is_list_binder() ? "list" : "value")_$n";
    if (!(slot in read || %(catch $n) in read)) return 0;
  }
  return 1;
}

// Source clauses parse here, so body, arms, and finalizer go in token order.
static List _bind_try(
  Compiler c, Var body, Var catches, Var cleanup) {
  List bound = _bind_statement(c, body);
  List arms = catches ? _bind_statement(c, catches) : NULL;
  List finalizer = cleanup ? _bind_statement(c, cleanup) : NULL;
  Macro tried = $tried, caught = $caught;
  List statement = arms
    ? caught(bound, finalizer, arms.cadr()) : tried(bound, finalizer);
  List rebuilt = c.rebuild_statement(statement).cadr();
  return arms ? source_retain_catch_handle(rebuilt, arms.caddr()) : rebuilt;
}

/* Binds each `match` arm's captures in a scope of its own. A source
   subject parses before the arms, and source arms parse as they bind. */
static List _bind_match(Compiler c, Var subject, Var cases) {
  Symbol kind = _source_clause_kind(subject);
  if (kind) subject = c.parse_source_clause(kind);
  kind = _source_clause_kind(cases);
  List rows = kind ? c.parse_source_clause(kind) : _bind_rows(c, cases);
  return %(match $(_resolve(c, subject)) $rows);
}

static List _bind_rows(Compiler c, List cases) {
  Array bound = [];
  foreach (Var value in cases)
    foreach (List row in c.evaluate_macro_rows(value)) {
      if (row.car() == <preproc>) {
        bound.push(row);
        continue;
      }
      List pattern = row.car();
      int binds = pattern !== %(*);
      if (binds) pattern = _resolve(c, pattern);
      bound.push(c.bind_match_arm(pattern, row.cadr(), c.token, binds, NULL));
    }
  return bound.list_free();
}

/** Binds one match arm's `body` in a scope of its own, which defines the
    definite binders of `pattern` when the arm `binds`. Binder diagnostics
    use `start`. A source arm's body parses here with the typed captures
    `types` that its pattern recorded.
*/
List Compiler.bind_match_arm(
  Compiler c, List pattern, Var body, Token start, int binds, List types) {
  c.sym.push_new_scope();
  defer c.sym.pop_scope();
  List bindings = NULL;
  if (binds) {
    _check_binders(c, pattern, start, "match");
    bindings = c.define_pattern_binders(pattern);
  }
  List statement = _bind_arm_body(c, body, types);
  if (!bindings || _declares_binders(body, bindings))
    return %($pattern $statement);
  List declarations = c.pattern_binder_declarations(bindings, NULL);
  match (statement)
    case %(guarded ?inner):
      return %($pattern (guarded (block @declarations $inner)));
  return %($pattern (block @declarations $statement));
}

static List _bind_arm_body(Compiler c, Var body, List types) {
  if (_source_clause_kind(body)) return c.parse_case_body(types);
  match (body) case %(guarded ?statements):
    return %(guarded $(_bind_statement(c, statements)));
  return _bind_statement(c, body);
}

/* A constructed block opens its own scope; a callable's outer block binds
   in its parameter scope instead. */
static List _bind_block(Compiler c, List block) {
  c.sym.push_new_scope();
  defer c.sym.pop_scope();
  return c.bind_callable_body(block, c.return_type);
}

static List _bind_group(Compiler c, List children) {
  Array items = [];
  foreach (Var child in children)
    items.push(c.bind_syntax(child, <block>, c.return_type));
  return %(group @(items.list_free()));
}

/** Binds a callable's outer block in its active parameter scope. Ordinary
    constructed blocks open their own scope before using this operation.
*/
List Compiler.bind_callable_body(Compiler c, List syntax, Type return_type) {
  match (syntax) {
    case %(at ?origin ?body):
      return _anchor(c, origin, c.bind_callable_body(body, return_type));
    case $source_block_content(%(*children)): {
      Array stmts = [];
      List present_before = c.present_references();
      defer c.restore_reference_presence(present_before);
      foreach (Var child in children)
        _push_items(stmts, c.bind_syntax(child, <block>, return_type));
      return %(block @(stmts.list_free()));
    }
  }
  return c.bind_syntax(syntax, <block>, return_type);
}
