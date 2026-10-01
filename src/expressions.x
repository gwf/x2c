/*  expressions.x -- expression syntax, resolution, and conversion

    Parses expressions with C precedence, resolves their types and members,
    and converts resolved values for typed destinations. Constructed syntax
    enters the same resolver as parsed source.
  */
#pragma once
$(import "../lib/private-keywords.xmacro")
#include "compiler.x"
#include "type.x"

/** A printf-family function: its name, the indexes of its format and first
    value arguments, and whether only a spelling no declaration resolves
    names it.
*/
typedef struct PrintfFn {
  const char *name, int fmt_arg, first_arg, unresolved;
} PrintfFn;

#pragma private
$(import "../src/grammar.xmacro")
#include "parse.x"
#include "literals.x"
#include "protocol.x"
#include "transform.x"
#include "stage.x"

/* postfix calls, indexing, and member lookup */

static List _iter_destination(void) {
  List values = source_commas_content(%((expr (int) (literal (int) "0"))));
  return %(expr (* struct "Iter")
    (op & (expr (struct "Iter")
      (cast (decl (struct "Iter") (bindings (bind () ())))
        (expr () (composite $values))))));
}

static int _parameters_variadic(List parameters) {
  foreach (Var parameter, parameters)
    if (parameter == <...> || (parameter is <list> && !parameter.is_nil() &&
        parameter.car() == <...>))
      return 1;
  return 0;
}

static int _exact_iter_type(Var value) {
  Type type = value is <list> ? value : %($value);
  return type.canonicalize().equal(%("Iter"));
}

static List _complete_iter_call(
  Compiler compiler, List expression, List callee, List arguments,
  List parameters, List binding) {
  Type result = expression.cadr();
  String name = binding_identity_spelling(binding);
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
      rewritten = compiler.complete_iter_chain(argument);
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
  return compiler.rebuild_expression(%("Iter"), called(callee, values));
}

/** Completes an eligible resolved `Iter` call chain for immediate consumption.
    It accepts only a typed identifier call of the form
    `(expr R (call (expr ((func P) T) (ident B)) (args A)))`, where `R` and
    the last formal in `P` canonicalize to `Iter`. `Iter` arguments are
    completed recursively; a call missing only that last formal receives the
    hidden destination. Variadic calls and `Iter_unzip` are returned unchanged.
*/
List Compiler.complete_iter_chain(Compiler compiler, List expression) {
  Macro called = $called;
  match (expression) case called(?callee, *arguments):
    match (callee)
      case %(expr ((func (!set ?parameters (*))) ?)
                  (ident ?binding)):
        return _complete_iter_call(
          compiler, expression, callee, arguments, parameters, binding);
  return expression;
}

#include "macros.x"

// True when a receiver's type must wait for macro substitution.
static int _deferred_receiver(List expr) {
  match (expr) case %(expr (<macro-expr>) ?): return 1;
  return 0;
}

/* Called after the optional start index and first `:` of
   `expr[start:end:step]`. */
static List _parse_slice(Compiler c, List expr, List start) {
  List type = expr.cadr(), stop = NULL, step = NULL;
  if (c.test(<:>)) {
    if (c.peek(0) != <]>) step = c.parse_expression();
  }
  else if (c.peek(0) != <]>) {
    stop = c.parse_expression();
    if (c.test(<:>) && c.peek(0) != <]>) step = c.parse_expression();
  }
  if (step && step.match(%(expr ?
      ${$source_literal_content(%(? "0"))})))
    c.report_error(<parse>, "slice step cannot be zero", c.token, %());
  c.expect(<]>);
  return %(expr $type ${source_slice_content(
    %($expr $start $stop $step))});
}

static List _typedef_index(
  Compiler c, List expr, List index, Type type) {
  String owner = type.car(), Type receiver = type;
  if (c.sym.is_array_type(type)) {
    owner = "Array";
    receiver = %("Array");
  }
  else if (c.sym.is_map_type(type)) {
    owner = "Map";
    receiver = %("Map");
  }
  String fnname = %"${owner}_getindex";
  List fntype = c.sym.get(%($fnname));
  match (fntype) {
    case %((func (!set ?params ($receiver ?))) ?rtype): {
      Type key = params.cadr(), supplied = index.cadr();
      if (key.is_integral() && c.sym.is_named_value_type(supplied, "Symbol"))
        c.report_error(
          <type>, "Symbol cannot be used as an integer bracket index",
          c.token, NULL);
      return %(expr ($rtype) (getindex $expr $index));
    }
  }
  Type native = c.sym.resolve_key(type);
  // A boxable handle to a record has no C array reading.
  if (native.is_pointer() && native.dereference().is_aggregate() &&
      type.var_tag())
    c.report_error(
      <type>, %"${type.car()} has no getindex", c.token, NULL);
  // A typedef of a plain C pointer indexes as that pointer; `String` and
  // its aliases keep their protocol reading.
  if (native.is_array() ||
      (native.is_pointer() && !c.sym.is_string_type(type)))
    return %(expr ${native.dereference()} (index $expr $index));
  return NULL;
}

static List Compiler._postfix_index_expression(
  Compiler c, List expr, List index) {
  Type type = expr.cadr();
  // `T *const p` indexes like `T *p`.
  while (type && type.car() is <symbol> &&
         Symbol.is_type_qualifier(type.car()))
    type = cdr(type);
  if (type.is_pointer() || type.is_array())
    return %(expr ${type.dereference()} (index $expr $index));
  if (!type.is_typedef_name()) return NULL;
  return _typedef_index(c, expr, index, type);
}

static List _parse_postfix_index(Compiler c, List expr) {
  c.expect(<[>);
  if (c.test(<:>)) return _parse_slice(c, expr, NULL);
  List index = c.parse_expression();
  if (c.test(<:>)) return _parse_slice(c, expr, index);
  c.expect(<]>);
  return c.resolve_expression(%(expr () (index $expr $index)), c.token);
}

/* An explicit converter call, `value.str()` or `value.var()`, is the most
   recent one parsed from source tokens, kept with its spelling and
   location. A destination parser compares the expression it just parsed
   against it, so nested calls and calls bound from constructed syntax never
   match. An argument list keeps the note left after each argument, since
   its destinations are known only once the call resolves. A converter takes
   only its receiver and is named for its result: the result spelled in
   lower case, or `str` for String. */
static void _note_explicit_converter(
  Compiler c, List call, String method, Token origin) {
  Type result = call.cadr();
  if (!result.match(%(?))) return;
  Macro called = $called;
  match (call) case called(?callee, ?argument): {
    String spelled = result.car().str().lower();
    if (method != spelled && (method != "str" || result !== %("String")))
      return;
    c.protocol_helpers["explicit-converter"] =
      %($call $method ${c.token_location(origin)});
  }
}

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
      String name = binding_identity_spelling(binding);
      int count = sizeof(printf_family_info) / sizeof(printf_family_info[0]);
      for (int i = 0; i < count; i++) {
        const PrintfFn *info = &printf_family_info[i];
        if (!String.equal(name, (String) info.name)) continue;
        if (info.unresolved && type.list()) return NULL;
        return info;
      }
    }
  return NULL;
}

/** Returns the format a printf-family call consumes when it is known at
    translation time, or `NULL`. That is a quoted C string literal, the
    canonical `String` one becomes, or the `String_new` of one; any other
    format, such as a variable or an object macro, is not readable here.
    `raw` reports C spelling, whose quotes and escape sequences the caller
    steps over.
*/
String Compiler.printf_static_format(
  Compiler compiler, Var format, int &raw) {
  match (format) {
    case %(expr (* char) ${$source_literal_content(
        %((* char) ?spelled))}): {
      String spelling = spelled;
      int length = spelling ? spelling.len() : 0;
      if (length < 2 || spelling[0] != '"' || spelling[length - 1] != '"')
        return NULL;
      raw = 1;
      return spelling;
    }
    case %(expr ("String") (cache ?id)): {
      List key = compiler.id_keys[id];
      match (key)
        case %(string (expr ("String") ${$source_literal_content(
            %(("String") ?text))})): {
          raw = 0;
          return text;
        }
      match (key)
        case %(string (expr ("String") (call "String_new" (args ?literal)))):
          return compiler.printf_static_format(literal, raw);
      return NULL;
    }
  }
  return NULL;
}

/* Each argument of a call spelled in source is checked against its declared
   parameter type. A method receiver selects the method and is not a
   destination, and a call the compiler builds for an operator is not a
   destination the source spelled. */
static void _check_converter_args(
  Compiler compiler, List result, int method, List notes) {
  List callee = NULL, params = NULL, arguments = NULL, supplied = NULL;
  Macro called = $called;
  match (result) case called(?function, *values): {
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
    _check_noted_converter(compiler, car(n), argument, expected, 0);
  }
  /* A static printf-family format converts each Var value it consumes. The
     family's positions count the receiver a method call spells before the
     dot, which `arguments` has already dropped. A format the transform
     cannot read leaves those values unlowered, so nothing converts them. */
  const PrintfFn *info = callee.printf_family(), int raw = 0;
  if (!info ||
      !compiler.printf_static_format(supplied[info.fmt_arg], raw))
    return;
  int first = info.first_arg - method, index = 0;
  for (List a = arguments, n = notes; a; a = cdr(a), n = cdr(n))
    if (index++ >= first && car(a) is <list>)
      _check_noted_converter(
        compiler, car(n), car(a), car(a).list().cadr(), 2);
}

/* Calling a Macro value builds code. Inside a template body the call is
   retained so the template can capture the value it applies; elsewhere it
   is an ordinary `Macro_apply` over the argument values. */
static List _apply_macro_value(
  Compiler c, List expr, List supplied, Token origin) {
  if (c.macro_holes)
    return %(expr (<macro-expr>) (tpl-call $expr (args @supplied)));
  List values = %(expr ("List") (nil));
  if (supplied === %((expr (void) ()))) supplied = NULL;
  foreach (List argument, supplied.reverse())
    values = %(expr ("List")
      (cons ${c.convert_expression(argument, %("Var"))} $values));
  List callee = c.resolve_expression(
    %(expr () (ident "Macro_apply")), origin);
  Macro called = $called;
  return c.resolve_expression(
    c.rebuild_expression(%("List"), called(callee, %($expr $values))),
    origin);
}

static List _parse_postfix_apply(Compiler c, List expr) {
  Token origin = c.token;
  c.expect(<(>);
  Array arguments = [], notes = [];
  if (c.peek(0) == <)>) arguments.push(%(expr (void) ()));
  while (c.peek(0) != <)>) {
    List argument = c.try_parse_macro_slot(<argument>);
    arguments.push(argument ? argument : c.parse_assignment());
    notes.push(c.protocol_helpers.getdefault("explicit-converter", %()));
    if (!c.test(<,>)) break;
  }
  c.expect(<)>);
  List supplied = arguments.list_free();
  if (c.sym.is_named_value_type(expr.cadr(), "Macro"))
    return _apply_macro_value(c, expr, supplied, origin);
  Macro called = $called;
  List result = c.resolve_expression(
    c.rebuild_expression(NULL, called(expr, supplied)), origin);
  int method = !!expr.match(%(expr () ${$source_operator_content(
    %(. ? (?)))}));
  _check_converter_args(c, result, method, notes.list_free());
  if (method && supplied === %((expr (void) ())))
    match (expr) case %(expr () ${$source_operator_content(
        %(. ? (?name)))}):
      _note_explicit_converter(c, result, name.str(), origin);
  return result;
}

static Type _receiver_relative_signature(
  Compiler compiler, List binding, Type signature, Type receiver) {
  String spelling = binding_identity_spelling(binding);
  if (!spelling) return signature;
  Type relative = compiler.sym.get_exact(%(self $spelling));
  if (!relative) return signature;
  Type base = receiver.canonicalize().base_type();
  if (!base || base.len() != 1) return signature;
  return relative.search_replace(<self>, base.car());
}

/* Find a method that an imported package adds to an external receiver. The
   package names are sorted so an ambiguous call reports deterministically. */
static List _imported_method(Compiler compiler, String method, Type receiver) {
  List packages = compiler.imported_providers(method);
  if (!packages) return NULL;
  if (packages.cdr()) return cons(<ambiguous>, packages);

  String spelling = %"${packages.car()}__$method";
  Type signature = compiler.sym.get_exact(%($spelling));
  List binding = compiler.sym.reference(%($spelling), NULL);
  signature = _receiver_relative_signature(
    compiler, binding, signature, receiver);
  return %(method $binding $signature);
}

static List _method_member(
  Compiler c, Type receiver_type, Type type, List field) {
  String method = %"${type.base_type().car()}_${field.car()}";
  Type signature = c.sym.get(%($method));
  int rejected =
    c.protocol_rejects_direct_member(type, field.car().str());
  if (signature && rejected) signature = NULL;
  List binding = NULL;
  if (signature) binding = c.sym.reference(%($method), NULL);
  else {
    List imported = rejected
      ? NULL : _imported_method(c, method, receiver_type);
    if (imported) return imported;
    List resolved = c.resolve_protocol_member(type, field.car().str());
    if (resolved) {
      (List method_binding, Type method_signature) = resolved;
      return %(method $method_binding $method_signature);
    }
  }
  if (!signature) return NULL;
  signature = _receiver_relative_signature(
    c, binding, signature, receiver_type);
  return %(method $binding $signature);
}

/** Resolves one field or method selection without consuming parser tokens.
    `field` is a single-name `List` and `access` is `.` or
    `->`. The result is a
    `(field access type)`, `(method binding signature)`, or `(ambiguous ...)`
    row, or NULL when no member is visible. Method lookup is enabled only by
    `call_context` and records the selected binding in `compiler.sym`.
*/
List Compiler.resolve_postfix_member(
  Compiler c, Type receiver_type, List field, Symbol access,
  int call_context) {
  if (receiver_type.car() == <opt-ref>)
    c.report_error(
      <type>, "check optional reference before accessing its value",
      c.token, NULL);
  // The receiver type is a lookup key here. A const or volatile receiver
  // names the same aggregate, fields, and methods.
  Type type = receiver_type.canonicalize();
  int hops = 0;
  if (access == <"->">) {
    Type object_type = c.sym.resolve_key(type);
    object_type = object_type.dereference();
    Type field_type = c.sym.lookup_field(object_type, field);
    return field_type ? %(field -> $field_type) : NULL;
  }
  while (type) {
    int is_method_type = type.is_typedef_name() || type.is_builtin();
    if (call_context && is_method_type) {
      List method = _method_member(c, receiver_type, type, field);
      if (method) return method;
    }
    if (type.is_pointer()) {
      Type object_type = type.dereference();
      Type field_type = c.sym.lookup_field(object_type, field);
      if (field_type) return %(field -> $field_type);
      type = NULL;
    }
    else if (type.is_aggregate()) {
      Type field_type = c.sym.lookup_field(type, field);
      if (field_type) return %(field . $field_type);
      type = NULL;
    }
    else type = c.sym.next_typedef(type, hops);
  }
  return NULL;
}

static String _delegate_type_name(Type type) {
  Type base = type.base_type();
  Var (head, name) = base;
  return base.is_aggregate_tag() ? name.str() : head.str();
}

static String _delegate_path_string(Type receiver, List path, String member) {
  Array parts = [];
  parts.push(_delegate_type_name(receiver));
  foreach (List step, path.cdr()) parts.push(step.caddr());
  if (member) parts.push(member);
  return ".".join(parts.list_free());
}

static void _report_method_ambiguity(
  Compiler compiler, Type receiver, String member, List packages,
  String delegate_path, Token origin) {
  List notes = delegate_path
             ? %("delegate path: $delegate_path") : NULL;
  foreach (String package, packages)
    notes = cons(%"package: '$package'", notes);
  String type = _delegate_type_name(receiver);
  compiler.report_error(
    <type>,
    %"method '$type.$member' is provided by multiple imported packages",
    origin, notes.reverse());
}

static List _delegate_step(Compiler compiler, Type receiver, String name) {
  List field = compiler.resolve_postfix_member(receiver, %($name), <.>, 0);
  (Symbol access, Type field_type) = field.cdr();
  return %(step $access $name $field_type);
}

typedef struct DelegateSearch {
  Compiler compiler;
  String member;
  Type outer;
  Token origin;
  Array candidates;
  List first_cycle;
} DelegateSearch;

static void DelegateSearch._find(
  DelegateSearch *d, Type receiver, List reverse_path, List seen) {
  Type aggregate = d.compiler.sym.delegate_aggregate(receiver);
  if (!aggregate) return;
  if (aggregate in seen) {
    if (!d.first_cycle)
      d.first_cycle = cons(<path>, reverse_path.reverse());
    return;
  }
  seen = cons(aggregate, seen);
  List order = d.compiler.sym.field_order(aggregate);
  foreach (List row, order ? order.cdr() : NULL) {
    String name = row.car();
    if (!name) continue;
    if (!d.compiler.sym.get(%(@aggregate delegate $name))) continue;
    List step = _delegate_step(d.compiler, receiver, name);
    Type field_type = step.cddr().cadr();
    List next_path = cons(step, reverse_path);
    List resolution = d.compiler.resolve_postfix_member(
      field_type, %(${d.member}), <.>, 1);
    if (resolution && resolution.car() == <method>) {
      List binding = resolution.cadr(), Type signature = resolution.caddr();
      List path = cons(<path>, next_path.reverse());
      d.candidates.push(%( delegate $binding $signature $path ));
    }
    else if (resolution && resolution.car() == <ambiguous>) {
      String path = _delegate_path_string(
        d.outer, cons(<path>, next_path.reverse()), NULL);
      _report_method_ambiguity(
        d.compiler, field_type, d.member,
        resolution.cdr(), path, d.origin);
    }
    else if (!resolution)
      d._find(field_type, next_path, seen);
  }
}

static List _resolve_delegate_method(
  Compiler compiler, Type receiver, String member, Token origin) {
  DelegateSearch search = {
    .compiler = compiler, .member = member, .outer = receiver,
    .origin = origin, .candidates = []};
  search._find(receiver, NULL, NULL);
  List candidates = search.candidates.list_free();
  if (candidates && candidates.cdr()) {
    List notes = NULL;
    foreach (List candidate, candidates) {
      List path = candidate.cddr().cadr();
      String spelling = binding_identity_spelling(candidate.cadr());
      String description = _delegate_path_string(receiver, path, member);
      notes = cons(%"delegate path: $description -> $spelling", notes);
    }
    String type = _delegate_type_name(receiver);
    compiler.report_error(
      <type>, %"method '$type.$member' has multiple delegate paths",
      origin, notes.reverse());
  }
  if (candidates) return candidates.car();
  if (search.first_cycle) {
    String type = _delegate_type_name(receiver);
    String path = _delegate_path_string(
      receiver, search.first_cycle, NULL);
    compiler.report_error(
      <type>, %"delegation cycle resolving $type.$member", origin,
      %("delegate path: $path"));
  }
  return NULL;
}

static void _completion_add(Map seen, Array names, String name) {
  if (!name || name in seen) return;
  seen[name] = 1;
  names.push(name);
}

static void _completion_fields(
  Compiler compiler, Type type, Map seen, Array names, Map visited) {
  type = compiler.sym.resolve_key(type);
  if (!type || !type.is_aggregate_tag() || type in visited) return;
  visited[type] = 1;
  List order = compiler.sym.field_order(type);
  foreach (List row, order ? order.cdr() : NULL) {
    String name = row.car();
    if (name) _completion_add(seen, names, name);
    else _completion_fields(compiler, row.cadr(), seen, names, visited);
  }
}

static void _completion_methods(
  Compiler compiler, Type receiver, Map seen, Array names) {
  Type type = receiver.canonicalize();
  int hops = 0;
  while (type) {
    if (type.is_typedef_name() || type.is_builtin()) {
      String owner = type.base_type().car();
      String prefix = %"${owner}_";
      foreach (List row, compiler.sym.visible_symbols()) {
        (String spelling, Var raw) = row;
        if (raw is not <list>) continue;
        Type signature = raw;
        if (signature.is_function() && spelling.startswith(prefix))
          _completion_add(seen, names, spelling.remove_prefix(prefix));
        foreach (Var (raw_package, _), compiler.package_roots) {
          String package = raw_package;
          String imported = %"${package}__$prefix";
          if (signature.is_function() && spelling.startswith(imported))
            _completion_add(
              seen, names, spelling.remove_prefix(imported));
        }
      }
      foreach (String name, compiler.protocol_member_names(type))
        _completion_add(seen, names, name);
    }
    if (type.is_pointer() || type.is_aggregate()) type = NULL;
    else type = compiler.sym.next_typedef(type, hops);
  }
}

static void _completion_delegates(
  Compiler compiler, Type receiver, Map seen, Array names, Map visited) {
  Type aggregate = compiler.sym.delegate_aggregate(receiver);
  if (!aggregate || aggregate in visited) return;
  visited[aggregate] = 1;
  List order = compiler.sym.field_order(aggregate);
  foreach (List row, order ? order.cdr() : NULL) {
    String field = row.car();
    if (!field ||
        !compiler.sym.get(%(@aggregate delegate $field))) continue;
    Type type = row.cadr();
    _completion_methods(compiler, type, seen, names);
    _completion_fields(compiler, type, seen, names, {});
    _completion_delegates(compiler, type, seen, names, visited);
  }
}

/** Returns sorted visible field and method names that resolve on `receiver`
    through `access`. */
List Compiler.postfix_completions(
  Compiler c, Type receiver, Symbol access) {
  Map seen = {}, visited = {};
  Array names = $auto([]), accepted = [];
  Type fields = c.sym.resolve_key(receiver);
  if (fields.is_pointer()) fields = fields.dereference();
  _completion_fields(c, fields, seen, names, {});
  if (access == <.>) {
    _completion_methods(c, receiver, seen, names);
    _completion_delegates(c, receiver, seen, names, visited);
  }
  names.sort();
  foreach (String name, names) {
    List resolution = c.resolve_postfix_member(receiver, %($name), access, 1);
    if (!resolution && access == <.>)
      resolution = _resolve_delegate_method(c, receiver, name, c.token);
    match (resolution) {
      case %((!or field method) ? ?): accepted.push(name);
    }
  }
  return accepted.list_free();
}

static List _materialize_delegate_receiver(List receiver, List path) {
  foreach (List step, path.cdr()) {
    (Symbol access, String name, Type type) = step.cdr();
    receiver = %(
      expr $type
        (op $access $receiver ($name))
    );
  }
  return receiver;
}

static List _parse_field_name(Compiler compiler, Symbol op_sym, List lhs_opt) {
  compiler.require_input();
  List slot = compiler.try_parse_macro_member();
  if (slot) return %($slot);
  String field_name = compiler.token.text;
  if (!field_name || !field_name.is_identifier()) {
    List notes = %("token:" ${compiler.token.text});
    if (lhs_opt) notes = cons(%("lhs expr:" ${lhs_opt.str()}), notes);
    String msg = %"expected identifier after '$op_sym'";
    compiler.report_error(<parse>, msg, compiler.token, notes);
  }
  List field = %( $field_name );
  compiler.next();
  return field;
}

static List _parse_postfix_dot(Compiler compiler, List expr) {
  Token origin = compiler.token;
  compiler.expect(<.>);
  if (compiler.at_completion()) {
    Type receiver = _expr_is_raw_string_literal(expr)
                  ? %("String") : expr.cadr();
    List rows = compiler.postfix_completions(receiver, <.>);
    raise %(replcomp (kind <members>) (rows $rows) (keywords ()));
  }
  List field = _parse_field_name(compiler, <.>, expr);
  List result = source_operator_expression(NULL, %(. $expr $field));
  if (compiler.peek(0) != <(>)
    return compiler.resolve_expression(result, origin);
  // Allocate a method identity before parsing its arguments.
  (void) compiler.resolve_postfix_member(expr.cadr(), field, <.>, 1);
  return result;
}

static List _parse_postfix_arrow(Compiler compiler, List expr) {
  Token origin = compiler.token;
  compiler.expect(<"->">);
  if (compiler.at_completion()) {
    List rows = compiler.postfix_completions(expr.cadr(), <"->">);
    raise %(replcomp (kind <members>) (rows $rows) (keywords ()));
  }
  List field = _parse_field_name(compiler, <"->">, expr);
  return compiler.resolve_expression(
    source_operator_expression(NULL, %(-> $expr $field)), origin);
}

static List _parse_postfix_decinc(Compiler compiler, List expr) {
  Token origin = compiler.token;
  Symbol op = compiler.peek(0);
  compiler.next();
  return compiler.resolve_expression(
    source_postfix_expression(NULL, %($op $expr)), origin);
}

/* The operators that apply to the expression written before them. */
static int _postfix_operator(Symbol token) {
  switch (token) {
    case <[>:
    case <(>:
    case <"->">:
    case <.>:
    case <++>:
    case <-->:
      return 1;
  }
  return 0;
}

static List _parse_postfix_tail(Compiler compiler, List expr) {
  while (_postfix_operator(compiler.peek(0))) {
    /* The operator makes what precedes it a receiver or a base, and neither
       is a destination, so a converter call noted before it never reaches
       one. */
    compiler.protocol_helpers.del("explicit-converter");
    switch (compiler.peek(0)) {
      case <[>:      expr = _parse_postfix_index(compiler, expr);   break;
      case <(>:      expr = _parse_postfix_apply(compiler, expr);   break;
      case <"->">:   expr = _parse_postfix_arrow(compiler, expr);   break;
      case <.>:      expr = _parse_postfix_dot(compiler, expr);     break;
      default:       expr = _parse_postfix_decinc(compiler, expr);  break;
    }
  }
  return expr;
}

static List _parse_postfix(Compiler compiler) =>
  _parse_postfix_tail(compiler, compiler.parse_primary());

// unary operators and builtins
/* unary syntax, casts, and operator types */

static List _parse_offsetof(Compiler compiler) {
  compiler.expect(<offsetof>);
  compiler.expect(<(>);
  List type = compiler.parse_simple_declaration();
  compiler.expect(<,>);
  List field = compiler.parse_basic_identifier();
  compiler.expect(<)>);
  return %(expr (unsigned) (offsetof $type $field));
}

static List _parse_sizeof(Compiler c) {
  c.expect(<sizeof>);
  int parens = c.test(<(>);
  Token head = c.token;
  List arg = NULL;
  if (c.test_declaration()) {
    arg = c.parse_simple_declaration();
    arg = cons(<decl>, arg.cdr());
  }
  // `sizeof(x + 1)` measures any expression; only `sizeof x` is unary.
  else if (parens) arg = c.parse_expression();
  else {
    c.token = head;
    arg = _parse_unary_op(c);
  }
  if (parens) {
    c.expect(<)>);
    arg = %(parens $arg);
  }
  return %(expr (unsigned) (sizeof $arg));
}

static List _parse_parens(Compiler compiler) {
  compiler.expect(<(>);
  List expr = compiler.parse_expression();
  compiler.expect(<)>);
  List type = expr.cadr();
  return %(expr $type (parens $expr));
}

// Designator chains retain the canonical field/index initializer forms.
static int _test_dot_init(Compiler compiler) {
  Token token = compiler.token;
  return token.type == <.> &&
    compiler.skip_trivia_from(token + 1).type == <ident>;
}

static List _parse_designated_init(Compiler compiler) {
  Symbol tag;
  List key;
  if (compiler.test(<.>)) {
    tag = <dotinit>;
    key = compiler.parse_basic_identifier();
  }
  else {
    compiler.expect(<[>);
    tag = <indexinit>;
    key = compiler.parse_assignment();
    compiler.expect(<]>);
  }
  List value;
  if (compiler.peek(0) == <.> || compiler.peek(0) == <[>)
    value = _parse_designated_init(compiler);
  else {
    compiler.expect(<=>);
    value = compiler.parse_assignment();
  }
  return %($tag $key $value);
}

static List _parse_va_arg(Compiler compiler) {
  compiler.next();
  compiler.expect(<(>);
  List expr = compiler.parse_assignment();
  compiler.expect(<,>);
  List decl = compiler.parse_simple_declaration(), type = decl.type_from_ast();
  decl = %( decl @{ decl.cdr() } );
  compiler.expect(<)>);
  expr = source_va_arg_content(%($expr $decl));
  return %( expr $type $expr );
}

/* A C11 generic selection. An association names its type with
   `parse_type_name`, which covers specifiers, qualifiers, and pointers; a
   function-pointer or array association needs a typedef name. */
static List _parse_generic(Compiler c) {
  Token origin = c.token;
  c.next();
  c.expect(<(>);
  List control = c.parse_assignment();
  Array associations = [];
  while (c.test(<,>)) {
    Var type = c.test(<default>) ? <default> : c.parse_type_name();
    c.expect(<:>);
    associations.push(%(association $type ${c.parse_assignment()}));
  }
  c.expect(<)>);
  List selection = source_generic_content(
    %($control @{associations.list_free()}));
  return c.resolve_expression(%(expr () $selection), origin);
}

/* Whether C gives an operand the type x2c records. A character constant is
   `int` in C; `sizeof`, `offsetof`, and a pointer difference have `size_t`
   and `ptrdiff_t` identities x2c does not model; an enum's compatible
   integer type is implementation-defined; and C compilers type a bitfield
   differently. */
static int _c_type_known(Compiler c, List operand) {
  match (operand) {
    case %(expr ? ${$source_content_pattern($grouped, %(?inner))}):
      return _c_type_known(c, inner);
    case %(expr ? ${$source_literal_content(%((char) *))}): return 0;
    case %(expr ? ${$source_content_pattern(
        $sizeof_grouped, %(?operand))}): return 0;
    case %(expr ? ${$source_content_pattern(
        $sizeof_expression, %(?operand))}): return 0;
    case %(expr ? (offsetof *)): return 0;
    case %(expr ? ${$source_operator_content(
        %(- (expr ?left *) (expr ?right *)))}): {
      Type l = left, r = right;
      if ((l.is_pointer() || l.is_array()) && (r.is_pointer() || r.is_array()))
        return 0;
    }
  }
  Type type = operand.cadr(), numeric = c.sym.resolve_numeric_type(type);
  return type && !type.is_bitfield() && !(numeric && numeric.is_enum());
}

static List _parse_unary_op(Compiler c) {
  c.__complete_here(<expr>, %());
  Symbol op = c.peek(0);
  Token origin = c.token;
  if (op == <sizeof>) return _parse_sizeof(c);
  if (op == <offsetof>) return _parse_offsetof(c);
  if (op != <++> && op != <--> && op != <~> && op != <*> &&
      op != <&> && op != <-> && op != <+> && op != <!>)
    return _parse_postfix(c);
  c.next();
  List operand = op == <++> || op == <--> || op == <~>
               ? _parse_unary_op(c) : _parse_cast(c);
  return c.resolve_expression(
    source_operator_expression(NULL, %($op $operand)), origin);
}

static int _cast_operand_follows(Symbol s) {
  switch (s) {
    case <ident>:
    case <in>:
    case <$>:
    case <"$(">:
    case <"(">:
    case <"{">:
    case <"%(">:
    case <"%<<">:
    case <[>:
    case <"%[">:
    case <"%{">:
    case <"%\"">:
    case <"%!">:
    case <lit-char>:
    case <lit-int>:
    case <lit-float>:
    case <lit-char*>:
    case <lit-atom>:
    case <lit-symbol>:
    case <void>:
    case <sizeof>:
    case <offsetof>:
    case <++>:
    case <-->:
    case <!>:
    case <~>:
    case <*>:
    case <&>:
    case <->:
    case <+>:
      return 1;
  }
  return 0;
}

static int _macro_hole_starts_cast_type(Compiler compiler, Token after) {
  if (!compiler.macro_holes || compiler.peek(0) != <$> ||
      compiler.peek(2) != <)>) return 0;
  List hole = compiler.peek_macro_hole();
  if (!hole) return 0;
  Symbol kind = hole.assoc(<kind>);
  if (kind && kind != <type>) return 0;
  /* `($items)[0]` subscripts the hole's value and `($key) in table` tests
     it; only a hole declared a type casts an array literal or a name `in`. */
  if ((after.type == <[> || after.text == "in") && kind != <type>) return 0;
  return _cast_operand_follows(after.type);
}

static int _cast_operand_after_parens(Compiler c) =>
  c.peek(0) == <"("> &&
  _cast_operand_follows(c.token.after_group().type);

/* A cast whose operand already has the cast type, qualifiers included,
   changes nothing. The comparison uses x2c's declared type, so a cast
   between a typedef and its C type stays silent, and only an operand whose
   C type x2c knows is compared: a pointer difference or a character
   constant is not. A `void` cast discards a value on purpose, and a cast of
   a C string literal is how source keeps the literal native where x2c would
   otherwise promote it to a `String`. */
static void _warn_unnecessary_cast(
  Compiler c, List operand, Type target, Token origin) {
  if (!target || target === %(void) || target === %(<macro-expr>) ||
      _expr_is_raw_string_literal(operand)) return;
  Type source = operand.cadr();
  if (!_c_type_known(c, operand) || source.declared() != target.declared())
    return;
  c.report_warning(
    <conversion>,
    %"unnecessary conversion: the operand already has type ${target.repr()}",
    origin, %("remove the cast"));
}

/* A template typedef is named by the binding each expansion supplies, so a
   cast to it, qualified or not, is typed where the template expands. A
   template keeps aggregate tags as spellings, so only a typedef base ends in
   a binding. */
static int _casts_to_template_typedef(Compiler c, List declaration) {
  List base = declaration.cadr();
  return c.macro_holes && !!base.match(%(* (binding ? ?)));
}

static List _parse_cast(Compiler c) {
  Token head = c.token;
  if (_cast_operand_after_parens(c) && c.test(<(>)) {
    if (c.test_declaration() ||
        _macro_hole_starts_cast_type(c, head.after_group())) {
      List decl = c.parse_simple_declaration(), type = decl.type_from_ast();
      decl = %(decl @{decl.cdr()});
      c.expect(<)>);
      List expr = _parse_cast(c);
      if (expr.cadr() === %(<macro-expr>) ||
          _casts_to_template_typedef(c, decl))
        type = %(<macro-expr>);
      _warn_unnecessary_cast(c, expr, type, head);
      return %(expr $type (cast $decl $expr));
    }
  }
  c.token = head;
  return _parse_unary_op(c);
}

/** Parses one macro target through the cast-expression grammar.
    Parsing starts at `c.token` and leaves it at the first token after
    the target.
*/
List Compiler.parse_macro_expression_target(Compiler c) => _parse_cast(c);

/* Larger levels bind more tightly. The recursive parser descends to level 10
   before consuming operators while each level folds left; `is` shares the
   relational level but is recognized from its identifier spelling. */
static inline int _precedence(Symbol op) {
  switch (op) {
    case <||>:                 return 1;   // logical OR
    case <&&>:                 return 2;   // logical AND
    case <|>:                  return 3;   // bitwise OR
    case <^>:                  return 4;   // bitwise XOR
    case <&>:                  return 5;   // bitwise AND
    case <==>:   case <!=>:
    case <===>:  case <!==>:   return 6;   // equality
    case <"<">:  case <">">:   case <in>:
    case <"<=">: case <">=">:  return 7;   // relational
    case <"<<">: case <">>">:  return 8;   // shift
    case <+>:    case <->:     return 9;   // additive
    case <*>:    case </>:
    case <%>:    case <@>:     return 10;  // multiplicative
    default:                   return 0;
  }
}

/* The keyword pass leaves `in` a name where a neighbor could also be C, as
   before a bare `[` literal. No name follows a complete operand, so there
   it is the membership operator. */
static inline Symbol _binary_operator(Compiler c) =>
  c.at_word("in") ? <in> : c.peek(0);

static inline int _is_type_operator(Compiler c) => c.at_word("is");

static int _is_type_selector_start(Compiler c) {
  if (c.at_word("Void")) return 1;
  Token head = c.token;
  if (c.test(<(>)) {
    int declaration = c.test_declaration();
    c.token = head;
    return declaration;
  }
  if (c.test_declaration()) return 1;
  if (c.peek(0) != <ident>) return 0;
  String spelling = c.token.text;
  return !c.sym.get(%($spelling));
}

static Type _parse_is_type(Compiler c, Token origin) {
  int parenthesized = c.test(<(>), Type type = c.parse_type_name();
  if (parenthesized) {
    if (c.peek(0) == <[>)
      c.report_error(
        <type>, "array type cannot be used after operator 'is'",
        origin, %("array types have no supported Var tag"));
    if (c.peek(0) == <(>)
      c.report_error(
        <type>, "function type cannot be used after operator 'is'",
        origin, %("function types have no supported Var tag"));
    c.expect(<)>);
  }
  else if (type.is_pointer())
    c.report_error(
      <parse>, "pointer type after 'is' must be parenthesized",
      origin, %("write value is (T *)"));
  return type;
}

static int _identifier_needs_resolution(
  Compiler compiler, List binding) {
  String spelling = binding_identity_spelling(binding);
  Map facts = compiler.semantic_binding_facts();
  int retained_parameter = %(lambda-param $binding) in facts;
  int retained_capture = %(lambda-depth $binding) in facts;
  if (compiler.lambda_capture_required(binding)) return 1;
  if (retained_parameter &&
      (compiler.local_macro_captures != NULL ||
       %(local-macro-capture $binding) in facts))
    return 1;
  return !spelling ||
    (compiler.sym.lookup(%($spelling), NULL) != binding &&
     !retained_parameter && !retained_capture);
}

static int _needs_resolution(Compiler compiler, Var value) {
  // The scan is an any-search; a worklist keeps deep operator chains from
  // costing one C frame per nesting level.
  Array pending = $auto([]);
  Macro lambda = $lambda_expression, captured = $lambda_captured;
  pending.push(value);
  while (pending.len()) {
    Var current = pending.take_last();
    if (current is not <list>) continue;
    List syntax = current;
    match (syntax) {
      case %(expr (? *) (parens (block *))): continue;
      case %(expr (!or () (<macro-expr>)) ?): return 1;
      case captured(?body, *captures, *params): {
        foreach (List row, captures)
          match (row) case %(capture ?binding ? ?):
            if (!compiler.semantic_binding_facts().contains(
              %(lambda-depth $binding))) return 1;
        continue;
      }
      case lambda(?body, *params): return 1;
      case %(at m-origin ?):
        if (compiler.source_map && !compiler.macro_holes) return 1;
      case %((!or macro-bind macro-invoke macro-slot meta-call) *): return 1;
      case $source_identifier_content(%(?name)):
        if (name is <list>) {
          List binding = name;
          if (_identifier_needs_resolution(compiler, binding)) return 1;
        }
        else return 1;
      // A Type hole can supply declarators with the base they bind to.
      case %(decl ?(List base) *):
        if (base.type().declaration_parts().cadr()) return 1;
    }
    foreach (Var child, syntax)
      if (child is <list>) pending.push(child);
  }
  return 0;
}

static inline int _type_is_char_pointer_like(List type) {
  if (!type) return 0;
  return type.match(%((!or (dim *) (!quote *)) char)) ||
    type.match(%((!or (dim *) (!quote *)) const char));
}

static inline int _expr_is_string_like(Compiler compiler, List expr) {
  if (!expr) return 0;
  List type = expr.cadr();
  return compiler.sym.is_string_type(type) ||
         _type_is_char_pointer_like(type);
}

static int _expr_is_raw_string_literal(List expr) {
  match (expr) {
    case %(expr ? ${$source_content_pattern($grouped, %(?inner))}):
      return _expr_is_raw_string_literal(inner);
    case %(expr ? ${$source_literal_content(%(?type ?))}):
      return _type_is_char_pointer_like(type);
    case %(expr ? ${$source_operator_content(
        %(? ? ?ontrue ?onfalse))}):
      return _expr_is_raw_string_literal(ontrue) &&
             _expr_is_raw_string_literal(onfalse);
  }
  return 0;
}

/** Converts a C string literal to `String` where no C meaning applies: as a
    method receiver, a `foreach` collection, or a raise detail. Parentheses
    and a conditional whose arms are both literals count as the literal; any
    other expression is returned unchanged.
*/
List Compiler.promote_string_literal(Compiler c, List expr) =>
  _expr_is_raw_string_literal(expr) ? c.convert_expression(expr, %("String"))
                                    : expr;

/* A participant that converts its operator's other operand: a struct or
   union, or a handle typedef pointing at one. Scalar pointers keep native C
   behavior, since `text + 1` must stay pointer arithmetic. */
static int _converts_operands(Compiler compiler, Type type) {
  Type resolved = compiler.sym.resolve_key(type);
  if (resolved && resolved.is_pointer())
    resolved = compiler.sym.resolve_key(resolved.dereference());
  return resolved && resolved.is_aggregate();
}

static Array _typedef_names(Compiler compiler, Type type) {
  Array names = [];
  int hops = 0;
  for (; type && (type.is_bare_typedef_name() || type.is_typedef());
       type = compiler.sym.next_typedef(type, hops))
    if (type.is_bare_typedef_name()) names.push(type);
  return names;
}

/* Two different typedef names that share an ancestor meet at the nearest
   one that has `member`, so an alias of `String` compares with a `String`,
   or with another alias, through `String.equal` rather than as the pointers
   C sees. */
static Type _shared_participant(
  Compiler compiler, Type lhs_type, Type rhs_type, Symbol member) {
  if (!lhs_type.is_bare_typedef_name() || !rhs_type.is_bare_typedef_name())
    return NULL;
  Array lhs_names = _typedef_names(compiler, lhs_type);
  foreach (Type name, _typedef_names(compiler, rhs_type))
    if (name in lhs_names &&
        compiler.resolve_protocol_member(name, member))
      return name;
  return NULL;
}

static Type _converted_participant(
  Compiler compiler, Symbol member, Type lhs_type, Type rhs_type,
  List &lhs, List &rhs) {
  if (compiler.sym.is_var_type(lhs_type) ||
      compiler.sym.is_var_type(rhs_type)) return NULL;
  Type shared = _shared_participant(
    compiler, lhs_type, rhs_type, member);
  if (shared) return shared;
  int lhs_member = !!compiler.resolve_protocol_member(lhs_type, member) &&
    _converts_operands(compiler, lhs_type);
  int rhs_member = !!compiler.resolve_protocol_member(rhs_type, member) &&
    _converts_operands(compiler, rhs_type);
  if (lhs_member && !rhs_member) {
    List converted = _converter_call(
      compiler, rhs, rhs_type, lhs_type);
    if (converted) { rhs = converted; return lhs_type; }
  }
  else if (rhs_member && !lhs_member) {
    List converted = _converter_call(
      compiler, lhs, lhs_type, rhs_type);
    if (converted) { lhs = converted; return rhs_type; }
  }
  return NULL;
}

/* A binary operator whose one operand is a converting participant converts
   the other operand to that type through its declared converter, so
   `x * 2.0` and `2.0 - x` resolve like `x * two`. The converted operand
   replaces the original through `lhs` and `rhs`. An operand's qualifier
   describes its storage, not the type that adopts the operator, so the
   participant is the unqualified type both here and in the operands'
   comparison. */
static List _resolve_protocol_operator(
  Compiler compiler, Symbol op, List &lhs, List &rhs, Symbol &derived) {
  derived = 0;
  Type lhs_type = lhs.cadr();
  lhs_type = lhs_type.canonicalize();
  Type participant = lhs_type, rhs_type = NULL;
  if (rhs) {
    rhs_type = rhs.cadr();
    rhs_type = rhs_type.canonicalize();
  }
  Symbol member = 0;
  if (!rhs) {
    if (op != <->) return NULL;
    member = <neg>;
  }
  else if (op == <in>) {
    participant = rhs_type;
    member = <contains>;
  }
  else {
    if (!participant) return NULL;
    member = compiler.operator_member(op);
    Symbol source = compiler.derived_member(op);
    if (!member) member = source;
    derived = source;
    if (!member) return NULL;
    if (participant !== rhs_type) {
      participant = _converted_participant(
        compiler, member, participant, rhs_type, lhs, rhs);
      if (!participant) return NULL;
    }
  }
  return participant && member
       ? compiler.resolve_protocol_member(participant, member)
       : NULL;
}

/* A call result is an unnamed temporary the consuming operator or call may
   discard when its callee is known to return a fresh value: a protocol
   operator member, a converter from a number, or a wrapper of either. The
   callee binding is shared by every call to that function, so the record
   survives the re-resolution that rebuilds call nodes. */
static void _note_fresh_callee(Compiler compiler, List binding) {
  long identity = (long) binding;
  compiler.protocol_helpers[%"fresh-callee $identity"] = 1;
}

static int _is_operator_temporary(Compiler c, List expression) {
  match (expression) {
    case %(expr ? ${$source_content_pattern($grouped, %(?inner))}):
      return _is_operator_temporary(c, inner);
  }
  Macro called = $called;
  match (expression) case called(?callee, *arguments):
    match (callee) case %(expr ? ${$source_identifier_content(
        %((!set ?binding (*))))}):
      return c.protocol_helpers.contains(
        %"fresh-callee ${(long) binding.list()}");
  return 0;
}

static List Compiler._protocol_operator_expression(
  Compiler c, Symbol op, List lhs, List rhs) {
  Symbol derived = 0;
  List resolved = _resolve_protocol_operator(c, op, lhs, rhs, derived);
  if (!resolved) return NULL;
  (List binding, Type signature) = resolved;
  Type result = signature.cdr(), List arguments = NULL;
  int which = 0;
  if (!rhs) arguments = %($lhs);
  else if (op == <in>) {
    List parameters = signature.car().cadr();
    lhs = c.convert_expression(lhs, parameters.cadr());
    arguments = %($rhs $lhs);
  }
  else arguments = %($lhs $rhs);
  if (op != <in>) {
    if (_is_operator_temporary(c, lhs)) which |= 1;
    if (rhs && _is_operator_temporary(c, rhs)) which |= 2;
  }
  if (!derived && c.resolve_protocol_member(result, "discard"))
    _note_fresh_callee(c, binding);
  if (which) {
    Symbol member = rhs ? c.operator_member(op) : <neg>;
    if (!member) member = c.derived_member(op);
    Type participant = lhs.cadr();
    participant = participant.canonicalize();
    List helper = c.protocol_discard_helper(
      participant, member, which);
    if (helper) (binding, signature) = helper;
  }
  Macro called = $called;
  List callee = %(expr $signature (ident $binding));
  List call = c.rebuild_expression(result, called(callee, arguments));
  if (!derived) return call;
  if (derived == <equal>) return %(expr (int) (op ! $call));
  List zero = %(expr (int) (literal (int) "0"));
  return %(expr (int) (op $op $call $zero));
}

static List _binary_op_type_addsub(
  Compiler compiler, Symbol op, List lhs, List rhs) {
  Type ltype = lhs.cadr(), rtype = rhs.cadr();
  if (op == <+> && _expr_is_string_like(compiler, lhs) &&
      _expr_is_string_like(compiler, rhs))
    return %("String");
  Type lscalar = compiler.sym.resolve_numeric_type(ltype);
  Type rscalar = compiler.sym.resolve_numeric_type(rtype);
  if (lscalar) {
    if (rscalar) return lscalar.widest(rscalar);
    else if (op == <+> && rtype.is_pointer()) return rtype;
  }
  else if (ltype.is_pointer()) {
    if (rscalar)                  return ltype;
    else if (rtype.is_pointer())  return %(int);
  }
  return NULL;
}

static List _binary_op_type_fallback(List lhs, List rhs) {
  Type ltype = lhs.cadr(), rtype = rhs.cadr();
  if (!ltype) return rtype;
  if (!rtype) return ltype;
  if (ltype === %("Var") || rtype === %("Var")) return %("Var");
  if (ltype.is_pointer()) return ltype;
  if (rtype.is_pointer()) return rtype;
  return NULL;
}

static Type _shift_type(Compiler c, Type lhs) {
  Type scalar = c.sym.resolve_numeric_type(lhs);
  return scalar ? scalar.promote() : NULL;
}

static Type _arithmetic_type(Compiler c, Type lhs, Type rhs) {
  Type left = c.sym.resolve_numeric_type(lhs);
  Type right = c.sym.resolve_numeric_type(rhs);
  return left.widest(right);
}

static List Compiler._binary_op_type(
  Compiler compiler, Symbol op, List lhs, List rhs) {
  Type ltype = lhs.cadr(), rtype = rhs.cadr();
  if (ltype.car() == <opt-ref> || rtype.car() == <opt-ref>) {
    int null_test =
      (_integer_literal_kind(lhs, NULL) == <zero> ||
       lhs.match(%(expr ? ${$source_identifier_content(
         %((binding ? "NULL")))}))) ||
      (_integer_literal_kind(rhs, NULL) == <zero> ||
       rhs.match(%(expr ? ${$source_identifier_content(
         %((binding ? "NULL")))})));
    if (!((op == <==> || op == <!=>) && null_test) &&
        op != <&&> && op != <||>)
      compiler.report_error(
        <type>, "check optional reference before using its value",
        compiler.token, NULL);
  }
  if (op == <in>) return NULL;
  if (compiler.sym.is_var_type(ltype) ||
      compiler.sym.is_var_type(rtype)) {
    switch (op) {
      case <||>:   case <&&>:
      case <==>:   case <!=>:  case <===>:  case <!==>:
      case <"<">:  case <">">: case <"<=">: case <">=">:
        return %(int);
      default: return %("Var");
    }
  }
  switch (op) {
    case <||>:   case <&&>:
    case <==>:   case <!=>:  case <===>:  case <!==>:
    case <"<">:  case <">">: case <"<=">: case <">=">:
      return %(int);
    case <"<<">: case <">>">:
      return _shift_type(compiler, ltype);
    case </>:    case <%>:
    case <"|">:  case <&>:   case <*>:
    case <^>: return _arithmetic_type(compiler, ltype, rtype);
    case <+>:    case <->:
      return _binary_op_type_addsub(compiler, op, lhs, rhs);
    default: return _binary_op_type_fallback(lhs, rhs);
  }
}

/* A `static` function belongs to the file that defines it, so an including
   unit replays a marker row naming that file instead of a declaration.
   Reporting the reference here names the function and its file, where C
   would otherwise report only an undefined symbol at link time. A macro body
   is the defining library's own syntax, bound wherever it expands, so only a
   reference written in an `.x` unit is reported. */
static void _check_unit_static(Compiler c, String spelling, Token origin) {
  if (!is_source_file(c.filename)) return;
  List owner = c.sym.get(%("unit-static" $spelling));
  if (!owner) return;
  String file = c.display_path(home_absolute_path(owner.car()));
  c.report_error(
    <type>, %"'$spelling' is a static function private to its unit", origin,
    %("it is defined in '$file';"
      "remove 'static' so other units can call it"));
}

/* names, calls, and resolved expression content */

/* Parsed identifiers arrive as spellings, while constructed syntax may carry
   producer-issued binding identities. Semantic binding facts validate those
   identities before resolution. A visible local replaces a stale local
   identity; global shadow handling instead gives the visible declaration an
   emitted alias so the original identity keeps its meaning. */
static List _identifier_binding(
  Compiler c, Var value, Type &type, Token origin, int &require_type) {
  require_type = value is <string>;
  if (value is <string>) return c.sym.reference(%($value), type);
  if (value is not <list>) return NULL;
  List name = value;
  int identity = 0;
  String spelling = NULL;
  if (binding_identity_try_parts(name, identity, spelling)) {
    Var issued;
    if (!c.semantic_binding_facts().try_get(
      %(known $identity), issued) ||
        issued is not <string> || !issued.string().equal(spelling))
      c.report_error(
        <type>, "identifier has an unknown binding identity",
        origin, %("binding: ${name.repr()}"));
    return name;
  }
  match (name) {
    case %("x2c.ident" ?(String spelling)): {
      require_type = 1;
      return c.sym.reference(%($spelling), type);
    }
    case %((!is ? type string)):
      return c.sym.reference(name, type);
  }
  return NULL;
}

static void _capture_identifier(Compiler c, List binding) {
  if (c.local_macro_captures == NULL || !binding ||
      !c.sym.binding_is_local_before(
        binding, c.local_macro_capture_scopes) ||
      c.local_macro_captures.contains(binding)) return;
  Var order = c.local_macro_captures[<order>];
  c.local_macro_captures[<order>] = cons(
    binding, order is <list> ? order : NULL);
  c.local_macro_captures[binding] = 1;
}

static void _shadow_identifier(
  Compiler c, List &binding, Type type, String spelling,
  Map binding_facts) {
  if (!spelling) return;
  Type visible_type = NULL;
  List visible = c.sym.lookup(%($spelling), visible_type);
  if (!visible || visible == binding) return;
  if (%(local-macro-capture $binding) in binding_facts) {
    if (!binding_facts.contains(%(emitted $visible)))
      binding_facts[%(emitted $visible)] = c.fresh_name("binding_shadow");
  }
  else if (c.sym.binding_is_local(binding) &&
           !binding_facts.contains(%(lambda-depth $binding)))
    binding = visible;
  else if (visible_type &&
           (!type || c.sym.resolve_global(%($spelling), NULL)) &&
           !binding_facts.contains(%(emitted $visible)))
    binding_facts[%(emitted $visible)] = c.fresh_name("binding_shadow");
}

static List _read_bound_reference(
  Compiler c, List result, List binding, Type type,
  int read_reference, Map binding_facts) {
  if (!read_reference ||
      !(%(reference-param $binding) in binding_facts)) return result;
  if (%(optional-reference-param $binding) in binding_facts &&
      !(binding in c.present_references())) return result;
  Type value_type = cdr(type);
  return %(expr $value_type
           (parens (expr $value_type (op * $result))));
}

static Type _identifier_type(
  Compiler c, List binding, String spelling, Map facts, Token origin) {
  Var stored;
  if (facts.try_get(%(type $binding), stored) && stored is <list>)
    return stored;
  if (!spelling) return NULL;
  Type type = c.sym.get(%($spelling));
  if (!type) _check_unit_static(c, spelling, origin);
  return type;
}

static List _resolve_identifier(
  Compiler c, Var value, Type type, Token origin) {
  if (type === %(<macro-expr>)) type = NULL;
  int read_reference = !type;
  int require_type = 0;
  List binding = _identifier_binding(c, value, type, origin, require_type);
  int macro_binder = value.is_binder() ||
    (value is <list> && !value.is_nil() &&
     value.car() == <macro-bind>);
  if (!binding && macro_binder) return %(expr (<macro-expr>) (ident $value));
  Map binding_facts = c.semantic_binding_facts();
  String spelling = binding_identity_spelling(binding);
  _capture_identifier(c, binding);
  _shadow_identifier(c, binding, type, spelling, binding_facts);
  if (!type) type = _identifier_type(
    c, binding, spelling, binding_facts, origin);
  if (!type && require_type)
    c.report_error(
      <type>, %"identifier ${value.repr()} has no semantic type",
      origin, NULL);
  List result = %(expr $type (ident $binding));
  if (c.lambda_scopes && !c.macro_holes) {
    result = c.capture_lambda_identifier(binding, type);
    match (result)
      case %(expr ?captured_type ${$source_identifier_content(
          %(?captured))}): {
        if (type.car() != <&> && captured_type.car() == <&>)
          read_reference = 1;
        type = captured_type;
        binding = captured;
      }
  }
  return _read_bound_reference(
    c, result, binding, type, read_reference, binding_facts);
}

static int _expression_is_addressable(Compiler c, List expression) {
  match (expression) {
    case %(expr ? ${$source_identifier_content(%(?binding))}):
      return !c.semantic_binding_facts().contains(%(lambda-snapshot $binding));
    case %(expr ? ${$source_content_pattern(
        $indexed, %(?receiver ?selector))}): return 1;
    case %(expr ? ${$source_operator_content(
        %((!quote *) ?operand))}): return 1;
    case %(expr ? ${$source_operator_content(
        %((!quote ->) ?receiver ?field))}): return 1;
    case %(expr ? ${$source_content_pattern($grouped, %(?base))}):
      return _expression_is_addressable(c, base);
    case %(expr ? ${$source_operator_content(%(. ?base ?))}):
      return _expression_is_addressable(c, base);
  }
  return 0;
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

static List _method_bind(
  Compiler compiler, List receiver, Type type, Type declared, Token origin) {
  if (!declared || !type) return receiver;
  Type target = declared.canonicalize(), source = type.canonicalize();
  if (_receiver_points_to(source, target))
    compiler.report_error(
      <type>,
      %"method receiver ${type.repr()} is a pointer to ${declared.repr()}",
      origin,
      %("'.' reaches one pointer level; write (*receiver).method()"));
  if (target.car() != <*> || cdr(target) !== source)
    return receiver;
  if (!_expression_is_addressable(compiler, receiver))
    compiler.report_error(
      <type>, "method pointer receiver requires an addressable value",
      origin, %("bind the value to an object before calling the method"));
  List address = %(expr ${type.reference()} (op & (parens $receiver)));
  return compiler.convert_expression(address, declared);
}

static List _resolve_call_arguments(
  Compiler compiler, List receiver, List supplied, Token origin) {
  Array arguments = [];
  if (receiver) arguments.push(receiver);
  if (!receiver && !supplied) supplied = %((expr (void) ()));
  if (receiver && supplied === %((expr (void) ()))) supplied = NULL;
  foreach (Var argument, supplied) {
    int slot = argument is <list> && !argument.is_nil() &&
               argument.car() == <macro-slot>;
    Var value = compiler.evaluate_macro_slot(argument);
    if (value is <list> && !value.is_nil() &&
        value.car() == <seq>)
      foreach (List item, value.list().cdr())
        arguments.push(compiler.resolve_expression(item, origin));
    else if (slot)
      arguments.push(
        compiler.resolve_expression(
          compiler.lift_macro_lisp_expression(value, origin), origin)
      );
    else if (value is <list>)
      arguments.push(compiler.resolve_expression(value, origin));
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
      c.protocol_helpers.contains(
        %"discard-helper ${(long) binding}"))
    return callee;
  int which = 0, index = 0;
  foreach (Var argument, arguments) {
    if (argument is <list> && _is_operator_temporary(c, argument))
      which |= 1 << index;
    index++;
  }
  if (!which) return callee;
  String stem = binding_identity_spelling(binding);
  if (!stem) return callee;
  List helper = c.discard_helper(binding, callee_type, stem, which);
  if (!helper) return callee;
  List (helper_binding, signature) = helper;
  return %(expr $signature (ident $helper_binding));
}

static List _finish_call(
  Compiler compiler, Type result_type, List callee, Type callee_type,
  List receiver, List supplied, Token origin) {
  if (result_type === %(<macro-expr>)) result_type = NULL;
  Type applied = callee_type.apply();
  if (!applied && callee_type)
    applied = compiler.sym.resolve_key(callee_type).apply();
  List arguments = _resolve_call_arguments(
    compiler, receiver, supplied, origin);
  if (_deferred_receiver(callee) ||
      (receiver && _deferred_receiver(receiver)))
    result_type = %(<macro-expr>);
  foreach (Var argument, arguments)
    if (argument is <list> && !argument.is_nil()) {
      List syntax = argument;
      if (_deferred_receiver(syntax) ||
          syntax.car() == <macro-bind> || syntax.car() == <macro-slot>)
        result_type = %(<macro-expr>);
    }
  if (!result_type) result_type = applied;
  if (receiver && result_type !== %(<macro-expr>))
    match (callee_type)
      case %((func (!set ?parameters (*))) *):
        if (!_parameters_variadic(parameters) &&
            arguments.len() > List.len(parameters))
          compiler.report_error(
            <type>,
            %"method takes ${List.len(parameters) - 1} argument${
              List.len(parameters) == 2 ? "" : "s"}, not ${
              arguments.len() - 1}",
            origin, NULL);
  compiler.check_meta_call(callee, origin);
  callee = _discarding_callee(compiler, callee, callee_type, arguments);
  Macro called = $called;
  return compiler.rebuild_expression(
    result_type, called(callee, arguments));
}

/* One argument, taken by reference when the callee's signature asks for a
   reference and by value otherwise. */
macro open Statement $func_argument(Expr $function, Expr $storage,
    Expr $count, Expr $index, Expr $address, Expr $type, Expr $value) {
  if (x2c_func_reference_type($function, $count, $index))
    $storage[$index] = FuncArg_reference($address, $type);
  else $storage[$index] = $value;
}

/* A null argument: a reference takes it with the callee's own type. */
macro open Statement $func_null_argument(Expr $function, Expr $storage,
    Expr $count, Expr $index, Expr $value) {
  {
    List reference = x2c_func_reference_type($function, $count, $index);
    if (reference) $storage[$index] = FuncArg_reference(0, reference);
    else $storage[$index] = $value;
  }
}

/* The by-value alternative: the argument boxed, or the diagnostic call for
   a type with no Var form. */
macro open Expression $func_value(Expr $argument) => FuncArg_value($argument);

macro open Expression $func_opaque(Expr $function, Expr $index,
    Expr $type) => x2c_func_unrepresentable_argument($function, $index, $type);

/* A call with no arguments applies the callee directly. */
macro open Expression $func_apply(Expr $callee) => Func_apply($callee, 0, 0);

static int _null_argument(List argument) =>
  _integer_literal_kind(argument, NULL) == <zero> ||
  argument.match(%(expr ? ${$source_identifier_content(
    %((binding ? "NULL")))}));

/** Returns one `$func_argument` or `$func_null_argument` application for
    each of `arguments`, preparing it into `storage` for the call through
    `function`; the `$func_call` template calls this in a slot. The choice
    of address, type and by-value alternative follows the argument's type.
*/
List x2c_func_call_arguments(List function, List storage, List arguments) {
  Compiler c = Compiler.expanding();
  Macro prepare = $func_argument, absent = $func_null_argument,
        boxed = $func_value, opaque = $func_opaque;
  List count = x2c_literal_int(arguments.len());
  Array prepared = [];
  int position = 0;
  foreach (List argument, arguments) {
    List index = x2c_literal_int(position++);
    Type type = argument.cadr();
    int forwarded = type.car() == <opt-ref>;
    List source = c.cache_literal_list(
      c.sym.normalize_declared_type(forwarded ? type.cdr() : type));
    List value = c.bind_syntax(
      c.sym.var_tag_for_type(type, NULL)
        ? boxed(c.convert_expression(argument, %("Var")))
        : opaque(function, index, source),
      AST_EXPRESSION, NULL);
    if (_null_argument(argument)) {
      prepared.push(absent(function, storage, count, index, value));
      continue;
    }
    int addressable = _expression_is_addressable(c, argument);
    List address = forwarded ? argument
      : addressable ? %(expr ${type.reference()} (op & (parens $argument)))
      : x2c_literal_int(0);
    List carrier = forwarded || addressable ? source : x2c_literal_int(0);
    prepared.push(
      prepare(function, storage, count, index, address, carrier, value));
  }
  return prepared.list_free();
}

/* A dynamic Func call stores its callee once, prepares each argument into
   an array from left to right, and applies the callee. Func_apply validates
   arity and dispatches; the selected adapter checks carrier, type and
   conversion. The call is the value of a statement expression around this
   block. */
macro open Statement $func_call(Expr $callee, Expr $count,
    Expr $arguments...) {
  {
    Func function = $callee;
    FuncArg storage[$count];
    $x2c_func_call_arguments(function, storage, $arguments)...
    Func_apply(function, $count, storage);
  }
}

static List _resolve_func_call(
  Compiler compiler, List callee, List supplied, Token origin) {
  List arguments = _resolve_call_arguments(compiler, NULL, supplied, origin);
  match (arguments)
    case %((expr (void) ())): arguments = NULL;
  if (!arguments) {
    Macro apply = $func_apply;
    return compiler.bind_syntax(apply(callee), AST_EXPRESSION, NULL);
  }
  Macro call = $func_call;
  return %(expr ("Var") (parens ${compiler.bind_syntax(
    call(callee, arguments.len(), arguments), AST_BLOCK, NULL)}));
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

/** Returns the callee and arguments of a typed `Func` call, or NULL for any
    other expression. `content` is the body of the call's `expr` node. Each
    argument is `(func-arg value address source)`: the argument boxed as a
    Var, or `(no-value)` when it has no Var form; its address, or 0; and its
    type, which is `(expr ("List") (ident reference))` for a null argument
    that takes the callee's own type. */
List Compiler.func_call_parts(Compiler compiler, Var content) {
  Macro call = $func_call, apply = $func_apply, prepare = $func_argument,
        absent = $func_null_argument, boxed = $func_value;
  match (%(expr () $content)) case apply(?callee): return %($callee);
  List block = NULL;
  match (content) case $source_content_pattern($grouped, %(?inner)):
    block = inner;
  if (!block) return NULL;
  match (block)
    case call(?callee, ?count, *arguments): {
      Array parts = $auto([callee]);
      foreach (List argument, _slot_statements(arguments)) {
        Var value = %(no-value), address = NULL, source = NULL;
        match (argument) {
          case prepare(
            ?function, ?storage, ?count, ?index, ?pointer,
            ?type, ?alternative): {
            match (alternative) case boxed(?boxed_value): value = boxed_value;
            address = pointer;
            source = type;
          }
          case absent(?function, ?storage, ?count, ?index, ?alternative): {
            match (alternative) case boxed(?boxed_value): value = boxed_value;
            address = x2c_literal_int(0);
            source = %(expr ("List") (ident reference));
          }
          default: return NULL;
        }
        parts.push(%(func-arg $value $address $source));
      }
      return parts;
    }
  return NULL;
}

/* The function being defined may be the implicit crossing itself, as a
   `Var.row` converter is for a `Row` destination; its explicit calls are how
   the crossing is written, not a repetition of it. */
static int _defines_crossing(Compiler c, Type source, Type target) {
  if (!c.fn_name || !source.match(%(?)) || !target.match(%(?))) return 0;
  String from = source.car().str(), to = target.car().str();
  return c.fn_name == %"${from}_${to.lower()}" ||
    c.fn_name == %"${from}_str" || c.fn_name == %"${from}_var";
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

static int _implicit_converter(
  Compiler c, List receiver, Type source, Type target,
  int source_is_var) =>
  source_is_var || c.sym.is_var_type(target) ||
  List.equal(c.sym.resolve_key(source), c.sym.resolve_key(target)) ||
  !!_converter_call(c, receiver, source, target);

static void _check_noted_converter(
  Compiler c, List noted, List parsed, Type target, int context) {
  if (!noted || !parsed || !target) return;
  (List call, String method, List location) = noted;
  if (!call.equal(parsed)) return;
  // A qualified target, such as `const char *`, is a different crossing.
  if (target.declared() != target.canonicalize() ||
      !List.equal(c.sym.resolve_key(call.cadr()), c.sym.resolve_key(target)))
    return;
  List receiver = call.caddr().caddr().cadr();
  Type source = receiver.cadr();
  if (!source) return;
  int source_is_var = c.sym.is_var_type(source);
  /* `Var.str` displays any value, while the implicit crossing to String
     reads the String payload: a different operation for a Symbol or a
     number. A hole and a format render a Var through `Var.str`, so there
     only `.str()` repeats the crossing. */
  if (source_is_var && (method == "str") != (context != 0)) return;
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
  String hint = context == 1 ? "remove the call; the hole renders the value"
    : context == 2 ? "remove the call; the format converts the value"
    : "remove the call; the destination converts the value";
  c.report_warning_at(
    <conversion>,
    %"unnecessary conversion: .$method() where ${target.repr()} is expected",
    location, %($hint));
}

typedef struct MemberCall {
  Compiler compiler;
  Type result_type, type;
  List receiver, field, supplied;
  Token origin;
  String method;
} MemberCall;

static List MemberCall._lookup(MemberCall *m) {
  m.receiver = m.compiler.resolve_expression(m.receiver, m.origin);
  m.type = m.receiver.cadr();
  m.method = m.field.car().str();
  List resolution = m.compiler.resolve_postfix_member(
    m.type, m.field, <.>, 1);
  if (!resolution && _expr_is_raw_string_literal(m.receiver)) {
    m.receiver = m.compiler.promote_string_literal(m.receiver);
    m.type = m.receiver.cadr();
    resolution = m.compiler.resolve_postfix_member(
      m.type, m.field, <.>, 1);
  }
  return resolution ? resolution : _resolve_delegate_method(
    m.compiler, m.type, m.method, m.origin);
}

static List MemberCall._bound(
  MemberCall *m, List binding, Type signature, List declared,
  List parameters, List returns) {
  m.receiver = _method_bind(
    m.compiler, m.receiver, m.type, declared, m.origin);
  List callee = %(expr ((func $parameters) $returns) (ident $binding));
  return _finish_call(
    m.compiler, signature.apply(), callee,
    signature, m.receiver, m.supplied, m.origin);
}

static List MemberCall._invoke(MemberCall *m) {
  List resolution = m._lookup();
  if (!resolution && _deferred_receiver(m.receiver)) {
    List callee = %(expr (<macro-expr>) (op . ${m.receiver} ${m.field}));
    return _finish_call(
      m.compiler, m.result_type, callee, NULL,
      NULL, m.supplied, m.origin);
  }
  if (!resolution) {
    Var name = m.field.car();
    m.compiler.report_error(
      <type>, %"type ${m.type.repr()} has no method $name",
      m.origin, NULL);
  }
  match (resolution) {
    case %(ambiguous *packages):
      _report_method_ambiguity(
        m.compiler, m.type, m.method, packages,
        NULL, m.origin);
    case %(method ?binding (!set ?signature
      ((func (!set ?parameters (?declared *))) *returns))):
      return m._bound(binding, signature, declared, parameters, returns);
    case %(delegate ?binding (!set ?signature
           ((func (!set ?parameters (?declared *))) *returns))
           ?path): {
      m.receiver = _materialize_delegate_receiver(m.receiver, path);
      m.type = m.receiver.cadr();
      return m._bound(binding, signature, declared, parameters, returns);
    }
    case %(field ?access ?field_type): {
      List callee = %(expr $field_type
        (op $access ${m.receiver} ${m.field}));
      return _finish_call(
        m.compiler, m.result_type, callee,
        field_type, NULL, m.supplied, m.origin);
    }
  }
  return NULL;
}

static List _resolve_member_call(
  Compiler c, Type result_type, List receiver, List field,
  List supplied, Token origin) {
  MemberCall call = {
    .compiler = c, .result_type = result_type,
    .receiver = receiver, .field = field, .supplied = supplied,
    .origin = origin};
  return call._invoke();
}

static List _resolve_call(
  Compiler c, Type result_type, List function, List supplied,
  Token origin) {
  match (function)
    case %(expr ? ${$source_operator_content(
        %(. ?receiver (!set ?field (?name))))}):
      return _resolve_member_call(
        c, result_type, receiver, field, supplied, origin);
  List resolved = c.resolve_expression(function, origin);
  Type type = resolved.cadr();
  Type func_type = c.sym.resolve_key(%("Func"));
  if (type && c.sym.resolve_key(type).equal(func_type))
    return _resolve_func_call(c, resolved, supplied, origin);
  return _finish_call(
    c, result_type, resolved, type, NULL, supplied, origin);
}

/** Returns the exact Var tag for a type test, rejecting types without one.
    Enums retain no identity after boxing and cannot be tested this way.
*/
Symbol Compiler.require_var_tag(
  Compiler compiler, Type target, Token origin) {
  Type resolved = NULL;
  Symbol vartag = compiler.sym.var_tag_for_type(target, resolved);
  if (resolved && resolved.is_enum()) {
    String note =
      "enum values box as the shared i32 family and retain no enum identity";
    compiler.report_error(
      <type>, %"enum type ${target.repr()} cannot be tested with 'is'",
      origin, %($note));
  }
  if (!vartag)
    compiler.report_error(
      <type>,
      %"type ${target.repr()} has no supported Var tag for operator 'is'",
      origin, NULL);
  return vartag;
}

static int _deferred_type_test(Type target) {
  foreach (Var specifier, target)
    match (specifier)
      case %((!or macro-bind macro-slot) *): return 1;
  return 0;
}

/** Builds an exact tag expression, deferring macro type slots until
    binding. */
List Compiler.var_tag_expression(Compiler c, Type target, Token origin) {
  if (_deferred_type_test(target))
    return %(expr (<macro-expr>) (type-tag $target));
  Symbol tag = c.require_var_tag(target, origin);
  return %(expr ("Symbol") (literal ("Symbol") ${tag.str()} $tag));
}

static void _convert_string_comparison(
  Compiler c, Symbol operator, List &lhs, List &rhs) {
  if (operator != <==> && operator != <!=> && operator != <"<"> &&
      operator != <">"> && operator != <"<="> && operator != <">=">)
    return;
  Type lhs_type = lhs.cadr(), rhs_type = rhs.cadr();
  if (c.sym.is_string_type(lhs_type) && _expr_is_raw_string_literal(rhs))
    rhs = c.convert_expression(rhs, lhs_type);
  else if (c.sym.is_string_type(rhs_type) &&
           _expr_is_raw_string_literal(lhs))
    lhs = c.convert_expression(lhs, rhs_type);
}

static int _convert_string_addition(
  Compiler c, Symbol operator, List &lhs, List &rhs) {
  if (operator != <+> || !_expr_is_string_like(c, lhs) ||
      !_expr_is_string_like(c, rhs)) return 0;
  Var matched;
  List bindings;
  /* Bare `%(ident *)` also matches literal data ending in <ident>. */
  int constant =
    !lhs.try_search($source_identifier_content(%((*))),
      matched, bindings) &&
    !rhs.try_search($source_identifier_content(%((*))),
      matched, bindings);
  lhs = c.convert_expression(lhs, %("String"));
  rhs = c.convert_expression(rhs, %("String"));
  return constant;
}

static void _check_untyped_operand(
  Compiler c, Symbol operator, Type participant, List other,
  Token origin) {
  Symbol member = c.operator_member(operator);
  if (!member || operator == <==> || operator == <!=>) return;
  if (_converts_operands(c, participant) &&
      c.resolve_protocol_member(participant, member) &&
      other.match(%(expr ? ${$source_identifier_content(%(?))})))
    c.report_error(
      <type>, "operand has no x2c type beside a protocol participant",
      origin, %("a preprocessor macro has no type here: cast it, or bind its value to a local"));
}

static void _check_matmul(
  Compiler c, Symbol operator, Type lhs_type, Type rhs_type,
  Token origin) {
  if (operator == <@> && !c.sym.is_var_type(lhs_type) &&
      !c.sym.is_var_type(rhs_type))
    c.report_error(
      <type>, "operator '@' requires an implemented matmul member",
      origin,
      %("left type: ${lhs_type.repr()} right type: ${rhs_type.repr()}"));
}

/* Operands have been resolved in the caller's current semantic scope. */
static List _native_binary_expression(
  Compiler c, Symbol operator, List lhs, List rhs,
  Type lhs_type, Type rhs_type, Token origin) {
  Type type = c._binary_op_type(operator, lhs, rhs);
  List operation = source_operator_content(%($operator $lhs $rhs));
  if (c.sym.is_var_type(lhs_type) || c.sym.is_var_type(rhs_type))
    operation = c.anchor_origin(operation, origin);
  return %(expr $type $operation);
}

static List Compiler._binary_expression(
  Compiler c, Symbol operator, List lhs, List rhs, Token origin) {
  Type lhs_type = lhs.cadr(), rhs_type = rhs.cadr();
  if (lhs_type === %(<macro-expr>) ||
      rhs_type === %(<macro-expr>))
    return source_operator_expression(
      %(<macro-expr>), %($operator $lhs $rhs));
  if (operator.is_assignment_op()) {
    Type type = lhs_type;
    /* Meta lowering adapts a callable stored to a Func itself; converting
       here would lift a function name to a hidden global first. */
    if (operator == <=> &&
        !(c.meta_body && c.sym.is_named_value_type(type, "Func")))
      rhs = c.convert_expression(rhs, type);
    return source_operator_expression(type, %($operator $lhs $rhs));
  }
  _convert_string_comparison(c, operator, lhs, rhs);
  int constant_string = _convert_string_addition(c, operator, lhs, rhs);
  List lowered = c._protocol_operator_expression(operator, lhs, rhs);
  if (lowered) {
    if (!constant_string) return lowered;
    List cached = c.cache(%(string $lowered));
    return %(expr ("String") $cached);
  }
  if (operator == <in>)
    c.report_error(
      <type>, "operator 'in' requires an implemented contains member",
      origin, %("receiver type: ${rhs_type.repr()}"));
  /* An untyped preprocessor name beside a converting protocol participant
     would reach the C compiler with no usable conversion. */
  if ((lhs_type != NULL) != (rhs_type != NULL))
    _check_untyped_operand(
      c, operator, lhs_type ? lhs_type : rhs_type,
      lhs_type ? rhs : lhs, origin);
  _check_matmul(c, operator, lhs_type, rhs_type, origin);
  return _native_binary_expression(
    c, operator, lhs, rhs, lhs_type, rhs_type, origin);
}

/* A statically known tag whose encoding row the decoder discriminates on
   `top` and `bottom` alone tests as two compares. `Var.is_row` takes the
   row as constants so the C compiler folds them and the operand is
   evaluated once. Tags with a validity clause, an immediate width, or a
   user registration have no row and keep the deciding decode. */
static List _constant_row_test(
  Compiler c, List lhs, Symbol tag, Token origin) {
  unsigned long top, mask, bottom;
  if (!Type.var_tag_row(tag, top, mask, bottom)) return NULL;
  List callee = _resolve_identifier(c, "Var_is_row", NULL, origin);
  List arguments = %($lhs
    (expr (unsigned) (literal (unsigned) "$top"))
    (expr (unsigned long) (literal (unsigned long) "$mask"))
    (expr (unsigned long) (literal (unsigned long) "$bottom")));
  Macro called = $called;
  return c.rebuild_expression(%(int), called(callee, arguments));
}

static List _resolve_initializer(Compiler c, List node, Token origin) {
  match (node) {
    case %(dotinit ?field ?value):
      return %(dotinit $field ${_resolve_initializer(c, value, origin)});
    case %(indexinit ?index ?value):
      return %(indexinit ${c.resolve_expression(index, origin)}
               ${_resolve_initializer(c, value, origin)});
  }
  return c.resolve_expression(node, origin);
}

static List _resolve_segments(
  Compiler c, List items, Token origin) {
  Array resolved = [];
  Type type = %("String");
  foreach (List item, items) match (item) {
    case %((!set ?tag (!or segvar segexp)) ?value): {
      List expression = c.resolve_expression(value, origin);
      if (_deferred_receiver(expression)) {
        type = %(<macro-expr>);
        resolved.push(%($tag $expression));
        continue;
      }
      resolved.push(%($tag ${c.convert_segment_to_string(expression)}));
      continue;
    }
    default: resolved.push(item);
  }
  return %(expr $type ${source_string_content(resolved.list_free())});
}

static List _resolve_initval(
  Compiler c, Type input_type, List content, Token origin) {
  List header = NULL;
  List cases = Ast.initializer_cases(content, header);
  Array resolved = [];
  if (header) {
    Array inputs = [];
    foreach (List argument, header.cdr()) {
      List value = c.resolve_expression(argument.cadr(), origin);
      inputs.push(%(${argument.car()} $value));
    }
    resolved.push(%(input @{inputs.list_free()}));
  }
  foreach (List choice, cases) {
    (List condition, List path, Type destination, List value) = choice;
    if (condition) condition = c.resolve_expression(condition, origin);
    value = c.resolve_expression(value, origin);
    resolved.push(%($condition $path $destination $value));
  }
  return %(expr $input_type (initval @{resolved.list_free()}));
}

static List _resolve_is_type(
  Compiler c, List operand, Type target, Token origin) {
  List lhs = c.resolve_expression(operand, origin);
  Type lhs_type = lhs.cadr();
  if (_deferred_receiver(lhs) || _deferred_type_test(target)) {
    Macro has_type = $has_type;
    return c.rebuild_expression(%(<macro-expr>), has_type(lhs, target));
  }
  if (!c.sym.is_var_type(lhs_type))
    c.report_error(
      <type>, "operator 'is' requires Var on the left",
      origin, %("operand type: ${lhs_type.repr()}"));
  Macro called = $called;
  if (target === %(void) || target === %("Void")) {
    List callee = _resolve_identifier(c, "Var_is_void", NULL, origin);
    return c.rebuild_expression(%(int), called(callee, %($lhs)));
  }
  Symbol vartag = c.require_var_tag(target, origin);
  List direct = _constant_row_test(c, lhs, vartag, origin);
  if (direct) return direct;
  String tagsym = %"${(unsigned long) vartag}";
  List callee = _resolve_identifier(c, "Var_is", NULL, origin);
  return c.rebuild_expression(
    %(int), called(callee, %($lhs (expr ("Symbol") $tagsym))));
}

static List _resolve_is_symbol(
  Compiler c, List operand, List selector, Token origin) {
  List lhs = c.resolve_expression(operand, origin);
  selector = c.resolve_expression(selector, origin);
  Type lhs_type = lhs.cadr(), selector_type = selector.cadr();
  if (_deferred_receiver(lhs) || _deferred_receiver(selector)) {
    Macro has_symbol = $has_symbol;
    return c.rebuild_expression(
      %(<macro-expr>), has_symbol(lhs, selector));
  }
  if (!c.sym.is_var_type(lhs_type))
    c.report_error(
      <type>, "operator 'is' requires Var on the left",
      origin, %("operand type: ${lhs_type.repr()}"));
  if (!c.sym.is_named_value_type(selector_type, "Symbol"))
    c.report_error(
      <type>, "operator 'is' requires a type or Symbol on the right",
      origin, %("operand type: ${selector_type.repr()}"));
  match (selector)
    case %(expr ("Symbol") ${$source_literal_content(
        %(("Symbol") ? ?tag_value))}): {
      if (tag_value is <symbol>) {
        Symbol tag = tag_value;
        List direct = _constant_row_test(c, lhs, tag, origin);
        if (direct) return direct;
      }
    }
  List callee = _resolve_identifier(c, "Var_is", NULL, origin);
  Macro called = $called;
  return c.rebuild_expression(%(int), called(callee, %($lhs $selector)));
}

static List _resolve_cons(
  Compiler c, Type input_type, List head, List tail, Token origin) {
  head = c.resolve_expression(head, origin);
  tail = c.resolve_expression(tail, origin);
  Type type = input_type ? input_type : %("List");
  if (_deferred_receiver(head) || _deferred_receiver(tail))
    return %(expr $type (cons $head $tail));
  head = c.convert_expression(head, %("Var"));
  List cached = c.cache_cons_cell(head, tail);
  if (cached) return cached;
  return %(expr $type (cons $head $tail));
}

static List _resolve_append(
  Compiler c, Type input_type, List head, List tail, Token origin) {
  head = c.resolve_expression(head, origin);
  tail = c.resolve_expression(tail, origin);
  head = c.sym.is_var_type(head.cadr())
       ? %(expr ("List") (call "Var_list" (args $head)))
       : c.convert_expression(head, %("List"));
  return %(expr ${input_type ? input_type : %("List")}
           (append $head $tail));
}

static List _resolve_slice(
  Compiler c, Type input_type, List receiver, List start, List stop,
  List step, Token origin) {
  receiver = c.resolve_expression(receiver, origin);
  if (start) start = c.resolve_expression(start, origin);
  if (stop) stop = c.resolve_expression(stop, origin);
  if (step) step = c.resolve_expression(step, origin);
  List operation = source_slice_content(%($receiver $start $stop $step));
  if (input_type === %(<macro-expr>))
    operation = c.anchor_origin(operation, origin);
  return %(expr ${receiver.cadr()} $operation);
}

static List _resolve_generic(
  Compiler c, List control, List associations, Token origin) {
  control = c.resolve_expression(control, origin);
  Array resolved = [];
  foreach (List association, associations) match (association)
    case %(association ?selector ?value):
      resolved.push(
        %(association $selector ${c.resolve_expression(value, origin)}));
  Type type = control.cadr() === %(<macro-expr>) ? %(<macro-expr>) : NULL;
  return %(expr $type ${source_generic_content(
    %($control @{resolved.list_free()}))});
}

static List _resolve_cast(
  Compiler c, List declaration, List operand, Token origin) {
  operand = c.resolve_expression(operand, origin);
  declaration = c.bind_syntax(declaration, AST_BLOCK, c.return_type);
  List typed = %(declare @{declaration.cdr()});
  Type type = operand.cadr() === %(<macro-expr>) ||
              _casts_to_template_typedef(c, declaration)
            ? %(<macro-expr>) : typed.type_from_ast();
  return %(expr $type (cast $declaration $operand));
}

static List _resolve_unary(
  Compiler c, Var operator, List operand, Token origin) {
  List lhs = c.resolve_expression(operand, origin);
  Type lhs_type = lhs.cadr();
  if (lhs_type.car() == <opt-ref> && operator != <!>)
    c.report_error(
      <type>, "check optional reference before using its value",
      origin, NULL);
  if (operator == <*> && operand.cadr().car() == <&> &&
      lhs_type.car() != <&>) return lhs;
  if (lhs_type === %(<macro-expr>))
    return source_operator_expression(%(<macro-expr>), %($operator $lhs));
  List lowered = operator == <->
    ? c._protocol_operator_expression(operator, lhs, NULL) : NULL;
  if (lowered) return lowered;
  Type type = lhs_type;
  switch (operator.symbol()) {
    case <!>: type = %(int); break;
    case <*>: {
      Type pointee = type.dereference();
      type = pointee ? pointee : c.sym.resolve_key(type).dereference();
      break;
    }
    case <&>: type = type.reference(); break;
    case <~>: case <+>: case <->: {
      type = c.sym.resolve_numeric_type(type);
      if (type && type.is_integral()) type = type.promote();
      if (!type && lhs_type && operator == <->)
        c.report_error(
          <type>,
          "unary '-' requires a numeric type or implemented neg",
          origin, %("operand type: ${lhs_type.repr()}"));
      if (!type) type = lhs_type;
      break;
    }
  }
  return source_operator_expression(type, %($operator $lhs));
}

static List _resolve_conditional(
  Compiler c, Var operator, List condition, List ontrue,
  List onfalse, Token origin) {
  condition = c.resolve_expression(condition, origin);
  ontrue = c.resolve_expression(ontrue, origin);
  onfalse = c.resolve_expression(onfalse, origin);
  Type true_type = ontrue.cadr(), false_type = onfalse.cadr();
  if (condition.cadr() === %(<macro-expr>) ||
      true_type === %(<macro-expr>) ||
      false_type === %(<macro-expr>))
    return source_operator_expression(
      %(<macro-expr>), %($operator $condition $ontrue $onfalse));
  /* Arms of one declared type keep it, so a `Symbol` conditional stays a
     `Symbol` rather than the integer that represents it. */
  Type type = true_type;
  if (true_type.declared() != false_type.declared()) {
    Type left = c.sym.resolve_numeric_type(type);
    Type right = c.sym.resolve_numeric_type(false_type);
    if (left && right) type = left.widest(right);
    else if (_conditional_joins(c, false_type, true_type)) {
      type = false_type;
      ontrue = c.convert_expression(ontrue, type);
    }
    else if (_conditional_joins(c, true_type, false_type))
      onfalse = c.convert_expression(onfalse, type);
  }
  return source_operator_expression(
    type, %($operator $condition $ontrue $onfalse));
}

static List _resolve_tadapt(
  Compiler c, List target, List source, Token origin) {
  target = c.resolve_expression(target, origin);
  source = c.resolve_expression(source, origin);
  match (target)
    case %(expr (!set ?syntax (typedef ?target_type)) ?): {
      Type type = c.sym.resolve_key(syntax);
      if (!type || !type.is_pointer() ||
          !type.dereference().is_function())
        c.report_error(
          <macro>,
          "typed callback adapter target must name a function pointer",
          origin, type ? %("target type: ${type.repr()}") : NULL);
      return %(expr ($target_type) (tadapt ${c.origin} $source));
    }
  c.report_error(
    <macro>, "typed callback adapter target must be a typedef name",
    origin, NULL);
}

static List _resolve_indexed(
  Compiler c, List receiver, List selector, Token origin) {
  receiver = c.resolve_expression(receiver, origin);
  selector = c.resolve_expression(selector, origin);
  if (receiver.cadr().car() == <opt-ref>)
    c.report_error(
      <type>, "check optional reference before indexing its value",
      origin, NULL);
  if (_deferred_receiver(receiver) || _deferred_receiver(selector))
    return %(expr (<macro-expr>) (index $receiver $selector));
  List resolved = c._postfix_index_expression(receiver, selector);
  if (resolved) return resolved;
  Type receiver_type = receiver.cadr();
  // A field of a foreign struct has no x2c type; C indexes it alone.
  if (!receiver_type &&
      List.match(receiver, %(expr () ${$source_operator_content(
        %((!or . ->) * *))})))
    return %(expr () (index $receiver $selector));
  c.report_error(
    <parse>, receiver_type.is_typedef_name()
      ? %"type $receiver_type does not support getindex"
      : %"type $receiver_type does not support indexing",
    origin, %());
}

static List _resolve_member(
  Compiler c, Var operator, List receiver, List field, Token origin) {
  receiver = c.resolve_expression(receiver, origin);
  Type receiver_type = receiver.cadr();
  List resolution = c.resolve_postfix_member(
    receiver_type, field, operator, 0);
  match (resolution)
    case %(field ?access ?field_type):
      return source_operator_expression(
        field_type, %($access $receiver $field));
  Type type = _deferred_receiver(receiver) ? %(<macro-expr>) : NULL;
  return source_operator_expression(type, %($operator $receiver $field));
}

static List _resolve_postfix_op(
  Compiler c, Var operator, List operand, Token origin) {
  operand = c.resolve_expression(operand, origin);
  Type operand_type = operand.cadr();
  if (operand_type.car() == <opt-ref>)
    c.report_error(
      <type>, "check optional reference before using its value",
      origin, NULL);
  if (operand_type === %(<macro-expr>))
    return source_postfix_expression(
      %(<macro-expr>), %($operator $operand));
  return source_postfix_expression(
    operand_type, %($operator $operand));
}

static List _resolve_macro_slot(
  Compiler c, List input, List content, Token origin) {
  if (c.macro_holes) return input;
  Var value = c.evaluate_macro_slot(content);
  match (value)
    case %(!set ?expression (expr ? ?)):
      return c.resolve_expression(expression, origin);
  return c.resolve_expression(
    c.lift_macro_lisp_expression(value, origin), origin);
}

static List _resolve_destructure(
  Compiler c, List targets, List source, Token origin) {
  Array resolved = [];
  foreach (List target, targets)
    resolved.push(c.resolve_expression(target, origin));
  source = c.resolve_expression(source, origin);
  return %(expr ${source.cadr()}
           (dstrasgn (targets @{resolved.list_free()}) $source));
}

static List _resolve_commas(
  Compiler c, Type input_type, List expressions, Token origin) {
  Array resolved = [];
  foreach (List expression, expressions)
    resolved.push(c.resolve_expression(expression, origin));
  List values = resolved.list_free();
  Type type = input_type;
  if (values) type = values.last().cadr();
  return %(expr $type ${source_commas_content(values)});
}

static List _resolve_composite(
  Compiler c, Type input_type, List elements, Token origin) {
  Array values = [];
  foreach (List element, elements)
    values.push(_resolve_initializer(c, element, origin));
  return %(expr $input_type ${source_composite_content(
    values.list_free())});
}

static List _resolve_managed_init(
  Compiler c, List initializer, Token origin) {
  initializer = c.resolve_expression(initializer, origin);
  Type type = initializer.cadr();
  return %(expr $type (managed-init $initializer));
}

static List _resolve_invocation(
  Compiler c, List input, Var definition, List arguments,
  Var invocation) {
  Token site = c.macro_invocation_site(invocation);
  if (!site) return input;
  return c.expand_macro_invocation_node(
    definition, arguments, site, AST_EXPRESSION);
}

static List _resolve_binary(
  Compiler c, Var operator, List left, List right, Token origin) {
  List lhs = c.resolve_expression(left, origin);
  List rhs = c.resolve_expression(right, origin);
  return c._binary_expression(operator, lhs, rhs, origin);
}

static List _resolve_lambda(
  Compiler c, List input, Type input_type, List body,
  List captures, List params) {
  if (c.macro_holes) return input;
  return c.bind_lambda_expression(
    input_type, %(params @params), captures, body);
}

static List _resolve_source(
  Compiler c, List input, Type input_type, List content) {
  match (content) case %(at m-origin ?inner): {
    if (!c.source_map || c.macro_holes) return input;
    return %(expr $input_type (at ${c.origin} $inner));
  }
  return input;
}

static List _resolve_native_call(
  Compiler c, Type input_type, String callee, List supplied,
  Token origin) {
  List arguments = _resolve_call_arguments(c, NULL, supplied, origin);
  return %(expr $input_type (call $callee (args @arguments)));
}

static List _resolve_parens(
  Compiler c, List inner, Token origin) {
  inner = c.resolve_expression(inner, origin);
  Type type = inner.cadr();
  return %(expr $type (parens $inner));
}

static List _resolve_content(
  Compiler c, List input, Type input_type, List content, Token origin) {
  Macro lambda = $lambda_expression, captured = $lambda_captured;
  Macro grouped_sizeof = $sizeof_grouped,
        expression_sizeof = $sizeof_expression;
  match (input) {
    case captured(?body, *captures, *params):
      return _resolve_lambda(c, input, input_type, body, captures, params);
    case lambda(?body, *params):
      return _resolve_lambda(c, input, input_type, body, NULL, params);
  }
  // Source-form cases examine input through origin and source wrappers.
  if (content &&
      (content.car() == <at> || content.car() == <src>))
    return _resolve_source(c, input, input_type, content);
  if (content && content.car() == <expr>)
    match (content) case %(!set ?inner (expr ? ?)):
      return c.resolve_expression(inner, origin);
  Macro indexed = $indexed;
  match (input) case indexed(?receiver, ?selector):
    return _resolve_indexed(c, receiver, selector, origin);
  match (content) case %(call ?(String callee) (args *supplied)):
    return _resolve_native_call(c, input_type, callee, supplied, origin);
  Macro called = $called;
  match (input) case called(?callee, *supplied):
    return _resolve_call(c, input_type, callee, supplied, origin);
  match (content) {
    case %(managed-init ?initializer):
      return _resolve_managed_init(c, initializer, origin);
    case $source_identifier_content(%(?value)):
      return _resolve_identifier(c, value, input_type, origin);
    case %(!set ?binding (binding ? ?)):
      if (binding_identity_try_parts(binding, NULL, NULL))
        return _resolve_identifier(c, binding, input_type, origin);
    case $source_literal_content(%(*)): return input;
    case %(tpl-call *): return input;
    case %(meta-call ?callee (args *arguments)): {
      if (c.meta_body || c.macro_holes) return input;
      return c.evaluate_meta_expression(input, origin);
    }
    case %(meta-cap *): return input;
    case %(macro-invoke ?definition ?arguments ?invocation):
      return _resolve_invocation(c, input, definition, arguments, invocation);
    case %(macro-slot ? ? *):
      return _resolve_macro_slot(c, input, content, origin);
    case $source_string_content(%(*items)):
      return _resolve_segments(c, items, origin);
    case %(cons ?head ?tail):
      return _resolve_cons(c, input_type, head, tail, origin);
    case %(append ?head ?tail):
      return _resolve_append(c, input_type, head, tail, origin);
    case $source_slice_content(%(?receiver ?start ?stop ?step)):
      return _resolve_slice(
        c, input_type, receiver, start, stop, step, origin);
    case %(getindex ?receiver ?selector):
      return %(expr $input_type
               (getindex ${c.resolve_expression(receiver, origin)}
                         ${c.resolve_expression(selector, origin)}));
    case %(dstrasgn (targets *targets) ?source):
      return _resolve_destructure(c, targets, source, origin);
    case $source_content_pattern($sizeof_grouped, %(?argument)):
      if (argument is <list>) {
        List source_argument = argument;
        return c.rebuild_expression(input_type, grouped_sizeof(
          c.resolve_expression(source_argument, origin)));
      }
    case $source_content_pattern($sizeof_expression, %(?argument)):
      if (argument is <list>) {
        List source_argument = argument;
        return c.rebuild_expression(input_type, expression_sizeof(
          c.resolve_expression(source_argument, origin)));
      }
    case $source_generic_content(%(?control *associations)):
      return _resolve_generic(c, control, associations, origin);
    case $source_va_arg_content(%(?argument ?declaration)):
      return %(expr $input_type
               ${source_va_arg_content(%(
                 ${c.resolve_expression(argument, origin)}
                 ${c.resolve_expression(declaration, origin)}))});
    case $source_commas_content(%(*expressions)):
      return _resolve_commas(c, input_type, expressions, origin);
    case %(splice ?expression):
      return %(expr $input_type
               (splice ${c.resolve_expression(expression, origin)}));
    case %((!or offsetof nil cache macro-bind) *): return input;
    case $source_content_pattern($grouped, %(?inner)):
      return _resolve_parens(c, inner, origin);
    case %(initval *choices):
      return _resolve_initval(c, input_type, content, origin);
    case $source_composite_content(%(*elements)):
      return _resolve_composite(c, input_type, elements, origin);
    case $source_cast_content(
        %((!set ?declaration (decl *)) ?operand)):
      return _resolve_cast(c, declaration, operand, origin);
    case %(type-tag ?target):
      return c.var_tag_expression(target, origin);
    case $source_content_pattern($has_type, %(?operand ?target_syntax)):
      return _resolve_is_type(c, operand, target_syntax, origin);
    case $source_content_pattern($has_symbol, %(?operand ?selector)):
      return _resolve_is_symbol(c, operand, selector, origin);
    case $source_operator_content(
        %((!or (!set ?operator .) (!set ?operator (!quote ->)))
          ?receiver (!set ?field (*)))):
      return _resolve_member(c, operator, receiver, field, origin);
    case $source_operator_content(%(?operator ?operand)):
      return _resolve_unary(c, operator, operand, origin);
    case $source_operator_content(
        %(?operator ?condition ?ontrue ?onfalse)):
      return _resolve_conditional(
        c, operator, condition, ontrue, onfalse, origin);
    case $source_operator_content(%(?operator ?left ?right)):
      return _resolve_binary(c, operator, left, right, origin);
    case $source_postfix_content(%(?operator ?operand)):
      return _resolve_postfix_op(c, operator, operand, origin);
    case %(tadapt ?target ?source):
      return _resolve_tadapt(c, target, source, origin);
  }
  if (content && content.car() == <array>) {
    Macro array_value = $array_value;
    match (input) case array_value(*elements): {
      Array resolved = [];
      foreach (List element, elements)
        resolved.push(c.resolve_expression(element, origin));
      return c.rebuild_expression(
        input_type, array_value(resolved.list_free()));
    }
  }
  if (content && content.car() == <map>) {
    Macro map_value = $map_value;
    match (input) case map_value(*entries): {
      Array resolved = [];
      foreach (Var entry, entries)
        foreach (Var row, c.evaluate_macro_rows(entry))
          resolved.push(c.resolve_map_entry(row, origin));
      return c.rebuild_expression(
        input_type, map_value(resolved.list_free()));
    }
  }
  return input;
}

/** Resolves the key and value of one `(map-entry key value)` AST row.
    Any other shape is reported at `origin` as a parse error.
*/
List Compiler.resolve_map_entry(Compiler compiler, List input, Token origin) {
  match (input)
    case %(map-entry ?key ?value):
      return %(map-entry
        ${compiler.resolve_expression(key, origin)}
        ${compiler.resolve_expression(value, origin)});
  compiler.report_error(<parse>, "expected one Map entry", origin, NULL);
}

/** Resolves and type-annotates one expression AST in current compiler state.
    Existing `expr` type annotations are resolved semantic types.
    Already-resolved trees without unresolved descendants and non-expression
    inputs are returned unchanged; abstract declarations use the declaration
    binder. `origin` anchors diagnostics and generated operations that must
    retain source position.
*/
List Compiler.resolve_expression(Compiler c, List input, Token origin) {
  if (c.macro_application) {
    Var staged;
    int retained;
    Var carrier = input;
    match (input) case %(expr (<macro-expr>) ?inside): carrier = inside;
    if (c.take_code_value(carrier, staged, retained))
      return retained ? staged : c.resolve_expression(staged, origin);
  }
  match (input) {
    case %(decl *):
      return c.bind_syntax(input, AST_BLOCK, c.return_type);
    case %(expr ?type ?(List content)): {
      if (type && !_needs_resolution(c, input)) return input;
      return _resolve_content(c, input, type, content, origin);
    }
  }
  return input;
}

/* precedence, assignment, and primary syntax */

/* Each parser entry consumes exactly its grammar level and leaves
   `compiler.token` at the first token belonging to its caller. Operators are
   resolved as their AST nodes are built, so higher levels receive typed or
   deferred expression nodes. */
static List _parse_binary_level_tail(Compiler c, int level, List lhs) {
  int first = 1;
  while (_precedence(_binary_operator(c)) == level ||
         (level == 7 && _is_type_operator(c))) {
    if (_is_type_operator(c)) {
      Token origin = c.token;
      c.next();
      int negate = c.take_word("not");
      List test;
      if (_is_type_selector_start(c)) {
        Type target = _parse_is_type(c, origin);
        Macro has_type = $has_type;
        test = c.resolve_expression(
          c.rebuild_expression(NULL, has_type(lhs, target)), origin);
      }
      else {
        List selector = _parse_cast(c);
        Macro has_symbol = $has_symbol;
        test = c.resolve_expression(
          c.rebuild_expression(NULL, has_symbol(lhs, selector)), origin);
      }
      lhs = negate
        ? c.resolve_expression(%(expr () (op ! $test)), origin)
        : test;
      continue;
    }
    Symbol op = _binary_operator(c);
    Token origin = c.token;
    c.next();
    List rhs = _parse_binary_level(c, level + 1);
    if (first) {
      lhs = c.resolve_expression(lhs, origin);
      first = 0;
    }
    rhs = c.resolve_expression(rhs, origin);
    lhs = c._binary_expression(op, lhs, rhs, origin);
  }
  return lhs;
}

static List _parse_binary_level(Compiler compiler, int level) {
  if (level > 10) return _parse_cast(compiler);
  return _parse_binary_level_tail(
    compiler, level, _parse_binary_level(compiler, level + 1));
}

static List _parse_binary_levels_from(Compiler compiler, List lhs) {
  for (int level = 10; level > 0; level--)
    lhs = _parse_binary_level_tail(compiler, level, lhs);
  return lhs;
}

static List _parse_binary_ops(Compiler compiler) =>
  _parse_binary_level(compiler, 1);

static int _destructure_identifier(List expression) {
  match (expression) {
    case %(expr ? ${$source_identifier_content(%(?))}): return 1;
    case %(expr ? ${$source_content_pattern($grouped, %(?inner))}):
      match (inner)
        case %(expr ? ${$source_content_pattern(
          $dereferenced, %(?address))}):
          match (address) case %(expr (& *) ${$source_identifier_content(
              %(?))}): return 1;
  }
  return 0;
}

static List _destructure_targets(Compiler compiler, List lhs) {
  match (lhs)
    case %(expr ? ${$source_content_pattern($grouped, %(?target))}): {
      if (_destructure_identifier(target)) return %(targets $target);
      match (target)
        case %(expr ? ${$source_commas_content(%(*targets))}): {
          foreach (List entry, targets) {
            if (_destructure_identifier(entry)) continue;
            compiler.report_error(
              <parse>, "unsupported destructuring assignment target",
              compiler.token,
              %("destructuring targets must be simple identifiers"));
          }
          return %(targets @targets);
        }
    }
  return NULL;
}

static List _parse_comma_list(Compiler compiler) {
  Array expressions = [];
  do {
    compiler.expect(<,>);
    expressions.push(compiler.parse_assignment());
  } while (compiler.peek(0) == <,>);
  return expressions.list_free();
}

/* A bracketed index followed by `=`, `.`, or `[` designates an element;
   any other bracket is an Array literal. */
static int _bracket_designates(Compiler c) {
  Symbol type = c.token.after_group().type;
  return type == <=> || type == <.> || type == <[>;
}

/* An entry that begins with a Map-entry macro, or whose first bracket-level
   `:` belongs to no conditional, makes a brace a Map literal. */
static int _brace_starts_map(Compiler c) {
  if (c.macro_starts_target_at(AST_MAP_ENTRY)) return 1;
  Token token = c.token;
  for (int conditionals = 0;; token = token.after_group()) {
    switch (token.type) {
      case <eof>: case <;>: case <,>: case <")">: case <]>: case <"}">:
        return 0;
      case <?>:
        conditionals++;
        break;
      case <:>:
        if (!conditionals--) return token != c.token;
    }
  }
}

static List _parse_bracket_array(Compiler compiler) {
  compiler.expect(<[>);
  Array elements = [];
  while (compiler.peek(0) != <]>) {
    elements.push(compiler.parse_assignment());
    if (!compiler.test(<,>)) break;
  }
  compiler.expect(<]>);
  return %(expr ("Array") (array @{elements.list_free()}));
}

static List _parse_composite_elements(Compiler compiler) {
  Array elements = [];
  while (compiler.peek(0) != <"}">) {
    List element =
      _test_dot_init(compiler) ||
      (compiler.peek(0) == <[> && _bracket_designates(compiler))
        ? _parse_designated_init(compiler)
        : compiler.parse_assignment();
    elements.push(element);
    if (!compiler.test(<,>)) break;
  }
  return elements.list_free();
}

static List _parse_composite(Compiler compiler) {
  compiler.expect(<"{">);
  if (_brace_starts_map(compiler)) {
    List entries = compiler.parse_map_entries();
    compiler.expect(<"}">);
    return %(expr ("Map") (map @entries));
  }
  List elems = _parse_composite_elements(compiler);
  elems = %( commas @elems );
  compiler.expect(<"}">);
  return %(expr () ( composite $elems ));
}

/** Parses and resolves one complex identifier expression.
    Parsing starts at `compiler.token` and leaves it after the identifier.
*/
List Compiler.parse_variable(Compiler c) {
  Token origin = c.token;
  Var definition;
  // A macro defined to a string literal is that literal after preprocessing.
  if (c.object_macros.try_get(origin.text, definition) &&
      definition.equal(<string>)) {
    c.next();
    return _join_c_string_literals(
      c, %(expr (* char) (literal (* char) ${origin.text})));
  }
  List name = c.parse_complex_identifier();
  Token after = c.token;
  List result = c.resolve_expression(%(expr () (ident $name)), origin);
  if (c.source_facts) match (result)
    case %(expr ?type ${$source_identifier_content(%(?binding))}):
      c.record_source_reference(binding, type, origin, after);
  if (c.source_map &&
      (origin.text == "__FILE__" || origin.text == "__LINE__"))
    match (result) case %(expr ?type ?content):
      return %(expr $type ${c.anchor_origin(content, origin)});
  return result;
}

static List _parse_conditional_tail(Compiler compiler, List condition) {
  Token origin = compiler.token;
  if (!compiler.test(<?>)) return condition;
  List ontrue = compiler.parse_expression();
  compiler.expect(<:>);
  return compiler.resolve_expression(source_operator_expression(
    NULL, %(? $condition $ontrue ${compiler.parse_conditional()})), origin);
}

/** Parses a binary expression and its optional conditional tail.
    The false arm recurses at conditional precedence, making `?:`
    right-associative, and `compiler.token` stops after the expression.
*/
List Compiler.parse_conditional(Compiler compiler) =>
  _parse_conditional_tail(compiler, _parse_binary_ops(compiler));

static List _parse_assignment_tail(Compiler compiler, List lhs) {
  Symbol op = compiler.peek(0);
  Token origin = compiler.token;
  if (!op.is_assignment_op()) return lhs;
  if (lhs.cadr().car() == <opt-ref>)
    compiler.report_error(
      <type>, "check optional reference before assigning its value",
      origin, NULL);
  List targets = op == <=> ? _destructure_targets(compiler, lhs) : NULL;
  compiler.next();
  List rhs = compiler.parse_assignment();
  if (targets) match (rhs)
    case %(expr ?type ?): return %(expr $type (dstrasgn $targets $rhs));
  if (op == <=>) compiler.check_explicit_converter(rhs, lhs.cadr(), 0);
  return compiler.resolve_expression(
    source_operator_expression(NULL, %($op $lhs $rhs)), origin);
}

/** Parses one right-associative assignment expression.
    A parenthesized identifier list on the left becomes a destructuring
    assignment only for `=`. `compiler.token` stops after the expression.
*/
List Compiler.parse_assignment(Compiler compiler) =>
  _parse_assignment_tail(compiler, compiler.parse_conditional());

/* A name adjacent to a C string literal is a preprocessor word: a macro this
   unit defines to a string literal, or a name it cannot resolve, as a
   header's `PRId64` is. `in` there is the membership operator. */
static int _string_word_follows(Compiler c) {
  if (c.peek(0) != <ident> || c.token.text == "in") return 0;
  Var definition;
  if (c.object_macros.try_get(c.token.text, definition))
    return definition.equal(<string>);
  return !c.sym.get(%(${c.token.text}));
}

/* Preserve each C token's escape boundary and the ordinary raw-string type.
   A macro defined to a string literal is one of the adjacent words, spelled
   as written, so the C preprocessor joins `printf("%" PRId64 "\n", x)`. */
static List _join_c_string_literals(Compiler c, List first) {
  if (c.peek(0) != <lit-char*> && !_string_word_follows(c)) return first;
  Array spellings = [];
  spellings.push(first.caddr().caddr());
  while (c.peek(0) == <lit-char*> || _string_word_follows(c)) {
    spellings.push(c.token.text);
    c.next();
  }
  String text = " ".join(spellings.list_free());
  return %(expr (* char) (literal (* char) $text));
}

static List _parse_c_string_literals(Compiler c) =>
  _join_c_string_literals(c, c.parse_atomic_literal());

static List _parse_ident_primary(Compiler compiler) {
  if (compiler.token.text == "macro" && compiler.peek(1) == <ident> &&
      compiler.peek(2) == <(>) {
    List definition = compiler.parse_macro_definition();
    foreach (Var captured, definition.assoc(<captures>).list())
      compiler.semantic_binding_facts()[
        %(local-macro-capture $captured)] = 1;
    return compiler.capture_macro_value(definition);
  }
  List binding = compiler.with_binding();
  Var stored;
  if (binding && compiler.semantic_binding_facts().try_get(
    %(with $binding), stored)) {
    List expression = stored;
    compiler.next();
    match (expression)
      case %(expr ?type ?): return %(expr $type (parens $expression));
  }
  List keyword = compiler.try_parse_macro_expression();
  if (keyword) return keyword;
  if (compiler.token.text == "va_arg") return _parse_va_arg(compiler);
  if (compiler.token.text == "_Generic") return _parse_generic(compiler);
  return compiler.parse_variable();
}

/** Parses one primary expression or expression-valued macro slot.
    Dispatch starts at `compiler.token` to the selected literal, identifier,
    grouping, or macro parser and leaves the token after that primary form.
*/
List Compiler.parse_primary(Compiler compiler) {
  compiler.require_input();
  compiler.__complete_here(<expr>, %());
  List slot = compiler.try_parse_macro_slot(<expression>);
  if (slot) return slot;
  switch (compiler.peek(0)) {
    case <"$(">: return compiler.parse_macro_lisp_expression();
    case <lit-char*>:  return _parse_c_string_literals(compiler);
    case <$>:          return compiler.try_parse_macro_expression();
    case <ident>:      return _parse_ident_primary(compiler);
    /* The keyword pass keeps `in` between tokens that can end and begin
       operands, as after a cast or a condition. An operand never begins
       with the operator, so here `in` is a name. */
    case <in>:        return compiler.parse_variable();
    case <"(">:       return _parse_parens(compiler);
    case <"{">:       return _parse_composite(compiler);
    case <[>:         return _parse_bracket_array(compiler);
    case <"%(">:      return compiler.parse_list_literal();
    case <"%<<">:     return compiler.parse_symbol_set_literal();
    case <"%[">:      return compiler.parse_array_literal();
    case <"%{">:      return compiler.parse_map_literal();
    case <"%\"">:     return compiler.parse_string_literal();
    case <"%!">:      return compiler.parse_lambda_literal();
  }
  return compiler.parse_atomic_literal();
}

static List _parse_expression_tail(Compiler compiler, List expr) {
  if (compiler.peek(0) == <,>) {
    expr = cons(expr, _parse_comma_list(compiler));
    List last = expr.last(), type = last.cadr();
    return %(expr $type ${source_commas_content(expr)});
  }
  return expr;
}

/** Parses an assignment expression and any following comma expressions.
    A comma expression retains source order and takes the type of its final
    value. `compiler.token` stops at the first token outside the expression.
*/
List Compiler.parse_expression(Compiler compiler) =>
  _parse_expression_tail(compiler, compiler.parse_assignment());

static List _finish_paren_statement(
  Compiler compiler, List expression, int postfix) {
  if (postfix) expression = _parse_postfix_tail(compiler, expression);
  expression = _parse_binary_levels_from(compiler, expression);
  expression = _parse_conditional_tail(compiler, expression);
  expression = _parse_assignment_tail(compiler, expression);
  expression = _parse_expression_tail(compiler, expression);
  compiler.expect(<;>);
  return %(stmnt $expression);
}

/** Parses a statement beginning with `(`.

    The ordinary parameter parser consumes the contents once: one anonymous
    parameter is a cast type, while named parameters are destructuring
    declarations. Everything following an ordinary parenthesized expression
    resumes at the postfix tail it had already reached. This entry consumes
    the terminating `;` and returns `(stmnt expression)` or an origin-anchored
    `(dstrdecl ...)`.
*/
List Compiler.parse_parenthesized_statement(Compiler c) {
  Token origin = c.token;
  c.expect(<(>);
  if (c.test_declaration()) {
    List parameters = c.parse_parameter_list();
    c.expect(<)>);
    match (parameters)
      case %((param ?type
                    (!set ?binding (bind () ?)))): {
        List declaration = %(decl $type (bindings $binding));
        List operand = _parse_cast(c);
        List expression = %(expr $type (cast $declaration $operand));
        return _finish_paren_statement(c, expression, 0);
      }
    c.expect(<=>);
    List source = c.parse_assignment();
    c.expect(<;>);
    return c.anchor_origin(
      %(dstrdecl (params @parameters) $source), origin);
  }

  List expression = c.parse_expression();
  c.expect(<)>);
  match (expression)
    case %(expr ?type ?):
      expression = %(expr $type (parens $expression));
  return _finish_paren_statement(c, expression, 1);
}

/* Answer whether an expression is certainly a zero integer literal,
   certainly a nonzero one, or neither.  Parentheses are unwrapped because
   they are the one wrapper that folds away without evaluation, and
   `out_text` receives the spelling when there is one.

   The tokenizer already accepted the spelling and Type.numeric_literal
   already turned its prefix and suffix into the node's own type, so what
   remains here is whether a digit is nonzero.  A float, a name, or an enum
   constant answers <unknown>; the null-pointer guard below stays silent
   when it cannot decide. */
static Symbol _integer_literal_kind(List expr, String &?out_text) {
  match (expr) {
    case %(expr ? ${$source_content_pattern($grouped, %(?inner))}):
      return _integer_literal_kind(inner, out_text);
    case %(expr ? ${$source_literal_content(%(?ltype ?text))}): {
      String spelling = text, Type type = ltype;
      if (!spelling || !type.is_integral()) return <unknown>;
      char *s = spelling;
      // A character constant is integral too, but it is not spelled in
      // digits, and '\0' is a null pointer constant.
      if (s[0] < '0' || s[0] > '9') return <unknown>;
      if (out_text) out_text = spelling;
      char radix = s[0] == '0' ? s[1] : 0;
      int i = radix == 'x' || radix == 'X' || radix == 'b' ||
              radix == 'B' || radix == 'o' || radix == 'O' ? 2 : 0;
      for (; s[i] && s[i] != 'u' && s[i] != 'U' &&
             s[i] != 'l' && s[i] != 'L'; i++)
        if (s[i] != '0') return <nonzero>;
      return <zero>;
    }
  }
  return <unknown>;
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

/* Report whether two types point at provably different things.  Every
   level of both chains is resolved through the typedef table first, so a
   spelling difference, Ast against List or Pool against struct Pool *, is
   not a difference here. */
static int _unrelated_pointers(Compiler compiler, Type source, Type target) {
  source = compiler.sym.resolve_key(source);
  target = compiler.sym.resolve_key(target);
  if (!source.is_pointer() || !target.is_pointer()) return 0;
  loop {
    source = compiler.sym.resolve_key(source.cdr());
    target = compiler.sym.resolve_key(target.cdr());
    if (source == target) return 0;
    if (!source.is_pointer() || !target.is_pointer())
      return _known_pointee(source) && _known_pointee(target);
  }
}

/* A proven nonzero operand yields its short spelling; unknown forms yield
   NULL. C11 6.3.2.3p3 requires an integer constant expression with value zero,
   not just the token 0. x2c does not fold constants, so this recognizes
   only syntactically decidable forms. A wrong guess would reject legal C. */
static String _not_null_pointer_constant(Compiler compiler, List expr) {
  match (expr) {
    case %(expr ? ${$source_content_pattern($grouped, %(?inner))}):
      return _not_null_pointer_constant(compiler, inner);
    // sizeof is an integer constant expression, but never a zero-valued
    // one: no type in C has size zero.
    case %(expr ? ${$source_content_pattern(
        $sizeof_grouped, %(?operand))}):
      return "sizeof";
    case %(expr ? ${$source_content_pattern(
        $sizeof_expression, %(?operand))}):
      return "sizeof";
    // Unary minus or plus over a nonzero literal is still nonzero.  The
    // pattern has a fixed length, so a binary use of the same operator,
    // which would need folding, does not match it.
    case %(expr ? ${$source_operator_content(%(?oper ?operand))}): {
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
    case %(expr ?type ${$source_identifier_content(
        %((binding ? ?name)))}): {
      Type vartype = compiler.sym.resolve_numeric_type(type);
      if (!vartype || vartype.is_enum() || !vartype.is_integral()) return NULL;
      return name;
    }
  }
  String spelling = NULL;
  if (_integer_literal_kind(expr, spelling) != <nonzero>) return NULL;
  return spelling;
}

// Build the T_str / T_<target> converter call for a type pair, or return
// NULL when no such converter is declared.  When name is given it receives
// the name that was looked for, which the caller reports on failure.
//
// Both sides of the comparison are spelled the way the collector recorded
// them, so this matches for a typedef name -- "Symbol" against
// Symbol_str's collected ("Symbol") parameter -- and never for a builtin,
// whose collected parameter is the symbol int rather than the string
// "int".  That asymmetry is why the speculative callers below have to ask
// this function rather than guess from the type.
/* The exact reader for a built-in Var payload is `Var.<target>`: it checks the
   tag and yields NULL for any other kind. `Var.pointer` checks nothing, so
   trying it first let a List-valued Var read as a String. Only a raw native
   pointer with no typed Var reader should still take that path. */
static List _var_exact_reader(Compiler compiler, List expr, Type target) {
  if (!target.match(%(?))) return NULL;
  String reader = %"Var_${target.car().str().lower()}", Type readertype = NULL;
  List binding = compiler.sym.resolve_global(%($reader), readertype);
  if (!binding || !readertype || readertype.car() is not <list>) return NULL;
  List function = readertype.car();
  (Var function_tag, List parameters) = function;
  if (function_tag != <func> || !parameters || parameters.cdr() ||
      !List.equal(parameters.car(), %("Var")) ||
      !readertype.cdr().equal(target))
    return NULL;
  List callee = %(expr $readertype (ident $binding));
  Macro called = $called;
  return compiler.rebuild_expression(target, called(callee, %($expr)));
}

/* A converter's result exists only for the operator that asked for it.
   Only a conversion from a number is known to be fresh; a converter from a
   handle type may return storage its source still owns. */
static List _converted_temporary(
  Compiler compiler, List call, Type owner, Type target) {
  if (compiler.sym.resolve_numeric_type(owner) &&
      compiler.resolve_protocol_member(target, "discard")) {
    Macro called = $called;
    match (call) case called(?callee, *arguments):
      match (callee) case %(expr ? ${$source_identifier_content(
          %((!set ?binding (*))))}):
        _note_fresh_callee(compiler, binding);
  }
  return call;
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
    ? %"$prefix${typename}_str"
    : %"$prefix${typename}_${targetedname.lower()}";
}

static List _converter_owned_call(
  Compiler compiler, List expr, Type owner, Type target, int &declared) {
  String typename = owner.car().str();
  String convfuncname = _converter_name(owner, target);
  Type cvrtrtype = NULL;
  List converter_binding = compiler.sym.resolve_global(
    %($convfuncname), cvrtrtype);
  declared = !!converter_binding || !!cvrtrtype;
  List callee = %(expr $cvrtrtype (ident $converter_binding));
  List argument = expr.cadr() == owner
    ? expr : %(expr $owner $expr);
  Macro called = $called;
  if (cvrtrtype && cvrtrtype.car() is <list>) {
    List function = cvrtrtype.car();
    (Var function_tag, List parameters) = function;
    Type result = cvrtrtype.cdr();
    if (function_tag == <func> &&
        parameters && !parameters.cdr() &&
        List.equal(parameters.car(), owner) &&
        result.equal(target)) {
      List call = compiler.rebuild_expression(
        target, called(callee, %($argument)));
      return _converted_temporary(compiler, call, owner, target);
    }
  }
  /* The relaxed form exists so a converter may spell its parameter as a
     typedef of the source type, which the exact comparison above rejects.
     It still takes exactly one argument: matching a longer parameter list
     emitted a call with the arguments missing. */
  if (cvrtrtype.match(%((func (($typename))) ?))) {
    List call = compiler.rebuild_expression(
      target, called(callee, %($argument)));
    return _converted_temporary(compiler, call, owner, target);
  }
  return NULL;
}

static List _converter_call(
  Compiler c, List expr, Type type, Type target) {
  if (!type.match(%(?)) || !target.match(%(?))) return NULL;
  List owners = type.is_bare_typedef_name()
              ? _typedef_names(c, type).list_free() : %($type);
  foreach (Type owner, owners) {
    if (owner == target) return NULL;
    int declared = 0;
    List converted = _converter_owned_call(
      c, expr, owner, target, declared);
    if (converted || declared) return converted;
  }
  return NULL;
}

/** The call to the converter `type` declares for `target`, applied to
    `expr`, or NULL when it declares none. */
List Compiler.converter_call(Compiler c, List expr, Type type, Type target) =>
  _converter_call(c, expr, type, target);

/* A built-in payload has an exact tag-checked reader, and a Var(T)
   participant declares its own reverse converter. Either takes the crossing
   ahead of the unchecked pointer payload. An alias with neither reads
   through its nearest ancestor that has one, so an alias of `String` checks
   the tag exactly as `String` does. */
static List _var_checked_reader(
  Compiler compiler, List expr, Type type, Type target) {
  List owners = target.is_bare_typedef_name()
              ? _typedef_names(compiler, target).list_free() : %($target);
  foreach (Type owner, owners) {
    List reader = _var_exact_reader(compiler, expr, owner);
    if (!reader) reader = _converter_call(compiler, expr, type, owner);
    if (reader)
      return owner == target ? reader : %(expr $target ${reader.caddr()});
  }
  return NULL;
}

/* Promote raw string expressions while caching only exact literal leaves.
   Parentheses and conditional arms retain their evaluation structure; a
   dynamic leaf still calls String_new each time it is selected. */
static List _raw_string_to_string(Compiler compiler, List expr) {
  match (expr) {
    case %(expr (!or (* char) ((dim *) char))
        ${$source_literal_content(
          %((!or (* char) ((dim *) char)) ?))}): {
      List value = %(expr ("String") (call "String_new" (args $expr)));
      return %(expr ("String") ${compiler.cache(%(string $value))});
    }
    case %(expr (!or (* char) ((dim *) char))
        ${$source_content_pattern($grouped, %(?inner))}): {
      List converted = _raw_string_to_string(compiler, inner);
      return %(expr ("String") (parens $converted));
    }
    case %(expr (!or (* char) ((dim *) char))
        ${$source_operator_content(
          %(? ?condition ?ontrue ?onfalse))}): {
      List converted_true = _raw_string_to_string(compiler, ontrue);
      List converted_false = _raw_string_to_string(compiler, onfalse);
      return %(expr ("String")
               (op ? $condition $converted_true $converted_false));
    }
  }

  return %(expr ("String") (call "String_new" (args $expr)));
}

/* initializer paths, rows, and native layout */

/* C positional initialization skips unnamed bit-fields, not anonymous
   aggregate subobjects. The ordered metadata retains both kinds. */
static List _next_initializer_field(List fields) {
  while (fields) {
    List row = fields.car();
    Type type = row.cadr();
    if (row.car().truth() || !type.is_bitfield()) break;
    fields = fields.cdr();
  }
  return fields;
}

/* Paths are stacks of (owner kind selector type following-fields) frames.
   The same subobject walk owns conversion and deferred native assignment. */
static Type _initializer_type(List path, Type root) {
  if (!path) return root;
  (Type owner, Symbol kind, Var selector, Type type, List rest) =
    path.car();
  return type;
}

static List _initializer_field(
  Type owner, List fields, List parent) {
  fields = _next_initializer_field(fields);
  if (!fields) return NULL;
  List row = fields.car();
  return cons(
    %($owner field ${row.car()} ${row.cadr()} ${fields.cdr()}), parent);
}

static List _initializer_first(
  Compiler c, Type type, List parent) {
  Type owner = c.sym.resolve_key(type);
  if (owner.is_array()) {
    List zero = %(expr (int) (literal (int) "0"));
    return cons(%($owner index $zero ${owner.cdr()} ()), parent);
  }
  if (owner.is_aggregate())
    return _initializer_field(owner, c.sym.field_order(owner).cdr(), parent);
  return NULL;
}

// Decode only a literal fact; native expressions are never evaluated here.
static int _initializer_integer(List expression, unsigned long long &value) {
  String text = NULL;
  match (expression) {
    case %(expr ? ${$source_literal_content(%(? ?spelling))}):
      text = spelling;
    case %(?(String spelling)): text = spelling;
  }
  if (!text || text[0] < '0' || text[0] > '9') return 0;
  char *end, *digits = text;
  int base = 0;
  if (text[0] == '0' && (text[1] == 'b' || text[1] == 'B')) base = 2;
  if (text[0] == '0' && (text[1] == 'o' || text[1] == 'O')) base = 8;
  if (base) digits += 2;
  unsigned long long decoded = strtoull(digits, &end, base);
  while (*end == 'u' || *end == 'U' || *end == 'l' || *end == 'L') end++;
  if (*end) return 0;
  value = decoded;
  return 1;
}

static Var _native_modifier(Compiler c, Var modifier, Var &reused) {
  reused = modifier;
  match (modifier)
    case %(dim ?dimension): {
      List bound = dimension;
      unsigned long long count;
      int captured = 0;
      match (bound)
        case %(expr ? ${$source_content_pattern(
          $sizeof_grouped, %(?argument))}):
          match (argument)
            case %(struct ?name (fields
              (declare (char) (bindings (bind ? ((dim ?))))))): {
              List prior = %(expr (unsigned long)
                (sizeof (parens (struct $name))));
              reused = %(dim $prior);
              captured = 1;
            }
      if (bound && !captured && !_initializer_integer(bound, count)) {
        String name = c.fresh_name("initializer_bound");
        Type bytes = %((dim $bound) char);
        List field = bytes.declaration_ast(%("bytes"));
        Type declared = %(struct $name (fields $field));
        List size = %(expr (unsigned long) (sizeof (parens $declared)));
        List prior = %(expr (unsigned long)
          (sizeof (parens (struct $name))));
        modifier = %(dim $size);
        reused = %(dim $prior);
      }
    }
  return modifier;
}

/** Returns native definition/reference types for a compound literal.
    Macro expansion stays in the original cast; named tags let later sizeof
    expressions reuse that exact layout without a new scope. */
List Compiler.initializer_native_types(Compiler c, Type type) {
  Type base = type.base_type(), definition = base, reference = base;
  match (base) {
    case %((!set ?kind (!or struct union)) (gensym ? ?) ?body): {
      String name = c.fresh_name("initializer_type");
      definition = %($kind $name $body);
      reference = %($kind $name);
    }
    case %((!set ?kind (!or struct union)) (!set ?body (fields *))): {
      String name = c.fresh_name("initializer_type");
      definition = %($kind $name $body);
      reference = %($kind $name);
    }
    case %((!set ?kind (!or struct union)) ?name (fields *)):
      reference = %($kind $name);
  }
  Array definitions = [], references = [];
  for (List rest = type; rest !== base; rest = rest.cdr()) {
    Var reused = NULL;
    Var modifier = _native_modifier(c, rest.car(), reused);
    definitions.push(modifier);
    references.push(reused);
  }
  definition = definitions.list_free().append(definition);
  reference = references.list_free().append(reference);
  return %($definition $reference);
}

/* An enum constant captures one native index expansion where the original
   designator occurred. Its ordinary cast shape survives normalization. */
static List _initializer_index(Compiler c, List index, List &reference) {
  match (index)
    case %(expr ? ${$source_cast_content(
        %((enum ((op = ?binding ?original)))
          (!set ?value (expr ? (ident ?binding)))))}): {
      reference = value;
      return index;
    }
  unsigned long long at;
  if (_initializer_integer(index, at)) {
    reference = index;
    return index;
  }
  Type type = index.cadr();
  List binding = c.sym.introduce(c.fresh_name("initializer_index"));
  c.sym.bind_identity(NULL, binding, type.declaration_ast(binding));
  Type native = %(enum ((op = $binding $index)));
  reference = %(expr $type (ident $binding));
  return %(expr $type (cast $native $reference));
}

/* Cursor offsets are literal facts even when their native starting index
   is not. Keep one base-plus-offset expression instead of nested
   increments. */
static void _initializer_position(
  List index, List &base, unsigned long long &offset) {
  base = NULL;
  if (_initializer_integer(index, offset)) return;
  match (index)
    case %(expr ? ${$source_operator_content(
        %(+ (expr ? ${$source_content_pattern(
          $grouped, %(?origin))}) ?amount))}):
      if (_initializer_integer(amount, offset)) {
        base = origin;
        return;
      }
  base = index;
  offset = 0;
}

static List _initializer_drop_bound(
  List condition, List bound, List base, unsigned long long minimum) {
  match (condition) {
    case %(expr ? ${$source_operator_content(
        %(&& (expr ? ${$source_content_pattern($grouped, %(?left))})
             (expr ? ${$source_content_pattern($grouped, %(?right))})))}):
      return _initializer_and(
        _initializer_drop_bound(left, bound, base, minimum),
        _initializer_drop_bound(right, bound, base, minimum));
    case %(expr ? ${$source_operator_content(
        %(< (expr ? ${$source_content_pattern($grouped, %(?index))})
            (expr ? ${$source_content_pattern($grouped, %(?length))})))}): {
      unsigned long long at;
      List origin;
      _initializer_position(index, origin, at);
      if (length === bound && origin === base && at <= minimum) return NULL;
    }
  }
  return condition;
}

static List _initializer_and(List first, List second) {
  if (!first) return second;
  if (!second) return first;
  match (second)
    case %(expr ? ${$source_operator_content(
        %(< (expr ? ${$source_content_pattern($grouped, %(?index))})
            (expr ? ${$source_content_pattern($grouped, %(?bound))})))}): {
      unsigned long long at;
      List base;
      _initializer_position(index, base, at);
      first = _initializer_drop_bound(first, bound, base, at);
    }
  return first ? %(expr (int) (op && (expr (int) (parens $first))
                                    (expr (int) (parens $second)))) : second;
}

/** Selects a native subobject without evaluating it when used by sizeof. */
List Compiler.initializer_slot(Compiler c, List target, List path) {
  foreach (List frame, path.reverse()) {
    (Type owner, Symbol kind, Var selector, Type selected, List rest) = frame;
    if (kind == <index>)
      target = %(expr $selected (index $target $selector));
    else if (selector.truth())
      target = %(expr $selected (op . $target ($selector)));
  }
  return target;
}

static List _index_inside(
  Compiler c, List target, List parent, Type type, List index) {
  List array = c.initializer_slot(target, parent);
  List element = %(expr $type (index $array
    (expr (int) (literal (int) "0"))));
  List length = %(expr (unsigned)
    (op / (expr (unsigned) (sizeof (parens $array)))
          (expr (unsigned) (sizeof (parens $element)))));
  return %(expr (int)
    (op < (expr (int) (parens $index))
          (expr (unsigned) (parens $length))));
}

static int _next_index(
  Compiler c, List target, List frame, List parent,
  List &condition, Array states) {
  (Type owner, Symbol kind, Var selector, Type type, List rest) = frame;
  List index = selector, dimension = owner.car().cadr();
  unsigned long long at, count;
  List base;
  _initializer_position(index, base, at);
  int known_index = !base;
  String next_index = %"${at + 1}ULL";
  List increment = %(expr (unsigned long long)
    (literal (unsigned long long) $next_index));
  index = base
    ? %(expr (unsigned long long)
        (op + (expr (unsigned long long) (parens $base)) $increment))
    : increment;
  List next = cons(%($owner index $index $type ()), parent);
  if (!dimension) { states.push(%($condition $next 1)); return 1; }
  if (known_index && _initializer_integer(dimension, count)) {
    if (at + 1 < count) { states.push(%($condition $next 1)); return 1; }
    return 0;
  }
  List inside = _index_inside(c, target, parent, type, index);
  states.push(%(${_initializer_and(condition, inside)} $next 1));
  condition = _initializer_and(
    condition, %(expr (int) (op ! (expr (int) (parens $inside)))));
  return 0;
}

static void _initializer_next(
  Compiler c, List target, List path, List condition, Array states) {
  while (path) {
    List frame = path.car(), parent = path.cdr();
    (Type owner, Symbol kind, Var selector, Type type, List rest) = frame;
    if (kind == <field>) {
      if (owner.car() != <union>) {
        List next = _initializer_field(owner, rest, parent);
        if (next) {
          states.push(%($condition $next 1));
          return;
        }
      }
    }
    else if (_next_index(c, target, frame, parent, condition, states)) return;
    path = parent;
  }
  // Excess entries are the native initializer's final fallback.
  states.push(%(() () 0));
}

static List _initializer_merge(Array states) {
  Map positions = {};
  Array merged = [];
  foreach (List state, states) {
    (List condition, List path, int available) = state;
    List key = %($path $available);
    Var stored;
    if (!positions.try_get(key, stored)) {
      positions[key] = merged.len();
      merged.push(state);
      continue;
    }
    int at = stored;
    List previous = merged[at], before = previous.car();
    if (!before || !condition) condition = NULL;
    else if (before !== condition)
      condition = %(expr (int)
        (op || (expr (int) (parens $before))
               (expr (int) (parens $condition))));
    merged[at] = %($condition $path $available);
  }
  states.free();
  return merged.list_free();
}

static List _initializer_named(
  Compiler c, Type type, Var name, List parent) {
  Type owner = c.sym.resolve_key(type);
  List fields = c.sym.field_order(owner).cdr();
  while (fields) {
    List row = fields.car();
    List path = _initializer_field(owner, fields, parent);
    if (row.car() == name) return path;
    Type member = row.cadr();
    if (!row.car().truth() && c.sym.resolve_key(member).is_aggregate()) {
      List nested = _initializer_named(c, member, name, path);
      if (nested) return nested;
    }
    fields = fields.cdr();
  }
  return NULL;
}

/** Returns the initializer path selecting one visible aggregate field.
    Anonymous aggregate members remain explicit path frames, so consumers
    observe the same member promotion as native initializer conversion. */
List Compiler.initializer_field_path(
  Compiler c, Type type, List field) =>
  _initializer_named(c, type, field.car(), NULL);

static List _initializer_designated(
  Compiler c, Type root, List node, List &value, List &normalized) {
  List path = NULL, selectors = NULL;
  Type type = root;
  loop {
    Type owner = c.sym.resolve_key(type);
    match (node) {
      case %(dotinit ?field ?inner): {
        selectors = cons(%(dotinit $field), selectors);
        List selected = _initializer_named(c, type, field.car(), path);
        type = c.sym.lookup_field(type, field);
        path = selected ? selected
          : cons(%($owner field ${field.car()} $type ()), path);
        node = inner;
        continue;
      }
      case %(indexinit ?index ?inner): {
        List reference = NULL;
        List captured = _initializer_index(c, index, reference);
        selectors = cons(%(indexinit $captured), selectors);
        type = owner.dereference();
        path = cons(%($owner index $reference $type ()), path);
        node = inner;
        continue;
      }
    }
    value = node;
    foreach (List selector, selectors) node = selector.append(%($node));
    normalized = node;
    return path;
  }
}

static int _initializer_string_array(Compiler c, Type type, List value) {
  if (!value.match(%(expr (* char) ${$source_literal_content(
      %((* char) ?))}))) return 0;
  Type array = c.sym.resolve_key(type);
  if (!array.is_array()) return 0;
  Type element = c.sym.resolve_key(array.cdr()).scalar();
  return element === %(char) || element === %(signed char) ||
         element === %(unsigned char);
}

static int _initializer_whole(Compiler c, Type type, List value) {
  if (value.match(%(expr ? (composite *)))) return 1;
  Type source = value.cadr(), resolved = c.sym.resolve_key(type);
  if (c.sym.resolve_key(source).equal(resolved)) return 1;
  if (c.sym.is_var_type(type)) return 1;
  if (_initializer_string_array(c, type, value)) return 1;
  return !resolved.is_array() && !resolved.is_aggregate();
}

/* Scalar positional runs have one ordinal, independent of the native array
   boundaries. Count the type tree once instead of retaining cursor histories.
   Children pair ordinary path frames with (type count children) layouts. */
static List _array_layout(
  Compiler c, Type type, Type owner, List target, List string,
  int &symbolic) {
  List dimension = owner.car().cadr();
  if (!dimension) return NULL;
  if (string && _initializer_string_array(c, type, string)) return NULL;
  unsigned long long size;
  if (!_initializer_integer(dimension, size)) symbolic = 1;
  List path = _initializer_first(c, type, NULL);
  List element = c.initializer_slot(target, path);
  List child = _initializer_layout(c, owner.cdr(), element, string, symbolic);
  if (!child) return NULL;
  List one = %(expr (unsigned long long)
    (literal (unsigned long long) "1ULL"));
  List bytes = %(expr (unsigned long long) (sizeof (parens $element)));
  List divisor = child.caddr() ? %(expr (unsigned long long)
    (op ? $bytes $bytes $one)) : bytes;
  List count = %(expr (unsigned long long)
    (op / (expr (unsigned long long) (sizeof (parens $target)))
          (expr (unsigned long long) (parens $divisor))));
  List units = child.cadr();
  if (units !== one)
    count = %(expr (unsigned long long)
      (op * (expr (unsigned long long) (parens $count))
            (expr (unsigned long long) (parens $units))));
  return %($type $count ((${path.car()} $child)));
}

static List _record_layout(
  Compiler c, Type type, Type owner, List target, List string,
  int &symbolic) {
  Array children = $auto([]);
  List count = NULL;
  List fields = c.sym.field_order(owner).cdr();
  while (fields) {
    List path = _initializer_field(owner, fields, NULL);
    if (!path) break;
    (Type parent, Symbol kind, Var name, Type member, List rest) = path.car();
    List slot = c.initializer_slot(target, path);
    List child = _initializer_layout(c, member, slot, string, symbolic);
    if (!child) return NULL;
    List units = child.cadr();
    count = count ? %(expr (unsigned long long)
      (op + (expr (unsigned long long) (parens $count))
            (expr (unsigned long long) (parens $units)))) : units;
    children.push(%(${path.car()} $child));
    fields = rest;
  }
  if (!count) return NULL;
  return %($type $count ${children.list()});
}

static List _initializer_layout(
  Compiler c, Type type, List target, List string, int &symbolic) {
  Type owner = c.sym.resolve_key(type);
  if (c.sym.is_var_type(type) ||
      (!owner.is_array() && !owner.is_aggregate())) {
    List one = %(expr (unsigned long long)
      (literal (unsigned long long) "1ULL"));
    return %($type $one ());
  }
  if (owner.is_array())
    return _array_layout(c, type, owner, target, string, symbolic);
  if (owner.car() == <union>) return NULL;
  return _record_layout(c, type, owner, target, string, symbolic);
}

static List _ordinal_index(
  List frame, List ordinal, List units, List one, List &position) {
  (Type owner, Symbol kind, Var selector, Type selected, List rest) = frame;
  List index = ordinal;
  position = %(expr (int) (literal (int) "0"));
  if (units !== one) {
    // Empty native subarrays leave these selectors well-formed.
    List divisor = %(expr (unsigned long long)
      (op ? $units $units $one));
    index = %(expr (unsigned long long)
      (op / (expr (unsigned long long) (parens $ordinal))
            (expr (unsigned long long) (parens $divisor))));
    position = %(expr (unsigned long long)
      (op % (expr (unsigned long long) (parens $ordinal))
            (expr (unsigned long long) (parens $divisor))));
  }
  return %($owner index $index $selected ());
}

static void _ordinal_field(
  List ordinal, List units, List one, List &start,
  List &position, List &active) {
  if (start) {
    position = %(expr (unsigned long long)
      (op - (expr (unsigned long long) (parens $ordinal))
            (expr (unsigned long long) (parens $start))));
    if (units !== one)
      active = _initializer_and(
        active,
        %(expr (int)
          (op >= (expr (unsigned long long) (parens $ordinal))
                 (expr (unsigned long long) (parens $start)))));
  }
  List test = units === one
    ? %(expr (int) (op == (expr (unsigned long long) (parens $position))
                         (expr (int) (literal (int) "0"))))
    : %(expr (int)
        (op < (expr (unsigned long long) (parens $position))
              (expr (unsigned long long) (parens $units))));
  active = _initializer_and(active, test);
  start = start ? %(expr (unsigned long long)
    (op + (expr (unsigned long long) (parens $start))
          (expr (unsigned long long) (parens $units)))) : units;
}

static void _initializer_ordinal(
  List layout, List ordinal, List path, List condition, List value,
  Array cases) {
  (Type type, List count, List children) = layout;
  if (!children) {
    cases.push(%($condition $path $type $value));
    return;
  }
  List start = NULL;
  List one = %(expr (unsigned long long)
    (literal (unsigned long long) "1ULL"));
  foreach (List entry, children) {
    (List frame, List child) = entry;
    Symbol kind = frame.cadr();
    List units = child.cadr(), position = ordinal, active = condition;
    if (kind == <index>)
      frame = _ordinal_index(frame, ordinal, units, one, position);
    else _ordinal_field(ordinal, units, one, start, position, active);
    _initializer_ordinal(
      child, position, cons(frame, path), active, value, cases);
  }
}

static int _scalar_inputs(Compiler c, List items, List &string) {
  foreach (List value, items) {
    match (value) {
      case %(expr ? (composite *)): return 0;
      case %(expr ? (initval *)): return 0;
      case %(expr ?type ?): {
        Type source = c.sym.resolve_key(type);
        if (!c.sym.is_var_type(type) &&
            (source.is_array() || source.is_aggregate())) return 0;
      }
      default: return 0;
    }
    if (value.match(%(expr (* char) ${$source_literal_content(
        %((* char) ?))}))) string = value;
  }
  return 1;
}

static List _initializer_scalar_rows(
  Compiler c, Type root, List items, List target) {
  int symbolic = 0;
  List string = NULL;
  if (!_scalar_inputs(c, items, string)) return NULL;
  List layout = _initializer_layout(c, root, target, string, symbolic);
  if (!layout || !symbolic) return NULL;
  int array = c.sym.resolve_key(root).is_array();
  Array rows = [];
  unsigned long long at = 0;
  foreach (List value, items) {
    String spelling = %"${at++}ULL";
    List ordinal = %(expr (unsigned long long)
      (literal (unsigned long long) $spelling));
    List count = layout.cadr();
    List condition = array ? %(expr (int)
      (op < $ordinal (expr (unsigned long long) (parens $count)))) : NULL;
    Array cases = [];
    _initializer_ordinal(layout, ordinal, NULL, condition, value, cases);
    cases.push(%(() () () $value));
    rows.push(%($value ${cases.list_free()}));
  }
  return rows.list_free();
}

static List _row_value(
  Compiler c, Type root, List &original, List &states) {
  List value = original;
  if (original.car() == <dotinit> || original.car() == <indexinit>) {
    List path = _initializer_designated(
      c, root, original, value, original);
    states = %((() $path 1));
  }
  return value;
}

static List _initializer_row(
  Compiler c, Type root, List original, List target,
  List &states, int first) {
  List value = _row_value(c, root, original, states);
  match (value)
    case %(expr ? (!set ?body (initval *))): {
      List header = NULL;
      List choices = Ast.initializer_cases(body, header);
      Array following = [];
      foreach (List choice, choices) {
        (List condition, List path, Type type, List input) = choice;
        _initializer_next(c, target, path, condition, following);
      }
      states = _initializer_merge(following);
      return %($original $choices);
    }
  Array cases = [], following = [];
  foreach (List state, states) {
    (List condition, List path, int available) = state;
    Type type = available ? _initializer_type(path, root) : NULL;
    if (first && _initializer_string_array(c, root, value)) {
      path = NULL;
      type = root;
    }
    while (type && !_initializer_whole(c, type, value)) {
      List next = _initializer_first(c, type, path);
      if (!next) break;
      path = next;
      type = _initializer_type(path, root);
    }
    cases.push(%($condition $path $type $value));
    _initializer_next(c, target, path, condition, following);
  }
  states = _initializer_merge(following);
  return %($original ${cases.list_free()});
}

/** Returns (original cases) rows; each case is
    (native-condition path destination value). Explicit braces start a nested
    walk. Scalar runs map their ordinal through the native dimensions; other
    inputs retain possible cursor continuations. A NULL condition is
    unconditional, and a NULL destination is excess. */
List Compiler.initializer_rows(
  Compiler c, Type root, List items, List target) {
  List scalar = _initializer_scalar_rows(c, root, items, target);
  if (scalar) return scalar;
  Array rows = [];
  List first_path = _initializer_first(c, root, NULL);
  Type resolved_root = c.sym.resolve_key(root);
  int available = !!first_path || resolved_root.scalar() ||
    resolved_root.is_pointer() || resolved_root.is_enum();
  List states = %((() $first_path $available));
  int first = 1;
  foreach (List original, items) {
    rows.push(_initializer_row(c, root, original, target, states, first));
    first = 0;
  }
  return rows.list_free();
}

static List _initializer_replace(List original, List value) {
  match (original)
    case %((!set ?tag (!or dotinit indexinit)) ?key ?inner):
      return %($tag $key ${_initializer_replace(inner, value)});
  return value;
}

static List _initializer_zero(Type type, List target) {
  Type native = type.is_bitfield() ? type.base_type()
    : target ? %("__typeof__" (parens $target)) : type;
  return %(expr $type (cast $native (expr $type
    (composite (commas (expr (int) (literal (int) "0")))))));
}

static List _accepted_initializer(
  List result, Type type, List target, List condition, List zero) {
  if (result.match(%(expr ? (composite *)))) {
    Type native = target ? %("__typeof__" (parens $target)) : type;
    return %(expr $type (cast $native $result));
  }
  return %(expr $type
    (call "__builtin_choose_expr" (args $condition $result $zero)));
}

static List _rejected_initializer(
  Type type, List condition, List zero) {
  List size = %(expr (int) (op ? $condition
    (expr (int) (literal (int) "-1"))
    (expr (int) (literal (int) "1"))));
  List check = %(expr (unsigned)
    (sizeof ("(" "char[" $size "]" ")")));
  Symbol comma = <,>;
  check = %(expr (void) (cast (void) $check));
  return %(expr $type (parens (expr $type (op $comma $check $zero))));
}

/* The transaction owns binding and name rollback while conversion may also
   append literal and adapter data. */
static List _speculative_initializer_conversion(
  Compiler c, List value, Type type, List condition, List target,
  int &?native_used, int &rejected) {
  SymTxn transaction = c.begin_semantic_transaction();
  Map keys = c.key_ids, adapters = c.names.adapters;
  int key_count = c.id_keys.len(), declarations = c.early_decls.len();
  c.key_ids = keys.copy();
  c.names.adapters = adapters.copy();
  DiagnosticsHold hold = c.diagnostics.hold();
  int depth = c.recovery_depth, completed = 0;
  List result = NULL;
  {
    defer {
      c.recovery_depth = depth;
      c.diagnostics.release(hold, !rejected);
      if (!completed) {
        c.key_ids = keys;
        c.names.adapters = adapters;
        c.id_keys.resize(key_count);
        c.early_decls.resize(declarations);
      }
      transaction.rollback();
    }
    c.recovery_depth = depth + 1;
    try {
      result = value.match(%(expr ? (composite ?)))
        ? _convert_composite(
          c, value, type.canonicalize(), target, condition, native_used)
        : c.convert_expression(value, type);
      transaction.commit();
      completed = 1;
    }
    catch %(malformed (category type)): rejected = 1;
  }
  return result;
}

/* Only native-dependent alternatives speculate. */
static List _initializer_conversion(
  Compiler c, List value, Type type, List condition, List target,
  int &?native_used) {
  if (!condition)
    return _convert_initializer(c, value, type, target, native_used);
  if (native_used) native_used = 1;
  match (value)
    case %(expr ?stored (call "__builtin_choose_expr"
                             (args ?when ?yes ?no))):
      if (stored === type && when === condition) return value;
  int rejected = 0;
  List result = _speculative_initializer_conversion(
    c, value, type, condition, target, native_used, rejected);
  List zero = _initializer_zero(type, target);
  return rejected ? _rejected_initializer(type, condition, zero)
    : _accepted_initializer(result, type, target, condition, zero);
}

// Keep literal construction/cache facts while capturing native value leaves.
static int _initializer_literal(List value) {
  match (value) {
    case %(expr ? ${$source_literal_content(%(*))}): return 1;
    case %(expr ? ${$source_content_pattern($grouped, %(?inner))}):
      return _initializer_literal(inner);
    case %(expr ? ${$source_cast_content(%(? ?inner))}):
      return _initializer_literal(inner);
  }
  return 0;
}

static List _capture_initializer_value(
  Compiler c, List value, Type type, Array inputs) {
  if (!c.sym.is_var_type(type) && !c.sym.resolve_key(type).scalar())
    return value;
  if (_initializer_literal(value)) return value;
  String formal = c.fresh_name("initializer_value");
  inputs.push(%($formal $value));
  return %(expr $type $formal);
}

static List _initializer_capture_leaves(
  Compiler c, List value, Array inputs) {
  match (value) {
    case %((!set ?kind (!or dotinit indexinit)) ?key ?inner):
      return %($kind $key ${_initializer_capture_leaves(c, inner, inputs)});
    case %(expr ?type ${$source_composite_content(%(*items))}): {
      Array captured = [];
      foreach (List item, items)
        captured.push(_initializer_capture_leaves(c, item, inputs));
      return %(expr $type ${source_composite_content(
        captured.list_free())});
    }
    case %(expr ?type ${$source_identifier_content(%(*))}):
      return _capture_initializer_value(c, value, type, inputs);
    case %(expr ?type ${$source_call_content($called, %(expr ? ?), %(*))}):
      return _capture_initializer_value(c, value, type, inputs);
    case %(expr ?type ${$source_operator_content(%(*))}):
      return _capture_initializer_value(c, value, type, inputs);
    case %(expr ?type ${$source_cast_content(%(*))}):
      return _capture_initializer_value(c, value, type, inputs);
    case %(expr ?type ${$source_content_pattern($grouped, %(?))}):
      return _capture_initializer_value(c, value, type, inputs);
    /* Internally constructed native calls may have a bare string callee. */
    case %(expr ?type (call *)):
      return _capture_initializer_value(c, value, type, inputs);
  }
  return value;
}

// Inline native type definitions cannot be copied into conversion arms.
// A selected by-value adapter consumes the original expression just once.
static Type _initializer_value_type(Compiler c, Type type) {
  if (c.sym.is_var_type(type)) return %("Var");
  Type scalar = c.sym.resolve_key(type).scalar();
  return scalar === %(void) ? NULL : scalar;
}

static List _initializer_adapter(
  Compiler c, List source, List converted) {
  Type from = _initializer_value_type(c, source.cadr());
  Type result = _initializer_value_type(c, converted.cadr());
  List formal = %(expr ${source.cadr()} "_x2c_initializer_argument");
  List body = converted.search_replace(%(!quote $source), formal);
  List key = %(iadapt $from $result $body);
  Var stored;
  if (c.names.adapters.try_get(key, stored)) return stored;
  List parameter = c.sym.introduce(c.fresh_name("initializer_arg"));
  List input = %(expr ${source.cadr()} (ident $parameter));
  body = body.search_replace(%(!quote $formal), input);
  List binding = c.sym.introduce(c.fresh_name("initializer_adapt"));
  List params = %(params ${from.parameter_ast(parameter)});
  List function = %(function (static $result)
    (bind $binding ((fnmod $params)))
    (block (stmnt (return $body))));
  Type callable = %((func ($from)) @result);
  List adapter = %(expr $callable (ident $binding));
  c.names.adapters[key] = adapter;
  c.add_early(function);
  return adapter;
}

static List _initializer_adapters(
  Compiler c, List source, List choices, List placeholder) {
  Type from = _initializer_value_type(c, source.cadr());
  if (!from || !ast_contains_head(source, <fields>)) return NULL;
  Array prepared = $auto([]);
  foreach (List choice, choices) {
    (List condition, List path, Type destination, List value) = choice;
    if (destination && !_initializer_value_type(c, destination)) return NULL;
    if (value !== source) {
      match (value) {
        case %(expr ? (call "__builtin_choose_expr" (args ? ?yes ?))):
          value = yes;
        default: return NULL;
      }
    }
    if (!_initializer_value_type(c, value.cadr())) return NULL;
    prepared.push(%($condition $path $destination $value));
  }
  Array adapted = [];
  foreach (List choice, prepared.list()) {
    (List condition, List path, Type destination, List value) = choice;
    List adapter = _initializer_adapter(c, source, value);
    Type callable = adapter.cadr(), result = callable.apply();
    Macro called = $called;
    value = c.rebuild_expression(
      result, called(adapter, %($placeholder)));
    adapted.push(%($condition $path $destination $value));
  }
  return adapted.list_free();
}

/* An empty initializer for a Map or Array, or for a type that converts from
   one, is a fresh empty collection. A Var holds a fresh empty Map. */
static List _empty_collection(Compiler c, Type target) {
  for (int kind = 0; kind < 2; kind++) {
    Macro shape = kind ? $array_value : $map_value;
    Type source = kind ? %("Array") : %("Map");
    List literal = c.rebuild_expression(source, shape(%()));
    if (!kind && c.sym.is_var_type(target))
      return c.convert_expression(literal, target);
    if (c.sym.resolve_key(target).equal(c.sym.resolve_key(source)))
      return c.convert_expression(literal, target);
    List converted = _converter_call(c, literal, source, target);
    if (converted) return converted;
  }
  return NULL;
}

static List _composite_rows(
  Compiler compiler, Type target, List items, List native_target,
  List parent_condition, int &discarded) {
  Array rows = [];
  int initialized = 0;
  foreach (List row, compiler.initializer_rows(target, items, native_target)) {
    List cases = row.cadr();
    int available = 0;
    foreach (List choice, cases)
      if (choice.caddr().truth()) { available = 1; break; }
    if (parent_condition && initialized && !available) {
      discarded = 1;
      continue;
    }
    if (available) initialized = 1;
    rows.push(row);
  }
  return rows.list_free();
}

/* Keep C's excess warning on one retained value of this alternative. */
static List _composite_excess_check(List parent_condition) {
  List zero = %(expr (int) (literal (int) "0"));
  List one = %(expr (int) (literal (int) "1"));
  List size = %(expr (int) (op ? $parent_condition $zero $one));
  Type array = %((dim $size) char);
  List probe = %(expr $array (cast $array
    (expr $array (composite (commas $zero)))));
  List count = %(expr (unsigned) (sizeof (parens $probe)));
  return %(expr (int) (op + $one (expr (int) (op * $zero $count))));
}

static List _materialize_mixed_row(
  Compiler compiler, List original, List source,
  Array converted, Array captured) {
  String formal = compiler.fresh_name("initializer_value");
  List placeholder = %(expr ${source.cadr()} $formal);
  List values = converted.list_free();
  List adapted = _initializer_adapters(
    compiler, source, values, placeholder);
  if (adapted) values = adapted;
  Array replaced = [];
  List inputs = captured.list_free();
  int uses_input = !!adapted;
  foreach (List choice, values) {
    (List condition, List path, Type destination, List result) = choice;
    List substituted =
      !destination && source.match(%(expr ? (composite *)))
        ? result : result.search_replace(%(!quote $source), placeholder);
    if (substituted !== result) uses_input = 1;
    replaced.push(%($condition $path $destination $substituted));
  }
  List choices = replaced.list_free();
  if (uses_input) inputs = cons(%($formal $source), inputs);
  if (inputs) choices = cons(%(input @inputs), choices);
  List result = %(expr () (initval @choices));
  return _initializer_replace(original, result);
}

static List _mixed_initializer_row(
  Compiler compiler, List row, List source, List native_target,
  List row_condition, List parent_condition, int &?native_used) {
  (List original, List cases) = row;
  Array converted = [], captured = [];
  List prepared = source;
  if (source.match(%(expr ? (composite *))))
    prepared = _initializer_capture_leaves(compiler, source, captured);
  int native_identity = !parent_condition;
  foreach (List choice, cases) {
    (List condition, List path, Type destination, List input) = choice;
    input = prepared;
    List slot = native_target
      ? compiler.initializer_slot(native_target, path) : NULL;
    List effective = _initializer_and(row_condition, condition);
    List result = destination
      ? _initializer_conversion(
        compiler, input, destination, effective, slot, native_used)
      : input;
    int identity = result === input;
    match (result)
      case %(expr ? (call "__builtin_choose_expr" (args ? ?yes ?))):
        if (yes === input) identity = 1;
    if (!identity) native_identity = 0;
    converted.push(%($condition $path $destination $result));
  }
  if (native_identity) {
    converted.free();
    captured.free();
    return original;
  }
  return _materialize_mixed_row(
    compiler, original, source, converted, captured);
}

typedef struct RowSelection {
  Type type;
  List value, path, applicable;
  int homogeneous, excess;
} RowSelection;

static RowSelection _select_row(List cases) {
  RowSelection selected = { .homogeneous = 1 };
  int applicable_seen = 0;
  foreach (List choice, cases) {
    (List condition, List path, Type destination, List input) = choice;
    selected.value = input;
    if (!destination) { selected.excess = 1; continue; }
    if (!applicable_seen) {
      selected.applicable = condition;
      applicable_seen = 1;
    }
    else if (!selected.applicable || !condition) selected.applicable = NULL;
    else if (selected.applicable !== condition)
      selected.applicable = %(expr (int)
        (op || (expr (int) (parens ${selected.applicable}))
               (expr (int) (parens $condition))));
    if (!selected.type) { selected.type = destination; selected.path = path; }
    else if (destination !== selected.type) selected.homogeneous = 0;
  }
  return selected;
}

static List _convert_initval_row(
  Compiler compiler, List row, List terminal, List native_target,
  List row_condition, int &?native_used) {
  (List original, List cases) = row;
  Array checked = [];
  foreach (List choice, cases) {
    (List condition, List path, Type destination, List input) = choice;
    List slot = compiler.initializer_slot(native_target, path);
    List effective = _initializer_and(row_condition, condition);
    List value = !destination ? input
      : _initializer_conversion(
        compiler, input, destination, effective, slot, native_used);
    checked.push(%($condition $path $destination $value));
  }
  List header = NULL;
  Ast.initializer_cases(terminal.caddr(), header);
  List choices = checked.list_free();
  if (header) choices = cons(header, choices);
  List value = %(expr () (initval @choices));
  return _initializer_replace(original, value);
}

static List _convert_homogeneous_row(
  Compiler compiler, List original, RowSelection selected,
  List native_target, List row_condition, int &?native_used) {
  List slot = native_target
    ? compiler.initializer_slot(native_target, selected.path) : NULL;
  List condition = _initializer_and(
    row_condition, selected.excess ? selected.applicable : NULL);
  List converted = !selected.type ? selected.value
    : _initializer_conversion(
      compiler, selected.value, selected.type, condition, slot, native_used);
  return _initializer_replace(original, converted);
}

static List _convert_composite_row(
  Compiler compiler, List row, List native_target, List row_condition,
  List parent_condition, int &?native_used) {
  (List original, List cases) = row;
  RowSelection selected = _select_row(cases);
  List terminal = original;
  while (terminal.car() == <dotinit> || terminal.car() == <indexinit>)
    terminal = terminal.caddr();
  if (terminal.match(%(expr ? (initval *))))
    return row_condition === parent_condition ? original
      : _convert_initval_row(
        compiler, row, terminal, native_target, row_condition, native_used);
  if (selected.homogeneous)
    return _convert_homogeneous_row(
      compiler, original, selected, native_target, row_condition,
      native_used);
  return _mixed_initializer_row(
    compiler, row, selected.value, native_target, row_condition,
    parent_condition, native_used);
}

/* An unevaluated `*(native *) 0` typed as `viewed`, from which initializer
   rows name their slots. */
static List _zero_pointer_target(Type viewed, Type native) {
  Type pointer = cons(<*>, native);
  List zero = %(expr (int) (literal (int) "0"));
  return %(expr $viewed (parens (expr $viewed
    (op * (expr $pointer (parens (expr $pointer (cast $pointer $zero))))))));
}

static List _convert_composite(
  Compiler compiler, List expr, Type target, List native_target,
  List parent_condition, int &?native_used) {
  if (!expr.caddr().cadr().cdr()) {
    List fresh = _empty_collection(compiler, target);
    if (fresh) return fresh;
  }
  if (!native_target) native_target = _zero_pointer_target(target, target);
  Array elements = [];
  List items = expr.caddr().cadr().cdr();
  int discarded = 0;
  List rows = _composite_rows(
    compiler, target, items, native_target, parent_condition, discarded);
  // Preserve C's excess warning only when this synthetic alternative applies.
  // The always-true ICE stays on a retained value, so braces remain braces.
  List excess_check = discarded
    ? _composite_excess_check(parent_condition) : NULL;
  foreach (List row, rows) {
    List row_condition = parent_condition;
    if (excess_check) {
      row_condition = _initializer_and(parent_condition, excess_check);
      excess_check = NULL;
    }
    List converted = _convert_composite_row(
      compiler, row, native_target, row_condition,
      parent_condition, native_used);
    elements.push(converted);
  }
  return %(expr $target (composite (commas @{elements.list_free()})));
}

static List _convert_initializer(
  Compiler c, List value, Type type, List target, int &?native_used) {
  if (value.match(%(expr ? (composite ?))))
    return _convert_composite(
      c, value, type.canonicalize(), target, NULL, native_used);
  return c.convert_expression(value, type.declared());
}

/** Converts an initializer using its declared native object for array
    bounds. */
List Compiler.convert_initializer(
  Compiler c, List value, Type type, List target) =>
  _convert_initializer(c, value, type, target, NULL);

/** Keeps a compound literal's native type definition at its original scope. */
List Compiler.convert_compound_literal(
  Compiler c, List value, Type type, Type native_type) {
  (Type definition, Type reference) = c.initializer_native_types(native_type);
  List target = _zero_pointer_target(type, reference);
  int native_used = 0;
  List converted = _convert_initializer(c, value, type, target, native_used);
  if (!native_used) definition = native_type;
  return %(cast $definition $converted);
}

/* destination conversion */

/* A conditional whose arms are a `Var` and another value is a `Var`: the
   other arm boxes, so C sees one operand type. Other mixed arms keep their
   C types until a target converts each arm. */
static int _conditional_joins(Compiler c, Type type, Type other) =>
  type && other && c.sym.is_var_type(type) && !c.sym.is_var_type(other);

/* A brace that stays a native initializer outside a declaration becomes a
   compound literal of the destination, because C accepts a bare brace only
   as an initializer. An anonymous struct or union has no spelling for that
   literal. */
static List _compound_literal(Compiler c, List composite, Type target) {
  List converted = _convert_composite(c, composite, target, NULL, NULL, NULL);
  match (converted)
    case %(expr ?type (composite *)): {
      if (Type.tag(type).match(%((gensym *))))
        c.report_error(
          <type>,
          "a brace outside an initializer needs a named destination type",
          NULL, %("declare the destination with a struct tag or typedef"));
      return %(expr $type (cast $type $converted));
    }
  return converted;
}

/* Only one conditional arm runs; convert each arm when C cannot convert
   the result as a whole. */
static List _convert_conditional_arms(
  Compiler c, List expr, Type declared_target) {
  match (expr) case %(expr ? ${$source_operator_content(
      %(?operator ?condition ?ontrue ?onfalse))}): {
    Type true_type = ontrue.cadr(), false_type = onfalse.cadr();
    if (ontrue.list().match(%(expr ? (composite *))) ||
        onfalse.list().match(%(expr ? (composite *))) ||
        (!true_type.equal(false_type) &&
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
  match (expr) case %(expr () ${$source_generic_content(
      %(?control *associations))}): {
    Array converted = [];
    int changed = 0;
    foreach (List association, associations) match (association)
      case %(association ?selector ?value): {
        List result = c.convert_expression(value, declared_target);
        if (result != value) changed = 1;
        converted.push(%(association $selector $result));
      }
    if (changed)
      return %(expr $declared_target ${source_generic_content(
        %($control @{converted.list_free()}))});
    converted.free();
  }
  return NULL;
}

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
      String tagsym = %"${(unsigned long) tag}";
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
    c.report_error(
      <type>, %"cannot convert Var to ${target.repr()}", NULL,
      %("write &value for its address, or value.pointer() to unbox a stored pointer"));
  if (target.is_pointer())
    return %(expr $target (call "Var_pointer" (args $expr)));
  if (target.is_typedef_name()) {
    // Unknown system typedefs have no proven pointer payload reader.
    Type resolved = c.sym.resolve_key(target);
    if (resolved.is_pointer())
      return %(expr $target (call "Var_pointer" (args $expr)));
    String message = %"cannot convert Var to type ${target.repr()}";
    c.report_error(<type>, message, NULL, NULL);
  }
  return NULL;
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
  String message = %"cannot convert ${type.repr()} to Var without loss";
  c.report_error(<type>, message, NULL, NULL);
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
    String tagsymnumstr = %"${(unsigned long) tag}";
    return %(expr ("Var") (call "Var_new" (args
                (expr ("Symbol") $tagsymnumstr) $expr)));
  }
  String message = %"cannot convert ${type.repr()} to Var without loss";
  // Conversion runs after parsing; a NULL token anchors the statement.
  c.report_error(<type>, message, NULL, NULL);
}

/* Same-address conversions must keep qualifiers, including void pointers. */
static void _check_qualifiers(
  Compiler c, Type type, Type target, Type source, Type destination) {
  int take_reference =
    (target.car() == <&> || target.car() == <opt-ref>) &&
    type === cdr(target);
  Type qualified = take_reference ? source.reference() : source;
  if ((take_reference || type == target || cdr(type) == cdr(target) ||
       (type.is_pointer() && target.is_pointer() &&
        (destination.base_type() === %(void) ||
         source.base_type() === %(void)))) &&
      qualified.discards_qualifiers(destination)) {
    String message =
      %"cannot convert ${source.repr()} to ${destination.repr()}";
    c.report_error(
      <type>, message, NULL,
      %("the target drops a type qualifier the source declares: spell the qualifier in the target, or copy the value"));
  }
}

static List _convert_reference(
  Compiler c, List expr, Type type, Type target) {
  // T -> &T: pass the address of an addressable value.
  if (type === cdr(target) &&
      (target.car() == <&> || target.car() == <opt-ref>)) {
    if (!_expression_is_addressable(c, expr))
      c.report_error(
        <type>, "reference argument must name an addressable object",
        NULL, NULL);
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

/* C accepts null pointer constants, pointer decay, and opaque system types.
   Reject only a proven nonzero integer, unrelated known pointers, or two
   typedef names that share a C representation without a declared crossing. */
static void _check_native_crossing(
  Compiler c, List expr, Type type, Type target,
  Type declared_source, Type declared_target) {
  String integer = _not_null_pointer_constant(c, expr);
  if (integer && c.sym.resolve_key(target).is_pointer()) {
    String message =
      %"cannot convert the integer $integer to pointer type ${target.repr()}";
    List hint =
      %( "only a zero integer constant expression converts to a pointer" );
    c.report_error(<type>, message, NULL, hint);
  }
  if (_unrelated_pointers(c, type, target)) {
    String message =
      %"cannot convert ${declared_source.repr()} to ${declared_target.repr()}";
    c.report_error(
      <type>, message, NULL,
      %("the pointer types are unrelated: cast the expression to say so on purpose"));
  }
  if (declared_source.is_bare_typedef_name() &&
      declared_target.is_bare_typedef_name() &&
      !declared_source.equal(declared_target) &&
      c.sym.resolve_key(declared_target).is_pointer() &&
      c.sym.resolve_key(declared_source).base_type() !== %(void) &&
      !_typedef_names(c, declared_source).contains(declared_target) &&
      !_typedef_names(c, declared_target).contains(declared_source)) {
    String message =
      %"cannot convert ${declared_source.repr()} to ${declared_target.repr()}";
    c.report_error(
      <type>, message, NULL,
      %("the names share one C type but not one meaning: declare the converter ${declared_source.car()}_${declared_target.car().str().lower()}, or cast the expression to say so on purpose"));
  }
}

static List _convert_untyped(
  Compiler c, List expr, Type declared_target, int target_is_var) {
  List generic = _convert_generic_arms(c, expr, declared_target);
  if (generic) return generic;
  if (target_is_var && expr.match(%(expr () ${$source_identifier_content(
      %((binding ? ?)))}))) {
    List binding = expr.caddr().cadr();
    if (binding_identity_spelling(binding) == "NULL")
      return %(expr ("Var") (call "Var_null" (args)));
    String message = "cannot convert an unresolved expression to Var";
    c.report_error(
      <type>, message, NULL,
      %("give the expression a declared x2c type before boxing it"));
  }
  return expr;
}

static void _check_reference_value(
  Compiler c, Type type, Type target) {
  /* An optional reference forwards only to another address type. */
  if (type.car() == <opt-ref> && target.car() != <&> &&
      target.car() != <opt-ref> && !c.sym.resolve_key(target).is_pointer())
    c.report_error(
      <type>, "check optional reference before using its value", NULL, NULL);
  /* A reference takes an lvalue of its referenced type. */
  if ((target.car() == <&> || target.car() == <opt-ref>) &&
      type.car() != <&> && type.car() != <opt-ref> &&
      type !== cdr(target))
    c.report_error(
      <type>, %"cannot pass ${type.repr()} where ${target.repr()} is expected",
      NULL, %("pass an lvalue of the referenced type; write *p for a pointer"));
}

static void _check_object_pointer(
  Compiler c, Type type, Type target, int type_is_var) {
  if (target.car() != <*> || type_is_var) return;
  Type source = c.sym.resolve_key(type);
  if (source && !source.is_pointer() && !source.is_array() &&
      !source.is_function())
    c.report_error(
      <type>, %"cannot pass ${type.repr()} where ${target.repr()} is expected",
      NULL, %("write &value to pass its address"));
}

static List _convert_known_value(
  Compiler c, List expr, Type type, Type target,
  int type_is_var, int target_is_var) {
  List reference = _convert_reference(c, expr, type, target);
  if (reference) return reference;
  if (type.match(%((!or (dim *) (!quote *)) char))) {
    List string = _raw_string_to_string(c, expr);
    if (c.sym.is_string_type(target))
      return %(expr $target ${string.caddr()});
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
  List converted = _converter_call(c, expr, type, target);
  if (converted) return converted;
  if (!type_is_var && target_is_var) return _box_var(c, expr, type);
  return NULL;
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
  if (c.sym.resolve_key(target).equal(func_type)) {
    List lifted = c.lift_func_expression(expr);
    if (lifted != expr) return lifted;
  }
  if (type && c.sym.resolve_key(type).equal(func_type) &&
      target.is_pointer() && target.dereference().is_function()) {
    String message = "cannot convert Func to a context-free callback";
    List hint = %(
      "call Func directly, or use a noncapturing lambda as the C callback"
    );
    c.report_error(<type>, message, NULL, hint);
  }
  return NULL;
}

static void _check_null_reference(
  Compiler c, List expr, Type target) {
  if (target.car() != <&>) return;
  if (_integer_literal_kind(expr, NULL) == <zero> ||
      (expr.match(%(expr () ${$source_identifier_content(
        %((binding ? ?)))})) &&
       binding_identity_spelling(expr.caddr().cadr()) == "NULL"))
    c.report_error(
      <type>, %"cannot pass a null pointer where ${target.repr()} is expected",
      NULL, %("a reference argument must name an object"));
}

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
List Compiler.convert_segment_to_string(Compiler compiler, List expr) {
  Type type = expr.cadr().type().canonicalize();
  if (compiler.sym.is_var_type(type))
    return %(expr ("String") (call "Var_str" (args $expr)));
  if (!compiler.sym.resolve_numeric_type(type))
    return compiler.convert_expression(expr, %("String"));
  List converted = _converter_call(compiler, expr, type, %("String"));
  if (converted) return converted;
  List boxed = compiler.convert_expression(expr, %("Var"));
  return %(expr ("String") (call "Var_str" (args $boxed)));
}
