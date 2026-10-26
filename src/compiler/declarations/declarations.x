/*  declarations.x -- declaration production, portable syntax, and defaults */

static macro Stmt $fail.compiler_ctor_parent(Expr $c, Expr $site) =>
  $c.report_error(
    <type>,
    "a forwarded class constructor has no completed parent constructor",
    $site, NULL);

static macro Stmt $fail.compiler_ctor_variadic(
  Expr $c, Expr $site, Expr $name) =>
  $c.report_error(
    <type>,
    %"'$($name)' requires an explicit variadic constructor",
    $site, NULL);

module {
  "production.x",
  "portable-syntax.x",
  "defaults.x",
}
