/*  expressions.x -- expression syntax and its resolution

    The parser reads expressions with C precedence and resolves each node as
    it builds it; constructed syntax enters the same resolver. Resolution
    gives a node its type and binding, and its last step converts the value
    to the type its destination declares. That conversion lives here; the
    walk of a brace initializer over its subobjects lives in
    `initializers.x`.
*/
#pragma once
$(import "../lib/private-keywords.xmacro")
#include "compiler.x"
#include "type.x"

/** A printf-family function: its name, the indexes of its format and first
    value arguments, and whether only a spelling no declaration resolves
    names it.
*/
typedef struct PrintfFn {
  const char *name, int fmt_arg, first_arg, unresolved;
} PrintfFn;

#pragma private
$(import "../src/grammar.xmacro")
#include "parse.x"
#include "literals.x"
#include "protocol.x"
#include "transform.x"
#include "stage.x"
#include "initializers.x"
#include "macros.x"

/* expression grammar

   Each parser entry consumes exactly its grammar level and leaves `c.token`
   at the first token that belongs to its caller. Each level resolves the
   nodes it builds, so higher levels receive typed or deferred nodes. */

/** Parses an assignment expression and any following comma expressions.
    A comma expression retains source order and takes the type of its final
    value. `c.token` stops at the first token outside the expression.
*/
List Compiler.parse_expression(Compiler c) =>
  c._parse_expression_tail(c.parse_assignment());

static List Compiler._parse_expression_tail(Compiler c, List expr) {
  if (c.peek(0) == <,>) {
    expr = cons(expr, c._parse_comma_list());
    List last = expr.last(), type = last.cadr();
    return %(expr $type ${source_commas_content(expr)});
  }
  return expr;
}

static List Compiler._parse_comma_list(Compiler c) {
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
  c._parse_assignment_tail(c.parse_conditional());

static List Compiler._parse_assignment_tail(Compiler c, List lhs) {
  Symbol op = c.peek(0);
  Token origin = c.token;
  if (!op.is_assignment_op()) return lhs;
  if (lhs.cadr().car() == <opt-ref>)
    c.report_error(
      <type>, "check optional reference before assigning its value",
      origin, NULL);
  List targets = op == <=> ? c._destructure_targets(lhs) : NULL;
  c.next();
  List rhs = c.parse_assignment();
  if (targets) match (rhs)
    case %(expr ?type ?): return %(expr $type (dstrasgn $targets $rhs));
  if (op == <=>) c.check_explicit_converter(rhs, lhs.cadr(), 0);
  return c.resolve_expression(
    source_operator_expression(NULL, %($op $lhs $rhs)), origin);
}

static List Compiler._destructure_targets(Compiler c, List lhs) {
  match (lhs)
    case %(expr ? ${$source_content_pattern($grouped, %(?target))}): {
      if (_destructure_identifier(target)) return %(targets $target);
      match (target)
        case %(expr ? ${$source_commas_content(%(*targets))}): {
          foreach (List entry, targets) {
            if (_destructure_identifier(entry)) continue;
            c.report_error(
              <parse>, "unsupported destructuring assignment target",
              c.token,
              %("destructuring targets must be simple identifiers"));
          }
          return %(targets @targets);
        }
    }
  return NULL;
}

static int _destructure_identifier(List expression) {
  match (expression) {
    case %(expr ? ${$source_identifier_content(%(?))}): return 1;
    case %(expr ? ${$source_content_pattern($grouped, %(?inner))}):
      match (inner)
        case %(expr ? ${$source_content_pattern(
          $dereferenced, %(?address))}):
          match (address) case %(expr (& *) ${$source_identifier_content(
              %(?))}): return 1;
  }
  return 0;
}

/** Parses a binary expression and its optional conditional tail.
    The false arm recurses at conditional precedence, making `?:`
    right-associative, and `c.token` stops after the expression.
*/
List Compiler.parse_conditional(Compiler c) =>
  c._parse_conditional_tail(c._parse_binary_ops());

static List Compiler._parse_conditional_tail(Compiler c, List condition) {
  Token origin = c.token;
  if (!c.test(<?>)) return condition;
  List ontrue = c.parse_expression();
  c.expect(<:>);
  return c.resolve_expression(source_operator_expression(
    NULL, %(? $condition $ontrue ${c.parse_conditional()})), origin);
}

static List Compiler._parse_binary_ops(Compiler c) =>
  c._parse_binary_level(1);

static List Compiler._parse_binary_level(Compiler c, int level) {
  if (level > 10) return c._parse_cast();
  return c._parse_binary_level_tail(level, c._parse_binary_level(level + 1));
}

static List Compiler._parse_binary_level_tail(
  Compiler c, int level, List lhs) {
  int first = 1;
  while (_precedence(c._binary_operator()) == level ||
         (level == 7 && c._is_type_operator())) {
    if (c._is_type_operator()) {
      lhs = c._parse_type_test(lhs);
      continue;
    }
    Symbol op = c._binary_operator();
    Token origin = c.token;
    c.next();
    List rhs = c._parse_binary_level(level + 1);
    if (first) {
      lhs = c.resolve_expression(lhs, origin);
      first = 0;
    }
    rhs = c.resolve_expression(rhs, origin);
    lhs = c._binary_expression(op, lhs, rhs, origin);
  }
  return lhs;
}

static List Compiler._parse_binary_levels_from(Compiler c, List lhs) {
  for (int level = 10; level > 0; level--)
    lhs = c._parse_binary_level_tail(level, lhs);
  return lhs;
}

/* Larger levels bind more tightly. The recursive parser descends to level 10
   before consuming operators while each level folds left; `is` shares the
   relational level but is recognized from its identifier spelling. */
static inline int _precedence(Symbol op) {
  switch (op) {
    case <||>:                 return 1;   // logical OR
    case <&&>:                 return 2;   // logical AND
    case <|>:                  return 3;   // bitwise OR
    case <^>:                  return 4;   // bitwise XOR
    case <&>:                  return 5;   // bitwise AND
    case <==>:   case <!=>:
    case <===>:  case <!==>:   return 6;   // equality
    case <"<">:  case <">">:   case <in>:
    case <"<=">: case <">=">:  return 7;   // relational
    case <"<<">: case <">>">:  return 8;   // shift
    case <+>:    case <->:     return 9;   // additive
    case <*>:    case </>:
    case <%>:    case <@>:     return 10;  // multiplicative
    default:                   return 0;
  }
}

/* The keyword pass leaves `in` a name where a neighbor could also be C, as
   before a bare `[` literal. No name follows a complete operand, so there
   it is the membership operator. */
static inline Symbol Compiler._binary_operator(Compiler c) =>
  c.at_word("in") ? <in> : c.peek(0);

static inline int Compiler._is_type_operator(Compiler c) => c.at_word("is");

/* `value is T` tests a Var tag; `value is selector` tests a Symbol. Either
   may be negated as `is not`. */
static List Compiler._parse_type_test(Compiler c, List lhs) {
  Token origin = c.token;
  c.next();
  int negate = c.take_word("not");
  List test;
  if (c._is_type_selector_start()) {
    Type target = c._parse_is_type(origin);
    Macro has_type = $has_type;
    test = c.resolve_expression(
      c.rebuild_expression(NULL, has_type(lhs, target)), origin);
  }
  else {
    List selector = c._parse_cast();
    Macro has_symbol = $has_symbol;
    test = c.resolve_expression(
      c.rebuild_expression(NULL, has_symbol(lhs, selector)), origin);
  }
  return negate ? c.resolve_expression(%(expr () (op ! $test)), origin)
                : test;
}

static int Compiler._is_type_selector_start(Compiler c) {
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
  return !c.sym.get(%($spelling));
}

static Type Compiler._parse_is_type(Compiler c, Token origin) {
  int parenthesized = c.test(<(>), Type type = c.parse_type_name();
  if (parenthesized) {
    if (c.peek(0) == <[>)
      c.report_error(
        <type>, "array type cannot be used after operator 'is'",
        origin, %("array types have no supported Var tag"));
    if (c.peek(0) == <(>)
      c.report_error(
        <type>, "function type cannot be used after operator 'is'",
        origin, %("function types have no supported Var tag"));
    c.expect(<)>);
  }
  else if (type.is_pointer())
    c.report_error(
      <parse>, "pointer type after 'is' must be parenthesized",
      origin, %("write value is (T *)"));
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
      case %((param ?type
                    (!set ?binding (bind () ?)))): {
        List declaration = %(decl $type (bindings $binding));
        List operand = c._parse_cast();
        List expression = %(expr $type (cast $declaration $operand));
        return c._finish_paren_statement(expression, 0);
      }
    c.expect(<=>);
    List source = c.parse_assignment();
    c.expect(<;>);
    return c.anchor_origin(
      %(dstrdecl (params @parameters) $source), origin);
  }

  List expression = c.parse_expression();
  c.expect(<)>);
  match (expression)
    case %(expr ?type ?):
      expression = %(expr $type (parens $expression));
  return c._finish_paren_statement(expression, 1);
}

static List Compiler._finish_paren_statement(
  Compiler c, List expression, int postfix) {
  if (postfix) expression = c._parse_postfix_tail(expression);
  expression = c._parse_binary_levels_from(expression);
  expression = c._parse_conditional_tail(expression);
  expression = c._parse_assignment_tail(expression);
  expression = c._parse_expression_tail(expression);
  c.expect(<;>);
  return %(stmnt $expression);
}

// casts and unary operators

static List Compiler._parse_cast(Compiler c) {
  Token head = c.token;
  if (c._cast_operand_after_parens() && c.test(<(>)) {
    if (c.test_declaration() ||
        c._macro_hole_starts_cast_type(head.after_group())) {
      List decl = c.parse_simple_declaration(), type = decl.type_from_ast();
      decl = %(decl @{decl.cdr()});
      c.expect(<)>);
      List expr = c._parse_cast();
      if (expr.cadr() === %(<macro-expr>) ||
          c._casts_to_template_typedef(decl))
        type = %(<macro-expr>);
      c._warn_unnecessary_cast(expr, type, head);
      return %(expr $type (cast $decl $expr));
    }
  }
  c.token = head;
  return c._parse_unary_op();
}

/** Parses one macro target through the cast-expression grammar.
    Parsing starts at `c.token` and leaves it at the first token after
    the target.
*/
List Compiler.parse_macro_expression_target(Compiler c) => c._parse_cast();

static int Compiler._cast_operand_after_parens(Compiler c) =>
  c.peek(0) == <"("> &&
  _cast_operand_follows(c.token.after_group().type);

static int Compiler._macro_hole_starts_cast_type(Compiler c, Token after) {
  if (!c.macro_holes || c.peek(0) != <$> ||
      c.peek(2) != <)>) return 0;
  List hole = c.peek_macro_hole();
  if (!hole) return 0;
  Symbol kind = hole.assoc(<kind>);
  if (kind && kind != <type>) return 0;
  /* `($items)[0]` subscripts the hole's value and `($key) in table` tests
     it; only a hole declared a type casts an array literal or a name `in`. */
  if ((after.type == <[> || after.text == "in") && kind != <type>) return 0;
  return _cast_operand_follows(after.type);
}

static int _cast_operand_follows(Symbol s) {
  switch (s) {
    case <ident>:
    case <in>:
    case <$>:
    case <"$(">:
    case <"(">:
    case <"{">:
    case <"%(">:
    case <"%<<">:
    case <[>:
    case <"%[">:
    case <"%{">:
    case <"%\"">:
    case <"%!">:
    case <lit-char>:
    case <lit-int>:
    case <lit-float>:
    case <lit-char*>:
    case <lit-atom>:
    case <lit-symbol>:
    case <void>:
    case <sizeof>:
    case <offsetof>:
    case <++>:
    case <-->:
    case <!>:
    case <~>:
    case <*>:
    case <&>:
    case <->:
    case <+>:
      return 1;
  }
  return 0;
}

/* A template typedef is named by the binding each expansion supplies, so a
   cast to it, qualified or not, is typed where the template expands. A
   template keeps aggregate tags as spellings, so only a typedef base ends in
   a binding. */
static int Compiler._casts_to_template_typedef(Compiler c, List declaration) {
  List base = declaration.cadr();
  return c.macro_holes && !!base.match(%(* (binding ? ?)));
}

/* A cast whose operand already has the cast type, qualifiers included,
   changes nothing. The comparison uses x2c's declared type, so a cast
   between a typedef and its C type stays silent, and only an operand whose
   C type x2c knows is compared: a pointer difference or a character
   constant is not. A `void` cast discards a value on purpose, and a cast of
   a C string literal is how source keeps the literal native where x2c would
   otherwise promote it to a `String`. */
static void Compiler._warn_unnecessary_cast(
  Compiler c, List operand, Type target, Token origin) {
  if (!target || target === %(void) || target === %(<macro-expr>) ||
      _expr_is_raw_string_literal(operand)) return;
  Type source = operand.cadr();
  if (!c._c_type_known(operand) || source.declared() != target.declared())
    return;
  c.report_warning(
    <conversion>,
    %"unnecessary conversion: the operand already has type ${target.repr()}",
    origin, %("remove the cast"));
}

/* Whether C gives an operand the type x2c records. A character constant is
   `int` in C; `sizeof`, `offsetof`, and a pointer difference have `size_t`
   and `ptrdiff_t` identities x2c does not model; an enum's compatible
   integer type is implementation-defined; and C compilers type a bitfield
   differently. */
static int Compiler._c_type_known(Compiler c, List operand) {
  match (operand) {
    case %(expr ? ${$source_content_pattern($grouped, %(?inner))}):
      return c._c_type_known(inner);
    case %(expr ? ${$source_literal_content(%((char) *))}): return 0;
    case %(expr ? ${$source_content_pattern(
        $sizeof_grouped, %(?operand))}): return 0;
    case %(expr ? ${$source_content_pattern(
        $sizeof_expression, %(?operand))}): return 0;
    case %(expr ? (offsetof *)): return 0;
    case %(expr ? ${$source_operator_content(
        %(- (expr ?left *) (expr ?right *)))}): {
      Type l = left, r = right;
      if ((l.is_pointer() || l.is_array()) && (r.is_pointer() || r.is_array()))
        return 0;
    }
  }
  Type type = operand.cadr(), numeric = c.sym.resolve_numeric_type(type);
  return type && !type.is_bitfield() && !(numeric && numeric.is_enum());
}

static List Compiler._parse_unary_op(Compiler c) {
  c.__complete_here(<expr>, %());
  Symbol op = c.peek(0);
  Token origin = c.token;
  if (op == <sizeof>) return c._parse_sizeof();
  if (op == <offsetof>) return c._parse_offsetof();
  if (op != <++> && op != <--> && op != <~> && op != <*> &&
      op != <&> && op != <-> && op != <+> && op != <!>)
    return c._parse_postfix();
  c.next();
  List operand = op == <++> || op == <--> || op == <~>
               ? c._parse_unary_op() : c._parse_cast();
  return c.resolve_expression(
    source_operator_expression(NULL, %($op $operand)), origin);
}

static List Compiler._parse_sizeof(Compiler c) {
  c.expect(<sizeof>);
  int parens = c.test(<(>);
  Token head = c.token;
  List arg = NULL;
  if (c.test_declaration()) {
    arg = c.parse_simple_declaration();
    arg = cons(<decl>, arg.cdr());
  }
  // `sizeof(x + 1)` measures any expression; only `sizeof x` is unary.
  else if (parens) arg = c.parse_expression();
  else {
    c.token = head;
    arg = c._parse_unary_op();
  }
  if (parens) {
    c.expect(<)>);
    arg = %(parens $arg);
  }
  return %(expr (unsigned) (sizeof $arg));
}

static List Compiler._parse_offsetof(Compiler c) {
  c.expect(<offsetof>);
  c.expect(<(>);
  List type = c.parse_simple_declaration();
  c.expect(<,>);
  List field = c.parse_basic_identifier();
  c.expect(<)>);
  return %(expr (unsigned) (offsetof $type $field));
}

// postfix operators

static List Compiler._parse_postfix(Compiler c) =>
  c._parse_postfix_tail(c.parse_primary());

static List Compiler._parse_postfix_tail(Compiler c, List expr) {
  while (_postfix_operator(c.peek(0))) {
    /* The operator makes what precedes it a receiver or a base, and neither
       is a destination, so a converter call noted before it never reaches
       one. */
    c.protocol_helpers.del("explicit-converter");
    switch (c.peek(0)) {
      case <[>:      expr = c._parse_postfix_index(expr);   break;
      case <(>:      expr = c._parse_postfix_apply(expr);   break;
      case <"->">:   expr = c._parse_postfix_arrow(expr);   break;
      case <.>:      expr = c._parse_postfix_dot(expr);     break;
      default:       expr = c._parse_postfix_decinc(expr);  break;
    }
  }
  return expr;
}

/* The operators that apply to the expression written before them. */
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

static List Compiler._parse_postfix_index(Compiler c, List expr) {
  c.expect(<[>);
  if (c.test(<:>)) return c._parse_slice(expr, NULL);
  List index = c.parse_expression();
  if (c.test(<:>)) return c._parse_slice(expr, index);
  c.expect(<]>);
  return c.resolve_expression(%(expr () (index $expr $index)), c.token);
}

/* Called after the optional start index and first `:` of
   `expr[start:end:step]`. */
static List Compiler._parse_slice(Compiler c, List expr, List start) {
  List type = expr.cadr(), stop = NULL, step = NULL;
  if (c.test(<:>)) {
    if (c.peek(0) != <]>) step = c.parse_expression();
  }
  else if (c.peek(0) != <]>) {
    stop = c.parse_expression();
    if (c.test(<:>) && c.peek(0) != <]>) step = c.parse_expression();
  }
  if (step && step.match(%(expr ?
      ${$source_literal_content(%(? "0"))})))
    c.report_error(<parse>, "slice step cannot be zero", c.token, %());
  c.expect(<]>);
  return %(expr $type ${source_slice_content(
    %($expr $start $stop $step))});
}

static List Compiler._parse_postfix_apply(Compiler c, List expr) {
  Token origin = c.token;
  c.expect(<(>);
  Array arguments = [], notes = [];
  if (c.peek(0) == <)>) arguments.push(%(expr (void) ()));
  while (c.peek(0) != <)>) {
    List argument = c.try_parse_macro_slot(<argument>);
    arguments.push(argument ? argument : c.parse_assignment());
    notes.push(c.protocol_helpers.getdefault("explicit-converter", %()));
    if (!c.test(<,>)) break;
  }
  c.expect(<)>);
  List supplied = arguments.list_free();
  if (c.sym.is_named_value_type(expr.cadr(), "Macro"))
    return c._apply_macro_value(expr, supplied, origin);
  Macro called = $called;
  List result = c.resolve_expression(
    c.rebuild_expression(NULL, called(expr, supplied)), origin);
  int method = !!expr.match(%(expr () ${$source_operator_content(
    %(. ? (?)))}));
  c._check_converter_args(result, method, notes.list_free());
  if (method && supplied === %((expr (void) ())))
    match (expr) case %(expr () ${$source_operator_content(
        %(. ? (?name)))}):
      c._note_explicit_converter(result, name.str(), origin);
  return result;
}

/* Calling a Macro value builds code. Inside a template body the call is
   retained so the template can capture the value it applies; elsewhere it
   is an ordinary `Macro_apply` over the argument values. */
static List Compiler._apply_macro_value(
  Compiler c, List expr, List supplied, Token origin) {
  if (c.macro_holes)
    return %(expr (<macro-expr>) (tpl-call $expr (args @supplied)));
  List values = %(expr ("List") (nil));
  if (supplied === %((expr (void) ()))) supplied = NULL;
  foreach (List argument, supplied.reverse())
    values = %(expr ("List")
      (cons ${c.convert_expression(argument, %("Var"))} $values));
  List callee = c.resolve_expression(
    %(expr () (ident "Macro_apply")), origin);
  Macro called = $called;
  return c.resolve_expression(
    c.rebuild_expression(%("List"), called(callee, %($expr $values))),
    origin);
}

static List Compiler._parse_postfix_arrow(Compiler c, List expr) {
  Token origin = c.token;
  c.expect(<"->">);
  if (c.at_completion()) {
    List rows = c.postfix_completions(expr.cadr(), <"->">);
    raise %(replcomp (kind <members>) (rows $rows) (keywords ()));
  }
  List field = c._parse_field_name(<"->">, expr);
  return c.resolve_expression(
    source_operator_expression(NULL, %(-> $expr $field)), origin);
}

static List Compiler._parse_postfix_dot(Compiler c, List expr) {
  Token origin = c.token;
  c.expect(<.>);
  if (c.at_completion()) {
    Type receiver = _expr_is_raw_string_literal(expr)
                  ? %("String") : expr.cadr();
    List rows = c.postfix_completions(receiver, <.>);
    raise %(replcomp (kind <members>) (rows $rows) (keywords ()));
  }
  List field = c._parse_field_name(<.>, expr);
  List result = source_operator_expression(NULL, %(. $expr $field));
  if (c.peek(0) != <(>)
    return c.resolve_expression(result, origin);
  // Allocate a method identity before parsing its arguments.
  (void) c.resolve_postfix_member(expr.cadr(), field, <.>, 1);
  return result;
}

static List Compiler._parse_field_name(
  Compiler c, Symbol op_sym, List lhs_opt) {
  c.require_input();
  List slot = c.try_parse_macro_member();
  if (slot) return %($slot);
  String field_name = c.token.text;
  if (!field_name || !field_name.is_identifier()) {
    List notes = %("token:" ${c.token.text});
    if (lhs_opt) notes = cons(%("lhs expr:" ${lhs_opt.str()}), notes);
    String msg = %"expected identifier after '$op_sym'";
    c.report_error(<parse>, msg, c.token, notes);
  }
  List field = %( $field_name );
  c.next();
  return field;
}

static List Compiler._parse_postfix_decinc(Compiler c, List expr) {
  Token origin = c.token;
  Symbol op = c.peek(0);
  c.next();
  return c.resolve_expression(
    source_postfix_expression(NULL, %($op $expr)), origin);
}

// primary expressions

/** Parses one primary expression or expression-valued macro slot.
    Dispatch starts at `c.token` to the selected literal, identifier,
    grouping, or macro parser and leaves the token after that primary form.
*/
List Compiler.parse_primary(Compiler c) {
  c.require_input();
  c.__complete_here(<expr>, %());
  List slot = c.try_parse_macro_slot(<expression>);
  if (slot) return slot;
  switch (c.peek(0)) {
    case <"$(">: return c.parse_macro_lisp_expression();
    case <lit-char*>:  return c._parse_c_string_literals();
    case <$>:          return c.try_parse_macro_expression();
    case <ident>:      return c._parse_ident_primary();
    /* The keyword pass keeps `in` between tokens that can end and begin
       operands, as after a cast or a condition. An operand never begins
       with the operator, so here `in` is a name. */
    case <in>:        return c.parse_variable();
    case <"(">:       return c._parse_parens();
    case <"{">:       return c._parse_composite();
    case <[>:         return c._parse_bracket_array();
    case <"%(">:      return c.parse_list_literal();
    case <"%<<">:     return c.parse_symbol_set_literal();
    case <"%[">:      return c.parse_array_literal();
    case <"%{">:      return c.parse_map_literal();
    case <"%\"">:     return c.parse_string_literal();
    case <"%!">:      return c.parse_lambda_literal();
  }
  return c.parse_atomic_literal();
}

static List Compiler._parse_ident_primary(Compiler c) {
  if (c.token.text == "macro" && c.peek(1) == <ident> &&
      c.peek(2) == <(>) {
    List definition = c.parse_macro_definition();
    foreach (Var captured, definition.assoc(<captures>).list())
      c.semantic_binding_facts()[
        %(local-macro-capture $captured)] = 1;
    return c.capture_macro_value(definition);
  }
  List binding = c.with_binding();
  Var stored;
  if (binding && c.semantic_binding_facts().try_get(
    %(with $binding), stored)) {
    List expression = stored;
    c.next();
    match (expression)
      case %(expr ?type ?): return %(expr $type (parens $expression));
  }
  List keyword = c.try_parse_macro_expression();
  if (keyword) return keyword;
  if (c.token.text == "va_arg") return c._parse_va_arg();
  if (c.token.text == "_Generic") return c._parse_generic();
  return c.parse_variable();
}

/** Parses and resolves one complex identifier expression.
    Parsing starts at `c.token` and leaves it after the identifier.
*/
List Compiler.parse_variable(Compiler c) {
  Token origin = c.token;
  Var definition;
  // A macro defined to a string literal is that literal after preprocessing.
  if (c.object_macros.try_get(origin.text, definition) &&
      definition.equal(<string>)) {
    c.next();
    return c._join_c_string_literals(
      %(expr (* char) (literal (* char) ${origin.text})));
  }
  List name = c.parse_complex_identifier();
  Token after = c.token;
  List result = c.resolve_expression(%(expr () (ident $name)), origin);
  if (c.source_facts) match (result)
    case %(expr ?type ${$source_identifier_content(%(?binding))}):
      c.record_source_reference(binding, type, origin, after);
  if (c.source_map &&
      (origin.text == "__FILE__" || origin.text == "__LINE__"))
    match (result) case %(expr ?type ?content):
      return %(expr $type ${c.anchor_origin(content, origin)});
  return result;
}

static List Compiler._parse_c_string_literals(Compiler c) =>
  c._join_c_string_literals(c.parse_atomic_literal());

/* Preserve each C token's escape boundary and the ordinary raw-string type.
   A macro defined to a string literal is one of the adjacent words, spelled
   as written, so the C preprocessor joins `printf("%" PRId64 "\n", x)`. */
static List Compiler._join_c_string_literals(Compiler c, List first) {
  if (c.peek(0) != <lit-char*> && !c._string_word_follows()) return first;
  Array spellings = [];
  spellings.push(first.caddr().caddr());
  while (c.peek(0) == <lit-char*> || c._string_word_follows()) {
    spellings.push(c.token.text);
    c.next();
  }
  String text = " ".join(spellings.list_free());
  return %(expr (* char) (literal (* char) $text));
}

/* A name adjacent to a C string literal is a preprocessor word: a macro this
   unit defines to a string literal, or a name it cannot resolve, as a
   header's `PRId64` is. `in` there is the membership operator. */
static int Compiler._string_word_follows(Compiler c) {
  if (c.peek(0) != <ident> || c.token.text == "in") return 0;
  Var definition;
  if (c.object_macros.try_get(c.token.text, definition))
    return definition.equal(<string>);
  return !c.sym.get(%(${c.token.text}));
}

static List Compiler._parse_parens(Compiler c) {
  c.expect(<(>);
  List expr = c.parse_expression();
  c.expect(<)>);
  List type = expr.cadr();
  return %(expr $type (parens $expr));
}

static List Compiler._parse_composite(Compiler c) {
  c.expect(<"{">);
  if (c._brace_starts_map()) {
    List entries = c.parse_map_entries();
    c.expect(<"}">);
    return %(expr ("Map") (map @entries));
  }
  List elems = c._parse_composite_elements();
  elems = %( commas @elems );
  c.expect(<"}">);
  return %(expr () ( composite $elems ));
}

/* An entry that begins with a Map-entry macro, or whose first bracket-level
   `:` belongs to no conditional, makes a brace a Map literal. */
static int Compiler._brace_starts_map(Compiler c) {
  if (c.macro_starts_target_at(AST_MAP_ENTRY)) return 1;
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

static List Compiler._parse_composite_elements(Compiler c) {
  Array elements = [];
  while (c.peek(0) != <"}">) {
    List element =
      c._test_dot_init() ||
      (c.peek(0) == <[> && c._bracket_designates())
        ? c._parse_designated_init()
        : c.parse_assignment();
    elements.push(element);
    if (!c.test(<,>)) break;
  }
  return elements.list_free();
}

/* A bracketed index followed by `=`, `.`, or `[` designates an element;
   any other bracket is an Array literal. */
static int Compiler._bracket_designates(Compiler c) {
  Symbol type = c.token.after_group().type;
  return type == <=> || type == <.> || type == <[>;
}

// Designator chains retain the canonical field/index initializer forms.
static int Compiler._test_dot_init(Compiler c) {
  Token token = c.token;
  return token.type == <.> &&
    Token.skip_trivia(token + 1).type == <ident>;
}

static List Compiler._parse_designated_init(Compiler c) {
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
    value = c._parse_designated_init();
  else {
    c.expect(<=>);
    value = c.parse_assignment();
  }
  return %($tag $key $value);
}

static List Compiler._parse_bracket_array(Compiler c) {
  c.expect(<[>);
  Array elements = [];
  while (c.peek(0) != <]>) {
    elements.push(c.parse_assignment());
    if (!c.test(<,>)) break;
  }
  c.expect(<]>);
  return %(expr ("Array") (array @{elements.list_free()}));
}

static List Compiler._parse_va_arg(Compiler c) {
  c.next();
  c.expect(<(>);
  List expr = c.parse_assignment();
  c.expect(<,>);
  List decl = c.parse_simple_declaration(), type = decl.type_from_ast();
  decl = %( decl @{ decl.cdr() } );
  c.expect(<)>);
  expr = source_va_arg_content(%($expr $decl));
  return %( expr $type $expr );
}

/* A C11 generic selection. An association names its type with
   `parse_type_name`, which covers specifiers, qualifiers, and pointers; a
   function-pointer or array association needs a typedef name. */
static List Compiler._parse_generic(Compiler c) {
  Token origin = c.token;
  c.next();
  c.expect(<(>);
  List control = c.parse_assignment();
  Array associations = [];
  while (c.test(<,>)) {
    Var type = c.test(<default>) ? <default> : c.parse_type_name();
    c.expect(<:>);
    associations.push(%(association $type ${c.parse_assignment()}));
  }
  c.expect(<)>);
  List selection = source_generic_content(
    %($control @{associations.list_free()}));
  return c.resolve_expression(%(expr () $selection), origin);
}

/* expression resolution

   Parsed source and constructed syntax enter the same resolver, which
   dispatches on a node's content. */

/** Resolves and type-annotates one expression AST in current compiler state.
    Existing `expr` type annotations are resolved semantic types.
    Already-resolved trees without unresolved descendants and non-expression
    inputs are returned unchanged; abstract declarations use the declaration
    binder. `origin` anchors diagnostics and generated operations that must
    retain source position.
*/
List Compiler.resolve_expression(Compiler c, List input, Token origin) {
  if (c.macro_application) {
    Var staged;
    int retained;
    Var carrier = input;
    match (input) case %(expr (<macro-expr>) ?inside): carrier = inside;
    if (c.take_code_value(carrier, staged, retained))
      return retained ? staged : c.resolve_expression(staged, origin);
  }
  match (input) {
    case %(decl *):
      return c.bind_syntax(input, AST_BLOCK, c.return_type);
    case %(expr ?type ?(List content)): {
      if (type && !c._needs_resolution(input)) return input;
      return c._resolve_content(input, type, content, origin);
    }
  }
  return input;
}

static int Compiler._needs_resolution(Compiler c, Var value) {
  // The scan is an any-search; a worklist keeps deep operator chains from
  // costing one C frame per nesting level.
  Array pending = $auto([]);
  Macro lambda = $lambda_expression, captured = $lambda_captured;
  pending.push(value);
  while (pending.len()) {
    Var current = pending.take_last();
    if (current is not <list>) continue;
    List syntax = current;
    match (syntax) {
      case %(expr (? *) (parens (block *))): continue;
      case %(expr (!or () (<macro-expr>)) ?): return 1;
      case captured(?body, *captures, *params): {
        foreach (List row, captures)
          match (row) case %(capture ?binding ? ?):
            if (!c.semantic_binding_facts().contains(
              %(lambda-depth $binding))) return 1;
        continue;
      }
      case lambda(?body, *params): return 1;
      case %(at m-origin ?):
        if (c.source_map && !c.macro_holes) return 1;
      case %((!or macro-bind macro-invoke macro-slot meta-call) *): return 1;
      case $source_identifier_content(%(?name)):
        if (name is <list>) {
          List binding = name;
          if (c._identifier_needs_resolution(binding)) return 1;
        }
        else return 1;
      // A Type hole can supply declarators with the base they bind to.
      case %(decl ?(List base) *):
        if (base.type().declaration_parts().cadr()) return 1;
    }
    foreach (Var child, syntax)
      if (child is <list>) pending.push(child);
  }
  return 0;
}

static int Compiler._identifier_needs_resolution(
  Compiler c, List binding) {
  String spelling = binding_identity_spelling(binding);
  Map facts = c.semantic_binding_facts();
  int retained_parameter = %(lambda-param $binding) in facts;
  int retained_capture = %(lambda-depth $binding) in facts;
  if (c.lambda_capture_required(binding)) return 1;
  if (retained_parameter &&
      (c.local_macro_captures != NULL ||
       %(local-macro-capture $binding) in facts))
    return 1;
  return !spelling ||
    (c.sym.lookup(%($spelling), NULL) != binding &&
     !retained_parameter && !retained_capture);
}

// True when a receiver's type must wait for macro substitution.
static int _deferred_receiver(List expr) {
  match (expr) case %(expr (<macro-expr>) ?): return 1;
  return 0;
}

static List Compiler._resolve_content(
  Compiler c, List input, Type input_type, List content, Token origin) {
  Macro lambda = $lambda_expression, captured = $lambda_captured;
  match (input) {
    case captured(?body, *captures, *params):
      return c._resolve_lambda(input, input_type, body, captures, params);
    case lambda(?body, *params):
      return c._resolve_lambda(input, input_type, body, NULL, params);
  }
  // Source-form cases examine input through origin and source wrappers.
  if (content && (content.car() == <at> || content.car() == <src>))
    return c._resolve_source(input, input_type, content);
  if (content && content.car() == <expr>)
    match (content) case %(!set ?inner (expr ? ?)):
      return c.resolve_expression(inner, origin);
  Macro indexed = $indexed;
  match (input) case indexed(?receiver, ?selector):
    return c._resolve_indexed(receiver, selector, origin);
  match (content) case %(call ?(String callee) (args *supplied)):
    return c._resolve_native_call(input_type, callee, supplied, origin);
  Macro called = $called;
  match (input) case called(?callee, *supplied):
    return c._resolve_call(input_type, callee, supplied, origin);
  match (content) {
    case %(managed-init ?initializer):
      return c._resolve_managed_init(initializer, origin);
    case $source_identifier_content(%(?value)):
      return c._resolve_identifier(value, input_type, origin);
    case %(!set ?binding (binding ? ?)):
      if (binding_identity_try_parts(binding, NULL, NULL))
        return c._resolve_identifier(binding, input_type, origin);
    case $source_literal_content(%(*)): return input;
    case %(tpl-call *): return input;
    case %(meta-call ?callee (args *arguments)):
      return c._resolve_meta_call(input, origin);
    case %(meta-cap *): return input;
    case %(macro-invoke ?definition ?arguments ?invocation):
      return c._resolve_invocation(input, definition, arguments, invocation);
    case %(macro-slot ? ? *):
      return c._resolve_macro_slot(input, content, origin);
    case $source_string_content(%(*items)):
      return c._resolve_segments(items, origin);
    case %(cons ?head ?tail):
      return c._resolve_cons(input_type, head, tail, origin);
    case %(append ?head ?tail):
      return c._resolve_append(input_type, head, tail, origin);
    case $source_slice_content(%(? ? ? ?)):
      return c._resolve_slice(input_type, content, origin);
    case %(getindex ?receiver ?selector):
      return c._resolve_getindex(input_type, receiver, selector, origin);
    case %(dstrasgn (targets *targets) ?source):
      return c._resolve_destructure(targets, source, origin);
    case $source_content_pattern($sizeof_grouped, %(?argument)):
      return c._resolve_sizeof(input, $sizeof_grouped, argument, origin);
    case $source_content_pattern($sizeof_expression, %(?argument)):
      return c._resolve_sizeof(input, $sizeof_expression, argument, origin);
    case $source_generic_content(%(?control *associations)):
      return c._resolve_generic(control, associations, origin);
    case $source_va_arg_content(%(?argument ?declaration)):
      return c._resolve_va_arg(input_type, argument, declaration, origin);
    case $source_commas_content(%(*expressions)):
      return c._resolve_commas(input_type, expressions, origin);
    case %(splice ?expression):
      return c._resolve_splice(input_type, expression, origin);
    case %((!or offsetof nil cache macro-bind) *): return input;
    case $source_content_pattern($grouped, %(?inner)):
      return c._resolve_parens(inner, origin);
    case %(initval *choices):
      return c._resolve_initval(input_type, content, origin);
    case $source_composite_content(%(*elements)):
      return c._resolve_composite(input_type, elements, origin);
    case $source_cast_content(
        %((!set ?declaration (decl *)) ?operand)):
      return c._resolve_cast(declaration, operand, origin);
    case %(type-tag ?target):
      return c.var_tag_expression(target, origin);
    case $source_content_pattern($has_type, %(?operand ?target_syntax)):
      return c._resolve_is_type(operand, target_syntax, origin);
    case $source_content_pattern($has_symbol, %(?operand ?selector)):
      return c._resolve_is_symbol(operand, selector, origin);
    case $source_operator_content(
        %((!or (!set ?operator .) (!set ?operator (!quote ->)))
          ?receiver (!set ?field (*)))):
      return c._resolve_member(operator, receiver, field, origin);
    case $source_operator_content(%(?operator ?operand)):
      return c._resolve_unary(operator, operand, origin);
    case $source_operator_content(
        %(?operator ?condition ?ontrue ?onfalse)):
      return c._resolve_conditional(
        operator, condition, ontrue, onfalse, origin);
    case $source_operator_content(%(?operator ?left ?right)):
      return c._resolve_binary(operator, left, right, origin);
    case $source_postfix_content(%(?operator ?operand)):
      return c._resolve_postfix_op(operator, operand, origin);
    case %(tadapt ?target ?source):
      return c._resolve_tadapt(target, source, origin);
  }
  if (content && content.car() == <array>)
    return c._resolve_array_value(input, input_type, origin);
  if (content && content.car() == <map>)
    return c._resolve_map_value(input, input_type, origin);
  return input;
}

static List Compiler._resolve_lambda(
  Compiler c, List input, Type input_type, List body,
  List captures, List params) {
  if (c.macro_holes) return input;
  return c.bind_lambda_expression(
    input_type, %(params @params), captures, body);
}

static List Compiler._resolve_source(
  Compiler c, List input, Type input_type, List content) {
  match (content) case %(at m-origin ?inner): {
    if (!c.source_map || c.macro_holes) return input;
    return %(expr $input_type (at ${c.origin} $inner));
  }
  return input;
}

static List Compiler._resolve_meta_call(
  Compiler c, List input, Token origin) {
  if (c.meta_body || c.macro_holes) return input;
  return c.evaluate_meta_expression(input, origin);
}

static List Compiler._resolve_invocation(
  Compiler c, List input, Var definition, List arguments,
  Var invocation) {
  Token site = c.macro_invocation_site(invocation);
  if (!site) return input;
  return c.expand_macro_invocation_node(
    definition, arguments, site, AST_EXPRESSION);
}

static List Compiler._resolve_macro_slot(
  Compiler c, List input, List content, Token origin) {
  if (c.macro_holes) return input;
  Var value = c.evaluate_macro_slot(content);
  match (value)
    case %(!set ?expression (expr ? ?)):
      return c.resolve_expression(expression, origin);
  return c.resolve_expression(
    c.lift_macro_lisp_expression(value, origin), origin);
}

// identifiers

static List Compiler._resolve_identifier(
  Compiler c, Var value, Type type, Token origin) {
  if (type === %(<macro-expr>)) type = NULL;
  int read_reference = !type;
  int require_type = 0;
  List binding = c._identifier_binding(value, type, origin, require_type);
  int macro_binder = value.is_binder() ||
    (value is <list> && !value.is_nil() &&
     value.car() == <macro-bind>);
  if (!binding && macro_binder) return %(expr (<macro-expr>) (ident $value));
  Map binding_facts = c.semantic_binding_facts();
  String spelling = binding_identity_spelling(binding);
  c._capture_identifier(binding);
  c._shadow_identifier(binding, type, spelling, binding_facts);
  if (!type) type = c._identifier_type(
    binding, spelling, binding_facts, origin);
  if (!type && require_type)
    c.report_error(
      <type>, %"identifier ${value.repr()} has no semantic type",
      origin, NULL);
  List result = %(expr $type (ident $binding));
  if (c.lambda_scopes && !c.macro_holes) {
    result = c.capture_lambda_identifier(binding, type);
    match (result)
      case %(expr ?captured_type ${$source_identifier_content(
          %(?captured))}): {
        if (type.car() != <&> && captured_type.car() == <&>)
          read_reference = 1;
        type = captured_type;
        binding = captured;
      }
  }
  return c._read_bound_reference(
    result, binding, type, read_reference, binding_facts);
}

/* Parsed identifiers arrive as spellings, while constructed syntax may carry
   producer-issued binding identities. Semantic binding facts validate those
   identities before resolution. A visible local replaces a stale local
   identity; global shadow handling instead gives the visible declaration an
   emitted alias so the original identity keeps its meaning. */
static List Compiler._identifier_binding(
  Compiler c, Var value, Type &type, Token origin, int &require_type) {
  require_type = value is <string>;
  if (value is <string>) return c.sym.reference(%($value), type);
  if (value is not <list>) return NULL;
  List name = value;
  int identity = 0;
  String spelling = NULL;
  if (binding_identity_try_parts(name, identity, spelling)) {
    Var issued;
    if (!c.semantic_binding_facts().try_get(
      %(known $identity), issued) ||
        issued is not <string> || !issued.string().equal(spelling))
      c.report_error(
        <type>, "identifier has an unknown binding identity",
        origin, %("binding: ${name.repr()}"));
    return name;
  }
  match (name) {
    case %("x2c.ident" ?(String spelling)): {
      require_type = 1;
      return c.sym.reference(%($spelling), type);
    }
    case %((!is ? type string)):
      return c.sym.reference(name, type);
  }
  return NULL;
}

static void Compiler._capture_identifier(Compiler c, List binding) {
  if (c.local_macro_captures == NULL || !binding ||
      !c.sym.binding_is_local_before(
        binding, c.local_macro_capture_scopes) ||
      c.local_macro_captures.contains(binding)) return;
  Var order = c.local_macro_captures[<order>];
  c.local_macro_captures[<order>] = cons(
    binding, order is <list> ? order : NULL);
  c.local_macro_captures[binding] = 1;
}

static void Compiler._shadow_identifier(
  Compiler c, List &binding, Type type, String spelling,
  Map binding_facts) {
  if (!spelling) return;
  Type visible_type = NULL;
  List visible = c.sym.lookup(%($spelling), visible_type);
  if (!visible || visible == binding) return;
  if (%(local-macro-capture $binding) in binding_facts) {
    if (!binding_facts.contains(%(emitted $visible)))
      binding_facts[%(emitted $visible)] = c.fresh_name("binding_shadow");
  }
  else if (c.sym.binding_is_local(binding) &&
           !binding_facts.contains(%(lambda-depth $binding)))
    binding = visible;
  else if (visible_type &&
           (!type || c.sym.resolve_global(%($spelling), NULL)) &&
           !binding_facts.contains(%(emitted $visible)))
    binding_facts[%(emitted $visible)] = c.fresh_name("binding_shadow");
}

static Type Compiler._identifier_type(
  Compiler c, List binding, String spelling, Map facts, Token origin) {
  Var stored;
  if (facts.try_get(%(type $binding), stored) && stored is <list>)
    return stored;
  if (!spelling) return NULL;
  Type type = c.sym.get(%($spelling));
  if (!type) c._check_unit_static(spelling, origin);
  return type;
}

/* A `static` function belongs to the file that defines it, so an including
   unit replays a marker row naming that file instead of a declaration.
   Reporting the reference here names the function and its file, where C
   would otherwise report only an undefined symbol at link time. A macro body
   is the defining library's own syntax, bound wherever it expands, so only a
   reference written in an `.x` unit is reported. */
static void Compiler._check_unit_static(
  Compiler c, String spelling, Token origin) {
  if (!is_source_file(c.filename)) return;
  List owner = c.sym.get(%("unit-static" $spelling));
  if (!owner) return;
  String file = c.display_path(home_absolute_path(owner.car()));
  c.report_error(
    <type>, %"'$spelling' is a static function private to its unit", origin,
    %("it is defined in '$file';"
      "remove 'static' so other units can call it"));
}

static List Compiler._read_bound_reference(
  Compiler c, List result, List binding, Type type,
  int read_reference, Map binding_facts) {
  if (!read_reference ||
      !(%(reference-param $binding) in binding_facts)) return result;
  if (%(optional-reference-param $binding) in binding_facts &&
      !(binding in c.present_references())) return result;
  Type value_type = cdr(type);
  return %(expr $value_type
           (parens (expr $value_type (op * $result))));
}

static int Compiler._expression_is_addressable(Compiler c, List expression) {
  match (expression) {
    case %(expr ? ${$source_identifier_content(%(?binding))}):
      return !c.semantic_binding_facts().contains(%(lambda-snapshot $binding));
    case %(expr ? ${$source_content_pattern(
        $indexed, %(?receiver ?selector))}): return 1;
    case %(expr ? ${$source_operator_content(
        %((!quote *) ?operand))}): return 1;
    case %(expr ? ${$source_operator_content(
        %((!quote ->) ?receiver ?field))}): return 1;
    case %(expr ? ${$source_content_pattern($grouped, %(?base))}):
      return c._expression_is_addressable(base);
    case %(expr ? ${$source_operator_content(%(. ?base ?))}):
      return c._expression_is_addressable(base);
  }
  return 0;
}

// indexing and slices

static List Compiler._resolve_indexed(
  Compiler c, List receiver, List selector, Token origin) {
  receiver = c.resolve_expression(receiver, origin);
  selector = c.resolve_expression(selector, origin);
  if (receiver.cadr().car() == <opt-ref>)
    c.report_error(
      <type>, "check optional reference before indexing its value",
      origin, NULL);
  if (_deferred_receiver(receiver) || _deferred_receiver(selector))
    return %(expr (<macro-expr>) (index $receiver $selector));
  List resolved = c._postfix_index_expression(receiver, selector);
  if (resolved) return resolved;
  Type receiver_type = receiver.cadr();
  // A field of a foreign struct has no x2c type; C indexes it alone.
  if (!receiver_type &&
      List.match(receiver, %(expr () ${$source_operator_content(
        %((!or . ->) * *))})))
    return %(expr () (index $receiver $selector));
  c.report_error(
    <parse>, receiver_type.is_typedef_name()
      ? %"type $receiver_type does not support getindex"
      : %"type $receiver_type does not support indexing",
    origin, %());
}

static List Compiler._postfix_index_expression(
  Compiler c, List expr, List index) {
  Type type = expr.cadr();
  // `T *const p` indexes like `T *p`.
  while (type && type.car() is <symbol> &&
         Symbol.is_type_qualifier(type.car()))
    type = cdr(type);
  if (type.is_pointer() || type.is_array())
    return %(expr ${type.dereference()} (index $expr $index));
  if (!type.is_typedef_name()) return NULL;
  return c._typedef_index(expr, index, type);
}

static List Compiler._typedef_index(
  Compiler c, List expr, List index, Type type) {
  String owner = type.car(), Type receiver = type;
  if (c.sym.is_array_type(type)) {
    owner = "Array";
    receiver = %("Array");
  }
  else if (c.sym.is_map_type(type)) {
    owner = "Map";
    receiver = %("Map");
  }
  String fnname = %"${owner}_getindex";
  List fntype = c.sym.get(%($fnname));
  match (fntype) {
    case %((func (!set ?params ($receiver ?))) ?rtype): {
      Type key = params.cadr(), supplied = index.cadr();
      if (key.is_integral() && c.sym.is_named_value_type(supplied, "Symbol"))
        c.report_error(
          <type>, "Symbol cannot be used as an integer bracket index",
          c.token, NULL);
      return %(expr ($rtype) (getindex $expr $index));
    }
  }
  Type native = c.sym.resolve_key(type);
  // A boxable handle to a record has no C array reading.
  if (native.is_pointer() && native.dereference().is_aggregate() &&
      type.var_tag())
    c.report_error(
      <type>, %"${type.car()} has no getindex", c.token, NULL);
  // A typedef of a plain C pointer indexes as that pointer; `String` and
  // its aliases keep their protocol reading.
  if (native.is_array() ||
      (native.is_pointer() && !c.sym.is_string_type(type)))
    return %(expr ${native.dereference()} (index $expr $index));
  return NULL;
}

static List Compiler._resolve_getindex(
  Compiler c, Type input_type, List receiver, List selector,
  Token origin) {
  return %(expr $input_type
           (getindex ${c.resolve_expression(receiver, origin)}
                     ${c.resolve_expression(selector, origin)}));
}

static List Compiler._resolve_slice(
  Compiler c, Type input_type, List slice, Token origin) {
  (List receiver, List start, List stop, List step) = slice.cdr();
  receiver = c.resolve_expression(receiver, origin);
  if (start) start = c.resolve_expression(start, origin);
  if (stop) stop = c.resolve_expression(stop, origin);
  if (step) step = c.resolve_expression(step, origin);
  List operation = source_slice_content(%($receiver $start $stop $step));
  if (input_type === %(<macro-expr>))
    operation = c.anchor_origin(operation, origin);
  return %(expr ${receiver.cadr()} $operation);
}

// calls

static List Compiler._resolve_native_call(
  Compiler c, Type input_type, String callee, List supplied,
  Token origin) {
  List arguments = c._resolve_call_arguments(NULL, supplied, origin);
  return %(expr $input_type (call $callee (args @arguments)));
}

/* One call being resolved: its expected result type, the arguments it
   supplies, and its origin. A method call adds the receiver, its type, and
   the member it selects. */
typedef struct CallSite {
  Compiler c;
  Type result_type, type;
  List receiver, field, supplied;
  Token origin;
  String method;
} CallSite;

static List Compiler._resolve_call(
  Compiler c, Type result_type, List function, List supplied,
  Token origin) {
  CallSite site = {
    .c = c, .result_type = result_type, .supplied = supplied,
    .origin = origin};
  match (function)
    case %(expr ? ${$source_operator_content(
        %(. ?receiver (!set ?field (?name))))}):
      return site._method(receiver, field);
  return site._function(function);
}

static List CallSite._function(CallSite *k, List function) {
  List resolved = k.c.resolve_expression(function, k.origin);
  Type type = resolved.cadr(), func_type = k.c.sym.resolve_key(%("Func"));
  if (type && k.c.sym.resolve_key(type).equal(func_type))
    return k.c._resolve_func_call(resolved, k.supplied, k.origin);
  return k._finish(k.result_type, resolved, type, NULL);
}

static List CallSite._finish(
  CallSite *k, Type result_type, List callee, Type callee_type,
  List receiver) {
  if (result_type === %(<macro-expr>)) result_type = NULL;
  Type applied = callee_type.apply();
  if (!applied && callee_type)
    applied = k.c.sym.resolve_key(callee_type).apply();
  List arguments = k.c._resolve_call_arguments(receiver, k.supplied, k.origin);
  if (_deferred_call(callee, receiver, arguments))
    result_type = %(<macro-expr>);
  if (!result_type) result_type = applied;
  if (receiver && result_type !== %(<macro-expr>))
    k._check_arity(callee_type, arguments);
  k.c.check_meta_call(callee, k.origin);
  callee = k.c._discarding_callee(callee, callee_type, arguments);
  Macro called = $called;
  return k.c.rebuild_expression(result_type, called(callee, arguments));
}

/* A call waits for macro substitution when its callee, its receiver, or
   one of its arguments does. */
static int _deferred_call(List callee, List receiver, List arguments) {
  if (_deferred_receiver(callee) ||
      (receiver && _deferred_receiver(receiver)))
    return 1;
  foreach (Var argument, arguments)
    if (argument is <list> && !argument.is_nil()) {
      List syntax = argument;
      if (_deferred_receiver(syntax) ||
          syntax.car() == <macro-bind> || syntax.car() == <macro-slot>)
        return 1;
    }
  return 0;
}

static void CallSite._check_arity(
  CallSite *k, Type callee_type, List arguments) {
  match (callee_type)
    case %((func (!set ?parameters (*))) *):
      if (!_parameters_variadic(parameters) &&
          arguments.len() > List.len(parameters))
        k.c.report_error(
          <type>,
          %"method takes ${List.len(parameters) - 1} argument${
            List.len(parameters) == 2 ? "" : "s"}, not ${
            arguments.len() - 1}",
          k.origin, NULL);
}

static int _parameters_variadic(List parameters) {
  foreach (Var parameter, parameters)
    if (parameter == <...> || (parameter is <list> && !parameter.is_nil() &&
        parameter.car() == <...>))
      return 1;
  return 0;
}

static List Compiler._resolve_call_arguments(
  Compiler c, List receiver, List supplied, Token origin) {
  Array arguments = [];
  if (receiver) arguments.push(receiver);
  if (!receiver && !supplied) supplied = %((expr (void) ()));
  if (receiver && supplied === %((expr (void) ()))) supplied = NULL;
  foreach (Var argument, supplied) {
    int slot = argument is <list> && !argument.is_nil() &&
               argument.car() == <macro-slot>;
    Var value = c.evaluate_macro_slot(argument);
    if (value is <list> && !value.is_nil() &&
        value.car() == <seq>)
      foreach (List item, value.list().cdr())
        arguments.push(c.resolve_expression(item, origin));
    else if (slot)
      arguments.push(
        c.resolve_expression(
          c.lift_macro_lisp_expression(value, origin), origin)
      );
    else if (value is <list>)
      arguments.push(c.resolve_expression(value, origin));
    else arguments.push(value);
  }
  return arguments.list_free();
}

/* A call whose receiver or argument is an unnamed operator temporary goes
   through a helper that discards that temporary once the call returns. */
static List Compiler._discarding_callee(
  Compiler c, List callee, Type callee_type, List arguments) {
  List binding = NULL;
  match (callee) case %(expr ? ${$source_identifier_content(
      %((!set ?bound (*))))}): binding = bound;
  if (!binding || !callee_type.match(%((func *) *)) ||
      c.protocol_helpers.contains(
        %"discard-helper ${(long) binding}"))
    return callee;
  int which = 0, index = 0;
  foreach (Var argument, arguments) {
    if (argument is <list> && c._is_operator_temporary(argument))
      which |= 1 << index;
    index++;
  }
  if (!which) return callee;
  String stem = binding_identity_spelling(binding);
  if (!stem) return callee;
  List helper = c.discard_helper(binding, callee_type, stem, which);
  if (!helper) return callee;
  List (helper_binding, signature) = helper;
  return %(expr $signature (ident $helper_binding));
}

// method calls

static List CallSite._method(CallSite *k, List receiver, List field) {
  k.receiver = receiver;
  k.field = field;
  List resolution = k._lookup();
  if (!resolution && _deferred_receiver(k.receiver)) {
    List callee = %(expr (<macro-expr>) (op . ${k.receiver} ${k.field}));
    return k._finish(k.result_type, callee, NULL, NULL);
  }
  if (!resolution) {
    Var name = k.field.car();
    k.c.report_error(
      <type>, %"type ${k.type.repr()} has no method $name", k.origin, NULL);
  }
  match (resolution) {
    case %(ambiguous *packages):
      k.c._report_method_ambiguity(k.type, k.method, packages, NULL, k.origin);
    case %(method ?binding (!set ?signature
      ((func (!set ?parameters (?declared *))) *returns))):
      return k._bound(binding, signature, declared, parameters, returns);
    case %(delegate ?binding (!set ?signature
           ((func (!set ?parameters (?declared *))) *returns))
           ?path): {
      k.receiver = _delegate_receiver(k.receiver, path);
      k.type = k.receiver.cadr();
      return k._bound(binding, signature, declared, parameters, returns);
    }
    case %(field ?access ?field_type): {
      List callee = %(expr $field_type
        (op $access ${k.receiver} ${k.field}));
      return k._finish(k.result_type, callee, field_type, NULL);
    }
  }
  return NULL;
}

static List CallSite._lookup(CallSite *k) {
  k.receiver = k.c.resolve_expression(k.receiver, k.origin);
  k.type = k.receiver.cadr();
  k.method = k.field.car().str();
  List resolution = k.c.resolve_postfix_member(k.type, k.field, <.>, 1);
  if (!resolution && _expr_is_raw_string_literal(k.receiver)) {
    k.receiver = k.c.promote_string_literal(k.receiver);
    k.type = k.receiver.cadr();
    resolution = k.c.resolve_postfix_member(k.type, k.field, <.>, 1);
  }
  return resolution ? resolution
    : k.c._resolve_delegate_method(k.type, k.method, k.origin);
}

static List CallSite._bound(
  CallSite *k, List binding, Type signature, List declared,
  List parameters, List returns) {
  k.receiver = k.c._method_bind(k.receiver, k.type, declared, k.origin);
  List callee = %(expr ((func $parameters) $returns) (ident $binding));
  return k._finish(signature.apply(), callee, signature, k.receiver);
}

static List Compiler._method_bind(
  Compiler c, List receiver, Type type, Type declared, Token origin) {
  if (!declared || !type) return receiver;
  Type target = declared.canonicalize(), source = type.canonicalize();
  if (_receiver_points_to(source, target))
    c.report_error(
      <type>,
      %"method receiver ${type.repr()} is a pointer to ${declared.repr()}",
      origin,
      %("'.' reaches one pointer level; write (*receiver).method()"));
  if (target.car() != <*> || cdr(target) !== source)
    return receiver;
  if (!c._expression_is_addressable(receiver))
    c.report_error(
      <type>, "method pointer receiver requires an addressable value",
      origin, %("bind the value to an object before calling the method"));
  List address = %(expr ${type.reference()} (op & (parens $receiver)));
  return c.convert_expression(address, declared);
}

/* Whether a method receiver is a pointer to the declared parameter. `.` binds
   a receiver by identity or by one address-of, so such a call would pass the
   wrong pointer; with a pointer typedef C only warns and the program
   aborts. */
static int _receiver_points_to(Type source, Type declared) {
  while (source.is_pointer()) {
    source = source.dereference();
    if (source === declared) return 1;
  }
  return 0;
}

// member lookup

/** Resolves one field or method selection without consuming parser tokens.
    `field` is a single-name `List` and `access` is `.` or
    `->`. The result is a
    `(field access type)`, `(method binding signature)`, or `(ambiguous ...)`
    row, or NULL when no member is visible. Method lookup is enabled only by
    `call_context` and records the selected binding in `c.sym`.
*/
List Compiler.resolve_postfix_member(
  Compiler c, Type receiver_type, List field, Symbol access,
  int call_context) {
  if (receiver_type.car() == <opt-ref>)
    c.report_error(
      <type>, "check optional reference before accessing its value",
      c.token, NULL);
  // The receiver type is a lookup key here. A const or volatile receiver
  // names the same aggregate, fields, and methods.
  Type type = receiver_type.canonicalize();
  int hops = 0;
  if (access == <"->">) {
    Type object_type = c.sym.resolve_key(type);
    object_type = object_type.dereference();
    Type field_type = c.sym.lookup_field(object_type, field);
    return field_type ? %(field -> $field_type) : NULL;
  }
  while (type) {
    int is_method_type = type.is_typedef_name() || type.is_builtin();
    if (call_context && is_method_type) {
      List method = c._method_member(receiver_type, type, field);
      if (method) return method;
    }
    if (type.is_pointer()) {
      Type object_type = type.dereference();
      Type field_type = c.sym.lookup_field(object_type, field);
      if (field_type) return %(field -> $field_type);
      type = NULL;
    }
    else if (type.is_aggregate()) {
      Type field_type = c.sym.lookup_field(type, field);
      if (field_type) return %(field . $field_type);
      type = NULL;
    }
    else type = c.sym.next_typedef(type, hops);
  }
  return NULL;
}

static List Compiler._method_member(
  Compiler c, Type receiver_type, Type type, List field) {
  String method = %"${type.base_type().car()}_${field.car()}";
  Type signature = c.sym.get(%($method));
  int rejected =
    c.protocol_rejects_direct_member(type, field.car().str());
  if (signature && rejected) signature = NULL;
  List binding = NULL;
  if (signature) binding = c.sym.reference(%($method), NULL);
  else {
    List imported = rejected
      ? NULL : c._imported_method(method, receiver_type);
    if (imported) return imported;
    List resolved = c.resolve_protocol_member(type, field.car().str());
    if (resolved) {
      (List method_binding, Type method_signature) = resolved;
      return %(method $method_binding $method_signature);
    }
  }
  if (!signature) return NULL;
  signature = c._receiver_relative_signature(
    binding, signature, receiver_type);
  return %(method $binding $signature);
}

/* Find a method that an imported package adds to an external receiver. The
   package names are sorted so an ambiguous call reports deterministically. */
static List Compiler._imported_method(
  Compiler c, String method, Type receiver) {
  List packages = c.imported_providers(method);
  if (!packages) return NULL;
  if (packages.cdr()) return cons(<ambiguous>, packages);

  String spelling = %"${packages.car()}__$method";
  Type signature = c.sym.get_exact(%($spelling));
  List binding = c.sym.reference(%($spelling), NULL);
  signature = c._receiver_relative_signature(binding, signature, receiver);
  return %(method $binding $signature);
}

static Type Compiler._receiver_relative_signature(
  Compiler c, List binding, Type signature, Type receiver) {
  String spelling = binding_identity_spelling(binding);
  if (!spelling) return signature;
  Type relative = c.sym.get_exact(%(self $spelling));
  if (!relative) return signature;
  Type base = receiver.canonicalize().base_type();
  if (!base || base.len() != 1) return signature;
  return relative.search_replace(<self>, base.car());
}

static List Compiler._resolve_member(
  Compiler c, Var operator, List receiver, List field, Token origin) {
  receiver = c.resolve_expression(receiver, origin);
  Type receiver_type = receiver.cadr();
  List resolution = c.resolve_postfix_member(
    receiver_type, field, operator, 0);
  match (resolution)
    case %(field ?access ?field_type):
      return source_operator_expression(
        field_type, %($access $receiver $field));
  Type type = _deferred_receiver(receiver) ? %(<macro-expr>) : NULL;
  return source_operator_expression(type, %($operator $receiver $field));
}

/* delegate methods

   A method missing from a receiver may be found through its delegate
   fields, searched depth first in field order. More than one path, or a
   cycle with no path, is an error. */

typedef struct DelegateSearch {
  Compiler c;
  String member;
  Type outer;
  Token origin;
  Array candidates;
  List first_cycle;
} DelegateSearch;

static List Compiler._resolve_delegate_method(
  Compiler c, Type receiver, String member, Token origin) {
  DelegateSearch search = {
    .c = c, .member = member, .outer = receiver,
    .origin = origin, .candidates = []};
  search._find(receiver, NULL, NULL);
  List candidates = search.candidates.list_free();
  if (candidates && candidates.cdr()) search._report_paths(candidates);
  if (candidates) return candidates.car();
  if (search.first_cycle) search._report_cycle();
  return NULL;
}

static void DelegateSearch._find(
  DelegateSearch *d, Type receiver, List reverse_path, List seen) {
  Type aggregate = d.c.sym.delegate_aggregate(receiver);
  if (!aggregate) return;
  if (aggregate in seen) {
    if (!d.first_cycle)
      d.first_cycle = cons(<path>, reverse_path.reverse());
    return;
  }
  seen = cons(aggregate, seen);
  List order = d.c.sym.field_order(aggregate);
  foreach (List row, order ? order.cdr() : NULL) {
    String name = row.car();
    if (!name) continue;
    if (!d.c.sym.get(%(@aggregate delegate $name))) continue;
    List step = d.c._delegate_step(receiver, name);
    Type field_type = step.cddr().cadr();
    List next_path = cons(step, reverse_path);
    List resolution = d.c.resolve_postfix_member(
      field_type, %(${d.member}), <.>, 1);
    if (resolution && resolution.car() == <method>) {
      List binding = resolution.cadr(), Type signature = resolution.caddr();
      List path = cons(<path>, next_path.reverse());
      d.candidates.push(%( delegate $binding $signature $path ));
    }
    else if (resolution && resolution.car() == <ambiguous>) {
      String path = _delegate_path_string(
        d.outer, cons(<path>, next_path.reverse()), NULL);
      d.c._report_method_ambiguity(
        field_type, d.member, resolution.cdr(), path, d.origin);
    }
    else if (!resolution)
      d._find(field_type, next_path, seen);
  }
}

static List Compiler._delegate_step(Compiler c, Type receiver, String name) {
  List field = c.resolve_postfix_member(receiver, %($name), <.>, 0);
  (Symbol access, Type field_type) = field.cdr();
  return %(step $access $name $field_type);
}

static void DelegateSearch._report_paths(
  DelegateSearch *d, List candidates) {
  List notes = NULL;
  foreach (List candidate, candidates) {
    List path = candidate.cddr().cadr();
    String spelling = binding_identity_spelling(candidate.cadr());
    String description = _delegate_path_string(d.outer, path, d.member);
    notes = cons(%"delegate path: $description -> $spelling", notes);
  }
  String type = _delegate_type_name(d.outer), member = d.member;
  d.c.report_error(
    <type>, %"method '$type.$member' has multiple delegate paths",
    d.origin, notes.reverse());
}

static void DelegateSearch._report_cycle(DelegateSearch *d) {
  String type = _delegate_type_name(d.outer), member = d.member;
  String path = _delegate_path_string(d.outer, d.first_cycle, NULL);
  d.c.report_error(
    <type>, %"delegation cycle resolving $type.$member", d.origin,
    %("delegate path: $path"));
}

static void Compiler._report_method_ambiguity(
  Compiler c, Type receiver, String member, List packages,
  String delegate_path, Token origin) {
  List notes = delegate_path
             ? %("delegate path: $delegate_path") : NULL;
  foreach (String package, packages)
    notes = cons(%"package: '$package'", notes);
  String type = _delegate_type_name(receiver);
  c.report_error(
    <type>,
    %"method '$type.$member' is provided by multiple imported packages",
    origin, notes.reverse());
}

static String _delegate_path_string(Type receiver, List path, String member) {
  Array parts = [];
  parts.push(_delegate_type_name(receiver));
  foreach (List step, path.cdr()) parts.push(step.caddr());
  if (member) parts.push(member);
  return ".".join(parts.list_free());
}

static String _delegate_type_name(Type type) {
  Type base = type.base_type();
  Var (head, name) = base;
  return base.is_aggregate_tag() ? name.str() : head.str();
}

static List _delegate_receiver(List receiver, List path) {
  foreach (List step, path.cdr()) {
    (Symbol access, String name, Type type) = step.cdr();
    receiver = %(
      expr $type
        (op $access $receiver ($name))
    );
  }
  return receiver;
}

// member completion

/** Returns sorted visible field and method names that resolve on `receiver`
    through `access`. */
List Compiler.postfix_completions(
  Compiler c, Type receiver, Symbol access) {
  Map seen = {}, visited = {};
  Array names = $auto([]), accepted = [];
  Type fields = c.sym.resolve_key(receiver);
  if (fields.is_pointer()) fields = fields.dereference();
  c._completion_fields(fields, seen, names, {});
  if (access == <.>) {
    c._completion_methods(receiver, seen, names);
    c._completion_delegates(receiver, seen, names, visited);
  }
  names.sort();
  foreach (String name, names) {
    List resolution = c.resolve_postfix_member(receiver, %($name), access, 1);
    if (!resolution && access == <.>)
      resolution = c._resolve_delegate_method(receiver, name, c.token);
    match (resolution) {
      case %((!or field method) ? ?): accepted.push(name);
    }
  }
  return accepted.list_free();
}

static void Compiler._completion_fields(
  Compiler c, Type type, Map seen, Array names, Map visited) {
  type = c.sym.resolve_key(type);
  if (!type || !type.is_aggregate_tag() || type in visited) return;
  visited[type] = 1;
  List order = c.sym.field_order(type);
  foreach (List row, order ? order.cdr() : NULL) {
    String name = row.car();
    if (name) _completion_add(seen, names, name);
    else c._completion_fields(row.cadr(), seen, names, visited);
  }
}

static void Compiler._completion_methods(
  Compiler c, Type receiver, Map seen, Array names) {
  Type type = receiver.canonicalize();
  int hops = 0;
  while (type) {
    if (type.is_typedef_name() || type.is_builtin()) {
      String owner = type.base_type().car();
      c._completion_owner_methods(%"${owner}_", seen, names);
      foreach (String name, c.protocol_member_names(type))
        _completion_add(seen, names, name);
    }
    if (type.is_pointer() || type.is_aggregate()) type = NULL;
    else type = c.sym.next_typedef(type, hops);
  }
}

/* Functions named `Owner_name`, or `package__Owner_name` for an imported
   package, among the visible symbols. */
static void Compiler._completion_owner_methods(
  Compiler c, String prefix, Map seen, Array names) {
  foreach (List row, c.sym.visible_symbols()) {
    (String spelling, Var raw) = row;
    if (raw is not <list>) continue;
    Type signature = raw;
    if (signature.is_function() && spelling.startswith(prefix))
      _completion_add(seen, names, spelling.remove_prefix(prefix));
    foreach (Var (raw_package, _), c.package_roots) {
      String package = raw_package;
      String imported = %"${package}__$prefix";
      if (signature.is_function() && spelling.startswith(imported))
        _completion_add(seen, names, spelling.remove_prefix(imported));
    }
  }
}

static void Compiler._completion_delegates(
  Compiler c, Type receiver, Map seen, Array names, Map visited) {
  Type aggregate = c.sym.delegate_aggregate(receiver);
  if (!aggregate || aggregate in visited) return;
  visited[aggregate] = 1;
  List order = c.sym.field_order(aggregate);
  foreach (List row, order ? order.cdr() : NULL) {
    String field = row.car();
    if (!field ||
        !c.sym.get(%(@aggregate delegate $field))) continue;
    Type type = row.cadr();
    c._completion_methods(type, seen, names);
    c._completion_fields(type, seen, names, {});
    c._completion_delegates(type, seen, names, visited);
  }
}

static void _completion_add(Map seen, Array names, String name) {
  if (!name || name in seen) return;
  seen[name] = 1;
  names.push(name);
}

/* dynamic Func calls

   A call through a `Func` value prepares its arguments with the templates
   below; `Compiler.func_call_parts` reads a prepared call back. */

/* One argument, taken by reference when the callee's signature asks for a
   reference and by value otherwise. */
macro open Statement $func_argument(Expr $function, Expr $storage,
    Expr $count, Expr $index, Expr $address, Expr $type, Expr $value) {
  if (x2c_func_reference_type($function, $count, $index))
    $storage[$index] = FuncArg_reference($address, $type);
  else $storage[$index] = $value;
}

/* A null argument: a reference takes it with the callee's own type. */
macro open Statement $func_null_argument(Expr $function, Expr $storage,
    Expr $count, Expr $index, Expr $value) {
  {
    List reference = x2c_func_reference_type($function, $count, $index);
    if (reference) $storage[$index] = FuncArg_reference(0, reference);
    else $storage[$index] = $value;
  }
}

/* The by-value alternative: the argument boxed, or the diagnostic call for
   a type with no Var form. */
macro open Expression $func_value(Expr $argument) => FuncArg_value($argument);

macro open Expression $func_opaque(Expr $function, Expr $index,
    Expr $type) => x2c_func_unrepresentable_argument($function, $index, $type);

/* A call with no arguments applies the callee directly. */
macro open Expression $func_apply(Expr $callee) => Func_apply($callee, 0, 0);

static int _null_literal(List expr) =>
  _integer_literal_kind(expr, NULL) == <zero> ||
  expr.match(%(expr ? ${$source_identifier_content(
    %((binding ? "NULL")))}));

/** Returns one `$func_argument` or `$func_null_argument` application for
    each of `arguments`, preparing it into `storage` for the call through
    `function`; the `$func_call` template calls this in a slot. The choice
    of address, type and by-value alternative follows the argument's type.
*/
List x2c_func_call_arguments(List function, List storage, List arguments) {
  Compiler c = Compiler.expanding();
  Macro prepare = $func_argument, absent = $func_null_argument,
        boxed = $func_value, opaque = $func_opaque;
  List count = x2c_literal_int(arguments.len());
  Array prepared = [];
  int position = 0;
  foreach (List argument, arguments) {
    List index = x2c_literal_int(position++);
    Type type = argument.cadr();
    int forwarded = type.car() == <opt-ref>;
    List source = c.cache_literal_list(
      c.sym.normalize_declared_type(forwarded ? type.cdr() : type));
    List value = c.bind_syntax(
      c.sym.var_tag_for_type(type, NULL)
        ? boxed(c.convert_expression(argument, %("Var")))
        : opaque(function, index, source),
      AST_EXPRESSION, NULL);
    if (_null_literal(argument)) {
      prepared.push(absent(function, storage, count, index, value));
      continue;
    }
    int addressable = c._expression_is_addressable(argument);
    List address = forwarded ? argument
      : addressable ? %(expr ${type.reference()} (op & (parens $argument)))
      : x2c_literal_int(0);
    List carrier = forwarded || addressable ? source : x2c_literal_int(0);
    prepared.push(
      prepare(function, storage, count, index, address, carrier, value));
  }
  return prepared.list_free();
}

/* A dynamic Func call stores its callee once, prepares each argument into
   an array from left to right, and applies the callee. Func_apply validates
   arity and dispatches; the selected adapter checks carrier, type and
   conversion. The call is the value of a statement expression around this
   block. */
macro open Statement $func_call(Expr $callee, Expr $count,
    Expr $arguments...) {
  {
    Func function = $callee;
    FuncArg storage[$count];
    $x2c_func_call_arguments(function, storage, $arguments)...
    Func_apply(function, $count, storage);
  }
}

static List Compiler._resolve_func_call(
  Compiler c, List callee, List supplied, Token origin) {
  List arguments = c._resolve_call_arguments(NULL, supplied, origin);
  match (arguments)
    case %((expr (void) ())): arguments = NULL;
  if (!arguments) {
    Macro apply = $func_apply;
    return c.bind_syntax(apply(callee), AST_EXPRESSION, NULL);
  }
  Macro call = $func_call;
  return %(expr ("Var") (parens ${c.bind_syntax(
    call(callee, arguments.len(), arguments), AST_BLOCK, NULL)}));
}

/** Returns the callee and arguments of a typed `Func` call, or NULL for any
    other expression. `content` is the body of the call's `expr` node. Each
    argument is `(func-arg value address source)`: the argument boxed as a
    Var, or `(no-value)` when it has no Var form; its address, or 0; and its
    type, which is `(expr ("List") (ident reference))` for a null argument
    that takes the callee's own type. */
List Compiler.func_call_parts(Compiler c, Var content) {
  Macro call = $func_call, apply = $func_apply;
  match (%(expr () $content)) case apply(?callee): return %($callee);
  List block = NULL;
  match (content) case $source_content_pattern($grouped, %(?inner)):
    block = inner;
  if (!block) return NULL;
  match (block)
    case call(?callee, ?count, *arguments): {
      Array parts = $auto([callee]);
      foreach (List argument, _slot_statements(arguments)) {
        List part = _func_arg_part(argument);
        if (!part) return NULL;
        parts.push(part);
      }
      return parts;
    }
  return NULL;
}

/* One prepared argument as `(func-arg value address source)`, or NULL for
   any other statement. */
static List _func_arg_part(List argument) {
  Macro prepare = $func_argument, absent = $func_null_argument,
        boxed = $func_value;
  Var value = %(no-value), address = NULL, source = NULL;
  match (argument) {
    case prepare(
      ?function, ?storage, ?count, ?index, ?pointer, ?type, ?alternative): {
      match (alternative) case boxed(?boxed_value): value = boxed_value;
      address = pointer;
      source = type;
    }
    case absent(?function, ?storage, ?count, ?index, ?alternative): {
      match (alternative) case boxed(?boxed_value): value = boxed_value;
      address = x2c_literal_int(0);
      source = %(expr ("List") (ident reference));
    }
    default: return NULL;
  }
  return %(func-arg $value $address $source);
}

/* Open statement groups in a slot. */
static List _slot_statements(List items) {
  Array opened = $auto([]);
  foreach (List item, items)
    match (item) {
      case %(seq *group):
        foreach (List statement, group) opened.push(statement);
      default: opened.push(item);
    }
  return opened;
}

// Iter chains

/** Completes an eligible resolved `Iter` call chain for immediate consumption.
    It accepts only a typed identifier call of the form
    `(expr R (call (expr ((func P) T) (ident B)) (args A)))`, where `R` and
    the last formal in `P` canonicalize to `Iter`. `Iter` arguments are
    completed recursively; a call missing only that last formal receives the
    hidden destination. Variadic calls and `Iter_unzip` are returned unchanged.
*/
List Compiler.complete_iter_chain(Compiler c, List expression) {
  Macro called = $called;
  match (expression) case called(?callee, *arguments):
    match (callee)
      case %(expr ((func (!set ?parameters (*))) ?)
                  (ident ?binding)):
        return c._complete_iter_call(
          expression, callee, arguments, parameters, binding);
  return expression;
}

static List Compiler._complete_iter_call(
  Compiler c, List expression, List callee, List arguments,
  List parameters, List binding) {
  Type result = expression.cadr();
  String name = binding_identity_spelling(binding);
  if (!_exact_iter_type(result) || name == "Iter_unzip" ||
      _parameters_variadic(parameters))
    return expression;
  List formal = parameters, actual = arguments;
  int supplied = arguments.len(), expected = formal.len();
  if (!formal ||
      (supplied != expected && supplied + 1 != expected) ||
      !_exact_iter_type(formal.last()))
    return expression;
  Array completed = [];
  int changed = 0;
  while (actual) {
    List argument = actual.car(), rewritten = argument;
    if (_exact_iter_type(formal.car()))
      rewritten = c.complete_iter_chain(argument);
    if (rewritten != argument) changed = 1;
    completed.push(rewritten);
    actual = actual.cdr();
    formal = formal.cdr();
  }
  List values = completed.list_free();
  if (supplied + 1 == expected) {
    values = values.append(%(${_iter_destination()}));
    changed = 1;
  }
  if (!changed) return expression;
  Macro called = $called;
  return c.rebuild_expression(%("Iter"), called(callee, values));
}

static int _exact_iter_type(Var value) {
  Type type = value is <list> ? value : %($value);
  return type.canonicalize().equal(%("Iter"));
}

static List _iter_destination(void) {
  List values = source_commas_content(%((expr (int) (literal (int) "0"))));
  return %(expr (* struct "Iter")
    (op & (expr (struct "Iter")
      (cast (decl (struct "Iter") (bindings (bind () ())))
        (expr () (composite $values))))));
}

// operators

static List Compiler._resolve_unary(
  Compiler c, Var operator, List operand, Token origin) {
  List lhs = c.resolve_expression(operand, origin);
  Type lhs_type = lhs.cadr();
  if (lhs_type.car() == <opt-ref> && operator != <!>)
    c.report_error(
      <type>, "check optional reference before using its value",
      origin, NULL);
  if (operator == <*> && operand.cadr().car() == <&> &&
      lhs_type.car() != <&>) return lhs;
  if (lhs_type === %(<macro-expr>))
    return source_operator_expression(%(<macro-expr>), %($operator $lhs));
  List lowered = operator == <->
    ? c._protocol_operator_expression(operator, lhs, NULL) : NULL;
  if (lowered) return lowered;
  Type type = lhs_type;
  switch (operator.symbol()) {
    case <!>: type = %(int); break;
    case <*>: {
      Type pointee = type.dereference();
      type = pointee ? pointee : c.sym.resolve_key(type).dereference();
      break;
    }
    case <&>: type = type.reference(); break;
    case <~>: case <+>: case <->: {
      type = c.sym.resolve_numeric_type(type);
      if (type && type.is_integral()) type = type.promote();
      if (!type && lhs_type && operator == <->)
        c.report_error(
          <type>,
          "unary '-' requires a numeric type or implemented neg",
          origin, %("operand type: ${lhs_type.repr()}"));
      if (!type) type = lhs_type;
      break;
    }
  }
  return source_operator_expression(type, %($operator $lhs));
}

static List Compiler._resolve_postfix_op(
  Compiler c, Var operator, List operand, Token origin) {
  operand = c.resolve_expression(operand, origin);
  Type operand_type = operand.cadr();
  if (operand_type.car() == <opt-ref>)
    c.report_error(
      <type>, "check optional reference before using its value",
      origin, NULL);
  if (operand_type === %(<macro-expr>))
    return source_postfix_expression(
      %(<macro-expr>), %($operator $operand));
  return source_postfix_expression(
    operand_type, %($operator $operand));
}

static List Compiler._resolve_conditional(
  Compiler c, Var operator, List condition, List ontrue,
  List onfalse, Token origin) {
  condition = c.resolve_expression(condition, origin);
  ontrue = c.resolve_expression(ontrue, origin);
  onfalse = c.resolve_expression(onfalse, origin);
  Type true_type = ontrue.cadr(), false_type = onfalse.cadr();
  if (condition.cadr() === %(<macro-expr>) ||
      true_type === %(<macro-expr>) ||
      false_type === %(<macro-expr>))
    return source_operator_expression(
      %(<macro-expr>), %($operator $condition $ontrue $onfalse));
  /* Arms of one declared type keep it, so a `Symbol` conditional stays a
     `Symbol` rather than the integer that represents it. */
  Type type = true_type;
  if (true_type.declared() != false_type.declared()) {
    Type left = c.sym.resolve_numeric_type(type);
    Type right = c.sym.resolve_numeric_type(false_type);
    if (left && right) type = left.widest(right);
    else if (c._conditional_joins(false_type, true_type)) {
      type = false_type;
      ontrue = c.convert_expression(ontrue, type);
    }
    else if (c._conditional_joins(true_type, false_type))
      onfalse = c.convert_expression(onfalse, type);
  }
  return source_operator_expression(
    type, %($operator $condition $ontrue $onfalse));
}

/* A conditional whose arms are a `Var` and another value is a `Var`: the
   other arm boxes, so C sees one operand type. Other mixed arms keep their
   C types until a target converts each arm. */
static int Compiler._conditional_joins(Compiler c, Type type, Type other) =>
  type && other && c.sym.is_var_type(type) && !c.sym.is_var_type(other);

static List Compiler._resolve_binary(
  Compiler c, Var operator, List left, List right, Token origin) {
  List lhs = c.resolve_expression(left, origin);
  List rhs = c.resolve_expression(right, origin);
  return c._binary_expression(operator, lhs, rhs, origin);
}

static List Compiler._binary_expression(
  Compiler c, Symbol operator, List lhs, List rhs, Token origin) {
  Type lhs_type = lhs.cadr(), rhs_type = rhs.cadr();
  if (lhs_type === %(<macro-expr>) ||
      rhs_type === %(<macro-expr>))
    return source_operator_expression(
      %(<macro-expr>), %($operator $lhs $rhs));
  if (operator.is_assignment_op()) {
    Type type = lhs_type;
    /* Meta lowering adapts a callable stored to a Func itself; converting
       here would lift a function name to a hidden global first. */
    if (operator == <=> &&
        !(c.meta_body && c.sym.is_named_value_type(type, "Func")))
      rhs = c.convert_expression(rhs, type);
    return source_operator_expression(type, %($operator $lhs $rhs));
  }
  c._convert_string_comparison(operator, lhs, rhs);
  int constant_string = c._convert_string_addition(operator, lhs, rhs);
  List lowered = c._protocol_operator_expression(operator, lhs, rhs);
  if (lowered) {
    if (!constant_string) return lowered;
    List cached = c.cache(%(string $lowered));
    return %(expr ("String") $cached);
  }
  if (operator == <in>)
    c.report_error(
      <type>, "operator 'in' requires an implemented contains member",
      origin, %("receiver type: ${rhs_type.repr()}"));
  /* An untyped preprocessor name beside a converting protocol participant
     would reach the C compiler with no usable conversion. */
  if ((lhs_type != NULL) != (rhs_type != NULL))
    c._check_untyped_operand(
      operator, lhs_type ? lhs_type : rhs_type,
      lhs_type ? rhs : lhs, origin);
  c._check_matmul(operator, lhs_type, rhs_type, origin);
  return c._native_binary_expression(operator, lhs, rhs, origin);
}

static void Compiler._convert_string_comparison(
  Compiler c, Symbol operator, List &lhs, List &rhs) {
  if (operator != <==> && operator != <!=> && operator != <"<"> &&
      operator != <">"> && operator != <"<="> && operator != <">=">)
    return;
  Type lhs_type = lhs.cadr(), rhs_type = rhs.cadr();
  if (c.sym.is_string_type(lhs_type) && _expr_is_raw_string_literal(rhs))
    rhs = c.convert_expression(rhs, lhs_type);
  else if (c.sym.is_string_type(rhs_type) &&
           _expr_is_raw_string_literal(lhs))
    lhs = c.convert_expression(lhs, rhs_type);
}

static int Compiler._convert_string_addition(
  Compiler c, Symbol operator, List &lhs, List &rhs) {
  if (operator != <+> || !c._expr_is_string_like(lhs) ||
      !c._expr_is_string_like(rhs)) return 0;
  Var matched;
  List bindings;
  /* Bare `%(ident *)` also matches literal data ending in <ident>. */
  int constant =
    !lhs.try_search($source_identifier_content(%((*))),
      matched, bindings) &&
    !rhs.try_search($source_identifier_content(%((*))),
      matched, bindings);
  lhs = c.convert_expression(lhs, %("String"));
  rhs = c.convert_expression(rhs, %("String"));
  return constant;
}

static void Compiler._check_untyped_operand(
  Compiler c, Symbol operator, Type participant, List other,
  Token origin) {
  Symbol member = c.operator_member(operator);
  if (!member || operator == <==> || operator == <!=>) return;
  if (c._converts_operands(participant) &&
      c.resolve_protocol_member(participant, member) &&
      other.match(%(expr ? ${$source_identifier_content(%(?))})))
    c.report_error(
      <type>, "operand has no x2c type beside a protocol participant",
      origin, %("a preprocessor macro has no type here: cast it, or bind its value to a local"));
}

static void Compiler._check_matmul(
  Compiler c, Symbol operator, Type lhs_type, Type rhs_type,
  Token origin) {
  if (operator == <@> && !c.sym.is_var_type(lhs_type) &&
      !c.sym.is_var_type(rhs_type))
    c.report_error(
      <type>, "operator '@' requires an implemented matmul member",
      origin,
      %("left type: ${lhs_type.repr()} right type: ${rhs_type.repr()}"));
}

/* Operands have been resolved in the caller's current semantic scope. */
static List Compiler._native_binary_expression(
  Compiler c, Symbol operator, List lhs, List rhs, Token origin) {
  Type type = c._binary_op_type(operator, lhs, rhs);
  List operation = source_operator_content(%($operator $lhs $rhs));
  if (c.sym.is_var_type(lhs.cadr()) || c.sym.is_var_type(rhs.cadr()))
    operation = c.anchor_origin(operation, origin);
  return %(expr $type $operation);
}

// operator result types

static List Compiler._binary_op_type(
  Compiler c, Symbol op, List lhs, List rhs) {
  c._check_optional_operands(op, lhs, rhs);
  if (op == <in>) return NULL;
  if (_is_comparison(op)) return %(int);
  Type ltype = lhs.cadr(), rtype = rhs.cadr();
  if (c.sym.is_var_type(ltype) || c.sym.is_var_type(rtype))
    return %("Var");
  switch (op) {
    case <"<<">: case <">>">:
      return c._shift_type(ltype);
    case </>:    case <%>:
    case <"|">:  case <&>:   case <*>:
    case <^>: return c._arithmetic_type(ltype, rtype);
    case <+>:    case <->:
      return c._binary_op_type_addsub(op, lhs, rhs);
    default: return _binary_op_type_fallback(lhs, rhs);
  }
}

static int _is_comparison(Symbol op) {
  switch (op) {
    case <||>:   case <&&>:
    case <==>:   case <!=>:  case <===>:  case <!==>:
    case <"<">:  case <">">: case <"<=">: case <">=">:
      return 1;
  }
  return 0;
}

/* An optional reference is usable only as a truth value or beside a null
   constant in an equality test. */
static void Compiler._check_optional_operands(
  Compiler c, Symbol op, List lhs, List rhs) {
  Type ltype = lhs.cadr(), rtype = rhs.cadr();
  if (ltype.car() != <opt-ref> && rtype.car() != <opt-ref>) return;
  int null_test = _null_literal(lhs) || _null_literal(rhs);
  if (!((op == <==> || op == <!=>) && null_test) &&
      op != <&&> && op != <||>)
    c.report_error(
      <type>, "check optional reference before using its value",
      c.token, NULL);
}

static Type Compiler._shift_type(Compiler c, Type lhs) {
  Type scalar = c.sym.resolve_numeric_type(lhs);
  return scalar ? scalar.promote() : NULL;
}

static Type Compiler._arithmetic_type(Compiler c, Type lhs, Type rhs) {
  Type left = c.sym.resolve_numeric_type(lhs);
  Type right = c.sym.resolve_numeric_type(rhs);
  return left.widest(right);
}

static List Compiler._binary_op_type_addsub(
  Compiler c, Symbol op, List lhs, List rhs) {
  Type ltype = lhs.cadr(), rtype = rhs.cadr();
  if (op == <+> && c._expr_is_string_like(lhs) &&
      c._expr_is_string_like(rhs))
    return %("String");
  Type lscalar = c.sym.resolve_numeric_type(ltype);
  Type rscalar = c.sym.resolve_numeric_type(rtype);
  if (lscalar) {
    if (rscalar) return lscalar.widest(rscalar);
    else if (op == <+> && rtype.is_pointer()) return rtype;
  }
  else if (ltype.is_pointer()) {
    if (rscalar)                  return ltype;
    else if (rtype.is_pointer())  return %(int);
  }
  return NULL;
}

static List _binary_op_type_fallback(List lhs, List rhs) {
  Type ltype = lhs.cadr(), rtype = rhs.cadr();
  if (!ltype) return rtype;
  if (!rtype) return ltype;
  if (ltype === %("Var") || rtype === %("Var")) return %("Var");
  if (ltype.is_pointer()) return ltype;
  if (rtype.is_pointer()) return rtype;
  return NULL;
}

/* protocol operators

   An operator whose operand type adopts the operator's protocol member
   becomes a call of that member. A call result that the member returns
   fresh is discarded by the operator or call that consumes it. */

static List Compiler._protocol_operator_expression(
  Compiler c, Symbol op, List lhs, List rhs) {
  Symbol derived = 0;
  List resolved = c._resolve_protocol_operator(op, lhs, rhs, derived);
  if (!resolved) return NULL;
  (List binding, Type signature) = resolved;
  Type result = signature.cdr(), List arguments = NULL;
  int which = 0;
  if (!rhs) arguments = %($lhs);
  else if (op == <in>) {
    List parameters = signature.car().cadr();
    lhs = c.convert_expression(lhs, parameters.cadr());
    arguments = %($rhs $lhs);
  }
  else arguments = %($lhs $rhs);
  if (op != <in>) {
    if (c._is_operator_temporary(lhs)) which |= 1;
    if (rhs && c._is_operator_temporary(rhs)) which |= 2;
  }
  if (!derived && c.resolve_protocol_member(result, "discard"))
    c._note_fresh_callee(binding);
  if (which) {
    Symbol member = rhs ? c.operator_member(op) : <neg>;
    if (!member) member = c.derived_member(op);
    Type participant = lhs.cadr();
    participant = participant.canonicalize();
    List helper = c.protocol_discard_helper(
      participant, member, which);
    if (helper) (binding, signature) = helper;
  }
  Macro called = $called;
  List callee = %(expr $signature (ident $binding));
  List call = c.rebuild_expression(result, called(callee, arguments));
  if (!derived) return call;
  if (derived == <equal>) return %(expr (int) (op ! $call));
  List zero = %(expr (int) (literal (int) "0"));
  return %(expr (int) (op $op $call $zero));
}

/* A binary operator whose one operand is a converting participant converts
   the other operand to that type through its declared converter, so
   `x * 2.0` and `2.0 - x` resolve like `x * two`. The converted operand
   replaces the original through `lhs` and `rhs`. An operand's qualifier
   describes its storage, not the type that adopts the operator, so the
   participant is the unqualified type both here and in the operands'
   comparison. */
static List Compiler._resolve_protocol_operator(
  Compiler c, Symbol op, List &lhs, List &rhs, Symbol &derived) {
  derived = 0;
  Type lhs_type = lhs.cadr();
  lhs_type = lhs_type.canonicalize();
  Type participant = lhs_type, rhs_type = NULL;
  if (rhs) {
    rhs_type = rhs.cadr();
    rhs_type = rhs_type.canonicalize();
  }
  Symbol member = 0;
  if (!rhs) {
    if (op != <->) return NULL;
    member = <neg>;
  }
  else if (op == <in>) {
    participant = rhs_type;
    member = <contains>;
  }
  else {
    if (!participant) return NULL;
    member = c.operator_member(op);
    Symbol source = c.derived_member(op);
    if (!member) member = source;
    derived = source;
    if (!member) return NULL;
    if (participant !== rhs_type) {
      participant = c._converted_participant(
        member, participant, rhs_type, lhs, rhs);
      if (!participant) return NULL;
    }
  }
  return participant && member
       ? c.resolve_protocol_member(participant, member)
       : NULL;
}

static Type Compiler._converted_participant(
  Compiler c, Symbol member, Type lhs_type, Type rhs_type,
  List &lhs, List &rhs) {
  if (c.sym.is_var_type(lhs_type) ||
      c.sym.is_var_type(rhs_type)) return NULL;
  Type shared = c._shared_participant(lhs_type, rhs_type, member);
  if (shared) return shared;
  int lhs_member = !!c.resolve_protocol_member(lhs_type, member) &&
    c._converts_operands(lhs_type);
  int rhs_member = !!c.resolve_protocol_member(rhs_type, member) &&
    c._converts_operands(rhs_type);
  if (lhs_member && !rhs_member) {
    List converted = c._converter_call(rhs, rhs_type, lhs_type);
    if (converted) { rhs = converted; return lhs_type; }
  }
  else if (rhs_member && !lhs_member) {
    List converted = c._converter_call(lhs, lhs_type, rhs_type);
    if (converted) { lhs = converted; return rhs_type; }
  }
  return NULL;
}

/* Two different typedef names that share an ancestor meet at the nearest
   one that has `member`, so an alias of `String` compares with a `String`,
   or with another alias, through `String.equal` rather than as the pointers
   C sees. */
static Type Compiler._shared_participant(
  Compiler c, Type lhs_type, Type rhs_type, Symbol member) {
  if (!lhs_type.is_bare_typedef_name() || !rhs_type.is_bare_typedef_name())
    return NULL;
  Array lhs_names = c._typedef_names(lhs_type);
  foreach (Type name, c._typedef_names(rhs_type))
    if (name in lhs_names &&
        c.resolve_protocol_member(name, member))
      return name;
  return NULL;
}

static Array Compiler._typedef_names(Compiler c, Type type) {
  Array names = [];
  int hops = 0;
  for (; type && (type.is_bare_typedef_name() || type.is_typedef());
       type = c.sym.next_typedef(type, hops))
    if (type.is_bare_typedef_name()) names.push(type);
  return names;
}

/* A participant that converts its operator's other operand: a struct or
   union, or a handle typedef pointing at one. Scalar pointers keep native C
   behavior, since `text + 1` must stay pointer arithmetic. */
static int Compiler._converts_operands(Compiler c, Type type) {
  Type resolved = c.sym.resolve_key(type);
  if (resolved && resolved.is_pointer())
    resolved = c.sym.resolve_key(resolved.dereference());
  return resolved && resolved.is_aggregate();
}

/* A call result is an unnamed temporary the consuming operator or call may
   discard when its callee is known to return a fresh value: a protocol
   operator member, a converter from a number, or a wrapper of either. The
   callee binding is shared by every call to that function, so the record
   survives the re-resolution that rebuilds call nodes. */
static void Compiler._note_fresh_callee(Compiler c, List binding) {
  long identity = (long) binding;
  c.protocol_helpers[%"fresh-callee $identity"] = 1;
}

static int Compiler._is_operator_temporary(Compiler c, List expression) {
  match (expression) {
    case %(expr ? ${$source_content_pattern($grouped, %(?inner))}):
      return c._is_operator_temporary(inner);
  }
  Macro called = $called;
  match (expression) case called(?callee, *arguments):
    match (callee) case %(expr ? ${$source_identifier_content(
        %((!set ?binding (*))))}):
      return c.protocol_helpers.contains(
        %"fresh-callee ${(long) binding.list()}");
  return 0;
}

// type tests and casts

static List Compiler._resolve_is_type(
  Compiler c, List operand, Type target, Token origin) {
  List lhs = c.resolve_expression(operand, origin);
  Type lhs_type = lhs.cadr();
  if (_deferred_receiver(lhs) || _deferred_type_test(target)) {
    Macro has_type = $has_type;
    return c.rebuild_expression(%(<macro-expr>), has_type(lhs, target));
  }
  if (!c.sym.is_var_type(lhs_type))
    c.report_error(
      <type>, "operator 'is' requires Var on the left",
      origin, %("operand type: ${lhs_type.repr()}"));
  Macro called = $called;
  if (target === %(void) || target === %("Void")) {
    List callee = c._resolve_identifier("Var_is_void", NULL, origin);
    return c.rebuild_expression(%(int), called(callee, %($lhs)));
  }
  Symbol vartag = c.require_var_tag(target, origin);
  List direct = c._constant_row_test(lhs, vartag, origin);
  if (direct) return direct;
  String tagsym = %"${(unsigned long) vartag}";
  List callee = c._resolve_identifier("Var_is", NULL, origin);
  return c.rebuild_expression(
    %(int), called(callee, %($lhs (expr ("Symbol") $tagsym))));
}

static List Compiler._resolve_is_symbol(
  Compiler c, List operand, List selector, Token origin) {
  List lhs = c.resolve_expression(operand, origin);
  selector = c.resolve_expression(selector, origin);
  Type lhs_type = lhs.cadr(), selector_type = selector.cadr();
  if (_deferred_receiver(lhs) || _deferred_receiver(selector)) {
    Macro has_symbol = $has_symbol;
    return c.rebuild_expression(
      %(<macro-expr>), has_symbol(lhs, selector));
  }
  if (!c.sym.is_var_type(lhs_type))
    c.report_error(
      <type>, "operator 'is' requires Var on the left",
      origin, %("operand type: ${lhs_type.repr()}"));
  if (!c.sym.is_named_value_type(selector_type, "Symbol"))
    c.report_error(
      <type>, "operator 'is' requires a type or Symbol on the right",
      origin, %("operand type: ${selector_type.repr()}"));
  match (selector)
    case %(expr ("Symbol") ${$source_literal_content(
        %(("Symbol") ? ?tag_value))}): {
      if (tag_value is <symbol>) {
        Symbol tag = tag_value;
        List direct = c._constant_row_test(lhs, tag, origin);
        if (direct) return direct;
      }
    }
  List callee = c._resolve_identifier("Var_is", NULL, origin);
  Macro called = $called;
  return c.rebuild_expression(%(int), called(callee, %($lhs $selector)));
}

/* A statically known tag whose encoding row the decoder discriminates on
   `top` and `bottom` alone tests as two compares. `Var.is_row` takes the
   row as constants so the C compiler folds them and the operand is
   evaluated once. Tags with a validity clause, an immediate width, or a
   user registration have no row and keep the deciding decode. */
static List Compiler._constant_row_test(
  Compiler c, List lhs, Symbol tag, Token origin) {
  unsigned long top, mask, bottom;
  if (!Type.var_tag_row(tag, top, mask, bottom)) return NULL;
  List callee = c._resolve_identifier("Var_is_row", NULL, origin);
  List arguments = %($lhs
    (expr (unsigned) (literal (unsigned) "$top"))
    (expr (unsigned long) (literal (unsigned long) "$mask"))
    (expr (unsigned long) (literal (unsigned long) "$bottom")));
  Macro called = $called;
  return c.rebuild_expression(%(int), called(callee, arguments));
}

/** Returns the exact Var tag for a type test, rejecting types without one.
    Enums retain no identity after boxing and cannot be tested this way.
*/
Symbol Compiler.require_var_tag(
  Compiler c, Type target, Token origin) {
  Type resolved = NULL;
  Symbol vartag = c.sym.var_tag_for_type(target, resolved);
  if (resolved && resolved.is_enum()) {
    String note =
      "enum values box as the shared i32 family and retain no enum identity";
    c.report_error(
      <type>, %"enum type ${target.repr()} cannot be tested with 'is'",
      origin, %($note));
  }
  if (!vartag)
    c.report_error(
      <type>,
      %"type ${target.repr()} has no supported Var tag for operator 'is'",
      origin, NULL);
  return vartag;
}

/** Builds an exact tag expression, deferring macro type slots until
    binding. */
List Compiler.var_tag_expression(Compiler c, Type target, Token origin) {
  if (_deferred_type_test(target))
    return %(expr (<macro-expr>) (type-tag $target));
  Symbol tag = c.require_var_tag(target, origin);
  return %(expr ("Symbol") (literal ("Symbol") ${tag.str()} $tag));
}

static int _deferred_type_test(Type target) {
  foreach (Var specifier, target)
    match (specifier)
      case %((!or macro-bind macro-slot) *): return 1;
  return 0;
}

static List Compiler._resolve_cast(
  Compiler c, List declaration, List operand, Token origin) {
  operand = c.resolve_expression(operand, origin);
  declaration = c.bind_syntax(declaration, AST_BLOCK, c.return_type);
  List typed = %(declare @{declaration.cdr()});
  Type type = operand.cadr() === %(<macro-expr>) ||
              c._casts_to_template_typedef(declaration)
            ? %(<macro-expr>) : typed.type_from_ast();
  return %(expr $type (cast $declaration $operand));
}

static List Compiler._resolve_tadapt(
  Compiler c, List target, List source, Token origin) {
  target = c.resolve_expression(target, origin);
  source = c.resolve_expression(source, origin);
  match (target)
    case %(expr (!set ?syntax (typedef ?target_type)) ?): {
      Type type = c.sym.resolve_key(syntax);
      if (!type || !type.is_pointer() ||
          !type.dereference().is_function())
        c.report_error(
          <macro>,
          "typed callback adapter target must name a function pointer",
          origin, type ? %("target type: ${type.repr()}") : NULL);
      return %(expr ($target_type) (tadapt ${c.origin} $source));
    }
  c.report_error(
    <macro>, "typed callback adapter target must be a typedef name",
    origin, NULL);
}

// collection literals

static List Compiler._resolve_segments(
  Compiler c, List items, Token origin) {
  Array resolved = [];
  Type type = %("String");
  foreach (List item, items) match (item) {
    case %((!set ?tag (!or segvar segexp)) ?value): {
      List expression = c.resolve_expression(value, origin);
      if (_deferred_receiver(expression)) {
        type = %(<macro-expr>);
        resolved.push(%($tag $expression));
        continue;
      }
      resolved.push(%($tag ${c.convert_segment_to_string(expression)}));
      continue;
    }
    default: resolved.push(item);
  }
  return %(expr $type ${source_string_content(resolved.list_free())});
}

static List Compiler._resolve_cons(
  Compiler c, Type input_type, List head, List tail, Token origin) {
  head = c.resolve_expression(head, origin);
  tail = c.resolve_expression(tail, origin);
  Type type = input_type ? input_type : %("List");
  if (_deferred_receiver(head) || _deferred_receiver(tail))
    return %(expr $type (cons $head $tail));
  head = c.convert_expression(head, %("Var"));
  List cached = c.cache_cons_cell(head, tail);
  if (cached) return cached;
  return %(expr $type (cons $head $tail));
}

static List Compiler._resolve_append(
  Compiler c, Type input_type, List head, List tail, Token origin) {
  head = c.resolve_expression(head, origin);
  tail = c.resolve_expression(tail, origin);
  head = c.sym.is_var_type(head.cadr())
       ? %(expr ("List") (call "Var_list" (args $head)))
       : c.convert_expression(head, %("List"));
  return %(expr ${input_type ? input_type : %("List")}
           (append $head $tail));
}

static List Compiler._resolve_splice(
  Compiler c, Type input_type, List expression, Token origin) =>
  %(expr $input_type (splice ${c.resolve_expression(expression, origin)}));

static List Compiler._resolve_array_value(
  Compiler c, List input, Type input_type, Token origin) {
  Macro array_value = $array_value;
  match (input) case array_value(*elements): {
    Array resolved = [];
    foreach (List element, elements)
      resolved.push(c.resolve_expression(element, origin));
    return c.rebuild_expression(
      input_type, array_value(resolved.list_free()));
  }
  return input;
}

static List Compiler._resolve_map_value(
  Compiler c, List input, Type input_type, Token origin) {
  Macro map_value = $map_value;
  match (input) case map_value(*entries): {
    Array resolved = [];
    foreach (Var entry, entries)
      foreach (Var row, c.evaluate_macro_rows(entry))
        resolved.push(c.resolve_map_entry(row, origin));
    return c.rebuild_expression(
      input_type, map_value(resolved.list_free()));
  }
  return input;
}

/** Resolves the key and value of one `(map-entry key value)` AST row.
    Any other shape is reported at `origin` as a parse error.
*/
List Compiler.resolve_map_entry(Compiler c, List input, Token origin) {
  match (input)
    case %(map-entry ?key ?value):
      return %(map-entry
        ${c.resolve_expression(key, origin)}
        ${c.resolve_expression(value, origin)});
  c.report_error(<parse>, "expected one Map entry", origin, NULL);
}

static List Compiler._resolve_initval(
  Compiler c, Type input_type, List content, Token origin) {
  List header = NULL;
  List cases = Ast.initializer_cases(content, header);
  Array resolved = [];
  if (header) {
    Array inputs = [];
    foreach (List argument, header.cdr()) {
      List value = c.resolve_expression(argument.cadr(), origin);
      inputs.push(%(${argument.car()} $value));
    }
    resolved.push(%(input @{inputs.list_free()}));
  }
  foreach (List choice, cases) {
    (List condition, List path, Type destination, List value) = choice;
    if (condition) condition = c.resolve_expression(condition, origin);
    value = c.resolve_expression(value, origin);
    resolved.push(%($condition $path $destination $value));
  }
  return %(expr $input_type (initval @{resolved.list_free()}));
}

static List Compiler._resolve_composite(
  Compiler c, Type input_type, List elements, Token origin) {
  Array values = [];
  foreach (List element, elements)
    values.push(c._resolve_initializer(element, origin));
  return %(expr $input_type ${source_composite_content(
    values.list_free())});
}

static List Compiler._resolve_initializer(
  Compiler c, List node, Token origin) {
  match (node) {
    case %(dotinit ?field ?value):
      return %(dotinit $field ${c._resolve_initializer(value, origin)});
    case %(indexinit ?index ?value):
      return %(indexinit ${c.resolve_expression(index, origin)}
               ${c._resolve_initializer(value, origin)});
  }
  return c.resolve_expression(node, origin);
}

// groups and built-in forms

static List Compiler._resolve_parens(
  Compiler c, List inner, Token origin) {
  inner = c.resolve_expression(inner, origin);
  Type type = inner.cadr();
  return %(expr $type (parens $inner));
}

static List Compiler._resolve_commas(
  Compiler c, Type input_type, List expressions, Token origin) {
  Array resolved = [];
  foreach (List expression, expressions)
    resolved.push(c.resolve_expression(expression, origin));
  List values = resolved.list_free();
  Type type = input_type;
  if (values) type = values.last().cadr();
  return %(expr $type ${source_commas_content(values)});
}

static List Compiler._resolve_destructure(
  Compiler c, List targets, List source, Token origin) {
  Array resolved = [];
  foreach (List target, targets)
    resolved.push(c.resolve_expression(target, origin));
  source = c.resolve_expression(source, origin);
  return %(expr ${source.cadr()}
           (dstrasgn (targets @{resolved.list_free()}) $source));
}

static List Compiler._resolve_managed_init(
  Compiler c, List initializer, Token origin) {
  initializer = c.resolve_expression(initializer, origin);
  Type type = initializer.cadr();
  return %(expr $type (managed-init $initializer));
}

static List Compiler._resolve_generic(
  Compiler c, List control, List associations, Token origin) {
  control = c.resolve_expression(control, origin);
  Array resolved = [];
  foreach (List association, associations) match (association)
    case %(association ?selector ?value):
      resolved.push(
        %(association $selector ${c.resolve_expression(value, origin)}));
  Type type = control.cadr() === %(<macro-expr>) ? %(<macro-expr>) : NULL;
  return %(expr $type ${source_generic_content(
    %($control @{resolved.list_free()}))});
}

/* A `sizeof` keeps its grouped or bare form around the resolved operand;
   an operand that is not syntax stays as written. */
static List Compiler._resolve_sizeof(
  Compiler c, List input, Macro form, Var argument, Token origin) {
  if (argument is not <list>) return input;
  List operand = argument;
  return c.rebuild_expression(
    input.cadr(), form(c.resolve_expression(operand, origin)));
}

static List Compiler._resolve_va_arg(
  Compiler c, Type input_type, List argument, List declaration,
  Token origin) {
  return %(expr $input_type
           ${source_va_arg_content(%(
             ${c.resolve_expression(argument, origin)}
             ${c.resolve_expression(declaration, origin)}))});
}

/* explicit converter calls

   A converter call that repeats the conversion its destination already
   performs draws a warning. */

/* An explicit converter call, `value.str()` or `value.var()`, is the most
   recent one parsed from source tokens, kept with its spelling and
   location. A destination parser compares the expression it just parsed
   against it, so nested calls and calls bound from constructed syntax never
   match. An argument list keeps the note left after each argument, since
   its destinations are known only once the call resolves. A converter takes
   only its receiver and is named for its result: the result spelled in
   lower case, or `str` for String. */
static void Compiler._note_explicit_converter(
  Compiler c, List call, String method, Token origin) {
  Type result = call.cadr();
  if (!result.match(%(?))) return;
  Macro called = $called;
  match (call) case called(?callee, ?argument): {
    String spelled = result.car().str().lower();
    if (method != spelled && (method != "str" || result !== %("String")))
      return;
    c.protocol_helpers["explicit-converter"] =
      %($call $method ${c.token_location(origin)});
  }
}

/** Reports `parsed` when it is the explicit converter call resolved last
    and `target` converts its receiver on its own: either side is Var, the
    types share one C type, or the receiver declares a converter to the
    target. The call then changes nothing but the spelling. `context` is 0
    for a typed destination, 1 for an interpolation hole, which displays
    every value through `Var.str`, and 2 for a printf-family value, which
    the format converts when it is a Var.
*/
void Compiler.check_explicit_converter(
  Compiler c, List parsed, Type target, int context) {
  c._check_noted_converter(
    c.protocol_helpers.getdefault("explicit-converter", %()), parsed,
    target, context);
}

/* Each argument of a call spelled in source is checked against its declared
   parameter type. A method receiver selects the method and is not a
   destination, and a call the compiler builds for an operator is not a
   destination the source spelled. */
static void Compiler._check_converter_args(
  Compiler c, List result, int method, List notes) {
  List callee = NULL, params = NULL, arguments = NULL, supplied = NULL;
  Macro called = $called;
  match (result) case called(?function, *values): {
    callee = function;
    supplied = values;
    arguments = method ? cdr(values) : values;
    match (callee) case %(expr ((func ?declared) *) ?):
      params = method ? cdr(declared) : declared;
  }
  List n = notes;
  for (List p = params, a = arguments; p && a;
       p = cdr(p), a = cdr(a), n = cdr(n)) {
    if (car(p) is not <list> || car(a) is not <list>) continue;
    List param = car(p), argument = car(a);
    Type expected = param.car() == <param> ? param.type_from_ast() : param;
    c._check_noted_converter(car(n), argument, expected, 0);
  }
  /* A static printf-family format converts each Var value it consumes. The
     family's positions count the receiver a method call spells before the
     dot, which `arguments` has already dropped. A format the transform
     cannot read leaves those values unlowered, so nothing converts them. */
  const PrintfFn *info = callee.printf_family(), int raw = 0;
  if (!info ||
      !c.printf_static_format(supplied[info.fmt_arg], raw))
    return;
  int first = info.first_arg - method, index = 0;
  for (List a = arguments, n = notes; a; a = cdr(a), n = cdr(n))
    if (index++ >= first && car(a) is <list>)
      c._check_noted_converter(car(n), car(a), car(a).list().cadr(), 2);
}

static void Compiler._check_noted_converter(
  Compiler c, List noted, List parsed, Type target, int context) {
  if (!noted || !parsed || !target) return;
  (List call, String method, List location) = noted;
  if (!call.equal(parsed)) return;
  // A qualified target, such as `const char *`, is a different crossing.
  if (target.declared() != target.canonicalize() ||
      !List.equal(c.sym.resolve_key(call.cadr()), c.sym.resolve_key(target)))
    return;
  List receiver = call.caddr().caddr().cadr();
  Type source = receiver.cadr();
  if (!source) return;
  int source_is_var = c.sym.is_var_type(source);
  /* `Var.str` displays any value, while the implicit crossing to String
     reads the String payload: a different operation for a Symbol or a
     number. A hole and a format render a Var through `Var.str`, so there
     only `.str()` repeats the crossing. */
  if (source_is_var && (method == "str") != (context != 0)) return;
  /* A Var reaches a numeric scalar other than Symbol through `Var.convert`
     and then a read. `Var.int` already converts, and a raw reader such as
     `Var.integer` skips the conversion, so either call differs. */
  if (source_is_var && target !== %("Symbol") &&
      c.sym.resolve_numeric_type(target))
    return;
  if (context == 2 && !source_is_var) return;
  // A declared crossing to String calls `str`, not a reader like `string`.
  if (!source_is_var && method != "str" && c.sym.is_string_type(target))
    return;
  int implicit = c._implicit_converter(
    receiver, source, target, source_is_var);
  if (!implicit || c._defines_crossing(source, target)) return;
  c.protocol_helpers.del("explicit-converter");
  String hint = context == 1 ? "remove the call; the hole renders the value"
    : context == 2 ? "remove the call; the format converts the value"
    : "remove the call; the destination converts the value";
  c.report_warning_at(
    <conversion>,
    %"unnecessary conversion: .$method() where ${target.repr()} is expected",
    location, %($hint));
}

static int Compiler._implicit_converter(
  Compiler c, List receiver, Type source, Type target,
  int source_is_var) =>
  source_is_var || c.sym.is_var_type(target) ||
  List.equal(c.sym.resolve_key(source), c.sym.resolve_key(target)) ||
  !!c._converter_call(receiver, source, target);

/* The function being defined may be the implicit crossing itself, as a
   `Var.row` converter is for a `Row` destination; its explicit calls are how
   the crossing is written, not a repetition of it. */
static int Compiler._defines_crossing(Compiler c, Type source, Type target) {
  if (!c.fn_name || !source.match(%(?)) || !target.match(%(?))) return 0;
  String from = source.car().str(), to = target.car().str();
  return c.fn_name == %"${from}_${to.lower()}" ||
    c.fn_name == %"${from}_str" || c.fn_name == %"${from}_var";
}

// printf formats

static const PrintfFn printf_family_info[] = {
  { "printf",        0, 1, 1 },
  { "fprintf",       1, 2, 1 },
  { "sprintf",       1, 2, 1 },
  { "snprintf",      2, 3, 1 },
  { "String_printf", 0, 1, 0 },
  { "File_printf",   1, 2, 0 },
  { "Buffer_printf", 1, 2, 0 }
};

/** Returns the printf-family entry a callee names, or `NULL`. A resolved
    user function that happens to use a libc spelling is not one. */
const PrintfFn *List.printf_family(List l) {
  match (l)
    case %(expr ?type ${$source_identifier_content(%(?binding))}): {
      String name = binding_identity_spelling(binding);
      int count = sizeof(printf_family_info) / sizeof(printf_family_info[0]);
      for (int i = 0; i < count; i++) {
        const PrintfFn *info = &printf_family_info[i];
        if (!String.equal(name, (String) info.name)) continue;
        if (info.unresolved && type.list()) return NULL;
        return info;
      }
    }
  return NULL;
}

/** Returns the format a printf-family call consumes when it is known at
    translation time, or `NULL`. That is a quoted C string literal, the
    canonical `String` one becomes, or the `String_new` of one; any other
    format, such as a variable or an object macro, is not readable here.
    `raw` reports C spelling, whose quotes and escape sequences the caller
    steps over.
*/
String Compiler.printf_static_format(
  Compiler c, Var format, int &raw) {
  match (format) {
    case %(expr (* char) ${$source_literal_content(
        %((* char) ?spelled))}): {
      String spelling = spelled;
      int length = spelling ? spelling.len() : 0;
      if (length < 2 || spelling[0] != '"' || spelling[length - 1] != '"')
        return NULL;
      raw = 1;
      return spelling;
    }
    case %(expr ("String") (cache ?id)): {
      List key = c.id_keys[id];
      match (key)
        case %(string (expr ("String") ${$source_literal_content(
            %(("String") ?text))})): {
          raw = 0;
          return text;
        }
      match (key)
        case %(string (expr ("String") (call "String_new" (args ?literal)))):
          return c.printf_static_format(literal, raw);
      return NULL;
    }
  }
  return NULL;
}

// C string literals

static int _expr_is_raw_string_literal(List expr) {
  match (expr) {
    case %(expr ? ${$source_content_pattern($grouped, %(?inner))}):
      return _expr_is_raw_string_literal(inner);
    case %(expr ? ${$source_literal_content(%(?type ?))}):
      return _type_is_char_pointer_like(type);
    case %(expr ? ${$source_operator_content(
        %(? ? ?ontrue ?onfalse))}):
      return _expr_is_raw_string_literal(ontrue) &&
             _expr_is_raw_string_literal(onfalse);
  }
  return 0;
}

static inline int _type_is_char_pointer_like(List type) {
  if (!type) return 0;
  return type.match(%((!or (dim *) (!quote *)) char)) ||
    type.match(%((!or (dim *) (!quote *)) const char));
}

static inline int Compiler._expr_is_string_like(Compiler c, List expr) {
  if (!expr) return 0;
  List type = expr.cadr();
  return c.sym.is_string_type(type) ||
         _type_is_char_pointer_like(type);
}

/** Converts a C string literal to `String` where no C meaning applies: as a
    method receiver, a `foreach` collection, or a raise detail. Parentheses
    and a conditional whose arms are both literals count as the literal; any
    other expression is returned unchanged.
*/
List Compiler.promote_string_literal(Compiler c, List expr) =>
  _expr_is_raw_string_literal(expr) ? c.convert_expression(expr, %("String"))
                                    : expr;

/* Promote raw string expressions while caching only exact literal leaves.
   Parentheses and conditional arms retain their evaluation structure; a
   dynamic leaf still calls String_new each time it is selected. */
static List Compiler._raw_string_to_string(Compiler c, List expr) {
  match (expr) {
    case %(expr (!or (* char) ((dim *) char))
        ${$source_literal_content(
          %((!or (* char) ((dim *) char)) ?))}): {
      List value = %(expr ("String") (call "String_new" (args $expr)));
      return %(expr ("String") ${c.cache(%(string $value))});
    }
    case %(expr (!or (* char) ((dim *) char))
        ${$source_content_pattern($grouped, %(?inner))}): {
      List converted = c._raw_string_to_string(inner);
      return %(expr ("String") (parens $converted));
    }
    case %(expr (!or (* char) ((dim *) char))
        ${$source_operator_content(
          %(? ?condition ?ontrue ?onfalse))}): {
      List converted_true = c._raw_string_to_string(ontrue);
      List converted_false = c._raw_string_to_string(onfalse);
      return %(expr ("String")
               (op ? $condition $converted_true $converted_false));
    }
  }

  return %(expr ("String") (call "String_new" (args $expr)));
}

/* destination conversion

   A resolved value converts to the type its destination declares. C
   performs every conversion this section returns unchanged. */

/** Adds operations to convert a resolved expression AST to `target`.
    The result may contain converter, boxing, unboxing, `Func`, reference, or
    composite-literal operations. Returns the original expression when C
    performs the conversion implicitly; an unsupported x2c conversion reports
    a type error through `c`. Synthesized operations may add generated
    bindings or immutable literal entries to compiler state.
*/
List Compiler.convert_expression(Compiler c, List expr, Type target) {
  if (!target) return expr;
  // Captured Func lambdas wait for reference-cell rewriting.
  expr = c._adapt_lambda_value(expr, target);
  Type type = expr.cadr();
  Type declared_source = type, declared_target = target;
  if (type) type = type.canonicalize();
  target = target.canonicalize();
  int type_is_var = c.sym.is_var_type(type);
  int target_is_var = c.sym.is_var_type(target);
  List lifted = c._lift_func_value(expr, type, target);
  if (lifted) return lifted;
  if (expr.match(%(expr ? (composite ?))))
    return c._compound_literal(expr, target);
  List conditional = c._convert_conditional_arms(expr, declared_target);
  if (conditional) return conditional;
  c._check_null_reference(expr, target);
  if (!type) return c._convert_untyped(expr, declared_target, target_is_var);
  c._check_qualifiers(type, target, declared_source, declared_target);
  if (type == target || (type_is_var && target_is_var)) return expr;
  c._check_reference_value(type, target);
  if (_integer_literal_kind(expr, NULL) == <zero> &&
      c.sym.resolve_key(target).is_pointer())
    return expr;
  c._check_object_pointer(type, target, type_is_var);
  List converted = c._convert_known_value(
    expr, type, target, type_is_var, target_is_var);
  if (converted) return converted;
  if (c.sym.resolve_numeric_type(type) &&
      c.sym.resolve_numeric_type(target))
    return expr; // allow implicit numeric conversions
  c._check_native_crossing(
    expr, type, target, declared_source, declared_target);
  // Everything reaching here is delegated to C: a typedef alias, array or
  // function decay, varargs, a system-header type the collector never
  // sees.  The report_error calls above cover every conversion x2c
  // refuses.
  return expr;
}

static List Compiler._adapt_lambda_value(
  Compiler c, List expr, Type target) {
  Type type = expr.cadr();
  if (!type.is_function()) return expr;
  List lowered = c.lower_lambda_expr(expr);
  return lowered == expr ? expr : c.adapt_lambda_arg(
    lowered, c.sym.resolve_key(target.type_from_ast()));
}

static List Compiler._lift_func_value(
  Compiler c, List expr, Type type, Type target) {
  Type func_type = c.sym.resolve_key(%("Func"));
  if (c.sym.resolve_key(target).equal(func_type)) {
    List lifted = c.lift_func_expression(expr);
    if (lifted != expr) return lifted;
  }
  if (type && c.sym.resolve_key(type).equal(func_type) &&
      target.is_pointer() && target.dereference().is_function()) {
    String message = "cannot convert Func to a context-free callback";
    List hint = %(
      "call Func directly, or use a noncapturing lambda as the C callback"
    );
    c.report_error(<type>, message, NULL, hint);
  }
  return NULL;
}

/* A brace that stays a native initializer outside a declaration becomes a
   compound literal of the destination, because C accepts a bare brace only
   as an initializer. An anonymous struct or union has no spelling for that
   literal. */
static List Compiler._compound_literal(
  Compiler c, List composite, Type target) {
  List converted = c.convert_initializer(composite, target, NULL);
  match (converted)
    case %(expr ?type (composite *)): {
      if (Type.tag(type).match(%((gensym *))))
        c.report_error(
          <type>,
          "a brace outside an initializer needs a named destination type",
          NULL, %("declare the destination with a struct tag or typedef"));
      return %(expr $type (cast $type $converted));
    }
  return converted;
}

/* Only one conditional arm runs; convert each arm when C cannot convert
   the result as a whole. */
static List Compiler._convert_conditional_arms(
  Compiler c, List expr, Type declared_target) {
  match (expr) case %(expr ? ${$source_operator_content(
      %(?operator ?condition ?ontrue ?onfalse))}): {
    Type true_type = ontrue.cadr(), false_type = onfalse.cadr();
    if (ontrue.list().match(%(expr ? (composite *))) ||
        onfalse.list().match(%(expr ? (composite *))) ||
        (!true_type.equal(false_type) &&
         !(c.sym.resolve_numeric_type(true_type) &&
           c.sym.resolve_numeric_type(false_type)))) {
      List converted_true = c.convert_expression(ontrue, declared_target);
      List converted_false = c.convert_expression(onfalse, declared_target);
      if (converted_true != ontrue || converted_false != onfalse)
        return %(expr $declared_target
          (op $operator $condition $converted_true $converted_false));
    }
  }
  return NULL;
}

/* A generic selection has no x2c type; each association owns its
   destination conversion because only one association runs. */
static List Compiler._convert_generic_arms(
  Compiler c, List expr, Type declared_target) {
  match (expr) case %(expr () ${$source_generic_content(
      %(?control *associations))}): {
    Array converted = [];
    int changed = 0;
    foreach (List association, associations) match (association)
      case %(association ?selector ?value): {
        List result = c.convert_expression(value, declared_target);
        if (result != value) changed = 1;
        converted.push(%(association $selector $result));
      }
    if (changed)
      return %(expr $declared_target ${source_generic_content(
        %($control @{converted.list_free()}))});
    converted.free();
  }
  return NULL;
}

static List Compiler._convert_untyped(
  Compiler c, List expr, Type declared_target, int target_is_var) {
  List generic = c._convert_generic_arms(expr, declared_target);
  if (generic) return generic;
  if (target_is_var && expr.match(%(expr () ${$source_identifier_content(
      %((binding ? ?)))}))) {
    List binding = expr.caddr().cadr();
    if (binding_identity_spelling(binding) == "NULL")
      return %(expr ("Var") (call "Var_null" (args)));
    String message = "cannot convert an unresolved expression to Var";
    c.report_error(
      <type>, message, NULL,
      %("give the expression a declared x2c type before boxing it"));
  }
  return expr;
}

static List Compiler._convert_known_value(
  Compiler c, List expr, Type type, Type target,
  int type_is_var, int target_is_var) {
  List reference = c._convert_reference(expr, type, target);
  if (reference) return reference;
  if (type.match(%((!or (dim *) (!quote *)) char))) {
    List string = c._raw_string_to_string(expr);
    if (c.sym.is_string_type(target))
      return %(expr $target ${string.caddr()});
    if (target_is_var)
      return %(expr ("Var") (call "String_var" (args $string)));
  }
  if (type_is_var && !target_is_var) {
    List reader = c._read_var(expr, type, target);
    if (reader) return reader;
  }
  if (!type_is_var && target_is_var) {
    List declared = c._declared_var_converter(expr, type);
    if (declared) return declared;
  }
  List converted = c._converter_call(expr, type, target);
  if (converted) return converted;
  if (!type_is_var && target_is_var) return c._box_var(expr, type);
  return NULL;
}

static List Compiler._convert_reference(
  Compiler c, List expr, Type type, Type target) {
  // T -> &T: pass the address of an addressable value.
  if (type === cdr(target) &&
      (target.car() == <&> || target.car() == <opt-ref>)) {
    if (!c._expression_is_addressable(expr))
      c.report_error(
        <type>, "reference argument must name an addressable object",
        NULL, NULL);
    return %(expr $target (op & (parens $expr)));
  }
  if (type.car() == <&> && target.car() == <opt-ref> &&
      cdr(type) === cdr(target))
    return %(expr $target $expr);
  if (cdr(type) == cdr(target) && type.car() == <&> && target.car() == <*>)
    return %(expr $target $expr);
  if (type.car() == <&> && cdr(type) === target)
    return %(expr $target (op * (parens $expr)));
  return NULL;
}

/** Converts a resolved interpolation segment to `String` when available.
    A missing `String` conversion is expected: the transform boxes that segment
    to `Var` and renders it at runtime.

    A declared numeric converter keeps its formatting; other numeric segments
    use `Var.str`. A segment statically spelled `Var` also uses `Var.str` for
    every
    runtime tag. The ordinary `Var`-to-`String` conversion is
    not equivalent: it
    extracts only a `String` payload and yields empty `String` for every other
    tag.
*/
List Compiler.convert_segment_to_string(Compiler c, List expr) {
  Type type = expr.cadr().type().canonicalize();
  if (c.sym.is_var_type(type))
    return %(expr ("String") (call "Var_str" (args $expr)));
  if (!c.sym.resolve_numeric_type(type))
    return c.convert_expression(expr, %("String"));
  List converted = c._converter_call(expr, type, %("String"));
  if (converted) return converted;
  List boxed = c.convert_expression(expr, %("Var"));
  return %(expr ("String") (call "Var_str" (args $boxed)));
}

// Var crossings

static List Compiler._read_var(
  Compiler c, List expr, Type type, Type target) {
  if (target === %("Symbol"))
    return %(expr $target (call "Var_symbol" (args $expr)));
  Type scalar_target = c.sym.resolve_numeric_type(target);
  if (scalar_target) {
    Symbol tag = scalar_target.scalar_tag();
    if (!tag && scalar_target.is_enum()) tag = <i32>;
    String extractor = scalar_target.var_numeric_extractor();
    if (extractor) {
      String tagsym = %"${(unsigned long) tag}";
      List converted = %(expr ("Var") (call "Var_convert" (args
        $expr (expr ("Symbol") $tagsym))));
      return %(expr $target (call $extractor (args $converted)));
    }
  }
  List reader = c._var_checked_reader(expr, type, target);
  if (reader) return reader;
  /* A Var reaching `Var *` almost always meant its address; unboxing a
     stored Var pointer must be spelled. */
  if (target.is_pointer() && c.sym.is_var_type(target.dereference()))
    c.report_error(
      <type>, %"cannot convert Var to ${target.repr()}", NULL,
      %("write &value for its address, or value.pointer() to unbox a stored pointer"));
  if (target.is_pointer())
    return %(expr $target (call "Var_pointer" (args $expr)));
  if (target.is_typedef_name()) {
    // Unknown system typedefs have no proven pointer payload reader.
    Type resolved = c.sym.resolve_key(target);
    if (resolved.is_pointer())
      return %(expr $target (call "Var_pointer" (args $expr)));
    String message = %"cannot convert Var to type ${target.repr()}";
    c.report_error(<type>, message, NULL, NULL);
  }
  return NULL;
}

/* A built-in payload has an exact tag-checked reader, and a Var(T)
   participant declares its own reverse converter. Either takes the crossing
   ahead of the unchecked pointer payload. An alias with neither reads
   through its nearest ancestor that has one, so an alias of `String` checks
   the tag exactly as `String` does. */
static List Compiler._var_checked_reader(
  Compiler c, List expr, Type type, Type target) {
  List owners = target.is_bare_typedef_name()
              ? c._typedef_names(target).list_free() : %($target);
  foreach (Type owner, owners) {
    List reader = c._var_exact_reader(expr, owner);
    if (!reader) reader = c._converter_call(expr, type, owner);
    if (reader)
      return owner == target ? reader : %(expr $target ${reader.caddr()});
  }
  return NULL;
}

/* The exact reader for a built-in Var payload is `Var.<target>`: it checks the
   tag and yields NULL for any other kind. `Var.pointer` checks nothing, so
   trying it first let a List-valued Var read as a String. Only a raw native
   pointer with no typed Var reader should still take that path. */
static List Compiler._var_exact_reader(Compiler c, List expr, Type target) {
  if (!target.match(%(?))) return NULL;
  String reader = %"Var_${target.car().str().lower()}", Type readertype = NULL;
  List binding = c.sym.resolve_global(%($reader), readertype);
  if (!binding || !readertype || readertype.car() is not <list>) return NULL;
  List function = readertype.car();
  (Var function_tag, List parameters) = function;
  if (function_tag != <func> || !parameters || parameters.cdr() ||
      !List.equal(parameters.car(), %("Var")) ||
      !readertype.cdr().equal(target))
    return NULL;
  List callee = %(expr $readertype (ident $binding));
  Macro called = $called;
  return c.rebuild_expression(target, called(callee, %($expr)));
}

/* A declared T.var converter owns custom boxing before tag based boxing. */
static List Compiler._declared_var_converter(
  Compiler c, List expr, Type type) {
  Type converter_type = type;
  String converter = converter_type.var_converter();
  if (!converter) {
    c.sym.var_tag_for_type(type, converter_type);
    converter = converter_type.var_converter();
  }
  if (!converter) return NULL;
  String typename = converter_type.car().str(), Type cvrtrtype = NULL;
  List converter_binding = c.sym.resolve_global(%($converter), cvrtrtype);
  if (cvrtrtype === %((func (($typename))) "Var")) {
    List argument = type == converter_type
      ? expr : %(expr $converter_type $expr);
    List callee = %(expr $cvrtrtype (ident $converter_binding));
    Macro called = $called;
    return c.rebuild_expression(%("Var"), called(callee, %($argument)));
  }
  String message = %"cannot convert ${type.repr()} to Var without loss";
  c.report_error(<type>, message, NULL, NULL);
}

static List Compiler._box_var(Compiler c, List expr, Type type) {
  Type tagged_type = NULL;
  Symbol tag = c.sym.var_tag_for_type(type, tagged_type);
  if (!tag && tagged_type && tagged_type.is_enum()) tag = <i32>;
  if (tag) {
    String box = NULL;
    switch (tag) {
      case <long>: box = "Var_box_long"; break;
      case <ulong>: box = "Var_box_ulong"; break;
      case <llong>: box = "Var_box_long_long"; break;
      case <ullong>: box = "Var_box_ulong_long"; break;
      case <ldouble>: box = "Var_box_long_double"; break;
    }
    if (box) return %(expr ("Var") (call $box (args $expr)));
    String tagsymnumstr = %"${(unsigned long) tag}";
    return %(expr ("Var") (call "Var_new" (args
                (expr ("Symbol") $tagsymnumstr) $expr)));
  }
  String message = %"cannot convert ${type.repr()} to Var without loss";
  // Conversion runs after parsing; a NULL token anchors the statement.
  c.report_error(<type>, message, NULL, NULL);
}

// converter calls

/* The call to the converter that `type`, or the first of its typedef names
   that declares one, provides for `target`, or NULL. */
static List Compiler._converter_call(
  Compiler c, List expr, Type type, Type target) {
  if (!type.match(%(?)) || !target.match(%(?))) return NULL;
  List owners = type.is_bare_typedef_name()
              ? c._typedef_names(type).list_free() : %($type);
  foreach (Type owner, owners) {
    if (owner == target) return NULL;
    int declared = 0;
    List converted = c._converter_owned_call(expr, owner, target, declared);
    if (converted || declared) return converted;
  }
  return NULL;
}

/** The call to the converter `type` declares for `target`, applied to
    `expr`, or NULL when it declares none. */
List Compiler.converter_call(Compiler c, List expr, Type type, Type target) =>
  c._converter_call(expr, type, target);

static List Compiler._converter_owned_call(
  Compiler c, List expr, Type owner, Type target, int &declared) {
  String typename = owner.car().str();
  String convfuncname = _converter_name(owner, target);
  Type cvrtrtype = NULL;
  List converter_binding = c.sym.resolve_global(
    %($convfuncname), cvrtrtype);
  declared = !!converter_binding || !!cvrtrtype;
  List callee = %(expr $cvrtrtype (ident $converter_binding));
  List argument = expr.cadr() == owner
    ? expr : %(expr $owner $expr);
  Macro called = $called;
  if (cvrtrtype && cvrtrtype.car() is <list>) {
    List function = cvrtrtype.car();
    (Var function_tag, List parameters) = function;
    Type result = cvrtrtype.cdr();
    if (function_tag == <func> &&
        parameters && !parameters.cdr() &&
        List.equal(parameters.car(), owner) &&
        result.equal(target)) {
      List call = c.rebuild_expression(
        target, called(callee, %($argument)));
      return c._converted_temporary(call, owner, target);
    }
  }
  /* The relaxed form exists so a converter may spell its parameter as a
     typedef of the source type, which the exact comparison above rejects.
     It still takes exactly one argument: matching a longer parameter list
     emitted a call with the arguments missing. */
  if (cvrtrtype.match(%((func (($typename))) ?))) {
    List call = c.rebuild_expression(
      target, called(callee, %($argument)));
    return c._converted_temporary(call, owner, target);
  }
  return NULL;
}

/* A package converter uses the package spelling of the external owner. */
static String _converter_name(Type owner, Type target) {
  String typename = owner.car().str(), targetedname = target.car().str();
  String prefix = "";
  int split = targetedname.find("__");
  if (split > 0) {
    prefix = targetedname[0:split + 2];
    targetedname = targetedname[split + 2:];
  }
  return targetedname == "String"
    ? %"$prefix${typename}_str"
    : %"$prefix${typename}_${targetedname.lower()}";
}

/* A converter's result exists only for the operator that asked for it.
   Only a conversion from a number is known to be fresh; a converter from a
   handle type may return storage its source still owns. */
static List Compiler._converted_temporary(
  Compiler c, List call, Type owner, Type target) {
  if (c.sym.resolve_numeric_type(owner) &&
      c.resolve_protocol_member(target, "discard")) {
    Macro called = $called;
    match (call) case called(?callee, *arguments):
      match (callee) case %(expr ? ${$source_identifier_content(
          %((!set ?binding (*))))}):
        c._note_fresh_callee(binding);
  }
  return call;
}

// conversion checks

static void Compiler._check_null_reference(
  Compiler c, List expr, Type target) {
  if (target.car() != <&>) return;
  if (_integer_literal_kind(expr, NULL) == <zero> ||
      (expr.match(%(expr () ${$source_identifier_content(
        %((binding ? ?)))})) &&
       binding_identity_spelling(expr.caddr().cadr()) == "NULL"))
    c.report_error(
      <type>, %"cannot pass a null pointer where ${target.repr()} is expected",
      NULL, %("a reference argument must name an object"));
}

/* Same-address conversions must keep qualifiers, including void pointers. */
static void Compiler._check_qualifiers(
  Compiler c, Type type, Type target, Type source, Type destination) {
  int take_reference =
    (target.car() == <&> || target.car() == <opt-ref>) &&
    type === cdr(target);
  Type qualified = take_reference ? source.reference() : source;
  if ((take_reference || type == target || cdr(type) == cdr(target) ||
       (type.is_pointer() && target.is_pointer() &&
        (destination.base_type() === %(void) ||
         source.base_type() === %(void)))) &&
      qualified.discards_qualifiers(destination)) {
    String message =
      %"cannot convert ${source.repr()} to ${destination.repr()}";
    c.report_error(
      <type>, message, NULL,
      %("the target drops a type qualifier the source declares: spell the qualifier in the target, or copy the value"));
  }
}

static void Compiler._check_reference_value(
  Compiler c, Type type, Type target) {
  /* An optional reference forwards only to another address type. */
  if (type.car() == <opt-ref> && target.car() != <&> &&
      target.car() != <opt-ref> && !c.sym.resolve_key(target).is_pointer())
    c.report_error(
      <type>, "check optional reference before using its value", NULL, NULL);
  /* A reference takes an lvalue of its referenced type. */
  if ((target.car() == <&> || target.car() == <opt-ref>) &&
      type.car() != <&> && type.car() != <opt-ref> &&
      type !== cdr(target))
    c.report_error(
      <type>, %"cannot pass ${type.repr()} where ${target.repr()} is expected",
      NULL, %("pass an lvalue of the referenced type; write *p for a pointer"));
}

static void Compiler._check_object_pointer(
  Compiler c, Type type, Type target, int type_is_var) {
  if (target.car() != <*> || type_is_var) return;
  Type source = c.sym.resolve_key(type);
  if (source && !source.is_pointer() && !source.is_array() &&
      !source.is_function())
    c.report_error(
      <type>, %"cannot pass ${type.repr()} where ${target.repr()} is expected",
      NULL, %("write &value to pass its address"));
}

/* C accepts null pointer constants, pointer decay, and opaque system types.
   Reject only a proven nonzero integer, unrelated known pointers, or two
   typedef names that share a C representation without a declared crossing. */
static void Compiler._check_native_crossing(
  Compiler c, List expr, Type type, Type target,
  Type declared_source, Type declared_target) {
  String integer = c._not_null_pointer_constant(expr);
  if (integer && c.sym.resolve_key(target).is_pointer()) {
    String message =
      %"cannot convert the integer $integer to pointer type ${target.repr()}";
    List hint =
      %( "only a zero integer constant expression converts to a pointer" );
    c.report_error(<type>, message, NULL, hint);
  }
  if (c._unrelated_pointers(type, target)) {
    String message =
      %"cannot convert ${declared_source.repr()} to ${declared_target.repr()}";
    c.report_error(
      <type>, message, NULL,
      %("the pointer types are unrelated: cast the expression to say so on purpose"));
  }
  if (declared_source.is_bare_typedef_name() &&
      declared_target.is_bare_typedef_name() &&
      !declared_source.equal(declared_target) &&
      c.sym.resolve_key(declared_target).is_pointer() &&
      c.sym.resolve_key(declared_source).base_type() !== %(void) &&
      !c._typedef_names(declared_source).contains(declared_target) &&
      !c._typedef_names(declared_target).contains(declared_source)) {
    String message =
      %"cannot convert ${declared_source.repr()} to ${declared_target.repr()}";
    c.report_error(
      <type>, message, NULL,
      %("the names share one C type but not one meaning: declare the converter ${declared_source.car()}_${declared_target.car().str().lower()}, or cast the expression to say so on purpose"));
  }
}

/* Report whether two types point at provably different things.  Every
   level of both chains is resolved through the typedef table first, so a
   spelling difference, Ast against List or Pool against struct Pool *, is
   not a difference here. */
static int Compiler._unrelated_pointers(Compiler c, Type source, Type target) {
  source = c.sym.resolve_key(source);
  target = c.sym.resolve_key(target);
  if (!source.is_pointer() || !target.is_pointer()) return 0;
  loop {
    source = c.sym.resolve_key(source.cdr());
    target = c.sym.resolve_key(target.cdr());
    if (source == target) return 0;
    if (!source.is_pointer() || !target.is_pointer())
      return _known_pointee(source) && _known_pointee(target);
  }
}

/* What a pointer may point at for the rule below to call two pointers
   different: a named struct, union, or enum, or a builtin scalar.  void is
   excluded because C converts it, and a function, an array, or a name the
   resolver left untouched is excluded because the compiler does not know
   enough about it to say. */
static int _known_pointee(Type type) {
  if (type === %(void)) return 0;
  return type.is_aggregate_tag() || type.is_enum_tag() || !!type.scalar();
}

/* A proven nonzero operand yields its short spelling; unknown forms yield
   NULL. C11 6.3.2.3p3 requires an integer constant expression with value zero,
   not just the token 0. x2c does not fold constants, so this recognizes
   only syntactically decidable forms. A wrong guess would reject legal C. */
static String Compiler._not_null_pointer_constant(Compiler c, List expr) {
  match (expr) {
    case %(expr ? ${$source_content_pattern($grouped, %(?inner))}):
      return c._not_null_pointer_constant(inner);
    // sizeof is an integer constant expression, but never a zero-valued
    // one: no type in C has size zero.
    case %(expr ? ${$source_content_pattern(
        $sizeof_grouped, %(?operand))}):
      return "sizeof";
    case %(expr ? ${$source_content_pattern(
        $sizeof_expression, %(?operand))}):
      return "sizeof";
    // Unary minus or plus over a nonzero literal is still nonzero.  The
    // pattern has a fixed length, so a binary use of the same operator,
    // which would need folding, does not match it.
    case %(expr ? ${$source_operator_content(%(?oper ?operand))}): {
      Symbol op = oper;
      if (op != <-> && op != <+>) return NULL;
      String inner = NULL;
      if (_integer_literal_kind(operand, inner) != <nonzero>) return NULL;
      return %"$op$inner";
    }
    // A variable is never a permitted operand of an integer constant
    // expression, so an integral one cannot spell a null pointer even when
    // it happens to hold zero at run time.  Enumerations are excluded
    // because an enum constant and a variable of enum type are spelled
    // identically here, and a zero-valued enum constant *is* a null pointer
    // constant.
    case %(expr ?type ${$source_identifier_content(
        %((binding ? ?name)))}): {
      Type vartype = c.sym.resolve_numeric_type(type);
      if (!vartype || vartype.is_enum() || !vartype.is_integral()) return NULL;
      return name;
    }
  }
  String spelling = NULL;
  if (_integer_literal_kind(expr, spelling) != <nonzero>) return NULL;
  return spelling;
}

/* Answer whether an expression is certainly a zero integer literal,
   certainly a nonzero one, or neither.  Parentheses are unwrapped because
   they are the one wrapper that folds away without evaluation, and
   `out_text` receives the spelling when there is one.

   The tokenizer already accepted the spelling and Type.numeric_literal
   already turned its prefix and suffix into the node's own type, so what
   remains here is whether a digit is nonzero.  A float, a name, or an enum
   constant answers <unknown>; the null-pointer guard below stays silent
   when it cannot decide. */
static Symbol _integer_literal_kind(List expr, String &?out_text) {
  match (expr) {
    case %(expr ? ${$source_content_pattern($grouped, %(?inner))}):
      return _integer_literal_kind(inner, out_text);
    case %(expr ? ${$source_literal_content(%(?ltype ?text))}): {
      String spelling = text, Type type = ltype;
      if (!spelling || !type.is_integral()) return <unknown>;
      char *s = spelling;
      // A character constant is integral too, but it is not spelled in
      // digits, and '\0' is a null pointer constant.
      if (s[0] < '0' || s[0] > '9') return <unknown>;
      if (out_text) out_text = spelling;
      char radix = s[0] == '0' ? s[1] : 0;
      int i = radix == 'x' || radix == 'X' || radix == 'b' ||
              radix == 'B' || radix == 'o' || radix == 'O' ? 2 : 0;
      for (; s[i] && s[i] != 'u' && s[i] != 'U' &&
             s[i] != 'l' && s[i] != 'L'; i++)
        if (s[i] != '0') return <nonzero>;
      return <zero>;
    }
  }
  return <unknown>;
}
