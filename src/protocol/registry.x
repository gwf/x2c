static typedef struct AdoptionDraft {
  Compiler c;
  Type base, participant, representation;
  Symbol storage, tag;
  List tag_expression, location;
  Token participant_token, modifier_token;
} AdoptionDraft;

static macro Stmt $fail.protocol_protocol_invalid(Expr $c, Expr $site) =>
  $c.report_error(
    <macro>, "constructed protocol syntax is invalid",
    $site, NULL);

static macro Stmt $fail.protocol_decl_conflict(
  Expr $c, Expr $site, Expr $base, Expr $first_location,
  Expr $second_location) {
  {
    String first = %"first: $($first_location)";
    String second = %"second: $($second_location)";
    $c.report_error(
      <protocol>, %"conflicting protocol declarations for $($base.repr())",
      $site, $(first, second));
  }
}

static macro Stmt $fail.protocol_type_undeclared(
  Expr $c, Expr $origin, Expr $spelling) =>
  $c.report_error(
    <protocol>,
    %"adoption participant '$($spelling)' does not name a declared type",
    $origin, NULL);

static macro Stmt $fail.protocol_adoption_conflict(
  Expr $c, Expr $site, Expr $adoption, Expr $first_location) {
  {
    String first = %"first: $(_location_string($first_location))";
    String second = %"second: $(_location_string($adoption.location))";
    String spelling =
      _adoption_spelling($adoption.base, $adoption.participant);
    $c.report_error(
      <protocol>, %"conflicting adoption declarations for $spelling",
      $site, $(first, second));
  }
}

static macro Stmt $report.protocol_adoption_conflict(
  Expr $c, Expr $site, Expr $adoption, Expr $previous) {
  {
    String first = %"first: $(_location_string(_adoption_location($previous)))";
    String second = %"second: $(_location_string($adoption.location))";
    String spelling =
      _adoption_spelling($adoption.base, $adoption.participant);
    $c.diagnostics.report(
      <protocol>, %"conflicting adoption declarations for $spelling",
      $site, $(first, second));
  }
}

// registry rows

/* Protocol occurrences retain the declaration record with its linkage and
   source location. Adoption rows use base, participant, and, for static rows,
   canonical source path as identity so another unit cannot consume them. */
static List _occurrence(List record, Symbol storage, List location) =>
  $(record, storage, location);

static Symbol _occurrence_storage(List occurrence) => occurrence.cadr();

module List _occurrence_location(List occurrence) => occurrence.caddr();

module List _adoption_node(
  Type base, Type participant, Symbol storage, Type representation,
  List tag, List location) {
  if (representation)
    return %(adopt $base $participant $storage $representation $location);
  if (tag) return %(adopt $base $participant $storage (tag $tag) $location);
  return %(adopt $base $participant $storage $location);
}

module Symbol _adoption_storage(List adoption) => adoption.cddr().cadr();

// A row without a representation or a tag has five fields.
module Type _adoption_representation(List adoption) {
  match (adoption) {
    case %(adopt ? ? ? (tag (!is ? type list)) ?): return NULL;
    case %(adopt ? ? ? ?representation ?): return representation;
  }
  return NULL;
}

module List _adoption_tag(List adoption) {
  match (adoption) case %(adopt ? ? ? (tag ?(List tag)) ?): return tag;
  return NULL;
}

module List _adoption_location(List adoption) => adoption.last();

module List _record(Compiler c, Type base) {
  Var stored;
  if (!c.protocols.try_get(base, stored)) return NULL;
  List occurrence = stored;
  return occurrence.car();
}

static List _adoption_row(
  Compiler c, Type base, Type participant, Symbol storage) {
  String path = _path(c);
  List key = storage == <static>
           ? $(base, participant, path)
           : $(base, participant);
  Var stored;
  return c.adoptions.try_get(key, stored) ? stored : NULL;
}

module List _visible_adoption(
  Compiler c, Type base, Type participant) {
  List local = _adoption_row(c, base, participant, <static>);
  return local ? local : _adoption_row(c, base, participant, <external>);
}

module Symbol _visibility(Compiler c, Type base, Type participant) {
  List external = _adoption_row(c, base, participant, <external>);
  List local = _adoption_row(c, base, participant, <static>);
  if (external && local) {
    if (_canonical_file(c, _adoption_location(external)) ==
        _canonical_file(c, _adoption_location(local)))
      return <static>;
    return <mixed>;
  }
  if (local) return <static>;
  if (external) return <external>;
  return 0;
}

// Participation exists only for a declared adoption row.
module int _is_adopted(Compiler c, Type base, Type participant) =>
    !!_visibility(c, base, participant);

module int _owns_adoption(Compiler c, Type base, Type participant) {
  List row = _visible_adoption(c, base, participant);
  return row && _canonical_file(c, _adoption_location(row)) == _path(c);
}

// source locations

module String _path(Compiler c) {
  String result = NULL;
  $memo(c.protocol_helpers, <proto-path>, result) {
    result = _normalize_file(c, c.filename ? c.filename : "<stdin>");
  }
  return result;
}

/* A module member's adoptions belong to its unit, as its other
   declarations do. */
module String _canonical_file(Compiler c, List location) {
  String file = _location_file(location), result = NULL;
  $memo(c.protocol_helpers, %(proto-file $file), result) {
    result = _normalize_file(c, file);
    if (_module_member(c, result)) result = _path(c);
  }
  return result;
}

static int _module_member(Compiler c, String file) {
  if (c.line_markers)
    foreach (List row in c.line_markers)
      match (row) case %(? ? ?(String member) ? ? ? ?):
        if (_normalize_file(c, member) == file) return 1;
  return 0;
}

/* A relative path names a file below the working directory, or else one below
   the x2c root, where `Compiler.display_path` spells root sources. It
   resolves on disk itself: trying the root depends on whether the first path
   resolved, which `Compiler.canonical_path` does not report. */
static String _normalize_file(Compiler c, String file) {
  String real = Path.real(file), root = c.root_dir;
  if (!real && root && file[0] != '/') real = Path.real(%"$root/$file");
  return c.display_path(real ? real : file);
}

static String _location_file(List location) {
  Var file = location ? location.assoc(<file>) : void;
  return file is <string> ? file : "<unknown>";
}

module String _location_string(List location) {
  String file = _location_file(location);
  Var line = location ? location.assoc(<line>) : void;
  Var column = location ? location.assoc(<column>) : void;
  return %"$file:$(line.is_integer() ? line.integer() : 1):$(
    column.is_integer() ? column.integer() : 1)";
}

module int _is_private(Compiler c, String name) =>
  $(name) in c.sym.file_statics();

// spellings

module String _base_name(Type base) =>
  base.is_bare_typedef_name() ? base.car() : NULL;

// Prefer a typedef's bare diagnostic spelling.
module String _type_spelling(Type type) =>
  type.is_bare_typedef_name() ? type.car() : type.repr();

module String _member_spelling(Type participant, String member) =>
  %"$(participant.car())_$member";

module String _adoption_spelling(Type base, Type participant) =>
  %"$(_type_spelling(base))($(_type_spelling(participant)))";

static String _representation_error(Type representation) {
  String spelling = _type_spelling(representation);
  return %"Var representation $spelling has no fixed tag";
}

/** Returns the conventional reverse converter spelling.
    A `Base.participant` reverse converter is declared under the participant's
    source spelling, and package mode rewrites that joined name as a whole, so
    the package prefix sits at the front of the derived binding instead of
    inside it. The split is keyed on a known package because a foreign
    header may spell `__` in a type name. */
String Compiler.reverse_converter_spelling(
  Compiler c, String base_name, String infix, String participant) {
  int split = participant.find("__");
  String package = split > 0 &&
    (c.package == participant[:split] ||
     participant[:split] in c.package_roots)
      ? participant[:split] : NULL;
  String bare = package ? participant[split + 2:] : participant;
  String binding = %"$(base_name)_$infix$(bare.lower())";
  return package ? %"$(package)__$binding" : binding;
}

/* publication

   A published node installs its row in the unit's registry and, in a
   generated context, retains the node in `Sym` for replay. */

/** Validates and installs one normalized protocol or adoption node.
    The node must carry a protocol record or supported adoption shape with its
    storage and source location. Installation invalidates cached protocol
    decisions and returns the canonical published node. Generated contexts may
    also retain that node in `Sym` for replay. A `(meta-protocol ADOPTION)`
    node publishes its adoption and marks it for compile-time code.
*/
List Compiler.publish_protocol_node(
  Compiler c, List node, Token participant_token,
  Token representation_token) {
  match (node) {
    case %(meta-protocol ?(List adoption)): {
      List published = c.publish_protocol_node(
        adoption, participant_token, representation_token);
      _retain_meta_protocol(c, published);
      return published;
    }
    case %(protocol
           (!set ?record
             ("protocol-record"
               ?(List base) (!is ? type string)
               (associated *) (members *)))
           external ?(List location)):
      return _publish_record(c, record, base, location);
  }
  return _publish_adoption(c, node, participant_token, representation_token);
}

static List _publish_adoption(
  Compiler c, List node, Token participant_token, Token modifier_token) {
  match (node)
    case %(adopt ?(List base) ?(List participant) (!or external static)
           *modifier ?(List location))
        if (!modifier || (base === %("Var") && !modifier.cdr() &&
                          modifier.car() is <list>)): {
      AdoptionDraft draft = {
        .c = c, .base = base, .participant = participant,
        .storage = _adoption_storage(node),
        .representation = _adoption_representation(node),
        .tag_expression = _adoption_tag(node), .location = location,
        .participant_token = participant_token,
        .modifier_token = modifier_token};
      return _publish(draft);
    }
  $fail.protocol_protocol_invalid(c, c.token);
}

module List _publish_record(
  Compiler c, List record, Type base, List location) {
  Symbol storage = c.source_private > 0 ? <static> : <external>;
  _install_occurrence(c, base, record, storage, location);
  c.proto_cache = {};
  List published = %(protocol $record $storage $location);
  _retain_source_node(c, published, storage, location);
  return published;
}

/* A `meta` adoption lets compile-time code call the conformance's
   witnesses. Its row travels beside the adoption row it marks. */
static void _retain_meta_protocol(Compiler c, List adoption) {
  Type (base, participant) = adoption.cdr();
  _retain_source_node(
    c, %(meta-protocol $base $participant), _adoption_storage(adoption),
    %(meta-protocol @(_adoption_location(adoption))));
}

static void _retain_source_node(
  Compiler c, List node, Symbol storage, List location) {
  List invocation = c.origin_location(c.origin);
  if (!invocation &&
      (!c.shallow ||
       (storage == <static> && c.source_private < 0)))
    return;
  List key = _source_key(c, location);
  c.sym.set(key, node);
  if (storage == <static>) c.sym.mark_static(key);
}

// Keep definition provenance in a generated node while its invocation site
// makes repeated expansions distinct in the retained symbol table.
static List _source_key(Compiler c, List location) {
  List invocation = c.origin_location(c.origin);
  return invocation
       ? $("source-node", location, invocation)
       : $("source-node", location);
}

static void _install_occurrence(
  Compiler c, Type base, List record, Symbol storage, List location) {
  String file = _canonical_file(c, location);
  if (storage == <static> && file != _path(c)) return;
  Var stored;
  if (!c.protocols.try_get(base, stored)) {
    c.protocols[base] = _occurrence(record, storage, location);
    return;
  }
  List occurrence = stored, existing = occurrence.car();
  if (existing == record) {
    if (_canonical_file(c, _occurrence_location(occurrence)) == file &&
        storage == <static> &&
        _occurrence_storage(occurrence) != <static>)
      c.protocols[base] = _occurrence(record, storage, location);
    return;
  }
  String first_location = _location_string(_occurrence_location(occurrence));
  String second_location = _location_string(location);
  if (first_location.compare(second_location) > 0) {
    String swap = first_location;
    first_location = second_location;
    second_location = swap;
  }
  $fail.protocol_decl_conflict(
    c, c.token, base, first_location, second_location);
}

// adoption drafts

static List _publish(AdoptionDraft &a) {
  Compiler c = a.c;
  if (a.tag_expression) a.tag_expression = _tag_syntax(a.tag_expression);
  String spelling = a.participant.car().str();
  List declared = c.sym.get($(spelling));
  if ((!declared || !declared.type().is_typedef()) && !c.shallow)
    $fail.protocol_type_undeclared(c, a.participant_token, spelling);
  a.tag = _check_modifiers(a);
  a.storage = _published_storage(a, spelling);
  _check_previous(a);
  _install(a);
  // An adoption resolved when the parse began has reported its failures.
  List pair = $(a.base, a.participant);
  int resolved = pair in c.conforms;
  c.conforms.del(pair);
  c.proto_cache = {};
  if (!c.shallow)
    _resolve_adoption(c, a.base, a.participant, resolved ? NULL : a.location);
  List published = _node(a);
  // A generated class declares several adoptions at one location.
  _retain_source_node(
    c, published, a.storage, %(adopt $(a.base) @(a.location)));
  return published;
}

static List _node(AdoptionDraft &a) => _adoption_node(
  a.base, a.participant, a.storage, a.representation, a.tag_expression,
  a.location);

static List _tag_syntax(List expression) {
  match (expression) {
    case %(src ? ?(List syntax)):
      return _tag_syntax(syntax);
    case %(expr (<macro-expr>) ?(List syntax)):
      return _tag_syntax(syntax);
  }
  return expression;
}

static Symbol _check_modifiers(AdoptionDraft &a) {
  Type representation = a.representation;
  if (representation && !representation.fixed_var_tag())
    _report_modifier(a, _representation_error(representation));
  if (!a.tag_expression) return 0;
  Symbol tag = _tag_value(a.tag_expression);
  if (!tag) _report_modifier(a, "Var adoption tag must be a Symbol literal");
  return tag;
}

/* A constructed adoption has no modifier token, so its diagnostic goes to
   the adoption's location. */
static void _report_modifier(AdoptionDraft &a, String message) {
  if (a.modifier_token)
    a.c.report_error(<protocol>, message, a.modifier_token, NULL);
  else
    a.c.diagnostics.report(<protocol>, message, a.location, NULL);
}

module Symbol _tag_value(List expression) {
  match (expression)
    case %(expr ("Symbol") $($source_literal_content(%(("Symbol") ? ?tag)))):
      if (tag is <symbol>) return tag;
  return 0;
}

static Symbol _published_storage(
  AdoptionDraft &a, String spelling) {
  Compiler c = a.c;
  if (a.storage == <static>) return <static>;
  if (c.source_private < 0) return a.storage;
  List record = _record(c, a.base);
  int private_native = record &&
    _has_private_native(c, record.last().list().cdr());
  String base_name = _base_name(a.base);
  String forward =
    base_name ? _member_spelling(a.participant, base_name.lower()) : NULL;
  String reverse = base_name
    ? c.reverse_converter_spelling(base_name, "", spelling) : NULL;
  String alternate = base_name
    ? c.reverse_converter_spelling(base_name, "as_", spelling) : NULL;
  Var occurrence_value;
  List occurrence = c.protocols.try_get(a.base, occurrence_value)
    ? occurrence_value : NULL;
  int private = c.source_private > 0 ||
    (occurrence && _occurrence_storage(occurrence) == <static>) ||
    _is_private(c, spelling) ||
    (forward && _is_private(c, forward)) ||
    (reverse && _is_private(c, reverse)) ||
    (alternate && _is_private(c, alternate)) ||
    private_native;
  return private ? <static> : a.storage;
}

static int _has_private_native(Compiler c, List templates) {
  foreach (List template in templates) {
    String binding = template.caddr();
    if (binding && _is_private(c, binding)) return 1;
  }
  return 0;
}

static void _check_previous(AdoptionDraft &a) {
  Compiler c = a.c;
  if (c.shallow) return;
  String path = _canonical_file(c, a.location);
  List key = $("parsed-protocol-adoption", a.base, a.participant, path);
  Var previous;
  if (!c.protocol_helpers.try_get(key, previous)) {
    c.protocol_helpers[key] = _node(a);
    return;
  }
  List row = previous;
  if (_adoption_representation(row) == a.representation &&
      _adoption_tag(row) == a.tag_expression) return;
  $report.protocol_adoption_conflict(c, a.location, a, row);
}

static void _install(AdoptionDraft &a) {
  Compiler c = a.c;
  String path = _canonical_file(c, a.location);
  if (a.storage == <static> && path != _path(c)) return;
  a.participant.register_var_adoption(a.representation, a.tag);
  List key = a.storage == <static>
           ? $(a.base, a.participant, path)
           : $(a.base, a.participant);
  List row = _node(a);
  Var stored;
  if (!c.adoptions.try_get(key, stored)) {
    c.adoptions[key] = row;
    return;
  }
  List existing = stored;
  if (existing == row) return;
  List first_location = _adoption_location(existing);
  if (_canonical_file(c, first_location) == path) return;
  $fail.protocol_adoption_conflict(c, c.token, a, first_location);
}

// registry lifecycle

/** Rebuilds the per-unit protocol and adoption registries from `symbols`.
    Existing rows, helper decisions, and lookup caches are discarded; a null
    map leaves those registries empty. The conformance rows included
    interfaces recorded are kept for reuse. Conformance reset and resolution
    belong to `resolve_protocols`.
*/
void Compiler.rebuild_protocols(Compiler c, Map symbols) {
  c.protocols = {};
  c.adoptions = {};
  c.protocol_helpers = {};
  c.proto_cache = {};
  if (!symbols) return;
  foreach (Var value in symbols) {
    if (value is not <list>) continue;
    match (value) {
      case %(protocol
             (!set ?record ("protocol-record" ?base *))
             ?storage ?location): {
        _install_occurrence(c, base, record, storage, location);
      }
      case %(adopt *): _install_stored(c, value);
      case %(conformance ?base ?participant *):
        c.protocol_helpers[$("recorded-conformance", base, participant)] =
          value;
    }
  }
}

static void _install_stored(Compiler c, List value) {
  match (value) {
    case %(adopt ?base ?participant ?storage ?location): {
      AdoptionDraft draft = {
        .c = c, .base = base, .participant = participant,
        .storage = storage, .location = location};
      _install(draft);
    }
    case %(adopt ?base ?participant ?storage
             (tag (!set ?tag_expression (expr ("Symbol")
               $($source_literal_content(%(("Symbol") ? ?candidate))))))
             ?location) if (candidate is <symbol>): {
      Symbol tag = candidate;
      AdoptionDraft draft = {
        .c = c, .base = base, .participant = participant,
        .storage = storage, .tag = tag,
        .tag_expression = tag_expression, .location = location};
      _install(draft);
    }
    case %(adopt ?base ?participant ?storage ?representation ?location): {
      AdoptionDraft draft = {
        .c = c, .base = base, .participant = participant,
        .storage = storage, .representation = representation,
        .location = location};
      _install(draft);
    }
  }
}
