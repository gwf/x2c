/*  protocol.x -- protocols from declaration to conform forms

    Copyright (c) 2025 Gary William Flake.

    This module owns the protocol feature: it parses protocol and adoption
    declarations, keeps their rows in per-unit registries, resolves each
    adoption into a conformance, answers member and operator lookups, and
    presents each conformance as native aliases or a `conform` form, from which
    `src/component-protocols.x` writes the adapters. Registries are rebuilt per
    translation unit; a static row is visible only in the unit of its canonical
    source path. The unit that declares an external adoption resolves it and
    records the conformance in its interface, which an including unit reuses.
*/
#pragma once
#include "compiler.x"
#include "grammar.x"
#include "adapter-memo.x"

#include <string.h>
#include "collect.x"
#include "expressions.x"
#include "parse.x"
#include "meta.x"

/* protocol diagnostics. */

static macro Stmt $report.protocols.tag_var(Expr $c, Expr $origin) =>
  $c.report_error(
    <protocol>, "'tag' applies only to a Var adoption",
    $origin, NULL);

static macro Stmt $report.protocols.modifier_conflict(Expr $c, Expr $origin) =>
  $c.report_error(
    <protocol>, "a Var adoption cannot use both 'as' and 'tag'",
    $origin, NULL);

static macro Stmt $report.protocols.as_var(Expr $c, Expr $origin) =>
  $c.report_error(
    <protocol>, "'as' applies only to a Var adoption",
    $origin, NULL);

static macro Stmt $report.protocols.static_adoption(Expr $c, Expr $origin) =>
  $c.report_error(
    <protocol>, "'static' applies only to a concrete protocol adoption",
    $origin, %("remove 'static' from the reusable protocol body"));

static macro Stmt $report.protocols.participant_expected(
  Expr $c, Expr $origin) =>
  $c.report_error(
    <protocol>, "expected protocol participant name",
    $origin, NULL);

static macro Stmt $report.protocols.modifier_adoption(
  Expr $c, Expr $representation, Expr $origin) =>
  $c.report_error(
    <protocol>, $representation
      ? "'as' applies only to a concrete protocol adoption"
      : "'tag' applies only to a concrete protocol adoption",
    $origin, NULL);

static macro Stmt $report.protocols.meta_adoption(Expr $c, Expr $origin) =>
  $c.report_error(
    <protocol>, "'meta' applies only to a concrete protocol adoption",
    $origin, %("mark each adoption: meta protocol BASE(TYPE);"));

static macro Stmt $report.protocols.assoc_order(Expr $c) =>
  $c.report_error(
    <protocol>, "associated types must precede protocol members",
    $c.token, NULL);

static macro Stmt $report.protocols.type_duplicate(Expr $c, Expr $name) =>
  $c.report_error(
    <protocol>, %"duplicate protocol type variable '${$name}'",
    $c.token, NULL);

static macro Stmt $report.protocols.assoc_expected(Expr $c) =>
  $c.report_error(
    <protocol>, "expected associated type name",
    $c.token, NULL);

static macro Stmt $report.protocols.member_duplicate(Expr $c, Expr $name) =>
  $c.report_error(
    <protocol>, %"duplicate protocol member '${$name}'",
    $c.token, NULL);

static macro Stmt $report.protocols.member_function(Expr $c, Expr $name) =>
  $c.report_error(
    <protocol>, "protocol member must be a function",
    $c.token, %("member:" ${$name}));

static macro Stmt $report.protocols.member_owner(Expr $c, Expr $participant) =>
  $c.report_error(
    <protocol>, "protocol member must be owned by its participant",
    $c.token, %("expected receiver:" ${$participant}));

static macro Stmt $report.protocols.member_single(Expr $c) =>
  $c.report_error(
    <protocol>, "protocol member must declare one function",
    $c.token, NULL);

static macro Stmt $report.protocols.native_ident(Expr $c) =>
  $c.report_error(
    <protocol>, "native protocol member requires an identifier",
    $c.token, NULL);

static macro Stmt $report.macro.protocol_invalid(Expr $c) =>
  $c.report_error(
    <macro>, "constructed protocol syntax is invalid",
    $c.token, NULL);

static macro Stmt $report.protocols.decl_conflict(
  Expr $c, Expr $base, Expr $first_location, Expr $second_location) {
  {
    String first = %"first: ${$first_location}";
    String second = %"second: ${$second_location}";
    $c.report_error(
      <protocol>, %"conflicting protocol declarations for ${$base.repr()}",
      $c.token, %($first $second));
  }
}

static macro Stmt $report.protocols.type_undeclared(
  Expr $c, Expr $spelling, Expr $origin) =>
  $c.report_error(
    <protocol>,
    %"adoption participant '${$spelling}' does not name a declared type",
    $origin, NULL);

static macro Stmt $report.protocols.adoption_conflict(
  Expr $c, Expr $adoption, Expr $first_location) {
  {
    String first = %"first: ${_location_string($first_location)}";
    String second = %"second: ${_location_string($adoption.location)}";
    String spelling =
      _adoption_spelling($adoption.base, $adoption.participant);
    $c.report_error(
      <protocol>, %"conflicting adoption declarations for $spelling",
      $c.token, %($first $second));
  }
}

static macro Stmt $report.shadow.protocol_binder(
  Expr $c, Expr $participant, Expr $token) {
  {
    String hint = %"hint: a bodyless `protocol BASE(${$participant});` " +
      "declares an adoption; a body introduces a fresh type variable";
    $c.report_warning(
      <shadow>,
      %"protocol binder '${$participant}' shadows a visible type name",
      $token, %($hint));
  }
}

static macro Expression $report.protocols.conformance_prefix(
  Expr $participant, Expr $owner) =>
  %"${$participant} does not satisfy ${$owner}: ";

static macro Expression $report.protocols.native_alias(
  Expr $prefix, Expr $base) =>
  %"${$prefix}its typedef is not a native alias of ${$base}";

static macro Expression $report.protocols.forward_conversion(
  Expr $prefix, Expr $forward) =>
  %"${$prefix}no forward conversion '${$forward}'";

static macro Expression $report.protocols.reverse_conversion(
  Expr $prefix, Expr $base, Expr $lowered) =>
  %"${$prefix}no reverse conversion '${$base}.${$lowered}' " +
    %"or '${$base}.as_${$lowered}'";

static macro Expression $report.protocols.fallback_nested(
  Expr $prefix, Expr $member, Expr $position) =>
  %"${$prefix}member '${$member}' uses T inside a compound " +
    %"${$position} type, which protocol fallback adapters " +
    "do not support";

static macro Expression $report.protocols.fallback_reverse(
  Expr $prefix, Expr $member, Expr $owner, Expr $base, Expr $lowered) =>
  %"${$prefix}member '${$member}' returns T, so ${$owner} needs " +
    %"'${$base}.${$lowered}' or '${$base}.as_${$lowered}'";

static macro Expression $report.protocols.fallback_forward(
  Expr $prefix, Expr $member, Expr $participant, Expr $base) =>
  %"${$prefix}member '${$member}' fallback requires forward " +
    %"conversion '${$participant}.${$base.lower()}'";

static macro Expression $report.protocols.thunk_nested(
  Expr $prefix, Expr $member, Expr $position) =>
  %"${$prefix}member '${$member}' uses T inside a compound " +
    %"${$position} type, which protocol descriptor thunks " +
    "do not support";

static macro Expression $report.protocols.thunk_parameter(
  Expr $prefix, Expr $member, Expr $owner, Expr $base, Expr $lowered) =>
  %"${$prefix}member '${$member}' has a T parameter, so " +
    %"${$owner} needs '${$base}.${$lowered}' or '${$base}.as_${$lowered}'";

static macro Expression $report.protocols.thunk_result(
  Expr $prefix, Expr $member, Expr $owner, Expr $participant, Expr $base) =>
  %"${$prefix}member '${$member}' returns T, so ${$owner} needs " +
    %"'${$participant}.${$base.lower()}'";

static macro Expression $report.protocols.native_parameter(
  Expr $prefix, Expr $member, Expr $base) =>
  %"${$prefix}native member '${$member}' has a T parameter " +
    %"that is not implicitly convertible to ${$base}";

static macro Expression $report.protocols.native_result(
  Expr $prefix, Expr $member, Expr $base) =>
  %"${$prefix}native member '${$member}' returns T, which is " +
    %"not implicitly convertible from ${$base}";

static macro Expression $report.protocols.native_member_alias(
  Expr $prefix, Expr $member) =>
  %"${$prefix}native member '${$member}' cannot be aliased";

static macro Stmt $report.protocols.signature_conflict(
  Expr $c, Expr $member, Expr $owner, Expr $declaration_site,
  Expr $binding, Expr $actual, Expr $expected, Expr $location) {
  {
    String protocol_note =
      %"protocol member '${$member}' declared by ${$owner}";
    if ($declaration_site)
      protocol_note = %"$protocol_note at ${$declaration_site}";
    String actual_repr = $actual.repr();
    String conflict_note =
      %"conflicting definition '${$binding}': $actual_repr";
    String expected_note = %"expected: ${$expected.repr()}";
    $c.diagnostics.report(
      <protocol>,
      %"'${$binding}' has a signature incompatible " +
        %"with ${$owner} member '${$member}'",
      $location,
      %($protocol_note $conflict_note $expected_note));
  }
}

static macro Expression $report.protocols.collision_prefix(
  Expr $member, Expr $participant) =>
  %"member '${$member}' of '${$participant}' ";

static macro Expression $report.protocols.collision_linkage(Expr $owners) =>
  %"has mixed static and external generated ownership in ${$owners}";

static macro Expression $report.protocols.collision_signature(Expr $owners) =>
  %"has incompatible generated signatures in ${$owners}";

static macro Expression $report.protocols.collision_ambiguous(
  Expr $owners, Expr $participant, Expr $member) =>
  %"would be generated by both ${$owners}; implement '" +
    %"${$participant}.${$member}' to choose its semantics";

static macro Expression $report.protocols.collision_linkage_notes(
  Expr $first, Expr $second, Expr $first_value, Expr $second_value) =>
  %(
    "${$first} adoption: ${$first_value}"
    "${$second} adoption: ${$second_value}"
  );

static macro Expression $report.protocols.collision_signature_notes(
  Expr $first, Expr $second, Expr $first_value, Expr $second_value) =>
  %(
    "${$first} signature: ${$first_value.repr()}"
    "${$second} signature: ${$second_value.repr()}"
  );

static macro Expression $report.protocols.collision_source_notes(
  Expr $first, Expr $second, Expr $first_value, Expr $second_value) =>
  %(
    "${$first} default source: ${$first_value}"
    "${$second} default source: ${$second_value}"
  );

// registry rows

/* Protocol occurrences retain the declaration record with its linkage and
   source location. Adoption rows use base, participant, and, for static rows,
   canonical source path as identity so another unit cannot consume them. */
static List _occurrence(List record, Symbol storage, List location) =>
  %( $record $storage $location );

static Symbol _occurrence_storage(List occurrence) => occurrence.cadr();

static List _occurrence_location(List occurrence) => occurrence.caddr();

static List _adoption_node(
  Type base, Type participant, Symbol storage, Type representation,
  List tag, List location) {
  if (representation)
    return %(adopt $base $participant $storage $representation $location);
  if (tag) return %(adopt $base $participant $storage (tag $tag) $location);
  return %(adopt $base $participant $storage $location);
}

static Symbol _adoption_storage(List adoption) => adoption.cddr().cadr();

// A row without a representation or a tag has five fields.
static Type _adoption_representation(List adoption) {
  match (adoption) {
    case %(adopt ? ? ? (tag (!is ? type list)) ?): return NULL;
    case %(adopt ? ? ? ?representation ?): return representation;
  }
  return NULL;
}

static List _adoption_tag(List adoption) {
  match (adoption) case %(adopt ? ? ? (tag ?(List tag)) ?): return tag;
  return NULL;
}

static List _adoption_location(List adoption) => adoption.last();

static List _record(Compiler c, Type base) {
  Var stored;
  if (!c.protocols.try_get(base, stored)) return NULL;
  List occurrence = stored;
  return occurrence.car();
}

static List _adoption_row(
  Compiler c, Type base, Type participant, Symbol storage) {
  String path = _path(c);
  List key = storage == <static>
           ? %($base $participant $path)
           : %($base $participant);
  Var stored;
  return c.adoptions.try_get(key, stored) ? stored : NULL;
}

static List _visible_adoption(
  Compiler c, Type base, Type participant) {
  List local = _adoption_row(c, base, participant, <static>);
  return local ? local : _adoption_row(c, base, participant, <external>);
}

static Symbol _visibility(Compiler c, Type base, Type participant) {
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
static int _is_adopted(Compiler c, Type base, Type participant) =>
    !!_visibility(c, base, participant);

static int _owns_adoption(Compiler c, Type base, Type participant) {
  List row = _visible_adoption(c, base, participant);
  return row && _canonical_file(c, _adoption_location(row)) == _path(c);
}

static typedef struct AdoptionDraft {
  Compiler c;
  Type base, participant, representation;
  Symbol storage, tag;
  List tag_expression, location;
  Token participant_token, modifier_token;
} AdoptionDraft;

// source locations

static String _path(Compiler c) {
  String result = NULL;
  $memo(c.protocol_helpers, <proto-path>, result) {
    result = _normalize_file(c, c.filename ? c.filename : "<stdin>");
  }
  return result;
}

/* A module member's adoptions belong to its unit, as its other
   declarations do. */
static String _canonical_file(Compiler c, List location) {
  String file = _location_file(location), result = NULL;
  $memo(c.protocol_helpers, %(proto-file $file), result) {
    result = _normalize_file(c, file);
    if (_module_member(c, result)) result = _path(c);
  }
  return result;
}

static int _module_member(Compiler c, String file) {
  if (c.line_markers)
    foreach (List row, c.line_markers)
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

static String _location_string(List location) {
  String file = _location_file(location);
  Var line = location ? location.assoc(<line>) : void;
  Var column = location ? location.assoc(<column>) : void;
  return %"$file:${line.is_integer() ? line.integer() : 1}:${
    column.is_integer() ? column.integer() : 1}";
}

static int _is_private(Compiler c, String name) =>
  %($name) in c.sym.file_statics();

// spellings

static String _base_name(Type base) =>
  base.is_bare_typedef_name() ? base.car() : NULL;

// Prefer a typedef's bare diagnostic spelling.
static String _type_spelling(Type type) =>
  type.is_bare_typedef_name() ? type.car() : type.repr();

static String _member_spelling(Type participant, String member) =>
  %"${participant.car()}_$member";

static String _adoption_spelling(Type base, Type participant) =>
  %"${_type_spelling(base)}(${_type_spelling(participant)})";

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
  String binding = %"${base_name}_$infix${bare.lower()}";
  return package ? %"${package}__$binding" : binding;
}

static Type _declared(Compiler c, String name) {
  if (c.sym.get(%("generated-protocol" $name)))
    return NULL;
  return c.sym.get(%($name));
}

/* declaration parsing

   A bodyless declaration adopts a protocol; a body declares one. Full
   parsing publishes the row at once, while macro-hole and uncollected
   shallow parsing return the node unpublished. */

/* One protocol declaration while it is parsed: the tokens diagnostics
   point at, the base and participant, and the adoption modifiers. */
static typedef struct ProtocolSyntax {
  Compiler c;
  Token start, meta, participant_token, modifier_token;
  Type base, participant_type, representation;
  String participant;
  List tag;
  Symbol storage;
  int generated_base;
} ProtocolSyntax;

/** Parses a protocol body or concrete adoption at the current token.
    The method consumes through the closing brace or semicolon. Full parsing
    publishes the normalized row immediately. Macro-hole parsing returns syntax
    for later binding; shallow parsing publishes only when protocol collection
    is enabled and otherwise returns the uninstalled node. A leading `meta`
    makes an adoption's witnesses available to compile-time code.
*/
List Compiler.parse_protocol_declaration(Compiler c) {
  ProtocolSyntax syntax = {.c = c, .start = c.token, .storage = <external>};
  _head(syntax);
  if (c.peek(0) == <;>) return _adoption(syntax);
  _check_body(syntax);
  _warn_shadowed(syntax);
  return _body(syntax);
}

static void _head(ProtocolSyntax &p) {
  Compiler c = p.c;
  if (c.at_word("meta")) {
    p.meta = c.token;
    c.next();
  }
  if (c.test(<static>)) p.storage = <static>;
  c.expect(<protocol>);
  p.generated_base = c.macro_holes &&
    (c.peek(0) == <$> || c.peek(0) == <"$(">);
  p.base = c.parse_type_name();
  c.expect(<(>);
  p.participant_token = c.token;
  p.participant_type = c.parse_type_name();
  Type participant = p.participant_type;
  p.participant = participant.len() == 1 && participant.car() is <string>
                ? participant.car() : NULL;
  c.expect(<)>);
  _modifiers(p);
}

static void _modifiers(ProtocolSyntax &p) {
  Compiler c = p.c;
  if (c.at_word("as")) {
    p.modifier_token = c.token;
    c.next();
    p.representation = c.parse_type_name().canonicalize();
    if (!p.generated_base && p.base !== %("Var"))
      $report.protocols.as_var(c, p.modifier_token);
  }
  if (c.at_word("tag")) {
    p.modifier_token = c.token;
    c.next();
    if (p.representation)
      $report.protocols.modifier_conflict(c, p.modifier_token);
    p.tag = c.try_parse_macro_slot(<expression>);
    if (!p.tag) p.tag = c.parse_atomic_literal();
    if (!p.generated_base && p.base !== %("Var"))
      $report.protocols.tag_var(c, p.modifier_token);
  }
}

static List _adoption(ProtocolSyntax &p) {
  Compiler c = p.c;
  c.next();
  List adoption = _adoption_node(
    p.base, p.participant_type, p.storage, p.representation, p.tag,
    c.token_location(p.start));
  List node = p.meta ? %(meta-protocol $adoption) : adoption;
  if (c.macro_holes || (c.shallow && !c.collect_protocols)) return node;
  return c.publish_protocol_node(node, p.participant_token, p.modifier_token);
}

static void _check_body(ProtocolSyntax &p) {
  Compiler c = p.c;
  if (p.meta)
    $report.protocols.meta_adoption(c, p.meta);

  if (p.representation || p.tag)
    $report.protocols.modifier_adoption(c, p.representation, p.start);

  if (!p.participant)
    $report.protocols.participant_expected(c, p.participant_token);

  if (p.storage == <static>)
    $report.protocols.static_adoption(c, p.start);
  c.expect(<"{">);
}

static void _warn_shadowed(ProtocolSyntax &p) {
  /* Only the full parse warns about a binder shadowing a visible type. */
  Compiler c = p.c;
  if (c.shallow) return;
  String participant = p.participant;
  List shadowed = c.sym.get(%($participant));
  if (!shadowed || !shadowed.type().is_typedef()) return;
  $report.shadow.protocol_binder(c, participant, p.participant_token);
}

static List _body(ProtocolSyntax &p) {
  Compiler c = p.c;
  String participant = p.participant;
  Array associations = [], members = [];
  Map type_names = {}, member_names = {};
  c.sym.push_new_scope();
  c.sym.define(%($participant), %(typedef $participant));
  type_names[participant] = 1;
  int saw_member = 0;
  while (c.peek(0) != <"}"> && c.peek(0) != <eof>) {
    if (c.peek(0) == <associated>) {
      if (saw_member)
        $report.protocols.assoc_order(c);
      associations.push(_parse_associated(c, type_names));
      continue;
    }
    saw_member = 1;
    members.push(_parse_member(c, participant, member_names));
  }
  c.expect(<"}">);
  c.sym.pop_scope();

  List record = %(
    "protocol-record" ${p.base} $participant
    (associated @{associations.list_free()})
    (members @{members.list_free()})
  );
  List location = c.token_location(p.start);
  if (c.macro_holes || (c.shallow && !c.collect_protocols))
    return %(protocol $record ${p.storage} $location);
  return _publish_record(c, record, p.base, location);
}

static List _parse_associated(Compiler c, Map names) {
  c.expect(<associated>);
  if (c.peek(0) != <ident>)
    $report.protocols.assoc_expected(c);
  String name = c.token.text;
  c.next();
  if (name in names)
    $report.protocols.type_duplicate(c, name);
  c.expect(<=>);
  Type type = c.parse_type_name().canonicalize();
  c.expect(<;>);
  names[name] = 1;
  c.sym.define(%($name), %(typedef $name));
  return %($name $type);
}

static List _parse_member(
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
    $report.protocols.member_single(c);
  String name = _member_name(identity, participant);
  if (!name)
    $report.protocols.member_owner(c, participant);
  Type signature = declaration.type_from_ast().canonicalize();
  if (!signature.is_function())
    $report.protocols.member_function(c, name);
  if (name in members)
    $report.protocols.member_duplicate(c, name);
  String native = _native_member(c);
  c.expect(<;>);
  members[name] = 1;
  return %($name $signature $native);
}

static String _member_name(List identity, String participant) {
  String name = NULL;
  match (identity)
    case %((!or (!is ?owner type <string>)
                ((!is ?owner type <string>)))
           (!is ?member type <string>)):
      if (owner == participant) name = member;
  if (name) return name;
  String full_name = Ast.binding_spelling(identity);
  String prefix = %"${participant}_";
  return full_name && full_name.startswith(prefix)
    ? full_name[prefix.len():] : NULL;
}

static String _native_member(Compiler c) {
  if (!c.test(<=>)) return NULL;
  if (c.peek(0) != <ident>)
    $report.protocols.native_ident(c);
  String native = c.token.text;
  c.next();
  return native;
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
  $report.macro.protocol_invalid(c);
}

static List _publish_record(
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
    %(meta-protocol @{_adoption_location(adoption)}));
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
       ? %("source-node" $location $invocation)
       : %("source-node" $location);
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
  $report.protocols.decl_conflict(c, base, first_location, second_location);
}

// adoption drafts

static List _publish(AdoptionDraft &a) {
  Compiler c = a.c;
  if (a.tag_expression) a.tag_expression = _tag_syntax(a.tag_expression);
  String spelling = a.participant.car().str();
  List declared = c.sym.get(%($spelling));
  if ((!declared || !declared.type().is_typedef()) && !c.shallow)
    $report.protocols.type_undeclared(c, spelling,
      a.participant_token);
  a.tag = _check_modifiers(a);
  a.storage = _published_storage(a, spelling);
  _check_previous(a);
  _install(a);
  // An adoption resolved when the parse began has reported its failures.
  List pair = %(${a.base} ${a.participant});
  int resolved = pair in c.conforms;
  c.conforms.del(pair);
  c.proto_cache = {};
  if (!c.shallow)
    _resolve_adoption(c, a.base, a.participant, resolved ? NULL : a.location);
  List published = _node(a);
  // A generated class declares several adoptions at one location.
  _retain_source_node(
    c, published, a.storage, %(adopt ${a.base} @{a.location}));
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

static Symbol _tag_value(List expression) {
  match (expression)
    case %(expr ("Symbol") ${$source_literal_content(%(("Symbol") ? ?tag))}):
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
  foreach (List template, templates) {
    String binding = template.caddr();
    if (binding && _is_private(c, binding)) return 1;
  }
  return 0;
}

static void _check_previous(AdoptionDraft &a) {
  Compiler c = a.c;
  if (c.shallow) return;
  String path = _canonical_file(c, a.location);
  List key = %("parsed-protocol-adoption" ${a.base} ${a.participant} $path);
  Var previous;
  if (!c.protocol_helpers.try_get(key, previous)) {
    c.protocol_helpers[key] = _node(a);
    return;
  }
  List row = previous;
  if (_adoption_representation(row) == a.representation &&
      _adoption_tag(row) == a.tag_expression) return;
  String first = %"first: ${_location_string(_adoption_location(row))}";
  String second = %"second: ${_location_string(a.location)}";
  String spelling = _adoption_spelling(a.base, a.participant);
  c.diagnostics.report(
    <protocol>, %"conflicting adoption declarations for $spelling",
    a.location, %($first $second));
}

static void _install(AdoptionDraft &a) {
  Compiler c = a.c;
  String path = _canonical_file(c, a.location);
  if (a.storage == <static> && path != _path(c)) return;
  a.participant.register_var_adoption(a.representation, a.tag);
  List key = a.storage == <static>
           ? %(${a.base} ${a.participant} $path)
           : %(${a.base} ${a.participant});
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
  $report.protocols.adoption_conflict(c, a, first_location);
}

// resolution

/* Native and ordinary resolution are the only conformance-row producers. A
   row carries base, participant, converters, type-variable maps, and member
   rows of `(name status source expected default-kind template)`. Consumers
   dispatch on `status`; a non-list cache value records failed resolution. */
static typedef struct ProtocolRequirements {
  String binder;
  List associations, templates;
} ProtocolRequirements;

/** Resolves every visible adoption into the current conformance registry.
    Resolution starts from an empty registry; diagnostics are located only for
    adoptions owned by the current translation unit. An adoption another
    unit declared and recorded keeps that conformance, which is installed
    when it is first used.
*/
void Compiler.resolve_protocols(Compiler c) => _resolve_visible(c, 1);

static void _resolve_visible(Compiler c, int report) {
  c.conforms = {};
  String owner = _path(c);
  foreach (Var value, c.adoptions) {
    List adoption = value;
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

// recorded conformance

/* An ordinary external conformance whose adoption the unit's collected
   entry declares is recorded in the unit's interface as
   `(conformance BASE PARTICIPANT FORWARD REVERSE (bindings (NAME TYPE)...)
   (MEMBER STATUS SOURCE)...)`, with each type variable's binding and each
   member resolved as anything but `no-member`. The expected and template
   types follow from the protocol record and the bindings. A member that
   resolved to a function static to this unit is left out, so it is
   `no-member` elsewhere: no other unit can call that function. A native
   conformance reads no participant member, so each unit resolves it. */
static void _record_conformances(Compiler c) {
  c.record_conformance_rows(c.conformance_rows(c.declared_adoptions()));
}

static List _recorded_conformance(
  Compiler c, Type base, Type participant) {
  if (_visibility(c, base, participant) != <external>) return NULL;
  match (c.conforms[%($base $participant)])
    case %(protocol-conformance ? ? ?forward ?reverse ? ?(Map bindings)
           (members *rows)): {
      if (_native_rows(rows)) return NULL;
      Array bound = [], resolved = [];
      foreach (Var (name, type), bindings) bound.push(%($name $type));
      bound.sort();
      foreach (List row, rows)
        match (row)
          case %(?member ?(Symbol status) ?(String source) *)
            if (status != <no-member> && !_is_private(c, source)):
              resolved.push(%($member $status $source));
      return %(conformance $base $participant $forward $reverse
               (bindings @{bound.list_free()}) @{resolved.list_free()});
    }
  return NULL;
}

/** Returns the interface rows of the resolved conformances `adoptions`
    declare. */
Map Compiler.conformance_rows(Compiler c, List adoptions) {
  Map rows = {};
  foreach (List adoption, adoptions) {
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
  foreach (Var key, c.conforms.keys()) pairs.push(key);
  foreach (List pair, pairs) {
    if (_recorded(c, pair.car(), pair.cadr())) continue;
    c.conforms.del(pair);
    c.proto_cache = {};
    _resolve_adoption(c, pair.car(), pair.cadr(), NULL);
  }
  pairs.free();
}

/* The row an included interface recorded for an adoption this unit does not
   own, or NULL. */
static List _recorded(Compiler c, Type base, Type participant) {
  Var recorded;
  if (_owns_adoption(c, base, participant) ||
      !c.protocol_helpers.try_get(
        %("recorded-conformance" $base $participant), recorded))
    return NULL;
  return recorded;
}

/* Installs the conformance an included interface recorded for an adoption
   this unit does not own. Returns 0 when there is none to reuse. */
static int _reuse_conformance(
  Compiler c, Type base, Type participant) {
  match (%(${_record(c, base)} ${_recorded(c, base, participant)}))
    case %((? ? ? ? (members *templates))
           (conformance ? ? ?forward ?reverse (bindings *bound) *members)): {
      Map variables = {}, bindings = {}, resolved = {};
      foreach (List pair, bound) {
        (String name, Type type) = pair;
        variables[name] = 1;
        bindings[name] = type;
      }
      foreach (List member, members) resolved[member.car()] = member;
      Array rows = [];
      foreach (List template, templates) {
        (String member, Type type) = template;
        Type expected = _substitute_signature(type, variables, bindings);
        rows.push(_recorded_row(resolved[member], member, expected, type));
      }
      c.conforms[%($base $participant)] = %(
        protocol-conformance $base $participant $forward $reverse
        $variables $bindings (members @{rows.list_free()})
      );
      return 1;
    }
  return 0;
}

/* The recorded conformances this unit may reuse and has not installed, as
   `((BASE PARTICIPANT) ROW)` pairs. */
static List _unused_recorded(Compiler c) {
  Array candidates = [], unused = [];
  foreach (Var key, c.protocol_helpers.keys())
    match (key)
      case %("recorded-conformance" ?(Type base) ?(Type participant)):
        candidates.push(%($base $participant));
  // Ownership answers are memoized in the helpers, so they follow the scan.
  foreach (List pair, candidates) {
    List row = _recorded(c, pair.car(), pair.cadr());
    if (row && !(pair in c.conforms)) unused.push(%($pair $row));
  }
  candidates.free();
  return unused.list_free();
}

/* Installs each recorded conformance with a base default whose forward
   converter is defined, so that its forwarding members are published. */
static void _reuse_defaults(Compiler c) {
  foreach (List entry, _unused_recorded(c))
    match (entry)
      case %((?(Type base) ?(Type participant))
             (conformance ? ? ?(String forward) ? ? *members)):
        if (forward in c.fn_defs && _has_default(members))
          _reuse_conformance(c, base, participant);
}

static int _has_default(List members) {
  foreach (List member, members) if (member.cadr() == <base-dflt>) return 1;
  return 0;
}

/* Rebuilds a member row as resolution writes it. A member the interface
   does not list resolved as `no-member`. */
static List _recorded_row(
  Var recorded, String member, Type expected, Type template) {
  match (recorded)
    case %(? ?(Symbol status) ?(String source)): {
      Symbol kind = status == <base-dflt> ? <ordinary> : <none>;
      return %($member $status $source $expected $kind $template);
    }
  String source = NULL;
  return %($member no-member $source $expected none $template);
}

static void _resolve_adoption(
  Compiler c, Type base, Type participant, List location) {
  List record = _record(c, base);
  if (!record) {
    if (!location) return;
    c.diagnostics.report(
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
  String prefix = $report.protocols.conformance_prefix(
    participant_repr, _adoption_spelling(base, participant));
  if (failure) return _requirement_detail(base, participant, failure);
  if (native)
    return $report.protocols.native_alias(prefix, base_repr);
  String base_name = _base_name(base);
  Type forward = base_name
    ? _declared(c, _member_spelling(participant, base_name.lower())) : NULL;
  if (base_name && !_exact_conversion(forward, participant, base))
    return $report.protocols.forward_conversion(
      prefix, %"$participant_repr.${base_name.lower()}");
  String lowered = participant.is_bare_typedef_name()
    ? participant.car().str().lower() : participant_repr;
  return $report.protocols.reverse_conversion(prefix, base_repr, lowered);
}

static String _requirement_detail(Type base, Type participant, List failure) {
  String base_repr = _type_spelling(base);
  String participant_repr = _type_spelling(participant);
  (String member, Symbol adapter, Symbol direction, Symbol position) = failure;
  String lowered = participant.is_bare_typedef_name()
    ? participant.car().str().lower() : participant_repr;
  String owner = _adoption_spelling(base, participant);
  String prefix = $report.protocols.conformance_prefix(
    participant_repr, owner);
  if (adapter == <fallback> && direction == <nested>)
    return $report.protocols.fallback_nested(prefix, member, position);
  if (adapter == <fallback> && direction == <reverse>)
    return $report.protocols.fallback_reverse(
      prefix, member, owner, base_repr, lowered);
  if (adapter == <fallback>)
    return $report.protocols.fallback_forward(
      prefix, member, participant_repr, base_repr);
  if (adapter == <thunk> && direction == <nested>)
    return $report.protocols.thunk_nested(prefix, member, position);
  if (adapter == <thunk> && position == <parameter>)
    return $report.protocols.thunk_parameter(
      prefix, member, owner, base_repr, lowered);
  if (adapter == <thunk>)
    return $report.protocols.thunk_result(
      prefix, member, owner, participant_repr, base_repr);
  if (position == <parameter>)
    return $report.protocols.native_parameter(prefix, member, base_repr);
  if (position == <result>)
    return $report.protocols.native_result(prefix, member, base_repr);
  return $report.protocols.native_member_alias(prefix, member);
}

static void _report_sig_conflicts(
  Compiler c, Type base, Type participant, List rows, List location) {
  String owner = _adoption_spelling(base, participant);
  String declaration_site = _definition_location(c, base);
  foreach (List row, rows)
    match (row)
      case %(?(String member) sig-cnflct ?(String binding)
             ?(Type expected) ? ?): {
        List dedupe = %("protocol-sig-conflict" $participant $member);
        if (dedupe in c.protocol_helpers) continue;
        c.protocol_helpers[dedupe] = 1;
        Type actual = _declared(c, binding);
        $report.protocols.signature_conflict(
          c, member, owner, declaration_site, binding, actual,
          expected, location);
      }
}

static String _definition_location(Compiler c, Type base) {
  List stored = c.protocols[base];
  return _location_string(_occurrence_location(stored));
}

// native conformance

static typedef struct NativeResolution {
  Type base, participant, definition;
  String binder;
  Map variables, bindings;
} NativeResolution;

static List _resolve_native(
  Compiler c, Type base, Type participant, ProtocolRequirements &requirements,
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
  List rows = _rows(resolution, requirements.templates, failure);
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

static List _rows(
  NativeResolution &r, List templates, List &failure) {
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

#define PROTOCOL_VARIABLE 1
#define PROTOCOL_VARIADIC 2

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

static int _native_converts(Type participant_definition, Type base) {
  if (participant_definition == base) return 1;
  return participant_definition.canonicalize() == base.canonicalize();
}

static Type _participant_definition(Compiler c, Type participant) {
  if (!participant.is_bare_typedef_name()) return NULL;
  String name = participant.car();
  Var definition = c.sym.global_symbols()[%(typedef $name)];
  return definition is <list> ? definition : NULL;
}

static void _install_native_bindings(
  Compiler c, Type participant, List rows) {
  if (!_native_rows(rows)) return;
  foreach (List row, rows)
    match (row)
      case %(?(String member) ? ? ? ? ?(Type signature)): {
        String generated = _member_spelling(participant, member);
        if (!c.sym.get(%($generated)))
          c.sym.define_global(%($generated), signature);
      }
}

static int _is_native(List templates) {
  foreach (List template, templates)
    if (template.caddr().str()) return 1;
  return 0;
}

static int _native_rows(List rows) {
  match (rows) case %((? native *) *): return 1;
  return 0;
}

// ordinary conformance

static typedef struct MemberResolution {
  Compiler c;
  Type base, participant, representation;
  String binder, forward;
  Map variables, defaults, bindings;
} MemberResolution;

static List _resolve_ordinary(
  Compiler c, Type base, Type participant,
  ProtocolRequirements &requirements, List &failure) {
  failure = NULL;
  Var stored;
  List key = %($base $participant);
  if (c.conforms.try_get(key, stored))
    return stored is <list> ? stored : NULL;
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
    ${resolution.variables} ${resolution.bindings} (members @rows)
  );
  c.conforms[key] = conformance;
  return conformance;
does_not_conform: c.conforms[key] = 0;
  return NULL;
}

static String _forward_binding(
  Compiler c, Type base, Type participant) {
  String base_name = _base_name(base);
  if (!base_name || !participant.is_bare_typedef_name()) return NULL;
  String binding = _member_spelling(participant, base_name.lower());
  Type found = _declared(c, binding);
  if (!_exact_conversion(found, participant, base)) return NULL;
  return binding;
}

static String _reverse_binding(
  Compiler c, Type base, Type participant) {
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
static List _resolve(
  MemberResolution &r, List associations, List templates) {
  r.variables[r.binder] = 1;
  r.bindings[r.binder] = r.participant;
  foreach (List association, associations) {
    (String name, Type value) = association;
    r.variables[name] = 1;
    r.defaults[name] = value;
  }
  Array selected = [];
  foreach (List row, templates) {
    List member = _select(r, row);
    if (member) selected.push(member);
  }
  foreach (Var (name, value), r.defaults) r.bindings.setdefault(name, value);
  Array completed = [];
  foreach (List row, selected) {
    List member = _complete(r, row);
    if (member) completed.push(member);
  }
  selected.free();
  return completed.list_free();
}

static List _select(MemberResolution &r, List row) {
  match (row)
    case %(?(String member) ?(Type template) ?): {
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
  foreach (Type owner,
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

  List binding = c.sym.reference(%($source), NULL);
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
  match (row)
    case %(?(String member) ?(Symbol status) ?(String source)
           ? ? ?(Type template)): {
      Type expected = _substitute_signature(template, r.variables, r.bindings);
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

/* adapter requirements

   Resolution accepts an ordinary conformance only when its adapters can be
   generated, and presentation checks an inherited member the same way.
   Both describe the adapters with one record. */

/* The adapters one conformance needs. Resolution fills the base, binder,
   and converters; presentation fills the rest. */
static typedef struct ProtocolAdapters {
  Compiler c;
  Type base, participant;
  String forward, reverse, binder;
  Map variables, bindings;
  List adoption;
  int shares_var_tag, central_initializer;
} ProtocolAdapters;

static List _requirement(ProtocolAdapters &a, List rows) {
  foreach (List row, rows)
    match (row)
      case %(?(String member) ?(Symbol status) ? ?
             ?(Symbol default_kind) ?(Type template)): {
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

static List _descriptor_requirement(
  ProtocolAdapters &a, String member, Type template) {
  if (a.base !== %("Var") ||
      !a.c.sym.lookup_field(%(struct "VarMethods"), %($member)))
    return NULL;
  return _conversion_requirement(a, member, template, <thunk>);
}

static List _conversion_requirement(
  ProtocolAdapters &a, String member, Type template, Symbol adapter) {
  int fallback = adapter == <fallback>;
  List parameters = template.car().list().cadr();
  Type result = template.cdr(), variable = %(${a.binder});
  Symbol direction = fallback ? <forward> : <reverse>;
  foreach (Var parameter, parameters) {
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

static void _report_requirement(
  ProtocolAdapters &a, List failure) {
  Type base = a.base, participant = a.participant;
  List dedupe =
    %("protocol-adapter-requirement" $base $participant ${failure.car()});
  if (dedupe in a.c.protocol_helpers) return;
  a.c.protocol_helpers[dedupe] = 1;
  List row = _visible_adoption(a.c, base, participant);
  a.c.diagnostics.report(
    <protocol>, _requirement_detail(base, participant, failure),
    _adoption_location(row), NULL);
}

// signature unification

static int _function_parts(Type signature, List &parameters, Type &result) {
  match (signature)
    case %((func ?arguments) *return_type): {
      parameters = arguments;
      result = return_type;
      return 1;
    }
  return 0;
}

/* A type variable is the one-element Type `("T")`. In a compound Type such
   as `(* "T")` it is the base suffix, so walking a Type by car and cdr
   reaches it as a whole Type in that position too. */
static String _type_variable(Var value, Map variables) {
  match (value)
    case %(?(String name)) if (name in variables): return name;
  return NULL;
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

static int _unify_signature(
  Type pattern, Type actual, Map variables, Map bindings) {
  List pattern_parameters = pattern.car().list().cadr();
  List parameters = NULL, Type result = NULL;
  return _function_parts(actual, parameters, result) &&
         _unify(pattern_parameters, parameters, variables, bindings) &&
         _unify(pattern.cdr(), result, variables, bindings);
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

static Type _substitute_signature(
  Type signature, Map variables, Map bindings) {
  List parameters = signature.car().list().cadr();
  Type result = signature.cdr();
  List parameter_types = parameters.map(
    %!(Var parameter) => _substitute(parameter, variables, bindings));
  Type result_type = _substitute(result, variables, bindings);
  return %((func $parameter_types) @result_type);
}

static int _exact_conversion(Type signature, Type parameter, Type result) {
  List parameters = NULL, Type actual_result = NULL;
  if (!_function_parts(signature, parameters, actual_result))
    return 0;
  return parameters && !parameters.cdr() &&
         parameters.car() == parameter &&
         actual_result == result;
}

// conformance lookup

/** Returns the resolved conformance for `participant` and `base`, if any.
    Lookup canonicalizes the participant and may use the nearest adopted
    typedef ancestor. Native conformances install their generated bindings
    before the cached conformance row is returned.
*/
List Compiler.protocol_members_for(Compiler c, Type participant, Type base) {
  participant = participant.canonicalize();
  if (c.import_protocols) _install_imports(c);
  Type owner = participant;
  if (!_is_adopted(c, base, owner)) {
    List ancestry = _ancestry(c, participant).cdr();
    for (; ancestry; ancestry = ancestry.cdr()) {
      owner = ancestry.car();
      if (_is_adopted(c, base, owner)) break;
    }
    if (!ancestry) return NULL;
  }
  List key = %($base $owner);
  Var stored = c.conforms[key];
  /* One adoption is resolved where it is asked for when the parse has not
     resolved it. `_publish` already skips resolving during
     a shallow pass, and an import installed just above resolves nothing.
     `adoptions` holds only the adoptions this compiler may use, and the full
     parse resolves all of them before it starts, except those an included
     interface recorded, which are installed here on first use. */
  if (stored is void) {
    if (!_reuse_conformance(c, base, owner))
      _resolve_adoption(c, base, owner, NULL);
    stored = c.conforms[key];
  }
  if (stored is not <list>) return NULL;
  List conformance = stored;
  _install_native_bindings(c, owner, conformance.last().list().cdr());
  return conformance;
}

/* Collection skips bodies and leaves protocol registries empty. A canonical
   template can need protocols before full parsing, so install the visible
   symbols on first use and resolve only the conformance requested. */
static void _install_imports(Compiler c) {
  c.import_protocols = 0;
  c.rebuild_protocols(c.sym.unit_symbols());
}

static List _ancestry(Compiler c, Type participant) {
  List result = NULL;
  $memo(c.proto_cache, %("protocol-ancestry" $participant), result) {
    Array ancestry = [], Type current = participant;
    for (int distance = 0; current && distance <= 128; distance++) {
      ancestry.push(current);
      if (!current.is_typedef_name() && !current.is_typedef()) break;
      current = c.sym.get(current);
    }
    result = ancestry.list_free();
  }
  return result;
}

static List _ordered_occurrences(Compiler c) {
  if (c.import_protocols) _install_imports(c);
  List result = NULL;
  $memo(c.proto_cache, <proto-ordr>, result) {
    Array ordered = [];
    foreach (Var (base, occurrence), c.protocols)
      ordered.push(%($base $occurrence));
    ordered.sort();
    result = ordered.list_free();
  }
  return result;
}

/* Runs visit once for each conformance participant adopts, in protocols
   order, after setting the caller's base to the protocol and rows to its
   member rows. */
static macro Decorator $adopted_rows(
  Stmt $visit, Expr $compiler, Expr $protocols,
  Expr $participant, Name $base, Name $rows) {
  foreach (List entry, $protocols) {
    $base = entry.car();
    if (!_is_adopted($compiler, $base, $participant)) continue;
    List conformance = $compiler.protocol_members_for($participant, $base);
    if (!conformance) continue;
    $rows = conformance.last().list().cdr();
    $visit;
  }
}

/** Returns unique member spellings from the participant's visible adopted
    conformances. Resolution remains responsible for selecting a binding. */
List Compiler.protocol_member_names(Compiler c, Type participant) {
  Map seen = {};
  Array names = [];
  List protocols = _ordered_occurrences(c), rows = NULL;
  Type base = NULL;
  foreach (Type current, _ancestry(c, participant.canonicalize()))
    $adopted_rows(c, protocols, current, base, rows) {
      foreach (List row, rows) {
        String name = row.car();
        if (name && !(name in seen)) {
          seen[name] = 1;
          names.push(name);
        }
      }
    }
  names.sort();
  return names.list_free();
}

/** Reports whether conformance supersedes an ambient direct member.
    The answer is cached for the canonical participant and includes the first
    visible adopted ancestor that declares the member.
*/
int Compiler.protocol_rejects_direct_member(
  Compiler c, Type participant, String member) {
  Type owner = participant.canonicalize();
  int rejects = 0;
  $memo(c.proto_cache, %("protocol-rejects" $owner $member), rejects) {
    List protocols = _ordered_occurrences(c);
    foreach (Type ancestor, _ancestry(c, owner)) {
      List row = _member_row(c, protocols, ancestor, member);
      if (row) {
        Symbol status = row.cadr();
        rejects = status != <implmntd>;
        break;
      }
    }
  }
  return rejects;
}

static List _member_row(
  Compiler c, List protocols, Type participant, String member) {
  Type base = NULL;
  List rows = NULL;
  $adopted_rows(c, protocols, participant, base, rows) {
    foreach (List row, rows) if (row.car() == member) return row;
  }
  return NULL;
}

/** Prints stable conformance rows for typedefs in `globs`.
    Rows are ordered by participant and protocol and identify whether each
    adoption is owned by this unit, so prelude and live symbol modes can be
    compared.
*/
void Compiler.dump_conformance(Compiler c, Map globs) {
  Array names = [];
  foreach (Var (key, value), globs)
    match (%($key $value))
      case %((?(String name)) (typedef *)):
        names.push(name);
  names.sort();
  List protocols = _ordered_occurrences(c), rows = NULL;
  Type base = NULL;
  foreach (Var candidate, names) {
    Type participant = %(${candidate.str()});
    $adopted_rows(c, protocols, participant, base, rows) {
      _dump_row(
        "conformance", _owns_adoption(c, base, participant), base,
        participant, rows);
    }
  }
  names.free();
}

static void _dump_row(
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
        printf(
          " (%s %s %s %s)", member, name, source ? source : "-", punctuation);
      }
  printf(")\n");
}

// operators

/* operator-ledger.x defines these methods outside the shared include graph. */
// lint: allow src-forward-declaration FI-6: leaf ledger binding
Symbol Compiler.operator_member(Compiler c, Symbol op);

// lint: allow src-forward-declaration FI-6: leaf ledger binding
Symbol Compiler.derived_member(Compiler c, Symbol op);

// member resolution

/** Resolves a protocol member for `participant`.
    Returns a `(binding signature)` pair for the selected implementation or
    null when no eligible resolved member exists; positive and negative
    results are cached. Inside the selected implementation itself the result
    is null, so the member's own body keeps the native operation.
*/
List Compiler.resolve_protocol_member(
  Compiler c, Type participant, String member_name) {
  // A const or volatile receiver adopts exactly what its unqualified type
  // adopts, so conformance is keyed on the unqualified participant.
  List resolved = _resolve_member(c, participant.canonicalize(), member_name);
  if (!resolved) return NULL;
  (String spelling, Type signature) = resolved;
  if (spelling == c.fn_name) return NULL;
  return %(${c.sym.reference(%($spelling), NULL)} $signature);
}

/* Cache the selected declaration, not a transaction-owned binding identity. */
static List _resolve_member(
  Compiler c, Type participant, String member_name) {
  List key = %("protocol-member" $participant $member_name), selected = NULL;
  $memo(c.proto_cache, key, selected) {
    List protocols = _ordered_occurrences(c);
    List ancestry = _ancestry(c, participant);
    /* A generated member is selected before a direct base alias. */
    selected = _generated_member(c, ancestry, member_name);
    if (!selected)
      selected = _base_alias(c, protocols, ancestry, member_name);
    if (!selected)
      selected = _adopted_member(c, protocols, ancestry, member_name);
  }
  return selected;
}

static List _generated_member(
  Compiler c, List ancestry, String member) {
  foreach (Type current, ancestry) {
    List decision = _generated_owner(c, current, member);
    match (decision)
      case %(owner ? ? ?signature ?): {
        String source = _member_spelling(current, member);
        return %($source $signature);
      }
  }
  return NULL;
}

static List _base_alias(
  Compiler c, List protocols, List ancestry, String member) {
  foreach (List entry, protocols) {
    (Type base, List occurrence) = entry;
    if (!(base in ancestry)) continue;
    String base_name = _base_name(base);
    if (!base_name) continue;
    List record = occurrence.car();
    List declared = record.last().list().cdr();
    if (!_declares_member(declared, member)) continue;
    String source = %"${base_name}_$member";
    Type signature = c.sym.get(%($source));
    if (!signature || !signature.is_function()) continue;
    return %($source $signature);
  }
  return NULL;
}

static int _declares_member(List rows, String member) {
  foreach (List row, rows) if (row.car() == member) return 1;
  return 0;
}

static List _adopted_member(
  Compiler c, List protocols, List ancestry, String member) {
  foreach (Type current, ancestry) {
    List row = _member_row(c, protocols, current, member);
    if (!row) continue;
    match (row)
      case %(? ?(Symbol status) ?(String source) ?(Type signature) ? ?): {
        if (status == <implmntd>) return %($source $signature);
        if (status == <native>)
          return %(${_member_spelling(current, member)} $signature);
      }
    return %();
  }
  return %();
}

/* generated owners

   A base default is generated for a participant by exactly one adopted
   protocol. Two candidates are a collision, reported once per member. */

static typedef struct GeneratedOwners {
  Type participant;
  String member;
  Array candidates;
  List result, first_linkage;
  Symbol first_storage;
} GeneratedOwners;

/* Select the sole generated owner across all adopted protocols. */
static List _generated_owner(
  Compiler c, Type participant, String member) {
  List key = %("protocol-generated-owner" $participant $member), owner = NULL;
  $memo(c.proto_cache, key, owner) {
    owner = _generated_decision(c, participant, member);
  }
  return owner;
}

static List _generated_decision(
  Compiler c, Type participant, String member) {
  GeneratedOwners owners = {
    .participant = participant, .member = member, .candidates = []};
  Type base = NULL;
  List rows = NULL;
  $adopted_rows(c, _ordered_occurrences(c), participant, base, rows) {
    foreach (List row, rows)
      if (_consider(owners, c, base, row)) return _decision(owners);
  }
  return _decision(owners);
}

static int _consider(
  GeneratedOwners &g, Compiler c, Type base, List row) {
  match (row)
    case %(?(String member) base-dflt ?(String source)
           ?(Type expected) ordinary ?): {
      if (member != g.member) return 0;
      Symbol storage = _visibility(c, base, g.participant);
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

static List _decision(GeneratedOwners &owners) {
  List rows = owners.candidates.list_free();
  if (owners.result) return owners.result;
  match (rows) {
    case %(?only): return only;
    case %(?first ?second *rest):
      return %(conflict $first $second @rest);
  }
  return NULL;
}

static void _report_collision(
  Compiler c, Type participant, String member, Symbol kind, List first,
  List second) {
  (Type first_base, String first_source, Type first_expected) = first.cdr();
  (Type second_base, String second_source, Type second_expected) =
    second.cdr();
  List dedupe = %("protocol-generated-collision" $participant $member);
  if (dedupe in c.protocol_helpers) return;
  c.protocol_helpers[dedupe] = 1;
  int linkage_conflict = kind == <linkage>;
  String participant_repr = _type_spelling(participant);
  int incompatible_signatures = first_expected != second_expected;
  String message = $report.protocols.collision_prefix(
    member, participant_repr);
  String owners = _adoption_spelling(first_base, participant) + " and " +
                  _adoption_spelling(second_base, participant);
  if (linkage_conflict)
    message += $report.protocols.collision_linkage(owners);
  else if (incompatible_signatures)
    message += $report.protocols.collision_signature(owners);
  else
    message += $report.protocols.collision_ambiguous(
      owners, participant_repr, member);

  List notes = _collision_notes(kind, first, second);
  List row = _visible_adoption(c, first_base, participant);
  c.diagnostics.report(<protocol>, message, _adoption_location(row), notes);
}

static List _collision_notes(Symbol kind, List first, List second) {
  (Type first_base, String first_source, Type first_expected,
   Symbol first_storage) = first.cdr();
  (Type second_base, String second_source, Type second_expected,
   Symbol second_storage) = second.cdr();
  String first_repr = _type_spelling(first_base);
  String second_repr = _type_spelling(second_base);
  if (kind == <linkage>)
    return $report.protocols.collision_linkage_notes(
      first_repr, second_repr, first_storage, second_storage);
  if (first_expected != second_expected)
    return $report.protocols.collision_signature_notes(
      first_repr, second_repr, first_expected, second_expected);
  return $report.protocols.collision_source_notes(
    first_repr, second_repr, first_source, second_source);
}

// update helpers

/** Returns the function `result name(params) { body }` bound in this
    unit. `result` is the storage class and result type, so static, inline
    and external helpers share it; `params` are the parameter declarations,
    and `body` its lowered statements. */
List Compiler.wrapper_function(
  Compiler c, Type result, List binding, List params, List body) {
  List lowered = %(code-value "lowered" (seq @body) ());
  return _generated_function(
    c, binding, $!Unit{ $result $binding(@params) { $lowered } });
}

/** Returns `(declarations arguments)` for a helper that forwards its
    parameters of `types`: each declaration names a fresh parameter `a0`,
    `a1`, ..., and each argument reads it. */
List Compiler.forward_parameters(Compiler c, List types) {
  Array declarations = [], arguments = [];
  int index = 0;
  foreach (Type type, types) {
    List binding = c.sym.introduce(%"a${index++}");
    declarations.push(type.parameter_ast(binding));
    arguments.push($!($type){ $binding });
  }
  return %(${declarations.list_free()} ${arguments.list_free()});
}

/* Binds `syntax`, a template that defines the function `binding`. The
   template's own definition is not authored API of this unit; a documented
   prototype the function completes keeps its prose. */
static List _generated_function(
  Compiler c, List binding, List syntax) {
  List key = %(api-definition $binding);
  Var authored;
  int documented = c.semantic_binding_facts().try_get(key, authored);
  List function = c.bind_syntax(syntax, AST_UNIT, NULL);
  if (documented) c.set_fact(key, authored);
  else c.drop_fact(key);
  return function;
}

/** Returns a generated helper for a direct protocol-backed update.
    The resolved member must have exactly `(Participant, RHS) -> Participant`.
    A matching helper is emitted once into the unit's pending support;
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
  Type rhs_type = _update_rhs(participant, source_type);
  if (!rhs_type) return NULL;

  String suffix = postfix ? "postfix" : "update";
  String name =
    %"_x2c_gensym_proto_${participant.car().str().lower()}_${member}_$suffix";
  List helper = c.sym.introduce(name);
  List callee = $!($source_type){ $source_binding };
  /* A direct update stores the member's result through `lhs`; the `op`
     parameter keeps the update ABI of the dynamic path. The postfix form
     adds one and returns the value it read first. */
  List update = postfix
    ? $!Unit{
        static $participant $helper(volatile $participant *lhs, Symbol op) {
          $participant old = lhs[0];
          lhs[0] = $callee(lhs[0], 1);
          return old;
        }
      }
    : $!Unit{
        static $participant $helper(
            volatile $participant *lhs, Symbol op, $rhs_type rhs) {
          lhs[0] = $callee(lhs[0], rhs);
          return lhs[0];
        }
      };
  _publish_update(c, helper, update);
  c.protocol_helpers[key] = name;
  return name;
}

static Type _update_rhs(Type participant, Type signature) {
  List parameters = signature.car().list().cadr();
  Type result = signature.cdr();
  match (parameters)
    case %(?receiver ?rhs):
      if (List.equal(receiver, participant) && result == participant)
        return rhs;
  return NULL;
}

static void _publish_update(Compiler c, List helper, List syntax) {
  List function = _generated_function(c, helper, syntax);
  match (function)
    case %(function ?result ?declarator (block *body)):
      function = %(function $result $declarator
                    (block (at ${c.origin} (seq @body))));
  c.add_early(function);
}

// discard helpers

static typedef struct DiscardCall {
  Compiler c;
  List binding, key;
  Type signature, result;
  String stem;
  List declarations, arguments;
  Array discards;
  int which, fresh;
} DiscardCall;

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
  int fresh = %"fresh-callee $callee_identity" in c.protocol_helpers;
  /* An ordinary call may return its input or a view into it. Without a
     fresh-result contract, keep that input alive in its enclosing scope. */
  if (!fresh && (resolved_result.is_pointer() ||
                 resolved_result.is_aggregate()))
    return NULL;
  (List declarations, List arguments) =
    c.forward_parameters(signature.car().list().cadr());
  DiscardCall call = {
    .c = c, .binding = binding, .key = key, .signature = signature,
    .result = result, .stem = stem, .which = which, .fresh = fresh,
    .declarations = declarations, .arguments = arguments, .discards = []};
  _collect(call);
  return call.discards.len() ? _emit(call) : NULL;
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

static void _collect(DiscardCall &d) {
  int index = 0;
  foreach (List argument, d.arguments) {
    if (d.which & (1 << index++)) {
      List drop = d.c.resolve_protocol_member(argument.cadr(), "discard");
      if (drop) d.discards.push($!{ ${drop.car()}($argument); });
    }
  }
}

static List _emit(DiscardCall &d) {
  String name = %"_x2c_gensym_discard_${d.stem}_${d.which}";
  List helper_binding = d.c.sym.introduce(name);
  List value = d.c.sym.introduce("value");
  List call = d.c.bind_syntax(
    $!( ${d.binding}(@{d.arguments}) ), AST_EXPRESSION, d.result);
  List drops = d.discards.list_free();
  List shape = d.result == %(void)
    ? $!{ $call; @drops return; }
    : $!{ ${d.result} $value = $call; @drops return $value; };
  List body = d.c.bind_syntax(shape, AST_BLOCK, d.result);
  List helper = d.c.wrapper_function(
    %(static @{d.result}), helper_binding, d.declarations, body.cdr());
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

/* adapter generation

   Resolved conformances become native aliases here, and `conform` forms
   whose rule writes ordinary adapters and descriptor thunks. Their external
   signatures are published first, so the unit's own calls bind before the
   adapters exist. */

/** Inserts native aliases and presents other resolved conformances as
    `conform` forms. A native alias is inserted at the participant's inferred
    public or private boundary. Each other conformance whose forward converter
    the unit defines goes to the rule on the `conform` head, which
    `src/component-protocols.x` registers to write its adapters into the unit's
    pending support. The external conformances the unit declares are first
    recorded in its interface. Returns `ast` with native insertions applied.
*/
List Compiler.generate_protocol_adapters(Compiler c, List ast) {
  _record_conformances(c);
  /* Emit adapters only for finalized, declared conformances. A recorded
     one is installed only when this unit emits its adapters. */
  int central_initializer = _defines_function(c, "x2c_initialize_protocols");
  Array ordered = [];
  foreach (Var (key, value), c.conforms)
    if (value is <list>) ordered.push(%($key $value));
  foreach (List entry, _unused_recorded(c)) ordered.push(entry);
  ordered.sort();
  foreach (List ordered_row, ordered)
    match (ordered_row) {
      case %(? (protocol-conformance ?(Type base) ?(Type participant)
                ?(String forward) ?(String reverse) ?(Map variables)
                ?(Map bindings) (members *rows))): {
        if (_native_rows(rows)) {
          ast = _native_aliases(c, ast, base, participant, rows);
          continue;
        }
        if (!_defines_function(c, forward)) continue;
        if (_numeric_participant(c, participant)) continue;
        _present_conformance(c, ordered_row.cadr(), central_initializer);
      }
      case %((?(Type base) ?(Type participant))
             (conformance ? ? ?(String forward) *)): {
        if (!_defines_function(c, forward)) continue;
        if (_numeric_participant(c, participant)) continue;
        _reuse_conformance(c, base, participant);
        _present_conformance(
          c, c.conforms[%($base $participant)], central_initializer);
      }
    }
  ordered.free();
  return ast;
}

/** Publishes external native alias and ordinary adapter signatures.
    Protocols must already be resolved in the active symbol table.
*/
void Compiler.install_generated_protocol_symbols(Compiler c) {
  _reuse_defaults(c);
  // An owner lookup can install a recorded conformance in the registry.
  Array conformances = [];
  foreach (Var value, c.conforms) conformances.push(value);
  foreach (Var value, conformances)
    match (value)
      case %(protocol-conformance ?(Type base) ?(Type participant)
             ?(String forward) ? ? ? (members *rows)): {
        if (_native_rows(rows)) {
          if (_visibility(c, base, participant) != <external>) continue;
          foreach (List row, rows)
            match (row)
              case %(?(String member) ? ? ? ? ?(Type signature)):
                _install_generated(c, participant, member, signature);
          continue;
        }
        if (!(forward in c.fn_defs)) continue;
        if (_numeric_participant(c, participant)) continue;
        foreach (List row, rows)
          match (row)
            case %(?(String member) base-dflt ? ? ordinary ?): {
              List decision = _generated_owner(c, participant, member);
              match (decision)
                case %(owner ? ? ?signature external):
                  _install_generated(c, participant, member, signature);
            }
      }
  conformances.free();
}

/* Publish resolved external signatures before their adapters are generated. */
static void _install_generated(
  Compiler c, Type participant, String member, Type signature) {
  String generated = _member_spelling(participant, member);
  c.sym.define_global(%("generated-protocol" $generated), %(generated));
  c.sym.define_global(%($generated), signature);
}

/** Reports whether a generated member names a native protocol host function.
    Its defining header supplies the alias instead of a C prototype. */
int Compiler.native_protocol_alias(Compiler c, String name) {
  foreach (Var conformance, c.conforms)
    match (conformance)
      case %(protocol-conformance ? ?(Type participant) ? ? ? ?
             (members *rows)):
        if (_native_rows(rows))
          foreach (List row, rows)
            if (_member_spelling(participant, row.car()) == name) return 1;
  return 0;
}

// Numeric participants other than Symbol keep their native operators.
static int _numeric_participant(Compiler c, Type participant) =>
  c.sym.resolve_numeric_type(participant) && participant !== %("Symbol");

static int _defines_function(Compiler c, String name) {
  List binding = c.sym.reference(%($name), NULL);
  Var stored;
  if (!binding ||
      !c.semantic_binding_facts().try_get(%(completion $binding), stored))
    return 0;
  Symbol state = stored.list().car();
  return state == <definition> || state == <completed>;
}

/* Presents one conformance to the rule on the `conform` head, which
   `src/component-protocols.x` documents and ships. The owner of each
   member, its collisions and missing conversions, and the generated
   names are settled here; the rule writes the code. */
static void _present_conformance(
  Compiler c, List conformance, int central_initializer) {
  match (conformance)
    case %(protocol-conformance ?(Type base) ?(Type participant)
           ?(String forward) ?(String reverse) ?(Map variables)
           ?(Map bindings) (members *rows)):
      match (_record(c, base))
        case %(? ? ?(String binder) ? ?): {
          List adoption = _visible_adoption(c, base, participant);
          ProtocolAdapters adapters = {
            .c = c, .base = base, .participant = participant,
            .forward = forward, .reverse = reverse, .binder = binder,
            .variables = variables, .bindings = bindings,
            .adoption = adoption,
            .central_initializer = central_initializer,
            .shares_var_tag = base === %("Var") &&
              _adoption_representation(adoption)};
          Array presented = [];
          foreach (List row, rows) presented.push(_present(adapters, row));
          List members = presented.list_free();
          List form = %(
            conform $base $participant $forward $reverse $binder
              ${_descriptor(adapters)} $members);
          _generated_support(c, members, form);
        }
}

/* The rule's functions are generated: one that completes a documented
   prototype keeps its prose, and none publishes prose of its own. */
static void _generated_support(Compiler c, List members, List form) {
  Map facts = c.semantic_binding_facts(), authored = {};
  Array keys = [];
  foreach (List row, members) match (row) case %(? ? ? ? ? *parts):
    foreach (List part, parts) keys.push(%(api-definition ${part.cadr()}));
  foreach (List key, keys) {
    Var fact;
    if (facts.try_get(key, fact)) authored[key] = fact;
  }
  c.shipped_support(<conform>, form, "protocol conformance");
  foreach (List key, keys) {
    Var fact;
    if (authored.try_get(key, fact)) c.set_fact(key, fact);
    else c.drop_fact(key);
  }
}

/* A row and the parts of it this unit writes. A forwarding member is
   written for a base default; a descriptor of its own also declares a
   member another conformance generates, and fills the slot of each
   implemented or declared member that `VarMethods` has. */
static List _present(ProtocolAdapters &a, List row) {
  match (row)
    case %(?(String member) ?(Symbol status) ?(String source)
           ?(Type expected) ? ?(Type template)): {
      List parts = NULL;
      if (status == <base-dflt>) parts = _default_part(a, member, expected);
      else if (_has_descriptor(a)) {
        if (status == <no-member>)
          parts = _inherited_part(a, member, template);
        if ((status == <implmntd> || parts) &&
            a.c.sym.lookup_field(%(struct "VarMethods"), %($member)))
          parts = parts.append(%(${_thunk(a, member, template)}));
      }
      return %($member $status $source $expected $template @parts);
    }
  return NULL;
}

static int _has_descriptor(ProtocolAdapters &a) =>
  a.base === %("Var") && !a.shares_var_tag;

static List _default_part(
  ProtocolAdapters &a, String member, Type expected) {
  List decision = _generated_owner(a.c, a.participant, member);
  match (decision) {
    case %(owner ? ? ? ?storage): {
      String spelling = _member_spelling(a.participant, member);
      if (storage == <static>)
        return %((default ${a.c.sym.introduce(spelling)} $storage));
      List name = a.c.sym.reference(%($spelling), NULL);
      a.c.record_generated_symbol(spelling, expected);
      return %((default $name $storage));
    }
    case %((!set ?kind (!or linkage conflict)) ?first ?second *):
      _report_collision(a.c, a.participant, member, kind, first, second);
  }
  return NULL;
}

static List _inherited_part(
  ProtocolAdapters &a, String member, Type template) {
  List decision = _generated_owner(a.c, a.participant, member);
  match (decision) {
    case %(owner ? ? ?owner_expected ?): {
      List requirement = _descriptor_requirement(a, member, template);
      if (requirement) _report_requirement(a, requirement);
      else {
        String spelling = _member_spelling(a.participant, member);
        List name = a.c.sym.reference(%($spelling), NULL);
        return %((inherited $name $owner_expected));
      }
    }
    case %((!set ?kind (!or linkage conflict)) ?first ?second *):
      _report_collision(a.c, a.participant, member, kind, first, second);
  }
  return NULL;
}

/* A descriptor thunk's name and its signature with every type variable
   `Var`. */
static List _thunk(
  ProtocolAdapters &a, String member, Type template) {
  Map erased = a.bindings.copy();
  foreach (Var variable, a.variables.keys()) erased[variable] = %("Var");
  Type target = _substitute_signature(template, a.variables, erased);
  String participant_name = a.participant.car().str().lower();
  String name = a.c.fresh_name(%"proto_${participant_name}_$member");
  return %(thunk ${a.c.sym.introduce(name)} $target);
}

static List _descriptor(ProtocolAdapters &a) {
  if (!_has_descriptor(a)) return NULL;
  Symbol tag = _tag_value(_adoption_tag(a.adoption));
  String name = a.c.unprefixed(a.participant.car().str());
  if (!tag) name = name.lower();
  List methods =
    a.c.sym.introduce(a.c.fresh_name("protocol_methods"));
  Symbol area = a.central_initializer ? <protocol> : <prepare>;
  return %($methods $name ${a.participant.var_tag()} $area
           @{tag ? %($tag) : NULL});
}

static List _signature_declaration(
  Compiler c, String name, Type signature, int make_static) {
  List parameters = signature.car().list().cadr();
  Type result = signature.cdr();
  Array declarations = [];
  foreach (Type type, parameters) declarations.push(type.parameter_ast(NULL));
  List binding = c.sym.reference(%($name), NULL);
  List storage = make_static ? %(static @result) : result;
  return %(
    declare $storage
      (bindings (bind $binding ((fnmod (params @{declarations.list_free()})))))
  );
}

// alias insertion

/** Remembers a source typedef's declaration and visibility, which native
    alias insertion reads for its participant. */
void Compiler.record_source_typedef(
  Compiler c, String name, List declaration, int private) {
  c.protocol_helpers[%("source-typedef" $name)] = %($declaration $private);
}

static List _native_aliases(
  Compiler c, List ast, Type base, Type participant, List rows) {
  Var stored;
  if (!c.protocol_helpers.try_get(
    %("source-typedef" ${participant.car()}), stored)) return ast;
  (List source, int private) = stored;
  int make_static = _visibility(c, base, participant) == <static>;
  Array aliases = [];
  foreach (List row, rows)
    match (row)
      case %(?(String member) ? ?(String binding) ? ?
             ?(Type signature)): {
        List alias = _native_alias(
          c, participant, member, binding, signature, make_static);
        aliases.push(alias);
      }
  return _insert_at_boundary(
    ast, source, private, aliases.list_free(), make_static);
}

static List _native_alias(
  Compiler c, Type participant, String member, String source,
  Type signature, int make_static) {
  String target = _member_spelling(participant, member);
  List declaration = _signature_declaration(c, target, signature, make_static);
  if (!make_static) c.record_generated_symbol(target, signature);
  List native_binding = c.sym.reference(%($source), NULL);
  return c.finish_foreign_alias(
    declaration, $!($signature){ $native_binding });
}

static List _insert_at_boundary(
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

static int _starts_private_region(List node) {
  match (node) {
    case %((!or function falias) *): return 1;
    case %(declare ?type *): return type.type().is_static();
  }
  return 0;
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
  foreach (Var value, symbols) {
    if (value is not <list>) continue;
    match (value) {
      case %(protocol
             (!set ?record ("protocol-record" ?base *))
             ?storage ?location): {
        _install_occurrence(c, base, record, storage, location);
      }
      case %(adopt *): _install_stored(c, value);
      case %(conformance ?base ?participant *):
        c.protocol_helpers[%("recorded-conformance" $base $participant)] =
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
               ${$source_literal_content(%(("Symbol") ? ?candidate))})))
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
