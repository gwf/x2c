/*  literate-lisp.x -- a complete Lisp implementation in x2c

    Copyright (c) 2026 Gary William Flake                                             #####                 #####
                                                                                      ########           ########
    A recursive Lisp, generously commented in 1,000 lines.                           ##########         ##########
    It follows the production Lisp's value and capture rules.                             #######     #######
    Block comments explain how Lisp is implemented. Right-margin                           ######     ######
    comments show how x2c combines native C with a dynamic runtime.                         ######   ######
                                                                                             #####   #####
    A Lisp program is a tree of values. Evaluation walks that tree,                          #####   #####
    looks up names in environments, and calls functions with argument                       ######   ######
    values. Quotation keeps a form as data without evaluating it.                          ######     ######
                                                                                          #######     #######
      (+ 1 2)             // evaluates to 3                                          ##########         ##########
      '(+ 1 2)            // evaluates to the List (+ 1 2)                            ########           ########
      (eval '(+ 1 2))     // evaluates that List as a call, producing 3               #####                 #####

    Environments, closures, runtime Lisp macro expansion, and the reader
    follow the evaluator. Definitions written in Lisp add conditionals,
    bindings, and collection operations to the core evaluation rules.
                                                                                             ######
    x2c supplies values, collections, a tokenizer, and calls to native                          ####
    functions. This interpreter uses those tools to evaluate Lisp itself.                        ####
    It does not call the production Lisp evaluator. Each Lisp call uses                           ####
    a recursive native call.                                                                     ######
                                                                                                ########
    There are two kinds of macros. x2c expands $fail and $rest when                            ####  ####
    compiling this file. This interpreter runs Lisp macros while                              ####    ####
    evaluating a Lisp program; each macro returns a form to evaluate.                        ####      ####
                                                                                            ####        ####
    The implementation follows x2c Lisp, including its rules for capture                   ####          ######
    and errors; those rules sometimes differ from Scheme or Common Lisp.
*/

#include <unistd.h>                                                              // C and POSIX headers work in x2c.

/* Values, names, and memory -------------------------------------------------------------------------------------------

   Var can store a number, String, List, or callable. A nonempty List has a           +-----+-----+
   first element (car) and a remaining List (cdr); the empty List, (),                | car | cdr |----+
   marks its end. Nested Lists represent the structure of a Lisp                      +-----+-----+    |
   expression.                                                                           |             v
                                                                                       value     +-----+-----+
   Fn stores a parameter List, a body, and captured local bindings. During                       | car | ()  |
   a call, each parameter is bound to its corresponding argument value.                          +-----+-----+
   Captures copy local values when the closure is created. These bindings
   remain available when its body is evaluated later.

   A Lisp macro is a closure that receives argument forms before evaluation.
   The macro field tells the evaluator to use this calling rule. */
typedef struct Fn {
  List params;                                                                   // Immutable parameter List.
  Var body;                                                                      // Var holds values of different types.
  Map captures;                                                                  // Names -> captured values.
  int macro;                                                                     // C integer flag in an x2c record.
} *Fn;                                                                           // C typedef for a struct pointer.

typedef struct LispEnv {                                                         // Stack-local environment frame.
  Map bindings;                                                                  // Names -> local values.
  struct LispEnv *parent;                                                        // Outer frame; borrowed pointer.
} LispEnv;

/* Globals persist across evaluations. The native registry maps names to host
   functions. Special forms are recognized by their function values. */
typedef struct Interp {                                                          // Maps store Var keys and values.
  Map globals;                                                                   // Names -> global values.
  Map natives;                                                                   // Binding Strings -> native Funcs.
  Map reserved;                                                                  // Reserved names -> callable Funcs.
  Map specials;                                                                  // Callable Funcs -> special names.
} Interp;

/* $fail adds the operation name to an error. Its caller supplies the cause
   and any additional key/value details. */
macro Stmt $fail(Expr $cause, Expr $op, Expr @fields) {                          // Expr captures unevaluated syntax.
  raise %($cause (operation ${$op}) @fields);                                    // Insert one form; splice @fields.
}

/* Evaluation: the language in three rules -----------------------------------------------------------------------------

   A name evaluates to its bound value; a literal evaluates to itself.                     (+ 1 (* 2 3))
   A nonempty List is a call. First, evaluate its head to find what to call.                   / | \
   That value determines how to handle the arguments: evaluate them for an                    +  1  *
   ordinary function, or follow the rules of a special form or Lisp macro.                         / \
   Only () is false; zero and the empty String are true.                                          2   3

   For (+ 1 (* 2 3)), evaluation first resolves +, then evaluates the                  (* 2 3) -> 6
   arguments to 1 and 6. Applying + to these values returns 7. The same                (+ 1 6) -> 7
   rule handles computed heads, such as ((lambda (x) x) 7).

   A Lisp macro receives argument forms before evaluation. Its body returns
   a replacement form, which eval evaluates in the caller's environment.
   Thus a macro can choose which arguments run, and in what order. */
static Var Interp.eval(Interp &self, LispEnv *env, Var form) {
  if (form is void) $fail(<void-op>, "eval");                                    // Expand to code that raises an error.
  if (form.is_atom()) return self.lookup(env, form);                             // Dot syntax passes the receiver.
  if (form is not <list> || form.is_nil()) return form;                          // is inspects the Var tag.
  List expr = form;                                                              // Implicit Var -> List conversion.
  Var fn = self.eval(env, expr.car());                                           // List head is itself a Var.
  List args = expr.cdr();                                                        // O(1) tail access; no List copy.
  if (fn is <lambda>) {                                                          // The Var tag identifies a closure.
    Fn closure = fn.pointer();                                                   // Unbox the stored pointer.
    if (closure.macro) return self.eval(env, self.invoke(closure, args));        // Evaluate the form in caller scope.
  }
  else {
    if (fn is not <func>) raise %(not-call (actual ${fn.kind()}));               // ${...} evaluates an x2c expression.
    if (fn in self.specials) return self.special(env, self.specials[fn], args);  // Map value converts to Symbol.
  }
  List values = self.eval_args(env, args);                                       // Evaluate arguments left to right.
  return self.apply(fn, values);                                                 // Call with evaluated arguments.
}

/* Arguments are evaluated left to right into a List of values.
   If evaluation defines globals, reads files, or raises an error, a later
   failure leaves earlier effects intact. */
static List Interp.eval_args(Interp &self, LispEnv *env, List forms) {
  Array values = $auto([]);                                                      // Array literal; cleanup on exit.
  foreach (Var form in forms) values.push(self.eval(env, form));                   // Typed List iteration.
  return values;                                                                 // Build List before Array cleanup.
}

/* Special forms control evaluation ------------------------------------------------------------------------------------

   Ordinary functions receive evaluated arguments. Special forms decide                       (cond ...)
   which forms to evaluate. quote returns its argument as data; lambda                             |
   saves its body in a closure; cond evaluates only the selected body.                             v
   The evaluator handles each special form directly, using patterns to                           test
   extract its arguments.                                                                          |
                                                                                           +-------+-------+
   cond tests clauses in order. When a test is true, it evaluates that                     |               |
   clause's body and returns the result. The Lisp macro if builds a cond                  true           false
   form, so the evaluator needs no separate rule for if.                                   |               |
                                                                                           v               v
   def always writes a global binding. eval first obtains a form, then                    body           next
   evaluates it globally. apply obtains a callable and argument values in a
   List, then invokes it without evaluating those values again. */
static Var Interp.special(Interp &self, LispEnv *env, Symbol op, List args) {
  match (%($op @args)) {                                                         // $ inserts a value; @ splices a List.
    case %(quote ?form): return form;                                            // Pattern binds one value.
    case %(quasiquote ?form): return self.quasiquote(env, form, 0);              // Literal Symbol plus bound form.
    case %(def ?name ?form) if (name.is_atom()):                                 // Guard sees the pattern bindings.
      return self.globals[name] = self.eval(env, form);                          // Map assignment yields its value.
    case %(lambda ?(List params) ?body):                                         // Tag mismatch skips this case.
      return self.closure(env, params, body, 0);                                 // The returned Fn is stored in a Var.
    case %(macro ?(List params) ?body):                                          // Check List type while binding.
      return self.closure(env, params, body, 1);                                 // Same receiver syntax for macros.
    case %(cond *clauses) if (clauses): {                                        // * binds the remaining elements.
      foreach (Var clause in clauses) {                                            // Iterate without an index.
        match (clause) {                                                         // Nested structural match.
          case %(?test ?body):                                                   // Require exactly two elements.
            if (!self.eval(env, test).is_nil()) return self.eval(env, body);     // Chain calls on returned values.
          default: _bad_clause(clause);                                          // Fallback for unmatched List shapes.
        }
      }
      return %();                                                                // Empty List implicitly boxes as Var.
    }
    case %(eval ?form): return self.eval(NULL, self.eval(env, form));            // Evaluate the form in global scope.
    case %(apply ?fn ?values): {                                                 // Pattern binds callable/value forms.
      Var callable = self.eval(env, fn),                                         // Evaluate the callable expression.
          actual = self.eval(env, values);                                       // Evaluate the argument expression.
      return self.apply(callable, _list_argument(actual, "apply"));              // Check List; apply evaluated values.
    }
    case %(bind ?name ?sig): {                                                   // Extract two argument forms.
      Var target = self.eval(env, name),                                         // Binding name as a dynamic value.
          type = self.eval(env, sig);                                            // Native signature is ordinary data.
      return self.bind(target, type);                                            // Return native Func boxed as Var.
    }
    case %(import ?form): {                                                      // Pattern binds the path expression.
      Var path = self.eval(env, form);                                           // Receiver call yields a Var.
      Atom hook = Atom.intern("_x2c.import-hook");                               // Atom supports longer names.
      _string_argument(path, "import");                                          // C literal promotes to String.
      if (hook in self.globals)                                                  // Map membership by key.
        return self.apply(self.globals[hook], %($path));                         // Construct a one-argument List.
      return _import_file(self, path);                                           // Var path converts to String.
    }
  }
  return _bad_form(op, args);                                                    // Symbol and List passed directly.
}

/* Applying a value ----------------------------------------------------------------------------------------------------

   eval evaluates expressions; apply calls a function with values that                   callable + values
   have already been evaluated. For example, (apply list '(a b)) returns                          |
   (a b). Neither a nor b is looked up as a name.                                                 v
                                                                                                apply
   Calling a closure binds its parameters and evaluates its saved body.                           |
   Calling a native function passes the values through Func to x2c code.                 +--------+--------+
   apply can also call a saved alias of apply, using the same rules.                     |        |        |
   It rejects Lisp macros because macros need unevaluated argument forms                 v        v        v
   and must evaluate their expansion in the caller's environment.                     closure   native   apply*

                                                                                      * invokes supplied callable
*/
static Var Interp.apply(Interp &self, Var fn, List values) {
  if (fn is <lambda>) {                                                          // Inspect the callable tag.
    Fn closure = fn.pointer();                                                   // Unbox the closure pointer.
    if (closure.macro) $fail(<not-call>, "apply", <actual>, fn.kind());          // kind() supplies the error type.
    return self.invoke(closure, values);                                         // Receiver call passes self first.
  }
  if (fn is not <func>) raise %(not-call (actual ${fn.kind()}));                 // Insert the type into the error List.
  if (fn in self.specials) {                                                     // Map membership by callable value.
    if (self.specials[fn] != <apply>.var())                                      // Box a Symbol for Var comparison.
      $fail(<not-call>, "apply", <actual>, fn.kind());                           // Compile-time macro; runtime error.
    match (values) case %(?callable ?args):                                      // Destructure by pattern.
      return self.apply(callable, _list_argument(args, "apply"));                // C literal promotes to String.
    return _bad_form(<apply>, values);                                           // <apply> is a Symbol literal.
  }
  return _native_call(fn, values);                                               // Implicit Var -> Func conversion.
}

/* Name lookup and captured bindings -----------------------------------------------------------------------------------

   Lookup searches local environments from nearest to farthest, then                      +-------------+
   globals, then reserved names. An inner binding hides an outer binding                  | local frame |
   without changing it. A Map lookup reports whether the name exists,                     +------+------+
   so a missing name differs from a name bound to ().                                            | parent
                                                                                                 v
   This closure captures the local binding x = 10:                                        +-------------+
                                                                                          | outer frame |
     (def add-ten (let ((x 10)) (lambda (y) (+ x y))))                                    +------+------+
     (add-ten 7)     // 17, after the let call has returned                                      |
                                                                                                 v
   Call frames can live on the native stack. Closures and their capture                       globals
   Maps belong to the session Scope, so saved bindings outlive those calls.                      |
   The values they refer to keep their ordinary ownership; immutable                             v
   Strings and Lists live in canonical pools.                                                 reserved
*/

static Var Interp.lookup(Interp &self, LispEnv *env, Var name) {
  Var local;
  if (_local_value(env, name, local)) return local;                              // Use the nearest local binding.
  if (name in self.globals) return self.globals[name];                           // Global Map: test key, fetch value.
  if (name in self.reserved) return self.reserved[name];                         // Reserved Map: same key operations.
  raise %(unbound (name $name));                                                 // $name inserts the named value.
}

/* A local lookup shared by evaluation and capture. */
static int _local_value(LispEnv *env, Var name, Var &value) {                    // Return the Var through a reference.
  for (; env; env = env.parent)                                                  // Walk borrowed frames by dot access.
    if (env.bindings.try_get(name, value)) return 1;                             // Success separates nil from absence.
  return 0;                                                                      // Zero means no local binding exists.
}

/* Capture local values that the body may read. Negative depth scans even
   data in calls whose behavior is unknown; positive depth tracks quasiquote.
   Globals are looked up later. Borrowed objects must outlive the closure. */
static void Interp.capture(
  Interp &self, LispEnv *env, Var form, List bound, int depth, Map captures) {   // Borrow self; point to a local frame.
  if (form.is_atom()) {                                                          // Atoms include Symbols or long names.
    Var value;                                                                   // Local lookup fills this Var.
    if (depth <= 0 && !(form in bound) &&                                        // Exclude nested parameters by name.
        _local_value(env, form, value) && !(form in captures))                   // Find the value; capture it once.
      captures[form] = value;                                                    // Copy the Var, keeping any reference.
    return;
  }
  if (form is not <list> || form.is_nil()) return;                               // Inspect only nonempty Lists.
  List items = form;                                                             // Implicit Var -> List conversion.
  Var head = items.car();                                                        // The head may be an expression.
  if (depth < 0) {                                                               // The call may treat data as code.
    foreach (Var part in items) self.capture(env, part, bound, depth, captures);   // Typed iteration; recursive call.
    return;
  }
  if (depth > 0) {                                                               // Skip names inside template data.
    int inner = depth;                                                           // Track nesting with a native integer.
    List parts = items;                                                          // Immutable Lists share tail storage.
    if (head == <quasiquote>) { inner++; parts = items.cdr(); }                  // Compare a Symbol with a Var.
    if (head == <unquote> || head == Atom.intern("unquote-splicing")) {          // Intern the long splice name.
      inner--; parts = items.cdr();                                              // Unquote removes one nesting level.
    }
    foreach (Var part in parts) self.capture(env, part, bound, inner, captures);   // Pass each child its nesting depth.
    return;
  }
  self.capture(env, head, bound, 0, captures);                                   // The call head may read a local.
  Var callable;                                                                  // Var holds functions and closures.
  if (!head.is_atom() || head in bound ||                                        // The function is not yet known.
      !_local_value(env, head, callable)) {                                      // Globals may change before the call.
    foreach (Var part in items.cdr())                                              // Iterate forms without copying them.
      self.capture(env, part, bound, -1, captures);                              // Unknown calls may evaluate data.
    return;
  }
  Symbol special = callable is <func> && callable in self.specials               // Look up the function as a Map key.
    ? self.specials[callable].symbol() : 0;                                      // Map lookup, then Var -> Symbol.
  if (special == <quote>) return;                                                // Known quote leaves its data unread.
  if (special == <lambda> || special == <macro>) {                               // lambda and macro introduce names.
    List rest = items.cdr();                                                     // Share the parameter and body tail.
    if (rest && rest.car() is <list>)                                            // C truth test, then List tag test.
      foreach (Var name in rest.car().list()) bound = cons(name, bound);           // Add nested parameters to bound.
    foreach (Var part in rest.cdr()) self.capture(env, part, bound, 0, captures);  // Parameters hide outer bindings.
    return;
  }
  int inner = special == <quasiquote> ? 1 :                                      // Start quasiquote at depth one.
    callable is <lambda> && ((Fn) callable.pointer()).macro ? -1 : 0;            // Read the Fn flag for Lisp macros.
  foreach (Var part in items.cdr()) self.capture(env, part, bound, inner, captures);
}

static Var Interp.closure(
  Interp &self, LispEnv *env, List params, Var body, int macro) {
  Map captures = {};                                                             // Each closure owns a capture Map.
  self.capture(env, body, params, 0, captures);                                  // Capture before the call returns.
  Fn closure = Scope.malloc(sizeof(struct Fn));                                  // Allocate in the current Scope.
  *closure = (struct Fn) { params, body, captures, macro };                      // C dereference and compound literal.
  return Var.new(<lambda>, closure);                                             // Tag an already allocated pointer.
}

/* Bind parameters to argument values; (first . rest) collects the remainder.
   Lookup searches parameters, captures, globals, then reserved names.
   The caller's local bindings are outside this chain. */
static Var Interp.invoke(Interp &self, Fn closure, List values) {
  Map bindings = $auto({});                                                      // Map literal; cleanup on exit.
  for (List params = closure.params; params; params = params.cdr()) {            // Walk parameters to the empty List.
    Var (name, rest) = params;                                                   // Extract and convert by position.
    if (name.is_atom() && name.str() == ".") {                                   // Canonical String identity test.
      if (!params.cdr()) $fail(<bad-sig>, "apply", <value>, closure.body);       // Error detail needs an x2c String.
      bindings[rest] = values;                                                   // List boxes as the Map value.
      values = NULL;
      break;
    }
    if (!values) $fail(<bad-arity>, "apply", <value>, closure.body);             // Macro builds the runtime error.
    bindings[name] = values.car();                                               // Receiver-style List access.
    values = values.cdr();                                                       // Advance the argument tail too.
  }
  if (values) $fail(<bad-arity>, "apply", <value>, closure.body);                // Macro constructs the error record.
  LispEnv captured = { closure.captures, NULL };                                 // No link to the caller's environment.
  LispEnv local = { bindings, &captured };                                       // & takes a stack frame's C address.
  return self.eval(&local, closure.body);                                        // C stack address passed to eval.
}

/* Quotation as a language for constructing code -----------------------------------------------------------------------

   quote returns its argument without evaluation. Quasiquote evaluates the             x = 7; xs = (8 9)
   comma-marked expressions within a template. Comma-at inserts the
   elements of a List into the surrounding List:                                           `(a ,x ,@xs)
                                                                                                |   |
     (let ((x 7) (xs '(8 9))) `(a ,x ,@xs))     // (a 7 8 9)                                    v   v
                                                                                           (a   7   8 9)
   quasiquote returns one value. When that value is a List,
   quoted_elements builds it from the template's elements.                            ,x: one value
   An ordinary element adds one value; a splice adds its List's elements.             ,@xs: List elements
   The builder visits each element once, keeping their order.

   Nested quasiquote increments depth; nested unquote decrements it.
   Unquote evaluates only at depth zero; otherwise it stays in the returned
   form. */
static Var Interp.quasiquote(Interp &self, LispEnv *env, Var form, int depth) {
  if (form is not <list> || form.is_nil()) return form;                          // Runtime tag inspection.
  List expr = form;                                                              // Implicit Var -> List conversion.
  Var (head, argument) = expr;                                                   // Positional List destructuring.
  Var (quote, unquote, splice) = %(quasiquote unquote unquote-splicing);         // Literal names unpack into Vars.
  if (head == quote)                                                             // Var equality with a Symbol value.
    return cons(head, self.quoted_elements(env, expr.cdr(), depth + 1));         // Keep the nested quasiquote form.
  if (head == unquote || head == splice) {                                       // Compare Symbols held in Vars.
    if (expr.len() != 2) $fail(<bad-arity>, "quasiquote", <value>, form);        // Receiver-style length query.
    if (depth)                                                                   // Inactive unquote stays in the form.
      return cons(head, self.quoted_elements(env, expr.cdr(), depth - 1));
    Var value = self.eval(env, argument);                                        // Recursive receiver-style call.
    if (head == splice)                                                          // Var equality against a Symbol.
      $fail(<bad-types>, "quasiquote-splice", <actual>, form.kind());            // Runtime kind in macro-built error.
    return value;
  }
  return self.quoted_elements(env, expr, depth);                                 // Siblings remain ordinary elements.
}

static List Interp.quoted_elements(
  Interp &self, LispEnv *env, List items, int depth) {
  Array values = $auto([]);                                                      // Collect values in a temporary Array.
  foreach (Var item in items) {                                                    // Recurse only into nested forms.
    match (item) {
      case %(unquote-splicing ?argument) if (!depth): {
        Var value = self.eval(env, argument);                                    // Evaluate each splice once, in order.
        if (value is not <list>)
          $fail(<bad-types>, "quasiquote-splice", <actual>, value.kind());
        foreach (Var part in value.list()) values.push(part);                      // Splice the contributed elements.
      }
      default: values.push(self.quasiquote(env, item, depth));                   // An ordinary element adds one value.
    }
  }
  return values;                                                                 // Build a List before Array cleanup.
}

/* Errors are part of the language's observable behavior ---------------------------------------------------------------

   An invalid call, an unbound name, and a wrong argument type raise                            raise
   different errors. Each error is a List: a cause followed by details                            |
   such as the operation name or actual type. A catch pattern can match                           v
   the cause and bind those details to local names.                                    (cause (key value) ...)
                                                                                                  |
   $fail includes the operation name in the error List. For example,                              v
   _list_argument reports bad-types with the actual and expected types.                     catch pattern
   _bad_clause reports a wrong clause type or a wrong number of parts.                            |
   These details let callers inspect an error as data. The command-line                           v
   handler prints the same List for a person to read.                                        bound fields
*/

static List _list_argument(Var value, String op) {
  if (value is not <list>)                                                       // Runtime type inspection.
    $fail(<bad-types>, op, <actual>, value.kind(), <want>, "List");              // op boxes as Var in the error List.
  return value;                                                                  // Implicit Var -> List conversion.
}

static String _string_argument(Var value, String op) {
  if (value is not <string>)                                                     // Runtime type inspection.
    $fail(<bad-types>, op, <actual>, value.kind(), <want>, "String");            // op boxes as Var in the error List.
  return value;                                                                  // Implicit Var -> String conversion.
}

static Var Interp.bind(Interp &self, Var name, Var sig) {
  _string_argument(name, "bind");                                                // C literal promotes to String.
  if (sig is not <list>) $fail(<bad-sig>, "bind", <value>, sig);                 // Type check and error macro.
  if (name in self.natives) return self.natives[name];                           // Hash lookup; no linear name scan.
  raise %(no-symbol (name $name) (sig $sig));                                    // Runtime values in an error List.
}

static void _bad_clause(Var clause) {
  if (clause is not <list>)                                                      // Runtime type inspection.
    $fail(<bad-types>, "cond", <value>, clause, <want>, "List");                 // Expand to code that raises an error.
  $fail(<bad-arity>, "cond-clause", <expected>, 2, <actual>,                     // Symbol keys; runtime boxed values.
        clause.list().len(), <value>, clause);                                   // Chain conversion; O(n) List length.
}

static Var _bad_form(Symbol name, List args) {
  if (name == <lambda> || name == <macro>)                                       // Constant-time Symbol comparisons.
    $fail(<bad-sig>, name, <value>, args);                                       // Symbol and List box as error values.
  int n = args.len();                                                            // Receiver-style length query.
  if (name == <def>)                                                             // Constant-time Symbol comparison.
    $fail(<bad-arity>, "def", <expected>, 2, <actual>, n, <value>, args);        // List and integers become error data.
  int want = name == <apply> || name == <bind> ? 2 : 1;                          // C ternary with Symbol comparisons.
  $fail(<bad-arity>, name.str(), <expected>, want, <actual>, n);                 // Symbol spelling via receiver syntax.
}

/* Reading: from characters to values ----------------------------------------------------------------------------------

   The reader turns text into values without evaluating them.                              "(+ 1 2)"
   Reading (+ 1 2) produces a List containing the name + and two numbers.                       |
   It does not look up + or add the numbers. Evaluation and macros use                          v
   the same Lists that quotation returns as data, so code needs no                            tokens
   separate representation.                                                                     |
                                                                                                v
   The tokenizer separates words, numbers, strings, and punctuation.                      +-----+-----+
   After an opening parenthesis, the reader collects forms until the                      |  +  |  *--+-> (1 2)
   closing parenthesis. Nested Lists use the same recursive rule.                         +-----+-----+
   Prefixes expand into Lists: 'x becomes (quote x); backquote, comma,
   and comma-at become quasiquote, unquote, and unquote-splicing.
*/
typedef struct Reader {
  Tokenizer tokens;                                                              // Runtime tokenizer handle.
  String source;                                                                 // Immutable String handle.
  unsigned base, start;                                                          // C offsets into source bytes.
} Reader;

static Var Reader.error(Reader &self, Symbol cause, unsigned at) {
  int line = 1, column = 1;
  scan_next_line_col(self.source, (int) at, &line, &column);                     // C addresses for output parameters.
  if (cause == <incomplete>)                                                     // Symbols compare as integers.
    raise %(incomplete (source ${self.source})                                   // ${...} interpolates an expression.
                       (line $line) (column $column));                           // $line interpolates a named value.
  raise %(malformed (source ${self.source}) (line $line) (column $column));      // Expression and identifier insertion.
}

static Var Reader.form(Reader &self, Token token) {
  if (!token || token.type == <eof>)                                             // Constant-time integer Symbol test.
    return self.error(<incomplete>, self.start);                                 // Symbol literal as a call argument.
  String text = token.text, prefix = NULL;                                       // Immutable String handle.
  switch (token.type) {                                                          // C switch dispatches on Symbols.
    case <error>:                                                                // Symbol constant in C switch.
      if (self.tokens.status() == <incomplete>)                                  // Method call and Symbol comparison.
        return self.error(<incomplete>, self.start);                             // Receiver call builds a source error.
      break;
    case <"(">: {                                                                // Quoted Symbol in a switch.
      Array elements = $auto([]);                                                // Array literal; cleanup on exit.
      while (1) {
        Token next = self.tokens.next();                                         // Pull a token with receiver syntax.
        if (next && next.type == <")">) return elements.list();                  // List result boxes as Var.
        elements.push(self.form(next));                                          // Compose two receiver-style calls.
      }
    }
    case <"'">:  prefix = "quote";      break;                                   // C literal promotes to String.
    case <"`">:  prefix = "quasiquote"; break;                                   // Quoted Symbol; C literal promotes.
    case <",">:  prefix = "unquote";    break;                                   // Symbol dispatch; String assignment.
    case <",@">: prefix = "unquote-splicing"; break;                             // Symbol can encode punctuation.
    case <lit-char*>:                                                            // Token kind is an integer Symbol.
      return String.new_len(text + 1, token.len - 2).unescape();                 // Chain construction and unescaping.
    case <lit-int>: {                                                            // Token types are Symbol constants.
      long value;                                                                // Ordinary C integer local.
      if (!text.try_long(&value)) break;                                         // Conversion with a success result.
      if (value == (int) value) return (int) value;                              // int implicitly boxes as Var.
      return value;                                                              // Native long implicitly boxes as Var.
    }
    case <lit-float>: {                                                          // Select a floating-point token.
      double value;                                                              // Ordinary C scalar local.
      if (text.try_double(&value)) return value;                                 // double implicitly boxes as Var.
      break;
    }
    case <lit-symbol>: {                                                         // Switch on the encoded token kind.
      String inner = text[1] == '"'                                              // C byte indexing of String storage.
        ? String.new_len(text + 2, token.len - 4).unescape()                     // C pointer arithmetic into text.
        : String.new_len(text + 1, token.len - 2);                               // C pointer span -> immutable String.
      if (inner) return Symbol.new(inner);                                       // Symbol result implicitly boxes.
      break;
    }
    case <ident>:                                                                // Identifier token as a Symbol tag.
      return Atom.intern(text.unescape());                                       // Intern exact short or long names.
  }
  if (prefix) {                                                                  // Canonical empty String is NULL.
    Var name = Atom.intern(prefix), inner = self.form(self.tokens.next());       // Atom and Var results in Var locals.
    return %($name $inner);                                                      // $name/$inner insert named values.
  }
  return self.error(<malformed>, self.base + token.pos);                         // C offset math inside a method call.
}

/* Tokens belong to one source batch. Parsed values outlive token storage:
   a definition can save a body for a later call. */
static Reader Reader.scan(String source, unsigned base, Scope *storage) {
  Reader reader = { .source = source, .base = base };                            // Named struct initializers.
  $scope(storage) {                                                              // Redirect Scope; restore on exit.
    reader.tokens = Tokenizer.new(                                               // Ordinary runtime tokenizer.
      source ? source + base : NULL, <lisp>);                                    // C pointer offset; Symbol mode.
    reader.tokens.scan();                                                        // Receiver-style function call.
  }
  return reader;                                                                 // Return the ordinary struct by value.
}

/* Reader.read returns void at EOF; () is a valid form. Incomplete input
   raises an error, and the REPL retains the text for the next line. */
static Var Reader.read(Reader &self) {
  Token first = self.tokens.next();                                              // Receiver-style token access.
  if (!first || first.type == <eof>) return void;                                // void differs from the empty List.
  self.start = self.base + first.pos;                                            // C arithmetic on source offsets.
  return self.form(first);                                                       // Dot syntax calls a Reader method.
}

/* Native functions ----------------------------------------------------------------------------------------------------

   Lisp calls native x2c functions through Func. A Func signature gives                  Lisp argument values
   the argument and result types. eval first evaluates the argument                               |
   forms. Then _native_call packs those values into FuncArg entries                               v
   and passes them to Func.apply.                                                             Func.apply
                                                                                                  |
   Native predicates return Lisp true or (). Arithmetic and collection                            v
   functions supply the basic operations. The Lisp definitions below                       typed C arguments
   combine them into functions such as map, filter, and foldl.                                    |
                                                                                                  v
                                                                                              C function
*/

static Var _native_call(Func native, List values) {
  FuncArg *args = Scope.malloc(values.len() * sizeof(FuncArg));                  // Allocate one FuncArg per value.
  defer Scope.free(args);                                                        // Cleanup on every block exit.
  int count = 0;
  foreach (Var value in values) args[count++] = FuncArg.value(value);              // Pack values into a native C array.
  return native.apply(count, args);                                              // Checked native call through Func.
}

static int _is_number(Var v) => v.is_integer() || v.is_floating();               // Accept integers and floating point.

static Var _bool(int x)      => x ? <true>.var() : %().var();                    // => returns true or () as a Var.

static Var _car(Var v) {                                                         // Check for a List before cell access.
  if (v is not <list>) $fail(<bad-types>, "car", <kind>, v.kind());              // Macro emits the error record.
  return v.car();                                                                // Receiver form of the List accessor.
}

static Var _cdr(Var v) {                                                         // Check for a List before tail access.
  if (v is not <list>) $fail(<bad-types>, "cdr", <kind>, v.kind());              // Same cause as car reports.
  return v.cdr();                                                                // List result boxes back into a Var.
}

static Var _atom(Var v)      => _bool(v is not <list> || v.is_nil());            // Runtime tag plus receiver predicate.
static Var _pair(Var v)      => _bool(v is <list> && !v.is_nil());               // C logic over Var predicates.
static Var _list(Var v)      => _bool(v is <list>);                              // Constant-time Var tag inspection.
static Var _number(Var v)    => _bool(_is_number(v));                            // Expression-bodied function.
static Var _string(Var v)    => _bool(v is <string>);                            // Dynamic type test in an expression.
static Var _symbol(Var v)    => _bool(v.kind() == <symbol>);                     // Runtime kind as a Symbol.
static Var _procedure(Var v) => _bool(v is <func> || v is <lambda>);             // Two callable tags.
static Var _eq(Var a, Var b) => _bool(a == b);                                   // Var equality follows value types.

static Var _compare(Var a, Var b) {
  if (!_is_number(a) || !_is_number(b))                                          // C logic over Var type predicates.
    $fail(<bad-types>, "lisp_compare",                                           // $fail builds the raised error.
          <left-kind>, a.kind(), <right-kind>, b.kind());                        // Runtime types in the error record.
  return a.compare(b);                                                           // Var comparison via receiver syntax.
}

static Var _add(Var a, Var b) =>                                                 // Strings concatenate.
  a is <string> || b is <string> ? %"$a$b".var() : a.binary(<+>, b);             // Numbers use Var arithmetic.

static Var _plus(List values) {
  Var seed = 0;                                                                  // Implicit int -> Var conversion.
  if (values && values.car() is <string>) seed = String.new("");                 // String implicitly boxes as Var.
  return values.foldl(seed, _add);                                               // Direct function uses cached Func.
}

/* + and * fold from 0 and 1. - and / require arguments; unary calls compute
   0-x or 1/x. Integer / truncates. Longer calls fold left: (- 10 3 2) is 5. */
static Var _arithmetic(List values, Symbol op, Var identity) {
  if (!values) $fail(<bad-arity>, op.str(), <expected>, 1, <actual>, 0);         // Macro constructs runtime errors.
  Var result = values.car();                                                     // List head is already a Var.
  if (!values.cdr()) return identity.binary(op, result);                         // Var arithmetic selected by Symbol.
  foreach (Var value in values.cdr()) result = result.binary(op, value);           // Iterate a List suffix.
  return result;
}

static Var _minus(List xs)  => _arithmetic(xs, <->, 0);                          // 0 promotes to Var.
static Var _divide(List xs) => _arithmetic(xs, </>, 1);                          // 1 promotes to Var.
static Var _times(List xs)  => xs.foldl(1, %!(a, b) => a.binary(<*>, b));        // %! constructs a callable.

/* Comparisons test neighboring pairs: (< 1 2 3) means 1 < 2 and 2 < 3.
   The first false comparison ends the test. Later values are not compared,
   so a wrong type in those values cannot raise a comparison error. */
static Var _chain(List values, String op, int want, int expect) {
  int n = values.len();                                                          // List length walks the cons cells.
  if (n < 2) $fail(<bad-arity>, op, <expected>, 2, <actual>, n);                 // Values box into the error record.
  Var left = values.car();                                                       // Receiver access yields a Var.
  foreach (Var right in values.cdr()) {                                            // Typed iteration over a suffix.
    int order = _compare(left, right).integer();                                 // Chain a call and Var conversion.
    if (expect ? order != want : order == want) return _bool(0);                 // C ternary selects comparison logic.
    left = right;
  }
  return _bool(1);                                                               // Convert C truth to Lisp truth.
}

static Var _eq_chain(List xs) => _chain(xs, "=",  0, 1);                         // Expression body returns directly.
static Var _lt_chain(List xs) => _chain(xs, "<", -1, 1);                         // C literal promotes to String.
static Var _le_chain(List xs) => _chain(xs, "<=", 1, 0);                         // Typed List in; dynamic Var out.
static Var _gt_chain(List xs) => _chain(xs, ">",  1, 1);                         // Call the shared comparison helper.
static Var _ge_chain(List xs) => _chain(xs, ">=", -1, 0);                        // One helper defines all comparisons.

/* These return Var because the native signature appears in Lisp errors. */
static Var _str(Var v)                        => v.str();                        // String result boxes as Var.
static Var _repr(Var v)                       => v.repr();                       // Readable formatting via receiver.
static Var _string_append(String a, String b) => a + b;                          // String +; result boxes as Var.
static Var _string_downcase(String s)         => s.lower();                      // Receiver call; result boxes as Var.
static Var _substring(String s, int a, int b) => s.getslice(a, b, 1);            // String slice; result boxes as Var.

static Var _match_replace(List input, Var pat, Var template) {
  Var result;                                                                    // Dynamic value for the match result.
  if (!input.try_match_replace(pat, template, result)) return input;             // Match/replace with a success result.
  return result;
}

static Var _read_file(String path) => path.open("r").string_close();             // Chain open, read, and close.

static Var _write_file(String path, String text) {
  File file = path.open("w");                                                    // String receiver opens a File.
  int wrote = !text || file.puts(text) >= 0,                                     // Native fputs via inline adapter.
      closed = file.close() == 0;                                                // Native fclose; always attempted.
  return _bool(wrote && closed);                                                 // C Boolean result -> Lisp truth.
}

/* Function conversion infers fixed signatures. A rest function receives all
   arguments in one List; $rest supplies that signature at compile time. */
macro Expression $rest(Expr $fn) =>                                              // Expand to a Func constructor call.
  Func.new_rest($fn, %((func (("List"))) "Var"));                                // Native signature as a List literal.

static void _install_natives(Interp &self) {
  List natives = %(                                                              // Rows: Lisp name, bind name, Func.
    (car             "Var_car"               ${Func.var(_car)})                  // Infer the x2c function signature.
    (cdr             "Var_cdr"               ${Func.var(_cdr)})                  // ${...} evaluates a full expression.
    (cons            "Var_cons"              ${Func.var(Var.cons)})              // Direct function caches Func wrapper.
    (atom?           "lisp_atom"             ${Func.var(_atom)})                 // Nested quoted text is x2c String.
    (pair?           "lisp_pair"             ${Func.var(_pair)})
    (list?           "lisp_list"             ${Func.var(_list)})
    (eq?             "lisp_eq"               ${Func.var(_eq)})
    (type            "lisp_type"             ${Func.var(Var.tag)})
    (number?         "lisp_number"           ${Func.var(_number)})
    (string?         "lisp_string"           ${Func.var(_string)})               //          /\_/\     _
    (symbol?         "lisp_symbol"           ${Func.var(_symbol)})               //         ( -.- )   / )
    (procedure?      "lisp_procedure"        ${Func.var(_procedure)})            //          > ^ <    /
    (reverse         "List_reverse"          ${Func.var(List.reverse)})          //          /   \    |
    (length          "List_len"              ${Func.var(List.len)})              //         /|   |\   |
    (_match          "List_match"            ${Func.var(List.match)})            //        (_|___|_)_/
    (match-replace   "lisp_match_replace"    ${Func.var(_match_replace)})        //          Mako
    (search          "List_search"           ${Func.var(List.search)})
    (_search-replace "List_search_replace"   ${Func.var(List.search_replace)})
    (_add            "lisp_add"              ${Func.var(_add)})
    (_binary         "Var_binary"            ${Func.var(Var.binary)})
    (_compare        "lisp_compare"          ${Func.var(_compare)})
    (+               "lisp_plus"             ${$rest(_plus)})                    // Macro supplies the rest signature.
    (-               "lisp_minus"            ${$rest(_minus)})
    (*               "lisp_times"            ${$rest(_times)})
    (/               "lisp_divide"           ${$rest(_divide)})
    (=               "lisp_eq_chain"         ${$rest(_eq_chain)})                //           /\_/\
    (<               "lisp_lt_chain"         ${$rest(_lt_chain)})                //          ( o.o )
    (<=              "lisp_le_chain"         ${$rest(_le_chain)})                //           > ^ <
    (>               "lisp_gt_chain"         ${$rest(_gt_chain)})                //          /     \
    (>=              "lisp_ge_chain"         ${$rest(_ge_chain)})                //         /       \
    (str             "lisp_str"              ${Func.var(_str)})                  //        (  (   )  )    /)
    (repr            "lisp_repr"             ${Func.var(_repr)})                 //         \__)_(__/____//
    (string-length   "String_len"            ${Func.var(String.len)})            //            Liko
    (_string-append  "lisp_string_append"    ${Func.var(_string_append)})
    (substring       "lisp_substring"        ${Func.var(_substring)})
    (string-downcase "lisp_string_downcase"  ${Func.var(_string_downcase)})
    (()              "lisp_read_file"        ${Func.var(_read_file)})            // No global name; available via bind.
    (()              "lisp_write_file"       ${Func.var(_write_file)})
    (()              "List_sort"             ${Func.var(List.sort)})
  );
  foreach (List row in natives) {                                                  // Typed List traversal.
    (Var name, String symbol, Func fn) = row;                                    // Convert each positional binding.
    self.natives[symbol] = fn;                                                   // Func boxes as a Map value.
    if (!name.is_nil()) self.globals[name] = fn;                                 // Receiver-style Var predicate.
  }
}

/* Building the rest of the language in itself -------------------------------------------------------------------------
                                                                                       native functions + core
   Startup evaluates these definitions in order. First, defmacro defines                          |
   Lisp macros. Then defun and if make function definitions and conditions                        v
   shorter. Recursive functions add map, filter, and folds.                                    defmacro
                                                                                                  |
   Each Lisp macro returns a form built from operations the evaluator                       +-----+-----+
   already understands. For example, defun builds a def containing a                        |           |
   lambda. Later definitions use these macros together with the native                      v           v
   functions registered above.                                                            defun         if
                                                                                            |           |
   The percent literal stores all these definitions in one List.                            +-----+-----+
   _interpreter evaluates each definition at startup, adding its bindings                         |
   to the global environment.                                                                     v
                                                                                        map / foldl / let / ...
*/

static List _stdlib = %(                                                         // Initialize the static List once.
  (def nil ())                                                                   // Empty List is literal data here.
  (def true 'true)                                                               // Quote keeps true as a Symbol value.
  (def false nil)                                                                // Bare nil is a literal Symbol.
  (def defmacro                                                                  // Define a Lisp macro for runtime use.
    (macro (name params body) `(def ,name (macro ,params ,body))))               // ` template; , inserts each value.
  (defmacro defun (name params body) `(def ,name (lambda ,params ,body)))        // defun expands to a Lisp lambda.
  (defmacro if (test ontrue onfalse) `(cond (,test ,ontrue) (true ,onfalse)))    // Expand if into the core cond form.
  (defun list (. values) values)                                                 // Dot denotes a Lisp rest parameter.
  (defun not (value) (if value false true))                                      // Use the Lisp if macro defined above.
  (defun null? (value) (eq? value nil))                                          // Call the registered eq? function.
  (def equal? eq?)                                                               // Bind another name to one callable.
  (defmacro and (. forms)                                                        // Runtime macro: short-circuiting.
    (if (null? forms) true                                                       // Reuse the null? defined above.
        (if (null? (cdr forms)) (car forms)                                      // cdr advances; car extracts one form.
            `(if ,(car forms) (and ,@(cdr forms)) false))))                      // ` template; , value; ,@ elements.
  (defmacro or (. forms)                                                         // Generated names may clash at use.
    (if (null? forms) false                                                      // Test for remaining argument forms.
        (if (null? (cdr forms)) (car forms)                                      // cdr advances; car extracts one form.
            `((lambda (_or_value)                                                // Backquote builds a Lisp template.
                (if _or_value _or_value (or ,@(cdr forms))))                     // ,@ inserts the remaining forms.
              ,(car forms)))))                                                   // , evaluates and inserts one form.
  (defun _last (values)                                                          // Ordinary recursive Lisp function.
    (if (null? values) nil                                                       // Stop when the List is empty.
        (if (null? (cdr values)) (car values) (_last (cdr values)))))            // Tail recursion finds the last value.
  (defun begin (. values) (_last values))                                        // Return last pre-evaluated argument.
  (defun map (procedure values)                                                  // Structural recursion over a List.
    (if (null? values) nil                                                       // No input produces an empty List.
        (cons (procedure (car values)) (map procedure (cdr values)))))           // Call fn; build a List with cons.
  (defun filter (predicate values)                                               // Keep elements satisfying a callable.
    (if (null? values) nil                                                       // Stop before invoking the predicate.
        (if (predicate (car values))                                             // Native car feeds a callable value.
            (cons (car values) (filter predicate (cdr values)))                  // cons retains a selected element.
            (filter predicate (cdr values)))))                                   // Recurse without retaining the head.
  (defun foldl (procedure initial values)                                        // Pass a callable as a value.
    (if (null? values) initial                                                   // Empty input returns the accumulator.
        (foldl procedure (procedure initial (car values)) (cdr values))))        // Fold invokes the supplied function.
  (defun member (value values)                                                   // Return matching suffix, or ().
    (if (null? values) nil                                                       // No candidates remain: return nil.
        (if (equal? value (car values)) values (member value (cdr values)))))    // equal? is an alias for eq?.
  (defun assoc (key pairs)                                                       // Return matching row, or ().
    (if (null? pairs) nil                                                        // Use the shared empty-List predicate.
        (if (and (pair? (car pairs)) (equal? key (car (car pairs))))             // and guards access to an empty List.
            (car pairs)                                                          // Return the whole matching row.
            (assoc key (cdr pairs)))))                                           // Continue through remaining rows.
  (defun _append2 (left right)                                                   // Immutable Lists safely share tails.
    (if (null? left) right (cons (car left) (_append2 (cdr left) right))))       // Base case shares the right List.
  (defun _append_lists (lists)                                                   // Repeat two-List append.
    (if (null? lists) nil                                                        // No Lists: return the empty List.
        (if (null? (cdr lists)) (car lists)                                      // One List: reuse it unchanged.
            (_append2 (car lists) (_append_lists (cdr lists))))))                // Compose the two append helpers.
  (defun append (. lists) (_append_lists lists))                                 // Rest parameter gathers List values.
  (defun sub (a b) (_binary a '- b))                                             // Lisp calls native Var.binary.
  (defun mul (a b) (_binary a '* b))                                             // Native arithmetic, Lisp call syntax.
  (defun div (a b) (_binary a '/ b))                                             // Symbol selects native division.
  (defun mod (a b) (_binary a '% b))                                             // Punctuation used as a Symbol value.
  (def % mod)                                                                    // Operator alias is a name binding.
  (defun string-append (. strings) (foldl _string-append "" strings))            // Fold with native string append.
  (defmacro let (bindings body)                                                  // Expand bindings into a call.
    `((lambda ,(map car bindings) ,body)                                         // map gets names; comma inserts them.
      ,@(map cadr bindings)))                                                    // map gets values; comma-at splices.
  (defmacro let* (bindings body)                                                 // Nest bindings for sequential scope.
    (if (null? bindings) body                                                    // No bindings: return the body form.
        `(let (,(car bindings)) (let* ,(cdr bindings) ,body))))                  // Comma inserts into a Lisp template.
  (defun caar (value) (car (car value)))                                         // Compose ordinary Lisp calls.
  (defun cadr (value) (car (cdr value)))                                         // Second element by List composition.
  (defun cdar (value) (cdr (car value)))                                         // Tail of the first nested List.
  (defun cddr (value) (cdr (cdr value)))                                         // Share the tail after two elements.
  (defun match (subject pattern)                                                 // Match evaluated values as List data.
    (if (list? subject) (_match subject pattern) nil))                           // Call registered native List.match.
  (defun bound (bindings binder) (cadr (assoc binder bindings)))                 // Extract a match binding from data.
  (defun search-replace (subject pattern template)                               // Patterns and templates are values.
    (if (match subject pattern) (match-replace subject pattern template)         // Use our match before replacement.
        (_search-replace subject pattern template)))                             // Registered native List search.
  (defun binder? (value)                                                         // Recognize a pattern-binding Symbol.
    (and (symbol? value)                                                         // Short-circuit before String queries.
         (member (substring (str value) 0 1) '("?" "*"))                         // Quoted List of allowed prefixes.
         (> (string-length (str value)) 1)))                                     // Exclude unnamed pattern wildcards.
  (defun _binders (pattern)                                                      // Collect binders by List recursion.
    (cond ((list? pattern)                                                       // Structural case analysis in Lisp.
           (foldl (lambda (found part) (append found (_binders part)))           // Pass a Lisp lambda to foldl.
                  nil pattern))                                                  // Accumulate from the empty List.
          ((binder? pattern) (list pattern))                                     // Wrap the binder in a List.
          (true nil)))                                                           // No binder contributes no elements.
  (defun _binder-lets (source binders)                                           // Expose match bindings as locals.
    (map (lambda (binder)                                                        // Pass a Lisp closure to map.
           (list binder (list 'bound source (list 'quote binder))))              // Quote emits data, not a name lookup.
         binders))                                                               // Apply to each collected binder.
  (defmacro match-case (subject . clauses)                                       // Runtime macro builds Lisp Lists.
    (foldl                                                                       // Build nested forms with foldl.
      (lambda (rest clause)                                                      // Wrap remaining choices in a cond.
        (if (equal? (car clause) 'else) (cadr clause)                            // Quoted else is data for comparison.
          `(let ((_match-case-subject ,subject))                                 // Backquote template; comma inserts.
             (let ((_match-case-bindings                                         // Construct a nested binding form.
                     (match _match-case-subject ',(car clause))))                // ', inserts a value then quotes it.
               (cond (_match-case-bindings                                       // Generated test uses match bindings.
                       (let ,(_binder-lets '_match-case-bindings                 // Comma inserts computed bindings.
                                           (_binders (car clause)))              // Collect the pattern-bound names.
                         ,(cadr clause)))                                        // Comma inserts the clause body.
                     (true ,rest))))))                                           // Comma inserts remaining choices.
      nil (reverse clauses)))                                                    // Process clauses from last to first.
  (def add _add)                                                                 // Alias an existing native callable.
  (def last _last)                                                               // Alias an existing Lisp closure.
  (def len length)                                                               // Name binding preserves identity.
  (def reduce foldl)                                                             // Higher-order function as a value.
  (def lower string-downcase)                                                    // Alias reuses the native function.
);

/* Completing a session ------------------------------------------------------------------------------------------------

   A batch is read and evaluated one form at a time. Each definition is                form 1 -> value 1
   available to later forms. The last value is the result of the batch.                form 2 -> value 2
   A later error does not undo earlier effects, such as global bindings                  ...
   or file writes. Import reads another file into the same environment,                form n -> final value
   so its definitions are available to the importing program.                             one shared environment
*/
static Var _eval_text(Interp &self, String source) {
  Scope storage = $auto(Scope.new());                                            // Destroy Scope on block exit.
  Reader reader = Reader.scan(source, 0, &storage);                              // Pass the token Scope by address.
  Var form, result = %();                                                        // Empty List implicitly boxes as Var.
  while ((form = reader.read()) is not void)                                     // Receiver call; distinct void value.
    result = self.eval(NULL, form);                                              // Receiver call in global environment.
  return result;
}

static Var _import_file(Interp &self, String path) {
  File source = $auto(path.open("r"));                                           // Close File on block exit.
  Block content = $auto(Block.new(sizeof(char)));                                // Release Block on block exit.
  if (source.read_into(content) == <eof>) return %();                            // EOF gives an empty List result.
  if (content.length > INT_MAX) {                                                // Native C size limit.
    size_t size = content.length, int limit = INT_MAX;                           // Mixed types in one declaration.
    $fail(<size-limit>, "Lisp.eval_file", <size>, size, <limit>, limit);         // Integers box into the error List.
  }
  if (memchr(content.bytes, '\0', content.length))                               // C library scans the raw bytes.
    $fail(<bad-arg>, "Lisp.eval_file", <reason>, "embedded NUL");                // Add the reason to the error List.
  return _eval_text(self, String.new_len(content.bytes, (int) content.length));  // C bytes converted to x2c String.
}

static Var _reserved(void) => Var.null();                                        // Expression body; void Var value.

/* Each special form gets its own function value before the library loads.
   Saving that value under another name keeps the same behavior, even if
   the original name is rebound. Maps connect names, functions, and forms. */
static Interp _interpreter(void) {
  Interp self = { {}, {}, {}, {} };                                              // Four independently allocated Maps.
  _install_natives(self);                                                        // Borrow the interpreter record.
  foreach (Symbol name in %(quote quasiquote cond def lambda macro eval            // Typed iteration over literal data.
                       apply bind import)) {                                     // Iterate literal Symbol values.
    Func fn = Func.new(_reserved, %((func ((void))) "Var"));                     // Give each special form its own Func.
    self.reserved[name] = fn;                                                    // Func implicitly boxes as Var.
    self.specials[fn] = name;                                                    // A callable can be a Map key.
  }
  foreach (List form in _stdlib) self.eval(NULL, form);                            // Typed iteration; receiver call.
  return self;
}

/* Incremental reading and evaluation ----------------------------------------------------------------------------------

   The REPL evaluates complete forms and keeps incomplete input for the               +------+  +------+  +-------+
   next line. A saved offset marks where reading must resume, so earlier              | read |->| eval |->| print |
   forms are not evaluated twice. Malformed input is reported as an error.            +--^---+  +------+  +---+---+
   Evaluation errors are caught per form; later forms can still run.                     |                    |
                                                                                         +--------------------+
   Each function call uses the native stack. There is no tail-call
   guarantee, so sufficiently deep Lisp recursion can exhaust that stack.
   Production Lisp reuses tail-call frames and checks native stack capacity.
*/
typedef struct Repl {
  Buffer source;                                                                 // Mutable input buffer.
  Scope storage;                                                                 // Owns token allocations.
  Reader reader;                                                                 // Reader state stored by value.
  unsigned cursor;                                                               // Native byte offset into the input.
  int failed, incomplete, interactive, done;                                     // C integer flags coordinate the REPL.
} Repl;

static int Repl.read_line(Repl &self) {
  if (self.interactive) {
    Stdout.puts(self.incomplete ? ".. " : "> ");                                 // Write the prompt through File.
    Stdout.flush();                                                              // Flush before waiting for input.
  }
  String line = Stdin.readline();                                                // Read an immutable String.
  if (!line) {                                                                   // NULL String signals EOF here.
    if (self.incomplete) {
      Stderr.puts("error: incomplete form at end of input\n");                   // Write the error to Stderr.
      self.failed = 1;
    }
    self.done = 1;
    return 0;
  }
  self.source.write(line);                                                       // Buffer receiver appends input.
  return 1;
}

static Var Repl.finish_batch(Repl &self) {
  self.storage.destroy();                                                        // Release the allocation Scope.
  self.storage = NULL;                                                           // C null clears the handle.
  self.reader = (Reader) {0};                                                    // Zero-initialize a struct value.
  if (!self.incomplete) {
    self.source.clear();                                                         // Reuse the mutable Buffer storage.
    self.cursor = 0;
  }
  return void;                                                                   // Return the distinct void value.
}

/* Read one form; void means none is ready, and done distinguishes EOF.
   Batch storage owns tokens; the surrounding session owns parsed forms. */
static Var Repl.read_unit(Repl &self) {
  if (!self.reader.tokens && !self.read_line()) return void;                     // Receiver-style function call.
  try {                                                                          // Structured exception boundary.
    if (!self.reader.tokens) {                                                   // Dot works on records and pointers.
      self.storage = Scope.new();                                                // Explicit allocation lifetime.
      self.incomplete = 0;
      self.reader = Reader.scan(self.source, self.cursor, &self.storage);        // Allocate tokens in the owned Scope.
    }
    Var form = self.reader.read();                                               // Struct receiver, no explicit &.
    if (form is not void) return form;                                           // Return preserves batch storage.
  }
  catch %(incomplete *): {                                                       // Specific catch before the catch-all.
    self.incomplete = 1;
    self.cursor = self.reader.start;                                             // Retain the incomplete form offset.
  }
  catch %(?code *detail): {                                                      // Bind cause and remaining data.
    Stderr.printf("error: %s\n", cons(code, detail).repr());                     // List -> readable String.
    self.failed = 1;
  }
  return self.finish_batch();                                                    // Receiver call returns a void Var.
}

static int _repl(Interp &self) {
  Buffer source = $auto(Buffer.new(0));                                          // Release Buffer on block exit.
  Repl repl = { .source = source, .interactive = isatty(Stdin.fileno()) };       // Named fields; POSIX terminal check.
  defer repl.storage.destroy();                                                  // Destroy remaining tokens on exit.
  while (!repl.done) {                                                           // Same dot for a stack struct value.
    Var form = repl.read_unit();                                                 // Receiver call borrows repl.
    if (form is void) continue;                                                  // Test the distinct void value.
    try {                                                                        // Structured exception boundary.
      Var value = self.eval(NULL, form);                                         // Receiver call returns a Var.
      Stdout.printf("%s\n", value.repr());                                       // Var provides readable output.
    }
    catch %(?code *detail): {                                                    // Pattern destructures the error.
      Stderr.printf("error: %s\n", cons(code, detail).repr());                   // Construct List, then format it.
      repl.failed = 1;
    }
  }
  return !repl.failed;
}

/* Command-line interface ----------------------------------------------------------------------------------------------
   main converts argv to x2c Strings and matches the command line.
   No arguments starts the REPL; -e evaluates an expression; --selftest
   runs a small check; a path loads a Lisp file. Every mode first loads
   the native functions and the Lisp definitions in _stdlib. */
int main(int argc, char **argv) {                                                // Standard C argc/argv entry point.
  $scope() {                                                                     // Session-wide allocation region.
    try {                                                                        // Structured exception boundary.
      Array args = range(0, argc - 1, 1)                                         // Lazy range iterator.
        .map(%!(int i) using &argv => String.new(argv[i]));                      // Capture &argv; convert each entry.
      Interp self = _interpreter();                                              // Session record returned by value.
      String source;                                                             // Immutable String held by a handle.
      match (args.list()) {                                                      // Chain conversion into matching.
        case %(?): return _repl(self) ? 0 : 1;                                   // ? matches without binding.
        case %(? "-e" ?text): source = text;                                     // Bound Var converts to String.
        case %(? "--selftest"):                                                  // Match a literal String argument.
          source = "(list (apply + '(10 20 12)) (append '(1 2) '(3 4)))";        // C literal promotes to cached String.
        case %(? ?file): {                                                       // Wildcard plus bound filename.
          const char *path = file.str();                                         // Borrow a C string pointer.
          source = File.open(path ? path : "", "r").string_close();              // Chain File open, read, and close.
        }
        default: {                                                               // Fallback when no pattern matches.
          Stderr.printf("usage: %s [--selftest | -e FORM | FILE]\n",             // Native format string with File I/O.
                        args[0].str());                                          // Array indexing, then String access.
          return 1;
        }
      }
      Stdout.printf("%s\n", _eval_text(self, source).repr());                    // Evaluate and print the last value.
      return 0;
    }
    catch %(?code *detail):                                                      // Destructure the error as a List.
      Stderr.printf("error: %s\n", cons(code, detail).repr());                   // Construct List, then format it.
  }
  return 1;
}
