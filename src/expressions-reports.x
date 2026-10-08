/*  expressions-reports.x -- expression typing diagnostics
*/

#pragma once

macro Stmt $report.type.optional_ref_assign(Expr $c, Expr $origin) =>
  $c.report_error(
    <type>, "check optional reference before assigning its value",
    $origin, NULL);

macro Stmt $report.parse.destructure_target(Expr $c) =>
  $c.report_error(
    <parse>, "unsupported destructuring assignment target",
    $c.token, %("destructuring targets must be simple identifiers"));

macro Stmt $report.parse.is_pointer(Expr $c, Expr $origin) =>
  $c.report_error(
    <parse>, "pointer type after 'is' must be parenthesized",
    $origin, %("write value is (T *)"));

macro Stmt $report.type.is_function(Expr $c, Expr $origin) =>
  $c.report_error(
    <type>, "function type cannot be used after operator 'is'",
    $origin, %("function types have no supported Var tag"));

macro Stmt $report.type.is_array(Expr $c, Expr $origin) =>
  $c.report_error(
    <type>, "array type cannot be used after operator 'is'",
    $origin, %("array types have no supported Var tag"));

macro Stmt $report.parse.slice_zero(Expr $c) =>
  $c.report_error(<parse>, "slice step cannot be zero", $c.token, %());

macro Stmt $report.parse.member_ident(Expr $c, Expr $op, Expr $lhs) {
  {
    List notes = %("token:" ${$c.token.text});
    if ($lhs) notes = cons(%("lhs expr:" ${$lhs.str()}), notes);
    String msg = %"expected identifier after '${$op}'";
    $c.report_error(<parse>, msg, $c.token, notes);
  }
}

macro Stmt $report.type.ident_semantic(Expr $c, Expr $value, Expr $origin) =>
  $c.report_error(
    <type>, %"identifier ${$value.repr()} has no semantic type",
    $origin, NULL);

macro Stmt $report.type.binding_unknown(Expr $c, Expr $name, Expr $origin) =>
  $c.report_error(
    <type>, "identifier has an unknown binding identity",
    $origin, %("binding: ${$name.repr()}"));

macro Stmt $report.type.function_private(
  Expr $c, Expr $spelling, Expr $file, Expr $origin) =>
  $c.report_error(
    <type>, %"'${$spelling}' is a static function private to its unit",
    $origin, %("it is defined in '${$file}';"
    "remove 'static' so other units can call it"));

macro Stmt $report.parse.index_unsupported(
  Expr $c, Expr $receiver_type, Expr $origin) =>
  $c.report_error(
    <parse>, $receiver_type.is_typedef_name()
    ? %"type ${$receiver_type} does not support getindex"
    : %"type ${$receiver_type} does not support indexing",
    $origin, %());

macro Stmt $report.type.optional_ref_index(Expr $c, Expr $origin) =>
  $c.report_error(
    <type>, "check optional reference before indexing its value",
    $origin, NULL);

macro Stmt $report.type.index_missing(Expr $c, Expr $type) =>
  $c.report_error(<type>, %"${$type.car()} has no getindex", $c.token, NULL);

macro Stmt $report.type.index_symbol(Expr $c) =>
  $c.report_error(
    <type>, "Symbol cannot be used as an integer bracket index",
    $c.token, NULL);

macro Stmt $report.type.method_arity(
  Expr $c, Expr $parameters, Expr $arguments, Expr $origin) =>
  $c.report_error(
    <type>, %"method takes ${List.len($parameters) - 1} argument${
            List.len($parameters) == 2 ? "" : "s"}, not ${
            $arguments.len() - 1}",
    $origin, NULL);

macro Stmt $report.type.method_missing(
  Expr $c, Expr $type, Expr $name, Expr $origin) =>
  $c.report_error(
    <type>, %"type ${$type.repr()} has no method ${$name}",
    $origin, NULL);

macro Stmt $report.type.receiver_address(Expr $c, Expr $origin) =>
  $c.report_error(
    <type>, "method pointer receiver requires an addressable value",
    $origin, %("bind the value to an object before calling the method"));

macro Stmt $report.type.receiver_pointer(
  Expr $c, Expr $type, Expr $declared, Expr $origin) =>
  $c.report_error(
    <type>,
    %"method receiver ${$type.repr()} is a pointer to ${$declared.repr()}",
    $origin, %("'.' reaches one pointer level; write (*receiver).method()"));

macro Stmt $report.type.optional_ref_access(Expr $c) =>
  $c.report_error(
    <type>, "check optional reference before accessing its value",
    $c.token, NULL);

macro Stmt $report.type.delegate_ambiguous(
  Expr $c, Expr $type, Expr $member, Expr $origin, Expr $notes) =>
  $c.report_error(
    <type>, %"method '${$type}.${$member}' has multiple delegate paths",
    $origin, $notes);

macro Stmt $report.type.delegate_cycle(
  Expr $c, Expr $type, Expr $member, Expr $origin, Expr $path) =>
  $c.report_error(
    <type>, %"delegation cycle resolving ${$type}.${$member}",
    $origin, %("delegate path: ${$path}"));

macro Stmt $report.type.method_packages(
  Expr $c, Expr $type, Expr $member, Expr $origin, Expr $notes) =>
  $c.report_error(
    <type>,
    %"method '${$type}.${$member}' is provided by multiple imported packages",
    $origin, $notes);

macro Stmt $report.type.neg_unsupported(Expr $c, Expr $type, Expr $origin) =>
  $c.report_error(
    <type>, "unary '-' requires a numeric type or implemented neg",
    $origin, %("operand type: ${$type.repr()}"));

macro Stmt $report.type.optional_ref_unchecked(Expr $c, Expr $origin) =>
  $c.report_error(
    <type>, "check optional reference before using its value",
    $origin, NULL);

macro Stmt $report.type.contains_missing(
  Expr $c, Expr $type, Expr $origin) =>
  $c.report_error(
    <type>, "operator 'in' requires an implemented contains member",
    $origin, %("receiver type: ${$type.repr()}"));

macro Stmt $report.type.operand_untyped(Expr $c, Expr $origin) =>
  $c.report_error(
    <type>, "operand has no x2c type beside a protocol participant",
    $origin,
    %("a preprocessor macro has no type here: cast it, or bind its value to a local"));

macro Stmt $report.type.is_var(Expr $c, Expr $type, Expr $origin) =>
  $c.report_error(
    <type>, "operator 'is' requires Var on the left",
    $origin, %("operand type: ${$type.repr()}"));

macro Stmt $report.type.is_selector(Expr $c, Expr $type, Expr $origin) =>
  $c.report_error(
    <type>, "operator 'is' requires a type or Symbol on the right",
    $origin, %("operand type: ${$type.repr()}"));

macro Stmt $report.type.is_tag(Expr $c, Expr $target, Expr $origin) =>
  $c.report_error(
    <type>,
    %"type ${$target.repr()} has no supported Var tag for operator 'is'",
    $origin, NULL);

macro Stmt $report.type.is_enum(Expr $c, Expr $target, Expr $origin) {
  {
    String note =
      "enum values box as the shared i32 family and retain no enum identity";
    $c.report_error(
      <type>, %"enum type ${$target.repr()} cannot be tested with 'is'",
      $origin, %($note));
  }
}

macro Stmt $report.macro.adapter_typedef(Expr $c, Expr $origin) =>
  $c.report_error(
    <macro>, "typed callback adapter target must be a typedef name",
    $origin, NULL);

macro Stmt $report.macro.adapter_pointer(
  Expr $c, Expr $type, Expr $origin) =>
  $c.report_error(
    <macro>, "typed callback adapter target must name a function pointer",
    $origin, $type ? %("target type: ${$type.repr()}") : NULL);

macro Stmt $report.parse.map_entry(Expr $c, Expr $origin) =>
  $c.report_error(<parse>, "expected one Map entry", $origin, NULL);

macro Stmt $report.type.func_callback(Expr $c) {
  {
    String message = "cannot convert Func to a context-free callback";
    List hint = %(
      "call Func directly, or use a noncapturing lambda as the C callback"
    );
    $c.report_error(<type>, message, NULL, hint);
  }
}

macro Stmt $report.type.brace_anonymous(Expr $c) =>
  $c.report_error(
    <type>, "a brace outside an initializer needs a named destination type",
    NULL, %("declare the destination with a struct tag or typedef"));

macro Stmt $report.type.var_unresolved(Expr $c, Expr $origin) {
  {
    String message = "cannot convert an unresolved expression to Var";
    $c.report_error(
      <type>, message,
      $origin, %("give the expression a declared x2c type before boxing it"));
  }
}

macro Stmt $report.type.ref_address(Expr $c) =>
  $c.report_error(
    <type>, "reference argument must name an addressable object",
    NULL, NULL);

macro Stmt $report.type.var_convert(Expr $c, Expr $target) {
  {
    String message = %"cannot convert Var to type ${$target.repr()}";
    $c.report_error(<type>, message, NULL, NULL);
  }
}

macro Stmt $report.type.var_address(Expr $c, Expr $target) =>
  $c.report_error(
    <type>, %"cannot convert Var to ${$target.repr()}",
    NULL,
    %("write &value for its address, or value.pointer() to unbox a stored pointer"));

macro Stmt $report.type.var_loss(Expr $c, Expr $type) {
  {
    String message = %"cannot convert ${$type.repr()} to Var without loss";
    $c.report_error(<type>, message, NULL, NULL);
  }
}

macro Stmt $report.type.ref_null(Expr $c, Expr $target) =>
  $c.report_error(
    <type>,
    %"cannot pass a null pointer where ${$target.repr()} is expected",
    NULL, %("a reference argument must name an object"));

macro Stmt $report.type.qualifier_dropped(
  Expr $c, Expr $source, Expr $destination) {
  {
    String message =
      %"cannot convert ${$source.repr()} to ${$destination.repr()}";
    $c.report_error(
      <type>, message,
      NULL,
      %("the target drops a type qualifier the source declares: spell the qualifier in the target, or copy the value"));
  }
}

macro Stmt $report.type.ref_lvalue(Expr $c, Expr $type, Expr $target) =>
  $c.report_error(
    <type>,
    %"cannot pass ${$type.repr()} where ${$target.repr()} is expected",
    NULL,
    %("pass an lvalue of the referenced type; write *p for a pointer"));

macro Stmt $report.type.pointer_address(Expr $c, Expr $type, Expr $target) =>
  $c.report_error(
    <type>,
    %"cannot pass ${$type.repr()} where ${$target.repr()} is expected",
    NULL, %("write &value to pass its address"));

macro Stmt $report.type.typedef_crossing(
  Expr $c, Expr $source, Expr $target) {
  {
    String message =
      %"cannot convert ${$source.repr()} to ${$target.repr()}";
    $c.report_error(
      <type>, message,
      NULL,
      %("the names share one C type but not one meaning: declare the converter ${$source.car()}_${$target.car().str().lower()}, or cast the expression to say so on purpose"));
  }
}

macro Stmt $report.type.pointer_unrelated(
  Expr $c, Expr $source, Expr $target) {
  {
    String message =
      %"cannot convert ${$source.repr()} to ${$target.repr()}";
    $c.report_error(
      <type>, message,
      NULL,
      %("the pointer types are unrelated: cast the expression to say so on purpose"));
  }
}

macro Stmt $report.type.pointer_integer(
  Expr $c, Expr $integer, Expr $target) {
  {
    String message =
      %"cannot convert the integer ${$integer} to pointer type ${$target.repr()}";
    List hint =
      %( "only a zero integer constant expression converts to a pointer" );
    $c.report_error(<type>, message, NULL, hint);
  }
}

macro Stmt $report.conversion.cast_redundant(
  Expr $c, Expr $target, Expr $origin) =>
  $c.report_warning(
    <conversion>,
    %"unnecessary conversion: the operand already has type ${$target.repr()}",
    $origin, %("remove the cast"));

macro Stmt $report.parse.statement_defer(Expr $c, Expr $origin) =>
  $c.report_error(
    <parse>,
    "a statement expression cannot directly contain a defer or managed "
    "declaration", $origin, %("move it into a nested block"));

macro Stmt $report.conversion.call_redundant(
  Expr $c, Expr $method, Expr $target, Expr $location, Expr $context) {
  {
    String hint = $context == 1 ?
      "remove the call; the hole renders the value" : $context == 2 ?
      "remove the call; the format converts the value" :
      "remove the call; the destination converts the value";
    $c.report_warning_at(
      <conversion>,
      %"unnecessary conversion: .${$method}() where ${$target.repr()} is expected",
      $location, %($hint));
  }
}
