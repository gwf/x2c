/*  statements.x -- x2c statement parsing

    `_parse_statement` dispatches each statement form to one
    production, which consumes its tokens in grammar order and returns its
    node. Preprocessor directives between statements stay in the tree, so
    each one emits where C read it. Return checking uses the return type
    that declaration parsing recorded.
*/

#pragma once
#include "private-keywords.x"
static keyword loop $private.loop;
#include "compiler/compiler.x"
#include "parse-reports.x"
#include "parse/parse.x"
#include "expressions/expressions.x"
#include "literals/literals.x"
#include "macros/macros.x"

/* statements diagnostics. */

static macro Stmt $fail.statements_with_body(Expr $c, Expr $site) =>
  $c.report_error(
    <parse>, "with requires a braced body",
    $site, NULL);

static macro Stmt $fail.statements_with_header(Expr $c, Expr $site) =>
  $c.report_error(
    <parse>, "with requires '(destination = expression, ...)'",
    $site, %("name an expression with alias"));

static macro Stmt $fail.statements_raise_payload(Expr $c, Expr $site) =>
  $c.report_error(
    <parse>, "raise requires a %() payload literal",
    $site, %("use raise %(code (key value)...);"));

static macro Stmt $fail.statements_match_default(Expr $c, Expr $site) =>
  $c.report_error(
    <parse>, "match default arm must be last",
    $site, %("move default after every case arm"));

static macro Stmt $fail.statements_match_arm(Expr $c, Expr $site) =>
  $c.report_error(
    <parse>, "expected 'case' or 'default' in match statement",
    $site, $("token:", $c.token.text));

static macro Stmt $fail.statements_match_pattern(
  Expr $c, Expr $origin, Expr $pattern) =>
  $c.report_error(
    <parse>, "match case pattern must be a %() list literal",
    $origin, $("pattern:", $pattern.repr()));

static macro Stmt $fail.statements_try_handler(Expr $c, Expr $site) =>
  $c.report_error(
    <parse>, "expected 'catch' or 'finally' after try block",
    $site, NULL);

static macro Stmt $fail.statements_catch_default(Expr $c, Expr $site) =>
  $c.report_error(
    <parse>, "catch default arm must be last",
    $site, %("move catch: after every filtered arm"));

static macro Stmt $fail.statements_catch_pattern(Expr $c, Expr $site) =>
  $c.report_error(
    <parse>, "catch filter requires a %() pattern literal",
    $site, %("use catch %(code (key pattern)...):"));

// statements

/* Parses and binds one statement or statement-position macro at the current
   token. On return, the cursor follows the complete statement and any
   temporary `Sym` scopes opened by the statement have been closed.
*/
static List _parse_statement(Compiler c) => _statement(c, <statement>);

/* A meta call written as the whole statement binds its result at
   `position`. */
static List _statement(Compiler c, Symbol position) {
  _x2c_complete_here(c, <statement>, _statement_keywords());
  List slot = c.try_parse_macro_slot(<statement>);
  if (slot) return slot;
  if (c.at_word("with")) return _with_statement(c, position);
  if (c.alias_form_starts())
    return c.parse_alias_statement(position == <block>);
  if (!c.alias_expression() && c.macro_starts_target_at(<statement>))
    return _macro_statement(c);
  switch (c.peek(0)) {
    case <if>: case <while>: case <for>: case <do>: case <match>: case <try>:
      return c.bind_source_statement();
    case <return>:      return _return_statement(c);
    case <case>:        return _case_statement(c);
    case <break>:       return _break_statement(c);
    case <continue>:    return _continue_statement(c);
    case <goto>:        return _goto_statement(c);
    case <raise>:       return _raise_statement(c);
    case <defer>:       return _defer_statement(c);
    case <switch>:      return _switch_statement(c);
    case <default>:     return _default_statement(c);
    case <;>:           return _empty_statement(c);
    case <(>:           return c.parse_parenthesized_statement();
    case <"{">: case <"%{">: return _compound_statement(c);
  }
  return _expression_statement(c, position);
}

static List _statement_keywords(void) => %(
  "if" "while" "for" "do" "return" "case" "break" "continue" "goto"
  "try" "raise" "defer" "match" "switch" "default" "with" "alias" "unalias"
);

/* A statement-position macro target, or else a macro expression ended by
   `;`. A template's `name` hole there parses as an ordinary expression. */
static List _macro_statement(Compiler c) {
  List hole = c.peek_macro_hole();
  List macro = c.try_parse_macro_target_at(<statement>);
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

static List _expression_statement(Compiler c, Symbol position) {
  List label = _label_statement(c);
  if (label) return label;
  Token start = c.token;
  List expr;
  with (c.meta_statement = start) { expr = c.parse_expression(); }
  c.expect(<;>);
  if (!c.macro_holes)
    match (expr) case %(expr ? (meta-call *)):
      return c.evaluate_meta_statement(expr, position, start);
  return %(stmnt $expr);
}

/* A `name:` label, or NULL with the cursor where it was. */
static List _label_statement(Compiler c) {
  Token head = c.token;
  if (c.peek(0) == <ident> ||
      (c.macro_holes && c.peek_macro_hole() &&
       c.after_hole().type == <:>)) {
    List label = c.try_parse_macro_slot(<name>);
    if (!label) label = c.parse_optional_identifier();
    if (c.test(<:>)) return %(label $label);
    c.token = head;
  }
  return NULL;
}

// with statements

/* `with (place = value, ...) { ... }` expands the built-in `$x2c.with`
   decorator over its braced body at `position`. */
static List _with_statement(Compiler c, Symbol position) {
  Token open = Token.skip_trivia(c.token + 1);
  if (open.type != <(>)
    $fail.statements_with_header(c, c.token);
  Token body = open.after_group();
  if (body.type != <"{">)
    $fail.statements_with_body(c, body);
  return c.try_parse_macro_target_at(position);
}

// conditionals and loops

/** Parses the clause `kind` of a source `if`, `while`, `do`, `for`,
    `match`, or `try`, with the punctuation after it, when the binder
    reaches that clause. An absent `else`, `for` header, `catch`, or
    `finally` clause is NULL.
*/
List Compiler.parse_source_clause(Compiler c, Symbol kind) {
  switch (kind) {
    case <test>: return _paren_expr(c);
    case <then>: return _then_arm(c);
    case <else>:
      return c.test(<else>) ? c.parse_governed(<statement>) : NULL;
    case <do>:   return _do_body(c);
    case <init>: return _for_init(c);
    case <cond>: return _for_clause(c, <;>);
    case <next>: return _for_clause(c, <)>);
    case <arms>: return _match_arms(c);
    case <try>:  return _continued(c, c.parse_governed(<statement>));
    case <catches>: return _catches(c);
    case <catch>: return _catch_body(c);
    case <finally>: return _finally(c);
  }
  return c.parse_governed(<statement>);
}

static List _keyword_paren_expr(Compiler c, Symbol keyword) {
  c.expect(keyword);
  return _paren_expr(c);
}

static List _paren_expr(Compiler c) {
  c.expect(<(>);
  List expr = c.parse_expression();
  c.expect(<)>);
  return expr;
}

/* Directives before an `else` follow the arm it continues. */
static List _then_arm(Compiler c) {
  List arm = c.parse_governed(<statement>);
  _x2c_complete_here(c, <continue>, %("else"));
  return c.peek(0) == <else> ? _continued(c, arm) : arm;
}

static List _do_body(Compiler c) {
  List body = _continued(c, c.parse_governed(<statement>));
  c.expect(<while>);
  return body;
}

/* An initializer that declares becomes a `(decl ...)` node. Each clause
   peeks for its terminator, so an omitted clause consumes exactly what a
   present one does. */
static List _for_init(Compiler c) {
  c.expect(<(>);
  List init = NULL;
  if (c.peek(0) != <;>)
    init = c.test_declaration() ? c.parse_type_operand(NULL)
                              : c.parse_expression();
  c.expect(<;>);
  return init;
}

static List _for_clause(Compiler c, Symbol end) {
  List clause = c.peek(0) == end ? NULL : c.parse_expression();
  c.expect(end);
  return clause;
}

// keyword statements

static List _return_statement(Compiler c) {
  c.expect(<return>);
  _x2c_complete_here(c, <expr>, %());
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
  return %(return $(c.return_type) $resolved);
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
    $fail.statements_raise_payload(c, c.token);
  List stmt = c.parse_raise_literal();
  c.expect(<;>);
  return stmt;
}

static List _defer_statement(Compiler c) {
  c.expect(<defer>);
  return %(defer $(c.parse_governed(<statement>)));
}

static List _switch_statement(Compiler c) {
  List expr = _keyword_paren_expr(c, <switch>);
  List body = c.parse_governed(<statement>);
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

static List _match_arms(Compiler c) {
  if (!c.test(<"{">)) return cons(_match_case(c), NULL);
  List cases = _match_cases(c);
  c.expect(<"}">);
  return cases;
}

static List _match_cases(Compiler c) {
  Array cases = [], groups = auto [];
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
      $fail.statements_match_default(c, c.token);
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
  foreach (List directive in c.leading_preproc()) {
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
  Symbol kind = Compiler.preproc_conditional_kind(d.cadr());
  if (kind == <open>) groups.push($(saw_default, saw_default));
  else if (kind && groups.len()) {
    (int before, int any) = groups.take_last();
    any |= saw_default;
    if (kind == <close>) return any;
    groups.push($(before, any));
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
  if (c.test(<case>)) pattern = _case_pattern(c, start, types);
  else if (c.test(<default>)) pattern = %(*);
  else
    $fail.statements_match_arm(c, c.token);
  return c.bind_match_arm(
    pattern, Compiler.source_clause(<arm>), start, peek == <case>, types);
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
  Array captures = auto [];
  List pattern = NULL;
  with (c.in_pattern = 1, c.match_types = captures) {
    pattern = c.try_parse_macro_pattern();
    if (!pattern) pattern = c.try_parse_macro_pattern_insertion(0);
    if (!pattern) pattern = c.parse_expression();
    types = captures;
  }
  return pattern;
}

static void _require_list_literal(Compiler c, List pattern, Token start) {
  match (pattern)
    case %(!not (expr ("List") *)):
      $fail.statements_match_pattern(c, start, pattern);
}

/** Parses a source match arm's guard and body, declaring its typed
    `types` captures, inside the arm scope that the binder opened.
*/
List Compiler.parse_case_body(Compiler c, List types) {
  List temporaries = NULL;
  List declarations = types ? _typed_captures(c, types, temporaries) : NULL;
  List guard = c.peek(0) == <if> ? _keyword_paren_expr(c, <if>) : NULL;
  c.expect(<:>);
  List body = c.parse_governed(<statement>);
  if (guard) body = %(if $guard (block $body (break)));
  if (types) {
    body = %(block @temporaries (block @declarations $body));
    c.sym.pop_scope();
  }
  if (guard) body = %(guarded $body);
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
  foreach (List row in types) match (row)
    case %(?name ?type): {
      String temporary = c.fresh_name("match_value");
      declarations.push(
        _capture_declaration(
          c, %("Var"), temporary, %(expr () (ident ($name))), 1));
      locals.push($(name, type, temporary));
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
  else binding = temporary ? c.sym.introduce(name) : $("x2c.ident", name);
  return c.bind_syntax(
    %(declare $type
      (bindings (op = (bind $binding ()) $initializer))),
    <block>, c.return_type);
}

static List _capture_locals(Compiler c, Array locals) {
  Array declarations = [];
  foreach (List row in locals) match (row)
    case %(?name ?type ?temporary):
      declarations.push(
        _capture_declaration(
          c, type, name, %(expr () (ident ($temporary))), 0));
  return declarations.list_free();
}

// try statements

/* A `try` needs a `catch` or a `finally` after its body. */
static List _catches(Compiler c) {
  _x2c_complete_here(c, <continue>, %("catch" "finally"));
  if (c.test(<catch>)) return _catch_cases(c);
  if (c.peek(0) != <finally>)
    $fail.statements_try_handler(c, c.token);
  return NULL;
}

static List _finally(Compiler c) {
  _x2c_complete_here(c, <continue>, %("finally"));
  return c.test(<finally>) ? c.parse_governed(<statement>) : NULL;
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
      $fail.statements_catch_default(c, c.token);
  }
  return %(catchcases $(arms.list_free()) $handle);
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
  return c.bind_catch_arm(
    pattern, Compiler.source_clause(<catch>), start, handle);
}

/* Directives before a later `catch` or `finally` follow the arm. */
static List _catch_body(Compiler c) {
  List body = c.parse_governed(<statement>);
  _x2c_complete_here(c, <continue>, %("catch" "finally"));
  return c.peek(0) == <catch> || c.peek(0) == <finally>
       ? _continued(c, body) : body;
}

static List _catch_filter(Compiler c) {
  if (c.peek(0) != <"%(">)
    $fail.statements_catch_pattern(c, c.token);
  List pattern = c.parse_catch_pattern_literal();
  c.expect(<:>);
  return pattern;
}

// governed statements

/** Parses the statement a control keyword or statement macro governs, or a
    block item at `<block>`. Directives written before it stay in front of
    it in a `(group DIRECTIVE... STATEMENT)`, which emits without braces, so
    each directive stays where C read it. A conditional group they open also
    takes the statement of each later arm and the closing directive, so a
    statement macro that wraps its body in braces keeps the whole group
    inside them. A later statement in the same arm follows the governed one,
    as in C.
*/
List Compiler.parse_governed(Compiler c, Symbol position) {
  Array items = auto [];
  int depth = _take_directives(c, items);
  loop {
    Token start = c.token;
    items.push(
      position == <block> ? c.parse_block_item() : _parse_statement(c));
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
  return items.len() == 1 ? items[0] : %(group @(items.list()));
}

/* Adds the directives before the cursor to `items` and returns how many
   conditional groups they open, less those they close. */
static int _take_directives(Compiler c, Array items) {
  int depth = 0;
  foreach (List directive in c.leading_preproc()) {
    items.push(directive);
    depth += _group_step(directive.cadr());
  }
  return depth;
}

/* How many conditional groups the directive `s` opens, or -1 when it
   closes one. */
static int _group_step(String s) {
  Symbol kind = Compiler.preproc_conditional_kind(s);
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
  foreach (List directive in run) {
    Symbol kind = Compiler.preproc_conditional_kind(directive.cadr());
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
  _x2c_complete_here(c, <block>, _block_keywords());
  if (c.test_static_assert()) return c.parse_static_assert();
  List slot = c.try_parse_macro_slot(<block>);
  if (slot) return slot;
  if (c.local_macro_form_is_definition()) return _local_macro(c);
  if (c.alias_form_starts()) return c.parse_alias_statement(1);
  if (c.at_word("with")) return _statement(c, <block>);
  // An identifier naming a visible alias is no macro target.
  List macro =
    c.alias_expression() ? NULL : c.try_parse_macro_target_at(<block>);
  if (macro) return macro;
  if (c.test_declaration()) return _declaration_item(c);
  return _statement(c, <block>);
}

static List _block_keywords(void) => %(
  "void" "char" "short" "int" "long" "float" "double"
  "signed" "unsigned" "if" "while" "for" "do" "return"
  "case" "break" "continue" "goto" "try" "raise" "defer"
  "match" "switch" "default" "with" "alias" "unalias"
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
  return c.finish_initializers(decl, origin);
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
  Array block = auto [];
  List present_before = c.present_references();
  defer c.restore_reference_presence(present_before);
  loop {
    _x2c_complete_here(c, <block>, _block_keywords());
    if (c.token != c.directives_taken)
      foreach (List directive in c.leading_preproc()) block.push(directive);
    if (c.peek(0) == <"}">) break;
    _push_item(c, block, anchor_items);
  }
  c.expect(<"}">);
  return cons(<block>, block);
}

/* Parses one item into `block`, anchored to the token that opens it, and
   then the code placed after it. Transform-phase diagnostics have no
   useful current token, so this occurrence lets them name a line inside
   the function instead of the end of the file. The anchor precedes
   parsing, which leaves the cursor on the following token. */
static void _push_item(Compiler c, Array block, int anchor_items) {
  Token origin = c.token;
  int expansion = _expands(c);
  c.enter((Ancestor){ .what = <statement>, .token = origin });
  List stmt = c.parse_block_item();
  List after = c.leave_item();
  if (c.macro_holes &&
      (stmt.car() == <macro-bind> || stmt.car() == <macro-slot>)) {
    block.push(stmt);
    return;
  }
  if (!expansion)
    block.push(anchor_items ? c.anchor_origin(stmt, origin) : stmt);
  else after = stmt.cdr().append(after);
  foreach (List item in after)
    block.push(
      !anchor_items || item.car() == <at>
        ? item : c.anchor_origin(item, origin)
    );
}

/* Whether the item at the cursor parses to a `(seq ...)` whose items join
   the block: a macro target outside a template hole, or a local macro
   definition outside a template. */
static int _expands(Compiler c) =>
  (c.macro_starts_target_at(<block>) &&
   !(c.macro_holes && c.peek_macro_hole())) ||
  (!c.macro_holes && c.local_macro_form_is_definition());
