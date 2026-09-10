/*  cstar-verify.x -- verify the annotated functions of one x2c file.

    The tool parses the file with the real compiler frontend, reads the
    annotation records `cstar.xmacro` left in the compile-time Lisp session,
    proves that each recorded body is the body the compiler kept, renders the
    admitted subset as a proof program, builds it with the ordinary x2c
    driver against the cstar package, and runs it against its own prover
    session.

    Nothing is cached: every run uses a fresh directory and a fresh prover
    session, and its result describes that run, not the file.

      0  verified            every requested function, no obligation left
      1  obligations remain
      2  unsupported         refused before any proof ran
      3  not completed       build failure, prover failure, timeout, a step
                              the engine refused, or a short inventory
*/

#include "frontend.x"
#include "utils.x"
#include "adapter.x"

#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#pragma private

typedef struct Options {
  String input, root, x2c, packages, cstar_home;
  List include_dirs;
  int port, emit, keep, timeout;
} *Options;

static void _preprocessor_errors(String text) {
  Stderr.printf("%s", text);
}

static int _open_input(Frontend frontend, String filename, ParsedUnit *unit) {
  int ok = frontend.start(filename, unit);
  if (ok) {
    unit->compiler.own_diagnostics();
    ok = unit.collect(frontend) && unit.parse();
  }
  if (ok) return 1;
  if (!unit->compiler.diagnostics.has_emitter())
    foreach (Var entry, unit->compiler.diagnostics())
      unit->compiler.print_diagnostic(entry);
  unit.close();
  return 0;
}

/** Removes every `(at ID NODE)` wrapper so two spellings of one body compare
    by structure alone. */
static Var _strip(Var value) {
  if (value is not <list>) return value;
  List node = value;
  match (node)
    case %(at ? ?inner): return _strip(inner);
  List result = %();
  foreach (Var child, node) result = cons(_strip(child), result);
  return result.reverse();
}

static List _strip_items(List items) {
  List result = %();
  foreach (Var item, items) result = cons(_strip(item), result);
  return result.reverse();
}

/** Returns `(DEFINITION BODY)` for the top-level function named `name`. */
static List _definition(List ast, String name) {
  foreach (List node, ast)
    match (node)
      case %(function ? (bind (binding ? (!is ?spelling type string)) ?)
             (!set ?body (block *))):
        if (((String) spelling) == name) return %($node $body);
  return NULL;
}

// the proof program

static String _contents(String path) {
  if (access(path, F_OK) != 0) return NULL;
  File opened = File.open(path, %"r");
  defer opened.close();
  return opened.string();
}

static String _directory(String path) {
  int slash = path.rfind(%"/");
  return slash > 0 ? path[:slash] : %".";
}

/** Returns the text of the companion helper file, which is spliced into the
    proof program rather than included: an `#include` of another `.x` unit
    would make it a separately translated unit the proof program cannot
    link. */
static String _companion(String input) {
  int dot = input.rfind(%".x");
  String path = %"${dot > 0 ? input[:dot] : input}.proofs.x";
  if (access(path, F_OK) != 0) return NULL;
  return %"// ${path}\n${_contents(path)}";
}

/** Renders the proof program and the `(name line)` row of every function it
    verifies, or NULL after reporting why the file cannot be verified. */
static List _program(Options options, ParsedUnit parsed, List records) {
  Map annotations = %{};
  foreach (List record, records)
    match (record)
      case %((!or assert invariant invariant_sl proof helper) ?id *):
        annotations[id] = record;
  Adapter adapter = Adapter.new(parsed.compiler, annotations);
  Array functions = %[];
  foreach (List record, records)
    match (record)
      case %(function ?name ? ? ? ? ?line ? ? ?erased): {
        String spelling = name.str();
        List definition = _definition(parsed.ast, spelling);
        if (!definition) {
          Stderr.printf("cstar-verify: %s: no function named %s survived "
                        "parsing\n", options.input, spelling);
          return NULL;
        }
        if (!List.equal(_strip_items(erased.list()),
                        _strip_items(definition.cadr().list().cdr()))) {
          Stderr.printf("cstar-verify: %s: the body recorded for %s is not "
                        "the body the compiler kept; $cstar.verify must be "
                        "the outermost decorator\n", options.input, spelling);
          return NULL;
        }
        functions.push(%($spelling $line));
        adapter.function(record, definition.car().list());
      }
  if (adapter.failure()) {
    Stderr.printf("cstar-verify: %s\n", adapter.failure());
    return NULL;
  }
  if (!functions.len()) {
    Stderr.printf("cstar-verify: %s: no $cstar.verify annotation\n",
                  options.input);
    return NULL;
  }
  Array text = %[];
  text.push(%"/*  Generated by cstar-verify from ${options.input}.\n" +
            %"    Do not edit; every run renders it again. */\n");
  text.push(%"import \"cstar\" with Cstar;\n");
  String companion = _companion(options.input);
  if (companion) text.push(companion);
  text.push(adapter.text());
  text.push(%"int main(void) {");
  text.push(%"  Cstar cstar = Cstar.open(${functions.len()}, " +
            %"\"${options.input}\");");
  if (adapter.uses_arrays()) text.push(%"  cstar.load_arrays();");
  foreach (List function, functions)
    text.push(%"  _verify_${function.car().str()}(cstar);");
  text.push(%"  return cstar.finish();");
  text.push(%"}");
  return %(${text.join(%"\n") + %"\n"} ${functions.list_free()});
}

/** Renders the proof program while the parsed unit is still open, and
    exports the result past the unit's pools. */
static List _render(Options options) {
  CliRequest request = Scope.calloc(1, sizeof(struct CliRequest));
  request.command = <translate>;
  request.include_dirs = options.include_dirs;
  Frontend frontend = Frontend.new(request);
  frontend.preprocessor_errors = _preprocessor_errors;
  ParsedUnit parsed;
  if (!_open_input(frontend, options.input, &parsed)) return NULL;
  Var stored;
  List rendered = NULL;
  if (!Lisp.try_get(parsed.compiler.macro_lisp, %"cstar.records", &stored))
    Stderr.printf("cstar-verify: %s: no cstar annotations\n", options.input);
  else rendered = _program(options, parsed, stored.list().reverse());
  if (rendered) rendered = parsed.context.export(rendered).list();
  parsed.close();
  return rendered;
}

// running children

static char **_argv(List words) {
  char **argv = Scope.calloc(words.len() + 1, sizeof(char *));
  int index = 0;
  foreach (Var word, words) argv[index++] = word.str();
  return argv;
}

/** Runs one child to completion, or kills it after `seconds` and reports
    `-2`. A local start failure reports `-1`. */
static int _run(List words, int seconds, String *output, String *errors) {
  ChildProcess child = process_start(_argv(words), 1);
  if (child.pid < 0) {
    Stderr.printf("cstar-verify: %s\n", child.start_error);
    return -1;
  }
  struct timespec pause = { 0, 20 * 1000 * 1000 };
  for (int waited = 0; waited < seconds * 50; waited++) {
    if (child.ready()) return child.wait(output, errors);
    nanosleep(&pause, NULL);
  }
  kill((pid_t) child.pid, SIGKILL);
  child.wait(output, errors);
  return -2;
}

/** Starts a prover session and returns it once its log reports the port it
    listens on. macOS Control Center also binds 7000, so readiness comes from
    the log line and never from a port probe. */
static ChildProcess _server(Options options, String directory, int port) {
  String log = %"${directory}/server.log";
  String command = %"exec '${options.cstar_home}/bin/hol_light_server' " +
                   %">'${log}' 2>&1";
  setenv("LCF_SERVER_PORT", %"${port}", 1);
  ChildProcess child = process_start(_argv(%("/bin/sh" "-c" $command)), 0);
  if (child.pid < 0) {
    Stderr.printf("cstar-verify: %s\n", child.start_error);
    return NULL;
  }
  String wanted = %"listening on 127.0.0.1:${port}";
  struct timespec pause = { 0, 100 * 1000 * 1000 };
  for (int waited = 0; waited < 900; waited++) {
    String text = _contents(log);
    if (text && text.find(wanted) >= 0) return child;
    if (child.ready()) break;
    nanosleep(&pause, NULL);
  }
  Stderr.printf("cstar-verify: hol_light_server did not report a listening "
                "port; see %s\n", log);
  kill((pid_t) child.pid, SIGKILL);
  child.wait(NULL, NULL);
  return NULL;
}

// the report

/** Selects the final report rather than any earlier snapshot a helper
    printed. The backend renders its JSON on one line. */
static String _final_report(String output) {
  String marker = %"\nCSTAR REPORT: ";
  int start = output ? output.rfind(marker) : -1;
  if (start < 0) return NULL;
  start += marker.len();
  int end = output.find_within(%"\n", start, -1);
  return end < 0 ? NULL : output[start:end];
}

/** Returns `(LINE TEXT)` for each remaining verification condition. */
static List _conditions(String report) {
  Array found = %[];
  int cursor = 0, length = report.len();
  while (1) {
    int at = report.find_within(%"\"line\":", cursor, -1);
    if (at < 0) break;
    int digits = at + 7, end = digits;
    while (end < length && report[end] >= '0' && report[end] <= '9') end++;
    int marker = report.find_within(%"\"condition\":\"", end, -1);
    if (marker < 0) break;
    int start = marker + 13, stop = start;
    while (stop < length && report[stop] != '"') stop++;
    int line = atoi(report[digits:end]);
    String text = report[start:stop];
    found.push(%($line $text));
    cursor = stop;
  }
  return found.list_free();
}

/** Prints one line per requested function, and its remaining obligations.
    A condition belongs to the last function that starts at or before it.
    Only a clean final verdict establishes verification; the full backend
    report preserves trust obligations that have no function location. */
static void _classify(List functions, String file, String report, int status) {
  List conditions = _conditions(report);
  for (List cursor = functions; cursor; cursor = cursor.cdr) {
    List function = cursor.car.list();
    int first = function.cadr().integer();
    int last = cursor.cdr ? cursor.cdr.car.list().cadr().integer() : 1 << 30;
    Array mine = %[];
    foreach (List condition, conditions) {
      int line = condition.car().integer();
      if (line >= first && line < last) mine.push(condition);
    }
    Stdout.printf("%s: %s\n", function.car().str(),
                  mine.len() ? "obligations remain"
                  : status ? "no local verification conditions" : "verified");
    foreach (List condition, mine.list_free())
      Stdout.printf("  %s:%d  %s\n", file, condition.car().integer(),
                    condition.cadr().str());
  }
  if (status)
    Stdout.printf("%s\nRESULT: obligations remain\n", report);
}

// the command

static void _usage(const char *program) {
  Stderr.printf(
    "usage: %s [--emit] [--port N] [--keep] [--root DIR] [-I DIR] FILE\n",
    program);
}

static String _env(const char *name, String fallback) {
  const char *value = getenv(name);
  return value ? String.new(value) : fallback;
}

static Options _options(int argc, char **argv) {
  Options options = Scope.calloc(1, sizeof(struct Options));
  options.timeout = 600;
  Array include_dirs = %[];
  for (int i = 1; i < argc; i++) {
    if (!strcmp(argv[i], "--emit")) options.emit = 1;
    else if (!strcmp(argv[i], "--keep")) options.keep = 1;
    else if (!strcmp(argv[i], "--port") && i + 1 < argc)
      options.port = atoi(argv[++i]);
    else if (!strcmp(argv[i], "--root") && i + 1 < argc)
      options.root = String.new(argv[++i]);
    else if (!strcmp(argv[i], "-I") && i + 1 < argc)
      include_dirs.push(String.new(argv[++i]));
    else if (argv[i][0] == '-' || options.input) return NULL;
    else options.input = String.new(argv[i]);
  }
  if (!options.input) return NULL;
  options.include_dirs = include_dirs.list_free();
  const char *port = getenv("CSTAR_PORT");
  if (port && !options.port) options.port = atoi(port);
  options.x2c = _env("X2C", %"x2c");
  options.packages = _env("X2C_PACKAGES", %"packages");
  options.cstar_home = _env("CSTAR_HOME", %"");
  return options;
}

static int _verify(Options options, String program, List functions) {
  char pattern[] = "/tmp/cstar-verify.XXXXXX";
  String directory = String.new(mkdtemp(pattern));
  String source = %"${directory}/unit.proof.x";
  File out = File.open(source, %"w");
  out.printf("%s", program);
  out.close();
  String executable = %"${directory}/unit.proof";
  String output, errors;
  int status = _run(%(
    ${options.x2c} "build" "--output" $executable "--build-dir"
    ${%"${directory}/cc"} "--package-dir" ${options.packages}
    "--x-include-dir" ${_directory(options.input)} $source
  ), 600, &output, &errors);
  if (status) {
    Stderr.printf("cstar-verify: cannot build the proof program; kept %s\n"
                  "%s%s", directory, output ? output : "",
                  errors ? errors : "");
    return 3;
  }
  int port = options.port;
  ChildProcess server = NULL;
  if (!port) {
    port = 20000 + (int) (getpid() % 30000);
    server = _server(options, directory, port);
    if (!server) return 3;
  }
  setenv("LCF_SERVER_PORT", %"${port}", 1);
  setenv("CSTAR_HOME", options.cstar_home, 1);
  status = _run(%($executable), options.timeout, &output, &errors);
  if (server) {
    kill((pid_t) server.pid, SIGKILL);
    server.wait(NULL, NULL);
  }
  if (!options.keep) _run(%("/bin/rm" "-rf" $directory), 60, NULL, NULL);
  else Stdout.printf("kept %s\n", directory);
  if (status == -2) {
    Stderr.printf("cstar-verify: the proof program did not finish within "
                  "%d seconds\n", options.timeout);
    return 3;
  }
  if (status < 0 || status > 2) {
    Stderr.printf("cstar-verify: the proof program failed\n%s%s",
                  output ? output : "", errors ? errors : "");
    return 3;
  }
  String report = _final_report(output);
  if (!report || output.find(%"RESULT: ") < 0) {
    Stderr.printf("%s%scstar-verify: the prover did not complete the run\n",
                  output ? output : "", errors ? errors : "");
    return 3;
  }
  if (status == 2) {
    Stderr.printf("cstar-verify: %sthe run did not reach every requested "
                  "function\n", output);
    return 3;
  }
  _classify(functions, options.input, report, status);
  return status;
}

int main(int argc, char **argv) {
  x2c_initialize_environment(argv[0]);
  Options options = _options(argc, argv);
  if (!options) {
    _usage(argv[0]);
    return 3;
  }
  if (options.root) x2c_set_root(options.root);
  Context command = Context.open_isolated_named("cstar verify");
  defer command.close();
  List rendered = _render(options);
  if (!rendered) return 2;
  if (options.emit) {
    Stdout.printf("%s", rendered.car().str());
    return 0;
  }
  return _verify(options, rendered.car().str(), rendered.cadr().list());
}
