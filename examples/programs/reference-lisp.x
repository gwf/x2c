/*  reference-lisp.x -- a recursive interpreter for x2c Lisp

    Ordinary x2c values hold syntax and data. Closures belong to the session
    Scope; call environments live on the C stack. Captures copy values, while
    uncaptured names remain visible through the caller's environment.
*/

#include <unistd.h>

typedef struct Closure {
  List params;
  Var body;
  Map captures;
  int macro;
} *Closure;

typedef struct Environment {
  Map bindings;
  struct Environment *parent;
} Environment;

typedef struct Interpreter {
  Map globals, reserved, specials, natives;
} Interpreter;

static Var _procedure(Var value) {
  return value is <func> || value is <lambda> ? <true>.var() : %().var();
}

static Symbol _type(Var value) {
  return value.tag();
}

static Var _lookup(Interpreter *self, Environment *env, Var name) {
  Var value;
  for (; env; env = env.parent)
    if (env.bindings.try_get(name, &value)) return value;
  if (self.globals.try_get(name, &value) ||
      self.reserved.try_get(name, &value)) return value;
  raise %(unbound (name $name));
}

static List _arguments(Interpreter *self, Environment *env, List forms) {
  Array values = $auto(%[]);
  foreach (Var form, forms) values.push(_eval(self, env, form));
  return values;
}

static Var _closure(Interpreter *self, Environment *env, List args,
                    int macro) {
  if (args.len() != 2 || args.car() is not <list>) {
    Symbol operation = macro ? <macro> : <lambda>;
    raise %(bad-sig (operation $operation) (value $args));
  }
  Closure closure = Scope.malloc(sizeof(struct Closure));
  (List params, Var body) = args;
  *closure = (struct Closure) { params, body, %{}, macro };
  // Compatibility includes names inside quoted and nested list bodies.
  if (body is <list>) foreach (Var name, List.flatten(body)) {
    if (!name.is_atom() || self.reserved.contains(name) ||
        closure.captures.contains(name) || params.contains(name)) continue;
    for (Environment *local = env; local; local = local.parent) {
      Var value;
      if (local.bindings.try_get(name, &value)) {
        closure.captures[name] = value;
        break;
      }
    }
  }
  return Var.new(<lambda>, closure);
}

static Var _call(Interpreter *self, Environment *env, Closure closure,
                 List values) {
  Map bindings = $auto(%{});
  for (List params = closure.params; params; params = params.cdr()) {
    Var (name, rest) = params;
    if (name.is_atom() && name.str() == %".") {
      if (!params.cdr())
        raise %(bad-sig (operation "apply") (value ${closure.body}));
      bindings[rest] = values;
      values = NULL;
      break;
    }
    if (!values)
      raise %(bad-arity (operation "apply") (value ${closure.body}));
    bindings[name] = values.car();
    values = values.cdr();
  }
  if (values)
    raise %(bad-arity (operation "apply") (value ${closure.body}));
  Environment captured = { closure.captures, env };
  Environment local = { bindings, &captured };
  return _eval(self, &local, closure.body);
}

static void _arity(List args, int expected, String operation) {
  int actual = args.len();
  if (actual != expected)
    raise %(bad-arity (operation $operation) (expected $expected)
                       (actual $actual));
}

static Var _quasiquote(Interpreter *self, Environment *env, Var expression,
                      int splice, int depth) {
  if (expression is not <list> || expression.is_nil())
    return splice ? %($expression).var() : expression;
  List form = expression;
  Var (head, argument) = form;
  Var quote = Atom.intern("quasiquote"), unquote = Atom.intern("unquote");
  Var splicing = Atom.intern("unquote-splicing");
  if (head == quote || head == unquote || head == splicing) {
    if (head != quote && form.len() != 2)
      raise %(bad-arity (operation "quasiquote") (value $expression));
    if (head == quote || depth > 0) {
      Var tail = _quasiquote(self, env, form.cdr(), 0,
                            depth + (head == quote ? 1 : -1));
      Var value = head.cons(tail);
      return splice ? %($value).var() : value;
    }
    Var value = _eval(self, env, argument);
    if (!splice && head == splicing)
      raise %(bad-types (operation "quasiquote-splice")
                         (actual ${expression.kind()}));
    if (splice && head == unquote) return %($value);
    if (splice && value is not <list>)
      raise %(bad-types (operation "quasiquote-splice")
                         (actual ${value.kind()}));
    return value;
  }
  List first = _quasiquote(self, env, head, 1, depth);
  List rest = _quasiquote(self, env, form.cdr(), 0, depth);
  Var value = first.append(rest);
  return splice ? %($value).var() : value;
}

static Var _special(Interpreter *self, Environment *env, Symbol operation,
                    List args) {
  Var (first, second) = args;
  switch (operation) {
    case <lambda>: case <macro>:
      return _closure(self, env, args, operation == <macro>);
    case <quote>:
      _arity(args, 1, %"quote");
      return first;
    case <quasiquote>:
      _arity(args, 1, %"quasiquote");
      return _quasiquote(self, env, first, 0, 0);
    case <def>: {
      if (args.len() != 2 || !first.is_atom()) {
        int actual = args.len();
        raise %(bad-arity (operation "def") (expected 2) (actual $actual)
                           (value $args));
      }
      return self.globals[first] = _eval(self, env, second);
    }
    case <cond>:
      if (!args)
        raise %(bad-arity (operation "cond") (expected 1) (actual 0));
      foreach (Var clause, args) {
        if (clause is not <list>)
          raise %(bad-types (operation "cond") (value $clause) (want "List"));
        List pair = clause;
        if (pair.len() != 2) {
          int actual = pair.len();
          raise %(bad-arity (operation "cond-clause") (expected 2)
                             (actual $actual) (value $clause));
        }
        Var (test, result) = pair;
        if (!_eval(self, env, test).is_nil()) return _eval(self, env, result);
      }
      return %();
    case <eval>:
      _arity(args, 1, %"eval");
      return _eval(self, NULL, _eval(self, env, first));
    case <apply>: {
      _arity(args, 2, %"apply");
      Var callable = _eval(self, env, first);
      Var values = _eval(self, env, second);
      if (values is not <list>)
        raise %(bad-types (operation "apply") (actual ${values.kind()})
                           (want "List"));
      return _apply(self, env, callable, values, 1);
    }
    case <bind>: {
      _arity(args, 2, %"bind");
      Var name = _eval(self, env, first);
      Var signature = _eval(self, env, second);
      if (name is not <string>)
        raise %(bad-types (operation "bind") (actual ${name.kind()})
                           (want "String"));
      if (signature is not <list>)
        raise %(bad-sig (operation "bind") (value $signature));
      Var function;
      if (!self.natives.try_get(name, &function))
        raise %(no-symbol (name $name) (sig $signature));
      return function;
    }
    case <import>: {
      _arity(args, 1, %"import");
      Var path = _eval(self, env, first);
      if (path is not <string>)
        raise %(bad-types (operation "import") (actual ${path.kind()})
                           (want "String"));
      Var hook;
      if (self.globals.try_get(Atom.intern("_x2c.import-hook"), &hook))
        return _apply(self, NULL, hook, %($path), 1);
      return _import_file(self, path);
    }
  }
  return void;
}

// `values` distinguishes ordinary calls from Lisp's explicit apply form.
static Var _apply(Interpreter *self, Environment *env, Var callable,
                  List args, int values) {
  if (callable is <lambda>) {
    Closure closure = callable.pointer();
    if (values && closure.macro)
      raise %(not-call (operation "apply") (actual ${callable.kind()}));
    List actual = values || closure.macro ? args : _arguments(self, env, args);
    Var result = _call(self, env, closure, actual);
    return closure.macro ? _eval(self, env, result) : result;
  }
  if (callable is not <func>) raise %(not-call (actual ${callable.kind()}));
  Var special;
  if (self.specials.try_get(callable, &special)) {
    if (!values) return _special(self, env, special, args);
    if (special != <apply>.var())
      raise %(not-call (operation "apply") (actual ${callable.kind()}));
    _arity(args, 2, %"apply");
    Var rest = args.cadr();
    if (rest is not <list>)
      raise %(bad-types (operation "apply") (actual ${rest.kind()})
                         (want "List"));
    return _apply(self, env, args.car(), rest, 1);
  }
  List actual = values ? args : _arguments(self, env, args);
  Func function = callable;
  FuncArg *argv = Scope.malloc(actual.len() * sizeof(FuncArg));
  defer Scope.free(argv);
  int count = 0;
  foreach (Var value, actual) argv[count++] = FuncArg.value(value);
  return function.apply(count, argv);
}

static Var _eval(Interpreter *self, Environment *env, Var expression) {
  if (expression is void) raise %(void-op (operation "eval"));
  if (expression.is_atom()) return _lookup(self, env, expression);
  if (expression is not <list> || expression.is_nil()) return expression;
  List form = expression;
  Var callable = _eval(self, env, form.car());
  return _apply(self, env, callable, form.cdr(), 0);
}

// The reader shares token spelling with x2c, but constructs its own forms.

static Symbol _read_error(Symbol cause, String source, unsigned at) {
  int line = 1, column = 1;
  scan_next_line_col(source, (int) at, &line, &column);
  if (cause == <incomplete>)
    raise %(incomplete (source $source) (line $line) (column $column));
  raise %(malformed (source $source) (line $line) (column $column));
}

static Symbol _read_atom(Token token, String source, unsigned base,
                         Var *out) {
  String text = token.text;
  switch (token.type) {
    case <lit-char*>:
      *out = String.new_len(text + 1, token.len - 2).unescape();
      return <value>;
    case <lit-int>: {
      long value;
      if (!String.new_len(text, token.len).try_long(&value))
        return _read_error(<malformed>, source, base + token.pos);
      if (value == (int) value) *out = (int) value;
      else *out = value;
      return <value>;
    }
    case <lit-float>: {
      double value;
      if (!String.new_len(text, token.len).try_double(&value))
        return _read_error(<malformed>, source, base + token.pos);
      *out = value;
      return <value>;
    }
    case <lit-symbol>: {
      String inner = text[1] == '"'
        ? String.new_len(text + 2, token.len - 4).unescape()
        : String.new_len(text + 1, token.len - 2);
      if (!inner)
        return _read_error(<malformed>, source, base + token.pos);
      *out = Symbol.new(inner);
      return <value>;
    }
    case <ident>:
      *out = Atom.intern(text.unescape());
      return <value>;
  }
  return _read_error(<malformed>, source, base + token.pos);
}

static Symbol _read_form(Tokenizer tokens, Token token, String source,
                         unsigned base, unsigned *end, Var *out) {
  if (!token || token.type == <eof>) return <incomplete>;
  String prefix = NULL;
  switch (token.type) {
    case <error>:
      if (tokens.status() == <incomplete>) return <incomplete>;
      return _read_error(<malformed>, source, base + token.pos);
    case <")">:
      return _read_error(<malformed>, source, base + token.pos);
    case <"(">: {
      Array elements = %[];
      defer elements.free();
      while (1) {
        Token next = tokens.next();
        if (!next || next.type == <eof>) return <incomplete>;
        if (next.type == <")">) {
          *end = next.pos + next.len;
          *out = elements.list();
          return <value>;
        }
        Var element = void;
        Symbol status = _read_form(tokens, next, source, base, end, &element);
        if (status != <value>) return status;
        elements.push(element);
      }
    }
    case <"'">:  prefix = "quote";      break;
    case <"`">:  prefix = "quasiquote"; break;
    case <",">:  prefix = "unquote";    break;
    case <",@">: prefix = "unquote-splicing"; break;
  }
  if (prefix) {
    Var inner = void;
    Symbol status = _read_form(
      tokens, tokens.next(), source, base, end, &inner);
    if (status == <value>) {
      Var name = Atom.intern(prefix);
      *out = %($name $inner);
    }
    return status;
  }
  *end = token.pos + token.len;
  return _read_atom(token, source, base, out);
}

static Symbol _read(String source, unsigned *cursor, Var *out) {
  if (!source || !cursor) return <eof>;
  unsigned base = *cursor;
  Scope token_scope = $auto(Scope.new_named("Reference tokens"));
  Tokenizer tokens;
  $scope(&token_scope) {
    tokens = Tokenizer.new_mode(source + base, <lisp>);
    tokens.scan();
  }
  Token first = tokens.next();
  if (!first || first.type == <eof>) {
    *cursor = source.len();
    return <eof>;
  }
  *cursor = base + first.pos;
  unsigned end = 0;
  Var value = void;
  Symbol status = _read_form(tokens, first, source, base, &end, &value);
  if (status == <incomplete>)
    return _read_error(status, source, *cursor);
  if (status == <value>) {
    if (out) *out = value;
    *cursor = base + end;
  }
  return status;
}

// Native operations for the independent recursive interpreter.

static Var _bool(int x) {
  if (x) return <true>;
  return %();
}

static Var _atom(Var value) => _bool(value is not <list> || value.is_nil());

static Var _eq(Var a, Var b) => _bool(a == b);

static Var _pair(Var value) => _bool(value is <list> && !value.is_nil());

static Var _list(Var value) => _bool(value is <list>);

static int _is_number(Var value) {
  Symbol kind = value.kind();
  return kind == <integer> || kind == <floating>;
}

static Var _number(Var value) => _bool(_is_number(value));

static Var _string(Var value) => _bool(value is <string>);

static Var _symbol(Var value) => _bool(value.kind() == <symbol>);

static Var _compare(Var a, Var b) {
  if (!_is_number(a) || !_is_number(b))
    raise %(bad-types (operation "lisp_compare")
                       (left-kind ${a.kind()})
                       (right-kind ${b.kind()}));
  return a.compare(b);
}

static Var _add(Var a, Var b) {
  if (a is <string> || b is <string>) return %"$a$b";
  return a.binary(<+>, b);
}

static Var _plus(List values) {
  Var total = 0;
  if (values && values.car() is <string>) total = String.new("");
  foreach (Var value, values) total = _add(total, value);
  return total;
}

static Var _minus(List values) {
  if (!values) raise %(bad-arity (operation "-") (expected 1) (actual 0));
  Var total = values.car();
  if (!values.cdr()) {
    Var zero = 0;
    return zero.binary(<->, total);
  }
  foreach (Var value, values.cdr()) total = total.binary(<->, value);
  return total;
}

static Var _times(List values) {
  Var total = 1;
  foreach (Var value, values) total = total.binary(<*>, value);
  return total;
}

static Var _divide(List values) {
  if (!values) raise %(bad-arity (operation "/") (expected 1) (actual 0));
  Var total = values.car();
  if (!values.cdr()) {
    Var one = 1;
    return one.binary(</>, total);
  }
  foreach (Var value, values.cdr()) total = total.binary(</>, value);
  return total;
}

static Var _chain(List values, String operation, int want, int expect) {
  int actual = values.len();
  if (actual < 2)
    raise %(bad-arity (operation $operation) (expected 2) (actual $actual));
  for (List p = values; p.cdr(); p = p.cdr()) {
    Var (left, right) = p;
    int order = _compare(left, right).integer();
    if (expect ? order != want : order == want) return _bool(0);
  }
  return _bool(1);
}

static Var _eq_chain(List values) => _chain(values, %"=", 0, 1);

static Var _lt_chain(List values) => _chain(values, %"<", -1, 1);

static Var _le_chain(List values) => _chain(values, %"<=", 1, 0);

static Var _gt_chain(List values) => _chain(values, %">", 1, 1);

static Var _ge_chain(List values) => _chain(values, %">=", -1, 0);

static Var _str(Var value) => value.str();

static Var _repr(Var value) => value.repr();

static Var _string_append(String left, String right) => left + right;

static Var _substring(String string, int start, int stop) =>
  string.getslice(start, stop, 1);

static Var _string_downcase(String string) => string.lower();

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

static Map _natives(void) {
  return %{
    "Var_car": ${Func.new(Var_car, %((func (("Var"))) "Var"))},
    "Var_cdr": ${Func.new(Var_cdr, %((func (("Var"))) "List"))},
    "Var_cons": ${Func.new(Var_cons, %((func (("Var") ("List"))) "List"))},
    "lisp_atom": ${Func.new(_atom, %((func (("Var"))) "Var"))},
    "lisp_pair": ${Func.new(_pair, %((func (("Var"))) "Var"))},
    "lisp_list": ${Func.new(_list, %((func (("Var"))) "Var"))},
    "lisp_eq": ${Func.new(_eq, %((func (("Var") ("Var"))) "Var"))},
    "lisp_type": ${Func.new(_type, %((func (("Var"))) "Symbol"))},
    "lisp_number": ${Func.new(_number, %((func (("Var"))) "Var"))},
    "lisp_string": ${Func.new(_string, %((func (("Var"))) "Var"))},
    "lisp_symbol": ${Func.new(_symbol, %((func (("Var"))) "Var"))},
    "lisp_procedure": ${Func.new(_procedure, %((func (("Var"))) "Var"))},
    "List_reverse": ${Func.new(List_reverse, %((func (("List"))) "List"))},
    "List_len": ${Func.new(List_len, %((func (("List"))) int))},
    "List_match": ${Func.new(List_match, %((func (("List") ("Var"))) "List"))},
    "lisp_match_replace":
      ${Func.new(_match_replace, %((func (("List") ("Var") ("Var"))) "Var"))},
    "List_search":
      ${Func.new(List_search, %((func (("List") ("Var"))) "List"))},
    "List_search_replace":
      ${Func.new(List_search_replace,
                 %((func (("List") ("Var") ("Var"))) "List"))},
    "lisp_add": ${Func.new(_add, %((func (("Var") ("Var"))) "Var"))},
    "Var_binary":
      ${Func.new(Var_binary, %((func (("Var") ("Symbol") ("Var"))) "Var"))},
    "lisp_compare": ${Func.new(_compare, %((func (("Var") ("Var"))) "Var"))},
    "lisp_plus": ${Func.new_rest(_plus, %((func (("List"))) "Var"))},
    "lisp_minus": ${Func.new_rest(_minus, %((func (("List"))) "Var"))},
    "lisp_times": ${Func.new_rest(_times, %((func (("List"))) "Var"))},
    "lisp_divide": ${Func.new_rest(_divide, %((func (("List"))) "Var"))},
    "lisp_eq_chain": ${Func.new_rest(_eq_chain, %((func (("List"))) "Var"))},
    "lisp_lt_chain": ${Func.new_rest(_lt_chain, %((func (("List"))) "Var"))},
    "lisp_le_chain": ${Func.new_rest(_le_chain, %((func (("List"))) "Var"))},
    "lisp_gt_chain": ${Func.new_rest(_gt_chain, %((func (("List"))) "Var"))},
    "lisp_ge_chain": ${Func.new_rest(_ge_chain, %((func (("List"))) "Var"))},
    "lisp_str": ${Func.new(_str, %((func (("Var"))) "Var"))},
    "lisp_repr": ${Func.new(_repr, %((func (("Var"))) "Var"))},
    "String_len": ${Func.new(String_len, %((func (("String"))) int))},
    "lisp_string_append":
      ${Func.new(_string_append, %((func (("String") ("String"))) "Var"))},
    "lisp_substring":
      ${Func.new(_substring, %((func (("String") (int) (int))) "Var"))},
    "lisp_string_downcase":
      ${Func.new(_string_downcase, %((func (("String"))) "Var"))},
    "lisp_read_file": ${Func.new(_read_file, %((func (("String"))) "Var"))},
    "lisp_write_file":
      ${Func.new(_write_file, %((func (("String") ("String"))) "Var"))},
    "List_sort": ${Func.new(List_sort, %((func (("List"))) "List"))},
  };
}

// The standard vocabulary is Lisp data, evaluated by this interpreter.

static List _standard(void) => %(
  (def nil ())
  (def true 'true)
  (def false nil)
  (def car
    (bind "Var_car" '((func (("Var"))) "Var")))
  (def cdr
    (bind "Var_cdr" '((func (("Var"))) "List")))
  (def cons
    (bind "Var_cons" '((func (("Var") ("List"))) "List")))
  (def atom?
    (bind "lisp_atom" '((func (("Var"))) "Var")))
  (def pair?
    (bind "lisp_pair" '((func (("Var"))) "Var")))
  (def list?
    (bind "lisp_list" '((func (("Var"))) "Var")))
  (def eq?
    (bind "lisp_eq" '((func (("Var") ("Var"))) "Var")))
  (def type
    (bind "lisp_type" '((func (("Var"))) "Symbol")))
  (def number?
    (bind "lisp_number" '((func (("Var"))) "Var")))
  (def string?
    (bind "lisp_string" '((func (("Var"))) "Var")))
  (def symbol?
    (bind "lisp_symbol" '((func (("Var"))) "Var")))
  (def procedure?
    (bind "lisp_procedure" '((func (("Var"))) "Var")))
  (def reverse
    (bind "List_reverse" '((func (("List"))) "List")))
  (def length
    (bind "List_len" '((func (("List"))) int)))
  (def _match
    (bind "List_match" '((func (("List") ("Var"))) "List")))
  (def match-replace
    (bind "lisp_match_replace"
      '((func (("List") ("Var") ("Var"))) "Var")))
  (def search
    (bind "List_search" '((func (("List") ("Var"))) "List")))
  (def _search-replace
    (bind "List_search_replace"
      '((func (("List") ("Var") ("Var"))) "List")))
  (def _add
    (bind "lisp_add" '((func (("Var") ("Var"))) "Var")))
  (def _binary
    (bind "Var_binary"
      '((func (("Var") ("Symbol") ("Var"))) "Var")))
  (def _compare
    (bind "lisp_compare" '((func (("Var") ("Var"))) "Var")))
  (def str
    (bind "lisp_str" '((func (("Var"))) "Var")))
  (def repr
    (bind "lisp_repr" '((func (("Var"))) "Var")))
  (def string-length
    (bind "String_len" '((func (("String"))) int)))
  (def _string-append
    (bind "lisp_string_append"
      '((func (("String") ("String"))) "Var")))
  (def substring
    (bind "lisp_substring"
      '((func (("String") (int) (int))) "Var")))
  (def string-downcase
    (bind "lisp_string_downcase"
      '((func (("String"))) "Var")))
  (def defmacro
    (macro (name params body)
      `(def ,name (macro ,params ,body))))
  (defmacro defun (name params body)
    `(def ,name (lambda ,params ,body)))
  (defmacro if (test ontrue onfalse)
    `(cond (,test ,ontrue) (true ,onfalse)))
  (defun list (. values) values)
  (defun not (value) (if value false true))
  (defun null? (value) (eq? value nil))
  (def equal? eq?)
  (defmacro and (. forms)
    (if (null? forms)
        true
        (if (null? (cdr forms))
            (car forms)
            `(if ,(car forms) (and ,@(cdr forms)) false))))
  (defmacro or (. forms)
    (if (null? forms)
        false
        (if (null? (cdr forms))
            (car forms)
            `((lambda (_or_value)
                (if _or_value _or_value (or ,@(cdr forms))))
              ,(car forms)))))
  (defun _last (values)
    (if (null? values)
        nil
        (if (null? (cdr values))
            (car values)
            (_last (cdr values)))))
  (defun begin (. values) (_last values))
  (defun map (procedure values)
    (if (null? values)
        nil
        (cons (procedure (car values))
              (map procedure (cdr values)))))
  (defun filter (predicate values)
    (if (null? values)
        nil
        (if (predicate (car values))
            (cons (car values) (filter predicate (cdr values)))
            (filter predicate (cdr values)))))
  (defun foldl (procedure initial values)
    (if (null? values)
        initial
        (foldl procedure
               (procedure initial (car values))
               (cdr values))))
  (defun member (value values)
    (if (null? values)
        nil
        (if (equal? value (car values))
            values
            (member value (cdr values)))))
  (defun assoc (key pairs)
    (if (null? pairs)
        nil
        (if (and (pair? (car pairs))
                 (equal? key (car (car pairs))))
            (car pairs)
            (assoc key (cdr pairs)))))
  (defun _append2 (left right)
    (if (null? left)
        right
        (cons (car left) (_append2 (cdr left) right))))
  (defun _append_lists (lists)
    (if (null? lists)
        nil
        (if (null? (cdr lists))
            (car lists)
            (_append2 (car lists) (_append_lists (cdr lists))))))
  (defun append (. lists) (_append_lists lists))
  (defun sub (a b) (_binary a '- b))
  (defun mul (a b) (_binary a '* b))
  (defun div (a b) (_binary a '/ b))
  (defun mod (a b) (_binary a '% b))
  (def + (bind "lisp_plus" '((func (("List"))) "Var")))
  (def - (bind "lisp_minus" '((func (("List"))) "Var")))
  (def * (bind "lisp_times" '((func (("List"))) "Var")))
  (def / (bind "lisp_divide" '((func (("List"))) "Var")))
  (def % mod)
  (def = (bind "lisp_eq_chain" '((func (("List"))) "Var")))
  (def < (bind "lisp_lt_chain" '((func (("List"))) "Var")))
  (def <= (bind "lisp_le_chain" '((func (("List"))) "Var")))
  (def > (bind "lisp_gt_chain" '((func (("List"))) "Var")))
  (def >= (bind "lisp_ge_chain" '((func (("List"))) "Var")))
  (defun string-append (. strings) (foldl _string-append "" strings))
  (defmacro let (bindings body)
    `((lambda ,(map car bindings) ,body) ,@(map cadr bindings)))
  (defmacro let* (bindings body)
    (if (null? bindings)
        body
        `(let (,(car bindings)) (let* ,(cdr bindings) ,body))))
  (defun caar (value) (car (car value)))
  (defun cadr (value) (car (cdr value)))
  (defun cdar (value) (cdr (car value)))
  (defun cddr (value) (cdr (cdr value)))
  (defun match (subject pattern)
    (if (list? subject) (_match subject pattern) nil))
  (defun bound (bindings binder) (cadr (assoc binder bindings)))
  (defun search-replace (subject pattern template)
    (if (match subject pattern)
        (match-replace subject pattern template)
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
      nil
      (reverse clauses)))
  (def add _add)
  (def last _last)
  (def len length)
  (def reduce foldl)
  (def lower string-downcase)
);

static Var _eval_text(Interpreter *self, String source) {
  unsigned cursor = 0;
  Var form = void, result = %();
  while (_read(source, &cursor, &form) == <value>)
    result = _eval(self, NULL, form);
  return result;
}

static Var _import_file(Interpreter *self, String path) {
  File source = $auto(File.open(path, "r"));
  Block content = $auto(Block.new(sizeof(char)));
  if (source.read_into(content) == FILE_READ_EOF) return %();
  if (content.length > INT_MAX) {
    size_t size = content.length, int limit = INT_MAX;
    raise %(size-limit (operation "Lisp.eval_file") (size $size)
                       (limit $limit));
  }
  if (memchr(content.bytes, '\0', content.length))
    raise %(bad-arg (operation "Lisp.eval_file") (why "embedded NUL"));
  return _eval_text(self, String.new_len(content.bytes, (int) content.length));
}

static Var _reserved(void) => Var.null();

static Interpreter _interpreter(void) {
  Interpreter self = { %{}, %{}, %{}, _natives() };
  foreach (Var name, %(quote quasiquote cond def lambda macro eval
                       apply bind import)) {
    Func function = Func.new(_reserved, %((func ((void))) "Var"));
    self.reserved[name] = function;
    self.specials[function] = name;
  }
  foreach (Var form, _standard()) _eval(&self, NULL, form);
  return self;
}

static int _evaluate(Interpreter *self, String source, int print) {
  try {
    Var result = _eval_text(self, source);
    if (print) Stdout.printf("%s\n", result.repr());
    return 1;
  }
  catch %(?code *detail): {
    Stderr.printf("error: %s\n", cons(code, detail).repr());
    return 0;
  }
}

static int _repl(Interpreter *self) {
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
    while (1) {
      Symbol status = <eof>;
      Var form = void;
      try status = _read(source, &cursor, &form);
      catch %(incomplete *): status = <incomplete>;
      catch %(?code *detail): {
        Stderr.printf("error: %s\n", cons(code, detail).repr());
        status = <malformed>;
      }
      if (status == <value>) {
        try Stdout.printf("%s\n", _eval(self, NULL, form).repr());
        catch %(?code *detail): {
          Stderr.printf("error: %s\n", cons(code, detail).repr());
          failed = 1;
        }
        incomplete = 0;
        continue;
      }
      incomplete = status == <incomplete>;
      if (!incomplete) {
        if (status == <malformed>) failed = 1;
        source.clear();
        cursor = 0;
      }
      break;
    }
  }
}

int main(int argc, char **argv) {
  Scope session = $auto(Scope.new_named("Reference Lisp"));
  $scope(&session) {
    try {
      Interpreter self = _interpreter();
      if (argc == 1) return _repl(&self) ? 0 : 1;
      if (argc == 3 && !strcmp(argv[1], "-e"))
        return _evaluate(&self, String.new(argv[2]), 1) ? 0 : 1;
      if (argc == 2 && !strcmp(argv[1], "--selftest"))
        return _evaluate(&self,
          "(list (apply + '(10 20 12)) (append '(1 2) '(3 4)))", 1) ? 0 : 1;
      if (argc == 2)
        return _evaluate(&self, File.open(argv[1], "r").string_close(), 1)
               ? 0 : 1;
      Stderr.printf("usage: %s [--selftest | -e FORM | FILE]\n", argv[0]);
    }
    catch %(?code *detail):
      Stderr.printf("error: %s\n", cons(code, detail).repr());
  }
  return 1;
}
