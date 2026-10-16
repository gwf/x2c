/*  calls.x -- call preparation and recognition */


// calls

module List _native(Resolve &r, String callee, List supplied) {
  List arguments = _resolve_call_arguments(r.c, NULL, supplied, r.origin);
  return %(expr ${r.type} (call $callee (args @arguments)));
}

/* One call being resolved: its expected result type, the arguments it
   supplies, and its origin. A method call adds the receiver, its type, and
   the member it selects. */
static typedef struct CallSite {
  Compiler c;
  Type result_type, type;
  List receiver, field, supplied;
  Token origin;
  String method;
} CallSite;

module List _call(Resolve &r, List function, List supplied) {
  CallSite site = {
    .c = r.c, .result_type = r.type, .supplied = supplied,
    .origin = r.origin};
  match (function)
    case %(expr ? ${$source_operator_content(
        %(. ?receiver (!set ?field (?name))))}):
      return _method(site, receiver, field);
  return _function(site, function);
}

static List _function(CallSite &k, List function) {
  List resolved = k.c.resolve_expression(function, k.origin);
  Type type = resolved.cadr(), func_type = k.c.sym.resolve_key(%("Func"));
  if (type && k.c.sym.resolve_key(type) == func_type)
    return _resolve_func_call(k.c, resolved, k.supplied, k.origin);
  return _finish(k, k.result_type, resolved, type, NULL);
}

static List _finish(
  CallSite &k, Type result_type, List callee, Type callee_type,
  List receiver) {
  if (result_type === %(<macro-expr>)) result_type = NULL;
  Type applied = callee_type.apply();
  if (!applied && callee_type)
    applied = k.c.sym.resolve_key(callee_type).apply();
  List arguments = _resolve_call_arguments(
    k.c, receiver, k.supplied, k.origin);
  if (_deferred_call(callee, receiver, arguments))
    result_type = %(<macro-expr>);
  if (!result_type) result_type = applied;
  if (receiver && result_type !== %(<macro-expr>))
    _check_arity(k, callee_type, arguments);
  k.c.check_meta_call(callee, k.origin);
  callee = _discarding_callee(k.c, callee, callee_type, arguments);
  Macro called = $called;
  return k.c.rebuild_expression(result_type, called(callee, arguments));
}

/* A call waits for macro substitution when its callee, its receiver, or
   one of its arguments does. */
static int _deferred_call(List callee, List receiver, List arguments) {
  if (_deferred_receiver(callee) ||
      (receiver && _deferred_receiver(receiver)))
    return 1;
  foreach (Var argument, arguments)
    if (argument is <list> && !argument.is_nil()) {
      List syntax = argument;
      if (_deferred_receiver(syntax) ||
          syntax.car() == <macro-bind> || syntax.car() == <macro-slot>)
        return 1;
    }
  return 0;
}

static void _check_arity(
  CallSite &k, Type callee_type, List arguments) {
  match (callee_type)
    case %((func (!set ?parameters (*))) *):
      if (!_parameters_variadic(parameters) &&
          arguments.len() > List.len(parameters))
        $fail.expressions_method_arity(k.c, k.origin, parameters, arguments);
}

static int _parameters_variadic(List parameters) {
  foreach (Var parameter, parameters)
    if (parameter == <...> || (parameter is <list> && !parameter.is_nil() &&
        parameter.car() == <...>))
      return 1;
  return 0;
}

static List _resolve_call_arguments(
  Compiler c, List receiver, List supplied, Token origin) {
  Array arguments = [];
  if (receiver) arguments.push(receiver);
  if (!receiver && !supplied) supplied = %((expr (void) ()));
  if (receiver && supplied === %((expr (void) ()))) supplied = NULL;
  foreach (Var argument, supplied) {
    int slot = argument is <list> && !argument.is_nil() &&
               argument.car() == <macro-slot>;
    Var value = c.evaluate_macro_slot(argument);
    if (value is <list> && !value.is_nil() &&
        value.car() == <seq>)
      foreach (List item, value.list().cdr())
        arguments.push(c.resolve_expression(item, origin));
    else if (slot)
      arguments.push(
        c.resolve_expression(
          c.lift_macro_lisp_expression(value, origin), origin)
      );
    else if (value is <list>)
      arguments.push(c.resolve_expression(value, origin));
    else arguments.push(value);
  }
  return arguments.list_free();
}

/* A call whose receiver or argument is an unnamed operator temporary goes
   through a helper that discards that temporary once the call returns. */
static List _discarding_callee(
  Compiler c, List callee, Type callee_type, List arguments) {
  List binding = NULL;
  match (callee) case %(expr ? ${$source_identifier_content(
      %((!set ?bound (*))))}): binding = bound;
  if (!binding || !callee_type.match(%((func *) *)) ||
      %"discard-helper ${(long) binding}" in c.protocol_helpers)
    return callee;
  int which = 0, index = 0;
  foreach (Var argument, arguments) {
    if (argument is <list> && _is_operator_temporary(c, argument))
      which |= 1 << index;
    index++;
  }
  if (!which) return callee;
  String stem = Ast.binding_spelling(binding);
  if (!stem) return callee;
  List helper = c.discard_helper(binding, callee_type, stem, which);
  if (!helper) return callee;
  List (helper_binding, signature) = helper;
  return %(expr $signature (ident $helper_binding));
}

// member invocation

static List _method(CallSite &k, List receiver, List field) {
  k.receiver = receiver;
  k.field = field;
  List resolution = _lookup(k);
  if (!resolution && _deferred_receiver(k.receiver)) {
    List callee = %(expr (<macro-expr>) (op . ${k.receiver} ${k.field}));
    return _finish(k, k.result_type, callee, NULL, NULL);
  }
  /* A template's free owner can name a type only where it lands, and
     `T.member` there calls `T_member`, as the parser folds it. */
  if (!resolution) match (k.type) case %(typedef ?(String owner)):
    return _function(k, %(expr () (ident (${%"${owner}_${k.method}"}))));
  if (!resolution && !k.c.macro_holes && k.c.rewrite_rules) {
    List rewritten = _member_rewrite(k);
    if (rewritten) return rewritten;
  }
  if (!resolution) {
    Var name = k.field.car();
    $fail.expressions_method_missing(k.c, k.origin, k.type, name);
  }
  match (resolution) {
    case %(ambiguous *packages):
      _report_method_ambiguity(k.c, k.type, k.method, packages, k.origin);
    case %(method ?binding (!set ?signature
      ((func (!set ?parameters (?declared *))) *returns))):
      return _bound(k, binding, signature, declared, parameters, returns);
    case %(field ?access ?field_type): {
      List callee = %(expr $field_type
        (op $access ${k.receiver} ${k.field}));
      return _finish(k, k.result_type, callee, field_type, NULL);
    }
  }
  return NULL;
}

/* Member rules are keyed by the receiver's type, or by a field keyword the
   aggregate it reaches through typedefs or one pointer declares. */
static List _member_rewrite(CallSite &k) {
  List source = %(expr () (call
    (expr () (op . ${k.receiver} ${k.field})) (args @{k.supplied})));
  List rewritten = k.c.rewrite(
    <member>, k.type.canonicalize(), source, <expression>, NULL, k.origin);
  Type aggregate = rewritten ? NULL : k.c.sym.aggregate_of(k.type);
  return aggregate
    ? k.c.marked_rewrite(aggregate, source, k.origin) : rewritten;
}

static List _lookup(CallSite &k) {
  k.receiver = k.c.resolve_expression(k.receiver, k.origin);
  k.type = k.receiver.cadr();
  k.method = k.field.car().str();
  List resolution = k.c.resolve_postfix_member(k.type, k.field, <.>, 1);
  if (!resolution && _is_raw_string_literal(k.receiver)) {
    k.receiver = k.c.promote_string_literal(k.receiver);
    k.type = k.receiver.cadr();
    resolution = k.c.resolve_postfix_member(k.type, k.field, <.>, 1);
  }
  return resolution;
}

static List _bound(
  CallSite &k, List binding, Type signature, List declared,
  List parameters, List returns) {
  k.receiver = _method_bind(k.c, k.receiver, k.type, declared, k.origin);
  List callee = %(expr ((func $parameters) $returns) (ident $binding));
  return _finish(k, signature.apply(), callee, signature, k.receiver);
}

static List _method_bind(
  Compiler c, List receiver, Type type, Type declared, Token origin) {
  if (!declared || !type) return receiver;
  Type target = declared.canonicalize(), source = type.canonicalize();
  Type named = source.is_aggregate() ? _tag_typedef(c, source) : NULL;
  if (named) {
    type = named.qualify(type);
    source = named;
    receiver = %(expr $type ${receiver.caddr()});
  }
  if (_receiver_points_to(source, target))
    $fail.expressions_receiver_pointer(c, origin, type, declared);
  if (target.car() != <*> || cdr(target) !== source)
    return receiver;
  if (!_is_addressable(c, receiver))
    $fail.expressions_receiver_address(c, origin);
  List address = %(expr ${type.reference()} (op & (parens $receiver)));
  return c.convert_expression(address, declared);
}

/* Whether a method receiver is a pointer to the declared parameter. `.` binds
   a receiver by identity or by one address-of, so such a call would pass the
   wrong pointer; with a pointer typedef C only warns and the program
   aborts. */
static int _receiver_points_to(Type source, Type declared) {
  while (source.is_pointer()) {
    source = source.dereference();
    if (source === declared) return 1;
  }
  return 0;
}

/* dynamic Func calls

   A call through a `Func` value prepares its arguments with the templates
   below; `Compiler.func_call_parts` reads a prepared call back. */

/* One argument, taken by reference when the callee's signature asks for a
   reference and by value otherwise. */
static macro Stmt $func_argument(Expr $function, Expr $storage,
    Expr $count, Expr $index, Expr $address, Expr $type, Expr $value) {
  if (x2c_func_reference_type($function, $count, $index))
    $storage[$index] = FuncArg_reference($address, $type);
  else $storage[$index] = $value;
}

/* A null argument: a reference takes it with the callee's own type. */
static macro Stmt $func_null_argument(Expr $function, Expr $storage,
    Expr $count, Expr $index, Expr $value) {
  {
    List reference = x2c_func_reference_type($function, $count, $index);
    if (reference) $storage[$index] = FuncArg_reference(0, reference);
    else $storage[$index] = $value;
  }
}

/* The by-value alternative: the argument boxed, or the diagnostic call for
   a type with no Var form. */
static macro Expression $func_value(Expr $argument) =>
  FuncArg_value($argument);

static macro Expression $func_opaque(Expr $function, Expr $index,
    Expr $type) => x2c_func_unrepresentable_argument($function, $index, $type);

/* A call with no arguments applies the callee directly. */
static macro Expression $func_apply(Expr $callee) => Func_apply($callee, 0, 0);

/* Returns one `$func_argument` or `$func_null_argument` application for
   each of `arguments`, preparing it into `storage` for the call through
   `function`; the `$func_call` template calls this in a slot. The choice
   of address, type and by-value alternative follows the argument's type. */
List _x2c_func_call_arguments(List function, List storage, List arguments) {
  Compiler c = Compiler.expanding();
  Macro prepare = $func_argument, absent = $func_null_argument,
        boxed = $func_value, opaque = $func_opaque;
  List count = $!int{ ${arguments.len()} };
  Array prepared = [];
  int position = 0;
  foreach (List argument, arguments) {
    List index = $!int{ ${position++} };
    Type type = argument.cadr();
    int forwarded = type.car() == <opt-ref>;
    List source = c.cache_literal_list(
      c.sym.normalize_declared_type(forwarded ? type.cdr() : type));
    List value = c.bind_syntax(
      c.sym.var_tag_for_type(type, NULL)
        ? boxed(c.convert_expression(argument, %("Var")))
        : opaque(function, index, source),
      <expression>, NULL);
    if (_null_literal(argument)) {
      prepared.push(absent(function, storage, count, index, value));
      continue;
    }
    int addressable = _is_addressable(c, argument);
    List address = forwarded ? argument
      : addressable ? %(expr ${type.reference()} (op & (parens $argument)))
      : $!int{ 0 };
    List carrier = forwarded || addressable ? source : $!int{ 0 };
    prepared.push(
      prepare(function, storage, count, index, address, carrier, value));
  }
  return prepared.list_free();
}

/* A dynamic Func call stores its callee once, prepares each argument into
   an array from left to right, and applies the callee. Func_apply validates
   arity and dispatches; the selected adapter checks carrier, type and
   conversion. */
static macro Expression $func_call(Expr $callee, Expr $count,
    Expr @arguments) => ({
  Func function = $callee;
  FuncArg storage[$count];
  @_x2c_func_call_arguments(function, storage, $arguments)
  Func_apply(function, $count, storage);
});

static List _resolve_func_call(
  Compiler c, List callee, List supplied, Token origin) {
  List arguments = _resolve_call_arguments(c, NULL, supplied, origin);
  if (_deferred_call(callee, NULL, arguments)) {
    Macro called = $called;
    return c.rebuild_expression(%(<macro-expr>), called(callee, arguments));
  }
  match (arguments)
    case %((expr (void) ())): arguments = NULL;
  if (!arguments) {
    Macro apply = $func_apply;
    return c.bind_syntax(apply(callee), <expression>, NULL);
  }
  Macro call = $func_call;
  return c.bind_syntax(
    call(callee, arguments.len(), arguments), <expression>, NULL);
}

/** Returns the callee and arguments of a typed `Func` call, or NULL for any
    other expression. `content` is the body of the call's `expr` node. Each
    argument is `(func-arg value address source)`: the argument boxed as a
    Var, or `(no-value)` when it has no Var form; its address, or 0; and its
    type, which is `(expr ("List") (ident reference))` for a null argument
    that takes the callee's own type. */
List Compiler.func_call_parts(Compiler c, Var content) {
  Macro call = $func_call, apply = $func_apply;
  match (%(expr () $content)) {
    case apply(?callee): return %($callee);
    case call(?callee, ?count, *arguments): {
      Array parts = $auto([callee]);
      foreach (List argument, _slot_statements(arguments)) {
        List part = _func_arg_part(argument);
        if (!part) return NULL;
        parts.push(part);
      }
      return parts;
    }
  }
  return NULL;
}

/* One prepared argument as `(func-arg value address source)`, or NULL for
   any other statement. */
static List _func_arg_part(List argument) {
  Macro prepare = $func_argument, absent = $func_null_argument,
        boxed = $func_value;
  Var value = %(no-value), address = NULL, source = NULL;
  match (argument) {
    case prepare(
      ?function, ?storage, ?count, ?index, ?pointer, ?type, ?alternative): {
      match (alternative) case boxed(?boxed_value): value = boxed_value;
      address = pointer;
      source = type;
    }
    case absent(?function, ?storage, ?count, ?index, ?alternative): {
      match (alternative) case boxed(?boxed_value): value = boxed_value;
      address = $!int{ 0 };
      source = %(expr ("List") (ident reference));
    }
    default: return NULL;
  }
  return %(func-arg $value $address $source);
}

/* Open statement groups in a slot. */
static List _slot_statements(List items) {
  Array opened = $auto([]);
  foreach (List item, items)
    match (item) {
      case %(seq *group):
        foreach (List statement, group) opened.push(statement);
      default: opened.push(item);
    }
  return opened;
}

// Iter chains

/** Completes an eligible resolved `Iter` call chain for immediate consumption.
    It accepts only a typed identifier call of the form
    `(expr R (call (expr ((func P) T) (ident B)) (args A)))`, where `R` and
    the last formal in `P` canonicalize to `Iter`. `Iter` arguments are
    completed recursively; a call missing only that last formal receives the
    hidden destination. Variadic calls and `Iter_unzip` are returned unchanged.
*/
List Compiler.complete_iter_chain(Compiler c, List expression) {
  match (expression)
    case $called(%(!set ?callee (expr ((func (!set ?parameters (*))) ?)
                                      (ident ?binding))),
                 *arguments):
      return _complete_iter_call(
        c, expression, callee, arguments, parameters, binding);
  return expression;
}

static List _complete_iter_call(
  Compiler c, List expression, List callee, List arguments,
  List parameters, List binding) {
  Type result = expression.cadr();
  String name = Ast.binding_spelling(binding);
  if (!_exact_iter_type(result) || name == "Iter_unzip" ||
      _parameters_variadic(parameters))
    return expression;
  List formal = parameters, actual = arguments;
  int supplied = arguments.len(), expected = formal.len();
  if (!formal ||
      (supplied != expected && supplied + 1 != expected) ||
      !_exact_iter_type(formal.last()))
    return expression;
  Array completed = [];
  int changed = 0;
  while (actual) {
    List argument = actual.car(), rewritten = argument;
    if (_exact_iter_type(formal.car()))
      rewritten = c.complete_iter_chain(argument);
    if (rewritten != argument) changed = 1;
    completed.push(rewritten);
    actual = actual.cdr();
    formal = formal.cdr();
  }
  List values = completed.list_free();
  if (supplied + 1 == expected) {
    values = values.append(%(${_iter_destination()}));
    changed = 1;
  }
  if (!changed) return expression;
  Macro called = $called;
  return c.rebuild_expression(%("Iter"), called(callee, values));
}

static int _exact_iter_type(Var value) {
  Type type = value is <list> ? value : %($value);
  return type.canonicalize() == %("Iter");
}

static List _iter_destination(void) =>
  $!(struct Iter *){ &(struct Iter){ 0 } };

// printf formats

static const PrintfFn printf_family_info[] = {
  { "printf",        0, 1, 1 },
  { "fprintf",       1, 2, 1 },
  { "sprintf",       1, 2, 1 },
  { "snprintf",      2, 3, 1 },
  { "String_printf", 0, 1, 0 },
  { "File_printf",   1, 2, 0 },
  { "Buffer_printf", 1, 2, 0 }
};

/** Returns the printf-family entry a callee names, or `NULL`. A resolved
    user function that happens to use a libc spelling is not one. */
const PrintfFn *List.printf_family(List l) {
  match (l)
    case %(expr ?type ${$source_identifier_content(%(?binding))}): {
      String name = Ast.binding_spelling(binding);
      int count = sizeof(printf_family_info) / sizeof(printf_family_info[0]);
      for (int i = 0; i < count; i++) {
        const PrintfFn *info = &printf_family_info[i];
        if (name != (String) info.name) continue;
        if (info.unresolved && type.list()) return NULL;
        return info;
      }
    }
  return NULL;
}

/** Returns the C spelling of the format a printf-family call consumes when
    it is known at translation time, or `NULL`. That is a quoted C string
    literal, the canonical `String` one becomes, or the `String_new` of one;
    any other format, such as a variable or an object macro, is not readable
    here. A `String` literal's text is spelled as a C literal.
*/
String Compiler.printf_static_format(Compiler c, Var format) {
  match (format) {
    case %(expr (* char) ${$source_literal_content(
        %((* char) ?spelled))}): {
      String spelling = spelled;
      int length = spelling ? spelling.len() : 0;
      if (length < 2 || spelling[0] != '"' || spelling[length - 1] != '"')
        return NULL;
      return spelling;
    }
    case %(expr ("String") (cache ?id)): {
      List key = c.id_keys[id];
      match (key)
        case %(string (expr ("String") ${$source_literal_content(
            %(("String") ?text))})): {
          String spelling = text;
          return spelling.repr();
        }
      match (key)
        case %(string (expr ("String") (call "String_new" (args ?literal)))):
          return c.printf_static_format(literal);
      return NULL;
    }
  }
  return NULL;
}
