/*  reference-lisp.x -- a recursive interpreter for x2c Lisp

    Values are ordinary x2c data. Closures live in the session Scope;
    environments live on the call stack. The evaluator below is the whole
    execution model: read a form, resolve its head, and recurse.
*/

#include <unistd.h>

typedef struct Fn {
  List params;
  Var body;
  Map captures;
  int macro;
} *Fn;

typedef struct Env {
  Map bindings;
  struct Env *parent;
} Env;

typedef struct Interp {
  Map globals, natives;
  // Reserved names map to functions; specials maps those identities back.
  Map reserved, specials;
} Interp;

// Error fields stay at the call site; the macro supplies the operation pair.
macro Statement $fail(Expr $cause, Expr $op, Expr $fields...) => {
  $(quasiquote (raise ,$cause
    (args (literal ("Symbol") "operation" operation) ,$op ,@$fields)))
}

// evaluation

static Var Interp.eval(Interp *self, Env *env, Var form) {
  if (form is void) $fail(<void-op>, %"eval");
  if (form.is_atom()) return self.lookup(env, form);
  if (form is not <list> || form.is_nil()) return form;
  List expr = form;
  Var fn = self.eval(env, expr.car());
  List args = expr.cdr();
  if (fn is <lambda>) {
    Fn closure = fn.pointer();
    if (closure.macro)
      return self.eval(env, self.invoke(env, closure, args));
  }
  else {
    if (fn is not <func>) raise %(not-call (actual ${fn.kind()}));
    if (self.specials.contains(fn))
      return self.special(env, self.specials[fn], args);
  }
  List values = self.eval_args(env, args);
  return self.apply(env, fn, values);
}

static List Interp.eval_args(Interp *self, Env *env, List forms) {
  Array values = $auto(%[]);
  foreach (Var form, forms) values.push(self.eval(env, form));
  return values;
}

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
      return self.apply(env, callable, _list_argument(actual, %"apply"));
    }
    case %(bind ?name ?sig): {
      Var target = self.eval(env, name), type = self.eval(env, sig);
      return self.bind(target, type);
    }
    case %(import ?form): {
      Var path = self.eval(env, form);
      Atom hook = Atom.intern("_x2c.import-hook");
      _string_argument(path, %"import");
      if (self.globals.contains(hook))
        return self.apply(NULL, self.globals[hook], %($path));
      return _import_file(self, path);
    }
  }
  return _bad_form(op, args);
}

// Apply receives values; eval alone decides which expressions to evaluate.
static Var Interp.apply(Interp *self, Env *env, Var fn, List values) {
  if (fn is <lambda>) {
    Fn closure = fn.pointer();
    if (closure.macro)
      $fail(<not-call>, %"apply", <actual>, fn.kind());
    return self.invoke(env, closure, values);
  }
  if (fn is not <func>) raise %(not-call (actual ${fn.kind()}));
  if (self.specials.contains(fn)) {
    if (self.specials[fn] != <apply>.var())
      $fail(<not-call>, %"apply", <actual>, fn.kind());
    match (values) case %(?callable ?args):
      return self.apply(env, callable, _list_argument(args, %"apply"));
    return _bad_form(<apply>, values);
  }
  return _native_call(fn, values);
}

// environments and closures

static Var Interp.lookup(Interp *self, Env *env, Var name) {
  for (; env; env = env.parent)
    if (env.bindings.contains(name)) return env.bindings[name];
  if (self.globals.contains(name)) return self.globals[name];
  if (self.reserved.contains(name)) return self.reserved[name];
  raise %(unbound (name $name));
}

static Var Interp.closure(Interp *self, Env *env,
                          List params, Var body, int macro) {
  Map captures = %{};
  // x2c Lisp captures names even inside quoted and nested List bodies.
  if (body is <list>) foreach (Var name, body.list().flatten()) {
    if (!name.is_atom() || self.reserved.contains(name) ||
        captures.contains(name) || params.contains(name)) continue;
    for (Env *local = env; local; local = local.parent) {
      if (local.bindings.contains(name)) {
        captures[name] = local.bindings[name];
        break;
      }
    }
  }
  Fn closure = Scope.malloc(sizeof(struct Fn));
  *closure = (struct Fn) { params, body, captures, macro };
  return Var.new(<lambda>, closure);
}

static Var Interp.invoke(Interp *self, Env *env, Fn closure, List values) {
  Map bindings = $auto(%{});
  for (List params = closure.params; params; params = params.cdr()) {
    Var (name, rest) = params;
    if (name.is_atom() && name.str() == %".") {
      if (!params.cdr())
        $fail(<bad-sig>, %"apply", <value>, closure.body);
      bindings[rest] = values;
      values = NULL;
      break;
    }
    if (!values)
      $fail(<bad-arity>, %"apply", <value>, closure.body);
    bindings[name] = values.car();
    values = values.cdr();
  }
  if (values)
    $fail(<bad-arity>, %"apply", <value>, closure.body);
  // Captures take priority; uncaptured names remain visible in the caller.
  Env captured = { closure.captures, env };
  Env local = { bindings, &captured };
  return self.eval(&local, closure.body);
}

// Quasiquote returns one form; quoted_item returns its contributed elements.
static Var Interp.quasiquote(Interp *self, Env *env, Var form, int depth) {
  if (form is not <list> || form.is_nil()) return form;
  List expr = form;
  Var (head, argument) = expr;
  Var (quote, unquote, splice) = %(quasiquote unquote unquote-splicing);
  if (head == quote)
    return cons(head, self.quasiquote(env, expr.cdr(), depth + 1));
  if (head == unquote || head == splice) {
    if (expr.len() != 2)
      $fail(<bad-arity>, %"quasiquote", <value>, form);
    if (depth)
      return cons(head, self.quasiquote(env, expr.cdr(), depth - 1));
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

// Diagnostics preserve the language's errors without obscuring valid forms.

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
  _string_argument(name, %"bind");
  if (sig is not <list>)
    $fail(<bad-sig>, %"bind", <value>, sig);
  if (self.natives.contains(name)) return self.natives[name];
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

// Tokens supply spelling; recursive descent supplies Lisp's grammar.
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

// Token storage is temporary; the forms we construct belong to the caller.
static Reader Reader.scan(String source, unsigned base, Scope *storage) {
  Reader reader = { .source = source, .base = base };
  $scope(storage) {
    reader.tokens = Tokenizer.new_mode(source ? source + base : NULL, <lisp>);
    reader.tokens.scan();
  }
  return reader;
}

// Void marks end of input; an unfinished form raises at its starting position.
static Var Reader.next(Reader *self) {
  Token first = self.tokens.next();
  if (!first || first.type == <eof>) return void;
  self.start = self.base + first.pos;
  return self._form(first);
}

// native operations

static Var _native_call(Func native, List values) {
  FuncArg *args = Scope.malloc(values.len() * sizeof(FuncArg));
  defer Scope.free(args);
  int count = 0;
  foreach (Var value, values) args[count++] = FuncArg.value(value);
  return native.apply(count, args);
}

static Var _bool(int x) {
  if (x) return <true>;
  return %();
}

static int _is_number(Var v) {
  Symbol k = v.kind();
  return k == <integer> || k == <floating>;
}

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

static Var _add(Var a, Var b) {
  if (a is <string> || b is <string>) return %"$a$b";
  return a.binary(<+>, b);
}

static Var _plus(List values) {
  Var seed = 0;
  if (values && values.car() is <string>) seed = String.new("");
  return values.foldl(seed, _add);
}

// Unary subtraction negates; unary division reciprocates. Both otherwise
// combine the first argument with each following argument, left to right.
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

static Var _chain(List values, String op, int want, int expect) {
  int n = values.len();
  if (n < 2)
    $fail(<bad-arity>, op, <expected>, 2, <actual>, n);
  Var left = values.car();
  foreach (Var right, values.cdr()) {
    int order = _compare(left, right).integer();
    if (expect ? order != want : order == want) return _bool(0);
    left = right;
  }
  return _bool(1);
}

static Var _eq_chain(List xs) => _chain(xs, %"=",  0, 1);
static Var _lt_chain(List xs) => _chain(xs, %"<", -1, 1);
static Var _le_chain(List xs) => _chain(xs, %"<=", 1, 0);
static Var _gt_chain(List xs) => _chain(xs, %">",  1, 1);
static Var _ge_chain(List xs) => _chain(xs, %">=", -1, 0);

// These return Var because the native signature appears in Lisp errors.
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

// Ordinary function conversion infers fixed native signatures. Rest natives
// consume one List; this macro states that shared calling convention once.
macro Expression $rest(Expr $fn) =>
  (Func.new_rest($fn, %((func (("List"))) "Var")))

static void _install_natives(Interp *self) {
  // Lisp name, bind spelling, implementation. () leaves a native import-only.
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

// The standard vocabulary is Lisp data, evaluated by this interpreter.

static List _stdlib = %(
  (def nil ())
  (def true 'true)
  (def false nil)
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
  (def % mod)
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

int main(int argc, char **argv) {
  $scope() {
    try {
      Interp self = _interpreter();
      if (argc == 1) return _repl(&self) ? 0 : 1;
      String source;
      if (argc == 3 && !strcmp(argv[1], "-e")) source = argv[2];
      else if (argc == 2 && !strcmp(argv[1], "--selftest"))
        source = "(list (apply + '(10 20 12)) (append '(1 2) '(3 4)))";
      else if (argc == 2) source = File.open(argv[1], "r").string_close();
      else {
        Stderr.printf("usage: %s [--selftest | -e FORM | FILE]\n", argv[0]);
        return 1;
      }
      Stdout.printf("%s\n", _eval_text(&self, source).repr());
      return 0;
    }
    catch %(?code *detail):
      Stderr.printf("error: %s\n", cons(code, detail).repr());
  }
  return 1;
}
