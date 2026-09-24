/* Built-in macro algorithms; generate with tools/gen-lisp-init.py. */
#include "x2c.x"
#include "meta.x"

meta Var lisp_write_file(String path, String text);
meta static Array builtin_forms = [];

meta List builtin_emit(List fn) {
  List forms = x2c_comptime_lower(fn);
  if (!forms)
    x2c_diagnostic_fail("cannot lower built-in macro function", %());
  builtin_forms.push(forms);
  return %(${fn});
}
macro Decorator $builtin.emit(Unit $fn) { $builtin_emit($fn)... }

meta List builtin_write(void) {
  String text = "";
  foreach (List forms, builtin_forms)
    foreach (Var form, forms)
      text = text + form.repr() + "\n";
  lisp_write_file("builtins-generated.xlisp", text);
  return %();
}
macro Unit $builtin.write() { $builtin_write()... }


$builtin.emit()
List builtin_scope_expand(List body, List destinations) {
  if (destinations.len() > 1)
    x2c_diagnostic_fail("$scope accepts zero or one destination", %());
  String push = destinations ? "Scope_push" : "Scope_retain";
  String pop = destinations ? "Scope_pop" : "Scope_release";
  return %((block
    (stmnt (expr () (call (expr () (ident $push)) (args @destinations))))
    (block
      (defer (stmnt (expr () (call (expr () (ident $pop)) (args)))))
      $body)));
}

/* Foreach expansion; lowered into the compiler's built-in Lisp artifact. */

List builtin_foreach_reference(String name);
List builtin_foreach_parameters(List type);
List builtin_foreach_return(List type);
Var builtin_foreach_pointer(List type);
Var builtin_foreach_integral(List type);
List builtin_foreach_element(List type);
Var builtin_foreach_unique(String name);
List builtin_foreach_complete(List expression);
List builtin_foreach_collection(List expression);
List builtin_foreach_bindings(List declaration);
List builtin_foreach_protocol(List type, List protocol, String member);

$builtin.emit()
int builtin_foreach_atom_type(Var type) {
  if (lisp_list(type).equal(%())) return 0;
  List items = type;
  if (items.len() != 1) return 0;
  Var name = items.car();
  return !lisp_string(name).equal(%()) || !lisp_symbol(name).equal(%());
}

$builtin.emit()
List builtin_foreach_expr(List type, Var binding) =>
  %(expr $type (ident $binding));

$builtin.emit()
List builtin_foreach_address(List value) => %(expr () (op & $value));

$builtin.emit()
List builtin_foreach_declare(List type, Var binding, List initializer) {
  List value = %(bind $binding ());
  if (initializer) value = %(op = $value $initializer);
  return %(declare $type (bindings $value));
}

$builtin.emit()
List builtin_foreach_assign(List target, List value) =>
  %(stmnt (expr () (op = $target $value)));

$builtin.emit()
int builtin_foreach_valid_outputs(List outputs) {
  if (!outputs) return 1;
  List output = outputs.car();
  if (builtin_foreach_pointer(output).equal(%())) return 0;
  if (!builtin_foreach_atom_type(builtin_foreach_element(output))) return 0;
  return builtin_foreach_valid_outputs(outputs.cdr());
}

$builtin.emit()
List builtin_foreach_cursor_spec(List collection_type) {
  if (!builtin_foreach_atom_type(collection_type)) return %();
  String owner = collection_type.car().str();
  List function = builtin_foreach_reference(owner + "_try_next");
  if (!function) return %();
  List type = x2c_syntax_type(function);
  List parameters = builtin_foreach_parameters(type);
  List cursor_parameter = parameters.cdr() ? parameters[1] : %();
  List outputs = parameters.cdr() ? parameters.cdr().cdr() : %();
  if (!builtin_foreach_return(type).equal(%(int)) ||
      !parameters.car().equal(collection_type) ||
      builtin_foreach_pointer(cursor_parameter).equal(%())) return %();
  List cursor_type = builtin_foreach_element(cursor_parameter);
  if (builtin_foreach_integral(cursor_type).equal(%()) &&
      !cursor_type.equal(collection_type)) return %();
  if (!outputs) return %();
  if (!builtin_foreach_valid_outputs(outputs)) return %();
  List output_types = outputs.map(%!(Var output) =>
    builtin_foreach_element(output));
  return %($function $cursor_type $output_types);
}

$builtin.emit()
List builtin_foreach_cursor_assignments(List targets, List outputs) {
  if (targets.len() == 1)
    return %(${builtin_foreach_assign(targets[0], outputs.last())});
  return %(${builtin_foreach_assign(targets[0], outputs[0])}
           ${builtin_foreach_assign(targets[1], outputs[1])});
}

$builtin.emit()
List builtin_foreach_cursor_loop(List declaration, List collection,
  List body, List targets, List collection_type, List spec, Var object,
  Var cursor) {
  List function = spec[0], cursor_type = spec[1], types = spec[2];
  List outputs = types.map(%!(Var type) =>
    %($type ${builtin_foreach_unique("cursor_output")}));
  List values = outputs.map(%!(List record) =>
    builtin_foreach_expr(record[0], record[1]));
  List addresses = values.map(%!(List value) =>
    builtin_foreach_address(value));
  List declarations = outputs.map(%!(List record) =>
    builtin_foreach_declare(record[0], record[1], %()));
  List object_expression = builtin_foreach_expr(collection_type, object);
  List cursor_expression = builtin_foreach_expr(cursor_type, cursor);
  List arguments = %($object_expression
    ${builtin_foreach_address(cursor_expression)} @addresses);
  List condition = x2c_expr_call(function, arguments);
  List assignments = builtin_foreach_cursor_assignments(targets, values);
  List loop_body = %(block @assignments $body);
  List initial = cursor_type.equal(collection_type)
    ? object_expression : x2c_literal_int(0);
  return %((block $declaration
    ${builtin_foreach_declare(collection_type, object, collection)}
    ${builtin_foreach_declare(cursor_type, cursor, initial)}
    @declarations (while $condition $loop_body)));
}

$builtin.emit()
List builtin_foreach_pair_assignments(List targets, List item, Var pair) {
  List expression = builtin_foreach_expr(%("List"), pair);
  return %(${builtin_foreach_declare(%("List"), pair, %())}
    ${builtin_foreach_assign(expression, item)}
    ${builtin_foreach_assign(targets[0],
      x2c_expr_index(expression, x2c_literal_int(0)))}
    ${builtin_foreach_assign(targets[1],
      x2c_expr_index(expression, x2c_literal_int(1)))});
}

$builtin.emit()
List builtin_foreach_iter_call(List function, List collection) =>
  %(expr ("Iter") (call $function (args $collection)));

$builtin.emit()
List builtin_foreach_general_loop(List declaration, List collection,
  List body, List targets, List collection_type, Var iterator, Var item,
  Var pair, List converter) {
  int atom = builtin_foreach_atom_type(collection_type);
  String owner = atom ? collection_type.car().str() : "";
  List enumerate = %();
  if (targets.len() == 2 && atom && !collection_type.equal(%("Iter")))
    enumerate = builtin_foreach_reference(owner + "_enumerate");
  List constructor = enumerate ? enumerate : converter;
  List iterator_expression = builtin_foreach_expr(%("Iter"), iterator);
  List item_expression = builtin_foreach_expr(%("Var"), item);
  List initializer = builtin_foreach_complete(constructor
    ? builtin_foreach_iter_call(constructor, collection) : collection);
  List next = builtin_foreach_reference("Iter_try_next");
  List condition = x2c_expr_call(next, %($iterator_expression
    ${builtin_foreach_address(item_expression)}));
  List assignments = targets.len() == 1
    ? %(${builtin_foreach_assign(targets[0], item_expression)})
    : builtin_foreach_pair_assignments(targets, item_expression, pair);
  List loop_body = %(block @assignments $body);
  return %((block $declaration
    ${builtin_foreach_declare(%("Iter"), iterator, initializer)}
    ${builtin_foreach_declare(%("Var"), item, %())}
    (while $condition $loop_body)));
}

$builtin.emit()
List builtin_foreach_expand(List declaration, List collection, List body,
  Var iterator, Var item, Var pair, Var object, Var cursor) {
  collection = builtin_foreach_collection(collection);
  List targets = builtin_foreach_bindings(declaration);
  List type = x2c_syntax_type(collection);
  int direct = type.equal(%("Iter"));
  List converter = %();
  if (!direct) {
    converter = type.equal(%("Var"))
      ? builtin_foreach_reference("Var_iter")
      : builtin_foreach_protocol(type, %("Iter"), "iter");
  }
  List spec = direct ? %() : builtin_foreach_cursor_spec(type);
  if (targets.len() != 1 && targets.len() != 2)
    x2c_diagnostic_fail(
      "foreach requires one binding or a two-name destructuring declaration",
      %());
  if (!direct && !converter) {
    Var printable = type;
    x2c_diagnostic_fail("type " + printable.repr() + " is not iterable",
      %("declare an Iter protocol adoption or iterate an Iter directly"));
  }
  if (spec && (targets.len() == 1 || List.len(spec[2]) >= 2))
    return builtin_foreach_cursor_loop(declaration, collection, body,
      targets, type, spec, object, cursor);
  return builtin_foreach_general_loop(declaration, collection, body,
    targets, type, iterator, item, pair, converter);
}

/* Class declarations and their deferred defaults. */
Var builtin_class_pointer(List type);
List builtin_class_element(List type);
List builtin_class_location(void);
List builtin_class_field(List receiver, String member);
List builtin_class_cast(List type, List expression);
List builtin_class_declaration(List type, Var name, List initializer);
List builtin_class_parameter(List type, Var name);

$builtin.emit()
List builtin_class_ref(String name) => %(expr () (ident ($name)));

$builtin.emit()
List builtin_class_op(Symbol op, List operands) =>
  %(expr () (op $op @operands));

$builtin.emit()
List builtin_class_call(String name, List arguments) =>
  x2c_expr_call(builtin_class_ref(name), arguments);

$builtin.emit()
List builtin_class_method(List receiver, String member, List arguments) =>
  x2c_expr_call(builtin_class_field(receiver, member), arguments);

$builtin.emit()
List builtin_class_size(List expression) =>
  %(expr (unsigned) (sizeof (parens $expression)));

$builtin.emit()
List builtin_class_function(String name, List result, List parameters,
                            List body) {
  List parts = x2c_type_parts(result);
  return %(function ${parts[0]}
    (bind ($name) ((fnmod (params @parameters)) @{parts[1]}))
    (block @body));
}

$builtin.emit()
List builtin_class_default(String owner, String member, List result,
                           List parameters, List body) =>
  %(default ${builtin_class_function(%"${owner}_${member}", result,
                                     parameters, body)});

$builtin.emit()
List builtin_class_value_type(List type) {
  List result = %();
  foreach (Var item, type) {
    if (item == <const> || item == <volatile> || item == <restrict>)
      continue;
    match (item) case %(bitfield *): continue;
    result = cons(item, result);
  }
  return result.reverse();
}

$builtin.emit()
List builtin_class_field_on(List field, List receiver) {
  List type = field[1];
  List value = builtin_class_field(receiver, field[0]);
  match (type) case %((bitfield *) *):
    return builtin_class_cast(builtin_class_value_type(type), value);
  return value;
}

$builtin.emit()
List builtin_class_field_value(List field) =>
  builtin_class_field_on(field, builtin_class_ref("value"));

$builtin.emit()
List builtin_class_allocate_copy(List value) =>
  builtin_class_call("Scope_memdup",
    %(${builtin_class_op(<&>, %($value))} ${builtin_class_size(value)}));

$builtin.emit()
List builtin_class_initializer(String owner, Var heap_value) {
  int heap = !heap_value.equal(%());
  List type = %($owner);
  List receiver = heap ? type : %(* @type);
  List signature = %((func ($receiver)) void);
  List method = x2c_method_resolve(type, "init");
  List value = builtin_class_ref("value");
  if (method && x2c_syntax_type(method).equal(signature)) {
    List declaration = builtin_class_declaration(%(* @signature), "initialize",
      builtin_class_ref(x2c_binding_spelling(method)));
    List argument = heap ? value : builtin_class_op(<&>, %($value));
    return %(seq $declaration
      ${x2c_stmnt_make(builtin_class_call("initialize", %($argument)))});
  }
  String suffix = heap ? ")" : " *)";
  x2c_diagnostic_fail(
    %"class ${owner} requires void ${owner}.init(${owner}${suffix}", %());
}

$builtin.emit()
List builtin_class_new(String owner, List representation, int heap,
                       List named, int positional) {
  List type = %($owner);
  List value = builtin_class_ref("value");
  int aggregate = representation.car() == <struct> ||
                  representation.car() == <union>;
  List parameters = %();
  List initializer;
  if (aggregate) {
    List arguments = %();
    if (positional) {
      foreach (List field, named) {
        parameters = cons(builtin_class_parameter(
          builtin_class_value_type(field[1]), %"field_${field[0]}"),
          parameters);
        arguments = cons(builtin_class_ref(%"field_${field[0]}"), arguments);
      }
      parameters = parameters.reverse();
      initializer = x2c_expr_composite(arguments.reverse());
    }
    else initializer = x2c_expr_composite(%(${x2c_literal_int(0)}));
  }
  else {
    parameters = %(${builtin_class_parameter(representation, "initial")});
    initializer = builtin_class_ref("initial");
  }
  List declared = representation;
  if (heap && !positional && aggregate) {
    declared = type;
    initializer = builtin_class_call("Scope_calloc",
      %(${x2c_literal_int(1)}
        ${builtin_class_size(builtin_class_op(<"*">, %($value)))}));
  }
  List body = %(${builtin_class_declaration(declared, "value", initializer)});
  if (aggregate && !positional) {
    Var heap_value = %();
    if (heap) heap_value = <true>;
    body = body.append(
      %((syntax-recipe class.initializer ($owner $heap_value))));
  }
  List returned = heap && (positional || !aggregate) ?
    builtin_class_allocate_copy(value) : value;
  return builtin_class_default(owner, "new", type, parameters,
    body.append(%(${x2c_stmnt_return(returned)})));
}

$builtin.emit()
List builtin_class_pointer_output(String owner, List value, List out) =>
  builtin_class_method(out, "printf",
    %(${x2c_literal_string(%"<${owner}: 0x%012lX>")}
      ${builtin_class_cast(%(long), value)}));

$builtin.emit()
List builtin_class_box(Symbol tag, int heap) {
  List value = builtin_class_ref("value");
  if (heap)
    return builtin_class_call("Var_new", %(${x2c_literal_symbol(tag)} $value));
  return builtin_class_call("Var_box_record", %(${x2c_literal_symbol(tag)}
    ${builtin_class_op(<&>, %($value))} ${builtin_class_size(value)}));
}

$builtin.emit()
List builtin_class_unbox(String owner, List expression) =>
  %(default ${builtin_class_function(x2c_type_reverse_name("Var", owner),
    %($owner), %(${builtin_class_parameter(%("Var"), "value")}),
    %(${x2c_stmnt_return(expression)}))});

$builtin.emit()
List builtin_class_field_write(List field) {
  List value = builtin_class_field_value(field);
  List type = field[1];
  List writer = %();
  if (builtin_class_pointer(type).equal(%()))
    writer = x2c_method_resolve(type, "write_repr");
  List out = builtin_class_ref("out");
  List expression;
  if (writer) expression = builtin_class_method(value, "write_repr", %($out));
  else if (x2c_type_is_value(type))
    expression = builtin_class_method(builtin_class_cast(%("Var"), value),
                                      "write_repr", %($out));
  else {
    if (builtin_class_pointer(x2c_type_resolve(type)).equal(%()))
      value = builtin_class_op(<&>, %($value));
    expression = builtin_class_pointer_output("opaque", value, out);
  }
  return x2c_stmnt_make(expression);
}

$builtin.emit()
List builtin_class_write_fields(String owner, List fields) {
  List out = builtin_class_ref("out");
  List body = %(${x2c_stmnt_make(builtin_class_method(out, "write",
    %(${x2c_literal_string(%"${owner} { ")})))});
  Var final = fields.last();
  foreach (List field, fields) {
    body = cons(x2c_stmnt_make(builtin_class_method(out, "write",
      %(${x2c_literal_string(%"${field[0]}: ")}))), body);
    body = cons(builtin_class_field_write(field), body);
    if (!field.equal(final))
      body = cons(x2c_stmnt_make(builtin_class_method(out,
        "write", %(${x2c_literal_string(", ")}))), body);
  }
  body = body.reverse();
  return %(seq @body ${x2c_stmnt_return(builtin_class_method(out, "write",
    %(${x2c_literal_string(" }")})))});
}

$builtin.emit()
List builtin_class_writer(String owner, int heap, List fields, String member,
                          List selected) {
  List type = %($owner);
  List value = builtin_class_ref("value");
  List out = builtin_class_ref("out");
  List parameters = %(${builtin_class_parameter(type, "value")}
                      ${builtin_class_parameter(%("Buffer"), "out")});
  List body;
  if (selected)
    body = %(${x2c_stmnt_return(builtin_class_method(out, "write",
      %(${builtin_class_method(value, member, %())})))});
  else if (heap && member == "str")
    body = %(${x2c_stmnt_return(
      builtin_class_pointer_output(owner, value, out))});
  else if (member == "str")
    body = %(${x2c_stmnt_return(
      builtin_class_method(value, "write_repr", %($out)))});
  else {
    body = %();
    if (heap) {
      List null_test = builtin_class_op(<==>,
        %(${builtin_class_cast(%(* void), value)}
          ${builtin_class_cast(%(* void), x2c_literal_int(0))}));
      List fallback = x2c_stmnt_return(
        builtin_class_pointer_output(owner, value, out));
      List path = builtin_class_ref("path");
      List entered = builtin_class_method(path, "enter", %($value));
      body = %((if $null_test $fallback)
        ${builtin_class_declaration(%("RenderPath"), "path", %())}
        (if ${builtin_class_op(<!>, %($entered))} $fallback)
        (defer ${x2c_stmnt_make(builtin_class_method(path, "leave", %()))}));
    }
    body = body.append(%((syntax-recipe class.write-fields
                           ($owner $fields))));
  }
  return builtin_class_default(owner, %"write_${member}", %("Buffer"),
                               parameters, body);
}

$builtin.emit()
List builtin_class_string_method(String owner, String member) {
  List out = builtin_class_ref("out");
  return builtin_class_default(owner, member, %("String"),
    %(${builtin_class_parameter(%($owner), "value")}),
    %(${builtin_class_declaration(%("Buffer"), "out",
        builtin_class_call("Buffer_new", %(${x2c_literal_int(0)})))}
      (defer ${x2c_stmnt_make(builtin_class_method(out, "free", %()))})
      ${x2c_stmnt_make(builtin_class_method(builtin_class_ref("value"),
        %"write_${member}", %($out)))}
      ${x2c_stmnt_return(builtin_class_method(out, "str", %()))}));
}

$builtin.emit()
List builtin_class_equal(String owner, int heap, List fields) {
  List left = builtin_class_ref("left");
  List right = builtin_class_ref("right");
  List body = %();
  if (heap)
    body = %(${x2c_stmnt_return(builtin_class_op(<==>,
      %(${builtin_class_cast(%(* void), left)}
        ${builtin_class_cast(%(* void), right)})))});
  else {
    foreach (List field, fields) {
      List equal = builtin_class_call("Var_equal",
        %(${builtin_class_cast(%("Var"), builtin_class_field_on(field, left))}
          ${builtin_class_cast(%("Var"),
            builtin_class_field_on(field, right))}));
      body = cons(%(if ${builtin_class_op(<!>, %($equal))}
        ${x2c_stmnt_return(x2c_literal_int(0))}), body);
    }
    body = body.reverse().append(%(${x2c_stmnt_return(x2c_literal_int(1))}));
  }
  return builtin_class_default(owner, "equal", %(int),
    %(${builtin_class_parameter(%($owner), "left")}
      ${builtin_class_parameter(%($owner), "right")}), body);
}

$builtin.emit()
List builtin_class_hash(String owner, int heap, List fields) {
  List value = builtin_class_ref("value");
  List body;
  if (heap)
    body = %(${x2c_stmnt_return(builtin_class_call("x2c_hash_word",
      %(${builtin_class_cast(%(unsigned long), value)})))});
  else {
    List hash = builtin_class_ref("hash");
    body = %(${builtin_class_declaration(%(unsigned), "hash",
                                         x2c_literal_int(0))});
    foreach (List field, fields) {
      List field_hash = builtin_class_call("Var_hash",
        %(${builtin_class_cast(%("Var"), builtin_class_field_value(field))}));
      List combined = builtin_class_call("x2c_hash_word",
        %(${builtin_class_op(<^>, %($hash $field_hash))}));
      body = cons(x2c_stmnt_make(
        builtin_class_op(<=>, %($hash $combined))), body);
    }
    body = body.reverse().append(%(${x2c_stmnt_return(hash)}));
  }
  return builtin_class_default(owner, "hash", %(unsigned),
    %(${builtin_class_parameter(%($owner), "value")}), body);
}

$builtin.emit()
List builtin_class_own_method(String owner, String member) {
  List found = x2c_method_resolve(%($owner), member);
  if (found && x2c_binding_spelling(found) == %"${owner}_${member}")
    return found;
  return %();
}

$builtin.emit()
List builtin_class_expand(List capture) {
  String owner = capture[1];
  List type = capture[2];
  if (!type) return %($capture);
  if (builtin_class_pointer(type).equal(%()) && type.car() == <enum>)
    x2c_diagnostic_fail(%"class ${owner} cannot take an enum value " +
      "representation: Var has no fixed tag for an enum",
      %("give the enum a typedef and name that typedef instead"));
  return %($capture (declaration-recipe class.defaults
    ($owner $type ${builtin_class_location()})));
}

$builtin.emit()
List builtin_class_named(List fields) {
  List named = %();
  foreach (List field, fields)
    if (!lisp_string(field.car()).equal(%()) && field.car().str().len() > 0)
      named = cons(field, named);
  return named.reverse();
}

$builtin.emit()
int builtin_class_positional(List fields) {
  int positional = 1;
  foreach (List field, fields)
    if (!x2c_type_is_value(field[1])) positional = 0;
  return positional;
}

$builtin.emit()
List builtin_class_constructor(String owner, List type, List pointee,
  List representation, int heap, int aggregate, int alias, List named,
  int positional) {
  if (builtin_class_own_method(owner, "new")) return %();
  if (heap && !aggregate && !x2c_type_is_value(pointee))
    x2c_diagnostic_fail(%"class ${owner} requires an explicit constructor",
                        %());
  List constructor = builtin_class_new(owner, representation, heap,
                                       named, positional);
  if (alias)
    return %((default-forward ($owner) $type "new" ${constructor[1]}));
  return %($constructor);
}

$builtin.emit()
List builtin_class_defaults(String owner, List type, List location) {
  int heap = !builtin_class_pointer(type).equal(%());
  int alias = type.len() == 1 && !lisp_string(type.car()).equal(%());
  List pointee = heap ? builtin_class_element(type) : type;
  List representation = x2c_type_is_value(pointee) ? pointee :
                        x2c_type_resolve(pointee);
  int aggregate = representation.car() == <struct> ||
                  representation.car() == <union>;
  List fields = aggregate ? x2c_type_layout(representation) : %();
  List named = builtin_class_named(fields);
  int positional = aggregate && representation.car() == <struct> &&
                   builtin_class_positional(fields);
  List body = builtin_class_constructor(owner, type, pointee,
    representation, heap, aggregate, alias, named, positional);
  List value = builtin_class_ref("value");
  List parameter = builtin_class_parameter(%($owner), "value");
  Symbol tag = x2c_type_tag_name(owner);
  if (alias) return %(seq @body);
  if (heap)
    body = body.append(%(
      ${builtin_class_default(owner, "free", %(void), %($parameter),
        %(${x2c_stmnt_make(builtin_class_call("Scope_free", %($value)))}))}
      ${builtin_class_default(owner, "cleanup", %(void), %($parameter),
        %(${x2c_stmnt_make(builtin_class_method(value, "free", %()))}))}
      (adopt ("Cleanup") ($owner) external $location)));
  if (aggregate || heap) {
    List pointer = builtin_class_call("Var_pointer", %($value));
    List unboxed = heap ? builtin_class_cast(%($owner), pointer) :
      builtin_class_op(<"*">, %(${builtin_class_cast(%(* $owner), pointer)}));
    body = body.append(%(
      ${builtin_class_default(owner, "var", %("Var"), %($parameter),
        %(${x2c_stmnt_return(builtin_class_box(tag, heap))}))}
      ${builtin_class_unbox(owner, unboxed)}));
    if (heap || positional)
      body = body.append(%(${builtin_class_equal(owner, heap, named)}
                           ${builtin_class_hash(owner, heap, named)}));
    else if (!x2c_method_resolve(%($owner), "equal") ||
             !x2c_method_resolve(%($owner), "hash"))
      x2c_diagnostic_fail(%"value class ${owner} requires compatible equal " +
                          "and hash methods", %());
    foreach (Var member_value, %("str" "repr")) {
      String member = member_value.str();
      List selected = builtin_class_own_method(owner, member);
      List writer = builtin_class_own_method(owner, %"write_${member}");
      if (!writer)
        body = body.append(%(${builtin_class_writer(owner, heap, named,
                                                    member, selected)}));
      if (!selected)
        body = body.append(%(${builtin_class_string_method(owner, member)}));
    }
    body = body.append(%((adopt ("Var") ($owner) external
      (tag ${x2c_literal_symbol(tag)}) $location)));
  }
  else
    body = body.append(%(
      ${builtin_class_default(owner, "var", %("Var"), %($parameter),
        %(${x2c_stmnt_return(builtin_class_cast(%("Var"),
          builtin_class_cast(representation, value)))}))}
      ${builtin_class_unbox(owner,
        builtin_class_cast(%($owner),
          builtin_class_cast(representation, value)))}
      (adopt ("Var") ($owner) external $representation $location)));
  return %(seq @body);
}

$builtin.write();
