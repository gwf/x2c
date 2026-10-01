/*  protocol.x -- protocols from declaration to generated adapters

    Copyright (c) 2025 Gary William Flake.

    This module owns the protocol feature: it parses protocol and adoption
    declarations, keeps their rows in per-unit registries, resolves each
    adoption into a conformance, answers member and operator lookups, and
    generates the adapters a conformance needs. Registries are rebuilt per
    translation unit; a static row is visible only when its canonical source
    path is the current unit.
*/
#pragma once
#include "compiler.x"
#pragma private
$(import "../src/error-reports.xmacro")
$(import "../src/grammar.xmacro")

#include <limits.h>
#include <stdlib.h>
#include <string.h>
#include "collect.x"
#include "expressions.x"
#include "parse.x"
#include "meta.x"

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
    case %(adopt ? ? ? (tag ?) ?): return NULL;
    case %(adopt ? ? ? ?representation ?): return representation;
  }
  return NULL;
}

static List _adoption_tag(List adoption) {
  match (adoption) case %(adopt ? ? ? (tag ?tag) ?): return tag;
  return NULL;
}

static List _adoption_location(List adoption) => adoption.last();

static List Compiler._record(Compiler c, Type base) {
  Var stored;
  if (!c.protocols.try_get(base, stored)) return NULL;
  List occurrence = stored;
  return occurrence.car();
}

static List Compiler._adoption_row(
  Compiler c, Type base, Type participant, Symbol storage) {
  String path = c._path();
  List key = storage == <static>
           ? %($base $participant $path)
           : %($base $participant);
  Var stored;
  return c.adoptions.try_get(key, stored) ? stored : NULL;
}

static List Compiler._visible_adoption(
  Compiler c, Type base, Type participant) {
  List local = c._adoption_row(base, participant, <static>);
  return local ? local : c._adoption_row(base, participant, <external>);
}

static Symbol Compiler._visibility(Compiler c, Type base, Type participant) {
  List external = c._adoption_row(base, participant, <external>);
  List local = c._adoption_row(base, participant, <static>);
  if (external && local) {
    if (c._canonical_file(_adoption_location(external)) ==
        c._canonical_file(_adoption_location(local)))
      return <static>;
    return <mixed>;
  }
  if (local) return <static>;
  if (external) return <external>;
  return 0;
}

// Participation exists only for a declared adoption row.
static int Compiler._is_adopted(Compiler c, Type base, Type participant) =>
    !!c._visibility(base, participant);

static int Compiler._owns_adoption(Compiler c, Type base, Type participant) {
  List row = c._visible_adoption(base, participant);
  return row && c._canonical_file(_adoption_location(row)) == c._path();
}

typedef struct AdoptionDraft {
  Compiler c;
  Type base, participant, representation;
  Symbol storage, tag;
  List tag_expression, location;
  Token participant_token, modifier_token;
} AdoptionDraft;

// source locations

static String Compiler._path(Compiler c) {
  Var cached;
  if (c.protocol_helpers.try_get(<proto-path>, cached)) return cached;
  String result = c._normalize_file(c.filename ? c.filename : "<stdin>");
  c.protocol_helpers[<proto-path>] = result;
  return result;
}

static String Compiler._canonical_file(Compiler c, List location) {
  String file = _location_file(location);
  List key = %(proto-file $file);
  Var cached;
  if (c.protocol_helpers.try_get(key, cached)) return cached;
  String result = c._normalize_file(file);
  c.protocol_helpers[key] = result;
  return result;
}

/* A relative path names a file below the working directory, or else one below
   the x2c root, where `Compiler.display_path` spells root sources. It
   resolves on disk itself: trying the root depends on whether the first path
   resolved, which `Compiler.canonical_path` does not report. */
static String Compiler._normalize_file(Compiler c, String file) {
  char path[PATH_MAX], String root = c.root_dir;
  if (realpath(file, path) ||
      (root && file[0] != '/' && realpath(%"$root/$file", path)))
    file = path;
  return c.display_path(file);
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

static int Compiler._is_private(Compiler c, String name) =>
  %($name) in c.sym.file_statics();

// spellings

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

static Type Compiler._declared(Compiler c, String name) {
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
typedef struct ProtocolSyntax {
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
  syntax.head();
  if (c.peek(0) == <;>) return syntax.adoption();
  syntax.check_body();
  syntax.warn_shadowed();
  return syntax.body();
}

static void ProtocolSyntax.head(ProtocolSyntax &p) {
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
  p.modifiers();
}

static void ProtocolSyntax.modifiers(ProtocolSyntax &p) {
  Compiler c = p.c;
  if (c.at_word("as")) {
    p.modifier_token = c.token;
    c.next();
    p.representation = c.parse_type_name().canonicalize();
    if (!p.generated_base && p.base !== %("Var"))
      $report(c, "protocol.as.var", p.modifier_token);
  }
  if (c.at_word("tag")) {
    p.modifier_token = c.token;
    c.next();
    if (p.representation)
      $report(c, "protocol.modifier.conflict", p.modifier_token);
    p.tag = c.try_parse_macro_slot(<expression>);
    if (!p.tag) p.tag = c.parse_atomic_literal();
    if (!p.generated_base && p.base !== %("Var"))
      $report(c, "protocol.tag.var", p.modifier_token);
  }
}

static List ProtocolSyntax.adoption(ProtocolSyntax &p) {
  Compiler c = p.c;
  c.next();
  List location = c.token_location(p.start);
  if (c.macro_holes || (c.shallow && !c.collect_protocols)) {
    List adoption = _adoption_node(
      p.base, p.participant_type, p.storage, p.representation, p.tag,
      location);
    return p.meta ? %(meta-protocol $adoption) : adoption;
  }
  AdoptionDraft draft = {
    .c = c, .base = p.base, .participant = p.participant_type,
    .storage = p.storage, .representation = p.representation,
    .tag_expression = p.tag, .location = location,
    .participant_token = p.participant_token,
    .modifier_token = p.modifier_token};
  List adoption = draft.publish();
  if (p.meta) c._retain_meta_protocol(adoption);
  return adoption;
}

static void ProtocolSyntax.check_body(ProtocolSyntax &p) {
  Compiler c = p.c;
  if (p.meta)
    $report(c, "protocol.meta.adoption", p.meta);

  if (p.representation || p.tag)
    $report(c, "protocol.modifier.adoption", p.representation, p.start);

  if (!p.participant)
    $report(c, "protocol.participant.expected", p.participant_token);

  if (p.storage == <static>)
    $report(c, "protocol.static.adoption", p.start);
  c.expect(<"{">);
}

static void ProtocolSyntax.warn_shadowed(ProtocolSyntax &p) {
  /* Only the full parse warns about a binder shadowing a visible type. */
  Compiler c = p.c;
  if (c.shallow) return;
  String participant = p.participant;
  List shadowed = c.sym.get(%($participant));
  if (!shadowed || !shadowed.type().is_typedef()) return;
  String hint = %"hint: a bodyless `protocol BASE($participant);` " +
    "declares an adoption; a body introduces a fresh type variable";
  c.report_warning(
    <shadow>,
    %"protocol binder '$participant' shadows a visible type name",
    p.participant_token, %($hint));
}

static List ProtocolSyntax.body(ProtocolSyntax &p) {
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
        $report(c, "protocol.assoc.order");
      associations.push(c._parse_associated(type_names));
      continue;
    }
    saw_member = 1;
    members.push(c._parse_member(participant, member_names));
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
  return c._publish_record(record, p.base, location);
}

static List Compiler._parse_associated(Compiler c, Map names) {
  c.expect(<associated>);
  if (c.peek(0) != <ident>)
    $report(c, "protocol.assoc.expected");
  String name = c.token.text;
  c.next();
  if (name in names)
    $report(c, "protocol.type.duplicate", name);
  c.expect(<=>);
  Type type = c.parse_type_name().canonicalize();
  c.expect(<;>);
  names[name] = 1;
  c.sym.define(%($name), %(typedef $name));
  return %($name $type);
}

static List Compiler._parse_member(
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
    $report(c, "protocol.member.single");
  String name = _member_name(identity, participant);
  if (!name)
    $report(c, "protocol.member.owner", participant);
  Type signature = declaration.type_from_ast().canonicalize();
  if (!signature.is_function())
    $report(c, "protocol.member.function", name);
  if (name in members)
    $report(c, "protocol.member.duplicate", name);
  String native = c._native_member();
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
  String full_name = binding_identity_spelling(identity);
  String prefix = %"${participant}_";
  return full_name && full_name.startswith(prefix)
    ? full_name[prefix.len():] : NULL;
}

static String Compiler._native_member(Compiler c) {
  if (!c.test(<=>)) return NULL;
  if (c.peek(0) != <ident>)
    $report(c, "protocol.native.ident");
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
      c._retain_meta_protocol(published);
      return published;
    }
    case %(protocol
           (!set ?record
             ("protocol-record"
               ?(List base) (!is ? type string)
               (associated *) (members *)))
           external ?(List location)):
      return c._publish_record(record, base, location);
  }
  return c._publish_adoption(node, participant_token, representation_token);
}

static List Compiler._publish_adoption(
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
  return c._publish_var_adoption(node, participant_token, modifier_token);
}

static List Compiler._publish_var_adoption(
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
  $report(c, "macro.protocol.invalid");
}

static List Compiler._publish_record(
  Compiler c, List record, Type base, List location) {
  Symbol storage = c.source_private > 0 ? <static> : <external>;
  c._install_occurrence(base, record, storage, location);
  c.proto_cache = {};
  List published = %(protocol $record $storage $location);
  c._retain_source_node(published, storage, location);
  return published;
}

/* A `meta` adoption lets compile-time code call the conformance's
   witnesses. Its row travels beside the adoption row it marks. */
static void Compiler._retain_meta_protocol(Compiler c, List adoption) {
  Type (base, participant) = adoption.cdr();
  c._retain_source_node(
    %(meta-protocol $base $participant), _adoption_storage(adoption),
    %(meta-protocol @{_adoption_location(adoption)}));
}

static void Compiler._retain_source_node(
  Compiler c, List node, Symbol storage, List location) {
  List invocation = c.origin_location(c.origin);
  if (!invocation &&
      (!c.shallow ||
       (storage == <static> && c.source_private < 0)))
    return;
  List key = c._source_key(location);
  c.sym.set(key, node);
  if (storage == <static>) c.sym.mark_static(key);
}

// Keep definition provenance in a generated node while its invocation site
// makes repeated expansions distinct in the retained symbol table.
static List Compiler._source_key(Compiler c, List location) {
  List invocation = c.origin_location(c.origin);
  return invocation
       ? %("source-node" $location $invocation)
       : %("source-node" $location);
}

static void Compiler._install_occurrence(
  Compiler c, Type base, List record, Symbol storage, List location) {
  String file = c._canonical_file(location);
  if (storage == <static> && file != c._path()) return;
  Var stored;
  if (!c.protocols.try_get(base, stored)) {
    c.protocols[base] = _occurrence(record, storage, location);
    return;
  }
  List occurrence = stored, existing = occurrence.car();
  if (existing == record) {
    if (c._canonical_file(_occurrence_location(occurrence)) == file &&
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
  $report(c, "protocol.decl.conflict", base, first_location, second_location);
}

// adoption drafts

static List AdoptionDraft.publish(AdoptionDraft &a) {
  Compiler c = a.c;
  if (a.tag_expression) a.tag_expression = _tag_syntax(a.tag_expression);
  String spelling = a.participant.car().str();
  List declared = c.sym.get(%($spelling));
  if ((!declared || !declared.type().is_typedef()) && !c.shallow)
    $report(c, "protocol.type.undeclared", spelling,
      a.participant_token);
  a.tag = a.check_modifiers();
  a.storage = a.published_storage(spelling);
  a.check_previous();
  a.install();
  // An adoption resolved when the parse began has reported its failures.
  List pair = %(${a.base} ${a.participant});
  int resolved = pair in c.conforms;
  c.conforms.del(pair);
  c.proto_cache = {};
  if (!c.shallow)
    c._resolve_adoption(a.base, a.participant, resolved ? NULL : a.location);
  List published = a.node();
  // A generated class declares several adoptions at one location.
  c._retain_source_node(
    published, a.storage, %(adopt ${a.base} @{a.location}));
  return published;
}

static List AdoptionDraft.node(AdoptionDraft &a) => _adoption_node(
  a.base, a.participant, a.storage, a.representation, a.tag_expression,
  a.location);

static String AdoptionDraft.spelling(AdoptionDraft &a) =>
  %"${_type_spelling(a.base)}(${_type_spelling(a.participant)})";

static List _tag_syntax(List expression) {
  match (expression) {
    case %(src ? ?(List syntax)):
      return _tag_syntax(syntax);
    case %(expr (<macro-expr>) ?(List syntax)):
      return _tag_syntax(syntax);
  }
  return expression;
}

static Symbol AdoptionDraft.check_modifiers(AdoptionDraft &a) {
  Type representation = a.representation;
  if (representation && !representation.fixed_var_tag())
    a.report_modifier(_representation_error(representation));
  if (!a.tag_expression) return 0;
  Symbol tag = _tag_value(a.tag_expression);
  if (!tag) a.report_modifier("Var adoption tag must be a Symbol literal");
  return tag;
}

/* A constructed adoption has no modifier token, so its diagnostic goes to
   the adoption's location. */
static void AdoptionDraft.report_modifier(AdoptionDraft &a, String message) {
  if (a.modifier_token)
    a.c.report_error(<protocol>, message, a.modifier_token, NULL);
  else
    a.c.diagnostics.report(<protocol>, message, a.location, NULL);
}

static Symbol _tag_value(List expression) {
  match (expression)
    case %(expr ("Symbol") ?content):
      match (content)
        case $source_literal_content(%(("Symbol") ? ?tag)):
          if (tag is <symbol>) return tag;
  return 0;
}

static Symbol AdoptionDraft.published_storage(
  AdoptionDraft &a, String spelling) {
  Compiler c = a.c;
  if (a.storage == <static>) return <static>;
  if (c.source_private < 0) return a.storage;
  List record = c._record(a.base);
  int private_native = record &&
    c._has_private_native(record.last().list().cdr());
  String base_name = _base_name(a.base);
  String forward = base_name ? %"${spelling}_${base_name.lower()}" : NULL;
  String reverse = base_name
    ? c.reverse_converter_spelling(base_name, "", spelling) : NULL;
  String alternate = base_name
    ? c.reverse_converter_spelling(base_name, "as_", spelling) : NULL;
  Var occurrence_value;
  List occurrence = c.protocols.try_get(a.base, occurrence_value)
    ? occurrence_value : NULL;
  int private = c.source_private > 0 ||
    (occurrence && _occurrence_storage(occurrence) == <static>) ||
    c._is_private(spelling) ||
    (forward && c._is_private(forward)) ||
    (reverse && c._is_private(reverse)) ||
    (alternate && c._is_private(alternate)) ||
    private_native;
  return private ? <static> : a.storage;
}

static int Compiler._has_private_native(Compiler c, List templates) {
  foreach (List template, templates) {
    String binding = template.caddr();
    if (binding && c._is_private(binding)) return 1;
  }
  return 0;
}

static void AdoptionDraft.check_previous(AdoptionDraft &a) {
  Compiler c = a.c;
  if (c.shallow) return;
  String path = c._canonical_file(a.location);
  List key = %("parsed-protocol-adoption" ${a.base} ${a.participant} $path);
  Var previous;
  if (!c.protocol_helpers.try_get(key, previous)) {
    c.protocol_helpers[key] = a.node();
    return;
  }
  List row = previous;
  if (_adoption_representation(row) == a.representation &&
      _adoption_tag(row).equal(a.tag_expression)) return;
  String first = %"first: ${_location_string(_adoption_location(row))}";
  String second = %"second: ${_location_string(a.location)}";
  c.diagnostics.report(
    <protocol>, %"conflicting adoption declarations for ${a.spelling()}",
    a.location, %($first $second));
}

static void AdoptionDraft.install(AdoptionDraft &a) {
  Compiler c = a.c;
  String path = c._canonical_file(a.location);
  if (a.storage == <static> && path != c._path()) return;
  a.participant.register_var_adoption(a.representation, a.tag);
  List key = a.storage == <static>
           ? %(${a.base} ${a.participant} $path)
           : %(${a.base} ${a.participant});
  List row = a.node();
  Var stored;
  if (!c.adoptions.try_get(key, stored)) {
    c.adoptions[key] = row;
    return;
  }
  List existing = stored;
  if (existing == row) return;
  List first_location = _adoption_location(existing);
  if (c._canonical_file(first_location) == path) return;
  $report(c, "protocol.adoption.conflict", a, first_location);
}

// resolution

/* Native and ordinary resolution are the only conformance-row producers. A
   row carries base, participant, converters, type-variable maps, and member
   rows of `(name status source expected default-kind template)`. Consumers
   dispatch on `status`; a non-list cache value records failed resolution. */
typedef struct ProtocolRequirements {
  String binder;
  List associations, templates;
} ProtocolRequirements;

/** Resolves every visible adoption into the current conformance registry.
    Resolution starts from an empty registry; diagnostics are located only for
    adoptions owned by the current translation unit.
*/
void Compiler.resolve_protocols(Compiler c) {
  c.conforms = {};
  String owner = c._path();
  foreach (Var value, c.adoptions) {
    List adoption = value;
    Type (base, participant) = adoption.cdr();
    Symbol storage = _adoption_storage(adoption);
    List location = _adoption_location(adoption);
    String path = c._canonical_file(location);
    if (storage == <static> && path != owner) continue;
    c._resolve_adoption(base, participant, path == owner ? location : NULL);
  }
}

static void Compiler._resolve_adoption(
  Compiler c, Type base, Type participant, List location) {
  List record = c._record(base);
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
      c._resolve_record(base, participant, location, requirements);
    }
}

static void Compiler._resolve_record(
  Compiler c, Type base, Type participant, List location,
  ProtocolRequirements &requirements) {
  int native = _is_native(requirements.templates);
  List conformance = NULL, failure = NULL;
  if (native) {
    Type definition = c._participant_definition(participant);
    conformance = c._resolve_native(
      base, participant, requirements, definition, failure);
  }
  else
    conformance = c._resolve_ordinary(
      base, participant, requirements, failure);

  if (!conformance) {
    if (!location) return;
    String detail = c._missing_detail(base, participant, native, failure);
    c.diagnostics.report(<protocol>, detail, location, NULL);
    return;
  }
  if (location) {
    List rows = conformance.last().list().cdr();
    if (native) c._install_native_bindings(participant, rows);
    c._report_sig_conflicts(base, participant, rows, location);
  }
}

static String Compiler._missing_detail(
  Compiler c, Type base, Type participant, int native, List failure) {
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
    ? c._declared(%"${participant.car()}_${base_name.lower()}")
    : NULL;
  if (base_name && !_exact_conversion(forward_type, participant, base))
    return %"${prefix}no forward conversion '$forward'";
  return %"${prefix}no reverse conversion '$base_repr.$lowered' " +
    %"or '$base_repr.as_$lowered'";
}

static String _requirement_detail(Type base, Type participant, List failure) {
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

static void Compiler._report_sig_conflicts(
  Compiler c, Type base, Type participant, List rows, List location) {
  String base_repr = _type_spelling(base);
  String participant_repr = _type_spelling(participant);
  String declaration_site = c._definition_location(base);
  foreach (List row, rows)
    match (row)
      case %(?(String member) sig-cnflct ?(String binding)
             ?(Type expected) ? ?): {
        List dedupe = %("protocol-sig-conflict" $participant $member);
        if (dedupe in c.protocol_helpers) continue;
        c.protocol_helpers[dedupe] = 1;
        Type actual = c._declared(binding);
        String owner = %"$base_repr($participant_repr)";
        String protocol_note = %"protocol member '$member' declared by $owner";
        if (declaration_site)
          protocol_note = %"$protocol_note at $declaration_site";
        String actual_repr = actual.repr();
        String conflict_note =
          %"conflicting definition '$binding': $actual_repr";
        String expected_note = %"expected: ${expected.repr()}";
        c.diagnostics.report(
          <protocol>,
          %"'$binding' has a signature incompatible " +
            %"with $owner member '$member'",
          location,
          %($protocol_note $conflict_note $expected_note)
        );
      }
}

static String Compiler._definition_location(Compiler c, Type base) {
  List stored = c.protocols[base];
  return _location_string(_occurrence_location(stored));
}

// native conformance

typedef struct NativeResolution {
  Type base, participant, definition;
  String binder;
  Map variables, bindings;
} NativeResolution;

static List Compiler._resolve_native(
  Compiler c, Type base, Type participant, ProtocolRequirements &requirements,
  Type participant_definition, List &failure) {
  failure = NULL;
  List key = %($base $participant);
  Var stored;
  if (c.conforms.try_get(key, stored)) {
    if (stored is not <list>) return NULL;
    List conformance = stored;
    c._install_native_bindings(participant, conformance.last().list().cdr());
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

static List NativeResolution.rows(
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

static Type Compiler._participant_definition(Compiler c, Type participant) {
  if (!participant.is_bare_typedef_name()) return NULL;
  String name = participant.car();
  Var definition = c.sym.global_symbols()[%(typedef $name)];
  return definition is <list> ? definition : NULL;
}

static void Compiler._install_native_bindings(
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

typedef struct MemberResolution {
  Compiler c;
  Type base, participant, representation;
  String binder, forward;
  Map variables, defaults, bindings;
} MemberResolution;

static List Compiler._resolve_ordinary(
  Compiler c, Type base, Type participant,
  ProtocolRequirements &requirements, List &failure) {
  failure = NULL;
  Var stored;
  List key = %($base $participant);
  if (c.conforms.try_get(key, stored))
    return stored is <list> ? stored : NULL;
  String base_name = _base_name(base);
  if (!base_name || !participant.is_bare_typedef_name()) goto does_not_conform;
  String forward = c._forward_binding(base, participant);
  String reverse = c._reverse_binding(base, participant);
  MemberResolution resolution = {
    .c = c, .base = base, .participant = participant,
    .binder = requirements.binder,
    .variables = {}, .defaults = {}, .bindings = {},
    .representation = base === %("Var")
      ? _adoption_representation(c._visible_adoption(base, participant))
      : NULL,
    .forward = base !== %("Var") ? forward : NULL};
  List rows = resolution.resolve(
    requirements.associations, requirements.templates);
  ProtocolAdapters adapters = {
    .c = c, .base = base, .binder = requirements.binder,
    .forward = forward, .reverse = reverse};
  List requirement = adapters.requirement(rows);
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

static String Compiler._forward_binding(
  Compiler c, Type base, Type participant) {
  String base_name = _base_name(base);
  if (!base_name || !participant.is_bare_typedef_name()) return NULL;
  String binding = %"${participant.car()}_${base_name.lower()}";
  Type found = c._declared(binding);
  if (!_exact_conversion(found, participant, base)) return NULL;
  return binding;
}

static String Compiler._reverse_binding(
  Compiler c, Type base, Type participant) {
  String base_name = _base_name(base);
  if (!base_name || !participant.is_bare_typedef_name()) return NULL;
  String participant_name = participant.car();
  String conventional =
    c.reverse_converter_spelling(base_name, "", participant_name);
  Type found = c._declared(conventional);
  if (_exact_conversion(found, base, participant)) return conventional;
  String alternate =
    c.reverse_converter_spelling(base_name, "as_", participant_name);
  found = c._declared(alternate);
  if (_exact_conversion(found, base, participant)) return alternate;
  return NULL;
}

/* Members are selected against the participant's bindings first; the
   associated-type defaults fill what selection left unbound before each
   member's expected signature is completed. */
static List MemberResolution.resolve(
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
    List member = r.select(row);
    if (member) selected.push(member);
  }
  foreach (Var (name, value), r.defaults) r.bindings.setdefault(name, value);
  Array completed = [];
  foreach (List row, selected) {
    List member = r.complete(row);
    if (member) completed.push(member);
  }
  selected.free();
  return completed.list_free();
}

static List MemberResolution.select(MemberResolution &r, List row) {
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

static Type MemberResolution.find_member(
  MemberResolution &r, String member, String &selected) {
  String binding = _member_spelling(r.participant, member);
  Type actual = r.c._declared(binding);
  if (actual && r.c._default_completes(binding, actual, r.forward))
    actual = NULL;
  if (!actual) {
    String imported = r.c.imported_spelling(binding);
    if (imported) {
      actual = r.c._declared(imported);
      if (actual) binding = imported;
    }
  }
  if (actual) selected = binding;
  foreach (Type owner,
           (r.base !== %("Var") || r.representation) && !actual
             ? r.c._ancestry(r.participant).cdr() : NULL) {
    if (owner == r.base) break;
    if (r.base === %("Var") && owner != r.representation) continue;
    actual = r.c._method_signature(owner, r.participant, member, selected);
    if (actual || r.base === %("Var")) break;
  }
  return actual;
}

static Type Compiler._method_signature(
  Compiler c, Type owner, Type participant, String member,
  String &selected) {
  if (!owner.is_bare_typedef_name()) return NULL;
  String source = _member_spelling(owner, member);
  Type signature = c._declared(source);
  if (!signature) {
    String imported = c.imported_spelling(source);
    if (imported) {
      signature = c._declared(imported);
      if (signature) source = imported;
    }
  }
  if (!signature) return NULL;

  List binding = c.sym.reference(%($source), NULL);
  signature = c._relative_signature(binding, signature, participant);
  List parameters = NULL, Type result = NULL;
  if (_function_parts(signature, parameters, result) &&
      parameters && parameters.car() == owner) {
    parameters = _inherited_parameters(parameters, owner, participant);
    signature = %((func $parameters) @result);
  }
  selected = source;
  return signature;
}

static Type Compiler._relative_signature(
  Compiler c, List binding, Type signature, Type receiver) {
  Var stored;
  if (!c.semantic_binding_facts().try_get(%(self $binding), stored))
    return signature;
  Type relative = stored, base = receiver.canonicalize().base_type();
  return relative.search_replace(<self>, base.car());
}

static List _inherited_parameters(
  List parameters, Type owner, Type participant) {
  if (!parameters) return NULL;
  Var parameter = parameters.car();
  return cons(
    parameter == owner ? participant : parameter,
    _inherited_parameters(parameters.cdr(), owner, participant));
}

/* A bodyless, non-static prototype of a member whose base default the
   visible forward converter generates declares that default rather than
   implementing the member. */
static int Compiler._default_completes(
  Compiler c, String name, Type declared, String forward) =>
  forward && declared.is_function() && forward in c.fn_defs &&
  !c.fn_defs.contains(name) &&
  !c.sym.file_statics().contains(%(function $name));

static List MemberResolution.complete(MemberResolution &r, List row) {
  match (row)
    case %(?(String member) ?(Symbol status) ?(String source)
           ? ? ?(Type template)): {
      Type expected = _substitute_signature(template, r.variables, r.bindings);
      Symbol default_kind = <none>;
      if (status == <no-member>) {
        String base_name = _base_name(r.base);
        if (base_name && r.base !== %("Var")) {
          String fallback = %"${base_name}_$member";
          Type fallback_type = r.c._declared(fallback);
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
   generated, and adapter generation checks an inherited member the same
   way. Both describe the adapters with one record. */

/* The adapters one conformance needs. Resolution fills the base, binder,
   and converters; generation fills the rest. */
typedef struct ProtocolAdapters {
  Compiler c;
  Type base, participant;
  String forward, reverse, binder;
  Map variables, bindings;
  List adoption;
  Array thunks;
  int shares_var_tag, central_initializer;
} ProtocolAdapters;

static List ProtocolAdapters.requirement(ProtocolAdapters &a, List rows) {
  foreach (List row, rows)
    match (row)
      case %(?(String member) ?(Symbol status) ? ?
             ?(Symbol default_kind) ?(Type template)): {
        if (status == <base-dflt> && default_kind == <ordinary>) {
          List requirement =
            a.conversion_requirement(member, template, <fallback>);
          if (requirement) return requirement;
        }
        if (status == <implmntd>) {
          List requirement = a.descriptor_requirement(member, template);
          if (requirement) return requirement;
        }
      }
  return NULL;
}

static List ProtocolAdapters.descriptor_requirement(
  ProtocolAdapters &a, String member, Type template) {
  if (a.base !== %("Var") ||
      !a.c.sym.lookup_field(%(struct "VarMethods"), %($member)))
    return NULL;
  return a.conversion_requirement(member, template, <thunk>);
}

static List ProtocolAdapters.conversion_requirement(
  ProtocolAdapters &a, String member, Type template, Symbol adapter) {
  int fallback = adapter == <fallback>;
  List parameters = template.car().list().cadr();
  Type result = template.cdr();
  Symbol direction = fallback ? <forward> : <reverse>;
  foreach (Var parameter, parameters) {
    if (_is_exact_variable(parameter, a.binder)) {
      if (!(fallback ? a.forward : a.reverse))
        return %($member $adapter $direction parameter);
    }
    else if (_contents(parameter, a.binder) & PROTOCOL_VARIABLE)
      return %($member $adapter nested parameter);
  }
  direction = fallback ? <reverse> : <forward>;
  if (_is_exact_variable(result, a.binder)) {
    if (!(fallback ? a.reverse : a.forward))
      return %($member $adapter $direction result);
  }
  else if (_contents(result, a.binder) & PROTOCOL_VARIABLE)
    return %($member $adapter nested result);
  return NULL;
}

static int _is_exact_variable(Var value, String variable) {
  if (value is not <list>) return 0;
  List type = value;
  return type && !type.cdr() && type.car() is <string> &&
         type.car() == variable;
}

static void ProtocolAdapters.report_requirement(
  ProtocolAdapters &a, List failure) {
  Type base = a.base, participant = a.participant;
  List dedupe =
    %("protocol-adapter-requirement" $base $participant ${failure.car()});
  if (dedupe in a.c.protocol_helpers) return;
  a.c.protocol_helpers[dedupe] = 1;
  List row = a.c._visible_adoption(base, participant);
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

static String _type_variable(Var value, Map variables) {
  String name = NULL;
  if (value is <string>) name = value;
  match (value)
    case %(?(String only)): name = only;
  if (!name) return NULL;
  return name in variables ? name : NULL;
}

static int _variable_is(Var template, Map variables, String name) {
  String variable = _type_variable(template, variables);
  return variable && variable == name;
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
  if (c.import_protocols) c._install_imports();
  Type owner = participant;
  if (!c._is_adopted(base, owner)) {
    List ancestry = c._ancestry(participant).cdr();
    for (; ancestry; ancestry = ancestry.cdr()) {
      owner = ancestry.car();
      if (c._is_adopted(base, owner)) break;
    }
    if (!ancestry) return NULL;
  }
  List key = %($base $owner);
  Var stored = c.conforms[key];
  /* One adoption is resolved where it is asked for when the parse has not
     resolved it. `AdoptionDraft.publish` already skips resolving during
     a shallow pass, and an import installed just above resolves nothing.
     `adoptions` holds only the adoptions this compiler may use, and the full
     parse resolves all of them before it starts, so the full parse has an
     entry for every pair that reaches this point. */
  if (stored is void) {
    c._resolve_adoption(base, owner, NULL);
    stored = c.conforms[key];
  }
  if (stored is not <list>) return NULL;
  List conformance = stored;
  c._install_native_bindings(owner, conformance.last().list().cdr());
  return conformance;
}

/* A macro import parses one body during the caller's collection pass, which
   keeps its own registries empty because it parses no bodies at all. That
   body's `foreach` is the only reader, so the protocols and adoptions visible
   to the import are installed the first time one is asked for. Installing
   them for every import, or resolving every conformance here rather than the
   one below, each cost more than the feature. */
static void Compiler._install_imports(Compiler c) {
  c.import_protocols = 0;
  Map symbols = c.sym.base_symbols();
  Map current = c.sym.current_symbols();
  if (current) symbols.merge(current);
  c.rebuild_protocols(symbols);
}

static List Compiler._ancestry(Compiler c, Type participant) =>
  c._proto_cached(
    %("protocol-ancestry" $participant), %!(Compiler &c) => {
    Array ancestry = [], Type current = participant;
    for (int distance = 0; current && distance <= 128; distance++) {
      ancestry.push(current);
      if (!current.is_typedef_name() && !current.is_typedef()) break;
      current = c.sym.get(current);
    }
    return ancestry.list_free();
  });

/* The single entry point for proto_cache. A hit returns the cached List (a
   non-list value records a null result); a miss runs compute(c) and
   stores what it returns. */
static List Compiler._proto_cached(Compiler c, Var key, Func compute) {
  Var cached;
  if (c.proto_cache.try_get(key, cached))
    return cached is <list> ? cached : NULL;
  List result = compute(c);
  c.proto_cache[key] = result ? result : 0;
  return result;
}

static List Compiler._ordered_occurrences(Compiler c) =>
  c._proto_cached(
    <proto-ordr>, %!(Compiler &c) => {
    Array ordered = [];
    foreach (Var (base, occurrence), c.protocols)
      ordered.push(%($base $occurrence));
    ordered.sort();
    return ordered.list_free();
  });

/** Returns unique member spellings from the participant's visible adopted
    conformances. Resolution remains responsible for selecting a binding. */
List Compiler.protocol_member_names(Compiler c, Type participant) {
  Map seen = {};
  Array names = [];
  List protocols = c._ordered_occurrences();
  foreach (Type current, c._ancestry(participant.canonicalize()))
    foreach (List entry, protocols) {
      Type base = entry.car();
      if (!c._is_adopted(base, current)) continue;
      List conformance = c.protocol_members_for(current, base);
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

/** Reports whether conformance supersedes an ambient direct member.
    The answer is cached for the canonical participant and includes the first
    visible adopted ancestor that declares the member.
*/
int Compiler.protocol_rejects_direct_member(
  Compiler c, Type participant, String member) {
  Type owner = participant.canonicalize();
  List cache_key = %("protocol-rejects" $owner $member);
  Var cached;
  if (c.proto_cache.try_get(cache_key, cached)) return cached;
  List protocols = c._ordered_occurrences(), int rejects = 0;
  foreach (Type ancestor, c._ancestry(owner)) {
    List row = c._member_row(protocols, ancestor, member);
    if (row) {
      Symbol status = row.cadr();
      rejects = status == <native> || status == <base-dflt> ||
                status == <no-member> || status == <sig-cnflct>;
      break;
    }
  }
  c.proto_cache[cache_key] = rejects;
  return rejects;
}

static List Compiler._member_row(
  Compiler c, List protocols, Type participant, String member) {
  List found = NULL;
  c._each_adopted_row(
    protocols, participant,
    %!(Compiler &c, Type base, List row) using &found => {
      (void) c; (void) base;
      if (row.car() == member) {
        found = row;
        return 1;
      }
      return 0;
    });
  return found;
}

/* Drive visit(c, base, row) over every member row of participant's
   adopted conformances, in protocols order. A nonzero visit result stops the
   iteration. */
static void Compiler._each_adopted_row(
  Compiler c, List protocols, Type participant, Func visit) {
  foreach (List entry, protocols) {
    Type base_type = entry.car();
    if (!c._is_adopted(base_type, participant)) continue;
    List conformance = c.protocol_members_for(participant, base_type);
    if (!conformance) continue;
    foreach (List row, conformance.last().list().cdr())
      if (visit(c, base_type, row).int()) return;
  }
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
  List protocols = c._ordered_occurrences();
  foreach (Var candidate, names) {
    Type participant = %(${candidate.str()});
    foreach (List entry, protocols) {
      Type base_type = entry.car();
      if (!c._is_adopted(base_type, participant)) continue;
      List conformance = c.protocol_members_for(participant, base_type);
      if (!conformance) continue;
      _dump_row(
        "conformance",
        c._owns_adoption(base_type, participant),
        base_type, participant,
        conformance.last().list().cdr());
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
        _dump_member(member, name, source, punctuation);
      }
  printf(")\n");
}

static void _dump_member(
  String member, const char *status, String source, const char *punctuation) {
  printf(" (%s %s %s %s)", member, status, source ? source : "-", punctuation);
}

// operators

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

static Symbol _operator_row(Symbol op, int derived) {
  int index = operator_ops.index(op);
  if (index < 0 || operator_members[index].derived != derived) return 0;
  return operator_members[index].member;
}

/** Returns the protocol member corresponding to a direct binary operator.
    Returns zero when the operator has no direct protocol mapping.
*/
Symbol Compiler.operator_member(Compiler c, Symbol op) {
  (void) c;
  return _operator_row(op, 0);
}

/** Returns the protocol member that derives a comparison operator.
    Inequality derives from `equal`, ordered comparisons derive from `compare`,
    and unsupported operators return zero.
*/
Symbol Compiler.derived_member(Compiler c, Symbol op) {
  (void) c;
  return _operator_row(op, 1);
}

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
  List resolved = c._resolve_member(participant.canonicalize(), member_name);
  if (!resolved) return NULL;
  String spelling = binding_identity_spelling(resolved.car());
  return spelling == c.fn_name ? NULL : resolved;
}

static List Compiler._resolve_member(
  Compiler c, Type participant, String member_name) {
  List cache_key = %("protocol-member" $participant $member_name);
  return c._proto_cached(
    cache_key, %!(Compiler &c) => {
    List protocols = c._ordered_occurrences();
    List ancestry = c._ancestry(participant);
    /* A generated member is selected before a direct base alias. */
    List selected = c._generated_member(ancestry, member_name);
    if (selected) return selected;
    selected = c._base_alias(protocols, participant, ancestry, member_name);
    return selected ? selected
      : c._adopted_member(protocols, ancestry, member_name);
  });
}

static List Compiler._generated_member(
  Compiler c, List ancestry, String member) {
  foreach (Type current, ancestry) {
    List decision = c._generated_owner(current, member);
    match (decision)
      case %(owner ? ? ?signature ?): {
        String source = _member_spelling(current, member);
        List binding = c.sym.reference(%($source), NULL);
        return %($binding $signature);
      }
  }
  return NULL;
}

static List Compiler._base_alias(
  Compiler c, List protocols, Type participant, List ancestry,
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
    Type signature = c.sym.get(%($source));
    if (!signature || !signature.is_function()) continue;
    List binding = c.sym.reference(%($source), NULL);
    return %($binding $signature);
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

static List Compiler._adopted_member(
  Compiler c, List protocols, List ancestry, String member) {
  foreach (Type current, ancestry) {
    List row = c._member_row(protocols, current, member);
    if (!row) continue;
    match (row)
      case %(? ?(Symbol status) ?(String source) ?(Type signature) ? ?): {
        if (status == <implmntd>) {
          List binding = c.sym.reference(%($source), NULL);
          return %($binding $signature);
        }
        if (status == <native>) {
          String binding_name = _member_spelling(current, member);
          List binding = c.sym.reference(%($binding_name), NULL);
          return %($binding $signature);
        }
      }
    return %();
  }
  return %();
}

/* generated owners

   A base default is generated for a participant by exactly one adopted
   protocol. Two candidates are a collision, reported once per member. */

typedef struct GeneratedOwners {
  Type participant;
  String member;
  Array candidates;
  List result, first_linkage;
  Symbol first_storage;
} GeneratedOwners;

/* Select the sole generated owner across all adopted protocols. */
static List Compiler._generated_owner(
  Compiler c, Type participant, String member_name) {
  List cache_key = %("protocol-generated-owner" $participant $member_name);
  return c._proto_cached(
    cache_key, %!(Compiler &c) => {
    GeneratedOwners owners = {
      .participant = participant, .member = member_name, .candidates = []};
    c._each_adopted_row(
      c._ordered_occurrences(), participant,
      %!(Compiler &c, Type base, List row)
        using &owners => owners.consider(c, base, row));
    return owners.decision();
  });
}

static int GeneratedOwners.consider(
  GeneratedOwners &g, Compiler c, Type base, List row) {
  match (row)
    case %(?(String member) base-dflt ?(String source)
           ?(Type expected) ordinary ?): {
      if (member != g.member) return 0;
      Symbol storage = c._visibility(base, g.participant);
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

static List GeneratedOwners.decision(GeneratedOwners &owners) {
  List rows = owners.candidates.list_free();
  if (owners.result) return owners.result;
  match (rows) {
    case %(?only): return only;
    case %(?first ?second *rest):
      return %(conflict $first $second @rest);
  }
  return NULL;
}

static void Compiler._report_collision(
  Compiler c, Type participant, String member, Symbol kind, List first,
  List second) {
  Type first_base = first.cadr(), second_base = second.cadr();
  Type first_expected = first.cdr().cdr().cdr().car();
  Type second_expected = second.cdr().cdr().cdr().car();
  List dedupe = %("protocol-generated-collision" $participant $member);
  if (dedupe in c.protocol_helpers) return;
  c.protocol_helpers[dedupe] = 1;
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
  List row = c._visible_adoption(first_base, participant);
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

// update helpers

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

static List Compiler._bound_call(
  Compiler c, Type result, List callee, List arguments) {
  Macro shape = $called;
  return c.rebuild_expression(result, shape(callee, arguments));
}

macro open Statement $update_body(Expr $current, Expr $call) {
  $current = $call;
  return $current;
}

macro open Statement $postfix_body(
    Type $type, Name $old, Expr $current, Expr $call) {
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

static void ProtocolUpdate.arguments(ProtocolUpdate &u) {
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

static void ProtocolUpdate.emit(ProtocolUpdate &u) {
  List call = u.c._bound_call(
    u.result, %(expr ${u.source_type} (ident ${u.source_binding})),
    %(${u.current} ${u.call_rhs}));
  Macro ordinary = $update_body, saved = $postfix_body;
  List shape = u.postfix
    ? saved(u.participant, u.old_binding, u.current, call)
    : ordinary(u.current, call);
  List body = u.c.bind_syntax(shape, AST_BLOCK, u.participant);
  List helper = u.c.wrapper_function(
    %(static @{u.participant}), u.helper_binding,
    u.declarations.list_free(), body.cdr());
  u.c.add_early(helper);
}

// discard helpers

macro open Expression $discard_call(
    Name $callee, Name $arguments...) => $callee($arguments...);

macro open Statement $discard_argument(Name $discard, Name $argument) {
  $discard($argument);
}

macro open Statement $discard_void(Expr $call, Statement $discards...) {
  $call;
  $discards...
  return;
}

macro open Statement $discard_value(
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

static void DiscardCall.collect(DiscardCall &d) {
  Macro drop_shape = $discard_argument;
  List parameters = d.signature.car().list().cadr();
  int index = 0;
  foreach (Type parameter, parameters) {
    List argument = d.c.sym.introduce(%"a$index");
    d.declarations.push(parameter.parameter_ast(argument));
    d.arguments.push(argument);
    if (d.which & (1 << index)) {
      List drop = d.c.resolve_protocol_member(parameter, "discard");
      if (drop) d.discards.push(drop_shape(drop.car(), argument));
    }
    index++;
  }
}

static List DiscardCall.emit(DiscardCall &d) {
  String name = %"_x2c_discard_${d.stem}_${d.which}";
  List helper_binding = d.c.sym.introduce(name);
  List value_binding = d.c.sym.introduce("value");
  Macro call_shape = $discard_call;
  List expression = d.c.bind_syntax(
    call_shape(d.binding, d.arguments.list_free()),
    AST_EXPRESSION, d.result);
  Macro void_shape = $discard_void, value_shape = $discard_value;
  List shape = d.result.equal(%(void))
    ? void_shape(expression, d.discards.list_free())
    : value_shape(d.result, value_binding, expression, d.discards.list_free());
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

/* adapter generation

   Resolved conformances become native aliases, ordinary adapters, and
   descriptor thunks. Their external signatures are published first, so
   the unit's own calls bind before the adapters exist. */

/** Generates adapters and descriptor registration for resolved conformances.
    Native aliases are inserted at the participant's inferred public or
    private boundary. Ordinary adapters and descriptor thunks are added to the
    compiler's early output. Returns `ast` with native insertions applied.
*/
List Compiler.generate_protocol_adapters(Compiler c, List ast) {
  /* Emit adapters only for finalized, declared conformances. */
  int central_initializer = c._defines_function("x2c_initialize_protocols");
  Array ordered = [];
  foreach (Var (key, value), c.conforms)
    if (value is <list>) ordered.push(%($key $value));
  ordered.sort();
  foreach (List ordered_row, ordered)
    match (ordered_row)
      case %(? (protocol-conformance ?(Type base) ?(Type participant)
                ?(String forward) ?(String reverse) ?(Map variables)
                ?(Map bindings) (members *rows))): {
        if (_native_rows(rows)) {
          ast = c._native_aliases(ast, base, participant, rows);
          continue;
        }
        if (!c._defines_function(forward)) continue;
        if (c._numeric_participant(participant)) continue;
        c._ordinary_adapters(ordered_row.cadr(), central_initializer);
      }
  ordered.free();
  return ast;
}

/** Publishes external native alias and ordinary adapter signatures.
    Protocols must already be resolved in the active symbol table.
*/
void Compiler.install_generated_protocol_symbols(Compiler c) {
  foreach (Var value, c.conforms)
    match (value)
      case %(protocol-conformance ?(Type base) ?(Type participant)
             ?(String forward) ? ? ? (members *rows)): {
        if (_native_rows(rows)) {
          if (c._visibility(base, participant) != <external>) continue;
          foreach (List row, rows)
            match (row)
              case %(?(String member) ? ? ? ? ?(Type signature)):
                c._install_generated(participant, member, signature);
          continue;
        }
        if (!c.fn_defs.contains(forward)) continue;
        if (c._numeric_participant(participant)) continue;
        foreach (List row, rows)
          match (row)
            case %(?(String member) base-dflt ? ? ordinary ?): {
              List decision = c._generated_owner(participant, member);
              match (decision)
                case %(owner ? ? ?signature external):
                  c._install_generated(participant, member, signature);
            }
      }
}

/* Publish resolved external signatures before their adapters are generated. */
static void Compiler._install_generated(
  Compiler c, Type participant, String member, Type signature) {
  String generated = _member_spelling(participant, member);
  c.sym.define_global(%("generated-protocol" $generated), %(generated));
  c.sym.define_global(%($generated), signature);
}

// Numeric participants other than Symbol keep their native operators.
static int Compiler._numeric_participant(Compiler c, Type participant) =>
  c.sym.resolve_numeric_type(participant) && participant !== %("Symbol");

static int Compiler._defines_function(Compiler c, String name) {
  List binding = c.sym.reference(%($name), NULL);
  Var stored;
  if (!binding ||
      !c.semantic_binding_facts().try_get(%(completion $binding), stored))
    return 0;
  Symbol state = stored.list().car();
  return state == <definition> || state == <completed>;
}

typedef struct AdapterFunction {
  Compiler c;
  String name, source, reverse, binder;
  Type target, signature, template;
  Map variables;
  List binding;
  int make_static;
} AdapterFunction;

static void Compiler._ordinary_adapters(
  Compiler c, List conformance, int central_initializer) {
  match (conformance)
    case %(protocol-conformance ?(Type base) ?(Type participant)
           ?(String forward) ?(String reverse) ?(Map variables)
           ?(Map bindings) (members *rows)):
      match (c._record(base))
        case %(? ? ?(String binder) ? ?): {
          List adoption = c._visible_adoption(base, participant);
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

static void ProtocolAdapters.member(ProtocolAdapters &a, List row) {
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

static void ProtocolAdapters.default_member(
  ProtocolAdapters &a, String member, String source, Type expected,
  Type template) {
  List decision = a.c._generated_owner(a.participant, member);
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
      a.c._report_collision(a.participant, member, kind, first, second);
  }
}

static void ProtocolAdapters.missing_member(
  ProtocolAdapters &a, String member, Type template) {
  if (a.base !== %("Var") || a.shares_var_tag) return;
  List decision = a.c._generated_owner(a.participant, member);
  match (decision) {
    case %(owner ? ? ?owner_expected ?):
      a.inherited_member(member, owner_expected, template);
    case %((!set ?kind (!or linkage conflict)) ?first ?second *):
      a.c._report_collision(a.participant, member, kind, first, second);
  }
}

static void ProtocolAdapters.inherited_member(
  ProtocolAdapters &a, String member, Type expected, Type template) {
  List requirement = a.descriptor_requirement(member, template);
  if (requirement) {
    a.report_requirement(requirement);
    return;
  }
  String inherited = _member_spelling(a.participant, member);
  a.c.add_early(a.c._signature_declaration(inherited, expected, 0));
  if (!a.c.sym.lookup_field(%(struct "VarMethods"), %($member))) return;
  a.thunks.push(a.thunk(member, expected, template, inherited));
}

static void ProtocolAdapters.implemented_member(
  ProtocolAdapters &a, String member, String source, Type expected,
  Type template) {
  if (a.base !== %("Var") || a.shares_var_tag) return;
  if (!a.c.sym.lookup_field(%(struct "VarMethods"), %($member))) return;
  a.thunks.push(a.thunk(member, expected, template, source));
}

static List ProtocolAdapters.thunk(
  ProtocolAdapters &a, String member, Type expected, Type template,
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
    function = a.c._guard_rendering(function, member);
  a.c.add_early(function);
  return %($member ${adapter.binding} $target);
}

static void ProtocolAdapters.register_descriptor(ProtocolAdapters &a) {
  List thunks = a.thunks.list_free();
  if (a.base !== %("Var") || a.shares_var_tag) return;
  Symbol tag = _tag_value(_adoption_tag(a.adoption));
  String name = a.participant.car().str();
  if (!tag) name = name.lower();
  a.c._register_descriptor(
    a.participant, name, tag, thunks, a.central_initializer);
}

// adapter functions

static List AdapterFunction.generate(AdapterFunction &a) {
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
  List call = a.c._bound_call(
    source_result, %(expr ${a.signature} (ident $source_binding)),
    arguments.list_free());
  a.binding = a.c.sym.reference(%(${a.name}), NULL);
  if (a.make_static) a.binding = a.c.sym.introduce(a.name);
  List storage = a.make_static
    ? %(static inline @target_result) : target_result;
  return a.c.wrapper_function(
    storage, a.binding, declarations.list_free(),
    %((return $target_result $call)));
}

macro Decorator $guard_value_rendering(
  Function $function, Name $path, Expr $enter, Expr $fallback,
  Expr $leave, Statement $body...) {
  RenderPath $path;
  if (!$enter) return $fallback;
  defer $leave;
  $body...
}

/* Copied aggregate boxes have an identity only before unboxing. Their direct
   value printer has no stable address to guard, so the descriptor thunk owns
   this boundary. Pointer participants guard their actual recursive writer. */
static List Compiler._guard_rendering(
  Compiler c, List function, String member) {
  match (function)
    case %(function ?result
           (!set ?declarator
             (bind ? ((fnmod (params
               (param ? (bind ?boxed ?)) *remaining)) *)))
           (block *body)): {
      List value = %(expr ("Var") (ident $boxed));
      List fallback = NULL;
      if (member == "str" || member == "repr")
        fallback = c._helper_call(
          %("String"), "Var_pointer_string", %($value));
      else match (remaining)
        case %((param ? (bind ?output ?))):
          fallback = c._helper_call(
            %("Buffer"), "Var_write_pointer_repr",
            %($value (expr ("Buffer") (ident $output))));
      List path = c.sym.introduce("render_path");
      c.semantic_binding_facts()[%(automatic $path)] = 1;
      c.semantic_binding_facts()[%(type $path)] = %("RenderPath");
      Macro addressed = $addressed;
      List address = c.rebuild_expression(
        %(* "RenderPath"),
        addressed(%(expr ("RenderPath") (ident $path))));
      List pointer = c._helper_call(%(* void), "Var_pointer", %($value));
      List enter = c._helper_call(
        %(int), "RenderPath_enter", %($address $pointer));
      List leave = c._helper_call(%(void), "RenderPath_leave", %($address));
      Macro shape = $guard_value_rendering;
      return c.rebuild_function(
        function, shape(path, enter, fallback, leave, body));
    }
  return function;
}

static List Compiler._signature_declaration(
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

// descriptor registration

macro open Unit $methods_table(Name $methods) {
  static VarMethods $methods;
}

macro open Statement $methods_value(Name $methods, Expr $value) {
  $methods = $value;
}

macro open Statement $registration_fallback(Expr $registered, Expr $fallback) {
  if (!$registered) { $fallback; }
}

static void Compiler._register_descriptor(
  Compiler c, Type participant, String name, Symbol explicit_tag,
  List thunks, int central_initializer) {
  Macro methods_shape = $methods_table, assign_shape = $methods_value;
  List methods = c.sym.introduce(c.fresh_name("_x2c_protocol_methods"));
  List fields = _descriptor_fields(thunks);
  List value = %(expr ("VarMethods")
    (cast (decl ("VarMethods") (bindings (bind () ())))
      (expr () (composite (commas @fields)))));
  /* A participant with no thunks still needs its tag registered, and the
     file-scope table is already zero, so skip the assignment rather than
     emit an empty initializer, which C only accepts from C23 on. */
  Symbol tag_symbol = participant.var_tag();
  List early_call = c._builtin_registration(methods, name, tag_symbol);
  List registration = c._fallback_registration(methods, name, early_call);
  List explicit_call = explicit_tag
    ? c._tagged_registration(methods, name, explicit_tag) : NULL;
  Symbol queue = central_initializer ? <protocol> : <early>;
  c.add_early(c.bind_syntax(methods_shape(methods), AST_UNIT, NULL));
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

static List _descriptor_fields(List thunks) {
  Array fields = [];
  foreach (List row, thunks) {
    (String member, List thunk, Type type) = row;
    fields.push(%(dotinit ($member) (expr $type (ident $thunk))));
  }
  return fields.list_free();
}

static List Compiler._builtin_registration(
  Compiler c, List methods, String name, Symbol tag) {
  List symbol = %(expr ("Symbol") (literal ("Symbol") $name $tag));
  List table = %(expr ("VarMethods") (ident $methods));
  return c._helper_call(
    %(int), "x2c_register_builtin_descriptor", %($symbol $table));
}

static List Compiler._tagged_registration(
  Compiler c, List methods, String name, Symbol tag) {
  List symbol = %(expr ("Symbol") (literal ("Symbol") ${tag.str()} $tag));
  List table = %(expr ("VarMethods") (ident $methods));
  return c._helper_call(
    %(void), "x2c_register_tagged_descriptor",
    %($symbol ${_string_literal(name)} $table));
}

static List Compiler._fallback_registration(
  Compiler c, List methods, String name, List early_call) {
  List table = %(expr ("VarMethods") (ident $methods));
  List fallback = c._helper_call(
    %(void), "x2c_register_descriptor", %(${_string_literal(name)} $table));
  Macro shape = $registration_fallback;
  return c.rebuild_statement(shape(early_call, fallback)).cadr();
}

macro open Expression $helper_call(
    Name $callee, Expr $arguments...) => $callee($arguments...);

static List Compiler._helper_call(
  Compiler c, Type result, String callee, List arguments) {
  Macro shape = $helper_call;
  return c.rebuild_expression(result, shape(%($callee), arguments));
}

static List _string_literal(String value) {
  String spelling = %"\"$value\"";
  List chars = %(expr (* char) (literal (* char) $spelling));
  return %(expr ("String") (call "String_new" (args $chars)));
}

// alias insertion

/** Remembers a source typedef's declaration and visibility, which native
    alias insertion reads for its participant. */
void Compiler.record_source_typedef(
  Compiler c, String name, List declaration, int private) {
  c.protocol_helpers[%("source-typedef" $name)] = %($declaration $private);
}

static List Compiler._native_aliases(
  Compiler c, List ast, Type base, Type participant, List rows) {
  Var stored;
  if (!c.protocol_helpers.try_get(
    %("source-typedef" ${participant.car()}), stored)) return ast;
  (List source, int private) = stored;
  int make_static = c._visibility(base, participant) == <static>;
  Array aliases = [];
  foreach (List row, rows)
    match (row)
      case %(?(String member) ? ?(String binding) ? ?
             ?(Type signature)): {
        List alias = c._native_alias(
          participant, member, binding, signature, make_static);
        aliases.push(alias);
      }
  return _insert_at_boundary(
    ast, source, private, aliases.list_free(), make_static);
}

static List Compiler._native_alias(
  Compiler c, Type participant, String member, String source,
  Type signature, int make_static) {
  String target = _member_spelling(participant, member);
  List declaration = c._signature_declaration(target, signature, make_static);
  if (!make_static) c.record_generated_symbol(target, signature);
  List native_binding = c.sym.reference(%($source), NULL);
  return c.finish_foreign_alias(
    declaration, %(expr $signature (ident $native_binding)));
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
    case %(preproc ?text *): return preproc_visibility(text) == 1;
  }
  return 0;
}

// registry lifecycle

/** Rebuilds the per-unit protocol and adoption registries from `symbols`.
    Existing rows, helper decisions, and lookup caches are discarded; a null
    map leaves those registries empty. Conformance reset and resolution belong
    to `resolve_protocols`.
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
        c._install_occurrence(base, record, storage, location);
      }
      case %(adopt *): c._install_stored(value);
    }
  }
}

static void Compiler._install_stored(Compiler c, List value) {
  match (value) {
    case %(adopt ?base ?participant ?storage ?location): {
      AdoptionDraft draft = {
        .c = c, .base = base, .participant = participant,
        .storage = storage, .location = location};
      draft.install();
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
      draft.install();
    }
    case %(adopt ?base ?participant ?storage ?representation ?location): {
      AdoptionDraft draft = {
        .c = c, .base = base, .participant = participant,
        .storage = storage, .representation = representation,
        .location = location};
      draft.install();
    }
  }
}
