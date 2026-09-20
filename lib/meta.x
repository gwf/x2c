/*  meta.x -- the compiler surface a `meta` function calls

    Copyright (c) 2025 Gary William Flake

    A `meta` function runs inside the compiler, so it can ask the compiler
    questions and build syntax for it to bind. Those operations were
    reachable only from compile-time Lisp, under names like `x2c.ident` and
    `x2c.type.fields`, which made Lisp the authoring language for any macro
    whose implementation needed them. The declarations below name the same
    operations from x2c, so a macro's implementation is x2c. Each x2c name is
    its Lisp name with `_` for `.`, and the lowering maps one to the other.

    Syntax builders have `meta` bodies shared by compile time and runtime.
    A declaration with no body names a compiler operation. A `meta` function
    that reaches one, directly or through another `meta` function, is therefore
    compile-time only, the compiler derives that and emits no runtime form for
    it, and a run-time call to it is diagnosed where it is written.

    This module is not part of the implicit prelude. Include it where the
    `meta` functions are parsed: a `.xmacro` borrows the consuming unit's
    symbol table, so the unit that imports it includes this file.

    The declarations below are the signatures. Each operation's semantics are
    those of the compile-time Lisp operation of the same name, specified under
    "Compile-time Lisp and imports" in the language reference, which also gives
    the naming rule and the two answers whose shape differs.
    See `plans/meta-functions.md`.
*/

#pragma once

#include "common.x"
#include "list.x"
#include "match.x"
#include "string.x"
#include "symbol.x"

/* --- identifiers and literals -------------------------------------------
   What a macro has to produce to return syntax at all: a checked identifier
   and the three literal expressions the compiler binds without further
   help. Without these a macro body can compute an answer and has no way to
   hand it back. */

/** Returns the checked identifier syntax for `spelling`, which the compiler
    resolves where the returned expression is bound. Fails the expansion
    when `spelling` is not an identifier. */
List x2c_ident(String spelling);

/** Returns a `String` expression holding `value`. */
meta List x2c_literal_string(String value) =>
  %(expr ("String") (segments
    (segexp (expr ("String") (literal ("String") $value)))));

/** Returns an `int` expression holding `value`. */
meta List x2c_literal_int(int value) =>
  %(expr (int) (literal (int) ${value.str()}));

/** Returns a `Symbol` expression holding `value`. */
meta List x2c_literal_symbol(Symbol value) =>
  %(expr ("Symbol") (literal ("Symbol") ${value.str()} $value));

/* --- expression construction --------------------------------------------
   The five expression shapes a macro assembles from parts it was given. A
   macro that only returns a literal needs none of them; one that rewrites
   its argument into a call, an index, or a member read needs the shape
   rather than the text, because the compiler binds and types the result. */

/** Returns an expression reading the identifier `name`, which is the syntax
    `x2c_ident` returned or a binding the compiler resolved. */
meta List x2c_expr_ident(List name) => %(expr () (ident $name));

/** Returns the expression `base[subscript]`. */
meta List x2c_expr_index(List base, List subscript) =>
  %(expr () (index $base $subscript));

/** Returns the expression `receiver.name`. */
meta List x2c_expr_field(List receiver, String name) {
  List checked = x2c_ident(name);
  return %(expr () (op . $receiver (${checked[1]})));
}

/** Returns the expression calling `callee` with `arguments`, a `List` of
    expressions. */
meta List x2c_expr_call(List callee, List arguments) =>
  %(expr () (call $callee (args @arguments)));

/** Returns the comma-separated composite initializer holding `items`, a
    `List` of expressions. */
meta List x2c_expr_composite(List items) =>
  %(expr () (composite (commas @items)));

/** Returns `expression` cast to `type`, which is a declared type rather
    than syntax. A generator needs it where the value it holds and the
    parameter it reaches differ in width or sign. */
meta List x2c_expr_cast(List type, List expression) {
  List parts = x2c_type_parts(type);
  return %(expr $type
    (cast (decl ${parts[0]} (bindings (bind () ${parts[1]}))) $expression));
}

/* --- reading what the macro captured ------------------------------------
   A macro receives bound syntax, and these are the four questions about it
   a body cannot answer by walking the List: the source the developer wrote,
   a binding's spelling, an expression's type, and the value behind an
   interned constant. Each reaches compiler state the syntax only refers
   to. */

/** Returns the source text the developer wrote for `syntax`, exactly as it
    appears in the file. Fails the expansion when the captured syntax is
    incomplete. */
String x2c_source_text(Var syntax);

/** Returns the spelling of the binding `syntax` names. Fails the expansion
    when `syntax` is not an identifier or a known binding. */
String x2c_binding_spelling(Var syntax);

/** Returns the canonical `Type` of the expression, parameter, declaration,
    or binding `value`. */
List x2c_syntax_type(List value);

/** Returns the interned value behind a `(cache ID)` reference, so a
    composite literal a macro received reads as a value. Fails the expansion
    when `node` holds no such reference. */
Var x2c_cache_value(List node);

/* --- reading a captured function ----------------------------------------
   A decorator receives a whole function, and these four take it apart: its
   name, one parameter by spelling, its body, and the argument list that
   forwards its parameters. A decorator that wraps or forwards a function
   needs all four; `lib/autodiff.xmacro` uses the Lisp spellings today. */

/** Returns the spelling of the function `function` defines. */
String x2c_function_name(List function);

/** Returns the expression reading the parameter spelled `wanted`. Fails the
    expansion when `function` has no such parameter. */
List x2c_function_parameter(List function, String wanted);

/** Returns the statements in the body of `function`. */
meta List x2c_function_body(List function) {
  match (function) case %(function ? ? (block *body)): return body;
  return %();
}

/** Returns the argument expressions that forward a parameter list, which is
    a `params` form or the parameters themselves. A `(void)` parameter list
    answers nothing. */
meta List x2c_parameters_arguments(List value) {
  match (value) case %(params *items): value = items;
  match (value) case %((param (void) (bind () ?))): return %();
  List arguments = %();
  foreach (List parameter, value) {
    match (parameter)
      case %(param ? (bind ?identity *)):
        arguments = cons(x2c_expr_ident(identity), arguments);
  }
  return arguments.reverse();
}

/* --- reading a type -----------------------------------------------------
   The generated-code questions: what a struct holds, what its declaration
   looks like, what a name resolves to, whether a value of it can be held in
   a `Var`, and which operation a member call selects. This is the group a
   macro family needs, and the one a body cannot derive from syntax at all,
   because the answers live in the symbol table. */

/** Returns the named fields of a struct or union `Type`, in declaration
    order, each as a metadata row. Fails the expansion when `value` is not a
    complete aggregate `Type`. */
List x2c_type_fields(List value);

/** Returns the layout rows of the `Type` `value` resolves to, including its
    unnamed members. */
List x2c_type_layout(List value);

/** Returns the declaration parts of the `Type` `value`, which spell it in
    source. */
List x2c_type_parts(List value);

/** Returns the `Type` the type key `value` resolves to. */
List x2c_type_resolve(List value);

/** Returns whether a value of the `Type` `value` can be held in a `Var`. */
int x2c_type_value(List value);

/** Returns the generated tag name for `name`, unique to this source file. */
Symbol x2c_type_tag_name(String name);

/** Returns the spelling of the reverse converter from `base` to
    `participant`. */
String x2c_type_reverse_name(String base, String participant);

/** Returns the expression naming the operation the member call `name` on the
    `Type` `type` selects, or nothing when there is none. Fails the
    expansion when imported packages provide it ambiguously. */
List x2c_method_resolve(List type, String name);

/* --- the invocation site ------------------------------------------------
   Where the macro was written and what is beside it. A macro that reports
   its own diagnostic, or that reads a data file next to the source, needs
   the site rather than the compiler's current position. */

/** Returns the file the macro invocation appears in. */
String x2c_invocation_file(void);

/** Returns the line the macro invocation appears on. */
int x2c_invocation_line(void);

/** Returns the column the macro invocation begins at. */
int x2c_invocation_column(void);

/** Returns the text of the file at `path`, resolved against the source that
    named it, and records it as a translation dependency. Fails the
    expansion when it cannot be read. */
String x2c_embed_text(String path);

/* --- failing ------------------------------------------------------------
   A macro that checks its argument needs to say what is wrong at the site
   the developer wrote, which no return value can do. */

/** Reports `message` with `notes` at the macro invocation and fails the
    expansion. This does not return. */
void x2c_diagnostic_fail(String message, List notes);
