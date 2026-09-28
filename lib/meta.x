/*  meta.x -- the compiler surface a `meta` function calls

    Copyright (c) 2025 Gary William Flake

    A `meta` function runs inside the compiler, so it can ask the compiler
    questions and build syntax for it to bind. Those operations were
    reachable only from compile-time Lisp, under names like `x2c.ident` and
    `x2c.type.fields`, which made Lisp the authoring language for any macro
    whose implementation needed them. The declarations below name the same
    operations from x2c, so a macro's implementation is x2c. The compiler
    derives each Lisp name from the x2c one: `_` becomes `.`, a predicate
    `x2c_type_is_X` is `x2c.type.X?`, and `x2c_type_tag_name` and
    `x2c_type_reverse_name` keep the hyphen of `x2c.type.tag-name` and
    `x2c.type.reverse-name`.

    Syntax builders have `meta` bodies shared by compile time and runtime.
    A `meta` prototype with no body names a compiler operation, which the
    compiler supplies from these declarations. A `meta` function that reaches
    one, directly or through another `meta` function, is therefore
    compile-time only, the compiler derives that and emits no runtime form
    for it, and a run-time call to it is diagnosed where it is written.

    This module is not part of the implicit prelude. Include it where the
    `meta` functions are parsed: a `.xmacro` borrows the consuming unit's
    symbol table, so the unit that imports it includes this file.

    The declarations below are the signatures. Each operation's semantics are
    those of the compile-time Lisp operation of the same name, specified under
    "Compile-time Lisp and imports" in the language reference, which also gives
    the naming rule and the answers whose shape differs.
    See `plans/archive/meta-functions.md`.
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

/** A `meta` parameter declared `Type` receives, at a `$` call, the
   description of its argument's type: `((name N) (kind K) (type T)
   (fields F) (methods M))`. Read a part with `List.assoc`. */
typedef List Type;

/** A `meta` parameter declared `Source` receives, at a `$` call, captured
   syntax with the source text it came from: `((text T) (file F) (syntax
   S))`. `x2c_source_text` and `x2c_embed_text` read it directly. */
typedef List Source;


/* --- declaration parts --------------------------------------------------
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
  foreach (Var item, reversed.reverse()) {
    match (item)
      case %(func ?(List parameters)): {
        Array params = [];
        foreach (List parameter, parameters) {
          List (b, m) = type_declaration_parts(parameter);
          params.push(%(param $b (bind () $m)));
        }
        item = %(fnmod (params @{params.list_free()}));
      }
    syntax.push(item);
  }
  return %(${qualifiers.append(base)} (@{syntax.list_free()}));
}

/* --- identifiers and literals -------------------------------------------
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

/* --- macro values -------------------------------------------------------
   A `Macro` is the canonical `macrodef` record of a definition. `$name`
   selects one and `macro Kind(...) => ...` creates one. Applying it
   returns a pending invocation the compiler expands and binds at the
   insertion site; naming it in a `case` derives a Match pattern from the
   same body. Projection keys spell the compiler's replacement binders. */

/** A macro as a value: called to build code, or used in a Match `case` to
   recognize code and capture its parameters. */
typedef List Macro;

static Atom _macro_key(List hole, String projection) {
  String name = hole.assoc(<binder>).str()[1:];
  int sequence = hole.assoc(<sequence>);
  if (projection == "splice") sequence = 1;
  else if (projection == "member") sequence = 0;
  return Atom.intern(%"${sequence ? "*" : "?"}__macro_${projection}_$name");
}

/** Records the Macro values an anonymous macro captured where it was
   created, so applying it later applies the same children. */
Macro Macro_close(Macro value, List captures) =>
  value.append(%((env $captures)));

static Var _macro_expr_value(Var value) =>
  value.is_integer() ? x2c_literal_int(value.integer()) : value;

/* Groups positional arguments by the definition's parameters: a sequence
   parameter takes every remaining argument as one List. */
static List _macro_group(Macro t, List values) {
  Array grouped = [];
  foreach (List hole, t.assoc(<parameters>).list()) {
    int sequence = hole.assoc(<sequence>);
    grouped.push(sequence ? values.var() : values.car());
    values = sequence ? NULL : values.cdr();
  }
  return grouped.list_free();
}

/** Applies a macro value to code values. The result is a pending
   invocation; inserting it into a program expands and binds it there. */
List Macro_apply(Macro t, List values) =>
  %("x2c.template" $t ${_macro_group(t, values)});

static Var _macro_inline(List environment, Var tree);

/* Substitutes grouped values into the body directly. Pattern derivation
   uses this for a captured child macro; construction goes through the
   compiler's invocation rows instead. */
static List _macro_instantiate(Macro t, List values) {
  List rows = NULL;
  foreach (List hole, t.assoc(<parameters>).list()) {
    int sequence = hole.assoc(<sequence>);
    Var value = sequence ? values.var() : values.car();
    if (hole.assoc(<kind>) == <expr>) {
      if (sequence) {
        Array lifted = [];
        foreach (Var item, values) lifted.push(_macro_expr_value(item));
        value = lifted.list_free();
      }
      else value = _macro_expr_value(value);
    }
    Var expression = value;
    if (!sequence && hole.assoc(<kind>) == <name>)
      expression = %(expr () (ident $value));
    rows = cons(%(${_macro_key(hole, "expression")} $expression), rows);
    rows = cons(%(${_macro_key(hole, "value")} $value), rows);
    rows = cons(%(${_macro_key(hole, "source")} $value), rows);
    if (hole.assoc(<kind>) == <name>)
      rows = cons(%(${_macro_key(hole, "member")} $value), rows);
    rows = cons(%(${_macro_key(hole, "splice")} $value), rows);
    values = sequence ? NULL : values.cdr();
  }
  List body = t.assoc(<template>);
  return _macro_inline(t.assoc(<env>), body.replace(rows));
}

static Var _macro_inline(List environment, Var tree) {
  if (tree is not <list>) return tree;
  match (tree) {
    case %(expr (<macro-expr>) (expr ?type ?body)):
      return _macro_inline(environment, %(expr $type $body));
    case %(tpl-call (expr ? (ident ?binding)) (args *arguments)): {
      Macro child = NULL;
      foreach (List row, environment)
        if (List.compare(row.car(), binding) == 0) {
          child = row.cadr();
          break;
        }
      return _macro_instantiate(child, arguments);
    }
    case %(literal *): return tree;
  }
  Array parts = [];
  foreach (Var part, tree.list()) parts.push(_macro_inline(environment, part));
  return parts.list_free();
}

/* Turns an instantiated body into a pattern: derived expression types
   become wildcards, literals and operators are quoted, and a binder in a
   hole shell stands alone. */
static Var _macro_pattern_view(Var value) {
  if (value is not <list>)
    return value == <*> || value == <?> ? %(!quote $value).var() : value;
  List node = value;
  match (node) {
    case %(expr ?type ?body): {
      if (type === %(<macro-expr>) && body.is_binder()) return body;
      if (type === %(<macro-expr>) && body is <list> &&
          body.list().car() == <expr>)
        return _macro_pattern_view(body);
      return %(expr ? ${_macro_pattern_view(body)});
    }
    case %(literal *): return %(!quote $node);
    case %(op ?operator *operands): {
      Array parts = [];
      foreach (Var operand, operands)
        parts.push(_macro_pattern_view(operand));
      return %(op (!quote $operator) @{parts.list_free()});
    }
    case %(seq ?one): return _macro_pattern_view(one);
    case %(return ?type ?body):
      return %(return ? ${_macro_pattern_view(body)});
  }
  Array parts = [];
  foreach (Var part, node) parts.push(_macro_pattern_view(part));
  return parts.list_free();
}

/** Derives the Match pattern that recognizes code this macro builds,
   capturing each parameter under the given binder. */
List Macro_pattern(Macro t, List names) {
  List rows = NULL, labels = names;
  foreach (List hole, t.assoc(<parameters>).list()) {
    Var selected = labels.car();
    labels = labels.cdr();
    if (hole.assoc(<kind>) == <type>)
      selected = Atom.intern("*" + selected.str()[1:]);
    int sequence = hole.assoc(<sequence>);
    Var projected = sequence ? %($selected).var() : selected;
    rows = cons(%(${_macro_key(hole, "expression")} $projected), rows);
    rows = cons(%(${_macro_key(hole, "value")} $projected), rows);
    rows = cons(%(${_macro_key(hole, "source")} $projected), rows);
    rows = cons(%(${_macro_key(hole, "member")} $selected), rows);
    rows = cons(%(${_macro_key(hole, "splice")} ($selected)), rows);
  }
  List body = t.assoc(<template>);
  List pattern = _macro_pattern_view(
    _macro_inline(t.assoc(<env>), body.replace(rows)));
  if (t.assoc(<kind>) == <block-item> && body.car() == <seq> &&
      body.cdr().len() == 1)
    return %(!or $pattern (seq $pattern));
  return pattern;
}

/* --- recognition with binding hygiene ------------------------------------
   Declarations the body introduces match any identity in the subject, one
   distinct identity per declaration; other references keep their exact
   identities. Source wrappers are removed from both sides for comparison,
   while captured values keep the subject's original subtrees. */

static Atom _macro_fixed(int index) => Atom.intern(%"?__fixed_$index");

static Var _macro_view(Var value) {
  if (value is not <list>) return value;
  List node = value;
  match (node) {
    case %(at ? ?body): return _macro_view(body);
    case %(src ? ?body): return _macro_view(body);
    case %(literal *): return value;
    case %(binding ? ?): return value;
  }
  Array parts = [];
  foreach (Var child, node) parts.push(_macro_view(child));
  return parts.list_free();
}

static List _macro_case_shape(Macro t, List names) {
  List pattern = Macro_pattern(t, names), replacements = NULL;
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

typedef struct MacroFixedSlots {
  int count, slots[MACHINE_BINDER_MAX];
} MacroFixedSlots;

static int _macro_identity_equal(
  void *raw_machine, int slot, Var left, Var right, void *raw_policy) {
  if (left != right) return 0;
  MatchMachine machine = raw_machine;
  MacroFixedSlots *policy = raw_policy;
  int local = 0;
  for (int i = 0; i < policy.count; i++)
    if (policy.slots[i] == slot) local = 1;
  if (!local) return 1;
  for (int i = 0; i < policy.count; i++) {
    int other = policy.slots[i];
    if (other != slot && machine.slots[other].kind == MACHINE_SLOT_VALUE &&
        machine.slots[other].value == right)
      return 0;
  }
  return 1;
}

static int _macro_case_match(
  List code, Macro t, List pattern, MatchCaptureBuffer *captured) {
  MatchPlan plan = MatchPlan.prepare(pattern);
  if (plan.status != MACHINE_PREPARED) {
    int result = plan.execute_capture(code, *captured, NULL);
    plan.free();
    return result == 1;
  }
  MacroFixedSlots policy;
  policy.count = 0;
  int ordinal = 0;
  foreach (List fresh, t.assoc(<fresh>).list()) {
    int slot = plan.layout.index(_macro_fixed(ordinal++));
    if (slot >= 0) policy.slots[policy.count++] = slot;
  }
  struct MatchMachine storage;
  MatchMachine machine = &storage;
  machine.open();
  machine.relation = _macro_identity_equal;
  machine.relation_context = &policy;
  machine.begin(plan.program.view(), _macro_view(code));
  machine.run();
  int matched = machine.status == <ok>;
  if (matched) {
    for (int i = 0; i < machine.slot_count; i++) {
      MachineSlot *slot = &machine.slots[i];
      if (slot.kind == MACHINE_SLOT_INVALID) continue;
      captured->values[i] = slot.kind == MACHINE_SLOT_SPAN
        ? machine.materialize_span(slot.span) : slot.value;
      captured->present |= 1UL << i;
    }
    matched = machine.status == <ok>;
  }
  machine.finish();
  machine.dispose();
  plan.free();
  return matched;
}

/* Publishes internal captures under the user's binders, in the order the
   `case` wrote them. */
static int _macro_publish(
  Macro t, List names, List internal_names, Var *values,
  MatchCaptureBuffer *captured, MatchCaptureBuffer *published) {
  MatchCaptureLayout actual = MatchCaptureLayout.analyze(
    %(!and @internal_names));
  MatchCaptureLayout logical = MatchCaptureLayout.analyze(%(!and @names));
  Var ordered[MACHINE_BINDER_MAX];
  int matched = 1;
  List labels = names, internal = internal_names;
  for (; labels; labels = labels.cdr(), internal = internal.cdr()) {
    int from = actual.index(internal.car()), to = logical.index(labels.car());
    if (from < 0 || to < 0 || !captured.has(from)) {
      matched = 0;
      break;
    }
    ordered[to] = values[from];
  }
  if (matched) {
    for (int i = 0; i < logical.binder_count; i++)
      published->values[i] = ordered[i];
    published->present = logical.definite;
  }
  actual.free();
  logical.free();
  return matched;
}

/* The binder each parameter is captured under inside the derived pattern:
   a Type parameter is a List splice, so it needs a List binder. */
static List _macro_internal_names(Macro t, List names, int pending) {
  Array internal = [];
  List labels = names;
  foreach (List hole, t.assoc(<parameters>).list()) {
    String label = labels.car().str(), prefix = label[0:1];
    labels = labels.cdr();
    if (pending) prefix = "?";
    else if (hole.assoc(<kind>) == <type>) prefix = "*";
    internal.push(Atom.intern(prefix + label[1:]));
  }
  return internal.list_free();
}

/* A retained invocation of this same definition matches by its arguments,
   without expanding it. */
static int _macro_pending_parts(
  Macro t, List code, List &grouped) {
  match (code) {
    case %("x2c.template" ?descriptor ?arguments): {
      if (descriptor is not <list> || List.compare(descriptor, t) != 0)
        return 0;
      grouped = arguments;
      return 1;
    }
    case %(macro-invoke ?descriptor (args *rows) ?): {
      if (descriptor is not <list> || List.compare(descriptor, t) != 0)
        return 0;
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
      grouped = projected.list_free();
      return 1;
    }
  }
  return 0;
}

/** Recognizes code built by `t`, whether retained as a pending
   invocation or already expanded, and publishes the captures under
   `names`. Generated `match` code calls this for a macro-valued case. */
int Macro_case_capture(
  List code, Macro t, List names, MatchCaptureBuffer *published) {
  Var values[MACHINE_BINDER_MAX];
  MatchCaptureBuffer captured = {values, 0, MACHINE_BINDER_MAX};
  List grouped = NULL;
  if (_macro_pending_parts(t, code, grouped)) {
    List internal = _macro_internal_names(t, names, 1);
    int matched = x2c_match_try_capture(grouped, internal, &captured);
    return matched &&
      _macro_publish(t, names, internal, values, &captured, published);
  }
  List pattern = _macro_case_shape(t, names);
  if (!_macro_case_match(code, t, pattern, &captured)) return 0;
  return _macro_publish(
    t, names, _macro_internal_names(t, names, 0), values, &captured,
    published);
}

/** The pattern a macro-valued `case` compiles to; the compiler lowers a
   call of this to `Macro_case_capture` over the match subject. */
List Macro_case_pattern(Macro t, List names) => Macro_pattern(t, names);

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

/* --- statement and declaration construction ----------------------------- */

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

/* --- reading what the macro captured ------------------------------------
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

/* --- reading a captured function ----------------------------------------
   A decorator receives a whole function, and these four take it apart: its
   name, one parameter by spelling, its body, and the argument list that
   forwards its parameters. A decorator that wraps or forwards a function
   needs all four; `packages/autodiff/src/autodiff.xmacro` uses this
   compiler surface. */

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

/* --- reading a type -----------------------------------------------------
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

/* --- the invocation site ------------------------------------------------
   Where the macro was written and what is beside it. A macro that reports
   its own diagnostic, or that reads a data file next to the source, needs
   the site rather than the compiler's current position. */

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

/* --- failing ------------------------------------------------------------
   A macro that checks its argument needs to say what is wrong at the site
   the developer wrote, which no return value can do. */

/** Reports `message` with `notes` at the macro invocation and fails the
    expansion. This does not return. */
meta void x2c_diagnostic_fail(String message, List notes);

/** Reports `message` with `notes` as a warning where it is raised, and
    returns so the expansion continues. */
meta void x2c_diagnostic_warn(String message, List notes);

/* --- lowering -----------------------------------------------------------
   The generators under `etc/` record the Lisp a function lowers to. */


/** Returns a `Map` from the name of each function the unit has defined so
    far to the hash of its definition text, from the first token after any
    `meta` marker to the end of its body. The compiler links copies of
    shipped `meta` code and binds a definition to its copy only when these
    hashes agree. */
meta Map x2c_meta_definition_hashes(void);
