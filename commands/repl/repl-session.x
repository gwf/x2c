/*  repl-session.x -- persistent compiler submissions and inspection

    Copyright (c) 2026 Gary William Flake.
*/
#pragma once
#include "frontend.x"
#include "repl-lower.x"
#include "repl-runtime.x"
#include "emit/emit.x"
#include "format.x"
#include "ast-rewrite.x"

/** One loaded file's origin and published declarations.
    Callable adapters borrow this record until the session closes. */
typedef struct ReplLoadedFile {
  String path;
  Map symbols, signatures;
  List types;
} *ReplLoadedFile;

/** The caller keeps the compiler's unit Context open until every result and
    this session are finished. Results borrow that Context's storage. */
typedef struct ReplSession {
  Compiler compiler;
  Lisp evaluator;
  ReplLower lowering;
  Array declarations;
  Map files, accessors;
  MetaHelper helper;
  // Published name -> (value), (type), (native [(source PATH) (objects CALL)]),
  // (global (source PATH) PATHS), or
  // (function (typed ...) (execution native)).
  Map names;
} *ReplSession;

/** status is incomplete, rejected, defined, loaded, reloaded, executed,
    value, or failed.
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

#include "parse/parse.x"
#include "diagnostics.x"
#include "lisp/lisp.x"
#include "scope/scope.x"
#include "meta.x"
#include "refusal-errors.x"
#include "repl-native.x"
#include "repl-globals.x"
#include <errno.h>
#include <signal.h>
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

/* The evaluator a SIGINT interrupts while a submission runs. */
static Lisp _running;

static void _interrupt(int signal) {
  (void) signal;
  _running.set_interrupted(1);
}

/** Borrows an initialized submission compiler until its unit closes.
    Source-fact collection must be disabled because submission scratch maps
    are reclaimed after each call. */
ReplSession ReplSession.new(Compiler compiler) {
  if (compiler.source_facts)
    raise %(bad-arg (operation "ReplSession.new")
                   (reason "source facts retain temporary symbol maps"));
  ReplSession session = Scope.calloc(1, sizeof(struct ReplSession));
  session.compiler = compiler;
  session.names = {};
  session.files = {};
  session.accessors = {};
  session.declarations = [];
  session.evaluator = Lisp.new();
  repl_runtime_initialize(session.evaluator);
  session.lowering = ReplLower.new(compiler, session.evaluator);
  $lisp.bind(session.evaluator, "print", _repl_print);
  $lisp.bind(session.evaluator, "println", _repl_println);
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

/** Returns (value), (type), (native [(source PATH) (objects CALL)]),
    (global (source PATH) PATHS), (function (typed AST) (execution native)),
    or NULL if absent. PATHS maps selections to getter/setter pairs.
    These are the original canonical Lists, borrowed until unit close. */
List ReplSession.inspect(ReplSession session, String name) {
  Var entry;
  return session.names.try_get(name, entry) ? entry.list() : NULL;
}

/** Returns a session function's declaration and source, or NULL for another
    name. Formatting uses the compiler's declaration emitter without calling
    the function. Loaded files supply their current declaration. */
String ReplSession.function_info(ReplSession session, String name) {
  String source = "prompt";
  String declaration = _function_declaration(session, name, source);
  if (!declaration) return NULL;
  return %"$declaration;\nsource: $source\nexecution: native";
}

/* A session function's declaration without its semicolon, and the file or
   `prompt` that defines it, or NULL for another name. */
static String _function_declaration(
  ReplSession session, String name, String &source) {
  List entry = session.inspect(name);
  if (!entry || (entry.car() != <function> && entry.car() != <native>))
    return NULL;
  Compiler c = session.compiler;
  Type type = c.sym.get_exact(%($name));
  match (entry) case %(native (source ?(String path)) *): {
    ReplLoadedFile file = session.files[path];
    type = file.symbols[%($name)];
    source = path;
  }
  List declaration = type.declaration_ast(%($name));
  String text = String.new(
    c.code_pretty_string(c.emit(%($declaration), NULL), NULL));
  return text.strip(NULL).rstrip(";");
}

/* The compiler's input state, which a submission or completion replaces
   with its own text and restores on every exit. The caller restores
   `braces` in its own `defer`, where the region check sees the scratch
   Array it installs put back. */
static struct _ParserInput {
  Tokenizer tokenizer;
  Token token, boundary, directives;
  String text;
  Map arms;
  Array layout_marks, packed_marks;
};

static struct _ParserInput _parser_input(Compiler c) {
  struct _ParserInput input = {
    .tokenizer = c.tokenizer, .token = c.token,
    .boundary = c.input_boundary, .directives = c.directives_taken,
    .text = c.text, .arms = c.arm_stacks, .layout_marks = c.layout_marks,
    .packed_marks = c.packed_marks
  };
  return input;
}

static void _restore_parser_input(Compiler c, struct _ParserInput input) {
  c.tokenizer = input.tokenizer;
  c.token = input.token;
  c.input_boundary = input.boundary;
  c.directives_taken = input.directives;
  c.text = input.text;
  c.arm_stacks = input.arms;
  c.layout_marks = input.layout_marks;
  c.packed_marks = input.packed_marks;
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
    if (!name || !name.startswith(prefix) || name in session.accessors)
      continue;
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
          !session.evaluator.try_get(name, callable))
        continue;
    }
    Symbol candidate_kind = <name>;
    if (kind == <members>) candidate_kind = <member>;
    else if (name in session.names) candidate_kind = <session>;
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

/** Returns sorted published session functions matching `prefix`.
    `native` also includes loaded functions and bound native prototypes. */
List ReplSession.complete_functions(
  ReplSession session, String prefix, int native) {
  Array names = $auto([]), candidates = [];
  foreach (Var (candidate, stored), session.names) {
    if (candidate is not <string> || stored is not <list>) continue;
    String name = candidate;
    List entry = stored;
    if ((entry.car() == <function> || (native && entry.car() == <native>)) &&
        name.startswith(prefix)) names.push(name);
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
  struct _ParserInput input = _parser_input(c);
  defer _restore_parser_input(c, input);
  Array braces = c.braces;
  defer c.braces = braces;
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
    _x2c_complete_here(
      c, <submit>,
      %("void" "char" "short" "int" "long" "float" "double"
        "signed" "unsigned" "if" "while" "for" "do" "return"
        "try" "raise" "defer" "match" "switch" "with"));
    int declaration = c.test_declaration();
    int end = marked.len();
    if (!declaration) {
      String head = _eval_head();
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
  catch %((!or incomplete malformed) *): return result;
  if (rows || keywords) result.candidates = _completion_filter(
    session, kind, rows, keywords, prefix);
  return result;
}

static List _bare(List node) {
  match (node) case %(at ? ?inner): return inner;
  return node;
}

/* Statements run in a function that the submission does not spell. */
static String _eval_head(void) => "void __repl_eval(void) {\n";

static List _thunk(List items) =>
  %(function (int)
    (bind (binding -1 "__repl_eval") ((fnmod (params))))
    (block @items));

static void _refuse(String why) { raise %(repl (reason $why)); }

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
        added.push(Ast.binding_spelling(name));
      return 1;
    }
  }
  return 0;
}

static void _tokenize(Compiler c, String source, Scope scratch) {
  $scope(&scratch) { c.tokenize(source); }
}

// Prompt submissions require bound names and session-owned persistent state.
static void _require_evaluable(Var syntax) {
  match (syntax) {
    case %(expr () (ident (binding ? ?name))):
      $refusal.binding.unresolved(name);
    case %(declare ?spec ?):
      if (<static> in spec || <extern> in spec || <threaded> in spec)
        $refusal.storage.native();
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
            if (name in names || name in added || name.startswith("__repl_"))
              $refusal.binding.redefined();
            added.push(name);
            ids.push(id);
            /* Keep the declaration's declarator and initializer together.
               Braced initialization has meaning only in that type context;
               the compile-time lowering consumes this private wrapper with
               the same initializer path used by ordinary declarations. */
            statements.push(
              %(repl-init $spec (bind (binding $id $name) $mods) $value));
            continue;
          }
        }
        $refusal.binding.initializer();
      }
      return _thunk(statements);
    }
  }
  $refusal.form.unsupported();
  return NULL;
}

static List _result_body(ReplSession session, List fn, int &prints) {
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
              List shown = session.inspect_global(%(expr $spec $value));
              items[items.len() - 1] = %(return ${shown.cadr()} $shown);
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
    evaluation effects on previously published values survive failure.
    While the submission is evaluated, SIGINT fails it with `<interrupt>`;
    the previous SIGINT disposition returns afterward. Diagnostics locate
    the submission's own lines and columns. */
ReplResult ReplSession.submit(ReplSession session, String source) {
  ReplResult result = _submit(session, source);
  if (result.source == source) return result;
  String filename = session.compiler.filename;
  Array entries = $auto([]);
  foreach (List entry, result.diagnostics)
    entries.push(_submission_entry(entry, filename, source));
  result.diagnostics = entries;
  result.source = source;
  return result;
}

/* An entry located in the wrapped text moves to the same byte of `source`.
   The wrapper's closing brace stands for the end of the submission. */
static List _submission_entry(List entry, String filename, String source) {
  match (entry)
    case %(?code ?severity ?message
           (location ((file ?(String file)) ? ? (length ?length)
                      (position ?(int position))))
           ?notes): {
      if (file != filename) return entry;
      int last = source.rstrip(NULL).len();
      int at = position - _eval_head().len();
      at = at < 0 ? 0 : at > last ? last : at;
      int line = 1, start = 0;
      for (int i = 0; i < at; i++)
        if (source[i] == '\n') { line++; start = i + 1; }
      return %($code $severity $message
               (location ((file $file) (line $line)
                          (column ${at - start + 1}) (length $length)
                          (position $at)))
               $notes);
    }
  return entry;
}

/* A call with the wrong number of arguments fails as its callee rejects
   them, naming only counts and the callee's signature. The submission's
   call with those counts names the function and its declaration. */
static List _arity_cause(ReplSession session, List syntax, List cause) {
  match (cause)
    case %(bad-arity (sig ?) (expected ?wanted) (actual ?given)): {
      int expected = wanted.int(), actual = given.int();
      String source = NULL, plural = expected == 1 ? "" : "s";
      List node;
      $ast.walk(syntax, node) {
        match (node)
          case %(call (expr ((func ?(List parameters)) *)
                            (ident (binding ? ?(String name))))
                      (args *arguments)): {
            int count = 0;
            foreach (Var argument, arguments)
              if (!argument.equal(%(expr (void) ()))) count++;
            int declared = parameters == %((void)) ? 0 : parameters.len();
            String declaration = declared == expected && count == actual
              ? _function_declaration(session, name, source) : NULL;
            if (declaration)
              return %(repl (reason ${
                %"$name takes $expected argument$plural, not $actual: "
                + declaration}));
          }
      }
    }
  return cause;
}

static ReplResult _submit(ReplSession session, String source) {
  Compiler c = session.compiler;
  Map names = session.names;
  ReplResult result = { .status = <rejected>, .value = void };
  c.diagnostics.reset();
  Scope scratch = $auto(Scope.new());
  struct _ParserInput input = _parser_input(c);
  defer _restore_parser_input(c, input);
  Array braces = c.braces;
  defer c.braces = braces;
  c.directives_taken = NULL;
  SymTxn transaction;
  $scope(&scratch) {
    c.braces = [];
    transaction = c.begin_semantic_transaction();
  }
  defer transaction.rollback();
  Array added = [], ids = [];
  defer { added.free(); ids.free(); }
  List fn = NULL, forms = NULL;
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
      if (token.type == <preproc> || token.type == <"$("> ||
          token.type == <"@(">)
        $refusal.input.unsupported();
      if (token.type == <const> || token.type == <volatile>)
        $refusal.qualifier.native();
    }
    if (c.peek(0) == <eof>) {
      result.status = <executed>;
      return result;
    }
    int native = _native_prototype(c);
    if (c.peek(0) == <import> || c.protocol_form_starts() ||
        c.peek(0) == <"$("> || c.peek(0) == <"@("> ||
        (c.meta_form_is_declaration() && !native) ||
        c.macro_form_is_definition() || c.keyword_form_is_definition())
      $refusal.definition.unsupported();
    if (c.peek(0) == <union> || c.peek(0) == <enum> ||
        c.peek(0) == <extern> || c.peek(0) == <static>)
      $refusal.declaration.unsupported();
    int declaration = native || c.test_declaration();
    if (!declaration) {
      String prefix = _eval_head();
      end += prefix.len();
      result.source = prefix + source + "\n}";
      _tokenize(c, result.source, scratch);
    }
    List node = c.parse_submission(end);
    if (native) {
      match (node)
        case %(declare ? (bindings (bind (binding ? ?(String name)) *))): {
          Var bound;
          if (name in names)
            $refusal.function.redefined();
          if (!c.macro_lisp.try_get(name, bound))
            $refusal.function.missing(name);
          session.evaluator.set_global(name, bound);
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
        if (name in names)
          $refusal.type.redefined();
      transaction.commit_transient();
      session.declarations.push(node);
      foreach (String name, added) names[name] = %(type);
      result.syntax = node;
      result.name = added.len() ? added[0].str() : NULL;
      result.status = <defined>;
      return result;
    }
    if (!declaration) {
      fn = _result_body(session, node, prints);
      execute = 1;
    }
    else {
      match (node) {
        case %(function ? (bind (binding ? ?(String name)) ?) ?): {
          Var existing;
          if (name in names || name.startswith("__repl_") ||
              session.evaluator.try_get(name, existing))
            $refusal.function.redefined();
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
    result.syntax = fn;
    $let(c.recovery_depth, c.recovery_depth + 1) {
      fn = session.rewrite_globals(fn);
      if (function_name) {
        Func function = session.compile_function(fn);
        transaction.commit_transient();
        session.evaluator.set_global(function_name, function);
        names[function_name] =
          %(function (typed ${result.syntax}) (execution native));
        result.name = function_name;
        result.status = <defined>;
        return result;
      }
      forms = session.lowering.lower(fn);
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
  catch %(repl (reason ?why)): {
    result.diagnostics = c.diagnostics();
    result.message = why;
    return result;
  }
  if (!forms) {
    result.message = "unsupported: " + session.lowering.declined();
    return result;
  }
  result.lowered = forms;
  _running = session.evaluator;
  _running.set_interrupted(0);
  struct sigaction stop = { .sa_handler = _interrupt }, previous;
  sigemptyset(&stop.sa_mask);
  sigaction(SIGINT, &stop, &previous);
  defer sigaction(SIGINT, &previous, NULL);
  try {
    foreach (Var form, forms) session.evaluator.eval(form);
    if (execute) result.value = session.evaluator.eval(%(__repl_eval));
  }
  catch %(?cause *details): {
    // Discard cells for unpublished bindings before rollback reuses their IDs.
    Var storage;
    if (session.evaluator.try_get("C.globals", storage)) {
      Map globals = storage;
      foreach (Var id, ids) {
        Var address;
        if (globals.try_get(id, address)) Scope.free(address.pointer());
        globals.del(id);
      }
    }
    result.status = <failed>;
    result.cause = _arity_cause(session, result.syntax, cons(cause, details));
    result.diagnostics = c.diagnostics();
    return result;
  }
  if (added.len()) {
    transaction.commit_transient();
    foreach (String name, added) names[name] = %(value);
  }
  result.diagnostics = c.diagnostics();
  result.status = prints ? <value> : <executed>;
  return result;
}

/** Releases interpreter services before closing the borrowed compiler unit. */
void ReplSession.close(ReplSession session) {
  session.lowering.free();
  session.lowering = NULL;
  session.declarations.free();
  session.declarations = NULL;
  session.evaluator.destroy();
  session.evaluator = NULL;
  foreach (Var (path, value), session.files) {
    ReplLoadedFile file = value;
    file.symbols.cleanup();
    file.signatures.cleanup();
    Scope.free(file);
  }
  Scope.free(session.helper);
  session.helper = NULL;
  session.files.cleanup();
  session.files = NULL;
  session.accessors.cleanup();
  session.accessors = NULL;
}
