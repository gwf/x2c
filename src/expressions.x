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
$(import "../src/ast-rewrite.xmacro")
$(import "../src/grammar.xmacro")
#include "parse.x"
#include "literals.x"
#include "protocol.x"
#include "transform.x"
#include "stage.x"
#include "initializers.x"
#include "macros.x"

$(import "../src/expressions-reports.xmacro")

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
    $report.type.optional_ref_assign(c, origin);
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
    case %(expr ? ${$grouped(?target)}): {
      if (_destructure_identifier(target)) return %(targets $target);
      match (target)
        case %(expr ? ${$source_commas_content(%(*targets))}): {
          foreach (List entry, targets) {
            if (_destructure_identifier(entry)) continue;
            $report.parse.destructure_target(c);
          }
          return %(targets @targets);
        }
    }
  return NULL;
}

static int _destructure_identifier(List expression) {
  match (expression) {
    case %(expr ? ${$source_identifier_content(%(?))}): return 1;
    case %(expr ? ${$grouped($dereferenced(%(expr (& *)
        ${$source_identifier_content(%(?))})))}):
      return 1;
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
  return c.resolve_expression(
    source_operator_expression(
      NULL, %(? $condition $ontrue ${c.parse_conditional()})), origin);
}

static List Compiler._parse_binary_ops(Compiler c) =>
  c._parse_binary_level(1);

/* Larger levels of `Symbol.binary_precedence` bind more tightly. The
   recursive parser descends to level 10 before consuming operators while
   each level folds left; `is` shares the relational level but is recognized
   from its identifier spelling. */
static List Compiler._parse_binary_level(Compiler c, int level) {
  if (level > 10) return c._parse_cast();
  return c._parse_binary_level_tail(level, c._parse_binary_level(level + 1));
}

static List Compiler._parse_binary_level_tail(
  Compiler c, int level, List lhs) {
  int first = 1;
  while (c._binary_operator().binary_precedence() == level ||
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
      $report.type.is_array(c, origin);
    if (c.peek(0) == <(>)
      $report.type.is_function(c, origin);
    c.expect(<)>);
  }
  else if (type.is_pointer())
    $report.parse.is_pointer(c, origin);
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
        List cast = c._finish_cast(
          decl, parameter.type_from_ast(), c._parse_cast(), origin);
        return c._finish_paren_statement(cast, 0);
      }
    foreach (List parameter, parameters)
      c.check_reference_placement(parameter.type_from_ast());
    c.expect(<=>);
    List source = c.parse_assignment();
    c.expect(<;>);
    return c.anchor_origin(
      %(dstrdecl (params @parameters) $source), origin);
  }

  return c._finish_paren_statement(c._parse_group_rest(), 1);
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
      Type type = NULL;
      List decl = c.parse_type_operand(&type);
      c.expect(<)>);
      return c._finish_cast(decl, type, c._parse_cast(), head);
    }
  }
  c.token = head;
  return c._parse_unary_op();
}

/* Types the cast of `operand` to `decl`, which declares `type`, and warns
   when the cast changes nothing. A template typedef or an operand typed at
   expansion leaves the cast typed at expansion too. */
static List Compiler._finish_cast(
  Compiler c, List decl, Type type, List operand, Token origin) {
  if (operand.cadr() === %(<macro-expr>) ||
      c._casts_to_template_typedef(decl))
    type = %(<macro-expr>);
  c._warn_unnecessary_cast(operand, type, origin);
  return %(expr $type ${source_cast_content(%($decl $operand))});
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
  $report.conversion.cast_redundant(c, target, origin);
}

/* Whether C gives an operand the type x2c records. A character constant is
   `int` in C; `sizeof`, `offsetof`, and a pointer difference have `size_t`
   and `ptrdiff_t` identities selected by the native toolchain; an enum's
   compatible integer type is implementation-defined; C compilers type a
   bitfield differently. */
static int Compiler._c_type_known(Compiler c, List operand) {
  match (operand) {
    case %(expr ? ${$grouped(?inner)}):
      return c._c_type_known(inner);
    case %(expr ? ${$source_literal_content(%((char) *))}): return 0;
    case %(expr ? ${$sizeof_grouped(?operand)}): return 0;
    case %(expr ? ${$sizeof_expression(?operand)}): return 0;
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
  int increment = op in increments;
  if (!increment && !(op in unary_operators)) return c._parse_postfix();
  c.next();
  List operand = increment ? c._parse_unary_op() : c._parse_cast();
  return c.resolve_expression(
    source_operator_expression(NULL, %($op $operand)), origin);
}

static List Compiler._parse_sizeof(Compiler c) {
  c.expect(<sizeof>);
  int parens = c.test(<(>);
  Token head = c.token;
  List arg = NULL;
  if (c.test_declaration()) arg = c.parse_type_operand(NULL);
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
  return %(expr ("size_t") (sizeof $arg));
}

/* `offsetof` names its member with a C member designator: a field, then
   any `.field` and `[index]` selections, kept as their C spelling. */
static List Compiler._parse_offsetof(Compiler c) {
  c.next();
  c.expect(<(>);
  Type type = c.parse_type_name();
  c.expect(<,>);
  List member = c.parse_basic_identifier();
  for (;;) {
    if (c.test(<.>))
      member = %(@member "." @{c.parse_basic_identifier()});
    else if (c.test(<[>)) {
      member = %(@member "[" ${c.parse_expression()} "]");
      c.expect(<]>);
    }
    else break;
  }
  c.expect(<)>);
  return %(expr ("size_t") (offsetof $type $member));
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
  if (step && step.match(
    %(expr ? ${$source_literal_content(%(? "0"))})))
    $report.parse.slice_zero(c);
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
    return c.apply_macro_value(expr, supplied, origin);
  Macro called = $called;
  List result = c.resolve_expression(
    c.rebuild_expression(NULL, called(expr, supplied)), origin);
  int method = !!expr.match(
    %(expr () ${$source_operator_content(%(. ? (?)))}));
  c._check_converter_args(result, method, notes.list_free());
  if (method && supplied === %((expr (void) ())))
    match (expr) case %(expr () ${$source_operator_content(
        %(. ? (?name)))}):
      c._note_explicit_converter(result, name.str(), origin);
  return result;
}

/** Applies the Macro value `expr` to `supplied` argument expressions.
    Inside a template body the call is retained so the template can capture
    the value it applies; elsewhere it is an ordinary `Macro_apply` over the
    argument values. */
List Compiler.apply_macro_value(
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
  if (!field_name || !field_name.is_identifier())
    $report.parse.member_ident(c, op_sym, lhs_opt);
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
    case <$>:
      return c.peek(1) == <!> ? c.parse_macro_quotation()
                              : c.try_parse_macro_expression();
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
    /* Inside a template the value is made where the template expands, once
       the names its body shares with the template are that expansion's. */
    if (c.macro_holes) return %(expr ("Macro") (macro-value $definition));
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
  if (c.token.text == "offsetof") return c._parse_offsetof();
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
      definition == <string>) {
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
    return definition == <string>;
  return !c.sym.get(%(${c.token.text}));
}

static List Compiler._parse_parens(Compiler c) {
  c.expect(<(>);
  return c._parse_group_rest();
}

/* Parses a group after its `(` through the closing `)`. */
static List Compiler._parse_group_rest(Compiler c) {
  if (c._statement_expression_follows()) {
    Token origin = c.token;
    c.expect(<"{">);
    List block = c.parse_compound_statement();
    c.expect(<)>);
    return c._statement_expression(block, origin);
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
static int Compiler._statement_expression_follows(Compiler c) {
  if (c.peek(0) != <"{">) return 0;
  int hole = 0, comma = 0;
  for (Token token = Token.skip_trivia(c.token + 1);;
       token = token.after_group()) {
    Symbol type = token.type;
    if (type == <;>) return 1;
    if (type == <eof> || type == <"}">) return hole && !comma;
    if (type == <,>) comma = 1;
    if (type == <$> && c.macro_holes) hole = 1;
  }
}

/* A statement expression has the value and type of its final expression
   statement, and is void otherwise. A defer directly inside would wrap that
   statement in a cleanup region, and C would lose the value. A template
   binds its statement expression where it expands. */
static List Compiler._statement_expression(
  Compiler c, List block, Token origin) {
  List items = Ast.without_origin(block).cdr();
  if (_defers_directly(items))
    $report.parse.statement_defer(c, origin);
  Type type = c.macro_holes ? %(<macro-expr>) : _final_value_type(items);
  return %(expr $type (parens $block));
}

static int _defers_directly(List items) {
  foreach (List item, items)
    match (Ast.without_origin(item)) {
      case %(defer ?): return 1;
      case %(seq *rows): if (_defers_directly(rows)) return 1;
    }
  return 0;
}

/* Reference reads retain their resolved type through the last expression. */
static Type _final_value_type(List items) {
  List last = items ? Ast.without_origin(items.last()) : NULL;
  match (last)
    case %(stmnt (expr ?(Type type) ?)): return type;
  return %(void);
}

static List Compiler._parse_composite(Compiler c) {
  c.expect(<"{">);
  if (c._brace_starts_map()) {
    List entries = c.parse_map_entries();
    c.expect(<"}">);
    return %(expr ("Map") (map @entries));
  }
  List elems = c._parse_composite_elements();
  c.expect(<"}">);
  return %(expr () ${source_composite_content(elems)});
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

/* A sequence hole splices initializer elements, as it splices call
   arguments; a Lisp slot or meta call stays one element. */
static List Compiler._parse_composite_elements(Compiler c) {
  Array elements = [];
  while (c.peek(0) != <"}">) {
    List hole = c.peek_macro_hole();
    List element = hole && hole.assoc(<sequence>).int()
                 ? c.try_parse_macro_slot(<argument>) : NULL;
    if (!element)
      element =
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
  Type type = NULL;
  List decl = c.parse_type_operand(&type);
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
    /* A quotation or macro value application that hand-built syntax holds
       expands where it is resolved, like one the binder meets directly. */
    case %((!or "x2c.template" "x2c.quoted" macro-invoke) *):
      return c.bind_syntax(input, AST_EXPRESSION, c.return_type);
    case %(expr ?type ?(List content)): {
      if (type && !c.needs_resolution(input)) return input;
      return c._resolve_content(input, type, content, origin);
    }
  }
  return input;
}

/** True when syntax still needs ordinary binding or macro substitution. */
int Compiler.needs_resolution(Compiler c, Var value) {
  Macro lambda = $lambda_expression, captured = $lambda_captured;
  List syntax;
  $ast.walk(value, syntax)
    match (syntax) {
      case %(expr (!or () (<macro-expr>)) ?): return 1;
      case %(expr ? (parens (block *))): continue;
      case captured(?body, *captures, *params): {
        foreach (List row, captures)
          match (row) case %(capture ?binding ? ?):
            if (!(%(lambda-depth $binding) in c.semantic_binding_facts()))
              return 1;
        continue;
      }
      case lambda(?body, *params): return 1;
      case %(at m-origin ?):
        if (c.source_map && !c.macro_holes) return 1;
      case %((!or macro-bind macro-invoke macro-slot meta-call macro-value
                  "x2c.quoted") *):
        return 1;
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
  return 0;
}

static int Compiler._identifier_needs_resolution(
  Compiler c, List binding) {
  String spelling = binding_identity_spelling(binding);
  Map facts = c.semantic_binding_facts();
  int retained_parameter = %(lambda-param $binding) in facts;
  int retained_capture = %(lambda-depth $binding) in facts;
  if (c.lambda_capture_required(binding)) return 1;
  if (retained_parameter && c.local_macro_captures != NULL) return 1;
  Var type;
  if (%(automatic $binding) in facts &&
      facts.try_get(%(type $binding), type) && type is <list> &&
      type.list() !== %(<macro-expr>)) return 0;
  return !spelling ||
    (c.sym.lookup(%($spelling), NULL) != binding &&
     !retained_parameter && !retained_capture);
}

// True when a receiver's type must wait for macro substitution.
static int _deferred_receiver(List expr) {
  match (expr) case %(expr (<macro-expr>) ?): return 1;
  return 0;
}

/* The semantic context of one expression resolution; handlers share its
   original input, expected type and diagnostic origin. */
typedef struct Resolve {
  Compiler c;
  List input;
  Type type;
  Token origin;
} Resolve;

static List Compiler._resolve_content(
  Compiler c, List input, Type input_type, List content, Token origin) {
  Resolve r = {.c = c, .input = input, .type = input_type, .origin = origin};
  return r._content(content);
}

static List Resolve._content(Resolve &r, List content) {
  Macro lambda = $lambda_expression, captured = $lambda_captured;
  match (r.input) {
    case captured(?body, *rows, *params): return r._lambda(body, rows, params);
    case lambda(?body, *params): return r._lambda(body, NULL, params);
  }
  if (content && (content.car() == <at> || content.car() == <src>))
    return r._source(content);
  if (content && content.car() == <expr>)
    match (content) case %(!set ?inner (expr ? ?)):
      return r.c.resolve_expression(inner, r.origin);
  Macro indexed = $indexed;
  match (r.input) {
    case indexed(?base, ?index):
      return r.c._resolve_indexed(base, index, r.origin);
  }
  match (content) {
    case %(call ?(String callee) (args *args)): return r._native(callee, args);
  }
  match (r.input) case $called(?callee, *args): return r._call(callee, args);
  match (content) {
    case %(managed-init ?value): return r._managed_init(value);
    case $source_identifier_content(%(?value)):
      return r.c._resolve_identifier(value, r.type, r.origin);
    case %(!set ?binding (binding ? ?)): return r._binding(binding);
    case $source_literal_content(%(*)): return r.input;
    case %(tpl-call *): return r.input;
    case %(macro-value ?form): return r.c.capture_macro_value(form);
    case %(meta-call ? (args *)): return r._meta_call();
    case %(meta-cap *): return r.input;
    case %(macro-invoke *): return r._invocation(content);
    case %("x2c.quoted" *):
      return r.c.bind_syntax(content, AST_EXPRESSION, r.c.return_type);
    case %(macro-slot ? ? *): return r._macro_slot(content);
    case $source_string_content(%(*items)): return r._segments(items);
    case %(cons ?head ?tail): return r._cons(head, tail);
    case %(append ?head ?tail): return r._append(head, tail);
    case $source_slice_content(%(? ? ? ?)): return r._slice(content);
    case %(getindex ?base ?index): return r._getindex(base, index);
    case %(dstrasgn (targets *rows) ?value):
      return r._destructure(rows, value);
    case $source_content_pattern($sizeof_grouped, %(?value)):
      return r._sizeof($sizeof_grouped, value);
    case $source_content_pattern($sizeof_expression, %(?value)):
      return r._sizeof($sizeof_expression, value);
    case $source_generic_content(%(?control *rows)):
      return r._generic(control, rows);
    case $source_va_arg_content(%(?expr ?decl)): return r._va_arg(expr, decl);
    case $source_commas_content(%(*items)): return r._commas(items);
    case %(splice ?value): return r._splice(value);
    case %((!or offsetof nil cache macro-bind) *): return r.input;
    case $source_content_pattern($grouped, %(?inner)): return r._parens(inner);
    case %(initval *): return r._initval(content);
    case $source_composite_content(%(*items)): return r._composite(items);
    case $source_cast_content(%((!set ?decl (decl *)) ?value)):
      return r._cast(decl, value);
    case %(type-tag ?target): return r.c.var_tag_expression(target, r.origin);
    case $source_content_pattern($has_type, %(?value ?target)):
      return r._is_type(value, target);
    case $source_content_pattern($has_symbol, %(?value ?tag)):
      return r._is_symbol(value, tag);
    case $source_operator_content(%(*parts)): return r._operator(parts);
    case $source_postfix_content(%(?op ?value)): return r._postfix(op, value);
    case %(tadapt ?target ?value): return r._tadapt(target, value);
  }
  if (content && content.car() == <array>) return r._array_value();
  if (content && content.car() == <map>) return r._map_value();
  return r.input;
}

static List Resolve._operator(Resolve &r, List parts) {
  match (parts) {
    case %((!or (!set ?op .) (!set ?op (!quote ->)))
           ?receiver (!set ?field (*))):
      return r._member(op, receiver, field);
    case %(?op ?value): return r._unary(op, value);
    case %(?op ?test ?yes ?no): return r._conditional(op, test, yes, no);
    case %(?op ?left ?right): return r._binary(op, left, right);
  }
  return r.input;
}

static List Resolve._binding(Resolve &r, List binding) {
  if (!binding_identity_try_parts(binding, NULL, NULL)) return r.input;
  return r.c._resolve_identifier(binding, r.type, r.origin);
}

static List Resolve._lambda(
  Resolve &r, List body, List captures, List params) {
  if (r.c.macro_holes) return r.input;
  return r.c.bind_lambda_expression(
    r.type, %(params @params), captures, body);
}

static List Resolve._source(Resolve &r, List content) {
  match (content) case %(at m-origin ?inner): {
    if (!r.c.source_map || r.c.macro_holes) return r.input;
    return %(expr ${r.type} (at ${r.c.origin} $inner));
  }
  return r.input;
}

static List Resolve._meta_call(Resolve &r) {
  if (r.c.meta_body || r.c.macro_holes) return r.input;
  if (r.origin == r.c.meta_statement && r.c.peek(0) == <;>) return r.input;
  return r.c.evaluate_meta_expression(r.input, r.origin);
}

/* An invocation expands where it is resolved, as the binder expands one,
   except in a template, whose expansion expands it. */
static List Resolve._invocation(Resolve &r, List content) {
  if (r.c.macro_holes) return r.input;
  return r.c.bind_syntax(content, AST_EXPRESSION, r.c.return_type);
}

static List Resolve._macro_slot(Resolve &r, List content) {
  if (r.c.macro_holes) return r.input;
  Var value = r.c.evaluate_macro_slot(content);
  match (value)
    case %(!set ?expression (expr ? ?)):
      return r.c.resolve_expression(expression, r.origin);
  return r.c.resolve_expression(
    r.c.lift_macro_lisp_expression(value, r.origin), r.origin);
}

// identifiers

static List Compiler._resolve_identifier(
  Compiler c, Var value, Type type, Token origin) {
  if (type === %(<macro-expr>)) type = NULL;
  int read_reference = !type;
  int require_type = 0;
  List binding = c._identifier_binding(value, type, origin, require_type);
  if (c.macro_holes && binding) {
    String name = binding_identity_spelling(binding);
    if (c.macro_holes[%(using $name)] is <list>)
      return %(expr (<macro-expr>) (ident (binding-global $name)));
    if (c._template_free_name(binding))
      return %(expr (<macro-expr>) (ident (binding-name $name)));
  }
  int macro_binder = value.is_binder() ||
    (value is <list> && !value.is_nil() &&
     value.car() == <macro-bind>);
  if (!binding && macro_binder) return %(expr (<macro-expr>) (ident $value));
  if (!binding) $report.type.binding_unknown(c, value, origin);
  Map binding_facts = c.semantic_binding_facts();
  String spelling = binding_identity_spelling(binding);
  c._capture_identifier(binding);
  int kept = 0;
  match (value) case %(binding-global *): kept = 1;
  if (c._shadow_identifier(binding, type, spelling, binding_facts, kept))
    type = NULL;
  if (!type) type = c._identifier_type(
    binding, spelling, binding_facts, origin);
  if (!type && require_type)
    $report.type.ident_semantic(c, value, origin);
  List result = %(expr $type (ident $binding));
  result = c._capture_lambda_value(result, binding, type, read_reference);
  return c._read_bound_reference(
    result, binding, type, read_reference, binding_facts);
}

static List Compiler._capture_lambda_value(
  Compiler c, List result, List &binding, Type &type, int &read_reference) {
  if (!c.lambda_scopes || c.macro_holes) return result;
  result = c.capture_lambda_identifier(binding, type);
  match (result)
    case %(expr ?captured_type ${$source_identifier_content(
        %(?captured))}): {
      if (type.car() != <&> && captured_type.car() == <&>)
        read_reference = 1;
      type = captured_type;
      binding = captured;
    }
  return result;
}

/* Parsed identifiers arrive as spellings, while constructed syntax may carry
   producer-issued binding identities. Semantic binding facts validate those
   identities before resolution. A visible local replaces a stale local
   identity; global shadow handling instead gives the visible declaration an
   emitted alias so the original identity keeps its meaning. A template's
   free name arrives as `binding-name` and binds where the expansion lands;
   a `using` name arrives as `binding-global` and binds at file scope. */
static List Compiler._identifier_binding(
  Compiler c, Var value, Type &type, Token origin, int &require_type) {
  require_type = value is <string>;
  if (value is <string>) return c.sym.reference(%($value), type);
  if (value is not <list>) return NULL;
  List name = value;
  int identity = 0;
  String spelling = NULL;
  if (binding_identity_try_parts(name, identity, spelling)) {
    Map facts = c.semantic_binding_facts();
    Var issued, source;
    if (!facts.try_get(%(known $identity), issued) ||
        issued is not <string> || issued.string() != spelling)
      $report.type.binding_unknown(c, name, origin);
    /* A template's private name that no declaration in scope reaches
       reads its source spelling where the expansion lands. A declared one
       keeps its identity, as when lowering binds code outside the scope
       that declared it. */
    if (facts.try_get(%(source-spelling $name), source) &&
        !(%(type $name) in facts) &&
        c.sym.lookup(%($spelling), NULL) != name)
      return c._landed_name(source, type);
    return name;
  }
  match (name) {
    case %("x2c.ident" ?(String spelling)): {
      require_type = 1;
      return c.sym.reference(%($spelling), type);
    }
    case %(binding-name ?(String spelling)):
      return c._landed_name(spelling, type);
    case %(binding-global ?(String spelling)):
      return c.sym.reference_global(%($spelling));
    case %((!is ? type string)):
      return c.sym.reference(name, type);
  }
  return NULL;
}

/* A name a template reads without declaring it binds where the expansion
   lands. A `Macro` local is a compile-time template the body composes, so
   an anonymous macro captures its value where it is written. */
static int Compiler._template_free_name(Compiler c, List binding) {
  if (!binding || c.macro_template_local(binding)) return 0;
  Var type = c.semantic_binding_facts()[%(type $binding)];
  return !(type is <list> && c.sym.is_named_value_type(type, "Macro"));
}

/* A template's name where its expansion lands: the visible declaration, or
   for a name nothing declares, one file-scope forward binding that C
   resolves. */
static List Compiler._landed_name(Compiler c, String spelling, Type &type) {
  List visible = c.sym.lookup(%($spelling), type);
  return visible ? visible : c.sym.reference_global(%($spelling));
}

static void Compiler._capture_identifier(Compiler c, List binding) {
  if (c.local_macro_captures == NULL || !binding ||
      !c.sym.binding_is_local_before(
        binding, c.local_macro_capture_scopes) ||
      binding in c.local_macro_captures) return;
  Var order = c.local_macro_captures[<order>];
  c.local_macro_captures[<order>] = cons(
    binding, order is <list> ? order : NULL);
  c.local_macro_captures[binding] = 1;
}

/* A visible local replaces a stale local identity. A declaration the
   active expansion introduced, such as one a caller's `Name` argument
   spells, supplies a file-scope name written in the caller's arguments,
   as it would where the expansion lands. Both return 1, since the
   identifier's type is the new binding's. Any other file-scope identity
   that a visible declaration hides, such as a name a template's `using`
   keeps, gives that declaration an emitted alias. */
static int Compiler._shadow_identifier(
  Compiler c, List &binding, Type type, String spelling, Map binding_facts,
  int kept) {
  if (!spelling) return 0;
  Type visible_type = NULL;
  List visible = c.sym.lookup(%($spelling), visible_type);
  if (!visible || visible == binding) return 0;
  if ((c.sym.binding_is_local(binding) &&
       !(%(lambda-depth $binding) in binding_facts)) ||
      (!kept && visible_type && c._expansion_introduced(visible))) {
    binding = visible;
    return 1;
  }
  if (visible_type &&
      (!type || c.sym.resolve_global(%($spelling), NULL)) &&
      !(%(emitted $visible) in binding_facts))
    c.set_fact(%(emitted $visible), c.fresh_name("binding_shadow"));
  return 0;
}

/* An active expansion issued `binding` after it began. */
static int Compiler._expansion_introduced(Compiler c, List binding) {
  int identity = 0;
  return c.macro_stack &&
         binding_identity_try_parts(binding, identity, NULL) &&
         identity > c.expansion_floor;
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
  $report.type.function_private(c, spelling, file, origin);
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
      return !(%(lambda-snapshot $binding) in c.semantic_binding_facts());
    case %(expr ? ${$indexed(?receiver, ?selector)}): return 1;
    case %(expr ? ${$source_operator_content(
        %((!quote *) ?operand))}): return 1;
    case %(expr ? ${$source_operator_content(
        %((!quote ->) ?receiver ?field))}): return 1;
    case %(expr ? ${$grouped(?base)}):
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
    $report.type.optional_ref_index(c, origin);
  if (_deferred_receiver(receiver) || _deferred_receiver(selector))
    return %(expr (<macro-expr>) (index $receiver $selector));
  List resolved = c._postfix_index_expression(receiver, selector);
  if (resolved) return resolved;
  Type receiver_type = receiver.cadr();
  // A field of a foreign struct has no x2c type; C indexes it alone.
  if (!receiver_type &&
      List.match(
        receiver, %(expr () ${$source_operator_content(%((!or . ->) * *))})))
    return %(expr () (index $receiver $selector));
  $report.parse.index_unsupported(c, receiver_type, origin);
}

static List Compiler._postfix_index_expression(
  Compiler c, List expr, List index) {
  Type type = expr.cadr(), element = type.dereference();
  if (element) return %(expr $element (index $expr $index));
  type = type.canonicalize();
  if (!type.is_typedef_name()) return NULL;
  return c._typedef_index(expr, index, type);
}

static List Compiler._typedef_index(
  Compiler c, List expr, List index, Type type) {
  int collection = c._collection_index_type(type);
  List resolved = c._nominal_getindex(type);
  if (!resolved && collection)
    resolved = c.resolve_protocol_member(type, "getindex");
  Type signature = resolved ? resolved.cadr() : NULL;
  match (signature)
    case %((func (!set ?params (?receiver ?))) ?rtype):
      if (collection || receiver == type)
        return c._getindex_expression(expr, index, params, rtype);
  return c._native_index(expr, index, type);
}

static int Compiler._collection_index_type(Compiler c, Type type) =>
  c.sym.is_named_value_type(type, "List") || c.sym.is_string_type(type) ||
  c.sym.is_array_type(type) || c.sym.is_map_type(type);

// Keep bracket admission and lowering on the same exact getter.
List Compiler._nominal_getindex(Compiler c, Type type) {
  if (!type.is_typedef_name()) return NULL;
  match (type)
    case %(?(String nominal)): {
      String source = %"${nominal}_getindex";
      if (source == c.fn_name && c._collection_index_type(type)) return NULL;
      Type signature = c.sym.get(%($source));
      match (signature)
        case %((func ($type ?)) ?):
          return %(${c.sym.reference(%($source), NULL)} $signature);
    }
  return NULL;
}

static List Compiler._getindex_expression(
  Compiler c, List expr, List index, Var params, Var rtype) {
  Type key = params.cadr(), supplied = index.cadr();
  if (key.is_integral() && c.sym.is_named_value_type(supplied, "Symbol"))
    $report.type.index_symbol(c);
  return %(expr ($rtype) (getindex $expr $index));
}

static List Compiler._native_index(
  Compiler c, List expr, List index, Type type) {
  Type native = c._index_native_type(expr.cadr());
  Type shape = native.canonicalize();
  // A boxable handle to a record has no C array reading.
  if (shape.is_pointer() && shape.dereference().is_aggregate() &&
      type.var_tag())
    $report.type.index_missing(c, type);
  // A typedef of a plain C pointer indexes as that pointer; `String` and
  // its aliases keep their protocol reading.
  if (shape.is_array() ||
      (shape.is_pointer() && !c.sym.is_string_type(type)))
    return %(expr ${native.dereference()} (index $expr $index));
  return NULL;
}

// Resolve the outer aliases without reducing the indexed element type.
static Type Compiler._index_native_type(Compiler c, Type native) {
  int hops = 0;
  loop {
    Type key = native.canonicalize();
    if (!key.is_bare_typedef_name() && !key.is_typedef()) break;
    Type next = c.sym.next_typedef(key, hops);
    if (!next) break;
    native = next.qualify(native);
  }
  return native;
}

static List Resolve._getindex(Resolve &r, List receiver, List selector) {
  return %(expr ${r.type}
           (getindex ${r.c.resolve_expression(receiver, r.origin)}
                     ${r.c.resolve_expression(selector, r.origin)}));
}

static List Resolve._slice(Resolve &r, List slice) {
  (List receiver, List start, List stop, List step) = slice.cdr();
  receiver = r.c.resolve_expression(receiver, r.origin);
  if (start) start = r.c.resolve_expression(start, r.origin);
  if (stop) stop = r.c.resolve_expression(stop, r.origin);
  if (step) step = r.c.resolve_expression(step, r.origin);
  List operation = source_slice_content(%($receiver $start $stop $step));
  if (r.type === %(<macro-expr>))
    operation = r.c.anchor_origin(operation, r.origin);
  return %(expr ${receiver.cadr()} $operation);
}

// calls

static List Resolve._native(Resolve &r, String callee, List supplied) {
  List arguments = r.c._resolve_call_arguments(NULL, supplied, r.origin);
  return %(expr ${r.type} (call $callee (args @arguments)));
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

static List Resolve._call(Resolve &r, List function, List supplied) {
  CallSite site = {
    .c = r.c, .result_type = r.type, .supplied = supplied,
    .origin = r.origin};
  match (function)
    case %(expr ? ${$source_operator_content(
        %(. ?receiver (!set ?field (?name))))}):
      return site._method(receiver, field);
  return site._function(function);
}

static List CallSite._function(CallSite &k, List function) {
  List resolved = k.c.resolve_expression(function, k.origin);
  Type type = resolved.cadr(), func_type = k.c.sym.resolve_key(%("Func"));
  if (type && k.c.sym.resolve_key(type) == func_type)
    return k.c._resolve_func_call(resolved, k.supplied, k.origin);
  return k._finish(k.result_type, resolved, type, NULL);
}

static List CallSite._finish(
  CallSite &k, Type result_type, List callee, Type callee_type,
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
  CallSite &k, Type callee_type, List arguments) {
  match (callee_type)
    case %((func (!set ?parameters (*))) *):
      if (!_parameters_variadic(parameters) &&
          arguments.len() > List.len(parameters))
        $report.type.method_arity(k.c, parameters, arguments, k.origin);
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
      %"discard-helper ${(long) binding}" in c.protocol_helpers)
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

static List CallSite._method(CallSite &k, List receiver, List field) {
  k.receiver = receiver;
  k.field = field;
  List resolution = k._lookup();
  if (!resolution && _deferred_receiver(k.receiver)) {
    List callee = %(expr (<macro-expr>) (op . ${k.receiver} ${k.field}));
    return k._finish(k.result_type, callee, NULL, NULL);
  }
  if (!resolution) {
    Var name = k.field.car();
    $report.type.method_missing(k.c, k.type, name, k.origin);
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

static List CallSite._lookup(CallSite &k) {
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
  CallSite &k, List binding, Type signature, List declared,
  List parameters, List returns) {
  k.receiver = k.c._method_bind(k.receiver, k.type, declared, k.origin);
  List callee = %(expr ((func $parameters) $returns) (ident $binding));
  return k._finish(signature.apply(), callee, signature, k.receiver);
}

static List Compiler._method_bind(
  Compiler c, List receiver, Type type, Type declared, Token origin) {
  if (!declared || !type) return receiver;
  Type target = declared.canonicalize(), source = type.canonicalize();
  Type named = source.is_aggregate() ? c._tag_typedef(source) : NULL;
  if (named) {
    type = named.qualify(type);
    source = named;
    receiver = %(expr $type ${receiver.caddr()});
  }
  if (_receiver_points_to(source, target))
    $report.type.receiver_pointer(c, type, declared, origin);
  if (target.car() != <*> || cdr(target) !== source)
    return receiver;
  if (!c._expression_is_addressable(receiver))
    $report.type.receiver_address(c, origin);
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
    $report.type.optional_ref_access(c);
  Type type = receiver_type.canonicalize();
  if (access == <"->">)
    return c._field_member(receiver_type, field, <"->">);
  int hops = 0, tagged = 0;
  while (type) {
    if (call_context && _method_owner(type)) {
      List method = c._method_member(receiver_type, type, field);
      if (method) return method;
    }
    if (type.is_pointer())
      return c._field_member(receiver_type, field, <"->">);
    if (type.is_aggregate()) {
      List member = c._field_member(receiver_type, field, <.>);
      if (member || !call_context) return member;
    }
    type = c._next_method_type(type, hops, tagged);
  }
  return NULL;
}

static int _method_owner(Type type) =>
  !type.is_aggregate() && (type.is_typedef_name() || type.is_builtin());

/* Lookup and completion follow the same typedef owner from an aggregate. */
static Type Compiler._next_method_type(
  Compiler c, Type type, int &hops, int &tagged) {
  if (type.is_pointer()) return NULL;
  if (type.is_aggregate()) return !tagged++ ? c._tag_typedef(type) : NULL;
  return c.sym.next_typedef(type, hops).canonicalize();
}

/* A field inherits its containing object's qualifiers, not its pointer's. */
static List Compiler._field_member(
  Compiler c, Type receiver, List field, Symbol access) {
  Type object = access == <"->">
    ? c.sym.normalize_declared_type(receiver).dereference() : receiver;
  Type declared = c.sym.lookup_field(object, field);
  return declared ? %(field $access $declared) : NULL;
}

/* A receiver spelled `struct T` or `union T` reaches the methods of the
   typedef that names the same aggregate: `T` itself, as the usual
   `typedef struct T {...} T;` declares, or else the only typedef declared
   directly as that aggregate. */
static Type Compiler._tag_typedef(Compiler c, Type aggregate) {
  match (aggregate) case %(? ?(String tag)): {
    Type name = %($tag), declared = c.sym.get(%(typedef $tag));
    if (declared && c.sym.resolve_key(declared) == aggregate) return name;
  }
  return c.sym.sole_typedef(aggregate);
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

static List Resolve._member(
  Resolve &r, Var operator, List receiver, List field) {
  receiver = r.c.resolve_expression(receiver, r.origin);
  Type receiver_type = receiver.cadr();
  List resolution = r.c.resolve_postfix_member(
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
  DelegateSearch &d, Type receiver, List reverse_path, List seen) {
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
  DelegateSearch &d, List candidates) {
  List notes = NULL;
  foreach (List candidate, candidates) {
    List path = candidate.cddr().cadr();
    String spelling = binding_identity_spelling(candidate.cadr());
    String description = _delegate_path_string(d.outer, path, d.member);
    notes = cons(%"delegate path: $description -> $spelling", notes);
  }
  String type = _delegate_type_name(d.outer), member = d.member;
  $report.type.delegate_ambiguous(d.c, type, member, d.origin,
    notes.reverse());
}

static void DelegateSearch._report_cycle(DelegateSearch &d) {
  String type = _delegate_type_name(d.outer), member = d.member;
  String path = _delegate_path_string(d.outer, d.first_cycle, NULL);
  $report.type.delegate_cycle(d.c, type, member, d.origin, path);
}

static void Compiler._report_method_ambiguity(
  Compiler c, Type receiver, String member, List packages,
  String delegate_path, Token origin) {
  List notes = delegate_path
             ? %("delegate path: $delegate_path") : NULL;
  foreach (String package, packages)
    notes = cons(%"package: '$package'", notes);
  String type = _delegate_type_name(receiver);
  $report.type.method_packages(c, type, member, origin, notes.reverse());
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
  int hops = 0, tagged = 0;
  while (type) {
    if (_method_owner(type)) {
      String owner = type.base_type().car();
      c._completion_owner_methods(%"${owner}_", seen, names);
      foreach (String name, c.protocol_member_names(type))
        _completion_add(seen, names, name);
    }
    type = c._next_method_type(type, hops, tagged);
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
macro Stmt $func_argument(Expr $function, Expr $storage,
    Expr $count, Expr $index, Expr $address, Expr $type, Expr $value) {
  if (x2c_func_reference_type($function, $count, $index))
    $storage[$index] = FuncArg_reference($address, $type);
  else $storage[$index] = $value;
}

/* A null argument: a reference takes it with the callee's own type. */
macro Stmt $func_null_argument(Expr $function, Expr $storage,
    Expr $count, Expr $index, Expr $value) {
  {
    List reference = x2c_func_reference_type($function, $count, $index);
    if (reference) $storage[$index] = FuncArg_reference(0, reference);
    else $storage[$index] = $value;
  }
}

/* The by-value alternative: the argument boxed, or the diagnostic call for
   a type with no Var form. */
macro Expression $func_value(Expr $argument) => FuncArg_value($argument);

macro Expression $func_opaque(Expr $function, Expr $index,
    Expr $type) => x2c_func_unrepresentable_argument($function, $index, $type);

/* A call with no arguments applies the callee directly. */
macro Expression $func_apply(Expr $callee) => Func_apply($callee, 0, 0);

static int _null_literal(List expr) =>
  _integer_literal_kind(expr, NULL) == <zero> ||
  expr.match(
    %(expr ? ${$source_identifier_content(%((binding ? "NULL")))}));

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
   conversion. */
macro Expression $func_call(Expr $callee, Expr $count,
    Expr $arguments...) => ({
  Func function = $callee;
  FuncArg storage[$count];
  $x2c_func_call_arguments(function, storage, $arguments)...
  Func_apply(function, $count, storage);
});

static List Compiler._resolve_func_call(
  Compiler c, List callee, List supplied, Token origin) {
  List arguments = c._resolve_call_arguments(NULL, supplied, origin);
  if (_deferred_call(callee, NULL, arguments)) {
    Macro called = $called;
    return c.rebuild_expression(%(<macro-expr>), called(callee, arguments));
  }
  match (arguments)
    case %((expr (void) ())): arguments = NULL;
  if (!arguments) {
    Macro apply = $func_apply;
    return c.bind_syntax(apply(callee), AST_EXPRESSION, NULL);
  }
  Macro call = $func_call;
  return c.bind_syntax(
    call(callee, arguments.len(), arguments), AST_EXPRESSION, NULL);
}

/** Returns the callee and arguments of a typed `Func` call, or NULL for any
    other expression. `content` is the body of the call's `expr` node. Each
    argument is `(func-arg value address source)`: the argument boxed as a
    Var, or `(no-value)` when it has no Var form; its address, or 0; and its
    type, which is `(expr ("List") (ident reference))` for a null argument
    that takes the callee's own type. */
List Compiler.func_call_parts(Compiler c, Var content) {
  Macro call = $func_call, apply = $func_apply;
  match (%(expr () $content)) {
    case apply(?callee): return %($callee);
    case call(?callee, ?count, *arguments): {
      Array parts = $auto([callee]);
      foreach (List argument, _slot_statements(arguments)) {
        List part = _func_arg_part(argument);
        if (!part) return NULL;
        parts.push(part);
      }
      return parts;
    }
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
  match (expression)
    case $called(%(!set ?callee (expr ((func (!set ?parameters (*))) ?)
                                      (ident ?binding))),
                 *arguments):
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
  return type.canonicalize() == %("Iter");
}

static List _iter_destination(void) {
  List values = source_commas_content(%(${x2c_literal_int(0)}));
  return %(expr (* struct "Iter")
    (op & (expr (struct "Iter")
      (cast (decl (struct "Iter") (bindings (bind () ())))
        (expr () (composite $values))))));
}

// operators

static List Resolve._unary(Resolve &r, Var operator, List operand) {
  List lhs = r.c.resolve_expression(operand, r.origin);
  Type lhs_type = lhs.cadr();
  if (lhs_type.car() == <opt-ref> && operator != <!>)
    $report.type.optional_ref_unchecked(r.c, r.origin);
  if (operator == <*> && operand.cadr().car() == <&> &&
      lhs_type.car() != <&>) return lhs;
  if (lhs_type === %(<macro-expr>))
    return source_operator_expression(%(<macro-expr>), %($operator $lhs));
  List lowered = operator == <->
    ? r.c._protocol_operator_expression(operator, lhs, NULL) : NULL;
  if (lowered) return lowered;
  Type type = lhs_type;
  switch (operator.symbol()) {
    case <!>: type = %(int); break;
    case <*>: {
      Type pointee = type.dereference();
      type = pointee ? pointee : r.c.sym.resolve_key(type).dereference();
      break;
    }
    case <&>: type = type.reference(); break;
    case <~>: case <+>: case <->: {
      type = r.c.sym.resolve_numeric_type(type);
      if (type && type.is_integral()) type = type.promote();
      if (!type && lhs_type && operator == <->)
        $report.type.neg_unsupported(r.c, lhs_type, r.origin);
      if (!type) type = lhs_type;
      break;
    }
  }
  if ((operator == <++> || operator == <-->) &&
      r.c._builtin_index_lvalue(lhs)) type = %("Var");
  return source_operator_expression(type, %($operator $lhs));
}

static List Resolve._postfix(Resolve &r, Var operator, List operand) {
  operand = r.c.resolve_expression(operand, r.origin);
  Type operand_type = operand.cadr();
  if (operand_type.car() == <opt-ref>)
    $report.type.optional_ref_unchecked(r.c, r.origin);
  if (operand_type === %(<macro-expr>))
    return source_postfix_expression(
      %(<macro-expr>), %($operator $operand));
  if (r.c._builtin_index_lvalue(operand)) operand_type = %("Var");
  return source_postfix_expression(
    operand_type, %($operator $operand));
}

static List Resolve._conditional(
  Resolve &r, Var operator, List condition, List ontrue, List onfalse) {
  condition = r.c.resolve_expression(condition, r.origin);
  ontrue = r.c.resolve_expression(ontrue, r.origin);
  onfalse = r.c.resolve_expression(onfalse, r.origin);
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
    Type left = r.c.sym.resolve_numeric_type(type);
    Type right = r.c.sym.resolve_numeric_type(false_type);
    if (left && right) type = left.widest(right);
    else if (r.c._conditional_joins(false_type, true_type)) {
      type = false_type;
      ontrue = r.c.convert_expression(ontrue, type);
    }
    else if (r.c._conditional_joins(true_type, false_type))
      onfalse = r.c.convert_expression(onfalse, type);
  }
  return source_operator_expression(
    type, %($operator $condition $ontrue $onfalse));
}

/* A conditional whose arms are a `Var` and another value is a `Var`: the
   other arm boxes, so C sees one operand type. Other mixed arms keep their
   C types until a target converts each arm. */
static int Compiler._conditional_joins(Compiler c, Type type, Type other) =>
  type && other && c.sym.is_var_type(type) && !c.sym.is_var_type(other);

static List Resolve._binary(Resolve &r, Var operator, List left, List right) {
  List lhs = r.c.resolve_expression(left, r.origin);
  List rhs = r.c.resolve_expression(right, r.origin);
  return r.c._binary_expression(operator, lhs, rhs, r.origin);
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
    int builtin_index = c._builtin_index_lvalue(lhs);
    if (builtin_index) type = %("Var");
    /* Meta lowering adapts a callable stored to a Func itself; converting
       here would lift a function name to a hidden global first. */
    if (operator == <=> && !builtin_index &&
        !(c.meta_body && c.sym.is_named_value_type(type, "Func")))
      rhs = c.convert_expression(rhs, type);
    return source_operator_expression(type, %($operator $lhs $rhs));
  }
  c._convert_string_comparison(operator, lhs, rhs);
  int constant_string = c._convert_string_addition(operator, lhs, rhs);
  List lowered = c._protocol_operator_expression(operator, lhs, rhs);
  if (lowered) {
    if (!constant_string || c.runtime_literals) return lowered;
    List cached = c.cache(%(string ${c.normalize(lowered)}));
    return %(expr ("String") $cached);
  }
  if (operator == <in>)
    $report.type.contains_missing(c, rhs_type, origin);
  /* An untyped preprocessor name beside a converting protocol participant
     would reach the C compiler with no usable conversion. */
  if ((lhs_type != NULL) != (rhs_type != NULL))
    c._check_untyped_operand(
      operator, lhs_type ? lhs_type : rhs_type,
      lhs_type ? rhs : lhs, origin);
  c._check_matmul(operator, lhs_type, rhs_type, origin);
  return c._native_binary_expression(operator, lhs, rhs, origin);
}

// Built-in indexed mutation returns Var, independently of a read override.
static int Compiler._builtin_index_lvalue(Compiler c, List expression) {
  match (expression)
    case %(expr ? (getindex (expr ?receiver_type ?) ?)):
      return !!c._indexed_builtin_helper(receiver_type);
  return 0;
}

// Identify only the built-in mutation helper family.
Symbol Compiler._indexed_builtin_helper(Compiler c, Type type) {
  if (c.sym.is_array_type(type)) return <array>;
  if (c.sym.is_map_type(type)) return <map>;
  return 0;
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
    !c.needs_resolution(lhs) && !c.needs_resolution(rhs) &&
    !lhs.try_search(
      $source_identifier_content(%((*))), matched, bindings) &&
    !rhs.try_search(
      $source_identifier_content(%((*))), matched, bindings);
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
    $report.type.operand_untyped(c, origin);
}

static void Compiler._check_matmul(
  Compiler c, Symbol operator, Type lhs_type, Type rhs_type,
  Token origin) {
  if (operator == <@> && !c.sym.is_var_type(lhs_type) &&
      !c.sym.is_var_type(rhs_type))
    $report.type.matmul_missing(c, lhs_type, rhs_type, origin);
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
    $report.type.optional_ref_unchecked(c, c.token);
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
  int rpointer = c.sym.resolve_key(rtype).is_pointer();
  if (lscalar) {
    if (rscalar) return lscalar.widest(rscalar);
    else if (op == <+> && rpointer) return rtype;
  }
  else if (c.sym.resolve_key(ltype).is_pointer()) {
    if (rscalar)        return ltype;
    else if (rpointer) return op == <-> ? %("ptrdiff_t") : %(int);
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
  List zero = x2c_literal_int(0);
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
    List converted = c.converter_call(rhs, rhs_type, lhs_type);
    if (converted) { rhs = converted; return lhs_type; }
  }
  else if (rhs_member && !lhs_member) {
    List converted = c.converter_call(lhs, lhs_type, rhs_type);
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
    case %(expr ? ${$grouped(?inner)}):
      return c._is_operator_temporary(inner);
  }
  match (expression)
    case $called(%(expr ? ${$source_identifier_content(
        %((!set ?binding (*))))}), *arguments):
      return %"fresh-callee ${(long) binding.list()}" in c.protocol_helpers;
  return 0;
}

// type tests and casts

static List Resolve._is_type(Resolve &r, List operand, Type target) {
  List lhs = r.c.resolve_expression(operand, r.origin);
  Type lhs_type = lhs.cadr();
  if (_deferred_receiver(lhs) || _deferred_type_test(target)) {
    Macro has_type = $has_type;
    return r.c.rebuild_expression(%(<macro-expr>), has_type(lhs, target));
  }
  if (!r.c.sym.is_var_type(lhs_type))
    $report.type.is_var(r.c, lhs_type, r.origin);
  Macro called = $called;
  if (target === %(void) || target === %("Void")) {
    List callee = r.c._resolve_identifier("Var_is_void", NULL, r.origin);
    return r.c.rebuild_expression(%(int), called(callee, %($lhs)));
  }
  Symbol vartag = r.c.require_var_tag(target, r.origin);
  List direct = r.c._constant_row_test(lhs, vartag, r.origin);
  if (direct) return direct;
  String tagsym = %"${(unsigned long) vartag}";
  List callee = r.c._resolve_identifier("Var_is", NULL, r.origin);
  return r.c.rebuild_expression(
    %(int), called(callee, %($lhs (expr ("Symbol") $tagsym))));
}

static List Resolve._is_symbol(Resolve &r, List operand, List selector) {
  List lhs = r.c.resolve_expression(operand, r.origin);
  selector = r.c.resolve_expression(selector, r.origin);
  Type lhs_type = lhs.cadr(), selector_type = selector.cadr();
  if (_deferred_receiver(lhs) || _deferred_receiver(selector)) {
    Macro has_symbol = $has_symbol;
    return r.c.rebuild_expression(
      %(<macro-expr>), has_symbol(lhs, selector));
  }
  if (!r.c.sym.is_var_type(lhs_type))
    $report.type.is_var(r.c, lhs_type, r.origin);
  if (!r.c.sym.is_named_value_type(selector_type, "Symbol"))
    $report.type.is_selector(r.c, selector_type, r.origin);
  match (selector)
    case %(expr ("Symbol") ${$source_literal_content(
        %(("Symbol") ? ?tag_value))}): {
      if (tag_value is <symbol>) {
        Symbol tag = tag_value;
        List direct = r.c._constant_row_test(lhs, tag, r.origin);
        if (direct) return direct;
      }
    }
  List callee = r.c._resolve_identifier("Var_is", NULL, r.origin);
  Macro called = $called;
  return r.c.rebuild_expression(%(int), called(callee, %($lhs $selector)));
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
  if (resolved && resolved.is_enum())
    $report.type.is_enum(c, target, origin);
  if (!vartag)
    $report.type.is_tag(c, target, origin);
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

static List Resolve._cast(Resolve &r, List declaration, List operand) {
  operand = r.c.resolve_expression(operand, r.origin);
  declaration = r.c.bind_syntax(declaration, AST_BLOCK, r.c.return_type);
  List typed = %(declare @{declaration.cdr()});
  Type type = operand.cadr() === %(<macro-expr>) ||
              r.c._casts_to_template_typedef(declaration)
            ? %(<macro-expr>) : typed.type_from_ast();
  return %(expr $type (cast $declaration $operand));
}

static List Resolve._tadapt(Resolve &r, List target, List source) {
  target = r.c.resolve_expression(target, r.origin);
  source = r.c.resolve_expression(source, r.origin);
  match (target)
    case %(expr (!set ?syntax (typedef ?target_type)) ?): {
      Type type = r.c.sym.resolve_key(syntax);
      if (!type || !type.is_pointer() ||
          !type.dereference().is_function())
        $report.macro.adapter_pointer(r.c, type, r.origin);
      return %(expr ($target_type) (tadapt ${r.c.origin} $source));
    }
  $report.macro.adapter_typedef(r.c, r.origin);
}

// collection literals

static List Resolve._segments(Resolve &r, List items) {
  Array resolved = [];
  Type type = %("String");
  foreach (List item, items) match (item) {
    case %((!set ?tag (!or segvar segexp)) ?value): {
      List expression = r.c.resolve_expression(value, r.origin);
      if (_deferred_receiver(expression)) {
        type = %(<macro-expr>);
        resolved.push(%($tag $expression));
        continue;
      }
      resolved.push(%($tag ${r.c.convert_segment_to_string(expression)}));
      continue;
    }
    default: resolved.push(item);
  }
  return %(expr $type ${source_string_content(resolved.list_free())});
}

static List Resolve._cons(Resolve &r, List head, List tail) {
  head = r.c.resolve_expression(head, r.origin);
  tail = r.c.resolve_expression(tail, r.origin);
  Type type = r.type ? r.type : %("List");
  if (_deferred_receiver(head) || _deferred_receiver(tail))
    return %(expr $type (cons $head $tail));
  head = r.c.convert_expression(head, %("Var"));
  List cached = r.c.cache_cons_cell(head, tail);
  if (cached) return cached;
  return %(expr $type (cons $head $tail));
}

static List Resolve._append(Resolve &r, List head, List tail) {
  head = r.c.resolve_expression(head, r.origin);
  tail = r.c.resolve_expression(tail, r.origin);
  head = r.c.sym.is_var_type(head.cadr())
       ? %(expr ("List") (call "Var_list" (args $head)))
       : r.c.convert_expression(head, %("List"));
  return %(expr ${r.type ? r.type : %("List")}
           (append $head $tail));
}

static List Resolve._splice(Resolve &r, List expression) =>
  %(expr ${r.type} (splice ${r.c.resolve_expression(expression, r.origin)}));

static List Resolve._array_value(Resolve &r) {
  Macro array_value = $array_value;
  match (r.input) case array_value(*elements): {
    Array resolved = [];
    foreach (List element, elements)
      resolved.push(r.c.resolve_expression(element, r.origin));
    return r.c.rebuild_expression(
      r.type, array_value(resolved.list_free()));
  }
  return r.input;
}

static List Resolve._map_value(Resolve &r) {
  Macro map_value = $map_value;
  match (r.input) case map_value(*entries): {
    Array resolved = [];
    foreach (Var entry, entries)
      foreach (Var row, r.c.evaluate_macro_rows(entry))
        resolved.push(r.c.resolve_map_entry(row, r.origin));
    return r.c.rebuild_expression(
      r.type, map_value(resolved.list_free()));
  }
  return r.input;
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
  $report.parse.map_entry(c, origin);
}

static List Resolve._initval(Resolve &r, List content) {
  List header = NULL;
  List cases = Ast.initializer_cases(content, header);
  Array resolved = [];
  if (header) {
    Array inputs = [];
    foreach (List argument, header.cdr()) {
      List value = r.c.resolve_expression(argument.cadr(), r.origin);
      inputs.push(%(${argument.car()} $value));
    }
    resolved.push(%(input @{inputs.list_free()}));
  }
  foreach (List choice, cases) {
    (List condition, List path, Type destination, List value) = choice;
    if (condition) condition = r.c.resolve_expression(condition, r.origin);
    value = r.c.resolve_expression(value, r.origin);
    resolved.push(%($condition $path $destination $value));
  }
  return %(expr ${r.type} (initval @{resolved.list_free()}));
}

static List Resolve._composite(Resolve &r, List elements) {
  Array values = [];
  foreach (List element, elements)
    values.push(r.c._resolve_initializer(element, r.origin));
  return %(expr ${r.type} ${source_composite_content(
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

static List Resolve._parens(Resolve &r, List inner) {
  if (Ast.without_origin(inner).car() == <block>)
    return r.c._statement_expression(
      r.c.bind_syntax(inner, AST_STATEMENT, r.c.return_type), r.origin);
  inner = r.c.resolve_expression(inner, r.origin);
  Type type = inner.cadr();
  return %(expr $type (parens $inner));
}

static List Resolve._commas(Resolve &r, List expressions) {
  Array resolved = [];
  foreach (List expression, expressions)
    resolved.push(r.c.resolve_expression(expression, r.origin));
  List values = resolved.list_free();
  Type type = r.type;
  if (values) type = values.last().cadr();
  return %(expr $type ${source_commas_content(values)});
}

static List Resolve._destructure(Resolve &r, List targets, List source) {
  Array resolved = [];
  foreach (List target, targets)
    resolved.push(r.c.resolve_expression(target, r.origin));
  source = r.c.resolve_expression(source, r.origin);
  return %(expr ${source.cadr()}
           (dstrasgn (targets @{resolved.list_free()}) $source));
}

static List Resolve._managed_init(Resolve &r, List initializer) {
  initializer = r.c.resolve_expression(initializer, r.origin);
  Type type = initializer.cadr();
  return %(expr $type (managed-init $initializer));
}

static List Resolve._generic(Resolve &r, List control, List associations) {
  control = r.c.resolve_expression(control, r.origin);
  Array resolved = [];
  foreach (List association, associations) match (association)
    case %(association ?selector ?value):
      resolved.push(
        %(association $selector ${r.c.resolve_expression(value, r.origin)}));
  Type type = control.cadr() === %(<macro-expr>) ? %(<macro-expr>) : NULL;
  return %(expr $type ${source_generic_content(
    %($control @{resolved.list_free()}))});
}

/* A `sizeof` keeps its grouped or bare form around the resolved operand;
   an operand that is not syntax stays as written. */
static List Resolve._sizeof(Resolve &r, Macro form, Var argument) {
  if (argument is not <list>) return r.input;
  List operand = argument;
  return r.c.rebuild_expression(
    r.input.cadr(), form(r.c.resolve_expression(operand, r.origin)));
}

static List Resolve._va_arg(Resolve &r, List argument, List declaration) {
  return %(expr ${r.type}
           ${source_va_arg_content(
             %(${r.c.resolve_expression(argument, r.origin)}
               ${r.c.resolve_expression(declaration, r.origin)}))});
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
  match (call) case $called(?callee, ?argument): {
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
  match (result) case $called(?function, *values): {
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
  if (call != parsed) return;
  // A qualified target, such as `const char *`, is a different crossing.
  if (target.declared() != target.canonicalize() ||
      c.sym.resolve_key(call.cadr()) != c.sym.resolve_key(target))
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
  $report.conversion.call_redundant(c, method, target, location, context);
}

static int Compiler._implicit_converter(
  Compiler c, List receiver, Type source, Type target,
  int source_is_var) =>
  source_is_var || c.sym.is_var_type(target) ||
  c.sym.resolve_key(source) == c.sym.resolve_key(target) ||
  !!c.converter_call(receiver, source, target);

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
        if (name != (String) info.name) continue;
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
    case %(expr ? ${$grouped(?inner)}):
      return _expr_is_raw_string_literal(inner);
    case %(expr ? ${$source_literal_content(%(?type ?))}):
      return Type.is_char_pointer_like(type);
    case %(expr ? ${$source_operator_content(
        %(? ? ?ontrue ?onfalse))}):
      return _expr_is_raw_string_literal(ontrue) &&
             _expr_is_raw_string_literal(onfalse);
  }
  return 0;
}

static inline int Compiler._expr_is_string_like(Compiler c, List expr) {
  if (!expr) return 0;
  Type type = expr.cadr();
  return c.sym.is_string_type(type) ||
         type.is_char_pointer_like();
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
      if (c.runtime_literals) return value;
      return %(expr ("String") ${c.cache(%(string $value))});
    }
    case %(expr (!or (* char) ((dim *) char))
        ${$grouped(?inner)}):
      // A statement expression's block converts as one dynamic value.
      match (inner) case %(expr *): {
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
  if (c.sym.resolve_key(target) == func_type) {
    List lifted = c.lift_func_expression(expr);
    if (lifted != expr) return lifted;
  }
  if (type && c.sym.resolve_key(type) == func_type &&
      target.is_pointer() && target.dereference().is_function()) {
    $report.type.func_callback(c);
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
        $report.type.brace_anonymous(c);
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
        (true_type != false_type &&
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
  if (target_is_var && expr.match(
    %(expr () ${$source_identifier_content(%((binding ? ?)))}))) {
    List binding = expr.caddr().cadr();
    if (binding_identity_spelling(binding) == "NULL")
      return %(expr ("Var") (call "Var_null" (args)));
    $report.type.var_unresolved(c, NULL);
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
  List converted = c.converter_call(expr, type, target);
  if (converted) return converted;
  if (!type_is_var && target_is_var) return c._box_var(expr, type);
  return NULL;
}

static List Compiler._convert_reference(
  Compiler c, List expr, Type type, Type target) {
  // T -> &T: pass the address of an addressable value.
  if (type === cdr(target) && target.is_reference()) {
    if (!c._expression_is_addressable(expr))
      $report.type.ref_address(c);
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
  List converted = c.converter_call(expr, type, %("String"));
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
    $report.type.var_address(c, target);
  if (target.is_pointer())
    return %(expr $target (call "Var_pointer" (args $expr)));
  if (target.is_typedef_name()) {
    // Unknown system typedefs have no proven pointer payload reader.
    Type resolved = c.sym.resolve_key(target);
    if (resolved.is_pointer())
      return %(expr $target (call "Var_pointer" (args $expr)));
    $report.type.var_convert(c, target);
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
    if (!reader) reader = c.converter_call(expr, type, owner);
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
      readertype.cdr() != target)
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
  $report.type.var_loss(c, type);
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
  // Conversion runs after parsing; a NULL token anchors the statement.
  $report.type.var_loss(c, type);
}

// converter calls

/** The call to the converter that `type`, or the first of its typedef names
    that declares one, provides for `target`, applied to `expr`, or NULL
    when none declares one. */
List Compiler.converter_call(Compiler c, List expr, Type type, Type target) {
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
  /* A return typedef may name the same declared type as the target. The
     relaxed form still takes one source argument and must return that type;
     a lowercased method name alone does not establish the result type. */
  if (cvrtrtype != %((func ($owner)) @target) &&
      (!cvrtrtype.match(%((func (($typename))) ?)) ||
       c.sym.normalize_declared_type(cvrtrtype.cdr()) !=
         c.sym.normalize_declared_type(target)))
    return NULL;
  Macro called = $called;
  List call = c.rebuild_expression(target, called(callee, %($argument)));
  return c._converted_temporary(call, owner, target);
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

/** The global builtin boxers and scalar formatters only observe their
    arguments. A custom converter or a shadowed callee may change state. */
int Compiler.is_builtin_converter_call(Compiler c, List expr) {
  match (expr)
    case %(expr ?result (call ?callee (args ?argument))): {
      Type target = result, source = argument.cadr();
      if (!source || !source.match(%(?)) || !target.match(%(?))) return 0;
      if (!source.fixed_var_tag() ||
          !(target == %("Var") ||
            (source.scalar_tag() && target == %("String"))))
        return 0;
      List binding = NULL;
      String spelling = NULL;
      if (callee is <string>) spelling = callee;
      else match (callee)
        case %(expr ? ${$source_identifier_content(%(?bound))}): {
          binding = bound;
          spelling = binding_identity_spelling(binding);
        }
      if (spelling != _converter_name(source, target)) return 0;
      Type declared = NULL;
      return !binding ||
        binding == c.sym.resolve_global(%($spelling), declared);
    }
  return 0;
}

/* A converter's result exists only for the operator that asked for it.
   Only a conversion from a number is known to be fresh; a converter from a
   handle type may return storage its source still owns. */
static List Compiler._converted_temporary(
  Compiler c, List call, Type owner, Type target) {
  if (c.sym.resolve_numeric_type(owner) &&
      c.resolve_protocol_member(target, "discard")) {
    match (call)
      case $called(%(expr ? ${$source_identifier_content(
          %((!set ?binding (*))))}), *arguments):
        c._note_fresh_callee(binding);
  }
  return call;
}

// conversion checks

static void Compiler._check_null_reference(
  Compiler c, List expr, Type target) {
  if (target.car() != <&>) return;
  if (_integer_literal_kind(expr, NULL) == <zero> ||
      (expr.match(
        %(expr () ${$source_identifier_content(%((binding ? ?)))})) &&
       binding_identity_spelling(expr.caddr().cadr()) == "NULL"))
    $report.type.ref_null(c, target);
}

/* Same-address conversions must keep qualifiers, including void pointers. */
static void Compiler._check_qualifiers(
  Compiler c, Type type, Type target, Type source, Type destination) {
  int take_reference = target.is_reference() && type === cdr(target);
  Type qualified = take_reference ? source.reference() : source;
  if ((take_reference || type == target || cdr(type) == cdr(target) ||
       (type.is_pointer() && target.is_pointer() &&
        (destination.base_type() === %(void) ||
         source.base_type() === %(void)))) &&
      qualified.discards_qualifiers(destination)) {
    $report.type.qualifier_dropped(c, source, destination);
  }
}

static void Compiler._check_reference_value(
  Compiler c, Type type, Type target) {
  /* An optional reference forwards only to another address type. */
  if (type.car() == <opt-ref> && !target.is_reference() &&
      !c.sym.resolve_key(target).is_pointer())
    $report.type.optional_ref_unchecked(c, NULL);
  /* A reference takes an lvalue of its referenced type. */
  if (target.is_reference() && !type.is_reference() &&
      type !== cdr(target))
    $report.type.ref_lvalue(c, type, target);
}

static void Compiler._check_object_pointer(
  Compiler c, Type type, Type target, int type_is_var) {
  if (target.car() != <*> || type_is_var) return;
  Type source = c.sym.resolve_key(type);
  if (source && !source.is_pointer() && !source.is_array() &&
      !source.is_function())
    $report.type.pointer_address(c, type, target);
}

/* C accepts null pointer constants, pointer decay, and opaque system types.
   Reject only a proven nonzero integer, unrelated known pointers, or two
   typedef names that share a C representation without a declared crossing. */
static void Compiler._check_native_crossing(
  Compiler c, List expr, Type type, Type target,
  Type declared_source, Type declared_target) {
  String integer = c._not_null_pointer_constant(expr);
  if (integer && c.sym.resolve_key(target).is_pointer())
    $report.type.pointer_integer(c, integer, target);
  if (c._unrelated_pointers(type, target))
    $report.type.pointer_unrelated(c, declared_source, declared_target);
  if (declared_source.is_bare_typedef_name() &&
      declared_target.is_bare_typedef_name() &&
      declared_source != declared_target &&
      c.sym.resolve_key(declared_target).is_pointer() &&
      c.sym.resolve_key(declared_source).base_type() !== %(void) &&
      !(declared_target in c._typedef_names(declared_source)) &&
      !(declared_source in c._typedef_names(declared_target))) {
    $report.type.typedef_crossing(c, declared_source, declared_target);
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
    case %(expr ? ${$grouped(?inner)}):
      return c._not_null_pointer_constant(inner);
    // sizeof is an integer constant expression, but never a zero-valued
    // one: no type in C has size zero.
    case %(expr ? ${$sizeof_grouped(?operand)}):
      return "sizeof";
    case %(expr ? ${$sizeof_expression(?operand)}):
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
   remains here is whether its value is zero.  A float, a name, or an enum
   constant answers <unknown>; the null-pointer guard below stays silent
   when it cannot decide. */
static Symbol _integer_literal_kind(List expr, String &?out_text) {
  match (expr) {
    case %(expr ? ${$grouped(?inner)}):
      return _integer_literal_kind(inner, out_text);
    case %(expr ? ${$source_literal_content(%(?ltype ?text))}): {
      String spelling = text, Type type = ltype;
      unsigned long long value;
      // A character constant is integral too, but it is not spelled in
      // digits, and '\0' is a null pointer constant.
      if (!type.integer_literal_magnitude(spelling, value)) return <unknown>;
      if (out_text) out_text = spelling;
      return value ? <nonzero> : <zero>;
    }
  }
  return <unknown>;
}
