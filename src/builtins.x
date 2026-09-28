/*  builtins.x -- the built-in macros' compile-time algorithms

    Copyright (c) 2026 Gary William Flake.

    `foreach`, `$scope`, `class`, and `$lisp.bind` expand through these
    functions, which run as native code inside the compiler. The compile-time
    Lisp in `etc/builtin-macros.xlisp` and `etc/lisp-bindings.xlisp` calls
    them by name; `builtin_targets` binds each into the shared session.
*/
#pragma once
#include "x2c.x"
#include "meta.x"
#pragma private
#include "lisp.x"
#include "macros.x"

/* The `lib/meta.x` builders that reach the compiler run here as the copies
   `src/linked-meta.x` links. */
List x2c_expr_field(List receiver, String name);
List x2c_expr_cast(List type, List expression);
List x2c_decl_make(List type, Var name, List initializer);
List x2c_param_make(List type, Var name);

static List builtin_scope_expand(List body, List destinations) {
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

static List builtin_foreach_parameters(List type) =>
  x2c_type_parameters(type);
static List builtin_foreach_return(List type) => x2c_type_return(type);
static Var builtin_foreach_pointer(List type) =>
  x2c_type_is_pointer(type) ? (Var) 1 : %();
static Var builtin_foreach_integral(List type) =>
  x2c_type_is_integral(type) ? (Var) 1 : %();
static List builtin_foreach_element(List type) => x2c_type_element(type);
static List builtin_foreach_protocol(List type, List base, String member) =>
  x2c_protocol_member(type, base, member);

static int builtin_foreach_atom_type(Var type) {
  if (lisp_list(type).equal(%())) return 0;
  List items = type;
  if (items.len() != 1) return 0;
  Var name = items.car();
  return !lisp_string(name).equal(%()) || !lisp_symbol(name).equal(%());
}

static List builtin_foreach_expr(List type, Var binding) =>
  %(expr $type (ident $binding));

static List builtin_foreach_address(List value) => %(expr () (op & $value));

static List builtin_foreach_declare(List type, Var binding, List initializer) {
  List value = %(bind $binding ());
  if (initializer) value = %(op = $value $initializer);
  return %(declare $type (bindings $value));
}

static List builtin_foreach_assign(List target, List value) =>
  %(stmnt (expr () (op = $target $value)));

static int builtin_foreach_valid_outputs(List outputs) {
  if (!outputs) return 1;
  List output = outputs.car();
  if (builtin_foreach_pointer(output).equal(%())) return 0;
  if (!builtin_foreach_atom_type(builtin_foreach_element(output))) return 0;
  return builtin_foreach_valid_outputs(outputs.cdr());
}

static List builtin_foreach_cursor_spec(List collection_type) {
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
  List output_types = outputs.map(
    %!(Var output) => builtin_foreach_element(output));
  /* A fourth element marks reference parameters. */
  if (cursor_parameter.car() == <*>)
    return %($function $cursor_type $output_types);
  return %($function $cursor_type $output_types reference);
}

static List builtin_foreach_cursor_assignments(List targets, List outputs) {
  if (targets.len() == 1)
    return %(${builtin_foreach_assign(targets[0], outputs.last())});
  return %(${builtin_foreach_assign(targets[0], outputs[0])}
           ${builtin_foreach_assign(targets[1], outputs[1])});
}

static List builtin_foreach_cursor_loop(
  List declaration, List collection, List body, List targets,
  List collection_type, List spec, Var object, Var cursor) {
  List function = spec[0], cursor_type = spec[1], types = spec[2];
  int by_reference = spec.len() > 3;
  List outputs = types.map(
    %!(Var type) => %($type ${builtin_foreach_unique("cursor_output")}));
  List values = outputs.map(
    %!(List record) => builtin_foreach_expr(record[0], record[1]));
  /* A reference parameter takes the object itself; a pointer takes its
     address. */
  List addresses = by_reference ? values : values.map(
    %!(List value) => builtin_foreach_address(value));
  List declarations = outputs.map(
    %!(List record) => builtin_foreach_declare(record[0], record[1], %()));
  List object_expression = builtin_foreach_expr(collection_type, object);
  List cursor_expression = builtin_foreach_expr(cursor_type, cursor);
  List cursor_argument = by_reference ? cursor_expression
    : builtin_foreach_address(cursor_expression);
  List arguments = %($object_expression $cursor_argument @addresses);
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

static List builtin_foreach_pair_assignments(
  List targets, List item, Var pair) {
  List expression = builtin_foreach_expr(%("List"), pair);
  return %(${builtin_foreach_declare(%("List"), pair, %())}
    ${builtin_foreach_assign(expression, item)}
    ${builtin_foreach_assign(
      targets[0], x2c_expr_index(expression, x2c_literal_int(0)))}
    ${builtin_foreach_assign(
      targets[1], x2c_expr_index(expression, x2c_literal_int(1)))});
}

static List builtin_foreach_iter_call(List function, List collection) =>
  %(expr ("Iter") (call $function (args $collection)));

static List builtin_foreach_general_loop(
  List declaration, List collection, List body, List targets,
  List collection_type, Var iterator, Var item, Var pair, List converter) {
  int atom = builtin_foreach_atom_type(collection_type);
  String owner = atom ? collection_type.car().str() : "";
  List enumerate = %();
  if (targets.len() == 2 && atom && !collection_type.equal(%("Iter")))
    enumerate = builtin_foreach_reference(owner + "_enumerate");
  List constructor = enumerate ? enumerate : converter;
  List iterator_expression = builtin_foreach_expr(%("Iter"), iterator);
  List item_expression = builtin_foreach_expr(%("Var"), item);
  List initializer = builtin_foreach_complete(
    constructor ? builtin_foreach_iter_call(constructor, collection)
    : collection);
  List next = builtin_foreach_reference("Iter_try_next");
  List output = builtin_foreach_parameters(x2c_syntax_type(next))[1];
  List item_argument = output.car() == <*>
    ? builtin_foreach_address(item_expression) : item_expression;
  List condition = x2c_expr_call(next, %($iterator_expression $item_argument));
  List assignments = targets.len() == 1
    ? %(${builtin_foreach_assign(targets[0], item_expression)})
    : builtin_foreach_pair_assignments(targets, item_expression, pair);
  List loop_body = %(block @assignments $body);
  return %((block $declaration
    ${builtin_foreach_declare(%("Iter"), iterator, initializer)}
    ${builtin_foreach_declare(%("Var"), item, %())}
    (while $condition $loop_body)));
}

static List builtin_foreach_expand(
  List declaration, List collection, List body, Var iterator, Var item,
  Var pair, Var object, Var cursor) {
  collection = builtin_foreach_collection(collection);
  List targets = builtin_foreach_bindings(declaration);
  List type = x2c_syntax_type(collection);
  int direct = type.equal(%("Iter"));
  List converter = %();
  if (!direct)
    converter = type.equal(%("Var"))
      ? builtin_foreach_reference("Var_iter")
      : builtin_foreach_protocol(type, %("Iter"), "iter");
  List spec = direct ? %() : builtin_foreach_cursor_spec(type);
  if (targets.len() != 1 && targets.len() != 2)
    x2c_diagnostic_fail(
      "foreach requires one binding or a two-name destructuring declaration",
      %());
  if (!direct && !converter) {
    Var printable = type;
    x2c_diagnostic_fail(
      "type " + printable.repr() + " is not iterable",
      %("declare an Iter protocol adoption or iterate an Iter directly"));
  }
  if (spec && (targets.len() == 1 || List.len(spec[2]) >= 2))
    return builtin_foreach_cursor_loop(
      declaration, collection, body, targets, type, spec, object, cursor);
  return builtin_foreach_general_loop(
    declaration, collection, body, targets, type, iterator, item, pair,
    converter);
}

/* Class declarations and their deferred defaults. */

static Var builtin_class_pointer(List type) =>
  x2c_type_is_pointer(type) ? (Var) 1 : %();
static List builtin_class_element(List type) => x2c_type_element(type);
static List builtin_class_field(List receiver, String member) =>
  x2c_expr_field(receiver, member);
static List builtin_class_cast(List type, List expression) =>
  x2c_expr_cast(type, expression);
static List builtin_class_declaration(
  List type, Var name, List initializer) =>
  x2c_decl_make(type, name, initializer);
static List builtin_class_parameter(List type, Var name) =>
  x2c_param_make(type, name);

static List builtin_class_ref(String name) => %(expr () (ident ($name)));

static List builtin_class_op(Symbol op, List operands) =>
  %(expr () (op $op @operands));

static List builtin_class_call(String name, List arguments) =>
  x2c_expr_call(builtin_class_ref(name), arguments);

static List builtin_class_method(
  List receiver, String member, List arguments) =>
  x2c_expr_call(builtin_class_field(receiver, member), arguments);

static List builtin_class_size(List expression) =>
  %(expr (unsigned) (sizeof (parens $expression)));

static List builtin_class_function(
  String name, List result, List parameters, List body) {
  List parts = x2c_type_parts(result);
  return %(function ${parts[0]}
    (bind ($name) ((fnmod (params @parameters)) @{parts[1]}))
    (block @body));
}

static List builtin_class_default(
  String owner, String member, List result, List parameters, List body) =>
  %(default ${builtin_class_function(
    %"${owner}_${member}", result, parameters, body)});

static List builtin_class_value_type(List type) {
  List result = %();
  foreach (Var item, type) {
    if (item == <const> || item == <volatile> || item == <restrict>)
      continue;
    match (item) case %(bitfield *): continue;
    result = cons(item, result);
  }
  return result.reverse();
}

static List builtin_class_field_on(List field, List receiver) {
  List type = field[1];
  List value = builtin_class_field(receiver, field[0]);
  match (type) case %((bitfield *) *):
    return builtin_class_cast(builtin_class_value_type(type), value);
  return value;
}

static List builtin_class_field_value(List field) =>
  builtin_class_field_on(field, builtin_class_ref("value"));

static List builtin_class_allocate_copy(List value) =>
  builtin_class_call(
    "Scope_memdup",
    %(${builtin_class_op(<&>, %($value))} ${builtin_class_size(value)}));

static List builtin_class_initializer(String owner, Var heap_value) {
  int heap = !heap_value.equal(%());
  List type = %($owner);
  List receiver = heap ? type : %(* @type);
  List method = x2c_method_resolve(type, "init");
  List value = builtin_class_ref("value");
  if (method) {
    List function = x2c_syntax_type(method).car();
    List declared = function[1];
    List parameters = cons(receiver, declared.cdr());
    int refusable = heap &&
      x2c_syntax_type(method).equal(%((func $parameters) int));
    if (refusable ||
        x2c_syntax_type(method).equal(%((func $parameters) void))) {
      List arguments = %(${heap ? value : builtin_class_op(<&>, %($value))});
      foreach (List parameter, parameters.cdr())
        arguments = cons(
          builtin_class_ref(%"argument_${arguments.len() - 1}"), arguments);
      List call = builtin_class_call(
        x2c_binding_spelling(method), arguments.reverse());
      if (!refusable) return x2c_stmnt_make(call);
      return %(if ${builtin_class_op(<!>, %($call))} (block
        ${x2c_stmnt_make(builtin_class_call("Scope_free", %($value)))}
        ${x2c_stmnt_return(x2c_literal_int(0))}));
    }
  }
  String suffix = heap ? ")" : " *)";
  x2c_diagnostic_fail(
    %"class ${owner} requires void ${owner}.init(${owner}${suffix}", %());
  return %();
}

static List builtin_class_new(
  String owner, List representation, int heap, List named, int positional,
  List extras) {
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
        List parameter = builtin_class_parameter(
          builtin_class_value_type(field[1]), %"field_${field[0]}");
        parameters = cons(parameter, parameters);
        arguments = cons(builtin_class_ref(%"field_${field[0]}"), arguments);
      }
      parameters = parameters.reverse();
      initializer = x2c_expr_composite(arguments.reverse());
    }
    else {
      foreach (List extra, extras)
        parameters = cons(
          builtin_class_parameter(extra, %"argument_${parameters.len()}"),
          parameters);
      parameters = parameters.reverse();
      initializer = x2c_expr_composite(%(${x2c_literal_int(0)}));
    }
  }
  else {
    parameters = %(${builtin_class_parameter(representation, "initial")});
    initializer = builtin_class_ref("initial");
  }
  List declared = representation;
  if (heap && !positional && aggregate) {
    declared = type;
    initializer = builtin_class_call(%"${owner}_alloc", %());
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
  return builtin_class_default(
    owner, "new", type, parameters,
    body.append(%(${x2c_stmnt_return(returned)})));
}

static List builtin_class_pointer_output(String owner, List value, List out) =>
  builtin_class_method(
    out, "printf",
    %(${x2c_literal_string(%"<${owner}: 0x%012lX>")}
      ${builtin_class_cast(%(long), value)}));

static List builtin_class_box(Symbol tag, int heap) {
  List value = builtin_class_ref("value");
  if (heap)
    return builtin_class_call("Var_new", %(${x2c_literal_symbol(tag)} $value));
  return builtin_class_call(
    "Var_box_record",
    %(${x2c_literal_symbol(tag)} ${builtin_class_op(<&>, %($value))}
      ${builtin_class_size(value)}));
}

static List builtin_class_unbox(String owner, List expression) =>
  %(default ${builtin_class_function(
    x2c_type_reverse_name("Var", owner), %($owner),
    %(${builtin_class_parameter(%("Var"), "value")}),
    %(${x2c_stmnt_return(expression)}))});

static List builtin_class_field_write(List field) {
  List value = builtin_class_field_value(field);
  List type = field[1];
  List out = builtin_class_ref("out");
  int array = 0;
  match (type) case %((dim *) *): array = 1;
  List writer = %();
  if (!array && builtin_class_pointer(type).equal(%()))
    writer = x2c_method_resolve(type, "write_repr");
  List expression;
  if (writer) expression = builtin_class_method(value, "write_repr", %($out));
  else if (!array && x2c_type_is_value(type))
    expression = builtin_class_method(
      builtin_class_cast(%("Var"), value), "write_repr", %($out));
  else {
    if (!array && builtin_class_pointer(x2c_type_resolve(type)).equal(%()))
      value = builtin_class_op(<&>, %($value));
    expression = builtin_class_pointer_output("opaque", value, out);
  }
  return x2c_stmnt_make(expression);
}

static List builtin_class_write_fields(String owner, List fields) {
  List out = builtin_class_ref("out");
  List opening = builtin_class_method(
    out, "write", %(${x2c_literal_string(%"${owner} { ")}));
  List body = %(${x2c_stmnt_make(opening)});
  Var final = fields.last();
  foreach (List field, fields) {
    List label = builtin_class_method(
      out, "write", %(${x2c_literal_string(%"${field[0]}: ")}));
    body = cons(x2c_stmnt_make(label), body);
    body = cons(builtin_class_field_write(field), body);
    if (!field.equal(final)) {
      List separator = builtin_class_method(
        out, "write", %(${x2c_literal_string(", ")}));
      body = cons(x2c_stmnt_make(separator), body);
    }
  }
  body = body.reverse();
  return %(seq @body ${x2c_stmnt_return(
    builtin_class_method(out, "write", %(${x2c_literal_string(" }")})))});
}

static List builtin_class_writer(
  String owner, int heap, List fields, String member, List selected) {
  List type = %($owner);
  List value = builtin_class_ref("value");
  List out = builtin_class_ref("out");
  List parameters = %(${builtin_class_parameter(type, "value")}
                      ${builtin_class_parameter(%("Buffer"), "out")});
  List body;
  if (selected) {
    List written = builtin_class_method(
      out, "write", %(${builtin_class_method(value, member, %())}));
    body = %(${x2c_stmnt_return(written)});
  }
  else if (heap && member == "str")
    body = %(${x2c_stmnt_return(
      builtin_class_pointer_output(owner, value, out))});
  else if (member == "str")
    body = %(${x2c_stmnt_return(
      builtin_class_method(value, "write_repr", %($out)))});
  else {
    body = %();
    if (heap) {
      List null_test = builtin_class_op(
        <==>,
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
    body = body.append(%((syntax-recipe class.write-fields ($owner $fields))));
  }
  return builtin_class_default(
    owner, %"write_${member}", %("Buffer"), parameters, body);
}

static List builtin_class_string_method(String owner, String member) {
  List out = builtin_class_ref("out");
  List write = builtin_class_method(
    builtin_class_ref("value"), %"write_${member}", %($out));
  return builtin_class_default(
    owner, member, %("String"),
    %(${builtin_class_parameter(%($owner), "value")}),
    %(${builtin_class_declaration(
      %("Buffer"), "out",
      builtin_class_call("Buffer_new", %(${x2c_literal_int(0)})))}
      (defer ${x2c_stmnt_make(builtin_class_method(out, "free", %()))})
      ${x2c_stmnt_make(write)}
      ${x2c_stmnt_return(builtin_class_method(out, "str", %()))}));
}

static List builtin_class_equal(String owner, int heap, List fields) {
  List left = builtin_class_ref("left");
  List right = builtin_class_ref("right");
  List body = %();
  if (heap) {
    List same = builtin_class_op(
      <==>,
      %(${builtin_class_cast(%(* void), left)}
        ${builtin_class_cast(%(* void), right)}));
    body = %(${x2c_stmnt_return(same)});
  }
  else {
    foreach (List field, fields) {
      List equal = builtin_class_call(
        "Var_equal",
        %(${builtin_class_cast(%("Var"), builtin_class_field_on(field, left))}
          ${builtin_class_cast(
            %("Var"), builtin_class_field_on(field, right))}));
      body = cons(
        %(if ${builtin_class_op(<!>, %($equal))}
          ${x2c_stmnt_return(x2c_literal_int(0))}),
        body);
    }
    body = body.reverse().append(%(${x2c_stmnt_return(x2c_literal_int(1))}));
  }
  return builtin_class_default(
    owner, "equal", %(int),
    %(${builtin_class_parameter(%($owner), "left")}
      ${builtin_class_parameter(%($owner), "right")}), body);
}

static List builtin_class_hash(String owner, int heap, List fields) {
  List value = builtin_class_ref("value");
  List body;
  if (heap) {
    List hashed = builtin_class_call(
      "x2c_hash_word", %(${builtin_class_cast(%(unsigned long), value)}));
    body = %(${x2c_stmnt_return(hashed)});
  }
  else {
    List hash = builtin_class_ref("hash");
    body = %(${builtin_class_declaration(
      %(unsigned), "hash", x2c_literal_int(0))});
    foreach (List field, fields) {
      List field_hash = builtin_class_call(
        "Var_hash",
        %(${builtin_class_cast(%("Var"), builtin_class_field_value(field))}));
      List combined = builtin_class_call(
        "x2c_hash_word", %(${builtin_class_op(<^>, %($hash $field_hash))}));
      body = cons(
        x2c_stmnt_make(builtin_class_op(<=>, %($hash $combined))), body);
    }
    body = body.reverse().append(%(${x2c_stmnt_return(hash)}));
  }
  return builtin_class_default(
    owner, "hash", %(unsigned),
    %(${builtin_class_parameter(%($owner), "value")}), body);
}

static List builtin_class_own_method(String owner, String member) {
  List found = x2c_method_resolve(%($owner), member);
  if (found && x2c_binding_spelling(found) == %"${owner}_${member}")
    return found;
  return %();
}

static List builtin_class_expand(List capture) {
  String owner = capture[1];
  List type = capture[2];
  if (!type) return %($capture);
  if (builtin_class_pointer(type).equal(%()) && type.car() == <enum>)
    x2c_diagnostic_fail(
      %"class ${owner} cannot take an enum value " +
      "representation: Var has no fixed tag for an enum",
      %("give the enum a typedef and name that typedef instead"));
  return %($capture (declaration-recipe class.defaults
    ($owner $type ${builtin_class_location()})));
}

static List builtin_class_named(List fields) {
  List named = %();
  foreach (List field, fields)
    if (!lisp_string(field.car()).equal(%()) && field.car().str().len() > 0)
      named = cons(field, named);
  return named.reverse();
}

static int builtin_class_positional(List fields) {
  int positional = 1;
  foreach (List field, fields)
    if (!x2c_type_is_value(field[1])) positional = 0;
  return positional;
}

static List builtin_class_constructor(
  String owner, List type, List pointee, List representation, int heap,
  int aggregate, int alias, List named, int positional) {
  if (builtin_class_own_method(owner, "new")) return %();
  List extras = %();
  List initialize = builtin_class_own_method(owner, "init");
  if (aggregate && !alias && initialize) {
    List function = x2c_syntax_type(initialize).car();
    List declared = function[1];
    extras = declared.cdr();
  }
  if (heap && !aggregate && !x2c_type_is_value(pointee))
    x2c_diagnostic_fail(
      %"class ${owner} requires an explicit constructor", %());
  List constructor = builtin_class_new(
    owner, representation, heap, named, positional && !initialize, extras);
  if (alias)
    return %((default-forward ($owner) $type "new" ${constructor[1]}));
  return %($constructor);
}

static List builtin_class_defaults(String owner, List type, List location) {
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
  List body = builtin_class_constructor(
    owner, type, pointee, representation, heap, aggregate, alias, named,
    positional);
  List value = builtin_class_ref("value");
  List parameter = builtin_class_parameter(%($owner), "value");
  Symbol tag = x2c_type_tag_name(owner);
  if (alias) return %(seq @body);
  List drop = builtin_class_own_method(owner, "drop");
  List release = %(${x2c_stmnt_make(
    builtin_class_call("Scope_free", %($value)))});
  if (drop) {
    List dropped = builtin_class_call(x2c_binding_spelling(drop), %($value));
    release = cons(%(if $value ${x2c_stmnt_make(dropped)}), release);
  }
  if (heap && aggregate) {
    List allocated = builtin_class_call(
      "Scope_calloc",
      %(${x2c_literal_int(1)}
        ${builtin_class_size(builtin_class_op(<"*">, %($value)))}));
    List alloc = builtin_class_default(
      owner, "alloc", %($owner), %(),
      %(${builtin_class_declaration(%($owner), "value", allocated)}
        ${x2c_stmnt_return(value)}));
    body = body.append(%($alloc));
  }
  if (heap) {
    List free_method = builtin_class_default(
      owner, "free", %(void), %($parameter), release);
    List cleanup_method = builtin_class_default(
      owner, "cleanup", %(void), %($parameter),
      %(${x2c_stmnt_make(builtin_class_method(value, "free", %()))}));
    body = body.append(
      %($free_method $cleanup_method
        (adopt ("Cleanup") ($owner) external $location)));
  }
  if (aggregate || heap) {
    List pointer = builtin_class_call("Var_pointer", %($value));
    List unboxed = heap ? builtin_class_cast(%($owner), pointer) :
      builtin_class_op(<"*">, %(${builtin_class_cast(%(* $owner), pointer)}));
    List var_method = builtin_class_default(
      owner, "var", %("Var"), %($parameter),
      %(${x2c_stmnt_return(builtin_class_box(tag, heap))}));
    body = body.append(
      %($var_method ${builtin_class_unbox(owner, unboxed)}));
    if (heap || positional)
      body = body.append(
        %(${builtin_class_equal(owner, heap, named)}
          ${builtin_class_hash(owner, heap, named)}));
    else if (!x2c_method_resolve(%($owner), "equal") ||
             !x2c_method_resolve(%($owner), "hash"))
      x2c_diagnostic_fail(
        %"value class ${owner} requires compatible equal " +
        "and hash methods", %());
    foreach (Var member_value, %("str" "repr")) {
      String member = member_value.str();
      List selected = builtin_class_own_method(owner, member);
      List writer = builtin_class_own_method(owner, %"write_${member}");
      if (!writer)
        body = body.append(
          %(${builtin_class_writer(owner, heap, named, member, selected)}));
      if (!selected)
        body = body.append(%(${builtin_class_string_method(owner, member)}));
    }
    body = body.append(
      %((adopt ("Var") ($owner) external
          (tag ${x2c_literal_symbol(tag)}) $location)));
  }
  else {
    List boxed = builtin_class_cast(
      %("Var"), builtin_class_cast(representation, value));
    List unboxed = builtin_class_cast(
      %($owner), builtin_class_cast(representation, value));
    List var_method = builtin_class_default(
      owner, "var", %("Var"), %($parameter), %(${x2c_stmnt_return(boxed)}));
    body = body.append(
      %($var_method ${builtin_class_unbox(owner, unboxed)}
        (adopt ("Var") ($owner) external $representation $location)));
  }
  return %(seq @body);
}

/* --- native Lisp bindings ------------------------------------------------ */

static List binding_reference(String name) =>
  builtin_foreach_reference(name);
static Var binding_literal_value(Var node) => x2c_literal_value(node);
static void binding_fail(String message, Var node) {
  x2c_diagnostic_fail(message, %("value: ${node.repr()}"));
}

static List binding_call(String name, List arguments) =>
  x2c_expr_call(x2c_expr_ident(x2c_ident(name)), arguments);

static List binding_name_signature(String name) =>
  binding_native_type(binding_reference(name));

static String binding_name(Var node) {
  Var value = binding_literal_value(node);
  if (!lisp_string(value).equal(%())) return value.str();
  binding_fail("native Lisp binding name requires a String literal", node);
  return NULL;
}

static List binding_rows_for(String group, List rows) {
  List selected = %();
  foreach (List row, rows)
    if (row.car().equal(group)) selected = cons(row, selected);
  return selected.reverse();
}

static List binding_record(
  Var group, Var name, List function, List all_rows, List sealed) {
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
      x2c_diagnostic_fail(
        "duplicate native Lisp binding name",
        %("group: ${group_name}" "name: ${lisp_name}"));
  return %(($group_name $lisp_name $function_name $type) @all_rows);
}

static List binding_statement(List lisp, List row) {
  match (row) case %(?group ?name ?function ?type): {
    List func = binding_call(
      "Func_new",
      %(${x2c_expr_ident(x2c_ident(function))} ${binding_literal_list(type)}));
    return %(stmnt ${binding_call(
      "Lisp_bind", %($lisp ${x2c_literal_string(name)} $func))});
  }
  return %();
}

static List binding_install_rows(String group, List all_rows) {
  List rows = binding_rows_for(group, all_rows).reverse();
  if (!rows)
    x2c_diagnostic_fail(
      "unknown native Lisp binding group", %("group: ${group}"));
  return rows;
}

static List binding_statements(List lisp, List rows) {
  List statements = %();
  foreach (List row, rows)
    statements = cons(binding_statement(lisp, row), statements);
  return statements.reverse();
}

static List binding_target(String bind_name, String name, String maker) {
  List func = binding_call(
    maker,
    %(${x2c_expr_ident(x2c_ident(name))}
      ${binding_literal_list(binding_name_signature(name))}));
  return %(${binding_call("String_var", %(${x2c_literal_string(bind_name)}))}
    ${binding_call("Func_var", %($func))});
}

static List binding_target_row(List row) {
  match (row) {
    case %(?name (as ?bind)):
      return binding_target(bind.str(), name.str(), "Func_new");
    case %(?name): return binding_target(name.str(), name.str(), "Func_new");
    case %(?name ?marker):
      return binding_target(name.str(), name.str(), "Func_new_rest");
  }
  return %();
}

static List binding_targets(List rows) {
  List arguments = %();
  foreach (List row, rows) {
    List pair = binding_target_row(row);
    foreach (Var item, pair) arguments = cons(item, arguments);
  }
  return binding_call(
    "Map_update_n",
    %(${binding_call("Map_new", %())} ${x2c_literal_int(rows.len())}
      @{arguments.reverse()}));
}

/* --- the Lisp names ------------------------------------------------------ */

macro Statement $builtin.row(Expr $rows, Expr $name, Expr $function) {
  $rows[$name] = Func.new(
    $function, $(_x2c.literal.list (_x2c.function.native-type $function)));
}

/* Func calls: the call template prepares its arguments through this. */
List x2c_func_call_arguments(List function, List storage, List arguments);

/* Try lowering: src/transform.x writes a try region through templates
   whose slots call these. */
List builtin_try_catch_site(List frame, List clause);
List builtin_catch_patterns(List patterns, List items);
List builtin_try_landing(List frame, List clause, List cleanup);
List builtin_catch_cases(List selected, List arms);
List builtin_defer_record(List record, List callback, List environment,
                          List records);
List builtin_defer_captures(List environment, List records);

/** Places the lowered statements that leave a try region after it, with
    the effect that marks the unit as needing exception support. */
List builtin_try_cleanup_placement(Var cleanup) {
  Atom token = Atom.intern("?__try_cleanup");
  match (cleanup)
    case %(code-value ? ?statements ?):
      return %(code-value "lowered" $token ((cleanup $token $statements)));
  x2c_diagnostic_fail("try cleanup must be lowered statements", %());
  return NULL;
}

/** Returns each built-in algorithm by the name compile-time code calls it
    with. */
Map builtin_targets(void) {
  Map rows = {};
  $builtin.row(rows, "builtin_scope_expand", builtin_scope_expand);
  $builtin.row(rows, "x2c_func_call_arguments", x2c_func_call_arguments);
  $builtin.row(rows, "builtin_defer_record", builtin_defer_record);
  $builtin.row(rows, "builtin_defer_captures", builtin_defer_captures);
  $builtin.row(rows, "builtin_try_catch_site", builtin_try_catch_site);
  $builtin.row(rows, "builtin_try_landing", builtin_try_landing);
  $builtin.row(rows, "builtin_catch_patterns", builtin_catch_patterns);
  $builtin.row(rows, "builtin_catch_cases", builtin_catch_cases);
  $builtin.row(rows, "builtin_try_cleanup_placement", builtin_try_cleanup_placement);
  $builtin.row(rows, "builtin_foreach_atom_type", builtin_foreach_atom_type);
  $builtin.row(rows, "builtin_foreach_expr", builtin_foreach_expr);
  $builtin.row(rows, "builtin_foreach_address", builtin_foreach_address);
  $builtin.row(rows, "builtin_foreach_declare", builtin_foreach_declare);
  $builtin.row(rows, "builtin_foreach_assign", builtin_foreach_assign);
  $builtin.row(rows, "builtin_foreach_valid_outputs", builtin_foreach_valid_outputs);
  $builtin.row(rows, "builtin_foreach_cursor_spec", builtin_foreach_cursor_spec);
  $builtin.row(rows, "builtin_foreach_cursor_assignments", builtin_foreach_cursor_assignments);
  $builtin.row(rows, "builtin_foreach_cursor_loop", builtin_foreach_cursor_loop);
  $builtin.row(rows, "builtin_foreach_pair_assignments", builtin_foreach_pair_assignments);
  $builtin.row(rows, "builtin_foreach_iter_call", builtin_foreach_iter_call);
  $builtin.row(rows, "builtin_foreach_general_loop", builtin_foreach_general_loop);
  $builtin.row(rows, "builtin_foreach_expand", builtin_foreach_expand);
  $builtin.row(rows, "builtin_class_ref", builtin_class_ref);
  $builtin.row(rows, "builtin_class_op", builtin_class_op);
  $builtin.row(rows, "builtin_class_call", builtin_class_call);
  $builtin.row(rows, "builtin_class_method", builtin_class_method);
  $builtin.row(rows, "builtin_class_size", builtin_class_size);
  $builtin.row(rows, "builtin_class_function", builtin_class_function);
  $builtin.row(rows, "builtin_class_default", builtin_class_default);
  $builtin.row(rows, "builtin_class_value_type", builtin_class_value_type);
  $builtin.row(rows, "builtin_class_field_on", builtin_class_field_on);
  $builtin.row(rows, "builtin_class_field_value", builtin_class_field_value);
  $builtin.row(rows, "builtin_class_allocate_copy", builtin_class_allocate_copy);
  $builtin.row(rows, "builtin_class_initializer", builtin_class_initializer);
  $builtin.row(rows, "builtin_class_new", builtin_class_new);
  $builtin.row(rows, "builtin_class_pointer_output", builtin_class_pointer_output);
  $builtin.row(rows, "builtin_class_box", builtin_class_box);
  $builtin.row(rows, "builtin_class_unbox", builtin_class_unbox);
  $builtin.row(rows, "builtin_class_field_write", builtin_class_field_write);
  $builtin.row(rows, "builtin_class_write_fields", builtin_class_write_fields);
  $builtin.row(rows, "builtin_class_writer", builtin_class_writer);
  $builtin.row(rows, "builtin_class_string_method", builtin_class_string_method);
  $builtin.row(rows, "builtin_class_equal", builtin_class_equal);
  $builtin.row(rows, "builtin_class_hash", builtin_class_hash);
  $builtin.row(rows, "builtin_class_own_method", builtin_class_own_method);
  $builtin.row(rows, "builtin_class_expand", builtin_class_expand);
  $builtin.row(rows, "builtin_class_named", builtin_class_named);
  $builtin.row(rows, "builtin_class_positional", builtin_class_positional);
  $builtin.row(rows, "builtin_class_constructor", builtin_class_constructor);
  $builtin.row(rows, "builtin_class_defaults", builtin_class_defaults);
  $builtin.row(rows, "binding_call", binding_call);
  $builtin.row(rows, "binding_name_signature", binding_name_signature);
  $builtin.row(rows, "binding_name", binding_name);
  $builtin.row(rows, "binding_rows_for", binding_rows_for);
  $builtin.row(rows, "binding_record", binding_record);
  $builtin.row(rows, "binding_statement", binding_statement);
  $builtin.row(rows, "binding_install_rows", binding_install_rows);
  $builtin.row(rows, "binding_statements", binding_statements);
  $builtin.row(rows, "binding_target", binding_target);
  $builtin.row(rows, "binding_target_row", binding_target_row);
  $builtin.row(rows, "binding_targets", binding_targets);
  return rows;
}
