/*  evaluate.x -- Lisp evaluate

    Copyright (c) 2026 Gary William Flake.
*/

static keyword loop $private.loop;

// session state

/* Environment records are activation-local. A rest activation's `bindings`
   is a temporary frame-owned Map, while the captured pseudo-frame aliases
   its Lambda's session-owned capture Map. Parameter names, captured
   Vars, argument arrays, and parent records are borrowed for the activation,
   and the environment records stay on the C stack until the call returns. */
module typedef struct LispEnv {
  Map bindings, List params;
  const Var *values;
  struct LispEnv *parent;
} LispEnv;

module inline Var Lambda.var(Lambda value) {
  return Var.new(<lambda>, value);
}

module inline Lambda Var.lambda(Var value) {
  return value.pointer();
}

static protocol Var(Lambda);

/* evaluation

   A name evaluates to its binding, and every other value except a nonempty
   List evaluates to itself. A List is a call: its head is evaluated first,
   then a lambda or native receives evaluated arguments and a macro or
   special form receives the raw forms. */

static Var _eval(Lisp lisp, Var expr, LispEnv *env) {
  if (expr is void) $error.eval.void();
  if (expr.is_atom()) {
    Var value;
    if (!_lookup(lisp, env, expr, value)) $error.eval.unbound(expr);
    return value;
  }
  if (expr is not <list> || expr.is_nil()) return expr;
  List form = expr;
  Var callable = _eval(lisp, form.car(), env);
  return _apply(lisp, callable, form.cdr(), env);
}

/* Native calls this wide evaluate into a stack array; wider ones take one
   scope allocation. Func itself has no arity limit. */
#define LISP_NATIVE_ARG_MAX  8

/* A native call's arguments are evaluated here, left to right. Its `defer`
   lowers to a `sigsetjmp` exception frame, which keeps a helper from being
   inlined, so a separate native-call step would add a C frame to every
   nested call. */
static Var _apply(Lisp lisp, Var callable, List raw, LispEnv *env) {
  if (callable is <lambda>) return _apply_lambda(lisp, callable, raw, env);
  if (callable is not <func>) $error.call.type(callable);
  Func fn = (Func) callable.pointer();
  Symbol special = _special_id(lisp, fn);
  if (special) return _apply_special(lisp, special, raw, env);
  int count = raw.len();
  FuncArg narrow[LISP_NATIVE_ARG_MAX];
  FuncArg *argv = count <= LISP_NATIVE_ARG_MAX
    ? narrow : Scope.malloc_in(&lisp.scope, count * sizeof(FuncArg));
  defer if (argv != narrow) Scope.free(argv);
  unsigned argc = 0;
  foreach (Var arg in raw) argv[argc++] = FuncArg.value(_eval(lisp, arg, env));
  return fn.apply(argc, argv);
}

/* The special form whose reserved Func is `function`, compared by
   identity, or zero for any other Func. */
static Symbol _special_id(Lisp lisp, Func fn) {
  for (unsigned i = 0; i < _canonical_count(); i++)
    if (lisp.specials[i] == fn) return lisp_canonical_names[i].special;
  return 0;
}

/* Applies `callable` to evaluated `values`. A macro, or a special form other
   than `apply`, is not a procedure. */
module Var _apply_values(Lisp lisp, Var callable, List values) {
  if (callable is <lambda>) {
    Lambda lambda = callable;
    if (lambda.macro) _not_procedure(callable);
    return _call_lambda(lisp, lambda, values);
  }
  if (callable is not <func>) $error.call.type(callable);
  Func fn = (Func) callable.pointer();
  Symbol special = _special_id(lisp, fn);
  if (!special) return _call_native(lisp, fn, values);
  if (special != <apply>) _not_procedure(callable);
  _arity(values, 2, "apply");
  List rest = _list_argument(values.cadr());
  return _apply_values(lisp, values.car(), rest);
}

static Var _call_native(Lisp lisp, Func fn, List values) {
  int count = values.len();
  FuncArg narrow[LISP_NATIVE_ARG_MAX];
  FuncArg *argv = count <= LISP_NATIVE_ARG_MAX
    ? narrow : Scope.malloc_in(&lisp.scope, count * sizeof(FuncArg));
  defer if (argv != narrow) Scope.free(argv);
  unsigned argc = 0;
  foreach (Var value in values) argv[argc++] = FuncArg.value(value);
  return fn.apply(argc, argv);
}

/* special forms

   A special form receives its argument forms unevaluated and evaluates only
   the ones its rule selects. Each form checks its own shape first. */

static Var _apply_special(Lisp lisp, Symbol id, List args, LispEnv *env) {
  switch (id) {
    case <quote>:      return _special_quote(args);
    case <def>:        return _special_def(lisp, args, env);
    case <cond>:       return _special_cond(lisp, args, env);
    case <lambda>:     return _make_lambda(lisp, args, env, 0);
    case <macro>:      return _make_lambda(lisp, args, env, 1);
    case <quasiquote>: return _special_quasiquote(lisp, args, env);
    case <eval>:       return _special_eval(lisp, args, env);
    case <bind>:       return _special_bind(lisp, args, env);
    case <apply>:      return _special_apply(lisp, args, env);
  }
  return _special_import(lisp, args, env);
}

static Var _special_quote(List args) {
  _arity(args, 1, "quote");
  return args.car();
}

/* `def` writes a session global and returns its value. */
static Var _special_def(Lisp lisp, List args, LispEnv *env) {
  Var (name, form) = args;
  if (args.len() != 2 || !name.is_atom()) {
    int actual = args.len();
    $error.def.arity(actual, args);
  }
  if (lisp.protect_x2c && name.str().startswith("x2c."))
    $error.def.protected(name);
  if (_inherited(lisp, name))
    $error.def.inherited(name);
  /* A frozen session is complete, and a value produced now belongs to a
     narrower Context than it does, so the binding would outlive what it
     names. A child session is where a later definition goes. */
  if (lisp.frozen)
    $error.def.frozen(name);
  Var value = _eval(lisp, form, env);
  _binding_set(&lisp.scope, lisp.globals, name, value);
  return value;
}

static Var _special_cond(Lisp lisp, List args, LispEnv *env) {
  Var form = _cond_select(lisp, args, env);
  if (form is void) return %();
  return _eval(lisp, form, env);
}

/* The result form of the first `cond` clause whose test holds, or `void`
   when none does. A clause's form comes from a List, so it is never
   `void`. */
static Var _cond_select(Lisp lisp, List args, LispEnv *env) {
  if (!args) $error.cond.empty();
  foreach (Var clause in args) {
    Var (test, form) = _cond_clause(clause);
    if (lisp_truth(_eval(lisp, test, env))) return form;
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

static Var _special_quasiquote(Lisp lisp, List args, LispEnv *env) {
  _arity(args, 1, "quasiquote");
  return _qq(lisp, args.car(), env, 0);
}

/* `eval` evaluates its argument, then evaluates that form globally. */
static Var _special_eval(Lisp lisp, List args, LispEnv *env) {
  _arity(args, 1, "eval");
  return _eval(lisp, _eval(lisp, args.car(), env), NULL);
}

/* `bind` finds a native target by name. The target carries its own
   signature, so the given one is checked for shape only. */
static Var _special_bind(Lisp lisp, List args, LispEnv *env) {
  _arity(args, 2, "bind");
  Var (name_form, signature_form) = args;
  Var name = _eval(lisp, name_form, env);
  Var signature = _eval(lisp, signature_form, env);
  _string_argument(name, "bind");
  if (signature is not <list>)
    $error.bind.signature(signature);
  String native_name = name, List native_signature = signature;
  Func fn = _native_target(native_name);
  if (!fn) $error.bind.missing(native_name, native_signature);
  return fn;
}

static Var _special_apply(Lisp lisp, List args, LispEnv *env) {
  _arity(args, 2, "apply");
  Var (callable_form, values_form) = args;
  Var callable = _eval(lisp, callable_form, env);
  Var values = _eval(lisp, values_form, env);
  return _apply_values(lisp, callable, _list_argument(values));
}

/* `import` hands its path to the `_x2c.import-hook` global when one is
   bound, and otherwise evaluates the file. */
static Var _special_import(Lisp lisp, List args, LispEnv *env) {
  _arity(args, 1, "import");
  Var path = _eval(lisp, args.car(), env);
  _string_argument(path, "import");
  Var hook;
  if (_global_lookup(lisp, Atom.intern("_x2c.import-hook"), hook))
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
static Var _qq(Lisp l, Var expr, LispEnv *env, int depth) {
  if (expr is not <list> || expr.is_nil()) return expr;
  List form = expr;
  Var head = form.car();
  if (head == lsym_quasiquote)
    return head.cons(_qq_elements(l, form.cdr(), env, depth + 1));
  if (head != lsym_unquote && head != lsym_splicing)
    return _qq_elements(l, form, env, depth);
  if (form.len() != 2)
    $error.quote.shape(expr);
  if (depth > 0) return head.cons(_qq_elements(l, form.cdr(), env, depth - 1));
  Var value = _eval(l, form.cadr(), env);
  if (head == lsym_splicing)
    $error.splice.type(expr);
  return value;
}

/* Walk siblings as elements, never as another headed quoted form. */
static List _qq_elements(Lisp lisp, List items, LispEnv *env, int depth) {
  Array values = $auto([]);
  foreach (Var item in items) {
    if (!depth && _is_splice(item))
      foreach (Var value in _splice(lisp, item, env)) values.push(value);
    else values.push(_qq(lisp, item, env, depth));
  }
  return values;
}

static int _is_splice(Var expr) =>
  expr is <list> && !expr.is_nil() && expr.car() == lsym_splicing;

static List _splice(Lisp lisp, Var expr, LispEnv *env) {
  List form = expr;
  if (form.len() != 2)
    $error.quote.shape(expr);
  Var value = _eval(lisp, form.cadr(), env);
  if (value is not <list>)
    $error.splice.type(value);
  return value;
}

/* closures

   A Lambda captures, when it is made, local values its body may read.
   Mutable global or unknown callables may later evaluate current data, so
   those forms retain possible reads too. A name bound nowhere in the
   defining environment is read from the session globals at each call. */

static Var _make_lambda(Lisp lisp, List args, LispEnv *env, int macro) {
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
    _capture(lisp, env, lambda);
  }
  return result = lambda;
}

static void _capture(Lisp lisp, LispEnv *env, Lambda lambda) {
  FreeNames walk = {lisp, env, lambda.captures};
  _free_form(walk, lambda.body, lambda.params, 0);
}

/* One capture analysis: the session and environment that resolve call
   heads, and the captured local values. */
static typedef struct FreeNames {
  Lisp lisp, LispEnv *env, Map captures;
} FreeNames;

/* A captured local callable keeps its identity. Global, parameter and
   computed heads may change which operands evaluate, so their operands
   retain all possible local reads. Negative depth marks that possibility;
   zero is an evaluated position and positive depth is quasiquote data.
   Stable special identities preserve quote opacity and inner binders. */
static void _free_form(FreeNames &f, Var form, List bound, int depth) {
  if (form.is_atom()) {
    if (depth <= 0 && !_param_has(bound, form)) _capture_name(f, form);
    return;
  }
  if (form is not <list>) return;
  List items = form;
  if (!items) return;
  if (depth < 0) _all(f, items, bound, depth);
  else if (depth > 0) _quoted(f, items, bound, depth);
  else _free_call(f, items, bound);
}

static void _capture_name(FreeNames &f, Var name) {
  if (name in f.captures) return;
  Var value;
  if (_env_lookup(f.env, name, value))
    _binding_set(&f.lisp.scope, f.captures, name, value);
}

static void _all(FreeNames &f, List items, List bound, int depth) {
  foreach (Var part in items) _free_form(f, part, bound, depth);
}

static void _quoted(FreeNames &f, List items, List bound, int depth) {
  int inner = _quote_depth(items.car(), depth);
  _all(f, inner >= 0 ? items.cdr() : items, bound, inner >= 0 ? inner : depth);
}

/* The head is an evaluated position, and what it names decides how its
   operands are read. */
static void _free_call(FreeNames &f, List items, List bound) {
  Var head = items.car(), callable;
  _free_form(f, head, bound, 0);
  if (!head.is_atom() || _param_has(bound, head) ||
      !_env_lookup(f.env, head, callable)) {
    _all(f, items.cdr(), bound, -1);
    return;
  }
  Symbol special = callable is <func>
    ? _special_id(f.lisp, (Func) callable.pointer()) : 0;
  if (special == <quote>) return;
  if (special == <lambda> || special == <macro>) {
    List rest = items.cdr(), params = _with_params(bound, rest);
    _all(f, rest.cdr(), params, 0);
    return;
  }
  int inner = special == <quasiquote> ? 1 :
    callable is <lambda> && ((Lambda) callable).macro ? -1 : 0;
  _all(f, items.cdr(), bound, inner);
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
    foreach (Var name in (List) rest.car()) bound = cons(name, bound);
  return bound;
}

static int _param_has(List params, Var name) {
  foreach (Var param in params) if (param == name) return 1;
  return 0;
}

/* calls

   A call evaluates its arguments into an array and runs its Lambda in an
   activation frame. Positional parameters read that array; a rest
   parameter is bound in the frame to a List of the values. */

static Var _apply_lambda(Lisp l, Lambda lambda, List raw, LispEnv *env) {
  if (lambda.macro) return _eval(l, _call_lambda(l, lambda, raw), env);
  int count = raw.len(), index = 0;
  Var *values = Scope.malloc_in(&l.scope, (count + 1) * sizeof(Var));
  defer Scope.free(values);
  foreach (Var form in raw) values[index++] = _eval(l, form, env);
  return _call_lambda_slots(l, lambda, values, count);
}

static Var _call_lambda(Lisp lisp, Lambda lambda, List args) {
  int count = args.len(), index = 0;
  Var *values = Scope.malloc_in(&lisp.scope, (count + 1) * sizeof(Var));
  defer Scope.free(values);
  foreach (Var value in args) values[index++] = value;
  return _call_lambda_slots(lisp, lambda, values, count);
}

/* Calls `lambda` and then each tail call its body leaves pending, in one
   C frame. Nesting is bounded by the C stack it uses, not by a count. */
static Var _call_lambda_slots(
  Lisp lisp, Lambda lambda, const Var *values, int count) {
  _spend_call(lisp);
  _check_stack(lisp, lambda, (unsigned long) __builtin_frame_address(0));
  lisp.call_depth++;
  defer lisp.call_depth--;
  Var *owned = NULL;
  defer if (owned) Scope.free(owned);
  for (;;) {
    Var result = _run_frame(lisp, lambda, values, count);
    if (!lisp.tail_lambda) return result;
    lambda = lisp.tail_lambda;
    lisp.tail_lambda = NULL;
    if (owned) Scope.free(owned);
    values = owned = lisp.tail_values;
    count = lisp.tail_count;
    _spend_call(lisp);
  }
}

/* Runs one activation of `lambda`. In tail position it may leave a pending
   call on `lisp` instead of making it; `_call_lambda_slots` runs that
   call after this frame is gone. */
static Var _run_frame(
  Lisp lisp, Lambda lambda, const Var *values, int count) {
  Scope frame = NULL;
  defer frame.cleanup();
  /* A free name the lambda did not capture is a global. The environment the
     call was written in is not a parameter here, so a caller's binding
     cannot change what the body reads. */
  LispEnv captured = {.bindings = lambda.captures, .parent = NULL};
  LispEnv local = {.parent = &captured};
  if (Atom.intern(".") in lambda.params) {
    $scope(&frame) { local.bindings = {}; }
    _bind_params(&frame, lambda, _value_list(values, count), local.bindings);
  }
  else _bind_values(&(local), lambda, values, count);
  if (lambda.source_function)
    return _run_source(lisp, lambda.body, &local, &frame);
  return _eval_tail(lisp, lambda.body, &local);
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

static void _bind_values(
  LispEnv *local, Lambda lambda, const Var *values, int count) {
  if (count != lambda.params.len())
    $error.apply.arity(lambda.body);
  local.params = lambda.params;
  local.values = values;
}

/* A lowered source function owns its automatic storage in the frame. A
   record it returns is copied into its caller's storage before the frame
   ends. */
static Var _run_source(Lisp lisp, Var body, LispEnv *env, Scope *frame) {
  Scope *caller_owner = lisp.automatic_owner;
  Scope *caller_result_owner = lisp.result_owner;
  defer {
    lisp.automatic_owner = caller_owner;
    lisp.result_owner = caller_result_owner;
  }
  lisp.result_owner = caller_owner;
  lisp.automatic_owner = frame;
  return _eval(lisp, body, env);
}

/* tail calls

   A call to an evaluator lambda in tail position does not nest. Its
   arguments are evaluated and the call is left on the session for
   `_call_lambda_slots`, which runs it in place of the frame that made
   it. */

/* Evaluates `expr` as the last act of the running frame. A macro's
   expansion and a `cond`'s selected form stay in tail position. */
static Var _eval_tail(Lisp lisp, Var expr, LispEnv *env) {
  for (;;) {
    if (expr is not <list> || expr.is_nil()) return _eval(lisp, expr, env);
    List form = expr;
    Var callable = _eval(lisp, form.car(), env);
    List raw = form.cdr();
    if (callable is <func> &&
        _special_id(lisp, (Func) callable.pointer()) == <cond>) {
      expr = _cond_select(lisp, raw, env);
      if (expr is void) return %();
      continue;
    }
    if (callable is not <lambda>) return _apply(lisp, callable, raw, env);
    Lambda lambda = callable;
    if (lambda.source_function) return _apply_lambda(lisp, lambda, raw, env);
    if (!lambda.macro) return _tail_call(lisp, lambda, raw, env);
    expr = _call_lambda(lisp, lambda, raw);
  }
}

/* Evaluates the arguments of a tail call and leaves the call on `lisp`. */
static Var _tail_call(Lisp lisp, Lambda lambda, List raw, LispEnv *env) {
  int count = raw.len(), index = 0;
  Var *values = Scope.malloc_in(&lisp.scope, (count + 1) * sizeof(Var));
  int pending = 0;
  defer if (!pending) Scope.free(values);
  foreach (Var argument in raw) values[index++] = _eval(lisp, argument, env);
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

static int _lookup(Lisp lisp, LispEnv *env, Var name, Var &out) =>
  _env_lookup(env, name, out) || _global_lookup(lisp, name, out) ||
  _reserved_lookup(lisp, name, out);

/* Captures are the values the Lambda was made with and do not change
   afterwards. */
static int _env_lookup(LispEnv *env, Var name, Var &out) {
  for (LispEnv *cur = env; cur; cur = cur.parent)
    if (_local_lookup(cur, name, out)) return 1;
  return 0;
}

/* A parameter name and the name a form reads are both produced by the
   reader through `Atom.intern`, which gives one canonical value per
   spelling: a short name packs into the `Symbol` bits and a long one is
   interned. Identity therefore answers what `Var.equal` answers here, and
   without the descriptor lookup and tag decode that the general comparison
   pays on both sides. Verified over a `lib/` and a `src/` translate: 89,898
   matches, no case where the two disagreed. */
static int _local_lookup(LispEnv *env, Var name, Var &out) {
  int found = 0, at = 0;
  for (List p = env.params; p; p = p.cdr(), at++)
    if (p.car().u64 == name.u64) {
      out = env.values[at];
      found = 1;
    }
  return found || _binding_get(env.bindings, name, out);
}

/* call limits

   An evaluation stops with `<call-stack>` when it makes more calls than its
   budget or nests past its share of the C stack, and with `<interrupt>`
   while its session is interrupted. The public entry opens the budget, and
   the outermost call measures the stack. */

static void _spend_call(Lisp lisp) {
  if (lisp.call_exhausted || ++lisp.call_steps > lisp.call_step_max) {
    if (lisp.interrupted) $error.apply.interrupted();
    lisp.call_exhausted = 1;
    $error.apply.steps();
  }
}

/* `at` is the frame address of the call being made. The outermost call
   sets the base and the allowance the calls nested below it share. */
static void _check_stack(Lisp lisp, Lambda lambda, unsigned long at) {
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
static void _open_call_budget(Lisp lisp) {
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

/* entry points

   A public evaluation entry makes its session the active one and pushes
   the session's user Scope, where evaluated code allocates. A nested entry
   restores its caller's session when it returns. */

static Var _bad_session(String operation) {
  $error.entry.null(operation);
}

static macro Decorator $lisp.entry(Function $function, Expr $operation) {
  if (!lisp) return _bad_session($operation);
  Scope.push(&lisp.user);
  defer Scope.pop();
  Lisp prior_lisp = lisp_active;
  lisp_active = lisp;
  defer lisp_active = prior_lisp;
  @Code.body($function)
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
  _open_call_budget(lisp);
  return _apply_values(lisp, callable, values);
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
  _open_call_budget(lisp);
  Scope tokens_scope = $auto(Scope.new_named("Lisp tokens"));
  Tokenizer tokenizer = _scan_lisp_tokens(source, &tokens_scope);
  unsigned cursor = 0;
  Var result = %();
  loop {
    Var form = void;
    if (_read_form(tokenizer, source, 0, cursor, form) == <eof>) break;
    result = _eval(lisp, form, NULL);
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
  if (source.read_into(content) == <eof>) return l.eval_string(NULL);
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

/** Marks the actual Lambda installed for one lowered source function. */
Var lisp_source_function(Var callable) {
  if (callable is not <lambda>)
    $error.source.callable(callable);
  ((Lambda) callable).source_function = 1;
  return callable;
}
