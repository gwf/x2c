/*  statements.x -- x2c statement parsing

    Parses control flow and block constructs: `if`/`else`, `while`/`for`/`do`,
    `switch`/`match`/`case`/`default`, labels/`goto`, `break`/`continue`,
    `try`/`catch`, `raise`, `defer`, `return`, empty statements, and compound
    blocks. Return checking uses the return type that declaration parsing
    recorded. Catch arms select `Error` records with `%()` match patterns.
  */

#pragma once
$(import "../lib/private-keywords.xmacro")
#include "compiler.x"
#pragma private
#include "parse.x"
#include "expressions.x"
#include "literals.x"
#include "macros.x"

static List _keyword_paren_expr(Compiler compiler, Symbol keyword) {
  compiler.expect(keyword);
  compiler.expect(<(>);
  List expr = compiler.parse_expression();
  compiler.expect(<)>);
  return expr;
}

/* How many conditional groups the directive `s` opens, or -1 when it
   closes one. */
static int _group_step(String s) {
  Symbol kind = preproc_conditional_kind(s);
  return kind == <open> ? 1 : kind == <close> ? -1 : 0;
}

/* Adds the directives before the cursor to `items` and returns how many
   conditional groups they open, less those they close. */
static int _take_directives(Compiler c, Array items) {
  int depth = 0;
  foreach (List directive, c.leading_preproc()) {
    items.push(directive);
    depth += _group_step(directive.cadr());
  }
  return depth;
}

/* `<branch>` when the directives `run` begin a later arm of a conditional
   group open before them, `<close>` when they close one, or 0 when the next
   statement is in the same arm. */
static Symbol _arm_end(List run) {
  int level = 0;
  Symbol end = 0;
  foreach (List directive, run) {
    Symbol kind = preproc_conditional_kind(directive.cadr());
    if (kind == <open>) level++;
    else if (kind && level) level -= kind == <close>;
    else if (kind) end = kind;
  }
  return end;
}

/** Parses the statement a control keyword or statement macro governs, or a
    block item at `AST_BLOCK`. Directives written before it stay in front of
    it in a `(group DIRECTIVE... STATEMENT)`, which emits without braces, so
    each directive stays where C read it. A conditional group they open also
    takes the statement of each later arm and the closing directive, so a
    statement macro that wraps its body in braces keeps the whole group
    inside them. A later statement in the same arm follows the governed one,
    as in C.
*/
List Compiler.parse_governed(Compiler c, AstPos position) {
  Array items = [];
  int depth = _take_directives(c, items);
  loop {
    Token start = c.token;
    items.push(position == AST_BLOCK ? c.parse_block_item()
                                     : c.parse_statement());
    /* A directive inside the statement may close the group; those after its
       last token precede the next item. */
    int pending = 0;
    for (Token token = start; depth > 0 && token < c.token; token++)
      if (token.type == <preproc>) pending += _group_step(token.text);
      else if (token.type != <space> && token.type != <comment>) {
        depth += pending;
        pending = 0;
      }
    if (depth <= 0) break;
    Symbol end = _arm_end(c.leading_preproc());
    if (!end) break;
    depth += _take_directives(c, items);
    c.directives_taken = c.token;
    if (depth <= 0 || end == <close> || c.peek(0) == <"}"> ||
        c.peek(0) == <eof>)
      break;
  }
  return items.len() == 1 ? items[0] : %(group @{items.list_free()});
}

/* Directives written before the `else`, `while`, `catch`, or `finally` that
   continues a statement follow that statement. */
static List _continued(Compiler c, List statement) {
  if (c.token == c.directives_taken) return statement;
  List directives = c.leading_preproc();
  return directives ? %(group $statement @directives) : statement;
}

static List _if_statement(Compiler compiler) {
  List cond = _keyword_paren_expr(compiler, <if>);
  List ontrue = compiler.parse_governed(AST_STATEMENT);
  if (compiler.peek(0) != <else>) return %(if $cond $ontrue);
  ontrue = _continued(compiler, ontrue);
  compiler.next();
  return %(if $cond $ontrue ${compiler.parse_governed(AST_STATEMENT)});
}

static List _while_statement(Compiler compiler) {
  List cond = _keyword_paren_expr(compiler, <while>);
  List body = compiler.parse_governed(AST_STATEMENT);
  return %(while $cond $body);
}

static List _for_statement(Compiler c) {
  List init, cond, inc, body;
  c.sym.push_new_scope();
  defer c.sym.pop_scope();
  c.expect(<for>);
  c.expect(<(>);
  /* Each clause peeks for its terminator and leaves the token for the
     expect below, so an omitted clause consumes exactly what a present
     one does. */
  if (c.peek(0) == <;>) init = NULL;
  else if (c.test_declaration()) {
    init = c.parse_simple_declaration();
    init = cons(<decl>, init.cdr());
  }
  else init = c.parse_expression();
  c.expect(<;>);
  if (c.peek(0) == <;>) cond = NULL;
  else cond = c.parse_expression();
  c.expect(<;>);
  if (c.peek(0) == <)>) inc = NULL;
  else inc = c.parse_expression();
  c.expect(<)>);
  body = c.parse_governed(AST_STATEMENT);
  return %(for $init $cond $inc $body);
}

static List _do_statement(Compiler compiler) {
  compiler.expect(<do>);
  List body = _continued(compiler, compiler.parse_governed(AST_STATEMENT));
  List cond = _keyword_paren_expr(compiler, <while>);
  return %(do $body $cond);
}

static List _defer_statement(Compiler c) {
  c.expect(<defer>);
  return %(defer ${c.parse_governed(AST_STATEMENT)});
}

/** Builds a return node for an optional expression without consuming tokens.
    A present expression is resolved in the current `Sym` scope and includes
    the current `return_type` for later conversion.
*/
List Compiler.finish_return_statement(Compiler compiler, List expression) {
  if (!expression) return %(return);
  List resolved = compiler.resolve_expression(expression, compiler.token);
  compiler.check_explicit_converter(resolved, compiler.return_type, 0);
  return %(return ${compiler.return_type} $resolved);
}

static List _return_statement(Compiler compiler) {
  compiler.expect(<return>);
  if (compiler.peek(0) == <;>) {
    compiler.next();
    return compiler.finish_return_statement(NULL);
  }
  List expr = compiler.parse_expression();
  compiler.expect(<;>);
  return compiler.finish_return_statement(expr);
}

static List _case_statement(Compiler compiler) {
  compiler.expect(<case>);
  List expr = compiler.parse_expression();
  compiler.expect(<:>);
  return %(case $expr);
}

static List _break_statement(Compiler compiler) {
  compiler.expect(<break>);
  compiler.expect(<;>);
  return %(break);
}

static List _continue_statement(Compiler compiler) {
  compiler.expect(<continue>);
  compiler.expect(<;>);
  return %(continue);
}

static List _goto_statement(Compiler compiler) {
  compiler.expect(<goto>);
  List label = compiler.parse_optional_identifier();
  compiler.expect(<;>);
  return %(goto $label);
}

static List _switch_statement(Compiler compiler) {
  List expr = _keyword_paren_expr(compiler, <switch>);
  List body = compiler.parse_governed(AST_STATEMENT);
  return %(switch $expr $body);
}

static List _default_statement(Compiler compiler) {
  compiler.expect(<default>);
  compiler.expect(<:>);
  return %(default);
}

/* Define the binders a match case or catch filter captures, rejecting the two
   ways a pattern can name one it does not reliably bind. `role` is the keyword
   the diagnostics name. */
static void _define_pattern_binders(
  Compiler compiler, List pattern, Token start, String role) {
  List possible = NULL;
  List definite = compiler.match_pattern_binders(pattern, &possible);
  foreach (Var binder, possible) {
    if (!definite.contains(binder))
      compiler.report_error(
        <type>, %"$role binder is not definitely assigned",
        start, %( "binder:" ${binder.str()}
                  "bind it in every alternative and never under !not")
      );
    String name = binder.str()[1:];
    foreach (Var other, possible) {
      if (other == binder || other.str()[1:] != name) continue;
      compiler.report_error(
        <type>, %"$role binder has conflicting capture kinds",
        start, %( "binder:" $name "use either '?' or '*' consistently"));
    }
  }
  compiler.define_match_binders(pattern);
}

/** Opens a `Sym` scope for one match arm and optionally defines its definite
    pattern binders. The caller must pop the scope after parsing or binding the
    arm body; binder diagnostics use `start`.
*/
void Compiler.begin_match_arm(
  Compiler compiler, List pattern, Token start, int binds) {
  compiler.sym.push_new_scope();
  if (binds) _define_pattern_binders(compiler, pattern, start, "match");
}

/** Opens a `Sym` scope for one catch arm and defines a nonempty filter's
    definite pattern binders. The caller must pop the scope after parsing or
    binding the arm body; binder diagnostics use `start`.
*/
void Compiler.begin_catch_arm(Compiler compiler, List pattern, Token start) {
  compiler.sym.push_new_scope();
  if (pattern) _define_pattern_binders(compiler, pattern, start, "catch");
}

static List _match_capture_declaration(
  Compiler compiler, Type type, String name, List initializer, int temporary) {
  List binding;
  if (compiler.macro_holes) {
    binding = compiler.macro_introduced_name(name);
    initializer = compiler.resolve_expression(initializer, compiler.token);
    compiler.bind_template_local(binding, type, NULL);
  }
  else binding = temporary ? compiler.sym.introduce(name)
                           : %("x2c.ident" $name);
  return compiler.bind_syntax(
    %(declare $type
      (bindings (op = (bind $binding ()) $initializer))),
    AST_BLOCK, compiler.return_type);
}

static List _match_capture_temporaries(Compiler c, List types, Array locals) {
  Array declarations = [];
  foreach (List row, types) match (row)
    case %(?name ?type): {
      String temporary = c.fresh_name("match_value");
      declarations.push(_match_capture_declaration(
        c, %("Var"), temporary, %(expr () (ident ($name))), 1));
      locals.push(%($name $type $temporary));
    }
  return declarations.list_free();
}

static List _match_capture_locals(Compiler c, Array locals) {
  Array declarations = [];
  foreach (List row, locals) match (row)
    case %(?name ?type ?temporary):
      declarations.push(_match_capture_declaration(
        c, type, name, %(expr () (ident ($temporary))), 0));
  return declarations.list_free();
}

static List _match_case(Compiler c) {
  Symbol peek = c.peek(0), List pattern = NULL;
  List types = NULL;
  Token start = c.token;
  c.next();
  if (peek == <case>) {
    {
      Array captures = $auto([]);
      $let(c.in_pattern, 1)
      $let(c.match_types, captures) {
        pattern = c.parse_expression();
        types = captures;
      }
    }
    if (types) pattern = c.typed_match_pattern(pattern, types);
    match (pattern)
      case %(!not (expr ("List") *)):
        c.report_error(
          <parse>, "match case pattern must be a %() list literal",
          start, %( "pattern:" ${pattern.repr()} ));
  }
  else if (peek == <default>)  pattern = %(*);
  else                         goto error;
  c.begin_match_arm(pattern, start, peek == <case>);
  List temporaries = NULL, declarations = NULL;
  if (types) {
    Array locals = [];
    temporaries = _match_capture_temporaries(c, types, locals);
    c.sym.push_new_scope();
    declarations = _match_capture_locals(c, locals);
    locals.free();
  }
  List guard = c.peek(0) == <if> ? _keyword_paren_expr(c, <if>) : NULL;
  c.expect(<:>);
  List body = c.parse_governed(AST_STATEMENT);
  if (guard) body = %(if $guard (block $body (break)));
  if (types) {
    body = %(block @temporaries (block @declarations $body));
    c.sym.pop_scope();
  }
  if (guard) body = %(guarded $body);
  c.sym.pop_scope();
  return %($pattern $body);
error:
  c.report_error(
    <parse>, "expected 'case' or 'default' in match statement",
    c.token, %( "token:" ${c.token.text} ));
}

/* A default arm must be last in each preprocessor configuration. `groups`
   holds, per open conditional group, whether a default preceded the group
   and whether one ended any of its branches; `saw_default` is the state of
   the current branch. */
static int _default_after_directive(Array groups, int saw_default, List d) {
  Symbol kind = preproc_conditional_kind(d.cadr());
  if (kind == <open>) groups.push(%($saw_default $saw_default));
  else if (kind && groups.len()) {
    (int before, int any) = groups.take_last();
    any |= saw_default;
    if (kind == <close>) return any;
    groups.push(%($before $any));
    return before;
  }
  return saw_default;
}

static List _match_cases(Compiler c) {
  Array cases = [], groups = $auto([]);
  Symbol peek = c.peek(0), int saw_default = 0;
  loop {
    // Directives around whole arms stay between them as `preproc` rows.
    if (c.token != c.directives_taken)
      foreach (List directive, c.leading_preproc()) {
        cases.push(directive);
        saw_default = _default_after_directive(groups, saw_default, directive);
      }
    if (peek != <case> && peek != <default>) break;
    if (saw_default)
      c.report_error(
        <parse>, "match default arm must be last",
        c.token, %("move default after every case arm"));
    if (peek == <default>) saw_default = 1;
    List mcase = _match_case(c);
    cases.push(mcase);
    peek = c.peek(0);
  }
  return cases.list_free();
}

static List _match_statement(Compiler compiler) {
  List cases = NULL, expr = _keyword_paren_expr(compiler, <match>);
  if (compiler.test(<"{">)) {
    cases = _match_cases(compiler);
    compiler.expect(<"}">);
  }
  else cases = cons(_match_case(compiler), NULL);
  return %(match ${compiler.resolve_expression(expr, compiler.token)} $cases);
}

static List _empty_statement(Compiler compiler) {
  compiler.expect(<;>);
  return %(empty);
}

static List _filtered_catch_arm(Compiler c, int *is_default) {
  Token start = c.token;
  List pattern = NULL;
  if (c.test(<:>)) *is_default = 1;
  else {
    if (c.peek(0) != <"%(">)
      c.report_error(
        <parse>, "catch filter requires a %() pattern literal",
        c.token, %("use catch %(code (key pattern)...):"));
    pattern = c.parse_catch_pattern_literal();
    c.expect(<:>);
  }
  c.begin_catch_arm(pattern, start);
  List body = c.parse_governed(AST_STATEMENT);
  if (c.peek(0) == <catch> || c.peek(0) == <finally>)
    body = _continued(c, body);
  c.sym.pop_scope();
  return %($pattern $body);
}

static List _filtered_catches(Compiler compiler) {
  Array arms = [], int saw_default = 0;
  loop {
    int is_default = 0;
    List arm = _filtered_catch_arm(compiler, &is_default);
    arms.push(arm);
    if (is_default) saw_default = 1;
    if (!compiler.test(<catch>)) break;
    if (saw_default)
      compiler.report_error(
        <parse>, "catch default arm must be last",
        compiler.token, %("move catch: after every filtered arm"));
  }
  return %(catchcases ${arms.list_free()});
}

static List _try_statement(Compiler c) {
  c.expect(<try>);
  List body = _continued(c, c.parse_governed(AST_STATEMENT)), ctch = NULL;
  if (c.test(<catch>)) ctch = _filtered_catches(c);
  List fnly = c.test(<finally>) ? c.parse_governed(AST_STATEMENT) : NULL;
  if (ctch || fnly) return %(try $body $ctch $fnly);
  c.report_error(
    <parse>, "expected 'catch' or 'finally' after try block",
    c.token, NULL);
}

static List _raise_statement(Compiler compiler) {
  compiler.expect(<raise>);
  if (compiler.peek(0) != <"%(">)
    compiler.report_error(
      <parse>, "raise requires a %() payload literal",
      compiler.token, %("use raise %(code (key value)...);"));
  List result = compiler.parse_raise_literal();
  compiler.expect(<;>);
  return result;
}

static List _optional_label_statement(Compiler compiler) {
  Token head = compiler.token;
  if (compiler.peek(0) == <ident>) {
    List label = compiler.parse_optional_identifier();
    if (compiler.test(<:>)) return %(label $label);
    compiler.token = head;
  }
  return NULL;
}

static List _expression_statement(Compiler compiler) {
  List expr = _optional_label_statement(compiler);
  if (expr) return expr;
  expr = compiler.parse_expression();
  compiler.expect(<;>);
  return %(stmnt $expr);
}

/** Returns the binding of the current identifier when it names a live
    `with` expression, or NULL.
*/
List Compiler.with_binding(Compiler c) {
  Var candidate;
  if (c.peek(0) != <ident> ||
      !c.semantic_binding_facts().try_get(
        %(with-name ${c.token.text}), &candidate))
    return NULL;
  List binding = c.sym.lookup(%(${c.token.text}), NULL);
  return binding.equal(candidate) ? binding : NULL;
}

/** Parses one block-position declaration, statement, or macro insertion.
    The caller owns the surrounding scope; a macro insertion may return a
    `(seq ...)` node containing several block items.
*/
List Compiler.parse_block_item(Compiler c) {
  if (c.test_static_assert()) return c.parse_static_assert();
  List slot = c.try_parse_macro_slot(<block>);
  if (slot) return slot;
  if (c.local_macro_form_is_definition()) {
    List definition = c.parse_macro_definition();
    return c.macro_holes ? definition : %(seq);
  }
  if (c.peek(0) == <ident> && c.token.text == "with")
    return c.parse_statement();
  // An identifier naming a live `with` expression is no macro target.
  int with_expression = !!c.with_binding();
  List macro = with_expression ? NULL : c.try_parse_macro_target_at(AST_BLOCK);
  if (macro) return macro;
  if (c.test_declaration()) {
    List declaration = c.parse_declaration_row();
    c.expect(<;>);
    return c.finish_managed_declaration(declaration);
  }
  return c.parse_statement();
}

/** Parses and binds one statement or statement-position macro at the current
    token. On return, the cursor follows the complete statement and any
    temporary `Sym` scopes opened by the statement have been closed.
*/
List Compiler.parse_statement(Compiler c) {
  List slot = c.try_parse_macro_slot(<statement>);
  if (slot) return slot;
  /* A `with` alias records its source expression, not a temporary. Its `Sym`
     scope and semantic rows exist only while the body parses, so every use
     substitutes the expression and an unused alias does not evaluate it. */
  if (c.peek(0) == <ident> && c.token.text == "with") {
    c.next();
    if ((c.peek(0) == <"{"> && c.peek(1) == <"}">) ||
        c.peek(0) == <;> || c.peek(0) == <eof>)
      c.report_error(<parse>, "with requires an expression", c.token, NULL);
    List expression = c.parse_expression(), String alias = "_";
    if (c.peek(0) == <ident> && c.token.text == "as") {
      c.next();
      if (c.peek(0) != <ident>)
        c.report_error(
          <parse>, "expected an alias identifier after 'as'", c.token, NULL);
      alias = c.token.text;
      c.next();
    }
    if (c.peek(0) != <"{">)
      c.report_error(<parse>, "with requires a braced body", c.token, NULL);
    List type = NULL;
    match (expression)
      case %(expr ?expression_type ?): type = expression_type;
    c.sym.push_new_scope();
    List binding = c.sym.define(%($alias), type);
    c.semantic_binding_facts()[%(with $binding)] = expression;
    Var old_with;
    int had_previous_with = c.semantic_binding_facts().try_get(
      %(with-name $alias), &old_with);
    c.semantic_binding_facts()[%(with-name $alias)] = binding;
    List body = NULL;
    {
      defer {
        c.semantic_binding_facts().del(%(with $binding));
        if (had_previous_with)
          c.semantic_binding_facts()[%(with-name $alias)] =
            old_with;
        else c.semantic_binding_facts().del(%(with-name $alias));
        c.sym.pop_scope();
      }
      c.next();
      body = c.parse_compound_statement();
    }
    return body;
  }
  if (!c.with_binding() && c.macro_starts_target_at(AST_STATEMENT)) {
    List hole = c.peek_macro_hole();
    List macro = c.try_parse_macro_target_at(AST_STATEMENT);
    if (macro) return macro;
    List expression = hole && hole.assoc(<kind>) == <name>
                    ? c.parse_expression() : c.try_parse_macro_expression();
    c.expect(<;>);
    return %(stmnt $expression);
  }
  Symbol token = c.peek(0);
  switch (token) {
    case <if>:          return _if_statement(c);
    case <while>:       return _while_statement(c);
    case <for>:         return _for_statement(c);
    case <do>:          return _do_statement(c);
    case <return>:      return _return_statement(c);
    case <case>:        return _case_statement(c);
    case <break>:       return _break_statement(c);
    case <continue>:    return _continue_statement(c);
    case <goto>:        return _goto_statement(c);
    case <try>:         return _try_statement(c);
    case <raise>:       return _raise_statement(c);
    case <defer>:       return _defer_statement(c);
    case <match>:       return _match_statement(c);
    case <switch>:      return _switch_statement(c);
    case <default>:     return _default_statement(c);
    case <;>:           return _empty_statement(c);
    case <(>:           return c.parse_parenthesized_statement();
    case <"{">: case <"%{">: {
      c.next();
      return c.parse_compound_statement();
    }
  }
  return _expression_statement(c);
}

/** Parses block items after an already-consumed opening brace through `}` and
    returns a `(block ...)` node. The call opens one lexical `Sym` scope;
    `anchor_items` records statement origins and distributes a macro sequence's
    invocation origin over its inserted items.
*/
List Compiler.parse_block_items(Compiler c, int anchor_items) {
  Array block = [], List stmt = NULL;
  c.sym.push_new_scope();
  loop {
    if (c.token != c.directives_taken)
      foreach (Var directive, c.leading_preproc()) block.push(directive);
    if (c.peek(0) == <"}">) break;
    /* Anchor every statement to the token that opens it. Transform-phase
       diagnostics have no useful current token, so this occurrence lets
       them name a line inside the function instead of the end of the file.
       The anchor precedes parsing because parsing leaves the cursor on the
       following token. */
    Token origin = c.token;
    int expansion =
      (c.macro_starts_target_at(AST_BLOCK) &&
       !(c.macro_holes && c.peek_macro_hole())) ||
      (!c.macro_holes && c.local_macro_form_is_definition());
    stmt = c.parse_block_item();
    if (c.macro_holes &&
        (stmt.car() == <macro-bind> || stmt.car() == <macro-slot>)) {
      block.push(stmt);
      continue;
    }
    if (!expansion) {
      block.push(anchor_items ? c.anchor_origin(stmt, origin) : stmt);
      continue;
    }
    foreach (List item, stmt.cdr())
      block.push(
        !anchor_items || item.car() == <at>
          ? item : c.anchor_origin(item, origin)
      );
  }
  c.expect(<"}">);
  c.sym.pop_scope();
  return cons(<block>, block.list_free());
}

/** Parses a compound body after its opening brace and consumes the closing
    `}`, returning an origin-anchored `(block ...)` node.
*/
List Compiler.parse_compound_statement(Compiler c) => c.parse_block_items(1);
