/*  repl.x -- terminal supervisor for native library sessions

    Copyright (c) 2026 Gary William Flake.
*/
#pragma once
#include "cli/cli.x"
#include "repl-types.x"
#include "repl-input.x"
#include "repl-worker.x"
#include "args.x"
#include "datum.x"
#include "path.x"
#include <limits.h>
#include <signal.h>
#include <stdio.h>
#include <unistd.h>

typedef struct ReplOptions {
  int dump, stats, verbose_stats;
  List arguments;
} ReplOptions;

/** Reads reporting options without building or evaluating a saved session. */
ReplOptions repl_reporting_options(List arguments) {
  ReplOptions options = {.arguments = arguments};
  foreach (String argument, arguments) {
    if (argument == "--") break;
    if (argument == "--dump") options.dump = 1;
    else if (argument == "--stats") options.stats = 1;
    else if (argument == "--verbose-stats") options.verbose_stats = 1;
  }
  return options;
}

static struct ReplCommand {
  String spelling, synopsis, description;
  Symbol argument;
};

static const struct ReplCommand _commands[] = {
  {":help", ":help [COMMAND]", "Show commands or one command's usage.", <command>},
  {":symbols", ":symbols [--all] [--kind KIND] [--file \"PATH\"] [PREFIX]",
   "Browse visible functions, types, values, and macros.", <symbol>},
  {":info", ":info NAME_OR_EXPRESSION", "Show a declaration or expression type without running it.", <name>},
  {":source", ":source NAME", "Show the source snapshot of a declaration.", <name>},
  {":members", ":members TYPE_OR_EXPRESSION", "Show fields, methods, and related C functions.", <name>},
  {":inspect", ":inspect [--depth N] [--limit N] EXPRESSION", "Evaluate once and inspect its typed result.", <name>},
  {":files", ":files", "Show loaded roots and native build configuration.", <none>},
  {":load", ":load \"PATH\" ...", "Load source/header roots; start a fresh session on success.", <path>},
  {":reload", ":reload", "Rebuild current roots; start fresh on success.", <none>},
  {":reset", ":reset", "Start fresh from the last successful program snapshot.", <none>},
  {":save", ":save \"PATH\"", "Save successful submissions and launch settings for replay.", <path>},
  {":replay", ":replay \"PATH\"", "Start fresh and explicitly rerun a saved transcript.", <path>},
  {":stats", ":stats [verbose]", "Show native worker allocation statistics.", <statmode>},
  {":ast", ":ast NAME", "Show a prompt definition's typed AST.", <name>},
  {":lowered", ":lowered NAME", "Explain native submission execution.", <name>},
  {":cancel", ":cancel", "Discard incomplete input.", <none>},
  {":quit", ":quit", "Run session cleanup and leave the playground.", <none>}
};

static struct ReplClient {
  ReplOptions options;
  ReplWorker worker;
  ReplInput input;
  List roots;
  String snapshot;
  Array transcript;
  String pending, directory, artifact;
  int interactive, failed, quit, replaying;
};

static int _blank(unsigned char c) => c == ' ' || c == '\t' || c == '\r' || c == '\n';

static String _word(String &text) {
  text = text.lstrip(NULL);
  size_t end = 0;
  while (end < text.len() && !_blank(text[end])) end++;
  String word = text[:end];
  text = text[end:].lstrip(NULL);
  return word;
}

static const struct ReplCommand *_command(String spelling) {
  for (size_t i = 0; i < sizeof(_commands) / sizeof(*_commands); i++)
    if (_commands[i].spelling == spelling) return _commands + i;
  return NULL;
}

static int _help(String command) {
  if (command) {
    if (!command.startswith(":")) command = ":" + command;
    const struct ReplCommand *row = _command(command);
    if (!row) {
      fprintf(stderr, "unknown command: %s\n", command);
      return 0;
    }
    printf("%s\n  %s\n", row->synopsis, row->description);
    return 1;
  }
  puts("Enter C or x2c declarations and statements with semicolons.\n"
       "Each executable submission compiles to native code.\n\n"
       "Explore");
  for (size_t i = 0; i < sizeof(_commands) / sizeof(*_commands); i++) {
    if (_commands[i].spelling == ":files") puts("\nLoad and repeat");
    if (_commands[i].spelling == ":stats") puts("\nInspect execution and control input");
    printf("  %-12s %s\n", _commands[i].spelling, _commands[i].description);
  }
  puts("\nTry a library\n"
       "  :load \"points.c\"\n"
       "  :symbols point\n"
       "  :info point_new\n"
       "  Point *p = point_new(1, 2);\n"
       "  point_move(p, 5);\n"
       "  :inspect *p\n"
       "  point_free(p);\n\n"
       "A successful load/reload clears all prompt and library state.\n"
       "A native crash or Ctrl-C during execution restarts that state.\n"
       "History survives; source is never replayed automatically.\n\n"
       "Tab completes names and paths; a second Tab lists choices.\n"
       "Arrow keys recall history. Ctrl-C cancels an edit; Ctrl-D exits an empty edit.\n"
       "Use :help COMMAND for its arguments.");
  return 1;
}

static List _paths(String argument) {
  Tokenizer tokens = auto Tokenizer.new(argument, <x2c>);
  tokens.scan();
  if (tokens.status() != <ok>) return NULL;
  Array paths = [];
  for (Token token = tokens.next(); token.type != <eof>; token = tokens.next()) {
    if (token.type != <lit-char*>) return NULL;
    paths.push(token.text.parse());
  }
  return paths.list_free();
}

static void _artifact_remove(String directory) {
  if (directory) {
    try ((Path) directory).remove_tree();
    catch %(io-fail *): {}
  }
}

static void _record(struct ReplClient &client, String source) {
  if (!client.replaying) client.transcript.push(source);
}

static int _replace(
  struct ReplClient &client, List roots, String snapshot, List requested, int announce) {
  ReplWorker candidate = repl_worker_start((ReplWorkerStart) {
    .arguments = client.options.arguments, .roots = roots, .requested = requested,
    .snapshot = snapshot, .interactive = client.interactive,
    .previous = client.worker, .input = client.input
  });
  if (candidate.failure) {
    fprintf(stderr, "session unchanged: %s\n", candidate.failure);
    repl_worker_close(candidate);
    return 0;
  }
  ReplWorker previous = client.worker;
  String previous_artifact = client.artifact;
  client.worker = candidate;
  client.roots = candidate.roots;
  client.snapshot = candidate.snapshot;
  client.artifact = candidate.directory;
  client.pending = "";
  if (announce) puts("started fresh session; cleared all prompt and library state");
  if (previous) repl_worker_close(previous);
  if (previous_artifact != client.artifact) _artifact_remove(previous_artifact);
  return 1;
}

static int _recover(struct ReplClient &client, String reason) {
  fprintf(stderr, "%s; all live session state was lost\n", reason);
  if (_replace(client, client.roots, client.snapshot, NULL, 0)) {
    fputs("started fresh session from the last successful program\n", stderr);
    return 1;
  }
  fputs("no running session; use :reload to rebuild the program\n", stderr);
  return 0;
}

static Map _call(struct ReplClient &client, Map message, int input) {
  Map response = repl_worker_call(client.worker, message, input);
  if (response) return response;
  String why = client.worker && client.worker.failure
             ? client.worker.failure : "no running native session";
  _recover(client, why);
  return NULL;
}

static int _show_response(struct ReplClient &client, Map response) {
  (void) client;
  if (!response) return 0;
  Symbol status = response[<status>];
  if (status == <ok>) {
    String text = response[<text>];
    if (text) printf("%s%s", text, text.endswith("\n") ? "" : "\n");
    return 1;
  }
  if (status == <defined>) {
    printf("defined %s\n", response[<name>]);
    return 1;
  }
  if (status == <value>) {
    printf("=> %s\n", response[<formatted>]);
    return 1;
  }
  if (status == <executed>) { puts("ok"); return 1; }
  if (status == <empty>) return 1;
  if (status == <incomplete>) return 1;
  String message = response[<message>];
  if (!message) message = response[<cause>];
  if (message) fprintf(stderr, "%s: %s\n",
                      status == <rejected> ? "rejected" : "failed", message);
  return 0;
}

static int _query(struct ReplClient &client, Map message, int input) =>
  _show_response(client, _call(client, message, input)) ? 1 : -1;

static int _submit(struct ReplClient &client, String source) {
  Map result = _call(client, {operation: <submit>, text: source}, 1);
  if (!result) return 0;
  if (client.options.dump) {
    String syntax = result[<syntax>];
    if (syntax) fprintf(stderr, "typed: %%%s\n", syntax);
    String artifact = result[<artifact>];
    if (artifact) fprintf(stderr, "native artifacts: %s\n", artifact);
  }
  if (result[<status>] == <incomplete>) return 2;
  return _show_response(client, result);
}

static int _symbols(struct ReplClient &client, String argument) {
  String prefix = "", path = "";
  Symbol kind = 0;
  int all = 0;
  while (argument) {
    String word = _word(argument);
    if (word == "--all") all = 1;
    else if (word == "--kind") {
      String name = _word(argument);
      if (!name) return 0;
      kind = Symbol.new(name);
      if (!(kind in %<<function native global value type macro constant>>)) return 0;
    }
    else if (word == "--file") {
      if (argument.startswith("\"")) {
        Tokenizer tokens = auto Tokenizer.new(argument, <x2c>);
        tokens.scan();
        Token token = tokens.next();
        if (token.type != <lit-char*>) return 0;
        path = token.text.parse();
        argument = argument[token.pos + token.len:].lstrip(NULL);
      }
      else path = _word(argument);
      if (!path) return 0;
    }
    else if (!prefix && !word.startswith("--")) prefix = word;
    else return 0;
  }
  return _query(client,
    {operation: <symbols>, text: "", prefix: prefix, kind: kind,
     path: path, all: all}, 0);
}

static int _number(String word, int &value) {
  if (!word) return 0;
  char *after = NULL;
  long n = strtol(word, &after, 10);
  if (!after || *after || n < 0 || n > INT_MAX) return 0;
  value = n;
  return 1;
}

static int _inspect(struct ReplClient &client, String argument) {
  int depth = 3, limit = 100;
  while (argument.startswith("--")) {
    String flag = _word(argument), number = _word(argument);
    if (flag == "--depth") { if (!_number(number, depth)) return 0; }
    else if (flag == "--limit") { if (!_number(number, limit) || !limit) return 0; }
    else return 0;
  }
  if (!argument) return 0;
  return _query(client,
    {operation: <inspect>, text: argument, depth: depth, limit: limit}, 1);
}

static int _save(struct ReplClient &client, String argument) {
  List paths = _paths(argument);
  if (paths.len() != 1) return 0;
  List saved = %(repl-session
    (directory $(client.directory))
    (arguments $(client.options.arguments))
    (submissions $(client.transcript.list())));
  Path path = paths.car();
  path.write_text(saved.repr() + "\n");
  printf("saved %s\n", path);
  return 1;
}

static int _line(struct ReplClient &client, String line);

static int _replay(struct ReplClient &client, String argument) {
  List paths = _paths(argument);
  if (paths.len() != 1) return 0;
  String text = ((Path) paths.car().str()).read_text();
  unsigned cursor = 0;
  Var data = void;
  if (!text.read_datum(cursor, data)) return 0;
  match (data) case %(repl-session (directory ?(String directory))
        (arguments ?(List arguments)) (submissions ?(List submissions))): {
    if (chdir(directory)) {
      fprintf(stderr, "cannot enter transcript directory: %s\n", directory);
      return 0;
    }
    ReplOptions previous = client.options;
    client.options = repl_reporting_options(arguments);
    if (!_replace(client, NULL, NULL, NULL, 1)) {
      client.options = previous;
      chdir(client.directory);
      return 0;
    }
    client.directory = directory;
    client.transcript.clear();
    client.pending = "";
    client.replaying = 1;
    int ok = 1;
    foreach (String source, submissions) {
      if (!_line(client, source)) { ok = 0; break; }
      client.transcript.push(source);
    }
    client.replaying = 0;
    return ok;
  }
  fputs("not a saved REPL transcript\n", stderr);
  return 0;
}

static int _control(
  struct ReplClient &client, const struct ReplCommand *command, String argument) {
  String operation = command->spelling;
  if (command->argument == <none> && argument) return 0;
  if (operation == ":quit") { client.pending = ""; client.quit = 1; return 1; }
  if (operation == ":cancel") { client.pending = ""; return 1; }
  if (operation == ":help") return _help(argument) ? 1 : -1;
  if (operation == ":files") {
    if (client.worker && client.worker.pid > 0)
      return _query(client, {operation: <files>, text: ""}, 0);
    foreach (String path, client.roots) printf("last successful root: %s\n", path);
    printf("launch arguments: %s\n", client.options.arguments.repr());
    return 1;
  }
  if (operation == ":symbols") return _symbols(client, argument);
  if (operation == ":inspect") return _inspect(client, argument);
  if (operation == ":save") return _save(client, argument);
  if (operation == ":replay") return _replay(client, argument);
  if (operation == ":reset")
    return _replace(client, client.roots, client.snapshot, NULL, 1) ? 1 : -1;
  if (operation == ":reload")
    return _replace(client, client.roots, NULL, NULL, 1) ? 1 : -1;
  if (operation == ":load") {
    List paths = _paths(argument);
    if (!paths) return 0;
    Array roots = auto [], requested = auto [];
    foreach (String path, client.roots) roots.push(path);
    foreach (String path, paths) {
      path = Path.resolved_absolute(path);
      requested.push(path);
      if (!(path in roots)) roots.push(path);
    }
    return _replace(client, roots, NULL, requested, 1) ? 1 : -1;
  }
  if (operation == ":stats") {
    if (argument && argument != "verbose") return 0;
    return _query(client,
      {operation: <stats>, text: "", verbose: argument == "verbose"}, 0);
  }
  if (!argument) return 0;
  Symbol query = Symbol.new(operation[1:]);
  return _query(client, {operation: query, text: argument}, 0);
}

static int _line(struct ReplClient &client, String line) {
  String text = line.strip(NULL);
  if (text.startswith(":")) {
    if (client.interactive) client.input.remember(line);
    String operation = _word(text);
    const struct ReplCommand *command = _command(operation);
    if (!command) {
      fprintf(stderr, "unknown command: %s\n", operation);
      return 0;
    }
    int result = _control(client, command, text);
    if (result <= 0) {
      if (!result) fprintf(stderr, "usage: %s\n", command->synopsis);
      return 0;
    }
    if (operation == ":load" || operation == ":reload" || operation == ":reset")
      _record(client, line);
    return 1;
  }
  client.pending += line + "\n";
  String submitted = client.pending;
  int result = _submit(client, submitted);
  if (result == 2) return 1;
  if (client.interactive)
    client.input.remember(submitted.remove_suffix("\n"));
  if (result) _record(client, submitted.remove_suffix("\n"));
  client.pending = "";
  return result;
}

static ReplInputCompletion _path_completion(String text, size_t cursor, size_t start) {
  while (start < cursor && _blank(text[start])) start++;
  int quoted = 0, closed = 0;
  for (size_t i = start; i < cursor; i++) {
    if (text[i] == '\\' && i + 1 < cursor) { i++; continue; }
    if (text[i] == '"') {
      quoted = !quoted;
      if (quoted) start = i + 1;
      closed = !quoted;
    }
    else if (!quoted && _blank(text[i])) start = i + 1, closed = 0;
  }
  if (closed) return (ReplInputCompletion) {.candidates = NULL};
  String prefix = String.new_len(text + start, cursor - start);
  Array candidates = [];
  foreach (Path path, ((Path) (prefix + "*")).glob()) {
    String spelling = (quoted ? "" : "\"") + path;
    spelling += path.is_dir() ? "/" : "\"";
    candidates.push(%(<name> $spelling));
  }
  return (ReplInputCompletion) {.start = start, .end = cursor,
                                .candidates = candidates.list_free()};
}

static ReplInputCompletion _literal_completion(
  String prefix, size_t start, size_t cursor, List choices, Symbol kind) {
  Array candidates = [];
  foreach (String choice, choices)
    if (choice.startswith(prefix)) candidates.push($(kind, choice));
  return (ReplInputCompletion) {.start = start, .end = cursor,
                                .candidates = candidates.list_free()};
}

static ReplInputCompletion _argument_completion(
  struct ReplClient &client, String command, String text, size_t cursor, size_t start) {
  String argument = text[start:cursor];
  if (command == ":help") {
    Array names = auto [];
    for (size_t i = 0; i < sizeof(_commands) / sizeof(*_commands); i++) {
      String spelling = _commands[i].spelling;
      names.push(argument.startswith(":") ? spelling : spelling[1:]);
    }
    return _literal_completion(argument, start, cursor, names, <command>);
  }
  if (command == ":symbols" || command == ":inspect") {
    while (argument.startswith("--")) {
      String flag = _word(argument);
      if (!argument && cursor && !_blank(text[cursor - 1]))
        return _literal_completion(flag, cursor - flag.len(), cursor,
          command == ":symbols" ? %("--all" "--kind" "--file")
                                 : %("--depth" "--limit"), <keyword>);
      if (flag == "--file") {
        Tokenizer paths = auto Tokenizer.new(argument, <x2c>);
        paths.scan();
        Token path = paths.next();
        size_t after = path.pos + path.len;
        if (paths.status() == <ok> && path.type == <lit-char*> &&
            after < argument.len() && _blank(argument[after])) {
          argument = argument[after:].lstrip(NULL);
          continue;
        }
        return _path_completion(text, cursor, cursor - argument.len());
      }
      if (flag == "--kind") {
        String kind = _word(argument);
        if (!argument && (!kind || !_blank(text[cursor - 1])))
          return _literal_completion(kind, cursor - kind.len(), cursor,
            %("function" "native" "global" "value" "type" "macro" "constant"),
            <keyword>);
      }
      else if (flag == "--depth" || flag == "--limit") (void) _word(argument);
      else if (flag != "--all") return (ReplInputCompletion) {.candidates = NULL};
    }
    start = cursor - argument.len();
  }
  Map result = _call(client,
    {operation: <complete>, text: argument, cursor: argument.len()}, 0);
  if (!result) return (ReplInputCompletion) {.candidates = NULL};
  return (ReplInputCompletion) {.start = start + result[<start>].integer(),
    .end = start + result[<end>].integer(), .candidates = result[<candidates>]};
}

static ReplInputCompletion _complete_input(void *raw, String text, size_t cursor) {
  struct ReplClient *client = raw;
  size_t first = 0;
  while (first < text.len() && _blank(text[first])) first++;
  if (first < text.len() && text[first] == ':') {
    size_t end = first;
    while (end < cursor && !_blank(text[end])) end++;
    String spelling = text[first:end];
    if (end == cursor) {
      Array candidates = [];
      for (size_t i = 0; i < sizeof(_commands) / sizeof(*_commands); i++)
        if (_commands[i].spelling.startswith(spelling))
          candidates.push(%(<command> $(_commands[i].spelling)));
      return (ReplInputCompletion) {.start = first, .end = cursor,
                                    .candidates = candidates.list_free()};
    }
    const struct ReplCommand *command = _command(spelling);
    if (!command) return (ReplInputCompletion) {.candidates = NULL};
    if (command->argument == <path>) return _path_completion(text, cursor, end);
    size_t start = end;
    while (start < cursor && _blank(text[start])) start++;
    if (command->argument == <statmode>)
      return (ReplInputCompletion) {.start = start, .end = cursor,
        .candidates = "verbose".startswith(text[start:cursor]) ? %((keyword "verbose")) : NULL};
    return _argument_completion(*client, spelling, text, cursor, start);
  }
  String source = client->pending + text;
  size_t offset = client->pending.len();
  Map result = _call(*client,
    {operation: <complete>, text: source, cursor: offset + cursor}, 0);
  if (!result || result[<start>].integer() < offset)
    return (ReplInputCompletion) {.candidates = NULL};
  List candidates = result[<candidates>];
  if (!offset && !text) {
    Array merged = [];
    for (size_t i = 0; i < sizeof(_commands) / sizeof(*_commands); i++)
      merged.push(%(<command> $(_commands[i].spelling)));
    foreach (Var row, candidates) merged.push(row);
    candidates = merged.list_free();
  }
  return (ReplInputCompletion) {
    .start = result[<start>].integer() - offset,
    .end = result[<end>].integer() - offset, .candidates = candidates};
}

/** Runs the terminal supervisor; native objects remain in its worker. */
int repl_run(CliRequest request, ReplOptions options) {
  struct sigaction previous_int, previous_pipe, action = {0};
  action.sa_handler = repl_worker_interrupt;
  sigemptyset(&action.sa_mask);
  sigaction(SIGINT, &action, &previous_int);
  action.sa_handler = SIG_IGN;
  sigaction(SIGPIPE, &action, &previous_pipe);
  defer {
    sigaction(SIGINT, &previous_int, NULL);
    sigaction(SIGPIPE, &previous_pipe, NULL);
  }
  struct ReplClient client = {
    .options = options, .interactive = isatty(STDIN_FILENO),
    .input = ReplInput.new(), .transcript = [], .pending = "",
    .directory = Path.absolute(".")
  };
  defer {
    if (client.worker) repl_worker_close(client.worker);
    if (client.interactive) client.input.save_history();
    client.input.close();
    client.transcript.free();
    _artifact_remove(client.artifact);
  }
  if (client.interactive) client.input.load_history();
  if (!_replace(client, request.inputs, NULL, NULL, 0)) return 1;
  if (client.interactive) puts("x2c library playground; :help for commands");
  while (!client.quit) {
    String line = NULL;
    if (client.interactive) {
      ReplInputResult read = client.input.read(
        client.pending ? "... " : "x2c> ", _complete_input, &client);
      if (read.status == <cancelled>) { client.pending = ""; continue; }
      if (read.status == <eof>) break;
      line = read.text;
    }
    else {
      line = Stdin.readline();
      if (!line) break;
      line = line.remove_suffix("\n");
    }
    int ok = 0;
    try ok = _line(client, line);
    catch %(?kind *details):
      fprintf(stderr, "failed: %s\n", cons(kind, details).repr());
    if (!ok) client.failed = 1;
    fflush(stdout);
  }
  if ((options.stats || options.verbose_stats) && client.worker && client.worker.pid) {
    Map result = _call(client,
      {operation: <stats>, text: "", verbose: options.verbose_stats}, 0);
    if (result && result[<status>] == <ok>)
      fprintf(stderr, "%s", result[<text>]);
  }
  if (client.pending) {
    fputs("incomplete input at EOF\n", stderr);
    return 1;
  }
  return !client.interactive && client.failed;
}
