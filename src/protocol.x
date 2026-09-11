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

#include <limits.h>
#include <stdlib.h>
#include <string.h>
#include "collect.x"
#include "expressions.x"
#include "parse.x"

static String _normalize_file(Compiler compiler, String file) {
  char path[PATH_MAX], String result = file, root = compiler.root_dir;
  if (root && file && file[0] != '/') {
    String rooted = %"$root/$file";
    if (realpath(rooted, path)) result = %"$path";
  }
  if (result == file && realpath(file, path)) result = %"$path";
  return compiler.display_path(result);
}

static String _path(Compiler compiler) {
  Var cached;
  if (compiler.protocol_helpers.try_get(<proto-path>, &cached)) return cached;
  String result = _normalize_file(
    compiler, compiler.filename ? compiler.filename : %"<stdin>");
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
  return compiler.sym.file_statics().contains(%($name));
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

static void _record_declaration_rows_visibility(
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
void Compiler.record_declaration_visibility(
  Compiler compiler, List declaration) {
  int private = _lexically_private(compiler);
  match (declaration) {
    case %(seq *rows):
      foreach (List row, rows) compiler.record_declaration_visibility(row);
    case %(function ?type (bind ?identity *) *): {
      if (!private && !type.type().is_static()) return;
      String name = binding_identity_spelling(identity);
      if (name) _mark_private(compiler, <binding>, name);
    }
    case %(
      (!set ?kind (!or typedef declare)) ?type (bindings *rows)
    ): {
      int mark = private || type.type().is_static();
      _record_declaration_rows_visibility(
        compiler, declaration, kind, private, mark, rows);
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

static Type _adoption_representation(List adoption) {
  // Snapshots written before representation sharing have five-field rows.
  if (adoption.len() < 6) return NULL;
  Var detail = adoption.cddr().cddr().car();
  match (detail) case %(tag ?): return NULL;
  return detail.list();
}

static List _adoption_tag(List adoption) {
  if (adoption.len() < 6) return NULL;
  List tag = NULL;
  match (adoption.cddr().cddr().car()) case %(tag ?value): tag = value;
  return tag;
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
    case %(expr ("Symbol")
           (literal ("Symbol") ? ?(Symbol tag))):
      return tag;
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
  return file is <string> ? file.string() : %"<unknown>";
}

static String _canonical_file(Compiler compiler, List location) {
  String file = _location_file(location);
  return _normalize_file(compiler, file);
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
  return compiler.adoptions.try_get(key, &stored)
       ? stored.list() : NULL;
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
  if (!c.protocols.try_get(base, &stored)) {
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

/** Rebuilds the per-unit protocol and adoption registries from `symbols`.
    Existing rows, helper decisions, and lookup caches are discarded; a null
    map leaves those registries empty. Conformance reset and resolution belong
    to `resolve_protocols`.
*/
void Compiler.rebuild_protocols(Compiler compiler, Map symbols) {
  compiler.protocols = %{};
  compiler.adoptions = %{};
  compiler.protocol_helpers = %{};
  compiler.proto_cache = %{};
  if (!symbols) return;
  foreach (Var value, symbols) {
    if (value is not <list>) continue;
    match (value) {
      case %(protocol
             (!set ?record ("protocol-record" ?base *))
             ?storage ?location):
        compiler._install_protocol_occurrence(
          base.list(), record, storage, location);
      case %(adopt ?base ?participant ?storage ?location):
        compiler._install_protocol_adoption(
          base.list(), participant.list(), storage,
          NULL, 0, NULL, location);
      case %(adopt ?base ?participant ?storage
                   (tag (!set ?tag_expression
                     (expr ("Symbol")
                       (literal ("Symbol") ? ?(Symbol tag)))))
                   ?location):
        compiler._install_protocol_adoption(
          base.list(), participant.list(), storage,
          NULL, tag, tag_expression, location);
      case %(adopt ?base ?participant ?storage ?representation ?location):
        compiler._install_protocol_adoption(
          base.list(), participant.list(), storage,
          representation.list(), 0, NULL, location);
    }
  }
}

static void Compiler._install_protocol_adoption(
  Compiler compiler, Type base, Type participant, Symbol storage,
  Type representation, Symbol tag, List tag_expression, List location) {
  String path = _canonical_file(compiler, location);
  if (storage == <static> && path != _path(compiler)) return;
  participant.register_var_adoption(representation, tag);
  List key = storage == <static>
           ? %($base $participant $path)
           : %($base $participant);
  List row = _adoption_node(
    base, participant, storage, representation, tag_expression, location);
  Var stored;
  if (!compiler.adoptions.try_get(key, &stored)) {
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
  Compiler compiler, String base_name, String infix, String participant) {
  int split = participant.find("__");
  String package = split > 0 &&
    (compiler.package == participant[:split] ||
     compiler.package_roots.contains(participant[:split]))
      ? participant[:split] : NULL;
  String bare = package ? participant[split + 2:] : participant;
  String binding = %"${base_name}_$infix${bare.lower()}";
  return package ? %"${package}__$binding" : binding;
}

static List Compiler._record(Compiler compiler, Type base) {
  Var stored;
  if (!compiler.protocols.try_get(base, &stored)) return NULL;
  List occurrence = stored;
  (List record, Symbol storage, List location) = occurrence;
  (void) storage; (void) location;
  return record;
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

static List Compiler._publish_protocol_record(
  Compiler compiler, List record, Type base, List location) {
  Symbol storage = compiler.source_private > 0 ? <static> : <external>;
  compiler._install_protocol_occurrence(base, record, storage, location);
  compiler.proto_cache = %{};
  List published = %(protocol $record $storage $location);
  compiler._retain_protocol_source_node(published, storage, location);
  return published;
}

static List Compiler._publish_protocol_adoption(
  Compiler c, Type base, Type participant, Symbol storage,
  Type representation, List tag_expression, List location,
  Token participant_token, Token modifier_token) {
  if (tag_expression) tag_expression = _protocol_tag_syntax(tag_expression);
  String spelling = participant.car().str();
  List declared = c.sym.get(%($spelling));
  if ((!declared || !declared.type().is_typedef()) && !c.shallow)
    c.report_error(
      <protocol>,
      %"adoption participant '$spelling' does not name a declared type",
      participant_token, NULL);
  if (representation && !representation.fixed_var_tag()) {
    if (modifier_token)
      c.report_error(
        <protocol>, _representation_error(representation),
        modifier_token, NULL);
    else
      c.diagnostics.report(
        <protocol>, _representation_error(representation),
        location, NULL);
  }
  Symbol tag = 0;
  if (tag_expression) {
    tag = _protocol_tag_value(tag_expression);
    if (!tag) {
      if (modifier_token)
        c.report_error(
          <protocol>, "Var adoption tag must be a Symbol literal",
          modifier_token, NULL);
      else
        c.diagnostics.report(
          <protocol>, "Var adoption tag must be a Symbol literal",
          location, NULL);
    }
    if (base != %("Var")) {
      if (modifier_token)
        c.report_error(
          <protocol>, "'tag' applies only to a Var adoption",
          modifier_token, NULL);
      else
        c.diagnostics.report(
          <protocol>, "'tag' applies only to a Var adoption",
          location, NULL);
    }
  }
  List record = c._record(base), int private_native = 0;
  if (record)
    private_native = _has_private_native(
      c, record.last().list().cdr());
  String base_name = _base_name(base);
  String forward = base_name ? %"${spelling}_${base_name.lower()}" : NULL;
  String reverse = base_name
    ? c.reverse_converter_spelling(base_name, %"", spelling)
    : NULL;
  String alternate = base_name
    ? c.reverse_converter_spelling(base_name, %"as_", spelling)
    : NULL;
  Var occurrence_value;
  List occurrence = c.protocols.try_get(base, &occurrence_value)
    ? occurrence_value.list() : NULL;
  int inferred_private = storage == <static>;
  if (c.source_private >= 0)
    inferred_private = inferred_private ||
      _lexically_private(c) ||
      (occurrence && _occurrence_storage(occurrence) == <static>) ||
      _declaration_is_private(c, <type>, spelling) ||
      (forward && _declaration_is_private(
        c, <binding>, forward)) ||
      (reverse && _declaration_is_private(
        c, <binding>, reverse)) ||
      (alternate && _declaration_is_private(
        c, <binding>, alternate)) ||
      private_native;
  if (inferred_private) storage = <static>;
  if (!c.shallow) {
    String path = _canonical_file(c, location);
    List key = %("parsed-protocol-adoption" $base $participant $path);
    Var previous;
    if (c.protocol_helpers.try_get(key, &previous)) {
      List row = previous;
      Type first_representation = _adoption_representation(row);
      List first_tag = _adoption_tag(row);
      if (first_representation != representation ||
          !List.equal(first_tag, tag_expression)) {
        List first_location = _adoption_location(row);
        String first = %"first: ${
          _location_string(first_location)}";
        String second = %"second: ${
          _location_string(location)}";
        String detail = %"${_type_spelling(base)}(${
          _type_spelling(participant)})";
        c.diagnostics.report(
          <protocol>,
          %"conflicting adoption declarations for $detail",
          location, %($first $second));
      }
    }
    else
      c.protocol_helpers[key] = _adoption_node(
        base, participant, storage, representation, tag_expression, location);
  }
  c._install_protocol_adoption(
    base, participant, storage, representation, tag, tag_expression, location);
  c.conforms.del(%($base $participant));
  c.proto_cache = %{};
  if (!c.shallow) _resolve_declared_adoption(c, base, participant, location);
  List published = _adoption_node(
    base, participant, storage, representation, tag_expression, location);
  c._retain_protocol_source_node(published, storage, location);
  return published;
}

/** Validates and installs one normalized protocol or adoption node.
    The node must carry a protocol record or supported adoption shape with its
    storage and source location. Installation invalidates cached protocol
    decisions and returns the canonical published node. Generated contexts may
    also retain that node in `Sym` for replay.
*/
List Compiler.publish_protocol_node(
  Compiler c, List node, Token participant_token,
  Token representation_token) {
  match (node) {
    case %(protocol
           (!set ?record
             ("protocol-record"
               ?(List base) (!is ? type string)
               (associated *) (members *)))
           external ?(List location)): {
      return c._publish_protocol_record(
        record, base, location);
    }
    case %(adopt
           ?(List base) ?(List participant)
           (!set ?storage (!or external static))
           ?(List location)):
      return c._publish_protocol_adoption(
        base, participant, storage,
        NULL, NULL, location, participant_token, representation_token);
    case %(adopt
           ("Var") ?(List participant)
           (!set ?storage (!or external static))
           (tag ?(List tag))
           ?(List location)):
      return c._publish_protocol_adoption(
        %("Var"), participant, storage,
        NULL, tag, location, participant_token,
        representation_token);
    case %(adopt
           ("Var") ?(List participant)
           (!set ?storage (!or external static))
           ?(List representation)
           ?(List location)):
      return c._publish_protocol_adoption(
        %("Var"), participant, storage,
        representation, NULL, location, participant_token,
        representation_token);
  }
  c.report_error(
    <macro>, "constructed protocol syntax is invalid",
    c.token, NULL);
}

// Participation exists only for a declared adoption row.
static int Compiler._is_adopted(
  Compiler compiler, Type base, Type participant) =>
    !!_adoption_visibility(compiler, base, participant);

static int _function_parts(
  Type signature, List *parameters, Type *result) {
  match (signature)
    case %((func ?arguments) *return_type): {
      *parameters = arguments;
      *result = return_type;
      return 1;
    }
  return 0;
}

static String _type_variable(Var value, Map variables) {
  String name = NULL;
  if (value is <string>) name = value.str();
  match (value)
    case %(?(String only)): name = only;
  if (!name) return NULL;
  return variables.contains(name) ? name : NULL;
}

static int _unify(
  Var pattern, Var actual, Map variables, Map bindings) {
  String variable = _type_variable(pattern, variables);
  if (variable) {
    Var bound;
    if (!bindings.try_get(variable, &bound)) {
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
  if (!_function_parts(actual, &actual_parameters, &actual_result))
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
  Array output = %[];
  foreach (Var item, value.list())
    output.push(_substitute(item, variables, bindings));
  List result = output.list_free();
  return result;
}

static Type _substitute_signature(
  Type signature, Map variables, Map bindings) {
  List parameters = signature.car().list().cadr();
  Type result = signature.cdr();
  List parameter_types = parameters.map(
    %!(Var parameter) =>
      _substitute(parameter, variables, bindings));
  Type result_type =
    _substitute(result, variables, bindings).list();
  Type final = %((func $parameter_types) @result_type);
  return final;
}

static int _exact_conversion(
  Type signature, Type parameter, Type result) {
  List parameters = NULL, Type actual_result = NULL;
  if (!_function_parts(signature, &parameters, &actual_result))
    return 0;
  return parameters && !parameters.cdr() &&
         parameters.car() == parameter &&
         actual_result == result;
}

static String _base_name(Type base) =>
  base.is_bare_typedef_name() ? base.car().str() : NULL;

// Prefer a typedef's bare diagnostic spelling.
static String _type_spelling(Type type) =>
  type.is_bare_typedef_name() ? type.car().str() : type.repr();

// The C spelling of a participant's implemented or generated member.
static String _member_spelling(Type participant, String member) =>
  %"${participant.car().str()}_$member";

static String _representation_error(Type representation) {
  String spelling = _type_spelling(representation);
  return %"Var representation $spelling has no fixed tag";
}

static Type _declared(Compiler compiler, String name) {
  if (compiler.sym.get(%("generated-protocol" $name)))
    return NULL;
  return compiler.sym.get(%($name));
}

static List _inherited_parameters(
  List parameters, Type owner, Type participant) {
  if (!parameters) return NULL;
  Var parameter = parameters.car();
  return cons(
    parameter == owner ? participant.var() : parameter,
    _inherited_parameters(parameters.cdr(), owner, participant));
}

static Type _receiver_relative_signature(
  Compiler compiler, List binding, Type signature, Type receiver) {
  Var stored;
  if (!compiler.semantic_binding_facts().try_get(%(self $binding), &stored))
    return signature;
  Type relative = stored, base = receiver.canonicalize().base_type();
  return relative.search_replace(<self>, base.car());
}

static Type _method_signature(
  Compiler compiler, Type owner, Type participant, String member,
  String *selected) {
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
  if (_function_parts(signature, &parameters, &result) &&
      parameters && parameters.car() == owner) {
    parameters = _inherited_parameters(
      parameters, owner, participant);
    signature = %((func $parameters) @result);
  }
  *selected = source;
  return signature;
}

#define PROTOCOL_VARIABLE 1
#define PROTOCOL_VARIADIC 2

static int _contents(Var value, String variable) {
  if (value is <string>)
    return value.str() == variable ? PROTOCOL_VARIABLE : 0;
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
         type.car().str() == variable;
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
  String name = participant.car().str();
  Var definition = compiler.sym.global_symbols()[%(typedef $name)];
  return definition is <list> ? definition.list() : NULL;
}

static void _install_native_bindings(
  Compiler compiler, Type participant, List rows) {
  match (rows)
    case %((? native *) *): {
      foreach (List row, rows)
        match (row)
          case %(?(String member) ? ? ?(Type expected) ? ?): {
            String generated = _member_spelling(participant, member);
            if (!compiler.sym.get(%($generated)))
              compiler.sym.define_global(%($generated), expected);
          }
    }
}

/* Native and ordinary resolution are the only conformance-row producers. A
   row carries base, participant, converters, type-variable maps, and member
   rows of `(name status source expected default-kind template)`. Consumers
   dispatch on `status`; a non-list cache value records failed resolution. */
static List Compiler._resolve_native_protocol_participant(
  Compiler compiler, Type base, Type participant, String binder,
  List associations, List templates, Type participant_definition,
  List *failure) {
  *failure = NULL;
  List key = %($base $participant);
  Var stored;
  if (compiler.conforms.try_get(key, &stored)) {
    if (stored is not <list>) return NULL;
    List conformance = stored;
    _install_native_bindings(
      compiler, participant, conformance.last().list().cdr());
    return conformance;
  }
  if (!participant.is_bare_typedef_name() || !participant_definition) {
    compiler.conforms[key] = 0;
    return NULL;
  }
  Map variables = %{}, bindings = %{};
  variables[binder] = 1;
  bindings[binder] = participant;
  foreach (List association, associations) {
    (String association_name, Type binding) = association;
    variables[association_name] = 1;
    bindings[association_name] = binding;
  }
  Array members = %[];
  foreach (List template, templates) {
    (String member_name, Type template_type, String native_name) = template;
    List requirement = _native_requirement(
      member_name, native_name, template_type, binder,
      participant_definition, base);
    if (requirement) {
      *failure = requirement;
      members.free();
      compiler.conforms[key] = 0;
      return NULL;
    }
    Type expected = _substitute_signature(
      template_type, variables, bindings);
    Map native_bindings = bindings.copy();
    native_bindings[binder] = base;
    Type native_signature = _substitute_signature(
      template_type, variables, native_bindings);
    Type alias_signature =
      participant_definition == base ? expected : native_signature;
    members.push(
      %(
      $member_name native $native_name $expected none $alias_signature
    ));
  }
  List rows = members.list_free();
  List conformance = %(
    protocol-conformance $base $participant "" ""
    $variables $bindings (members @rows)
  );
  compiler.conforms[key] = conformance;
  return conformance;
}

static String _reverse_binding(
  Compiler compiler, Type base, Type participant) {
  String base_name = _base_name(base);
  if (!base_name || !participant.is_bare_typedef_name()) return NULL;
  String participant_name = participant.car().str();
  String conventional =
    compiler.reverse_converter_spelling(base_name, %"", participant_name);
  Type found = _declared(compiler, conventional);
  if (_exact_conversion(found, base, participant)) return conventional;
  String alternate =
    compiler.reverse_converter_spelling(base_name, %"as_", participant_name);
  found = _declared(compiler, alternate);
  if (_exact_conversion(found, base, participant)) return alternate;
  return NULL;
}

static String _forward_binding(
  Compiler compiler, Type base, Type participant) {
  String base_name = _base_name(base);
  if (!base_name || !participant.is_bare_typedef_name()) return NULL;
  String binding = %"${participant.car().str()}_${base_name.lower()}";
  Type found = _declared(compiler, binding);
  if (!_exact_conversion(found, participant, base)) return NULL;
  return binding;
}

static List _resolve_members(
  Compiler compiler, Type base, String binder, List associations,
  List templates, Type participant, Map *variables_out, Map *bindings_out) {
  Type representation = base == %("Var")
    ? _adoption_representation(
      _visible_adoption_row(compiler, base, participant))
    : NULL;
  Map variables = %{}, defaults = %{}, bindings = %{};
  variables[binder] = 1;
  bindings[binder] = participant;
  foreach (List association, associations) {
    (String association_name, Type value) = association;
    variables[association_name] = 1;
    defaults[association_name] = value;
  }

  Array resolved = %[];
  foreach (List row, templates)
    match (row)
      case %(?(String member_name) ?(Type template_type) ?): {
        Type actual = NULL;
        Symbol status = <no-member>, String selected = NULL;
        String binding = _member_spelling(participant, member_name);
        actual = _declared(compiler, binding);
        if (!actual) {
          String imported = compiler.imported_spelling(binding);
          if (imported) {
            actual = _declared(compiler, imported);
            if (actual) binding = imported;
          }
        }
        if (actual) selected = binding;
        foreach (Type owner,
                 (base != %("Var") || representation) && !actual
                   ? _ancestry(compiler, participant).cdr() : NULL) {
          if (owner == base) break;
          if (base == %("Var") && owner != representation) continue;
          actual = _method_signature(
            compiler, owner, participant, member_name, &selected);
          if (actual || base == %("Var")) break;
        }
        if (actual) {
          Map candidate = bindings.copy();
          if (_unify_signature(
            template_type, actual, variables, candidate)) {
            bindings = candidate;
            status = <implmntd>;
          }
          else status = <sig-cnflct>;
        }
        resolved.push(
          %($member_name $status $selected $actual none $template_type));
      }

  foreach (Var (name, value), defaults) bindings.setdefault(name, value);

  Array final = %[];
  foreach (List row, resolved)
    match (row)
      case %(?(String member_name) ?(Symbol status) ?(String source)
             ? ? ?(Type template_type)): {
        Type expected = _substitute_signature(
          template_type, variables, bindings);
        Symbol default_kind = <none>;
        if (status == <no-member>) {
          String base_name = _base_name(base);
          if (base_name && base != %("Var")) {
            String fallback = %"${base_name}_$member_name";
            Type fallback_type = _declared(compiler, fallback);
            Map base_bindings = bindings.copy();
            base_bindings[binder] = base;
            Type base_signature = _substitute_signature(
              template_type, variables, base_bindings);
            if (fallback_type == base_signature) {
              status = <base-dflt>;
              source = fallback;
              default_kind = <ordinary>;
            }
          }
        }
        final.push(
          %($member_name $status $source $expected $default_kind
            $template_type));
      }
  resolved.free();
  *variables_out = variables;
  *bindings_out = bindings;
  return final.list_free();
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

static List _descriptor_requirement(
  Compiler compiler, Type base, String binder, String member, Type template,
  String forward, String reverse) {
  if (base != %("Var") ||
      !compiler.sym.lookup_field(%(struct "VarMethods"), %($member)))
    return NULL;
  return _conversion_requirement(
    binder, member, template, <thunk>, forward, reverse);
}

static List _ordinary_requirement(
  Compiler compiler, Type base, String binder, List rows, String forward,
  String reverse) {
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
            compiler, base, binder, member, template, forward, reverse);
          if (requirement) return requirement;
        }
      }
  return NULL;
}

static List Compiler._resolve_ordinary_protocol(
  Compiler compiler, Type base, Type participant, String binder,
  List associations, List templates, List *failure) {
  *failure = NULL;
  Var stored;
  List key = %($base $participant);
  if (compiler.conforms.try_get(key, &stored))
    return stored is <list> ? stored.list() : NULL;
  String base_name = _base_name(base);
  if (!base_name || !participant.is_bare_typedef_name()) goto does_not_conform;
  String forward = _forward_binding(
    compiler, base, participant);
  String reverse = _reverse_binding(
    compiler, base, participant);
  Map variables = NULL, bindings = NULL;
  List rows = _resolve_members(
    compiler, base, binder, associations, templates,
    participant, &variables, &bindings);
  List requirement = _ordinary_requirement(
    compiler, base, binder, rows, forward, reverse);
  if (requirement) {
    *failure = requirement;
    goto does_not_conform;
  }
  List conformance = %(
    protocol-conformance $base $participant $forward $reverse
    $variables $bindings (members @rows)
  );
  compiler.conforms[key] = conformance;
  return conformance;
does_not_conform: compiler.conforms[key] = 0;
  return NULL;
}

/** Resolves every visible adoption into the current conformance registry.
    Resolution starts from an empty registry; diagnostics are located only for
    adoptions owned by the current translation unit.
*/
void Compiler.resolve_protocols(Compiler compiler) {
  compiler.conforms = %{};
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

/* Live collection has complete declarations and protocol rows but does not
   run generation. Publish its external call signatures so live and artifact
   lookup enforce the same conversions. */
static void _install_generated_protocol_symbol(
  Compiler compiler, Type participant, String member, Type signature) {
  String generated = _member_spelling(participant, member);
  compiler.sym.define_global(
    %("generated-protocol" $generated), %(generated));
  compiler.sym.define_global(%($generated), signature);
}

/** Publishes generated protocol call signatures into a live symbol map.
    The map becomes the active `Sym` table, then protocol rows are rebuilt and
    resolved so live collection exposes the same external native aliases and
    ordinary generated members as artifact-backed lookup. A null map is a
    no-op.
*/
void Compiler.install_generated_protocol_symbols(
  Compiler c, Map symbols) {
  if ((void *) symbols == NULL) return;
  c.sym.reset(symbols);
  c.rebuild_protocols(symbols);
  c.resolve_protocols();
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
                _install_generated_protocol_symbol(
                  c, participant, member, signature);
          continue;
        }
        if (!c.fn_defs.contains(forward)) continue;
        if (c.sym.resolve_numeric_type(participant) &&
            participant != %("Symbol"))
          continue;
        foreach (List row, rows)
          match (row)
            case %(?(String member) base-dflt ? ? ordinary ?): {
              List decision = _generated_owner(c, participant, member);
              match (decision)
                case %(owner ? ? ?signature external):
                  _install_generated_protocol_symbol(
                    c, participant, member, signature.list());
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
        if (compiler.protocol_helpers.contains(dedupe)) continue;
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
      %"${position.str()} type, which protocol fallback adapters " +
      "do not support";
  if (adapter == <fallback> && direction == <reverse>)
    return %"${prefix}member '$member' returns T, so $owner needs " +
      %"'$base_repr.$lowered' or '$base_repr.as_$lowered'";
  if (adapter == <fallback>)
    return %"${prefix}member '$member' fallback requires forward " +
      %"conversion '$participant_repr.${base_repr.lower()}'";
  if (adapter == <thunk> && direction == <nested>)
    return %"${prefix}member '$member' uses T inside a compound " +
      %"${position.str()} type, which protocol descriptor thunks " +
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

static void _resolve_protocol_record(
  Compiler compiler, Type base, Type participant, List location, String binder,
  List associations, List templates) {
  int native = _is_native(templates);
  List conformance = NULL, failure = NULL;
  if (native) {
    Type definition = _participant_definition(compiler, participant);
    conformance = compiler._resolve_native_protocol_participant(
      base, participant, binder, associations, templates,
      definition, &failure);
  }
  else
    conformance = compiler._resolve_ordinary_protocol(
      base, participant, binder, associations, templates, &failure);

  if (!conformance) {
    if (!location) return;
    String base_repr = _type_spelling(base);
    String participant_repr = _type_spelling(participant);
    String owner = %"$base_repr($participant_repr)";
    String prefix = %"$participant_repr does not satisfy $owner: ", detail;
    if (failure)
      detail =
        _requirement_detail(base, participant, failure);
    else if (native)
      detail = %"${prefix}its typedef is not a native alias of $base_repr";
    else {
      String base_name = _base_name(base);
      String lowered =
        participant.is_bare_typedef_name()
          ? participant.car().str().lower() : participant_repr;
      String forward =
        base_name ? %"$participant_repr.${base_name.lower()}" : NULL;
      Type forward_type =
        forward && base_name
          ? _declared(
            compiler,
            %"${participant.car().str()}_${base_name.lower()}")
          : NULL;
      if (base_name && !_exact_conversion(
        forward_type, participant, base))
        detail = %"${prefix}no forward conversion '$forward'";
      else
        detail = %"${prefix}no reverse conversion '$base_repr.$lowered' " +
          %"or '$base_repr.as_$lowered'";
    }
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
      location, NULL
    );
    return;
  }
  match (record)
    case %(? ? ?(String binder) (associated *associations)
           (members *members)):
      _resolve_protocol_record(
        compiler, base, participant, location, binder, associations, members);
}

/** Returns the resolved conformance for `participant` and `base`, if any.
    Lookup canonicalizes the participant and may use the nearest adopted
    typedef ancestor. Native conformances install their generated bindings
    before the cached conformance row is returned.
*/
List Compiler.protocol_members_for(
  Compiler compiler, Type participant, Type base) {
  participant = participant.canonicalize();
  Type owner = participant;
  if (!compiler._is_adopted(base, owner)) {
    List ancestry = _ancestry(compiler, participant).cdr();
    for (; ancestry; ancestry = ancestry.cdr()) {
      owner = ancestry.car();
      if (compiler._is_adopted(base, owner)) break;
    }
    if (!ancestry) return NULL;
  }
  Var stored = compiler.conforms[%($base $owner)];
  if (stored is not <list>) return NULL;
  List conformance = stored;
  _install_native_bindings(
    compiler, owner, conformance.last().list().cdr());
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
  if (compiler.proto_cache.try_get(cache_key, &cached)) return cached.int();
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
static const struct { Symbol op, member; int derived; } operator_members[] = {
  { <+>,  <add>,   0 },  { <->,  <sub>,   0 },  { <*>,  <mul>,     0 },
  { </>,  <div>,   0 },  { <%>,  <mod>,   0 },  { <@>,  <matmul>,  0 },
  { <==>, <equal>,   0 },
  { <!=>, <equal>, 1 },  { <"<">,  <compare>, 1 },  { <"<=">, <compare>, 1 },
  { <">">,  <compare>, 1 },  { <">=">, <compare>, 1 }
};

static Symbol _operator_member_row(Symbol op, int derived) {
  int count = sizeof(operator_members) / sizeof(operator_members[0]);
  for (int i = 0; i < count; i++)
    if (operator_members[i].op == op && operator_members[i].derived == derived)
      return operator_members[i].member;
  return 0;
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
    adoption is owned by this unit, making the output suitable for comparing
    live and artifact symbol modes.
*/
void Compiler.dump_conformance(Compiler compiler, Map globs) {
  Array names = %[];
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

/** Returns the protocol member used to derive a comparison operator.
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
  if (compiler.proto_cache.try_get(key, &cached))
    return cached is <list> ? cached.list() : NULL;
  List result = compute(compiler);
  compiler.proto_cache[key] = result ? result : 0;
  return result;
}

static List _ordered_occurrences(Compiler compiler) =>
  _proto_cached(compiler, <proto-ordr>, %!(Compiler &compiler) => {
    Array ordered = %[];
    foreach (Var (base, occurrence), compiler.protocols)
      ordered.push(%($base $occurrence));
    ordered.sort();
    return ordered.list_free();
  });

static List _ancestry(Compiler compiler, Type participant) => _proto_cached(
    compiler, %("protocol-ancestry" $participant),
    %!(Compiler &compiler) => {
      Array ancestry = %[], Type current = participant;
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

static List _member_row(
  Compiler compiler, List protocols, Type participant, String member) {
  List found = NULL;
  _each_adopted_row(
    compiler, protocols, participant,
    %!(Compiler &compiler, Type base, List row) using &found => {
      (void) compiler; (void) base;
      if (row.car().str() == member) {
        found = row;
        return 1;
      }
      return 0;
    });
  return found;
}

/* Select the sole generated owner across all adopted protocols. */
static List _generated_owner(
  Compiler compiler, Type participant, String member_name) {
  List cache_key = %("protocol-generated-owner" $participant $member_name);
  return _proto_cached(compiler, cache_key, %!(Compiler &compiler) => {
    Array candidates = %[], List result = NULL, first_linkage = NULL;
    Symbol first_storage = 0;
    _each_adopted_row(
      compiler, _ordered_occurrences(compiler), participant,
      %!(Compiler &compiler, Type base, List row)
        using &result, &first_linkage, &first_storage => {
        match (row)
          case %(?(String member) base-dflt ?(String source)
                 ?(Type expected) ordinary ?): {
            if (member != member_name) return 0;
            Symbol storage = _adoption_visibility(
              compiler, base, participant);
            List owner = %(owner $base $source $expected $storage);
            candidates.push(owner);
            if (storage == <mixed>) {
              result = %(linkage $owner $owner);
              return 1;
            }
            if (!first_linkage) {
              first_linkage = owner;
              first_storage = storage;
            }
            else if (first_storage != storage) {
              result = %(linkage $first_linkage $owner);
              return 1;
            }
          }
        return 0;
      });
    List owners = candidates.list_free();
    if (!result)
      match (owners) {
        case %(?only): result = only;
        case %(?first ?second *rest):
          result = %(conflict $first $second @rest);
      }
    return result;
  });
}

static void _report_generated_collision(
  Compiler compiler, Type participant, String member, Symbol kind, List first,
  List second) {
  (Type first_base, String first_source, Type first_expected,
   Symbol first_storage) = first.cdr();
  (Type second_base, String second_source, Type second_expected,
   Symbol second_storage) = second.cdr();
  List dedupe = %("protocol-generated-collision" $participant $member);
  if (compiler.protocol_helpers.contains(dedupe)) return;
  compiler.protocol_helpers[dedupe] = 1;
  int linkage_conflict = kind == <linkage>;
  String first_repr = _type_spelling(first_base);
  String second_repr = _type_spelling(second_base);
  String participant_repr = _type_spelling(participant);
  int incompatible_signatures = !List.equal(first_expected, second_expected);
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

  List notes =
    linkage_conflict
      ? %(
          "$first_repr adoption: ${first_storage.str()}"
          "$second_repr adoption: ${second_storage.str()}"
        )
      : incompatible_signatures
      ? %(
          "$first_repr signature: ${first_expected.repr()}"
          "$second_repr signature: ${second_expected.repr()}"
        )
      : %(
          "$first_repr default source: $first_source"
          "$second_repr default source: $second_source"
        );
  List row = _visible_adoption_row(compiler, first_base, participant);
  compiler.diagnostics.report(
    <protocol>, message, _adoption_location(row), notes);
}

static List _resolve_protocol_member(
  Compiler compiler, Type participant, String member_name, int method_path) {
  // A const or volatile receiver adopts exactly what its unqualified type
  // adopts, so conformance is keyed on the unqualified participant.
  participant = participant.canonicalize();
  List cache_key =
    %("protocol-member" ${method_path ? <method> : <operator>}
      $participant $member_name);
  return _proto_cached(compiler, cache_key, %!(Compiler &compiler) => {
    List protocols = _ordered_occurrences(compiler);
    List base_ancestry = _ancestry(compiler, participant);
    /* A generated member is selected before a direct base alias. */
    foreach (Type current, base_ancestry) {
      List decision = _generated_owner(compiler, current, member_name);
      match (decision)
        case %(owner ? ? ?signature ?): {
          String source = _member_spelling(current, member_name);
          if (source == compiler.fn_name) return %();
          List binding = compiler.sym.reference(%($source), NULL);
          return %($binding $signature);
        }
    }
    foreach (List entry, protocols) {
      (Type base, List occurrence) = entry;
      List record = occurrence.car();
      List declared = record.last().list().cdr();
      int matches = List.equal(base, participant);
      for (List ancestry = base_ancestry ? base_ancestry.cdr() : NULL;
           !matches && ancestry; ancestry = ancestry.cdr())
        matches = List.equal(base, ancestry.car());
      if (!matches) continue;
      String base_name = _base_name(base);
      if (!base_name) continue;
      int declares_member = 0;
      foreach (List row, declared)
        if (row.car().str() == member_name) {
          declares_member = 1;
          break;
        }
      if (!declares_member) continue;
      String source = %"${base_name}_$member_name";
      Type signature = compiler.sym.get(%($source));
      if (!signature || !signature.is_function()) continue;
      if (source == compiler.fn_name) return %();
      List binding = compiler.sym.reference(%($source), NULL);
      return %($binding $signature);
    }

    foreach (Type current, _ancestry(compiler, participant)) {
      List row = _member_row(compiler, protocols, current, member_name);
      if (!row) continue;
      match (row)
        case %(? ?(Symbol status) ?(String source) ?(Type signature) ? ?): {
          if (status == <implmntd>) {
            if (source == compiler.fn_name) return %();
            List binding = compiler.sym.reference(%($source), NULL);
            return %($binding $signature);
          }
          if (status == <native>) {
            String binding_name = _member_spelling(current, member_name);
            if (binding_name == compiler.fn_name) return %();
            List binding = compiler.sym.reference(%($binding_name), NULL);
            return %($binding $signature);
          }
        }
      return %();
    }
    return %();
  });
}

/** Resolves an operator-facing protocol member for `participant`.
    Returns a `(binding signature)` pair for the selected implementation or
    null when no eligible resolved member exists; positive and negative
    results are cached.
*/
List Compiler.resolve_protocol_member(
  Compiler compiler, Type participant, String member_name) =>
    _resolve_protocol_member(compiler, participant, member_name, 0);

/** Resolves a method-facing protocol member for `participant`.
    Returns a `(binding signature)` pair for the selected implementation or
    null when no eligible resolved member exists; positive and negative
    results are cached separately from operator lookup.
*/
List Compiler.resolve_protocol_method(
  Compiler compiler, Type participant, String member_name) =>
    _resolve_protocol_member(compiler, participant, member_name, 1);

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
  if (c.protocol_helpers.try_get(key, &stored)) return stored.str();

  List resolved = c.resolve_protocol_member(participant, member);
  if (!resolved) return NULL;
  List (source_binding, source_type) = resolved;
  List parameters = source_type.car().list().cadr();
  Type result = source_type.cdr();
  Type rhs_type = NULL;
  match (parameters)
    case %(?receiver ?rhs):
      if (List.equal(receiver, participant) &&
          List.equal(result, participant))
        rhs_type = rhs.list();
  if (!rhs_type) return NULL;

  String suffix = postfix ? "postfix" : "update";
  String name =
    %"_x2c_proto_${participant.car().str().lower()}_${member}_$suffix";
  List helper_binding = c.sym.introduce(name);
  List lhs_binding = c.sym.introduce("lhs");
  List op_binding = c.sym.introduce("op");
  Type pointer = cons(<*>, cons(<volatile>, participant));
  Type pointer_base = cons(<volatile>, participant);
  List lhs_pointer = %(expr $pointer (ident $lhs_binding));
  List zero = %(expr (int) (literal (int) "0"));
  List current = %(expr $participant (index $lhs_pointer $zero));
  List call_rhs = NULL, old_declaration = NULL, return_value = current;
  Array declarations = %[];
  declarations.push(%(param $pointer_base (bind $lhs_binding (*))));
  declarations.push(%(param ("Symbol") (bind $op_binding ())));

  if (postfix) {
    List one = %(expr (int) (literal (int) "1"));
    call_rhs = c.convert_expression(one, rhs_type);
    List old_binding = c.sym.introduce("old");
    old_declaration = %(
      declare $participant
        (bindings (op = (bind $old_binding ()) $current))
    );
    return_value = %(expr $participant (ident $old_binding));
  }
  else {
    List rhs_binding = c.sym.introduce("rhs");
    declarations.push(%(param $rhs_type (bind $rhs_binding ())));
    call_rhs = %(expr $rhs_type (ident $rhs_binding));
  }

  List call = %(expr $result
    (call
      (expr $source_type (ident $source_binding))
      (args $current $call_rhs)));
  List assignment = %(stmnt (expr $participant (op = $current $call)));
  List body = postfix
            ? %(block $old_declaration $assignment
                (return $participant $return_value))
            : %(block $assignment (return $participant $return_value));
  List function = %(
    function (static @participant)
      (bind $helper_binding ((fnmod (params @{declarations.list_free()}))))
      $body
  );
  c.add_early(function);
  c.protocol_helpers[key] = name;
  return name;
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
  if (c.protocol_helpers.try_get(key, &stored)) return stored.list();

  List parameters = signature.car().list().cadr();
  Type result = signature.cdr();
  Type resolved_result = c.sym.resolve_key(result);
  long callee_identity = (long) binding;
  int fresh = c.protocol_helpers.contains(%"fresh-callee $callee_identity");
  /* An ordinary call may return its input or a view into it. Without a
     fresh-result contract, keep that input alive in its enclosing scope. */
  if (!fresh && (resolved_result.is_pointer() ||
                 resolved_result.is_aggregate()))
    return NULL;
  Array declarations = %[], arguments = %[], discards = %[];
  int index = 0;
  foreach (Type parameter, parameters) {
    List argument_binding = c.sym.introduce(%"a$index");
    declarations.push(parameter.parameter_ast(argument_binding));
    arguments.push(%(expr $parameter (ident $argument_binding)));
    if (which & (1 << index)) {
      List drop = c.resolve_protocol_member(parameter, "discard");
      if (drop) {
        List (drop_binding, drop_type) = drop;
        discards.push(%(stmnt (expr (void)
          (call (expr $drop_type (ident $drop_binding))
                (args (expr $parameter (ident $argument_binding)))))));
      }
    }
    index++;
  }
  if (!discards.len()) return NULL;

  String name = %"_x2c_discard_${stem}_$which";
  List helper_binding = c.sym.introduce(name);
  List value_binding = c.sym.introduce("value");
  List call = %(expr $result
    (call (expr $signature (ident $binding))
          (args @{arguments.list_free()})));
  List body = List.equal(result, %(void))
    ? %(block (stmnt $call) @{discards.list_free()} (return))
    : %(block
        (declare $result (bindings (op = (bind $value_binding ()) $call)))
        @{discards.list_free()}
        (return $result (expr $result (ident $value_binding))));
  List function = %(
    function (static @result)
      (bind $helper_binding ((fnmod (params @{declarations.list_free()}))))
      $body
  );
  c.add_early(function);
  List entry = %($helper_binding $signature);
  c.protocol_helpers[key] = entry;
  /* Wrapping a call preserves its return ownership. Discarding an argument
     does not make an arbitrary method's borrowed result fresh. */
  long identity = (long) helper_binding;
  c.protocol_helpers[%"discard-helper $identity"] = 1;
  if (fresh) c.protocol_helpers[%"fresh-callee $identity"] = 1;
  return entry;
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

static List _parameter_declarations(
  Compiler compiler, List types, Array bindings) {
  Array declarations = %[], int index = 0;
  foreach (Type type, types) {
    List binding = compiler.sym.introduce(%"a$index");
    bindings.push(binding);
    declarations.push(type.parameter_ast(binding));
    index++;
  }
  List result = declarations.list_free();
  return result;
}

static int _variable_is(Var template, Map variables, String name) {
  String variable = _type_variable(template, variables);
  return variable && variable == name;
}

static List _adapter_argument(
  Compiler compiler, List expression, Type template, Type actual,
  Map variables, String binder, String reverse) {
  if (_variable_is(template, variables, binder))
    return %(expr $actual (call $reverse (args $expression)));
  if (_type_variable(template, variables))
    return compiler.convert_expression(expression, actual);
  return expression;
}

static List _adapter_result(
  Compiler compiler, List expression, Type template, Type target,
  Map variables) {
  if (_type_variable(template, variables))
    return compiler.convert_expression(expression, target);
  return expression;
}

static List Compiler._generate_protocol_function(
  Compiler compiler, String name, int make_static, Type target_signature,
  Type source_signature, Type template, Map variables, String binder,
  String source, String reverse, List *binding_out) {
  List target_parameters = target_signature.car().list().cadr();
  Type target_result = target_signature.cdr();
  List source_parameters = source_signature.car().list().cadr();
  Type source_result = source_signature.cdr();
  List template_parameters = template.car().list().cadr();
  Type template_result = template.cdr();
  Array parameter_bindings = %[];
  List declarations = _parameter_declarations(
    compiler, target_parameters, parameter_bindings);
  Array arguments = %[];
  List target_at = target_parameters, template_at = template_parameters;
  List source_at = source_parameters;
  for (int i = 0; target_at;
       i++, target_at = target_at.cdr(), template_at = template_at.cdr(),
       source_at = source_at.cdr()) {
    List argument = %(expr ${target_at.car()}
      (ident ${parameter_bindings[i]}));
    arguments.push(
      _adapter_argument(
        compiler, argument, template_at.car(), source_at.car(),
        variables, binder, reverse)
    );
  }
  List source_binding = compiler.sym.reference(%($source), NULL);
  List call = %(expr $source_result
    (call (expr $source_signature (ident $source_binding))
      (args @{arguments.list_free()})));
  List result = _adapter_result(
    compiler, call, template_result, target_result, variables);
  List function_binding = compiler.sym.reference(%($name), NULL);
  if (make_static) function_binding = compiler.sym.introduce(name);
  if (binding_out) *binding_out = function_binding;
  List storage = make_static ? %(static inline @target_result) : target_result;
  List function = %(
    function $storage
      (bind $function_binding ((fnmod (params @declarations))))
      (block (return $target_result $result))
  );
  parameter_bindings.free();
  return function;
}

static int _defines_function(Compiler compiler, String name) {
  List binding = compiler.sym.reference(%($name), NULL);
  Var stored;
  if (!binding ||
      !compiler.semantic_binding_facts().try_get(
        %(completion $binding), &stored))
    return 0;
  Symbol state = stored.list().car();
  return state == <definition> || state == <completed>;
}

static List _declaration_from_signature(
  Compiler compiler, String name, Type signature, int make_static) {
  List parameters = signature.car().list().cadr();
  Type result = signature.cdr();
  Array declarations = %[];
  foreach (Type type, parameters) declarations.push(type.parameter_ast(NULL));
  List binding = compiler.sym.reference(%($name), NULL);
  List storage = make_static ? %(static @result) : result;
  List declaration = %(
    declare $storage
      (bindings (bind $binding ((fnmod (params @{declarations.list_free()})))))
  );
  return declaration;
}

static List Compiler._generate_native_alias(
  Compiler compiler, Type participant, String member, String source,
  Type signature, int make_static) {
  String target = _member_spelling(participant, member);
  List declaration = _declaration_from_signature(
    compiler, target, signature, make_static);
  if (!make_static) compiler.record_generated_header_symbol(target, signature);
  List native_binding = compiler.sym.reference(%($source), NULL);
  return compiler.finish_foreign_alias(
    declaration, %(expr $signature (ident $native_binding)));
}

static int _starts_private_region(List node) {
  match (node) {
    case %((!or function falias) *): return 1;
    case %(declare ?type *): return type.type().is_static();
    case %(preproc ?text *): return text.str().contains("pragma private");
  }
  return 0;
}

static List _insert_at_visibility_boundary(
  List ast, List declaration, int declaration_private, List additions,
  int make_static) {
  Array output = %[], int eligible = 0, inserted = 0;
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
  List result = output.list_free();
  return result;
}

static List _string_literal(Compiler compiler, String value) {
  (void) compiler;
  String spelling = %"\"$value\"";
  List chars = %(expr (* char) (literal (* char) $spelling));
  return %(expr ("String") (call "String_new" (args $chars)));
}

static void Compiler._generate_descriptor_registration(
  Compiler compiler, Type participant, String name, Symbol explicit_tag,
  List thunks, int central_initializer) {
  String methods_name = compiler.fresh_name("_x2c_protocol_methods");
  List methods_binding = compiler.sym.introduce(methods_name);
  Array fields = %[];
  foreach (List row, thunks) {
    (String member, List thunk_binding, Type thunk_type) = row;
    fields.push(
      %(
      dotinit ($member)
        (expr $thunk_type (ident $thunk_binding))
    ));
  }
  List declaration = %(
    declare (static "VarMethods")
      (bindings (bind $methods_binding ()))
  );
  List methods_type = %(decl ("VarMethods") (bindings (bind () ())));
  List methods_literal = %(expr () (composite (commas @{fields.list_free()})));
  List methods_value = %(
    expr ("VarMethods") (cast $methods_type $methods_literal)
  );
  /* A participant with no thunks still needs its tag registered, and the
     file-scope table is already zero, so skip the assignment rather than
     emit an empty initializer, which C only accepts from C23 on. */
  List assignment = thunks ? %(
    stmnt
      (expr ("VarMethods")
        (op = (expr ("VarMethods") (ident $methods_binding)) $methods_value))
  ) : NULL;
  Symbol tag_symbol = participant.var_tag();
  List early_call = %(
    expr (int)
      (call "x2c_register_builtin_descriptor"
        (args
          (expr ("Symbol") (literal ("Symbol") $name $tag_symbol))
          (expr ("VarMethods") (ident $methods_binding))))
  );
  List fallback = %(
    stmnt
      (expr (void)
        (call "x2c_register_descriptor"
          (args
            ${_string_literal(compiler, name)}
            (expr ("VarMethods") (ident $methods_binding)))))
  );
  List registration = %(if (expr (int) (op ! $early_call)) (block $fallback));
  List explicit_call = NULL;
  if (explicit_tag)
    explicit_call = %(
      expr (void)
        (call "x2c_register_tagged_descriptor"
          (args
            (expr ("Symbol")
              (literal ("Symbol") ${explicit_tag.str()} $explicit_tag))
            ${_string_literal(compiler, name)}
            (expr ("VarMethods") (ident $methods_binding))))
    );
  compiler.add_early(declaration);
  List call = explicit_tag ? explicit_call : early_call;
  if (central_initializer) {
    if (assignment) compiler.add_protocol_init(assignment);
    compiler.add_protocol_init(%(stmnt $call));
  }
  else {
    if (assignment) compiler.add_early_init(assignment);
    compiler.add_early_init(explicit_tag ? %(stmnt $call) : registration);
  }
}

static void _report_requirement_at_adoption(
  Compiler compiler, Type base, Type participant, List failure) {
  List dedupe =
    %("protocol-adapter-requirement" $base $participant ${failure.car()});
  if (compiler.protocol_helpers.contains(dedupe)) return;
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
      Type returns = result.type().declared();
      List value = %(expr ("Var") (ident $boxed));
      List fallback = NULL;
      if (member == "str" || member == "repr")
        fallback = %(expr ("String")
          (call "Var_pointer_string" (args $value)));
      else match (remaining)
        case %((param ? (bind ?output ?))):
          fallback = %(expr ("Buffer")
            (call "Var_write_pointer_repr"
              (args $value (expr ("Buffer") (ident $output)))));
      List path = compiler.sym.introduce("render_path");
      compiler.semantic_binding_facts()[%(automatic $path)] = 1;
      compiler.semantic_binding_facts()[%(type $path)] = %("RenderPath");
      List address = %(expr (* "RenderPath")
        (op & (expr ("RenderPath") (ident $path))));
      List enter = %(expr (int)
        (call "RenderPath_enter" (args $address
          (expr (* void) (call "Var_pointer" (args $value))))));
      return %(function $result $declarator
        (block
          (declare ("RenderPath") (bindings (bind $path ())))
          (if (expr (int) (op ! $enter)) (return $returns $fallback))
          (defer (stmnt (expr (void)
            (call "RenderPath_leave" (args $address)))))
          @body));
    }
  return function;
}

static List Compiler._generate_protocol_thunk(
  Compiler compiler, Type participant, String member, Type expected,
  Type template, Map variables, Map bindings, String binder, String source,
  String reverse) {
  Map erased = bindings.copy();
  foreach (Var variable, variables.keys()) erased[variable] = %("Var");
  Type target = _substitute_signature(template, variables, erased);
  String participant_name = participant.car().str().lower();
  String thunk_name =
    compiler.fresh_name(%"proto_${participant_name}_$member");
  List thunk_binding = NULL;
  List function = compiler._generate_protocol_function(
    thunk_name, 1, target, expected, template,
    variables, binder, source, reverse, &thunk_binding);
  if ((member == "str" || member == "repr" || member == "write_str" ||
       member == "write_repr") &&
      compiler.sym.normalize_declared_type(participant).is_aggregate())
    function = _guard_value_rendering(compiler, function, member);
  compiler.add_early(function);
  return %($member $thunk_binding $target);
}

static void Compiler._generate_ordinary_protocol_adapters(
  Compiler c, Type base, Type participant, String forward,
  String reverse, Map variables, Map bindings, String binder, List rows,
  int central_initializer) {
  List adoption = _visible_adoption_row(c, base, participant);
  int shares_var_tag = base == %("Var") &&
    _adoption_representation(adoption);
  Array thunks = %[];
  foreach (List row, rows)
    match (row)
      case %(?(String member) ?(Symbol status) ?(String source)
             ?(Type expected) ? ?(Type template)): {
        if (status == <base-dflt>) {
          List decision = _generated_owner(c, participant, member);
          match (decision) {
            case %(owner ? ? ? ?storage): {
              int make_static = storage == <static>;
              String generated = _member_spelling(participant, member);
              c.add_early(
                c._generate_protocol_function(
                  generated, make_static, expected,
                  c.sym.get(%($source)), template,
                  variables, binder, source, forward, NULL)
              );
              if (!make_static)
                c.record_generated_header_symbol(generated, expected);
            }
            case %(
              (!set ?kind (!or linkage conflict))
              ?first ?second *
            ):
              _report_generated_collision(
                c, participant, member, kind,
                first, second);
          }
          continue;
        }
        if (status == <no-member>) {
          if (base != %("Var") || shares_var_tag) continue;
          List decision = _generated_owner(c, participant, member);
          match (decision) {
            case %(owner ? ? ?owner_expected ?): {
              List requirement = _descriptor_requirement(
                c, base, binder, member, template, forward, reverse);
              if (requirement) {
                _report_requirement_at_adoption(
                  c, base, participant, requirement);
                continue;
              }
              String inherited = _member_spelling(participant, member);
              Type inherited_type = owner_expected.list();
              c.add_early(
                _declaration_from_signature(
                  c, inherited, inherited_type, 0)
              );
              if (!c.sym.lookup_field(%(struct "VarMethods"), %($member)))
                continue;
              thunks.push(
                c._generate_protocol_thunk(
                  participant, member, inherited_type, template,
                  variables, bindings, binder, inherited, reverse)
              );
            }
            case %(
              (!set ?kind (!or linkage conflict))
              ?first ?second *
            ):
              _report_generated_collision(
                c, participant, member, kind,
                first, second);
          }
          continue;
        }
        if (status != <implmntd> || base != %("Var") || shares_var_tag)
          continue;
        if (!c.sym.lookup_field(%(struct "VarMethods"), %($member)))
          continue;
        thunks.push(
          c._generate_protocol_thunk(
            participant, member, expected, template,
            variables, bindings, binder, source, reverse)
        );
      }
  List thunk_rows = thunks.list_free();
  if (base == %("Var") && !shares_var_tag) {
    List tag_expression = _adoption_tag(adoption);
    Symbol explicit_tag = _protocol_tag_value(tag_expression);
    String name = participant.car().str();
    if (!explicit_tag) name = name.lower();
    c._generate_descriptor_registration(
      participant, name, explicit_tag, thunk_rows, central_initializer);
  }
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
  Array ordered = %[];
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
          Var stored;
          if (!c.protocol_helpers.try_get(
            %("source-typedef" ${participant.car()}), &stored))
            continue;
          (List source, int private) = stored;
          int make_static =
            _adoption_visibility(c, base, participant) == <static>;
          Array aliases = %[];
          foreach (List row, rows)
            match (row)
              case %(?(String member) ? ?(String binding) ? ?
                     ?(Type signature)):
                aliases.push(c._generate_native_alias(
                  participant, member, binding, signature, make_static));
          ast = _insert_at_visibility_boundary(
            ast, source, private, aliases.list_free(), make_static);
          continue;
        }
        if (!_defines_function(c, forward)) continue;
        if (c.sym.resolve_numeric_type(participant) &&
            participant != %("Symbol"))
          continue;
        match (c._record(base))
          case %(? ? ?(String binder) ? ?):
            c._generate_ordinary_protocol_adapters(
              base, participant, forward, reverse, variables, bindings,
              binder, rows, central_initializer);
      }
  ordered.free();
  return ast;
}

static List _parse_associated_type(
  Compiler c, Map names, String participant) {
  (void) participant;
  c.expect(<associated>);
  if (c.peek(0) != <ident>)
    c.report_error(
      <protocol>, "expected associated type name", c.token, NULL);
  String name = c.token.text;
  c.next();
  if (names.contains(name))
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
  String name = NULL;
  match (identity)
    case %((!or (!is ?owner type <string>)
                ((!is ?owner type <string>)))
           (!is ?member type <string>)):
      if (owner.str() == participant) name = member.str();
  if (!name) {
    String full_name = binding_identity_spelling(identity);
    String prefix = %"${participant}_";
    if (full_name && full_name.startswith(prefix))
      name = full_name[prefix.len():];
  }
  if (!name)
    c.report_error(
      <protocol>, "protocol member must be owned by its participant",
      c.token, %("expected receiver:" $participant));
  Type signature = declaration.type_from_ast().canonicalize();
  if (!signature.is_function())
    c.report_error(
      <protocol>, "protocol member must be a function",
      c.token, %("member:" $name));
  if (members.contains(name))
    c.report_error(
      <protocol>, %"duplicate protocol member '$name'",
      c.token, NULL);
  String native = NULL;
  if (c.test(<=>)) {
    if (c.peek(0) != <ident>)
      c.report_error(
        <protocol>, "native protocol member requires an identifier",
        c.token, NULL);
    native = c.token.text;
    c.next();
  }
  c.expect(<;>);
  members[name] = 1;
  return %($name $signature $native);
}

/** Parses a protocol body or concrete adoption at the current token.
    The method consumes through the closing brace or semicolon. Full parsing
    publishes the normalized row immediately. Macro-hole parsing returns syntax
    for later binding; shallow parsing publishes only when protocol collection
    is enabled and otherwise returns the uninstalled node.
*/
List Compiler.parse_protocol_declaration(Compiler c) {
  Token start = c.token;
  Symbol storage = <external>;
  if (c.test(<static>)) storage = <static>;
  c.expect(<protocol>);
  int generated_base = c.macro_holes &&
    (c.peek(0) == <$> || c.peek(0) == <"$(">);
  Type base = c.parse_type_name();
  c.expect(
    <(>);
  Token participant_token = c.token;
  Type participant_type = c.parse_type_name();
  String participant = participant_type.len() == 1 &&
                       participant_type.car() is <string>
                     ? participant_type.car().str() : NULL;
  c.expect(<)>);
  Type representation = NULL;
  List tag = NULL;
  Token modifier_token = NULL;
  if (c.peek(0) == <ident> && c.token.text == "as") {
    modifier_token = c.token;
    c.next();
    representation = c.parse_type_name().canonicalize();
    if (!generated_base && base != %("Var"))
      c.report_error(
        <protocol>, "'as' applies only to a Var adoption",
        modifier_token, NULL);
  }
  if (c.peek(0) == <ident> && c.token.text == "tag") {
    modifier_token = c.token;
    c.next();
    if (representation)
      c.report_error(
        <protocol>, "a Var adoption cannot use both 'as' and 'tag'",
        modifier_token, NULL);
    tag = c.try_parse_macro_slot(<expression>);
    if (!tag) tag = c.parse_atomic_literal();
    if (!generated_base && base != %("Var"))
      c.report_error(
        <protocol>, "'tag' applies only to a Var adoption",
        modifier_token, NULL);
  }

  /* A bodyless declaration adopts the protocol and produces no AST. */
  if (c.peek(0) == <;>) {
    c.next();
    List location = c.token_location(start);
    if (c.macro_holes || (c.shallow && !c.collect_protocols))
      return _adoption_node(
        base, participant_type, storage, representation, tag, location);
    return c._publish_protocol_adoption(
      base, participant_type, storage, representation, tag, location,
      participant_token, modifier_token);
  }

  if (representation || tag)
    c.report_error(
      <protocol>, representation
        ? "'as' applies only to a concrete protocol adoption"
        : "'tag' applies only to a concrete protocol adoption",
      start, NULL);

  if (!participant)
    c.report_error(
      <protocol>, "expected protocol participant name",
      participant_token, NULL);

  if (storage == <static>)
    c.report_error(
      <protocol>,
      "'static' applies only to a concrete protocol adoption",
      start,
      %("remove 'static' from the reusable protocol body"));
  c.expect(<"{">);

  /* Only the full parse warns about a binder shadowing a visible type. */
  if (!c.shallow) {
    List shadowed = c.sym.get(%($participant));
    if (shadowed && shadowed.type().is_typedef()) {
      String hint = %"hint: a bodyless `protocol BASE($participant);` " +
        "declares an adoption; a body introduces a fresh type variable";
      c.report_warning(
        <warning>,
        %"protocol binder '$participant' shadows a visible type name",
        participant_token, %($hint));
    }
  }

  Array associations = %[], members = %[];
  Map type_names = %{}, member_names = %{};
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
      associations.push(_parse_associated_type(c, type_names, participant));
      continue;
    }
    saw_member = 1;
    members.push(_parse_protocol_member(c, participant, member_names));
  }
  c.expect(<"}">);
  c.sym.pop_scope();

  List record = %(
    "protocol-record" $base $participant
    (associated @{associations.list_free()})
    (members @{members.list_free()})
  );
  List location = c.token_location(start);
  if (c.macro_holes || (c.shallow && !c.collect_protocols))
    return %(protocol $record $storage $location);
  return c._publish_protocol_record(record, base, location);
}
