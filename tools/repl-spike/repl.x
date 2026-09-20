/*  repl.x -- local research adapter for the compiler's Lisp lowering

    Copyright (c) 2026 Gary William Flake.

    The unit Context stays open: compiler syntax and evaluated values borrow
    its storage. No source or earlier expression is replayed between inputs.
*/
#include "frontend.x"
#include "comptime.x"
#include "parse.x"
#include "diagnostics.x"
#include "lisp.x"
#include "file.x"
#include <stdio.h>
#include <unistd.h>
#include <string.h>

static List _bare(List node) {
  match (node) case %(at ? ?inner): return inner;
  return node;
}

static List _thunk(List items) =>
  %(function (int)
    (bind (binding -1 "__repl_eval") ((fnmod (params))))
    (block @items));

static void _refuse(String why) { raise %(spike (why $why)); }

// Native C can resolve an untyped name later; this evaluator cannot.
static void _require_bound(Var syntax) {
  match (syntax)
    case %(expr () (ident (binding ? ?name))):
      _refuse(%"unresolved identifier: $name");
  if (syntax is <list>) foreach (Var child, syntax.list())
    _require_bound(child);
}

static List _initializers(List node, Map names, Array added) {
  Array statements = [];
  match (node) {
    case %(declare ?spec (bindings *bindings)): {
      foreach (List item, bindings) {
        match (item) {
          case %(op = (bind (binding ?id ?(String name)) ()) ?value): {
            if (names.contains(name) || added.contains(name) ||
                name.startswith("__repl_"))
              _refuse("redeclaration is disabled; use assignment");
            added.push(name);
            statements.push(%(stmnt
              (expr $spec (op = (expr $spec (ident (binding $id $name)))
                               $value))));
            continue;
          }
        }
        _refuse("top-level values need an initializer and a simple binding");
      }
      return _thunk(statements);
    }
  }
  _refuse("this top-level form is outside the spike");
  return NULL;
}

static List _result_body(List fn, int *prints) {
  match (fn) {
    case %(function ? ? (block *body)): {
      Array items = body;
      if (items.len()) {
        List last = _bare(items[items.len() - 1]);
        match (last) {
          case %(stmnt (expr ?spec ?value)): {
            int effect = 0;
            match (value) {
              case %(op ?operator *):
                effect = %("=" "++" "--" "+=" "-=" "*=" "/=" "%="
                           "&=" "|=" "^=" "<<=" ">>=").contains(operator.str());
              case %(postfix *): effect = 1;
            }
            if (!effect) {
              items[items.len() - 1] = %(return $spec (expr $spec $value));
              *prints = 1;
            }
          }
        }
      }
      return _thunk(items);
    }
  }
  return fn;
}

// Returns 0 for incomplete syntax, 1 for an accepted input, -1 for rejection.
static int _submit(Compiler c, String source, Map names, int dump) {
  c.diagnostics.reset();
  SymTxn transaction = c.begin_semantic_transaction();
  int scope_count = c.sym.scope_count();
  SymScope params = c.params;
  defer {
    while (c.sym.scope_count() > scope_count) (void) c.sym.pop_scope();
    c.params = params;
    transaction.rollback();
  }
  Array added = [];
  List fn = NULL;
  String function_name = NULL;
  int execute = 0, prints = 0, end = source.len();
  try {
    c.tokenize(source);
    if (c.tokenizer.status() == <incomplete>) return 0;
    for (Token token = c.tokenizer.tokens; token.type != <eof>; token++) {
      if (token.type == <preproc> || token.type == <"$(">)
        _refuse("preprocessor and direct Lisp input are unsupported");
      if (token.type == <const> || token.type == <volatile>)
        _refuse("const and volatile need native checks outside this spike");
    }
    if (c.peek(0) == <eof>) return 1;
    if (c.peek(0) == <import> || c.peek(0) == <protocol> ||
        c.peek(0) == <"$("> || c.meta_form_is_definition() ||
        c.macro_form_is_definition() || c.keyword_form_is_definition())
      _refuse("compiler-session definitions are outside the spike");
    if (c.peek(0) == <typedef> || c.peek(0) == <struct> ||
        c.peek(0) == <union> || c.peek(0) == <enum> ||
        c.peek(0) == <extern> || c.peek(0) == <static>)
      _refuse("type and storage declarations are outside the spike");
    int declaration = c.test_declaration();
    if (!declaration) {
      String prefix = "void __repl_eval(void) {\n";
      end += prefix.len();
      c.tokenize(prefix + source + "\n}");
    }
    List node = c.parse_top_level();
    if (c.peek(0) != <eof>) _refuse("submit one top-level item at a time");
    if (!declaration) {
      fn = _result_body(node, &prints);
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
        fn = _initializers(node, names, added);
        execute = 1;
      }
    }
    _require_bound(fn);
  }
  catch %(malformed (category ?category) *): {
    int needs_tokens = category == <parse>;
    foreach (List entry, c.diagnostics())
      if (entry.get(<message>) == "expected scalar type") needs_tokens = 1;
    if (needs_tokens && c.token.pos >= end) return 0;
    foreach (Var entry, c.diagnostics()) c.print_diagnostic(entry);
    return -1;
  }
  catch %(spike (why ?why)): {
    fprintf(stderr, "rejected: %s\n", why);
    return -1;
  }
  if (dump) fprintf(stderr, "typed: %s\n", fn.repr());
  List forms = c.lower_comptime(fn);
  if (!forms) {
    fprintf(stderr, "unsupported: %s\n", c.lower_declined());
    return -1;
  }
  if (dump) fprintf(stderr, "lowered: %s\n", forms.repr());
  foreach (Var form, forms) c.macro_lisp.eval(form);
  // Publish bindings before execution: runtime failure keeps earlier effects.
  if (function_name || added.len()) {
    transaction.commit();
    foreach (String name, added) names[name] = 1;
  }
  if (execute) {
    try {
      Var result = c.macro_lisp.eval(%(__repl_eval));
      if (prints) printf("=> %s\n", result.repr());
      else puts("ok");
    }
    catch %(?cause *details): {
      fprintf(stderr, "evaluation failed: %s\n", cons(cause, details).repr());
      return -1;
    }
  }
  else printf("defined %s\n", function_name);
  return 1;
}

int main(int argc, char **argv) {
  x2c_initialize_environment(argv[0]);
  CliRequest request = Scope.calloc(1, sizeof(struct CliRequest));
  request.command = <translate>;
  Frontend frontend = Frontend.new(request);
  if (!frontend.preload_macro_libraries()) return 1;
  ParsedUnit unit;
  if (!frontend.open(String.new(argv[1]), &unit)) {
    foreach (Var entry, unit.compiler.diagnostics())
      unit.compiler.print_diagnostic(entry);
    return 1;
  }
  defer unit.close();
  unit.compiler.filename = "<repl>";
  Map names = {};
  String pending = "", line;
  int interactive = isatty(STDIN_FILENO);
  int dump = argc > 2 && !strcmp(argv[2], "--dump");
  unit.compiler.macro_lisp.call_budget(1000000);
  if (interactive) puts("x2c research REPL; :quit, :cancel; semicolons required");
  while (1) {
    if (interactive) {
      printf("%s", pending.len() ? "... " : "x2c> ");
      fflush(stdout);
    }
    line = Stdin.readline();
    if (!line) break;
    if (line.strip(NULL) == ":quit") break;
    if (line.strip(NULL) == ":cancel") { pending = ""; continue; }
    pending += line + "\n";
    int status = _submit(unit.compiler, pending, names, dump);
    if (status) pending = "";
    fflush(stdout);
  }
  if (argc > 2 && !strcmp(argv[2], "--stats")) {
    LispAutoStats stats = unit.compiler.macro_lisp.auto_stats();
    fprintf(stderr, "Lisp calls=%ld machine entries=%ld machine errors=%ld\n",
            stats.invocations, stats.machine_entries, stats.machine_errors);
  }
  if (pending.len()) { fputs("incomplete input at EOF\n", stderr); return 1; }
  return 0;
}
