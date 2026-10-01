/*  meta.x -- the compiler surface a `meta` function calls

    Copyright (c) 2025 Gary William Flake

    A `meta` function runs inside the compiler, so it can ask the compiler
    questions and build syntax for it to bind. This module declares those
    operations in x2c and implements the macro values a `meta` function
    applies and recognizes. Each operation's semantics and Lisp name are
    specified under "Compile-time Lisp and imports" in the language
    reference.

    A syntax builder's `meta` body is shared by compile time and run time.
    A bodyless `meta` prototype names an operation the compiler supplies
    from its declaration here. A `meta` function that reaches one, directly
    or through another `meta` function, is compile-time only: the compiler
    emits no run-time form for it and diagnoses a run-time call where it is
    written.

    The library builds it as an optional module, but the prelude's
    `varops.x` includes it for its own `meta` rows, so every unit sees its
    declarations; the one-line import of `system-macros.xmacro` relies on
    that. Include it explicitly where `meta` functions are written: a
    `.xmacro` borrows the consuming unit's symbol table.
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

// meta parameter types

/** A `meta` parameter declared `Type` receives, at a `$` call, the
   description of its argument's type: `((name N) (kind K) (type T)
   (fields F) (methods M))`. Read a part with `List.assoc`. */
typedef List Type;

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

/* failing

   A macro that checks its argument needs to say what is wrong at the site
   the developer wrote, which no return value can do. */

/** Reports `message` with `notes` at the macro invocation and fails the
    expansion. This does not return. */
meta void x2c_diagnostic_fail(String message, List notes);

/** Reports `message` with `notes` as a warning where it is raised, and
    returns so the expansion continues. */
meta void x2c_diagnostic_warn(String message, List notes);

// definition hashes

/** Returns a `Map` from the name of each function the unit has defined so
    far to the hash of its definition text, from the first token after any
    `meta` marker to the end of its body. The compiler links copies of
    shipped `meta` code and binds a definition to its copy only when these
    hashes agree. */
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

/* macro values

   A `Macro` is the canonical `macrodef` record of a definition. `$name`
   selects one and `macro Kind(...) => ...` creates one. Applying it returns
   a pending invocation the compiler expands and binds at the insertion
   site; naming it in a `case` derives a Match pattern from the same body. */

/** A macro as a value: called to build code, or used in a Match `case` to
   recognize code and capture its parameters. */
typedef List Macro;

/** Records the Macro values an anonymous macro captured where it was
   created, so applying it later applies the same children. */
Macro Macro_close(Macro value, List captures) =>
  value.append(%((env $captures)));

/** Applies a macro value to code values. The result is a pending
   invocation; inserting it into a program expands and binds it there. */
List Macro_apply(Macro t, List values) =>
  %("x2c.template" $t ${_macro_group(t, values)});

/* Groups positional arguments by the definition's parameters: a sequence
   parameter takes every remaining argument as one List. */
static List _macro_group(Macro t, List values) {
  Array grouped = [];
  foreach (List hole, t.assoc(<parameters>).list()) {
    int sequence = hole.assoc(<sequence>);
    /* One List of syntax passes the whole sequence, as `call(f, items)`. */
    if (sequence && values && !values.cdr() && values.car() is <list>) {
      List items = values.car();
      if (!items || items.car() is <list>) values = items;
    }
    grouped.push(sequence ? values.var() : values.car());
    values = sequence ? NULL : values.cdr();
  }
  return grouped.list_free();
}

// subject bindings

/* The rows `Macro.use_subject` set, or void when no call describes its
   subject. */
static Var macro_subject = void;

/* Whether the pattern being derived resolved a free reference against the
   current call's subject, which ties it to that call. */
static threaded int macro_subject_used;

/** Returns the table `Macro.use_subject` last set, or void. */
Var Macro.subject(void) => macro_subject;

/** Sets the `(SPELLING BINDING)` rows for global references and the
    `(source-spelling BINDING SPELLING)` rows for renamed local bindings in
    a compile-time call's syntax arguments. A macro value's free reference
    recognizes only the recorded global binding; with void it recognizes
    any binding of its spelling. The compiler sets these rows for each
    `meta` call and carries them through the helper. */
void Macro.use_subject(Var rows) { macro_subject = rows; }

/* The pattern for a free reference to `spelling`: any binding of it, or
   only the subject's binding while a call sets a subject. */
static Var _macro_free_reference(String spelling) {
  if (macro_subject is void) return %(binding ? $spelling);
  macro_subject_used = 1;
  foreach (List row, macro_subject.list())
    if (row.car() == spelling) return row.cadr();
  return %(binding-name $spelling);
}

/* pattern derivation

   A pattern is the macro's body with each parameter's projections replaced
   by its binder and each child macro call inlined. The projection keys are
   the replacement binders the compiler writes into a template. */

/** Derives the Match pattern that recognizes code this macro builds,
   capturing each parameter under the given binder. */
List Macro_pattern(Macro t, List names) {
  return _macro_pattern(t, names, 0);
}

static List _macro_pattern(Macro t, List names, int case_pattern) {
  List rows = _macro_binder_rows(t, names, case_pattern);
  List body = t.assoc(<template>);
  List pattern =
    _macro_pattern_view(_macro_inline(t.assoc(<env>), body.replace(rows)));
  /* A one-statement block item also matches inside its `seq`. */
  if (t.assoc(<kind>) == <block-item> && body.car() == <seq> &&
      body.cdr().len() == 1)
    return %(!or $pattern (seq $pattern));
  return pattern;
}

/* The rows that replace each parameter's projections with its binder. A
   Type or captures parameter is a List splice, so its binder is a List
   binder. A name read as an expression is an identifier of its binding,
   as `_macro_value_rows` builds it. */
static List _macro_binder_rows(Macro t, List names, int case_pattern) {
  List rows = NULL;
  foreach (List hole, t.assoc(<parameters>).list()) {
    Var selected = names.car(), kind = hole.assoc(<kind>);
    names = names.cdr();
    if (kind == <type> || kind == <captures>)
      selected = Atom.intern("*" + selected.str()[1:]);
    int sequence = hole.assoc(<sequence>);
    Var projected = sequence ? %($selected).var() : selected;
    if (case_pattern && kind == <name>)
      projected = %(!and $selected ${_macro_name_identity(hole)});
    Var expression = !sequence && kind == <name>
                   ? %(expr ? (ident $projected)).var() : projected;
    rows = cons(%(${_macro_key(hole, "expression")} $expression), rows);
    rows = cons(%(${_macro_key(hole, "value")} $projected), rows);
    rows = cons(%(${_macro_key(hole, "source")} $projected), rows);
    rows = cons(%(${_macro_key(hole, "member")} $selected), rows);
    rows = cons(%(${_macro_key(hole, "splice")} ($selected)), rows);
  }
  return rows;
}

/* The key of one projection of a hole. A splice is always a sequence
   binder, and a member never is. */
static Atom _macro_key(List hole, String projection) {
  String name = hole.assoc(<binder>).str()[1:];
  int sequence = hole.assoc(<sequence>);
  if (projection == "splice") sequence = 1;
  else if (projection == "member") sequence = 0;
  return Atom.intern(%"${sequence ? "*" : "?"}__macro_${projection}_$name");
}

/* The second slot of a Name's declaration and reference projection keeps
   exact binding identity when a member label reaches the first slot first. */
static Atom _macro_name_identity(List hole) =>
  Atom.intern(%"?__macro_identity_${hole.assoc(<binder>).str()[1:]}");

static List _macro_instantiate(Macro t, List values);

/* Inlines each child macro the body calls, instantiated with its
   arguments, and drops the shell a template leaves around an
   expression. */
static Var _macro_inline(List environment, Var tree) {
  if (tree is not <list>) return tree;
  match (tree) {
    case %(expr (<macro-expr>) (expr ?type ?body)):
      return _macro_inline(environment, %(expr $type $body));
    case %(tpl-call (expr ? (ident ?binding)) (args *arguments)):
      return _macro_instantiate(_macro_child(environment, binding), arguments);
    case %(literal *): return tree;
  }
  Array parts = [];
  foreach (Var part, tree.list()) parts.push(_macro_inline(environment, part));
  return parts.list_free();
}

/* The Macro value the environment captured for `binding`, or NULL. */
static Macro _macro_child(List environment, Var binding) {
  foreach (List row, environment)
    if (List.compare(row.car(), binding) == 0) return row.cadr();
  return NULL;
}

/* Substitutes grouped values into the body directly. Pattern derivation
   uses this for a captured child macro; construction goes through the
   compiler's invocation rows instead. */
static List _macro_instantiate(Macro t, List values) {
  List rows = _macro_value_rows(t, values), body = t.assoc(<template>);
  return _macro_inline(t.assoc(<env>), body.replace(rows));
}

/* The rows that replace each parameter's projections with its argument. A
   name read as an expression is an identifier of its binding. */
static List _macro_value_rows(Macro t, List values) {
  List rows = NULL;
  foreach (List hole, t.assoc(<parameters>).list()) {
    int sequence = hole.assoc(<sequence>);
    Var kind = hole.assoc(<kind>);
    Var value = sequence ? values.var() : values.car();
    if (kind == <expr>)
      value = sequence ? _macro_expr_values(values).var()
                       : _macro_expr_value(value);
    Var expression = !sequence && kind == <name>
                   ? %(expr () (ident $value)).var() : value;
    rows = cons(%(${_macro_key(hole, "expression")} $expression), rows);
    rows = cons(%(${_macro_key(hole, "value")} $value), rows);
    rows = cons(%(${_macro_key(hole, "source")} $value), rows);
    if (kind == <name>)
      rows = cons(%(${_macro_key(hole, "member")} $value), rows);
    rows = cons(%(${_macro_key(hole, "splice")} $value), rows);
    values = sequence ? NULL : values.cdr();
  }
  return rows;
}

/* An expression parameter takes code, so an integer argument becomes the
   literal expression that holds it. */
static Var _macro_expr_value(Var value) =>
  value.is_integer() ? x2c_literal_int(value.integer()) : value;

static List _macro_expr_values(List values) {
  Array lifted = [];
  foreach (Var item, values) lifted.push(_macro_expr_value(item));
  return lifted.list_free();
}

// pattern views

/* Turns an instantiated body into a pattern: derived expression types
   become wildcards, literals and operators are quoted, a binder in a hole
   shell stands alone, and a free reference matches a binding of its
   spelling. */
static Var _macro_pattern_view(Var value) {
  if (value is not <list>)
    return value == <*> || value == <?> ? %(!quote $value).var() : value;
  List node = value;
  match (node) {
    case %(expr ?type ?body): return _macro_expr_view(type, body);
    case %(literal *): return %(!quote $node);
    case %(binding-name ?(String name)): return _macro_free_reference(name);
    case %(op ?operator *operands):
      return %(op (!quote $operator) @{_macro_pattern_views(operands)});
    case %(seq ?one): return _macro_pattern_view(one);
    case %(macro-slot ?(int splice) ?form):
      return _macro_slot_view(splice, form);
    case %(return ? ?body): return %(return ? ${_macro_pattern_view(body)});
  }
  return _macro_pattern_views(node);
}

/* A template's shell passes through a binder or the expression it holds;
   any other expression matches whatever type binding derived. */
static Var _macro_expr_view(Var type, Var body) {
  int shell = type === %(<macro-expr>);
  if (shell && body.is_binder()) return body;
  if (shell && body is <list> && body.list().car() == <expr>)
    return _macro_pattern_view(body);
  return %(expr ? ${_macro_pattern_view(body)});
}

static List _macro_pattern_views(List items) {
  Array parts = [];
  foreach (Var part, items) parts.push(_macro_pattern_view(part));
  return parts.list_free();
}

/* A slot builds code the pattern cannot see; a spliced slot captures it
   under the sequence hole it was given. */
static Var _macro_slot_view(int splice, Var form) {
  if (!splice) return <?>;
  Var binder = _macro_slot_binder(form);
  return binder ? binder : <*>;
}

/* The first named `*` binder in a slot's arguments, depth first, or NULL. */
static Var _macro_slot_binder(Var form) {
  if (form.is_binder())
    return form.str().len() > 1 && form.str()[0] == '*' ? form : NULL;
  if (form is not <list>) return NULL;
  foreach (Var child, form.list()) {
    Var binder = _macro_slot_binder(child);
    if (binder) return binder;
  }
  return NULL;
}

/* macro-valued cases

   A `case` that names a macro recognizes code the macro built. A retained
   invocation of the same definition matches by its arguments; other code
   matches the pattern derived from the body, which the case's site keeps
   unless it depends on the current call. */

/** Records fixed-local slots for distinct-identity checks and Name slots
    for member-spelling comparisons during recognition. */
typedef struct MacroFixedSlots {
  int count, slots[MACHINE_BINDER_MAX];
  int names, name_slots[MACHINE_BINDER_MAX];
} MacroFixedSlots;

/** Records where each of a `case`'s binders reads its capture: the slot
    of its internal binder in the pattern that captured, and its own slot
    in the `case`, which need not share the parameters' order.
*/
typedef struct MacroPublishing {
  int from[MACHINE_BINDER_MAX], fallback[MACHINE_BINDER_MAX];
  int to[MACHINE_BINDER_MAX];
  int count, binders, complete;
  unsigned long definite;
} MacroPublishing;

/** Holds one macro-valued `case` site's prepared recognition for the
    process: the plan Match keeps, the slots of the macro's fixed locals, and
    where each binder reads its capture. The compiler emits one
    zero-initialized static site per `case`.
*/
typedef struct MacroCaseSite {
  MatchCaptureSite match;
  MacroFixedSlots policy;
  MacroPublishing route;
  int ready;
} MacroCaseSite;

/** The pattern a macro-valued `case` compiles to; the compiler lowers a
   call of this to `Macro_case_capture_at` over the match subject. */
List Macro_case_pattern(Macro t, List names) => Macro_pattern(t, names);

/** Recognizes code built by `t` for the `case` whose site is `site`, which
    may be NULL, and publishes the captures under `names`. A pattern that
    does not depend on the current call's subject is prepared once and kept
    in the site; generated `match` code calls this for a macro-valued case.
*/
int Macro_case_capture_at(
  MacroCaseSite *site, List code, Macro t, List names,
  MatchCaptureBuffer *published) {
  List grouped = NULL;
  if (_macro_pending_parts(t, code, grouped))
    return _macro_pending_capture(t, grouped, names, published);
  if (site && __atomic_load_n(&site.ready, __ATOMIC_ACQUIRE))
    return _macro_site_capture(site, code, published);
  return _macro_derived_capture(site, code, t, names, published);
}

/* A retained invocation of this same definition matches by its arguments,
   without expanding it. */
static int _macro_pending_parts(Macro t, List code, List &grouped) {
  match (code) {
    case %("x2c.template" ?descriptor ?arguments): {
      if (!_macro_same(t, descriptor)) return 0;
      grouped = arguments;
      return 1;
    }
    case %(macro-invoke ?descriptor (args *rows) ?): {
      if (!_macro_same(t, descriptor)) return 0;
      grouped = _macro_invoke_values(t, rows);
      return 1;
    }
  }
  return 0;
}

static int _macro_same(Macro t, Var descriptor) =>
  descriptor is <list> && List.compare(descriptor, t) == 0;

/* The arguments a `macro-invoke` recorded, one per parameter: the bound
   expression of an expression parameter, the value of any other, and the
   captured items of a sequence. */
static List _macro_invoke_values(Macro t, List rows) {
  Array projected = [];
  List holes = t.assoc(<parameters>);
  foreach (List row, rows) {
    List hole = holes.car();
    holes = holes.cdr();
    Var value = hole.assoc(<kind>) == <expr>
      ? row.assoc(<expression>) : row.assoc(<value>);
    if (hole.assoc(<sequence>).int())
      match (row) case %(capture ? (value *items) *): value = items;
    projected.push(value);
  }
  return projected.list_free();
}

/* Matches a retained invocation's arguments, one per parameter, against
   the parameters' binders. */
static int _macro_pending_capture(
  Macro t, List grouped, List names, MatchCaptureBuffer *published) {
  Var values[MACHINE_BINDER_MAX];
  MatchCaptureBuffer captured = {values, 0, MACHINE_BINDER_MAX};
  List internal = _macro_internal_names(t, names, 1);
  if (!x2c_match_try_capture(grouped, internal, &captured)) return 0;
  MacroPublishing route = _macro_publishing(t, internal, names, internal);
  return _macro_publish(&route, &captured, published);
}

/* The binder each parameter is captured under inside the derived pattern:
   a Type parameter is a List splice, so it needs a List binder. Against a
   retained invocation each binder captures one argument. */
static List _macro_internal_names(Macro t, List names, int pending) {
  Array internal = [];
  foreach (List hole, t.assoc(<parameters>).list()) {
    String label = names.car().str(), prefix = label[0:1];
    names = names.cdr();
    if (pending) prefix = "?";
    else if (hole.assoc(<kind>) == <type>) prefix = "*";
    internal.push(Atom.intern(prefix + label[1:]));
  }
  return internal.list_free();
}

/* Recognizes `code` with the pattern `site` keeps. */
static int _macro_site_capture(
  MacroCaseSite *site, List code, MatchCaptureBuffer *published) {
  Var values[MACHINE_BINDER_MAX];
  MatchCaptureBuffer captured = {values, 0, MACHINE_BINDER_MAX};
  return _macro_case_match(code, site.match.plan, &site.policy, &captured) &&
    _macro_publish(&site.route, &captured, published);
}

/* Derives the pattern for this call. `site` keeps a pattern that does not
   depend on the call's subject; any other is prepared for this call
   alone. */
static int _macro_derived_capture(
  MacroCaseSite *site, List code, Macro t, List names,
  MatchCaptureBuffer *published) {
  macro_subject_used = 0;
  List pattern = _macro_case_shape(t, names);
  MacroPublishing route = _macro_publishing(
    t, pattern, names, _macro_internal_names(t, names, 0));
  if (_macro_keep(site, t, names, pattern, route))
    return _macro_site_capture(site, code, published);
  Var values[MACHINE_BINDER_MAX];
  MatchCaptureBuffer captured = {values, 0, MACHINE_BINDER_MAX};
  MatchPlan plan = MatchPlan.prepare(pattern);
  defer plan.free();
  MacroFixedSlots policy = _macro_fixed_slots(t, names, plan);
  return _macro_case_match(code, plan, &policy, &captured) &&
    _macro_publish(&route, &captured, published);
}

/* Keeps `pattern` in `site` with its fixed slots and route once Match
   retains its prepared plan, unless the pattern resolved a reference
   against the current call's subject. Returns whether `site` is ready. */
static int _macro_keep(
  MacroCaseSite *site, Macro t, List names, List pattern,
  MacroPublishing &route) {
  MatchPlan kept = site && !macro_subject_used && List.try_own(pattern)
                 ? x2c_match_site_prepare(&site.match, pattern) : NULL;
  if (!kept || kept.status != MACHINE_PREPARED) return 0;
  site.policy = _macro_fixed_slots(t, names, kept);
  site.route = route;
  __atomic_store_n(&site.ready, 1, __ATOMIC_RELEASE);
  return 1;
}

/* recognition with binding hygiene

   Declarations the body introduces match any identity in the subject, one
   distinct identity per declaration; other references match the subject's
   binding of the same spelling. Source wrappers are removed from both
   sides for comparison, while captured values keep the subject's original
   subtrees. */

/* The pattern a case runs: each fixed local bound to one distinct
   identity, a statement sequence that also matches as a block, and no
   source wrappers. */
static List _macro_case_shape(Macro t, List names) {
  List pattern = _macro_pattern(t, names, 1), replacements = NULL;
  int ordinal = 0;
  foreach (List fresh, t.assoc(<fresh>).list()) {
    Atom identity = _macro_fixed(ordinal++);
    replacements = cons(
      %(${fresh.car()} (binding (!and $identity $identity) ?)),
      replacements);
  }
  pattern = pattern.replace(replacements);
  match (pattern)
    case %(seq *parts): pattern = %(!or (seq @parts) (block @parts));
  return _macro_view(pattern);
}

/* The binder of the fixed local the body declares `index`th. */
static Atom _macro_fixed(int index) => Atom.intern(%"?__fixed_$index");

/* Removes source wrappers and template shells throughout a pattern, down
   to literals and bindings, which stay whole. */
static Var _macro_view(Var value) {
  value = _macro_unwrap(value);
  if (value is not <list>) return value;
  List node = value;
  match (node) {
    case %(literal *): return value;
    case %(binding ? ?): return value;
  }
  Array parts = [];
  foreach (Var child, node) parts.push(_macro_view(child));
  return parts.list_free();
}

/* The slots of a prepared plan that hold the macro's fixed locals. */
static MacroFixedSlots _macro_fixed_slots(
  Macro t, List names, MatchPlan plan) {
  MacroFixedSlots policy;
  policy.count = policy.names = 0;
  if (plan.status != MACHINE_PREPARED) return policy;
  int ordinal = 0;
  foreach (List fresh, t.assoc(<fresh>).list()) {
    int slot = plan.layout.index(_macro_fixed(ordinal++));
    if (slot >= 0) policy.slots[policy.count++] = slot;
  }
  foreach (List hole, t.assoc(<parameters>).list()) {
    if (hole.assoc(<kind>) == <name>) {
      int slot = plan.layout.index(names.car());
      if (slot >= 0) policy.name_slots[policy.names++] = slot;
    }
    names = names.cdr();
  }
  return policy;
}

/* Runs `plan` over `code` with the fixed-local relation and the unwrapping
   view, and copies its captures. A plan that is not prepared takes Match's
   ordinary route, which reports why. */
static int _macro_case_match(
  List code, MatchPlan plan, MacroFixedSlots *policy,
  MatchCaptureBuffer *captured) {
  if (plan.status != MACHINE_PREPARED)
    return plan.execute_capture(code, *captured, NULL) == 1;
  struct MatchMachine storage;
  MatchMachine machine = &storage;
  machine.open();
  machine.relation = _macro_identity_equal;
  machine.relation_context = policy;
  machine.view = _macro_unwrap;
  machine.begin(plan.program.view(), code);
  machine.run();
  int matched = machine.status == <ok> && _macro_take_slots(machine, captured);
  machine.finish();
  machine.dispose();
  return matched;
}

/* Copies each slot the machine filled, materializing spans, and returns
   whether the machine is still ok. */
static int _macro_take_slots(
  MatchMachine machine, MatchCaptureBuffer *captured) {
  for (int i = 0; i < machine.slot_count; i++) {
    MachineSlot *slot = &machine.slots[i];
    if (slot.kind == MACHINE_SLOT_INVALID) continue;
    captured.values[i] = slot.kind == MACHINE_SLOT_SPAN
      ? machine.materialize_span(slot.span) : slot.value;
    captured.present |= 1UL << i;
  }
  return machine.status == <ok>;
}

/* A repeated binder compares the nodes both sides unwrap to. At a fixed
   local's slot, a node another fixed local already holds is unequal, so
   distinct declarations capture distinct identities. */
static int _macro_identity_equal(
  void *raw_machine, int slot, Var left, Var right, void *raw_policy) {
  MatchMachine machine = raw_machine;
  MacroFixedSlots *policy = raw_policy;
  left = _macro_unwrap(left);
  right = _macro_unwrap(right);
  if (_macro_is_name(policy, slot)) {
    String spelling = NULL;
    if (left is <string> && right is <list>)
      spelling = _macro_source_spelling(right);
    else if (right is <string> && left is <list>)
      spelling = _macro_source_spelling(left);
    if (spelling) return spelling == (left is <string> ? left : right);
  }
  if (left != right) return 0;
  if (!_macro_is_fixed(policy, slot)) return 1;
  return !_macro_held_elsewhere(machine, policy, slot, right);
}

static int _macro_is_name(MacroFixedSlots *policy, int slot) {
  for (int i = 0; i < policy.names; i++)
    if (policy.name_slots[i] == slot) return 1;
  return 0;
}

/* The caller's source spelling survives helper transport in the existing
   subject rows; ordinary bindings use the spelling they already carry. */
static String _macro_source_spelling(Var value) {
  if (value is not <list>) return NULL;
  foreach (List row, macro_subject is <list> ? macro_subject.list() : NULL)
    match (row)
      case %(source-spelling ?binding ?(String spelling)):
        if (List.compare(binding, value) == 0) return spelling;
  match (value) case %(binding ? ?(String spelling)): return spelling;
  return NULL;
}

static int _macro_is_fixed(MacroFixedSlots *policy, int slot) {
  for (int i = 0; i < policy.count; i++) if (policy.slots[i] == slot) return 1;
  return 0;
}

/* Whether a fixed local's slot other than `slot` holds `value`. */
static int _macro_held_elsewhere(
  MatchMachine machine, MacroFixedSlots *policy, int slot, Var value) {
  for (int i = 0; i < policy.count; i++) {
    int other = policy.slots[i];
    if (other != slot && machine.slots[other].kind == MACHINE_SLOT_VALUE &&
        machine.slots[other].value == value)
      return 1;
  }
  return 0;
}

/* The node a pattern examines for `value`: through position and source
   wrappers, and through the shell binding leaves around a typed
   expression. */
static Var _macro_unwrap(Var value) {
  for (;;) {
    if (value is not <list>) return value;
    List node = value;
    match (node) {
      case %(at ? ?body): value = body;
      case %(src ? ?body): value = body;
      case %(expr (<macro-expr>) (!set ?inner (expr *))): value = inner;
      default: return value;
    }
  }
}

/* publishing captures

   A pattern captures each parameter under an internal binder. Publishing
   copies those captures into the slots of the `case`'s own binders. */

/* Where each of the user's binders reads its capture: the slot of its
   internal binder in `pattern` and its own slot among `names`. A binder
   either side lacks leaves the route incomplete. */
static MacroPublishing _macro_publishing(
  Macro t, Var pattern, List names, List internal) {
  MacroPublishing route;
  memset(&route, 0, sizeof(route));
  MatchCaptureLayout actual = MatchCaptureLayout.analyze(pattern);
  MatchCaptureLayout logical = MatchCaptureLayout.analyze(names);
  route.complete = 1;
  List holes = t.assoc(<parameters>);
  for (; names; names = names.cdr(), internal = internal.cdr(),
                  holes = holes.cdr()) {
    int fallback = actual.index(internal.car());
    int from = holes.car().list().assoc(<kind>) == <name>
             ? actual.index(_macro_name_identity(holes.car())) : -1;
    if (from < 0) from = fallback;
    int to = logical.index(names.car());
    if (from < 0 || to < 0) route.complete = 0;
    route.from[route.count] = from;
    route.fallback[route.count] = fallback;
    route.to[route.count++] = to;
  }
  route.binders = logical.binder_count;
  route.definite = logical.definite;
  actual.free();
  logical.free();
  return route;
}

/* Publishes the internal captures under the user's binders. An incomplete
   route or an absent capture publishes nothing and returns 0. */
static int _macro_publish(
  MacroPublishing *route, MatchCaptureBuffer *captured,
  MatchCaptureBuffer *published) {
  if (!route.complete) return 0;
  Var ordered[MACHINE_BINDER_MAX];
  for (int i = 0; i < route.count; i++) {
    int from = captured.has(route.from[i])
             ? route.from[i] : route.fallback[i];
    if (from < 0 || !captured.has(from)) return 0;
    ordered[route.to[i]] = captured.values[from];
  }
  for (int i = 0; i < route.binders; i++) published.values[i] = ordered[i];
  published.present = route.definite;
  return 1;
}
