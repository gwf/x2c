/*  repl-session.x -- persistent compiler submissions and inspection

    Copyright (c) 2026 Gary William Flake.
*/
#pragma once
#include "frontend.x"

/** The caller keeps the compiler's unit Context open until every result and
    this session are finished. Results borrow that Context's storage. */
typedef struct ReplSession {
  Compiler compiler;
  // Published name -> (value), (type), (native), or (function (typed ...)).
  Map names;
  // Binding id of each published value -> the binding of its cell.
  Map cells;
  // Staged session function name -> the module that defines it.
  Map modules;
  int serial;
} *ReplSession;

/** status is incomplete, rejected, defined, executed, value, or failed.
    diagnostics are ordinary compiler reports; message/cause describe the
    staging or evaluation failure. source retains diagnostic source text;
    syntax supports optional tracing. */
typedef struct ReplResult {
  Symbol status;
  Var value;
  String name, message, source;
  List diagnostics, cause, syntax;
} ReplResult;

/** Byte range and sorted `(kind "spelling")` replacement candidates for one
    completion request. Candidate storage is borrowed until the session unit
    closes. */
typedef struct ReplCompletion {
  size_t start, end;
  List candidates;
} ReplCompletion;

#pragma private
#include "stage.x"
#include "path.x"
#include "parse.x"
#include "diagnostics.x"
#include "lisp.x"
#include "scope.x"
#include <dlfcn.h>
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

/* The session's `print` and `println`, which staged submissions call. */
void print(String text) => _write_stdout(text, 0, <print>);
void println(String text) => _write_stdout(text, 1, <println>);

/** Borrows an initialized submission compiler until its unit closes.
    Source-fact collection must be disabled because submission scratch maps
    are reclaimed after each call. Each submission that runs or defines code
    stages the session's definitions as one native module. */
ReplSession ReplSession.new(Compiler compiler) {
  if (compiler.source_facts)
    raise %(bad-arg (operation "ReplSession.new")
                   (why "source facts retain temporary symbol maps"));
  ReplSession session = Scope.calloc(1, sizeof(struct ReplSession));
  session.compiler = compiler;
  session.names = {};
  session.cells = {};
  session.modules = {};
  compiler.unit_nodes = [
    %(preproc "void print(String text);"),
    %(preproc "void println(String text);")
  ];
  // Completion offers callables the session binds.
  $lisp.bind(compiler.macro_lisp, "print", print);
  $lisp.bind(compiler.macro_lisp, "println", println);
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

/** Returns (value), (type), (native), (function (typed AST)), or NULL if
    absent.
    These are the original canonical Lists, borrowed until unit close. */
List ReplSession.inspect(ReplSession session, String name) {
  Var entry;
  return session.names.try_get(name, entry) ? entry.list() : NULL;
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
          !session.compiler.macro_lisp.try_get(name, callable))
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
    if (candidate is not <string> || stored is not <list>) continue;
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
    c.__complete_here(
      <submit>,
      %("void" "char" "short" "int" "long" "float" "double"
        "signed" "unsigned" "if" "while" "for" "do" "return"
        "try" "raise" "defer" "match" "switch" "with"));
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
  catch %((!or incomplete malformed) *): return result;
  if (rows || keywords) result.candidates = _completion_filter(
    session, kind, rows, keywords, prefix);
  return result;
}

static List _bare(List node) {
  match (node) case %(at ? ?inner): return inner;
  return node;
}

/* A parameterless function returning `result`, under a fresh name. */
static List _thunk(ReplSession session, List result, List items) {
  List binding = session.compiler.sym.introduce(
    "__repl_eval_%d".printf(session.serial++));
  return %(function $result
    (bind $binding ((fnmod (params (param (void) (bind () ()))))))
    (block @items));
}

/* `node` with each reference to a published value read through its cell. */
static Var _through_cells(Var node, Map cells) {
  if (node is not <list>) return node;
  Var cell;
  match (node)
    case %(binding ?id ?(String _)): return cells.try_get(id, cell) ? cell : node;
  Array parts = [];
  foreach (Var part, (List) node) parts.push(_through_cells(part, cells));
  return parts.list_free();
}

/* Adds function `fn` to the session's meta group. */
static void _group(ReplSession session, List fn) {
  fn = _through_cells(fn, session.cells);
  match (fn)
    case %(function ?spec (!set ?declarator (bind (binding ? ?(String name))
                                                  *)) ?): {
      Type type = %(declare $spec (bindings $declarator)).type_from_ast()
                    .canonicalize();
      session.compiler.meta_group.push(%(function $fn $name $type));
    }
}

static String _thunk_name(List thunk) {
  match (thunk)
    case %(function ? (bind (binding ? ?(String name)) *) ?): return name;
  return NULL;
}

static const int _trapped[] = { SIGINT, SIGSEGV, SIGBUS, SIGFPE, SIGILL };
enum { _TRAPPED = sizeof(_trapped) / sizeof(_trapped[0]) };

/* Raises an `Error` from the signal that stopped a submission, so the
   submission unwinds to `_run`. The handler runs on its own stack, which
   survives a submission that exhausts the native stack. */
static void _stop(int number) {
  if (number == SIGINT) raise %(interrupt (signal $number));
  raise %(crash (signal $number)
                (why "the session may be inconsistent after a crash"));
}

/* Clears the record that the handler's stack is in use, which leaving a
   handler by a jump keeps on some hosts, by jumping with the state saved
   here, off that stack. */
static void _leave_signal_stack(void) {
  sigjmp_buf here;
  if (!sigsetjmp(here, 1)) siglongjmp(here, 1);
}

/* Calls the staged thunk `thunk`. Ctrl-C and a crash in the submission
   raise, and the submission fails instead of ending the session. */
static Var _run(Compiler c, List thunk) {
  static char stack[1 << 17];
  static int ready = 0;
  Var function;
  if (!c.macro_lisp.try_get(_thunk_name(thunk), function))
    _refuse("the result has no Var form");
  if (!ready) {
    stack_t alternate = { .ss_sp = stack, .ss_size = sizeof(stack) };
    ready = !sigaltstack(&alternate, NULL);
  }
  else _leave_signal_stack();
  struct sigaction action = {
    .sa_handler = _stop, .sa_flags = SA_ONSTACK | SA_NODEFER };
  struct sigaction saved[_TRAPPED];
  sigemptyset(&action.sa_mask);
  for (int i = 0; i < _TRAPPED; i++)
    sigaction(_trapped[i], &action, &saved[i]);
  defer for (int i = 0; i < _TRAPPED; i++)
    sigaction(_trapped[i], &saved[i], NULL);
  return c.macro_lisp.apply(function, %());
}

/* Replaces the declaration of each value in `declarations`, now defined
   by the module just loaded at `addresses`, with a declaration that only
   gives its cell a type and a macro that reads the cell at its address.
   The macro's own name inside its expansion is not expanded again. */
static void _publish_cells(
  ReplSession session, int first, Array declarations, Array addresses) {
  Array nodes = session.compiler.unit_nodes;
  for (int i = 0; i < (int) declarations.len(); i++)
    match (declarations[i])
      case %(declare ?spec (bindings (bind (binding ?id ?) ?mods))): {
        String cell = "__repl_cell_%d".printf(session.serial++);
        long address = addresses[i];
        nodes[first + 2 * i] =
          %(declare (extern @spec) (bindings (bind (binding $id $cell) $mods)));
        nodes[first + 2 * i + 1] = %(preproc ${
          "#define %s (*(__typeof__(%s) *) %#lx)".printf(
            cell, cell, (unsigned long) address)});
        session.cells[id] = %(binding $id $cell);
      }
}

/* Moves the function `fn`, just staged in `module`, out of the session's
   group: later modules declare it and call it at its address in `module`
   through a macro, so each submission stages only its own code. Returns
   whether the function left the group. */
static int _publish_function(ReplSession session, List fn, String module) {
  match (fn)
    case %(function ?spec (!set ?declarator (bind (binding ? ?(String name))
                                                  *)) ?): {
      void *handle = dlopen(module, RTLD_NOW | RTLD_NOLOAD);
      void *address = handle ? dlsym(handle, name) : NULL;
      if (!address) return 0;
      Array nodes = session.compiler.unit_nodes;
      nodes.push(%(declare $spec (bindings $declarator)));
      nodes.push(%(preproc ${
        "#define %s (*(__typeof__(%s) *) %#lx)".printf(
          name, name, (unsigned long) address)}));
      session.modules[name] = module;
      return 1;
    }
  return 0;
}

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

/* Declares each value of `node` in `declarations` and adds to `thunks`, in
   order, a function that initializes it and returns its address. A braced
   initializer has meaning only in its declaration, so each value is
   initialized from a local declared the same way. */
static void _initializers(
  ReplSession session, List node, Array added, Array declarations,
  Array thunks) {
  Compiler c = session.compiler;
  match (node) {
    case %(declare ?spec (bindings *bindings)): {
      foreach (List item, bindings) {
        match (item) {
          case %(op = (bind (!set ?binding (binding ? ?(String name))) ?mods)
                    ?value): {
            if (session.names.contains(name) || added.contains(name) ||
                name.startswith("__repl_"))
              _refuse("redeclaration is disabled; use assignment");
            Type type = %(declare $spec (bindings (bind $binding $mods)))
                          .type_from_ast().canonicalize();
            if (type.is_array())
              _refuse("array values are outside the REPL subset");
            added.push(name);
            List local = c.sym.introduce("__repl_value");
            List cell = %(expr $type (ident $binding));
            declarations.push(%(declare $spec (bindings (bind $binding $mods))));
            thunks.push(_thunk(session, %(long), %(
              (declare $spec (bindings (op = (bind $local $mods) $value)))
              (stmnt (expr $type (op = $cell (expr $type (ident $local)))))
              (return (long) (expr (long)
                (cast (decl (long) (bindings (bind () ())))
                  (expr (* @type) (op & $cell))))))));
            continue;
          }
        }
        _refuse("top-level values need an initializer and a simple binding");
      }
      return;
    }
  }
  _refuse("this top-level form is outside the REPL subset");
}

static List _result_body(ReplSession session, List fn, int &prints) {
  match (fn) {
    case %(function ? ? (block *body)): {
      Array items = $auto(body);
      if (items.len()) {
        List last = _bare(items[items.len() - 1]);
        match (last) {
          case %(stmnt (expr ?spec ?value)): {
            if (spec === %(void)) return _thunk(session, %(void), items);
            int effect = 0;
            match (value) {
              case %(op ?operator *):
                effect = %("=" "++" "--" "+=" "-=" "*=" "/=" "%="
                           "&=" "|=" "^=" "<<=" ">>=").contains(operator.str());
              case %(postfix *): effect = 1;
            }
            if (!effect) {
              items[items.len() - 1] =
                %(return ("Var") (expr $spec $value));
              prints = 1;
              return _thunk(session, %("Var"), items);
            }
          }
        }
      }
      return _thunk(session, %(void), items);
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
  Array added = [], declarations = [], thunks = [];
  defer { added.free(); declarations.free(); thunks.free(); }
  List fn = NULL;
  String function_name = NULL;
  int prints = 0, end = source.len();
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
          if (!c.macro_lisp.try_get(name, bound))
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
      c.unit_nodes.push(node);
      foreach (String name, added) names[name] = %(type);
      result.syntax = node;
      result.name = added.len() ? added[0].str() : NULL;
      result.status = <defined>;
      return result;
    }
    if (!declaration) {
      thunks.push(_result_body(session, node, prints));
    }
    else {
      match (node) {
        case %(function ? (bind (binding ? ?(String name)) ?) ?): {
          Var existing;
          if (names.contains(name) || name.startswith("__repl_") ||
              c.macro_lisp.try_get(name, existing))
            _refuse("function redeclaration is disabled");
          added.push(name);
          function_name = name;
          fn = node;
        }
      }
      if (!fn) _initializers(session, node, added, declarations, thunks);
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
  result.syntax = fn ? fn : thunks.len() == 1 ? thunks[0].list() : NULL;
  /* Stage the session's definitions with this submission's as one module.
     Thunks leave the group once they run, and a submission that fails
     leaves the group and the declarations as it found them. */
  Array group = c.meta_group, nodes = c.unit_nodes;
  size_t group_mark = group.len(), node_mark = nodes.len();
  defer if (group.len() > group_mark) group.resize(group_mark);
  foreach (List declaration, declarations) {
    nodes.push(declaration);
    nodes.push(%(preproc ""));
  }
  if (fn) _group(session, fn);
  foreach (List thunk, thunks) _group(session, thunk);
  String failure = NULL;
  String module = c.stage_meta_group(failure);
  if (!module) {
    nodes.resize(node_mark);
    result.message = failure;
    return result;
  }
  Array addresses = $auto([]);
  try {
    foreach (List thunk, thunks) {
      Var value = _run(c, thunk);
      if (declarations.len()) addresses.push(value);
      else result.value = value;
    }
  }
  catch %(repl (why ?why)): {
    nodes.resize(node_mark);
    result.message = why;
    return result;
  }
  catch %(?cause *details): {
    nodes.resize(node_mark);
    result.status = <failed>;
    result.cause = cons(cause, details);
    return result;
  }
  _publish_cells(session, node_mark, declarations, addresses);
  if (fn && !_publish_function(session, fn, module)) {
    group_mark++;
    session.modules[function_name] = module;
  }
  if (function_name || added.len()) {
    transaction.commit_transient();
    foreach (String name, added)
      names[name] = function_name
        ? %(function (typed ${result.syntax})) : %(value);
  }
  result.name = function_name;
  result.status = function_name ? <defined> : prints ? <value> : <executed>;
  return result;
}

/** Returns the C that the last staging emitted for session function
    `name`, or NULL when it is not a staged session function. */
String ReplSession.lowered(ReplSession session, String name) {
  List entry = session.inspect(name);
  Var module;
  if (!entry || entry.car() != <function> ||
      !session.modules.try_get(name, module))
    return NULL;
  String code = Path.read_text(Path.dirname(module.str()) + "/group.c");
  Array lines = $auto([]);
  int inside = 0;
  foreach (String line, code.lines()) {
    if (!inside && line.len() && line[0] != ' ' && line.contains(name + "(") &&
        !line.endswith(";"))
      inside = 1;
    if (!inside) continue;
    lines.push(line);
    if (line == "}") break;
  }
  return lines.len() ? "\n".join(lines) : NULL;
}
