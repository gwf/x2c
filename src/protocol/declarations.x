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
