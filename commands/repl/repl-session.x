/*  repl-session.x -- persistent compiler submissions and inspection

    Copyright (c) 2026 Gary William Flake.
*/
#pragma once
#include "frontend.x"

/** The caller keeps the compiler's unit Context open until every result and
    this session are finished. Results borrow that Context's storage. */
typedef struct ReplSession {
  Compiler compiler;
  // Published name -> (value), (native), or
  // (function (typed ...) (lowered ...)).
  Map names;
} *ReplSession;

/** status is incomplete, rejected, defined, executed, value, or failed.
    diagnostics are ordinary compiler reports; message/cause describe the
    adapter or evaluator failure. source retains diagnostic source text;
    syntax and lowered support optional tracing. */
typedef struct ReplResult {
  Symbol status;
  Var value;
  String name, message, source;
  List diagnostics, cause, syntax, lowered;
} ReplResult;

/** Byte range and sorted `(kind "spelling")` replacement candidates for one
    completion request. Candidate storage is borrowed until the session unit
    closes. */
typedef struct ReplCompletion {
  size_t start, end;
  List candidates;
} ReplCompletion;

#pragma private
#include "comptime.x"
#include "parse.x"
#include "diagnostics.x"
#include "lisp.x"
#include "scope.x"
#include <errno.h>
#include <stdio.h>

static void _write_stdout(String text, int newline, Symbol operation) {
  size_t length = text.len();
  if ((length && fwrite(text, 1, length, stdout) != length) ||
      (newline && fputc('\n', stdout) == EOF) || ferror(stdout)) {
    int error = errno;
    raise %(io-fail (operation $operation) (errno $error));
  }
}

static void _repl_print(String text) => _write_stdout(text, 0, <print>);
static void _repl_println(String text) => _write_stdout(text, 1, <println>);

/** Borrows an initialized submission compiler until its unit closes.
    Source-fact collection must be disabled because submission scratch maps
    are reclaimed after each call. */
ReplSession ReplSession.new(Compiler compiler) {
  if (compiler.source_facts)
    raise %(bad-arg (operation "ReplSession.new")
                   (why "source facts retain temporary symbol maps"));
  ReplSession session = Scope.calloc(1, sizeof(struct ReplSession));
  session.compiler = compiler;
  session.names = {};
  $lisp.bind(compiler.macro_lisp, "print", _repl_print);
  $lisp.bind(compiler.macro_lisp, "println", _repl_println);
  return session;
}

/** Returns an immutable snapshot of (kind "name") entries, sorted by name.
    Only session definitions appear; storage is borrowed until unit close. */
List ReplSession.symbols(ReplSession session) {
  Array names = $auto([]), entries = [];
  foreach (Var (name, entry), session.names) names.push(name);
  foreach (String name, names.sort()) {
    List entry = session.names[name];
    entries.push(%(${entry.car()} $name));
  }
  return entries.list_free();
}

/** Returns (value), (native), (function (typed AST) (lowered FORMS)), or
    NULL if absent.
    These are the original canonical Lists, borrowed until unit close. */
List ReplSession.inspect(ReplSession session, String name) {
  Var entry;
  return session.names.try_get(name, &entry) ? entry.list() : NULL;
}

static List _completion_filter(
  ReplSession session, Symbol kind, List rows, List keywords, String prefix) {
  Array candidates = [];
  foreach (String keyword, keywords)
    if (keyword.startswith(prefix)) candidates.push(%(<keyword> $keyword));
  foreach (Var row, rows) {
    String name = NULL;
    Var type = void;
    if (kind == <members>) name = row;
    else match (row) case %(?(String spelling) ?semantic): {
      name = spelling;
      type = semantic;
    }
    if (!name || !name.startswith(prefix)) continue;
    Type semantic_type = type is <list> ? type : NULL;
    if (kind == <type> && type != <typemacro> &&
        (!semantic_type || !semantic_type.is_typedef())) continue;
    if ((kind == <expr> || kind == <statement>) &&
        (type == <typemacro> ||
         (semantic_type && semantic_type.is_typedef()))) continue;
    if (kind == <continue>) continue;
    if (type is <list>) {
      Type semantic = type;
      Var callable;
      if (semantic.is_function() && !session.names.contains(name) &&
          !session.compiler.macro_lisp.try_get(name, &callable))
        continue;
    }
    Symbol candidate_kind = <name>;
    if (kind == <members>) candidate_kind = <member>;
    else if (session.names.contains(name)) candidate_kind = <session>;
    else if (type is <list>) {
      Type semantic = type;
      if (semantic.is_typedef()) candidate_kind = <type>;
      else if (semantic.is_function()) candidate_kind = <callable>;
    }
    else if (type == <typemacro>) candidate_kind = <type>;
    else if (type == <macro>) candidate_kind = <callable>;
    candidates.push(%($candidate_kind $name));
  }
  return candidates.sort().list_free();
}

/** Returns sorted published session functions matching `prefix`. */
List ReplSession.complete_functions(ReplSession session, String prefix) {
  Array names = $auto([]), candidates = [];
  foreach (Var (candidate, stored), session.names) {
    if (!(candidate is <string>) || !(stored is <list>)) continue;
    String name = candidate;
    List entry = stored;
    if (entry.car() == <function> && name.startswith(prefix)) names.push(name);
  }
  foreach (String name, names.sort())
    candidates.push(%(<session> $name));
  return candidates.list_free();
}

/** Completes the source namespace at byte `cursor` without publishing parse
    state. Invalid or non-code prefixes return no candidates. */
ReplCompletion ReplSession.complete(
  ReplSession session, String source, size_t cursor) {
  if (!session || cursor > source.len())
    raise %(bad-arg (operation "ReplSession.complete"));
  size_t start = cursor;
  while (start && (source[start - 1] == '_' ||
         scan_ascii_alpha((unsigned char) source[start - 1]) ||
         scan_ascii_digit((unsigned char) source[start - 1]))) start--;
  String prefix = String.new_len(source + start, cursor - start);
  String marker = "__x2c_completion__";
  String marked = String.new_len(source, start) + marker;
  ReplCompletion result = {
    .start = start, .end = cursor, .candidates = %()
  };
  Compiler c = session.compiler;
  DiagnosticsHold diagnostics = c.diagnostics.hold();
  defer c.diagnostics.release(diagnostics, 0);
  Scope scratch = $auto(Scope.new());
  Tokenizer tokenizer = c.tokenizer;
  Token token = c.token, boundary = c.input_boundary;
  Token directives = c.directives_taken;
  String text = c.text;
  Map arms = c.arm_stacks;
  Array braces = c.braces, layout_marks = c.layout_marks;
  Array packed_marks = c.packed_marks;
  defer {
    c.tokenizer = tokenizer;
    c.token = token;
    c.input_boundary = boundary;
    c.directives_taken = directives;
    c.text = text;
    c.arm_stacks = arms;
    c.layout_marks = layout_marks;
    c.packed_marks = packed_marks;
    c.braces = braces;
  }
  c.directives_taken = NULL;
  SymTxn transaction;
  $scope(&scratch) {
    c.braces = [];
    transaction = c.begin_semantic_transaction();
  }
  defer transaction.rollback();
  Symbol kind = 0;
  List rows = NULL, keywords = NULL;
  try {
    _tokenize(c, marked, scratch);
    if (c.tokenizer.status() != <ok>) return result;
    /* Parsing a meta declaration can run its declaration effect. Completion
       has no publication path, so leave those forms to complete after a
       declaration is submitted instead. */
    if (c.meta_form_is_declaration()) return result;
    c.mark_completion(marked.len() - marker.len());
    c.__complete_here(<submit>, %(
      "void" "char" "short" "int" "long" "float" "double"
      "signed" "unsigned" "if" "while" "for" "do" "return"
      "try" "raise" "defer" "match" "switch" "with"
    ));
    int declaration = c.test_declaration();
    int end = marked.len();
    if (!declaration) {
      String head = "void __repl_eval(void) {\n";
      end += head.len();
      marked = head + marked + "\n}";
      _tokenize(c, marked, scratch);
      c.mark_completion(head.len() + start);
    }
    (void) c.parse_submission(end);
  }
  catch %(replcomp (kind ?(Symbol found_kind)) (rows ?found)
                   (keywords ?found_keywords)): {
    kind = found_kind;
    rows = found;
    keywords = found_keywords;
  }
  catch %(incomplete *): return result;
  catch %(malformed *): return result;
  if (rows || keywords) result.candidates = _completion_filter(
    session, kind, rows, keywords, prefix);
  return result;
}

static List _bare(List node) {
  match (node) case %(at ? ?inner): return inner;
  return node;
}

static List _thunk(List items) =>
  %(function (int)
    (bind (binding -1 "__repl_eval") ((fnmod (params))))
    (block @items));

static void _refuse(String why) { raise %(repl (why $why)); }

static int _type_submission_names(List node, Array added) {
  match (node) {
    case %(typedef ? (bindings *bindings)): {
      foreach (List binding, bindings)
        match (binding) case %(bind (binding ? ?(String name)) *):
          added.push(name);
      return 1;
    }
    case %(declare ?spec (bindings (bind () ()))): {
      Type type = node.type_from_ast().base_type();
      if (type.car() != <struct>) return 0;
      Var name = type.cadr();
      if (name is <string>) added.push(name);
      else if (name is <list>)
        added.push(binding_identity_spelling(name));
      return 1;
    }
  }
  return 0;
}

static void _tokenize(Compiler c, String source, Scope scratch) {
  $scope(&scratch) { c.tokenize(source); }
}

// Native name resolution and persistent local storage need native execution.
static void _require_evaluable(Var syntax) {
  match (syntax) {
    case %(expr () (ident (binding ? ?name))):
      _refuse(%"unresolved identifier: $name");
    case %(declare ?spec ?):
      if (spec.contains(<static>) || spec.contains(<extern>) ||
          spec.contains(<threaded>))
        _refuse("static, extern, and threaded storage need native execution");
  }
  if (syntax is <list>) foreach (Var child, syntax.list())
    _require_evaluable(child);
}

static List _initializers(List node, Map names, Array added, Array ids) {
  Array statements = $auto([]);
  match (node) {
    case %(declare ?spec (bindings *bindings)): {
      foreach (List item, bindings) {
        match (item) {
          case %(op = (bind (binding ?id ?(String name)) ?mods) ?value): {
            if (names.contains(name) || added.contains(name) ||
                name.startswith("__repl_"))
              _refuse("redeclaration is disabled; use assignment");
            added.push(name);
            ids.push(id);
            /* Keep the declaration's declarator and initializer together.
               Braced initialization has meaning only in that type context;
               the compile-time lowering consumes this private wrapper with
               the same initializer path used by ordinary declarations. */
            statements.push(%(repl-init $spec
              (bind (binding $id $name) $mods) $value));
            continue;
          }
        }
        _refuse("top-level values need an initializer and a simple binding");
      }
      return _thunk(statements);
    }
  }
  _refuse("this top-level form is outside the REPL subset");
  return NULL;
}

static List _result_body(List fn, int &prints) {
  match (fn) {
    case %(function ? ? (block *body)): {
      Array items = $auto(body);
      if (items.len()) {
        List last = _bare(items[items.len() - 1]);
        match (last) {
          case %(stmnt (expr ?spec ?value)): {
            if (spec === %(void)) return _thunk(items);
            int effect = 0;
            match (value) {
              case %(op ?operator *):
                effect = %("=" "++" "--" "+=" "-=" "*=" "/=" "%="
                           "&=" "|=" "^=" "<<=" ">>=").contains(operator.str());
              case %(postfix *): effect = 1;
            }
            if (!effect) {
              items[items.len() - 1] = %(return $spec (expr $spec $value));
              prints = 1;
            }
          }
        }
      }
      return _thunk(items);
    }
  }
  return fn;
}

/* Whether the submission is a bodyless `meta` prototype. It binds a
   function the compiler links or a loaded native module supplies. A body
   opens with `{`, or with the `=` of `=>` for an expression body, and a
   `meta` value has an `=` initializer. */
static int _native_prototype(Compiler c) {
  if (!c.meta_form_is_declaration()) return 0;
  for (Token token = c.token; token.type != <eof>; token++)
    if (token.type == <"{"> || token.type == <=>) return 0;
  return 1;
}

/** Submits one complete candidate without printing or retaining a pending
    prefix. Only successfully initialized declarations publish new bindings;
    evaluation effects on previously published values survive failure. */
ReplResult ReplSession.submit(ReplSession session, String source) {
  Compiler c = session.compiler;
  Map names = session.names;
  ReplResult result = { .status = <rejected>, .value = void };
  c.diagnostics.reset();
  Scope scratch = $auto(Scope.new());
  Tokenizer tokenizer = c.tokenizer;
  Token token = c.token, boundary = c.input_boundary;
  Token directives = c.directives_taken;
  String text = c.text;
  Map arms = c.arm_stacks;
  Array braces = c.braces, layout_marks = c.layout_marks;
  Array packed_marks = c.packed_marks;
  defer {
    c.tokenizer = tokenizer;
    c.token = token;
    c.input_boundary = boundary;
    c.directives_taken = directives;
    c.text = text;
    c.arm_stacks = arms;
    c.layout_marks = layout_marks;
    c.packed_marks = packed_marks;
    c.braces = braces;
  }
  c.directives_taken = NULL;
  SymTxn transaction;
  $scope(&scratch) {
    c.braces = [];
    transaction = c.begin_semantic_transaction();
  }
  defer transaction.rollback();
  Array added = [], ids = [];
  defer { added.free(); ids.free(); }
  List fn = NULL;
  String function_name = NULL;
  int execute = 0, prints = 0, end = source.len();
  try {
    result.source = source;
    _tokenize(c, result.source, scratch);
    if (c.tokenizer.status() == <incomplete>) {
      result.status = <incomplete>;
      return result;
    }
    for (Token token = c.tokenizer.tokens; token.type != <eof>; token++) {
      if (token.type == <preproc> || token.type == <"$(">)
        _refuse("preprocessor and direct Lisp input are unsupported");
      if (token.type == <const> || token.type == <volatile>)
        _refuse("const and volatile need native checks outside the REPL");
    }
    if (c.peek(0) == <eof>) {
      result.status = <executed>;
      return result;
    }
    int native = _native_prototype(c);
    if (c.peek(0) == <import> || c.protocol_form_starts() ||
        c.peek(0) == <"$("> || (c.meta_form_is_declaration() && !native) ||
        c.macro_form_is_definition() || c.keyword_form_is_definition())
      _refuse("compiler-session definitions are outside the REPL subset");
    if (c.peek(0) == <union> || c.peek(0) == <enum> ||
        c.peek(0) == <extern> || c.peek(0) == <static>)
      _refuse("type and storage declarations are outside the REPL subset");
    int declaration = native || c.test_declaration();
    if (!declaration) {
      String prefix = "void __repl_eval(void) {\n";
      end += prefix.len();
      result.source = prefix + source + "\n}";
      _tokenize(c, result.source, scratch);
    }
    List node = c.parse_submission(end);
    if (native) {
      match (node)
        case %(declare ? (bindings (bind (binding ? ?(String name)) *))): {
          Var bound;
          if (names.contains(name))
            _refuse("function redeclaration is disabled");
          if (!c.macro_lisp.try_get(name, &bound))
            _refuse(%"no native function is available for $name");
          transaction.commit_transient();
          names[name] = %(native);
          result.syntax = node;
          result.name = name;
          result.status = <defined>;
          return result;
        }
    }
    _require_evaluable(node);
    if (_type_submission_names(node, added)) {
      foreach (String name, added)
        if (names.contains(name))
          _refuse("a type cannot be redefined; the session keeps its layout");
      transaction.commit_transient();
      foreach (String name, added) names[name] = %(type);
      result.syntax = node;
      result.name = added.len() ? added[0].str() : NULL;
      result.status = <defined>;
      return result;
    }
    if (!declaration) {
      fn = _result_body(node, prints);
      execute = 1;
    }
    else {
      match (node) {
        case %(function ? (bind (binding ? ?(String name)) ?) ?): {
          Var existing;
          if (names.contains(name) || name.startswith("__repl_") ||
              c.macro_lisp.try_get(name, &existing))
            _refuse("function redeclaration is disabled");
          added.push(name);
          function_name = name;
          fn = node;
        }
      }
      if (!fn) {
        fn = _initializers(node, names, added, ids);
        execute = 1;
      }
    }
    result.diagnostics = c.diagnostics();
  }
  catch %(incomplete *): {
    result.status = <incomplete>;
    return result;
  }
  catch %(malformed *): {
    result.diagnostics = c.diagnostics();
    return result;
  }
  catch %(repl (why ?why)): {
    result.diagnostics = c.diagnostics();
    result.message = why;
    return result;
  }
  result.syntax = fn;
  List forms = c.lower_repl(fn);
  if (!forms) {
    result.message = "unsupported: " + c.lower_declined();
    return result;
  }
  result.lowered = forms;
  try {
    foreach (Var form, forms) c.macro_lisp.eval(form);
    if (execute) result.value = c.macro_lisp.eval(%(__repl_eval));
  }
  catch %(?cause *details): {
    // Discard cells for unpublished bindings before rollback reuses their IDs.
    Var storage;
    if (c.macro_lisp.try_get("C._globals", &storage)) {
      Map globals = storage;
      foreach (Var id, ids) globals.del(id);
    }
    result.status = <failed>;
    result.cause = cons(cause, details);
    return result;
  }
  if (function_name || added.len()) {
    transaction.commit_transient();
    foreach (String name, added)
      names[name] = function_name
        ? %(function (typed ${result.syntax}) (lowered ${result.lowered}))
        : %(value);
  }
  result.name = function_name;
  result.status = function_name ? <defined> : prints ? <value> : <executed>;
  return result;
}
