/*  reference-lisp.x -- building a Lisp interpreter in x2c

    A Lisp program is represented as a tree of values. Evaluation traverses
    that tree, resolves names through environments, and applies functions
    to arguments. Quotation preserves a form as data instead of evaluating it.

      (+ 1 2)             evaluates to 3
      '(+ 1 2)            evaluates to the List (+ 1 2)
      (eval '(+ 1 2))     evaluates that List as a call, producing 3

    The evaluator is followed by environments, closures, runtime Lisp macro
    expansion, and the reader. Definitions written in Lisp extend the core
    evaluation rules with conditionals, bindings, and collection operations.

    x2c supplies values, collections, tokenization, and native function calls.
    This file implements Lisp evaluation independently of the production
    Lisp object and word-code machine. Evaluation uses native recursive calls.

    Two distinct macro systems appear here. The x2c macros $fail and $rest
    expand when this file is compiled. Runtime Lisp macros are Fn closures
    executed by this interpreter while evaluating a Lisp program.

    The implementation follows x2c Lisp, including its rules for capture and
    errors; those rules sometimes differ from Scheme or Common Lisp.
*/

#include <unistd.h>

/* Values, names, and memory

   Var can store a number, String, List, or callable. A nonempty List has a
   first element (car) and a remaining List (cdr); the empty List, (), marks
   its end. Nested Lists represent the structure of a Lisp expression.

   Fn stores a parameter List, a body, and captured local bindings. During a
   call, each parameter is bound to its corresponding argument value. Captures
   contain copies of local values taken when the closure was created; these
   bindings remain available when its body is evaluated later.

   A runtime Lisp macro uses the same record but receives unevaluated argument
   forms. The macro field selects this calling convention. It does not refer
   to an x2c compile-time macro.
*/
typedef struct Fn {
  List params;
  Var body;
  Map captures;
  int macro;
} *Fn;

/* An environment maps names to values. Each call adds bindings in front of
   an existing environment. Returning discards that local frame; the outer
   bindings need no copying or restoration.
*/
typedef struct Env {
  Map bindings;
  struct Env *parent;
} Env;

/* Global bindings persist across top-level evaluations. The native registry
   maps binding names to host functions. Reserved forms have callable
   identities; name lookup and callable dispatch are separate operations.
*/
typedef struct Interp {
  Map globals, natives;
  /* Reserved names map to functions; specials maps those identities back. */
  Map reserved, specials;
} Interp;

/* The x2c compile-time macro $fail adds the operation pair to raise syntax.
   The other error fields remain explicit at each call site.
*/
macro Statement $fail(Expr $cause, Expr $op, Expr $fields...) => {
  $(quasiquote (raise ,$cause
    (args (literal ("Symbol") "operation" operation) ,$op ,@$fields)))
}

/* Evaluation: the language in three rules

   Evaluating a name returns its bound value; evaluating a literal returns
   the literal itself. A nonempty List represents a call. Its head is evaluated
   first, and argument handling depends on the resulting callable's type:
   ordinary function, special form, or runtime Lisp macro. Only () is false;
   zero and the empty String are true.

   For (+ 1 (* 2 3)), evaluation first resolves +, then evaluates the arguments
   to 1 and 6. Applying + to these values returns 7. The same rule handles
   calls whose heads are expressions, such as ((lambda (x) x) 7).

   A runtime Lisp macro receives the original argument forms. Its body runs
   in this interpreter and returns a replacement form, which eval evaluates
   in the caller's environment. This expansion happens during Lisp program
   evaluation, after all x2c compile-time macros have already expanded.
*/

static Var Interp.eval(Interp *self, Env *env, Var form) {
  if (form is void) $fail(<void-op>, %"eval");
  if (form.is_atom()) return self.lookup(env, form);
  if (form is not <list> || form.is_nil()) return form;
  List expr = form;
  Var fn = self.eval(env, expr.car());
  List args = expr.cdr();
  if (fn is <lambda>) {
    Fn closure = fn.pointer();
    if (closure.macro) return self.eval(env, self.invoke(env, closure, args));
  }
  else {
    if (fn is not <func>) raise %(not-call (actual ${fn.kind()}));
    if (fn in self.specials)
      return self.special(env, self.specials[fn], args);
  }
  List values = self.eval_args(env, args);
  return self.apply(env, fn, values);
}

/* Evaluation proceeds left to right. That ordering matters when arguments
   define globals, read files, or raise errors: a later failure does not undo
   an earlier effect. The result is a List of values ready for application.
*/
static List Interp.eval_args(Interp *self, Env *env, List forms) {
  Array values = $auto(%[]);
  foreach (Var form, forms) values.push(self.eval(env, form));
  return values;
}

/* Special forms control evaluation

   Ordinary function arguments are evaluated before the function body runs.
   Special forms require different rules: quote returns an unevaluated form,
   lambda constructs a closure without evaluating its body, and cond evaluates
   only the selected clause's body. The evaluator handles these forms directly.

   Each pattern matches an accepted form and binds its components. In cond,
   tests run in order until one is true; only that clause's body is evaluated.
   The runtime Lisp macro if expands into cond.

   def always writes a global binding. eval first obtains a form, then
   evaluates it globally. apply instead obtains a callable and a List of
   values. apply passes those values to the callable without evaluating them
   again, including any Lists that could also be parsed as calls.
*/
static Var Interp.special(Interp *self, Env *env, Symbol op, List args) {
  match (%($op @args)) {
    case %(quote ?form): return form;
    case %(quasiquote ?form): return self.quasiquote(env, form, 0);
    case %(def ?name ?form) if (name.is_atom()):
      return self.globals[name] = self.eval(env, form);
    case %(lambda ?(List params) ?body):
      return self.closure(env, params, body, 0);
    case %(macro ?(List params) ?body):
      return self.closure(env, params, body, 1);
    case %(cond *clauses) if (clauses): {
      foreach (Var clause, clauses) {
        match (clause) {
          case %(?test ?body):
            if (!self.eval(env, test).is_nil()) return self.eval(env, body);
          default: _bad_clause(clause);
        }
      }
      return %();
    }
    case %(eval ?form): return self.eval(NULL, self.eval(env, form));
    case %(apply ?fn ?values): {
      Var callable = self.eval(env, fn), actual = self.eval(env, values);
      return self.apply(env, callable, _list_argument(actual, "apply"));
    }
    case %(bind ?name ?sig): {
      Var target = self.eval(env, name), type = self.eval(env, sig);
      return self.bind(target, type);
    }
    case %(import ?form): {
      Var path = self.eval(env, form);
      Atom hook = Atom.intern("_x2c.import-hook");
      _string_argument(path, "import");
      if (hook in self.globals)
        return self.apply(NULL, self.globals[hook], %($path));
      return _import_file(self, path);
    }
  }
  return _bad_form(op, args);
}

/* Applying a value

   eval converts expressions to values; apply invokes a callable with values
   already evaluated. For example, (apply list '(a b)) returns (a b), without
   looking up either a or b.

   Applying a closure evaluates its saved body with new bindings; applying
   a native callable invokes an x2c function. Runtime Lisp macros require
   unevaluated argument forms and subsequent evaluation of their expansion.
   apply accepts evaluated values and rejects runtime Lisp macros. x2c
   compile-time macros do not enter this path.
*/
static Var Interp.apply(Interp *self, Env *env, Var fn, List values) {
  if (fn is <lambda>) {
    Fn closure = fn.pointer();
    if (closure.macro) $fail(<not-call>, %"apply", <actual>, fn.kind());
    return self.invoke(env, closure, values);
  }
  if (fn is not <func>) raise %(not-call (actual ${fn.kind()}));
  if (fn in self.specials) {
    if (self.specials[fn] != <apply>.var())
      $fail(<not-call>, %"apply", <actual>, fn.kind());
    match (values) case %(?callable ?args):
      return self.apply(env, callable, _list_argument(args, "apply"));
    return _bad_form(<apply>, values);
  }
  return _native_call(fn, values);
}

/* Name lookup and captured bindings

   Lookup searches the nearest environment first, then globals, then reserved
   names. An inner binding shadows an outer one without modifying it. Keeping
   bindings in Maps also separates a missing name from a name bound to ().

   This closure captures the local binding x = 10:

     (def add-ten (let ((x 10)) (lambda (y) (+ x y))))
     (add-ten 7)     // 17, after the let call has returned

   Call frames can live on the native stack. Closures and their capture Maps
   belong to the session Scope, so saved bindings outlive those calls. The
   values they refer to keep their ordinary ownership; immutable Strings and
   Lists live in canonical pools.
*/

static Var Interp.lookup(Interp *self, Env *env, Var name) {
  for (; env; env = env.parent)
    if (name in env.bindings) return env.bindings[name];
  if (name in self.globals) return self.globals[name];
  if (name in self.reserved) return self.reserved[name];
  raise %(unbound (name $name));
}

/* x2c Lisp collects captures by flattening a List body and copying values
   for names bound in local environments. This includes names inside quoted
   and nested forms, but excludes parameters and reserved names. Global
   bindings are looked up during evaluation rather than copied into closures.

   This is not a free-variable analysis or a purely lexical environment.
   Names absent from the captures may still resolve in the caller. A scalar
   body captures nothing. Consequently, a lambda's result can differ from
   the result under lexical scope rules used by other Lisp implementations.
*/
static Var Interp.closure(Interp *self, Env *env,
                          List params, Var body, int macro) {
  Map captures = %{};
  if (body is <list>) foreach (Var name, body.list().flatten()) {
    if (!name.is_atom() || name in self.reserved ||
        name in captures || name in params) continue;
    for (Env *local = env; local; local = local.parent) {
      if (name in local.bindings) {
        captures[name] = local.bindings[name];
        break;
      }
    }
  }
  Fn closure = Scope.malloc(sizeof(struct Fn));
  *closure = (struct Fn) { params, body, captures, macro };
  return Var.new(<lambda>, closure);
}

/* Invocation pairs parameters with values. A dotted parameter, as in
   (lambda (first . rest) ...), binds the remaining arguments as one List.
   The body's lookup order is parameters, captures, caller frames, globals,
   and reserved names. A captured value takes precedence over a caller binding
   of the same name.
*/
static Var Interp.invoke(Interp *self, Env *env, Fn closure, List values) {
  Map bindings = $auto(%{});
  for (List params = closure.params; params; params = params.cdr()) {
    Var (name, rest) = params;
    if (name.is_atom() && name.str() == ".") {
      if (!params.cdr()) $fail(<bad-sig>, %"apply", <value>, closure.body);
      bindings[rest] = values;
      values = NULL;
      break;
    }
    if (!values) $fail(<bad-arity>, %"apply", <value>, closure.body);
    bindings[name] = values.car();
    values = values.cdr();
  }
  if (values) $fail(<bad-arity>, %"apply", <value>, closure.body);
  Env captured = { closure.captures, env };
  Env local = { bindings, &captured };
  return self.eval(&local, closure.body);
}

/* Quotation as a language for constructing code

   quote returns its argument without evaluation. Quasiquote evaluates the
   comma-marked expressions within a template. Comma-at inserts
   the elements of a List into the surrounding List:

     (let ((x 7) (xs '(8 9))) `(a ,x ,@xs))     // (a 7 8 9)

   There are two result shapes here. quasiquote produces one value;
   quoted_item produces the sequence of elements contributed by an item.
   An ordinary item contributes one element; a splice may contribute many.
   The containing List is constructed by concatenating these item sequences.

   The depth tracks nested quasiquotes. Processing a nested quasiquote
   increments it; processing a nested unquote decrements it. An unquote is
   evaluated only at depth zero. Otherwise, it remains in the returned form.
*/
static Var Interp.quasiquote(Interp *self, Env *env, Var form, int depth) {
  if (form is not <list> || form.is_nil()) return form;
  List expr = form;
  Var (head, argument) = expr;
  Var (quote, unquote, splice) = %(quasiquote unquote unquote-splicing);
  if (head == quote)
    return cons(head, self.quasiquote(env, expr.cdr(), depth + 1));
  if (head == unquote || head == splice) {
    if (expr.len() != 2) $fail(<bad-arity>, %"quasiquote", <value>, form);
    if (depth) return cons(head, self.quasiquote(env, expr.cdr(), depth - 1));
    Var value = self.eval(env, argument);
    if (head == splice)
      $fail(<bad-types>, %"quasiquote-splice", <actual>, form.kind());
    return value;
  }
  List first = self.quoted_item(env, head, depth);
  List rest = self.quasiquote(env, expr.cdr(), depth);
  return first.append(rest);
}

static List Interp.quoted_item(Interp *self, Env *env, Var form, int depth) {
  match (form) case %(unquote-splicing ?argument) if (!depth): {
    Var value = self.eval(env, argument);
    if (value is not <list>)
      $fail(<bad-types>, %"quasiquote-splice", <actual>, value.kind());
    return value;
  }
  return %(${self.quasiquote(env, form, depth)});
}

/* Errors are part of the language's observable behavior

   A malformed call is different from an unbound name or a value of the
   wrong type. These helpers construct the corresponding error causes and
   details. Errors are structured data that a surrounding x2c catch can match.

   $fail, defined near the top, is an x2c compile-time macro that constructs
   raise syntax while compiling this x2c file. Runtime Lisp macros in _stdlib
   construct Lisp forms during evaluation. The shared use of Lists does not
   imply that these two macro systems share an execution phase.
*/

static List _list_argument(Var value, String op) {
  if (value is not <list>)
    $fail(<bad-types>, op, <actual>, value.kind(), <want>, %"List");
  return value;
}

static String _string_argument(Var value, String op) {
  if (value is not <string>)
    $fail(<bad-types>, op, <actual>, value.kind(), <want>, %"String");
  return value;
}

static Var Interp.bind(Interp *self, Var name, Var sig) {
  _string_argument(name, "bind");
  if (sig is not <list>) $fail(<bad-sig>, %"bind", <value>, sig);
  if (name in self.natives) return self.natives[name];
  raise %(no-symbol (name $name) (sig $sig));
}

static void _bad_clause(Var clause) {
  if (clause is not <list>)
    $fail(<bad-types>, %"cond", <value>, clause, <want>, %"List");
  $fail(<bad-arity>, %"cond-clause",
        <expected>, 2, <actual>, clause.list().len(), <value>, clause);
}

static Var _bad_form(Symbol name, List args) {
  if (name == <lambda> || name == <macro>)
    $fail(<bad-sig>, name, <value>, args);
  int n = args.len();
  if (name == <def>)
    $fail(<bad-arity>, %"def", <expected>, 2, <actual>, n, <value>, args);
  int want = name == <apply> || name == <bind> ? 2 : 1;
  $fail(<bad-arity>, name.str(), <expected>, want, <actual>, n);
}

/* Reading: from characters to values

   The reader parses spelling and nesting without evaluating expressions.
   Reading (+ 1 2) constructs a List; it does not look up + or add. Evaluation,
   quotation, and runtime Lisp macro expansion all consume these same values,
   so the reader needs no separate representation for executable forms.

   Tokenization recognizes words, numbers, strings, and punctuation. Recursive
   descent supplies the grammar: after an opening parenthesis, read forms
   until its closing parenthesis. Reading a nested List uses the same rule.
   Prefixes are shorthand: 'x becomes (quote x), and commas and backquotes
   become the corresponding unquote and quasiquote Lists.
*/
typedef struct Reader {
  Tokenizer tokens;
  String source;
  unsigned base, start;
} Reader;

static Var Reader._error(Reader *self, Symbol cause, unsigned at) {
  int line = 1, column = 1;
  scan_next_line_col(self.source, (int) at, &line, &column);
  if (cause == <incomplete>)
    raise %(incomplete (source ${self.source}) (line $line) (column $column));
  raise %(malformed (source ${self.source}) (line $line) (column $column));
}

static Var Reader._form(Reader *self, Token token) {
  if (!token || token.type == <eof>)
    return self._error(<incomplete>, self.start);
  String text = token.text, prefix = NULL;
  switch (token.type) {
    case <error>:
      if (self.tokens.status() == <incomplete>)
        return self._error(<incomplete>, self.start);
      break;
    case <"(">: {
      Array elements = $auto(%[]);
      while (1) {
        Token next = self.tokens.next();
        if (next && next.type == <")">) return elements.list();
        elements.push(self._form(next));
      }
    }
    case <"'">:  prefix = "quote";      break;
    case <"`">:  prefix = "quasiquote"; break;
    case <",">:  prefix = "unquote";    break;
    case <",@">: prefix = "unquote-splicing"; break;
    case <lit-char*>:
      return String.new_len(text + 1, token.len - 2).unescape();
    case <lit-int>: {
      long value;
      if (!text.try_long(&value)) break;
      if (value == (int) value) return (int) value;
      return value;
    }
    case <lit-float>: {
      double value;
      if (text.try_double(&value)) return value;
      break;
    }
    case <lit-symbol>: {
      String inner = text[1] == '"'
        ? String.new_len(text + 2, token.len - 4).unescape()
        : String.new_len(text + 1, token.len - 2);
      if (inner) return Symbol.new(inner);
      break;
    }
    case <ident>:
      return Atom.intern(text.unescape());
  }
  if (prefix) {
    Var name = Atom.intern(prefix), inner = self._form(self.tokens.next());
    return %($name $inner);
  }
  return self._error(<malformed>, self.base + token.pos);
}

/* Tokens describe one source batch and may be discarded after it is read.
   The constructed values must outlive them: a definition can save a body for
   a later call. Token storage is released separately from the returned forms.
*/
static Reader Reader.scan(String source, unsigned base, Scope *storage) {
  Reader reader = { .source = source, .base = base };
  $scope(storage) {
    reader.tokens = Tokenizer.new_mode(source ? source + base : NULL, <lisp>);
    reader.tokens.scan();
  }
  return reader;
}

/* Reader.next returns void at end of input. The empty List () is a valid
   form, so it cannot serve as the end marker. Incomplete input raises an
   error that the REPL handles by retaining the text for the next input line.
*/
static Var Reader.next(Reader *self) {
  Token first = self.tokens.next();
  if (!first || first.type == <eof>) return void;
  self.start = self.base + first.pos;
  return self._form(first);
}

/* Native functions

   Primitive operations are implemented as x2c functions invoked through Func.
   Func signatures specify argument and result types. eval evaluates the
   argument expressions before _native_call passes their values to Func.apply.

   Predicates translate native conditions into Lisp truth values. Arithmetic
   and collection primitives are used by the recursive and higher-order
   operations defined in Lisp below.
*/

static Var _native_call(Func native, List values) {
  FuncArg *args = Scope.malloc(values.len() * sizeof(FuncArg));
  defer Scope.free(args);
  int count = 0;
  foreach (Var value, values) args[count++] = FuncArg.value(value);
  return native.apply(count, args);
}

static int _is_number(Var v) {
  Symbol k = v.kind();
  return k == <integer> || k == <floating>;
}

static Var _bool(int x)      => x ? <true>.var() : %().var();
static Var _atom(Var v)      => _bool(v is not <list> || v.is_nil());
static Var _pair(Var v)      => _bool(v is <list> && !v.is_nil());
static Var _list(Var v)      => _bool(v is <list>);
static Var _number(Var v)    => _bool(_is_number(v));
static Var _string(Var v)    => _bool(v is <string>);
static Var _symbol(Var v)    => _bool(v.kind() == <symbol>);
static Var _procedure(Var v) => _bool(v is <func> || v is <lambda>);
static Var _eq(Var a, Var b) => _bool(a == b);

static Var _compare(Var a, Var b) {
  if (!_is_number(a) || !_is_number(b))
    $fail(<bad-types>, %"lisp_compare",
          <left-kind>, a.kind(), <right-kind>, b.kind());
  return a.compare(b);
}

static Var _add(Var a, Var b) =>
  a is <string> || b is <string> ? %"$a$b".var() : a.binary(<+>, b);

static Var _plus(List values) {
  Var seed = 0;
  if (values && values.car() is <string>) seed = String.new("");
  return values.foldl(seed, _add);
}

/* A fold combines a sequence with a running result. Addition and
   multiplication have empty cases, 0 and 1. Subtraction and division require
   an argument: one means negation or reciprocal; several combine left to
   right. Thus (- 10 3 2) means (10 - 3) - 2, not 10 - (3 - 2).
*/
static Var _arithmetic(List values, Symbol op, Var identity) {
  if (!values) $fail(<bad-arity>, op.str(), <expected>, 1, <actual>, 0);
  Var result = values.car();
  if (!values.cdr()) return identity.binary(op, result);
  foreach (Var value, values.cdr()) result = result.binary(op, value);
  return result;
}

static Var _minus(List xs)  => _arithmetic(xs, <->, 0);
static Var _divide(List xs) => _arithmetic(xs, </>, 1);
static Var _times(List xs)  => xs.foldl(1, %!(a, b) => a.binary(<*>, b));

/* Chained comparisons test neighboring pairs: (< 1 2 3) succeeds only if
   1 < 2 and 2 < 3. Comparison stops at the first false result; inspecting
   later values could otherwise introduce an error in an unreached comparison.
*/
static Var _chain(List values, String op, int want, int expect) {
  int n = values.len();
  if (n < 2) $fail(<bad-arity>, op, <expected>, 2, <actual>, n);
  Var left = values.car();
  foreach (Var right, values.cdr()) {
    int order = _compare(left, right).integer();
    if (expect ? order != want : order == want) return _bool(0);
    left = right;
  }
  return _bool(1);
}

static Var _eq_chain(List xs) => _chain(xs, "=",  0, 1);
static Var _lt_chain(List xs) => _chain(xs, "<", -1, 1);
static Var _le_chain(List xs) => _chain(xs, "<=", 1, 0);
static Var _gt_chain(List xs) => _chain(xs, ">",  1, 1);
static Var _ge_chain(List xs) => _chain(xs, ">=", -1, 0);

/* These return Var because the native signature appears in Lisp errors. */
static Var _str(Var v)                        => v.str();
static Var _repr(Var v)                       => v.repr();
static Var _string_append(String a, String b) => a + b;
static Var _string_downcase(String s)         => s.lower();
static Var _substring(String s, int a, int b) => s.getslice(a, b, 1);

static Var _match_replace(List input, Var pat, Var template) {
  Var result;
  if (!input.try_match_replace(pat, template, &result)) return input.var();
  return result;
}

static Var _read_file(String path) => path.open("r").string_close();

static Var _write_file(String path, String text) {
  File file = path.open("w");
  int wrote = !text || file.puts(text) >= 0, closed = file.close() == 0;
  return _bool(wrote && closed);
}

/* Ordinary function conversion infers fixed native signatures. Rest natives
   consume one List. The x2c compile-time macro $rest supplies that signature
   when building the native registry; it does not perform Lisp macro expansion.
*/
macro Expression $rest(Expr $fn) =>
  (Func.new_rest($fn, %((func (("List"))) "Var")))

static void _install_natives(Interp *self) {
  /* Lisp name, bind spelling, implementation. () means import-only. */
  List natives = %(
    (car             "Var_car"              ${Func.var(Var_car)})
    (cdr             "Var_cdr"              ${Func.var(Var_cdr)})
    (cons            "Var_cons"             ${Func.var(Var_cons)})
    (atom?           "lisp_atom"            ${Func.var(_atom)})
    (pair?           "lisp_pair"            ${Func.var(_pair)})
    (list?           "lisp_list"            ${Func.var(_list)})
    (eq?             "lisp_eq"              ${Func.var(_eq)})
    (type            "lisp_type"            ${Func.var(Var_tag)})
    (number?         "lisp_number"          ${Func.var(_number)})
    (string?         "lisp_string"          ${Func.var(_string)})
    (symbol?         "lisp_symbol"          ${Func.var(_symbol)})
    (procedure?      "lisp_procedure"       ${Func.var(_procedure)})
    (reverse         "List_reverse"         ${Func.var(List_reverse)})
    (length          "List_len"             ${Func.var(List_len)})
    (_match          "List_match"           ${Func.var(List_match)})
    (match-replace   "lisp_match_replace"   ${Func.var(_match_replace)})
    (search          "List_search"          ${Func.var(List_search)})
    (_search-replace "List_search_replace"  ${Func.var(List_search_replace)})
    (_add            "lisp_add"             ${Func.var(_add)})
    (_binary         "Var_binary"           ${Func.var(Var_binary)})
    (_compare        "lisp_compare"         ${Func.var(_compare)})
    (+               "lisp_plus"            ${$rest(_plus)})
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
    (string-length   "String_len"           ${Func.var(String_len)})
    (_string-append  "lisp_string_append"   ${Func.var(_string_append)})
    (substring       "lisp_substring"       ${Func.var(_substring)})
    (string-downcase "lisp_string_downcase" ${Func.var(_string_downcase)})
    (()              "lisp_read_file"       ${Func.var(_read_file)})
    (()              "lisp_write_file"      ${Func.var(_write_file)})
    (()              "List_sort"            ${Func.var(List_sort)})
  );
  foreach (List row, natives) {
    (Var name, String symbol, Func fn) = row;
    self.natives[symbol] = fn;
    if (!name.is_nil()) self.globals[name] = fn;
  }
}

/* Building the rest of the language in itself

   Startup evaluates the following definitions in order. defmacro is used
   to define defun and if. Recursive functions then implement
   map, filter, folds, and other collection operations.

   Runtime Lisp macros express new constructs as transformations into
   existing forms. They extend the language without adding evaluator
   branches. The definitions below reduce to lambda, cond, quote, and
   application, along with the primitive operations in the native registry.

   The percent literal constructs a List containing these definitions. It
   does not evaluate them; _interpreter evaluates each definition at startup.
*/

static List _stdlib = %(
  (def nil ())
  (def true 'true)
  (def false nil)
  /* defmacro defines a runtime Lisp macro closure. defun defines an ordinary
     Lisp closure. Both are runtime Lisp macros themselves: their backquoted
     templates construct the definitions that eval will subsequently evaluate.
  */
  (def defmacro
    (macro (name params body) `(def ,name (macro ,params ,body))))
  (defmacro defun (name params body) `(def ,name (lambda ,params ,body)))
  (defmacro if (test ontrue onfalse) `(cond (,test ,ontrue) (true ,onfalse)))
  (defun list (. values) values)
  (defun not (value) (if value false true))
  (defun null? (value) (eq? value nil))
  (def equal? eq?)
  /* Short-circuit operators use runtime Lisp macros. An ordinary call
     evaluates every operand before its body. and expands into nested choices.
     or saves a tested value so an expression with effects runs only once.
     These runtime Lisp macros use ordinary names; introduced names have no
     automatic hygiene in this evaluator.
  */
  (defmacro and (. forms)
    (if (null? forms) true
        (if (null? (cdr forms)) (car forms)
            `(if ,(car forms) (and ,@(cdr forms)) false))))
  (defmacro or (. forms)
    (if (null? forms) false
        (if (null? (cdr forms)) (car forms)
            `((lambda (_or_value)
                (if _or_value _or_value (or ,@(cdr forms))))
              ,(car forms)))))
  /* begin is an ordinary function here. Argument evaluation has already
     performed the sequence of effects; begin returns the final argument value.
  */
  (defun _last (values)
    (if (null? values) nil
        (if (null? (cdr values)) (car values) (_last (cdr values)))))
  (defun begin (. values) (_last values))
  /* Structural recursion follows the shape of a List. The empty case stops;
     the nonempty case handles car and recurses over cdr. map preserves one
     result per element, filter selects elements, and foldl accumulates a
     result. Passing the operation as a value makes each traversal reusable.
  */
  (defun map (procedure values)
    (if (null? values) nil
        (cons (procedure (car values)) (map procedure (cdr values)))))
  (defun filter (predicate values)
    (if (null? values) nil
        (if (predicate (car values))
            (cons (car values) (filter predicate (cdr values)))
            (filter predicate (cdr values)))))
  (defun foldl (procedure initial values)
    (if (null? values) initial
        (foldl procedure (procedure initial (car values)) (cdr values))))
  /* member returns the suffix beginning at the match; assoc returns a
     matching row. Both return () for absence. A result therefore supplies
     the matching data and can also be used as a condition.
  */
  (defun member (value values)
    (if (null? values) nil
        (if (equal? value (car values)) values (member value (cdr values)))))
  (defun assoc (key pairs)
    (if (null? pairs) nil
        (if (and (pair? (car pairs)) (equal? key (car (car pairs))))
            (car pairs)
            (assoc key (cdr pairs)))))
  /* Appending rebuilds the left spine with cons and shares the right List.
     Immutable Lists make that sharing safe: neither caller can change a
     shared tail. Appending several Lists repeats this two-List operation.
  */
  (defun _append2 (left right)
    (if (null? left) right (cons (car left) (_append2 (cdr left) right))))
  (defun _append_lists (lists)
    (if (null? lists) nil
        (if (null? (cdr lists)) (car lists)
            (_append2 (car lists) (_append_lists (cdr lists))))))
  (defun append (. lists) (_append_lists lists))
  (defun sub (a b) (_binary a '- b))
  (defun mul (a b) (_binary a '* b))
  (defun div (a b) (_binary a '/ b))
  (defun mod (a b) (_binary a '% b))
  (def % mod)
  (defun string-append (. strings) (foldl _string-append "" strings))
  /* The runtime Lisp macro let translates local bindings into a function call:
     (let ((x 3) (y 4)) (+ x y))  ->  ((lambda (x y) (+ x y)) 3 4)
     Initial values are evaluated in the caller. let* nests these bindings,
     so each later initializer is evaluated with the earlier bindings in scope.
  */
  (defmacro let (bindings body)
    `((lambda ,(map car bindings) ,body) ,@(map cadr bindings)))
  (defmacro let* (bindings body)
    (if (null? bindings) body
        `(let (,(car bindings)) (let* ,(cdr bindings) ,body))))
  (defun caar (value) (car (car value)))
  (defun cadr (value) (car (cdr value)))
  (defun cdar (value) (cdr (car value)))
  (defun cddr (value) (cdr (cdr value)))
  /* Patterns describe data to recognize and names to bind within it. These
     functions use ordinary collection matching; they do not evaluate the
     matched data. The runtime Lisp macro match-case creates local bindings.
  */
  (defun match (subject pattern)
    (if (list? subject) (_match subject pattern) nil))
  (defun bound (bindings binder) (cadr (assoc binder bindings)))
  (defun search-replace (subject pattern template)
    (if (match subject pattern) (match-replace subject pattern template)
        (_search-replace subject pattern template)))
  (defun binder? (value)
    (and (symbol? value)
         (member (substring (str value) 0 1) '("?" "*"))
         (> (string-length (str value)) 1)))
  (defun _binders (pattern)
    (cond ((list? pattern)
           (foldl (lambda (found part) (append found (_binders part)))
                  nil pattern))
          ((binder? pattern) (list pattern))
          (true nil)))
  (defun _binder-lets (source binders)
    (map (lambda (binder)
           (list binder (list 'bound source (list 'quote binder))))
         binders))
  /* The runtime Lisp macro match-case processes clauses from last to first.
     Each step wraps the remaining choices in a new conditional. Matching
     yields bindings; generated let forms make them available to the body.
     The result is executable Lisp assembled entirely from ordinary Lists.
  */
  (defmacro match-case (subject . clauses)
    (foldl
      (lambda (rest clause)
        (if (equal? (car clause) 'else) (cadr clause)
          `(let ((_match-case-subject ,subject))
             (let ((_match-case-bindings
                     (match _match-case-subject ',(car clause))))
               (cond (_match-case-bindings
                       (let ,(_binder-lets '_match-case-bindings
                                           (_binders (car clause)))
                         ,(cadr clause)))
                     (true ,rest))))))
      nil (reverse clauses)))
  (def add _add)
  (def last _last)
  (def len length)
  (def reduce foldl)
  (def lower string-downcase)
);

/* Completing a session

   A batch is read and evaluated one form at a time. Earlier definitions are
   available to later forms, and the last value is the batch's result. A later
   read or evaluation error does not roll back effects already performed.
   File import is another source of such batches, with the same environment.
*/
static Var _eval_text(Interp *self, String source) {
  Scope tokens = $auto(Scope.new());
  Reader reader = Reader.scan(source, 0, &tokens);
  Var form, result = %();
  while ((form = reader.next()) is not void)
    result = self.eval(NULL, form);
  return result;
}

static Var _import_file(Interp *self, String path) {
  File source = $auto(path.open("r"));
  Block content = $auto(Block.new(sizeof(char)));
  if (source.read_into(content) == FILE_READ_EOF) return %();
  if (content.length > INT_MAX) {
    size_t size = content.length, int limit = INT_MAX;
    $fail(<size-limit>, %"Lisp.eval_file", <size>, size, <limit>, limit);
  }
  if (memchr(content.bytes, '\0', content.length))
    $fail(<bad-arg>, %"Lisp.eval_file", <why>, %"embedded NUL");
  return _eval_text(self, String.new_len(content.bytes, (int) content.length));
}

static Var _reserved(void) => Var.null();

/* Special forms receive distinct callable identities before library loading.
   Saving one under another name preserves its behavior; shadowing its original
   name does not change the saved callable. The two lookup Maps retain this
   distinction between a name and the callable value bound to it.
*/
static Interp _interpreter(void) {
  Interp self = { %{}, %{}, %{}, %{} };
  _install_natives(&self);
  foreach (Var name, %(quote quasiquote cond def lambda macro eval
                       apply bind import)) {
    Func fn = Func.new(_reserved, %((func ((void))) "Var"));
    self.reserved[name] = fn;
    self.specials[fn] = name;
  }
  foreach (Var form, _stdlib) self.eval(NULL, form);
  return self;
}

/* Incremental reading and evaluation

   The REPL evaluates complete forms, retains incomplete input for the next
   line, and reports malformed input as an error. The saved start position
   prevents rereading earlier complete forms and repeating their effects.
   Evaluation errors are caught per form, so the next form can still run.

   Each function call uses the native stack. There is no tail-call guarantee,
   so sufficiently deep Lisp recursion can exhaust that stack. The production
   word machine uses a different execution strategy.
*/
static int _repl(Interp *self) {
  Buffer source = $auto(Buffer.new(0));
  unsigned cursor = 0;
  int failed = 0, incomplete = 0, interactive = isatty(Stdin.fileno());
  while (1) {
    if (interactive) {
      Stdout.puts(incomplete ? ".. " : "> ");
      Stdout.flush();
    }
    String line = Stdin.readline();
    if (!line) {
      if (incomplete) {
        Stderr.puts("error: incomplete form at end of input\n");
        failed = 1;
      }
      return !failed;
    }
    source.write(line);
    Scope tokens = $auto(Scope.new());
    Reader reader = {0};
    incomplete = 0;
    try {
      reader = Reader.scan(source, cursor, &tokens);
      Var form;
      while ((form = reader.next()) is not void) {
        try Stdout.printf("%s\n", self.eval(NULL, form).repr());
        catch %(?code *detail): {
          Stderr.printf("error: %s\n", cons(code, detail).repr());
          failed = 1;
        }
      }
    }
    catch %(incomplete *): {
      incomplete = 1;
      cursor = reader.start;
    }
    catch %(?code *detail): {
      Stderr.printf("error: %s\n", cons(code, detail).repr());
      failed = 1;
    }
    if (!incomplete) {
      source.clear();
      cursor = 0;
    }
  }
}

/* main converts argv to x2c Strings and matches the supported argument forms.
   With no arguments it starts the REPL; -e evaluates a supplied expression,
   --selftest runs a small check, and a single path loads a Lisp source file.
   Each mode starts with the native registry and _stdlib definitions loaded.
*/
int main(int argc, char **argv) {
  $scope() {
    try {
      Array args = range(0, argc - 1, 1)
        .map(%!(int i) using &argv => String.new(argv[i])).array();
      Interp self = _interpreter();
      String source;
      match (args.list()) {
        case %(?): return _repl(&self) ? 0 : 1;
        case %(? "-e" ?text): source = text;
        case %(? "--selftest"):
          source = "(list (apply + '(10 20 12)) (append '(1 2) '(3 4)))";
        case %(? ?file): {
          const char *path = file.str();
          source = File.open(path ? path : "", "r").string_close();
        }
        default: {
          Stderr.printf("usage: %s [--selftest | -e FORM | FILE]\n",
                        args[0].str());
          return 1;
        }
      }
      Stdout.printf("%s\n", _eval_text(&self, source).repr());
      return 0;
    }
    catch %(?code *detail):
      Stderr.printf("error: %s\n", cons(code, detail).repr());
  }
  return 1;
}
