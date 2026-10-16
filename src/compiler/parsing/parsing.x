/* The shallow and full parses, script assembly, and shared token state. */

static macro Stmt $fail.compiler_token_eof(Expr $c, Expr $site) =>
  $c.report_error(
    <parse>,
    "unexpected end of file",
    $site, NULL);

static macro Stmt $fail.compiler_script_main(Expr $c, Expr $site) =>
  $c.report_error(
    <parse>,
    "a script that defines main cannot have top-level statements",
    $site, %("move the statement into main, or remove main so the statements run"));

static macro Stmt $fail.compiler_script_local(
  Expr $c, Expr $site, Expr $name) =>
  $c.report_error(
    <type>,
    %"'${$name}' is declared among the script's statements",
    $site, %("functions cannot see those locals;"
    "declare it static to share it"));

static macro Stmt $fail.compiler_decl_duplicate(
  Expr $c, Expr $site, Expr $kind, Expr $spelling) =>
  $c.report_error(
    <type>,
    %"${$kind} '${$spelling}' is already defined in this scope",
    $site, %("prior definition: '${$spelling}'"));

static macro Stmt $fail.compiler_decl_prototype(
  Expr $c, Expr $site, Expr $spelling, Expr $prior_contract, Expr $contract) =>
  $c.report_error(
    <type>,
    %"definition '${$spelling}' does not match prior prototype",
    $site, %(
    "prototype: ${$prior_contract.repr()}"
    "definition: ${$contract.repr()}"
    ));

static macro Stmt $fail.compiler_static_dependency(
  Expr $c, Expr $site, Expr $name, Expr $target) =>
  $c.report_error(
    <parse>,
    %"file-static x2c initializer depends on non-static '${$name}'",
    $site, $target ? %("initializer: ${$target}") : NULL);

static macro Stmt $fail.compiler_token_malformed(
  Expr $c, Expr $site, Expr $status) =>
  $c.report_error(
    <parse>,
    $status == <indent> ? "inconsistent indentation" : "invalid token",
    $site, NULL);

static macro Stmt $fail.compiler_token_expected(
  Expr $c, Expr $site, Expr $type) =>
  $c.report_error(
    <parse>,
    %"expected '${$type}'",
    $site, NULL);

static macro Stmt $fail.compiler_brace_unexpected(Expr $c, Expr $site) =>
  $c.report_error(
    <parse>,
    "unexpected '}'",
    $site, %("encountered '}' without matching '{'"));

static macro Stmt $fail.compiler_brace_missing(Expr $c, Expr $site) =>
  $c.report_error(
    <parse>,
    "missing '}'",
    $site, %( "'{' opened here" ));

static macro Stmt $debug.compiler_token(Expr $token) =>
  log_debug(
    <tokenizer>, %(
    (func "tokenize")
    (type ${$token.type})
    (text ${$token.text})
    (line ${$token.line})
    (col  ${$token.col})
  ));

module {
  "collection.x",
  "parse.x",
  "scripts.x",
  "definitions.x",
  "tokens.x",
}
