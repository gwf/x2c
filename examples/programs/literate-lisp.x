/*  literate-lisp.x -- a complete Lisp implementation in x2c

    Copyright (c) 2026 Gary William Flake                                             #####                 #####
                                                                                      ########           ########
    A recursive Lisp, generously commented in 1,000 lines.                           ##########         ##########
    It is functionally equivalent to the x2c runtime's word-code machine.                 #######     #######
    Block comments explain how Lisp is implemented. Right-margin                           ######     ######
    comments show how x2c combines native C with a dynamic runtime.                         ######   ######
                                                                                             #####   #####
    A Lisp program is a tree of values. Evaluation traverses the tree,                       #####   #####
    resolves names through environments, and applies functions to                           ######   ######
    arguments. Quotation preserves a form as data without evaluating it.                   ######     ######
                                                                                          #######     #######
      (+ 1 2)             // evaluates to 3                                          ##########         ##########
      '(+ 1 2)            // evaluates to the List (+ 1 2)                            ########           ########
      (eval '(+ 1 2))     // evaluates that List as a call, producing 3               #####                 #####

    Environments, closures, runtime Lisp macro expansion, and the reader
    follow the evaluator. Definitions written in Lisp add conditionals,
    bindings, and collection operations to the core evaluation rules.
                                                                                             ######
    x2c supplies values, collections, tokenization, and native function                         ####
    calls. This file implements Lisp evaluation independently of the                             ####
    production Lisp object and word-code machine. Evaluation uses native                          ####
    recursive calls.                                                                             ######
                                                                                                ########
    Two distinct macro systems appear here. The x2c macros $fail and $rest                     ####  ####
    expand when this file is compiled. Runtime Lisp macros are Fn closures                    ####    ####
    executed by this interpreter while evaluating a Lisp program.                            ####      ####
                                                                                            ####        ####
    The implementation follows x2c Lisp, including its rules for capture                   ####          ######
    and errors; those rules sometimes differ from Scheme or Common Lisp.
*/

#include <unistd.h>                                                             // Ordinary C/POSIX headers coexist.

/* Values, names, and memory ------------------------------------------------------------------------------------------

   Var can store a number, String, List, or callable. A nonempty List has a            +-----+-----+
   first element (car) and a remaining List (cdr); the empty List, (),                 | car | cdr |---+
   marks its end. Nested Lists represent the structure of a Lisp                       +-----+-----+   |
   expression.                                                                            |           v
                                                                                        value    +-----+-----+
   Fn stores a parameter List, a body, and captured local bindings. During                       | car | () |
   a call, each parameter is bound to its corresponding argument value.                          +-----+-----+
   Captures contain copies of local values taken when the closure was
   created; these bindings remain available when its body is evaluated
   later.

   A runtime Lisp macro uses the same record but receives unevaluated
   argument forms. The macro field selects this calling convention. It does
   not refer to an x2c compile-time macro.
*/
typedef struct Fn {
  List params;                                                                  // Immutable parameter List.
  Var body;                                                                     // Tagged, heterogeneous value.
  Map captures;                                                                 // Names -> captured values.
  int macro;                                                                    // C integer flag in an x2c record.
} *Fn;                                                                          // C typedef for a struct pointer.

typedef struct Env {                                                            // Stack-local environment frame.
  Map bindings;                                                                 // Names -> local values.
  struct Env *parent;                                                           // Outer frame; borrowed pointer.
} Env;

/* Global bindings persist across top-level evaluations. The native
   registry maps binding names to host functions. Reserved forms have
   callable identities; name lookup and callable dispatch are separate
   operations.
*/
typedef struct Interp {                                                         // Maps store Var keys and values.
  Map globals;                                                                  // Names -> global values.
  Map natives;                                                                  // Binding Strings -> native Funcs.
  Map reserved;                                                                 // Reserved names -> callable Funcs.
  Map specials;                                                                 // Callable Funcs -> special names.
} Interp;

/* The x2c compile-time macro $fail adds the operation pair to raise
   syntax. The other error fields remain explicit at each call site.
*/
macro Statement $fail(Expr $cause, Expr $op, Expr $fields...) => {              // Expr parameters capture syntax.
  $(quasiquote                                                                  // Quasiquote builds the raise AST.
    (raise ,$cause                                                              // Unquote inserts captured syntax.
      (args (literal ("Symbol") "operation" operation)                          // AST for a Symbol literal.
            ,$op ,@$fields)))                                                   // ,@ splices syntax at compile time.
}

/* Evaluation: the language in three rules ----------------------------------------------------------------------------

   Evaluating a name returns its bound value; evaluating a literal returns                   (+ 1 (* 2 3))
   the literal itself. A nonempty List represents a call. Its head is                         / | \
   evaluated first, and argument handling depends on the resulting                           +  1  *
   callable's type: ordinary function, special form, or runtime Lisp macro.                       / \
   Only () is false; zero and the empty String are true.                                         2   3

   For (+ 1 (* 2 3)), evaluation first resolves +, then evaluates the                  (* 2 3) -> 6
   arguments to 1 and 6. Applying + to these values returns 7. The same                (+ 1 6) -> 7
   rule handles calls whose heads are expressions, such as ((lambda (x) x)
   7).

   A runtime Lisp macro receives the original argument forms. Its body runs
   in this interpreter and returns a replacement form, which eval evaluates
   in the caller's environment. This expansion happens during Lisp program
   evaluation, after all x2c compile-time macros have already expanded.
*/
static Var Interp.eval(Interp *self, Env *env, Var form) {
  if (form is void) $fail(<void-op>, %"eval");                                  // Macro emits runtime error creation.
  if (form.is_atom()) return self.lookup(env, form);                            // Receiver-style function calls.
  if (form is not <list> || form.is_nil()) return form;                         // is inspects the Var tag.
  List expr = form;                                                             // Implicit Var -> List conversion.
  Var fn = self.eval(env, expr.car());                                          // List head is itself a Var.
  List args = expr.cdr();                                                       // O(1) tail access; no List copy.
  if (fn is <lambda>) {                                                         // Runtime callable-type introspection.
    Fn closure = fn.pointer();                                                  // Unbox the stored pointer.
    if (closure.macro)                                                          // Dot dereferences the heap pointer.
      return self.eval(env, self.invoke(env, closure, args));                   // Expansion stays an ordinary Var.
  }
  else {
    if (fn is not <func>)                                                       // Reject a non-callable Var tag.
      raise %(not-call (actual ${fn.kind()}));                                  // ${...} evaluates an x2c expression.
    if (fn in self.specials)                                                    // Map membership by key.
      return self.special(env, self.specials[fn], args);                        // Map value converts to Symbol.
  }
  List values = self.eval_args(env, args);                                      // Evaluate arguments left to right.
  return self.apply(env, fn, values);                                           // Apply to values, not source forms.
}

/* Evaluation proceeds left to right. When arguments define globals, read
   files, or raise errors, a later failure leaves earlier effects intact.
   The result is a List of values ready for application.
*/
static List Interp.eval_args(Interp *self, Env *env, List forms) {
  Array values = $auto(%[]);                                                    // Array literal; cleanup on exit.
  foreach (Var form, forms) values.push(self.eval(env, form));                  // Typed List iteration.
  return values;                                                                // Build List before Array cleanup.
}

/* Special forms control evaluation -----------------------------------------------------------------------------------

   Ordinary function arguments are evaluated before the function body runs.                   (cond ...)
   Special forms require different rules: quote returns an unevaluated                             |
   form, lambda constructs a closure without evaluating its body, and cond                         v
   evaluates only the selected clause's body. The evaluator handles these                        test
   forms directly.                                                                                 |
                                                                                           +-------+-------+
   Each pattern matches an accepted form and binds its components. In cond,                |               |
   tests run in order until one is true; only that clause's body is                       true           false
   evaluated. The runtime Lisp macro if expands into cond.                                 |               |
                                                                                           v               v
   def always writes a global binding. eval first obtains a form, then                    body           next
   evaluates it globally. apply instead obtains a callable and a List of
   values. apply passes those values to the callable without evaluating
   them again, including any Lists that could also be parsed as calls.
*/
static Var Interp.special(Interp *self, Env *env, Symbol op, List args) {
  match (%($op @args)) {                                                        // $ inserts a value; @ splices a List.
    case %(quote ?form): return form;                                           // Pattern binds one value.
    case %(quasiquote ?form): return self.quasiquote(env, form, 0);             // Literal Symbol plus bound form.
    case %(def ?name ?form) if (name.is_atom()):                                // Guard sees the pattern bindings.
      return self.globals[name] = self.eval(env, form);                         // Map assignment yields its value.
    case %(lambda ?(List params) ?body):                                        // Tag mismatch skips this case.
      return self.closure(env, params, body, 0);                                // Receiver call returns a boxed Fn.
    case %(macro ?(List params) ?body):                                         // Check List type while binding.
      return self.closure(env, params, body, 1);                                // Same receiver syntax for macros.
    case %(cond *clauses) if (clauses): {                                       // * binds the remaining elements.
      foreach (Var clause, clauses) {                                           // Iterate without an index.
        match (clause) {                                                        // Nested structural match.
          case %(?test ?body):                                                  // Require exactly two elements.
            if (!self.eval(env, test).is_nil()) return self.eval(env, body);    // Chain calls on returned values.
          default: _bad_clause(clause);                                         // Fallback for unmatched List shapes.
        }
      }
      return %();                                                               // Empty List implicitly boxes as Var.
    }
    case %(eval ?form): return self.eval(NULL, self.eval(env, form));           // Evaluate the form in global scope.
    case %(apply ?fn ?values): {                                                // Pattern binds callable/value forms.
      Var callable = self.eval(env, fn),                                        // Evaluate the callable expression.
          actual = self.eval(env, values);                                      // Evaluate the argument expression.
      return self.apply(env, callable, _list_argument(actual, "apply"));        // Check List; apply evaluated values.
    }
    case %(bind ?name ?sig): {                                                  // Bind two unevaluated forms.
      Var target = self.eval(env, name),                                        // Binding name as a dynamic value.
          type = self.eval(env, sig);                                           // Native signature is ordinary data.
      return self.bind(target, type);                                           // Return native Func boxed as Var.
    }
    case %(import ?form): {                                                     // Pattern binds the path expression.
      Var path = self.eval(env, form);                                          // Receiver call yields a Var.
      Atom hook = Atom.intern("_x2c.import-hook");                              // Exact names beyond Symbol capacity.
      _string_argument(path, "import");                                         // C literal promotes to String.
      if (hook in self.globals)                                                 // Map membership by key.
        return self.apply(NULL, self.globals[hook], %($path));                  // Construct a one-argument List.
      return _import_file(self, path);                                          // Var path converts to String.
    }
  }
  return _bad_form(op, args);                                                   // Symbol and List passed directly.
}

/* Applying a value ---------------------------------------------------------------------------------------------------

   eval converts expressions to values; apply invokes a callable with                   callable        values
   values already evaluated. For example, (apply list '(a b)) returns (a                   |               |
   b), without looking up either a or b.                                                   +-------+-------+
                                                                                                   |
   Applying a closure evaluates its saved body with new bindings; applying                         v
   a native callable invokes an x2c function. Runtime Lisp macros require                        apply
   unevaluated argument forms and subsequent evaluation of their expansion.                +-------+-------+
   apply accepts evaluated values and rejects runtime Lisp macros. x2c                     v               v
   compile-time macros do not enter this path.                                          closure          native
*/
static Var Interp.apply(Interp *self, Env *env, Var fn, List values) {
  if (fn is <lambda>) {                                                         // Inspect the callable tag.
    Fn closure = fn.pointer();                                                  // Unbox the closure pointer.
    if (closure.macro) $fail(<not-call>, %"apply", <actual>, fn.kind());        // kind() supplies runtime type data.
    return self.invoke(env, closure, values);                                   // Receiver call passes self first.
  }
  if (fn is not <func>) raise %(not-call (actual ${fn.kind()}));                // Structured error with interpolation.
  if (fn in self.specials) {                                                    // Map membership by callable value.
    if (self.specials[fn] != <apply>.var())                                     // Box a Symbol for Var comparison.
      $fail(<not-call>, %"apply", <actual>, fn.kind());                         // Compile-time macro; runtime error.
    match (values) case %(?callable ?args):                                     // Destructure by pattern.
      return self.apply(env, callable, _list_argument(args, "apply"));          // C literal promotes to String.
    return _bad_form(<apply>, values);                                          // <apply> is a Symbol literal.
  }
  return _native_call(fn, values);                                              // Implicit Var -> Func conversion.
}

/* Name lookup and captured bindings ----------------------------------------------------------------------------------

   Lookup searches the nearest environment first, then globals, then                      +-------------+
   reserved names. An inner binding shadows an outer one without modifying                | local frame |
   it. Keeping bindings in Maps also separates a missing name from a name                 +------+------+
   bound to ().                                                                                  |
                                                                                                 | parent
   This closure captures the local binding x = 10:                                               v
                                                                                          +-------------+
     (def add-ten (let ((x 10)) (lambda (y) (+ x y))))                                    | outer frame |
     (add-ten 7)     // 17, after the let call has returned                               +------+------+
                                                                                                 |
   Call frames can live on the native stack. Closures and their capture                          v
   Maps belong to the session Scope, so saved bindings outlive those calls.                   globals
   The values they refer to keep their ordinary ownership; immutable
   Strings and Lists live in canonical pools.
*/

static Var Interp.lookup(Interp *self, Env *env, Var name) {
  for (; env; env = env.parent)                                                 // C pointer walk with x2c dot access.
    if (name in env.bindings) return env.bindings[name];                        // Map membership and indexing.
  if (name in self.globals) return self.globals[name];                          // Global Map: test key, fetch value.
  if (name in self.reserved) return self.reserved[name];                        // Reserved Map: same key operations.
  raise %(unbound (name $name));                                                // $name interpolates one named value.
}

/* x2c Lisp collects captures by flattening one level of a List body. It
   copies values for locally bound names exposed by that step, excluding
   parameters and reserved names. Quotation does not prevent capture, but
   names in deeper Lists are not collected. Global bindings are looked up
   during evaluation rather than copied into closures.

   This is not a free-variable analysis or a purely lexical environment.
   Names absent from the captures may still resolve in the caller. A scalar
   body captures nothing. Consequently, a lambda's result can differ from
   the result under lexical scope rules used by other Lisp implementations.
*/
static Var Interp.closure(
  Interp *self, Env *env, List params, Var body, int macro) {
  Map captures = %{};                                                           // Mutable Map; Var keys and values.
  if (body is <list>)                                                           // Test before converting the Var.
    foreach (Var name, body.list().flatten()) {                                 // Chain conversion and traversal.
      if (!name.is_atom() || name in self.reserved ||                           // Receiver predicate; Map membership.
          name in captures || name in params) continue;                         // in works on Maps and Lists.
      for (Env *local = env; local; local = local.parent) {                     // C pointer walks the outer frames.
        if (name in local.bindings) {                                           // Map access through a C pointer.
          captures[name] = local.bindings[name];                                // Copy a Var between Maps.
          break;
        }
      }
    }
  Fn closure = Scope.malloc(sizeof(struct Fn));                                 // Allocate in the current Scope.
  *closure = (struct Fn) { params, body, captures, macro };                     // C dereference and compound literal.
  return Var.new(<lambda>, closure);                                            // Tag an already allocated pointer.
}

/* Invocation pairs parameters with values. A dotted parameter, as in
   (lambda (first . rest) ...), binds the remaining arguments as one List.
   The body's lookup order is parameters, captures, caller frames, globals,
   and reserved names. A captured value takes precedence over a caller
   binding of the same name.
*/
static Var Interp.invoke(Interp *self, Env *env, Fn closure, List values) {
  Map bindings = $auto(%{});                                                    // Map literal; cleanup on exit.
  for (List params = closure.params;                                            // C for with a typed List handle.
       params;                                                                  // Empty List is the null handle.
       params = params.cdr()) {                                                 // Advance with an x2c List method.
    Var (name, rest) = params;                                                  // Extract and convert by position.
    if (name.is_atom() && name.str() == ".") {                                  // Canonical String identity test.
      if (!params.cdr()) $fail(<bad-sig>, %"apply", <value>, closure.body);     // Error detail needs an x2c String.
      bindings[rest] = values;                                                  // List boxes as the Map value.
      values = NULL;
      break;
    }
    if (!values) $fail(<bad-arity>, %"apply", <value>, closure.body);           // Macro builds the runtime error.
    bindings[name] = values.car();                                              // Receiver-style List access.
    values = values.cdr();                                                      // Advance the argument tail too.
  }
  if (values) $fail(<bad-arity>, %"apply", <value>, closure.body);              // Macro constructs the error record.
  Env captured = { closure.captures, env };                                     // C aggregate with x2c Map handle.
  Env local = { bindings, &captured };                                          // & takes a stack frame's C address.
  return self.eval(&local, closure.body);                                       // C stack address passed to eval.
}

/* Quotation as a language for constructing code ----------------------------------------------------------------------

   quote returns its argument without evaluation. Quasiquote evaluates the                 `(a ,x ,@xs)
   comma-marked expressions within a template. Comma-at inserts the                            |    |
   elements of a List into the surrounding List:                                         x = 7 |    | xs = (8 9)
                                                                                               v    v
     (let ((x 7) (xs '(8 9))) `(a ,x ,@xs))     // (a 7 8 9)                               (a  7    8 9)

   There are two result shapes here. quasiquote produces one value;                     one value   List elements
   quoted_item produces the sequence of elements contributed by an item. An
   ordinary item contributes one element; a splice may contribute many. The
   containing List is constructed by concatenating these item sequences.

   The depth tracks nested quasiquotes. Processing a nested quasiquote
   increments it; processing a nested unquote decrements it. An unquote is
   evaluated only at depth zero. Otherwise, it remains in the returned
   form.
*/
static Var Interp.quasiquote(Interp *self, Env *env, Var form, int depth) {
  if (form is not <list> || form.is_nil()) return form;                         // Runtime tag inspection.
  List expr = form;                                                             // Implicit Var -> List conversion.
  Var (head, argument) = expr;                                                  // Positional List destructuring.
  Var (quote, unquote, splice) = %(quasiquote unquote unquote-splicing);        // Literal names unpack into Vars.
  if (head == quote)                                                            // Var equality with a Symbol value.
    return cons(head, self.quasiquote(env, expr.cdr(), depth + 1));             // Construct List; result boxes as Var.
  if (head == unquote || head == splice) {                                      // Compare Symbols held in Vars.
    if (expr.len() != 2) $fail(<bad-arity>, %"quasiquote", <value>, form);      // Receiver-style length query.
    if (depth) return cons(head, self.quasiquote(env, expr.cdr(), depth - 1));  // C condition with List construction.
    Var value = self.eval(env, argument);                                       // Recursive receiver-style call.
    if (head == splice)                                                         // Var equality against a Symbol.
      $fail(<bad-types>, %"quasiquote-splice", <actual>, form.kind());          // Runtime kind in macro-built error.
    return value;
  }
  List first = self.quoted_item(env, head, depth);                              // Receiver call returns a typed List.
  List rest = self.quasiquote(env, expr.cdr(), depth);                          // Returned Var converts to List.
  return first.append(rest);                                                    // Result List implicitly boxes as Var.
}

static List Interp.quoted_item(Interp *self, Env *env, Var form, int depth) {
  match (form) case %(unquote-splicing ?argument) if (!depth): {                // Pattern plus guard.
    Var value = self.eval(env, argument);                                       // Recursive receiver-style call.
    if (value is not <list>)                                                    // Runtime type inspection.
      $fail(<bad-types>, %"quasiquote-splice", <actual>, value.kind());         // Macro emits runtime error creation.
    return value;                                                               // Implicit Var -> List conversion.
  }
  return %(${self.quasiquote(env, form, depth)});                               // ${...} inserts a whole expression.
}

/* Errors are part of the language's observable behavior --------------------------------------------------------------

   A malformed call is different from an unbound name or a value of the                       raise
   wrong type. These helpers construct the corresponding error causes and                       |
   details. Errors are structured data that a surrounding x2c catch can                (cause (key value) ...)
   match.                                                                                       |
                                                                                         catch pattern
   $fail, defined near the top, is an x2c compile-time macro that                               |
   constructs raise syntax while compiling this x2c file. Runtime Lisp                     bound fields
   macros in _stdlib construct Lisp forms during evaluation. The shared use
   of Lists does not imply that these two macro systems share an execution
   phase.
*/

static List _list_argument(Var value, String op) {
  if (value is not <list>)                                                      // Runtime type inspection.
    $fail(<bad-types>, op, <actual>, value.kind(), <want>, %"List");            // op boxes as Var in the error List.
  return value;                                                                 // Implicit Var -> List conversion.
}

static String _string_argument(Var value, String op) {
  if (value is not <string>)                                                    // Runtime type inspection.
    $fail(<bad-types>, op, <actual>, value.kind(), <want>, %"String");          // op boxes as Var in the error List.
  return value;                                                                 // Implicit Var -> String conversion.
}

static Var Interp.bind(Interp *self, Var name, Var sig) {
  _string_argument(name, "bind");                                               // C literal promotes to String.
  if (sig is not <list>) $fail(<bad-sig>, %"bind", <value>, sig);               // Type check and error macro.
  if (name in self.natives) return self.natives[name];                          // Hash lookup; no linear name scan.
  raise %(no-symbol (name $name) (sig $sig));                                   // Runtime values in an error List.
}

static void _bad_clause(Var clause) {
  if (clause is not <list>)                                                     // Runtime type inspection.
    $fail(<bad-types>, %"cond", <value>, clause, <want>, %"List");              // Macro emits runtime error creation.
  $fail(<bad-arity>, %"cond-clause", <expected>, 2, <actual>,                   // Symbol keys; runtime boxed values.
        clause.list().len(), <value>, clause);                                  // Chain conversion; O(n) List length.
}

static Var _bad_form(Symbol name, List args) {
  if (name == <lambda> || name == <macro>)                                      // Constant-time Symbol comparisons.
    $fail(<bad-sig>, name, <value>, args);                                      // Symbol and List box as error values.
  int n = args.len();                                                           // Receiver-style length query.
  if (name == <def>)                                                            // Constant-time Symbol comparison.
    $fail(<bad-arity>, %"def", <expected>, 2, <actual>, n, <value>, args);      // List and integers become error data.
  int want = name == <apply> || name == <bind> ? 2 : 1;                         // C ternary with Symbol comparisons.
  $fail(<bad-arity>, name.str(), <expected>, want, <actual>, n);                // Symbol spelling via receiver syntax.
}

/* Reading: from characters to values ---------------------------------------------------------------------------------

   The reader parses spelling and nesting without evaluating expressions.                  "(+ 1 2)"
   Reading (+ 1 2) constructs a List; it does not look up + or add.                             |
   Evaluation, quotation, and runtime Lisp macro expansion all consume                        tokens
   these same values, so the reader needs no separate representation for                        |
   executable forms.                                                                      +-----+-----+
                                                                                          |  +  |  *--+-> (1 2)
   Tokenization recognizes words, numbers, strings, and punctuation.                      +-----+-----+
   Recursive descent supplies the grammar: after an opening parenthesis,
   read forms until its closing parenthesis. Reading a nested List uses the
   same rule. Prefixes are shorthand: 'x becomes (quote x), and commas and
   backquotes become the corresponding unquote and quasiquote Lists.
*/
typedef struct Reader {
  Tokenizer tokens;                                                             // Runtime tokenizer handle.
  String source;                                                                // Immutable String handle.
  unsigned base, start;                                                         // C offsets into source bytes.
} Reader;

static Var Reader._error(Reader *self, Symbol cause, unsigned at) {
  int line = 1, column = 1;
  scan_next_line_col(self.source, (int) at, &line, &column);                    // C addresses for output parameters.
  if (cause == <incomplete>)                                                    // Integer comparison; no text scan.
    raise %(incomplete (source ${self.source})                                  // ${...} interpolates an expression.
                       (line $line) (column $column));                          // $line interpolates a named value.
  raise %(malformed (source ${self.source}) (line $line) (column $column));     // Expression and identifier insertion.
}

static Var Reader._form(Reader *self, Token token) {
  if (!token || token.type == <eof>)                                            // Constant-time integer Symbol test.
    return self._error(<incomplete>, self.start);                               // Symbol literal as a call argument.
  String text = token.text, prefix = NULL;                                      // Immutable String handle.
  switch (token.type) {                                                         // C switch dispatches on Symbols.
    case <error>:                                                               // Symbol constant in C switch.
      if (self.tokens.status() == <incomplete>)                                 // Method call and Symbol comparison.
        return self._error(<incomplete>, self.start);                           // Receiver call builds a source error.
      break;
    case <"(">: {                                                               // Quoted Symbol in a switch.
      Array elements = $auto(%[]);                                              // Array literal; cleanup on exit.
      while (1) {
        Token next = self.tokens.next();                                        // Pull a token with receiver syntax.
        if (next && next.type == <")">) return elements.list();                 // List result boxes as Var.
        elements.push(self._form(next));                                        // Compose two receiver-style calls.
      }
    }
    case <"'">:  prefix = "quote";      break;                                  // C literal promotes to String.
    case <"`">:  prefix = "quasiquote"; break;                                  // Quoted Symbol; C literal promotes.
    case <",">:  prefix = "unquote";    break;                                  // Symbol dispatch; String assignment.
    case <",@">: prefix = "unquote-splicing"; break;                            // Symbol can encode punctuation.
    case <lit-char*>:                                                           // Token kind is an integer Symbol.
      return String.new_len(text + 1, token.len - 2).unescape();                // Chain construction and unescaping.
    case <lit-int>: {                                                           // Symbol constant, not a string test.
      long value;                                                               // Ordinary C integer local.
      if (!text.try_long(&value)) break;                                        // Conversion with a success result.
      if (value == (int) value) return (int) value;                             // int implicitly boxes as Var.
      return value;                                                             // Native long implicitly boxes as Var.
    }
    case <lit-float>: {                                                         // Constant-time token-kind dispatch.
      double value;                                                             // Ordinary C scalar local.
      if (text.try_double(&value)) return value;                                // double implicitly boxes as Var.
      break;
    }
    case <lit-symbol>: {                                                        // Switch on the encoded token kind.
      String inner = text[1] == '"'                                             // C byte indexing of String storage.
        ? String.new_len(text + 2, token.len - 4).unescape()                    // C pointer arithmetic into text.
        : String.new_len(text + 1, token.len - 2);                              // C pointer span -> immutable String.
      if (inner) return Symbol.new(inner);                                      // Symbol result implicitly boxes.
      break;
    }
    case <ident>:                                                               // Identifier token as a Symbol tag.
      return Atom.intern(text.unescape());                                      // Intern exact short or long names.
  }
  if (prefix) {                                                                 // Canonical empty String is NULL.
    Var name = Atom.intern(prefix), inner = self._form(self.tokens.next());     // Atom and Var results in Var locals.
    return %($name $inner);                                                     // $name/$inner insert named values.
  }
  return self._error(<malformed>, self.base + token.pos);                       // C offset math inside a method call.
}

/* Tokens describe one source batch and may be discarded after it is read.
   The constructed values must outlive them: a definition can save a body
   for a later call. Token storage is released separately from the returned
   forms.
*/
static Reader Reader.scan(String source, unsigned base, Scope *storage) {
  Reader reader = { .source = source, .base = base };                           // Named struct initializers.
  $scope(storage) {                                                             // Redirect Scope; restore on exit.
    reader.tokens = Tokenizer.new_mode(                                         // Ordinary runtime tokenizer.
      source ? source + base : NULL, <lisp>);                                   // C pointer offset; Symbol mode.
    reader.tokens.scan();                                                       // Receiver-style function call.
  }
  return reader;                                                                // Return the ordinary struct by value.
}

/* Reader.read returns void at end of input; the empty List () is a valid
   form. Incomplete input raises an error, and the REPL retains the text
   for the next line.
*/
static Var Reader.read(Reader *self) {
  Token first = self.tokens.next();                                             // Receiver-style token access.
  if (!first || first.type == <eof>)                                            // Constant-time integer Symbol test.
    return void;                                                                // void differs from the empty List.
  self.start = self.base + first.pos;                                           // C arithmetic on source offsets.
  return self._form(first);                                                     // C pointer supports x2c dot calls.
}

/* Native functions ---------------------------------------------------------------------------------------------------

   Primitive operations are implemented as x2c functions invoked through                 Lisp argument values
   Func. Func signatures specify argument and result types. eval evaluates                        |
   the argument expressions before _native_call passes their values to                        Func.apply
   Func.apply.                                                                                    |
                                                                                          typed C arguments
   Predicates translate native conditions into Lisp truth values.                                 |
   Arithmetic and collection primitives are used by the recursive and                        C function
   higher-order operations defined in Lisp below.
*/

static Var _native_call(Func native, List values) {
  FuncArg *args = Scope.malloc(values.len() * sizeof(FuncArg));                 // C sizeof sizes Scope allocation.
  defer Scope.free(args);                                                       // Cleanup on every block exit.
  int count = 0;
  foreach (Var value, values)                                                   // x2c iteration over a List.
    args[count++] = FuncArg.value(value);                                       // C indexing; native argument packing.
  return native.apply(count, args);                                             // Checked native call through Func.
}

static int _is_number(Var v) {
  Symbol k = v.kind();                                                          // Runtime type introspection.
  return k == <integer> || k == <floating>;                                     // Symbol values compare as integers.
}

static Var _bool(int x)      => x ? <true>.var() : %().var();                   // Explicit Var branches; => returns.
static Var _atom(Var v)      => _bool(v is not <list> || v.is_nil());           // Runtime tag plus receiver predicate.
static Var _pair(Var v)      => _bool(v is <list> && !v.is_nil());              // C logic over Var predicates.
static Var _list(Var v)      => _bool(v is <list>);                             // Constant-time Var tag inspection.
static Var _number(Var v)    => _bool(_is_number(v));                           // Expression-bodied function.
static Var _string(Var v)    => _bool(v is <string>);                           // Dynamic type test in an expression.
static Var _symbol(Var v)    => _bool(v.kind() == <symbol>);                    // Runtime kind as a Symbol.
static Var _procedure(Var v) => _bool(v is <func> || v is <lambda>);            // Two callable tags.
static Var _eq(Var a, Var b) => _bool(a == b);                                  // Var equality uses type semantics.

static Var _compare(Var a, Var b) {
  if (!_is_number(a) || !_is_number(b))                                         // C logic over Var type predicates.
    $fail(<bad-types>, %"lisp_compare",                                         // Compile-time macro emits error code.
          <left-kind>, a.kind(), <right-kind>, b.kind());                       // Runtime types in the error record.
  return a.compare(b);                                                          // Var comparison via receiver syntax.
}

static Var _add(Var a, Var b) =>
  a is <string> || b is <string>                                                // Runtime type inspection.
    ? %"$a$b".var()                                                             // $a/$b interpolate identifier values.
    : a.binary(<+>, b);                                                         // Var arithmetic selected by Symbol.

static Var _plus(List values) {
  Var seed = 0;                                                                 // Implicit int -> Var conversion.
  if (values && values.car() is <string>) seed = String.new("");                // String implicitly boxes as Var.
  return values.foldl(seed, _add);                                              // Direct function uses cached Func.
}

/* Addition and multiplication fold from 0 and 1. Subtraction and division
   need at least one argument: a single x computes 0-x or 1/x. Integer
   division truncates. Multiple arguments combine left to right, so
   (- 10 3 2) means (10 - 3) - 2, not 10 - (3 - 2).
*/
static Var _arithmetic(List values, Symbol op, Var identity) {
  if (!values) $fail(<bad-arity>, op.str(), <expected>, 1, <actual>, 0);        // Macro constructs runtime errors.
  Var result = values.car();                                                    // List head is already a Var.
  if (!values.cdr()) return identity.binary(op, result);                        // Var arithmetic selected by Symbol.
  foreach (Var value, values.cdr()) result = result.binary(op, value);          // Iterate a List suffix.
  return result;
}

static Var _minus(List xs)  => _arithmetic(xs, <->, 0);                         // 0 promotes to Var.
static Var _divide(List xs) => _arithmetic(xs, </>, 1);                         // 1 promotes to Var.
static Var _times(List xs)  => xs.foldl(1, %!(a, b) => a.binary(<*>, b));       // %! constructs a callable.

/* Chained comparisons test neighboring pairs: (< 1 2 3) succeeds only if 1
   < 2 and 2 < 3. Comparison stops at the first false result; inspecting
   later values could otherwise introduce an error in an unreached
   comparison.
*/
static Var _chain(List values, String op, int want, int expect) {
  int n = values.len();                                                         // List length walks the cons cells.
  if (n < 2) $fail(<bad-arity>, op, <expected>, 2, <actual>, n);                // Values box into the error record.
  Var left = values.car();                                                      // Receiver access yields a Var.
  foreach (Var right, values.cdr()) {                                           // Typed iteration over a suffix.
    int order = _compare(left, right).integer();                                // Chain a call and Var conversion.
    if (expect ? order != want : order == want) return _bool(0);                // C ternary selects comparison logic.
    left = right;
  }
  return _bool(1);                                                              // Convert C truth to Lisp truth.
}

static Var _eq_chain(List xs) => _chain(xs, "=",  0, 1);                        // Expression body returns directly.
static Var _lt_chain(List xs) => _chain(xs, "<", -1, 1);                        // C literal promotes to String.
static Var _le_chain(List xs) => _chain(xs, "<=", 1, 0);                        // Typed List in; dynamic Var out.
static Var _gt_chain(List xs) => _chain(xs, ">",  1, 1);                        // Ordinary call; no wrapper object.
static Var _ge_chain(List xs) => _chain(xs, ">=", -1, 0);                       // One helper defines all comparisons.

/* These return Var because the native signature appears in Lisp errors. */
static Var _str(Var v)                        => v.str();                       // String result boxes as Var.
static Var _repr(Var v)                       => v.repr();                      // Readable formatting via receiver.
static Var _string_append(String a, String b) => a + b;                         // String +; result boxes as Var.
static Var _string_downcase(String s)         => s.lower();                     // Receiver call; result boxes as Var.
static Var _substring(String s, int a, int b) => s.getslice(a, b, 1);           // String slice; result boxes as Var.

static Var _match_replace(List input, Var pat, Var template) {
  Var result;                                                                   // Dynamic value for the match result.
  if (!input.try_match_replace(pat, template, &result)) return input.var();     // Match/replace with a success result.
  return result;
}

static Var _read_file(String path) => path.open("r").string_close();            // Chain open, read, and close.

static Var _write_file(String path, String text) {
  File file = path.open("w");                                                   // String receiver opens a File.
  int wrote = !text || file.puts(text) >= 0,                                    // Native fputs via inline adapter.
      closed = file.close() == 0;                                               // Native fclose; always attempted.
  return _bool(wrote && closed);                                                // C Boolean result -> Lisp truth.
}

/* Ordinary function conversion infers fixed native signatures. Rest
   natives consume one List. The x2c compile-time macro $rest supplies that
   signature when building the native registry; it does not perform Lisp
   macro expansion.
*/
macro Expression $rest(Expr $fn) =>                                             // Returns syntax at compile time.
  (Func.new_rest($fn, %((func (("List"))) "Var")))                              // Native signature as a List literal.

static void _install_natives(Interp *self) {
  List natives = %(                                                             // Rows: Lisp name, bind name, Func.
    (car             "Var_car"              ${Func.var(Var.car)})               // Function infers native signature.
    (cdr             "Var_cdr"              ${Func.var(Var.cdr)})               // ${...} evaluates a full expression.
    (cons            "Var_cons"             ${Func.var(Var.cons)})              // Direct function caches Func wrapper.
    (atom?           "lisp_atom"            ${Func.var(_atom)})                 // Nested quoted text is x2c String.
    (pair?           "lisp_pair"            ${Func.var(_pair)})
    (list?           "lisp_list"            ${Func.var(_list)})
    (eq?             "lisp_eq"              ${Func.var(_eq)})
    (type            "lisp_type"            ${Func.var(Var.tag)})
    (number?         "lisp_number"          ${Func.var(_number)})
    (string?         "lisp_string"          ${Func.var(_string)})
    (symbol?         "lisp_symbol"          ${Func.var(_symbol)})
    (procedure?      "lisp_procedure"       ${Func.var(_procedure)})
    (reverse         "List_reverse"         ${Func.var(List.reverse)})
    (length          "List_len"             ${Func.var(List.len)})
    (_match          "List_match"           ${Func.var(List.match)})
    (match-replace   "lisp_match_replace"   ${Func.var(_match_replace)})
    (search          "List_search"          ${Func.var(List.search)})
    (_search-replace "List_search_replace"  ${Func.var(List.search_replace)})
    (_add            "lisp_add"             ${Func.var(_add)})
    (_binary         "Var_binary"           ${Func.var(Var.binary)})
    (_compare        "lisp_compare"         ${Func.var(_compare)})
    (+               "lisp_plus"            ${$rest(_plus)})                    // Macro supplies the rest signature.
    (-               "lisp_minus"           ${$rest(_minus)})
    (*               "lisp_times"           ${$rest(_times)})
    (/               "lisp_divide"          ${$rest(_divide)})
    (=               "lisp_eq_chain"        ${$rest(_eq_chain)})
    (<               "lisp_lt_chain"        ${$rest(_lt_chain)})
    (<=              "lisp_le_chain"        ${$rest(_le_chain)})
    (>               "lisp_gt_chain"        ${$rest(_gt_chain)})
    (>=              "lisp_ge_chain"        ${$rest(_ge_chain)})
    (str             "lisp_str"             ${Func.var(_str)})
    (repr            "lisp_repr"            ${Func.var(_repr)})
    (string-length   "String_len"           ${Func.var(String.len)})
    (_string-append  "lisp_string_append"   ${Func.var(_string_append)})
    (substring       "lisp_substring"       ${Func.var(_substring)})
    (string-downcase "lisp_string_downcase" ${Func.var(_string_downcase)})
    (()              "lisp_read_file"       ${Func.var(_read_file)})            // No global name; available via bind.
    (()              "lisp_write_file"      ${Func.var(_write_file)})
    (()              "List_sort"            ${Func.var(List.sort)})
  );
  foreach (List row, natives) {                                                 // Typed List traversal.
    (Var name, String symbol, Func fn) = row;                                   // Convert each positional binding.
    self.natives[symbol] = fn;                                                  // Func boxes as a Map value.
    if (!name.is_nil()) self.globals[name] = fn;                                // Receiver-style Var predicate.
  }
}

/* Building the rest of the language in itself ------------------------------------------------------------------------

   Startup evaluates the following definitions in order. defmacro is used               native functions + core
   to define defun and if. Recursive functions then implement map, filter,                        |
   folds, and other collection operations.                                                   defmacro
                                                                                                  |
   Runtime Lisp macros express new constructs as transformations into                      defun      if
   existing forms. They extend the language without adding evaluator                              |
   branches. These definitions combine the core forms with the native                    map / foldl / let / ...
   operations registered above, including binding and collection functions.

   The percent literal constructs a List containing these definitions. It
   does not evaluate them; _interpreter evaluates each definition at
   startup.
*/

static List _stdlib = %(                                                        // Static List; x2c hoists its setup.
  (def nil ())                                                                  // Empty List is literal data here.
  (def true 'true)                                                              // Quote expands to a List form.
  (def false nil)                                                               // Bare nil is a literal Symbol.
  (def defmacro                                                                 // Runtime Lisp macro, not x2c macro.
    (macro (name params body) `(def ,name (macro ,params ,body))))              // ` template; , inserts each value.
  (defmacro defun (name params body) `(def ,name (lambda ,params ,body)))       // defun expands to a Lisp lambda.
  (defmacro if (test ontrue onfalse) `(cond (,test ,ontrue) (true ,onfalse)))   // Our macro reduces if to core cond.
  (defun list (. values) values)                                                // Dot denotes a Lisp rest parameter.
  (defun not (value) (if value false true))                                     // Lisp function uses our if macro.
  (defun null? (value) (eq? value nil))                                         // Lisp wrapper calls native eq?.
  (def equal? eq?)                                                              // Bind another name to one callable.
  (defmacro and (. forms)                                                       // Runtime macro: short-circuiting.
    (if (null? forms) true                                                      // Reuse the null? defined above.
        (if (null? (cdr forms)) (car forms)                                     // cdr advances; car extracts one form.
            `(if ,(car forms) (and ,@(cdr forms)) false))))                     // ` template; , value; ,@ elements.
  (defmacro or (. forms)                                                        // Introduced names are not hygienic.
    (if (null? forms) false                                                     // Call our Lisp null? predicate.
        (if (null? (cdr forms)) (car forms)                                     // cdr advances; car extracts one form.
            `((lambda (_or_value)                                               // Backquote builds a Lisp template.
                (if _or_value _or_value (or ,@(cdr forms))))                    // ,@ inserts the remaining forms.
              ,(car forms)))))                                                  // , evaluates and inserts one form.
  (defun _last (values)                                                         // Ordinary recursive Lisp function.
    (if (null? values) nil                                                      // Use our null? to end traversal.
        (if (null? (cdr values)) (car values) (_last (cdr values)))))           // Tail recursion finds the last value.
  (defun begin (. values) (_last values))                                       // Return last pre-evaluated argument.
  (defun map (procedure values)                                                 // Structural recursion over a List.
    (if (null? values) nil                                                      // No input produces an empty List.
        (cons (procedure (car values)) (map procedure (cdr values)))))          // Native cons; either callable kind.
  (defun filter (predicate values)                                              // Keep elements satisfying a callable.
    (if (null? values) nil                                                      // Stop before invoking the predicate.
        (if (predicate (car values))                                            // Native car feeds a callable value.
            (cons (car values) (filter predicate (cdr values)))                 // cons retains a selected element.
            (filter predicate (cdr values)))))                                  // Recurse without retaining the head.
  (defun foldl (procedure initial values)                                       // Pass a callable as a value.
    (if (null? values) initial                                                  // Empty input returns the accumulator.
        (foldl procedure (procedure initial (car values)) (cdr values))))       // Fold invokes the supplied function.
  (defun member (value values)                                                  // Return matching suffix, or ().
    (if (null? values) nil                                                      // No candidates remain: return nil.
        (if (equal? value (car values)) values (member value (cdr values)))))   // Reuse equal?, our alias for eq?.
  (defun assoc (key pairs)                                                      // Return matching row, or ().
    (if (null? pairs) nil                                                       // Use the shared empty-List predicate.
        (if (and (pair? (car pairs)) (equal? key (car (car pairs))))            // Our and macro guards the row access.
            (car pairs)                                                         // Return the whole matching row.
            (assoc key (cdr pairs)))))                                          // Continue through remaining rows.
  (defun _append2 (left right)                                                  // Immutable Lists safely share tails.
    (if (null? left) right (cons (car left) (_append2 (cdr left) right))))      // Base case shares the right List.
  (defun _append_lists (lists)                                                  // Repeat two-List append.
    (if (null? lists) nil                                                       // No Lists: return the empty List.
        (if (null? (cdr lists)) (car lists)                                     // One List: reuse it unchanged.
            (_append2 (car lists) (_append_lists (cdr lists))))))               // Compose the two append helpers.
  (defun append (. lists) (_append_lists lists))                                // Rest parameter gathers List values.
  (defun sub (a b) (_binary a '- b))                                            // Lisp calls native Var.binary.
  (defun mul (a b) (_binary a '* b))                                            // Native arithmetic, Lisp call syntax.
  (defun div (a b) (_binary a '/ b))                                            // Symbol selects native division.
  (defun mod (a b) (_binary a '% b))                                            // Punctuation used as a Symbol value.
  (def % mod)                                                                   // Operator alias is a name binding.
  (defun string-append (. strings) (foldl _string-append "" strings))           // Lisp fold calls our native adapter.
  (defmacro let (bindings body)                                                 // Expand bindings into a call.
    `((lambda ,(map car bindings) ,body)                                        // Our map calls native car; , inserts.
      ,@(map cadr bindings)))                                                   // Our map calls Lisp cadr; ,@ splices.
  (defmacro let* (bindings body)                                                // Nest bindings for sequential scope.
    (if (null? bindings) body                                                   // No bindings: return the body form.
        `(let (,(car bindings)) (let* ,(cdr bindings) ,body))))                 // Comma inserts into a Lisp template.
  (defun caar (value) (car (car value)))                                        // Compose ordinary Lisp calls.
  (defun cadr (value) (car (cdr value)))                                        // Second element by List composition.
  (defun cdar (value) (cdr (car value)))                                        // Tail of the first nested List.
  (defun cddr (value) (cdr (cdr value)))                                        // Share the tail after two elements.
  (defun match (subject pattern)                                                // Match evaluated values as List data.
    (if (list? subject) (_match subject pattern) nil))                          // Call registered native List.match.
  (defun bound (bindings binder) (cadr (assoc binder bindings)))                // Extract a match binding from data.
  (defun search-replace (subject pattern template)                              // Patterns and templates are values.
    (if (match subject pattern) (match-replace subject pattern template)        // Use our match before replacement.
        (_search-replace subject pattern template)))                            // Registered native List search.
  (defun binder? (value)                                                        // Recognize a pattern-binding Symbol.
    (and (symbol? value)                                                        // Short-circuit before String queries.
         (member (substring (str value) 0 1) '("?" "*"))                        // Quoted List of allowed prefixes.
         (> (string-length (str value)) 1)))                                    // Exclude unnamed pattern wildcards.
  (defun _binders (pattern)                                                     // Collect binders by List recursion.
    (cond ((list? pattern)                                                      // Structural case analysis in Lisp.
           (foldl (lambda (found part) (append found (_binders part)))          // Our fold receives a Lisp lambda.
                  nil pattern))                                                 // Accumulate from the empty List.
          ((binder? pattern) (list pattern))                                    // Our list wraps one found binder.
          (true nil)))                                                          // No binder contributes no elements.
  (defun _binder-lets (source binders)                                          // Expose match bindings as locals.
    (map (lambda (binder)                                                       // Our map receives a Lisp closure.
           (list binder (list 'bound source (list 'quote binder))))             // Quote emits data, not a name lookup.
         binders))                                                              // Apply to each collected binder.
  (defmacro match-case (subject . clauses)                                      // Runtime macro builds Lisp Lists.
    (foldl                                                                      // Use our fold to construct code.
      (lambda (rest clause)                                                     // Wrap remaining choices in a cond.
        (if (equal? (car clause) 'else) (cadr clause)                           // Quoted else is data for comparison.
          `(let ((_match-case-subject ,subject))                                // Backquote template; comma inserts.
             (let ((_match-case-bindings                                        // Construct a nested binding form.
                     (match _match-case-subject ',(car clause))))               // ', inserts a value then quotes it.
               (cond (_match-case-bindings                                      // Generated test uses match bindings.
                       (let ,(_binder-lets '_match-case-bindings                // Comma inserts computed bindings.
                                           (_binders (car clause)))             // Reuse our binder-collection helper.
                         ,(cadr clause)))                                       // Comma inserts the clause body.
                     (true ,rest))))))                                          // Comma inserts remaining choices.
      nil (reverse clauses)))                                                   // Process clauses from last to first.
  (def add _add)                                                                // Alias an existing native callable.
  (def last _last)                                                              // Alias an existing Lisp closure.
  (def len length)                                                              // Name binding preserves identity.
  (def reduce foldl)                                                            // Higher-order function as a value.
  (def lower string-downcase)                                                   // Alias reuses the native function.
);

/* Completing a session -----------------------------------------------------------------------------------------------

   A batch is read and evaluated one form at a time. Earlier definitions               form 1 -> value 1
   are available to later forms, and the last value is the batch's result.             form 2 -> value 2
   A later read or evaluation error does not roll back effects already                   ...
   performed. File import is another source of such batches, with the same             form n -> final value
   environment.                                                                           one shared environment
*/
static Var _eval_text(Interp *self, String source) {
  Scope storage = $auto(Scope.new());                                           // Destroy Scope on block exit.
  Reader reader = Reader.scan(source, 0, &storage);                             // C address selects token ownership.
  Var form, result = %();                                                       // Empty List implicitly boxes as Var.
  while ((form = reader.read()) is not void)                                    // Receiver call; distinct void value.
    result = self.eval(NULL, form);                                             // Receiver call in global environment.
  return result;
}

static Var _import_file(Interp *self, String path) {
  File source = $auto(path.open("r"));                                          // Close File on block exit.
  Block content = $auto(Block.new(sizeof(char)));                               // Release Block on block exit.
  if (source.read_into(content) == FILE_READ_EOF) return %();                   // C status; empty List result.
  if (content.length > INT_MAX) {                                               // Native C size limit.
    size_t size = content.length, int limit = INT_MAX;                          // Mixed types in one declaration.
    $fail(<size-limit>, %"Lisp.eval_file", <size>, size, <limit>, limit);       // Integers box into the error List.
  }
  if (memchr(content.bytes, '\0', content.length))                              // C library scans the raw bytes.
    $fail(<bad-arg>, %"Lisp.eval_file", <why>, %"embedded NUL");                // String details in generated error.
  return _eval_text(self, String.new_len(content.bytes, (int) content.length)); // C bytes converted to x2c String.
}

static Var _reserved(void) => Var.null();                                       // Expression body; void Var value.

/* Special forms receive distinct callable identities before library
   loading. Saving one under another name preserves its behavior; shadowing
   its original name does not change the saved callable. The two lookup
   Maps retain this distinction between a name and the callable value bound
   to it.
*/
static Interp _interpreter(void) {
  Interp self = { %{}, %{}, %{}, %{} };                                         // Four independently allocated Maps.
  _install_natives(&self);                                                      // Pass a C stack address.
  foreach (Var name, %(quote quasiquote cond def lambda macro eval              // Typed iteration over literal data.
                       apply bind import)) {                                    // Iterate literal Symbol values.
    Func fn = Func.new(_reserved, %((func ((void))) "Var"));                    // new creates fresh callable identity.
    self.reserved[name] = fn;                                                   // Func implicitly boxes as Var.
    self.specials[fn] = name;                                                   // A callable can be a Map key.
  }
  foreach (Var form, _stdlib) self.eval(NULL, form);                            // Typed iteration; receiver call.
  return self;
}

/* Incremental reading and evaluation ---------------------------------------------------------------------------------

   The REPL evaluates complete forms, retains incomplete input for the next            +------+  +------+  +-------+
   line, and reports malformed input as an error. The saved start position             | read |->| eval |->| print |
   prevents rereading earlier complete forms and repeating their effects.              +--^---+  +------+  +---+---+
   Evaluation errors are caught per form, so the next form can still run.                 |                   |
                                                                                          +-------------------+
   Each function call uses the native stack. There is no tail-call
   guarantee, so sufficiently deep Lisp recursion can exhaust that stack.
   The production word machine uses a different execution strategy.
*/
typedef struct Repl {
  Buffer source;                                                                // Mutable input buffer.
  Scope storage;                                                                // Owns token allocations.
  Reader reader;                                                                // Reader state stored by value.
  unsigned cursor;                                                              // Native byte offset into the input.
  int failed, incomplete, interactive, done;                                    // C integer flags coordinate the REPL.
} Repl;

static int Repl.read_line(Repl *self) {
  if (self.interactive) {
    Stdout.puts(self.incomplete ? ".. " : "> ");                                // Native fputs; inline argument swap.
    Stdout.flush();                                                             // Direct C fflush; no dispatch.
  }
  String line = Stdin.readline();                                               // Read an immutable String.
  if (!line) {                                                                  // NULL String signals EOF here.
    if (self.incomplete) {
      Stderr.puts("error: incomplete form at end of input\n");                  // Native fputs on the C stderr stream.
      self.failed = 1;
    }
    self.done = 1;
    return 0;
  }
  self.source.write(line);                                                      // Buffer receiver appends input.
  return 1;
}

static Var Repl.finish_batch(Repl *self) {
  self.storage.destroy();                                                       // Release the allocation Scope.
  self.storage = NULL;                                                          // C null clears the handle.
  self.reader = (Reader) {0};                                                   // Zero-initialize a struct value.
  if (!self.incomplete) {
    self.source.clear();                                                        // Reuse the mutable Buffer storage.
    self.cursor = 0;
  }
  return void;                                                                  // Return the distinct void value.
}

/* Read one form. void means no form is ready; done distinguishes EOF from
   incomplete input or an exhausted batch. The storage scope owns the
   tokens until the batch is finished; parsed forms use the surrounding
   session.
*/
static Var Repl.read_unit(Repl *self) {
  if (!self.reader.tokens && !self.read_line()) return void;                    // Receiver-style function call.
  try {                                                                         // Structured exception boundary.
    if (!self.reader.tokens) {                                                  // Dot chains pointer and value fields.
      self.storage = Scope.new();                                               // Explicit allocation lifetime.
      self.incomplete = 0;
      self.reader = Reader.scan(self.source, self.cursor, &self.storage);       // C address passes the owned Scope.
    }
    Var form = self.reader.read();                                              // Struct receiver, no explicit &.
    if (form is not void) return form;                                          // Return preserves batch storage.
  }
  catch %(incomplete *): {                                                      // Specific catch before the catch-all.
    self.incomplete = 1;
    self.cursor = self.reader.start;                                            // Retain the incomplete form offset.
  }
  catch %(?code *detail): {                                                     // Bind cause and remaining data.
    Stderr.printf("error: %s\n", cons(code, detail).repr());                    // List -> readable String.
    self.failed = 1;
  }
  return self.finish_batch();                                                   // Receiver call returns a void Var.
}

static int _repl(Interp *self) {
  Buffer source = $auto(Buffer.new(0));                                         // Release Buffer on block exit.
  Repl repl = { .source = source,                                               // C designated field initializer.
                .interactive = isatty(Stdin.fileno()) };                        // x2c file descriptor -> POSIX call.
  defer repl.storage.destroy();                                                 // Destroy remaining tokens on exit.
  while (!repl.done) {                                                          // Same dot for a stack struct value.
    Var form = repl.read_unit();                                                // Receiver call takes &repl.
    if (form is void) continue;                                                 // Test the distinct void value.
    try {                                                                       // Structured exception boundary.
      Var value = self.eval(NULL, form);                                        // Receiver call returns a Var.
      Stdout.printf("%s\n", value.repr());                                      // Var provides readable output.
    }
    catch %(?code *detail): {                                                   // Pattern destructures the error.
      Stderr.printf("error: %s\n", cons(code, detail).repr());                  // Construct List, then format it.
      repl.failed = 1;
    }
  }
  return !repl.failed;
}

/* Command-line interface ---------------------------------------------------------------------------------------------

   main converts argv to x2c Strings and matches the supported argument
   forms. With no arguments it starts the REPL; -e evaluates a supplied
   expression, --selftest runs a small check, and a single path loads a
   Lisp source file. Each mode starts with the native registry and _stdlib
   definitions loaded.
*/
int main(int argc, char **argv) {                                               // Standard C argc/argv entry point.
  $scope() {                                                                    // Session-wide allocation region.
    try {                                                                       // Structured exception boundary.
      Array args = range(0, argc - 1, 1)                                        // Lazy range iterator.
        .map(%!(int i) using &argv                                              // Typed lambda; capture C pointer.
          => String.new(argv[i]))                                               // C indexing -> immutable String.
        .array();                                                               // Materialize the iterator as Array.
      Interp self = _interpreter();                                             // Session record returned by value.
      String source;                                                            // Immutable String held by a handle.
      match (args.list()) {                                                     // Chain conversion into matching.
        case %(?): return _repl(&self) ? 0 : 1;                                 // ? matches without binding.
        case %(? "-e" ?text): source = text;                                    // Bound Var converts to String.
        case %(? "--selftest"):                                                 // Match a literal String argument.
          source = "(list (apply + '(10 20 12)) (append '(1 2) '(3 4)))";       // C literal promotes to cached String.
        case %(? ?file): {                                                      // Wildcard plus bound filename.
          const char *path = file.str();                                        // Borrow a C string pointer.
          source = File.open(path ? path : "", "r").string_close();             // Chain File open, read, and close.
        }
        default: {                                                              // Fallback when no pattern matches.
          Stderr.printf("usage: %s [--selftest | -e FORM | FILE]\n",            // Native format string with File I/O.
                        args[0].str());                                         // Array indexing, then String access.
          return 1;
        }
      }
      Stdout.printf("%s\n",                                                     // C format string; x2c File receiver.
                    _eval_text(&self, source).repr());                          // C address; chain Var formatting.
      return 0;
    }
    catch %(?code *detail):                                                     // Destructure the error as a List.
      Stderr.printf("error: %s\n", cons(code, detail).repr());                  // Construct List, then format it.
  }
  return 1;
}
