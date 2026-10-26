/*  syntax.x -- expression grammar */

/* expression grammar

   Each parser entry consumes exactly its grammar level and leaves `c.token`
   at the first token that belongs to its caller. Each level resolves the
   nodes it builds, so higher levels receive typed or deferred nodes. */

/** Parses an assignment expression and any following comma expressions.
    A comma expression retains source order and takes the type of its final
    value. `c.token` stops at the first token outside the expression.
*/
List Compiler.parse_expression(Compiler c) =>
  _parse_expression_tail(c, c.parse_assignment());

static List _parse_expression_tail(Compiler c, List expr) {
  if (c.peek(0) == <,>) {
    expr = cons(expr, _parse_comma_list(c));
    List last = expr.last(), type = last.cadr();
    return %(expr $type $(source_commas_content(expr)));
  }
  return expr;
}

static List _parse_comma_list(Compiler c) {
  Array expressions = [];
  do {
    c.expect(<,>);
    expressions.push(c.parse_assignment());
  } while (c.peek(0) == <,>);
  return expressions.list_free();
}

/** Parses one right-associative assignment expression.
    A parenthesized identifier list on the left becomes a destructuring
    assignment only for `=`. `c.token` stops after the expression.
*/
List Compiler.parse_assignment(Compiler c) =>
  _parse_assignment_tail(c, c.parse_conditional());

static List _parse_assignment_tail(Compiler c, List lhs) {
  Symbol op = c.peek(0);
  Token origin = c.token;
  if (!op.is_assignment_op()) return lhs;
  if (lhs.cadr().car() == <opt-ref>)
    $fail.expressions_optional_ref_assign(c, origin);
  List targets = op == <=> ? _destructure_targets(c, lhs) : NULL;
  c.next();
  List rhs = c.parse_assignment();
  if (targets) match (rhs)
    case %(expr ?type ?): return %(expr $type (dstrasgn $targets $rhs));
  if (op == <=>) c.check_explicit_converter(rhs, lhs.cadr(), 0);
  return c.resolve_expression(
    source_operator_expression(NULL, $(op, lhs, rhs)), origin);
}

static List _destructure_targets(Compiler c, List lhs) {
  match (lhs)
    case %(expr ? $($grouped(?target))): {
      if (_destructure_identifier(target)) return %(targets $target);
      match (target)
        case %(expr ? $($source_commas_content(%(*targets)))): {
          foreach (List entry in targets) {
            if (_destructure_identifier(entry)) continue;
            $fail.expressions_destructure_target(c, c.token);
          }
          return %(targets @targets);
        }
    }
  return NULL;
}

static int _destructure_identifier(List expression) {
  match (expression) {
    case %(expr ? $($source_identifier_content(%(?)))): return 1;
    case %(expr ? $($grouped($dereferenced(%(expr (& *)
        $($source_identifier_content(%(?)))))))):
      return 1;
  }
  return 0;
}

/** Parses a binary expression and its optional conditional tail.
    The false arm recurses at conditional precedence, making `?:`
    right-associative, and `c.token` stops after the expression.
*/
List Compiler.parse_conditional(Compiler c) =>
  _parse_conditional_tail(c, _parse_binary_ops(c));

static List _parse_conditional_tail(Compiler c, List condition) {
  Token origin = c.token;
  if (!c.test(<?>)) return condition;
  List ontrue = c.parse_expression();
  c.expect(<:>);
  return c.resolve_expression(
    source_operator_expression(
      NULL, %(? $condition $ontrue $(c.parse_conditional()))), origin);
}

static List _parse_binary_ops(Compiler c) =>
  _parse_binary_level(c, 1);

/* Larger levels of `Symbol.binary_precedence` bind more tightly. The
   recursive parser descends to level 10 before consuming operators while
   each level folds left; `is` shares the relational level but is recognized
   from its identifier spelling. */
static List _parse_binary_level(Compiler c, int level) {
  if (level > 10) return _parse_cast(c);
  return _parse_binary_level_tail(c, level, _parse_binary_level(c, level + 1));
}

static List _parse_binary_level_tail(Compiler c, int level, List lhs) {
  int first = 1;
  while (_binary_operator(c).binary_precedence() == level ||
         (level == 7 && _is_type_operator(c))) {
    if (_is_type_operator(c)) {
      lhs = _parse_type_test(c, lhs);
      continue;
    }
    Symbol op = _binary_operator(c);
    Token origin = c.token;
    c.next();
    List rhs = _parse_binary_level(c, level + 1);
    if (first) {
      lhs = c.resolve_expression(lhs, origin);
      first = 0;
    }
    rhs = c.resolve_expression(rhs, origin);
    lhs = _binary_expression(c, op, lhs, rhs, origin);
  }
  return lhs;
}

static List _parse_binary_levels_from(Compiler c, List lhs) {
  for (int level = 10; level > 0; level--)
    lhs = _parse_binary_level_tail(c, level, lhs);
  return lhs;
}

/* The keyword pass leaves `in` a name where a neighbor could also be C, as
   before a bare `[` literal. No name follows a complete operand, so there
   it is the membership operator. */
static inline Symbol _binary_operator(Compiler c) =>
  c.at_word("in") ? <in> : c.peek(0);

static inline int _is_type_operator(Compiler c) => c.at_word("is");

/* `value is T` tests a Var tag; `value is selector` tests a Symbol. Either
   may be negated as `is not`. */
static List _parse_type_test(Compiler c, List lhs) {
  Token origin = c.token;
  c.next();
  int negate = c.take_word("not");
  List test;
  if (_is_type_selector_start(c)) {
    Type target = _parse_is_type(c, origin);
    Macro has_type = $has_type;
    test = c.resolve_expression(
      c.rebuild_expression(NULL, has_type(lhs, target)), origin);
  }
  else {
    List selector = _parse_cast(c);
    Macro has_symbol = $has_symbol;
    test = c.resolve_expression(
      c.rebuild_expression(NULL, has_symbol(lhs, selector)), origin);
  }
  return negate ? c.resolve_expression(%(expr () (op ! $test)), origin)
                : test;
}

static int _is_type_selector_start(Compiler c) {
  if (c.at_word("Void")) return 1;
  Token head = c.token;
  if (c.test(<(>)) {
    int declaration = c.test_declaration();
    c.token = head;
    return declaration;
  }
  if (c.test_declaration()) return 1;
  if (c.peek(0) != <ident>) return 0;
  String spelling = c.token.text;
  return !c.sym.get($(spelling));
}

static Type _parse_is_type(Compiler c, Token origin) {
  int parenthesized = c.test(<(>), Type type = c.parse_type_name();
  if (parenthesized) {
    if (c.peek(0) == <[>)
      $fail.expressions_is_array(c, origin);
    if (c.peek(0) == <(>)
      $fail.expressions_is_function(c, origin);
    c.expect(<)>);
  }
  else if (type.is_pointer())
    $fail.expressions_is_pointer(c, origin);
  return type;
}

/** Parses a statement beginning with `(`.

    The ordinary parameter parser consumes the contents once: one anonymous
    parameter is a cast type, while named parameters are destructuring
    declarations. Everything following an ordinary parenthesized expression
    resumes at the postfix tail it had already reached. This entry consumes
    the terminating `;` and returns `(stmnt expression)` or an origin-anchored
    `(dstrdecl ...)`.
*/
List Compiler.parse_parenthesized_statement(Compiler c) {
  Token origin = c.token;
  c.expect(<(>);
  if (c.test_declaration()) {
    List parameters = c.parse_parameter_list();
    c.expect(<)>);
    match (parameters)
      case %((!set ?(List parameter)
                (param ?base (!set ?binding (bind () ?))))): {
        List decl = %(decl $base (bindings $binding));
        List cast = _finish_cast(
          c, decl, parameter.type_from_ast(), _parse_cast(c), origin);
        return _finish_paren_statement(c, cast, 0);
      }
    foreach (List parameter in parameters)
      c.check_reference_placement(parameter.type_from_ast());
    c.expect(<=>);
    List source = c.parse_assignment();
    c.expect(<;>);
    return c.anchor_origin(
      %(dstrdecl (params @parameters) $source), origin);
  }

  return _finish_paren_statement(c, _parse_group_rest(c), 1);
}

static List _finish_paren_statement(Compiler c, List expression, int postfix) {
  if (postfix) expression = _parse_postfix_tail(c, expression);
  expression = _parse_binary_levels_from(c, expression);
  expression = _parse_conditional_tail(c, expression);
  expression = _parse_assignment_tail(c, expression);
  expression = _parse_expression_tail(c, expression);
  c.expect(<;>);
  return %(stmnt $expression);
}

// casts and unary operators

static List _parse_cast(Compiler c) {
  Token head = c.token;
  if (_cast_operand_after_parens(c) && c.test(<(>)) {
    if (c.test_declaration() ||
        _macro_hole_starts_cast_type(c, head.after_group())) {
      Type type = NULL;
      List decl = c.parse_type_operand(&type);
      c.expect(<)>);
      return _finish_cast(c, decl, type, _parse_cast(c), head);
    }
  }
  c.token = head;
  return _parse_unary_op(c);
}

/* Types the cast of `operand` to `decl`, which declares `type`, and warns
   when the cast changes nothing. A template typedef or an operand typed at
   expansion leaves the cast typed at expansion too. */
static List _finish_cast(
  Compiler c, List decl, Type type, List operand, Token origin) {
  if (operand.cadr() === %(<macro-expr>) ||
      _casts_to_template_typedef(c, decl) || _casts_to_typedef_name(c, decl))
    type = %(<macro-expr>);
  _warn_unnecessary_cast(c, operand, type, origin);
  return _cast_expression(c, decl, type, operand);
}

/** Parses one macro target through the cast-expression grammar.
    Parsing starts at `c.token` and leaves it at the first token after
    the target.
*/
List Compiler.parse_macro_expression_target(Compiler c) => _parse_cast(c);

static int _cast_operand_after_parens(Compiler c) =>
  c.peek(0) == <"("> &&
  _cast_operand_follows(c.token.after_group().type);

static int _macro_hole_starts_cast_type(Compiler c, Token after) {
  if (!c.macro_holes || c.peek(0) != <$> ||
      c.after_hole().type != <)>) return 0;
  List hole = c.peek_macro_hole();
  if (!hole) return 0;
  Symbol kind = hole.assoc(<kind>);
  if (kind && kind != <type>) return 0;
  /* `($items)[0]` subscripts the hole's value and `($key) in table` tests
     it; only a hole declared a type casts an array literal or a name `in`. */
  if ((after.type == <[> || after.text == "in") && kind != <type>) return 0;
  return _cast_operand_follows(after.type);
}

/* C 6.5.3: `++` and `--` take a unary expression, and the unary operators
   take a cast expression. A primary expression begins with a name, a
   literal, a group, or a macro form. */
static const SymbolSet increments = %<<"++" "--">>;
static const SymbolSet unary_operators = %<<"&" "*" "+" "-" "~" "!">>;
static const SymbolSet primary_starts =
  %<<ident in "$" "$(" "(" "{" "[" "%(" "%<<" "%[" "%{" "%\"" "%!" void
     lit-char lit-int lit-float lit-char* lit-atom lit-symbol>>;

static int _cast_operand_follows(Symbol s) =>
  s in primary_starts || s == <sizeof> || s in increments ||
  s in unary_operators;

/* A template typedef is named by the binding each expansion supplies, so a
   cast to it, qualified or not, is typed where the template expands. A
   template keeps aggregate tags as spellings, so only a typedef base ends in
   a binding. */
module int _casts_to_template_typedef(Compiler c, List declaration) {
  List base = declaration.cadr();
  return c.macro_holes && !!base.match(%(* (binding ? ?)));
}

/* A template body binds any other typedef name where it expands too, so
   when the body is defined, a cast to one is left for the expansion to
   type. A typedef base ends in its String spelling; a C type word does not,
   and an aggregate tag keeps its spelling after `struct`, `union`, or
   `enum`. */
static int _casts_to_typedef_name(Compiler c, List declaration) {
  List base = declaration.cadr();
  if (!c.macro_holes || !base.match(%(* ?(String name)))) return 0;
  foreach (Var word in base)
    if (word == <struct> || word == <union> || word == <enum>) return 0;
  return 1;
}

/* A cast whose operand already has the cast type, qualifiers included,
   changes nothing. The comparison uses x2c's declared type, so a cast
   between a typedef and its C type stays silent, and only an operand whose
   C type x2c knows is compared: a pointer difference or a character
   constant is not. A `void` cast discards a value on purpose, and a cast of
   a C string literal is how source keeps the literal native where x2c would
   otherwise promote it to a `String`. */
static void _warn_unnecessary_cast(
  Compiler c, List operand, Type target, Token origin) {
  if (!target || target === %(void) || target === %(<macro-expr>) ||
      _is_raw_string_literal(operand)) return;
  Type source = operand.cadr();
  if (!_c_type_known(c, operand) || source.declared() != target.declared())
    return;
  $warn.expressions_cast_redundant(c, origin, target);
}

/* Whether C gives an operand the type x2c records. A character constant is
   `int` in C; `sizeof`, `offsetof`, and a pointer difference have `size_t`
   and `ptrdiff_t` identities selected by the native toolchain; an enum's
   compatible integer type is implementation-defined; C compilers type a
   bitfield differently. */
static int _c_type_known(Compiler c, List operand) {
  match (operand) {
    case %(expr ? $($grouped(?inner))):
      return _c_type_known(c, inner);
    case %(expr ? $($source_literal_content(%((char) *)))): return 0;
    case %(expr ? $($sizeof_grouped(?operand))): return 0;
    case %(expr ? $($sizeof_expression(?operand))): return 0;
    case %(expr ? (offsetof *)): return 0;
    case %(expr ? $($source_operator_content(
        %(- (expr ?left *) (expr ?right *))))): {
      Type l = left, r = right;
      if ((l.is_pointer() || l.is_array()) && (r.is_pointer() || r.is_array()))
        return 0;
    }
  }
  Type type = operand.cadr(), numeric = c.sym.resolve_numeric_type(type);
  return type && !type.is_bitfield() && !(numeric && numeric.is_enum());
}

static List _parse_unary_op(Compiler c) {
  _x2c_complete_here(c, <expr>, %());
  Symbol op = c.peek(0);
  Token origin = c.token;
  if (op == <sizeof>) return _parse_sizeof(c);
  int increment = op in increments;
  if (!increment && !(op in unary_operators)) return _parse_postfix(c);
  c.next();
  List operand = increment ? _parse_unary_op(c) : _parse_cast(c);
  return c.resolve_expression(
    source_operator_expression(NULL, $(op, operand)), origin);
}

static List _parse_sizeof(Compiler c) {
  c.expect(<sizeof>);
  Token head = c.token;
  int parens = c.test(<(>);
  List arg = NULL, declaration = NULL;
  // `sizeof (T){...}` measures a compound literal, which parses as a cast
  if (parens && c.test_declaration() && head.after_group().type == <{>) {
    c.token = head;
    arg = _parse_cast(c);
  }
  else if (c.test_declaration()) {
    arg = declaration = c.parse_type_operand(NULL);
    if (parens) {
      c.expect(<)>);
      arg = %(parens $arg);
    }
  }
  else {
    c.token = head;
    arg = _parse_unary_op(c);
    match (arg) case %(expr ? (parens ?inner)): arg = %(parens $inner);
  }
  /* A template binds a typedef name where it expands, as a declaration
     does, so `sizeof` of one is typed there too. */
  int named = declaration && _casts_to_typedef_name(c, declaration);
  Type type = named ? %(<macro-expr>) : %("size_t");
  return %(expr $type (sizeof $arg));
}

/* `offsetof` names its member with a C member designator: a field, then
   any `.field` and `[index]` selections, kept as their C spelling. */
static List _parse_offsetof(Compiler c) {
  c.next();
  c.expect(<(>);
  Type type = c.parse_type_name();
  c.expect(<,>);
  List member = c.parse_basic_identifier();
  for (;;) {
    if (c.test(<.>))
      member = %(@member "." @(c.parse_basic_identifier()));
    else if (c.test(<[>)) {
      member = %(@member "[" $(c.parse_expression()) "]");
      c.expect(<]>);
    }
    else break;
  }
  c.expect(<)>);
  return %(expr ("size_t") (offsetof $type $member));
}

// postfix operators

static List _parse_postfix(Compiler c) =>
  _parse_postfix_tail(c, c.parse_primary());

static List _parse_postfix_tail(Compiler c, List expr) {
  while (_postfix_operator(c.peek(0))) {
    /* The operator makes what precedes it a receiver or a base, and neither
       is a destination, so a converter call noted before it never reaches
       one. */
    c.protocol_helpers.del("explicit-converter");
    switch (c.peek(0)) {
      case <[>:      expr = _parse_postfix_index(c, expr);   break;
      case <(>:      expr = _parse_postfix_apply(c, expr);   break;
      case <"->">:   expr = _parse_postfix_arrow(c, expr);   break;
      case <.>:      expr = _parse_postfix_dot(c, expr);     break;
      default:       expr = _parse_postfix_decinc(c, expr);  break;
    }
  }
  return expr;
}

static int _postfix_operator(Symbol token) {
  switch (token) {
    case <[>:
    case <(>:
    case <"->">:
    case <.>:
    case <++>:
    case <-->:
      return 1;
  }
  return 0;
}

static List _parse_postfix_index(Compiler c, List expr) {
  c.expect(<[>);
  if (c.test(<:>)) return _parse_slice(c, expr, NULL);
  List index = c.parse_expression();
  if (c.test(<:>)) return _parse_slice(c, expr, index);
  c.expect(<]>);
  return c.resolve_expression(%(expr () (index $expr $index)), c.token);
}

/* Called after the optional start index and first `:` of
   `expr[start:end:step]`. */
static List _parse_slice(Compiler c, List expr, List start) {
  List type = expr.cadr(), stop = NULL, step = NULL;
  if (c.test(<:>)) {
    if (c.peek(0) != <]>) step = c.parse_expression();
  }
  else if (c.peek(0) != <]>) {
    stop = c.parse_expression();
    if (c.test(<:>) && c.peek(0) != <]>) step = c.parse_expression();
  }
  if (step && step.match(
    %(expr ? $($source_literal_content(%(? "0"))))))
    $fail.expressions_slice_zero(c, c.token);
  c.expect(<]>);
  return %(expr $type $(source_slice_content(
    $(expr, start, stop, step))));
}

/** Parses an explicit List splice argument, or returns NULL without consuming
    an ordinary argument. Parentheses delimit a complete splice expression. */
List Compiler.parse_call_splice(Compiler c) {
  if (!c.test(<@>)) return NULL;
  List value;
  if (c.test(<(>)) {
    value = c.parse_expression();
    c.expect(<)>);
  }
  else value = c.parse_variable();
  return %(expr ("List") (splice $value));
}

static List _parse_postfix_apply(Compiler c, List expr) {
  Token origin = c.token;
  c.expect(<(>);
  Array arguments = [], notes = [];
  if (c.peek(0) == <)>) arguments.push(%(expr (void) ()));
  while (c.peek(0) != <)>) {
    List argument = c.try_parse_macro_slot(<argument>);
    if (!argument) argument = c.parse_call_splice();
    arguments.push(argument ? argument : c.parse_assignment());
    notes.push(c.protocol_helpers.getdefault("explicit-converter", %()));
    if (!c.test(<,>)) break;
  }
  c.expect(<)>);
  List supplied = arguments.list_free();
  if (c.sym.is_named_value_type(expr.cadr(), "Macro"))
    return _apply_macro_value(c, expr, supplied, origin);
  Macro called = $called;
  List result = c.resolve_expression(
    c.rebuild_expression(NULL, called(expr, supplied)), origin);
  int method = !!expr.match(
    %(expr () $($source_operator_content(%(. ? (?))))));
  _check_converter_args(c, result, method, notes.list_free());
  if (method && supplied === %((expr (void) ())))
    match (expr) case %(expr () $($source_operator_content(
        %(. ? (?name))))):
      _note_explicit_converter(c, result, name.str(), origin);
  return result;
}

/* Applies the Macro value `expr` to `supplied` argument expressions.
   Inside a template body the call is retained so the template can capture
   the value it applies; elsewhere it is an ordinary `Macro_apply` over the
   argument values. */
static List _apply_macro_value(
  Compiler c, List expr, List supplied, Token origin) {
  if (c.macro_holes)
    return %(expr (<macro-expr>) (tpl-call $expr (args @supplied)));
  List values = %(expr ("List") (nil));
  if (supplied === %((expr (void) ()))) supplied = NULL;
  foreach (List argument in supplied.reverse())
    values = %(expr ("List")
      (cons $(c.convert_expression(argument, %("Var"))) $values));
  List callee = c.resolve_expression(
    %(expr () (ident "Macro_apply")), origin);
  Macro called = $called;
  return c.resolve_expression(
    c.rebuild_expression(%("List"), called(callee, $(expr, values))),
    origin);
}

static List _parse_postfix_arrow(Compiler c, List expr) {
  Token origin = c.token;
  c.expect(<"->">);
  if (c.at_completion()) {
    List rows = c.postfix_completions(expr.cadr(), <"->">);
    raise %(replcomp (kind <members>) (rows $rows) (keywords ()));
  }
  List field = _parse_field_name(c, <"->">, expr);
  return c.resolve_expression(
    source_operator_expression(NULL, %(-> $expr $field)), origin);
}

static List _parse_postfix_dot(Compiler c, List expr) {
  Token origin = c.token;
  c.expect(<.>);
  if (c.at_completion()) {
    Type receiver = _is_raw_string_literal(expr)
                  ? %("String") : expr.cadr();
    List rows = c.postfix_completions(receiver, <.>);
    raise %(replcomp (kind <members>) (rows $rows) (keywords ()));
  }
  List field = _parse_field_name(c, <.>, expr);
  List result = source_operator_expression(NULL, %(. $expr $field));
  if (c.peek(0) != <(>)
    return c.resolve_expression(result, origin);
  // Allocate a method identity before parsing its arguments.
  (void) c.resolve_postfix_member(expr.cadr(), field, <.>, 1);
  return result;
}

static List _parse_field_name(Compiler c, Symbol op_sym, List lhs_opt) {
  c.require_input();
  List slot = c.try_parse_macro_member();
  if (slot) return $(slot);
  String field_name = c.token.text;
  if (!field_name || !field_name.is_identifier())
    $fail.expressions_member_ident(c, c.token, op_sym, lhs_opt);
  List field = $(field_name);
  c.next();
  return field;
}

static List _parse_postfix_decinc(Compiler c, List expr) {
  Token origin = c.token;
  Symbol op = c.peek(0);
  c.next();
  return c.resolve_expression(
    source_postfix_expression(NULL, $(op, expr)), origin);
}

// primary expressions

/** Parses one primary expression or expression-valued macro slot.
    Dispatch starts at `c.token` to the selected literal, identifier,
    grouping, or macro parser and leaves the token after that primary form.
*/
List Compiler.parse_primary(Compiler c) {
  c.require_input();
  _x2c_complete_here(c, <expr>, %());
  List slot = c.try_parse_macro_slot(<expression>);
  if (slot) return slot;
  switch (c.peek(0)) {
    case <lit-char*>:  return _parse_c_string_literals(c);
    case <$>:
      if (c.peek(1) == <!>) return c.parse_macro_quotation();
      if ((c.token + 1).type == <(>) return c.parse_evaluated_list();
      if ((c.token + 1).type == <"{">) return c.parse_evaluated_map();
      return c.try_parse_macro_expression();
    case <ident>:      return _parse_ident_primary(c);
    /* The keyword pass keeps `in` between tokens that can end and begin
       operands, as after a cast or a condition. An operand never begins
       with the operator, so here `in` is a name. */
    case <in>:        return c.parse_variable();
    case <"(">:       return _parse_parens(c);
    case <"{">:       return _parse_composite(c);
    case <[>:         return _parse_bracket_array(c);
    case <"%(">:      return c.parse_list_literal();
    case <"%<<">:     return c.parse_symbol_set_literal();
    case <"%[">:      return c.parse_array_literal();
    case <"%{">:      return c.parse_map_literal();
    case <"%\"">:     return c.parse_string_literal();
    case <"%!">:      return c.parse_lambda_literal();
  }
  return c.parse_atomic_literal();
}

static List _parse_ident_primary(Compiler c) {
  if (c.token.text == "macro" && c.peek(1) == <ident> &&
      c.peek(2) == <(>) {
    List definition = c.parse_macro_definition();
    /* Inside a template the value is made where the template expands, once
       the names its body shares with the template are that expansion's. */
    if (c.macro_holes) return %(expr ("Macro") (macro-value $definition));
    return c.capture_macro_value(definition);
  }
  /* An alias use is its parsed expression, already grouped as one operand,
     so `(name)` stays the only source spelling of a parenthesized name. */
  List alias = c.alias_expression();
  if (alias) {
    c.next();
    return alias;
  }
  List keyword = c.try_parse_macro_expression();
  if (keyword) return keyword;
  switch (c.token.text) {
    case "va_arg": return _parse_va_arg(c);
    case "_Generic": return _parse_generic(c);
    case "offsetof": return _parse_offsetof(c);
    case "_Alignof": return _parse_alignof(c);
  }
  return c.parse_variable();
}

static List _parse_alignof(Compiler c) {
  c.next();
  c.expect(<(>);
  int declaration = c.test_declaration();
  List operand = declaration ? c.parse_type_operand(NULL)
                             : c.parse_assignment();
  c.expect(<)>);
  int named = declaration && _casts_to_typedef_name(c, operand);
  Type type = named ? %(<macro-expr>) : %("size_t");
  return %(expr $type (call "_Alignof" (args $operand)));
}

/** Parses and resolves one complex identifier expression.
    Parsing starts at `c.token` and leaves it after the identifier.
*/
List Compiler.parse_variable(Compiler c) {
  Token origin = c.token;
  Var definition;
  // A macro defined to a string literal is that literal after preprocessing.
  if (c.object_macros.try_get(origin.text, definition) &&
      definition == <string>) {
    c.next();
    return _join_c_string_literals(
      c, %(expr (* char) (literal (* char) $(origin.text))));
  }
  List name = c.parse_complex_identifier();
  Token after = c.token;
  List result = c.resolve_expression(%(expr () (ident $name)), origin);
  if (c.source_facts) match (result)
    case %(expr ?type $($source_identifier_content(%(?binding)))):
      c.record_source_reference(binding, type, origin, after);
  if (c.source_map &&
      (origin.text == "__FILE__" || origin.text == "__LINE__"))
    match (result) case %(expr ?type ?content):
      return %(expr $type $(c.anchor_origin(content, origin)));
  return result;
}

static List _parse_c_string_literals(Compiler c) =>
  _join_c_string_literals(c, c.parse_atomic_literal());

/* Preserve each C token's escape boundary and the ordinary raw-string type.
   A macro defined to a string literal is one of the adjacent words, spelled
   as written, so the C preprocessor joins `printf("%" PRId64 "\n", x)`. */
static List _join_c_string_literals(Compiler c, List first) {
  if (c.peek(0) != <lit-char*> && !_string_word_follows(c)) return first;
  Array spellings = [];
  spellings.push(first.caddr().caddr());
  while (c.peek(0) == <lit-char*> || _string_word_follows(c)) {
    spellings.push(c.token.text);
    c.next();
  }
  String text = " ".join(spellings.list_free());
  return %(expr (* char) (literal (* char) $text));
}

/* A name adjacent to a C string literal is a preprocessor word: a macro this
   unit defines to a string literal, or a name it cannot resolve, as a
   header's `PRId64` is. `in` there is the membership operator. */
static int _string_word_follows(Compiler c) {
  if (c.peek(0) != <ident> || c.token.text == "in") return 0;
  Var definition;
  if (c.object_macros.try_get(c.token.text, definition))
    return definition == <string>;
  return !c.sym.get($(c.token.text));
}

static List _parse_parens(Compiler c) {
  c.expect(<(>);
  return _parse_group_rest(c);
}

/* Parses a group after its `(` through the closing `)`. */
static List _parse_group_rest(Compiler c) {
  if (_statement_expression_follows(c)) {
    Token origin = c.token;
    c.expect(<"{">);
    List block = c.parse_compound_statement();
    c.expect(<)>);
    return _statement_expression(c, block, origin);
  }
  List expr = c.parse_expression();
  c.expect(<)>);
  // C has no parenthesized brace; the brace converts at its destination.
  match (expr) case %(expr ? (composite ?)): return expr;
  List type = expr.cadr();
  return %(expr $type (parens $expr));
}

/* A brace after `(` opens a statement expression when a `;` stands at its
   top level. In a macro body, where a hole stands for a statement with no
   `;` of its own, a hole at the top level opens one too unless a comma
   makes the brace data; one datum states its type, as in `(T){ $x }`. Any
   other brace is a composite or Map literal. */
static int _statement_expression_follows(Compiler c) {
  if (c.peek(0) != <"{">) return 0;
  int hole = 0, comma = 0;
  for (Token token = Token.skip_trivia(c.token + 1);;
       token = token.after_group()) {
    Symbol type = token.type;
    if (type == <;>) return 1;
    if (type == <eof> || type == <"}">) return hole && !comma;
    if (type == <,>) comma = 1;
    if (c.macro_holes && (type == <$> || type == <@>))
      hole = 1;
  }
}

static List _parse_composite(Compiler c) {
  c.expect(<"{">);
  if (_brace_starts_map(c)) {
    List entries = c.parse_map_entries();
    c.expect(<"}">);
    return %(expr ("Map") (map @entries));
  }
  List elems = _parse_composite_elements(c);
  c.expect(<"}">);
  return %(expr () $(source_composite_content(elems)));
}

/* An entry that begins with a Map-entry macro, or whose first bracket-level
   `:` belongs to no conditional, makes a brace a Map literal. */
static int _brace_starts_map(Compiler c) {
  if (c.macro_starts_target_at(<map-entry>)) return 1;
  Token token = c.token;
  for (int conditionals = 0;; token = token.after_group()) {
    switch (token.type) {
      case <eof>: case <;>: case <,>: case <")">: case <]>: case <"}">:
        return 0;
      case <?>:
        conditionals++;
        break;
      case <:>:
        if (!conditionals--) return token != c.token;
    }
  }
}

/* A sequence hole splices initializer elements, as it splices call
   arguments; a meta call stays one element. */
static List _parse_composite_elements(Compiler c) {
  Array elements = [];
  while (c.peek(0) != <"}">) {
    List hole = c.peek_macro_hole();
    int sequence = c.peek(0) == <@> ||
                   (hole && hole.assoc(<sequence>).int());
    List element = sequence ? c.try_parse_macro_slot(<argument>) : NULL;
    if (!element)
      element =
        _test_dot_init(c) ||
        (c.peek(0) == <[> && _bracket_designates(c))
          ? _parse_designated_init(c)
          : c.parse_assignment();
    elements.push(element);
    if (!c.test(<,>)) break;
  }
  return elements.list_free();
}

/* A bracketed index followed by `=`, `.`, or `[` designates an element;
   any other bracket is an Array literal. */
static int _bracket_designates(Compiler c) {
  Symbol type = c.token.after_group().type;
  return type == <=> || type == <.> || type == <[>;
}

// Designator chains retain the canonical field/index initializer forms.
static int _test_dot_init(Compiler c) {
  Token token = c.token;
  return token.type == <.> &&
    Token.skip_trivia(token + 1).type == <ident>;
}

static List _parse_designated_init(Compiler c) {
  Symbol tag;
  List key;
  if (c.test(<.>)) {
    tag = <dotinit>;
    key = c.parse_basic_identifier();
  }
  else {
    c.expect(<[>);
    tag = <indexinit>;
    key = c.parse_assignment();
    c.expect(<]>);
  }
  List value;
  if (c.peek(0) == <.> || c.peek(0) == <[>)
    value = _parse_designated_init(c);
  else {
    c.expect(<=>);
    value = c.parse_assignment();
  }
  return $(tag, key, value);
}

static List _parse_bracket_array(Compiler c) {
  c.expect(<[>);
  Array elements = [];
  while (c.peek(0) != <]>) {
    elements.push(c.parse_assignment());
    if (!c.test(<,>)) break;
  }
  c.expect(<]>);
  return %(expr ("Array") (array @(elements.list_free())));
}

static List _parse_va_arg(Compiler c) {
  c.next();
  c.expect(<(>);
  List expr = c.parse_assignment();
  c.expect(<,>);
  Type type = NULL;
  List decl = c.parse_type_operand(&type);
  c.expect(<)>);
  expr = source_va_arg_content($(expr, decl));
  return %( expr $type $expr );
}

/* A C11 generic selection. An association names its type with
   `parse_type_name`, which covers specifiers, qualifiers, and pointers; a
   function-pointer or array association needs a typedef name. */
static List _parse_generic(Compiler c) {
  Token origin = c.token;
  c.next();
  c.expect(<(>);
  List control = c.parse_assignment();
  Array associations = [];
  while (c.test(<,>)) {
    Var type = c.test(<default>) ? <default> : c.parse_type_name();
    c.expect(<:>);
    associations.push(%(association $type $(c.parse_assignment())));
  }
  c.expect(<)>);
  List selection = source_generic_content(
    $(control, @(associations.list_free())));
  return c.resolve_expression(%(expr () $selection), origin);
}
