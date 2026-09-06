/*  lisp.x -- the Lisp runtime: reader, session, and evaluator

    Copyright (c) 2026 Gary William Flake.

    Each `Lisp` session owns a `Scope` holding its global environment.
    Evaluation uses eager left-to-right
    arguments for lambdas and natives, raw arguments for macros and
    special forms, macro expansion evaluated once in the caller's
    environment, globals able to shadow reserved forms, `nil` as the only
    false value, and by-value capture of free locals using the V1
    body-flattening rule.

    Identifiers use canonical `Atom`s: compact x2c `Symbol`s when their
    spelling
    round-trips exactly, with direct canonical-`String` `<lsym>` `Var`s as the
    arbitrary-length, case-sensitive fallback. The reader converts shared
    Tokenizer output into `Var` and `List` forms.

    The session `Scope` owns the Lisp record, `Map`s, Lambdas, bound `Func`
    storage,
    prepared programs, and reusable machine slots. The internal
    `lisp-machine.x` decoder executes eligible prepared programs. `Map`s,
    Lambda
    bodies, and captures retain `Var`s by value without cloning their
    referents.
    Canonical graphs and identity-bearing values therefore keep their pool or
    caller ownership and must outlive every session entry that refers to
    them. A session is not synchronized; its caller serializes evaluation
    and mutation and destroys it only after every call has returned.
*/

#pragma once

$(import "private-keywords.xmacro")
#include "x2c.x"
#include "machine.x"

/** Represents one isolated embedded `Lisp` session.
    Create it with `Lisp.new` or `Lisp.new_bare` and end it with
    `Lisp.destroy`. The module header describes its owned and borrowed state.
    A session is mutable and requires caller serialization.
*/
typedef struct Lisp *Lisp;

macro Expression $lisp._standard.source() => (
  $(x2c.literal.string (x2c._embed.text "../etc/init.xlisp"))
)

/** Reports cumulative automatic-evaluator activity for one `Lisp` session.
    Counter values are snapshots since session creation. `program_bytes`
    counts published programs still owned by the session; detailed machine
    counters are collected separately through `Lisp.auto_instrument`.
*/
typedef struct LispAutoStats {
  long invocations, machine_entries, machine_errors;
  long analyses, published, ineligible;
  long guard_failures, remembered_fallbacks;
  long program_bytes;   // live published AUTO program bytes
} LispAutoStats;

/** Returns the prepared AUTO program for an eligible Lisp Lambda.
    On success, writes all three nonnull outputs and returns 1. Otherwise it
    returns 0 and leaves them unchanged. The view and body are borrowed from
    the Lambda and remain valid only while its owning `Lisp` session lives.
*/
int Lisp.program(Var callable, MachineView *view, int *nparam, Var *body) {
  if (callable is not <lambda>) return 0;
  Lambda lambda = callable;
  if (lambda.macro || lambda.auto_status != MACHINE_PREPARED ||
      !lambda.auto_program)
    return 0;
  *view = lambda.auto_program.view();
  *nparam = lambda.params.len();
  *body = lambda.body;
  return 1;
}

/** Resolves one Lisp name for the active shared-machine environment.
    `storage` must be the context of a running LispMachine and `value` must be
    nonnull. Returns 1 and writes the borrowed binding, or returns 0 and leaves
    the output unchanged.
*/
int Lisp.resolve(void *storage, Var name, Var *value) {
  LispMachineContext context = (LispMachineContext) storage;
  return _lookup(context.lisp, _machine_env(context), name, value);
}

/** Pushes one prepared-Lambda environment for the shared machine.
    `storage` names a running LispMachine context, `callable` is a prepared
    Lambda, and `values` supplies the Lambda's `count` borrowed arguments. The
    array and its values must remain live until the matching `Lisp.leave`.
*/
void Lisp.enter(void *storage, Var callable, const Var *values, int count) {
  LispMachineContext context = (LispMachineContext) storage;
  Lambda lambda = callable;
  LispEnv *parent = _machine_env(context);
  // The machine's own frame guard bounds this: Lisp.enter runs only after
  // LispMachine._push_frame accepted a frame.
  assert(context.depth + 1 < MACHINE_FRAME_MAX);
  context.depth++;
  _machine_env_set(
    context.frames + context.depth, lambda, values, count, parent);
}

/** Pops the innermost environment installed by `Lisp.enter`.
    Calls must balance in last-in, first-out order; the borrowed argument array
    is no longer retained afterward.
*/
void Lisp.leave(void *storage) {
  LispMachineContext context = (LispMachineContext) storage;
  assert(context.depth > 0);
  bzero(context.frames + context.depth, sizeof(LispEnv));
  context.depth--;
}

/** Replaces the current shared-machine environment for a self tail call.
    The parent environment is preserved. `callable` must be its prepared
    Lambda, `count` must match its parameters, and the borrowed `values` remain
    live until another retarget or the environment is left.
*/
void Lisp.retarget(void *storage, Var callable, const Var *values, int count) {
  LispMachineContext context = (LispMachineContext) storage;
  LispEnv *frame = _machine_env(context);
  Lambda lambda = callable;
  _machine_env_set(frame, lambda, values, count, frame.parent);
}

/** Applies a Lisp callable to already evaluated shared-machine values.
    `storage` names the running context; `values` may be null only when `count`
    is zero, `count` must not be negative, and the array is borrowed for the
    call. The active `Lisp` session owns new `Scope` allocations; other
    returned
    `Var`s keep their ordinary owners.
    Raises any cause from argument materialization or the callable.
*/
Var Lisp.apply_values(
  void *storage, Var callable, const Var *values, int count) {
  LispMachineContext context = (LispMachineContext) storage;
  List args = NULL;
  for (int i = count - 1; i >= 0; i--) args = cons(values[i], args);
  return _apply_values(context.lisp, callable, args, _machine_env(context));
}

/** Handles a callable that cannot continue through prepared machine dispatch.
    Returns 0 and leaves `value` unchanged when the machine may proceed.
    Otherwise it applies the callable to borrowed raw forms, writes `value`,
    and returns 1. `storage` and `value` must be nonnull and belong to the
    running LispMachine invocation.
*/
int Lisp.precall(void *storage, Var callable, List raw, Var *value) {
  LispMachineContext context = (LispMachineContext) storage;
  Lisp lisp = context.lisp;
  LispEnv *env = _machine_env(context);
  if (callable is <func> && _special_id(lisp, (Func) callable.pointer()) < 0)
    return 0;
  if (callable is <lambda>) {
    Lambda lambda = callable;
    if (!lambda.macro && lambda.auto_status == MACHINE_PREPARED &&
        lambda.auto_program && _auto_specials_ok(lisp, env, lambda))
      return 0;
  }
  *value = _apply(lisp, callable, raw, env);
  return 1;
}

#pragma private

static String lisp_standard_source = $lisp._standard.source();

enum LispSpecial {
  LISP_BIND, LISP_EVAL, LISP_QUOTE, LISP_COND, LISP_DEF,
  LISP_LAMBDA, LISP_MACRO, LISP_QUASIQUOTE, LISP_IMPORT,
  LISP_APPLY, LISP_SPECIAL_COUNT
};

typedef struct LispEnv {
  Map bindings, List params;
  const Var *values;
  int value_count, Map captures, struct LispEnv *parent;
} LispEnv;

/* Environment records are activation-local. An ordinary activation's
   `bindings` is a temporary frame-owned Map, while the captured pseudo-frame
   aliases its Lambda's session-owned capture Map. Parameter names, captured
   Vars, argument arrays, and parent records are borrowed for the activation.
   Machine frames keep argument arrays live until leave or retarget. Evaluator
   calls copy arguments into the temporary bindings Map and keep their
   environment records on the C stack until `_call_lambda` returns. */

typedef struct LispMachineContext {
  Lisp lisp;
  LispEnv frames[MACHINE_FRAME_MAX];
  int depth;
} *LispMachineContext;

/* One machine invocation needs a LispMachine plus its context. On the C
   stack that reserves the space in every evaluator frame even when a call
   never reaches the machine, and recursion runs out of stack. Slots are
   allocated on the session scope instead and return to a free list, so a
   nested invocation reuses one and steady state allocates nothing. */
typedef struct LispMachineSlot {
  struct LispMachine machine, struct LispMachineContext context;
  struct LispMachineSlot *next;
} *LispMachineSlot;

struct Lisp {
  Scope scope;          // semantic session scope
  Map globals;          // global bindings, Lisp name -> value
  Map reserved;         // reserved special forms, Lisp name -> <func> Var
  Func specials[LISP_SPECIAL_COUNT];
  LispAutoStats auto_stats;
  MachineStats *auto_machine_stats;
  LispMachineSlot machine_free;   // reusable machine slots, innermost first
  int machine_depth;    // machine invocations in progress on this session
  int auto_disabled;    // benchmark/test forced-evaluator arm only
  int protect_x2c;      // compiler SDK installed; x2c.* cannot be redefined
};

/* The Lambda record, capture Map storage, and AUTO program belong to the
   session Scope. Parameter and body Lists and captured Var referents are
   borrowed: capture copies Var identity, not the referenced object or
   canonical graph. Their owners must outlive the Lambda. Callable replacement
   starts a fresh AUTO threshold because state is stored on the new Lambda, and
   a recycled allocation address cannot observe an earlier Lambda's state. */
typedef struct Lambda {
  List params;
  Var body;
  Map captures, int macro, auto_calls, auto_status;
  MachineProgram auto_program;
  List auto_specials;   // reserved special-form identity guards
} *Lambda;

static inline Var Lambda.var(Lambda);
static inline Lambda Var.lambda(Var);

$(import "var-adapters.xmacro") $var.pointer(Lambda, lambda, <lambda>);

protocol Var(Lambda);

// canonical Lisp names

static Var lsym_quote, lsym_quasiquote, lsym_unquote, lsym_splicing;
static Var lsym_cond, lsym_def, lsym_bind, lsym_eval, lsym_lambda;
static Var lsym_macro, lsym_import, lsym_apply;
static pthread_once_t lisp_initialize_once =
  (pthread_once_t) PTHREAD_ONCE_INIT;
static int lisp_initialize_success;

typedef struct LispCanonicalName {
  int special, const char *spelling;
  Var *value;
} LispCanonicalName;

static const LispCanonicalName lisp_canonical_names[] = {
  { LISP_QUOTE,      "quote",            &lsym_quote },
  { LISP_QUASIQUOTE, "quasiquote",       &lsym_quasiquote },
  { -1,              "unquote",          &lsym_unquote },
  { -1,              "unquote-splicing", &lsym_splicing },
  { LISP_COND,       "cond",             &lsym_cond },
  { LISP_DEF,        "def",              &lsym_def },
  { LISP_BIND,       "bind",             &lsym_bind },
  { LISP_EVAL,       "eval",             &lsym_eval },
  { LISP_LAMBDA,     "lambda",           &lsym_lambda },
  { LISP_MACRO,      "macro",            &lsym_macro },
  { LISP_IMPORT,     "import",           &lsym_import },
  { LISP_APPLY,      "apply",            &lsym_apply }
};

static unsigned _canonical_count(void) =>
  sizeof(lisp_canonical_names) / sizeof(lisp_canonical_names[0]);

static const LispCanonicalName *_special_name(int special) {
  for (unsigned i = 0; i < _canonical_count(); i++)
    if (lisp_canonical_names[i].special == special)
      return &lisp_canonical_names[i];
  return NULL;
}

static void _initialize_once(void) {
  Var values[sizeof(lisp_canonical_names) / sizeof(lisp_canonical_names[0])];
  for (unsigned i = 0; i < _canonical_count(); i++)
    values[i] = Atom.intern(lisp_canonical_names[i].spelling);
  for (unsigned i = 0; i < _canonical_count(); i++)
    if (values[i] is <lsym> && !values[i].str().try_own()) return;
  for (unsigned i = 0; i < _canonical_count(); i++)
    *lisp_canonical_names[i].value = values[i];
  lisp_initialize_success = 1;
}

static int Lisp._initialize(Lisp lisp) {
  (void) lisp;
  if (pthread_once(&lisp_initialize_once, _initialize_once)) {
    fprintf(stderr, "Lisp: could not initialize canonical names\n");
    abort();
  }
  return lisp_initialize_success;
}

// reader

static Symbol _malformed(String source, unsigned at) {
  int line = 1, column = 1;
  scan_next_line_col(source, (int) at, &line, &column);
  raise %(malformed (source $source) (line $line) (column $column));
}

static Symbol _read_token_list(
  Tokenizer tokenizer, char *source, unsigned base, unsigned *end, Var *out) {
  Array elements = %[], Symbol status = <value>;
  loop {
    Token token = tokenizer.next();
    if (!token || token.type == <eof>) {
      status = <incomplete>;
      break;
    }
    if (token.type == <")">) {
      *end = token.pos + token.len;
      break;
    }
    Var element = void;
    status = _read_token_form(tokenizer, token, source, base, end, &element);
    if (status != <value>) break;
    elements.push(element);
  }
  if (status == <value>) *out = elements.list();
  elements.free();
  return status;
}

static Symbol _read_token_atom(
  Token token, char *source, unsigned base, Var *out) {
  String text = token.text;
  switch (token.type) {
    case <lit-char*>:
      *out = String.new_len(text + 1, token.len - 2).unescape();
      return <value>;
    case <lit-int>: {
      long value;
      String literal = String.new_len(text, token.len);
      if (!literal.try_long(&value))
        return _malformed(source, base + token.pos);
      if (value == (int) value) *out = (int) value;
      else *out = value;
      return <value>;
    }
    case <lit-float>: {
      double value, String literal = String.new_len(text, token.len);
      if (!literal.try_double(&value))
        return _malformed(source, base + token.pos);
      *out = value;
      return <value>;
    }
    case <lit-symbol>: {
      int n = token.len;
      String inner = text[1] == '"'
        ? String.new_len(text + 2, n - 4).unescape()
        : String.new_len(text + 1, n - 2);
      if (!inner) return _malformed(source, base + token.pos);
      *out = Symbol.new(inner);
      return <value>;
    }
    case <ident>:
      *out = Atom.intern(text.unescape());
      return <value>;
  }
  return _malformed(source, base + token.pos);
}

static Symbol _read_token_form(
  Tokenizer tokenizer, Token token, char *source, unsigned base, unsigned *end,
  Var *out) {
  if (!token || token.type == <eof>) return <incomplete>;
  Var prefix = void;
  switch (token.type) {
    case <error>:
      if (tokenizer.status() == <incomplete>) return <incomplete>;
      return _malformed(source, base + token.pos);
    case <")">: return _malformed(source, base + token.pos);
    case <"(">: return _read_token_list(tokenizer, source, base, end, out);
    case <"'">:  prefix = lsym_quote;      break;
    case <"`">:  prefix = lsym_quasiquote; break;
    case <",">:  prefix = lsym_unquote;    break;
    case <",@">: prefix = lsym_splicing;   break;
  }
  if (prefix is not void) {
    Var inner = void;
    Symbol status = _read_token_form(
      tokenizer, tokenizer.next(), source, base, end, &inner);
    if (status == <value>) *out = %($prefix $inner);
    return status;
  }
  *end = token.pos + token.len;
  return _read_token_atom(token, source, base, out);
}

static Symbol _read_tokenizer(
  Tokenizer tokenizer, String source, unsigned base, unsigned *cursor,
  Var *out) {
  Token token = tokenizer.next();
  if (!token || token.type == <eof>) {
    *cursor = source.len();
    return <eof>;
  }
  unsigned start = base + token.pos;
  *cursor = start;
  unsigned end = 0;
  Var value = void;
  Symbol status = _read_token_form(
    tokenizer, token, source, base, &end, &value);
  if (status == <value>) {
    if (out) *out = value;
    *cursor = base + end;
  }
  else if (status == <incomplete>) {
    int line = 1, column = 1;
    scan_next_line_col(source, (int) start, &line, &column);
    raise %(incomplete (source $source) (line $line) (column $column));
  }
  return status;
}

static Tokenizer _scan_lisp_tokens(String source, Scope *scope) {
  Scope.push(scope);
  Tokenizer tokenizer = NULL;
  {
    defer Scope.pop();
    tokenizer = Tokenizer.new_mode(source, <lisp>);
    tokenizer.scan();
  }
  return tokenizer;
}

static Var _bad_session(String operation) {
  raise %(bad-arg (operation $operation));
}

macro Decorator $lisp.entry(Function $function, Expr $operation) => {
  if (!$(x2c.function.parameter $function "lisp"))
    return _bad_session($operation);

  Scope.push(&$(x2c.function.parameter $function "lisp")->scope);
  defer Scope.pop();
  $(x2c.function.body $function)...
}

/** Creates an isolated embedded `Lisp` session with only evaluator primitives.
    The caller owns a successful session and must pass it to `Lisp.destroy`.
    Returns NULL if a long shared name cannot be owned by the active pool
    chain. Failure of native once initialization writes a diagnostic and
    aborts the process.
    Raises: `<alloc-fail>` or `<size-limit>` while creating session storage, or
    `<bad-enc>` while interning shared or special-form names.
*/
Lisp Lisp.new_bare(void) {
  Scope session = Scope.new_named("Lisp session"), Lisp result = NULL;
  defer if (!result) Scope.destroy(session);
  Lisp lisp = NULL;
  { // Limit Scope.pop to allocation before an Error transfer.
    Scope.push(&session);
    defer Scope.pop();
    lisp = Scope.calloc(1, sizeof(struct Lisp));
  }
  if (!lisp._initialize()) return NULL;
  lisp.scope = session;
  memset(&lisp.auto_stats, 0, sizeof(LispAutoStats));
  lisp.auto_machine_stats = NULL;
  lisp.auto_disabled = 0;
  { // Limit Scope.pop to global setup before an Error transfer.
    Scope.push(&lisp.scope);
    defer Scope.pop();
    lisp.globals = %{};
    lisp.reserved = %{};
    _install_specials(lisp);
  }
  return result = lisp;
}

/** Creates an isolated session with the standard Lisp environment loaded.
    The caller owns the result and must pass it to `Lisp.destroy`.
    If standard-source evaluation transfers, no handle is returned and the
    constructed session remains allocated.
    Raises any cause from `Lisp.new_bare` or `Lisp.eval_string`.
*/
Lisp Lisp.new(void) {
  Lisp lisp = Lisp.new_bare();
  lisp.eval_string(lisp_standard_source);
  return lisp;
}

/** Releases a `Lisp` session and invalidates all session-owned state.
    This includes its global and reserved `Map`s, Lambdas, transferred `Func`s,
    prepared programs, and machine slots. Borrowed values are not released. A
    null session does nothing; no evaluation or machine call may remain active.
    Destroying its still-active `Scope` raises `<bad-state>`.
*/
void Lisp.destroy(Lisp lisp) { if (lisp) Scope.destroy(lisp.scope); }

/** Reads one Lisp form and returns `<value>` or `<eof>`.
    A nonnull `out` receives the form only for `<value>`; it is otherwise
    unchanged. New result storage uses the caller's active `Scope` and
    canonical
    pools, not the temporary token `Scope`, and remains valid until those
    owners
    are released. On success `cursor` advances past the form, at EOF it becomes
    the source length, and on a reader error it identifies the failing form's
    first token. A null source or cursor returns `<eof>` without raising. A
    nonnull cursor must initially hold a byte offset no greater than the source
    length. A successful session construction must first initialize the shared
    reader names; afterward `lisp` is not consulted and may be null.
    Raises: `<incomplete>` for a truncated form, `<malformed>` for invalid
    reader syntax, or `<alloc-fail>`, `<size-limit>`, or `<bad-enc>` while
    tokenizing, constructing, interning, or boxing the form.
*/
Symbol Lisp.read(Lisp lisp, String source, unsigned *cursor, Var *out) {
  (void) lisp;
  if (!source || !cursor) return <eof>;
  unsigned base = *cursor;
  Scope tokens_scope = Scope.new_named("Lisp tokens"), Symbol status;
  {
    defer Scope.destroy(tokens_scope);
    Tokenizer tokenizer = _scan_lisp_tokens(source + base, &tokens_scope);
    status = _read_tokenizer(tokenizer, source, base, cursor, out);
  }
  return status;
}

// evaluator

static Var _bool(int x) {
  if (x) return <true>;
  return %();
}

/** Returns Lisp true unless `value` is a nonempty `List`. */
Var lisp_atom(Var value) => _bool(value is not <list> || value.is_nil());

/** Returns Lisp true when `a` and `b` are equal by `Var.equal`. */
Var lisp_eq(Var a, Var b) => _bool(a == b);

/** Returns Lisp true when `value` is a nonempty `List`. */
Var lisp_pair(Var value) => _bool(value is <list> && !value.is_nil());

/** Returns Lisp true when `value` is `List`-typed, including `nil`. */
Var lisp_list(Var value) => _bool(value is <list>);

static int _is_lisp_number(Var value) {
  Symbol kind = value.kind();
  return kind == <integer> || kind == <floating>;
}

/** Returns Lisp true when `value` has an integer or floating kind. */
Var lisp_number(Var value) => _bool(_is_lisp_number(value));

/** Returns Lisp true when `value` is a `String`. */
Var lisp_string(Var value) => _bool(value is <string>);

/** Returns Lisp true when `value` has `Symbol` kind. */
Var lisp_symbol(Var value) => _bool(value.kind() == <symbol>);

/** Returns Lisp true when `value` is a native function or Lambda. */
Var lisp_procedure(Var value) => _bool(value is <func> || value is <lambda>);

/** Compares Lisp numbers and returns a boxed negative, zero, or positive.
    A nonnumeric operand raises `<bad-types>`.
*/
Var lisp_compare(Var a, Var b) {
  if (!_is_lisp_number(a) || !_is_lisp_number(b))
    raise %(bad-types (operation "lisp_compare")
                       (left-kind ${a.kind()})
                       (right-kind ${b.kind()}));
  return a.compare(b);
}
/** Returns the runtime tag of `value`. */
Symbol lisp_type(Var value) => value.tag();

/** Concatenates when either operand is `String`, otherwise adds dynamically.
*/
Var lisp_add(Var a, Var b) {
  if (a is <string> || b is <string>) return %"$a$b";
  return a.binary(<+>, b);
}

/* The numeric and comparison operators are natives rather than Lisp
   lambdas because they are variadic, and a variadic lambda cannot be
   prepared: every arithmetic call in a compiled body would leave the
   machine, taking the whole `foldl` chain with it. */

/** Adds or concatenates every value left to right; no values gives 0. */
Var lisp_plus(List values) {
  Var total = 0;
  if (values && values.car() is <string>) total = String.new("");
  foreach (Var value, values) total = lisp_add(total, value);
  return total;
}

/** Subtracts each later value from the first; one value negates it.
    An empty input raises `<bad-arity>`.
*/
Var lisp_minus(List values) {
  if (!values) raise %(bad-arity (operation "-") (expected 1) (actual 0));
  Var total = values.car();
  if (!values.cdr()) {
    Var zero = 0;
    return zero.binary(<->, total);
  }
  foreach (Var value, values.cdr()) total = total.binary(<->, value);
  return total;
}

/** Multiplies every value; no values gives 1. */
Var lisp_times(List values) {
  Var total = 1;
  foreach (Var value, values) total = total.binary(<*>, value);
  return total;
}

/** Divides the first value by each later one; one value reciprocates it.
    An empty input raises `<bad-arity>`.
*/
Var lisp_divide(List values) {
  if (!values) raise %(bad-arity (operation "/") (expected 1) (actual 0));
  Var total = values.car();
  if (!values.cdr()) {
    Var one = 1;
    return one.binary(</>, total);
  }
  foreach (Var value, values.cdr()) total = total.binary(</>, value);
  return total;
}

/* Every comparison holds pairwise along the whole chain. `want` is the
   order each neighbouring pair must have, or must avoid when `expect` is
   zero, so `<=` and `=` read as one rule. */
static Var _chain(List values, String operation, int want, int expect) {
  int actual = values.len();
  if (actual < 2)
    raise %(bad-arity (operation $operation) (expected 2) (actual $actual));
  for (List p = values; p.cdr(); p = p.cdr()) {
    Var (left, right) = p;
    int order = lisp_compare(left, right).integer();
    if (expect ? order != want : order == want) return _bool(0);
  }
  return _bool(1);
}

/** Reports whether every neighbouring pair of numbers compares equal.
    Fewer than two values raise `<bad-arity>`; a nonnumber raises
    `<bad-types>`.
*/
Var lisp_eq_chain(List values) => _chain(values, %"=", 0, 1);

/** Reports whether two or more numbers strictly increase.
    Fewer than two values raise `<bad-arity>`; a nonnumber raises
    `<bad-types>`.
*/
Var lisp_lt_chain(List values) => _chain(values, %"<", -1, 1);

/** Reports whether two or more numbers never decrease.
    Fewer than two values raise `<bad-arity>`; a nonnumber raises
    `<bad-types>`.
*/
Var lisp_le_chain(List values) => _chain(values, %"<=", 1, 0);

/** Reports whether two or more numbers strictly decrease.
    Fewer than two values raise `<bad-arity>`; a nonnumber raises
    `<bad-types>`.
*/
Var lisp_gt_chain(List values) => _chain(values, %">", 1, 1);

/** Reports whether two or more numbers never increase.
    Fewer than two values raise `<bad-arity>`; a nonnumber raises
    `<bad-types>`.
*/
Var lisp_ge_chain(List values) => _chain(values, %">=", -1, 0);

/** Boxes the display `String` of `value`. */
Var lisp_str(Var value) => value.str();

/** Boxes the readable representation of `value`. */
Var lisp_repr(Var value) => value.repr();

/** Returns the boxed concatenation of `left` and `right`. */
Var lisp_string_append(String left, String right) => left + right;

/** Returns the boxed unit-step slice `string[start:stop]`. */
Var lisp_substring(String string, int start, int stop) =>
  string.getslice(start, stop, 1);

/** Returns a boxed lower-case copy of `string`. */
Var lisp_string_downcase(String string) => string.lower();

/** Returns the instantiated `template` when `input` matches `pat`.
    `List.match_replace` returns a `List`, so a template that is a bare binder
    loses a scalar result. Lisp sees the replacement itself. A miss, malformed
    pattern, cache pressure, or machine error returns `input` unchanged.
*/
Var lisp_match_replace(List input, Var pat, Var template) {
  Var result;
  if (!input.try_match_replace(pat, template, &result)) return input.var();
  return result;
}

/** Reads `path` completely, closes it, and returns its boxed `String`
    contents.
    Raises the open, read, size, or allocation cause reported by `File`. An
    opened stream is still closed on transfer.
*/
Var lisp_read_file(String path) => path.open("r").string_close();

/** Replaces `path` with `text` and reports Lisp success.
    The file is opened with truncation and always closed. A write or close
    failure returns `nil` after any accepted bytes; this operation is not
    atomic.
    An open failure transfers its `File` cause. `Null` text writes an empty
    file.
*/
Var lisp_write_file(String path, String text) {
  File file = path.open("w");
  int wrote = !text || file.puts(text) >= 0, closed = file.close() == 0;
  return _bool(wrote && closed);
}

// The direct targets let the compiler generate their call adapters.
$(import "../etc/lisp-bindings.xlisp")
$(def lisp.native.target.rows '(
  (Var_car              ((func (("Var"))) "Var"))
  (Var_cdr              ((func (("Var"))) "List"))
  (Var_cons             ((func (("Var") ("List"))) "List"))
  (lisp_atom            ((func (("Var"))) "Var"))
  (lisp_pair            ((func (("Var"))) "Var"))
  (lisp_list            ((func (("Var"))) "Var"))
  (lisp_eq              ((func (("Var") ("Var"))) "Var"))
  (lisp_type            ((func (("Var"))) "Symbol"))
  (lisp_number          ((func (("Var"))) "Var"))
  (lisp_string          ((func (("Var"))) "Var"))
  (lisp_symbol          ((func (("Var"))) "Var"))
  (lisp_procedure       ((func (("Var"))) "Var"))
  (List_reverse         ((func (("List"))) "List"))
  (List_len             ((func (("List"))) int))
  (List_match           ((func (("List") ("Var"))) "List"))
  (lisp_match_replace   ((func (("List") ("Var") ("Var"))) "Var"))
  (List_search          ((func (("List") ("Var"))) "List"))
  (List_search_replace  ((func (("List") ("Var") ("Var"))) "List"))
  (lisp_add             ((func (("Var") ("Var"))) "Var"))
  (Var_binary           ((func (("Var") ("Symbol") ("Var"))) "Var"))
  (lisp_compare         ((func (("Var") ("Var"))) "Var"))
  (lisp_plus            ((func (("List"))) "Var") rest)
  (lisp_minus           ((func (("List"))) "Var") rest)
  (lisp_times           ((func (("List"))) "Var") rest)
  (lisp_divide          ((func (("List"))) "Var") rest)
  (lisp_eq_chain        ((func (("List"))) "Var") rest)
  (lisp_lt_chain        ((func (("List"))) "Var") rest)
  (lisp_le_chain        ((func (("List"))) "Var") rest)
  (lisp_gt_chain        ((func (("List"))) "Var") rest)
  (lisp_ge_chain        ((func (("List"))) "Var") rest)
  (lisp_str             ((func (("Var"))) "Var"))
  (lisp_repr            ((func (("Var"))) "Var"))
  (String_len           ((func (("String"))) int))
  (lisp_string_append   ((func (("String") ("String"))) "Var"))
  (lisp_substring       ((func (("String") (int) (int))) "Var"))
  (lisp_string_downcase ((func (("String"))) "Var"))
  (lisp_read_file       ((func (("String"))) "Var"))
  (lisp_write_file      ((func (("String") ("String"))) "Var"))
  (List_sort            ((func (("List"))) "List"))
))

macro Expression $lisp.native.target.map() => (
  $(lisp.native.targets lisp.native.target.rows)
)

static Map lisp_native_targets = $lisp.native.target.map();

static Func _native_target(String name) {
  Var target;
  if (!lisp_native_targets.try_get(name, &target)) return NULL;
  return (Func) target.pointer();
}

/* Name lookup walks activation frames inward to outward. Within one frame the
   last duplicate parameter wins, then local bindings precede captured values.
   Session globals precede reserved forms, so a global may shadow a special
   form without mutating the reserved Map. */
static int _lookup(Lisp lisp, LispEnv *env, Var name, Var *out) {
  for (LispEnv *cur = env; cur; cur = cur.parent) {
    Var found = void;
    int at = 0;
    for (List p = cur.params; p && at < cur.value_count; p = p.cdr(), at++)
      if (p.car() == name) found = cur.values[at];
    if (found is not void) {
      *out = found;
      return 1;
    }
    if (cur.bindings && cur.bindings.try_get(name, out)) return 1;
    if (cur.captures && cur.captures.try_get(name, out)) return 1;
  }
  return lisp.globals.try_get(name, out) || lisp.reserved.try_get(name, out);
}

static int _param_has(List params, Var name) {
  foreach (Var param, params) if (param == name) return 1;
  return 0;
}

static void _capture(Lisp lisp, LispEnv *env, List params, Var body,
                     Map captures) {
  if (body is not <list>) return;
  foreach (Var name, List.flatten(body)) {
    Var value;
    if (!name.is_atom() || lisp.reserved.contains(name) ||
        captures.contains(name) || _param_has(params, name))
      continue;
    for (LispEnv *cur = env; cur; cur = cur.parent)
      if (cur.bindings.try_get(name, &value)) {
        captures[name] = value;
        break;
      }
  }
}

static void _eval_args(Lisp lisp, List args, LispEnv *env, List *out) {
  Array values = %[];
  defer values.free();
  foreach (Var arg, args) values.push(_eval(lisp, arg, env));
  *out = values;
}

static Var _qq(Lisp lisp, Var expr, LispEnv *env, int list, int depth) {
  if (expr is <list> && !expr.is_nil()) {
    List form = expr;
    Var (head, argument) = form;
    if (head == lsym_quasiquote) {
      Var tail = _qq(lisp, form.cdr(), env, 0, depth + 1);
      Var value = head.cons(tail);
      return list ? %($value).var() : value;
    }
    if (head == lsym_unquote || head == lsym_splicing) {
      if (form.len() != 2)
        raise %(bad-arity (operation "quasiquote") (value $expr));
      if (depth > 0) {
        Var tail = _qq(lisp, form.cdr(), env, 0, depth - 1);
        Var value = head.cons(tail);
        return list ? %($value).var() : value;
      }
      Var value = _eval(lisp, argument, env);
      if (!list && head == lsym_splicing)
        raise %(bad-types (operation "quasiquote-splice")
                           (actual ${expr.kind()}));
      if (list && head == lsym_unquote) return %($value);
      if (list && value is not <list>)
        raise %(bad-types (operation "quasiquote-splice")
                           (actual ${value.kind()}));
      return value;
    }
    List first = _qq(lisp, head, env, 1, depth);
    List rest = _qq(lisp, form.cdr(), env, 0, depth);
    Var value = first.append(rest);
    return list ? %($value).var() : value;
  }
  return list ? %($expr).var() : expr;
}

static Var _make_lambda(Lisp lisp, List args, LispEnv *env, int macro) {
  if (args.len() != 2 || args.car() is not <list>) {
    Symbol operation = macro ? <macro> : <lambda>;
    raise %(bad-sig (operation $operation) (value $args));
  }
  Lambda lambda = Scope.malloc(sizeof(struct Lambda));
  Var result = void;
  lambda.captures = NULL;
  defer if (result is void) Scope.free(lambda);
  (List params, Var body) = args;
  lambda.params = params;
  lambda.body = body;
  lambda.captures = %{};
  lambda.macro = macro;
  lambda.auto_calls = 0;
  lambda.auto_status = -1;
  lambda.auto_program = NULL;
  lambda.auto_specials = NULL;
  _capture(lisp, env, lambda.params, lambda.body, lambda.captures);
  return result = lambda;
}

static void _bind_params(Lambda lambda, List args, Map bindings) {
  for (List p = lambda.params; p; p = p.cdr()) {
    Var (name, rest_name) = p;
    if (name.is_atom() && name.str() == %".") {
      if (!p.cdr())
        raise %(bad-sig (operation "apply") (value ${lambda.body}));
      Var rest = args;
      bindings[rest_name] = rest;
      return;
    }
    if (!args) raise %(bad-arity (operation "apply") (value ${lambda.body}));
    bindings[name] = args.car();
    args = args.cdr();
  }
  if (args) raise %(bad-arity (operation "apply") (value ${lambda.body}));
}

static Var _call_lambda(Lisp lisp, Lambda lambda, List args, LispEnv *env) {
  Scope frame = Scope.new_named("Lisp frame"), Map bindings = NULL;
  defer Scope.destroy(frame);
  {
    Scope.push(&frame);
    defer Scope.pop();
    bindings = %{};
  }
  LispEnv captured = {
    .bindings = lambda.captures,
    .parent = env
  };
  LispEnv local = {
    .bindings = bindings,
    .parent = &captured
  };
  _bind_params(lambda, args, bindings);
  return _eval(lisp, lambda.body, &local);
}

static Var _apply_lambda(Lisp lisp, Lambda lambda, List raw, LispEnv *env) {
  List args = raw;
  if (!lambda.macro) _eval_args(lisp, raw, env, &args);
  Var result = _call_lambda(lisp, lambda, args, env);
  return lambda.macro ? _eval(lisp, result, env) : result;
}

static int _special_id(Lisp lisp, Func function) {
  for (int i = 0; i < LISP_SPECIAL_COUNT; i++)
    if (lisp.specials[i] == function) return i;
  return -1;
}

static Var _apply_special(Lisp lisp, int id, List args, LispEnv *env) {
  switch (id) {
    case LISP_QUOTE: {
      if (args.len() != 1) {
        int actual = args.len();
        raise %(bad-arity (operation "quote") (expected 1) (actual $actual));
      }
      return args.car();
    }
    case LISP_DEF: {
      Var (name, expression) = args;
      if (args.len() != 2 || !name.is_atom()) {
        int actual = args.len();
        raise %(bad-arity (operation "def") (expected 2) (actual $actual)
                           (value $args));
      }
      if (lisp.protect_x2c && name.str().startswith("x2c."))
        raise %(bad-state (operation "def") (name $name));
      Var value = _eval(lisp, expression, env);
      lisp.globals[name] = value;
      return value;
    }
    case LISP_COND: {
      if (!args) raise %(bad-arity (operation "cond") (expected 1) (actual 0));
      foreach (Var clause, args) {
        if (clause is not <list>)
          raise %(bad-types (operation "cond") (value $clause) (want "List"));
        List pair = clause;
        if (pair.len() != 2) {
          int actual = pair.len();
          raise %(bad-arity (operation "cond-clause") (expected 2)
                             (actual $actual) (value $clause));
        }
        Var (condition_form, result_form) = pair;
        Var condition = _eval(lisp, condition_form, env);
        if (!condition.is_nil()) return _eval(lisp, result_form, env);
      }
      return %();
    }
    case LISP_LAMBDA:
    case LISP_MACRO:
      return _make_lambda(lisp, args, env, id == LISP_MACRO);
    case LISP_QUASIQUOTE: {
      if (args.len() != 1) {
        int actual = args.len();
        raise %(bad-arity (operation "quasiquote") (expected 1)
                           (actual $actual));
      }
      return _qq(lisp, args.car(), env, 0, 0);
    }
    case LISP_EVAL: {
      if (args.len() != 1) {
        int actual = args.len();
        raise %(bad-arity (operation "eval") (expected 1) (actual $actual));
      }
      Var expression = _eval(lisp, args.car(), env);
      return _eval(lisp, expression, NULL);
    }
    case LISP_BIND: {
      if (args.len() != 2) {
        int actual = args.len();
        raise %(bad-arity (operation "bind") (expected 2) (actual $actual));
      }
      Var (name_form, signature_form) = args;
      Var name = _eval(lisp, name_form, env);
      Var signature = _eval(lisp, signature_form, env);
      if (name is not <string>)
        raise %(bad-types (operation "bind") (actual ${name.kind()})
                           (want "String"));
      if (signature is not <list>)
        raise %(bad-sig (operation "bind") (value $signature));
      String native_name = name, List native_signature = signature;
      Func function = _native_target(native_name);
      if (!function)
        raise %(no-symbol (name $native_name) (sig $native_signature));
      return function;
    }
    case LISP_APPLY: {
      if (args.len() != 2) {
        int actual = args.len();
        raise %(bad-arity (operation "apply") (expected 2) (actual $actual));
      }
      Var (callable_form, values_form) = args;
      Var callable = _eval(lisp, callable_form, env);
      Var values = _eval(lisp, values_form, env);
      if (values is not <list>)
        raise %(bad-types (operation "apply") (actual ${values.kind()})
                           (want "List"));
      return _apply_values(lisp, callable, values, env);
    }
  }
  // LISP_IMPORT
  if (args.len() != 1) {
    int actual = args.len();
    raise %(bad-arity (operation "import") (expected 1) (actual $actual));
  }
  Var path = _eval(lisp, args.car(), env);
  if (path is not <string>)
    raise %(bad-types (operation "import") (actual ${path.kind()})
                       (want "String"));
  Var hook;
  if (lisp.globals.try_get(Atom.intern("_x2c.import-hook"), &hook))
    return lisp.apply(hook, %($path));
  File source = File.open(path, "r");
  Var result;
  {
    defer source.close();
    result = lisp.eval_file(source);
  }
  return result;
}

// second-call AUTO inside the private _apply
/* The bounded compiler lowers repeated lambda and macro bodies to the
   shared machine. Compiled calls retain ordinary Lisp activation
   records, and a pre-call check sends raw arguments to the evaluator
   whenever the current callable is a macro, special form, or an
   unprepared lambda. */

#define LISP_AUTO_PARAM_MAX  8
// Native calls this wide evaluate into a stack array; wider ones take one
// scope allocation. Func itself has no arity limit.
#define LISP_NATIVE_ARG_MAX  8
// Machine invocations one session may nest before AUTO defers to the
// evaluator. Each level holds one slot, so this also bounds slot memory.
#define LISP_MACHINE_NESTING_MAX 128
// Macro expansions nested along one path before analysis stops. A macro
// that expands to a call to itself would otherwise never terminate.
#define LISP_AUTO_EXPAND_MAX 32

typedef struct LispLower {
  Lisp lisp;
  LispEnv *env;         // the call site that triggered analysis
  Lambda lambda;
  MachineBuilder b;
  List specials;
  int depth;            // macro expansions open on this path
} *LispLower;

static int LispLower._auto_reject(LispLower l, const char *reason) {
  MachineBuilder b = l.b;
  if (b.status == MACHINE_PREPARED) {
    b.status = MACHINE_INELIGIBLE;
    b.reason = reason;
  }
  return 0;
}

static int _auto_param_index(Lambda lambda, Var name) {
  int index = -1, at = 0;
  for (List p = lambda.params; p; p = p.cdr(), at++)
    if (p.car() == name) index = at;  // last binding wins, like Map.set
  return index;
}

static void LispLower._auto_note(LispLower l, Var name, Var value) {
  l.specials = cons(%($name $value), l.specials);
}

static int LispLower._auto_load_name(LispLower l, Var name) {
  int local = _auto_param_index(l.lambda, name);
  if (local >= 0) return l.b.emit(MW_LLOCAL, local, 0, 0, 0, 0) >= 0;
  Var captured;
  if (l.lambda.captures.try_get(name, &captured)) {
    int constant = l.b.constant(captured);
    return constant >= 0 && l.b.emit(MW_LCAPTURE, constant, 0, 0, 0, 0) >= 0;
  }
  int constant = l.b.constant(name);
  if (constant < 0) return 0;
  return l.b.emit(MW_LGLOBAL, constant, 0, 0, 0, 0) >= 0;
}

static int LispLower._auto_local_name(LispLower l, Var name) =>
  _auto_param_index(l.lambda, name) >= 0 ||
         l.lambda.captures.contains(name);

static int LispLower._auto_compile_constant(LispLower l, Var value) {
  int constant = l.b.constant(value);
  return constant >= 0 && l.b.emit(MW_LCONST, constant, 0, 0, 0, 0) >= 0;
}

/* Only nil is false, so the branch tests for nil. */
static int LispLower._auto_compile_cond(LispLower l, List clauses,
                                        int tail) {
  MachineBuilder b = l.b;
  l._auto_note(lsym_cond, l.lisp.specials[LISP_COND]);
  if (!clauses) return l._auto_reject("cond-args");
  int end_jumps[64], end_count = 0;
  foreach (Var clause, clauses) {
    if (clause is not <list> || List.len(clause) != 2)
      return l._auto_reject("cond-clause");
    if (end_count >= 64) return l._auto_reject("cond-width");
    List pair = clause;
    Var (condition, consequent) = pair;
    if (!l._auto_compile(condition, 0)) return 0;
    int branch = b.emit(MW_LBR_NIL, 0, 0, 0, 0, -1);
    if (branch < 0) return 0;
    if (b.emit(MW_LDROP, 0, 0, 0, 0, 0) < 0 ||
        !l._auto_compile(consequent, tail))
      return 0;
    int jump = b.emit(MW_JUMP, 0, 0, 0, 0, -1);
    if (jump < 0) return 0;
    end_jumps[end_count++] = jump;
    b.set_target(branch, b.length);
  }
  // all-nil conditions produce nil
  if (!l._auto_compile_constant(%())) return 0;
  b.patch(end_jumps, end_count, b.length);
  return 1;
}

static int _auto_qq_dynamic(Var expression, int depth) {
  if (expression is not <list> || expression.is_nil()) return 0;
  List form = expression;
  Var head = form.car();
  if (head == lsym_quasiquote) return _auto_qq_dynamic(form.cdr(), depth + 1);
  if (head == lsym_unquote || head == lsym_splicing) {
    if (form.len() != 2 || depth == 0) return 1;
    return _auto_qq_dynamic(form.cdr(), depth - 1);
  }
  return _auto_qq_dynamic(head, depth) || _auto_qq_dynamic(form.cdr(), depth);
}

static int LispLower._auto_qq_wrap(LispLower l) =>
  l.b.emit(MW_LQQ_WRAP, 0, 0, 0, 0, 0) >= 0;

static int LispLower._auto_qq_append(LispLower l) =>
  l.b.emit(MW_LQQ_APPEND, 0, 0, 0, 0, 0) >= 0;

static int LispLower._auto_compile_qq(
  LispLower l, Var expression, int list, int depth, int live
) {
  if (live >= MACHINE_VALUE_MAX - LISP_AUTO_PARAM_MAX)
    return l._auto_reject("quasiquote-stack");
  if (!_auto_qq_dynamic(expression, depth)) {
    if (!l._auto_compile_constant(expression)) return 0;
    return !list || l._auto_qq_wrap();
  }
  if (expression is <list> && !expression.is_nil()) {
    List form = expression;
    Var (head, argument) = form;
    if (head == lsym_quasiquote) {
      if (!l._auto_compile_constant(%($head)) ||
          !l._auto_compile_qq(form.cdr(), 0, depth + 1, live + 1) ||
          !l._auto_qq_append())
        return 0;
      return !list || l._auto_qq_wrap();
    }
    if (head == lsym_unquote || head == lsym_splicing) {
      if (form.len() != 2) return l._auto_reject("quasiquote-arity");
      if (depth > 0) {
        if (!l._auto_compile_constant(%($head)) ||
            !l._auto_compile_qq(form.cdr(), 0, depth - 1, live + 1) ||
            !l._auto_qq_append())
          return 0;
        return !list || l._auto_qq_wrap();
      }
      if (!list && head == lsym_splicing)
        return l._auto_reject("quasiquote-splice-position");
      if (!l._auto_compile(argument, 0)) return 0;
      return head == lsym_splicing || !list || l._auto_qq_wrap();
    }
    if (!l._auto_compile_qq(head, 1, depth, live) ||
        !l._auto_compile_qq(form.cdr(), 0, depth, live + 1) ||
        !l._auto_qq_append())
      return 0;
    return !list || l._auto_qq_wrap();
  }
  if (!l._auto_compile_constant(expression)) return 0;
  return !list || l._auto_qq_wrap();
}

/* `if`, `and`, `or` and every user macro are Lambdas, not reserved forms,
   and a call to one cannot be lowered. Nothing else in this runtime expands
   a macro ahead of time, so expand the head here and compile the expansion
   instead. Returns 1 with the expansion, 0 when the head names no macro, and
   -1 when the lambda was rejected. */
static int LispLower._auto_expand(LispLower l, Var head, List args,
                                  Var *expansion) {
  Var value;
  if (!_lookup(l.lisp, l.env, head, &value) || value is not <lambda>) return 0;
  Lambda macro = value;
  if (!macro.macro) return 0;
  if (l.depth >= LISP_AUTO_EXPAND_MAX) {
    l._auto_reject("macro-depth");
    return -1;
  }
  /* The evaluator expands only the calls it reaches, so a macro call in a
     branch that never runs fails nowhere today. Analysis reaches every
     branch; keep its failures local by rejecting rather than raising. */
  try *expansion = _call_lambda(l.lisp, macro, args, l.env);
  catch: {
    l._auto_reject("macro-expansion");
    return -1;
  }
  l._auto_note(head, value);
  return 1;
}

/* A tail call may reuse its own frame only when the callee is the lambda
   being compiled: the frame it replaces then holds the same parameters,
   so a free name resolving through the caller chain still finds what it
   found before. Calling a different lambda in tail position would drop
   the caller's locals out of that chain, which the evaluator keeps. */
static int LispLower._auto_self_call(LispLower l, Var head) {
  Var value;
  if (!_lookup(l.lisp, l.env, head, &value) || value is not <lambda>) return 0;
  if (value.lambda() != l.lambda) return 0;
  l._auto_note(head, value);
  return 1;
}

static int LispLower._auto_compile(LispLower l, Var expression, int tail) {
  MachineBuilder b = l.b;
  if (expression.is_atom()) return l._auto_load_name(expression);
  if (expression is not <list> || expression.is_nil())
    return l._auto_compile_constant(expression);
  List form = expression;
  Var (head, argument) = form;
  if (!head.is_atom()) return l._auto_reject("computed-call-head");
  if (l._auto_local_name(head)) return l._auto_reject("dynamic-call-head");
  if (head == lsym_quote) {
    if (form.len() != 2) return l._auto_reject("quote-args");
    l._auto_note(lsym_quote, l.lisp.specials[LISP_QUOTE]);
    return l._auto_compile_constant(argument);
  }
  if (head == lsym_cond) return l._auto_compile_cond(form.cdr(), tail);
  if (head == lsym_def || head == lsym_bind)
    return l._auto_reject("mutation-form");
  if (head == lsym_lambda || head == lsym_macro)
    return l._auto_reject("nested-lambda");
  if (head == lsym_eval) return l._auto_reject("eval-form");
  if (head == lsym_quasiquote) {
    if (form.len() != 2) return l._auto_reject("quasiquote-args");
    l._auto_note(lsym_quasiquote, l.lisp.specials[LISP_QUASIQUOTE]);
    return l._auto_compile_qq(argument, 0, 0, 0);
  }
  if (head == lsym_import) return l._auto_reject("import-form");
  if (head == lsym_apply) return l._auto_reject("apply-form");
  Var expansion;
  int expanded = l._auto_expand(head, form.cdr(), &expansion);
  if (expanded < 0) return 0;
  if (expanded) {
    l.depth++;
    defer l.depth--;
    return l._auto_compile(expansion, tail);
  }
  int name = b.constant(head);
  if (name < 0 || b.emit(MW_LGLOBAL, name, 0, 0, 0, 0) < 0) return 0;
  int raw = b.constant(form.cdr());
  if (raw < 0) return 0;
  int precall = b.emit(MW_LPRECALL, raw, 0, 0, 0, -1);
  if (precall < 0) return 0;
  int argc = 0;
  foreach (Var arg, form.cdr()) {
    if (argc >= LISP_AUTO_PARAM_MAX) return l._auto_reject("call-arity");
    if (!l._auto_compile(arg, 0)) return 0;
    argc++;
  }
  int op = tail && l._auto_self_call(head) ? MW_LTAILCALL : MW_LCALL;
  if (b.emit(op, 0, argc, 0, 0, 0) < 0) return 0;
  b.set_target(precall, b.length);
  return 1;
}

static int _auto_analyze(Lisp lisp, Lambda lambda, LispEnv *env) {
  if (lambda.auto_status >= 0) return lambda.auto_status;
  lisp.auto_stats.analyses++;
  const char *reason = NULL;
  int param_count = 0;
  foreach (Var name, lambda.params) {
    if (name.is_atom() && name.str() == %".") {
      reason = "rest-parameters";
      break;
    }
    param_count++;
  }
  if (!reason && param_count > LISP_AUTO_PARAM_MAX)
    reason = "parameter-capacity";
  if (reason) {
    lambda.auto_status = MACHINE_INELIGIBLE;
    lisp.auto_stats.ineligible++;
    return lambda.auto_status;
  }
  Scope.push(&lisp.scope);
  defer Scope.pop();
  MachineBuilder b = MachineBuilder.new();
  defer b.free();
  struct LispLower storage = { lisp, env, lambda, b, NULL, 0 };
  LispLower lower = &storage;
  int ok = lower._auto_compile(lambda.body, 1) &&
           b.emit(MW_LRETURN, 0, 0, 0, 0, 0) >= 0;
  if (ok) {
    b.root = 0;
    lambda.auto_program = b.freeze();
    lambda.auto_specials = lower.specials;
    lambda.auto_status = MACHINE_PREPARED;
  }
  else
    lambda.auto_status = b.status == MACHINE_PREPARED
                       ? MACHINE_INELIGIBLE : b.status;
  if (lambda.auto_status == MACHINE_PREPARED) {
    lisp.auto_stats.published++;
    lisp.auto_stats.program_bytes += (long) lambda.auto_program.bytes();
  }
  else
    lisp.auto_stats.ineligible++;

  return lambda.auto_status;
}

/* Each note pairs a name with the callable used while compiling it.
   Rebinding the name invalidates the program, so the call falls back to the
   evaluator. */
static int _auto_specials_ok(Lisp lisp, LispEnv *env, Lambda lambda) {
  foreach (List pair, lambda.auto_specials) {
    Var (name, expected) = pair;
    Var value;
    if (!_lookup(lisp, env, name, &value) || value.u64 != expected.u64)
      return 0;
  }
  return 1;
}

static void _raise_machine_error(Var error) {
  if (error is <symbol>) raise %(invariant (owner "Machine") (why $error));

  match (error) {
    case %(unbound (name ?name)):
      raise %(unbound (name $name));
    case %(bad-arity (expected ?expected) (actual ?actual) (value ?value)):
      raise %(bad-arity (expected $expected) (actual $actual)
                         (value-kind ${value.kind()}));
    case %(not-call (value ?value)):
      raise %(not-call (actual ${value.kind()}));
    case %(bad-types (actual ?actual)):
      raise %(bad-types (operation "quasiquote-splice") (actual $actual));
  }
  raise %(invariant (owner "Machine") (cause $error));
}

// decoder crossings declared in lib/machine.x

static LispEnv *_machine_env(LispMachineContext context) =>
  &context.frames[context.depth];

static void _machine_env_set(
  LispEnv *env, Lambda lambda, const Var *values, int count, LispEnv *parent) {
  bzero(env, sizeof(LispEnv));
  env.params = lambda.params;
  env.values = values;
  env.value_count = count;
  env.captures = lambda.captures;
  env.parent = parent;
}

/* Slots form a stack: acquire takes the innermost free one, release returns
   it clean. `defer` pairs them across every exit from a machine invocation,
   including a cause that transfers out of the machine's own callbacks. */
static LispMachineSlot _machine_slot_acquire(Lisp lisp) {
  LispMachineSlot slot = lisp.machine_free;
  if (slot) lisp.machine_free = slot.next;
  else slot = Scope.malloc_in(&lisp.scope, sizeof(struct LispMachineSlot));
  lisp.machine_depth++;
  return slot;
}

static void _machine_slot_release(Lisp lisp, LispMachineSlot slot) {
  LispMachine.finish(&slot.machine);
  slot.next = lisp.machine_free;
  lisp.machine_free = slot;
  lisp.machine_depth--;
}

/* The private hook, called by _apply immediately before _apply_lambda
   for Lambda callables.  Returns 1 with the result only when the
   prepared machine ran the whole call; every decline leaves the
   evaluator path to run unchanged, with no argument evaluated and no
   other effect performed. */
static int _auto_apply(
  Lisp lisp, Lambda lambda, List raw, LispEnv *env, Var *out) {
  if (lisp.auto_disabled) return 0;
  lisp.auto_stats.invocations++;
  if (lambda.auto_calls < 2) lambda.auto_calls++;
  if (lambda.auto_calls < 2) return 0;
  if (lambda.auto_status < 0) {
    if (_auto_analyze(lisp, lambda, env) != MACHINE_PREPARED) return 0;
  }
  else if (lambda.auto_status != MACHINE_PREPARED) {
    lisp.auto_stats.remembered_fallbacks++;
    return 0;
  }
  if (raw.len() != lambda.params.len() ||
      lisp.machine_depth >= LISP_MACHINE_NESTING_MAX ||
      !_auto_specials_ok(lisp, env, lambda)) {
    lisp.auto_stats.guard_failures++;
    return 0;
  }

  Var argv[LISP_AUTO_PARAM_MAX];
  int argc = 0;
  foreach (Var arg, raw)
    argv[argc++] = lambda.macro ? arg : _eval(lisp, arg, env);

  LispMachineSlot slot = _machine_slot_acquire(lisp);
  defer _machine_slot_release(lisp, slot);
  LispMachine m = &slot.machine;
  LispMachineContext context = &slot.context;
  bzero(context, sizeof(struct LispMachineContext));
  context.lisp = lisp;
  _machine_env_set(context.frames, lambda, argv, argc, env);
  LispMachine.open(m);
  /* Only a Lisp callback can raise out of the machine, and that leaves it
     marked running. Clear the flag ahead of the release below, so its
     `LispMachine.finish` never meets the `<bad-state>` guard. */
  defer m.running = 0;
  m.stats = lisp.auto_machine_stats;
  LispMachine.begin(m, lambda.auto_program.view(), context, argv, argc);
  lisp.auto_stats.machine_entries++;
  LispMachine.run(m);
  if (m.status == <ok>) {
    Var result = m.value;
    *out = lambda.macro ? _eval(lisp, result, env) : result;
    return 1;
  }
  Var error = m.error;
  lisp.auto_stats.machine_errors++;
  _raise_machine_error(error);
}

/** Returns the current cumulative automatic-evaluator statistics for `lisp`.
    `lisp` must be a live session. The returned structure is a value snapshot
    and does not reset any counter.
*/
LispAutoStats Lisp.auto_stats(Lisp lisp) => lisp.auto_stats;

/** Selects optional detailed machine statistics for later AUTO executions.
    `lisp` must be a live session.
    `stats` is borrowed, retained without initialization, and updated in place;
    it must outlive every evaluation until replaced or cleared with NULL.
*/
void Lisp.auto_instrument(Lisp lisp, MachineStats *stats) {
  lisp.auto_machine_stats = stats;
}

/* Benchmark and test control for the forced-evaluator comparison arm;
   production leaves AUTO enabled. */
/** Forces calls through the recursive evaluator when `disabled` is nonzero.
    `lisp` must be a live session.
    Re-enabling AUTO preserves published programs, thresholds, statistics, and
    the instrumentation pointer.
*/
void Lisp.auto_disable(Lisp lisp, int disabled) {
  lisp.auto_disabled = disabled;
}

static Var _apply(Lisp lisp, Var callable, List raw, LispEnv *env) {
  if (callable is <lambda>) {
    Lambda lambda = callable;
    Var prepared;
    if (_auto_apply(lisp, lambda, raw, env, &prepared)) return prepared;
    return _apply_lambda(lisp, lambda, raw, env);
  }
  if (callable is not <func>) raise %(not-call (actual ${callable.kind()}));
  Func function = (Func) callable.pointer();
  int special = _special_id(lisp, function);
  if (special >= 0) return _apply_special(lisp, special, raw, env);
  /* The wide path materializes a values List; the narrow one need not. */
  if (raw.len() <= LISP_NATIVE_ARG_MAX) {
    FuncArg argv[LISP_NATIVE_ARG_MAX];
    unsigned argc = 0;
    foreach (Var arg, raw)
      argv[argc++] = FuncArg.value(_eval(lisp, arg, env));
    return function.apply(argc, argv);
  }
  List values;
  _eval_args(lisp, raw, env, &values);
  return _apply_values(lisp, callable, values, env);
}

static Var _apply_values(Lisp lisp, Var callable, List values, LispEnv *env) {
  if (callable is <lambda>) {
    Lambda lambda = callable;
    if (lambda.macro)
      raise %(not-call (operation "apply") (actual ${callable.kind()}));
    return _call_lambda(lisp, lambda, values, env);
  }
  if (callable is not <func>) raise %(not-call (actual ${callable.kind()}));
  Func function = (Func) callable.pointer();
  int special = _special_id(lisp, function);
  if (special >= 0) {
    if (special != LISP_APPLY)
      raise %(not-call (operation "apply") (actual ${callable.kind()}));
    if (values.len() != 2) {
      int actual = values.len();
      raise %(bad-arity (operation "apply") (expected 2) (actual $actual));
    }
    Var rest = values.cadr();
    if (rest is not <list>)
      raise %(bad-types (operation "apply") (actual ${rest.kind()})
                         (want "List"));
    return _apply_values(lisp, values.car(), rest, env);
  }
  int count = values.len();
  FuncArg narrow[LISP_NATIVE_ARG_MAX];
  FuncArg *argv = count <= LISP_NATIVE_ARG_MAX
                ? narrow : Scope.malloc(count * sizeof(FuncArg));
  unsigned argc = 0;
  foreach (Var value, values) argv[argc++] = FuncArg.value(value);
  return function.apply(argc, argv);
}

static Var _eval(Lisp lisp, Var expression, LispEnv *env) {
  if (expression is void) raise %(void-op (operation "eval"));
  if (expression.is_atom()) {
    Var value;
    if (!_lookup(lisp, env, expression, &value))
      raise %(unbound (name $expression));
    return value;
  }
  if (expression is not <list> || expression.is_nil()) return expression;
  List form = expression;
  Var callable = _eval(lisp, form.car(), env);
  return _apply(lisp, callable, form.cdr(), env);
}

static Var _special_stub(void) => Var.null();

static void _install_specials(Lisp lisp) {
  for (int i = 0; i < LISP_SPECIAL_COUNT; i++) {
    const LispCanonicalName *info = _special_name(i);
    lisp.specials[i] = Func.new(_special_stub, %((func ((void))) "Var"));
    Atom name = Atom.intern(info.spelling);
    lisp.reserved[name] = lisp.specials[i];
  }
}

/** Evaluates one Lisp form in `lisp`.
    Evaluation is synchronous and may retain the expression or values it
    reaches in session globals, Lambdas, or captures as described by the module
    ownership rule. Effects completed before a later failure are not rolled
    back. Raises: `<bad-arg>` for a null session, or any evaluator, imported
    operation, or called-procedure cause.
*/
$lisp.entry("Lisp.eval")
Var Lisp.eval(Lisp lisp, Var expression) => _eval(lisp, expression, NULL);

/** Applies `callable` to already evaluated `values`.
    Macros and evaluator special forms other than the built-in `apply` are not
    procedures and are rejected. The built-in accepts a callable
    and a `List` and
    recursively applies those already evaluated values. The Lisp session owns
    `Scope` allocations made by the call; returned canonical or caller-supplied
    values keep their existing owners. The caller retains responsibility for
    `callable`, `values`, and their referents.
    Raises: `<bad-arg>` for a null session, `<not-call>` for a non-procedure or
    evaluator-only callable, `<bad-arity>` or `<bad-types>` at the call
    boundary, or a cause raised by the called procedure.
*/
$lisp.entry("Lisp.apply")
Var Lisp.apply(Lisp lisp, Var callable, List values) =>
  _apply_values(lisp, callable, values, NULL);

/** Reads and evaluates every form in `source`.
    Forms run in source order and the return value is the last result, or Lisp
    `nil` for a null, empty, or comment-only source. Globals and other effects
    completed before a later reader or evaluator failure remain installed.
    Raises: `<bad-arg>` for a null session, `<incomplete>` or `<malformed>`
    while reading, or any cause from `Lisp.eval`.
*/
$lisp.entry("Lisp.eval_string")
Var Lisp.eval_string(Lisp lisp, String source) {
  if (!source) return %();
  Scope tokens_scope = Scope.new_named("Lisp tokens");
  defer Scope.destroy(tokens_scope);
  Tokenizer tokenizer = _scan_lisp_tokens(source, &tokens_scope);
  unsigned cursor = 0;
  Var result = %();
  loop {
    Var form = void;
    Symbol status = _read_tokenizer(tokenizer, source, 0, &cursor, &form);
    if (status == <eof>) break;
    result = _eval(lisp, form, NULL);
  }
  return result;
}

/** Reads and evaluates every form from `file`.
    Reading starts at the current stream position, consumes through EOF, and
    leaves the borrowed stream open. Forms run in order, so effects from forms
    completed before a later read or evaluation failure are not rolled back.
    A null `Lisp` session is rejected by `Lisp.eval_string` only after the
    stream
    has been consumed.
    Raises: `<bad-arg>` for a null stream or embedded NUL, `<io-fail>`,
    `<size-limit>`, or `<alloc-fail>` while reading, or any cause from
    `Lisp.eval_string`.
*/
Var Lisp.eval_file(Lisp lisp, File source) {
  if (!source) raise %(bad-arg (operation "Lisp.eval_file"));
  Block content = Block.new(sizeof(char));
  defer content.free();
  if (source.read_into(content) == FILE_READ_EOF)
    return lisp.eval_string(NULL);
  if (content.length > INT_MAX) {
    size_t size = content.length, int limit = INT_MAX;
    raise %(size-limit (operation "Lisp.eval_file") (size $size)
                       (limit $limit));
  }
  if (memchr(content.bytes, '\0', content.length))
    raise %(bad-arg (operation "Lisp.eval_file") (why "embedded NUL"));
  String text = String.new_len(content.bytes, (int) content.length);
  return lisp.eval_string(text);
}

/** Writes the global binding for `name` to `out` when present.
    Returns 1 only after writing the borrowed value. A null session, name, or
    output, or an absent name returns 0 and leaves `out` unchanged. Raises
    `<alloc-fail>` or `<bad-enc>` when a nonempty lookup name cannot be
    canonicalized.
*/
int Lisp.try_get(Lisp lisp, String name, Var *out) =>
  lisp && name && out && lisp.globals.try_get(Atom.intern(name), out);

/** Binds `name` to `value` in the embedded Lisp global environment.
    The `Map` retains the canonicalized name and `Var` value without taking
    ownership of their referents; their canonical graphs or other owners must
    outlive the binding or session. Binding an `x2c.` name protects that
    namespace from later Lisp `def` forms, but direct calls to this function
    may replace such a binding.
    Raises: `<bad-arg>` for a null session or name, `<void-op>` for a `void`
    value, or `<alloc-fail>`, `<size-limit>`, or `<bad-enc>` while
    canonicalizing or storing the binding.
*/
void Lisp.set_global(Lisp lisp, String name, Var value) {
  if (!lisp || !name) raise %(bad-arg (operation "Lisp.set_global"));

  if (value is void) raise %(void-op (operation "Lisp.set_global"));

  Scope.push(&lisp.scope);
  defer Scope.pop();
  lisp.globals[Atom.intern(name)] = value;
  if (name.startswith("x2c.")) lisp.protect_x2c = 1;
}

/** Installs `function` as `name` and transfers its storage to `lisp`.
    Invalid arguments raise `<bad-arg>` without transferring ownership. Once
    validation succeeds, the `Func` moves before the global insertion. The
    caller relinquishes ownership even if name canonicalization or `Map` growth
    then raises `<alloc-fail>`, `<size-limit>`, or `<bad-enc>`, but may borrow
    the pointer while the session lives. Values inside the `Func`, including
    its
    signature graph, retain their existing owners.
*/
void Lisp.bind(Lisp lisp, String name, Func function) {
  if (!lisp || !name || !function) raise %(bad-arg (operation "Lisp.bind"));

  Scope.move(function, &lisp.scope);
  lisp.set_global(name, Func.var(function));
}
