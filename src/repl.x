/*  repl.x -- terminal client for persistent compiler submissions

    Copyright (c) 2026 Gary William Flake.
*/
#pragma once
#include "cli.x"

#pragma private
#include "repl-session.x"
#include "diagnostics.x"
#include "lisp.x"
#include "file.x"
#include <stdio.h>
#include <unistd.h>

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

static int _inspect(ReplSession session, String command) {
  Array words = [];
  defer words.free();
  foreach (String word, command.words()) words.push(word);
  String operation = words[0];
  if (operation == ":symbols") {
    if (words.len() != 1) fputs("usage: :symbols\n", stderr);
    else {
      printf("%%%s\n", session.symbols().repr());
      return 1;
    }
  }
  else if (operation == ":ast" || operation == ":lowered") {
    if (words.len() != 2) {
      fprintf(stderr, "usage: %s NAME\n", operation);
      return 0;
    }
    String name = words[1];
    match (session.inspect(name)) {
      case %(function (typed ?syntax) (lowered ?forms)): {
        if (operation == ":ast") printf("typed: %%%s\n", syntax.repr());
        else printf("lowered: %s\n", forms.repr());
        return 1;
      }
    }
    fprintf(stderr, "not a session function: %s\n", name);
  }
  else fprintf(stderr, "unknown command: %s\n", command);
  return 0;
}

/** Runs the experimental REPL on stdin. Piped input continues after errors
    and exits with status one if any submission or command failed. Interactive
    errors leave the session usable; SIGINT retains its process-exit action. */
int repl_run(CliRequest request) {
  Frontend frontend = Frontend.new(request);
  if (!frontend.preload_macro_libraries()) return 1;
  ParsedUnit unit;
  int opened = frontend.open_session(&unit);
  defer unit.close();
  if (!opened) {
    foreach (Var entry, unit.compiler.diagnostics())
      unit.compiler.print_diagnostic(entry);
    return 1;
  }
  ReplSession session = ReplSession.new(unit.compiler);
  String pending = "", line;
  int interactive = isatty(STDIN_FILENO), failed = 0;
  unit.compiler.macro_lisp.call_budget(1000000);
  if (interactive) puts("x2c experimental REPL; :help for commands");
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
      if (!_inspect(session, command)) failed = 1;
      fflush(stdout);
      continue;
    }
    pending += line + "\n";
    ReplResult result = session.submit(pending);
    if (request.repl_dump && result.syntax)
      fprintf(stderr, "typed: %%%s\n", result.syntax.repr());
    if (request.repl_dump && result.lowered)
      fprintf(stderr, "lowered: %s\n", result.lowered.repr());
    $let(unit.compiler.text, result.source) {
      foreach (Var entry, result.diagnostics)
        unit.compiler.print_diagnostic(entry);
    }
    switch (result.status) {
      case <defined>: printf("defined %s\n", result.name); break;
      case <value>: printf("=> %s\n", result.value.repr()); break;
      case <executed>: puts("ok"); break;
      case <rejected>:
        failed = 1;
        if (result.message) fprintf(stderr, "rejected: %s\n", result.message);
        break;
      case <failed>:
        failed = 1;
        fprintf(stderr, "evaluation failed: %s\n", result.cause.repr());
        break;
    }
    if (result.status != <incomplete>) pending = "";
    fflush(stdout);
  }
  if (request.repl_stats) {
    LispAutoStats stats = unit.compiler.macro_lisp.auto_stats();
    fprintf(stderr, "Lisp calls=%ld machine entries=%ld machine errors=%ld\n",
            stats.invocations, stats.machine_entries, stats.machine_errors);
  }
  if (pending.len()) { fputs("incomplete input at EOF\n", stderr); return 1; }
  return !interactive && failed;
}
