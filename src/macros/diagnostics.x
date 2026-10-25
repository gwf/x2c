/*  diagnostics.x -- macro diagnostics and source notes */

/* macros diagnostics. */

static macro Stmt $fail.macros_result_type(
  Expr $c, Expr $site, Expr $expected, Expr $actual) =>
  $c.report_error(
    <type>, "indexed rewrite must preserve the getter result type", $site,
    %("expected: ${$expected.repr()}" "actual: ${$actual.repr()}"
      "return an explicitly converted expression"));

static macro Stmt $fail.macros_expansion_count(Expr $c, Expr $origin) =>
  $c.report_error(
    <macro>, "macro expansion count exceeds 10000",
    $origin, NULL);

static macro Stmt $fail.macros_expansion_recursive(
  Expr $c, Expr $origin, Expr $spelling, Expr $definition_note, Expr $shown) =>
  $c.report_error(
    <macro>, %"identical recursive expansion of '${$spelling}'",
    $origin, %(${$definition_note} "input: ${$shown.repr()}"));

static macro Stmt $fail.macros_expansion_depth(
  Expr $c, Expr $origin, Expr $definition_note, Expr $first_note) {
  {
    String first_note = %"first expansion: ${$first_note}";
    $c.report_error(
      <macro>, "macro expansion depth exceeds 64", $origin,
      %(${$definition_note} $first_note));
  }
}

static macro Stmt $fail.macros_macro_kind(Expr $c, Expr $site) =>
  $c.report_error(
    <parse>, "expected macro result kind before '$'",
    $site, NULL);

static macro Stmt $fail.macros_macro_result(Expr $c, Expr $site) =>
  $c.report_error(
    <parse>, "macro definition requires a result kind before '$'",
    $site, %("write the result kind between 'macro' and the macro name"));

static macro Stmt $fail.macros_macro_unknown_kind(
  Expr $c, Expr $origin, Expr $spelling) =>
  $c.report_error(
    <parse>, %"unknown macro result kind '${$spelling}'",
    $origin, NULL);

static macro Stmt $fail.macros_macro_reserved(
  Expr $c, Expr $origin, Expr $spelling) =>
  $c.report_error(
    <parse>, %"macro name '${$spelling}' is reserved",
    $origin, %("x2c.* is reserved for compiler facilities"));

static macro Stmt $fail.macros_name_with(Expr $c, Expr $origin) =>
  $c.report_error(
    <macro>, "'with' cannot be a local macro name",
    $origin, NULL);

static macro Stmt $fail.macros_macro_kind_order(Expr $c, Expr $site) =>
  $c.report_error(
    <parse>, "macro result kind belongs after 'macro', before the '$' name",
    $site, NULL);

static macro Stmt $fail.macros_hole_final(Expr $c, Expr $site) =>
  $c.report_error(
    <parse>, "sequence macro hole must be the final argument",
    $site, NULL);

static macro Stmt $fail.macros_decorator_singular(Expr $c, Expr $origin) =>
  $c.report_error(
    <parse>, "decorator target parameter must be singular",
    $origin, NULL);

static macro Stmt $fail.macros_decorator_kind(Expr $c, Expr $origin) =>
  $c.report_error(
    <parse>, "decorator first parameter has invalid target kind",
    $origin, %("expected Expression, Function, Stmt, Field, Unit,"
      "or NamedType"));

static macro Stmt $fail.macros_local_target(
  Expr $c, Expr $origin, Expr $target) =>
  $c.report_error(
    <macro>, %"local decorators cannot target ${$target} syntax",
    $origin, NULL);

static macro Stmt $fail.macros_local_result(
  Expr $c, Expr $origin, Expr $result_spelling) =>
  $c.report_error(
    <macro>, %"local macros cannot have ${$result_spelling} results",
    $origin, NULL);

static macro Stmt $fail.macros_decorator_target_kind(Expr $c, Expr $origin) =>
  $c.report_error(
    <parse>, "decorator requires a first target parameter",
    $origin, NULL);

static macro Stmt $fail.macros_macro_paren_body(Expr $c, Expr $site) =>
  $c.report_error(
    <parse>, "parenthesized macro body requires Expression result or target",
    $site, NULL);

static macro Stmt $fail.macros_macro_body(
  Expr $c, Expr $site, Expr $kind, Expr $form) =>
  $c.report_error(
    <parse>, %"${$kind} macro body requires ${$form}", $site, NULL);

static macro Stmt $fail.macros_hole_untyped(
  Expr $c, Expr $origin, Expr $hole_spelling) =>
  $c.report_error(
    <parse>, %"macro hole '${$hole_spelling}' has no inferred kind",
    $origin, %("annotate holes the template does not use"));

static macro Stmt $fail.macros_hole_unknown_kind(
  Expr $c, Expr $site, Expr $spelling) =>
  $c.report_error(
    <parse>, %"unknown macro hole kind '${$spelling}'",
    $site, NULL);

static macro Stmt $fail.macros_hole_name(Expr $c, Expr $site) =>
  $c.report_error(
    <parse>, "expected macro hole name after '$' or '@'",
    $site, NULL);

static macro Stmt $fail.macros_hole_duplicate(
  Expr $c, Expr $origin, Expr $spelling) =>
  $c.report_error(
    <parse>, %"duplicate macro hole '${$spelling}'",
    $origin, NULL);

static macro Stmt $fail.macros_splice_expr(Expr $c, Expr $site) =>
  $c.report_error(
    <parse>, "sequence insertion is not legal in an expression slot",
    $site, NULL);

static macro Stmt $fail.macros_splice_position(Expr $c, Expr $site) =>
  $c.report_error(
    <parse>, "sequence insertion is not legal in this syntax slot",
    $site, NULL);

static macro Stmt $fail.macros_typed_quotation(Expr $c, Expr $origin) =>
  $c.report_error(
    <parse>, "this quotation cannot declare a name or apply a template",
    $origin,
    %("a typed, Type, or Param quotation builds where it is written"));

static macro Stmt $fail.macros_typed_quotation_nested(
  Expr $c, Expr $origin) {
  {
    String note = "write ${$!T{ ... }} to insert the code it builds";
    $c.report_error(
      <parse>, "typed quotation inside a quotation must be written as a hole",
      $origin, %($note));
  }
}

static macro Stmt $fail.macros_hole_ambiguous(
  Expr $c, Expr $origin, Expr $spelling, Expr $first, Expr $also) =>
  $c.report_error(
    <parse>, %"macro hole '${$spelling}' has ambiguous kind",
    $origin, %("first: ${$first}"
      "also: ${$also}"));

static macro Stmt $fail.macros_hole_cardinality(
  Expr $c, Expr $origin, Expr $sequence, Expr $spelling) {
  {
    String message = $sequence
      ? %"singular macro hole '${$spelling}' cannot be spliced"
      : %"sequence macro hole '${$spelling}' requires '@'";
    $c.report_error(<parse>, message, $origin, NULL);
  }
}

static macro Stmt $fail.macros_keyword_internal(
  Expr $c, Expr $origin, Expr $spelling, Expr $definition_note) =>
  $c.report_error(
    <macro>, %"keyword alias cannot name internal macro kind '${$spelling}'",
    $origin, %(${$definition_note}));

static macro Stmt $fail.macros_keyword_builtin(Expr $c, Expr $origin) =>
  $c.report_error(
    <macro>, "built-in keyword alias cannot be replaced",
    $origin, NULL);

static macro Stmt $fail.macros_keyword_name(Expr $c, Expr $site) =>
  $c.report_error(
    <parse>, "keyword alias requires an identifier",
    $site, NULL);

static macro Stmt $fail.macros_macro_name(Expr $c, Expr $origin) =>
  $c.report_error(
    <parse>, $c.peek(1) == <ident>
      ? "expected macro name component after '.'"
      : "expected macro name after '$'",
    $origin, NULL);

static macro Stmt $fail.macros_macro_unbound(
  Expr $c, Expr $origin, Expr $spelling) =>
  $c.report_error(
    <parse>, %"unknown or forward-referenced macro '${$spelling}'",
    $origin, NULL);

static macro Stmt $fail.macros_macro_extra_args(Expr $c, Expr $site) =>
  $c.report_error(
    <parse>, "macro invocation has too many arguments",
    $site, NULL);

static macro Stmt $fail.macros_macro_missing_args(Expr $c, Expr $site) =>
  $c.report_error(
    <parse>, "macro invocation has too few arguments",
    $site, NULL);

static macro Stmt $fail.macros_argument_contract(Expr $c, Expr $site) =>
  $c.report_error(
    <macro>, "macro argument has no parsing contract",
    $site, NULL);

static macro Stmt $fail.macros_name_identifier(Expr $c, Expr $site) =>
  $c.report_error(
    <parse>, "Name macro argument requires an identifier",
    $site, NULL);

static macro Stmt $fail.macros_result_position(
  Expr $c, Expr $origin, Expr $spelling, Expr $result, Expr $description) {
  {
    String message =
      %"macro '${$spelling}' has result kind ${$result} and cannot be " +
      %"invoked at ${$description}";
    $c.report_error(<macro>, message, $origin, NULL);
  }
}

static macro Stmt $fail.macros_decorator_position(
  Expr $c, Expr $origin, Expr $name, Expr $kind) =>
  $c.report_error(
    <macro>,
    %"decorator '${$name}' targets ${$kind} syntax and cannot be used here",
    $origin, NULL);

static macro Stmt $fail.macros_decorator_target(
  Expr $c, Expr $origin, Expr $spelling, Expr $definition_note) =>
  $c.report_error(
    <macro>, %"decorator '${$spelling}' requires a following target",
    $origin, %(${$definition_note}));

static macro Stmt $fail.macros_decorator_semicolon(
  Expr $c, Expr $origin, Expr $definition_note) =>
  $c.report_error(
    <macro>, "decorator application must not end with ';'",
    $origin, %(${$definition_note}));

static macro Stmt $fail.macros_result_expr(
  Expr $c, Expr $origin, Expr $kind, Expr $spelling, Expr $definition_note) {
  {
    String subject = $kind == <decorator>
      ? %"decorator '${$spelling}'"
      : %"macro '${$spelling}'";
    $c.report_error(
      <macro>, %"$subject cannot be invoked in an expression", $origin,
      $kind == <decorator> ? %(${$definition_note}) : NULL);
  }
}

static macro Stmt $fail.macros_decorator_expr(
  Expr $c, Expr $origin, Expr $spelling, Expr $definition_note) =>
  $c.report_error(
    <macro>, %"decorator '${$spelling}' requires a following expression",
    $origin, %(${$definition_note}));

static macro Stmt $fail.macros_macro_pattern_arity(
  Expr $c, Expr $origin, Expr $name, Expr $expected) =>
  $c.report_error(
    <parse>,
    %"macro pattern '${$name}' takes ${$expected} argument patterns",
    $origin, NULL);

static macro Stmt $fail.macros_lisp_removed(Expr $c, Expr $origin) =>
  $c.report_error(
    <parse>, "compile-time Lisp forms are not supported", $origin,
    %("write the compile-time code as an x2c meta function"));

static macro Stmt $fail.macros_meta_expr(
  Expr $c, Expr $origin, Expr $value) =>
  $c.report_error(
    <macro>, "compile-time result cannot fill an expression slot",
    $origin, %( "value:" ${$value.repr()} ));

static macro Stmt $fail.macros_type_name(
  Expr $c, Expr $origin, Expr $message) =>
  $c.report_error(<macro>, $message, $origin, NULL);

static macro Stmt $fail.macros_placement(Expr $c, Expr $site, Expr $where) =>
  $c.report_error(
    <macro>, "unknown placement", $site, %("where: ${$where.repr()}"));

static macro Stmt $fail.macros_meta_failed(
  Expr $c, Expr $origin, Expr $source, Expr $error) {
  {
    String form_note = %"form: ${$source}",
      error_note = %"error: ${$error.repr()}";
    $c.report_error(
      <macro>, "meta call failed", $origin, %($form_note $error_note));
  }
}

static macro Stmt $fail.macros_code_effect(
  Expr $c, Expr $site, Expr $effect) =>
  $c.report_error(
    <macro>, "a meta call returned an unknown code effect", $site,
    %("effect: ${$effect.repr()}"));

static macro Stmt $fail.macros_variable_unbound(
  Expr $c, Expr $origin, Expr $spelling) =>
  $c.report_error(
    <parse>, %"unbound replacement variable '${$spelling}'",
    $origin, NULL);

// diagnostics

module String _definition_note(List definition) {
  List origin = definition.assoc(<origin>);
  String file = origin.assoc(<file>);
  int line = origin.assoc(<line>),
      column = origin.assoc(<column>);
  return %"definition: $file:$line:$column";
}

/** Reports that the meta call `source` failed with `error` at
    `invocation`. */
void Compiler.report_meta_failure(
  Compiler c, Token invocation, List error, String source) {
  $fail.macros_meta_failed(c, invocation, source, error);
}

/** Reports the compile-time Lisp form at the cursor, which x2c no longer
    evaluates. */
List Compiler.reject_lisp_form(Compiler c) {
  $fail.macros_lisp_removed(c, c.token);
}

/* A template names a hole, projection, or replacement variable that it
   does not bind. */
module void _unbound(Compiler c, String spelling, Token token) {
  $fail.macros_variable_unbound(c, token, spelling);
}
