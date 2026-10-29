/*  expressions-reports.x -- expression typing diagnostics */

#pragma once

macro Stmt $fail.expressions_optional_ref_assign(Expr $c, Expr $origin) =>
  $c.report_error(
    <type>, "check optional reference before assigning its value",
    $origin, NULL);

macro Stmt $fail.expressions_destructure_target(Expr $c, Expr $site) =>
  $c.report_error(
    <parse>, "unsupported destructuring assignment target",
    $site, %("destructuring targets must be simple identifiers"));

macro Stmt $fail.expressions_is_pointer(Expr $c, Expr $origin) =>
  $c.report_error(
    <parse>, "pointer type after 'is' must be parenthesized",
    $origin, %("write value is (T *)"));

macro Stmt $fail.expressions_is_function(Expr $c, Expr $origin) =>
  $c.report_error(
    <type>, "function type cannot be used after operator 'is'",
    $origin, %("function types have no supported Var tag"));

macro Stmt $fail.expressions_is_array(Expr $c, Expr $origin) =>
  $c.report_error(
    <type>, "array type cannot be used after operator 'is'",
    $origin, %("array types have no supported Var tag"));

macro Stmt $fail.expressions_slice_zero(Expr $c, Expr $site) =>
  $c.report_error(<parse>, "slice step cannot be zero", $site, %());

macro Stmt $fail.expressions_member_ident(
  Expr $c, Expr $site, Expr $op, Expr $lhs) {
  {
    List notes = $("token:", $c.token.text);
    if ($lhs) notes = cons($("lhs expr:", $lhs.str()), notes);
    String msg = %"expected identifier after '$($op)'";
    $c.report_error(<parse>, msg, $site, notes);
  }
}

macro Stmt $fail.expressions_ident_semantic(
  Expr $c, Expr $origin, Expr $value) =>
  $c.report_error(
    <type>, %"identifier $($value.repr()) has no semantic type",
    $origin, NULL);

macro Stmt $fail.expressions_binding_unknown(
  Expr $c, Expr $origin, Expr $name) =>
  $c.report_error(
    <type>, "identifier has an unknown binding identity",
    $origin, %("binding: $($name.repr())"));

macro Stmt $fail.expressions_function_private(
  Expr $c, Expr $origin, Expr $spelling, Expr $file) =>
  $c.report_error(
    <type>, %"'$($spelling)' is a static function private to its unit",
    $origin, %("it is defined in '$($file)';"
    "remove 'static' so other units can call it"));

macro Stmt $fail.expressions_index_unsupported(
  Expr $c, Expr $origin, Expr $receiver_type) =>
  $c.report_error(
    <parse>, $receiver_type.is_typedef_name()
    ? %"type $($receiver_type) does not support getindex"
    : %"type $($receiver_type) does not support indexing",
    $origin, %());

macro Stmt $fail.expressions_optional_ref_index(Expr $c, Expr $origin) =>
  $c.report_error(
    <type>, "check optional reference before indexing its value",
    $origin, NULL);

macro Stmt $fail.expressions_index_missing(Expr $c, Expr $site, Expr $type) =>
  $c.report_error(<type>, %"$($type.car()) has no getindex", $site, NULL);

macro Stmt $fail.expressions_index_symbol(Expr $c, Expr $site) =>
  $c.report_error(
    <type>, "Symbol cannot be used as an integer bracket index",
    $site, NULL);

macro Stmt $fail.expressions_call_arity(
  Expr $c, Expr $origin, Expr $method, Expr $variadic, Expr $expected,
  Expr $supplied) =>
  $c.report_error(
    <type>, %"$($method ? "method" : "function") takes $(
            $variadic ? "at least " : "")$($expected) argument$(
            $expected == 1 ? "" : "s"), not $($supplied)",
    $origin, NULL);

macro Stmt $fail.expressions_method_missing(
  Expr $c, Expr $origin, Expr $type, Expr $name) =>
  $c.report_error(
    <type>, %"type $($type.repr()) has no method $($name)",
    $origin, NULL);

macro Stmt $fail.expressions_receiver_unresolved(
  Expr $c, Expr $origin, Expr $name) =>
  $c.report_error(<type>, %"unresolved identifier: $($name)", $origin, NULL);

macro Stmt $fail.expressions_receiver_address(Expr $c, Expr $origin) =>
  $c.report_error(
    <type>, "method pointer receiver requires an addressable value",
    $origin, %("bind the value to an object before calling the method"));

macro Stmt $fail.expressions_receiver_pointer(
  Expr $c, Expr $origin, Expr $type, Expr $declared) =>
  $c.report_error(
    <type>,
    %"method receiver $($type.repr()) is a pointer to $($declared.repr())",
    $origin, %("'.' reaches one pointer level; write (*receiver).method()"));

macro Stmt $fail.expressions_optional_ref_access(Expr $c, Expr $site) =>
  $c.report_error(
    <type>, "check optional reference before accessing its value",
    $site, NULL);

macro Stmt $fail.expressions_method_packages(
  Expr $c, Expr $origin, Expr $type, Expr $member, Expr $notes) =>
  $c.report_error(
    <type>,
    %"method '$($type).$($member)' is provided by multiple imported packages",
    $origin, $notes);

macro Stmt $fail.expressions_neg_unsupported(
  Expr $c, Expr $origin, Expr $type) =>
  $c.report_error(
    <type>, "unary '-' requires a numeric type or implemented neg",
    $origin, %("operand type: $($type.repr())"));

macro Stmt $fail.expressions_optional_ref_unchecked(Expr $c, Expr $origin) =>
  $c.report_error(
    <type>, "check optional reference before using its value",
    $origin, NULL);

macro Stmt $fail.expressions_contains_missing(
  Expr $c, Expr $origin, Expr $type) =>
  $c.report_error(
    <type>, "operator 'in' requires an implemented contains member",
    $origin, %("receiver type: $($type.repr())"));

macro Stmt $fail.expressions_operand_untyped(Expr $c, Expr $origin) =>
  $c.report_error(
    <type>, "operand has no x2c type beside a protocol participant",
    $origin,
    %("a preprocessor macro has no type here: cast it, or bind its value to a local"));

macro Stmt $fail.expressions_is_var(Expr $c, Expr $origin, Expr $type) =>
  $c.report_error(
    <type>, "operator 'is' requires Var on the left",
    $origin, %("operand type: $($type.repr())"));

macro Stmt $fail.expressions_is_selector(Expr $c, Expr $origin, Expr $type) =>
  $c.report_error(
    <type>, "operator 'is' requires a type or Symbol on the right",
    $origin, %("operand type: $($type.repr())"));

macro Stmt $fail.expressions_is_tag(Expr $c, Expr $origin, Expr $target) =>
  $c.report_error(
    <type>,
    %"type $($target.repr()) has no supported Var tag for operator 'is'",
    $origin, NULL);

macro Stmt $fail.expressions_is_enum(Expr $c, Expr $origin, Expr $target) {
  {
    String note =
      "enum values box as the shared i32 family and retain no enum identity";
    $c.report_error(
      <type>, %"enum type $($target.repr()) cannot be tested with 'is'",
      $origin, $(note));
  }
}

macro Stmt $fail.expressions_adapter_typedef(Expr $c, Expr $origin) =>
  $c.report_error(
    <macro>, "typed callback adapter target must be a typedef name",
    $origin, NULL);

macro Stmt $fail.expressions_adapter_pointer(
  Expr $c, Expr $origin, Expr $type) =>
  $c.report_error(
    <macro>, "typed callback adapter target must name a function pointer",
    $origin, $type ? %("target type: $($type.repr())") : NULL);

macro Stmt $fail.expressions_map_entry(Expr $c, Expr $origin) =>
  $c.report_error(<parse>, "expected one Map entry", $origin, NULL);

macro Stmt $fail.expressions_func_callback(Expr $c, Expr $site) =>
  $c.report_error(
    <type>, "cannot convert Func to a context-free callback", $site,
    %("call Func directly, or use a noncapturing lambda as the C callback"));

macro Stmt $fail.expressions_brace_anonymous(Expr $c, Expr $site) =>
  $c.report_error(
    <type>, "a brace outside an initializer needs a named destination type",
    $site, %("declare the destination with a struct tag or typedef"));

macro Stmt $fail.expressions_var_unresolved(Expr $c, Expr $origin) =>
  $c.report_error(
    <type>, "cannot convert an unresolved expression to Var",
    $origin, %("give the expression a declared x2c type before boxing it"));

macro Stmt $fail.expressions_ref_address(Expr $c, Expr $site) =>
  $c.report_error(
    <type>, "reference argument must name an addressable object",
    $site, NULL);

macro Stmt $fail.expressions_var_convert(Expr $c, Expr $site, Expr $target) =>
  $c.report_error(
    <type>, %"cannot convert Var to type $($target.repr())", $site, NULL);

macro Stmt $fail.expressions_var_address(Expr $c, Expr $site, Expr $target) =>
  $c.report_error(
    <type>, %"cannot convert Var to $($target.repr())",
    $site,
    %("write &value for its address, or value.pointer() to unbox a stored pointer"));

macro Stmt $fail.expressions_var_loss(Expr $c, Expr $site, Expr $type) =>
  $c.report_error(
    <type>, %"cannot convert $($type.repr()) to Var without loss", $site, NULL);

macro Stmt $fail.expressions_ref_null(Expr $c, Expr $site, Expr $target) =>
  $c.report_error(
    <type>,
    %"cannot pass a null pointer where $($target.repr()) is expected",
    $site, %("a reference argument must name an object"));

macro Stmt $fail.expressions_qualifier_dropped(
  Expr $c, Expr $site, Expr $source, Expr $destination) =>
  $c.report_error(
    <type>, %"cannot convert $($source.repr()) to $($destination.repr())",
    $site,
    %("the target drops a type qualifier the source declares: spell the qualifier in the target, or copy the value"));

macro Stmt $fail.expressions_ref_lvalue(
  Expr $c, Expr $site, Expr $type, Expr $target) =>
  $c.report_error(
    <type>,
    %"cannot pass $($type.repr()) where $($target.repr()) is expected",
    $site,
    %("pass an lvalue of the referenced type; write *p for a pointer"));

macro Stmt $fail.expressions_pointer_address(
  Expr $c, Expr $site, Expr $type, Expr $target) =>
  $c.report_error(
    <type>,
    %"cannot pass $($type.repr()) where $($target.repr()) is expected",
    $site, %("write &value to pass its address"));

macro Stmt $fail.expressions_typedef_crossing(
  Expr $c, Expr $site, Expr $source, Expr $target) {
  {
    String message =
      %"cannot convert $($source.repr()) to $($target.repr())";
    $c.report_error(
      <type>, message,
      $site,
      %("the names share one C type but not one meaning: declare the converter $($source.car())_$($target.car().str().lower()), or cast the expression to say so on purpose"));
  }
}

macro Stmt $fail.expressions_pointer_unrelated(
  Expr $c, Expr $site, Expr $source, Expr $target) =>
  $c.report_error(
    <type>, %"cannot convert $($source.repr()) to $($target.repr())",
    $site,
    %("the pointer types are unrelated: cast the expression to say so on purpose"));

macro Stmt $fail.expressions_pointer_integer(
  Expr $c, Expr $site, Expr $integer, Expr $target) =>
  $c.report_error(
    <type>,
    %"cannot convert the integer $($integer) to pointer type $($target.repr())",
    $site, %("only a zero integer constant expression converts to a pointer"));

macro Stmt $warn.expressions_cast_redundant(
  Expr $c, Expr $origin, Expr $target) =>
  $c.report_warning(
    <conversion>,
    %"unnecessary conversion: the operand already has type $($target.repr())",
    $origin, %("remove the cast"));

macro Stmt $fail.expressions_statement_defer(Expr $c, Expr $origin) =>
  $c.report_error(
    <parse>,
    "a statement expression cannot directly contain a defer or managed "
    "declaration", $origin, %("move it into a nested block"));

macro Stmt $warn.expressions_call_redundant(
  Expr $c, Expr $location, Expr $method, Expr $target, Expr $context) {
  {
    String hint = "remove the call; the destination converts the value";
    if ($context == 1)
      hint = "remove the call; the hole renders the value";
    else if ($context == 2)
      hint = "remove the call; the format converts the value";
    $c.report_warning_at(
      <conversion>,
      %"unnecessary conversion: .$($method)() where $($target.repr()) is expected",
      $location, $(hint));
  }
}
