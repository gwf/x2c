/* script units

   A script unit that defines `main` rejects top-level statements; one that
   does not runs them, in source order, inside a generated `main`. */

/* Retained token runs and the gap whose conditional directives precede the
   next form. `first` is the first statement, distinct from copied directives.
   A negative first index means no statement has been retained. */
static typedef struct ScriptParse {
  Compiler c;
  Array nodes, statements;
  int gap, first;
} ScriptParse;

/* File-scope forms establish effects before the retained statements parse.
   A macro may define main where the initial token scan saw none. Report that
   conflict outside recovery, as for the original script's entry point. */
module void _parse_script(Compiler c, Array nodes) {
  ScriptParse p = {.c = c, .nodes = nodes, .statements = [], .first = -1};
  Token conflict = NULL;
  $let(c.recovery_depth, c.recovery_depth + 1) {
    _append_preproc(c, nodes);
    while (c.peek(0) != <eof>) if (!_script_form(p)) break;
    if (p.first >= 0) {
      Token tokens = c.tokenizer.tokens;
      if ("main" in c.fn_defs) conflict = tokens + p.first;
      else {
        _push_conditionals(c, p.statements, p.gap, c.token - tokens);
        _append_script_main(c, p.statements);
        _parse_forms(c, nodes);
      }
    }
  }
  if (conflict) {
    c.token = conflict;
    _report_script_statement(c);
  }
}

// Script policy selects retained statements; ordinary parsing owns grammar.
static int _script_form(ScriptParse &p) {
  Compiler c = p.c;
  Token start = c.token, tokens = c.tokenizer.tokens;
  int begin = start - tokens, braces = c.braces.len();
  try {
    if (!c.script.defines_main) {
      _push_conditionals(c, p.statements, p.gap, begin);
      if (c.script_statement_starts()) _hoist(p, begin, tokens);
      else _top_level(c, p.nodes);
    }
    else {
      _reject_statement(c);
      _top_level(c, p.nodes);
    }
    p.gap = _end_index(c, tokens);
    _append_preproc(c, p.nodes);
    _debug_tokens(start, c.token);
  }
  catch %(malformed (category ?category) *): {
    (void) category;
    if (!_recover_form(c, start, braces)) return 0;
    p.gap = _end_index(c, c.tokenizer.tokens);
    _append_preproc(c, p.nodes);
    return c.peek(0) != <eof>;
  }
  return 1;
}

static void _hoist(ScriptParse &p, int begin, Token tokens) {
  p.c.skip_script_statement();
  p.statements.push(begin);
  p.statements.push(_end_index(p.c, tokens));
  if (p.first < 0) p.first = begin;
}

module void _finish_script(Compiler c, List ast) {
  if (!c.script.defines_main && !c.error_count()) _check_script_locals(c, ast);
}

/** Skips a collected script statement, or diagnoses one beside `main`.
    Called after top-level directives establish source visibility.
*/
int Compiler.skip_collected_script_statement(Compiler c) {
  if (!c.script) return 0;
  if (!c.script.defines_main && c.script_statement_starts()) {
    c.skip_script_statement();
    return 1;
  }
  _reject_statement(c);
  return 0;
}

/** Moves past one run of a script unit's statement tokens, through a `;` or
    a closing `}` outside every bracket. A statement that ends early this
    way leaves its remainder as the next run, and runs are rejoined in order.
*/
void Compiler.skip_script_statement(Compiler c) {
  for (int depth = 0; c.peek(0) != <eof>;) {
    Symbol type = c.peek(0);
    if (type == <"$(">) {
      c.token = c.token.after_group();
      continue;
    }
    depth += type.group_step();
    c.next();
    if (depth <= 0 && (type == <;> || type == <"}">)) return;
  }
}

/* A script unit either defines `main` or runs its top-level statements, so
   a statement beside `main` is the one form it rejects. */
static void _reject_statement(Compiler c) {
  if (c.script && c.script.defines_main && c.script_statement_executes())
    _report_script_statement(c);
}

static void _report_script_statement(Compiler c) {
  $fail.compiler_script_main(c, c.token);
}

/* A file-scope conditional directive also governs the statements it
   surrounds, so a copy of each joins the statement runs in source order and
   the script body keeps the file's conditional structure. */
static void _push_conditionals(
  Compiler c, Array statements, int first, int end) {
  Token tokens = c.tokenizer.tokens;
  for (int i = first; i < end; i++) {
    Token token = tokens + i;
    if (token.type != <preproc> ||
        !Compiler.preproc_conditional_kind(token.text))
      continue;
    statements.push(i);
    statements.push(i + 1);
  }
}

/* A script unit's `main` is ordinary source the parser reads after the last
   top-level form: this template with the statement runs, in source order,
   in place of `x2c_script_statements`. The statements run in their own
   function, so the `try` that reports an uncaught error leaves their locals
   ordinary. A failed command's status becomes the exit status; any other
   uncaught error exits with 1. */
static String script_main =
%"static int x2c_script(int argc, char **argv, List args) {
  (void) argc, (void) argv, (void) args;
  x2c_script_statements
  return 0;
}
int main(int argc, char **argv) {
  try {
    return x2c_script(argc, argv, Args.from_argv(argc, argv));
  }
  catch %(cmd-fail (command ?command) (status ?status) *): {
    fprintf(stderr, \"%s: command %s failed with status %ld\\n\",
            argv[0], command.repr().str(), status.integer());
    return (int) status.integer();
  }
  catch %(?code *detail): {
    fprintf(stderr, \"%s: %s %s\\n\",
            argv[0], code, detail.repr().str());
    return 1;
  }
}
";

/* Replaces the token stream with a copy that ends in the script's `main`.
   The copy keeps every consumed token at its index, so recorded token
   indices stay valid, and drops the trivia already read before end of file.
   `statements` holds each run's first and past-the-end token index. */
static void _append_script_main(Compiler c, Array statements) {
  Token tokens = c.tokenizer.tokens, eof = c.token;
  long kept = _end_index(c, tokens);
  Token first = tokens + statements[0].integer();
  Bytes stream = Bytes.new(sizeof(struct Token));
  stream = stream.append(tokens, kept);
  Tokenizer template = Tokenizer.new(script_main, <x2c>);
  template.scan();
  for (Token token = template.tokens; token.type != <eof>; token++) {
    if (token.text == "x2c_script_statements")
      stream = _append_runs(stream, tokens, statements);
    else stream = _append_placed(stream, token, first);
  }
  stream = stream.append(eof, 1);
  c.tokenizer.tokens = stream;
  c.token = Token.skip_trivia((Token) stream + kept);
}

static Bytes _append_runs(Bytes stream, Token tokens, Array statements) {
  for (int i = 0; i < statements.len(); i += 2) {
    long start = statements[i];
    long end = statements[i + 1];
    stream = stream.append(tokens + start, end - start);
  }
  return stream;
}

/* A template token takes the first statement's position with no length, so
   a diagnostic about it names the script without reading past its text. */
static Bytes _append_placed(Bytes stream, Token token, Token first) {
  struct Token placed = *token;
  placed.line = first.line;
  placed.col = first.col;
  placed.pos = first.pos;
  placed.len = 0;
  return stream.append(&placed, 1);
}

/* A script's functions cannot see the variables declared among its
   statements, which are locals of `x2c_script`. C would report such a name
   as undeclared; this names the cause and the `static` spelling that
   shares it. */
static void _check_script_locals(Compiler c, List ast) {
  Map locals = _script_locals(ast);
  if (!locals.len()) return;
  foreach (List node, ast) match (node)
    case %(function ? (bind (binding ? ?(String function)) ?)
           (block *items)):
      if (function != "x2c_script" && function != "main")
        _check_local_uses(c, items, locals);
}

static Map _script_locals(List ast) {
  Map locals = {};
  foreach (List node, ast) match (node)
    case %(function ? (bind (binding ? "x2c_script") ?)
        ${$source_block_content(%(*items))}):
      foreach (List item, items) match (item)
        case %(at ? (declare ? (bindings *bindings))):
          foreach (List binding, bindings) match (binding)
            case %(!or (bind (binding ? ?(String name)) ?)
                       (op = (bind (binding ? ?(String name)) ?) ?)):
              locals[name] = 1;
  return locals;
}

static void _check_local_uses(Compiler c, List items, Map locals) {
  foreach (List item, items) match (item) case %(at ?origin ?statement):
    foreach (Var name, locals.keys()) {
      Var found;
      List bindings;
      int present = statement.list().try_search(
        %(expr () ${source_identifier_content(%((binding ? $name)))}),
        found, bindings);
      if (!present) continue;
      c.origin = origin;
      $fail.compiler_script_local(c, NULL, name);
    }
}
