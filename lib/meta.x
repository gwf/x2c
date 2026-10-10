/*  meta.x -- the compiler surface a `meta` function calls

    Copyright (c) 2025 Gary William Flake

    A `meta` function runs inside the compiler, so it can ask the compiler
    questions and build syntax for it to bind. This module declares those
    operations in x2c; the macro values a `meta` function applies and
    recognizes are in `macro-value.x`. Code builds code with quotations
    (`$!( ... )`, `$!{ ... }`, `$!T{ ... }`) and `%(...)` Lists, so the
    surface declares no constructors.

    The operations on a value are methods of the value's type: `Code`,
    captured code, and `Type`, a semantic type. The rest are `x2c_` helpers
    that have no captured receiver: the identifier check, the invocation
    site, embedded text, ancestry and placement, diagnostics, and the
    definition hashes. Compile-time Lisp names a method `Owner.member`,
    as in `Code.binding_spelling`, and a helper with each `_` of its name
    as `.`, as in `x2c.invocation.line`. The semantics are specified under
    "Compile-time Lisp and imports" in the language reference.

    Each operation is a bodyless `meta` prototype the compiler supplies. A
    `meta` function that reaches one, directly or through another `meta`
    function, is compile-time only: the compiler emits no run-time form for
    it and diagnoses a run-time call where it is written.

    Two operations let a macro contribute code beyond its result.
    `x2c_enclosing` answers the initialized declarator, block item,
    function, or unit around the invocation, and `x2c_place` puts code
    after that declarator or block item, on the exits of its block, at the
    entry of its function, among the unit's support declarations, or in its
    initialization, under the expansion's transaction. `$auto` is built on
    them.

    The library builds it as an optional module, but the prelude's
    `varops.x` includes it for its own `meta` rows, so every unit sees its
    declarations. Include it explicitly where `meta` functions are written.
    Shared compile-time definitions use ordinary source includes.
*/

#pragma once

#include "array.x"
#include "atom.x"
#include "common.x"
#include "list.x"
#include "match.x"
#include "string.x"
#include "symbol.x"
#include "symbolset.x"

/** A macro as a value: called to build code, or used in a Match `case` to
    recognize code and capture its parameters. */
typedef List Macro;

/** Semantic type syntax with canonical List-pool lifetime. */
typedef List Type;

/** Captured code parsed from source or produced by a quotation. */
typedef List Code;

// meta parameter types

/** A `meta` parameter declared `TypeInfo` receives, at a `$` call, the
   description of its argument's type: `((name N) (kind K) (type T)
   (fields F) (methods M))`. Read a part with `List.assoc`. */
typedef List TypeInfo;

/** A `meta` parameter declared `Source` receives, at a `$` call, captured
   syntax with the source text it came from: `((text T) (file F) (syntax
   S))`. `Code.source_text` and `x2c_embed_text` read it directly. */
typedef List Source;

/* captured code

   The questions about code a body cannot answer by walking the List: its
   type and value, the source the developer wrote, a binding's spelling,
   and the parts of a captured function. Each reaches compiler state the
   code only refers to. */

/** Returns the canonical semantic type of captured code in the current
    expansion. Unbound expressions are resolved in that expansion. */
meta Type Code.type(Code value);

/** Returns the value of captured constant code, including a literal or a
    macro value. Rejects expressions that require runtime evaluation. */
meta Var Code.value(Code code);

/** Returns the source text the developer wrote for `syntax`, exactly as it
    appears in the file: the text a `Source` argument carries. Fails the
    expansion when the captured syntax is incomplete. */
meta String Code.source_text(Var syntax);

/** Returns the spelling of the binding `syntax` names: an identifier
    `String`, or identifier or binding syntax. Fails the expansion when
    `syntax` is neither or names an unknown binding. */
meta String Code.binding_spelling(Var syntax);

/** Returns the spelling of the function `function` defines. */
meta String Code.name(Code function);

/** Returns the expression reading the parameter of `function` spelled
    `name`. Fails the expansion when `function` has no such parameter. */
meta Code Code.parameter(Code function, String name);

/** Returns the statements in the body of `function`. */
meta List Code.body(Code function);

/** Returns the argument expressions that forward `parameters`, a `params`
    form or the parameters themselves. A `(void)` parameter list answers
    nothing. */
meta List Code.arguments(Code parameters);

/** Tests whether control cannot reach the end of the statement
    `statement`, because it ends in a `return` or in a raise or call that
    does not return. */
meta int Code.exits(Code statement);

/** Returns the C spelling of the static string literal `value` holds as a
    printf-family format, or NULL when the format is not known until the
    program runs. A `String` literal's text is spelled as a C literal. */
meta String Code.format(Code value);

/** Tests whether the Match pattern expression `pattern` builds the same
    value each time it runs, so it can be prepared once. */
meta int Code.is_static_pattern(Code pattern);

/* lowering code

   What a translator returns: code converted, promoted, or called as the
   compiler would, marked as already lowered. */

/** Returns the expression `value` converted to `target` as a destination of
    that type converts it. */
meta Code Code.convert(Code value, Type target);

/** Returns `value` as a `String` when it is a C string literal, or one in
    parentheses or in both arms of a conditional, as a method receiver,
    a `foreach` collection, or a raise detail converts one; returns any
    other `value` itself. */
meta Code Code.promoted(Code value);

/** Returns a `type` expression that calls the protocol member `member`
    with `arguments`, each converted to its parameter and evaluated once,
    in order, before the call. */
meta Code Code.call_in_order(Code member, List arguments, Type type);

/** Returns `code`, which is already bound, typed, and lowered, marked so
    that a translator's result is placed as written instead of bound and
    lowered again. */
meta Code Code.lowered(Code code);

/* registering translators */

/** Registers a translator for the code `pattern` recognizes: a macro with
    optional hole patterns, whose recognition uses the source views and
    binding identity rules of a macro-valued case, or a Match pattern.
    NULL holes use the macro's named captures.

    The pattern's form selects the operations that test it: an indexed
    access or assignment, a binary operator, a member call by receiver
    type, a call by callee spelling, an Array or Map literal by head, a
    `switch`, `try`, or `raise` node, or a function definition. An operator the
    pattern writes as `(!or OP...)` registers it for each operator. An
    operator pattern that types the operation or an operand `Var`, or an
    alias of it, takes the dynamic operations instead: those with an
    operand of `Var` identity that no protocol member resolved, each
    presented typed `Var`. A member call whose receiver pattern is
    `(expr MARK *)`, with a field keyword Symbol for its type, takes the
    calls that find no member on a receiver whose aggregate declares a field
    with that keyword, such as `delegate`.

    A `Unit` macro whose body is one function definition, or only its one
    `Function` hole, registers a function rule. The compiler offers each
    function definition the unit emits, including a lifted lambda body, to
    the function rules once, bound and typed, before its body lowers.
    Rules keyed by the return type and storage the pattern spells come
    before rules whose pattern holds a hole there. A rule declines by
    returning its input, void, or null, and then costs only its match and
    call. A replacement is a function definition to bind, or a bound or
    lowered code-value carrier; it is lowered as written and offered to
    the other rules, but not again to the rule that returned it. */
meta Code Code.register_rewrite(Code function, List pattern, List holes);

/** Registers block items to follow matching local initializations. */
meta Code Code.register_after_initialization(
  Code function, Macro shape, List holes);

/* semantic types

   The generated-code questions: what a struct holds, how its declaration
   is spelled, what a name resolves to, whether a `Var` holds its values,
   and which operation a member call selects. The answers live in the
   symbol table, so a body cannot derive them from syntax. */

/** Tests named-type ancestry without resolving through the named owner. */
meta int Type.is_named(Type type, String name);

/** Returns the numeric type reached through typedefs, or NULL. */
meta Type Type.numeric(Type type);

/** Tests String ancestry or a canonical char pointer/array type. */
meta int Type.is_text(Type type);

/** Tests whether a `Var` can hold a value of `type`: a numeric scalar or
    enum, Symbol, Var, Atom, String, List, or a typedef of one. */
meta int Type.is_value(Type type);

/** Returns the type the type key `type` resolves to through its typedefs. */
meta Type Type.resolve(Type type);

/** Returns `(BASE MODIFIERS)`, the declaration parts that spell `type` in
    source. */
meta List Type.parts(Type type);

/** Returns the type the pointer or array `type` refers to. */
meta Type Type.element(Type type);

/** Returns the parameter types of the function `type`, or of the function
    a pointer or array `type` refers to. */
meta List Type.parameters(Type type);

/** Returns the result type of the function `type`. */
meta Type Type.return_type(Type type);

/** Returns the struct or union tag `type` reaches through typedefs or one
    pointer level, or NULL. */
meta Type Type.aggregate(Type type);

/** Returns the named fields of the struct or union `type`, in declaration
    order, each as a `(NAME TYPE)` row. Fails the expansion when `type` is
    not a complete aggregate. */
meta List Type.fields(Type type);

/** Returns the `(NAME TYPE)` layout rows of the type `type` resolves to,
    including its unnamed members. */
meta List Type.layout(Type type);

/** Returns the `(NAME TYPE)` layout rows of the fields of the aggregate tag
    `aggregate` declared with the field keyword `mark`, such as `delegate`,
    in declaration order. */
meta List Type.marked_fields(Type aggregate, Symbol mark);

/** Returns the members of the enum `type` as `(NAME VALUE)` rows in
    declaration order. An implicit value is nil; a literal value retains
    its spelling, and another value is its expression. */
meta List Type.members(Type type);

/** Returns how ordinary member lookup selects `name` on a `type` receiver
    with `.`: `(field ACCESS TYPE)`, `(method BINDING SIGNATURE)`,
    `(ambiguous PACKAGE...)` when imported packages each provide the method,
    or NULL. Methods are selected only when `call` is nonzero, as for a
    call. */
meta List Type.resolve_member(Type type, String name, int call);

/** Returns the selected protocol callable, or null if unavailable in the
    current function. Selection includes explicit protocol adoption. */
meta Code Type.protocol_member(Type type, String name);

/** Returns the callable a bracket read on a `type` value calls: its own
    `getindex`, else the selected protocol member, or null. */
meta Code Type.getter(Type type);

/** Returns the runtime helper that applies a dynamic update to a `type`
    lvalue, a numeric scalar, or null for any other type. */
meta String Type.update_helper(Type type);

/** Returns the generated tag name for the type named `name`, unique to
    this source file. */
meta Symbol Type.tag_name(String name);

/** Returns the spelling of the reverse converter from the type named
    `base` to the type named `participant`. */
meta String Type.reverse_name(String base, String participant);

/* names

   A quotation's `$name` fills a name with a String, but a name that a
   typed quotation reads, or that Lisp builds, is the checked identifier
   value this returns. */

/** Returns the checked identifier syntax for `spelling`, which the compiler
    resolves where the returned expression is bound. Fails the expansion
    when `spelling` is not an identifier. */
meta List x2c_ident(String spelling);

/* the invocation site

   Where the macro was written and what is beside it. A macro that reports
   its own diagnostic, or reads a data file next to its source, needs the
   site, which can differ from the compiler's current position. */

/** Returns the file the macro invocation appears in. */
meta String x2c_invocation_file(void);

/** Returns the line the macro invocation appears on. */
meta int x2c_invocation_line(void);

/** Returns the column the macro invocation begins at. */
meta int x2c_invocation_column(void);

/** Returns the text of the file at `path`, a `String` or a `Source`
    holding a `String` literal, resolved against the source that named it,
    and records it as a translation dependency. Fails the expansion when it
    cannot be read. */
meta String x2c_embed_text(Var path);

/* ancestry and placement

   A macro that contributes code beyond its own result asks where it
   stands and places that code where the compiler finishes it. */

/** Returns the innermost `what` around the invocation, or nothing when
    there is none. `<declarator>` answers the initialized declarator whose
    initializer directly holds the invocation, as its one-declarator
    declaration; `<statement>` the enclosing block item, as its origin
    anchor for `x2c_diagnostic_fail_at`; `<function>` the enclosing
    function definition, whose body is still the empty `(seq)`; and
    `<unit>` a `String` expression of the unit's path. */
meta Code x2c_enclosing(Symbol what);

/** Places `code` under the expansion's transaction. `where` is
    `%(after-statement)`, after the enclosing block item or the
    initialized declarator whose initializer holds the invocation;
    `%(block-exit)`, run on every transfer that leaves the enclosing block
    after that item or declarator, as `defer code` written after it runs;
    `%(function-entry)`, at the entry of the enclosing function
    definition, after its parameters bind and before its first statement,
    in placement order; code in a lambda body enters the definition that
    holds the lambda;
    `%(unit-support)` among the unit's file-scope support declarations, or
    `%(unit-support KEY)` once for each KEY; or `%(unit-init)` in the
    unit's initialization, or `%(unit-init AREA)` in its `protocol`,
    `prepare`, `statics`, or `finish` area. Code placed after a declarator
    requires the expansion's result to be that declarator's complete
    initializer. */
meta void x2c_place(List where, Code code);

/* failing

   A macro that checks its argument needs to say what is wrong at the site
   the developer wrote, which no return value can do. */

/** Reports `message` with `notes` at the macro invocation and fails the
    expansion. This does not return. */
meta void x2c_diagnostic_fail(String message, List notes);

/** Reports `message` with `notes` under `category`, such as `<parse>` or
    `<type>`, at `node`, syntax the macro received, and fails the
    expansion. The position is the first one recorded in or around `node`,
    such as a captured statement's; a node without one reports at the macro
    invocation. This does not return. */
meta void x2c_diagnostic_fail_at(
  Var node, Symbol category, String message, List notes);

/** Reports `message` with `notes` under `category` at `node`, located as
    `x2c_diagnostic_fail_at` locates it, and returns so the expansion
    continues. The translation fails when it finishes. */
meta void x2c_diagnostic_error_at(
  Var node, Symbol category, String message, List notes);

/** Reports `message` with `notes` as a warning where it is raised, and
    returns so the expansion continues. */
meta void x2c_diagnostic_warn(String message, List notes);

// definition hashes

/** Returns a `Map` from each function or initialized file-static value the
    unit has defined so far to its definition's String hash, from the first
    token after any `meta` marker to the end of its body or initializer.
    The compiler links copies of shipped `meta` code and binds a definition
    to its copy only when these hashes agree. */
meta Map x2c_meta_definition_hashes(void);

/* declaration parts

   The compiler and a project's helper both spell a Type as declaration
   syntax, so the one implementation lives here. */

static const SymbolSet _base_keywords = %<<typedef struct union enum int
  long short char signed unsigned void float double>>;
static const SymbolSet _type_qualifiers = %<<const restrict volatile>>;

/** Returns the suffix of `type` that begins at its typedef name or base
    keyword, sharing `type`, or `NULL` when it has none. */
List type_base_suffix(List type) {
  for (; type; type = type.cdr()) {
    Var head = type.car();
    if (head is <string> || (head is <symbol> && head in _base_keywords))
      return type;
  }
  return NULL;
}

/** Returns the diagnostic for a `type` that names its type with an Atom
    other than a C type keyword, as `%(String)` and `%(* Point)` do, or
    `NULL`. A type name is a String, as in `%("String")` and `%(* "Point")`;
    neither a short Symbol nor a long Atom supplies that representation. */
String type_name_error(List type) {
  Var name = type.last();
  if (name is not <lsym> &&
      (name is not <symbol> || name == <*> || name in _base_keywords ||
       name in _type_qualifiers))
    return NULL;
  Array fixed = [];
  for (List rest = type; rest.cdr(); rest = rest.cdr())
    fixed.push(rest.car());
  fixed.push(name.str());
  String wanted = fixed.list_free().repr();
  return %"type name '${name}' must be a String: write %${wanted}";
}

/** Returns `(base modifiers)` for reconstructing a declaration of `type`.
    Function modifiers hold parameter syntax, and modifier order retains C
    declarator precedence. */
List type_declaration_parts(List type) {
  List base = type_base_suffix(type);
  if (!base) return %($type ());
  List reversed = %(), qualifiers = %();
  for (List rest = type; rest !== base; rest = rest.cdr())
    reversed = cons(rest.car(), reversed);
  while (reversed && reversed.car() is <symbol> &&
         reversed.car() in _type_qualifiers) {
    qualifiers = cons(reversed.car(), qualifiers);
    reversed = reversed.cdr();
  }
  Array syntax = [];
  foreach (Var item, reversed.reverse()) syntax.push(_modifier_syntax(item));
  return %(${qualifiers.append(base)} (@{syntax.list_free()}));
}

/* A function modifier's parameter types become parameter declarations. */
static Var _modifier_syntax(Var modifier) {
  match (modifier)
    case %(func ?(List parameters)): {
      Array params = [];
      foreach (List parameter, parameters) {
        List (base, modifiers) = type_declaration_parts(parameter);
        params.push(%(param $base (bind () $modifiers)));
      }
      return %(fnmod (params @{params.list_free()}));
    }
  return modifier;
}
