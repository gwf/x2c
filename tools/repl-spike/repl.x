/*  repl.x -- terminal client for the incremental session spike

    Copyright (c) 2026 Gary William Flake.
*/
#include "session.x"
#include "diagnostics.x"
#include "lisp.x"
#include "file.x"
#include <stdio.h>
#include <unistd.h>
#include <string.h>

static void _help(void) {
  puts("Enter declarations or statements with semicolons.\n"
       ":help    show this help\n"
       ":symbols list session-defined names and kinds\n"
       ":ast NAME show a function's typed AST\n"
       ":lowered NAME show a function's lowered Lisp\n"
       ":cancel  discard incomplete input\n"
       ":quit    leave the session\n"
       "Options: --dump prints typed AST and lowered Lisp; --stats prints "
       "execution counters.");
}

static void _inspect(ReplSession session, String command) {
  Array words = [];
  defer words.free();
  foreach (String word, command.words()) words.push(word);
  String operation = words[0];
  if (operation == ":symbols") {
    if (words.len() != 1) fputs("usage: :symbols\n", stderr);
    else printf("%%%s\n", session.symbols().repr());
  }
  else if (operation == ":ast" || operation == ":lowered") {
    if (words.len() != 2) {
      fprintf(stderr, "usage: %s NAME\n", operation);
      return;
    }
    String name = words[1];
    match (session.inspect(name)) {
      case %(function (typed ?syntax) (lowered ?forms)): {
        if (operation == ":ast") printf("typed: %%%s\n", syntax.repr());
        else printf("lowered: %s\n", forms.repr());
        return;
      }
    }
    fprintf(stderr, "not a session function: %s\n", name);
  }
  else fprintf(stderr, "unknown command: %s\n", command);
}

int main(int argc, char **argv) {
  int dump = 0, stats = 0;
  for (int i = 2; i < argc; i++) {
    if (!strcmp(argv[i], "--dump")) dump = 1;
    else if (!strcmp(argv[i], "--stats")) stats = 1;
    else if (!strcmp(argv[i], "--help")) { _help(); return 0; }
    else {
      fprintf(stderr, "unknown option: %s; use --help\n", argv[i]);
      return 2;
    }
  }
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
  ReplSession session = ReplSession.new(unit.compiler);
  String pending = "", line;
  int interactive = isatty(STDIN_FILENO);
  unit.compiler.macro_lisp.call_budget(1000000);
  if (interactive) puts("x2c research REPL; :help for commands");
  while (1) {
    if (interactive) {
      printf("%s", pending.len() ? "... " : "x2c> ");
      fflush(stdout);
    }
    line = Stdin.readline();
    if (!line) break;
    String command = line.strip(NULL);
    if (command == ":quit") { pending = ""; break; }
    if (command == ":cancel") { pending = ""; continue; }
    if (command == ":help") { _help(); continue; }
    if (command.startswith(":")) {
      _inspect(session, command);
      fflush(stdout);
      continue;
    }
    pending += line + "\n";
    ReplResult result = session.submit(pending);
    if (dump && result.syntax) fprintf(stderr, "typed: %s\n", result.syntax.repr());
    if (dump && result.lowered) fprintf(stderr, "lowered: %s\n", result.lowered.repr());
    $let(unit.compiler.text, result.source) {
      foreach (Var entry, result.diagnostics)
        unit.compiler.print_diagnostic(entry);
    }
    switch (result.status) {
      case <defined>: printf("defined %s\n", result.name); break;
      case <value>: printf("=> %s\n", result.value.repr()); break;
      case <executed>: puts("ok"); break;
      case <rejected>:
        if (result.message) fprintf(stderr, "rejected: %s\n", result.message);
        break;
      case <failed>:
        fprintf(stderr, "evaluation failed: %s\n", result.cause.repr());
        break;
    }
    if (result.status != <incomplete>) pending = "";
    fflush(stdout);
  }
  if (stats) {
    LispAutoStats stats = unit.compiler.macro_lisp.auto_stats();
    fprintf(stderr, "Lisp calls=%ld machine entries=%ld machine errors=%ld\n",
            stats.invocations, stats.machine_entries, stats.machine_errors);
  }
  if (pending.len()) { fputs("incomplete input at EOF\n", stderr); return 1; }
  return 0;
}
