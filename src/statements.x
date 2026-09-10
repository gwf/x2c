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
  compiler.expect(
    <(>);
  List expr = compiler.parse_expression();
  compiler.expect(<)>);
  return expr;
}

static List _if_statement(Compiler compiler) {
  List cond = _keyword_paren_expr(compiler, <if>);
  List ontrue = compiler.parse_statement();
  if (compiler.test(<else>)) {
    List onfalse = compiler.parse_statement();
    return %(if $cond $ontrue $onfalse);
  }
  return %(if $cond $ontrue);
}

static List _while_statement(Compiler compiler) {
  List cond = _keyword_paren_expr(compiler, <while>);
  List body = compiler.parse_statement();
  return %(while $cond $body);
}

static List _for_statement(Compiler c) {
  List init, cond, inc, body;
  c.sym.push_new_scope();
  defer c.sym.pop_scope();
  c.expect(<for>);
  c.expect(
    <(>);
  /* Each clause peeks for its terminator and leaves the token for the
     expect below, so an omitted clause consumes exactly what a present
     one does. */
  if (c.peek(0) == <;>) init = NULL;
  else if (c.test_declaration()) {
    init = c.parse_simple_declaration();
    init = cons(<decl>, cdr(init));
  }
  else init = c.parse_expression();
  c.expect(<;>);
  if (c.peek(0) == <;>) cond = NULL;
  else cond = c.parse_expression();
  c.expect(<;>);
  if (c.peek(0) == <)>) inc = NULL;
  else inc = c.parse_expression();
  c.expect(<)>);
  body = c.parse_statement();
  return %(for $init $cond $inc $body);
}

static List _do_statement(Compiler compiler) {
  compiler.expect(<do>);
  List body = compiler.parse_statement();
  List cond = _keyword_paren_expr(compiler, <while>);
  return %(do $body $cond);
}

static List _defer_statement(Compiler compiler) {
  compiler.expect(<defer>);
  List body = compiler.parse_statement();
  return %(defer $body);
}

/** Builds a return node for an optional expression without consuming tokens.
    A present expression is resolved in the current `Sym` scope and includes
    the current `return_type` for later conversion.
*/
List Compiler.finish_return_statement(Compiler compiler, List expression) {
  if (!expression) return %(return);
  return %(return ${compiler.return_type}
           ${compiler.resolve_expression(expression, compiler.token)});
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
  List body = compiler.parse_statement();
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
  Array declarations = %[];
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
  Array declarations = %[];
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
    int previous = c.in_pattern;
    Array previous_types = c.match_types;
    Array captures = %[];
    {
      defer {
        c.match_types = previous_types;
        c.in_pattern = previous;
        captures.free();
      }
      c.in_pattern = 1;
      c.match_types = captures;
      pattern = c.parse_expression();
      types = captures.list();
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
    Array locals = %[];
    temporaries = _match_capture_temporaries(c, types, locals);
    c.sym.push_new_scope();
    declarations = _match_capture_locals(c, locals);
    locals.free();
  }
  List guard = c.peek(0) == <if> ? _keyword_paren_expr(c, <if>) : NULL;
  c.expect(<:>);
  List body = c.parse_statement();
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

static List _match_cases(Compiler compiler) {
  Array cases = %[], Symbol peek = compiler.peek(0), int saw_default = 0;
  while (peek == <case> || peek == <default>) {
    if (saw_default)
      compiler.report_error(
        <parse>, "match default arm must be last",
        compiler.token, %("move default after every case arm"));
    if (peek == <default>) saw_default = 1;
    List mcase = _match_case(compiler);
    cases.push(mcase);
    peek = compiler.peek(0);
  }
  List result = cases.list_free();
  return result;
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
  List body = c.parse_statement();
  c.sym.pop_scope();
  return %($pattern $body);
}

static List _filtered_catches(Compiler compiler) {
  Array arms = %[], int saw_default = 0;
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
  List result = arms.list_free();
  return %(catchcases $result);
}

static List _try_statement(Compiler c) {
  c.expect(<try>);
  List body = c.parse_statement(), ctch = NULL;
  if (c.test(<catch>)) ctch = _filtered_catches(c);
  List fnly = c.test(<finally>) ? c.parse_statement() : NULL;
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

/** Parses one block-position declaration, statement, or macro insertion.
    The caller owns the surrounding scope; a macro insertion may return a
    `(seq ...)` node containing several block items.
*/
List Compiler.parse_block_item(Compiler compiler) {
  if (compiler.test_static_assert()) return compiler.parse_static_assert();
  List slot = compiler.try_parse_macro_slot(<block>);
  if (slot) return slot;
  if (compiler.local_macro_form_is_definition()) {
    List definition = compiler.parse_macro_definition();
    return compiler.macro_holes ? definition : %(seq);
  }
  if (compiler.peek(0) == <ident> && compiler.token.text == "with")
    return compiler.parse_statement();
  Var candidate;
  int with_expression = compiler.peek(0) == <ident> &&
    compiler.semantic_binding_facts().try_get(
      %(with-name ${compiler.token.text}), &candidate) && List.equal(
        compiler.sym.lookup(%(${compiler.token.text}), NULL),
        candidate);
  List macro = with_expression ? NULL
    : compiler.try_parse_macro_target_at(AST_BLOCK);
  if (macro) return macro;
  if (compiler.test_declaration()) {
    List declaration = compiler.parse_declaration_row();
    compiler.expect(<;>);
    return declaration;
  }
  return compiler.parse_statement();
}

/** Parses and binds one statement or statement-position macro at the current
    token. On return, the cursor follows the complete statement and any
    temporary `Sym` scopes opened by the statement have been closed.
*/
List Compiler.parse_statement(Compiler compiler) {
  List slot = compiler.try_parse_macro_slot(<statement>);
  if (slot) return slot;
  if (compiler.peek(0) == <$> &&
      compiler.macro_starts_target_at(AST_STATEMENT)) {
    List hole = compiler.peek_macro_hole();
    List macro = compiler.try_parse_macro_target_at(AST_STATEMENT);
    if (macro) return macro;
    List expression = hole && hole.assoc(<kind>) == <name>
                    ? compiler.parse_expression()
                    : compiler.try_parse_macro_expression();
    compiler.expect(<;>);
    return %(stmnt $expression);
  }
  /* A `with` alias records its source expression, not a temporary. Its `Sym`
     scope and semantic rows exist only while the body parses, so every use
     substitutes the expression and an unused alias does not evaluate it. */
  if (compiler.peek(0) == <ident> && compiler.token.text == "with") {
    compiler.next();
    if ((compiler.peek(0) == <"{"> && compiler.peek(1) == <"}">) ||
        compiler.peek(0) == <;> || compiler.peek(0) == <eof>)
      compiler.report_error(
        <parse>, "with requires an expression", compiler.token, NULL);
    List expression = compiler.parse_expression(), String alias = %"_";
    if (compiler.peek(0) == <ident> && compiler.token.text == "as") {
      compiler.next();
      if (compiler.peek(0) != <ident>)
        compiler.report_error(
          <parse>, "expected an alias identifier after 'as'",
          compiler.token, NULL);
      alias = compiler.token.text;
      compiler.next();
    }
    if (compiler.peek(0) != <"{">)
      compiler.report_error(
        <parse>, "with requires a braced body", compiler.token, NULL);
    List type = NULL;
    match (expression)
      case %(expr ?expression_type ?): type = expression_type;
    compiler.sym.push_new_scope();
    List binding = compiler.sym.define(%($alias), type);
    compiler.semantic_binding_facts()[%(with $binding)] = expression;
    Var old_with;
    int had_previous_with = compiler.semantic_binding_facts().try_get(
      %(with-name $alias), &old_with);
    compiler.semantic_binding_facts()[%(with-name $alias)] = binding;
    List body = NULL;
    {
      defer {
        compiler.semantic_binding_facts().del(%(with $binding));
        if (had_previous_with)
          compiler.semantic_binding_facts()[%(with-name $alias)] =
            old_with;
        else compiler.semantic_binding_facts().del(%(with-name $alias));
        compiler.sym.pop_scope();
      }
      compiler.next();
      body = compiler.parse_compound_statement();
    }
    return body;
  }
  Var candidate;
  int with_expression = compiler.peek(0) == <ident> &&
    compiler.semantic_binding_facts().try_get(
      %(with-name ${compiler.token.text}), &candidate) && List.equal(
        compiler.sym.lookup(%(${compiler.token.text}), NULL),
        candidate);
  List keyword = !with_expression && compiler.peek(0) == <ident>
    ? compiler.try_parse_macro_target_at(AST_STATEMENT) : NULL;
  if (keyword) return keyword;
  Symbol token = compiler.peek(0);
  switch (token) {
    case <if>:          return _if_statement(compiler);
    case <while>:       return _while_statement(compiler);
    case <for>:         return _for_statement(compiler);
    case <do>:          return _do_statement(compiler);
    case <return>:      return _return_statement(compiler);
    case <case>:        return _case_statement(compiler);
    case <break>:       return _break_statement(compiler);
    case <continue>:    return _continue_statement(compiler);
    case <goto>:        return _goto_statement(compiler);
    case <try>:         return _try_statement(compiler);
    case <raise>:       return _raise_statement(compiler);
    case <defer>:       return _defer_statement(compiler);
    case <match>:       return _match_statement(compiler);
    case <switch>:      return _switch_statement(compiler);
    case <default>:     return _default_statement(compiler);
    case <;>:           return _empty_statement(compiler);
    case <(>:           return compiler.parse_parenthesized_statement();
    case <"{">: case <"%{">: {
      compiler.next();
      return compiler.parse_compound_statement();
    }
  }
  return _expression_statement(compiler);
}

/** Parses block items after an already-consumed opening brace through `}` and
    returns a `(block ...)` node. The call opens one lexical `Sym` scope;
    `anchor_items` records statement origins and distributes a macro sequence's
    invocation origin over its inserted items.
*/
List Compiler.parse_block_items(Compiler c, int anchor_items) {
  Array block = %[], List stmt = NULL;
  c.sym.push_new_scope();
  loop {
    foreach (Var directive, c.leading_preproc()) block.push(directive);
    if (c.peek(0) == <"}">) break;
    /* Anchor every statement to the token that opens it. Transform-phase
       diagnostics have no useful current token, so this occurrence lets
       them name a line inside the function instead of the end of the file.
       The anchor precedes parsing because parsing leaves the cursor on the
       following token. */
    Token origin = c.token;
    int expansion = (c.peek(0) == <$> &&
      !(c.macro_holes && c.peek_macro_hole())) ||
      (!c.macro_holes && c.local_macro_form_is_definition()) ||
      (c.peek(0) == <ident> &&
       c.keyword_alias_starts_target_at(AST_BLOCK));
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
  List result = cons(<block>, block.list_free());
  return result;
}

/** Parses a compound body after its opening brace and consumes the closing
    `}`, returning an origin-anchored `(block ...)` node.
*/
List Compiler.parse_compound_statement(Compiler compiler) =>
  compiler.parse_block_items(1);
