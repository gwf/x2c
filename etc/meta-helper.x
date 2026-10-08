/*  meta-helper.x -- the main loop of a project's compile-time helper

    Copyright (c) 2026 Gary William Flake.

    The compiler builds a project's bodied `meta` functions into one helper
    program with this unit and calls them through it, one request and one
    reply at a time. Each message is a frame: its length in decimal and a
    newline, then that many bytes of one datum (`lib/datum.x`). Requests
    arrive on descriptor 3 and replies leave on descriptor 4, so a body
    that prints still reaches the terminal.

      (reset)               begin a unit, whose first call of each table
                            runs its `meta static` initializers; no reply
      (call K NAME (ARG ...) (GLOBAL ...))
                            call NAME in table K; each GLOBAL is
                            `(SPELLING BINDING)`, the unit's binding that a
                            macro value's free reference recognizes
      (quit)

    A call replies with a `(warning MESSAGE (NOTE ...))` frame for each
    warning it made and a `(dependency PATH HASH)` frame for each file it
    embedded, then `(value V)`, `(void)` for no value, `(error
    MESSAGE (NOTE ...))` for a failure the body reported or the compiler
    would report, `(error MESSAGE (NOTE ...) (at NODE))` for one the body
    reported at a node, or `(failure
    CAUSE)` for an Error the body raised, or `(missing)` when the table has
    no such function. A body that crashes or exits ends the helper, which
    the compiler reports at the call.

    A body receives what it needs as arguments. The operations that read
    compiler state are compiler-owned and fail here. The builders compute
    what the compiler would. A template call returns `("x2c.template"
    STORED VALUES)`, which the compiler replaces by the invocation after
    the call returns.
*/

#include "x2c.x"
#include "meta.x"
#include "datum.x"
#include "path.x"
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <errno.h>
#include <dlfcn.h>
#include <fcntl.h>
#include <pthread.h>
#include <signal.h>

/* The generated table unit supplies each module's name-to-`Func` Map. */
Map x2c_meta_helper_table(int index);
int x2c_meta_helper_count(void);

static FILE *helper_out = NULL;
static Array helper_notices = NULL;

/* The handle of each native module loaded, by path, which `main` makes,
   and the Scope of what a module's constructors allocate. A module's code
   stays loaded for the helper's lifetime, so both outlast the call that
   loaded it. */
static Map helper_modules = NULL;
static Scope helper_module_scope = NULL;

/* What the unit's `meta static` initializers allocate, a Job one starts
   included, which lasts until the next unit's reset or the helper's end,
   and each table whose initializers ran in the unit, with the failure its
   calls reply with when they raised. */
static Scope helper_unit_scope = NULL;
static Map helper_started = NULL;
static Map helper_tables = NULL;

/* Raises the failure a body reports, which the call replies with. */
static void _fail(String message, List notes) {
  raise %(meta-fail (message $message) (notes $notes));
}

static void _unavailable(String name) {
  _fail(
    %"$name is not available to project meta code",
    %("reason: it reads compiler state; pass what it answers as an"
      "argument"));
}

/* The compiler checked and selected this module before building the group.
   Its code remains loaded for the helper's lifetime. */
void *x2c_meta_native_symbol(String path, String name) {
  Var loaded;
  void *handle;
  if (helper_modules.try_get(path, loaded)) handle = loaded.pointer();
  else {
    $scope(&helper_module_scope) handle = dlopen(path, RTLD_NOW | RTLD_LOCAL);
    if (!handle)
      _fail(
        "cannot load native module in project meta helper",
        %("module: $path" "reason: ${String.new(dlerror())}"));
    helper_modules[path] = handle;
  }
  void *target = dlsym(handle, name);
  if (!target)
    _fail(
      "native module has no C target for project meta code",
      %("module: $path" "function: $name"));
  return target;
}

static void _check_notes(String operation, List notes) {
  foreach (Var note, notes)
    if (note is not <string>)
      _fail(%"$operation notes must be Strings", %("value: ${note.repr()}"));
}

/* --- the operations a body may call ------------------------------------- */

List x2c_ident(String spelling) {
  if (!spelling.is_identifier())
    _fail(
      "x2c.ident requires an identifier spelling",
      %("value: ${spelling.repr()}"));
  return %("x2c.ident" $spelling);
}

void x2c_diagnostic_fail(String message, List notes) {
  _check_notes("x2c.diagnostic.fail", notes);
  _fail(message, notes);
}

/* The failure carries the node, whose position the compiler reports. */
void x2c_diagnostic_fail_at(Var node, String message, List notes) {
  _check_notes("x2c.diagnostic.fail-at", notes);
  raise %(meta-fail (message $message) (notes $notes) (at $node));
}

void x2c_diagnostic_warn(String message, List notes) {
  _check_notes("x2c.diagnostic.warn", notes);
  helper_notices.push(%(warning $message $notes));
}

String x2c_binding_spelling(Var syntax) {
  if (syntax is <string>) return syntax;
  List value = syntax;
  match (value) case %(expr ? (? *)): value = value.caddr();
  match (value) {
    case %(ident (*)):  value = value.cadr();
    case %(bind (*) ?): value = value.cadr();
  }
  match (value) {
    case %((!is ?name type string)):          return name;
    case %(binding ? (!is ?name type string)): return name;
  }
  _fail(
    "x2c.binding.spelling requires an identifier or binding",
    %("value: ${syntax.repr()}"));
}

String x2c_function_name(List function) {
  List identity = function.match_replace(
    %(function ? (bind ?binding ?) ?), <?binding>);
  return x2c_binding_spelling(identity);
}

List x2c_template_call(Var stored, List values) =>
  %("x2c.template" $stored $values);

List x2c_expr_field(List receiver, String name) {
  List checked = x2c_ident(name);
  return %(expr () (op . $receiver (${checked[1]})));
}

List x2c_type_parts(List type) => type_declaration_parts(type);

/* The code effect builders compute what the compiler's do. */
List x2c_code(List code, List effects) =>
  %(code-value "source" $code $effects);

Atom x2c_fresh_name(String role) => Atom.intern("?__" + role);

List x2c_effect_name(Atom name) => %(new-name $name ${name.str()[3:]});

List x2c_effect_support(Var key, Atom name, List declaration) =>
  %(early $key $name $declaration);

List x2c_effect_initialize(Symbol area, List statement) =>
  %(initialize $area $statement);

/* The three builders below are the bodies in `lib/meta.x`. */
List x2c_expr_cast(List type, List expression) {
  List (base, mods) = type_declaration_parts(type);
  return %(expr $type
    (cast (decl $base (bindings (bind () $mods))) $expression));
}

List x2c_decl_make(List type, Var name, List initializer) {
  List (base, mods) = type_declaration_parts(type);
  List binding = %(bind ($name) $mods);
  if (initializer) binding = %(op = $binding $initializer);
  return %(declare $base (bindings $binding));
}

List x2c_param_make(List type, Var name) {
  List (base, mods) = type_declaration_parts(type);
  return %(param $base (bind ($name) $mods));
}

/* A `Source` parameter's description carries its text. */
String x2c_source_text(Var syntax) {
  match (syntax)
    case %((text ?(String text)) (file ?) (syntax ?)): return text;
  _unavailable("x2c.source.text");
}

/* The operations that read compiler state have no answer here. */
List x2c_type_members(List v) { _unavailable("x2c.type.members"); }
List x2c_type_resolve(List v) { _unavailable("x2c.type.resolve"); }
List x2c_type_element(List v) { _unavailable("x2c.type.element"); }
List x2c_type_parameters(List v) { _unavailable("x2c.type.parameters"); }
List x2c_type_return(List v) { _unavailable("x2c.type.return"); }
List x2c_type_layout(List v) { _unavailable("x2c.type.layout"); }
List x2c_method_resolve(List v, String w) {
  _unavailable("x2c.method.resolve");
}
List x2c_protocol_member(List v, List w, String x) {
  _unavailable("x2c.protocol.member");
}
List x2c_function_parameter(List v, String w) {
  _unavailable("x2c.function.parameter");
}
List x2c_syntax_type(List v) { _unavailable("x2c.syntax.type"); }
List x2c_type_fields(List v) { _unavailable("x2c.type.fields"); }
Var x2c_literal_value(Var v) { _unavailable("x2c.literal.value"); }
int x2c_type_is_value(List v) { _unavailable("x2c.type.value?"); }
int x2c_type_is_integral(List v) { _unavailable("x2c.type.integral?"); }
int x2c_type_is_pointer(List v) { _unavailable("x2c.type.pointer?"); }
Symbol x2c_type_tag_name(String v) { _unavailable("x2c.type.tag-name"); }
String x2c_type_reverse_name(String v, String w) {
  _unavailable("x2c.type.reverse-name");
}
String x2c_invocation_file(void) { _unavailable("x2c.invocation.file"); }
int x2c_invocation_line(void) { _unavailable("x2c.invocation.line"); }
int x2c_invocation_column(void) { _unavailable("x2c.invocation.column"); }
Map x2c_meta_definition_hashes(void) {
  _unavailable("x2c.meta.definition-hashes");
}

/* A `Source` holding a String literal is read beside its file; a String
   must be absolute, since the helper does not know the definition's file.
   The compiler records each file read as a translation dependency. */
String x2c_embed_text(Var path) {
  String file = NULL, spelling = NULL;
  if (path is <string>) {
    if (((String) path).startswith("/")) spelling = path;
  }
  else
    match (path)
      case %((text ?) (file ?(String source))
             (syntax (expr ? (literal ? ?(String literal))))):
        if (literal.startswith("\"") || literal.startswith("%\"")) {
          file = source;
          spelling = literal.parse();
        }
  if (!spelling)
    _fail(
      "x2c.embed.text requires a captured String literal or an "
      "absolute path", %("value: ${path.repr()}"));
  if (!spelling.len())
    _fail("x2c.embed.text requires a non-empty path", NULL);
  if (file && !spelling.startswith("/"))
    spelling = %"${Path.dirname(file)}/$spelling";
  String target = Path.absolute(spelling), text = NULL;
  try text = Path.read_text(target);
  catch %((!or not-found io-fail) *):
    _fail("cannot read embedded text", %("path: $target"));
  helper_notices.push(%(dependency $target ${"%08x".printf(text.hash())}));
  return text;
}

/* --- the protocol ------------------------------------------------------- */

/* The next request frame on descriptor `in`, reading into `input`, or
   void at the end of `in`. */
static Var _request(int in, Buffer input) {
  for (;;) {
    String text = input;
    size_t used = 0;
    Var request = void;
    if (datum_unframe(text, used, request)) {
      String rest = text[used:];
      input.clear();
      if (rest) input.write(rest);
      return request;
    }
    char bytes[65536];
    ssize_t n = read(in, bytes, sizeof bytes);
    if (n < 0 && errno == EINTR) continue;
    if (n <= 0) return void;
    input.write(String.new_len(bytes, n));
  }
}

/* Writes one reply frame, or returns 0 for a message with no datum. */
static int _reply(List message) {
  Buffer out = Buffer.new(0);
  if (!datum_frame(out, message)) return 0;
  String frame = %"$out";
  fwrite((char *) frame, 1, frame.len(), helper_out);
  fflush(helper_out);
  return 1;
}

static void _call(Map table, String name, List arguments) {
  helper_notices = [];
  Var target;
  if (!table || !table.try_get(name, target)) _reply(%(missing));
  else _apply(target, name, arguments);
}

/* Calls `target` and writes its replies. The call has a Scope of its own
   that ends after them, so what the body allocates ends with the call when
   it returns or raises, and a Job it started is terminated and reaped. */
$scope() static void _apply(Var target, String name, List arguments) {
  unsigned count = arguments.len(), i = 0;
  FuncArg *argv = Scope.calloc(count ? count : 1, sizeof(FuncArg));
  foreach (Var argument, arguments) argv[i++] = FuncArg.value(argument);
  Var result = void;
  List failure = NULL;
  try result = ((Func) target.pointer()).apply(count, argv);
  catch %(meta-fail (message ?message) (notes ?notes)):
    failure = Error.snapshot(%(error $message $notes));
  catch %(meta-fail (message ?message) (notes ?notes) (at ?node)):
    failure = Error.snapshot(%(error $message $notes (at $node)));
  /* A catch binding is borrowed by the arm; the reply is written after. */
  catch %(?code *detail):
    failure = %(failure ${Error.snapshot(cons(code, detail))});
  foreach (List notice, helper_notices) _reply(notice);
  if (failure) {
    _reply(failure);
    return;
  }
  List problem = datum_result_problem(result, {});
  if (problem) {
    _reply(cons(<error>, problem));
    return;
  }
  // A List cannot hold `void`, so no value has a reply of its own.
  if (result is void) {
    _reply(%(void));
    return;
  }
  if (!_reply(%(value $result)))
    _reply(
      %(error "compile-time result has no value the compiler can read"
        ("function: $name")));
}

/* Ends the last unit's Scope and begins the next unit's. */
static void _reset(void) {
  helper_unit_scope.destroy();
  helper_unit_scope = NULL;
  $scope(&helper_unit_scope) helper_started = {};
}

/* Runs the `meta static` initializers of table `index` once per unit, in
   the unit's Scope. Returns the failure that its calls reply with, or
   NULL. */
static List _start(int index, Map table) {
  Var state;
  if (!helper_started.try_get(index, state)) {
    helper_started[index] = 0;
    List failure = _initialize(table);
    if (failure) state = failure;
    else state = 0;
    helper_started[index] = state;
  }
  return state is <list> ? state.list() : NULL;
}

/* Native calls between providers use the same unit initialization as a
   call through the protocol. Recursive provider dependencies start once. */
void x2c_meta_helper_start(String name) {
  foreach (Var (index, value), helper_tables) {
    Map table = value;
    Var functions;
    if (!table.try_get(<functions>, functions) ||
        !(name in functions.list())) continue;
    List failure = _start(index, table);
    match (failure) case %(failure (?code *detail)): Error.raise(code, detail);
    return;
  }
}

static List _initialize(Map table) {
  Var reset;
  if (!table || !table.try_get("x2c_module_reset", reset)) return NULL;
  $scope(&helper_unit_scope) {
    try ((Func) reset.pointer()).apply(0, NULL);
    catch %(?code *detail):
      return %(failure ${Error.snapshot(cons(code, detail))});
  }
  return NULL;
}

/* Ends the helper and every process it started once the process that
   started it has gone. The helper leads its own process group, which a
   signal to the compiler's group, such as Ctrl-C, does not reach. */
static void *_watch(void *parent) {
  while (getppid() == (pid_t) (long) parent) usleep(100000);
  killpg(getpid(), SIGKILL);
  return NULL;
}

int main(void) {
  Lisp.kernel();
  helper_out = fdopen(4, "wb");
  if (!helper_out) _exit(2);
  /* A process that a body starts inherits neither end of the protocol, so
     the compiler reads the end of the replies as soon as the helper ends. */
  fcntl(3, F_SETFD, FD_CLOEXEC);
  fcntl(4, F_SETFD, FD_CLOEXEC);
  pthread_t watcher;
  pthread_create(&watcher, NULL, _watch, (void *) (long) getppid());
  helper_modules = {};
  Buffer input = Buffer.new(0);
  helper_tables = {};
  for (int i = 0; i < x2c_meta_helper_count(); i++) {
    Map table = x2c_meta_helper_table(i);
    if (table) helper_tables[i] = table;
  }
  _reset();
  for (;;) {
    Var request = _request(3, input), found;
    match (request) {
      case %(reset): _reset();
      case %(call ?(int index) ?(String name) ?(List arguments)
             ?(List globals)): {
        Macro.use_subject(globals);
        Map table = helper_tables.try_get(index, found) ? found : NULL;
        List failure = _start(index, table);
        if (failure) _reply(failure);
        else _call(table, name, arguments);
      }
      default: {
        helper_unit_scope.destroy();
        _exit(0);
      }
    }
  }
}
