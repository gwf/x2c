/*  patterns.x -- match pattern values

   The compile-time value graph behind a Match pattern represents dynamic
   expressions by a private marker, so binder analysis can distinguish a
   computed operator head from ordinary literal data. */

/** Recovers a pattern value graph, using `x2c-dyn` for computed values. */
Var Compiler.match_pattern_value(Compiler c, Var node) {
  if (node is not <list>) return node;
  List ast = node;
  if (!ast) return %();
  Var (head, second, third) = ast;
  if (head == <cache>) return c.match_pattern_value(c.id_keys[second]);
  if (head == <expr>) {
    if (ast ~= %(expr ("Var") (call ? (args ?argument))))
      if (c.is_builtin_converter_call(ast))
        return c.match_pattern_value(argument);
    return c.match_pattern_value(ast.last());
  }
  if (head == <var>) return c.match_pattern_value(second);
  if (head == <string>) return c.match_pattern_value(second);
  if (head == <call>) return _call_value(c, second, third);
  if (head == <literal>) return ast.last();
  if (head == <nil>) return %();
  if (head == <cons>) return _cons_value(c, second, third);
  return <x2c-dyn>;
}

/* A case pattern matches what its labels match. Other untyped calls are
   computed; typed builtin boxers were recognized with their expression. */
static Var _call_value(Compiler c, Var callee, Var args) {
  String converter = _converter_name(callee);
  if (converter == "Macro_case_pattern" || converter == "Macro_case_shape")
    if (args ~= %(args ? ?names *)) {
      List labels = c.match_pattern_value(names);
      return %(!and x2c-dyn @labels);
    }
  return <x2c-dyn>;
}

static Var _cons_value(Compiler c, Var head, Var tail) {
  Var value = c.match_pattern_value(head);
  Var rest = c.match_pattern_value(tail);
  if (rest is not <list>) return <x2c-dyn>;
  return cons(value, rest);
}

static String _converter_name(Var node) {
  if (node is <string>) return node;
  if (node ~= %(expr ? $($source_identifier_content(%(?binding)))))
    return Ast.binding_spelling(binding);
  return NULL;
}

/** Reports whether a recovered pattern value graph is fully static. */
int Compiler.match_value_is_static(Var value) {
  if (value == <x2c-dyn>) return 0;
  if (value is not <list>) return 1;
  foreach (Var part in value.list())
    if (!Compiler.match_value_is_static(part)) return 0;
  return 1;
}

/** Reports whether a typed `Match` pattern has a fully static value graph. */
int Compiler.match_pattern_is_static(Compiler c, List pattern) =>
  Compiler.match_value_is_static(c.match_pattern_value(pattern));

/* match binders

   A pattern's definite binders become declarations in the scope of its
   case, or of its catch clause, whose lowering keeps the issued bindings. */

/** Returns definite binders from a typed `Match` pattern AST.

    When `possible` is non-null, stores every binder appearing on any path.
*/
List Compiler.match_pattern_binders(
  Compiler c, List pattern, List &?possible) {
  Var value = c.match_pattern_value(pattern);
  MatchCaptureLayout layout = MatchCaptureLayout.analyze(value);
  List definite = layout.definite_list();
  if (possible) possible = layout.possible_list();
  layout.free();
  return definite;
}

/** Declares pattern locals and returns their capture-token/binding pairs. */
List Compiler.define_pattern_binders(Compiler c, List pattern) {
  Array rows = [];
  foreach (Atom binder in c.match_pattern_binders(pattern, NULL)) {
    String name = binder.str()[1:];
    List binding;
    if (c.macro_holes) {
      binding = c.macro_introduced_name(name);
      c.bind_template_local(binding, _binder_type(binder), NULL);
    }
    else binding = c.sym.declare(NULL, $(name), _binder_type(binder));
    rows.push($(binder, binding));
  }
  return rows.list_free();
}

static List _binder_type(Var binder) =>
  binder.is_list_binder() ? %("List") : %("Var");

/** Returns the typed expression reading one native match capture slot. */
List Compiler.match_capture_value(Var binder, int index) =>
  %(expr $(_binder_type(binder))
    ($(%"_x2c_gensym_match_$(
      binder.is_list_binder() ? "list" : "value")_$index")));

/** Builds ordinary declarations from a pattern scope's issued bindings.
    A catch reads through its handler; a match reads its capture slots.
*/
List Compiler.pattern_binder_declarations(
  Compiler c, List bindings, List handle) {
  Array declarations = [];
  int index = 0;
  foreach (List row in bindings) {
    Type type = _binder_type(row.car());
    List value = handle ? %(expr ("Var")
      (call "x2c_error_catch_capture"
        (args (expr ("ErrorHandler") (ident $handle))
              (expr (int) (literal (int) $(%"$index"))))))
      : Compiler.match_capture_value(row.car(), index);
    index++;
    if (handle && row.car().is_list_binder())
      value = %(expr $type (call "Var_list_payload" (args $value)));
    declarations.push(%(declare $type (bindings (bind $(row.cadr()) ()))));
    declarations.push(
      %(stmnt (expr $type (op = (expr $type (ident $(row.cadr()))) $value))));
  }
  return declarations.list_free();
}

/** Returns captures established by a true condition. Other operations do
    not establish names, including negation and disjunction.
*/
List Compiler.condition_bindings(List expression) {
  match (expression) {
    case %(expr ? (matches ? ? ? ?bindings)): return bindings;
    case %(expr ? (parens ?inner)):
      return Compiler.condition_bindings(inner);
    case %(expr ? (op && ?left ?right)):
      return Compiler.condition_bindings(left).append(
        Compiler.condition_bindings(right));
  }
  return NULL;
}

/** Opens a scope for the captures established by a true condition. Returns
    whether a scope was opened; the caller closes it after its continuation.
*/
int Compiler.open_condition_scope(Compiler c, List expression) {
  List bindings = Compiler.condition_bindings(expression);
  if (!bindings) return 0;
  c.sym.push_new_scope();
  foreach (List row in bindings) {
    Type type = row.cadr();
    c.sym.bind_identity(NULL, row.car(), type.declaration_ast(row.car()));
  }
  return 1;
}
