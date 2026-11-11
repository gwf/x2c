/*  calls.x -- call preparation and recognition */

/* One call being resolved: its expected result type, the arguments it
   supplies, and its origin. A method call adds the receiver, its type, and
   the member it selects. */
static typedef struct CallSite {
  Compiler c;
  Type result_type, type;
  List receiver, field, supplied;
  Token origin;
  String method;
  Atom owner;
} CallSite;

/* dynamic Func calls

   A call through a `Func` value prepares its arguments with the templates
   below. */

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
static macro Stmt $func_splice(Expr $function, Expr $storage,
    Expr $index, Expr $value) {
  $storage[$index] = x2c_func_splice_argument($function, $index, $value);
}

static macro Stmt $func_map_splice(Expr $function, Expr $storage,
    Expr $index, Expr $value) {
  $storage[$index] = x2c_func_map_splice_argument($function, $index, $value);
}

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
  List count = $!int{ $(arguments.len()) };
  Array prepared = [];
  int position = 0;
  foreach (List argument in arguments) {
    List index = $!int{ $(position++) };
    match (argument) case %(expr ? (splice ?value)): {
      int map = c.sym.is_map_type(value.cadr());
      Macro splice = map ? $func_map_splice : $func_splice;
      prepared.push(
        splice(
          function, storage, index,
          c.convert_expression(value, map ? %("Map") : %("List"))));
      continue;
    }
    Type type = argument.cadr();
    int forwarded = type.is_optional_reference();
    List source = c.cache_literal_list(
      c.sym.normalize_declared_type(forwarded ? type.cdr() : type));
    /* C text boxes as a String, as it does for any Var destination. */
    List value = c.bind_syntax(
      _null_literal(argument) || c.sym.var_tag_for_type(type, NULL) ||
      type.canonicalize().is_char_pointer_like()
        ? boxed(c.convert_expression(argument, %("Var")))
        : opaque(function, index, source),
      <expression>, NULL);
    if (_null_literal(argument)) {
      prepared.push(absent(function, storage, count, index, value));
      continue;
    }
    int addressable = _is_addressable(c, argument);
    List address = forwarded ? argument
      : addressable ? %(expr $(type.reference()) (op & (parens $argument)))
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

// Iter chains

/** Completes an eligible resolved `Iter` call chain for immediate consumption.
    It accepts a typed call `(expr R (call (expr F C) (args A)))` whose
    callee type `F` resolves to a function, or a pointer to one, with formals
    `P`, where `R` and the last formal in `P` canonicalize to `Iter`. `Iter`
    arguments are completed recursively; a call missing only that last formal
    receives the hidden destination. Variadic calls and `Iter_unzip` are
    returned unchanged.
*/
List Compiler.complete_iter_chain(Compiler c, List expression) {
  List parameters = NULL;
  match (expression)
    case $called(%(!set ?callee (expr ?type ?)), *arguments)
        if (c.sym.resolve_key(type).function_parts(parameters, NULL)):
      return _complete_iter_call(
        c, expression, callee, arguments, parameters);
  return expression;
}

/** Returns the C spelling of the format a printf-family call consumes when
    it is known at translation time, or `NULL`. That is a quoted C string
    literal, the canonical `String` one becomes, or the `String_new` of one;
    any other format, such as a variable or an object macro, is not readable
    here. A `String` literal's text is spelled as a C literal.
*/
String Compiler.printf_static_format(Compiler c, Var format) {
  match (format) {
    case %(expr (* char) (literal (* char) ?spelled)): {
      String spelling = spelled;
      int len = spelling.len();
      if (!len) return NULL;
      for (int i = 0; i < len;) {
        if (spelling[i] != '"') return NULL;
        int size = scan_c_string(spelling + i);
        if (size < 0) return NULL;
        i += size;
        while (i < len && isspace((unsigned char) spelling[i])) i++;
      }
      return spelling;
    }
    case %(expr ("String") (cache ?id)): {
      List key = c.id_keys[id];
      match (key)
        case %(string (expr ("String") (literal ("String") ?text))): {
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

// completing Iter chains

static List _complete_iter_call(
  Compiler c, List expression, List callee, List arguments,
  List parameters) {
  if (!_exact_iter_type(expression.cadr()) ||
      _parameters_variadic(parameters))
    return expression;
  match (callee) case %(expr ? (ident ?binding)):
    if (Ast.binding_spelling(binding) == "Iter_unzip") return expression;
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
    values = values.append($(_iter_destination()));
    changed = 1;
  }
  if (!changed) return expression;
  Macro called = $called;
  return c.rebuild_expression(%("Iter"), called(callee, values));
}

// calls

static int _parameters_variadic(List parameters) {
  foreach (Var parameter in parameters)
    if (_parameter_variadic(parameter)) return 1;
  return 0;
}

static int _parameter_variadic(Var parameter) {
  if (parameter == <...>) return 1;
  if (parameter is <list> && !parameter.is_nil()) {
    Type type = parameter;
    return type.car() == <...> || type.rest_container() != NULL;
  }
  return 0;
}

static int _exact_iter_type(Type type) =>
  type.canonicalize() == %("Iter");

static List _iter_destination(void) =>
  $!(struct Iter *){ &(struct Iter){ 0 } };

module List _native(Resolve &r, String callee, List supplied) {
  List arguments = _resolve_call_arguments(r.c, NULL, supplied, r.origin);
  Type type = callee == "_Alignof" && r.type === %(<macro-expr>)
            ? %("size_t") : r.type;
  return %(expr $type (call $callee (args @arguments)));
}

module List _call(Resolve &r, List function, List supplied) {
  CallSite site = {
    .c = r.c, .result_type = r.type, .supplied = supplied,
    .origin = r.origin, .owner = r.owner};
  match (function)
    case %(expr ? (op . ?receiver (!set ?field (?name)))):
      return _method(site, receiver, field);
  return _function(site, function);
}

// member invocation

static List _method(CallSite &k, List receiver, List field) {
  k.receiver = receiver;
  k.field = field;
  List resolution = _lookup(k);
  /* A template's receiver may get its type only where the template
     expands, and a method-form macro of that type then takes the call. */
  if (k.c.macro_stack && !k.c.macro_holes) {
    List macro =
      k.c.bind_method_macro(k.receiver, k.method, k.supplied, k.owner);
    if (macro) return macro;
  }
  if (!resolution && _deferred_receiver(k.receiver)) {
    List callee = %(expr (<macro-expr>) (op . $(k.receiver) $(k.field)));
    return _finish(k, k.result_type, callee, NULL, NULL);
  }
  /* A template's free owner can name a type only where it lands, and
     `T.member` there calls `T_member`, as the parser folds it. */
  if (!resolution) match (k.type) case %(typedef ?(String owner)):
    return _function(k, %(expr () (ident ($(%"$(owner)_$(k.method)")))));
  if (!resolution && !k.c.macro_holes && k.c.rewrite_rules) {
    List rewritten = _member_rewrite(k);
    if (rewritten) return rewritten;
  }
  if (!resolution) {
    if (k.receiver ~= %(expr () (ident ?binding)))
      $fail.expressions_receiver_unresolved(
        k.c, k.origin, Ast.binding_spelling(binding));
    Var name = k.field.car();
    $fail.expressions_method_missing(k.c, k.origin, k.type, name);
  }
  match (resolution) {
    case %(ambiguous *packages):
      _report_method_ambiguity(k.c, k.type, k.method, packages, k.origin);
    case %(method ?binding (!set ?signature
      ((func (!set ?parameters (?declared *))) *returns))):
      return _bound(k, binding, signature, declared, parameters, returns);
    case %(field ?access ?field_type):
      return _function(
        k, %(expr $field_type (op $access $(k.receiver) $(k.field))));
  }
  return NULL;
}

static List _function(CallSite &k, List function) {
  List resolved = k.c.resolve_expression(function, k.origin);
  Type type = resolved.cadr(), func_type = k.c.sym.resolve_key(%("Func"));
  if (type && k.c.sym.resolve_key(type) == func_type)
    return _resolve_func_call(k.c, resolved, k.supplied, k.origin);
  if (k.c.sym.is_var_type(type))
    $fail.expressions_call_nonfunction(k.c, k.origin);
  return _finish(k, k.result_type, resolved, type, NULL);
}

/* Member rules are keyed by the receiver's type, or by a field keyword the
   aggregate it reaches through typedefs or one pointer declares. */
static List _member_rewrite(CallSite &k) {
  List source = %(expr () (call
    (expr () (op . $(k.receiver) $(k.field))) (args @(k.supplied))));
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
  List resolution = k.c.resolve_postfix_member(k.type, k.field, <.>, 1, NULL);
  if (!resolution && _is_raw_string_literal(k.receiver)) {
    k.receiver = k.c.promote_string_literal(k.receiver);
    k.type = k.receiver.cadr();
    resolution = k.c.resolve_postfix_member(k.type, k.field, <.>, 1, NULL);
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

static List _finish(
  CallSite &k, Type result_type, List callee, Type callee_type,
  List receiver) {
  if (result_type === %(<macro-expr>)) result_type = NULL;
  Type applied = callee_type.apply();
  if (!applied && callee_type) {
    Type signature = k.c.sym.resolve_key(callee_type);
    applied = signature.apply();
    if (!applied && signature.is_pointer())
      applied = k.c.sym.resolve_key(signature.dereference()).apply();
  }
  List arguments = _resolve_call_arguments(
    k.c, receiver, k.supplied, k.origin);
  if (!callee_type && !k.c.macro_holes)
    foreach (List argument in arguments)
      if (argument.cadr().type().is_function() &&
          Ast.contains_head(argument, <lambda>))
        $fail.expressions_lambda_untyped(k.c, k.origin);
  if (_deferred_call(callee, receiver, arguments))
    result_type = %(<macro-expr>);
  if (!result_type) result_type = applied;
  if (result_type !== %(<macro-expr>))
    _check_arity(
      k, callee, callee_type, result_type, arguments, receiver != NULL);
  k.c.check_meta_call(callee, k.origin);
  callee = _discarding_callee(k.c, callee, callee_type, arguments);
  Macro called = $called;
  return k.c.rebuild_expression(result_type, called(callee, arguments));
}

/* A call supplies every fixed parameter, no more unless the parameters are
   variadic, and may omit a final `Iter` destination that transform
   completes. A short call that a call rewrite rule may complete, such as
   `Thread.run(jobs)`, is left to its rule. A method's receiver is counted
   on both sides. */
static void _check_arity(
  CallSite &k, List callee, Type callee_type, Type result, List arguments,
  int method) {
  List parameters = NULL;
  if (!(callee_type ~= %((func *) *)) ||
      !callee_type.function_parts(parameters, NULL)) return;
  int supplied = arguments === %((expr (void) ())) ? 0 : arguments.len();
  int fixed = _fixed_parameter_count(parameters);
  int variadic = _parameters_variadic(parameters);
  if (supplied == fixed || (variadic && supplied > fixed)) return;
  if (supplied + 1 == fixed && !variadic &&
      _exact_iter_type(parameters.last()) && _exact_iter_type(result))
    return;
  if (supplied < fixed && _call_rewritable(k.c, callee)) return;
  $fail.expressions_call_arity(
    k.c, k.origin, method, variadic, fixed - method, supplied - method);
}

/* Whether a call rewrite rule is registered for the spelling `callee`
   names. */
static int _call_rewritable(Compiler c, List callee) {
  match (callee) case %(expr ? (ident ?binding)):
    return c.rewrite_rules &&
           c.has_rewrites(<call>, Ast.binding_spelling(binding));
  return 0;
}

/* The parameters before `...` or a rest container. */
static int _fixed_parameter_count(List parameters) {
  int count = 0;
  foreach (Var parameter in parameters) {
    if (_parameter_variadic(parameter)) break;
    count++;
  }
  return count;
}

/* A call whose receiver or argument is an unnamed operator temporary goes
   through a helper that discards that temporary once the call returns. */
static List _discarding_callee(
  Compiler c, List callee, Type callee_type, List arguments) {
  List binding = NULL;
  match (callee) case %(expr ? (ident (!set ?bound (*)))): binding = bound;
  if (!binding || !(callee_type ~= %((func *) *)) ||
      %"discard-helper $((long) binding)" in c.protocol_helpers)
    return callee;
  int which = 0, index = 0;
  foreach (Var argument in arguments) {
    if (argument is <list> && c.is_operator_temporary(argument))
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

static List _method_bind(
  Compiler c, List receiver, Type type, Type declared, Token origin) {
  if (!declared || !type) return receiver;
  Type target = declared.canonicalize(), source = type.canonicalize();
  Type named = source.is_aggregate() ? _tag_typedef(c, source) : NULL;
  if (named) {
    type = named.qualify(type);
    source = named;
    receiver = %(expr $type $(receiver.caddr()));
  }
  if (_receiver_points_to(source, target))
    $fail.expressions_receiver_pointer(c, origin, type, declared);
  if (target.car() != <*> || cdr(target) !== source)
    return receiver;
  if (!_is_addressable(c, receiver))
    $fail.expressions_receiver_address(c, origin);
  List address = %(expr $(type.reference()) (op & (parens $receiver)));
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

/* A dynamic call passes each Map rest entry as its key and then its value;
   Func.apply pairs them into the Map. */
static List _resolve_func_call(
  Compiler c, List callee, List supplied, Token origin) {
  Array flat = [];
  foreach (List argument in
           _resolve_call_arguments(c, NULL, supplied, origin))
    match (argument) {
      case %(expr ? (map-entry ?key ?value)): flat.push(key), flat.push(value);
      default: flat.push(argument);
    }
  List arguments = flat.list_free();
  if (_deferred_call(callee, NULL, arguments)) {
    Macro called = $called;
    return c.rebuild_expression(%(<macro-expr>), called(callee, arguments));
  }
  if (arguments ~= %((expr (void) ()))) arguments = NULL;
  if (!arguments) {
    Macro apply = $func_apply;
    return c.bind_syntax(apply(callee), <expression>, NULL);
  }
  Macro call = $func_call;
  return c.bind_syntax(
    call(callee, arguments.len(), arguments), <expression>, NULL);
}

/* A call waits for macro substitution when its callee, its receiver, or
   one of its arguments does. */
static int _deferred_call(List callee, List receiver, List arguments) {
  if (_deferred_receiver(callee) ||
      (receiver && _deferred_receiver(receiver)))
    return 1;
  foreach (Var argument in arguments)
    if (argument is <list> && !argument.is_nil()) {
      List syntax = argument;
      if (_deferred_receiver(syntax) ||
          syntax.car() == <macro-bind> || syntax.car() == <macro-slot>)
        return 1;
    }
  return 0;
}

static List _resolve_call_arguments(
  Compiler c, List receiver, List supplied, Token origin) {
  Array arguments = [];
  if (receiver) arguments.push(receiver);
  if (!receiver && !supplied) supplied = %((expr (void) ()));
  if (receiver && supplied === %((expr (void) ()))) supplied = NULL;
  foreach (Var argument in supplied) {
    int slot = argument is <list> && !argument.is_nil() &&
               argument.car() == <macro-slot>;
    Var value = c.evaluate_macro_slot(argument);
    if (value is <list> && !value.is_nil() &&
        value.car() == <seq>)
      foreach (List item in value.list().cdr())
        arguments.push(c.resolve_expression(_entry_argument(item), origin));
    else if (slot)
      arguments.push(
        c.resolve_expression(
          c.lift_meta_expression(value, origin), origin)
      );
    else if (value is <list>)
      arguments.push(c.resolve_expression(_entry_argument(value), origin));
    else arguments.push(value);
  }
  return arguments.list_free();
}

/* An `Entry` row spliced into a call is a `key: value` argument, spelled
   as `parse_call_entry` spells one. */
static List _entry_argument(List item) =>
  item.car() == <map-entry> ? %(expr ("Map") $item) : item;

/* Returns the printf-family entry a callee names, or `NULL`. A resolved
   user function that happens to use a libc spelling is not one. */
module const PrintfFn *_printf_family(List l) {
  match (l)
    case %(expr ?type (ident ?binding)): {
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
