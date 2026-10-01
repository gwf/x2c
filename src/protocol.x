/*  protocol.x -- Protocol collection and per-unit semantic registry

    Copyright (c) 2025 Gary William Flake.

    This module carries protocol and adoption rows from parsing through
    resolved conformance and generated adapters. Registries are rebuilt per
    translation unit; static rows are visible only when their canonical
    source path is the current unit.
*/
#pragma once
#include "compiler.x"
#pragma private
$(import "../src/grammar.xmacro")

#include <limits.h>
#include <stdlib.h>
#include <string.h>
#include "collect.x"
#include "expressions.x"
#include "parse.x"
#include "meta.x"

macro Decorator $guard_value_rendering(
  Function $function, Name $path, Expr $enter, Expr $fallback,
  Expr $leave, Statement $body...) {
  RenderPath $path;
  if (!$enter) return $fallback;
  defer $leave;
  $body...
}

/* A relative path names a file below the working directory, or else one below
   the x2c root, where `Compiler.display_path` spells root sources. */
static String _normalize_file(Compiler compiler, String file) {
  char path[PATH_MAX], String root = compiler.root_dir;
  if (realpath(file, path) ||
      (root && file[0] != '/' && realpath(%"$root/$file", path)))
    file = path;
  return compiler.display_path(file);
}

static String _path(Compiler compiler) {
  Var cached;
  if (compiler.protocol_helpers.try_get(<proto-path>, cached)) return cached;
  String result = _normalize_file(
    compiler, compiler.filename ? compiler.filename : "<stdin>");
  compiler.protocol_helpers[<proto-path>] = result;
  return result;
}

static int _lexically_private(Compiler compiler) =>
  compiler.source_private > 0;

static void _mark_private(
  Compiler compiler, Symbol kind, String name) {
  (void) kind;
  compiler.sym.mark_static(%($name));
}

static int _declaration_is_private(
  Compiler compiler, Symbol kind, String name) {
  (void) kind;
  return %($name) in compiler.sym.file_statics();
}

static void _record_declaration_binding_visibility(
  Compiler compiler, List declaration, Symbol kind, int private, int mark,
  List identity) {
  String name = binding_identity_spelling(identity);
  if (kind == <typedef> && name)
    compiler.protocol_helpers[%(
      "source-typedef" $name
    )] = %($declaration $private);
  if (mark && name)
    _mark_private(
      compiler, kind == <typedef> ? <type> : <binding>, name);
}

static void _record_rows_visibility(
  Compiler compiler, List declaration, Symbol kind, int private, int mark,
  List rows) {
  foreach (List row, rows) match (row) {
    case %(bind ?identity *):
      _record_declaration_binding_visibility(
        compiler, declaration, kind, private, mark, identity);
    case %(op = (bind ?identity *) ?):
      _record_declaration_binding_visibility(
        compiler, declaration, kind, private, mark, identity);
  }
}

/** Records the visibility of one parsed top-level declaration.
    Lexical privacy and static storage mark bindings in `Sym`; typedef rows are
    retained for placing generated protocol declarations at the same boundary.
*/
void Compiler.record_declaration_visibility(Compiler c, List declaration) {
  int private = _lexically_private(c);
  match (declaration) {
    case %(seq *rows):
      foreach (List row, rows) c.record_declaration_visibility(row);
    case %(function ?type (bind ?identity *) *): {
      if (!private && !type.type().is_static()) return;
      String name = binding_identity_spelling(identity);
      if (name) _mark_private(c, <binding>, name);
    }
    case %(
      (!set ?kind (!or typedef declare)) ?type (bindings *rows)
    ): {
      int mark = private || type.type().is_static();
      _record_rows_visibility(c, declaration, kind, private, mark, rows);
    }
  }
}

/* Protocol occurrences retain the declaration record with its linkage and
   source location. Adoption rows use base, participant, and, for static rows,
   canonical source path as identity so another unit cannot consume them. */
static List _occurrence(List record, Symbol storage, List location) =>
  %( $record $storage $location );

static Symbol _occurrence_storage(List occurrence) => occurrence.cadr();

static List _occurrence_location(List occurrence) => occurrence.caddr();

static Symbol _adoption_storage(List adoption) => adoption.cddr().cadr();

// A row without a representation or a tag has five fields.
static Type _adoption_representation(List adoption) {
  match (adoption) {
    case %(adopt ? ? ? (tag ?) ?): return NULL;
    case %(adopt ? ? ? ?representation ?): return representation;
  }
  return NULL;
}

static List _adoption_tag(List adoption) {
  match (adoption) case %(adopt ? ? ? (tag ?tag) ?): return tag;
  return NULL;
}

static List _protocol_tag_syntax(List expression) {
  match (expression) {
    case %(src ? ?(List syntax)):
      return _protocol_tag_syntax(syntax);
    case %(expr (<macro-expr>) ?(List syntax)):
      return _protocol_tag_syntax(syntax);
  }
  return expression;
}

static Symbol _protocol_tag_value(List expression) {
  match (expression)
    case %(expr ("Symbol") ?content):
      match (content)
        case $source_literal_content(%(("Symbol") ? ?tag)):
          if (tag is <symbol>) return tag;
  return 0;
}

static List _adoption_node(
  Type base, Type participant, Symbol storage, Type representation,
  List tag, List location) {
  if (representation)
    return %(adopt $base $participant $storage $representation $location);
  if (tag) return %(adopt $base $participant $storage (tag $tag) $location);
  return %(adopt $base $participant $storage $location);
}

static List _adoption_location(List adoption) => adoption.last();

static String _location_file(List location) {
  Var file = location ? location.assoc(<file>) : void;
  return file is <string> ? file : "<unknown>";
}

static String _canonical_file(Compiler compiler, List location) {
  String file = _location_file(location);
  List key = %(proto-file $file);
  Var cached;
  if (compiler.protocol_helpers.try_get(key, cached)) return cached;
  String result = _normalize_file(compiler, file);
  compiler.protocol_helpers[key] = result;
  return result;
}

static String _location_string(List location) {
  String file = _location_file(location);
  Var line = location ? location.assoc(<line>) : void;
  Var column = location ? location.assoc(<column>) : void;
  return %"$file:${line.is_integer() ? line.integer() : 1}:${
    column.is_integer() ? column.integer() : 1}";
}

static List _adoption_row(
  Compiler compiler, Type base, Type participant, Symbol storage) {
  String path = _path(compiler);
  List key = storage == <static>
           ? %($base $participant $path)
           : %($base $participant);
  Var stored;
  return compiler.adoptions.try_get(key, stored)
       ? stored : NULL;
}

static Symbol _adoption_visibility(
  Compiler compiler, Type base, Type participant) {
  List external =
    _adoption_row(compiler, base, participant, <external>);
  List local = _adoption_row(compiler, base, participant, <static>);
  if (external && local) {
    if (_canonical_file(
      compiler, _adoption_location(external)) ==
        _canonical_file(compiler, _adoption_location(local)))
      return <static>;
    return <mixed>;
  }
  if (local) return <static>;
  if (external) return <external>;
  return 0;
}

static List _visible_adoption_row(
  Compiler compiler, Type base, Type participant) {
  List local = _adoption_row(compiler, base, participant, <static>);
  return local
       ? local
       : _adoption_row(compiler, base, participant, <external>);
}

static int _adoption_owned(
  Compiler compiler, Type base, Type participant) {
  List row = _visible_adoption_row(compiler, base, participant);
  return row &&
         _canonical_file(
           compiler, _adoption_location(row)) ==
           _path(compiler);
}

static void Compiler._install_protocol_occurrence(
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
    if (_canonical_file(
      c, _occurrence_location(occurrence)) == file &&
        storage == <static> &&
        _occurrence_storage(occurrence) != <static>)
      c.protocols[base] =
        _occurrence(record, storage, location);
    return;
  }
  String first_location = _location_string(
    _occurrence_location(occurrence));
  String second_location = _location_string(location);
  if (first_location.compare(second_location) > 0) {
    String swap = first_location;
    first_location = second_location;
    second_location = swap;
  }
  String first = %"first: $first_location";
  String second = %"second: $second_location";
  c.report_error(
    <protocol>, %"conflicting protocol declarations for ${base.repr()}",
    c.token, %($first $second));
}

typedef struct AdoptionDraft {
  Compiler c;
  Type base, participant, representation;
  Symbol storage, tag;
  List tag_expression, location;
  Token participant_token, modifier_token;
} AdoptionDraft;

static void _install_stored_adoption(Compiler compiler, List value) {
  match (value) {
    case %(adopt ?base ?participant ?storage ?location): {
      AdoptionDraft draft = {
        .c = compiler, .base = base, .participant = participant,
        .storage = storage, .location = location};
      draft.install();
    }
    case %(adopt ?base ?participant ?storage
             (tag (!set ?tag_expression (expr ("Symbol")
               ${$source_literal_content(%(("Symbol") ? ?candidate))})))
             ?location) if (candidate is <symbol>): {
      Symbol tag = candidate;
      AdoptionDraft draft = {
        .c = compiler, .base = base, .participant = participant,
        .storage = storage, .tag = tag,
        .tag_expression = tag_expression, .location = location};
      draft.install();
    }
    case %(adopt ?base ?participant ?storage ?representation ?location): {
      AdoptionDraft draft = {
        .c = compiler, .base = base, .participant = participant,
        .storage = storage, .representation = representation,
        .location = location};
      draft.install();
    }
  }
}

/** Rebuilds the per-unit protocol and adoption registries from `symbols`.
    Existing rows, helper decisions, and lookup caches are discarded; a null
    map leaves those registries empty. Conformance reset and resolution belong
    to `resolve_protocols`.
*/
void Compiler.rebuild_protocols(Compiler compiler, Map symbols) {
  compiler.protocols = {};
  compiler.adoptions = {};
  compiler.protocol_helpers = {};
  compiler.proto_cache = {};
  if (!symbols) return;
  foreach (Var value, symbols) {
    if (value is not <list>) continue;
    match (value) {
      case %(protocol
             (!set ?record ("protocol-record" ?base *))
             ?storage ?location): {
        compiler._install_protocol_occurrence(
          base, record, storage, location);
      }
      case %(adopt *): _install_stored_adoption(compiler, value);
    }
  }
}

static void AdoptionDraft.install(AdoptionDraft *a) {
  Compiler compiler = a.c;
  Type base = a.base, participant = a.participant;
  Symbol storage = a.storage;
  List location = a.location;
  String path = _canonical_file(compiler, location);
  if (storage == <static> && path != _path(compiler)) return;
  participant.register_var_adoption(a.representation, a.tag);
  List key = storage == <static>
           ? %($base $participant $path)
           : %($base $participant);
  List row = _adoption_node(
    base, participant, storage, a.representation, a.tag_expression, location);
  Var stored;
  if (!compiler.adoptions.try_get(key, stored)) {
    compiler.adoptions[key] = row;
    return;
  }
  List existing = stored;
  if (existing == row) return;
  List first_location = _adoption_location(existing);
  if (_canonical_file(compiler, first_location) == path) return;
  String first = %"first: ${_location_string(first_location)}";
  String second = %"second: ${_location_string(location)}";
  String base_name = _type_spelling(base);
  String participant_name = _type_spelling(participant);
  String detail = %"$base_name($participant_name)";
  compiler.report_error(
    <protocol>, %"conflicting adoption declarations for $detail",
    compiler.token, %($first $second));
}

static int _has_private_native(Compiler compiler, List templates) {
  foreach (List template, templates) {
    String binding = template.caddr();
    if (binding && _declaration_is_private(
      compiler, <binding>, binding))
      return 1;
  }
  return 0;
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
  String binding = %"${base_name}_$infix${bare.lower()}";
  return package ? %"${package}__$binding" : binding;
}

static List Compiler._record(Compiler compiler, Type base) {
  Var stored;
  if (!compiler.protocols.try_get(base, stored)) return NULL;
  List occurrence = stored;
  return occurrence.car();
}

// Keep definition provenance in a generated node while its invocation site
// makes repeated expansions distinct in the retained symbol table.
static List _generated_source_key(Compiler compiler, List location) {
  List invocation = compiler.origin_location(compiler.origin);
  return invocation
       ? %("source-node" $location $invocation)
       : %("source-node" $location);
}

static void Compiler._retain_protocol_source_node(
  Compiler compiler, List node, Symbol storage, List location) {
  List invocation = compiler.origin_location(compiler.origin);
  if (!invocation &&
      (!compiler.shallow ||
       (storage == <static> && compiler.source_private < 0)))
    return;
  List key = _generated_source_key(compiler, location);
  compiler.sym.set(key, node);
  if (storage == <static>) compiler.sym.mark_static(key);
}

/* A `meta` adoption lets compile-time code call the conformance's
   witnesses. Its row travels beside the adoption row it marks. */
static void Compiler._retain_meta_protocol(Compiler c, List adoption) {
  Type (base, participant) = adoption.cdr();
  c._retain_protocol_source_node(
    %(meta-protocol $base $participant), _adoption_storage(adoption),
    %(meta-protocol @{_adoption_location(adoption)}));
}

static List Compiler._publish_protocol_record(
  Compiler compiler, List record, Type base, List location) {
  Symbol storage = compiler.source_private > 0 ? <static> : <external>;
  compiler._install_protocol_occurrence(base, record, storage, location);
  compiler.proto_cache = {};
  List published = %(protocol $record $storage $location);
  compiler._retain_protocol_source_node(published, storage, location);
  return published;
}

static Symbol _check_adoption_modifier(
  Compiler c, Type representation, List tag_expression, List location,
  Token modifier_token) {
  if (representation && !representation.fixed_var_tag()) {
    if (modifier_token)
      c.report_error(
        <protocol>, _representation_error(representation),
        modifier_token, NULL);
    else
      c.diagnostics.report(
        <protocol>, _representation_error(representation), location, NULL);
  }
  if (!tag_expression) return 0;
  Symbol tag = _protocol_tag_value(tag_expression);
  if (tag) return tag;
  if (modifier_token)
    c.report_error(
      <protocol>, "Var adoption tag must be a Symbol literal",
      modifier_token, NULL);
  else
    c.diagnostics.report(
      <protocol>, "Var adoption tag must be a Symbol literal",
      location, NULL);
  return 0;
}

static Symbol _published_storage(
  Compiler c, Type base, String spelling, Symbol storage) {
  if (storage == <static>) return <static>;
  if (c.source_private < 0) return storage;
  List record = c._record(base);
  int private_native = record &&
    _has_private_native(c, record.last().list().cdr());
  String base_name = _base_name(base);
  String forward = base_name ? %"${spelling}_${base_name.lower()}" : NULL;
  String reverse = base_name
    ? c.reverse_converter_spelling(base_name, "", spelling) : NULL;
  String alternate = base_name
    ? c.reverse_converter_spelling(base_name, "as_", spelling) : NULL;
  Var occurrence_value;
  List occurrence = c.protocols.try_get(base, occurrence_value)
    ? occurrence_value : NULL;
  int private = _lexically_private(c) ||
    (occurrence && _occurrence_storage(occurrence) == <static>) ||
    _declaration_is_private(c, <type>, spelling) ||
    (forward && _declaration_is_private(c, <binding>, forward)) ||
    (reverse && _declaration_is_private(c, <binding>, reverse)) ||
    (alternate && _declaration_is_private(c, <binding>, alternate)) ||
    private_native;
  return private ? <static> : storage;
}

static void AdoptionDraft.check_previous(AdoptionDraft *a) {
  Compiler c = a.c;
  Type base = a.base, participant = a.participant;
  List location = a.location;
  if (c.shallow) return;
  String path = _canonical_file(c, location);
  List key = %("parsed-protocol-adoption" $base $participant $path);
  Var previous;
  if (!c.protocol_helpers.try_get(key, previous)) {
    c.protocol_helpers[key] = _adoption_node(
      base, participant, a.storage, a.representation,
      a.tag_expression, location);
    return;
  }
  List row = previous;
  Type first_representation = _adoption_representation(row);
  List first_tag = _adoption_tag(row);
  if (first_representation == a.representation &&
      first_tag.equal(a.tag_expression)) return;
  List first_location = _adoption_location(row);
  String first = %"first: ${_location_string(first_location)}";
  String second = %"second: ${_location_string(location)}";
  String detail = %"${_type_spelling(base)}(${
    _type_spelling(participant)})";
  c.diagnostics.report(
    <protocol>, %"conflicting adoption declarations for $detail",
    location, %($first $second));
}

static List AdoptionDraft.publish(AdoptionDraft *a) {
  Compiler c = a.c;
  Type base = a.base, participant = a.participant;
  List location = a.location;
  if (a.tag_expression)
    a.tag_expression = _protocol_tag_syntax(a.tag_expression);
  String spelling = participant.car().str();
  List declared = c.sym.get(%($spelling));
  if ((!declared || !declared.type().is_typedef()) && !c.shallow)
    c.report_error(
      <protocol>,
      %"adoption participant '$spelling' does not name a declared type",
      a.participant_token, NULL);
  a.tag = _check_adoption_modifier(
    c, a.representation, a.tag_expression, location, a.modifier_token);
  a.storage = _published_storage(c, base, spelling, a.storage);
  a.check_previous();
  a.install();
  // An adoption resolved when the parse began has reported its failures.
  int resolved = %($base $participant) in c.conforms;
  c.conforms.del(%($base $participant));
  c.proto_cache = {};
  if (!c.shallow)
    _resolve_declared_adoption(
      c, base, participant, resolved ? NULL : location);
  List published = _adoption_node(
    base, participant, a.storage, a.representation,
    a.tag_expression, location);
  // A generated class declares several adoptions at one location.
  c._retain_protocol_source_node(
    published, a.storage, %(adopt $base @location));
  return published;
}

static List _publish_var_adoption_node(
  Compiler c, List node, Token participant_token, Token modifier_token) {
  match (node) {
    case %(adopt
           ("Var") ?(List participant)
           (!set ?storage (!or external static))
           (tag ?(List tag))
           ?(List location)): {
      AdoptionDraft draft = {
        .c = c, .base = %("Var"), .participant = participant,
        .storage = storage, .tag_expression = tag, .location = location,
        .participant_token = participant_token,
        .modifier_token = modifier_token};
      return draft.publish();
    }
    case %(adopt
           ("Var") ?(List participant)
           (!set ?storage (!or external static))
           ?(List representation)
           ?(List location)): {
      AdoptionDraft draft = {
        .c = c, .base = %("Var"), .participant = participant,
        .storage = storage, .representation = representation,
        .location = location, .participant_token = participant_token,
        .modifier_token = modifier_token};
      return draft.publish();
    }
  }
  c.report_error(
    <macro>, "constructed protocol syntax is invalid",
    c.token, NULL);
}

static List _publish_adoption_node(
  Compiler c, List node, Token participant_token, Token modifier_token) {
  match (node)
    case %(adopt
           ?(List base) ?(List participant)
           (!set ?storage (!or external static))
           ?(List location)): {
      AdoptionDraft draft = {
        .c = c, .base = base, .participant = participant,
        .storage = storage, .location = location,
        .participant_token = participant_token,
        .modifier_token = modifier_token};
      return draft.publish();
    }
  return _publish_var_adoption_node(
    c, node, participant_token, modifier_token);
}

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
      c._retain_meta_protocol(published);
      return published;
    }
    case %(protocol
           (!set ?record
             ("protocol-record"
               ?(List base) (!is ? type string)
               (associated *) (members *)))
           external ?(List location)):
      return c._publish_protocol_record(record, base, location);
  }
  return _publish_adoption_node(
    c, node, participant_token, representation_token);
}

// Participation exists only for a declared adoption row.
static int Compiler._is_adopted(
  Compiler compiler, Type base, Type participant) =>
    !!_adoption_visibility(compiler, base, participant);

static int _function_parts(
  Type signature, List &parameters, Type &result) {
  match (signature)
    case %((func ?arguments) *return_type): {
      parameters = arguments;
      result = return_type;
      return 1;
    }
  return 0;
}

static String _type_variable(Var value, Map variables) {
  String name = NULL;
  if (value is <string>) name = value;
  match (value)
    case %(?(String only)): name = only;
  if (!name) return NULL;
  return name in variables ? name : NULL;
}

static int _unify(
  Var pattern, Var actual, Map variables, Map bindings) {
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
  while (left && right) {
    if (!_unify(left.car(), right.car(), variables, bindings))
      return 0;
    left = left.cdr();
    right = right.cdr();
  }
  return !left && !right;
}

static int _unify_signature(
  Type pattern, Type actual, Map variables, Map bindings) {
  List pattern_parameters = pattern.car().list().cadr();
  Type pattern_result = pattern.cdr();
  List actual_parameters = NULL;
  Type actual_result = NULL;
  if (!_function_parts(actual, actual_parameters, actual_result))
    return 0;
  while (pattern_parameters && actual_parameters) {
    if (!_unify(
      pattern_parameters.car(), actual_parameters.car(),
      variables, bindings))
      return 0;
    pattern_parameters = pattern_parameters.cdr();
    actual_parameters = actual_parameters.cdr();
  }
  if (pattern_parameters || actual_parameters) return 0;
  return _unify(pattern_result, actual_result, variables, bindings);
}

static Var _substitute(Var value, Map variables, Map bindings) {
  String variable = _type_variable(value, variables);
  if (variable) return bindings[variable];
  if (value is not <list>) return value;
  Array output = [];
  foreach (Var item, value.list())
    output.push(_substitute(item, variables, bindings));
  return output.list_free();
}

static Type _substitute_signature(
  Type signature, Map variables, Map bindings) {
  List parameters = signature.car().list().cadr();
  Type result = signature.cdr();
  List parameter_types = parameters.map(
    %!(Var parameter) =>
      _substitute(parameter, variables, bindings));
  Type result_type = _substitute(result, variables, bindings);
  return %((func $parameter_types) @result_type);
}

static int _exact_conversion(
  Type signature, Type parameter, Type result) {
  List parameters = NULL, Type actual_result = NULL;
  if (!_function_parts(signature, parameters, actual_result))
    return 0;
  return parameters && !parameters.cdr() &&
         parameters.car() == parameter &&
         actual_result == result;
}

static String _base_name(Type base) =>
  base.is_bare_typedef_name() ? base.car() : NULL;

// Prefer a typedef's bare diagnostic spelling.
static String _type_spelling(Type type) =>
  type.is_bare_typedef_name() ? type.car() : type.repr();

static String _member_spelling(Type participant, String member) =>
  %"${participant.car()}_$member";

static String _representation_error(Type representation) {
  String spelling = _type_spelling(representation);
  return %"Var representation $spelling has no fixed tag";
}

static Type _declared(Compiler compiler, String name) {
  if (compiler.sym.get(%("generated-protocol" $name)))
    return NULL;
  return compiler.sym.get(%($name));
}

/* A bodyless, non-static prototype of a member whose base default the
   visible forward converter generates declares that default rather than
   implementing the member. */
static int _default_completes(
  Compiler compiler, String name, Type declared, String forward) =>
  forward && declared.is_function() && forward in compiler.fn_defs &&
  !compiler.fn_defs.contains(name) &&
  !compiler.sym.file_statics().contains(%(function $name));

static List _inherited_parameters(
  List parameters, Type owner, Type participant) {
  if (!parameters) return NULL;
  Var parameter = parameters.car();
  return cons(
    parameter == owner ? participant : parameter,
    _inherited_parameters(parameters.cdr(), owner, participant));
}

static Type _receiver_relative_signature(
  Compiler compiler, List binding, Type signature, Type receiver) {
  Var stored;
  if (!compiler.semantic_binding_facts().try_get(%(self $binding), stored))
    return signature;
  Type relative = stored, base = receiver.canonicalize().base_type();
  return relative.search_replace(<self>, base.car());
}

static Type _method_signature(
  Compiler compiler, Type owner, Type participant, String member,
  String &selected) {
  if (!owner.is_bare_typedef_name()) return NULL;
  String source = _member_spelling(owner, member);
  Type signature = _declared(compiler, source);
  if (!signature) {
    String imported = compiler.imported_spelling(source);
    if (imported) {
      signature = _declared(compiler, imported);
      if (signature) source = imported;
    }
  }
  if (!signature) return NULL;

  List binding = compiler.sym.reference(%($source), NULL);
  signature = _receiver_relative_signature(
    compiler, binding, signature, participant);
  List parameters = NULL, Type result = NULL;
  if (_function_parts(signature, parameters, result) &&
      parameters && parameters.car() == owner) {
    parameters = _inherited_parameters(
      parameters, owner, participant);
    signature = %((func $parameters) @result);
  }
  selected = source;
  return signature;
}

#define PROTOCOL_VARIABLE 1
#define PROTOCOL_VARIADIC 2

static int _contents(Var value, String variable) {
  if (value is <string>)
    return value == variable ? PROTOCOL_VARIABLE : 0;
  if (value == <...>) return PROTOCOL_VARIADIC;
  if (value is not <list>) return 0;
  int contents = 0;
  foreach (Var item, value.list())
    contents |= _contents(item, variable);
  return contents;
}

static int _is_exact_variable(Var value, String variable) {
  if (value is not <list>) return 0;
  List type = value;
  return type && !type.cdr() && type.car() is <string> &&
         type.car() == variable;
}

static int _is_native(List templates) {
  foreach (List template, templates)
    if (template.caddr().str()) return 1;
  return 0;
}

static int _native_parameter_conversion(
  Type participant_definition, Type base) {
  if (participant_definition == base) return 1;
  return participant_definition.canonicalize() == base.canonicalize();
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
      !_native_parameter_conversion(participant_definition, base))
    return %($member native parameter implicit);
  if ((_contents(result, binder) & PROTOCOL_VARIABLE) &&
      participant_definition != base)
    return %($member native result implicit);
  return NULL;
}

static Type _participant_definition(
  Compiler compiler, Type participant) {
  if (!participant.is_bare_typedef_name()) return NULL;
  String name = participant.car();
  Var definition = compiler.sym.global_symbols()[%(typedef $name)];
  return definition is <list> ? definition : NULL;
}

static void _install_native_bindings(
  Compiler compiler, Type participant, List rows) {
  match (rows)
    case %((? native *) *): {
      foreach (List row, rows)
        match (row)
          case %(?(String member) ? ? ? ? ?(Type signature)): {
            String generated = _member_spelling(participant, member);
            if (!compiler.sym.get(%($generated)))
              compiler.sym.define_global(%($generated), signature);
          }
    }
}

/* Native and ordinary resolution are the only conformance-row producers. A
   row carries base, participant, converters, type-variable maps, and member
   rows of `(name status source expected default-kind template)`. Consumers
   dispatch on `status`; a non-list cache value records failed resolution. */
typedef struct ProtocolRequirements {
  String binder;
  List associations, templates;
} ProtocolRequirements;

typedef struct NativeResolution {
  Type base, participant, definition;
  String binder;
  Map variables, bindings;
} NativeResolution;

static List NativeResolution.rows(
  NativeResolution *r, List templates, List &failure) {
  Array members = [];
  Map native_bindings = NULL;
  foreach (List template, templates) {
    (String member, Type type, String native) = template;
    List requirement = _native_requirement(
      member, native, type, r.binder, r.definition, r.base);
    if (requirement) {
      failure = requirement;
      members.free();
      return NULL;
    }
    Type expected = _substitute_signature(
      type, r.variables, r.bindings);
    if (r.definition != r.base && native_bindings == NULL) {
      native_bindings = r.bindings.copy();
      native_bindings[r.binder] = r.base;
    }
    Type alias_signature = r.definition == r.base ? expected
      : _substitute_signature(type, r.variables, native_bindings);
    members.push(
      %($member native $native $expected none $alias_signature));
  }
  return members.list_free();
}

static List Compiler._resolve_native_protocol_participant(
  Compiler c, Type base, Type participant, ProtocolRequirements *requirements,
  Type participant_definition, List &failure) {
  failure = NULL;
  List key = %($base $participant);
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
  foreach (List association, requirements.associations) {
    (String association_name, Type binding) = association;
    resolution.variables[association_name] = 1;
    resolution.bindings[association_name] = binding;
  }
  List rows = resolution.rows(requirements.templates, failure);
  if (failure) {
    c.conforms[key] = 0;
    return NULL;
  }
  List conformance = %(
    protocol-conformance $base $participant "" ""
    ${resolution.variables} ${resolution.bindings} (members @rows)
  );
  c.conforms[key] = conformance;
  return conformance;
}

static String _reverse_binding(
  Compiler compiler, Type base, Type participant) {
  String base_name = _base_name(base);
  if (!base_name || !participant.is_bare_typedef_name()) return NULL;
  String participant_name = participant.car();
  String conventional =
    compiler.reverse_converter_spelling(base_name, "", participant_name);
  Type found = _declared(compiler, conventional);
  if (_exact_conversion(found, base, participant)) return conventional;
  String alternate =
    compiler.reverse_converter_spelling(base_name, "as_", participant_name);
  found = _declared(compiler, alternate);
  if (_exact_conversion(found, base, participant)) return alternate;
  return NULL;
}

static String _forward_binding(
  Compiler compiler, Type base, Type participant) {
  String base_name = _base_name(base);
  if (!base_name || !participant.is_bare_typedef_name()) return NULL;
  String binding = %"${participant.car()}_${base_name.lower()}";
  Type found = _declared(compiler, binding);
  if (!_exact_conversion(found, participant, base)) return NULL;
  return binding;
}

typedef struct MemberResolution {
  Compiler c;
  Type base, participant, representation;
  String binder, forward;
  Map variables, defaults, bindings;
} MemberResolution;

static Type MemberResolution.find_member(
  MemberResolution *r, String member, String &selected) {
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
  foreach (Type owner,
           (r.base !== %("Var") || r.representation) && !actual
             ? _ancestry(r.c, r.participant).cdr() : NULL) {
    if (owner == r.base) break;
    if (r.base === %("Var") && owner != r.representation) continue;
    actual = _method_signature(
      r.c, owner, r.participant, member, selected);
    if (actual || r.base === %("Var")) break;
  }
  return actual;
}

static List MemberResolution.select(MemberResolution *r, List row) {
  match (row)
    case %(?(String member) ?(Type template) ?): {
      String selected = NULL;
      Type actual = r.find_member(member, selected);
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

static List MemberResolution.complete(MemberResolution *r, List row) {
  match (row)
    case %(?(String member) ?(Symbol status) ?(String source)
           ? ? ?(Type template)): {
      Type expected = _substitute_signature(
        template, r.variables, r.bindings);
      Symbol default_kind = <none>;
      if (status == <no-member>) {
        String base_name = _base_name(r.base);
        if (base_name && r.base !== %("Var")) {
          String fallback = %"${base_name}_$member";
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
      return %($member $status $source $expected $default_kind $template);
    }
  return NULL;
}

static List _resolve_members(
  MemberResolution *resolution, List associations, List templates) {
  resolution.variables[resolution.binder] = 1;
  resolution.bindings[resolution.binder] = resolution.participant;
  foreach (List association, associations) {
    (String name, Type value) = association;
    resolution.variables[name] = 1;
    resolution.defaults[name] = value;
  }
  Array selected = [];
  foreach (List row, templates) {
    List member = resolution.select(row);
    if (member) selected.push(member);
  }
  foreach (Var (name, value), resolution.defaults)
    resolution.bindings.setdefault(name, value);
  Array completed = [];
  foreach (List row, selected) {
    List member = resolution.complete(row);
    if (member) completed.push(member);
  }
  selected.free();
  return completed.list_free();
}

static List _conversion_requirement(
  String binder, String member, Type template, Symbol adapter,
  String forward, String reverse) {
  int fallback = adapter == <fallback>;
  List parameters = template.car().list().cadr();
  Type result = template.cdr();
  Symbol direction = fallback ? <forward> : <reverse>;
  foreach (Var parameter, parameters) {
    if (_is_exact_variable(parameter, binder)) {
      if (!(fallback ? forward : reverse))
        return %($member $adapter $direction parameter);
    }
    else if (_contents(parameter, binder) & PROTOCOL_VARIABLE)
      return %($member $adapter nested parameter);
  }
  direction = fallback ? <reverse> : <forward>;
  if (_is_exact_variable(result, binder)) {
    if (!(fallback ? reverse : forward))
      return %($member $adapter $direction result);
  }
  else if (_contents(result, binder) & PROTOCOL_VARIABLE)
    return %($member $adapter nested result);
  return NULL;
}

typedef struct ConversionNeed {
  Compiler c;
  Type base;
  String binder, forward, reverse;
} ConversionNeed;

static List _descriptor_requirement(
  ConversionNeed *need, String member, Type template) {
  if (need.base !== %("Var") ||
      !need.c.sym.lookup_field(%(struct "VarMethods"), %($member)))
    return NULL;
  return _conversion_requirement(
    need.binder, member, template, <thunk>,
    need.forward, need.reverse);
}

static List _ordinary_requirement(
  Compiler compiler, Type base, String binder, List rows, String forward,
  String reverse) {
  ConversionNeed need = {
    .c = compiler, .base = base, .binder = binder,
    .forward = forward, .reverse = reverse};
  foreach (List row, rows)
    match (row)
      case %(?(String member) ?(Symbol status) ? ?
             ?(Symbol default_kind) ?(Type template)): {
        if (status == <base-dflt> && default_kind == <ordinary>) {
          List requirement = _conversion_requirement(
            binder, member, template, <fallback>, forward, reverse);
          if (requirement) return requirement;
        }
        if (status == <implmntd>) {
          List requirement = _descriptor_requirement(
            &need, member, template);
          if (requirement) return requirement;
        }
      }
  return NULL;
}

static List Compiler._resolve_ordinary_protocol(
  Compiler c, Type base, Type participant,
  ProtocolRequirements *requirements, List &failure) {
  failure = NULL;
  Var stored;
  List key = %($base $participant);
  if (c.conforms.try_get(key, stored))
    return stored is <list> ? stored : NULL;
  String base_name = _base_name(base);
  if (!base_name || !participant.is_bare_typedef_name()) goto does_not_conform;
  String forward = _forward_binding(
    c, base, participant);
  String reverse = _reverse_binding(
    c, base, participant);
  MemberResolution resolution = {
    .c = c, .base = base, .participant = participant,
    .binder = requirements.binder,
    .variables = {}, .defaults = {}, .bindings = {},
    .representation = base === %("Var")
      ? _adoption_representation(
        _visible_adoption_row(c, base, participant)) : NULL,
    .forward = base !== %("Var")
      ? _forward_binding(c, base, participant) : NULL};
  List rows = _resolve_members(
    &resolution, requirements.associations, requirements.templates);
  List requirement = _ordinary_requirement(
    c, base, requirements.binder, rows, forward, reverse);
  if (requirement) {
    failure = requirement;
    goto does_not_conform;
  }
  List conformance = %(
    protocol-conformance $base $participant $forward $reverse
    ${resolution.variables} ${resolution.bindings} (members @rows)
  );
  c.conforms[key] = conformance;
  return conformance;
does_not_conform: c.conforms[key] = 0;
  return NULL;
}

/** Resolves every visible adoption into the current conformance registry.
    Resolution starts from an empty registry; diagnostics are located only for
    adoptions owned by the current translation unit.
*/
void Compiler.resolve_protocols(Compiler compiler) {
  compiler.conforms = {};
  String owner = _path(compiler);
  foreach (Var value, compiler.adoptions) {
    List adoption = value;
    Type (base, participant) = adoption.cdr();
    Symbol storage = _adoption_storage(adoption);
    List location = _adoption_location(adoption);
    String path = _canonical_file(compiler, location);
    if (storage == <static> && path != owner) continue;
    _resolve_declared_adoption(
      compiler, base, participant,
      path == owner ? location : NULL);
  }
}

/* Publish resolved external signatures before their adapters are generated. */
static void _install_generated_symbol(
  Compiler compiler, Type participant, String member, Type signature) {
  String generated = _member_spelling(participant, member);
  compiler.sym.define_global(
    %("generated-protocol" $generated), %(generated));
  compiler.sym.define_global(%($generated), signature);
}

/** Publishes external native alias and ordinary adapter signatures.
    Protocols must already be resolved in the active symbol table.
*/
void Compiler.install_generated_protocol_symbols(Compiler c) {
  foreach (Var value, c.conforms)
    match (value)
      case %(protocol-conformance ?(Type base) ?(Type participant)
             ?(String forward) ? ? ? (members *rows)): {
        int native = 0;
        match (rows)
          case %((? native *) *): native = 1;
        if (native) {
          if (_adoption_visibility(c, base, participant) != <external>)
            continue;
          foreach (List row, rows)
            match (row)
              case %(?(String member) ? ? ? ? ?(Type signature)):
                _install_generated_symbol(c, participant, member, signature);
          continue;
        }
        if (!c.fn_defs.contains(forward)) continue;
        if (c.sym.resolve_numeric_type(participant) &&
            participant !== %("Symbol"))
          continue;
        foreach (List row, rows)
          match (row)
            case %(?(String member) base-dflt ? ? ordinary ?): {
              List decision = _generated_owner(c, participant, member);
              match (decision)
                case %(owner ? ? ?signature external):
                  _install_generated_symbol(c, participant, member, signature);
            }
      }
}

static String _definition_location(Compiler compiler, Type base) {
  List stored = compiler.protocols[base];
  return _location_string(_occurrence_location(stored));
}

static void _report_member_sig_conflicts(
  Compiler compiler, Type base, Type participant, List rows, List location) {
  String base_repr = _type_spelling(base);
  String participant_repr = _type_spelling(participant);
  String declaration_site = _definition_location(compiler, base);
  foreach (List row, rows)
    match (row)
      case %(?(String member) sig-cnflct ?(String binding)
             ?(Type expected) ? ?): {
        List dedupe = %("protocol-sig-conflict" $participant $member);
        if (dedupe in compiler.protocol_helpers) continue;
        compiler.protocol_helpers[dedupe] = 1;
        Type actual = _declared(compiler, binding);
        String owner = %"$base_repr($participant_repr)";
        String protocol_note = %"protocol member '$member' declared by $owner";
        if (declaration_site)
          protocol_note = %"$protocol_note at $declaration_site";
        String actual_repr = actual.repr();
        String conflict_note =
          %"conflicting definition '$binding': $actual_repr";
        String expected_note = %"expected: ${expected.repr()}";
        compiler.diagnostics.report(
          <protocol>,
          %"'$binding' has a signature incompatible " +
            %"with $owner member '$member'",
          location,
          %($protocol_note $conflict_note $expected_note)
        );
      }
}

static String _requirement_detail(
  Type base, Type participant, List failure) {
  String base_repr = _type_spelling(base);
  String participant_repr = _type_spelling(participant);
  (String member, Symbol adapter, Symbol direction, Symbol position) = failure;
  String lowered = participant.is_bare_typedef_name()
    ? participant.car().str().lower() : participant_repr;
  String owner = %"$base_repr($participant_repr)";
  String prefix = %"$participant_repr does not satisfy $owner: ";
  if (adapter == <fallback> && direction == <nested>)
    return %"${prefix}member '$member' uses T inside a compound " +
      %"${position} type, which protocol fallback adapters " +
      "do not support";
  if (adapter == <fallback> && direction == <reverse>)
    return %"${prefix}member '$member' returns T, so $owner needs " +
      %"'$base_repr.$lowered' or '$base_repr.as_$lowered'";
  if (adapter == <fallback>)
    return %"${prefix}member '$member' fallback requires forward " +
      %"conversion '$participant_repr.${base_repr.lower()}'";
  if (adapter == <thunk> && direction == <nested>)
    return %"${prefix}member '$member' uses T inside a compound " +
      %"${position} type, which protocol descriptor thunks " +
      "do not support";
  if (adapter == <thunk> && position == <parameter>)
    return %"${prefix}member '$member' has a T parameter, so " +
      %"$owner needs '$base_repr.$lowered' or '$base_repr.as_$lowered'";
  if (adapter == <thunk>)
    return %"${prefix}member '$member' returns T, so $owner needs " +
      %"'$participant_repr.${base_repr.lower()}'";
  if (position == <parameter>)
    return %"${prefix}native member '$member' has a T parameter " +
      %"that is not implicitly convertible to $base_repr";
  if (position == <result>)
    return %"${prefix}native member '$member' returns T, which is " +
      %"not implicitly convertible from $base_repr";
  return %"${prefix}native member '$member' cannot be aliased";
}

static String _missing_conformance_detail(
  Compiler compiler, Type base, Type participant, int native,
  List failure) {
  String base_repr = _type_spelling(base);
  String participant_repr = _type_spelling(participant);
  String owner = %"$base_repr($participant_repr)";
  String prefix = %"$participant_repr does not satisfy $owner: ";
  if (failure) return _requirement_detail(base, participant, failure);
  if (native)
    return %"${prefix}its typedef is not a native alias of $base_repr";
  String base_name = _base_name(base);
  String lowered = participant.is_bare_typedef_name()
    ? participant.car().str().lower() : participant_repr;
  String forward = base_name
    ? %"$participant_repr.${base_name.lower()}" : NULL;
  Type forward_type = forward && base_name
    ? _declared(compiler, %"${participant.car()}_${base_name.lower()}")
    : NULL;
  if (base_name && !_exact_conversion(forward_type, participant, base))
    return %"${prefix}no forward conversion '$forward'";
  return %"${prefix}no reverse conversion '$base_repr.$lowered' " +
    %"or '$base_repr.as_$lowered'";
}

static void _resolve_protocol_record(
  Compiler compiler, Type base, Type participant, List location,
  ProtocolRequirements *requirements) {
  int native = _is_native(requirements.templates);
  List conformance = NULL, failure = NULL;
  if (native) {
    Type definition = _participant_definition(compiler, participant);
    conformance = compiler._resolve_native_protocol_participant(
      base, participant, requirements, definition, failure);
  }
  else
    conformance = compiler._resolve_ordinary_protocol(
      base, participant, requirements, failure);

  if (!conformance) {
    if (!location) return;
    String detail = _missing_conformance_detail(
      compiler, base, participant, native, failure);
    compiler.diagnostics.report(<protocol>, detail, location, NULL);
    return;
  }
  if (location) {
    List rows = conformance.last().list().cdr();
    if (native)
      _install_native_bindings(compiler, participant, rows);
    _report_member_sig_conflicts(
      compiler, base, participant, rows, location);
  }
}

static void _resolve_declared_adoption(
  Compiler compiler, Type base, Type participant, List location) {
  List record = compiler._record(base);
  if (!record) {
    if (!location) return;
    compiler.diagnostics.report(
      <protocol>,
      %"adoption base ${_type_spelling(base)} names no visible protocol",
      location, NULL);
    return;
  }
  match (record)
    case %(? ? ?(String binder) (associated *associations)
           (members *members)): {
      ProtocolRequirements requirements = {
        .binder = binder, .associations = associations,
        .templates = members};
      _resolve_protocol_record(
        compiler, base, participant, location, &requirements);
    }
}

/* A macro import parses one body during the caller's collection pass, which
   keeps its own registries empty because it parses no bodies at all. That
   body's `foreach` is the only reader, so the protocols and adoptions visible
   to the import are installed the first time one is asked for. Installing
   them for every import, or resolving every conformance here rather than the
   one below, each cost more than the feature. */
static void _install_import_protocols(Compiler c) {
  c.import_protocols = 0;
  Map symbols = c.sym.base_symbols();
  Map current = c.sym.current_symbols();
  if (current) symbols.merge(current);
  c.rebuild_protocols(symbols);
}

/** Returns the resolved conformance for `participant` and `base`, if any.
    Lookup canonicalizes the participant and may use the nearest adopted
    typedef ancestor. Native conformances install their generated bindings
    before the cached conformance row is returned.
*/
List Compiler.protocol_members_for(Compiler c, Type participant, Type base) {
  participant = participant.canonicalize();
  if (c.import_protocols) _install_import_protocols(c);
  Type owner = participant;
  if (!c._is_adopted(base, owner)) {
    List ancestry = _ancestry(c, participant).cdr();
    for (; ancestry; ancestry = ancestry.cdr()) {
      owner = ancestry.car();
      if (c._is_adopted(base, owner)) break;
    }
    if (!ancestry) return NULL;
  }
  List key = %($base $owner);
  Var stored = c.conforms[key];
  /* One adoption is resolved where it is asked for when the parse has not
     resolved it. `_install_protocol_adoption` already skips resolving during
     a shallow pass, and an import installed just above resolves nothing.
     `adoptions` holds only the adoptions this compiler may use, and the full
     parse resolves all of them before it starts, so the full parse has an
     entry for every pair that reaches this point. */
  if (stored is void) {
    _resolve_declared_adoption(c, base, owner, NULL);
    stored = c.conforms[key];
  }
  if (stored is not <list>) return NULL;
  List conformance = stored;
  _install_native_bindings(
    c, owner, conformance.last().list().cdr());
  return conformance;
}

/** Reports whether conformance supersedes an ambient direct member.
    The answer is cached for the canonical participant and includes the first
    visible adopted ancestor that declares the member.
*/
int Compiler.protocol_rejects_direct_member(
  Compiler compiler, Type participant, String member) {
  Type owner = participant.canonicalize();
  List cache_key = %("protocol-rejects" $owner $member);
  Var cached;
  if (compiler.proto_cache.try_get(cache_key, cached)) return cached;
  List protocols = _ordered_occurrences(compiler), int rejects = 0;
  foreach (Type ancestor, _ancestry(compiler, owner)) {
    List row = _member_row(
      compiler, protocols, ancestor, member);
    if (row) {
      Symbol status = row.cadr();
      rejects = status == <native> || status == <base-dflt> ||
                status == <no-member> || status == <sig-cnflct>;
      break;
    }
  }
  compiler.proto_cache[cache_key] = rejects;
  return rejects;
}

/* Maps each operator to its protocol member. Direct rows lower the operator
   straight to its member; derived rows compute `!=` from `equal` and the
   ordered comparisons from `compare` against zero. The punctuation table in
   docs/src/guide/protocols.md mirrors these rows. */
static const SymbolSet operator_ops =
  %<<"+" "-" "*" "/" "%" "@" "==" "!=" "<" "<=" ">" ">=">>;

static const struct { Symbol member; int derived; } operator_members[] = {
  { <add>, 0 },      { <sub>, 0 },      { <mul>, 0 },
  { <div>, 0 },      { <mod>, 0 },      { <matmul>, 0 },
  { <equal>, 0 },
  { <equal>, 1 },    { <compare>, 1 },  { <compare>, 1 },
  { <compare>, 1 },  { <compare>, 1 }
};

static Symbol _operator_member_row(Symbol op, int derived) {
  int index = operator_ops.index(op);
  if (index < 0 || operator_members[index].derived != derived) return 0;
  return operator_members[index].member;
}

/** Returns the protocol member corresponding to a direct binary operator.
    Returns zero when the operator has no direct protocol mapping.
*/
Symbol Compiler.operator_member(Compiler compiler, Symbol op) {
  (void) compiler;
  return _operator_member_row(op, 0);
}

static void _dump_conformance_member(
  String member, const char *status, String source, const char *punctuation) {
  printf(" (%s %s %s %s)", member, status, source ? source : "-", punctuation);
}

static void _dump_conformance_row(
  const char *kind, int owned, Type base, Type participant, List rows) {
  printf(
    "(%s %s %s %s", kind, owned ? "owned" : "visible",
    base.repr(), participant.repr());
  foreach (List row, rows)
    match (row)
      case %(?(String member) ?(Symbol status) ?(String source) ? ? ?): {
        const char *name = NULL, *punctuation = "none";
        switch (status) {
          case <implmntd>: name = "implemented"; break;
          case <base-dflt>: name = "base-default"; break;
          case <sig-cnflct>: name = "sig-conflict"; break;
          case <no-member>: name = "no-member"; break;
          case <native>: name = "native"; break;
        }
        if (status == <implmntd> || status == <base-dflt> ||
            status == <native>)
          punctuation = "dot+punctuation";
        _dump_conformance_member(member, name, source, punctuation);
      }
  printf(")\n");
}

/** Prints stable conformance rows for typedefs in `globs`.
    Rows are ordered by participant and protocol and identify whether each
    adoption is owned by this unit, so prelude and live symbol modes can be
    compared.
*/
void Compiler.dump_conformance(Compiler compiler, Map globs) {
  Array names = [];
  foreach (Var (key, value), globs)
    match (%($key $value))
      case %((?(String name)) (typedef *)):
        names.push(name);
  names.sort();
  List protocols = _ordered_occurrences(compiler);
  foreach (Var candidate, names) {
    Type participant = %(${candidate.str()});
    foreach (List entry, protocols) {
      Type base_type = entry.car();
      if (!compiler._is_adopted(base_type, participant)) continue;
      List conformance = compiler.protocol_members_for(
        participant, base_type);
      if (!conformance) continue;
      _dump_conformance_row(
        "conformance",
        _adoption_owned(compiler, base_type, participant),
        base_type, participant,
        conformance.last().list().cdr());
    }
  }
  names.free();
}

/** Returns the protocol member that derives a comparison operator.
    Inequality derives from `equal`, ordered comparisons derive from `compare`,
    and unsupported operators return zero.
*/
Symbol Compiler.derived_member(Compiler compiler, Symbol op) {
  (void) compiler;
  return _operator_member_row(op, 1);
}

/* The single entry point for proto_cache. A hit returns the cached List (a
   non-list value records a null result); a miss runs compute(compiler) and
   stores what it returns. */
static List _proto_cached(Compiler compiler, Var key, Func compute) {
  Var cached;
  if (compiler.proto_cache.try_get(key, cached))
    return cached is <list> ? cached : NULL;
  List result = compute(compiler);
  compiler.proto_cache[key] = result ? result : 0;
  return result;
}

static List _ordered_occurrences(Compiler compiler) =>
  _proto_cached(
    compiler, <proto-ordr>, %!(Compiler &compiler) => {
    Array ordered = [];
    foreach (Var (base, occurrence), compiler.protocols)
      ordered.push(%($base $occurrence));
    ordered.sort();
    return ordered.list_free();
  });

static List _ancestry(Compiler compiler, Type participant) => _proto_cached(
  compiler, %("protocol-ancestry" $participant),
  %!(Compiler &compiler) => {
    Array ancestry = [], Type current = participant;
    for (int distance = 0; current && distance <= 128; distance++) {
      ancestry.push(current);
      if (!current.is_typedef_name() && !current.is_typedef()) break;
      current = compiler.sym.get(current);
    }
    return ancestry.list_free();
  });

/* Drive visit(compiler, base, row) over every member row of participant's
   adopted conformances, in protocols order. A nonzero visit result stops the
   iteration. */
static void _each_adopted_row(
  Compiler compiler, List protocols, Type participant, Func visit) {
  foreach (List entry, protocols) {
    Type base_type = entry.car();
    if (!compiler._is_adopted(base_type, participant)) continue;
    List conformance = compiler.protocol_members_for(
      participant, base_type);
    if (!conformance) continue;
    foreach (List row, conformance.last().list().cdr())
      if (visit(compiler, base_type, row).int()) return;
  }
}

/** Returns unique member spellings from the participant's visible adopted
    conformances. Resolution remains responsible for selecting a binding. */
List Compiler.protocol_member_names(Compiler compiler, Type participant) {
  Map seen = {};
  Array names = [];
  List protocols = _ordered_occurrences(compiler);
  foreach (Type current, _ancestry(compiler, participant.canonicalize()))
    foreach (List entry, protocols) {
      Type base = entry.car();
      if (!compiler._is_adopted(base, current)) continue;
      List conformance = compiler.protocol_members_for(current, base);
      if (!conformance) continue;
      foreach (List row, conformance.last().list().cdr()) {
        String name = row.car();
        if (name && !seen.contains(name)) {
          seen[name] = 1;
          names.push(name);
        }
      }
    }
  names.sort();
  return names.list_free();
}

static List _member_row(
  Compiler compiler, List protocols, Type participant, String member) {
  List found = NULL;
  _each_adopted_row(
    compiler, protocols, participant,
    %!(Compiler &compiler, Type base, List row) using &found => {
      (void) compiler; (void) base;
      if (row.car() == member) {
        found = row;
        return 1;
      }
      return 0;
    });
  return found;
}

typedef struct GeneratedOwners {
  Type participant;
  String member;
  Array candidates;
  List result, first_linkage;
  Symbol first_storage;
} GeneratedOwners;

static int GeneratedOwners.consider(
  GeneratedOwners *g, Compiler compiler, Type base, List row) {
  match (row)
    case %(?(String member) base-dflt ?(String source)
           ?(Type expected) ordinary ?): {
      if (member != g.member) return 0;
      Symbol storage = _adoption_visibility(
        compiler, base, g.participant);
      List owner = %(owner $base $source $expected $storage);
      g.candidates.push(owner);
      if (storage == <mixed>) {
        g.result = %(linkage $owner $owner);
        return 1;
      }
      if (!g.first_linkage) {
        g.first_linkage = owner;
        g.first_storage = storage;
      }
      else if (g.first_storage != storage) {
        g.result = %(linkage ${g.first_linkage} $owner);
        return 1;
      }
    }
  return 0;
}

static List GeneratedOwners.decision(GeneratedOwners *owners) {
  List rows = owners.candidates.list_free();
  if (owners.result) return owners.result;
  match (rows) {
    case %(?only): return only;
    case %(?first ?second *rest):
      return %(conflict $first $second @rest);
  }
  return NULL;
}

/* Select the sole generated owner across all adopted protocols. */
static List _generated_owner(
  Compiler compiler, Type participant, String member_name) {
  List cache_key = %("protocol-generated-owner" $participant $member_name);
  return _proto_cached(
    compiler, cache_key, %!(Compiler &compiler) => {
    GeneratedOwners owners = {
      .participant = participant, .member = member_name, .candidates = []};
    _each_adopted_row(
      compiler, _ordered_occurrences(compiler), participant,
      %!(Compiler &compiler, Type base, List row)
        using &owners => owners.consider(compiler, base, row));
    return owners.decision();
  });
}

static List _collision_notes(Symbol kind, List first, List second) {
  (Type first_base, String first_source, Type first_expected,
   Symbol first_storage) = first.cdr();
  (Type second_base, String second_source, Type second_expected,
   Symbol second_storage) = second.cdr();
  String first_repr = _type_spelling(first_base);
  String second_repr = _type_spelling(second_base);
  if (kind == <linkage>)
    return %(
      "$first_repr adoption: ${first_storage}"
      "$second_repr adoption: ${second_storage}"
    );
  if (!first_expected.equal(second_expected))
    return %(
      "$first_repr signature: ${first_expected.repr()}"
      "$second_repr signature: ${second_expected.repr()}"
    );
  return %(
    "$first_repr default source: $first_source"
    "$second_repr default source: $second_source"
  );
}

static void _report_generated_collision(
  Compiler compiler, Type participant, String member, Symbol kind, List first,
  List second) {
  Type first_base = first.cadr(), second_base = second.cadr();
  Type first_expected = first.cdr().cdr().cdr().car();
  Type second_expected = second.cdr().cdr().cdr().car();
  List dedupe = %("protocol-generated-collision" $participant $member);
  if (dedupe in compiler.protocol_helpers) return;
  compiler.protocol_helpers[dedupe] = 1;
  int linkage_conflict = kind == <linkage>;
  String first_repr = _type_spelling(first_base);
  String second_repr = _type_spelling(second_base);
  String participant_repr = _type_spelling(participant);
  int incompatible_signatures = !first_expected.equal(second_expected);
  String message = %"member '$member' of '$participant_repr' ";
  String owners =
    %"$first_repr($participant_repr) and $second_repr($participant_repr)";
  if (linkage_conflict)
    message += %"has mixed static and external generated ownership in $owners";
  else if (incompatible_signatures)
    message += %"has incompatible generated signatures in $owners";
  else
    message += %"would be generated by both $owners; implement '" +
      %"$participant_repr.$member' to choose its semantics";

  List notes = _collision_notes(kind, first, second);
  List row = _visible_adoption_row(compiler, first_base, participant);
  compiler.diagnostics.report(
    <protocol>, message, _adoption_location(row), notes);
}

/* A generated function around a body its caller lowered. `result` carries
   the storage class, so static, inline and external helpers share it. */
macro open Unit $compiler_wrapper(Type $result, Name $name, Statement $body,
    Param $params...) {
  $result $name($params...) { $body }
}

/** Returns the function `result name(params) { body }` bound in this
    unit. `result` is the storage class and result type, `params` the
    parameter declarations, and `body` its lowered statements. */
List Compiler.wrapper_function(
  Compiler c, Type result, List binding, List params, List body) {
  /* The template's own definition is not authored API of this unit; a
     documented prototype the function completes keeps its prose. */
  List key = %(api-definition $binding);
  Var authored;
  int documented = c.semantic_binding_facts().try_get(key, authored);
  Macro wrapper = $compiler_wrapper;
  List function = c.bind_syntax(
    wrapper(result, binding, %(code-value "lowered" (seq @body) ()), params),
    AST_UNIT, NULL);
  if (documented) c.semantic_binding_facts()[key] = authored;
  else c.semantic_binding_facts().del(key);
  return function;
}

static List _generated_member(
  Compiler compiler, List ancestry, String member) {
  foreach (Type current, ancestry) {
    List decision = _generated_owner(compiler, current, member);
    match (decision)
      case %(owner ? ? ?signature ?): {
        String source = _member_spelling(current, member);
        List binding = compiler.sym.reference(%($source), NULL);
        return %($binding $signature);
      }
  }
  return NULL;
}

static int _base_in_ancestry(Type base, Type participant, List ancestry) {
  if (base.equal(participant)) return 1;
  for (List row = ancestry ? ancestry.cdr() : NULL; row; row = row.cdr())
    if (base.equal(row.car())) return 1;
  return 0;
}

static int _declares_member(List rows, String member) {
  foreach (List row, rows) if (row.car() == member) return 1;
  return 0;
}

static List _base_alias(
  Compiler compiler, List protocols, Type participant, List ancestry,
  String member) {
  foreach (List entry, protocols) {
    (Type base, List occurrence) = entry;
    if (!_base_in_ancestry(base, participant, ancestry)) continue;
    String base_name = _base_name(base);
    if (!base_name) continue;
    List record = occurrence.car();
    List declared = record.last().list().cdr();
    if (!_declares_member(declared, member)) continue;
    String source = %"${base_name}_$member";
    Type signature = compiler.sym.get(%($source));
    if (!signature || !signature.is_function()) continue;
    List binding = compiler.sym.reference(%($source), NULL);
    return %($binding $signature);
  }
  return NULL;
}

static List _adopted_member(
  Compiler compiler, List protocols, List ancestry, String member) {
  foreach (Type current, ancestry) {
    List row = _member_row(compiler, protocols, current, member);
    if (!row) continue;
    match (row)
      case %(? ?(Symbol status) ?(String source) ?(Type signature) ? ?): {
        if (status == <implmntd>) {
          List binding = compiler.sym.reference(%($source), NULL);
          return %($binding $signature);
        }
        if (status == <native>) {
          String binding_name = _member_spelling(current, member);
          List binding = compiler.sym.reference(%($binding_name), NULL);
          return %($binding $signature);
        }
      }
    return %();
  }
  return %();
}

static List _resolve_protocol_member(
  Compiler compiler, Type participant, String member_name) {
  List cache_key = %("protocol-member" $participant $member_name);
  return _proto_cached(
    compiler, cache_key, %!(Compiler &compiler) => {
    List protocols = _ordered_occurrences(compiler);
    List ancestry = _ancestry(compiler, participant);
    /* A generated member is selected before a direct base alias. */
    List selected = _generated_member(compiler, ancestry, member_name);
    if (selected) return selected;
    selected = _base_alias(
      compiler, protocols, participant, ancestry, member_name);
    return selected ? selected
      : _adopted_member(compiler, protocols, ancestry, member_name);
  });
}

/** Resolves a protocol member for `participant`.
    Returns a `(binding signature)` pair for the selected implementation or
    null when no eligible resolved member exists; positive and negative
    results are cached. Inside the selected implementation itself the result
    is null, so the member's own body keeps the native operation.
*/
List Compiler.resolve_protocol_member(
  Compiler compiler, Type participant, String member_name) {
  // A const or volatile receiver adopts exactly what its unqualified type
  // adopts, so conformance is keyed on the unqualified participant.
  List resolved = _resolve_protocol_member(
    compiler, participant.canonicalize(), member_name);
  if (!resolved) return NULL;
  String spelling = binding_identity_spelling(resolved.car());
  return spelling == compiler.fn_name ? NULL : resolved;
}

macro open Statement $protocol_update_body(Expr $current, Expr $call) {
  $current = $call;
  return $current;
}

macro open Statement $protocol_postfix_body(Type $type, Name $old,
    Expr $current, Expr $call) {
  $type $old = $current;
  $current = $call;
  return $old;
}

typedef struct ProtocolUpdate {
  Compiler c;
  Type participant, rhs_type, result, source_type;
  List source_binding, helper_binding, current, call_rhs, old_binding;
  Array declarations;
  int postfix;
} ProtocolUpdate;

static List _bound_protocol_call(
  Compiler c, Type result, List callee, List arguments) {
  Macro shape = $called;
  return c.rebuild_expression(result, shape(callee, arguments));
}

static void ProtocolUpdate.arguments(ProtocolUpdate *u) {
  List lhs_binding = u.c.sym.introduce("lhs");
  List op_binding = u.c.sym.introduce("op");
  Type pointer = cons(<*>, cons(<volatile>, u.participant));
  Type pointer_base = cons(<volatile>, u.participant);
  List lhs_pointer = %(expr $pointer (ident $lhs_binding));
  List zero = %(expr (int) (literal (int) "0"));
  u.current = %(expr ${u.participant} (index $lhs_pointer $zero));
  u.declarations.push(%(param $pointer_base (bind $lhs_binding (*))));
  u.declarations.push(%(param ("Symbol") (bind $op_binding ())));
  if (u.postfix) {
    List one = %(expr (int) (literal (int) "1"));
    u.call_rhs = u.c.convert_expression(one, u.rhs_type);
    u.old_binding = u.c.sym.introduce("old");
  }
  else {
    List rhs_binding = u.c.sym.introduce("rhs");
    u.declarations.push(%(param ${u.rhs_type} (bind $rhs_binding ())));
    u.call_rhs = %(expr ${u.rhs_type} (ident $rhs_binding));
  }
}

static void ProtocolUpdate.emit(ProtocolUpdate *u) {
  List call = _bound_protocol_call(u.c, u.result,
    %(expr ${u.source_type} (ident ${u.source_binding})),
    %(${u.current} ${u.call_rhs}));
  Macro ordinary = $protocol_update_body;
  Macro saved = $protocol_postfix_body;
  List shape = u.postfix
    ? saved(u.participant, u.old_binding, u.current, call)
    : ordinary(u.current, call);
  List body = u.c.bind_syntax(shape, AST_BLOCK, u.participant);
  List helper = u.c.wrapper_function(
    %(static @{u.participant}), u.helper_binding,
    u.declarations.list_free(), body.cdr());
  u.c.add_early(helper);
}

/** Returns a generated helper for a direct protocol-backed update.
    The resolved member must have exactly `(Participant, RHS) -> Participant`.
    A matching helper is emitted once into the compiler's early declarations;
    `postfix` selects whether it returns the old or stored value. Returns null
    when the member cannot implement this update shape.
*/
String Compiler.protocol_update_helper(
  Compiler c, Type participant, String member, int postfix) {
  List key = %("protocol-update-helper" $participant $member $postfix);
  Var stored;
  if (c.protocol_helpers.try_get(key, stored)) return stored;

  List resolved = c.resolve_protocol_member(participant, member);
  if (!resolved) return NULL;
  List (source_binding, source_type) = resolved;
  List parameters = source_type.car().list().cadr();
  Type result = source_type.cdr();
  Type rhs_type = NULL;
  match (parameters)
    case %(?receiver ?rhs):
      if (List.equal(receiver, participant) &&
          result.equal(participant))
        rhs_type = rhs;
  if (!rhs_type) return NULL;

  String suffix = postfix ? "postfix" : "update";
  String name =
    %"_x2c_proto_${participant.car().str().lower()}_${member}_$suffix";
  ProtocolUpdate update = {
    .c = c, .participant = participant, .rhs_type = rhs_type,
    .result = result, .source_type = source_type,
    .source_binding = source_binding, .helper_binding = c.sym.introduce(name),
    .declarations = [], .postfix = postfix};
  update.arguments();
  update.emit();
  c.protocol_helpers[key] = name;
  return name;
}

macro open Expression $protocol_discard_call(
    Name $callee, Name $arguments...) => $callee($arguments...);

macro open Statement $protocol_discard_argument(
    Name $discard, Name $argument) {
  $discard($argument);
}

macro open Statement $protocol_discard_void(
    Expr $call, Statement $discards...) {
  $call;
  $discards...
  return;
}

macro open Statement $protocol_discard_value(
    Type $type, Name $value, Expr $call, Statement $discards...) {
  $type $value = $call;
  $discards...
  return $value;
}

typedef struct DiscardCall {
  Compiler c;
  List binding, key;
  Type signature, result;
  String stem;
  Array declarations, arguments, discards;
  int which, fresh;
} DiscardCall;

static void DiscardCall.collect(DiscardCall *call) {
  Macro drop_shape = $protocol_discard_argument;
  List parameters = call.signature.car().list().cadr();
  int index = 0;
  foreach (Type parameter, parameters) {
    List argument = call.c.sym.introduce(%"a$index");
    call.declarations.push(parameter.parameter_ast(argument));
    call.arguments.push(argument);
    if (call.which & (1 << index)) {
      List drop = call.c.resolve_protocol_member(parameter, "discard");
      if (drop) call.discards.push(drop_shape(drop.car(), argument));
    }
    index++;
  }
}

static List DiscardCall.emit(DiscardCall *d) {
  String name = %"_x2c_discard_${d.stem}_${d.which}";
  List helper_binding = d.c.sym.introduce(name);
  List value_binding = d.c.sym.introduce("value");
  Macro call_shape = $protocol_discard_call;
  List expression = d.c.bind_syntax(
    call_shape(d.binding, d.arguments.list_free()),
    AST_EXPRESSION, d.result);
  Macro void_shape = $protocol_discard_void;
  Macro value_shape = $protocol_discard_value;
  List shape = d.result.equal(%(void))
    ? void_shape(expression, d.discards.list_free())
    : value_shape(
      d.result, value_binding, expression, d.discards.list_free());
  List body = d.c.bind_syntax(shape, AST_BLOCK, d.result);
  List helper = d.c.wrapper_function(
    %(static @{d.result}), helper_binding,
    d.declarations.list_free(), body.cdr());
  d.c.add_early(helper);
  List entry = %($helper_binding ${d.signature});
  d.c.protocol_helpers[d.key] = entry;
  /* Wrapping a call preserves its return ownership. Discarding an argument
     does not make an arbitrary method's borrowed result fresh. */
  long identity = (long) helper_binding;
  d.c.protocol_helpers[%"discard-helper $identity"] = 1;
  if (d.fresh) d.c.protocol_helpers[%"fresh-callee $identity"] = 1;
  return entry;
}

/** Returns `(binding signature)` for a generated helper that calls the
    function `binding` of type `signature` and then discards the unnamed
    argument temporaries `which` selects (bit `n` for argument `n`). A
    discarded argument is one the compiler produced for this call alone, so
    its `discard` member may release what it owns before the enclosing scope
    ends. Returns null when no selected argument type has a `discard` member,
    or an ordinary pointer or aggregate result may borrow an argument.
*/
List Compiler.discard_helper(
  Compiler c, List binding, Type signature, String stem, int which) {
  List key = %("discard-helper" $stem $which);
  Var stored;
  if (c.protocol_helpers.try_get(key, stored)) return stored;

  Type result = signature.cdr();
  Type resolved_result = c.sym.resolve_key(result);
  long callee_identity = (long) binding;
  int fresh = c.protocol_helpers.contains(%"fresh-callee $callee_identity");
  /* An ordinary call may return its input or a view into it. Without a
     fresh-result contract, keep that input alive in its enclosing scope. */
  if (!fresh && (resolved_result.is_pointer() ||
                 resolved_result.is_aggregate()))
    return NULL;
  DiscardCall call = {
    .c = c, .binding = binding, .key = key, .signature = signature,
    .result = result, .stem = stem, .which = which, .fresh = fresh,
    .declarations = [], .arguments = [], .discards = []};
  call.collect();
  return call.discards.len() ? call.emit() : NULL;
}

/** The `discard_helper` for `participant`'s protocol `member`. */
List Compiler.protocol_discard_helper(
  Compiler c, Type participant, String member, int which) {
  List resolved = c.resolve_protocol_member(participant, member);
  if (!resolved) return NULL;
  List (binding, signature) = resolved;
  String stem = %"${participant.car().str().lower()}_$member";
  return c.discard_helper(binding, signature, stem, which);
}

static int _variable_is(Var template, Map variables, String name) {
  String variable = _type_variable(template, variables);
  return variable && variable == name;
}

typedef struct AdapterFunction {
  Compiler c;
  String name, source, reverse, binder;
  Type target, signature, template;
  Map variables;
  List binding;
  int make_static;
} AdapterFunction;

static List AdapterFunction.generate(AdapterFunction *a) {
  List target_parameters = a.target.car().list().cadr();
  Type target_result = a.target.cdr();
  List source_parameters = a.signature.car().list().cadr();
  Type source_result = a.signature.cdr();
  List template_parameters = a.template.car().list().cadr();
  Array declarations = [], arguments = [];
  List target_at = target_parameters, template_at = template_parameters;
  List source_at = source_parameters;
  for (int i = 0; target_at;
       i++, target_at = target_at.cdr(), template_at = template_at.cdr(),
       source_at = source_at.cdr()) {
    List binding = a.c.sym.introduce(%"a$i");
    Type parameter = target_at.car();
    declarations.push(parameter.parameter_ast(binding));
    List argument = %(expr $parameter (ident $binding));
    if (_variable_is(template_at.car(), a.variables, a.binder))
      argument = %(expr ${source_at.car()}
        (call ${a.reverse} (args $argument)));
    arguments.push(argument);
  }
  List source_binding = a.c.sym.reference(%(${a.source}), NULL);
  List call = _bound_protocol_call(a.c, source_result,
    %(expr ${a.signature} (ident $source_binding)),
    arguments.list_free());
  a.binding = a.c.sym.reference(%(${a.name}), NULL);
  if (a.make_static) a.binding = a.c.sym.introduce(a.name);
  List storage = a.make_static
    ? %(static inline @target_result) : target_result;
  return a.c.wrapper_function(
    storage, a.binding, declarations.list_free(),
    %((return $target_result $call)));
}

static int _defines_function(Compiler compiler, String name) {
  List binding = compiler.sym.reference(%($name), NULL);
  Var stored;
  if (!binding ||
      !compiler.semantic_binding_facts().try_get(
        %(completion $binding), stored))
    return 0;
  Symbol state = stored.list().car();
  return state == <definition> || state == <completed>;
}

static List _declaration_from_signature(
  Compiler compiler, String name, Type signature, int make_static) {
  List parameters = signature.car().list().cadr();
  Type result = signature.cdr();
  Array declarations = [];
  foreach (Type type, parameters) declarations.push(type.parameter_ast(NULL));
  List binding = compiler.sym.reference(%($name), NULL);
  List storage = make_static ? %(static @result) : result;
  return %(
    declare $storage
      (bindings (bind $binding ((fnmod (params @{declarations.list_free()})))))
  );
}

static List Compiler._generate_native_alias(
  Compiler compiler, Type participant, String member, String source,
  Type signature, int make_static) {
  String target = _member_spelling(participant, member);
  List declaration = _declaration_from_signature(
    compiler, target, signature, make_static);
  if (!make_static) compiler.record_generated_symbol(target, signature);
  List native_binding = compiler.sym.reference(%($source), NULL);
  return compiler.finish_foreign_alias(
    declaration, %(expr $signature (ident $native_binding)));
}

static int _starts_private_region(List node) {
  match (node) {
    case %((!or function falias) *): return 1;
    case %(declare ?type *): return type.type().is_static();
    case %(preproc ?text *): return preproc_visibility(text) == 1;
  }
  return 0;
}

static List _insert_at_visibility_boundary(
  List ast, List declaration, int declaration_private, List additions,
  int make_static) {
  Array output = [], int eligible = 0, inserted = 0;
  foreach (List node, ast) {
    int boundary = eligible && _starts_private_region(node);
    if (!inserted && boundary && !make_static) {
      foreach (Var added, additions) output.push(added);
      inserted = 1;
    }
    output.push(node);
    if (!inserted && boundary && make_static) {
      foreach (Var added, additions) output.push(added);
      inserted = 1;
    }
    if (node != declaration) continue;
    eligible = 1;
    if (!make_static || !declaration_private) continue;
    foreach (Var added, additions) output.push(added);
    inserted = 1;
  }
  if (!inserted) foreach (Var added, additions) output.push(added);
  return output.list_free();
}

static List _string_literal(Compiler compiler, String value) {
  (void) compiler;
  String spelling = %"\"$value\"";
  List chars = %(expr (* char) (literal (* char) $spelling));
  return %(expr ("String") (call "String_new" (args $chars)));
}

macro open Unit $protocol_methods(Name $methods) {
  static VarMethods $methods;
}

macro open Statement $protocol_methods_value(Name $methods, Expr $value) {
  $methods = $value;
}

macro open Statement $protocol_registration_fallback(
    Expr $registered, Expr $fallback) {
  if (!$registered) { $fallback; }
}

macro open Expression $protocol_helper_call(
    Name $callee, Expr $arguments...) => $callee($arguments...);

static List _protocol_helper_call(
  Compiler c, Type result, String callee, List arguments) {
  Macro shape = $protocol_helper_call;
  return c.rebuild_expression(
    result, shape(%($callee), arguments));
}

static List _descriptor_fields(List thunks) {
  Array fields = [];
  foreach (List row, thunks) {
    (String member, List thunk, Type type) = row;
    fields.push(%(dotinit ($member) (expr $type (ident $thunk))));
  }
  return fields.list_free();
}

static List _builtin_registration(
  Compiler c, List methods, String name, Symbol tag) {
  List symbol = %(expr ("Symbol") (literal ("Symbol") $name $tag));
  List table = %(expr ("VarMethods") (ident $methods));
  return _protocol_helper_call(
    c, %(int), "x2c_register_builtin_descriptor", %($symbol $table));
}

static List _tagged_registration(
  Compiler c, List methods, String name, Symbol tag) {
  List symbol = %(
    expr ("Symbol") (literal ("Symbol") ${tag.str()} $tag));
  List table = %(expr ("VarMethods") (ident $methods));
  return _protocol_helper_call(c, %(void),
    "x2c_register_tagged_descriptor",
    %($symbol ${_string_literal(c, name)} $table));
}

static List _fallback_registration(
  Compiler c, List methods, String name, List early_call) {
  List table = %(expr ("VarMethods") (ident $methods));
  List fallback = _protocol_helper_call(c, %(void),
    "x2c_register_descriptor", %(${_string_literal(c, name)} $table));
  Macro shape = $protocol_registration_fallback;
  return c.rebuild_statement(shape(early_call, fallback)).cadr();
}

static void Compiler._generate_descriptor_registration(
  Compiler c, Type participant, String name, Symbol explicit_tag,
  List thunks, int central_initializer) {
  Macro methods_shape = $protocol_methods;
  Macro assign_shape = $protocol_methods_value;
  List methods = c.sym.introduce(
    c.fresh_name("_x2c_protocol_methods"));
  List fields = _descriptor_fields(thunks);
  List value = %(expr ("VarMethods")
    (cast (decl ("VarMethods") (bindings (bind () ())))
      (expr () (composite (commas @fields)))));
  /* A participant with no thunks still needs its tag registered, and the
     file-scope table is already zero, so skip the assignment rather than
     emit an empty initializer, which C only accepts from C23 on. */
  Symbol tag_symbol = participant.var_tag();
  List early_call = _builtin_registration(c, methods, name, tag_symbol);
  List registration = _fallback_registration(
    c, methods, name, early_call);
  List explicit_call = explicit_tag
    ? _tagged_registration(c, methods, name, explicit_tag) : NULL;
  Symbol queue = central_initializer ? <protocol> : <early>;
  List methods_unit = c.bind_syntax(
    methods_shape(methods), AST_UNIT, NULL);
  c.add_early(methods_unit);
  if (thunks) {
    List assignment = c.bind_syntax(
      assign_shape(methods, value), AST_BLOCK, NULL);
    c.add_init(queue, assignment);
  }
  List call = explicit_tag ? explicit_call : early_call;
  Macro statement_shape = $expression_statement;
  c.add_init(
    queue, central_initializer || explicit_tag
      ? c.rebuild_statement(statement_shape(call)).cadr() : registration);
}

static void _report_requirement(
  Compiler compiler, Type base, Type participant, List failure) {
  List dedupe =
    %("protocol-adapter-requirement" $base $participant ${failure.car()});
  if (dedupe in compiler.protocol_helpers) return;
  compiler.protocol_helpers[dedupe] = 1;
  List row = _visible_adoption_row(compiler, base, participant);
  compiler.diagnostics.report(
    <protocol>,
    _requirement_detail(base, participant, failure),
    _adoption_location(row), NULL);
}

/* Copied aggregate boxes have an identity only before unboxing. Their direct
   value printer has no stable address to guard, so the descriptor thunk owns
   this boundary. Pointer participants guard their actual recursive writer. */
static List _guard_value_rendering(
  Compiler compiler, List function, String member) {
  match (function)
    case %(function ?result
           (!set ?declarator
             (bind ? ((fnmod (params
               (param ? (bind ?boxed ?)) *remaining)) *)))
           (block *body)): {
      List value = %(expr ("Var") (ident $boxed));
      List fallback = NULL;
      if (member == "str" || member == "repr")
        fallback = _protocol_helper_call(
          compiler, %("String"), "Var_pointer_string", %($value));
      else match (remaining)
        case %((param ? (bind ?output ?))):
          fallback = _protocol_helper_call(compiler, %("Buffer"),
            "Var_write_pointer_repr",
            %($value (expr ("Buffer") (ident $output))));
      List path = compiler.sym.introduce("render_path");
      compiler.semantic_binding_facts()[%(automatic $path)] = 1;
      compiler.semantic_binding_facts()[%(type $path)] = %("RenderPath");
      Macro addressed = $addressed;
      List address = compiler.rebuild_expression(
        %(* "RenderPath"),
        addressed(%(expr ("RenderPath") (ident $path))));
      List pointer = _protocol_helper_call(
        compiler, %(* void), "Var_pointer", %($value));
      List enter = _protocol_helper_call(compiler, %(int),
        "RenderPath_enter", %($address $pointer));
      List leave = _protocol_helper_call(
        compiler, %(void), "RenderPath_leave", %($address));
      Macro shape = $guard_value_rendering;
      return compiler.rebuild_function(
        function, shape(path, enter, fallback, leave, body));
    }
  return function;
}

typedef struct ProtocolAdapters {
  Compiler c;
  Type base, participant;
  String forward, reverse, binder;
  Map variables, bindings;
  List adoption;
  Array thunks;
  int shares_var_tag, central_initializer;
} ProtocolAdapters;

static List ProtocolAdapters.thunk(
  ProtocolAdapters *a, String member, Type expected, Type template,
  String source) {
  Map erased = a.bindings.copy();
  foreach (Var variable, a.variables.keys()) erased[variable] = %("Var");
  Type target = _substitute_signature(template, a.variables, erased);
  String participant_name = a.participant.car().str().lower();
  String thunk_name = a.c.fresh_name(%"proto_${participant_name}_$member");
  AdapterFunction adapter = {
    .c = a.c, .name = thunk_name, .source = source, .reverse = a.reverse,
    .binder = a.binder, .target = target, .signature = expected,
    .template = template, .variables = a.variables, .make_static = 1};
  List function = adapter.generate();
  if ((member == "str" || member == "repr" || member == "write_str" ||
       member == "write_repr") &&
      a.c.sym.normalize_declared_type(a.participant).is_aggregate())
    function = _guard_value_rendering(a.c, function, member);
  a.c.add_early(function);
  return %($member ${adapter.binding} $target);
}

static void ProtocolAdapters.default_member(
  ProtocolAdapters *a, String member, String source, Type expected,
  Type template) {
  List decision = _generated_owner(a.c, a.participant, member);
  match (decision) {
    case %(owner ? ? ? ?storage): {
      int make_static = storage == <static>;
      String generated = _member_spelling(a.participant, member);
      AdapterFunction adapter = {
        .c = a.c, .name = generated, .source = source,
        .reverse = a.forward, .binder = a.binder, .target = expected,
        .signature = a.c.sym.get(%($source)), .template = template,
        .variables = a.variables, .make_static = make_static};
      a.c.add_early(adapter.generate());
      if (!make_static) a.c.record_generated_symbol(generated, expected);
    }
    case %((!set ?kind (!or linkage conflict)) ?first ?second *):
      _report_generated_collision(
        a.c, a.participant, member, kind, first, second);
  }
}

static void ProtocolAdapters.inherited_member(
  ProtocolAdapters *a, String member, Type expected, Type template) {
  ConversionNeed need = {
    .c = a.c, .base = a.base, .binder = a.binder,
    .forward = a.forward, .reverse = a.reverse};
  List requirement = _descriptor_requirement(
    &need, member, template);
  if (requirement) {
    _report_requirement(a.c, a.base, a.participant, requirement);
    return;
  }
  String inherited = _member_spelling(a.participant, member);
  a.c.add_early(_declaration_from_signature(a.c, inherited, expected, 0));
  if (!a.c.sym.lookup_field(%(struct "VarMethods"), %($member))) return;
  a.thunks.push(a.thunk(member, expected, template, inherited));
}

static void ProtocolAdapters.missing_member(
  ProtocolAdapters *a, String member, Type template) {
  if (a.base !== %("Var") || a.shares_var_tag) return;
  List decision = _generated_owner(a.c, a.participant, member);
  match (decision) {
    case %(owner ? ? ?owner_expected ?):
      a.inherited_member(member, owner_expected, template);
    case %((!set ?kind (!or linkage conflict)) ?first ?second *):
      _report_generated_collision(
        a.c, a.participant, member, kind, first, second);
  }
}

static void ProtocolAdapters.implemented_member(
  ProtocolAdapters *a, String member, String source, Type expected,
  Type template) {
  if (a.base !== %("Var") || a.shares_var_tag) return;
  if (!a.c.sym.lookup_field(%(struct "VarMethods"), %($member))) return;
  a.thunks.push(a.thunk(member, expected, template, source));
}

static void ProtocolAdapters.member(ProtocolAdapters *a, List row) {
  match (row)
    case %(?(String member) ?(Symbol status) ?(String source)
           ?(Type expected) ? ?(Type template)): {
      if (status == <base-dflt>)
        a.default_member(member, source, expected, template);
      else if (status == <no-member>)
        a.missing_member(member, template);
      else if (status == <implmntd>)
        a.implemented_member(member, source, expected, template);
    }
}

static void ProtocolAdapters.register_descriptor(ProtocolAdapters *a) {
  List thunks = a.thunks.list_free();
  if (a.base !== %("Var") || a.shares_var_tag) return;
  Symbol tag = _protocol_tag_value(_adoption_tag(a.adoption));
  String name = a.participant.car().str();
  if (!tag) name = name.lower();
  a.c._generate_descriptor_registration(
    a.participant, name, tag, thunks, a.central_initializer);
}

static void _ordinary_adapters(
  Compiler c, List conformance, int central_initializer) {
  match (conformance)
    case %(protocol-conformance ?(Type base) ?(Type participant)
           ?(String forward) ?(String reverse) ?(Map variables)
           ?(Map bindings) (members *rows)):
      match (c._record(base))
        case %(? ? ?(String binder) ? ?): {
          List adoption = _visible_adoption_row(c, base, participant);
          ProtocolAdapters adapters = {
            .c = c, .base = base, .participant = participant,
            .forward = forward, .reverse = reverse, .binder = binder,
            .variables = variables, .bindings = bindings,
            .adoption = adoption, .thunks = [],
            .central_initializer = central_initializer,
            .shares_var_tag = base === %("Var") &&
              _adoption_representation(adoption)};
          foreach (List row, rows) adapters.member(row);
          adapters.register_descriptor();
        }
}

static List _native_aliases(
  Compiler c, List ast, Type base, Type participant, List rows) {
  Var stored;
  if (!c.protocol_helpers.try_get(
    %("source-typedef" ${participant.car()}), stored)) return ast;
  (List source, int private) = stored;
  int make_static =
    _adoption_visibility(c, base, participant) == <static>;
  Array aliases = [];
  foreach (List row, rows)
    match (row)
      case %(?(String member) ? ?(String binding) ? ?
             ?(Type signature)): {
        List alias = c._generate_native_alias(
          participant, member, binding, signature, make_static);
        aliases.push(alias);
      }
  return _insert_at_visibility_boundary(
    ast, source, private, aliases.list_free(), make_static);
}

/** Generates adapters and descriptor registration for resolved conformances.
    Native aliases are inserted at the participant's inferred public or
    private boundary. Ordinary adapters and descriptor thunks are added to the
    compiler's early output. Returns `ast` with native insertions applied.
*/
List Compiler.generate_protocol_adapters(Compiler c, List ast) {
  /* Emit adapters only for finalized, declared conformances. */
  int central_initializer =
    _defines_function(c, "x2c_initialize_protocols");
  Array ordered = [];
  foreach (Var (key, value), c.conforms)
    if (value is <list>) ordered.push(%($key $value));
  ordered.sort();
  foreach (List ordered_row, ordered)
    match (ordered_row)
      case %(? (protocol-conformance ?(Type base) ?(Type participant)
                ?(String forward) ?(String reverse) ?(Map variables)
                ?(Map bindings) (members *rows))): {
        int native = 0;
        match (rows)
          case %((? native *) *): native = 1;
        if (native) {
          ast = _native_aliases(c, ast, base, participant, rows);
          continue;
        }
        if (!_defines_function(c, forward)) continue;
        if (c.sym.resolve_numeric_type(participant) &&
            participant !== %("Symbol"))
          continue;
        List conformance = ordered_row.cadr();
        _ordinary_adapters(c, conformance, central_initializer);
      }
  ordered.free();
  return ast;
}

static List _parse_associated_type(Compiler c, Map names) {
  c.expect(<associated>);
  if (c.peek(0) != <ident>)
    c.report_error(
      <protocol>, "expected associated type name", c.token, NULL);
  String name = c.token.text;
  c.next();
  if (name in names)
    c.report_error(
      <protocol>, %"duplicate protocol type variable '$name'",
      c.token, NULL);
  c.expect(<=>);
  Type type = c.parse_type_name().canonicalize();
  c.expect(<;>);
  names[name] = 1;
  c.sym.define(%($name), %(typedef $name));
  return %($name $type);
}

static String _member_name(
  List identity, String participant) {
  String name = NULL;
  match (identity)
    case %((!or (!is ?owner type <string>)
                ((!is ?owner type <string>)))
           (!is ?member type <string>)):
      if (owner == participant) name = member;
  if (name) return name;
  String full_name = binding_identity_spelling(identity);
  String prefix = %"${participant}_";
  return full_name && full_name.startswith(prefix)
    ? full_name[prefix.len():] : NULL;
}

static String _native_member(Compiler c) {
  if (!c.test(<=>)) return NULL;
  if (c.peek(0) != <ident>)
    c.report_error(
      <protocol>, "native protocol member requires an identifier",
      c.token, NULL);
  String native = c.token.text;
  c.next();
  return native;
}

static List _parse_protocol_member(
  Compiler c, String participant, Map members) {
  List declaration = NULL;
  $let(c.in_proto, 1) {
    declaration = c.parse_simple_declaration();
  }
  List binding = NULL, identity = NULL;
  match (declaration)
    case %(declare ? (bindings (!set ?captured (bind ?name ?)))): {
      binding = captured;
      identity = name;
    }
  if (!binding)
    c.report_error(
      <protocol>, "protocol member must declare one function",
      c.token, NULL);
  String name = _member_name(identity, participant);
  if (!name)
    c.report_error(
      <protocol>, "protocol member must be owned by its participant",
      c.token, %("expected receiver:" $participant));
  Type signature = declaration.type_from_ast().canonicalize();
  if (!signature.is_function())
    c.report_error(
      <protocol>, "protocol member must be a function",
      c.token, %("member:" $name));
  if (name in members)
    c.report_error(
      <protocol>, %"duplicate protocol member '$name'",
      c.token, NULL);
  String native = _native_member(c);
  c.expect(<;>);
  members[name] = 1;
  return %($name $signature $native);
}

typedef struct ProtocolSyntax {
  Token start, meta, participant_token, modifier_token;
  Type base, participant_type, representation;
  String participant;
  List tag;
  Symbol storage;
  int generated_base;
} ProtocolSyntax;

static void _parse_adoption_modifiers(
  Compiler c, ProtocolSyntax *syntax) {
  if (c.at_word("as")) {
    syntax.modifier_token = c.token;
    c.next();
    syntax.representation = c.parse_type_name().canonicalize();
    if (!syntax.generated_base && syntax.base !== %("Var"))
      c.report_error(
        <protocol>, "'as' applies only to a Var adoption",
        syntax.modifier_token, NULL);
  }
  if (c.at_word("tag")) {
    syntax.modifier_token = c.token;
    c.next();
    if (syntax.representation)
      c.report_error(
        <protocol>, "a Var adoption cannot use both 'as' and 'tag'",
        syntax.modifier_token, NULL);
    syntax.tag = c.try_parse_macro_slot(<expression>);
    if (!syntax.tag) syntax.tag = c.parse_atomic_literal();
    if (!syntax.generated_base && syntax.base !== %("Var"))
      c.report_error(
        <protocol>, "'tag' applies only to a Var adoption",
        syntax.modifier_token, NULL);
  }
}

static ProtocolSyntax _parse_protocol_head(Compiler c) {
  ProtocolSyntax syntax = {.start = c.token, .storage = <external>};
  if (c.at_word("meta")) {
    syntax.meta = c.token;
    c.next();
  }
  if (c.test(<static>)) syntax.storage = <static>;
  c.expect(<protocol>);
  syntax.generated_base = c.macro_holes &&
    (c.peek(0) == <$> || c.peek(0) == <"$(">);
  syntax.base = c.parse_type_name();
  c.expect(<(>);
  syntax.participant_token = c.token;
  syntax.participant_type = c.parse_type_name();
  Type participant_type = syntax.participant_type;
  syntax.participant = participant_type.len() == 1 &&
                       participant_type.car() is <string>
                     ? participant_type.car() : NULL;
  c.expect(<)>);
  _parse_adoption_modifiers(c, &syntax);
  return syntax;
}

static List _parse_adoption(Compiler c, ProtocolSyntax syntax) {
  c.next();
  List location = c.token_location(syntax.start);
  if (c.macro_holes || (c.shallow && !c.collect_protocols)) {
    List adoption = _adoption_node(
      syntax.base, syntax.participant_type, syntax.storage,
      syntax.representation, syntax.tag, location);
    return syntax.meta ? %(meta-protocol $adoption) : adoption;
  }
  AdoptionDraft draft = {
    .c = c, .base = syntax.base, .participant = syntax.participant_type,
    .storage = syntax.storage, .representation = syntax.representation,
    .tag_expression = syntax.tag, .location = location,
    .participant_token = syntax.participant_token,
    .modifier_token = syntax.modifier_token};
  List adoption = draft.publish();
  if (syntax.meta) c._retain_meta_protocol(adoption);
  return adoption;
}

static void _check_protocol_body(Compiler c, ProtocolSyntax syntax) {
  if (syntax.meta)
    c.report_error(
      <protocol>, "'meta' applies only to a concrete protocol adoption",
      syntax.meta, %("mark each adoption: meta protocol BASE(TYPE);"));

  if (syntax.representation || syntax.tag)
    c.report_error(
      <protocol>, syntax.representation
        ? "'as' applies only to a concrete protocol adoption"
        : "'tag' applies only to a concrete protocol adoption",
      syntax.start, NULL);

  if (!syntax.participant)
    c.report_error(
      <protocol>, "expected protocol participant name",
      syntax.participant_token, NULL);

  if (syntax.storage == <static>)
    c.report_error(
      <protocol>,
      "'static' applies only to a concrete protocol adoption",
      syntax.start,
      %("remove 'static' from the reusable protocol body"));
  c.expect(<"{">);
}

static void _warn_shadowed_binder(Compiler c, ProtocolSyntax syntax) {
  /* Only the full parse warns about a binder shadowing a visible type. */
  if (c.shallow) return;
  String participant = syntax.participant;
  List shadowed = c.sym.get(%($participant));
  if (!shadowed || !shadowed.type().is_typedef()) return;
  String hint = %"hint: a bodyless `protocol BASE($participant);` " +
    "declares an adoption; a body introduces a fresh type variable";
  c.report_warning(
    <shadow>,
    %"protocol binder '$participant' shadows a visible type name",
    syntax.participant_token, %($hint));
}

static List _parse_protocol_body(Compiler c, ProtocolSyntax syntax) {
  String participant = syntax.participant;
  Array associations = [], members = [];
  Map type_names = {}, member_names = {};
  c.sym.push_new_scope();
  c.sym.define(%($participant), %(typedef $participant));
  type_names[participant] = 1;
  int saw_member = 0;
  while (c.peek(0) != <"}"> && c.peek(0) != <eof>) {
    if (c.peek(0) == <associated>) {
      if (saw_member)
        c.report_error(
          <protocol>, "associated types must precede protocol members",
          c.token, NULL);
      associations.push(_parse_associated_type(c, type_names));
      continue;
    }
    saw_member = 1;
    members.push(_parse_protocol_member(c, participant, member_names));
  }
  c.expect(<"}">);
  c.sym.pop_scope();

  List record = %(
    "protocol-record" ${syntax.base} $participant
    (associated @{associations.list_free()})
    (members @{members.list_free()})
  );
  List location = c.token_location(syntax.start);
  if (c.macro_holes || (c.shallow && !c.collect_protocols))
    return %(protocol $record ${syntax.storage} $location);
  return c._publish_protocol_record(record, syntax.base, location);
}

/** Parses a protocol body or concrete adoption at the current token.
    The method consumes through the closing brace or semicolon. Full parsing
    publishes the normalized row immediately. Macro-hole parsing returns syntax
    for later binding; shallow parsing publishes only when protocol collection
    is enabled and otherwise returns the uninstalled node. A leading `meta`
    makes an adoption's witnesses available to compile-time code.
*/
List Compiler.parse_protocol_declaration(Compiler c) {
  ProtocolSyntax syntax = _parse_protocol_head(c);
  if (c.peek(0) == <;>) return _parse_adoption(c, syntax);
  _check_protocol_body(c, syntax);
  _warn_shadowed_binder(c, syntax);
  return _parse_protocol_body(c, syntax);
}
