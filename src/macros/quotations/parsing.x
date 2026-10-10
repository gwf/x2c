/*  parsing.x -- quotation kinds, expression holes, and types
*/

#pragma once

/* The kind a quotation builds: one a result kind names, or a type or one
   parameter, which only a hole kind names. */
module Symbol Compiler._quotation_kind(Compiler c, Token token) {
  const MacroCategory *category = _category(token.text);
  if (category && (category.hole == <type> || category.hole == <param>))
    return category.hole;
  return c._result_kind_token(token);
}

/* Whether the quotation after `$!` states its type: `T{` where the
   identifier `T` names no kind, or a group that a brace follows. A type
   keyword such as `int` is an identifier here. */
module int Compiler._typed_quotation(Compiler c) {
  if (c.token.text.is_identifier())
    return c.peek(1) == <"{"> && !_category(c.token.text);
  return c.peek(0) == <(> && c.token.after_group().type == <"{">;
}

/* Declares a hidden local for each `${expression}` or `@{expression}` in
   the body, in source order, and records its name under the sigil's position.
   A nested quotation's holes are its own, and `case ${$name(...)}` is
   a macro pattern. */
module List Compiler._expression_holes(Compiler c, Map holes) {
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
      locals.push(c._hole_local(holes, t.pos));
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
static List Compiler._hole_local(Compiler c, Map holes, int position) {
  c.expect(<"{">);
  Token origin = c.token;
  List value = c.parse_expression();
  if (!value.cadr()) $report.type.var_unresolved(c, origin);
  c.expect(<"}">);
  String name = c.fresh_name("hole");
  holes[%(expression $position)] = name;
  Var constant = c.folded_constant(value);
  if (constant is void) holes[%(dynamic)] = 1;
  else holes[%(constant $name)] = constant;
  return c.bind_syntax(
    %(declare ${value.cadr()}
      (bindings (op = (bind ${c.sym.introduce(name)} ()) $value))),
    AST_BLOCK, c.return_type);
}

/* The expression that computes a typed quotation's type: the identifier at
   the cursor, or the group there, which holds a type or a `$name` local or
   `${expression}` hole whose value is the type. */
module List Compiler._quoted_type(Compiler c, Map holes) {
  if (c.peek(0) != <(>) return c._quoted_type_name();
  c.expect(<(>);
  Token origin = c.token;
  List type = NULL;
  if (c.peek(0) == <$>) {
    Var name = c.peek(1) == <"{">
             ? holes[%(expression ${c.token.pos})]
             : Token.skip_trivia(c.token + 1).text;
    c.token = c.after_hole();
    type = c._checked_type(
      c.resolve_expression(%(expr () (ident ${name.str()})), origin), origin);
  }
  else type = c._quoted_type_name();
  c.expect(<)>);
  return type;
}

/* The `Type` expression `type`, which a `meta` function checks names its
   type with a String before a typed quotation inserts it:
   `type_name_error(type) ? (x2c_diagnostic_fail(...), type) : type`. */
module List Compiler._checked_type(Compiler c, List type, Token origin) {
  if (!c.meta_body) return type;
  List error = c._runtime_call("type_name_error", %($type), origin);
  List fail = c._runtime_call(
    "x2c_diagnostic_fail", %($error (expr ("List") (nil))), origin);
  return c.resolve_expression(
    %(expr () (op ? $error
      (expr ("Type") ${source_commas_content(%($fail $type))}) $type)),
    origin);
}

static List Compiler._quoted_type_name(Compiler c) {
  Type parsed = NULL;
  c.parse_type_operand(&parsed);
  return c.cache_literal_list(parsed);
}

