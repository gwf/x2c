/*  repl-session.x -- native library playground submissions

    Copyright (c) 2026 Gary William Flake.
*/
#pragma once
#include "repl-types.x"
#include "repl-native.x"
#include "repl-prompt-types.x"
#include "repl-ledgers.x"
#include "parse/parse.x"
#include "diagnostics.x"
#include "cpp/cpp.x"
#include "ast-rewrite.x"
#include <dlfcn.h>

void ReplSession.describe(ReplSession session, String name,
                          List syntax, String source);
List repl_member_candidates(Compiler c, Type type);

static String _eval_head(void);
static void _tokenize(ReplSession session, String source, Scope scratch);

static List _ledger_rows(String text) {
  Array rows = [];
  foreach (String line, text.split("\n"))
    if (line && line[0] != '#') rows.push(line.split("|"));
  return rows.list_free();
}

/* The names declared by modules `docs/library-manifest.txt` marks internal,
   and the callables and types `docs/library-api-tiers.txt` marks internal,
   in the C spelling completion offers. */
static Map _internal_names(void) {
  Map names = {};
  foreach (List row, _ledger_rows(repl_library_manifest()))
    match (row) case %(?(String path) "internal" *):
      foreach (String name, Compiler.collected_names(path)) names[name] = 1;
  foreach (List row, _ledger_rows(repl_library_api_tiers()))
    match (row) case %(? "internal" ?(String listed)):
      foreach (String name, listed.split(","))
        names[name.replace(".", "_")] = 1;
  return names;
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

/* An internal name, or a value or constant whose type is internal. */
static int _is_internal(ReplSession session, String name, Type type) {
  if (name in session.internal) return 1;
  if (!type || type.is_typedef() || type.is_function()) return 0;
  match (type.base_type()) {
    case %(?(String base) *): return base in session.internal;
    case %(enum ?(String base) *): return base in session.internal;
  }
  return 0;
}

/* Internal runtime names are offered only when no other candidate matches. */
static List _completion_filter(
  ReplSession session, Symbol kind, List rows, List keywords, String prefix) {
  Array candidates = [], internal = [];
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
    if (!name || !name.startswith(prefix) || name.startswith("__repl_"))
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
    if (candidate_kind != <session> &&
        _is_internal(session, name, semantic_type))
      internal.push($(candidate_kind, name));
    else candidates.push($(candidate_kind, name));
  }
  return (candidates.len() ? candidates : internal).sort().list_free();
}

/** Returns sorted published session functions matching `prefix`.
    `native` also includes loaded functions and bound native prototypes. */
List ReplSession.complete_functions(
  ReplSession session, String prefix, int native) {
  (void) native;
  Array names = auto [], candidates = [];
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
  Scope scratch = auto Scope.new();
  struct _ParserInput input = _parser_input(c);
  defer _restore_parser_input(c, input);
  Array braces = c.braces;
  defer c.braces = braces;
  c.directives_taken = NULL;
  SymTxn transaction;
  auto (&scratch) {
    c.braces = [];
    transaction = c.begin_semantic_transaction();
  }
  defer transaction.rollback();
  Symbol kind = 0, access = 0;
  List rows = NULL, keywords = NULL;
  Type receiver = NULL;
  try {
    _tokenize(session, marked, scratch);
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
        "try" "raise" "defer" "match" "switch" "with" "alias"
        "unalias"));
    int declaration = c.test_declaration();
    int end = marked.len();
    if (!declaration) {
      String head = _eval_head();
      end += head.len();
      marked = head + marked + "\n}";
      _tokenize(session, marked, scratch);
      c.mark_completion(head.len() + start);
    }
    (void) c.parse_submission(end);
  }
  catch %(replcomp (kind ?(Symbol found_kind)) (rows ?found)
                   (keywords ?found_keywords) *more): {
    kind = found_kind;
    rows = found;
    keywords = found_keywords;
    foreach (List fact, more) match (fact) {
      case %(receiver ?type): receiver = type;
      case %(access ?operator): access = operator;
    }
  }
  catch %((!or incomplete malformed) *): return result;
  if (receiver && access == <.>) {
    Array candidates = [];
    foreach (List candidate, repl_member_candidates(c, receiver))
      if (candidate.cadr().str().startswith(prefix)) candidates.push(candidate);
    result.candidates = candidates.list_free();
  }
  else if (rows || keywords) result.candidates = _completion_filter(
    session, kind, rows, keywords, prefix);
  return result;
}

static List _bare(List node) {
  match (node) case %(at ? ?inner): return inner;
  return node;
}

/* Statements run in a function that the submission does not spell. */
static String _eval_head(void) => "void __repl_eval(void) {\n";

static void _tokenize(ReplSession session, String source, Scope scratch) {
  Compiler c = session.compiler;
  auto (&scratch) {
    Map macros = c.initial_macros(c.filename);
    if (session.program) macros.merge(session.program.macros);
    c.cpp = Cpp.new(macros);
    c.tokenize(source);
  }
}

static List _session_bare(List node) => Ast.without_origin(node);

static int _type_only(List node) {
  match (node) {
    case %(typedef *): return 1;
    case %(declare ?spec (bindings (bind () ()))):
      return spec.type().base_type().is_aggregate() ||
             spec.type().base_type().is_enum();
  }
  return 0;
}

static int _file_submission(Compiler c) {
  if (!c.test_declaration()) return 0;
  Token token = c.token;
  SymScope params = c.params;
  int count = c.sym.scope_count();
  DiagnosticsHold hold = c.diagnostics.hold();
  defer {
    c.token = token;
    c.params = params;
    while (c.sym.scope_count() > count) c.sym.pop_scope();
    c.diagnostics.release(hold, 0);
  }
  SymTxn transaction = c.begin_semantic_transaction();
  defer transaction.rollback();
  try with (c.shallow = 1) {
    List declaration = c.parse_declaration_row();
    return _type_only(declaration) || declaration.type_from_ast().is_function();
  }
  catch %((!or incomplete malformed) *): return 0;
  return 0;
}

static List _native_top_statements(Compiler c, List statements) {
  Array result = [];
  foreach (List anchored, statements) {
    List node = Ast.without_origin(anchored), expanded = anchored;
    if (node.car() == <dstrdecl>) {
      c.sym.push_new_scope();
      List lowered = NULL;
      {
        defer c.sym.pop_scope();
        lowered = c.lower_rewrite(
          <node>, <dstrdecl>, node, <block>, %(void), NULL);
      }
      if (!lowered) raise %(repl (reason "destructuring did not lower"));
      node = lowered;
      expanded = Ast.rewrap_origin(anchored, lowered);
    }
    if (node ~= %(seq *items)) {
      foreach (List item, _native_top_statements(c, items)) result.push(item);
    }
    else result.push(expanded);
  }
  return result.list_free();
}

static void _submission_objects(ReplSession session, List items,
                                Array declarations, Array names) {
  Compiler c = session.compiler;
  foreach (List anchored, items) {
    List node = _session_bare(anchored);
    if (node ~= %(seq *children)) {
      _submission_objects(session, children, declarations, names);
      continue;
    }
    List spec = NULL, rows = NULL;
    match (node) case %(declare ?found (bindings *bindings)): {
      spec = found;
      rows = bindings;
    }
    if (!spec) continue;
    foreach (List row, rows) {
      List bound = row;
      match (row) case %(op = ?target ?): bound = target;
      List binding = NULL;
      match (bound) case %(bind ?found ?): binding = found;
      if (!binding) continue;
      String name = Ast.binding_spelling(binding);
      if (!name) continue;
      if (name in session.names || name in names || name.startswith("__repl_"))
        raise %(repl (reason $("redeclaration is disabled: " + name)));
      List declaration = %(declare $spec (bindings $bound));
      declarations.push(declaration);
      names.push(name);
      c.sym.bind_identity(NULL, binding, declaration);
      c.sym.drop(c.semantic_binding_facts(), %(automatic $binding));
    }
  }
}

static int _submission_prints(List statements) {
  if (!statements) return 0;
  List last = _session_bare(statements.last());
  List type = NULL, content = NULL;
  match (last) case %(stmnt (expr ?found ?value)): {
    type = found;
    content = value;
  }
  if (!type || type == %(void)) return 0;
  match (content) {
    case %(op ?operator *):
      if (%("=" "++" "--" "+=" "-=" "*=" "/=" "%="
             "&=" "|=" "^=" "<<=" ">>=").contains(operator.str())) return 0;
    case %(postfix *): return 0;
  }
  return 1;
}

static void _discard_cleanups(ReplSession session, size_t count) {
  while (session.cleanups.len() > count) {
    Func cleanup = session.cleanups[session.cleanups.len() - 1];
    session.cleanups.pop();
    cleanup.apply(0, NULL);
  }
}

static void _complete_native_array(Compiler c, List declaration, Var extent) {
  if (extent is void) return;
  Type type = declaration.type_from_ast().declared();
  List bound = declaration.caddr().cadr().cadr();
  String count = extent.str();
  List dimension = %(dim (expr (int) (literal (int) $count)));
  Type complete = cons(dimension, type.cdr());
  c.sym.bind_identity(NULL, bound, complete.declaration_ast(bound));
}

static void _session_print(String text) {
  if (text.len()) fwrite(text, 1, text.len(), stdout);
}

static void _session_println(String text) {
  _session_print(text);
  fputc('\n', stdout);
}

/** Opens a native session in the borrowed compiler's lifetime. */
ReplSession ReplSession.new(Compiler compiler) {
  ReplSession session = xcalloc(1, sizeof(struct ReplSession));
  session.compiler = compiler;
  session.names = {};
  session.addresses = {};
  session.addresses["print"] = (void *) _session_print;
  session.addresses["println"] = (void *) _session_println;
  session.descriptions = {};
  session.internal = _internal_names();
  session.declarations = [];
  session.cleanups = [];
  session.storage = Scope.new_named("repl native objects");
  session.inspect_depth = 3;
  session.inspect_limit = 100;
  return session;
}

/** Returns the published names and kinds without evaluating user code. */
List ReplSession.symbols(ReplSession session) {
  Array names = auto [], result = [];
  foreach (Var name, session.names.keys()) names.push(name);
  foreach (String name, names.sort()) {
    List entry = session.names[name];
    result.push($(entry.car(), name));
  }
  return result.list_free();
}

/** Returns a published binding's kind and retained typed syntax. */
List ReplSession.inspect(ReplSession session, String name) {
  Var value;
  return session.names.try_get(name, value) ? value : NULL;
}

/** Resolves an expression without executing it or publishing bindings. */
List ReplSession.resolve(ReplSession session, String expression) {
  Compiler c = session.compiler;
  DiagnosticsHold hold = c.diagnostics.hold();
  defer c.diagnostics.release(hold, 0);
  Scope scratch = auto Scope.new();
  struct _ParserInput input = _parser_input(c);
  defer _restore_parser_input(c, input);
  Array braces = c.braces;
  defer c.braces = braces;
  SymTxn transaction = c.begin_semantic_transaction();
  defer transaction.rollback();
  try {
    auto (&scratch) c.braces = [];
    _tokenize(session, expression, scratch);
    List result = c.parse_expression();
    if (c.peek(0) == <;>) c.next();
    return c.peek(0) == <eof> ? result : NULL;
  }
  catch %((!or malformed incomplete) *): return NULL;
  return NULL;
}

static ReplResult _submit_native(ReplSession session, String source) {
  Compiler c = session.compiler;
  c.diagnostics.reset();
  ReplResult result = {.status = <rejected>, .value = void, .source = source};
  Scope scratch = auto Scope.new();
  struct _ParserInput input = _parser_input(c);
  defer _restore_parser_input(c, input);
  Array braces = c.braces;
  defer c.braces = braces;
  auto (&scratch) c.braces = [];
  SymTxn transaction = c.begin_semantic_transaction();
  defer transaction.rollback();
  Array declarations = auto [], names = auto [], retained = auto [];
  size_t cleanup_count = session.cleanups.len();
  List syntax = NULL;
  String function = NULL;
  int prints = 0, wrapped = 0;
  try {
    _tokenize(session, source, scratch);
    if (c.tokenizer.status() == <incomplete>) {
      result.status = <incomplete>;
      return result;
    }
    if (c.peek(0) == <eof>) { result.status = <empty>; return result; }
    for (Token token = c.tokenizer.tokens; token.type != <eof>; token++)
      if (token.type == <preproc>)
        raise %(repl (reason "use :load for source/header configuration"));
    if (c.peek(0) == <import> || c.macro_form_is_definition() ||
        c.protocol_form_starts() || c.meta_form_is_declaration())
      raise %(repl (reason "load compile-time declarations from a source file"));
    if (_file_submission(c)) {
      syntax = c.parse_submission(source.len());
      if (_type_only(syntax)) {
        List type = syntax.type_from_ast().base_type();
        if (syntax ~= %(typedef ? (bindings *rows))) {
          foreach (List row, rows) names.push(Ast.binding_spelling(row.cadr()));
        }
        else if (type.len() > 1 && type.cadr() is <string>) names.push(type.cadr());
        foreach (String name, names)
          if (name in session.names)
            raise %(repl (reason $("a type cannot be redefined: " + name)));
        session.declarations.push(syntax);
        foreach (String name, names) {
          session.names[name] = %(type);
          session.describe(name, syntax, source);
        }
        transaction.commit_transient();
        result.status = <defined>;
        result.name = names.len() ? names[0] : "type";
        result.syntax = syntax;
        return result;
      }
      if (syntax ~= %(function ? (bind ?binding ?) ?)) {
        function = Ast.binding_spelling(binding);
        if (function in session.names || function.startswith("__repl_"))
          raise %(repl (reason $("function redeclaration is disabled: " + function)));
      }
      else raise %(repl (reason "a function prototype needs a loaded provider"));
    }
    else {
      wrapped = 1;
      String prefix = _eval_head();
      result.source = prefix + source + "\n}";
      _tokenize(session, result.source, scratch);
      List parsed = c.parse_submission(prefix.len() + source.len());
      List body = NULL;
      match (parsed) case %(function ? ? (block *items)): body = items;
      if (!body && parsed.car() != <function>)
        raise %(repl (reason "expected an executable submission"));
      syntax = %(block @body);
      body = _native_top_statements(c, body);
      body = repl_prompt_types(session, body, retained);
      syntax = %(block @body);
      _submission_objects(session, body, declarations, names);
      prints = _submission_prints(body);
      c.sym.undefine_global(%("__repl_eval"));
    }
    result.syntax = syntax;
    Map published = NULL;
    Array native_declarations = auto session.declarations.copy();
    foreach (Var declaration, retained) native_declarations.push(declaration);
    with (session.declarations = native_declarations) {
      auto (&session.storage)
        published = repl_native_execute(session, syntax, wrapped, prints);
    }
    foreach (List declaration, retained) {
      session.declarations.push(declaration);
      Type family = Ast.without_origin(declaration).cadr().type().base_type();
      if (family.len() < 2 || family.cadr() is not <string>) continue;
      String name = family.cadr();
      session.names[name] = %(type);
      session.describe(name, declaration, source);
    }
    for (int i = 0; i < names.len(); i++) {
      String name = names[i];
      _complete_native_array(c, declarations[i], published["extent:" + name]);
      session.addresses[name] = published[name];
      session.names[name] = %(value);
    }
    for (int i = 0; i < names.len(); i++) {
      String name = names[i];
      if (name.startswith("_x2c_gensym_")) session.internal[name] = 1;
      else session.describe(name, declarations[i], source);
    }
    if (function) {
      session.addresses[function] = published[function];
      session.names[function] = %(function (typed $syntax) (execution native));
      session.describe(function, syntax, source);
      result.name = function;
    }
    if (function || names.len() || retained.len()) transaction.commit_transient();
    if (prints) result.formatted = published["formatted"];
    result.status = function ? <defined> : prints ? <value> : <executed>;
  }
  catch %(incomplete *): result.status = <incomplete>;
  catch %(malformed *): result.diagnostics = c.diagnostics();
  catch %(repl (reason ?why)): result.message = why;
  catch %(?kind *details): {
    _discard_cleanups(session, cleanup_count);
    result.status = <failed>;
    result.cause = cons(kind, details);
  }
  result.diagnostics = c.diagnostics();
  return result;
}

/** Compiles and executes one complete native submission. */
ReplResult ReplSession.submit(ReplSession session, String source) {
  ReplResult result = _submit_native(session, source);
  if (result.source == source) return result;
  Array entries = auto [];
  foreach (List entry, result.diagnostics) {
    match (entry)
      case %(?code ?severity ?message
        (location ((file ?file) ? ? (length ?length) (position ?(int position))))
        ?notes): {
        int at = position - _eval_head().len();
        at = at < 0 ? 0 : at > source.len() ? source.len() : at;
        int line = 1, first = 0;
        for (int i = 0; i < at; i++)
          if (source[i] == '\n') { line++; first = i + 1; }
        entry = %($code $severity $message
          (location ((file $file) (line $line) (column $(at - first + 1))
            (length $length) (position $at))) $notes);
      }
    entries.push(entry);
  }
  result.diagnostics = entries;
  result.source = source;
  return result;
}

/** Evaluates an inspection expression once using the ordinary native backend. */
ReplResult ReplSession.inspect_expression(
  ReplSession session, String expression, int depth, int limit) {
  with (session.inspect_depth = depth, session.inspect_limit = limit) {
    return session.submit("(" + expression.rstrip("; \t\r\n") + ");");
  }
}

/** Runs session cleanups before reclaiming persistent native storage. */
void ReplSession.close(ReplSession session) {
  auto (&session.storage) _discard_cleanups(session, 0);
  session.storage.destroy();
  session.storage = NULL;
  session.declarations.free();
  session.cleanups.free();
  session.names.cleanup();
  session.addresses.cleanup();
  session.descriptions.cleanup();
  session.internal.cleanup();
  xfree(session);
}
