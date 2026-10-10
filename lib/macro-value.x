/*  macro-value.x -- macros as values that build and recognize code

    Copyright (c) 2025 Gary William Flake

    A `Macro` is the canonical `macrodef` record of a definition. `$name`
    selects one and `macro Kind(...) => ...` creates one. Applying it returns
    a pending invocation the compiler expands and binds at the insertion
    site; naming it in a `case` derives a Match pattern from the same body.
    Generated code calls these operations by name, so the module is part of
    the prelude.
*/

#pragma once

#include "common.x"
#include "match.x"

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

#include "array.x"
#include "atom.x"
#include "list.x"
#include "match-machine.x"
#include "match-cache.x"
#include "meta.x"
#include "string.x"
#include "varconvert.x"
#include <math.h>

// application

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
    /* One List of syntax or of numbers and Strings passes the whole
       sequence, as `call(f, items)`; the compiler lifts each scalar. */
    if (sequence && values && !values.cdr() && values.car() is <list> &&
        _macro_items(values.car()))
      values = values.car();
    grouped.push(sequence ? values.var() : values.car());
    values = sequence ? NULL : values.cdr();
  }
  return grouped.list_free();
}

/* Whether `items` is a List of arguments rather than one: empty, or led by
   syntax, a number, or a String other than an identifier's or pending
   code's tag. A Symbol leads one syntax node. */
static int _macro_items(List items) {
  if (!items) return 1;
  match (items)
    case %((!or "x2c.ident" "x2c.quoted" "x2c.template") *): return 0;
  Var first = items.car();
  return first is <list> || first is <string> || first.is_integer() ||
         first.is_floating();
}

// typed quotations

/** Returns what a typed quotation inserts for one use of a hole whose
    local holds `value`, as a rebuild inserts it. An expression hole
    (`lifts`) takes a number, String, or Symbol as its literal. Where the
    code takes an expression (`expression`), a binding, an `x2c_ident`
    spelling, or a Name hole's String becomes an identifier expression;
    in a Name hole's member position, an `x2c_ident` spelling is its
    String. */
Var Macro.inserted(Var value, int lifts, int expression) {
  if (lifts) value = _macro_expr_value(value);
  Var spelling = value;
  match (value) case %("x2c.ident" ?(String name)): spelling = name;
  if (!expression) return lifts ? value : spelling;
  if (spelling is <string>) return %(expr () (ident $spelling));
  match (value) case %(binding ? ?): return %(expr () (ident $value));
  return value;
}

/** Returns the name a typed quotation declares with a Name hole whose local
    holds `value`: the name form of an `x2c_ident` spelling or a String,
    or a binding as it is. */
Var Macro.declared(Var value) {
  Var spelling = Macro.inserted(value, 0, 0);
  return spelling is <string> ? %($spelling).var() : value;
}

/** Returns the items a typed quotation splices for an expression sequence
    hole whose local holds `values`: each number, String, or Symbol becomes
    its literal, as a spliced data List's items do. */
List Macro.inserted_items(List values) => _macro_expr_values(values);

/** Returns what a typed quotation builds when its code is one hole whose
    local holds `value`: the inserted expression with the type `type`. A
    String typed `String` is a String literal. */
List Macro.typed(List type, Var value) {
  if (value is <list> && value.list().car().is_match_op())
    return %(expr $type $value);
  if (value is <string> && List.compare(type, %("String")) == 0)
    value = x2c_literal_string(value);
  List expression = Macro.inserted(value, 1, 1);
  return %(expr $type @{expression.cddr()});
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

/* The pattern for a `using` reference to `spelling`: any binding of it, or
   only the subject's file-scope binding while a call sets a subject. A free
   reference matches any binding of its spelling, since it binds where its
   expansion lands. */
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
    // An explicit expression pattern owns its type constraint.
    if (!sequence && selected is <list> && selected.list().car() == <expr>)
      projected = %(!and $selected);
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

/** Returns the binder that captures one projection of the template hole
    whose binder is `binder`. Splice and construction projections are
    always sequences; return, declarator, and member projections never
    are; source, value, and expression follow the hole's `sequence`. */
Atom Macro.binder(Var binder, String projection, int sequence) {
  if (projection == "splice" || projection == "construction") sequence = 1;
  else if (projection == "return" || projection == "declarator" ||
           projection == "member") sequence = 0;
  String prefix = sequence ? "*" : "?", name = binder.str();
  return Atom.intern(%"${prefix}__macro_${projection}_${name[1:]}");
}

static Atom _macro_key(List hole, String projection) =>
  Macro.binder(hole.assoc(<binder>), projection, hole.assoc(<sequence>));

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

/* An expression parameter takes code, so a number, String, or Symbol
   argument becomes the literal expression that holds it, as the compiler
   lifts a compile-time value. */
static Var _macro_expr_value(Var value) {
  if (value is <string>)
    return %(expr (* char) (literal (* char) ${value.repr()}));
  if (value is <symbol>) return x2c_literal_symbol(value);
  Type type = Macro.number_type(value);
  return type ? Macro.number_literal(type, type, value) : value;
}

static List _macro_expr_values(List values) {
  Array lifted = [];
  foreach (Var item, values) lifted.push(_macro_expr_value(item));
  return lifted.list_free();
}

// number literals

/** Returns the C type of a number's Var family, or NULL when `value` is not
    a number. An untyped integer is an `int` when it fits one. */
List Macro.number_type(Var value) {
  switch (value.tag()) {
    case <i8>: return %(signed char);
    case <u8>: return %(unsigned char);
    case <i16>: return %(short);
    case <u16>: return %(unsigned short);
    case <i32>: return %(int);
    case <u32>: return %(unsigned);
    case <long>: return %(long);
    case <ulong>: return %(unsigned long);
    case <llong>: return %(long long);
    case <ullong>: return %(unsigned long long);
    case <f32>: return %(float);
    case <ldouble>: return %(long double);
  }
  if (value.is_floating()) return %(double);
  if (value.is_integer()) {
    long n = value.integer();
    return n == (int) n ? %(int) : %(long long);
  }
  return NULL;
}

/** Returns the literal expression of type `result` that holds `value`, a
    number of the scalar type `type`. An `int` value is its decimal
    literal; another number is its exact bits cast to `type`. */
List Macro.number_literal(List result, List type, Var value) {
  if (value.tag() == <i32>) return _int_literal(result, value);
  List literal = _bits_literal(value);
  return %(expr $result (parens (expr $result (cast $type $literal))));
}

/* C reads a negative literal as a negation, so it takes parentheses, and
   INT_MIN's magnitude does not fit an int, so its literal is cast back. */
static List _int_literal(Type result, Var value) {
  long n = value.integer();
  List literal = %(expr $result (literal (int) ${value.str()}));
  if (n == INT_MIN)
    return %(expr $result (parens (expr $result (cast (int) $literal))));
  return n < 0 ? %(expr $result (parens $literal)) : literal;
}

/* The exact bits of a number that is not an int, as a long double or an
   unsigned long long literal that the caller casts to the number's type. */
static List _bits_literal(Var value) {
  X2CVarNumeric number;
  value.numeric_decode(number);
  Type literal_type = number.floating ? %(long double) : %(unsigned long long);
  String text = number.floating ? _float_text(number.floating_value)
                                : "%lluULL".printf(number.raw);
  return %(expr $literal_type (literal $literal_type $text));
}

/* NaN and the infinities have no literal, so they spell builtin calls. */
static String _float_text(long double n) {
  if (isnan(n)) return "__builtin_nanl(\"\")";
  if (isinf(n)) return n < 0 ? "(-__builtin_infl())" : "__builtin_infl()";
  return _hex_float(n);
}

/* Spells finite `n` exactly as a normalized hex literal. Printf's %La
   layout depends on the host's long double. */
static String _hex_float(long double n) {
  const char *sign = signbit(n) ? "-" : "";
  if (n == 0) return "%s0x0p+0L".printf(sign);
  int exponent;
  long double fraction = frexpl(fabsl(n), &exponent) * 2 - 1;
  char digits[32];
  int count = 0;
  for (; fraction != 0; count++) {
    fraction *= 16;
    int digit = (int) fraction;
    fraction -= digit;
    digits[count] = "0123456789abcdef"[digit];
  }
  digits[count] = 0;
  return "%s0x1%s%sp%+dL".printf(sign, count ? "." : "", digits, exponent - 1);
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
  /* Explicit Match operands already describe recognition, not source code. */
  if (node.car().is_match_op()) return node;
  match (node) {
    case %(expr ?type ?body): return _macro_expr_view(type, body);
    case %(literal *): return %(!quote $node);
    case %(binding-name ?(String name)): return %(binding ? $name);
    case %(binding-global ?(String name)): return _macro_free_reference(name);
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
  if (shell && body is <list> && body.list().car().is_match_op())
    return body;
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
    return _macro_capture(
      code, site.match.plan, &site.policy, &site.route, published);
  return _macro_derived_capture(site, code, t, names, published);
}

/** Retains a macro and hole patterns for repeated recognition. A pattern
    independent of subject bindings is derived once; contextual references
    are resolved against each subject. The caller keeps the source values
    alive as long as this record. Match plans use the active Match cache. */
typedef struct MacroMatcher {
  Macro shape;
  List holes, pattern;
} MacroMatcher;

/** Prepares repeated recognition without retaining subject-specific
    bindings. */
MacroMatcher Macro.matcher(Macro shape, List holes) {
  Var previous = Macro.subject();
  Macro.use_subject(%());
  defer Macro.use_subject(previous);
  macro_subject_used = 0;
  List pattern = _macro_case_shape(shape, holes);
  return (MacroMatcher){shape, holes, macro_subject_used ? NULL : pattern};
}

/** Tests code with the same source views and identity rules as a macro
    case. */
int MacroMatcher.matches(MacroMatcher &m, List code) {
  List pattern =
    m.pattern ? m.pattern : _macro_case_shape(m.shape, m.holes);
  MatchLease lease;
  int status = MatchCache.current().acquire(pattern, lease, "Macro.matches");
  defer lease.release();
  if (status != MACHINE_PREPARED) return 0;
  MatchPlan plan = lease.plan();
  MacroFixedSlots policy = _macro_fixed_slots(m.shape, m.holes, plan);
  return _macro_case_match(code, plan, &policy, NULL);
}

/** Tests complete code against a macro and its hole patterns. Repeated
    recognition can retain `Macro.matcher` so the pattern is derived once. */
int Macro.matches(Macro t, List code, List holes) {
  MacroMatcher matcher = {t, holes, NULL};
  return matcher.matches(code);
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
    case %(!or (macro-invoke ?descriptor (args *rows) ?)
               (expr ? (macro-invoke ?descriptor (args *rows) ?))): {
      if (!_macro_same(t, descriptor)) return 0;
      grouped = _macro_invoke_values(t, rows);
      return 1;
    }
  }
  return 0;
}

/* A retained invocation may name its macro, carry its stored definition,
   or carry this value; a definition is identified by its name and the
   place it was written. */
static int _macro_same(Macro t, Var descriptor) {
  if (descriptor.is_atom()) return descriptor.str() == t.assoc(<name>).str();
  if (descriptor is not <list>) return 0;
  List stored = descriptor;
  return List.compare(stored, t) == 0 ||
    (stored.car() == <macrodef> &&
     stored.assoc(<name>).str() == t.assoc(<name>).str() &&
     List.compare(stored.assoc(<origin>), t.assoc(<origin>)) == 0);
}

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

/* Recognizes `code` with `plan` and publishes its captures by `route`. */
static int _macro_capture(
  List code, MatchPlan plan, MacroFixedSlots *policy, MacroPublishing *route,
  MatchCaptureBuffer *published) {
  Var values[MACHINE_BINDER_MAX];
  MatchCaptureBuffer captured = {values, 0, MACHINE_BINDER_MAX};
  return _macro_case_match(code, plan, policy, &captured) &&
    _macro_publish(route, &captured, published);
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
    return _macro_capture(
      code, site.match.plan, &site.policy, &site.route, published);
  MatchPlan plan = MatchPlan.prepare(pattern);
  defer plan.free();
  MacroFixedSlots policy = _macro_fixed_slots(t, names, plan);
  return _macro_capture(code, plan, &policy, &route, published);
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
  /* A Unit body that is one function definition recognizes that bound
     function, which carries no `api-source` record. */
  match (pattern) {
    case %(seq *parts): pattern = %(!or (seq @parts) (block @parts));
    case %(api-source ? ? ?function): pattern = function;
  }
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
   view, and copies captures when requested. An unprepared plan takes Match's
   ordinary route, which reports why. */
static int _macro_case_match(
  List code, MatchPlan plan, MacroFixedSlots *policy,
  MatchCaptureBuffer *captured) {
  if (plan.status != MACHINE_PREPARED)
    return plan.execute_capture(code, *captured, NULL) == 1;
  if (!plan.admits(code, _macro_unwrap)) return 0;
  MatchMachine machine;
  machine.open();
  machine.relation = _macro_identity_equal;
  machine.relation_context = policy;
  machine.view = _macro_unwrap;
  machine.begin(plan.program.view(), code);
  machine.run();
  int matched = machine.status == <ok> &&
    (!captured || _macro_take_slots(machine, captured));
  machine.finish();
  machine.dispose();
  return matched;
}

/* Copies each slot the machine filled, materializing spans, and returns
   whether the machine is still ok. */
static int _macro_take_slots(
  MatchMachine &machine, MatchCaptureBuffer *captured) {
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
  MatchMachine *machine = raw_machine;
  MacroFixedSlots *policy = raw_policy;
  left = _macro_unwrap(left);
  right = _macro_unwrap(right);
  if (_macro_has_slot(policy.name_slots, policy.names, slot)) {
    String spelling = NULL;
    if (left is <string> && right is <list>)
      spelling = _macro_source_spelling(right);
    else if (right is <string> && left is <list>)
      spelling = _macro_source_spelling(left);
    if (spelling) return spelling == (left is <string> ? left : right);
  }
  if (left != right) return 0;
  if (!_macro_has_slot(policy.slots, policy.count, slot)) return 1;
  return !_macro_held_elsewhere(*machine, policy, slot, right);
}

static int _macro_has_slot(const int *slots, int count, int slot) {
  for (int i = 0; i < count; i++) if (slots[i] == slot) return 1;
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

/* Whether a fixed local's slot other than `slot` holds `value`. */
static int _macro_held_elsewhere(
  MatchMachine &machine, MacroFixedSlots *policy, int slot, Var value) {
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
  MacroPublishing route = {.complete = 1};
  MatchCaptureLayout actual = MatchCaptureLayout.analyze(pattern);
  MatchCaptureLayout logical = MatchCaptureLayout.analyze(names);
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
