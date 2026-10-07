#pragma once
#include "common.x"
#include "macro-value.x"

/*  grammar.x -- the source forms that lowering recognizes

    Copyright (c) 2026 Gary William Flake.

    Each macro's body is the source form a lowering receives, so a lowering
    recognizes its input with `case` on the macro instead of spelling the
    parsed node. The accessors read the parts of a parsed node that no
    source form writes, such as a handler the parser introduced.
*/
/* A try whose only exit work is its finalizer. */
macro Stmt $tried(Stmt $body, Stmt $finalizer) {
  try $body finally $finalizer
}

/* A try with catch arms, each a pattern and a body, and a finalizer. */
macro Stmt $caught(Stmt $body, Stmt $finalizer,
    Catch @arms) {
  try $body catch @arms finally $finalizer
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
macro Stmt $if_else(Expr $condition, Stmt $yes,
    Stmt $no) {
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
macro Stmt $for_loop(Expr $init, Expr $condition, Expr $advance,
    Stmt $body) {
  for ($init; $condition; $advance) $body
}

/* A switch whose body owns its cases. */
macro Stmt $switched(Expr $subject, Stmt $body) {
  switch ($subject) $body
}

/* Return's result type is binder context, not source syntax. */
macro Stmt $return_empty() { return; }
macro Stmt $return_value(Expr $value) { return $value; }

/** Returns a return node's target type, or NULL for another form.
    The binder supplies the type; the source form does not write it. */
meta List source_return_type(List node) {
  match (node) case %(return ?type ?): return type;
  return NULL;
}

/** Returns the canonical pattern for conditional statements.
    With is normally parsed away; foreach and finally remain accepted
    canonical compatibility heads. */
meta List source_conditional_statement(void) =>
  %((!or if while do for switch try match with foreach finally) *);

/* One expression used as a statement, retaining its bound expression. */
macro Stmt $expression_statement(Expr $value) { $value; }

/** Returns a pattern for either lambda form, with or without captures. */
meta List source_any_lambda(void) => %(expr ? (lambda *));

/* A noncapturing lambda expression: its parameters and body. */
macro Expression $lambda_expression(Expr $body, Param @params) =>
  %!(@params) => $body;

/* A lambda with the value and reference rows its binder supplied. */
macro Expression $lambda_captured(Expr $body, Captures $captures,
    Param @params) => %!(@params) using $captures => $body;

/* The parsed bracket index, before receiver-specific lowering. */
macro Expression $indexed(Expr $receiver, Expr $selector) =>
  $receiver[$selector];

/* A call with its typed callee and source-ordered arguments. */
macro Expression $called(Expr $callee, Expr @arguments) =>
  $callee(@arguments);

/* Complete, source-ordered collection members before semantic resolution. */
macro Expression $array_value(Expr @items) => %[@items];
macro Expression $map_value(Entry @rows) => %{${@rows}};

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

/** Builds cast content with its children unchanged.
    The first child is a declaration or a semantic type at different stages. */
meta List source_cast_content(List parts) => cons(<cast>, parts);

/** Builds generic selection content with its declaration and ordered rows. */
meta List source_generic_content(List parts) => cons(<generic>, parts);
/** Builds va-arg content with its declaration and operand. */
meta List source_va_arg_content(List parts) => cons(<va-arg>, parts);
/** Builds comma sequence content from its ordered rows. */
meta List source_commas_content(List rows) => cons(<commas>, rows);

/** Builds slice content while retaining omitted bounds. */
meta List source_slice_content(List parts) => cons(<slice>, parts);
/** Builds braced initializer content from its ordered comma rows. */
meta List source_composite_content(List rows) =>
  %(composite ${source_commas_content(rows)});

/** Builds string content from its ordered text, expression, and cache rows.
    The parser and resolver share this shape. */
meta List source_string_content(List rows) => cons(<segments>, rows);

/** Builds operator content with its token and source-ordered operands.
    Constructed nonstandard operators retain the same form. */
meta List source_operator_content(List parts) => cons(<op>, parts);

/** Builds a typed operator expression from its content children. */
meta List source_operator_expression(List type, List parts) =>
  %(expr $type ${source_operator_content(parts)});

/** Builds postfix update content with its token and operand. */
meta List source_postfix_content(List parts) => cons(<postfix>, parts);

/** Builds a typed postfix update expression from its content children. */
meta List source_postfix_expression(List type, List parts) =>
  %(expr $type ${source_postfix_content(parts)});

/** Returns a source form's content pattern without its typed shell.
    Bare-content dispatch arms retain the fixed head the match emitter labels.
    Inside a shell, write `%(expr ? ${$shape(...)})` instead. */
meta List source_content_pattern(Macro shape, List names) =>
  shape.pattern(names).caddr();

/** Returns bare call content with the supplied callee and argument
    patterns. */
meta List source_call_content(
  Macro call, List callee, List arguments) {
  List pattern = call.pattern(%(?callee *arguments));
  return pattern.caddr().list().replace(
    %((?callee $callee) (*arguments $arguments)));
}

/** Builds return content with all bound and normalized fields. */
meta List source_return_content(List fields) =>
  cons(<return>, fields);

/** Builds block content with its complete source-ordered statements. */
meta List source_block_content(List fields) =>
  cons(<block>, fields);

/** Builds identifier content with its bound child records. */
meta List source_identifier_content(List fields) =>
  cons(<ident>, fields);

/** Builds literal content with its typed child records. */
meta List source_literal_content(List fields) =>
  cons(<literal>, fields);

/** Returns a pattern for a declarator row, with or without its initializer. */
meta List source_declarator_row(List fields) =>
  %(!or (bind @fields) (op = (bind @fields) ?));

/** Returns the source expression beneath casts and parentheses with
    its type. */
meta Var source_expression(Var value) {
  while (1) {
    match (value) {
      case %(expr ? (parens ?inner)): value = inner;
      case %(expr ? (cast ? ?inner)): value = inner;
      case %(parens ?inner): value = inner;
      case %(cast ? ?inner): value = inner;
      default: return value;
    }
  }
}

/** Returns the error handler the parser introduced for the catch arms of
    the parsed try `node`, or NULL for a try without catches. The arms read
    their captures through it, and no source form writes it. */
meta List catch_handle(List node) {
  match (node) case %(try ? (catchcases ? ?handle) ?): return handle;
  return NULL;
}

/** Restores the binder's handler after a caught template rebuild.
    The source form has no hole for this derived identity. */
meta List retain_catch_handle(List rebuilt, List handle) {
  Var marker = rebuilt.caddr().caddr();
  return rebuilt.search_replace(%(!quote $marker), handle);
}
