/*  meta.x -- the compiler surface a `meta` function calls

    Copyright (c) 2025 Gary William Flake

    A `meta` function runs inside the compiler, so it can ask the compiler
    questions and build syntax for it to bind. Those operations were
    reachable only from compile-time Lisp, under names like `x2c.ident` and
    `x2c.type.fields`, which made Lisp the authoring language for any macro
    whose implementation needed them. The declarations below name the same
    operations from x2c, so a macro's implementation is x2c.

    Nothing here has a runtime definition: each name resolves to a compiler
    operation through `etc/comptime.xlisp`, and there is no such function in
    a linked program. A `meta` function that reaches one, directly or through
    another `meta` function, is therefore compile-time only, and the compiler
    derives that and emits no runtime form for it. The consequence to know
    about is that such a function cannot be called at run time at all.

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
#include "string.x"
#include "symbol.x"

/** The namespace the compile-time operations below belong to. It is a type
    only so that its operations spell as `Meta.operation`; no value of it
    exists and none is ever made. */
typedef struct Meta *Meta;

/* --- identifiers and literals -------------------------------------------
   What a macro has to produce to return syntax at all: a checked identifier
   and the three literal expressions the compiler binds without further
   help. Without these a macro body can compute an answer and has no way to
   hand it back. */

/** Returns the checked identifier syntax for `spelling`, which the compiler
    resolves where the returned expression is bound. Fails the expansion
    when `spelling` is not an identifier. */
List Meta.ident(String spelling);

/** Returns a `String` expression holding `value`. */
List Meta.literal_string(String value);

/** Returns an `int` expression holding `value`. */
List Meta.literal_int(int value);

/** Returns a `Symbol` expression holding `value`. */
List Meta.literal_symbol(Symbol value);

/* --- expression construction --------------------------------------------
   The five expression shapes a macro assembles from parts it was given. A
   macro that only returns a literal needs none of them; one that rewrites
   its argument into a call, an index, or a member read needs the shape
   rather than the text, because the compiler binds and types the result. */

/** Returns an expression reading the identifier `name`, which is the syntax
    `Meta.ident` returned or a binding the compiler resolved. */
List Meta.expr_ident(List name);

/** Returns the expression `base[subscript]`. */
List Meta.expr_index(List base, List subscript);

/** Returns the expression `receiver.name`. */
List Meta.expr_field(List receiver, String name);

/** Returns the expression calling `callee` with `arguments`, a `List` of
    expressions. */
List Meta.expr_call(List callee, List arguments);

/** Returns the comma-separated composite initializer holding `items`, a
    `List` of expressions. */
List Meta.expr_composite(List items);

/* --- reading what the macro captured ------------------------------------
   A macro receives bound syntax, and these are the four questions about it
   a body cannot answer by walking the List: the source the developer wrote,
   a binding's spelling, an expression's type, and the value behind an
   interned constant. Each reaches compiler state the syntax only refers
   to. */

/** Returns the source text the developer wrote for `syntax`, exactly as it
    appears in the file. Fails the expansion when the captured syntax is
    incomplete. */
String Meta.source_text(Var syntax);

/** Returns the spelling of the binding `syntax` names. Fails the expansion
    when `syntax` is not an identifier or a known binding. */
String Meta.binding_spelling(Var syntax);

/** Returns the canonical `Type` of the expression, parameter, declaration,
    or binding `value`. */
List Meta.syntax_type(List value);

/** Returns the interned value behind a `(cache ID)` reference, so a
    composite literal a macro received reads as a value. Fails the expansion
    when `node` holds no such reference. */
Var Meta.cache_value(List node);

/* --- reading a captured function ----------------------------------------
   A decorator receives a whole function, and these four take it apart: its
   name, one parameter by spelling, its body, and the argument list that
   forwards its parameters. A decorator that wraps or forwards a function
   needs all four; `lib/autodiff.xmacro` uses the Lisp spellings today. */

/** Returns the spelling of the function `function` defines. */
String Meta.function_name(List function);

/** Returns the expression reading the parameter spelled `wanted`. Fails the
    expansion when `function` has no such parameter. */
List Meta.function_parameter(List function, String wanted);

/** Returns the statements in the body of `function`. */
List Meta.function_body(List function);

/** Returns the argument expressions that forward a parameter list, which is
    a `params` form or the parameters themselves. A `(void)` parameter list
    answers nothing. */
List Meta.parameters_arguments(List value);

/* --- reading a type -----------------------------------------------------
   The generated-code questions: what a struct holds, what its declaration
   looks like, what a name resolves to, whether a value of it can be held in
   a `Var`, and which operation a member call selects. This is the group a
   macro family needs, and the one a body cannot derive from syntax at all,
   because the answers live in the symbol table. */

/** Returns the named fields of a struct or union `Type`, in declaration
    order, each as a metadata row. Fails the expansion when `value` is not a
    complete aggregate `Type`. */
List Meta.type_fields(List value);

/** Returns the layout rows of the `Type` `value` resolves to, including its
    unnamed members. */
List Meta.type_layout(List value);

/** Returns the declaration parts of the `Type` `value`, which spell it in
    source. */
List Meta.type_parts(List value);

/** Returns the `Type` the type key `value` resolves to. */
List Meta.type_resolve(List value);

/** Returns whether a value of the `Type` `value` can be held in a `Var`. */
int Meta.type_value(List value);

/** Returns the generated tag name for `name`, unique to this source file. */
Symbol Meta.type_tag_name(String name);

/** Returns the spelling of the reverse converter from `base` to
    `participant`. */
String Meta.type_reverse_name(String base, String participant);

/** Returns the expression naming the operation the member call `name` on the
    `Type` `type` selects, or nothing when there is none. Fails the
    expansion when imported packages provide it ambiguously. */
List Meta.method_resolve(List type, String name);

/* --- the invocation site ------------------------------------------------
   Where the macro was written and what is beside it. A macro that reports
   its own diagnostic, or that reads a data file next to the source, needs
   the site rather than the compiler's current position. */

/** Returns the file the macro invocation appears in. */
String Meta.invocation_file(void);

/** Returns the line the macro invocation appears on. */
int Meta.invocation_line(void);

/** Returns the column the macro invocation begins at. */
int Meta.invocation_column(void);

/** Returns the text of the file at `path`, resolved against the source that
    named it, and records it as a translation dependency. Fails the
    expansion when it cannot be read. */
String Meta.embed_text(String path);

/* --- failing ------------------------------------------------------------
   A macro that checks its argument needs to say what is wrong at the site
   the developer wrote, which no return value can do. */

/** Reports `message` with `notes` at the macro invocation and fails the
    expansion. This does not return. */
void Meta.diagnostic_fail(String message, List notes);
