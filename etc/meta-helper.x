/*  meta-helper.x -- the main loop of a project's compile-time helper

    Copyright (c) 2026 Gary William Flake.

    The compiler builds a project's bodied `meta` functions into one helper
    program with this unit and calls them through it, one request and one
    reply at a time. Each message is a frame: its length in decimal and a
    newline, then that many bytes of one datum (`lib/datum.x`). Requests
    arrive on descriptor 3 and replies leave on descriptor 4, so a body
    that prints still reaches the terminal.

      (reset K)             select table K and run its `meta static`
                            initializers again; no reply
      (call NAME (ARG ...)) call NAME in the selected table
      (quit)

    A call replies with a `(warning MESSAGE (NOTE ...))` frame for each
    warning it made and a `(dependency PATH HASH)` frame for each file it
    embedded, then `(value V)`, `(void)` for no value, `(error
    MESSAGE (NOTE ...))` for a
    failure the body reported or the compiler would report, or `(failure
    CAUSE)` for an Error the body raised, or `(missing)` when the table has
    no such function. A body that crashes or exits ends the helper, which
    the compiler reports at the call.

    A body receives what it needs as arguments. The operations that read
    compiler state are compiler-owned: a builder the compiler finishes
    returns `("x2c.deferred" NAME ARG ...)`, a template call returns
    `("x2c.template" STORED VALUES)`, and the compiler replaces each after
    the call returns. The rest fail here.
*/

#include "x2c.x"
#include "meta.x"
#include "datum.x"
#include "path.x"
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

/* The generated table unit supplies each module's name-to-`Func` Map. */
Map x2c_meta_helper_table(int index);
int x2c_meta_helper_count(void);

static FILE *helper_out = NULL;
static Array helper_notices = NULL;

/* Raises the failure a body reports, which the call replies with. */
static void _fail(String message, List notes) {
  raise %(meta-fail (message $message) (notes $notes));
}

static void _unavailable(String name) {
  _fail(%"$name is not available to project meta code",
        %("reason: it reads compiler state; pass what it answers as an"
          "argument"));
}

static void _check_notes(String operation, List notes) {
  foreach (Var note, notes)
    if (note is not <string>)
      _fail(%"$operation notes must be Strings",
            %("value: ${note.repr()}"));
}

/* --- the operations a body may call ------------------------------------- */

List x2c_ident(String spelling) {
  if (!spelling.is_identifier())
    _fail("x2c.ident requires an identifier spelling",
          %("value: ${spelling.repr()}"));
  return %("x2c.ident" $spelling);
}

void x2c_diagnostic_fail(String message, List notes) {
  _check_notes("x2c.diagnostic.fail", notes);
  _fail(message, notes);
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
  _fail("x2c.binding.spelling requires an identifier or binding",
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

List x2c_expr_cast(List type, List expression) =>
  %("x2c.deferred" "x2c_expr_cast" $type $expression);
List x2c_decl_make(List type, Var name, List initializer) =>
  %("x2c.deferred" "x2c_decl_make" $type $name $initializer);
List x2c_param_make(List type, Var name) =>
  %("x2c.deferred" "x2c_param_make" $type $name);
List x2c_type_members(List type) =>
  %("x2c.deferred" "x2c_type_members" $type);
List x2c_type_parts(List value) =>
  %("x2c.deferred" "x2c_type_parts" $value);
List x2c_type_resolve(List value) =>
  %("x2c.deferred" "x2c_type_resolve" $value);
List x2c_type_element(List value) =>
  %("x2c.deferred" "x2c_type_element" $value);
List x2c_type_parameters(List value) =>
  %("x2c.deferred" "x2c_type_parameters" $value);
List x2c_type_return(List value) =>
  %("x2c.deferred" "x2c_type_return" $value);
List x2c_type_layout(List value) =>
  %("x2c.deferred" "x2c_type_layout" $value);
List x2c_method_resolve(List type, String name) =>
  %("x2c.deferred" "x2c_method_resolve" $type $name);
List x2c_protocol_member(List participant, List base, String member) =>
  %("x2c.deferred" "x2c_protocol_member" $participant $base $member);
List x2c_function_parameter(List function, String wanted) =>
  %("x2c.deferred" "x2c_function_parameter" $function $wanted);

/* A `Source` parameter's description carries its text. */
String x2c_source_text(Var syntax) {
  match (syntax) case %((text ?(String text)) (file ?) (syntax ?)): return text;
  _unavailable("x2c.source.text");
}

List x2c_syntax_type(List value) {
  (void) value;
  _unavailable("x2c.syntax.type");
}

List x2c_type_fields(List value) {
  (void) value;
  _unavailable("x2c.type.fields");
}

Var x2c_literal_value(Var syntax) {
  (void) syntax;
  _unavailable("x2c.literal.value");
}

int x2c_type_is_value(List value) {
  (void) value;
  _unavailable("x2c.type.value?");
}

int x2c_type_is_integral(List value) {
  (void) value;
  _unavailable("x2c.type.integral?");
}

int x2c_type_is_pointer(List value) {
  (void) value;
  _unavailable("x2c.type.pointer?");
}

Symbol x2c_type_tag_name(String name) {
  (void) name;
  _unavailable("x2c.type.tag-name");
}

String x2c_type_reverse_name(String base, String participant) {
  (void) base;
  (void) participant;
  _unavailable("x2c.type.reverse-name");
}

String x2c_invocation_file(void) {
  _unavailable("x2c.invocation.file");
}

int x2c_invocation_line(void) {
  _unavailable("x2c.invocation.line");
}

int x2c_invocation_column(void) {
  _unavailable("x2c.invocation.column");
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
    _fail("x2c.embed.text requires a captured String literal or an "
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

Map x2c_meta_definition_hashes(void) {
  _unavailable("x2c.meta.definition-hashes");
}

/* --- the protocol ------------------------------------------------------- */

/* The next frame on `in`, or NULL at its end. */
static String _frame_read(FILE *in) {
  size_t length = 0;
  if (fscanf(in, "%zu", &length) != 1 || fgetc(in) != '\n') return NULL;
  char *bytes = malloc(length + 1);
  if (!bytes || fread(bytes, 1, length, in) != length) return NULL;
  bytes[length] = 0;
  String text = String.new_len(bytes, length);
  free(bytes);
  return text;
}

static void _frame_write(String text) {
  fprintf(helper_out, "%zu\n", (size_t) text.len());
  fwrite((char *) text, 1, text.len(), helper_out);
  fflush(helper_out);
}

static void _reply(List message) {
  Buffer out = Buffer.new(0);
  datum_write(out, message, 1);
  _frame_write(out);
}

/* Why `value` cannot return to the compiler, or NULL. `marks` holds 1 for
   an Array or Map being checked and 2 for one already checked. */
static List _result_problem(Var value, Map marks) {
  if (value.is_pointer() && value.u64)
    return %("compile-time result is a compiler address"
             ("return data built from the pointed-to values instead"));
  if (value is <list>) {
    foreach (Var item, value.list()) {
      List problem = _result_problem(item, marks);
      if (problem) return problem;
    }
    return NULL;
  }
  if (value is not <array> && value is not <map>) return NULL;
  ulong address = (ulong) value.u64;
  if (address in marks)
    return %(${marks[address] == 1
                 ? "compile-time result contains itself"
                 : "compile-time result holds one collection twice"}
             ("each Array and Map in a result is built separately"));
  marks[address] = 1;
  if (value is <array>)
    foreach (Var item, value.array()) {
      List problem = _result_problem(item, marks);
      if (problem) return problem;
    }
  else
    foreach (Var (key, item), (Map) value) {
      List problem = _result_problem(key, marks);
      if (!problem) problem = _result_problem(item, marks);
      if (problem) return problem;
    }
  marks[address] = 2;
  return NULL;
}

static void _call(Map table, String name, List arguments) {
  helper_notices = [];
  Var target;
  if (!table || !table.try_get(name, target)) {
    _reply(%(missing));
    return;
  }
  unsigned count = arguments.len(), i = 0;
  FuncArg *argv = Scope.calloc(count ? count : 1, sizeof(FuncArg));
  foreach (Var argument, arguments) argv[i++] = FuncArg.value(argument);
  Var result = void;
  List failure = NULL;
  try result = ((Func) target.pointer()).apply(count, argv);
  catch %(meta-fail (message ?message) (notes ?notes)):
    failure = %(error $message $notes);
  catch %(?code *detail): failure = %(failure ${cons(code, detail)});
  foreach (List notice, helper_notices) _reply(notice);
  if (failure) {
    _reply(failure);
    return;
  }
  List problem = _result_problem(result, {});
  if (problem) {
    _reply(cons(<error>, problem));
    return;
  }
  // A List cannot hold `void`, so no value has a reply of its own.
  if (result is void) {
    _reply(%(void));
    return;
  }
  Buffer out = Buffer.new(0);
  out.write("(value ");
  if (!datum_write(out, result, 1)) {
    _reply(%(error "compile-time result has no value the compiler can read"
                   ("function: $name")));
    return;
  }
  out.write(")");
  _frame_write(out);
}

int main(void) {
  Lisp.kernel();
  FILE *in = fdopen(3, "rb");
  helper_out = fdopen(4, "wb");
  if (!in || !helper_out) _exit(2);
  Map tables = {};
  for (int i = 0; i < x2c_meta_helper_count(); i++) {
    Map table = x2c_meta_helper_table(i);
    if (table) tables[i] = table;
  }
  Map current = NULL;
  for (;;) {
    String text = _frame_read(in);
    unsigned cursor = 0;
    Var request = void, table, reset;
    if (!text || !datum_read(text, cursor, request)) _exit(0);
    match (request) {
      case %(reset ?(int index)): {
        current = tables.try_get(index, table) ? table : NULL;
        if (current && current.try_get("x2c_module_reset", reset))
          try ((Func) reset.pointer()).apply(0, NULL);
          catch %(?code *detail): (void) detail;
      }
      case %(call ?(String name) ?(List arguments)):
        _call(current, name, arguments);
      default: _exit(0);
    }
  }
}
