/*  statements.x -- x2c statement parsing

    `Compiler.parse_statement` dispatches each statement form to one
    production, which consumes its tokens in grammar order and returns its
    node. Preprocessor directives between statements stay in the tree, so
    each one emits where C read it. Return checking uses the return type
    that declaration parsing recorded.
*/

#pragma once
$(import "../lib/private-keywords.xmacro")
#include "compiler.x"
#pragma private
#include "parse.x"
#include "expressions.x"
#include "literals.x"
#include "macros.x"

// statements

/** Parses and binds one statement or statement-position macro at the current
    token. On return, the cursor follows the complete statement and any
    temporary `Sym` scopes opened by the statement have been closed.
*/
List Compiler.parse_statement(Compiler c) {
  c.__complete_here(<statement>, _statement_keywords());
  List slot = c.try_parse_macro_slot(<statement>);
  if (slot) return slot;
  if (c.peek(0) == <ident> && c.token.text == "with")
    return _with_statement(c);
  if (!c.with_binding() && c.macro_starts_target_at(AST_STATEMENT))
    return _macro_statement(c);
  switch (c.peek(0)) {
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
    case <"{">: case <"%{">: return _compound_statement(c);
  }
  return _expression_statement(c);
}

static List _statement_keywords(void) => %(
  "if" "while" "for" "do" "return" "case" "break" "continue" "goto"
  "try" "raise" "defer" "match" "switch" "default" "with"
);

/* A statement-position macro target, or else a macro expression ended by
   `;`. A template's `name` hole there parses as an ordinary expression. */
static List _macro_statement(Compiler c) {
  List hole = c.peek_macro_hole();
  List macro = c.try_parse_macro_target_at(AST_STATEMENT);
  if (macro) return macro;
  List expression = hole && hole.assoc(<kind>) == <name>
                  ? c.parse_expression() : c.try_parse_macro_expression();
  c.expect(<;>);
  return %(stmnt $expression);
}

static List _compound_statement(Compiler c) {
  c.next();
  return c.parse_compound_statement();
}

static List _expression_statement(Compiler c) {
  List label = _label_statement(c);
  if (label) return label;
  List expr = c.parse_expression();
  c.expect(<;>);
  return %(stmnt $expr);
}

/* A `name:` label, or NULL with the cursor where it was. */
static List _label_statement(Compiler c) {
  Token head = c.token;
  if (c.peek(0) == <ident> ||
      (c.macro_holes && c.peek_macro_hole() && c.peek(2) == <:>)) {
    List label = c.try_parse_macro_slot(<name>);
    if (!label) label = c.parse_optional_identifier();
    if (c.test(<:>)) return %(label $label);
    c.token = head;
  }
  return NULL;
}

// with statements

/* A `with` alias stands for its source expression. Its `Sym` scope and
   semantic rows exist only while the body parses, so every use substitutes
   the expression and an unused alias does not evaluate it. */
static List _with_statement(Compiler c) {
  c.next();
  if ((c.peek(0) == <"{"> && c.peek(1) == <"}">) ||
      c.peek(0) == <;> || c.peek(0) == <eof>)
    c.report_error(<parse>, "with requires an expression", c.token, NULL);
  List expression = c.parse_expression();
  String alias = _with_alias(c);
  if (c.peek(0) != <"{">)
    c.report_error(<parse>, "with requires a braced body", c.token, NULL);
  return _with_body(c, expression, alias);
}

/* The name after `as`, or `_` when the statement names none. */
static String _with_alias(Compiler c) {
  if (c.peek(0) != <ident> || c.token.text != "as") return "_";
  c.next();
  if (c.peek(0) != <ident>)
    c.report_error(
      <parse>, "expected an alias identifier after 'as'", c.token, NULL);
  String alias = c.token.text;
  c.next();
  return alias;
}

/* Parses the braced body with `alias` bound to `expression`. The alias
   shadows any outer `with` of the same name until the body ends. */
static List _with_body(Compiler c, List expression, String alias) {
  List type = NULL;
  match (expression)
    case %(expr ?expression_type ?): type = expression_type;
  c.sym.push_new_scope();
  List binding = c.sym.define(%($alias), type);
  c.semantic_binding_facts()[%(with $binding)] = expression;
  Var shadowed;
  int shadows = c.semantic_binding_facts().try_get(
    %(with-name $alias), shadowed);
  c.semantic_binding_facts()[%(with-name $alias)] = binding;
  defer {
    c.semantic_binding_facts().del(%(with $binding));
    if (shadows) c.semantic_binding_facts()[%(with-name $alias)] = shadowed;
    else c.semantic_binding_facts().del(%(with-name $alias));
    c.sym.pop_scope();
  }
  c.next();
  return c.parse_compound_statement();
}

/** Returns the binding of the current identifier when it names a live
    `with` expression, or NULL.
*/
List Compiler.with_binding(Compiler c) {
  Var candidate;
  if (c.peek(0) != <ident> ||
      !c.semantic_binding_facts().try_get(
        %(with-name ${c.token.text}), candidate))
    return NULL;
  List binding = c.sym.lookup(%(${c.token.text}), NULL);
  return binding.equal(candidate) ? binding : NULL;
}

// control flow

static List _if_statement(Compiler c) {
  List cond = _keyword_paren_expr(c, <if>);
  int true_is_present = 1;
  List binding = c.optional_reference_test(cond, true_is_present);
  List ontrue = _if_arm(c, binding, true_is_present);
  c.__complete_here(<continue>, %("else"));
  if (c.peek(0) != <else>) {
    if (binding && !true_is_present && reference_guard_exits(ontrue))
      c.mark_reference_present(binding);
    return %(if $cond $ontrue);
  }
  ontrue = _continued(c, ontrue);
  c.next();
  List onfalse = _if_arm(c, binding, !true_is_present);
  if (binding && reference_guard_exits(ontrue) && !true_is_present)
    c.mark_reference_present(binding);
  if (binding && reference_guard_exits(onfalse) && true_is_present)
    c.mark_reference_present(binding);
  return %(if $cond $ontrue $onfalse);
}

static List _keyword_paren_expr(Compiler c, Symbol keyword) {
  c.expect(keyword);
  c.expect(<(>);
  List expr = c.parse_expression();
  c.expect(<)>);
  return expr;
}

/* Parses one arm of an `if`. When the condition tests the optional
   reference `binding`, the arm parses with it marked present if `present`
   says the arm runs only with the reference present. */
static List _if_arm(Compiler c, List binding, int present) {
  if (!binding) return c.parse_governed(AST_STATEMENT);
  List before = c.present_references();
  if (present) c.mark_reference_present(binding);
  List arm = c.parse_governed(AST_STATEMENT);
  c.restore_reference_presence(before);
  return arm;
}

static List _while_statement(Compiler c) {
  List cond = _keyword_paren_expr(c, <while>);
  List body = c.parse_governed(AST_STATEMENT);
  return %(while $cond $body);
}

static List _for_statement(Compiler c) {
  c.sym.push_new_scope();
  defer c.sym.pop_scope();
  c.expect(<for>);
  c.expect(<(>);
  /* Each clause peeks for its terminator and leaves the token for the
     expect below, so an omitted clause consumes exactly what a present
     one does. */
  List init = _for_init(c);
  c.expect(<;>);
  List cond = c.peek(0) == <;> ? NULL : c.parse_expression();
  c.expect(<;>);
  List inc = c.peek(0) == <)> ? NULL : c.parse_expression();
  c.expect(<)>);
  List body = c.parse_governed(AST_STATEMENT);
  return %(for $init $cond $inc $body);
}

/* An initializer that declares becomes a `(decl ...)` node. */
static List _for_init(Compiler c) {
  if (c.peek(0) == <;>) return NULL;
  if (!c.test_declaration()) return c.parse_expression();
  List init = c.parse_simple_declaration();
  return cons(<decl>, init.cdr());
}

static List _do_statement(Compiler c) {
  c.expect(<do>);
  List body = _continued(c, c.parse_governed(AST_STATEMENT));
  List cond = _keyword_paren_expr(c, <while>);
  return %(do $body $cond);
}

static List _return_statement(Compiler c) {
  c.expect(<return>);
  c.__complete_here(<expr>, %());
  if (c.peek(0) == <;>) {
    c.next();
    return c.finish_return_statement(NULL);
  }
  List expr = c.parse_expression();
  c.expect(<;>);
  return c.finish_return_statement(expr);
}

/** Builds a return node for an optional expression without consuming tokens.
    A present expression is resolved in the current `Sym` scope and includes
    the current `return_type` for later conversion.
*/
List Compiler.finish_return_statement(Compiler c, List expr) {
  if (!expr) return %(return);
  List resolved = c.resolve_expression(expr, c.token);
  c.check_explicit_converter(resolved, c.return_type, 0);
  return %(return ${c.return_type} $resolved);
}

static List _case_statement(Compiler c) {
  c.expect(<case>);
  List expr = c.parse_expression();
  c.expect(<:>);
  return %(case $expr);
}

static List _break_statement(Compiler c) {
  c.expect(<break>);
  c.expect(<;>);
  return %(break);
}

static List _continue_statement(Compiler c) {
  c.expect(<continue>);
  c.expect(<;>);
  return %(continue);
}

static List _goto_statement(Compiler c) {
  c.expect(<goto>);
  List label = c.parse_optional_identifier();
  c.expect(<;>);
  return %(goto $label);
}

static List _raise_statement(Compiler c) {
  c.expect(<raise>);
  if (c.peek(0) != <"%(">)
    c.report_error(
      <parse>, "raise requires a %() payload literal",
      c.token, %("use raise %(code (key value)...);"));
  List stmt = c.parse_raise_literal();
  c.expect(<;>);
  return stmt;
}

static List _defer_statement(Compiler c) {
  c.expect(<defer>);
  return %(defer ${c.parse_governed(AST_STATEMENT)});
}

static List _switch_statement(Compiler c) {
  List expr = _keyword_paren_expr(c, <switch>);
  List body = c.parse_governed(AST_STATEMENT);
  return %(switch $expr $body);
}

static List _default_statement(Compiler c) {
  c.expect(<default>);
  c.expect(<:>);
  return %(default);
}

static List _empty_statement(Compiler c) {
  c.expect(<;>);
  return %(empty);
}

// match statements

static List _match_statement(Compiler c) {
  List cases = NULL, expr = _keyword_paren_expr(c, <match>);
  if (c.test(<"{">)) {
    cases = _match_cases(c);
    c.expect(<"}">);
  }
  else cases = cons(_match_case(c), NULL);
  return %(match ${c.resolve_expression(expr, c.token)} $cases);
}

static List _match_cases(Compiler c) {
  Array cases = [], groups = $auto([]);
  Symbol peek = c.peek(0), int saw_default = 0;
  loop {
    saw_default = _arm_directives(c, cases, groups, saw_default);
    List hole = c.try_parse_macro_slot(<match-row>);
    if (hole) {
      cases.push(hole);
      peek = c.peek(0);
      continue;
    }
    if (peek != <case> && peek != <default>) break;
    if (saw_default)
      c.report_error(
        <parse>, "match default arm must be last",
        c.token, %("move default after every case arm"));
    if (peek == <default>) saw_default = 1;
    cases.push(_match_case(c));
    peek = c.peek(0);
  }
  return cases.list_free();
}

/* Directives around whole arms stay between them as `preproc` rows. Returns
   `saw_default` for the configuration after them. */
static int _arm_directives(
  Compiler c, Array cases, Array groups, int saw_default) {
  if (c.token == c.directives_taken) return saw_default;
  foreach (List directive, c.leading_preproc()) {
    cases.push(directive);
    saw_default = _default_after_directive(groups, saw_default, directive);
  }
  return saw_default;
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

/** Parses one MatchRow macro argument with the ordinary match-arm owner. */
List Compiler.parse_match_row_argument(Compiler c) => _match_case(c);

// match arms

static List _match_case(Compiler c) {
  Symbol peek = c.peek(0), Token start = c.token;
  List pattern = NULL, types = NULL;
  c.next();
  if (peek == <case>) pattern = _case_pattern(c, start, types);
  else if (peek == <default>) pattern = %(*);
  else
    c.report_error(
      <parse>, "expected 'case' or 'default' in match statement",
      c.token, %( "token:" ${c.token.text} ));
  c.begin_match_arm(pattern, start, peek == <case>);
  List body = _case_body(c, types);
  return %($pattern $body);
}

/* Typed captures rewrite the pattern after `case` and leave their rows in
   `types`. */
static List _case_pattern(Compiler c, Token start, List &types) {
  List pattern = _parse_pattern(c, types);
  if (types) pattern = c.typed_match_pattern(pattern, types);
  _require_list_literal(c, pattern, start);
  return pattern;
}

/* Parses a pattern while `c.match_types` collects its typed captures. */
static List _parse_pattern(Compiler c, List &types) {
  Array captures = $auto([]);
  List pattern = NULL;
  $let(c.in_pattern, 1)
  $let(c.match_types, captures) {
    pattern = c.try_parse_macro_pattern();
    if (!pattern) pattern = c.parse_expression();
    types = captures;
  }
  return pattern;
}

static void _require_list_literal(Compiler c, List pattern, Token start) {
  match (pattern)
    case %(!not (expr ("List") *)):
      c.report_error(
        <parse>, "match case pattern must be a %() list literal",
        start, %( "pattern:" ${pattern.repr()} ));
}

/** Opens a `Sym` scope for one match arm and optionally defines its definite
    pattern binders. The caller must pop the scope after parsing or binding the
    arm body; binder diagnostics use `start`.
*/
void Compiler.begin_match_arm(
  Compiler c, List pattern, Token start, int binds) {
  c.sym.push_new_scope();
  if (!binds) return;
  _check_binders(c, pattern, start, "match");
  c.define_match_binders(pattern);
}

/* Rejects the two ways a match or catch pattern can name a binder it does
   not reliably bind. `role` is the keyword the diagnostics name. */
static void _check_binders(
  Compiler c, List pattern, Token start, String role) {
  List possible = NULL;
  List definite = c.match_pattern_binders(pattern, possible);
  foreach (Var binder, possible) {
    if (!definite.contains(binder))
      c.report_error(
        <type>, %"$role binder is not definitely assigned",
        start, %( "binder:" ${binder.str()}
                  "bind it in every alternative and never under !not")
      );
    String name = binder.str()[1:];
    foreach (Var other, possible) {
      if (other == binder || other.str()[1:] != name) continue;
      c.report_error(
        <type>, %"$role binder has conflicting capture kinds",
        start, %( "binder:" $name "use either '?' or '*' consistently"));
    }
  }
}

/* Parses an arm's guard and body inside the scope `begin_match_arm` opened,
   and closes that scope. */
static List _case_body(Compiler c, List types) {
  List temporaries = NULL;
  List declarations = types ? _typed_captures(c, types, temporaries) : NULL;
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
  return body;
}

/* A typed capture binds a Var, which a temporary in the arm scope keeps. A
   new scope then declares the capture's name with its type, read from the
   temporary; the caller closes that scope. */
static List _typed_captures(Compiler c, List types, List &temporaries) {
  Array locals = [];
  temporaries = _capture_temporaries(c, types, locals);
  c.sym.push_new_scope();
  List declarations = _capture_locals(c, locals);
  locals.free();
  return declarations;
}

static List _capture_temporaries(Compiler c, List types, Array locals) {
  Array declarations = [];
  foreach (List row, types) match (row)
    case %(?name ?type): {
      String temporary = c.fresh_name("match_value");
      declarations.push(
        _capture_declaration(
          c, %("Var"), temporary, %(expr () (ident ($name))), 1));
      locals.push(%($name $type $temporary));
    }
  return declarations.list_free();
}

static List _capture_declaration(
  Compiler c, Type type, String name, List initializer, int temporary) {
  List binding;
  if (c.macro_holes) {
    binding = c.macro_introduced_name(name);
    initializer = c.resolve_expression(initializer, c.token);
    c.bind_template_local(binding, type, NULL);
  }
  else binding = temporary ? c.sym.introduce(name) : %("x2c.ident" $name);
  return c.bind_syntax(
    %(declare $type
      (bindings (op = (bind $binding ()) $initializer))),
    AST_BLOCK, c.return_type);
}

static List _capture_locals(Compiler c, Array locals) {
  Array declarations = [];
  foreach (List row, locals) match (row)
    case %(?name ?type ?temporary):
      declarations.push(
        _capture_declaration(
          c, type, name, %(expr () (ident ($temporary))), 0));
  return declarations.list_free();
}

// try statements

static List _try_statement(Compiler c) {
  c.expect(<try>);
  List body = _continued(c, c.parse_governed(AST_STATEMENT)), catches = NULL;
  c.__complete_here(<continue>, %("catch" "finally"));
  if (c.test(<catch>)) catches = _catch_cases(c);
  c.__complete_here(<continue>, %("finally"));
  List cleanup = c.test(<finally>) ? c.parse_governed(AST_STATEMENT) : NULL;
  if (catches || cleanup) return %(try $body $catches $cleanup);
  c.report_error(
    <parse>, "expected 'catch' or 'finally' after try block",
    c.token, NULL);
}

static List _catch_cases(Compiler c) {
  List handle = _catch_handle(c);
  Array arms = [], int saw_default = 0;
  loop {
    /* A template writes its catch arms as one `Catch` sequence hole. */
    List hole = c.try_parse_macro_slot(<catch>);
    if (hole) {
      arms.push(hole);
      if (!c.test(<catch>)) break;
      continue;
    }
    int is_default = 0;
    arms.push(_catch_arm(c, is_default, handle));
    if (is_default) saw_default = 1;
    if (!c.test(<catch>)) break;
    if (saw_default)
      c.report_error(
        <parse>, "catch default arm must be last",
        c.token, %("move catch: after every filtered arm"));
  }
  return %(catchcases ${arms.list_free()} $handle);
}

/* A template's handler is its own local, like any it declares. */
static List _catch_handle(Compiler c) =>
  c.macro_holes ? c.macro_introduced_name("error_handler")
                : c.sym.introduce(c.fresh_name("error_handler"));

static List _catch_arm(Compiler c, int &is_default, List handle) {
  Token start = c.token;
  List pattern = NULL;
  if (c.test(<:>)) is_default = 1;
  else pattern = _catch_filter(c);
  List bindings = c.begin_catch_arm(pattern, start);
  List body = c.parse_governed(AST_STATEMENT);
  c.__complete_here(<continue>, %("catch" "finally"));
  if (c.peek(0) == <catch> || c.peek(0) == <finally>)
    body = _continued(c, body);
  c.sym.pop_scope();
  return %($pattern (block
    @{c.catch_binder_declarations(bindings, handle)} $body));
}

static List _catch_filter(Compiler c) {
  if (c.peek(0) != <"%(">)
    c.report_error(
      <parse>, "catch filter requires a %() pattern literal",
      c.token, %("use catch %(code (key pattern)...):"));
  List pattern = c.parse_catch_pattern_literal();
  c.expect(<:>);
  return pattern;
}

/** Opens a `Sym` scope for one catch arm and defines a nonempty filter's
    definite pattern binders. Returns their capture-token/binding pairs.
    The caller must pop the scope after parsing or binding the arm body;
    binder diagnostics use `start`.
*/
List Compiler.begin_catch_arm(Compiler c, List pattern, Token start) {
  c.sym.push_new_scope();
  if (!pattern) return NULL;
  _check_binders(c, pattern, start, "catch");
  return c.define_catch_binders(pattern);
}

// governed statements

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
  Array items = $auto([]);
  int depth = _take_directives(c, items);
  loop {
    Token start = c.token;
    items.push(
      position == AST_BLOCK ? c.parse_block_item() : c.parse_statement());
    depth = _depth_after(c, start, depth);
    if (depth <= 0) break;
    Symbol end = _arm_end(c.leading_preproc());
    if (!end) break;
    depth += _take_directives(c, items);
    c.directives_taken = c.token;
    if (depth <= 0 || end == <close> || c.peek(0) == <"}"> ||
        c.peek(0) == <eof>)
      break;
  }
  return items.len() == 1 ? items[0] : %(group @{items.list()});
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

/* How many conditional groups the directive `s` opens, or -1 when it
   closes one. */
static int _group_step(String s) {
  Symbol kind = preproc_conditional_kind(s);
  return kind == <open> ? 1 : kind == <close> ? -1 : 0;
}

/* The group depth after the statement that began at `start`. A directive
   inside the statement may close the group; those after its last token
   precede the next item. */
static int _depth_after(Compiler c, Token start, int depth) {
  int pending = 0;
  for (Token token = start; depth > 0 && token < c.token; token++)
    if (token.type == <preproc>) pending += _group_step(token.text);
    else if (token.type != <space> && token.type != <comment>) {
      depth += pending;
      pending = 0;
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
    else if (!kind) continue;
    else if (!level) end = kind;
    else if (kind == <close>) level--;
  }
  return end;
}

/* Directives written before the `else`, `while`, `catch`, or `finally` that
   continues a statement follow that statement. */
static List _continued(Compiler c, List statement) {
  if (c.token == c.directives_taken) return statement;
  List directives = c.leading_preproc();
  return directives ? %(group $statement @directives) : statement;
}

// blocks

/** Parses one block-position declaration, statement, or macro insertion.
    The caller owns the surrounding scope; a macro insertion may return a
    `(seq ...)` node containing several block items.
*/
List Compiler.parse_block_item(Compiler c) {
  c.__complete_here(<block>, _block_keywords());
  if (c.test_static_assert()) return c.parse_static_assert();
  List slot = c.try_parse_macro_slot(<block>);
  if (slot) return slot;
  if (c.local_macro_form_is_definition()) return _local_macro(c);
  if (c.peek(0) == <ident> && c.token.text == "with")
    return c.parse_statement();
  // An identifier naming a live `with` expression is no macro target.
  int with_expression = !!c.with_binding();
  List macro = with_expression ? NULL : c.try_parse_macro_target_at(AST_BLOCK);
  if (macro) return macro;
  if (c.test_declaration()) return _declaration_item(c);
  return c.parse_statement();
}

static List _block_keywords(void) => %(
  "void" "char" "short" "int" "long" "float" "double"
  "signed" "unsigned" "if" "while" "for" "do" "return"
  "case" "break" "continue" "goto" "try" "raise" "defer"
  "match" "switch" "default" "with"
);

/* A local macro definition, which only a template keeps as an item. */
static List _local_macro(Compiler c) {
  List definition = c.parse_macro_definition();
  return c.macro_holes ? definition : %(seq);
}

static List _declaration_item(Compiler c) {
  Token origin = c.token;
  List decl = c.parse_declaration_row();
  c.expect(<;>);
  return c.finish_managed_declaration(decl, origin);
}

/** Parses a compound body after its opening brace and consumes the closing
    `}`, returning an origin-anchored `(block ...)` node.
*/
List Compiler.parse_compound_statement(Compiler c) => c.parse_block_items(1);

/** Parses block items after an already-consumed opening brace through `}` in
    a new lexical scope. `anchor_items` records statement origins.
*/
List Compiler.parse_block_items(Compiler c, int anchor_items) {
  c.sym.push_new_scope();
  defer c.sym.pop_scope();
  return _block_items(c, anchor_items);
}

/** Parses a callable's outer block in its active parameter scope. */
List Compiler.parse_callable_body(Compiler c) => _block_items(c, 1);

static List _block_items(Compiler c, int anchor_items) {
  Array block = $auto([]);
  List present_before = c.present_references();
  defer c.restore_reference_presence(present_before);
  loop {
    c.__complete_here(<block>, _block_keywords());
    if (c.token != c.directives_taken)
      foreach (Var directive, c.leading_preproc()) block.push(directive);
    if (c.peek(0) == <"}">) break;
    _push_item(c, block, anchor_items);
  }
  c.expect(<"}">);
  return cons(<block>, block);
}

/* Parses one item into `block`, anchored to the token that opens it.
   Transform-phase diagnostics have no useful current token, so this
   occurrence lets them name a line inside the function instead of the end
   of the file. The anchor precedes parsing, which leaves the cursor on the
   following token. */
static void _push_item(Compiler c, Array block, int anchor_items) {
  Token origin = c.token;
  int expansion = _expands(c);
  List stmt = c.parse_block_item();
  if (c.macro_holes &&
      (stmt.car() == <macro-bind> || stmt.car() == <macro-slot>)) {
    block.push(stmt);
    return;
  }
  if (!expansion) {
    block.push(anchor_items ? c.anchor_origin(stmt, origin) : stmt);
    return;
  }
  foreach (List item, stmt.cdr())
    block.push(
      !anchor_items || item.car() == <at>
        ? item : c.anchor_origin(item, origin)
    );
}

/* Whether the item at the cursor parses to a `(seq ...)` whose items join
   the block: a macro target outside a template hole, or a local macro
   definition outside a template. */
static int _expands(Compiler c) =>
  (c.macro_starts_target_at(AST_BLOCK) &&
   !(c.macro_holes && c.peek_macro_hole())) ||
  (!c.macro_holes && c.local_macro_form_is_definition());
