/*  meta.x -- the compiler surface a `meta` function calls

    Copyright (c) 2025 Gary William Flake

    A `meta` function runs inside the compiler, so it can ask the compiler
    questions and build syntax for it to bind. This module declares those
    operations in x2c; the macro values a `meta` function applies and
    recognizes are in `macro-value.x`. Each operation's semantics and Lisp
    name are specified under "Compile-time Lisp and imports" in the language
    reference.

    A syntax builder's `meta` body is shared by compile time and run time.
    A bodyless `meta` prototype names an operation the compiler supplies
    from its declaration here. A `meta` function that reaches one, directly
    or through another `meta` function, is compile-time only: the compiler
    emits no run-time form for it and diagnoses a run-time call where it is
    written.

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
   S))`. `x2c_source_text` and `x2c_embed_text` read it directly. */
typedef List Source;

/* identifiers and literals

   What a macro has to produce to return syntax at all: a checked identifier
   and the three literal expressions the compiler binds without further
   help. Without these a macro body can compute an answer and has no way to
   hand it back. */

/** Returns the checked identifier syntax for `spelling`, which the compiler
    resolves where the returned expression is bound. Fails the expansion
    when `spelling` is not an identifier. */
meta List x2c_ident(String spelling);

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

/* expression construction

   The expression shapes a macro assembles from parts it was given. The
   compiler binds and types the result, so a macro that rewrites its
   argument into a call, an index, or a member read builds the shape; one
   that only returns a literal needs none of them. */

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

// statement and declaration construction

/** Returns an expression statement. */
meta List x2c_stmnt_make(List expression) => %(stmnt $expression);

/** Returns a return statement carrying `expression`. */
meta List x2c_stmnt_return(List expression) => %(return () $expression);

/** Returns a block containing `items` in order. */
meta List x2c_block_make(List items) => %(block @items);

/** Declares `name` with `type` and an optional initializer. */
meta List x2c_decl_make(List type, Var name, List initializer) {
  List parts = x2c_type_parts(type);
  List binding = %(bind ($name) ${parts[1]});
  if (initializer) binding = %(op = $binding $initializer);
  return %(declare ${parts[0]} (bindings $binding));
}

/** Returns a parameter named `name` with `type`. */
meta List x2c_param_make(List type, Var name) {
  List parts = x2c_type_parts(type);
  return %(param ${parts[0]} (bind ($name) ${parts[1]}));
}

/* reading what the macro captured

   A macro receives bound syntax, and these are the questions about it a
   body cannot answer by walking the List: the source the developer wrote,
   a binding's spelling, an expression's type, and a literal's value. Each
   reaches compiler state the syntax only refers to. */

/** Returns the source text the developer wrote for `syntax`, exactly as it
    appears in the file: the text a `Source` argument carries. Fails the
    expansion when the captured syntax is incomplete. */
meta String x2c_source_text(Var syntax);

/** Returns the spelling of the binding `syntax` names. Fails the expansion
    when `syntax` is not an identifier or a known binding. */
meta String x2c_binding_spelling(Var syntax);

/** Returns the canonical `Type` of the expression, parameter, declaration,
    or binding `value`. */
meta List x2c_syntax_type(List value);

/** Returns the canonical semantic type of captured code in the current
    expansion. Unbound expressions are resolved in that expansion. */
meta Type Code.type(Code value);

/** Returns the value of captured constant code, including a macro value.
    Rejects expressions that require runtime evaluation. */
meta Var Code.value(Code code);

/** Tests whether control cannot reach the end of the statement
    `statement`, because it ends in a `return` or in a raise or call that
    does not return. */
meta int Code.exits(Code statement);

/** Returns the expression `value` converted to `target` as a destination of
    that type converts it. */
meta Code Code.convert(Code value, Type target);

/** Returns the C spelling of the static string literal `value` holds as a
    printf-family format, or NULL when the format is not known until the
    program runs. A `String` literal's text is spelled as a C literal. */
meta String Code.format(Code value);

/** Tests whether the Match pattern expression `pattern` builds the same
    value each time it runs, so it can be prepared once. */
meta int Code.is_static_pattern(Code pattern);

/** Returns the captured expression `value` converted to `type` as an
    argument or assignment converts it. */
meta Code Code.convert(Code value, Type type);

/** Returns a `type` expression that calls the protocol member `member`
    with `arguments`, each converted to its parameter and evaluated once,
    in order, before the call. */
meta Code Code.call_in_order(Code member, List arguments, Type type);

/** Registers a translator with its macro and optional hole patterns.
    NULL holes use the macro's named captures. Recognition uses the source
    views and binding identity rules of a macro-valued case.

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
meta Code Code.register_rewrite(Code function, Macro shape, List holes);

/** Registers a translator for member calls that find no member on a
    receiver whose aggregate declares a field with the field keyword `mark`,
    such as `delegate`. A call on any other receiver never tests it. */
meta Code Code.register_marked_rewrite(
  Code function, Symbol mark, Macro shape, List holes);

/** Registers a translator for the operator its macro pattern spells when
    an operand has type `type`, `Var` or an alias of it: a binary operator
    that no protocol member resolved, a compound assignment, an increment
    or decrement, or a unary operator. */
meta Code Code.register_typed_rewrite(
  Code function, Type type, Macro shape, List holes);

/** Registers a translator for each operator in `operators` applied to an
    operand of `type`, `Var` or an alias of it, in `form`: `<binary>` for a
    binary operator or compound assignment, `<prefix>` for a prefix or
    unary operator, or `<postfix>`. The translator has no pattern; it
    receives every such operation. */
meta Code Code.register_operator_rewrite(
  Code function, Type type, Symbol form, List operators);

/** Registers block items to follow matching local initializations. */
meta Code Code.register_after_initialization(
  Code function, Macro shape, List holes);

/** Tests named-type ancestry without resolving through the named owner. */
meta int Type.is_named(Type type, String name);

/** Returns the numeric type reached through typedefs, or NULL. */
meta Type Type.numeric(Type type);

/** Tests String ancestry or a canonical char pointer/array type. */
meta int Type.is_text(Type type);

/** Returns the selected protocol callable, or null if unavailable in the
    current function. Selection includes explicit protocol adoption. */
meta Code Type.protocol_member(Type type, String name);

/** Returns the callable a bracket read on a `type` value calls: its own
    `getindex`, else the selected protocol member, or null. */
meta Code Type.getter(Type type);

/** Returns the runtime helper that applies a dynamic update to a `type`
    lvalue, a numeric scalar, or null for any other type. */
meta String Type.update_helper(Type type);

/** Returns the struct or union tag `type` reaches through typedefs or one
    pointer level, or NULL. */
meta Type Type.aggregate(Type type);

/** Returns the `(NAME TYPE)` layout rows of the fields of the aggregate tag
    `aggregate` declared with the field keyword `mark`, such as `delegate`,
    in declaration order. */
meta List Type.marked_fields(Type aggregate, Symbol mark);

/** Returns how ordinary member lookup selects `name` on a `type` receiver
    with `.`: `(field ACCESS TYPE)`, `(method BINDING SIGNATURE)`,
    `(ambiguous PACKAGE...)` when imported packages each provide the method,
    or NULL. Methods are selected only when `call` is nonzero, as for a
    call. */
meta List Type.resolve_member(Type type, String name, int call);

/** Returns the `String`, `int`, or `Symbol` a literal expression holds.
    Fails the expansion when `syntax` is not such a literal. */
meta Var x2c_literal_value(Var syntax);

/* reading a captured function

   A decorator receives a whole function, and these four take it apart: its
   name, one parameter by spelling, its body, and the argument list that
   forwards its parameters. */

/** Returns the spelling of the function `function` defines. */
meta String x2c_function_name(List function);

/** Returns the expression reading the parameter spelled `wanted`. Fails the
    expansion when `function` has no such parameter. */
meta List x2c_function_parameter(List function, String wanted);

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
  foreach (List parameter, value)
    match (parameter)
      case %(param ? (bind ?identity *)):
        arguments = cons(x2c_expr_ident(identity), arguments);
  return arguments.reverse();
}

/* reading a type

   The generated-code questions: what a struct holds, what its declaration
   looks like, what a name resolves to, whether a value of it can be held in
   a `Var`, and which operation a member call selects. This is the group a
   macro family needs, and the one a body cannot derive from syntax at all,
   because the answers live in the symbol table. */

/** Returns the named fields of a struct or union `Type`, in declaration
    order, each as a metadata row. Fails the expansion when `value` is not a
    complete aggregate `Type`. */
meta List x2c_type_fields(List value);

/** Returns the layout rows of the `Type` `value` resolves to, including its
    unnamed members. */
meta List x2c_type_layout(List value);

/** Returns the declaration parts of the `Type` `value`, which spell it in
    source. */
meta List x2c_type_parts(List value);

/** Returns the `Type` the type key `value` resolves to. */
meta List x2c_type_resolve(List value);

meta static Var _meta_initializer(List node) {
  match (node) {
    case %(expr ? (literal ? ?text)): return text;
    case %(?text): return text;
  }
  return node;
}

meta static void _meta_fail(String message, Var value) {
  x2c_diagnostic_fail(message, %("value: ${value.repr()}"));
}

meta static List _meta_member(List node) {
  match (node) {
    case %(op = (?name) ?value):
      return %($name ${_meta_initializer(value)});
    case %(?name): return %($name ());
  }
  _meta_fail("x2c.type.members found an unreadable member", node);
  return %();
}

/** Returns enum members as `(name value)` rows in declaration order.
    An implicit value is nil; a literal value retains its spelling. */
meta List x2c_type_members(List type) {
  List resolved = x2c_type_resolve(type);
  if (resolved.car() != <enum>)
    _meta_fail("x2c.type.members requires an enum Type", type);
  List members = resolved.reverse().car();
  List rows = %();
  foreach (List member, members) rows = cons(_meta_member(member), rows);
  return rows.reverse();
}

/** Returns whether a value of the `Type` `value` can be held in a `Var`. */
meta int x2c_type_is_value(List value);

/** Returns whether the `Type` `value` is an integral type. */
meta int x2c_type_is_integral(List value);

/** Returns whether the `Type` `value` is a pointer type. */
meta int x2c_type_is_pointer(List value);

/** Returns the `Type` the pointer or array `Type` `value` refers to. */
meta List x2c_type_element(List value);

/** Returns the parameter `Type`s of the function `Type` `value`, or of the
    function a pointer or array `Type` refers to. */
meta List x2c_type_parameters(List value);

/** Returns the result `Type` of the function `Type` `value`. */
meta List x2c_type_return(List value);

/** Returns the generated tag name for `name`, unique to this source file. */
meta Symbol x2c_type_tag_name(String name);

/** Returns the spelling of the reverse converter from `base` to
    `participant`. */
meta String x2c_type_reverse_name(String base, String participant);

/** Returns the expression naming the operation the member call `name` on the
    `Type` `type` selects, or nothing when there is none. Fails the
    expansion when imported packages provide it ambiguously. */
meta List x2c_method_resolve(List type, String name);

/** Returns the expression naming the function that implements `member` in
    the conformance of `participant` to the protocol `base`, or nothing when
    there is none. */
meta List x2c_protocol_member(List participant, List base, String member);

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
