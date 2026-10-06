/*  lisp.x -- the Lisp runtime: reader, session, and evaluator

    Copyright (c) 2026 Gary William Flake.

    Lisp owns embedded compile-time Lisp sessions: the reader, the evaluator,
    and each session's global environment. Lambdas and natives receive their
    arguments evaluated left to right, macros and special forms receive them
    raw, nil is the only false value, and a Lambda captures by value the free
    locals its body reads. Names are canonical Atoms, and `bind` reaches
    native operations through the table that lisp-targets.x builds.

    The session Scope owns the Lisp record, its Maps, Lambdas, and bound Func
    storage, which hold Vars by value without cloning their referents. Those
    referents keep their own pool or caller owners and must outlive every
    session entry that refers to them. A session is not synchronized: its
    caller serializes evaluation and destroys it only after every call has
    returned.
*/

#pragma once

#include "private-keywords.x"
#include "cleanup.x"
#include "x2c.x"
#include "macro-value.x"

/** Reads one exact C scalar from `bytes`; a wide result is boxed in
    `owner`. */
typedef Var (*NativeScalarLoad)(const void *bytes, Scope *owner);
/** Writes `value`, converted to one exact C scalar type, to `bytes`. */
typedef void (*NativeScalarStore)(void *bytes, Var value);
/** Describes one exact C scalar type in native bytes: its Var tag, size,
    alignment, load, and store. Compile-time code that keeps C objects in
    bytes, and the compiler's layouts, select a row with
    `native_scalar_access`. */
typedef struct NativeScalarAccess {
  Symbol tag;
  size_t size, alignment;
  NativeScalarLoad load;
  NativeScalarStore store;
} *NativeScalarAccess;

#include "native-scalar-types.x"
$native.scalar.access.all();

static Map native_scalars = %{ ${$native.scalar.access.entries()} };

/** Returns the access record for an exact C scalar type such as
    `(unsigned long)`, or NULL for any other type. */
NativeScalarAccess native_scalar_access(List exact_type) =>
  native_scalars.getdefault(exact_type, NULL).pointer();

/** Represents one isolated embedded `Lisp` session.
    Create it with `Lisp.new` or `Lisp.kernel` and end it with
    `Lisp.destroy`. The module header describes its owned and borrowed state.
    A session is mutable and requires caller serialization.
*/
typedef struct Lisp *Lisp;

macro Expression $lisp._standard.source() =>
  $(x2c.literal.string (x2c.embed.text "../etc/init.xlisp"));

$cleanup.by(Lisp, destroy);

#include "meta.x"

/* Lisp form error conditions. Runtime operands retain their original
   detail types, order and source helper ownership. */

static macro Stmt $error.eval.void() {
  raise %(void-op (operation "eval"));
}

static macro Stmt $error.eval.unbound(Expr $expr) {
  raise %(unbound (name ${$expr}));
}

static macro Stmt $error.call.type(Expr $callable) {
  raise %(not-call (actual ${$callable.kind()}));
}

static macro Stmt $error.def.arity(Expr $actual, Expr $args) {
  raise %(bad-arity (operation "def") (expected 2) (actual ${$actual})
          (value ${$args}));
}

static macro Stmt $error.def.protected(Expr $name) {
  raise %(bad-state (operation "def") (name ${$name}));
}

static macro Stmt $error.def.inherited(Expr $name) {
  raise %(bad-state (operation "def") (reason "inherited") (name ${$name}));
}

static macro Stmt $error.def.frozen(Expr $name) {
  raise %(bad-state (operation "def") (reason "frozen") (name ${$name}));
}

static macro Stmt $error.cond.empty() {
  raise %(bad-arity (operation "cond") (expected 1) (actual 0));
}

static macro Stmt $error.cond.type(Expr $clause) {
  raise %(bad-types (operation "cond") (value ${$clause}) (want "List"));
}

static macro Stmt $error.cond.arity(Expr $actual, Expr $clause) {
  raise %(bad-arity (operation "cond-clause") (expected 2)
          (actual ${$actual}) (value ${$clause}));
}

static macro Stmt $error.bind.signature(Expr $signature) {
  raise %(bad-sig (operation "bind") (value ${$signature}));
}

static macro Stmt $error.bind.missing(Expr $name, Expr $sig) {
  raise %(no-symbol (name ${$name}) (sig ${$sig}));
}

static macro Stmt $error.quote.shape(Expr $expr) {
  raise %(bad-arity (operation "quasiquote") (value ${$expr}));
}

static macro Stmt $error.splice.type(Expr $value) {
  raise %(bad-types (operation "quasiquote-splice")
          (actual ${$value.kind()}));
}

static macro Stmt $error.lambda.signature(Expr $operation, Expr $args) {
  raise %(bad-sig (operation ${$operation}) (value ${$args}));
}

static macro Stmt $error.apply.void(Expr $index) {
  raise %(void-op (operation "apply") (index ${$index}));
}

static macro Stmt $error.apply.rest(Expr $body) {
  raise %(bad-sig (operation "apply") (value ${$body}));
}

static macro Stmt $error.apply.arity(Expr $body) {
  raise %(bad-arity (operation "apply") (value ${$body}));
}

static macro Stmt $error.apply.interrupted() {
  raise %(interrupt (operation "apply"));
}

static macro Stmt $error.apply.steps() {
  raise %(call-stack (operation "apply") (reason "steps"));
}

static macro Stmt $error.apply.stack(Expr $body) {
  raise %(call-stack (operation "apply") (value ${$body}));
}

static macro Stmt $error.form.arity(
  Expr $operation, Expr $expected, Expr $actual) {
  raise %(bad-arity (operation ${$operation}) (expected ${$expected})
          (actual ${$actual}));
}

static macro Stmt $error.form.string(Expr $operation, Expr $value) {
  raise %(bad-types (operation ${$operation}) (actual ${$value.kind()})
          (want "String"));
}

static macro Stmt $error.apply.list(Expr $values) {
  raise %(bad-types (operation "apply") (actual ${$values.kind()})
          (want "List"));
}

static macro Stmt $error.apply.procedure(Expr $callable) {
  raise %(not-call (operation "apply") (actual ${$callable.kind()}));
}

/* Lisp session error conditions. Runtime operands retain their original
   detail types, order and source helper ownership. */

static macro Stmt $error.callback.absent(Expr $operation) {
  raise %(bad-state (operation ${$operation}) (reason "no session"));
}

static macro Stmt $error.callback.wrong(Expr $operation) {
  raise %(bad-state (operation ${$operation}) (reason "wrong session"));
}

static macro Stmt $error.entry.null(Expr $operation) {
  raise %(bad-arg (operation ${$operation}));
}

static macro Stmt $error.global.args() {
  raise %(bad-arg (operation "Lisp.set_global"));
}

static macro Stmt $error.global.frozen() {
  raise %(bad-state (operation "Lisp.set_global") (reason "frozen"));
}

static macro Stmt $error.bind.args() {
  raise %(bad-arg (operation "Lisp.bind"));
}

static macro Stmt $error.source.callable(Expr $callable) {
  raise %(bad-types (operation "lisp_source_function") (want "Lambda")
          (actual ${$callable.kind()}));
}

#include <signal.h>

// session state

static enum LispSpecial {
  LISP_BIND, LISP_EVAL, LISP_QUOTE, LISP_COND, LISP_DEF,
  LISP_LAMBDA, LISP_MACRO, LISP_QUASIQUOTE, LISP_IMPORT,
  LISP_APPLY, LISP_SPECIAL_COUNT
};

/* Environment records are activation-local. A rest activation's `bindings`
   is a temporary frame-owned Map, while the captured pseudo-frame aliases
   its Lambda's session-owned capture Map. Parameter names, captured
   Vars, argument arrays, and parent records are borrowed for the activation,
   and the environment records stay on the C stack until the call returns. */
static typedef struct LispEnv {
  Map bindings, List params;
  const Var *values;
  int value_count, struct LispEnv *parent;
} LispEnv;

static struct Lisp {
  Scope scope;          // semantic session scope
  /* The slot user code allocates in while the session evaluates. Code that
     retains, releases, pushes, or pops a Scope acts on this slot, so it
     never frees evaluator bindings or session state, which name `scope`
     explicitly. */
  Scope user;
  Scope *automatic_owner, *result_owner;
  /* A session may read a parent's globals, reserved names and special
     forms. The parent holds definitions built once, before any child
     exists. Lisp definitions cannot replace inherited names. A host
     binding shadows a name only in the child that receives it.
     A parent outlives every child that names it. */
  Lisp parent;
  /* Set once the parent is complete. Nothing a child does may produce a
     value the parent reaches, because a child's values belong to a
     narrower Context than the parent's. */
  int frozen;
  Map globals;          // global bindings, Lisp name -> value
  Map reserved;         // reserved special forms, Lisp name -> <func> Var
  Func specials[LISP_SPECIAL_COUNT];
  int call_depth;       // evaluator calls nested on this session
  unsigned long stack_base; // C stack address at the outermost call
  unsigned long stack_allowance; // bytes below stack_base calls may use
  Lambda tail_lambda;   // a tail call waiting for its caller's frame
  Var *tail_values;     // its evaluated arguments, owned by the session
  int tail_count;
  /* Calls made by the evaluation in progress. Each outer entry resets the
     count, so a long translation spends one budget per entry. */
  long call_steps;
  /* The budget ran out or evaluation was interrupted, and no call may renew
     it until the public entry that opened it returns. `Lisp.set_interrupted`
     may set it from a signal handler. */
  volatile sig_atomic_t call_exhausted;
  long call_step_max;   // calls one evaluation may make
  volatile sig_atomic_t interrupted; // stops every call until cleared
  int protect_x2c;      // compiler SDK installed; x2c.* cannot be redefined
};

/* Native value bindings may adapt an interpreted callable to Func. Public
   entries set this thread-local for the whole evaluation. Nested entries
   restore their caller. */
static threaded Lisp lisp_active;

/* The Lambda record and capture Map storage belong to the session Scope.
   Parameter and body Lists and captured Var referents are borrowed: capture
   copies Var identity, not the referenced object or canonical graph. Their
   owners must outlive the Lambda. */
static typedef struct Lambda {
  List params;
  Var body;
  Map captures;
  int macro, source_function;
} *Lambda;

#include "var-adapters.x"
$var.pointer(Lambda, lambda, <lambda>);

static protocol Var(Lambda);

/* canonical names

   The reader and evaluator share one canonical value per special-form and
   reader-prefix name, interned once per process. A long name is promoted to
   the outermost String pool, so it outlives the pool that interned it. */

static Var lsym_quote, lsym_quasiquote, lsym_unquote, lsym_splicing;
static Var lsym_cond, lsym_def, lsym_bind, lsym_eval, lsym_lambda;
static Var lsym_macro, lsym_import, lsym_apply;
static pthread_once_t lisp_initialize_once =
  (pthread_once_t) PTHREAD_ONCE_INIT;
static int lisp_initialize_success;

static typedef struct LispCanonicalName {
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

static int _initialize(void) {
  if (pthread_once(&lisp_initialize_once, _initialize_once)) {
    fprintf(stderr, "Lisp: could not initialize canonical names\n");
    abort();
  }
  return lisp_initialize_success;
}

/* evaluation

   A name evaluates to its binding, and every other value except a nonempty
   List evaluates to itself. A List is a call: its head is evaluated first,
   then a lambda or native receives evaluated arguments and a macro or
   special form receives the raw forms. */

static Var Lisp._eval(Lisp lisp, Var expr, LispEnv *env) {
  if (expr is void) $error.eval.void();
  if (expr.is_atom()) {
    Var value;
    if (!lisp._lookup(env, expr, value)) $error.eval.unbound(expr);
    return value;
  }
  if (expr is not <list> || expr.is_nil()) return expr;
  List form = expr;
  Var callable = lisp._eval(form.car(), env);
  return lisp._apply(callable, form.cdr(), env);
}

/* Native calls this wide evaluate into a stack array; wider ones take one
   scope allocation. Func itself has no arity limit. */
#define LISP_NATIVE_ARG_MAX  8

/* A native call's arguments are evaluated here, left to right. Its `defer`
   lowers to a `sigsetjmp` exception frame, which keeps a helper from being
   inlined, so a separate native-call step would add a C frame to every
   nested call. */
static Var Lisp._apply(Lisp lisp, Var callable, List raw, LispEnv *env) {
  if (callable is <lambda>) return lisp._apply_lambda(callable, raw, env);
  if (callable is not <func>) $error.call.type(callable);
  Func fn = (Func) callable.pointer();
  int special = lisp._special_id(fn);
  if (special >= 0) return lisp._apply_special(special, raw, env);
  int count = raw.len();
  FuncArg narrow[LISP_NATIVE_ARG_MAX];
  FuncArg *argv = count <= LISP_NATIVE_ARG_MAX
    ? narrow : Scope.malloc_in(&lisp.scope, count * sizeof(FuncArg));
  defer if (argv != narrow) Scope.free(argv);
  unsigned argc = 0;
  foreach (Var arg, raw) argv[argc++] = FuncArg.value(lisp._eval(arg, env));
  return fn.apply(argc, argv);
}

/* The special form whose reserved Func is `function`, compared by
   identity, or -1 for any other Func. */
static int Lisp._special_id(Lisp lisp, Func fn) {
  for (int i = 0; i < LISP_SPECIAL_COUNT; i++)
    if (lisp.specials[i] == fn) return i;
  return -1;
}

/* Applies `callable` to evaluated `values`. A macro, or a special form other
   than `apply`, is not a procedure. */
static Var Lisp._apply_values(
  Lisp lisp, Var callable, List values, LispEnv *env) {
  if (callable is <lambda>) {
    Lambda lambda = callable;
    if (lambda.macro) _not_procedure(callable);
    return lisp._call_lambda(lambda, values);
  }
  if (callable is not <func>) $error.call.type(callable);
  Func fn = (Func) callable.pointer();
  int special = lisp._special_id(fn);
  if (special < 0) return lisp._call_native(fn, values);
  if (special != LISP_APPLY) _not_procedure(callable);
  _arity(values, 2, "apply");
  List rest = _list_argument(values.cadr());
  return lisp._apply_values(values.car(), rest, env);
}

static Var Lisp._call_native(Lisp lisp, Func fn, List values) {
  int count = values.len();
  FuncArg narrow[LISP_NATIVE_ARG_MAX];
  FuncArg *argv = count <= LISP_NATIVE_ARG_MAX
    ? narrow : Scope.malloc_in(&lisp.scope, count * sizeof(FuncArg));
  defer if (argv != narrow) Scope.free(argv);
  unsigned argc = 0;
  foreach (Var value, values) argv[argc++] = FuncArg.value(value);
  return fn.apply(argc, argv);
}

/* special forms

   A special form receives its argument forms unevaluated and evaluates only
   the ones its rule selects. Each form checks its own shape first. */

static Var Lisp._apply_special(Lisp lisp, int id, List args, LispEnv *env) {
  switch (id) {
    case LISP_QUOTE:      return _special_quote(args);
    case LISP_DEF:        return lisp._special_def(args, env);
    case LISP_COND:       return lisp._special_cond(args, env);
    case LISP_LAMBDA:     return lisp._make_lambda(args, env, 0);
    case LISP_MACRO:      return lisp._make_lambda(args, env, 1);
    case LISP_QUASIQUOTE: return lisp._special_quasiquote(args, env);
    case LISP_EVAL:       return lisp._special_eval(args, env);
    case LISP_BIND:       return lisp._special_bind(args, env);
    case LISP_APPLY:      return lisp._special_apply(args, env);
  }
  return lisp._special_import(args, env);
}

static Var _special_quote(List args) {
  _arity(args, 1, "quote");
  return args.car();
}

/* `def` writes a session global and returns its value. */
static Var Lisp._special_def(Lisp lisp, List args, LispEnv *env) {
  Var (name, form) = args;
  if (args.len() != 2 || !name.is_atom()) {
    int actual = args.len();
    $error.def.arity(actual, args);
  }
  if (lisp.protect_x2c && name.str().startswith("x2c."))
    $error.def.protected(name);
  if (lisp._inherited(name))
    $error.def.inherited(name);
  /* A frozen session is complete, and a value produced now belongs to a
     narrower Context than it does, so the binding would outlive what it
     names. A child session is where a later definition goes. */
  if (lisp.frozen)
    $error.def.frozen(name);
  Var value = lisp._eval(form, env);
  _binding_set(&lisp.scope, lisp.globals, name, value);
  return value;
}

static Var Lisp._special_cond(Lisp lisp, List args, LispEnv *env) {
  Var form = lisp._cond_select(args, env);
  if (form is void) return %();
  return lisp._eval(form, env);
}

/* The result form of the first `cond` clause whose test holds, or `void`
   when none does. A clause's form comes from a List, so it is never
   `void`. */
static Var Lisp._cond_select(Lisp lisp, List args, LispEnv *env) {
  if (!args) $error.cond.empty();
  foreach (Var clause, args) {
    Var (test, form) = _cond_clause(clause);
    if (lisp_truth(lisp._eval(test, env))) return form;
  }
  return void;
}

/* A clause is a List of a test and a result form. */
static List _cond_clause(Var clause) {
  if (clause is not <list>)
    $error.cond.type(clause);
  List pair = clause;
  if (pair.len() != 2) {
    int actual = pair.len();
    $error.cond.arity(actual, clause);
  }
  return pair;
}

static Var Lisp._special_quasiquote(Lisp lisp, List args, LispEnv *env) {
  _arity(args, 1, "quasiquote");
  return lisp._qq(args.car(), env, 0);
}

/* `eval` evaluates its argument, then evaluates that form globally. */
static Var Lisp._special_eval(Lisp lisp, List args, LispEnv *env) {
  _arity(args, 1, "eval");
  return lisp._eval(lisp._eval(args.car(), env), NULL);
}

/* `bind` finds a native target by name. The target carries its own
   signature, so the given one is checked for shape only. */
static Var Lisp._special_bind(Lisp lisp, List args, LispEnv *env) {
  _arity(args, 2, "bind");
  Var (name_form, signature_form) = args;
  Var name = lisp._eval(name_form, env);
  Var signature = lisp._eval(signature_form, env);
  _string_argument(name, "bind");
  if (signature is not <list>)
    $error.bind.signature(signature);
  String native_name = name, List native_signature = signature;
  Func fn = _native_target(native_name);
  if (!fn) $error.bind.missing(native_name, native_signature);
  return fn;
}

static Var Lisp._special_apply(Lisp lisp, List args, LispEnv *env) {
  _arity(args, 2, "apply");
  Var (callable_form, values_form) = args;
  Var callable = lisp._eval(callable_form, env);
  Var values = lisp._eval(values_form, env);
  return lisp._apply_values(callable, _list_argument(values), env);
}

/* `import` hands its path to the `_x2c.import-hook` global when one is
   bound, and otherwise evaluates the file. */
static Var Lisp._special_import(Lisp lisp, List args, LispEnv *env) {
  _arity(args, 1, "import");
  Var path = lisp._eval(args.car(), env);
  _string_argument(path, "import");
  Var hook;
  if (lisp._global_lookup(Atom.intern("_x2c.import-hook"), hook))
    return lisp.apply(hook, %($path));
  File source = $auto(File.open(path, "r"));
  return lisp.eval_file(source);
}

/* quasiquote

   A quasiquoted form is data except where an unquote reaches depth zero.
   Each nested quasiquote adds a level and each unquote removes one. */

/* The value of quasiquoted `expr`. A List's element contributes its value,
   or at depth zero an unquote-splicing contributes the elements it
   evaluates to. */
static Var Lisp._qq(Lisp l, Var expr, LispEnv *env, int depth) {
  if (expr is not <list> || expr.is_nil()) return expr;
  List form = expr;
  Var head = form.car();
  if (head == lsym_quasiquote)
    return head.cons(l._qq_elements(form.cdr(), env, depth + 1));
  if (head != lsym_unquote && head != lsym_splicing)
    return l._qq_elements(form, env, depth);
  if (form.len() != 2)
    $error.quote.shape(expr);
  if (depth > 0) return head.cons(l._qq_elements(form.cdr(), env, depth - 1));
  Var value = l._eval(form.cadr(), env);
  if (head == lsym_splicing)
    $error.splice.type(expr);
  return value;
}

/* Walk siblings as elements, never as another headed quoted form. */
static List Lisp._qq_elements(Lisp lisp, List items, LispEnv *env, int depth) {
  Array values = $auto([]);
  foreach (Var item, items) {
    if (!depth && _is_splice(item))
      foreach (Var value, lisp._splice(item, env)) values.push(value);
    else values.push(lisp._qq(item, env, depth));
  }
  return values;
}

static int _is_splice(Var expr) =>
  expr is <list> && !expr.is_nil() && expr.car() == lsym_splicing;

static List Lisp._splice(Lisp lisp, Var expr, LispEnv *env) {
  List form = expr;
  if (form.len() != 2)
    $error.quote.shape(expr);
  Var value = lisp._eval(form.cadr(), env);
  if (value is not <list>)
    $error.splice.type(value);
  return value;
}

/* closures

   A Lambda captures, when it is made, local values its body may read.
   Mutable global or unknown callables may later evaluate current data, so
   those forms retain possible reads too. A name bound nowhere in the
   defining environment is read from the session globals at each call. */

static Var Lisp._make_lambda(Lisp lisp, List args, LispEnv *env, int macro) {
  if (args.len() != 2 || args.car() is not <list>) {
    Symbol operation = macro ? <macro> : <lambda>;
    $error.lambda.signature(operation, args);
  }
  Lambda lambda = Scope.malloc_in(&lisp.scope, sizeof(struct Lambda));
  Var result = void;
  defer if (result is void) Scope.free(lambda);
  (List params, Var body) = args;
  *lambda = (struct Lambda) {.params = params, .body = body, .macro = macro};
  if (env) {
    $scope(&lisp.scope) lambda.captures = {};
    lisp._capture(env, lambda);
  }
  return result = lambda;
}

static void Lisp._capture(Lisp lisp, LispEnv *env, Lambda lambda) {
  Array names = $auto([]);
  FreeNames walk = {lisp, env, names};
  walk.form(lambda.body, lambda.params, 0);
  foreach (Var name, names) {
    Var value;
    if (name in lambda.captures) continue;
    if (env._lookup(name, value))
      _binding_set(&lisp.scope, lambda.captures, name, value);
  }
}

/* One capture analysis: the session and environment that resolve call
   heads, and the free names found so far. */
static typedef struct FreeNames {
  Lisp lisp, LispEnv *env, Array out;
} FreeNames;

/* A captured local callable keeps its identity. Global, parameter and
   computed heads may change which operands evaluate, so their operands
   retain all possible local reads. Negative depth marks that possibility;
   zero is an evaluated position and positive depth is quasiquote data.
   Stable special identities preserve quote opacity and inner binders. */
static void FreeNames.form(FreeNames &f, Var form, List bound, int depth) {
  if (form.is_atom()) {
    if (depth <= 0 && !_param_has(bound, form)) f.out.push(form);
    return;
  }
  if (form is not <list>) return;
  List items = form;
  if (!items) return;
  if (depth < 0) f.all(items, bound, depth);
  else if (depth > 0) f.quoted(items, bound, depth);
  else f.call(items, bound);
}

static void FreeNames.all(FreeNames &f, List items, List bound, int depth) {
  foreach (Var part, items) f.form(part, bound, depth);
}

static void FreeNames.quoted(FreeNames &f, List items, List bound, int depth) {
  int inner = _quote_depth(items.car(), depth);
  f.all(inner >= 0 ? items.cdr() : items, bound, inner >= 0 ? inner : depth);
}

/* The head is an evaluated position, and what it names decides how its
   operands are read. */
static void FreeNames.call(FreeNames &f, List items, List bound) {
  Var head = items.car(), callable;
  f.form(head, bound, 0);
  if (!head.is_atom() || _param_has(bound, head) ||
      !f.env._lookup(head, callable)) {
    f.all(items.cdr(), bound, -1);
    return;
  }
  int special = callable is <func>
    ? f.lisp._special_id((Func) callable.pointer()) : -1;
  if (special == LISP_QUOTE) return;
  if (special == LISP_LAMBDA || special == LISP_MACRO) {
    List rest = items.cdr(), params = _with_params(bound, rest);
    f.all(rest.cdr(), params, 0);
    return;
  }
  int inner = special == LISP_QUASIQUOTE ? 1 :
    callable is <lambda> && ((Lambda) callable).macro ? -1 : 0;
  f.all(items.cdr(), bound, inner);
}

/* The quasiquote depth below a form headed by `head`, or -1 when `head`
   leaves it unchanged. */
static int _quote_depth(Var head, int depth) {
  if (head == lsym_quasiquote) return depth + 1;
  if (head == lsym_unquote || head == lsym_splicing)
    return depth ? depth - 1 : 0;
  return -1;
}

/* `bound` with the parameters of an inner `lambda` or `macro` form. */
static List _with_params(List bound, List rest) {
  if (rest && rest.car() is <list>)
    foreach (Var name, (List) rest.car()) bound = cons(name, bound);
  return bound;
}

static int _param_has(List params, Var name) {
  foreach (Var param, params) if (param == name) return 1;
  return 0;
}

/* calls

   A call evaluates its arguments into an array and runs its Lambda in an
   activation frame. Positional parameters read that array; a rest
   parameter is bound in the frame to a List of the values. */

static Var Lisp._apply_lambda(Lisp l, Lambda lambda, List raw, LispEnv *env) {
  if (lambda.macro) return l._eval(l._call_lambda(lambda, raw), env);
  int count = raw.len(), index = 0;
  Var *values = Scope.malloc_in(&l.scope, (count + 1) * sizeof(Var));
  defer Scope.free(values);
  foreach (Var form, raw) values[index++] = l._eval(form, env);
  return l._call_lambda_slots(lambda, values, count);
}

static Var Lisp._call_lambda(Lisp lisp, Lambda lambda, List args) {
  int count = args.len(), index = 0;
  Var *values = Scope.malloc_in(&lisp.scope, (count + 1) * sizeof(Var));
  defer Scope.free(values);
  foreach (Var value, args) values[index++] = value;
  return lisp._call_lambda_slots(lambda, values, count);
}

/* Calls `lambda` and then each tail call its body leaves pending, in one
   C frame. Nesting is bounded by the C stack it uses, not by a count. */
static Var Lisp._call_lambda_slots(
  Lisp lisp, Lambda lambda, const Var *values, int count) {
  lisp._spend_call();
  lisp._check_stack(lambda, (unsigned long) __builtin_frame_address(0));
  lisp.call_depth++;
  defer lisp.call_depth--;
  Var *owned = NULL;
  defer if (owned) Scope.free(owned);
  for (;;) {
    Var result = lisp._run_frame(lambda, values, count);
    if (!lisp.tail_lambda) return result;
    lambda = lisp.tail_lambda;
    lisp.tail_lambda = NULL;
    if (owned) Scope.free(owned);
    values = owned = lisp.tail_values;
    count = lisp.tail_count;
    lisp._spend_call();
  }
}

/* Runs one activation of `lambda`. In tail position it may leave a pending
   call on `lisp` instead of making it; `Lisp._call_lambda_slots` runs that
   call after this frame is gone. */
static Var Lisp._run_frame(
  Lisp lisp, Lambda lambda, const Var *values, int count) {
  Scope frame = $auto((Scope) NULL);
  /* A free name the lambda did not capture is a global. The environment the
     call was written in is not a parameter here, so a caller's binding
     cannot change what the body reads. */
  LispEnv captured = {.bindings = lambda.captures, .parent = NULL};
  LispEnv local = {.parent = &captured};
  if (Atom.intern(".") in lambda.params) {
    $scope(&frame) { local.bindings = {}; }
    _bind_params(&frame, lambda, _value_list(values, count), local.bindings);
  }
  else local._bind_values(lambda, values, count);
  if (lambda.source_function)
    return lisp._run_source(lambda.body, &local, &frame);
  return lisp._eval_tail(lambda.body, &local);
}

/* The argument values as a List, which cannot hold `void`. */
static List _value_list(const Var *values, int count) {
  List args = NULL;
  for (int i = count - 1; i >= 0; i--) {
    if (values[i] is void) $error.apply.void(i);
    args = cons(values[i], args);
  }
  return args;
}

/* Binds each name before `.` to one value and the name after it to the
   rest. */
static void _bind_params(
  Scope *frame, Lambda lambda, List args, Map bindings) {
  Var body = lambda.body;
  for (List p = lambda.params; p; p = p.cdr()) {
    Var name = p.car();
    if (name.is_atom() && name.str() == ".") {
      if (!p.cdr()) $error.apply.rest(body);
      _binding_set(frame, bindings, p.cadr(), args);
      return;
    }
    if (!args) $error.apply.arity(body);
    _binding_set(frame, bindings, name, args.car());
    args = args.cdr();
  }
  if (args) $error.apply.arity(body);
}

static void LispEnv._bind_values(
  LispEnv *local, Lambda lambda, const Var *values, int count) {
  if (count != lambda.params.len())
    $error.apply.arity(lambda.body);
  local.params = lambda.params;
  local.values = values;
  local.value_count = count;
}

/* A lowered source function owns its automatic storage in the frame. A
   record it returns is copied into its caller's storage before the frame
   ends. */
static Var Lisp._run_source(Lisp lisp, Var body, LispEnv *env, Scope *frame) {
  Scope *caller_owner = lisp.automatic_owner;
  Scope *caller_result_owner = lisp.result_owner;
  defer {
    lisp.automatic_owner = caller_owner;
    lisp.result_owner = caller_result_owner;
  }
  lisp.result_owner = caller_owner;
  lisp.automatic_owner = frame;
  return lisp._eval(body, env);
}

/* tail calls

   A call to an evaluator lambda in tail position does not nest. Its
   arguments are evaluated and the call is left on the session for
   `Lisp._call_lambda_slots`, which runs it in place of the frame that made
   it. */

/* Evaluates `expr` as the last act of the running frame. A macro's
   expansion and a `cond`'s selected form stay in tail position. */
static Var Lisp._eval_tail(Lisp lisp, Var expr, LispEnv *env) {
  for (;;) {
    if (expr is not <list> || expr.is_nil()) return lisp._eval(expr, env);
    List form = expr;
    Var callable = lisp._eval(form.car(), env);
    List raw = form.cdr();
    if (callable is <func> &&
        lisp._special_id((Func) callable.pointer()) == LISP_COND) {
      expr = lisp._cond_select(raw, env);
      if (expr is void) return %();
      continue;
    }
    if (callable is not <lambda>) return lisp._apply(callable, raw, env);
    Lambda lambda = callable;
    if (lambda.source_function) return lisp._apply_lambda(lambda, raw, env);
    if (!lambda.macro) return lisp._tail_call(lambda, raw, env);
    expr = lisp._call_lambda(lambda, raw);
  }
}

/* Evaluates the arguments of a tail call and leaves the call on `lisp`. */
static Var Lisp._tail_call(Lisp lisp, Lambda lambda, List raw, LispEnv *env) {
  int count = raw.len(), index = 0;
  Var *values = Scope.malloc_in(&lisp.scope, (count + 1) * sizeof(Var));
  int pending = 0;
  defer if (!pending) Scope.free(values);
  foreach (Var argument, raw) values[index++] = lisp._eval(argument, env);
  pending = 1;
  lisp.tail_lambda = lambda;
  lisp.tail_values = values;
  lisp.tail_count = count;
  return void;
}

/* name lookup

   A name resolves in the activation frames from the innermost out, which
   end at the Lambda's captures, then in the session globals, then in the
   reserved forms. Within one frame the last duplicate parameter wins, and
   parameters precede the frame's Map bindings. A global may shadow a
   special form without mutating the reserved Map. */

static int Lisp._lookup(Lisp lisp, LispEnv *env, Var name, Var &out) =>
  env._lookup(name, out) || lisp._global_lookup(name, out) ||
  lisp._reserved_lookup(name, out);

/* Captures are the values the Lambda was made with and do not change
   afterwards. */
static int LispEnv._lookup(LispEnv *env, Var name, Var &out) {
  for (LispEnv *cur = env; cur; cur = cur.parent)
    if (cur._local_lookup(name, out)) return 1;
  return 0;
}

/* A parameter name and the name a form reads are both produced by the
   reader through `Atom.intern`, which gives one canonical value per
   spelling: a short name packs into the `Symbol` bits and a long one is
   interned. Identity therefore answers what `Var.equal` answers here, and
   without the descriptor lookup and tag decode that the general comparison
   pays on both sides. Verified over a `lib/` and a `src/` translate: 89,898
   matches, no case where the two disagreed. */
static int LispEnv._local_lookup(LispEnv *env, Var name, Var &out) {
  int found = 0, at = 0;
  for (List p = env.params; p && at < env.value_count; p = p.cdr(), at++)
    if (p.car().u64 == name.u64) {
      out = env.values[at];
      found = 1;
    }
  return found || _binding_get(env.bindings, name, out);
}

static int Lisp._global_lookup(Lisp lisp, Var name, Var &out) {
  for (Lisp s = lisp; s; s = s.parent)
    if (_binding_get(s.globals, name, out)) return 1;
  return 0;
}

/* A reserved special form, from this session or the nearest parent. A child
   that inherits its parent's specials also inherits their identity, which is
   what `Lisp._special_id` compares. */
static int Lisp._reserved_lookup(Lisp lisp, Var name, Var &out) {
  for (Lisp s = lisp; s; s = s.parent)
    if (s.reserved.try_get(name, out)) return 1;
  return 0;
}

/* A child may define new names but cannot replace inherited definitions. */
static int Lisp._inherited(Lisp lisp, Var name) {
  for (Lisp s = lisp.parent; s; s = s.parent)
    if (name in s.globals || name in s.reserved) return 1;
  return 0;
}

static int _binding_get(Map bindings, Var name, Var &out) {
  Var slot;
  if (!bindings || !bindings.try_get(name, slot)) return 0;
  out = _cell_load(slot);
  return 1;
}

static void _binding_set(Scope *owner, Map bindings, Var name, Var value) {
  Var slot;
  if (bindings.try_get(name, slot)) _cell_store(slot, value);
  else bindings[name] = _cell(owner, value);
}

/* Bindings use separately allocated cells because a Map excludes void from
   its value domain. */
static Var _cell(Scope *owner, Var value) {
  Var *slot = Scope.malloc_in(owner, sizeof(Var));
  *slot = value;
  return Var.new(<var*>, slot);
}

static Var _cell_load(Var cell) => *((Var *) cell.pointer());

static void _cell_store(Var cell, Var value) {
  *((Var *) cell.pointer()) = value;
}

/* call limits

   An evaluation stops with `<call-stack>` when it makes more calls than its
   budget or nests past its share of the C stack, and with `<interrupt>`
   while its session is interrupted. The public entry opens the budget, and
   the outermost call measures the stack. */

static void Lisp._spend_call(Lisp lisp) {
  if (lisp.call_exhausted || ++lisp.call_steps > lisp.call_step_max) {
    if (lisp.interrupted) $error.apply.interrupted();
    lisp.call_exhausted = 1;
    $error.apply.steps();
  }
}

/* `at` is the frame address of the call being made. The outermost call
   sets the base and the allowance the calls nested below it share. */
static void Lisp._check_stack(Lisp lisp, Lambda lambda, unsigned long at) {
  if (!lisp.call_depth) {
    lisp.stack_base = at;
    lisp.stack_allowance = _stack_allowance(at);
  }
  unsigned long used =
    lisp.stack_base > at ? lisp.stack_base - at : at - lisp.stack_base;
  if (used > lisp.stack_allowance)
    $error.apply.stack(lambda.body);
}

/* C stack evaluator calls may use below the outermost one. Threads get 8 MB
   (lib/thread.x) and so does a default main thread; the rest is left for the
   compiler and native calls, so a runaway ends in an error the compiler can
   report instead of a crash. Tail calls use none. */
#define LISP_STACK_BYTES_MAX (6L << 20)

#if defined(__GLIBC__)
extern int pthread_getattr_np(pthread_t thread, pthread_attr_t *attributes);
#endif

/* Returns the stack evaluator calls starting at `at` may use: four fifths of
   what the current thread has left below `at`, at most
   LISP_STACK_BYTES_MAX. Where the thread's stack is unknown it is the
   maximum. */
static unsigned long _stack_allowance(unsigned long at) {
  unsigned long low = 0;
#if defined(__APPLE__)
  pthread_t self = pthread_self();
  low = (unsigned long) pthread_get_stackaddr_np(self)
    - pthread_get_stacksize_np(self);
#elif defined(__GLIBC__)
  pthread_attr_t attributes;
  if (!pthread_getattr_np(pthread_self(), &attributes)) {
    void *address;
    size_t size;
    if (!pthread_attr_getstack(&attributes, &address, &size))
      low = (unsigned long) address;
    pthread_attr_destroy(&attributes);
  }
#endif
  if (!low || low >= at) return LISP_STACK_BYTES_MAX;
  unsigned long left = at - low;
  left -= left / 5;
  return left < LISP_STACK_BYTES_MAX ? left : LISP_STACK_BYTES_MAX;
}

/* Calls one compile-time evaluation may make before it is stopped. A loop
   that never ends makes calls without nesting any, so the stack limit never
   sees it. */
#define LISP_CALL_STEP_MAX 40000000

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

/** Sets whether evaluation in `lisp` is interrupted. While `interrupted` is
    nonzero, every interpreted call raises `<interrupt>`, including calls
    made after a catch. The store is async-signal-safe, so a signal handler
    may interrupt a running evaluation; the owner clears the flag before the
    next one. `lisp` must be a live session. */
void Lisp.set_interrupted(Lisp lisp, int interrupted) {
  lisp.interrupted = interrupted;
  if (interrupted) lisp.call_exhausted = 1;
}

/* Opens one budget for an outer entry. A call that runs out raises, and
   code that catches the raise continues under the same exhausted budget,
   so one runaway reports once. */
static void Lisp._open_call_budget(Lisp lisp) {
  if (lisp.call_depth) return;
  lisp.call_steps = 0;
  lisp.call_exhausted = lisp.interrupted;
}

// form errors

/* Raises `<bad-arity>` unless `args` holds `expected` forms. */
static void _arity(List args, int expected, String operation) {
  int actual = args.len();
  if (actual != expected)
    $error.form.arity(operation, expected, actual);
}

static void _string_argument(Var value, String operation) {
  if (value is not <string>)
    $error.form.string(operation, value);
}

/* `apply` takes its values as one List. */
static List _list_argument(Var values) {
  if (values is not <list>)
    $error.apply.list(values);
  return values;
}

static void _not_procedure(Var callable) {
  $error.apply.procedure(callable);
}

/* reader

   The reader turns the shared Tokenizer's Lisp tokens into forms. A form
   whose tokens run out is incomplete, and the reader reports it at the
   form's first token. */

/* Reads the next form into `out` and returns `<value>`, or returns `<eof>`
   when no token remains. `cursor` ends past the form, or at the length of
   `source` at EOF; a failure raises with `cursor` at the form's first
   token. */
static Symbol _read_form(
  Tokenizer tokenizer, String source, unsigned base, unsigned &cursor,
  Var &?out) {
  Token token = tokenizer.next();
  if (!token || token.type == <eof>) {
    cursor = source.len();
    return <eof>;
  }
  unsigned start = base + token.pos;
  cursor = start;
  LispReader r = {tokenizer, source, base, 0};
  Var form = r.form(token, 0);
  if (form is void) _incomplete(source, start);
  if (out) out = form;
  cursor = base + r.end;
  return <value>;
}

/* One read over scanned tokens: `source` holds their text from byte `base`,
   and `end` is the offset past the last token a form used. */
static typedef struct LispReader {
  Tokenizer tokenizer, char *source, unsigned base, end;
} LispReader;

/* The form that starts at `token`, or `void` when the tokens end inside
   it. A form is never `void`. */
static Var LispReader.form(LispReader &r, Token token, int depth) {
  if (!token || token.type == <eof>) return void;
  Var prefix = void;
  switch (token.type) {
    case <error>:
      if (r.tokenizer.status() == <incomplete>) return void;
      return r.malformed(token);
    case <")">:  return r.malformed(token);
    case <"(">:  return r.list(depth + 1);
    case <"'">:  prefix = lsym_quote;      break;
    case <"`">:  prefix = lsym_quasiquote; break;
    case <",">:  prefix = lsym_unquote;    break;
    case <",@">: prefix = lsym_splicing;   break;
  }
  if (prefix is not void) return r.prefixed(prefix, depth);
  r.end = token.pos + token.len;
  return r.atom(token);
}

/* A reader prefix wraps the next form, as `'x` reads `(quote x)`. */
static Var LispReader.prefixed(LispReader &r, Var prefix, int depth) {
  Var inner = r.form(r.tokenizer.next(), depth + 1);
  if (inner is void) return void;
  return %($prefix $inner);
}

/* A form's elements are read in a loop, so only nesting costs a frame.
   The reader fences that nesting instead of exhausting the C stack, which
   on a worker thread is a fraction of the main thread's. */
#define LISP_READ_DEPTH_MAX 1024

/* The List after its `(`, or `void` when the tokens end inside it. */
static Var LispReader.list(LispReader &r, int depth) {
  if (depth >= LISP_READ_DEPTH_MAX)
    raise %(size-limit (operation "Lisp.read") (depth $depth));
  Array elements = $auto([]);
  Var out = void;
  loop {
    Token token = r.tokenizer.next();
    if (!token || token.type == <eof>) break;
    if (token.type == <")">) {
      r.end = token.pos + token.len;
      out = elements.list();
      break;
    }
    Var element = r.form(token, depth);
    if (element is void) break;
    elements.push(element);
  }
  return out;
}

static Var LispReader.atom(LispReader &r, Token token) {
  String text = token.text;
  switch (token.type) {
    case <lit-char*>:
      return String.new_len(text + 1, token.len - 2).unescape();
    case <lit-int>:    return r.integer(token);
    case <lit-float>:  return r.floating(token);
    case <lit-symbol>: return r.symbol(token);
    case <ident>:      return Atom.intern(text.unescape());
  }
  return r.malformed(token);
}

/* An integer that fits an `int` reads as one. */
static Var LispReader.integer(LispReader &r, Token token) {
  long value;
  String literal = String.new_len(token.text, token.len);
  if (!literal.try_long(&value)) return r.malformed(token);
  if (value == (int) value) return (int) value;
  return value;
}

static Var LispReader.floating(LispReader &r, Token token) {
  double value, String literal = String.new_len(token.text, token.len);
  if (!literal.try_double(&value)) return r.malformed(token);
  return value;
}

/* A Symbol literal is `<name>` or `<"escaped name">`. */
static Var LispReader.symbol(LispReader &r, Token token) {
  String text = token.text, int n = token.len;
  String inner = text[1] == '"'
    ? String.new_len(text + 2, n - 4).unescape()
    : String.new_len(text + 1, n - 2);
  if (!inner) return r.malformed(token);
  return Symbol.new(inner);
}

static Var LispReader.malformed(LispReader &r, Token token) =>
  _malformed(r.source, r.base + token.pos);

static Var _malformed(String source, unsigned at) {
  int line = 1, column = 1;
  scan_next_line_col(source, (int) at, &line, &column);
  raise %(malformed (source $source) (line $line) (column $column));
}

static Var _incomplete(String source, unsigned at) {
  int line = 1, column = 1;
  scan_next_line_col(source, (int) at, &line, &column);
  raise %(incomplete (source $source) (line $line) (column $column));
}

static Tokenizer _scan_lisp_tokens(String source, Scope *scope) {
  Tokenizer tokenizer = NULL;
  $scope(scope) {
    tokenizer = Tokenizer.new(source, <lisp>);
    tokenizer.scan();
  }
  return tokenizer;
}

/* primitives

   The native operations Lisp code reaches through `bind`. A predicate
   answers `<true>` or nil. */

static Var _bool(int x) { if (x) return <true>; return %(); }

/** Returns Lisp true for every value except nil and `void`. */
Var lisp_truth(Var value) => _bool(value is not void && !value.is_nil());

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

/** Returns the runtime tag of `value`. */
Symbol lisp_type(Var value) => value.tag();

// numbers

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
    raise %(bad-types (operation "lisp_compare") (left-kind ${a.kind()})
                       (right-kind ${b.kind()}));
  return _number_compare(a, b);
}

/** Concatenates when either operand is `String`, otherwise adds dynamically.
*/
Var lisp_add(Var a, Var b) {
  if (a is <string> || b is <string>) return %"$a$b";
  return a.binary(<+>, b);
}

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

// strings and files

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
  if (!input.try_match_replace(pat, template, result)) return input;
  return result;
}

/** Reads `path` completely, closes it, and returns its boxed `String`
    contents. Raises the open, read, size, or allocation cause reported by
    `File`. An opened stream is still closed on transfer.
*/
Var lisp_read_file(String path) => path.open("r").string_close();

/** Replaces `path` with `text` and reports Lisp success.
    The file is opened with truncation and always closed. A write or close
    failure returns `nil` after any accepted bytes; this operation is not
    atomic. An open failure transfers its `File` cause. `Null` text writes
    an empty file.
*/
Var lisp_write_file(String path, String text) {
  File file = path.open("w");
  int wrote = !text || file.puts(text) >= 0, closed = file.close() == 0;
  return _bool(wrote && closed);
}

/* callbacks

   A native operation that takes a Func, such as `List.map`, calls an
   interpreted callable through a Func whose context holds the session and
   the callable. A callback runs only inside the session that made it. */

static typedef struct LispCallback {
  Lisp lisp;
  Var callable;
  String operation;
  unsigned arity;
} LispCallback;

static List unary_signature = $!Type{ Var (Var) };
static List binary_signature = $!Type{ Var (Var, Var) };

static Func _unary_callback(Var callable) =>
  _callback(callable, _call, 1, "Lisp callback");
static Func _binary_callback(Var callable) =>
  _callback(callable, _call, 2, "Lisp callback");
static Func _predicate_callback(Var callable) =>
  _callback(callable, _predicate_call, 1, "Lisp callback");

/* A Func that meta code can keep, as a value or inside a lazy Iter, lives as
   long as the session that runs it, whatever region is active when it is
   made. A callback used only during one call stays in the active region.
   `Iter` keeps it in its existing auxiliary field; the native pull ABI
   remains the library's IterNextFn, and the callback carries its iterator
   and output-cell arguments into the interpreted source function. */
static Func _iter_callback(Var callable) {
  Func fn = _callback(callable, _call, 2, "Lisp iterator callback");
  if (fn) Scope.move(fn, &lisp_active.scope);
  return fn;
}

/* A Func of `arity` value arguments that runs `callable` in the active
   session, or NULL for a nil callable. */
static Func _callback(
  Var callable, FuncAdapter adapter, unsigned arity, String operation) {
  if (callable.is_nil()) return NULL;
  if (!lisp_active)
    $error.callback.absent(operation);
  LispCallback context = { lisp_active, callable, operation, arity };
  List signature = arity == 1 ? unary_signature : binary_signature;
  return Func.new_context(adapter, signature, &context, sizeof context);
}

static Var _call(Func fn, const FuncArg *args) {
  LispCallback *context = _callback_context(fn);
  List values = NULL;
  for (unsigned i = context.arity; i--;)
    values = cons(x2c_func_value_argument(fn, args, i, <var>), values);
  return context.lisp._apply_values(context.callable, values, NULL);
}

/* A call to _call here would add a C frame to every nested predicate
   call. */
static Var _predicate_call(Func fn, const FuncArg *args) {
  LispCallback *context = _callback_context(fn);
  Var value = x2c_func_value_argument(fn, args, 0, <var>);
  return lisp_truth(
    context.lisp._apply_values(context.callable, %($value), NULL));
}

static LispCallback *_callback_context(Func fn) {
  LispCallback *context = (void *) fn.context();
  if (!lisp_active || lisp_active != context.lisp)
    $error.callback.wrong(context.operation);
  return context;
}

static int _iter_next(Iter iter, Var *out) =>
  iter.aux.apply_values(iter, Var.new(<var*>, out)).int();

// callback targets

static List _lisp_List_map(List values, Var callable) =>
  values.map(_unary_callback(callable));
static List _lisp_List_filter(List values, Var callable) =>
  values.filter(_unary_callback(callable));
static int _lisp_List_any(List values, Var callable) =>
  values.any(_unary_callback(callable));
static int _lisp_List_all(List values, Var callable) =>
  values.all(_unary_callback(callable));
static List _lisp_List_map2(List left, List right, Var callable) =>
  left.map2(right, _binary_callback(callable));
static List _lisp_List_sort_by(List values, Var callable) =>
  values.sort_by(_unary_callback(callable));
static List _lisp_List_sort_with(List values, Var callable) =>
  values.sort_with(_binary_callback(callable));
static List _lisp_List_zip_with(List left, List right, Var callable) =>
  left.zip_with(right, _binary_callback(callable));
static Var _lisp_List_foldl(List values, Var seed, Var callable) =>
  values.foldl(seed, _binary_callback(callable));
static Var _lisp_List_find(List values, Var callable) =>
  values.find(_unary_callback(callable));

static Array _lisp_Array_map(Array values, Var callable) =>
  values.map(_unary_callback(callable));
static Array _lisp_Array_map2(Array left, Array right, Var callable) =>
  left.map2(right, _binary_callback(callable));
static Array _lisp_Array_sort_by(Array values, Var callable) =>
  values.sort_by(_unary_callback(callable));
static Array _lisp_Array_sort_with(Array values, Var callable) =>
  values.sort_with(_binary_callback(callable));
static Var _lisp_Array_foldl(Array values, Var seed, Var callable) =>
  values.foldl(seed, _binary_callback(callable));

static String _lisp_String_map(String value, Var callable) =>
  value.map(_unary_callback(callable));
static String _lisp_String_filter(String value, Var callable) =>
  value.filter(_unary_callback(callable));

/* A compile-time call gets fresh Iter storage from `C.iterator.call`. Only
   a callable argument needs this session's Func bridge. */
static Iter _lisp_Iter_init(
  Iter destination, Var object, Var callable, Var state) {
  if (!destination) return NULL;
  Func callback = _iter_callback(callable);
  destination.init(object, callback ? _iter_next : NULL, state);
  destination.aux = callback;
  return destination;
}

static Iter _lisp_Iter_map_into(
  Iter iter, Var callable, Iter destination) =>
  iter.map(_unary_callback(callable), destination);
static Iter _lisp_Iter_filter_into(
  Iter iter, Var callable, Iter destination) =>
  iter.filter(_unary_callback(callable), destination);
static Iter _lisp_Iter_zip_with_into(
  Iter left, Iter right, Var callable, Iter destination) =>
  left.zip_with(right, _binary_callback(callable), destination);
static Iter _lisp_Iter_map2_into(
  Iter left, Iter right, Var callable, Iter destination) =>
  left.map2(right, _binary_callback(callable), destination);
static Iter _lisp_Iter_scan_into(
  Iter iter, Var seed, Var callable, Iter destination) =>
  iter.scan(seed, _binary_callback(callable), destination);
static int _lisp_Iter_any(Iter iter, Var callable) =>
  iter.any(_unary_callback(callable));
static int _lisp_Iter_all(Iter iter, Var callable) =>
  iter.all(_unary_callback(callable));
static Var _lisp_Iter_foldl(Iter iter, Var seed, Var callable) =>
  iter.foldl(seed, _binary_callback(callable));
static Var _lisp_Iter_find(Iter iter, Var callable) =>
  iter.find(_unary_callback(callable));

/* The x2c bindings above preserve native Var truth. Lisp surface calls adapt
   predicate results through Lisp truth before native collection code observes
   them, so nil and void are false while every other value remains true. */
static List _lisp_Lisp_List_filter(List values, Var callable) =>
  values.filter(_predicate_callback(callable));
static int _lisp_Lisp_List_any(List values, Var callable) =>
  values.any(_predicate_callback(callable));
static int _lisp_Lisp_List_all(List values, Var callable) =>
  values.all(_predicate_callback(callable));
static Var _lisp_Lisp_List_find(List values, Var callable) =>
  values.find(_predicate_callback(callable));
static String _lisp_Lisp_String_filter(String value, Var callable) =>
  value.filter(_predicate_callback(callable));
static Iter _lisp_Lisp_Iter_filter(Iter iter, Var callable) =>
  iter.filter(_predicate_callback(callable), Iter.new());
static int _lisp_Lisp_Iter_any(Iter iter, Var callable) =>
  iter.any(_predicate_callback(callable));
static int _lisp_Lisp_Iter_all(Iter iter, Var callable) =>
  iter.all(_predicate_callback(callable));
static Var _lisp_Lisp_Iter_find(Iter iter, Var callable) =>
  iter.find(_predicate_callback(callable));

/* native targets

   `bind` resolves a name through the callback targets above, then through
   the table `lisp-targets.x` builds. That unit includes the optional modules
   the evaluator binds, which the implicit prelude must not carry, so this
   C-only declaration reaches its table without entering the x2c interface. */

static macro Unit $lisp.native.declarations() {
  $(quote ((preproc "extern Map lisp_native_targets(void);")))...
}

$lisp.native.declarations();

$x2c.foreign.alias(lisp_native_targets)
static Map _library_targets(void);

static $(import "../etc/lisp-bindings.xlisp")
static macro Expression $lisp.callback.target.map() => $(lisp.native.targets '(
  (_lisp_List_map (as List_map))
  (_lisp_List_filter (as List_filter))
  (_lisp_List_any (as List_any))
  (_lisp_List_all (as List_all))
  (_lisp_List_map2 (as List_map2))
  (_lisp_List_sort_by (as List_sort_by))
  (_lisp_List_sort_with (as List_sort_with))
  (_lisp_List_zip_with (as List_zip_with))
  (_lisp_List_foldl (as List_foldl))
  (_lisp_List_find (as List_find))
  (_lisp_Array_map (as Array_map))
  (_lisp_Array_map2 (as Array_map2))
  (_lisp_Array_sort_by (as Array_sort_by))
  (_lisp_Array_sort_with (as Array_sort_with))
  (_lisp_Array_foldl (as Array_foldl))
  (_lisp_String_map (as String_map))
  (_lisp_String_filter (as String_filter))
  // Iterator operations are declared `meta` in iter.x and adopted with
  // `meta protocol` in protocols.x, which generates their `_into` targets.
  // One that takes a callback binds here through its adapter.
  (_lisp_Iter_init (as Iter_init))
  (_lisp_Iter_map_into (as Iter_map_into))
  (_lisp_Iter_filter_into (as Iter_filter_into))
  (_lisp_Iter_zip_with_into (as Iter_zip_with_into))
  (_lisp_Iter_map2_into (as Iter_map2_into))
  (_lisp_Iter_scan_into (as Iter_scan_into))
  (_lisp_Iter_any (as Iter_any))
  (_lisp_Iter_all (as Iter_all))
  (_lisp_Iter_foldl (as Iter_foldl))
  (_lisp_Iter_find (as Iter_find))
  (_lisp_Lisp_List_filter (as Lisp_List_filter))
  (_lisp_Lisp_List_any (as Lisp_List_any))
  (_lisp_Lisp_List_all (as Lisp_List_all))
  (_lisp_Lisp_List_find (as Lisp_List_find))
  (_lisp_Lisp_String_filter (as Lisp_String_filter))
  (_lisp_Lisp_Iter_filter (as Lisp_Iter_filter))
  (_lisp_Lisp_Iter_any (as Lisp_Iter_any))
  (_lisp_Lisp_Iter_all (as Lisp_Iter_all))
  (_lisp_Lisp_Iter_find (as Lisp_Iter_find))
));

static Map callback_targets = $lisp.callback.target.map();

static Func _native_target(String name) {
  Var target;
  if (!callback_targets.try_get(name, target) &&
      !_library_targets().try_get(name, target)) return NULL;
  return (Func) target.pointer();
}

/* sessions

   A kernel session holds only the evaluator's special forms, and a new
   session also evaluates the standard environment from `etc/init.xlisp`. */

static String lisp_standard_source = $lisp._standard.source();

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
  Lisp lisp = Scope.calloc_in(&session, 1, sizeof(struct Lisp));
  defer if (!result) Scope.destroy(lisp.user);
  if (!_initialize()) return NULL;
  lisp.scope = session;
  lisp.user = Scope.new_named("Lisp user");
  lisp.call_step_max = LISP_CALL_STEP_MAX;
  $scope(&lisp.scope) {
    lisp.globals = {};
    lisp.reserved = {};
    lisp._install_specials();
  }
  return result = lisp;
}

/* A special form's reserved value is a distinct stub Func, which the
   evaluator recognizes by identity. */
static void Lisp._install_specials(Lisp lisp) {
  for (int i = 0; i < LISP_SPECIAL_COUNT; i++) {
    const LispCanonicalName *info = _special_name(i);
    lisp.specials[i] = Func.new(_special_stub, $!Type{ Var (void) });
    Atom name = Atom.intern(info.spelling);
    lisp.reserved[name] = lisp.specials[i];
  }
}

static Var _special_stub(void) => Var.null();

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
    This includes its global and reserved `Map`s, Lambdas, and transferred
    `Func`s. Borrowed values are not released. A null session does nothing;
    no evaluation may remain active.
    Destroying its still-active `Scope` raises `<bad-state>`.
*/
void Lisp.destroy(Lisp lisp) {
  if (!lisp) return;
  Scope.destroy(lisp.user);
  Scope.destroy(lisp.scope);
}

/** Makes `lisp` read `parent`'s definitions for names it does not bind.

    Lisp definitions cannot replace names supplied by an ancestor.
    `Lisp.set_global` may shadow them in the child. Child writes never
    reach the parent or another child. The child also takes the parent's
    special forms in place of its own, because
    the evaluator recognizes a special form by the identity of the `Func` a
    name resolves to, and the child resolves reserved names in the parent.

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

    A frozen session rejects `def` and `Lisp.set_global`: a value produced
    while a narrower `Context` is current would leave the session holding
    values that die with that `Context`.
*/
void Lisp.freeze(Lisp lisp) { if (lisp) lisp.frozen = 1; }

/* entry points

   A public evaluation entry makes its session the active one and pushes
   the session's user Scope, where evaluated code allocates. A nested entry
   restores its caller's session when it returns. */

static Var _bad_session(String operation) {
  $error.entry.null(operation);
}

static macro Decorator $lisp.entry(Function $function, Expr $operation) {
  if (!$(x2c.function.parameter $function "lisp"))
    return _bad_session($operation);
  Scope.push(&$(x2c.function.parameter $function "lisp").user);
  defer Scope.pop();
  Lisp prior_lisp = lisp_active;
  lisp_active = $(x2c.function.parameter $function "lisp");
  defer lisp_active = prior_lisp;
  $(x2c.function.body $function)...
}

/** Reads one Lisp form and returns `<value>` or `<eof>`.
    A nonnull `out` receives the form only for `<value>`; it is otherwise
    unchanged. New result storage uses the caller's active `Scope` and
    canonical pools, not the temporary token `Scope`, and remains valid
    until those owners are released. On success `cursor` advances past the
    form, at EOF it becomes the source length, and on a reader error it
    identifies the failing form's first token. A null source or cursor
    returns `<eof>` without raising. A nonnull cursor must initially hold a
    byte offset no greater than the source length. A successful session
    construction must first initialize the shared reader names; afterward
    `lisp` is not consulted and may be null.
    Raises: `<incomplete>` for a truncated form, `<malformed>` for invalid
    reader syntax, or `<alloc-fail>`, `<size-limit>`, or `<bad-enc>` while
    tokenizing, constructing, interning, or boxing the form.
*/
Symbol Lisp.read(Lisp lisp, String source, unsigned &?cursor, Var &?out) {
  (void) lisp;
  if (!source) return <eof>;
  if (!cursor) return <eof>;
  unsigned base = cursor;
  Scope tokens_scope = $auto(Scope.new_named("Lisp tokens"));
  Tokenizer tokenizer = _scan_lisp_tokens(source + base, &tokens_scope);
  return _read_form(tokenizer, source, base, cursor, out);
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
  lisp._open_call_budget();
  return lisp._eval(expression, NULL);
}

/** Applies `callable` to already evaluated `values`.
    Macros and evaluator special forms other than the built-in `apply` are
    not procedures and are rejected. The built-in accepts a callable and a
    `List` and recursively applies those already evaluated values. The Lisp
    session owns `Scope` allocations made by the call; returned canonical or
    caller-supplied values keep their existing owners. The caller retains
    responsibility for `callable`, `values`, and their referents.
    Raises: `<bad-arg>` for a null session, `<not-call>` for a non-procedure
    or evaluator-only callable, `<bad-arity>` or `<bad-types>` at the call
    boundary, or a cause raised by the called procedure.
*/
$lisp.entry("Lisp.apply")
Var Lisp.apply(Lisp lisp, Var callable, List values) {
  lisp._open_call_budget();
  return lisp._apply_values(callable, values, NULL);
}

/** Reads and evaluates every form in `source`.
    Forms run in source order and the return value is the last result, or Lisp
    `nil` for a null, empty, or comment-only source. Globals and other effects
    completed before a later reader or evaluator failure remain installed.
    Lambdas retain local values that may become reads after a global callable
    changes, including names in current data. These captures belong to the
    session; borrowed referents keep their original lifetimes.
    Raises: `<bad-arg>` for a null session, `<incomplete>` or `<malformed>`
    while reading, or any cause from `Lisp.eval`.
*/
$lisp.entry("Lisp.eval_string")
Var Lisp.eval_string(Lisp lisp, String source) {
  if (!source) return %();
  lisp._open_call_budget();
  Scope tokens_scope = $auto(Scope.new_named("Lisp tokens"));
  Tokenizer tokenizer = _scan_lisp_tokens(source, &tokens_scope);
  unsigned cursor = 0;
  Var result = %();
  loop {
    Var form = void;
    if (_read_form(tokenizer, source, 0, cursor, form) == <eof>) break;
    result = lisp._eval(form, NULL);
  }
  return result;
}

/** Reads and evaluates every form from `source`.
    Reading starts at the current stream position, consumes through EOF, and
    leaves the borrowed stream open. Forms run in order, so effects from
    forms completed before a later read or evaluation failure are not rolled
    back. A null `Lisp` session is rejected by `Lisp.eval_string` only after
    the stream has been consumed.
    Raises: `<bad-arg>` for a null stream or embedded NUL, `<io-fail>`,
    `<size-limit>`, or `<alloc-fail>` while reading, or any cause from
    `Lisp.eval_string`.
*/
Var Lisp.eval_file(Lisp l, File source) {
  if (!source) raise %(bad-arg (operation "Lisp.eval_file"));
  Block content = $auto(Block.new(sizeof(char)));
  if (source.read_into(content) == FILE_READ_EOF) return l.eval_string(NULL);
  if (content.length > INT_MAX) {
    size_t size = content.length, int limit = INT_MAX;
    raise %(size-limit (operation "Lisp.eval_file") (size $size)
                       (limit $limit));
  }
  if (memchr(content.bytes, '\0', content.length))
    raise %(bad-arg (operation "Lisp.eval_file") (reason "embedded NUL"));
  String text = String.new_len(content.bytes, (int) content.length);
  return l.eval_string(text);
}

// globals

/** Writes the global binding for `name` to `out` when present.
    Returns 1 only after writing the borrowed value. A null session, name, or
    output, or an absent name returns 0 and leaves `out` unchanged. Raises
    `<alloc-fail>` or `<bad-enc>` when a nonempty lookup name cannot be
    canonicalized.
*/
int Lisp.try_get(Lisp lisp, String name, Var &?out) =>
  lisp && name && out && lisp._global_lookup(Atom.intern(name), out);

/** Binds `name` to `value` in the embedded Lisp global environment.
    The session stores the value in a raw slot, so `void` remains distinct
    from Lisp `nil`. The binding does not take ownership of value referents;
    their canonical graphs or other owners must outlive the binding or
    session. A host binding may shadow an inherited name in this session;
    it does not change the ancestor. Lisp `def` still rejects inherited
    names, including a name the host has shadowed locally.
    Binding an `x2c.` name protects that namespace from later Lisp
    `def` forms, but direct calls to this function may replace such a
    binding.
    Raises: `<bad-arg>` for a null session or name, or `<alloc-fail>`,
    `<size-limit>`, or `<bad-enc>` while canonicalizing or storing the binding.
*/
void Lisp.set_global(Lisp lisp, String name, Var value) {
  if (!lisp || !name) $error.global.args();
  if (lisp.frozen)
    $error.global.frozen();
  $scope(&lisp.scope) {
    Var interned = Atom.intern(name);
    _binding_set(&lisp.scope, lisp.globals, interned, value);
    if (name.startswith("x2c.")) lisp.protect_x2c = 1;
  }
}

/** Installs `function` as `name` and transfers its storage to `lisp`.
    Invalid arguments raise `<bad-arg>` without transferring ownership. Once
    validation succeeds, the `Func` moves before the global insertion. The
    caller relinquishes ownership even if name canonicalization or `Map`
    growth then raises `<alloc-fail>`, `<size-limit>`, or `<bad-enc>`, but
    may borrow the pointer while the session lives. A direct function or
    noncapturing lambda converts to a shared handle that lives for the
    program; the session only borrows it. Values inside the `Func`,
    including its signature graph, retain their existing owners.
*/
void Lisp.bind(Lisp lisp, String name, Func function) {
  if (!lisp || !name || !function) $error.bind.args();
  function.move(&lisp.scope);
  lisp.set_global(name, function);
}

// session storage

/** Borrows the session executing the current native Lisp callback. */
Lisp Lisp.active(void) => lisp_active;
/** Borrows the storage owner for callback state retained by this session. */
Scope *Lisp.storage(Lisp lisp) => &lisp.scope;
/** Borrows the current lowered source activation's automatic storage. */
Scope *Lisp.automatic_storage(Lisp lisp) =>
  lisp.automatic_owner ? lisp.automatic_owner : &lisp.scope;
/** Borrows the caller's storage for a lowered record result. */
Scope *Lisp.result_storage(Lisp lisp) =>
  lisp.result_owner ? lisp.result_owner : &lisp.scope;

/** Marks the actual Lambda installed for one lowered source function. */
Var lisp_source_function(Var callable) {
  if (callable is not <lambda>)
    $error.source.callable(callable);
  ((Lambda) callable).source_function = 1;
  return callable;
}
