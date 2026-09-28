/* A focused native probe linked against builds/0's existing compiler objects.
   It exercises the internal reconstruction operation without a second SDK
   entry point or a temporary compiler-source adopter. */
#include "compiler.h"
#include "diagnostics.h"
#include "expressions.h"
#include "lisp.h"
#include "macros.h"
#include "meta.h"
#include "parse.h"
#include "utils.h"
#include <stdio.h>
#include <stdlib.h>

static void require(int condition, const char *message) {
  if (condition) return;
  fprintf(stderr, "bound template: %s\n", message);
  exit(1);
}

static List read_list(Lisp reader, const char *text) {
  unsigned cursor = 0;
  Var result;
  Lisp_read(reader, String_new(text), &cursor, &result);
  return Var_list(result);
}

static Macro definition(Compiler c, const char *text) {
  Compiler_tokenize(c, (char *) text);
  return Compiler_parse_macro_definition(c);
}

static void check(Compiler c, Lisp reader, Macro plain, Macro captured,
    const char *text, Type override, int source_wrapper) {
  Compiler_tokenize(c, (char *) text);
  List code = Compiler_parse_assignment(c);
  Type type = override ? override : Var_list(List_cadr(code));
  List content = Var_list(List_caddr(code));
  int has_captures = List_len(content) == 4;
  Macro shape = has_captures ? captured : plain;
  List names = read_list(reader, has_captures
    ? "(?body *captures *params)" : "(?body *params)");
  List bindings = List_match(code, List_var(Macro_pattern(shape, names)));
  require(bindings != NULL, "source template did not recognize the lambda");
  List body = Var_list(List_assoc(bindings, List_car(names)));
  if (source_wrapper) {
    body = List_list_n(3, Atom_intern(String_new("src")),
      List_var(read_list(reader, "(source \"<caller>\" 10 20)")),
      List_var(body));
    content = List_append(List_getslice(content, 0, List_len(content) - 1, 1),
      List_list_n(1, List_var(body)));
  }
  List rows = has_captures
    ? Var_list(List_assoc(bindings, List_cadr(names))) : NULL;
  List params = Var_list(List_assoc(bindings, has_captures
    ? List_caddr(names) : List_cadr(names)));
  List values = has_captures
    ? List_list_n(3, List_var(body), List_var(rows), List_var(params))
    : List_list_n(2, List_var(body), List_var(params));
  List application = Macro_apply(shape, values);
  require(Var_string(List_car(application)) == String_new("x2c.template"),
    "ordinary application stopped returning a pending invocation");

  Map facts = Compiler_semantic_binding_facts(c);
  Map saved = Map_copy(facts);
  int next_binding = c->names->next_binding;
  int scopes = Sym_scope_count(c->sym), count = c->macro_count;
  List lambda_scopes = c->lambda_scopes;
  Map retained_holes = c->macro_holes;
  size_t early = Array_len(c->early_decls);
  List rebuilt = Compiler_rebuild_expression(c, type, application);
  require(Var_list(List_cadr(rebuilt)) == type, "root type changed");
  require(List_equal(Var_list(List_caddr(rebuilt)), content),
    "bound lambda contents changed");
  require(Var_list(List_last(Var_list(List_caddr(rebuilt)))) == body,
    "body was rebound or reconstructed");
  require(c->names->next_binding == next_binding, "allocated bindings");
  require(Map_equal(facts, saved), "changed semantic binding facts");
  require(Sym_scope_count(c->sym) == scopes, "changed lexical scopes");
  require(c->lambda_scopes == lambda_scopes, "changed capture scopes");
  require(c->macro_holes == retained_holes, "changed template hole context");
  require(c->macro_count == count, "performed normal macro expansion");
  require(Array_len(c->early_decls) == early, "added early declarations");
  require(Compiler_error_count(c) == 0, "reported a compiler error");
  require(List_match(rebuilt, List_var(Macro_pattern(shape, names))) != NULL,
    "rebuilt lambda stopped matching its source template");
  printf("bound template: %s%s\n", text,
    source_wrapper ? " (retained src wrapper)" : "");
}

int main(int argc, char **argv) {
  (void) argc;
  x2c_initialize();
  x2c_initialize_environment(argv[0]);
  Scope_retain();
  Compiler c = Compiler_new();
  c->filename = String_new("<bound-template-probe>");
  Sym_reset(c->sym, NULL);
  Macro plain = definition(c,
    "macro Expression $plain(Expr $body, Param $params...) => "
    "%!($params...) => $body;");
  Macro captured = definition(c,
    "macro Expression $captured(Expr $body, Captures $captures, "
    "Param $params...) => %!($params...) using $captures => $body;");
  Sym_push_new_scope(c->sym);
  Compiler_tokenize(c, "int snapshot, shared, unused");
  Compiler_parse_simple_declaration(c);
  Lisp reader = Lisp_new();
  check(c, reader, plain, captured,
    "%!(int n) using &shared => snapshot + shared + n", NULL, 0);
  check(c, reader, plain, captured,
    "%!() using &shared => { shared++; return shared; }", NULL, 0);
  check(c, reader, plain, captured,
    "%!(int a, int b) => a + b", NULL, 0);
  check(c, reader, plain, captured, "%!() => 7", NULL, 0);
  check(c, reader, plain, captured, "%!() => 7", NULL, 1);
  /* An explicit but unused capture may leave no rows while the established
     result is still Func. Reconstruction must not infer a callable type. */
  check(c, reader, plain, captured, "%!() using &unused => 7",
    read_list(reader, "(\"Func\")"), 0);
  c->macro_holes = Map_new();
  List holes = Var_list(List_assoc(captured,
    Symbol_var(Symbol_new("parameters"))));
  for (List rest = holes; rest; rest = List_cdr(rest)) {
    List hole = Var_list(List_car(rest));
    String binder = Var_str(List_assoc(hole, Symbol_var(Symbol_new("binder"))));
    Map_setindex(c->macro_holes, Atom_intern(String_new(binder + 1)),
      List_var(hole));
  }
  check(c, reader, plain, captured,
    "%!($params...) using $captures => $body", NULL, 0);
  check(c, reader, plain, captured, "%!($params...) => $body", NULL, 0);
  c->macro_holes = NULL;
  Lisp_destroy(reader);
  Scope_release();
  return 0;
}
