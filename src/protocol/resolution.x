/*  resolution.x -- protocol conformance resolution

    Native and ordinary resolution are the only conformance-row producers. A
    row carries base, participant, converters, type-variable maps, and member
    rows of `(name status source expected default-kind template)`. Consumers
    dispatch on `status`; a non-list cache value records failed resolution.
*/
static typedef struct ProtocolRequirements {
  String binder;
  List associations, templates;
} ProtocolRequirements;

static typedef struct NativeResolution {
  Type base, participant, definition;
  String binder;
  Map variables, bindings;
} NativeResolution;

static typedef struct MemberResolution {
  Compiler c;
  Type base, participant, representation;
  String binder, forward;
  Map variables, defaults, bindings;
} MemberResolution;

/* adapter requirements

   Resolution accepts an ordinary conformance only when its adapters can be
   generated, and presentation checks an inherited member the same way.
   Both describe the adapters with one record. */

/* The adapters one conformance needs. Resolution fills the base, binder,
   and converters; presentation fills the rest. */
module typedef struct ProtocolAdapters {
  Compiler c;
  Type base, participant;
  String forward, reverse, binder;
  Map variables, bindings;
  List adoption;
  int shares_var_tag, central_initializer;
} ProtocolAdapters;

static macro Expression $reason.protocol_conformance_prefix(
  Expr $participant, Expr $owner) =>
  %"$($participant) does not satisfy $($owner): ";

static macro Expression $reason.protocol_native_alias(
  Expr $prefix, Expr $base) =>
  %"$($prefix)its typedef is not a native alias of $($base)";

static macro Expression $reason.protocol_forward_conversion(
  Expr $prefix, Expr $forward) =>
  %"$($prefix)no forward conversion '$($forward)'";

static macro Expression $reason.protocol_reverse_conversion(
  Expr $prefix, Expr $base, Expr $lowered) =>
  %"$($prefix)no reverse conversion '$($base).$($lowered)' " +
    %"or '$($base).as_$($lowered)'";

static macro Expression $reason.protocol_fallback_nested(
  Expr $prefix, Expr $member, Expr $position) =>
  %"$($prefix)member '$($member)' uses T inside a compound " +
    %"$($position) type, which protocol fallback adapters " +
    "do not support";

static macro Expression $reason.protocol_fallback_reverse(
  Expr $prefix, Expr $member, Expr $owner, Expr $base, Expr $lowered) =>
  %"$($prefix)member '$($member)' returns T, so $($owner) needs " +
    %"'$($base).$($lowered)' or '$($base).as_$($lowered)'";

static macro Expression $reason.protocol_fallback_forward(
  Expr $prefix, Expr $member, Expr $participant, Expr $base) =>
  %"$($prefix)member '$($member)' fallback requires forward " +
    %"conversion '$($participant).$($base.lower())'";

static macro Expression $reason.protocol_thunk_nested(
  Expr $prefix, Expr $member, Expr $position) =>
  %"$($prefix)member '$($member)' uses T inside a compound " +
    %"$($position) type, which protocol descriptor thunks " +
    "do not support";

static macro Expression $reason.protocol_thunk_parameter(
  Expr $prefix, Expr $member, Expr $owner, Expr $base, Expr $lowered) =>
  %"$($prefix)member '$($member)' has a T parameter, so " +
    %"$($owner) needs '$($base).$($lowered)' or '$($base).as_$($lowered)'";

static macro Expression $reason.protocol_thunk_result(
  Expr $prefix, Expr $member, Expr $owner, Expr $participant, Expr $base) =>
  %"$($prefix)member '$($member)' returns T, so $($owner) needs " +
    %"'$($participant).$($base.lower())'";

static macro Expression $reason.protocol_native_parameter(
  Expr $prefix, Expr $member, Expr $base) =>
  %"$($prefix)native member '$($member)' has a T parameter " +
    %"that is not implicitly convertible to $($base)";

static macro Expression $reason.protocol_native_result(
  Expr $prefix, Expr $member, Expr $base) =>
  %"$($prefix)native member '$($member)' returns T, which is " +
    %"not implicitly convertible from $($base)";

static macro Expression $reason.protocol_native_member_alias(
  Expr $prefix, Expr $member) =>
  %"$($prefix)native member '$($member)' cannot be aliased";

static macro Stmt $report.protocol_base_missing(
  Expr $c, Expr $site, Expr $base) =>
  $c.diagnostics.report(
    <protocol>,
    %"adoption base $(_type_spelling($base)) names no visible protocol",
    $site, NULL);

static macro Stmt $report.protocol_signature_conflict(
  Expr $c, Expr $location, Expr $member, Expr $owner, Expr $declaration_site,
  Expr $binding, Expr $actual, Expr $expected) {
  {
    String protocol_note =
      %"protocol member '$($member)' declared by $($owner)";
    if ($declaration_site)
      protocol_note = %"$protocol_note at $($declaration_site)";
    String actual_repr = $actual.repr();
    String conflict_note =
      %"conflicting definition '$($binding)': $actual_repr";
    String expected_note = %"expected: $($expected.repr())";
    $c.diagnostics.report(
      <protocol>,
      %"'$($binding)' has a signature incompatible " +
        %"with $($owner) member '$($member)'",
      $location,
      $(protocol_note, conflict_note, expected_note));
  }
}

#define PROTOCOL_VARIABLE 1
#define PROTOCOL_VARIADIC 2

/** Resolves every visible adoption into the current conformance registry.
    Resolution starts from an empty registry; diagnostics are located only for
    adoptions owned by the current translation unit. An adoption another
    unit declared and recorded keeps that conformance, which is installed
    when it is first used.
*/
void Compiler.resolve_protocols(Compiler c) => _resolve_visible(c, 1);

// recorded conformance

/** Returns the interface rows of the resolved conformances `adoptions`
    declare.
*/
Map Compiler.conformance_rows(Compiler c, List adoptions) {
  Map rows = {};
  foreach (List adoption in adoptions) {
    Type (base, participant) = adoption.cdr();
    List recorded = _recorded_conformance(c, base, participant);
    if (recorded)
      rows[%("source-node" (conformance $base $participant))] = recorded;
  }
  return rows;
}

/** Resolves the adoptions visible in `symbols` as a declaring unit's full
    parse resolves its own: before the parse, and again, after the
    generated members are published, where the parse publishes each one.
    Their declaring units report their failures, so nothing is reported.
*/
void Compiler.resolve_as_declared(Compiler c, Map symbols) {
  c.sym.reset(symbols);
  c.rebuild_protocols(symbols);
  _resolve_visible(c, 0);
  c.install_generated_protocol_symbols();
  Array pairs = [];
  foreach (List key in c.conforms.keys()) pairs.push(key);
  foreach (List pair in pairs) {
    if (_recorded(c, pair.car(), pair.cadr())) continue;
    c.conforms.del(pair);
    c.proto_cache = {};
    _resolve_adoption(c, pair.car(), pair.cadr(), NULL);
  }
  pairs.free();
}

// protocol conformance resolution

static void _resolve_visible(Compiler c, int report) {
  c.conforms = {};
  String owner = _path(c);
  foreach (List adoption in c.adoptions) {
    Type (base, participant) = adoption.cdr();
    Symbol storage = _adoption_storage(adoption);
    List location = _adoption_location(adoption);
    String path = _canonical_file(c, location);
    if (storage == <static> && path != owner) continue;
    if (_recorded(c, base, participant)) continue;
    _resolve_adoption(
      c, base, participant, report && path == owner ? location : NULL);
  }
}

/* The row an included interface recorded for an adoption this unit does not
   own, or NULL. */
static List _recorded(Compiler c, Type base, Type participant) {
  Var recorded;
  if (_owns_adoption(c, base, participant) ||
      !c.protocol_helpers.try_get(
        $("recorded-conformance", base, participant), recorded))
    return NULL;
  return recorded;
}

module void _resolve_adoption(
  Compiler c, Type base, Type participant, List location) {
  List record = _record(c, base);
  if (!record) {
    if (!location) return;
    $report.protocol_base_missing(c, location, base);
    return;
  }
  if (record ~= %(? ? ?(String binder) (associated *associations)
                  (members *members))) {
    ProtocolRequirements requirements = {
      .binder = binder, .associations = associations,
      .templates = members};
    _resolve_record(c, base, participant, location, requirements);
  }
}

static void _resolve_record(
  Compiler c, Type base, Type participant, List location,
  ProtocolRequirements &requirements) {
  int native = _is_native(requirements.templates);
  List conformance = NULL, failure = NULL;
  if (native) {
    Type definition = _participant_definition(c, participant);
    conformance = _resolve_native(
      c, base, participant, requirements, definition, failure);
  }
  else
    conformance = _resolve_ordinary(
      c, base, participant, requirements, failure);

  if (!conformance) {
    if (!location) return;
    String detail = _missing_detail(c, base, participant, native, failure);
    c.diagnostics.report(<protocol>, detail, location, NULL);
    return;
  }
  if (location) {
    List rows = conformance.last().list().cdr();
    if (native) _install_native_bindings(c, participant, rows);
    _report_sig_conflicts(c, base, participant, rows, location);
  }
}

static String _missing_detail(
  Compiler c, Type base, Type participant, int native, List failure) {
  String base_repr = _type_spelling(base);
  String participant_repr = _type_spelling(participant);
  String prefix = $reason.protocol_conformance_prefix(
    participant_repr, _adoption_spelling(base, participant));
  if (failure) return _requirement_detail(base, participant, failure);
  if (native)
    return $reason.protocol_native_alias(prefix, base_repr);
  String base_name = _base_name(base);
  Type forward = base_name
    ? _declared(c, _member_spelling(participant, base_name.lower())) : NULL;
  if (base_name && !_exact_conversion(forward, participant, base))
    return $reason.protocol_forward_conversion(
      prefix, %"$participant_repr.$(base_name.lower())");
  String lowered = participant.is_bare_typedef_name()
    ? participant.car().str().lower() : participant_repr;
  return $reason.protocol_reverse_conversion(prefix, base_repr, lowered);
}

module String _requirement_detail(Type base, Type participant, List failure) {
  String base_repr = _type_spelling(base);
  String participant_repr = _type_spelling(participant);
  (String member, Symbol adapter, Symbol direction, Symbol position) = failure;
  String lowered = participant.is_bare_typedef_name()
    ? participant.car().str().lower() : participant_repr;
  String owner = _adoption_spelling(base, participant);
  String prefix = $reason.protocol_conformance_prefix(participant_repr, owner);
  if (adapter == <fallback> && direction == <nested>)
    return $reason.protocol_fallback_nested(prefix, member, position);
  if (adapter == <fallback> && direction == <reverse>)
    return $reason.protocol_fallback_reverse(
      prefix, member, owner, base_repr, lowered);
  if (adapter == <fallback>)
    return $reason.protocol_fallback_forward(
      prefix, member, participant_repr, base_repr);
  if (adapter == <thunk> && direction == <nested>)
    return $reason.protocol_thunk_nested(prefix, member, position);
  if (adapter == <thunk> && position == <parameter>)
    return $reason.protocol_thunk_parameter(
      prefix, member, owner, base_repr, lowered);
  if (adapter == <thunk>)
    return $reason.protocol_thunk_result(
      prefix, member, owner, participant_repr, base_repr);
  if (position == <parameter>)
    return $reason.protocol_native_parameter(prefix, member, base_repr);
  if (position == <result>)
    return $reason.protocol_native_result(prefix, member, base_repr);
  return $reason.protocol_native_member_alias(prefix, member);
}

static void _report_sig_conflicts(
  Compiler c, Type base, Type participant, List rows, List location) {
  String owner = _adoption_spelling(base, participant);
  String declaration_site = _definition_location(c, base);
  foreach (List row in rows)
    if (row ~= %(?(String member) sig-cnflct ?(String binding)
                  ?(Type expected) ? ?)) {
      List dedupe = $("protocol-sig-conflict", participant, member);
      if (dedupe in c.protocol_helpers) continue;
      c.protocol_helpers[dedupe] = 1;
      Type actual = _declared(c, binding);
      $report.protocol_signature_conflict(
        c, location, member, owner, declaration_site, binding, actual,
        expected);
    }
}

static String _definition_location(Compiler c, Type base) {
  List stored = c.protocols[base];
  return _location_string(_occurrence_location(stored));
}

// native conformance

static List _resolve_native(
  Compiler c, Type base, Type participant, ProtocolRequirements &requirements,
  Type participant_definition, List &failure) {
  failure = NULL;
  List key = $(base, participant);
  Var stored;
  if (c.conforms.try_get(key, stored)) {
    if (stored is not <list>) return NULL;
    List conformance = stored;
    _install_native_bindings(c, participant, conformance.last().list().cdr());
    return conformance;
  }
  if (!participant.is_bare_typedef_name() || !participant_definition) {
    c.conforms[key] = 0;
    return NULL;
  }
  NativeResolution resolution = {
    .base = base, .participant = participant,
    .definition = participant_definition, .binder = requirements.binder,
    .variables = {}, .bindings = {}};
  resolution.variables[requirements.binder] = 1;
  resolution.bindings[requirements.binder] = participant;
  foreach (List association in requirements.associations) {
    (String association_name, Type binding) = association;
    resolution.variables[association_name] = 1;
    resolution.bindings[association_name] = binding;
  }
  List rows = _rows(resolution, requirements.templates, failure);
  if (failure) {
    c.conforms[key] = 0;
    return NULL;
  }
  List conformance = %(
    protocol-conformance $base $participant "" ""
    $(resolution.variables) $(resolution.bindings) (members @rows)
  );
  c.conforms[key] = conformance;
  return conformance;
}

static List _rows(NativeResolution &r, List templates, List &failure) {
  Array members = [];
  Map native_bindings = NULL;
  foreach (List template in templates) {
    (String member, Type type, String native) = template;
    List requirement = _native_requirement(
      member, native, type, r.binder, r.definition, r.base);
    if (requirement) {
      failure = requirement;
      members.free();
      return NULL;
    }
    Type expected = _substitute_signature(type, r.variables, r.bindings);
    if (r.definition != r.base && native_bindings == NULL) {
      native_bindings = r.bindings.copy();
      native_bindings[r.binder] = r.base;
    }
    Type alias_signature = r.definition == r.base ? expected
      : _substitute_signature(type, r.variables, native_bindings);
    members.push(%($member native $native $expected none $alias_signature));
  }
  return members.list_free();
}

static List _native_requirement(
  String member, String native, Type template, String binder,
  Type participant_definition, Type base) {
  if (!native) return %($member native binding missing);
  List parameters = template.car().list().cadr();
  Type result = template.cdr();
  int contents = _contents(parameters, binder);
  if (contents & PROTOCOL_VARIADIC)
    return %($member native parameter variadic);
  if ((contents & PROTOCOL_VARIABLE) &&
      !_native_converts(participant_definition, base))
    return %($member native parameter implicit);
  if ((_contents(result, binder) & PROTOCOL_VARIABLE) &&
      participant_definition != base)
    return %($member native result implicit);
  return NULL;
}

static int _native_converts(Type participant_definition, Type base) {
  if (participant_definition == base) return 1;
  return participant_definition.canonicalize() == base.canonicalize();
}

static Type _participant_definition(Compiler c, Type participant) {
  if (!participant.is_bare_typedef_name()) return NULL;
  String name = participant.car();
  Var definition = c.sym.global_symbols()[%(typedef $name)];
  /* The Type destination maps other value tags to nil. */
  return definition;
}

module void _install_native_bindings(Compiler c, Type participant, List rows) {
  if (!_native_rows(rows)) return;
  foreach (List row in rows)
    if (row ~= %(?(String member) ? ? ? ? ?(Type signature))) {
      String generated = _member_spelling(participant, member);
      if (!c.sym.get($(generated)))
        c.sym.define_global($(generated), signature);
    }
}

static int _is_native(List templates) {
  foreach (List template in templates)
    if (template.caddr().str()) return 1;
  return 0;
}

module int _native_rows(List rows) {
  return rows ~= %((? native *) *);
}

// ordinary conformance

static List _resolve_ordinary(
  Compiler c, Type base, Type participant,
  ProtocolRequirements &requirements, List &failure) {
  failure = NULL;
  Var stored;
  List key = $(base, participant);
  /* The List destination preserves non-List negative entries as nil. */
  if (c.conforms.try_get(key, stored))
    return stored;
  String base_name = _base_name(base);
  if (!base_name || !participant.is_bare_typedef_name()) goto does_not_conform;
  String forward = _forward_binding(c, base, participant);
  String reverse = _reverse_binding(c, base, participant);
  MemberResolution resolution = {
    .c = c, .base = base, .participant = participant,
    .binder = requirements.binder,
    .variables = {}, .defaults = {}, .bindings = {},
    .representation = base === %("Var")
      ? _adoption_representation(_visible_adoption(c, base, participant))
      : NULL,
    .forward = base !== %("Var") ? forward : NULL};
  List rows = _resolve(
    resolution, requirements.associations, requirements.templates);
  ProtocolAdapters adapters = {
    .c = c, .base = base, .binder = requirements.binder,
    .forward = forward, .reverse = reverse};
  List requirement = _requirement(adapters, rows);
  if (requirement) {
    failure = requirement;
    goto does_not_conform;
  }
  List conformance = %(
    protocol-conformance $base $participant $forward $reverse
    $(resolution.variables) $(resolution.bindings) (members @rows)
  );
  c.conforms[key] = conformance;
  return conformance;
does_not_conform: c.conforms[key] = 0;
  return NULL;
}

static String _forward_binding(Compiler c, Type base, Type participant) {
  String base_name = _base_name(base);
  if (!base_name || !participant.is_bare_typedef_name()) return NULL;
  String binding = _member_spelling(participant, base_name.lower());
  Type found = _declared(c, binding);
  if (!_exact_conversion(found, participant, base)) return NULL;
  return binding;
}

static String _reverse_binding(Compiler c, Type base, Type participant) {
  String base_name = _base_name(base);
  if (!base_name || !participant.is_bare_typedef_name()) return NULL;
  String participant_name = participant.car();
  String conventional =
    c.reverse_converter_spelling(base_name, "", participant_name);
  Type found = _declared(c, conventional);
  if (_exact_conversion(found, base, participant)) return conventional;
  String alternate =
    c.reverse_converter_spelling(base_name, "as_", participant_name);
  found = _declared(c, alternate);
  if (_exact_conversion(found, base, participant)) return alternate;
  return NULL;
}

/* Members are selected against the participant's bindings first; the
   associated-type defaults fill what selection left unbound before each
   member's expected signature is completed. */
static List _resolve(MemberResolution &r, List associations, List templates) {
  r.variables[r.binder] = 1;
  r.bindings[r.binder] = r.participant;
  foreach (List association in associations) {
    (String name, Type value) = association;
    r.variables[name] = 1;
    r.defaults[name] = value;
  }
  Array selected = [];
  foreach (List row in templates) {
    List member = _select(r, row);
    if (member) selected.push(member);
  }
  foreach ((String name, Type value) in r.defaults)
    r.bindings.setdefault(name, value);
  Array completed = [];
  foreach (List row in selected) {
    List member = _complete(r, row);
    if (member) completed.push(member);
  }
  selected.free();
  return completed.list_free();
}

static List _select(MemberResolution &r, List row) {
  if (row ~= %(?(String member) ?(Type template) ?)) {
    String selected = NULL;
    Type actual = _find_member(r, member, selected);
    Symbol status = <no-member>;
    if (actual) {
      Map candidate = r.bindings.copy();
      if (_unify_signature(template, actual, r.variables, candidate)) {
        r.bindings = candidate;
        status = <implmntd>;
      }
      else status = <sig-cnflct>;
    }
    return %($member $status $selected $actual none $template);
  }
  return NULL;
}

static Type _find_member(
  MemberResolution &r, String member, String &selected) {
  String binding = _member_spelling(r.participant, member);
  Type actual = _declared(r.c, binding);
  if (actual && _default_completes(r.c, binding, actual, r.forward))
    actual = NULL;
  if (!actual) {
    String imported = r.c.imported_spelling(binding);
    if (imported) {
      actual = _declared(r.c, imported);
      if (actual) binding = imported;
    }
  }
  if (actual) selected = binding;
  foreach (Type owner in
           (r.base !== %("Var") || r.representation) && !actual
             ? _ancestry(r.c, r.participant).cdr() : NULL) {
    if (owner == r.base) break;
    if (r.base === %("Var") && owner != r.representation) continue;
    actual = _method_signature(r.c, owner, r.participant, member, selected);
    if (actual || r.base === %("Var")) break;
  }
  return actual;
}

static Type _method_signature(
  Compiler c, Type owner, Type participant, String member,
  String &selected) {
  if (!owner.is_bare_typedef_name()) return NULL;
  String source = _member_spelling(owner, member);
  Type signature = _declared(c, source);
  if (!signature) {
    String imported = c.imported_spelling(source);
    if (imported) {
      signature = _declared(c, imported);
      if (signature) source = imported;
    }
  }
  if (!signature) return NULL;

  List binding = c.sym.reference($(source), NULL);
  signature = _relative_signature(c, binding, signature, participant);
  List parameters = NULL, Type result = NULL;
  if (_function_parts(signature, parameters, result) &&
      parameters && parameters.car() == owner) {
    parameters = parameters.map(
      %!(Var parameter) => parameter == owner ? participant : parameter);
    signature = %((func $parameters) @result);
  }
  selected = source;
  return signature;
}

static Type _relative_signature(
  Compiler c, List binding, Type signature, Type receiver) {
  Var stored;
  if (!c.semantic_binding_facts().try_get(%(self $binding), stored))
    return signature;
  Type relative = stored, base = receiver.canonicalize().base_type();
  return relative.search_replace(<self>, base.car());
}

/* A bodyless, non-static prototype of a member whose base default the
   visible forward converter generates declares that default rather than
   implementing the member. */
static int _default_completes(
  Compiler c, String name, Type declared, String forward) =>
  forward && declared.is_function() && forward in c.fn_defs &&
  !(name in c.fn_defs) &&
  !(%(function $name) in c.sym.file_statics());

static List _complete(MemberResolution &r, List row) {
  if (row ~= %(?(String member) ?(Symbol status) ?(String source)
               ? ? ?(Type template))) {
    Type expected = _substitute_signature(template, r.variables, r.bindings);
    Symbol default_kind = <none>;
    if (status == <no-member>) {
      String base_name = _base_name(r.base);
      if (base_name && r.base !== %("Var")) {
        String fallback = %"$(base_name)_$member";
        Type fallback_type = _declared(r.c, fallback);
        Map base_bindings = r.bindings.copy();
        base_bindings[r.binder] = r.base;
        Type base_signature = _substitute_signature(
          template, r.variables, base_bindings);
        if (fallback_type == base_signature) {
          status = <base-dflt>;
          source = fallback;
          default_kind = <ordinary>;
        }
      }
    }
    return $(member, status, source, expected, default_kind, template);
  }
  return NULL;
}

static Type _declared(Compiler c, String name) {
  if (c.sym.get($("generated-protocol", name))) return NULL;
  return c.sym.get($(name));
}

static List _requirement(ProtocolAdapters &a, List rows) {
  foreach (List row in rows)
    if (row ~= %(?(String member) ?(Symbol status) ? ?
                  ?(Symbol default_kind) ?(Type template))) {
      if (status == <base-dflt> && default_kind == <ordinary>) {
        List requirement =
          _conversion_requirement(a, member, template, <fallback>);
        if (requirement) return requirement;
      }
      if (status == <implmntd>) {
        List requirement = _descriptor_requirement(a, member, template);
        if (requirement) return requirement;
      }
    }
  return NULL;
}

module List _descriptor_requirement(
  ProtocolAdapters &a, String member, Type template) {
  if (a.base !== %("Var") ||
      !a.c.sym.lookup_field(%(struct "VarMethods"), $(member), NULL))
    return NULL;
  return _conversion_requirement(a, member, template, <thunk>);
}

static List _conversion_requirement(
  ProtocolAdapters &a, String member, Type template, Symbol adapter) {
  int fallback = adapter == <fallback>;
  List parameters = template.car().list().cadr();
  Type result = template.cdr(), variable = $(a.binder);
  Symbol direction = fallback ? <forward> : <reverse>;
  foreach (Var parameter in parameters) {
    if (parameter == variable) {
      if (!(fallback ? a.forward : a.reverse))
        return %($member $adapter $direction parameter);
    }
    else if (_contents(parameter, a.binder) & PROTOCOL_VARIABLE)
      return %($member $adapter nested parameter);
  }
  direction = fallback ? <reverse> : <forward>;
  if (result == variable) {
    if (!(fallback ? a.reverse : a.forward))
      return %($member $adapter $direction result);
  }
  else if (_contents(result, a.binder) & PROTOCOL_VARIABLE)
    return %($member $adapter nested result);
  return NULL;
}

static int _contents(Var value, String variable) {
  if (value is <string>)
    return value == variable ? PROTOCOL_VARIABLE : 0;
  if (value == <...>) return PROTOCOL_VARIADIC;
  if (value is not <list>) return 0;
  int contents = 0;
  foreach (Var item in value.list())
    contents |= _contents(item, variable);
  return contents;
}

// signature unification

static int _unify_signature(
  Type pattern, Type actual, Map variables, Map bindings) {
  List pattern_parameters = pattern.car().list().cadr();
  List parameters = NULL, Type result = NULL;
  return _function_parts(actual, parameters, result) &&
         _unify(pattern_parameters, parameters, variables, bindings) &&
         _unify(pattern.cdr(), result, variables, bindings);
}

static int _unify(Var pattern, Var actual, Map variables, Map bindings) {
  String variable = _type_variable(pattern, variables);
  if (variable) {
    Var bound;
    if (!bindings.try_get(variable, bound)) {
      bindings[variable] = actual;
      return 1;
    }
    return bound == actual;
  }
  if (pattern is <list> != actual is <list>) return 0;
  if (pattern is not <list>) return pattern == actual;
  List left = pattern, right = actual;
  if (!left || !right) return left == right;
  return _unify(left.car(), right.car(), variables, bindings) &&
         _unify(left.cdr(), right.cdr(), variables, bindings);
}

module Type _substitute_signature(
  Type signature, Map variables, Map bindings) {
  List parameters = signature.car().list().cadr();
  Type result = signature.cdr();
  List parameter_types = parameters.map(
    %!(Var parameter) => _substitute(parameter, variables, bindings));
  Type result_type = _substitute(result, variables, bindings);
  return %((func $parameter_types) @result_type);
}

static Var _substitute(Var value, Map variables, Map bindings) {
  String variable = _type_variable(value, variables);
  if (variable) return bindings[variable];
  if (value is not <list> || !value.list()) return value;
  List type = value;
  return cons(
    _substitute(type.car(), variables, bindings),
    _substitute(type.cdr(), variables, bindings));
}

/* A type variable is the one-element Type `("T")`. In a compound Type such
   as `(* "T")` it is the base suffix, so walking a Type by car and cdr
   reaches it as a whole Type in that position too. */
static String _type_variable(Var value, Map variables) {
  if (value ~= %(?(String name)) && name in variables) return name;
  return NULL;
}

static int _exact_conversion(Type signature, Type parameter, Type result) {
  List parameters = NULL, Type actual_result = NULL;
  if (!_function_parts(signature, parameters, actual_result))
    return 0;
  return parameters && !parameters.cdr() &&
         parameters.car() == parameter &&
         actual_result == result;
}

static int _function_parts(Type signature, List &parameters, Type &result) {
  if (signature ~= %((func ?arguments) *return_type)) {
    parameters = arguments;
    result = return_type;
    return 1;
  }
  return 0;
}

static List _recorded_conformance(Compiler c, Type base, Type participant) {
  if (_visibility(c, base, participant) != <external>) return NULL;
  if (c.conforms[$(base, participant)] ~= %(
        protocol-conformance ? ? ?forward ?reverse ? ?(Map bindings)
        (members *rows))) {
    if (_native_rows(rows)) return NULL;
    Array bound = [], resolved = [];
    foreach ((String name, Type type) in bindings)
      bound.push($(name, type));
    bound.sort();
    foreach (List row in rows)
      if (row ~= %(?member ?(Symbol status) ?(String source) *)) {
        source = _recorded_spelling(c, source);
        if (status != <no-member> && !_is_private(c, source))
          resolved.push($(member, status, source));
      }
    forward = _recorded_spelling(c, forward);
    reverse = _recorded_spelling(c, reverse);
    return %(conformance $base $participant $forward $reverse
             (bindings @(bound.list_free())) @(resolved.list_free()));
  }
  return NULL;
}

static String _recorded_spelling(Compiler c, String name) {
  if (!name) return name;
  List binding = c.sym.lookup($(name), NULL);
  return binding ? Ast.binding_spelling(binding) : name;
}

/* An ordinary external conformance whose adoption the unit's collected
   entry declares is recorded in the unit's interface as
   `(conformance BASE PARTICIPANT FORWARD REVERSE (bindings (NAME TYPE)...)
   (MEMBER STATUS SOURCE)...)`, with each type variable's binding and each
   member resolved as anything but `no-member`. The expected and template
   types follow from the protocol record and the bindings. A member that
   resolved to a function static to this unit is left out, so it is
   `no-member` elsewhere: no other unit can call that function. A native
   conformance reads no participant member, so each unit resolves it. */
module void _record_conformances(Compiler c) {
  c.record_conformance_rows(c.conformance_rows(c.declared_adoptions()));
}

/* Installs each recorded conformance with a base default whose forward
   converter is defined, so that its forwarding members are published. */
module void _reuse_defaults(Compiler c) {
  foreach (List entry in _unused_recorded(c))
    if (entry ~= %((?(Type base) ?(Type participant))
                   (conformance ? ? ?(String forward) ? ? *members)) &&
        forward in c.fn_defs && _has_default(members))
      _reuse_conformance(c, base, participant);
}

/* Installs the conformance an included interface recorded for an adoption
   this unit does not own. Returns 0 when there is none to reuse. */
module int _reuse_conformance(Compiler c, Type base, Type participant) {
  if ($(_record(c, base), _recorded(c, base, participant)) ~= %(
        (? ? ? ? (members *templates))
        (conformance ? ? ?forward ?reverse (bindings *bound) *members))) {
    Map variables = {}, bindings = {}, resolved = {};
    foreach (List pair in bound) {
      (String name, Type type) = pair;
      variables[name] = 1;
      bindings[name] = type;
    }
    foreach (List member in members) resolved[member.car()] = member;
    Array rows = [];
    foreach (List template in templates) {
      (String member, Type type) = template;
      Type expected = _substitute_signature(type, variables, bindings);
      rows.push(_recorded_row(resolved[member], member, expected, type));
    }
    c.conforms[$(base, participant)] = %(
      protocol-conformance $base $participant $forward $reverse
      $variables $bindings (members @(rows.list_free()))
    );
    return 1;
  }
  return 0;
}

/* The recorded conformances this unit may reuse and has not installed, as
   `((BASE PARTICIPANT) ROW)` pairs. */
module List _unused_recorded(Compiler c) {
  Array candidates = [], unused = [];
  foreach (Var key in c.protocol_helpers.keys())
    if (key ~= %("recorded-conformance" ?(Type base) ?(Type participant)))
      candidates.push($(base, participant));
  // Ownership results are memoized in the helpers, so they follow the scan.
  foreach (List pair in candidates) {
    List row = _recorded(c, pair.car(), pair.cadr());
    if (row && !(pair in c.conforms)) unused.push($(pair, row));
  }
  candidates.free();
  return unused.list_free();
}

static int _has_default(List members) {
  foreach (List member in members) if (member.cadr() == <base-dflt>) return 1;
  return 0;
}

/* Rebuilds a member row as resolution writes it. A member the interface
   does not list resolved as `no-member`. */
static List _recorded_row(
  Var recorded, String member, Type expected, Type template) {
  if (recorded ~= %(? ?(Symbol status) ?(String source))) {
    Symbol kind = status == <base-dflt> ? <ordinary> : <none>;
    return $(member, status, source, expected, kind, template);
  }
  String source = NULL;
  return %($member no-member $source $expected none $template);
}
