/*  grammar.x -- the source forms that lowering recognizes

    Copyright (c) 2026 Gary William Flake.

    Each macro's body is the source form a lowering receives, so a lowering
    recognizes its input with `case` on the macro instead of spelling the
    parsed node. Ast helpers describe shared canonical forms; Macro helpers
    derive bare-content patterns from source macros.
*/

#pragma once
#include "common.x"
#include "macrovalue/macrovalue.x"

/** Represents one compiler AST node as a canonical immutable `List`.
    `NULL` denotes no node, and nonempty nodes have the canonical `List`-pool
    lifetime.
*/
typedef List Ast;

/** Returns the return of no value that ends a function returning `Var`. */
meta List Ast.return_none(void) =>
  %(return ("Var") (expr ("Var") (literal ("Var") "void")));

/** Returns a pattern for either lambda form, with or without captures. */
meta List Ast.lambda_pattern(void) => %(expr ? (lambda *));

/** Returns a pattern for a declarator row, with or without its initializer. */
meta List Ast.declarator_pattern(List fields) =>
  %(!or (bind @fields) (op = (bind @fields) ?));

/** Returns a source form's content pattern without its typed shell.
    Bare-content dispatch arms retain the fixed head the match emitter labels.
    Inside a shell, write `%(expr ? $($shape(...)))` instead.
*/
meta List Macro.content_pattern(Macro shape, List names) =>
  shape.pattern(names).caddr();

/** Returns bare call content with the supplied callee and argument
    patterns.
*/
meta List Macro.call_content(Macro call, List callee, List arguments) {
  List pattern = call.pattern(%(?callee *arguments));
  return pattern.caddr().list().replace(
    %((?callee $callee) (*arguments $arguments)));
}

/* A try whose only exit work is its finalizer. */
macro Stmt $tried(Stmt $body, Stmt $finalizer) {
  try $body finally $finalizer
}

/* A try with catch arms, each a pattern and a body, and a finalizer. */
macro Stmt $caught(Stmt $body, Stmt $finalizer, Catch @arms) {
  try $body catch @arms finally $finalizer
}

/* A raise with its code and its detail keys and values, alternating. */
macro Stmt $raised(Expr $code, Expr @details) {
  raise %($code @details);
}

/* A match with its complete source-ordered arm and directive rows. */
macro Stmt $matched(Expr $subject, MatchRow @rows) {
  match ($subject) { @rows }
}

/* A cleanup statement owned by the rest of its enclosing block. */
macro Stmt $deferred(Stmt $body) {
  defer $body
}

/* A conditional with one branch. */
macro Stmt $if_then(Expr $condition, Stmt $yes) {
  if ($condition) $yes
}

/* A conditional with both branches. */
macro Stmt $if_else(Expr $condition, Stmt $yes, Stmt $no) {
  if ($condition) $yes else $no
}

/* A loop that tests before its body. */
macro Stmt $while_loop(Expr $condition, Stmt $body) {
  while ($condition) $body
}

/* A loop that tests after its body. */
macro Stmt $do_loop(Stmt $body, Expr $condition) {
  do $body while ($condition)
}

/* Optional header clauses retain the parser's absent fields; the first
   clause can also be a declaration in its own for scope. */
macro Stmt $for_loop(Expr $init, Expr $condition, Expr $advance, Stmt $body) {
  for ($init; $condition; $advance) $body
}

/* A switch whose body owns its cases. */
macro Stmt $switched(Expr $subject, Stmt $body) {
  switch ($subject) $body
}

/* Return's result type is binder context, not source syntax. */
macro Stmt $return_empty() { return; }
macro Stmt $return_value(Expr $value) { return $value; }

/* One expression used as a statement, retaining its bound expression. */
macro Stmt $expression_statement(Expr $value) { $value; }

/* A noncapturing lambda expression: its parameters and body. */
macro Expression $lambda_expression(Expr $body, Param @params) =>
  %!(@params) => $body;

/* A lambda with the value and reference rows its binder supplied. */
macro Expression $lambda_captured(
  Expr $body, Captures $captures, Param @params) =>
  %!(@params) using $captures => $body;

/* The parsed bracket index, before receiver-specific lowering. */
macro Expression $indexed(Expr $receiver, Expr $selector) =>
  $receiver[$selector];

/* A call with its typed callee and source-ordered arguments. */
macro Expression $called(Expr $callee, Expr @arguments) =>
  $callee(@arguments);

/* Complete, source-ordered collection members before semantic resolution. */
macro Expression $array_value(Expr @items) => %[@items];
macro Expression $map_value(Entry @rows) => %{$(@rows)};

/* Assignment syntax, before receiver-specific lowering. */
macro Expression $assigned(Expr $target, Expr $stored) => $target = $stored;

/* Unary source forms used by designation analysis before and after typing. */
macro Expression $addressed(Expr $value) => &$value;
macro Expression $dereferenced(Expr $value) => *$value;

/* Grouping preserves its operand as parsed, without unwrapping a cast. */
macro Expression $grouped(Expr $value) => ($value);

/* Sizeof has distinct source forms with and without grouping. */
macro Expression $sizeof_expression(Expr $value) => sizeof $value;
macro Expression $sizeof_grouped(Expr $value) => sizeof($value);

/* The two `is` source forms select a Type or a Symbol expression. */
macro Expression $has_type(Expr $value, Type $target) => $value is $target;
macro Expression $has_symbol(Expr $value, Expr $tag) => $value is $tag;
