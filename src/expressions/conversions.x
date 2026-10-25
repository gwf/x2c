/*  conversions.x -- destination conversion and crossing checks */

static keyword loop $private.loop;


module int _null_literal(List expr) =>
  _integer_literal_kind(expr, NULL) == <zero> ||
  expr.match(
    %(expr ? $($source_identifier_content(%((binding ? "NULL"))))));

/* explicit converter calls

   A converter call that repeats the conversion its destination already
   performs draws a warning. */

/* An explicit converter call, `value.str()` or `value.var()`, is the most
   recent one parsed from source tokens, kept with its spelling and
   location. A destination parser compares the expression it just parsed
   against it, so nested calls and calls bound from constructed syntax never
   match. An argument list keeps the note left after each argument, since
   its destinations are known only once the call resolves. A converter takes
   only its receiver and is named for its result: the result spelled in
   lower case, or `str` for String. */
module void _note_explicit_converter(
  Compiler c, List call, String method, Token origin) {
  Type result = call.cadr();
  if (!result.match(%(?))) return;
  match (call) case $called(?callee, ?argument): {
    match (callee) case %(expr ? (ident ?binding)):
      if (Compiler.supplies_native_meta(Ast.binding_spelling(binding)))
        return;
    String spelled = result.car().str().lower();
    if (method != spelled && (method != "str" || result !== %("String")))
      return;
    c.protocol_helpers["explicit-converter"] =
      %($call $method $(c.token_location(origin)));
  }
}

/** Reports `parsed` when it is the explicit converter call resolved last
    and `target` converts its receiver on its own: either side is Var, the
    types share one C type, or the receiver declares a converter to the
    target. The call then changes nothing but the spelling. `context` is 0
    for a typed destination, 1 for an interpolation hole, which displays
    every value through `Var.str`, and 2 for a printf-family value, which
    the format converts when it is a Var.
*/
void Compiler.check_explicit_converter(
  Compiler c, List parsed, Type target, int context) {
  _check_noted_converter(
    c, c.protocol_helpers.getdefault("explicit-converter", %()), parsed,
    target, context);
}

/* Each argument of a call spelled in source is checked against its declared
   parameter type. A method receiver selects the method and is not a
   destination, and a call the compiler builds for an operator is not a
   destination the source spelled. */
module void _check_converter_args(
  Compiler c, List result, int method, List notes) {
  List callee = NULL, params = NULL, arguments = NULL, supplied = NULL;
  match (result) case $called(?function, *values): {
    callee = function;
    supplied = values;
    arguments = method ? cdr(values) : values;
    match (callee) case %(expr ((func ?declared) *) ?):
      params = method ? cdr(declared) : declared;
  }
  List n = notes;
  for (List p = params, a = arguments; p && a;
       p = cdr(p), a = cdr(a), n = cdr(n)) {
    if (car(p) is not <list> || car(a) is not <list>) continue;
    List param = car(p), argument = car(a);
    Type expected = param.car() == <param> ? param.type_from_ast() : param;
    _check_noted_converter(c, car(n), argument, expected, 0);
  }
  /* A static printf-family format converts each Var value it consumes. The
     family's positions count the receiver a method call spells before the
     dot, which `arguments` has already dropped. A format the printf
     component cannot read leaves those values as written. */
  const PrintfFn *info = _printf_family(callee);
  if (!info || !c.printf_static_format(supplied[info.fmt_arg])) return;
  int first = info.first_arg - method, index = 0;
  for (List a = arguments, n = notes; a; a = cdr(a), n = cdr(n))
    if (index++ >= first && car(a) is <list>)
      _check_noted_converter(c, car(n), car(a), car(a).list().cadr(), 2);
}

static void _check_noted_converter(
  Compiler c, List noted, List parsed, Type target, int context) {
  if (!noted || !parsed || !target) return;
  (List call, String method, List location) = noted;
  if (call != parsed) return;
  // A qualified target, such as `const char *`, is a different crossing.
  if (target.declared() != target.canonicalize() ||
      c.sym.resolve_key(call.cadr()) != c.sym.resolve_key(target))
    return;
  List receiver = NULL;
  match (call) case %(expr ? $($called(?, %(?first *)))): receiver = first;
  Type source = receiver ? receiver.cadr() : NULL;
  if (!source) return;
  int source_is_var = c.sym.is_var_type(source);
  /* A hole and a format render a Var through `Var.str`, so there `.str()`
     repeats the crossing. A String destination displays any value but
     `void`, while `Var.string` reads the payload and raises for another
     tag: a different operation, never redundant, and `.str()` there asks
     for the display of `void` too. A destination with a payload reader
     takes NULL for another tag, while its explicit reader raises. */
  if (source_is_var && context != 0 && method != "str") return;
  if (source_is_var && context == 0 &&
      (method == "str" || c.sym.is_string_type(target) ||
       _payload_reader(c, target)))
    return;
  /* A Var reaches a numeric scalar other than Symbol through `Var.convert`
     and then a read. `Var.int` already converts, and a raw reader such as
     `Var.integer` skips the conversion, so either call differs. */
  if (source_is_var && target !== %("Symbol") &&
      c.sym.resolve_numeric_type(target))
    return;
  if (context == 2 && !source_is_var) return;
  // A declared crossing to String calls `str`, not a reader like `string`.
  if (!source_is_var && method != "str" && c.sym.is_string_type(target))
    return;
  int implicit = _implicit_converter(
    c, receiver, source, target, source_is_var);
  if (!implicit || _defines_crossing(c, source, target)) return;
  c.protocol_helpers.del("explicit-converter");
  $warn.expressions_call_redundant(c, location, method, target, context);
}

static int _implicit_converter(
  Compiler c, List receiver, Type source, Type target,
  int source_is_var) =>
  source_is_var || c.sym.is_var_type(target) ||
  c.sym.resolve_key(source) == c.sym.resolve_key(target) ||
  !!c.converter_call(receiver, source, target);

/* The function being defined may be the implicit crossing itself, as a
   `Var.row` converter is for a `Row` destination; its explicit calls are how
   the crossing is written, not a repetition of it. */
static int _defines_crossing(Compiler c, Type source, Type target) {
  if (!c.fn_name || !source.match(%(?)) || !target.match(%(?))) return 0;
  String from = source.car().str(), to = target.car().str();
  return c.fn_name == %"$(from)_$(to.lower())" ||
    c.fn_name == %"$(from)_str" || c.fn_name == %"$(from)_var";
}

// C string literals

module int _is_raw_string_literal(List expr) {
  match (expr) {
    case %(expr ? $($grouped(?inner))):
      return _is_raw_string_literal(inner);
    case %(expr ? $($source_literal_content(%(?type ?)))):
      return Type.is_char_pointer_like(type);
    case %(expr ? $($source_operator_content(
        %(? ? ?ontrue ?onfalse)))):
      return _is_raw_string_literal(ontrue) &&
             _is_raw_string_literal(onfalse);
  }
  return 0;
}

module inline int _is_string_like(Compiler c, List expr) {
  if (!expr) return 0;
  Type type = expr.cadr();
  return c.sym.is_string_type(type) ||
         type.is_char_pointer_like();
}

/** Converts a C string literal to `String` where no C meaning applies: as a
    method receiver, a `foreach` collection, or a raise detail. Parentheses
    and a conditional whose arms are both literals count as the literal; any
    other expression is returned unchanged.
*/
List Compiler.promote_string_literal(Compiler c, List expr) =>
  _is_raw_string_literal(expr) ? c.convert_expression(expr, %("String"))
                                    : expr;

/* Promote raw string expressions while caching only exact literal leaves.
   Parentheses and conditional arms retain their evaluation structure; a
   dynamic leaf still calls String_new each time it is selected. */
static List _raw_string_to_string(Compiler c, List expr) {
  match (expr) {
    case %(expr (!or (* char) ((dim *) char))
        $($source_literal_content(
          %((!or (* char) ((dim *) char)) ?)))): {
      List value = %(expr ("String") (call "String_new" (args $expr)));
      if (c.runtime_literals) return value;
      return %(expr ("String") $(c.cache(%(string $value))));
    }
    case %(expr (!or (* char) ((dim *) char))
        $($grouped(?inner))):
      // A statement expression's block converts as one dynamic value.
      match (inner) case %(expr *): {
        List converted = _raw_string_to_string(c, inner);
        return %(expr ("String") (parens $converted));
      }
    case %(expr (!or (* char) ((dim *) char))
        $($source_operator_content(
          %(? ?condition ?ontrue ?onfalse)))): {
      List converted_true = _raw_string_to_string(c, ontrue);
      List converted_false = _raw_string_to_string(c, onfalse);
      return %(expr ("String")
               (op ? $condition $converted_true $converted_false));
    }
  }

  return %(expr ("String") (call "String_new" (args $expr)));
}

/* destination conversion

   A resolved value converts to the type its destination declares. C
   performs every conversion this section returns unchanged. */

/** Adds operations to convert a resolved expression AST to `target`.
    The result may contain converter, boxing, unboxing, `Func`, reference, or
    composite-literal operations. Returns the original expression when C
    performs the conversion implicitly; an unsupported x2c conversion reports
    a type error through `c`. Synthesized operations may add generated
    bindings or immutable literal entries to compiler state.
*/
List Compiler.convert_expression(Compiler c, List expr, Type target) {
  if (!target) return expr;
  // Captured Func lambdas wait for reference-cell rewriting.
  expr = _adapt_lambda_value(c, expr, target);
  Type type = expr.cadr();
  Type declared_source = type, declared_target = target;
  if (type) type = type.canonicalize();
  target = target.canonicalize();
  int type_is_var = c.sym.is_var_type(type);
  int target_is_var = c.sym.is_var_type(target);
  List lifted = _lift_func_value(c, expr, type, target);
  if (lifted) return lifted;
  if (expr.match(%(expr ? (composite ?))))
    return _compound_literal(c, expr, target);
  List conditional = _convert_conditional_arms(c, expr, declared_target);
  if (conditional) return conditional;
  _check_null_reference(c, expr, target);
  if (!type) return _convert_untyped(c, expr, declared_target, target_is_var);
  _check_qualifiers(c, type, target, declared_source, declared_target);
  if (type == target || (type_is_var && target_is_var)) return expr;
  _check_reference_value(c, type, target);
  if (_integer_literal_kind(expr, NULL) == <zero> &&
      c.sym.resolve_key(target).is_pointer())
    return expr;
  _check_object_pointer(c, type, target, type_is_var);
  List converted = _convert_known_value(
    c, expr, type, target, type_is_var, target_is_var);
  if (converted) return converted;
  if (c.sym.resolve_numeric_type(type) &&
      c.sym.resolve_numeric_type(target))
    return expr; // allow implicit numeric conversions
  _check_native_crossing(
    c, expr, type, target, declared_source, declared_target);
  // Everything reaching here is delegated to C: a typedef alias, array or
  // function decay, varargs, a system-header type the collector never
  // sees.  The report_error calls above cover every conversion x2c
  // refuses.
  return expr;
}

static List _adapt_lambda_value(
  Compiler c, List expr, Type target) {
  Type type = expr.cadr();
  if (!type.is_function()) return expr;
  List lowered = c.lower_lambda_expr(expr);
  return lowered == expr ? expr : c.adapt_lambda_arg(
    lowered, c.sym.resolve_key(target.type_from_ast()));
}

static List _lift_func_value(
  Compiler c, List expr, Type type, Type target) {
  Type func_type = c.sym.resolve_key(%("Func"));
  if (c.sym.resolve_key(target) == func_type) {
    List lifted = c.lift_func_expression(expr);
    if (lifted != expr) return lifted;
  }
  if (type && c.sym.resolve_key(type) == func_type &&
      target.is_pointer() && target.dereference().is_function()) {
    $fail.expressions_func_callback(c, NULL);
  }
  return NULL;
}

/* A brace that stays a native initializer outside a declaration becomes a
   compound literal of the destination, because C accepts a bare brace only
   as an initializer. An anonymous struct or union has no spelling for that
   literal. */
static List _compound_literal(
  Compiler c, List composite, Type target) {
  List converted = c.convert_initializer(composite, target, NULL);
  match (converted)
    case %(expr ?type (composite *)): {
      if (Type.tag(type).match(%((gensym *))))
        $fail.expressions_brace_anonymous(c, NULL);
      return %(expr $type (cast $type $converted));
    }
  return converted;
}

/* Only one conditional arm runs; convert each arm when C cannot convert
   the result as a whole. */
static List _convert_conditional_arms(
  Compiler c, List expr, Type declared_target) {
  match (expr) case %(expr ? $($source_operator_content(
      %(?operator ?condition ?ontrue ?onfalse)))): {
    Type true_type = ontrue.cadr(), false_type = onfalse.cadr();
    if (ontrue.list().match(%(expr ? (composite *))) ||
        onfalse.list().match(%(expr ? (composite *))) ||
        (true_type != false_type &&
         !(c.sym.resolve_numeric_type(true_type) &&
           c.sym.resolve_numeric_type(false_type)))) {
      List converted_true = c.convert_expression(ontrue, declared_target);
      List converted_false = c.convert_expression(onfalse, declared_target);
      if (converted_true != ontrue || converted_false != onfalse)
        return %(expr $declared_target
          (op $operator $condition $converted_true $converted_false));
    }
  }
  return NULL;
}

/* A generic selection has no x2c type; each association owns its
   destination conversion because only one association runs. */
static List _convert_generic_arms(
  Compiler c, List expr, Type declared_target) {
  match (expr) case %(expr () $($source_generic_content(
      %(?control *associations)))): {
    Array converted = [];
    int changed = 0;
    foreach (List association in associations) match (association)
      case %(association ?selector ?value): {
        List result = c.convert_expression(value, declared_target);
        if (result != value) changed = 1;
        converted.push(%(association $selector $result));
      }
    if (changed)
      return %(expr $declared_target $(source_generic_content(
        %($control @(converted.list_free())))));
    converted.free();
  }
  return NULL;
}

static List _convert_untyped(
  Compiler c, List expr, Type declared_target, int target_is_var) {
  List generic = _convert_generic_arms(c, expr, declared_target);
  if (generic) return generic;
  if (target_is_var)
    match (expr) {
      case %(expr () $($source_identifier_content(%((binding ? "NULL"))))):
        return %(expr ("Var") (call "Var_null" (args)));
      case %(expr () $($source_identifier_content(%((binding ? ?))))):
        $fail.expressions_var_unresolved(c, NULL);
    }
  return expr;
}

static List _convert_known_value(
  Compiler c, List expr, Type type, Type target,
  int type_is_var, int target_is_var) {
  List reference = _convert_reference(c, expr, type, target);
  if (reference) return reference;
  if (type.match(%((!or (dim *) (!quote *)) char))) {
    List string = _raw_string_to_string(c, expr);
    if (c.sym.is_string_type(target))
      return %(expr $target $(string.caddr()));
    if (target_is_var)
      return %(expr ("Var") (call "String_var" (args $string)));
  }
  if (type_is_var && !target_is_var) {
    List reader = _read_var(c, expr, type, target);
    if (reader) return reader;
  }
  if (!type_is_var && target_is_var) {
    List declared = _declared_var_converter(c, expr, type);
    if (declared) return declared;
  }
  List converted = c.converter_call(expr, type, target);
  if (converted) return converted;
  if (!type_is_var && target_is_var) return _box_var(c, expr, type);
  return NULL;
}

static List _convert_reference(
  Compiler c, List expr, Type type, Type target) {
  // T -> &T: pass the address of an addressable value.
  if (type === cdr(target) && target.is_reference()) {
    if (!_is_addressable(c, expr))
      $fail.expressions_ref_address(c, NULL);
    return %(expr $target (op & (parens $expr)));
  }
  if (type.car() == <&> && target.car() == <opt-ref> &&
      cdr(type) === cdr(target))
    return %(expr $target $expr);
  if (cdr(type) == cdr(target) && type.car() == <&> && target.car() == <*>)
    return %(expr $target $expr);
  if (type.car() == <&> && cdr(type) === target)
    return %(expr $target (op * (parens $expr)));
  return NULL;
}

/** Converts a resolved interpolation segment to `String` when available.
    A missing `String` conversion is expected: the transform boxes that segment
    to `Var` and renders it at runtime.

    A declared numeric converter keeps its formatting; other numeric segments
    use `Var.str`. A segment statically spelled `Var` also uses `Var.str` for
    every
    runtime tag. The ordinary `Var`-to-`String` conversion is
    not equivalent: it
    extracts only a `String` payload and yields empty `String` for every other
    tag.
*/
List Compiler.convert_segment_to_string(Compiler c, List expr) {
  Type type = expr.cadr().type().canonicalize();
  if (c.sym.is_var_type(type))
    return %(expr ("String") (call "Var_str" (args $expr)));
  if (!c.sym.resolve_numeric_type(type))
    return c.convert_expression(expr, %("String"));
  List converted = c.converter_call(expr, type, %("String"));
  if (converted) return converted;
  List boxed = c.convert_expression(expr, %("Var"));
  return %(expr ("String") (call "Var_str" (args $boxed)));
}

// Var crossings

static List _read_var(
  Compiler c, List expr, Type type, Type target) {
  if (target === %("Symbol"))
    return %(expr $target (call "Var_symbol" (args $expr)));
  Type scalar_target = c.sym.resolve_numeric_type(target);
  if (scalar_target) {
    Symbol tag = scalar_target.scalar_tag();
    if (!tag && scalar_target.is_enum()) tag = <i32>;
    String extractor = scalar_target.var_numeric_extractor();
    if (extractor) {
      String tagsym = %"$((unsigned long) tag)";
      List converted = %(expr ("Var") (call "Var_convert" (args
        $expr (expr ("Symbol") $tagsym))));
      return %(expr $target (call $extractor (args $converted)));
    }
  }
  List reader = _var_checked_reader(c, expr, type, target);
  if (reader) return reader;
  /* A Var reaching `Var *` almost always meant its address; unboxing a
     stored Var pointer must be spelled. */
  if (target.is_pointer() && c.sym.is_var_type(target.dereference()))
    $fail.expressions_var_address(c, NULL, target);
  if (target.is_pointer())
    return %(expr $target (call "Var_pointer" (args $expr)));
  if (target.is_typedef_name()) {
    // Unknown system typedefs have no proven pointer payload reader.
    Type resolved = c.sym.resolve_key(target);
    if (resolved.is_pointer())
      return %(expr $target (call "Var_pointer" (args $expr)));
    $fail.expressions_var_convert(c, NULL, target);
  }
  return NULL;
}

/* A built-in payload has an exact tag-checked reader, and a Var(T)
   participant declares its own reverse converter. Either takes the crossing
   ahead of the unchecked pointer payload. An alias with neither reads
   through its nearest ancestor that has one, so an alias of `String` checks
   the tag exactly as `String` does. */
static List _var_checked_reader(
  Compiler c, List expr, Type type, Type target) {
  List owners = target.is_bare_typedef_name()
              ? _typedef_names(c, target).list_free() : %($target);
  foreach (Type owner in owners) {
    List reader = _var_exact_reader(c, expr, owner);
    if (!reader) reader = c.converter_call(expr, type, owner);
    if (reader)
      return owner == target ? reader : %(expr $target $(reader.caddr()));
  }
  return NULL;
}

/* The exact reader for a built-in Var payload is `Var.<target>_payload`,
   or `Var.<target>` when there is none: it checks the tag and yields NULL
   for any other kind. A `String` destination instead reads
   `Var.as_string`: the payload, the display text of another value, or NULL
   for `void`. `Var.pointer` checks nothing, so trying it first let a
   List-valued Var read as a String. Only a raw native pointer with no typed
   Var reader should still take that path. */
static List _var_exact_reader(Compiler c, List expr, Type target) {
  if (!target.match(%(?))) return NULL;
  String name = target.car().str().lower();
  List callee = NULL;
  if (target == %("String")) callee = _var_reader(c, "Var_as_string", target);
  else {
    callee = _payload_reader(c, target);
    if (!callee) callee = _var_reader(c, %"Var_$name", target);
  }
  if (!callee) return NULL;
  Macro called = $called;
  return c.rebuild_expression(target, called(callee, %($expr)));
}

/* The reader that crosses a `Var` to `target` and yields NULL for another
   tag, when the runtime declares one, as a callee; or NULL. */
static List _payload_reader(Compiler c, Type target) =>
  target.match(%(?))
    ? _var_reader(c, %"Var_$(target.car().str().lower())_payload", target)
    : NULL;

/* The global function `reader` from one `Var` to `target`, as a callee, or
   NULL. */
static List _var_reader(Compiler c, String reader, Type target) {
  Type readertype = NULL;
  List binding = c.sym.resolve_global(%($reader), readertype);
  if (!binding || !readertype || readertype.car() is not <list>) return NULL;
  List function = readertype.car();
  (Var function_tag, List parameters) = function;
  if (function_tag != <func> || !parameters || parameters.cdr() ||
      !List.equal(parameters.car(), %("Var")) ||
      readertype.cdr() != target)
    return NULL;
  return %(expr $readertype (ident $binding));
}

/* A declared T.var converter owns custom boxing before tag based boxing. */
static List _declared_var_converter(
  Compiler c, List expr, Type type) {
  Type converter_type = type;
  String converter = converter_type.var_converter();
  if (!converter) {
    c.sym.var_tag_for_type(type, converter_type);
    converter = converter_type.var_converter();
  }
  if (!converter) return NULL;
  String typename = converter_type.car().str(), Type cvrtrtype = NULL;
  List converter_binding = c.sym.resolve_global(%($converter), cvrtrtype);
  if (cvrtrtype === %((func (($typename))) "Var")) {
    List argument = type == converter_type
      ? expr : %(expr $converter_type $expr);
    List callee = %(expr $cvrtrtype (ident $converter_binding));
    Macro called = $called;
    return c.rebuild_expression(%("Var"), called(callee, %($argument)));
  }
  $fail.expressions_var_loss(c, NULL, type);
}

static List _box_var(Compiler c, List expr, Type type) {
  Type tagged_type = NULL;
  Symbol tag = c.sym.var_tag_for_type(type, tagged_type);
  if (!tag && tagged_type && tagged_type.is_enum()) tag = <i32>;
  if (tag) {
    String box = NULL;
    switch (tag) {
      case <long>: box = "Var_box_long"; break;
      case <ulong>: box = "Var_box_ulong"; break;
      case <llong>: box = "Var_box_long_long"; break;
      case <ullong>: box = "Var_box_ulong_long"; break;
      case <ldouble>: box = "Var_box_long_double"; break;
    }
    if (box) return %(expr ("Var") (call $box (args $expr)));
    String tagsymnumstr = %"$((unsigned long) tag)";
    return %(expr ("Var") (call "Var_new" (args
                (expr ("Symbol") $tagsymnumstr) $expr)));
  }
  // Conversion runs after parsing; a NULL token anchors the statement.
  $fail.expressions_var_loss(c, NULL, type);
}

// converter calls

/** The call to the converter that `type`, or the first of its typedef names
    that declares one, provides for `target`, applied to `expr`, or NULL
    when none declares one. */
List Compiler.converter_call(Compiler c, List expr, Type type, Type target) {
  if (!type.match(%(?)) || !target.match(%(?))) return NULL;
  List owners = type.is_bare_typedef_name()
              ? _typedef_names(c, type).list_free() : %($type);
  foreach (Type owner in owners) {
    if (owner == target) return NULL;
    int declared = 0;
    List converted = _converter_owned_call(c, expr, owner, target, declared);
    if (converted || declared) return converted;
  }
  return NULL;
}

static List _converter_owned_call(
  Compiler c, List expr, Type owner, Type target, int &declared) {
  String typename = owner.car().str();
  String convfuncname = _converter_name(owner, target);
  Type cvrtrtype = NULL;
  List converter_binding = c.sym.resolve_global(
    %($convfuncname), cvrtrtype);
  declared = !!converter_binding || !!cvrtrtype;
  List callee = %(expr $cvrtrtype (ident $converter_binding));
  List argument = expr.cadr() == owner
    ? expr : %(expr $owner $expr);
  /* A return typedef may name the same declared type as the target. The
     relaxed form still takes one source argument and must return that type;
     a lowercased method name alone does not establish the result type. */
  if (cvrtrtype != %((func ($owner)) @target) &&
      (!cvrtrtype.match(%((func (($typename))) ?)) ||
       c.sym.normalize_declared_type(cvrtrtype.cdr()) !=
         c.sym.normalize_declared_type(target)))
    return NULL;
  Macro called = $called;
  List call = c.rebuild_expression(target, called(callee, %($argument)));
  return _converted_temporary(c, call, owner, target);
}

/* A package converter uses the package spelling of the external owner. */
static String _converter_name(Type owner, Type target) {
  String typename = owner.car().str(), targetedname = target.car().str();
  String prefix = "";
  int split = targetedname.find("__");
  if (split > 0) {
    prefix = targetedname[0:split + 2];
    targetedname = targetedname[split + 2:];
  }
  return targetedname == "String"
    ? %"$prefix$(typename)_str"
    : %"$prefix$(typename)_$(targetedname.lower())";
}

/** The global builtin boxers and scalar formatters only observe their
    arguments. A custom converter or a shadowed callee may change state. */
int Compiler.is_builtin_converter_call(Compiler c, List expr) {
  match (expr)
    case %(expr ?result (call ?callee (args ?argument))): {
      Type target = result, source = argument.cadr();
      if (!source || !source.match(%(?)) || !target.match(%(?))) return 0;
      if (!source.fixed_var_tag() ||
          !(target == %("Var") ||
            (source.scalar_tag() && target == %("String"))))
        return 0;
      List binding = NULL;
      String spelling = NULL;
      if (callee is <string>) spelling = callee;
      else match (callee)
        case %(expr ? $($source_identifier_content(%(?bound)))): {
          binding = bound;
          spelling = Ast.binding_spelling(binding);
        }
      if (spelling != _converter_name(source, target)) return 0;
      Type declared = NULL;
      return !binding ||
        binding == c.sym.resolve_global(%($spelling), declared);
    }
  return 0;
}

/* A converter's result exists only for the operator that asked for it.
   Only a conversion from a number is known to be fresh; a converter from a
   handle type may return storage its source still owns. */
static List _converted_temporary(
  Compiler c, List call, Type owner, Type target) {
  if (c.sym.resolve_numeric_type(owner) &&
      c.resolve_protocol_member(target, "discard")) {
    match (call)
      case $called(%(expr ? $($source_identifier_content(
          %((!set ?binding (*)))))), *arguments):
        _note_fresh_callee(c, binding);
  }
  return call;
}

// conversion checks

static void _check_null_reference(
  Compiler c, List expr, Type target) {
  if (target.car() != <&>) return;
  if (_integer_literal_kind(expr, NULL) == <zero> || expr.match(
    %(expr () $($source_identifier_content(%((binding ? "NULL")))))))
    $fail.expressions_ref_null(c, NULL, target);
}

/* Same-address conversions must keep qualifiers, including void pointers. */
static void _check_qualifiers(
  Compiler c, Type type, Type target, Type source, Type destination) {
  int take_reference = target.is_reference() && type === cdr(target);
  Type qualified = take_reference ? source.reference() : source;
  if ((take_reference || type == target || cdr(type) == cdr(target) ||
       (type.is_pointer() && target.is_pointer() &&
        (destination.base_type() === %(void) ||
         source.base_type() === %(void)))) &&
      qualified.discards_qualifiers(destination)) {
    $fail.expressions_qualifier_dropped(c, NULL, source, destination);
  }
}

static void _check_reference_value(
  Compiler c, Type type, Type target) {
  /* An optional reference forwards only to another address type. */
  if (type.car() == <opt-ref> && !target.is_reference() &&
      !c.sym.resolve_key(target).is_pointer())
    $fail.expressions_optional_ref_unchecked(c, NULL);
  /* A reference takes an lvalue of its referenced type. */
  if (target.is_reference() && !type.is_reference() &&
      type !== cdr(target))
    $fail.expressions_ref_lvalue(c, NULL, type, target);
}

static void _check_object_pointer(
  Compiler c, Type type, Type target, int type_is_var) {
  if (target.car() != <*> || type_is_var) return;
  Type source = c.sym.resolve_key(type);
  if (source && !source.is_pointer() && !source.is_array() &&
      !source.is_function())
    $fail.expressions_pointer_address(c, NULL, type, target);
}

/* C accepts null pointer constants, pointer decay, and opaque system types.
   Reject only a proven nonzero integer, unrelated known pointers, or two
   typedef names that share a C representation without a declared crossing. */
static void _check_native_crossing(
  Compiler c, List expr, Type type, Type target,
  Type declared_source, Type declared_target) {
  String integer = _not_null_pointer_constant(c, expr);
  if (integer && c.sym.resolve_key(target).is_pointer())
    $fail.expressions_pointer_integer(c, NULL, integer, target);
  if (_unrelated_pointers(c, type, target))
    $fail.expressions_pointer_unrelated(
      c, NULL, declared_source, declared_target);
  if (declared_source.is_bare_typedef_name() &&
      declared_target.is_bare_typedef_name() &&
      declared_source != declared_target &&
      c.sym.resolve_key(declared_target).is_pointer() &&
      !c.sym.resolve_key(declared_source).is_array() &&
      c.sym.resolve_key(declared_source).base_type() !== %(void) &&
      !(declared_target in _typedef_names(c, declared_source)) &&
      !(declared_source in _typedef_names(c, declared_target))) {
    $fail.expressions_typedef_crossing(
      c, NULL, declared_source, declared_target);
  }
}

/* Report whether two types point at provably different things.  Every
   level of both chains is resolved through the typedef table first, so a
   spelling difference, Ast against List or Pool against struct Pool *, is
   not a difference here. */
static int _unrelated_pointers(Compiler c, Type source, Type target) {
  source = c.sym.resolve_key(source);
  target = c.sym.resolve_key(target);
  if (!source.is_pointer() || !target.is_pointer()) return 0;
  loop {
    source = c.sym.resolve_key(source.cdr());
    target = c.sym.resolve_key(target.cdr());
    if (source == target) return 0;
    if (!source.is_pointer() || !target.is_pointer())
      return _known_pointee(source) && _known_pointee(target);
  }
}

/* What a pointer may point at for the rule below to call two pointers
   different: a named struct, union, or enum, or a builtin scalar.  void is
   excluded because C converts it, and a function, an array, or a name the
   resolver left untouched is excluded because the compiler does not know
   enough about it to say. */
static int _known_pointee(Type type) {
  if (type === %(void)) return 0;
  return type.is_aggregate_tag() || type.is_enum_tag() || !!type.scalar();
}

/* A proven nonzero operand yields its short spelling; unknown forms yield
   NULL. C11 6.3.2.3p3 requires an integer constant expression with value zero,
   not just the token 0. x2c does not fold constants, so this recognizes
   only syntactically decidable forms. A wrong guess would reject legal C. */
static String _not_null_pointer_constant(Compiler c, List expr) {
  match (expr) {
    case %(expr ? $($grouped(?inner))):
      return _not_null_pointer_constant(c, inner);
    // sizeof is an integer constant expression, but never a zero-valued
    // one: no type in C has size zero.
    case %(expr ? $($sizeof_grouped(?operand))):
      return "sizeof";
    case %(expr ? $($sizeof_expression(?operand))):
      return "sizeof";
    // Unary minus or plus over a nonzero literal is still nonzero.  The
    // pattern has a fixed length, so a binary use of the same operator,
    // which would need folding, does not match it.
    case %(expr ? $($source_operator_content(%(?oper ?operand)))): {
      Symbol op = oper;
      if (op != <-> && op != <+>) return NULL;
      String inner = NULL;
      if (_integer_literal_kind(operand, inner) != <nonzero>) return NULL;
      return %"$op$inner";
    }
    // A variable is never a permitted operand of an integer constant
    // expression, so an integral one cannot spell a null pointer even when
    // it happens to hold zero at run time.  Enumerations are excluded
    // because an enum constant and a variable of enum type are spelled
    // identically here, and a zero-valued enum constant *is* a null pointer
    // constant.
    case %(expr ?type $($source_identifier_content(
        %((binding ? ?name))))): {
      Type vartype = c.sym.resolve_numeric_type(type);
      if (!vartype || vartype.is_enum() || !vartype.is_integral()) return NULL;
      return name;
    }
  }
  String spelling = NULL;
  if (_integer_literal_kind(expr, spelling) != <nonzero>) return NULL;
  return spelling;
}

/* Answer whether an expression is certainly a zero integer literal,
   certainly a nonzero one, or neither.  Parentheses are unwrapped because
   they are the one wrapper that folds away without evaluation, and
   `out_text` receives the spelling when there is one.

   The tokenizer already accepted the spelling and Type.numeric_literal
   already turned its prefix and suffix into the node's own type, so what
   remains here is whether its value is zero.  A float, a name, or an enum
   constant answers <unknown>; the null-pointer guard below stays silent
   when it cannot decide. */
static Symbol _integer_literal_kind(List expr, String &?out_text) {
  match (expr) {
    case %(expr ? $($grouped(?inner))):
      return _integer_literal_kind(inner, out_text);
    case %(expr ? $($source_literal_content(%(?ltype ?text)))): {
      String spelling = text, Type type = ltype;
      unsigned long long value;
      // A character constant is integral too, but it is not spelled in
      // digits, and '\0' is a null pointer constant.
      if (!type.integer_literal_magnitude(spelling, value)) return <unknown>;
      if (out_text) out_text = spelling;
      return value ? <nonzero> : <zero>;
    }
  }
  return <unknown>;
}
