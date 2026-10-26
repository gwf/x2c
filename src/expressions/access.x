/*  access.x -- indexing and member lookup */

static keyword loop $private.loop;

module int _is_addressable(Compiler c, List expression) {
  match (expression) {
    case %(expr ? $($source_identifier_content(%(?binding)))): {
      Map facts = c.semantic_binding_facts();
      Type declared = facts[%(type $binding)];
      return !(%(lambda-snapshot $binding) in facts) &&
             !(declared ~= %(* register *));
    }
    case %(expr ? $($indexed(?receiver, ?selector))):
      return !c.sym.normalize_declared_type(receiver.cadr()).is_array() ||
             _is_addressable(c, receiver);
    case %(expr ? $($source_operator_content(
        %((!quote *) ?operand)))): return 1;
    case %(expr ? $($source_operator_content(
        %((!quote ->) ?receiver ?field)))): return 1;
    case %(expr ? $($grouped(?base))):
      return _is_addressable(c, base);
    case %(expr ? $($source_operator_content(%(. ?base ?)))):
      return _is_addressable(c, base);
  }
  return 0;
}

/* Dynamic update helpers take a writable native address rather than leaving
   those requirements for the C assignment operator to check. */
module void _check_dynamic_target(Compiler c, List target, Token origin) {
  match (target) {
    case %(expr ? (getindex ? ?)): return;
    case %(expr ? $($grouped(?inner))):
      return _check_dynamic_target(c, inner, origin);
  }
  Type type = c.sym.normalize_declared_type(target.cadr());
  foreach (Var part in type) {
    if (part is not <symbol> || !part.symbol().is_type_qualifier()) break;
    if (part == <const>)
      $fail.expressions_dynamic_const(c, origin);
  }
  if (!_is_addressable(c, target))
    $fail.expressions_dynamic_address(c, origin);
}

// indexing and slices

module List _resolve_indexed(
  Compiler c, List receiver, List selector, Token origin) {
  receiver = c.resolve_expression(receiver, origin);
  selector = c.resolve_expression(selector, origin);
  if (receiver.cadr().car() == <opt-ref>)
    $fail.expressions_optional_ref_index(c, origin);
  if (_deferred_receiver(receiver) || _deferred_receiver(selector))
    return %(expr (<macro-expr>) (index $receiver $selector));
  List resolved = _postfix_index_expression(c, receiver, selector);
  if (resolved) return resolved;
  Type receiver_type = receiver.cadr();
  // A field of a foreign struct has no x2c type; C indexes it alone.
  if (!receiver_type &&
      receiver ~= %(expr () $($source_operator_content(%((!or . ->) * *)))))
    return %(expr () (index $receiver $selector));
  $fail.expressions_index_unsupported(c, origin, receiver_type);
}

static List _postfix_index_expression(Compiler c, List expr, List index) {
  Type type = expr.cadr(), element = type.dereference();
  if (element) return %(expr $element (index $expr $index));
  type = type.canonicalize();
  if (!type.is_typedef_name()) return NULL;
  return _typedef_index(c, expr, index, type);
}

static List _typedef_index(Compiler c, List expr, List index, Type type) {
  int collection = _collection_index_type(c, type);
  List resolved = _x2c_nominal_getindex(c, type);
  if (!resolved && collection)
    resolved = c.resolve_protocol_member(type, "getindex");
  Type signature = resolved ? resolved.cadr() : NULL;
  if (signature ~= %((func (!set ?params (?receiver ?))) ?rtype) &&
      (collection || receiver == type))
    return _getindex_expression(c, expr, index, params, rtype);
  return _native_index(c, expr, index, type);
}

static int _collection_index_type(Compiler c, Type type) =>
  c.sym.is_named_value_type(type, "List") || c.sym.is_string_type(type) ||
  c.sym.is_array_type(type) || c.sym.is_map_type(type);

/* Resolves the exact nominal getter shared by bracket admission and lowering.
    A collection getter's own body uses the inherited implementation instead.
*/
List _x2c_nominal_getindex(Compiler c, Type type) {
  if (!type.is_typedef_name()) return NULL;
  if (type ~= %(?(String nominal))) {
    String source = %"$(nominal)_getindex";
    if (source == c.fn_name && _collection_index_type(c, type)) return NULL;
    Type signature = c.sym.get($(source));
    if (signature ~= %((func ($type ?)) ?))
      return $(c.sym.reference($(source), NULL), signature);
  }
  return NULL;
}

static List _getindex_expression(
  Compiler c, List expr, List index, Var params, Var rtype) {
  Type key = params.cadr(), supplied = index.cadr();
  if (key.is_integral() && c.sym.is_named_value_type(supplied, "Symbol"))
    $fail.expressions_index_symbol(c, c.token);
  return %(expr ($rtype) (getindex $expr $index));
}

static List _native_index(Compiler c, List expr, List index, Type type) {
  Type native = _index_native_type(c, expr.cadr());
  Type shape = native.canonicalize();
  // A boxable handle to a record has no C array reading.
  if (shape.is_pointer() && shape.dereference().is_aggregate() &&
      type.var_tag())
    $fail.expressions_index_missing(c, c.token, type);
  // A typedef of a plain C pointer indexes as that pointer; `String` and
  // its aliases keep their protocol reading.
  if (shape.is_array() ||
      (shape.is_pointer() && !c.sym.is_string_type(type)))
    return %(expr $(native.dereference()) (index $expr $index));
  return NULL;
}

// Resolve the outer aliases without reducing the indexed element type.
static Type _index_native_type(Compiler c, Type native) {
  int hops = 0;
  loop {
    Type key = native.canonicalize();
    if (!key.is_bare_typedef_name() && !key.is_typedef()) break;
    Type next = c.sym.next_typedef(key, hops);
    if (!next) break;
    native = next.qualify(native);
  }
  return native;
}

module List _getindex(Resolve &r, List receiver, List selector) =>
  %(expr $(r.type)
    (getindex $(r.c.resolve_expression(receiver, r.origin))
              $(r.c.resolve_expression(selector, r.origin))));

module List _slice(Resolve &r, List slice) {
  (List receiver, List start, List stop, List step) = slice.cdr();
  receiver = r.c.resolve_expression(receiver, r.origin);
  if (start) start = r.c.resolve_expression(start, r.origin);
  if (stop) stop = r.c.resolve_expression(stop, r.origin);
  if (step) step = r.c.resolve_expression(step, r.origin);
  List operation = source_slice_content($(receiver, start, stop, step));
  if (r.type === %(<macro-expr>))
    operation = r.c.anchor_origin(operation, r.origin);
  return %(expr $(receiver.cadr()) $operation);
}

// member lookup

/** Resolves one field or method selection without consuming parser tokens.
    `field` is a single-name `List` and `access` is `.` or `->`. The result is
    a `(field access type)`, `(method binding signature)`, or `(ambiguous ...)`
    row, or NULL when no member is visible. Method lookup is enabled only by
    `call_context` and records the selected binding in `c.sym`.
*/
List Compiler.resolve_postfix_member(
  Compiler c, Type receiver_type, List field, Symbol access,
  int call_context) {
  if (receiver_type.car() == <opt-ref>)
    $fail.expressions_optional_ref_access(c, c.token);
  Type type = receiver_type.canonicalize();
  if (access == <"->">)
    return _field_member(c, receiver_type, field, <"->">);
  int hops = 0, tagged = 0;
  while (type) {
    if (call_context && _method_owner(type)) {
      List method = _method_member(c, receiver_type, type, field);
      if (method) return method;
    }
    if (type.is_pointer())
      return _field_member(c, receiver_type, field, <"->">);
    if (type.is_aggregate()) {
      List member = _field_member(c, receiver_type, field, <.>);
      if (member || !call_context) return member;
    }
    type = _next_method_type(c, type, hops, tagged);
  }
  return NULL;
}

static int _method_owner(Type type) =>
  !type.is_aggregate() && (type.is_typedef_name() || type.is_builtin());

/* Lookup and completion follow the same typedef owner from an aggregate. */
static Type _next_method_type(Compiler c, Type type, int &hops, int &tagged) {
  if (type.is_pointer()) return NULL;
  if (type.is_aggregate()) return !tagged++ ? _tag_typedef(c, type) : NULL;
  return c.sym.next_typedef(type, hops).canonicalize();
}

/* A field inherits its containing object's qualifiers, not its pointer's. */
static List _field_member(
  Compiler c, Type receiver, List field, Symbol access) {
  Type object = access == <"->">
    ? c.sym.normalize_declared_type(receiver).dereference() : receiver;
  Type declared = c.sym.lookup_field(object, field);
  return declared ? %(field $access $declared) : NULL;
}

/* A receiver spelled `struct T` or `union T` reaches the methods of the
   typedef that names the same aggregate: `T` itself, as the usual
   `typedef struct T {...} T;` declares, or else the only typedef declared
   directly as that aggregate. */
module Type _tag_typedef(Compiler c, Type aggregate) {
  if (aggregate ~= %(? ?(String tag))) {
    Type name = $(tag), declared = c.sym.get(%(typedef $tag));
    if (declared && c.sym.resolve_key(declared) == aggregate) return name;
  }
  return c.sym.sole_typedef(aggregate);
}

static List _method_member(
  Compiler c, Type receiver_type, Type type, List field) {
  String method = %"$(type.base_type().car())_$(field.car())";
  Type signature = c.sym.get($(method));
  int rejected =
    c.protocol_rejects_direct_member(type, field.car().str());
  if (signature && rejected == 2) {
    String name = %"$(type.base_type().car()).$(field.car())";
    String hidden = %"method '$name' is hidden by an inherited protocol";
    c.report_error(<type>,
      hidden + " conformance; adopt the protocol for this type to use it",
      NULL, NULL);
  }
  if (signature && rejected) signature = NULL;
  List binding = NULL;
  if (signature) binding = c.sym.reference($(method), NULL);
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

/* Find a method that an imported package adds to an external receiver. The
   package names are sorted so an ambiguous call reports deterministically. */
static List _imported_method(Compiler c, String method, Type receiver) {
  List packages = c.imported_providers(method);
  if (!packages) return NULL;
  if (packages.cdr()) return cons(<ambiguous>, packages);

  String spelling = %"$(packages.car())__$method";
  Type signature = c.sym.get_exact($(spelling));
  List binding = c.sym.reference($(spelling), NULL);
  signature = _receiver_relative_signature(c, binding, signature, receiver);
  return %(method $binding $signature);
}

static Type _receiver_relative_signature(
  Compiler c, List binding, Type signature, Type receiver) {
  String spelling = Ast.binding_spelling(binding);
  if (!spelling) return signature;
  Type relative = c.sym.get_exact(%(self $spelling));
  if (!relative) return signature;
  Type base = receiver.canonicalize().base_type();
  if (!base || base.len() != 1) return signature;
  return relative.search_replace(<self>, base.car());
}

module List _member(Resolve &r, Var operator, List receiver, List field) {
  receiver = r.c.resolve_expression(receiver, r.origin);
  Type receiver_type = receiver.cadr();
  List resolution = r.c.resolve_postfix_member(
    receiver_type, field, operator, 0);
  if (resolution ~= %(field ?access ?field_type))
    return source_operator_expression(
      field_type, $(access, receiver, field));
  Type type = _deferred_receiver(receiver) ? %(<macro-expr>) : NULL;
  return source_operator_expression(type, $(operator, receiver, field));
}

module void _report_method_ambiguity(
  Compiler c, Type receiver, String member, List packages, Token origin) {
  Array notes = [];
  foreach (String package in packages) notes.push(%"package: '$package'");
  String type = _member_type_name(receiver);
  $fail.expressions_method_packages(
    c, origin, type, member, notes.list_free());
}

/* A method's receiver in a diagnostic: its aggregate tag or its leading
   word. */
static String _member_type_name(Type type) {
  Type base = type.base_type();
  Var (head, name) = base;
  return base.is_aggregate_tag() ? name.str() : head.str();
}

// member completion

/** Returns sorted visible field and method names that resolve on `receiver`
    through `access`.
*/
List Compiler.postfix_completions(Compiler c, Type receiver, Symbol access) {
  Map seen = {};
  Array names = auto [], accepted = [];
  Type fields = c.sym.resolve_key(receiver);
  if (fields.is_pointer()) fields = fields.dereference();
  _completion_fields(c, fields, seen, names, {});
  if (access == <.>) _completion_methods(c, receiver, seen, names);
  names.sort();
  foreach (String name in names) {
    List resolution = c.resolve_postfix_member(receiver, $(name), access, 1);
    if (resolution ~= %((!or field method) ? ?)) accepted.push(name);
  }
  return accepted.list_free();
}

static void _completion_fields(
  Compiler c, Type type, Map seen, Array names, Map visited) {
  type = c.sym.resolve_key(type);
  if (!type || !type.is_aggregate_tag() || type in visited) return;
  visited[type] = 1;
  List order = c.sym.field_order(type);
  foreach (List row in order ? order.cdr() : NULL) {
    String name = row.car();
    if (name) _completion_add(seen, names, name);
    else _completion_fields(c, row.cadr(), seen, names, visited);
  }
}

static void _completion_methods(
  Compiler c, Type receiver, Map seen, Array names) {
  Type type = receiver.canonicalize();
  int hops = 0, tagged = 0;
  while (type) {
    if (_method_owner(type)) {
      String owner = type.base_type().car();
      _completion_owner_methods(c, %"$(owner)_", seen, names);
      foreach (String name in c.protocol_member_names(type))
        _completion_add(seen, names, name);
    }
    type = _next_method_type(c, type, hops, tagged);
  }
}

/* Functions named `Owner_name`, or `package__Owner_name` for an imported
   package, among the visible symbols. */
static void _completion_owner_methods(
  Compiler c, String prefix, Map seen, Array names) {
  foreach (List row in c.sym.visible_symbols()) {
    (String spelling, Var raw) = row;
    if (raw is not <list>) continue;
    Type signature = raw;
    if (signature.is_function() && spelling.startswith(prefix))
      _completion_add(seen, names, spelling.remove_prefix(prefix));
    foreach (String (package, _) in c.package_roots) {
      String imported = %"$(package)__$prefix";
      if (signature.is_function() && spelling.startswith(imported))
        _completion_add(seen, names, spelling.remove_prefix(imported));
    }
  }
}

static void _completion_add(Map seen, Array names, String name) {
  if (!name || name in seen) return;
  seen[name] = 1;
  names.push(name);
}
