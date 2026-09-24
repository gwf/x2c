/* Native Lisp signatures and binding declarations. */
#include "x2c.x"
#include "meta.x"

$(import "lisp-bindings.xlisp")

meta Var lisp_write_file(String path, String text);
meta static Array binding_forms = [];

meta List binding_emit(List fn) {
  List forms = x2c_comptime_lower(fn);
  if (!forms)
    x2c_diagnostic_fail("cannot lower Lisp binding function", %());
  binding_forms.push(forms);
  return %(${fn});
}
macro Decorator $binding.emit(Unit $fn) { $binding_emit($fn)... }

meta List binding_write(void) {
  String text = "";
  foreach (List forms, binding_forms)
    foreach (Var form, forms)
      text = text + form.repr() + "\n";
  lisp_write_file("bindings-generated.xlisp", text);
  return %();
}
macro Unit $binding.write() { $binding_write()... }

List binding_parameters(List type);
List binding_return(List type);
List binding_reference(String name);
List binding_native_type(List function);
Var binding_literal_value(List node);
void binding_fail(String message, List node);
List binding_signature(List values);

$binding.emit()
List binding_call(String name, List arguments) =>
  x2c_expr_call(x2c_expr_ident(x2c_ident(name)), arguments);

$binding.emit()
List binding_list_item(Var value) {
  if (!lisp_string(value).equal(%()))
    return binding_call("String_var", %(${x2c_literal_string(value.str())}));
  if (!lisp_symbol(value).equal(%()))
    return binding_call("Symbol_var", %(${x2c_literal_symbol(value)}));
  if (value.is_integer())
    return binding_call("int_var", %(${x2c_literal_int(value.int())}));
  if (!lisp_list(value).equal(%()))
    return binding_call("List_var", %(${binding_signature(value)}));
  return %();
}

$binding.emit()
List binding_signature(List values) {
  if (!values)
    return %(expr () (cast
      (decl ("List") (bindings (bind () ()))) ${x2c_literal_int(0)}));
  return binding_call("cons", %(${binding_list_item(values.car())}
                                ${binding_signature(values.cdr())}));
}

$binding.emit()
List binding_name_signature(String name) =>
  binding_native_type(binding_reference(name));

$binding.emit()
String binding_name(List node) {
  Var value = binding_literal_value(node);
  if (!lisp_string(value).equal(%())) return value.str();
  binding_fail("native Lisp binding name requires a String literal", node);
}

$binding.emit()
List binding_rows_for(String group, List rows) {
  List selected = %();
  foreach (List row, rows)
    if (row.car().equal(group)) selected = cons(row, selected);
  return selected.reverse();
}

$binding.emit()
List binding_record(List group, List name, List function, List all_rows,
                    List sealed) {
  String group_name = x2c_binding_spelling(group);
  String lisp_name = binding_name(name);
  String function_name = x2c_function_name(function);
  List type = binding_native_type(function);
  List rows = binding_rows_for(group_name, all_rows);
  foreach (Var installed, sealed)
    if (installed.equal(group_name))
      x2c_diagnostic_fail(
        "native Lisp binding appears after its group was installed",
        %("group: ${group_name}"));
  foreach (List row, rows)
    if (row[1].equal(lisp_name))
      x2c_diagnostic_fail("duplicate native Lisp binding name",
        %("group: ${group_name}" "name: ${lisp_name}"));
  return %(($group_name $lisp_name $function_name $type) @all_rows);
}

$binding.emit()
List binding_statement(List lisp, List row) {
  match (row) case %(?group ?name ?function ?type):
    return %(stmnt ${binding_call("Lisp_bind", %($lisp
      ${x2c_literal_string(name)}
      ${binding_call("Func_new", %(${x2c_expr_ident(x2c_ident(function))}
        ${binding_signature(type)}))}))});
  return %();
}

$binding.emit()
List binding_install_rows(String group, List all_rows) {
  List rows = binding_rows_for(group, all_rows).reverse();
  if (!rows)
    x2c_diagnostic_fail("unknown native Lisp binding group",
                        %("group: ${group}"));
  return rows;
}

$binding.emit()
List binding_statements(List lisp, List rows) {
  List statements = %();
  foreach (List row, rows)
    statements = cons(binding_statement(lisp, row), statements);
  return statements.reverse();
}

$binding.emit()
List binding_target(String bind_name, String name, String maker) =>
  %(${binding_call("String_var", %(${x2c_literal_string(bind_name)}))}
    ${binding_call("Func_var", %(${binding_call(maker,
      %(${x2c_expr_ident(x2c_ident(name))}
        ${binding_signature(binding_name_signature(name))}))}))});

$binding.emit()
List binding_target_row(List row) {
  match (row) {
    case %(?name (as ?bind)):
      return binding_target(bind.str(), name.str(), "Func_new");
    case %(?name): return binding_target(name.str(), name.str(), "Func_new");
    case %(?name ?marker):
      return binding_target(name.str(), name.str(), "Func_new_rest");
  }
  return %();
}

$binding.emit()
List binding_targets(List rows) {
  List arguments = %();
  foreach (List row, rows) {
    List pair = binding_target_row(row);
    foreach (Var item, pair) arguments = cons(item, arguments);
  }
  return binding_call("Map_update_n", %(${binding_call("Map_new", %())}
    ${x2c_literal_int(rows.len())} @{arguments.reverse()}));
}

$binding.write();
