/*  lisp.x -- the Lisp runtime: reader, session, and evaluator

    Copyright (c) 2026 Gary William Flake.

    Each `Lisp` session owns a `Scope` holding its global environment.
    Evaluation uses eager left-to-right
    arguments for lambdas and natives, raw arguments for macros and
    special forms, macro expansion evaluated once in the caller's
    environment, globals able to shadow reserved forms, `nil` as the only
    false value, and by-value capture of free locals through body flattening.

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
    Create it with `Lisp.new` or `Lisp.kernel` and end it with
    `Lisp.destroy`. The module header describes its owned and borrowed state.
    A session is mutable and requires caller serialization.
*/
typedef struct Lisp *Lisp;

macro Expression $lisp._standard.source() => (
  $(x2c.literal.string (_x2c.embed.text "../etc/init.xlisp"))
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
  long inlined_scopes;  // binding scopes lowered into a caller's slots
  long inline_declines; // binding scopes the evaluator took instead
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

/** Resolves one global Lisp name for the running shared machine.
    `storage` must be the context of a running LispMachine and `value` must be
    nonnull. Returns 1 and writes the borrowed binding, or returns 0 and leaves
    the output unchanged.

    Lowering emits this read only for a name that is none of the frame's
    slots and none of the Lambda's captures. A free name is lexical, so the
    only place left to look is the session and its parents, and the frame is
    not consulted.
*/
int Lisp.resolve(void *storage, Var name, Var *value) {
  Lisp lisp = ((LispMachineContext) storage).lisp;
  if (!_global_lookup(lisp, name, value) &&
      !_reserved_lookup(lisp, name, value))
    return 0;
  _expansion_note(lisp, name, *value);
  return 1;
}

/** Pushes one prepared-Lambda environment for the shared machine.
    `storage` names a running LispMachine context, `callable` is a prepared
    Lambda, and `values` supplies the Lambda's `count` borrowed arguments. The
    array and its values must remain live until the matching `Lisp.leave`.
*/
void Lisp.enter(void *storage, Var callable, const Var *values, int count) {
  LispMachineContext context = (LispMachineContext) storage;
  Lambda lambda = callable;
  // A callee's free names are lexical: they resolve through its captures
  // and then the globals, never through the frame that called it.
  LispEnv *parent = NULL;
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

/** Replaces the current shared-machine environment for a tail call.
    The callee may be any prepared Lambda, not only the running one, because
    a free name is lexical and the callee never reads the frame it lands in.
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

/** Counts one call made by the running machine and reports whether the
    evaluation in progress has made too many. An exhausted budget stays
    exhausted until the entry that opened it returns.
*/
int Lisp.step(void *storage) {
  Lisp lisp = ((LispMachineContext) storage).lisp;
  if (lisp.call_exhausted) return 1;
  if (++lisp.call_steps <= lisp.call_step_max) return 0;
  lisp.call_exhausted = 1;
  return 1;
}

/** Renames the live slots of the current shared-machine frame.
    `params` names every slot the frame holds: the Lambda's parameters first,
    then the bindings a lowered binding scope opened, in slot order. `count`
    is how many of those slots are live. The evaluator resolves a free name
    through this list, so a form that leaves the machine from inside a lowered
    binding scope still reads that scope's bindings.
*/
void Lisp.reslot(void *storage, List params, int count) {
  LispEnv *frame = _machine_env((LispMachineContext) storage);
  frame.params = params;
  frame.value_count = count;
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
        lambda.auto_program)
      return 0;
  }
  *value = _apply(lisp, callable, raw, env);
  return 1;
}

/** Resolves a prepared immediate lambda in the running machine context.
    Returns `callable` while the lambda constructor is unchanged; otherwise
    evaluates its original literal. The caller environment stays live and is
    borrowed by the prepared body. `storage` must name the running context,
    and `callable` must be its prepared immediate Lambda.
*/
Var Lisp.immediate(void *storage, Var callable) {
  LispMachineContext context = (LispMachineContext) storage;
  Lisp lisp = context.lisp;
  LispEnv *env = _machine_env(context);
  Var constructor;
  if (_lookup(lisp, env, lsym_lambda, &constructor) &&
      constructor.u64 == Func.var(lisp.specials[LISP_LAMBDA]).u64)
    return callable;
  Lambda lambda = callable;
  return _eval(lisp, %($lsym_lambda ${lambda.params} ${lambda.body}), env);
}

/** Evaluates one borrowed form in the running machine's environment.
    `storage` must name a running LispMachine context. The form is interpreted
    by the ordinary evaluator with the machine frame's parameters and captures
    visible, so a form the lowering does not cover behaves exactly as it does
    outside a prepared program. Results keep their ordinary session or value
    owners.
    Raises any cause the form raises.
*/
Var Lisp.evaluate(void *storage, Var form) {
  LispMachineContext context = (LispMachineContext) storage;
  return _eval(context.lisp, form, _machine_env(context));
}

/** Checks a lowered form after preceding effects have run.
    Returns 0 when its dependencies match. Otherwise evaluates the original
    call into `out` and returns 1. `storage` must name the running context,
    `site` must contain the original form and dependency pairs, and `out`
    must be nonnull. Results retain their ordinary session or value owners.
*/
int Lisp.expanded(void *storage, List site, Var *out) {
  LispMachineContext context = (LispMachineContext) storage;
  Var (form, dependencies) = site;
  if (_auto_bindings_ok(context.lisp, _machine_env(context), dependencies))
    return 0;
  context.lisp.auto_stats.guard_failures++;
  *out = _eval(context.lisp, form, _machine_env(context));
  return 1;
}

protocol Cleanup(Lisp);

#pragma private

#include "typed-list.x"
#include "list-selectors.x"
#include "digest.x"
#include "json.x"

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

typedef struct LispExpansion {
  List dependencies;
  int calls, steps;
} LispExpansion;

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
  /* A session may read a parent's globals, reserved names and special
     forms. The parent holds definitions built once, before any child
     exists, and a child holds only its own, so a name the child defines
     shadows the parent's and nothing a child writes reaches another child.
     A parent outlives every child that names it. */
  Lisp parent;
  /* Set once the parent is complete. Nothing a child does may produce a
     value the parent reaches, because a child's values belong to a
     narrower Context than the parent's. */
  int frozen;
  Map globals;          // global bindings, Lisp name -> value
  Map reserved;         // reserved special forms, Lisp name -> <func> Var
  Func specials[LISP_SPECIAL_COUNT];
  LispAutoStats auto_stats;
  MachineStats *auto_machine_stats;
  LispMachineSlot machine_free;   // reusable machine slots, innermost first
  LispExpansion *expansion;
  int machine_depth;    // machine invocations in progress on this session
  int call_depth;       // evaluator calls nested on this session
  long call_steps;      // calls made by the evaluation in progress, reset
                        // at each public entry so a long translation is a
                        // sequence of budgets rather than one
  int call_exhausted;   // the budget ran out and no call may renew it until
                        // the public entry that opened it returns
  long call_step_max;   // calls one evaluation may make
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
  Lisp owner;
  List params;
  Var body;
  Map captures, int macro, auto_calls, auto_status;
  MachineProgram auto_program;
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

/* A form's elements are read in a loop, so only nesting costs a frame.
   The reader fences that nesting instead of exhausting the C stack, which
   on a worker thread is a fraction of the main thread's. */
#define LISP_READ_DEPTH_MAX 1024

static Symbol _read_token_list(
  Tokenizer tokenizer, char *source, unsigned base, unsigned *end, Var *out,
  int depth) {
  if (depth >= LISP_READ_DEPTH_MAX)
    raise %(size-limit (operation "Lisp.read") (depth $depth));
  Array elements = [], Symbol status = <value>;
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
    status =
      _read_token_form(tokenizer, token, source, base, end, &element, depth);
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
  Var *out, int depth) {
  if (!token || token.type == <eof>) return <incomplete>;
  Var prefix = void;
  switch (token.type) {
    case <error>:
      if (tokenizer.status() == <incomplete>) return <incomplete>;
      return _malformed(source, base + token.pos);
    case <")">: return _malformed(source, base + token.pos);
    case <"(">:
      return _read_token_list(tokenizer, source, base, end, out, depth + 1);
    case <"'">:  prefix = lsym_quote;      break;
    case <"`">:  prefix = lsym_quasiquote; break;
    case <",">:  prefix = lsym_unquote;    break;
    case <",@">: prefix = lsym_splicing;   break;
  }
  if (prefix is not void) {
    Var inner = void;
    Symbol status = _read_token_form(
      tokenizer, tokenizer.next(), source, base, end, &inner, depth + 1);
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
    tokenizer, token, source, base, &end, &value, 0);
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
  Tokenizer tokenizer = NULL;
  $scope(scope) {
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

  Scope.push(&$(x2c.function.parameter $function "lisp").scope);
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
Lisp Lisp.kernel(void) {
  Scope session = Scope.new_named("Lisp session"), Lisp result = NULL;
  defer if (!result) Scope.destroy(session);
  Lisp lisp = NULL;
  $scope(&session) {
    lisp = Scope.calloc(1, sizeof(struct Lisp));
  }
  if (!lisp._initialize()) return NULL;
  lisp.scope = session;
  lisp.auto_stats = (LispAutoStats) {0};
  lisp.auto_machine_stats = NULL;
  lisp.auto_disabled = 0;
  lisp.parent = NULL;
  lisp.frozen = 0;
  lisp.call_step_max = LISP_CALL_STEP_MAX;
  $scope(&lisp.scope) {
    lisp.globals = {};
    lisp.reserved = {};
    _install_specials(lisp);
  }
  return result = lisp;
}

/** Creates an isolated session with the standard Lisp environment loaded.
    The caller owns the result and must pass it to `Lisp.destroy`.
    If standard-source evaluation transfers, no handle is returned and the
    constructed session remains allocated.
    Raises any cause from `Lisp.kernel` or `Lisp.eval_string`.
*/
Lisp Lisp.new(void) {
  Lisp lisp = Lisp.kernel();
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

/** Makes `lisp` read `parent`'s definitions for names it does not bind.

    A name the child defines shadows the parent's, and a write always lands
    in the child, so one child never observes another's definitions. The
    child also takes the parent's special forms rather than its own, because
    `_auto_bindings_ok` compares a binding's identity and a program the
    parent compiled has to keep guarding correctly under a child.

    The caller keeps `parent` alive for as long as any child names it, and
    freezes it with `Lisp.freeze` before the first child runs: a child's
    values belong to a narrower `Context` than the parent's, so nothing a
    child produces may become reachable from the parent.
*/
void Lisp.adopt(Lisp lisp, Lisp parent) {
  if (!lisp || !parent) return;
  lisp.parent = parent;
  $scope(&lisp.scope) lisp.reserved = {};
  for (int i = 0; i < LISP_SPECIAL_COUNT; i++)
    lisp.specials[i] = parent.specials[i];
}

/** Marks `lisp` complete, so nothing produced later may reach it.

    Word compilation is what this guards: a program's frozen constants do
    not own their pointees, so one compiled while a unit's `Context` is
    current would leave a frozen session holding values that die with that
    unit. After this, `Lisp.auto_prepare` is the only way a lambda this
    session owns gains a program.
*/
void Lisp.freeze(Lisp lisp) { if (lisp) lisp.frozen = 1; }

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
  Symbol status;
  {
    Scope tokens_scope = $auto(Scope.new_named("Lisp tokens"));
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

/* `Var.car` and `Var.cdr` read the raw payload as a cell, which is the right
   contract for a caller that already typed the value. Lisp applies these to
   whatever the program evaluated, so the tag is checked here first. */

/** Returns the first element of `value`, or `void` when it is `nil`.
    A nonlist operand raises `<bad-types>`.
*/
Var lisp_car(Var value) {
  if (value is not <list>)
    raise %(bad-types (operation "car") (kind ${value.kind()}));
  return value.car();
}

/** Returns the tail of `value`, or `nil` when it is `nil`.
    A nonlist operand raises `<bad-types>`.
*/
Var lisp_cdr(Var value) {
  if (value is not <list>)
    raise %(bad-types (operation "cdr") (kind ${value.kind()}));
  return value.cdr();
}

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

/* Orders the four number classes the total order uses:
   -inf < finite < +inf < NaN. */
static int _number_class(Var value, long double magnitude) {
  Symbol tag = value.tag();
  if (tag == <-inf>) return 0;
  if (tag == <+inf>) return 2;
  if (tag == <nan> || magnitude != magnitude) return 3;
  if (magnitude == 1.0L / 0.0L) return 2;
  if (magnitude == -1.0L / 0.0L) return 0;
  return 1;
}

/* `Var.compare` is a total order over every value, so it separates two
   encodings of the same number by rank to give each one its own place in a
   sort. Lisp `=`, `<`, and `<=` answer about numbers, so 1 and 1.0 are one
   number here and comparison stops at the value. */
static int _number_compare(Var a, Var b) {
  Symbol ak = a.kind(), bk = b.kind();
  long double da = ak == <floating> ? a.long_double() : 0.0L;
  long double db = bk == <floating> ? b.long_double() : 0.0L;
  int ca = _number_class(a, da), cb = _number_class(b, db);
  if (ca != cb) return ca < cb ? -1 : 1;
  if (ca != 1) return 0;
  if (ak == <integer> && bk == <integer>) return a.integer_compare(b);
  if (ak == <integer>) return a.integer_floating_compare(b);
  if (bk == <integer>) return -b.integer_floating_compare(a);
  return da < db ? -1 : da > db ? 1 : 0;
}

/** Compares Lisp numbers by value and returns a boxed negative, zero, or
    positive. Integer and floating encodings of one number compare equal.
    A nonnumeric operand raises `<bad-types>`.
*/
Var lisp_compare(Var a, Var b) {
  if (!_is_lisp_number(a) || !_is_lisp_number(b))
    raise %(bad-types (operation "lisp_compare")
                       (left-kind ${a.kind()})
                       (right-kind ${b.kind()}));
  return _number_compare(a, b);
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
  if (values && values.car() is <string>) total = %"";
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
    int order = lisp_compare(left, right);
    if (expect ? order != want : order == want) return _bool(0);
  }
  return _bool(1);
}

/** Reports whether every neighbouring pair of numbers compares equal.
    Fewer than two values raise `<bad-arity>`; a nonnumber raises
    `<bad-types>`.
*/
Var lisp_eq_chain(List values) => _chain(values, "=", 0, 1);

/** Reports whether two or more numbers strictly increase.
    Fewer than two values raise `<bad-arity>`; a nonnumber raises
    `<bad-types>`.
*/
Var lisp_lt_chain(List values) => _chain(values, "<", -1, 1);

/** Reports whether two or more numbers never decrease.
    Fewer than two values raise `<bad-arity>`; a nonnumber raises
    `<bad-types>`.
*/
Var lisp_le_chain(List values) => _chain(values, "<=", 1, 0);

/** Reports whether two or more numbers strictly decrease.
    Fewer than two values raise `<bad-arity>`; a nonnumber raises
    `<bad-types>`.
*/
Var lisp_gt_chain(List values) => _chain(values, ">", 1, 1);

/** Reports whether two or more numbers never increase.
    Fewer than two values raise `<bad-arity>`; a nonnumber raises
    `<bad-types>`.
*/
Var lisp_ge_chain(List values) => _chain(values, ">=", -1, 0);

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

static char *_string_charset(Var chars) =>
  chars.is_nil() || (chars.is_integer() && !chars.integer())
    ? NULL : chars.string();

/** Trims the bytes in `chars`, using whitespace for an empty String. */
String lisp_string_strip(String string, Var chars) =>
  string.strip(_string_charset(chars));

/** Trims leading bytes, accepting the same charset values as `strip`. */
String lisp_string_lstrip(String string, Var chars) =>
  string.lstrip(_string_charset(chars));

/** Trims trailing bytes, accepting the same charset values as `strip`. */
String lisp_string_rstrip(String string, Var chars) =>
  string.rstrip(_string_charset(chars));

/** Returns the instantiated `template` when `input` matches `pat`.
    `List.match_replace` returns a `List`, so a template that is a bare binder
    loses a scalar result. Lisp sees the replacement itself. A miss, malformed
    pattern, cache pressure, or machine error returns `input` unchanged.
*/
Var lisp_match_replace(List input, Var pat, Var template) {
  Var result;
  if (!input.try_match_replace(pat, template, &result)) return input;
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

/* Native const-char pointers use represented String storage here. */
static String _lisp_string_new_len(String text, int length) =>
  String.new_len(text, length);
static Symbol _lisp_symbol_parse(String text) => Symbol.parse(text);
static Symbol _lisp_symbol_new_len(String text, int length) =>
  Symbol.new_len(text, length);

// The direct targets let the compiler generate their call adapters and
// read each signature from the declared prototype.
$(import "../etc/lisp-bindings.xlisp")
$(def lisp.native.target.rows '(
  (lisp_car (as Var_car))
  (lisp_cdr (as Var_cdr))
  (Var_cons)
  (lisp_atom)
  (lisp_pair)
  (lisp_list)
  (lisp_eq)
  (lisp_type)
  (lisp_number)
  (lisp_string)
  (lisp_symbol)
  (lisp_procedure)
  (List_reverse)
  (List_len)
  (List_match)
  (lisp_match_replace)
  (List_search)
  (List_search_replace)
  (lisp_add)
  (Var_binary)
  (lisp_compare)
  (lisp_plus rest)
  (lisp_minus rest)
  (lisp_times rest)
  (lisp_divide rest)
  (lisp_eq_chain rest)
  (lisp_lt_chain rest)
  (lisp_le_chain rest)
  (lisp_gt_chain rest)
  (lisp_ge_chain rest)
  (lisp_str)
  (lisp_repr)
  (String_len)
  (lisp_string_append)
  (lisp_substring)
  (lisp_string_downcase)
  (lisp_read_file)
  (lisp_write_file)
  (List_sort)

  // The core value types: their operations are the library's own, so a
  // Lisp session and a compiled program build the same List, String, Map,
  // and Array. `etc/lisp-values.xlisp` names them.
  (List_unique)
  (List_sublis)
  (List_flatten)
  (List_flatten_all)
  (List_nth_cdr)
  (List_tail)
  (List_head)
  (List_subseq)
  (List_getslice)
  (List_hash)
  (List_compare)
  (List_replace)
  (List_match_replace)
  (Array_copy)
  (Array_getslice)
  (Array_concat)
  (Array_reverse)
  (Array_compare)
  (Array_sort)
  (Array_equal)
  (Array_indexof)
  (Array_truth)
  (Map_copy)
  (Map_merge)
  (Map_compare)
  (Map_equal)
  (Map_truth)
  (String_intern)
  (String_parse)
  (String_parse_char)
  (String_withindex)
  (String_truth)
  (Symbol_first)
  (Symbol_last)
  (Array_capacity)
  (Array_remslice)
  (Array_setslice)
  (Array_splice)
  (Array_updateindex)
  (Array_postfixindex)
  (Array_clear)
  (Array_heap_push)
  (Array_heapify)
  (Array_pop)
  (Array_resize)
  (Array_truncate)
  (Map_new_capacity)
  (Map_updateindex)
  (Map_postfixindex)
  (Map_set)
  (Var_array)
  (Var_map)
  (Var_string)
  (Var_symbol)
  (Var_char)
  (Var_short)
  (Var_int)
  (Var_long)
  (Var_long_long)
  (Var_unsigned)
  (Var_ushort)
  (Var_uchar)
  (Var_uint)
  (Var_ulong)
  (Var_ulong_long)
  (Var_float)
  (Var_double)
  (Var_long_double)
  (Var_long_value)
  (Var_ulong_value)
  (Var_long_long_value)
  (Var_ulong_long_value)
  (Var_long_double_value)
  (Var_compare)
  (Var_contains)
  (Var_hash)
  (Var_same)
  (Var_is_atom)
  (Var_is_atom_binder)
  (Var_is_binder)
  (Var_is_list_binder)
  (Var_is_match_op)
  (Var_is_floating)
  (Var_is_integer)
  (Var_is_pointer)
  (Var_is_reference)
  (Var_is_object)
  (Var_is_wide)
  (Var_is_nil)
  (Var_add)
  (Var_sub)
  (Var_mul)
  (Var_div)
  (Var_mod)
  (Var_neg)
  (Var_truth)
  (Var_setindex)
  (Var_updateindex)
  (Var_postfixindex)
  (List_truth)
  (List_listchar)
  (List_listshort)
  (List_listint)
  (List_listfloat)
  (List_listdbl)
  (List_liststring)
  (List_listsymbol)
  (List_cdddr)
  (List_cddddr)
  (Var_listchar)
  (Var_listshort)
  (Var_listint)
  (Var_listfloat)
  (Var_listdbl)
  (Var_liststring)
  (Var_listsymbol)
  (Var_cdddr)
  (Var_cddddr)
  (Var_json)
  (Var_pretty_json)
  (String_sha256)
  (_lisp_string_new_len)
  (_lisp_symbol_new_len)
  (_lisp_symbol_parse)
  (Var_box_f32)
  (Var_box_f64)
  (Var_box_i16)
  (Var_box_i32_bits)
  (Var_box_i8)
  (Var_box_long)
  (Var_box_long_double)
  (Var_box_long_long)
  (Var_box_u16)
  (Var_box_u32)
  (Var_box_u8)
  (Var_box_ulong)
  (Var_box_ulong_long)
  (Var_custom_descriptor_index)
  (Var_decode_f32)
  (Var_decode_f64)
  (Var_encoding_valid)
  (Var_fallback_compare)
  (Var_fallback_equal)
  (Var_fallback_hash)
  (Var_fallback_repr)
  (Var_fallback_str)
  (Var_fallback_truth)
  (Var_integer_box)
  (Var_integer_compare)
  (Var_integer_floating_compare)
  (Var_integer_tag)
  (Var_is_row)
  (Var_known_tag)
  (Var_payload32)
  (Var_signed_from_bits)
  (Var_wide_compare)
  (Var_wide_equal)
  (Var_wide_hash)
  (Var_width_mask)
  (List_getindex)
  (List_last)
  (List_index)
  (List_contains)
  (List_get)
  (List_assoc)
  (List_array)
  (Array_new)
  (Array_len)
  (Array_push)
  (Array_getindex)
  (Array_setindex)
  (Array_take_last)
  (Array_shift)
  (Array_unshift)
  (Array_insert)
  (Array_remove)
  (Array_find)
  (Array_contains)
  (Array_count)
  (Array_join)
  (Array_list)
  (Map_new)
  (Map_len)
  (Map_get)
  (Map_getindex)
  (Map_setindex)
  (Map_contains)
  (Map_del)
  (Map_getdefault)
  (Map_setdefault)
  (Map_list)
  (String_contains_digit)
  (String_is_alpha)
  (String_is_alpha_under)
  (String_is_digit)
  (String_is_alnum)
  (String_is_alnum_under)
  (String_is_identifier)
  (String_is_space)
  (String_is_lower)
  (String_is_lower_under)
  (String_is_upper)
  (String_is_upper_under)
  (String_compare)
  (String_hash)
  (String_symbol)
  (String_dedent)
  (String_keep)
  (String_reject)
  (String_squeeze)
  (String_pad_left)
  (String_pad_right)
  (String_pad_center)
  (String_new_fill)
  (String_find_within)
  (String_replace_n)
  (String_split_n)
  (lisp_string_lstrip)
  (lisp_string_rstrip)
  (String_find)
  (String_rfind)
  (String_count)
  (String_contains)
  (String_startswith)
  (String_endswith)
  (String_getindex)
  (String_getslice)
  (String_add)
  (String_lower)
  (String_upper)
  (lisp_string_strip)
  (String_capitalize)
  (String_repeat)
  (String_replace)
  (String_join)
  (String_split)
  (String_split_lines)
  (String_partition)
  (String_rpartition)
  (String_find_all)
  (String_remove_prefix)
  (String_remove_suffix)
  (String_escape)
  (String_unescape)
  (Var_tag)
  (Var_kind)
  (Var_is)
  (Var_parse)
  (Var_convert)
  (Var_integer)
  (Var_floating)
  (Var_is_null)
  (Symbol_len)
  (Symbol_str)
  (Symbol_compare)
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
/* A parameter name and the name a form reads are both produced by the
   reader through `Atom.intern`, which gives one canonical value per
   spelling: a short name packs into the `Symbol` bits and a long one is
   interned. Identity therefore answers what `Var.equal` answers here, and
   without the descriptor lookup and tag decode that the general comparison
   pays on both sides. Verified over a `lib/` and a `src/` translate: 89,898
   matches, no case where the two disagreed. */
static int _local_lookup(LispEnv *env, Var name, Var *out) {
  int found = 0, at = 0;
  for (List p = env.params; p && at < env.value_count; p = p.cdr(), at++)
    if (p.car().u64 == name.u64) {
      *out = env.values[at];
      found = 1;
    }
  return found || (env.bindings && env.bindings.try_get(name, out));
}

/* An expansion whose result depends on something the program can change
   later cannot be baked into a shared program. */
static void _expansion_decline(void) {
  raise %(bad-state (operation "Lisp AUTO expansion"));
}

static void _expansion_note(Lisp lisp, Var name, Var value) {
  if (!lisp.expansion) return;
  foreach (List pair, lisp.expansion.dependencies)
    if (pair.car() == name) return;
  lisp.expansion.dependencies =
    cons(%($name $value), lisp.expansion.dependencies);
}

/* Only immutable data can be shared as a prepared expansion. In particular,
   a freshly created closure or mutable container must remain a runtime value.
   The same bound keeps native inspection away from mutable nested values. */
static int _expansion_value(Var value, int depth) {
  if (value is <list>) {
    if (depth >= LISP_AUTO_EXPAND_MAX) return 0;
    foreach (Var part, value.list())
      if (!_expansion_value(part, depth + 1)) return 0;
    return 1;
  }
  return value.is_atom() || _is_lisp_number(value) || value is <string>;
}

/* This is an optimization boundary, not permission to call an arbitrary
   host function. Identity admits aliases of these fixed implementations;
   a rebound Lisp name or a newly bound native still declines. */
static void _expansion_native(Lisp lisp, Func function) {
  if (!lisp.expansion) return;
  static const char *names[] = {
    "Var_car", "Var_cdr", "Var_cons", "lisp_atom", "lisp_pair", "lisp_list",
    "lisp_eq", "lisp_type", "lisp_number", "lisp_string", "lisp_symbol",
    "List_reverse", "List_len", "lisp_add", "lisp_compare", "lisp_plus",
    "lisp_minus", "lisp_times", "lisp_divide", "lisp_eq_chain",
    "lisp_lt_chain", "lisp_le_chain", "lisp_gt_chain", "lisp_ge_chain",
    "lisp_str", "String_len", "lisp_string_append", "lisp_substring",
    "lisp_string_downcase"
  };
  for (unsigned i = 0; i < sizeof(names) / sizeof(names[0]); i++)
    if (function == _native_target(names[i])) return;
  _expansion_decline();
}

static void _expansion_argument(Lisp lisp, Var value) {
  if (lisp.expansion && !_expansion_value(value, 0))
    _expansion_decline();
}

/* A prepared expansion records the globals it read, because the session can
   change one later. Slots and captures need no record: a call's environment
   chain ends at its Lambda's captures, which are the values the Lambda was
   made with and do not change afterwards. */
static int _env_lookup(LispEnv *env, Var name, Var *out) {
  for (LispEnv *cur = env; cur; cur = cur.parent)
    if (_local_lookup(cur, name, out) ||
        (cur.captures && cur.captures.try_get(name, out)))
      return 1;
  return 0;
}

/* A session inherits its parent's definitions and cannot replace one. The
   parent outlives every child and is shared by all of them, so a child that
   rebound an inherited name would change what its siblings read, and nothing
   lowered against that name could be trusted. */
static int _inherited(Lisp lisp, Var name) {
  for (Lisp s = lisp.parent; s; s = s.parent)
    if (name in s.globals || name in s.reserved) return 1;
  return 0;
}

/* The binding an ancestor supplies, when that ancestor is frozen and the
   rule above therefore makes it final for this session's whole life. */
static int _frozen_binding(Lisp lisp, Var name, Var *out) {
  for (Lisp s = lisp.parent; s; s = s.parent)
    if (s.globals.try_get(name, out) || s.reserved.try_get(name, out))
      return s.frozen;
  return 0;
}

static int _global_lookup(Lisp lisp, Var name, Var *out) {
  for (Lisp s = lisp; s; s = s.parent)
    if (s.globals.try_get(name, out)) return 1;
  return 0;
}

/* A reserved special form, from this session or the nearest parent. A child
   that inherits its parent's specials also inherits their identity, which is
   what `_auto_bindings_ok` compares, so a program the parent compiled still
   guards correctly when a child runs it. */
static int _reserved_lookup(Lisp lisp, Var name, Var *out) {
  for (Lisp s = lisp; s; s = s.parent)
    if (s.reserved.try_get(name, out)) return 1;
  return 0;
}

static int _lookup(Lisp lisp, LispEnv *env, Var name, Var *out) {
  if (_env_lookup(env, name, out)) return 1;
  if (!_global_lookup(lisp, name, out) && !_reserved_lookup(lisp, name, out))
    return 0;
  _expansion_note(lisp, name, *out);
  return 1;
}

static int _param_has(List params, Var name) {
  foreach (Var param, params) if (param == name) return 1;
  return 0;
}

/* The names a body reads from the environment that defines it.

   Only an evaluated position contributes one. Outside a `quasiquote` a
   `quote`d subform is data; inside one the data is the default and a
   `quote`d subform may still hold an unquote. `depth` counts the
   quasiquote nesting, an unquote lowers it, and a name is read only where it
   reaches zero again. An inner `lambda` or `macro` binds its parameters for
   its own body, so a name it rebinds is not free below it.

   `bound` grows as the walk descends, so it is the enclosing binders at this
   point rather than one flat set. */
static void _free_names(
  Lisp lisp, Var form, List bound, int depth, Array out) {
  if (form.is_atom()) {
    if (depth == 0 && !(form in lisp.reserved) && !_param_has(bound, form))
      out.push(form);
    return;
  }
  if (form is not <list>) return;
  List items = form;
  if (!items) return;
  Var head = items.car();
  /* Quoted data reads nothing on its own, but inside a quasiquote an
     unquote below it is still evaluated, so the walk continues there. */
  if (head == lsym_quote && depth == 0) return;
  if (head == lsym_quasiquote || head == lsym_unquote ||
      head == lsym_splicing) {
    int inner = head == lsym_quasiquote ? depth + 1 : depth - 1;
    if (inner < 0) inner = 0;
    foreach (Var part, items.cdr()) _free_names(lisp, part, bound, inner, out);
    return;
  }
  if (depth == 0 && (head == lsym_lambda || head == lsym_macro)) {
    List rest = items.cdr();
    List extended = bound;
    if (rest && rest.car() is <list>)
      foreach (Var name, (List) rest.car()) extended = cons(name, extended);
    foreach (Var part, rest.cdr())
      _free_names(lisp, part, extended, depth, out);
    return;
  }
  foreach (Var part, items) _free_names(lisp, part, bound, depth, out);
}

static void _capture(Lisp lisp, LispEnv *env, List params, Var body,
                     Map captures) {
  Array names = $auto([]);
  _free_names(lisp, body, params, 0, names);
  foreach (Var name, names) {
    Var value;
    if (name in captures) continue;
    if (_env_lookup(env, name, &value)) captures[name] = value;
  }
}

static void _eval_args(Lisp lisp, List args, LispEnv *env, List *out) {
  Array values = $auto([]);
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
  lambda.owner = lisp;
  (List params, Var body) = args;
  lambda.params = params;
  lambda.body = body;
  lambda.captures = {};
  lambda.macro = macro;
  lambda.auto_calls = 0;
  lambda.auto_status = -1;
  lambda.auto_program = NULL;
  _capture(lisp, env, lambda.params, lambda.body, lambda.captures);
  return result = lambda;
}

static void _bind_params(Lambda lambda, List args, Map bindings) {
  for (List p = lambda.params; p; p = p.cdr()) {
    Var (name, rest_name) = p;
    if (name.is_atom() && name.str() == ".") {
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

static Var _call_lambda(Lisp lisp, Lambda lambda, List args) {
  if (lisp.call_exhausted || ++lisp.call_steps > lisp.call_step_max) {
    lisp.call_exhausted = 1;
    raise %(call-stack (operation "apply") (why "steps"));
  }
  if (++lisp.call_depth > LISP_CALL_DEPTH_MAX) {
    lisp.call_depth--;
    raise %(call-stack (operation "apply") (value ${lambda.body}));
  }
  defer lisp.call_depth--;
  LispExpansion *trace = lisp.expansion;
  if (trace && ++trace.calls >= MACHINE_FRAME_MAX) _expansion_decline();
  defer if (trace) trace.calls--;
  Scope frame = $auto(Scope.new_named("Lisp frame")), Map bindings = NULL;
  $scope(&frame) { bindings = {}; }
  /* A free name the lambda did not capture is a global. The environment the
     call was written in is not a parameter here, so a caller's binding
     cannot change what the body reads. */
  LispEnv captured = {
    .bindings = lambda.captures,
    .parent = NULL
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
  Var result = _call_lambda(lisp, lambda, args);
  return lambda.macro ? _eval(lisp, result, env) : result;
}

static int _special_id(Lisp lisp, Func function) {
  for (int i = 0; i < LISP_SPECIAL_COUNT; i++)
    if (lisp.specials[i] == function) return i;
  return -1;
}

static Var _apply_special(Lisp lisp, int id, List args, LispEnv *env) {
  if (lisp.expansion &&
      (id == LISP_DEF || id == LISP_BIND || id == LISP_EVAL ||
       id == LISP_IMPORT))
    _expansion_decline();
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
      if (_inherited(lisp, name))
        raise %(bad-state (operation "def") (why "inherited") (name $name));
      /* A frozen session is complete, and a value produced now belongs to a
         narrower Context than it does, so the binding would outlive what it
         names. A child session is where a later definition goes. */
      if (lisp.frozen)
        raise %(bad-state (operation "def") (why "frozen") (name $name));
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
  if (_global_lookup(lisp, Atom.intern("_x2c.import-hook"), &hook))
    return lisp.apply(hook, %($path));
  Var result;
  {
    File source = $auto(File.open(path, "r"));
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
/* Evaluator calls nested along one path. Each costs about 2 KB of C stack,
   measured by running a compile-time loop nest until it died: an 8 MB stack
   carries a little over 4,000. The deepest legitimate nesting anywhere in
   this repository is 158, in the autodiff tests, so this leaves room for
   code far deeper than any that exists while ending a runaway in an error
   the compiler can report instead of a crash. */
#define LISP_CALL_DEPTH_MAX 1024
// Calls one compile-time evaluation may make before it is stopped. A loop
// that never ends makes calls without nesting any, so the depth budget above
// never sees it.
#define LISP_CALL_STEP_MAX 40000000

typedef struct LispLower {
  Lisp lisp;
  LispEnv *env;         // the call site that triggered analysis
  Lambda lambda;
  MachineBuilder b;
  int depth;            // macro expansions open on this path
  List scope_params;    // every live slot's name, in slot order
  int slots;            // inlined slots bound above the parameters
  Var slot_names[MACHINE_LOCAL_RESERVE];
} *LispLower;

/* Answers the frame slot the innermost inlined binding of `name` owns, or
   -1 when no inlined scope binds it. Later bindings sit at higher slots, so
   the downward scan finds the one that shadows. */
static int LispLower._auto_inlined_slot(LispLower l, Var name) {
  for (int i = l.slots - 1; i >= 0; i--)
    if (l.slot_names[i].u64 == name.u64)
      return l.lambda.params.len() + i;
  return -1;
}

static int _auto_param_index(Lambda lambda, Var name) {
  int index = -1, at = 0;
  for (List p = lambda.params; p; p = p.cdr(), at++)
    if (p.car() == name) index = at;  // last binding wins, like Map.set
  return index;
}

static int LispLower._auto_load_name(LispLower l, Var name) {
  int local = l._auto_inlined_slot(name);
  if (local < 0) local = _auto_param_index(l.lambda, name);
  if (local >= 0) return l.b.emit(MW_LLOCAL, local, 0, 0, 0, 0) >= 0;
  Var captured;
  if (l.lambda.captures.try_get(name, &captured)) {
    int constant = l.b.constant(captured);
    return constant >= 0 && l.b.emit(MW_LCAPTURE, constant, 0, 0, 0, 0) >= 0;
  }
  /* A frozen ancestor's binding cannot be replaced, so the value stands in
     for the read and no guard has to watch it. */
  Var inherited;
  if (_frozen_binding(l.lisp, name, &inherited))
    return l._auto_compile_constant(inherited);
  int constant = l.b.constant(name);
  if (constant < 0) return 0;
  return l.b.emit(MW_LGLOBAL, constant, 0, 0, 0, 0) >= 0;
}

static int LispLower._auto_local_name(LispLower l, Var name) =>
  l._auto_inlined_slot(name) >= 0 ||
  _auto_param_index(l.lambda, name) >= 0 ||
  name in l.lambda.captures;

static int LispLower._auto_compile_constant(LispLower l, Var value) {
  int constant = l.b.constant(value);
  return constant >= 0 && l.b.emit(MW_LCONST, constant, 0, 0, 0, 0) >= 0;
}

/* Only nil is false, so the branch tests for nil. */
static int LispLower._auto_compile_cond(LispLower l, List clauses,
                                        int tail) {
  MachineBuilder b = l.b;
  if (!clauses) return 0;
  int end_jumps[64], end_count = 0;
  foreach (Var clause, clauses) {
    if (clause is not <list> || List.len(clause) != 2)
      return 0;
    if (end_count >= 64) return 0;
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
    return 0;
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
      if (form.len() != 2) return 0;
      if (depth > 0) {
        if (!l._auto_compile_constant(%($head)) ||
            !l._auto_compile_qq(form.cdr(), 0, depth - 1, live + 1) ||
            !l._auto_qq_append())
          return 0;
        return !list || l._auto_qq_wrap();
      }
      if (!list && head == lsym_splicing)
        return 0;
      if (!l._auto_compile(argument, 0)) return 0;
      // Appending nil checks a splice before effects in the remaining forms.
      if (head == lsym_splicing)
        return l._auto_compile_constant(%()) && l._auto_qq_append();
      return !list || l._auto_qq_wrap();
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

/* Expand only through the effect-restricted evaluator. A declined expansion
   stays an ordinary runtime macro call; successful immutable syntax carries
   the bindings that must still hold when the compiled expansion executes. */
/* Drops the rows a frozen ancestor supplies. Those bindings are final for
   this session, so nothing has to re-check them at execution; an expansion
   whose every row drops needs no site guard at all. */
static List LispLower._auto_live_bindings(LispLower l, List bindings) {
  List live = NULL;
  foreach (List pair, bindings) {
    Var (name, expected) = pair;
    Var settled;
    if (_frozen_binding(l.lisp, name, &settled) &&
        settled.u64 == expected.u64)
      continue;
    live = cons(pair, live);
  }
  return live;
}

static int LispLower._auto_expand(LispLower l, Var head, List args,
                                  Var *expansion, List *dependencies) {
  Var value;
  if (!_lookup(l.lisp, l.env, head, &value) || value is not <lambda>) return 0;
  Lambda macro = value;
  if (!macro.macro) return 0;
  if (l.depth >= LISP_AUTO_EXPAND_MAX) return 0;
  /* The evaluator expands only the calls it reaches, so a macro call in a
     branch that never runs fails nowhere today. Analysis reaches every
     branch; keep its failures local by rejecting rather than raising. */
  LispExpansion trace = { %(( $head $value )), 0, 0 };
  try $let(l.lisp.expansion, &trace)
    *expansion = _call_lambda(l.lisp, macro, args);
  catch: return 0;
  if (!_expansion_value(*expansion, 0)) return 0;
  *dependencies = trace.dependencies;
  return 1;
}

/* Undo a declined attempt. Only LLAMBDA words own a callee, so the rewind
   frees those programs; constants intern in emission order, so every index
   the retained words name was added before the mark. */
static void LispLower._auto_rewind(
  LispLower l, int mark, int constants) {
  MachineBuilder b = l.b;
  for (int i = mark; i < b.length; i++)
    if (b.code[i].op == MW_LLAMBDA)
      _auto_discard(l.lisp, b.consts[b.code[i].a]);
  b.length = mark;
  b.const_count = constants;
}

/* A declined form runs through the evaluator in the current frame. Rewind
   its partial program before emitting that crossing; capacity failures still
   stop preparation of the whole body. */
static int LispLower._auto_compile(LispLower l, Var expression, int tail) {
  MachineBuilder b = l.b;
  int mark = b.length, constants = b.const_count;
  if (l._auto_lower(expression, tail)) return 1;
  if (b.status != MACHINE_PREPARED) return 0;
  l._auto_rewind(mark, constants);
  int constant = b.constant(expression);
  return constant >= 0 && b.emit(MW_LEVAL, constant, 0, 0, 0, 0) >= 0;
}

/* Lowers an immediately applied lambda literal, which is what `let` and the
   other binding macros expand to, into the frame it stands in. The arguments
   are expressions of the enclosing scope and are lowered there; MW_LBIND
   moves them into fresh slots above the parameters, the body reads those
   slots like parameters, and MW_LUNBIND drops them.

   A call is the alternative and is not available: the callee's free names
   are the enclosing frame's slots, which no callee can reach. Both words
   also rename the frame's slots, so a form that leaves the machine from
   inside the scope reads its bindings through the environment. */
static int LispLower._auto_compile_inline(
  LispLower l, List form, int tail) {
  MachineBuilder b = l.b;
  List literal = form.car(), args = form.cdr();
  List params = literal.cadr();
  int count = params.len();
  if (count != args.len() || l.slots + count > MACHINE_LOCAL_RESERVE)
    return 0;
  /* `lambda` is an ordinary binding and a program may rebind it. The site
     guard re-evaluates the whole form when it no longer names the lambda
     constructor, before any argument of this form has run. */
  Var expected = l.lisp.specials[LISP_LAMBDA];
  List live = l._auto_live_bindings(%(($lsym_lambda $expected)));
  int site = live ? b.constant(%($form $live)) : 0;
  if (site < 0) return 0;
  int guard = live ? b.emit(MW_LEXPAND, site, 0, 0, 0, -1) : 0;
  if (guard < 0) return 0;
  List scope = l.scope_params;
  foreach (Var name, params) {
    if (!name.is_atom()) return 0;
    scope = scope.append(cons(name, NULL));
  }
  int enter = count ? b.constant(scope) : 0;
  int leave = count ? b.constant(l.scope_params) : 0;
  if (enter < 0 || leave < 0) return 0;
  foreach (Var argument, args)
    if (!l._auto_compile(argument, 0)) return 0;
  if (count && b.emit(MW_LBIND, enter, count, 0, 0, 0) < 0) return 0;
  foreach (Var name, params) l.slot_names[l.slots++] = name;
  int ok;
  $let(l.scope_params, scope)
    ok = l._auto_compile(literal.caddr(), tail);
  l.slots -= count;
  if (!ok) {
    if (b.status == MACHINE_PREPARED) l.lisp.auto_stats.inline_declines++;
    return 0;
  }
  if (count && b.emit(MW_LUNBIND, leave, count, 0, 0, 0) < 0) return 0;
  if (live) b.set_target(guard, b.length);
  l.lisp.auto_stats.inlined_scopes++;
  return 1;
}

static int LispLower._auto_lower(LispLower l, Var expression, int tail) {
  MachineBuilder b = l.b;
  if (expression.is_atom()) return l._auto_load_name(expression);
  if (expression is not <list> || expression.is_nil())
    return l._auto_compile_constant(expression);
  List form = expression;
  Var (head, argument) = form;
  if (head is <list>) {
    List literal = head;
    if (literal.len() != 3 || literal.car() != lsym_lambda ||
        literal.cadr() is not <list>)
      return 0;
    return l._auto_compile_inline(form, tail);
  }
  /* A computed head, a head naming a runtime local, and the mutating,
     binding, and reflective special forms have no wordcode; each declines
     to MW_LEVAL. */
  if (!head.is_atom() || l._auto_local_name(head) ||
      head == lsym_def || head == lsym_bind || head == lsym_lambda ||
      head == lsym_macro || head == lsym_eval || head == lsym_import ||
      head == lsym_apply)
    return 0;
  if (head == lsym_quote || head == lsym_cond || head == lsym_quasiquote)
    return l._auto_compile_special(form, tail);
  Var expansion;
  List dependencies;
  if (l._auto_expand(head, form.cdr(), &expansion, &dependencies))
    $let(l.depth, l.depth + 1) {
      List live = l._auto_live_bindings(dependencies);
      int guard = live ? b.emit(MW_LEXPAND, 0, 0, 0, 0, -1) : 0;
      if (guard < 0 || !l._auto_compile(expansion, tail)) return 0;
      if (!live) return 1;
      int site = b.constant(%($form $live));
      if (site < 0) return 0;
      b.code[guard].a = site;
      b.set_target(guard, b.length);
      return 1;
    }
  if (!l._auto_load_name(head)) return 0;
  return l._auto_compile_call(form.cdr(), tail);
}

/* Earlier forms and call arguments may rebind a special. Check at the
   form's start: a miss evaluates only this untouched form,
   and a hit keeps its selected operation through effects inside that form. */
static int LispLower._auto_compile_special(LispLower l, List form, int tail) {
  Var (head, argument) = form;
  int special = head == lsym_quote ? LISP_QUOTE
              : head == lsym_cond ? LISP_COND : LISP_QUASIQUOTE;
  Var expected = l.lisp.specials[special];
  MachineBuilder b = l.b;
  List live = l._auto_live_bindings(%(($head $expected)));
  int site = live ? b.constant(%($form $live)) : 0;
  if (site < 0) return 0;
  int guard = live ? b.emit(MW_LEXPAND, site, 0, 0, 0, -1) : 0;
  if (guard < 0) return 0;
  int ok = 0;
  if (special == LISP_COND)
    ok = l._auto_compile_cond(form.cdr(), tail);
  else if (form.len() == 2)
    ok = special == LISP_QUOTE ? l._auto_compile_constant(argument)
                               : l._auto_compile_qq(argument, 0, 0, 0);
  if (!ok) return 0;
  if (live) b.set_target(guard, b.length);
  return 1;
}

static int LispLower._auto_compile_call(LispLower l, List args, int tail) {
  MachineBuilder b = l.b;
  int raw = b.constant(args);
  if (raw < 0) return 0;
  int precall = b.emit(MW_LPRECALL, raw, 0, 0, 0, -1);
  if (precall < 0) return 0;
  int argc = 0;
  foreach (Var arg, args) {
    if (argc >= LISP_AUTO_PARAM_MAX) return 0;
    if (!l._auto_compile(arg, 0)) return 0;
    argc++;
  }
  int op = tail ? MW_LTAILCALL : MW_LCALL;
  if (b.emit(op, 0, argc, 0, 0, 0) < 0) return 0;
  b.set_target(precall, b.length);
  return 1;
}

/* Only LLAMBDA constants own private callees. Other Lambda constants are
   borrowed captures, so discarding a failed compilation must leave them. */
static void _auto_discard_children(Lisp lisp, MachineView view) {
  for (int i = 0; i < view.length; i++)
    if (view.code[i].op == MW_LLAMBDA)
      _auto_discard(lisp, view.consts[view.code[i].a]);
}

static void _auto_discard(Lisp lisp, Lambda lambda) {
  if (lambda.auto_program) {
    _auto_discard_children(lisp, lambda.auto_program.view());
    lisp.auto_stats.program_bytes -= (long) lambda.auto_program.bytes();
    lambda.auto_program.free();
  }
  lambda.captures.cleanup();
  Scope.free(lambda);
}

static int _auto_analyze(
  Lisp lisp, Lambda lambda, LispEnv *env, int depth) {
  if (lambda.auto_status >= 0) return lambda.auto_status;
  /* A frozen session's lambda is only compiled by `Lisp.auto_prepare`,
     while the Context that owns the session is still current. Compiling one
     now would freeze this unit's constants into a program that outlives the
     unit, and `lib/machine.x` states that a program's constants do not own
     their pointees. The evaluator runs it instead, and the status is left
     unset so the next process can still prepare it. */
  if (lambda.owner && lambda.owner.frozen && lambda.owner != lisp)
    return MACHINE_INELIGIBLE;
  lisp.auto_stats.analyses++;
  /* Body fallback does not remove frame limits: a rest parameter has no
     fixed slot and the local frame is bounded. */
  int bindable = 1, param_count = 0;
  foreach (Var name, lambda.params) {
    if (name.is_atom() && name.str() == ".") {
      bindable = 0;
      break;
    }
    param_count++;
  }
  if (!bindable || param_count > LISP_AUTO_PARAM_MAX) {
    lambda.auto_status = MACHINE_INELIGIBLE;
    lisp.auto_stats.ineligible++;
    return lambda.auto_status;
  }
  $scope(&lambda.owner.scope) {
    MachineBuilder b = $auto(MachineBuilder.new());
    struct LispLower storage =
      { lisp, env, lambda, b, depth, lambda.params };
    LispLower lower = &storage;
    int ok = lower._auto_compile(lambda.body, 1) &&
             b.emit(MW_LRETURN, 0, 0, 0, 0, 0) >= 0;
    if (ok) {
      b.root = 0;
      lambda.auto_program = b.freeze();
      lambda.auto_status = MACHINE_PREPARED;
    }
    else
      lambda.auto_status = b.status == MACHINE_PREPARED
                         ? MACHINE_INELIGIBLE : b.status;
    if (lambda.auto_status == MACHINE_PREPARED) {
      lisp.auto_stats.published++;
      lisp.auto_stats.program_bytes += (long) lambda.auto_program.bytes();
    }
    else {
      _auto_discard_children(lisp, b.view());
      lisp.auto_stats.ineligible++;
    }

    return lambda.auto_status;
  }
}

/* Each dependency pairs a name with the value used while lowering a form.
   A mismatch makes that form use the evaluator at its execution site. */
static int _auto_bindings_ok(Lisp lisp, LispEnv *env, List bindings) {
  foreach (List pair, bindings) {
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
    /* The budgets raise the same cause from the machine as from the
       evaluator, so a caller reads one shape wherever it was stopped. */
    case %(call-stack (operation ?operation) (why ?why)):
      raise %(call-stack (operation $operation) (why $why));
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
  if (lisp.auto_disabled || lisp.expansion) return 0;
  lisp.auto_stats.invocations++;
  if (lambda.auto_calls < 2) lambda.auto_calls++;
  if (lambda.auto_calls < 2) return 0;
  if (lambda.auto_status < 0) {
    if (_auto_analyze(lisp, lambda, env, 0) != MACHINE_PREPARED)
      return 0;
  }
  else if (lambda.auto_status != MACHINE_PREPARED) {
    lisp.auto_stats.remembered_fallbacks++;
    return 0;
  }
  if (raw.len() != lambda.params.len() ||
      lisp.machine_depth >= LISP_MACHINE_NESTING_MAX) {
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
  m.open();
  /* Only a Lisp callback can raise out of the machine, and that leaves it
     marked running. Clear the flag ahead of the release below, so its
     `LispMachine.finish` never meets the `<bad-state>` guard. */
  defer m.running = 0;
  m.stats = lisp.auto_machine_stats;
  m.begin(lambda.auto_program.view(), context, argv, argc);
  /* The frame reads the machine's own slots, not the argument array `begin`
     copied from: a lowered binding scope opens slots above the parameters
     and names them for the evaluator. */
  _machine_env_set(context.frames, lambda, m.locals, argc, NULL);
  lisp.auto_stats.machine_entries++;
  m.run();
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

/** Sets how many calls one evaluation of `lisp` may make before it is
    stopped. `lisp` must be a live session and `budget` must be positive.
    The default is `LISP_CALL_STEP_MAX`, which is large enough that only a
    computation that does not end reaches it; a test sets a small one to
    reach it quickly.

    The budget belongs to the public entry. `Lisp.eval`, `Lisp.apply`, and
    `Lisp.eval_string` each open one, and a call that runs it out does not
    renew it, so one entry reports a runaway once however many calls follow.
*/
void Lisp.call_budget(Lisp lisp, long budget) {
  if (lisp && budget > 0) lisp.call_step_max = budget;
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

/** Word-compiles every lambda this session's globals name, in place.

    Call it while the `Context` that owns `lisp` is current and before any
    child session runs, so each program's frozen constants belong to that
    `Context`. Returns the number of lambdas that gained a program.

    A lambda a global holds indirectly, inside a `List` or a `Map` value, is
    not reached: the globals a library defines are the callables a child
    resolves by name, and those are what a shared program guards against.
*/
int Lisp.auto_prepare(Lisp lisp) {
  if (!lisp || lisp.auto_disabled) return 0;
  int prepared = 0;
  foreach (Var (name, value), lisp.globals) {
    (void) name;
    if (value is not <lambda>) continue;
    Lambda lambda = value;
    if (_auto_analyze(lisp, lambda, NULL, 0) == MACHINE_PREPARED)
      prepared++;
  }
  return prepared;
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
  _expansion_native(lisp, function);
  /* The wide path materializes a values List; the narrow one need not. */
  if (raw.len() <= LISP_NATIVE_ARG_MAX) {
    FuncArg argv[LISP_NATIVE_ARG_MAX];
    unsigned argc = 0;
    foreach (Var arg, raw) {
      Var value = _eval(lisp, arg, env);
      _expansion_argument(lisp, value);
      argv[argc++] = FuncArg.value(value);
    }
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
    return _call_lambda(lisp, lambda, values);
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
  _expansion_native(lisp, function);
  int count = values.len();
  FuncArg narrow[LISP_NATIVE_ARG_MAX];
  FuncArg *argv = count <= LISP_NATIVE_ARG_MAX
                ? narrow : Scope.malloc(count * sizeof(FuncArg));
  unsigned argc = 0;
  foreach (Var value, values) {
    _expansion_argument(lisp, value);
    argv[argc++] = FuncArg.value(value);
  }
  return function.apply(argc, argv);
}

static Var _eval(Lisp lisp, Var expression, LispEnv *env) {
  if (lisp.expansion && ++lisp.expansion.steps > MACHINE_CODE_MAX * 4)
    _expansion_decline();
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

/* Opens one budget. Only a public entry does this: a call that runs out
   raises, and whoever catches that raise continues under the same exhausted
   budget rather than a fresh one, so one runaway reports once. */
static void _open_call_budget(Lisp lisp) {
  lisp.call_steps = 0;
  lisp.call_exhausted = 0;
}

/** Evaluates one Lisp form in `lisp`.
    Evaluation is synchronous and may retain the expression or values it
    reaches in session globals, Lambdas, or captures as described by the module
    ownership rule. Effects completed before a later failure are not rolled
    back. Raises: `<bad-arg>` for a null session, or any evaluator, imported
    operation, or called-procedure cause.
*/
$lisp.entry("Lisp.eval")
Var Lisp.eval(Lisp lisp, Var expression) {
  _open_call_budget(lisp);
  return _eval(lisp, expression, NULL);
}

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
Var Lisp.apply(Lisp lisp, Var callable, List values) {
  _open_call_budget(lisp);
  return _apply_values(lisp, callable, values, NULL);
}

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
  _open_call_budget(lisp);
  Scope tokens_scope = $auto(Scope.new_named("Lisp tokens"));
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
  Block content = $auto(Block.new(sizeof(char)));
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
  lisp && name && out && _global_lookup(lisp, Atom.intern(name), out);

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
  if (lisp.frozen)
    raise %(bad-state (operation "Lisp.set_global") (why "frozen"));

  $scope(&lisp.scope) {
    Var interned = Atom.intern(name);
    if (_inherited(lisp, interned))
      raise %(bad-state (operation "Lisp.set_global") (why "inherited")
                        (name $interned));
    lisp.globals[interned] = value;
    if (name.startswith("x2c.")) lisp.protect_x2c = 1;
  }
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
  lisp.set_global(name, function);
}

/** Ends the owned lifetime when a managed local leaves its block. */
void Lisp.cleanup(Lisp value) { value.destroy(); }
