/*  slots.x -- macro definition slots */

/* template holes

   A named hole, Lisp slot, or computed call fills a syntax role. `$` inserts
   one value and `@` splices a sequence. The first role an untyped hole fills
   gives it its kind. */

/** Parses a macro hole or Lisp slot for `role` while reading a template.
    Returns role-shaped syntax containing `(macro-bind ...)` or
    `(macro-slot ...)`, or NULL when ordinary grammar owns the current tokens;
    successful parsing advances the cursor.
*/
List Compiler.try_parse_macro_slot(Compiler c, Symbol role) {
  if (!c.macro_holes) return NULL;
  if (c.peek(0) == <@> && !c.peek_macro_hole())
    return _meta_call_slot(c, role);
  String name;
  if (role != <expression> && role != <statement> &&
      c.peek(0) == <$> && _scan_name(c, name).type == <(> &&
      !c.peek_macro_hole() && !_peek_invocation(c, _slot_position(role)))
    return _meta_call_slot(c, role);
  if (c.peek(0) == <"$("> || c.peek(0) == <"@(">)
    return _lisp_slot(c, role);
  return _hole_slot(c, role);
}

/* The callable supplies syntax in the requested insertion position. */
static List _meta_call_slot(Compiler c, Symbol role) {
  int sequence = c.peek(0) == <@>;
  if (sequence && !(role in sequence_roles))
    $fail.macros_splice_position(c, c.token);
  if (!sequence && (role == <block> || role in declaration_roles))
    return NULL;
  List definition = _peek_invocation(c, _slot_position(role));
  if (sequence && definition && _result_kind(definition) != <expression>)
    return _target_at(c, _slot_position(role), 1);
  List call = c.try_parse_macro_expression();
  return %(macro-slot $sequence $call);
}

/* A result macro keeps the ordinary position's kind and decorator rules. */
static Symbol _slot_position(Symbol role) =>
  role in %<<unit block field enumerator map-entry>> ? role : <expression>;

/* A Lisp slot fills a declaration slot only when @ splices it. A block
   item that continues into a declaration, and a statement, keep the
   ordinary grammar. */
static List _lisp_slot(Compiler c, Symbol role) {
  int splice = c.peek(0) == <"@(">;
  if (splice && !(role in sequence_roles))
    $fail.macros_splice_position(c, c.token);
  if (role in declaration_roles && !splice) return NULL;
  if (!splice && role == <block> && c.macro_lisp_starts_declaration())
    return NULL;
  if (role == <statement>) return NULL;
  if (role == <expression>) return c.parse_macro_lisp_expression();
  return _parse_lisp_slot(c, role);
}

/* A hole fills a slot whose role its kind accepts. A sequence hole of no
   kind takes the slot's kind. */
static List _hole_slot(Compiler c, Symbol role) {
  List hole = c.peek_macro_hole();
  if (!hole ||
      (role == <argument> && !hole.assoc(<sequence>).int()) ||
      (role == <statement> && c.after_hole().type == <(>)) return NULL;
  if (role == <expression> && hole.assoc(<sequence>).int())
    $fail.macros_splice_expr(c, c.token);
  if (!(role in untyped_roles)) {
    Symbol kind = hole.assoc(<kind>);
    if (!kind && c.peek(0) != <@> && c.peek(0) != <"@{"> &&
        !_quoted_role(c, role))
      return NULL;
    if (kind && !_kind_accepts_role(kind, role)) return NULL;
  }
  List syntax = _parse_hole(c, role);
  return syntax && role == <expression>
       ? %(expr (<macro-expr>) $syntax) : syntax;
}

static const SymbolSet declaration_roles =
  %<<field enumerator map-entry unit>>;

static const SymbolSet sequence_roles =
  %<<argument block field enumerator map-entry param unit catch match-row
     decl-row>>;

static const SymbolSet untyped_roles = %<<expression argument type>>;

/** Returns the registered hole descriptor for a named or expression hole.
    `$NAME` and `${expression}` insert one value; `@NAME` and `@{expression}`
    splice a sequence. Returns NULL without consuming a non-hole spelling.
*/
List Compiler.peek_macro_hole(Compiler c) {
  Symbol prefix = c.peek(0);
  if (prefix == <"@{">) return _expression_hole(c, c.token);
  if (prefix != <$> && prefix != <@>) return NULL;
  if (c.peek(1) == <"{">) return _expression_hole(c, c.token);
  if (c.peek(1) != <ident>) return NULL;
  Token name = Token.skip_trivia(c.token + 1);
  List hole = _hole_record(c, Atom.intern(name.text));
  return hole ? hole : _quoted_hole(c, name.text, c.token);
}

/** Returns the token after the named or expression hole at the cursor.
    Consumes neither its `$` or `@` prefix nor its optional braces.
*/
Token Compiler.after_hole(Compiler c) {
  if (c.peek(0) == <"@{">) return c.token.after_group();
  Token next = Token.skip_trivia(c.token + 1);
  return next.type == <"{"> ? next.after_group()
                           : Token.skip_trivia(next + 1);
}

/* Consumes a hole filling `role` and returns its projection. */
module List _parse_hole(Compiler c, Symbol role) {
  Token token = c.token;
  List hole = c.peek_macro_hole();
  if (!hole) _unbound(c, _hole_name_token(c, token.type).text, token);
  c.token = c.after_hole();
  Atom name = _hole_name(hole);
  int sequence = token.type == <@> ||
                 token.type == <"@{">;
  if (sequence != hole.assoc(<sequence>).int())
    _cardinality_error(c, name.str(), sequence, token);
  if (sequence && !(role in sequence_roles))
    $fail.macros_splice_position(c, c.token);
  Symbol inferred = _role_kind(role), kind = hole.assoc(<kind>);
  if (!kind) {
    hole = hole.search_replace(%(kind ?prior), %(kind $inferred));
    c.macro_holes[name] = hole;
  }
  else if (!_kind_accepts_role(kind, role)) {
    String spelling = name.str();
    $fail.macros_hole_ambiguous(
      c, token, spelling, _kind_spelling(kind), _kind_spelling(inferred));
  }
  String projection = _hole_projection(c, hole, role, sequence);
  return %(macro-bind ${_hole_key(hole, projection)});
}

static void _cardinality_error(
  Compiler c, String spelling, int sequence, Token token) {
  $fail.macros_hole_cardinality(c, token, sequence, spelling);
}

static Symbol _role_kind(Symbol role) {
  if (role == <expression> || role == <argument>) return <expr>;
  return role == <statement> ? <block> : role;
}

/* A decorator's Unit target projects its source; a sequence, a type, or
   a captures list projects its splice; other holes project their
   expression or value. */
static String _hole_projection(
  Compiler c, List hole, Symbol role, int sequence) {
  Var binder = hole.assoc(<binder>);
  if (%(source $binder) in c.macro_holes) return "source";
  if (sequence || role == <type> || role == <captures>) return "splice";
  return role in %(expression argument expr) ? "expression" : "value";
}

static const SymbolSet value_kinds = %<<expr name literal>>;

static int _kind_accepts_role(Symbol kind, Symbol role) {
  Symbol expected = role == <statement> ? <block> : role;
  if (expected == <expression> || expected == <argument>)
    return kind in value_kinds;
  return kind == expected ||
    (expected == <field> && kind == <decl>) ||
    (expected == <block> && kind == <decl>) ||
    (expected == <unit> &&
     (kind == <decl> || kind == <function> || kind == <named-type>));
}

/** Returns whether tokens after a Lisp form or explicit meta call continue
    a declaration. The balanced argument group is inspected without moving
    the compiler cursor; a visible source macro retains its own grammar.
*/
int Compiler.macro_lisp_starts_declaration(Compiler c) {
  Token opening = c.token;
  if (opening.type == <$>) {
    if (_peek_invocation(c, <expression>)) return 0;
    String name;
    opening = _scan_name(c, name);
    if (opening.type != <(>) return 0;
  }
  Token token = opening.after_group();
  return token.type == <$> || token.type == <ident> ||
         token.type == <*> || token.type == <(>;
}

/** Parses a member name in a template. A singular `Name` hole there
    supplies the spelling it captured, without hygienic renaming.
*/
List Compiler.try_parse_macro_member(Compiler c) {
  List hole = c.peek_macro_hole();
  List slot = c.try_parse_macro_slot(<name>);
  // A quotation's first use of a hole gives the hole its kind.
  if (hole) hole = _hole_record(c, _hole_name(hole));
  if (!slot || !hole || hole.assoc(<kind>) != <name> ||
      hole.assoc(<sequence>).int())
    return slot;
  return %(macro-bind ${_hole_key(hole, "member")});
}

/* A Lisp slot carries its form and the construction binders its Unit holes
   need. A slot inside a Unit decorator also carries the target's. */
static List _parse_lisp_slot(Compiler c, Symbol role) {
  int sequence = c.peek(0) == <"@(">;
  String form = _lisp_form(c);
  Var target = c.macro_holes[%(target)];
  List construction = _lisp_construction(c, form);
  if (target is <list>) {
    Var required = _hole_key(target, "construction");
    if (role == <name>)
      construction = construction.append(%((target $required)));
    else if (role == <unit>) construction = construction.append(%($required));
  }
  return %(
    macro-slot $sequence $form
    @construction
  );
}

/* The construction binder of each Unit hole the form names, once each. */
static List _lisp_construction(Compiler c, String form) {
  Tokenizer tokenizer = Tokenizer.new(form, <macro-lisp>);
  tokenizer.scan();
  Array construction = [];
  Map seen = {};
  Token token = tokenizer.next();
  while (token && token.type != <eof>) {
    if (token.type == <$>) {
      Token name = tokenizer.next();
      if (name && name.type == <ident>)
        _unit_construction(c, name, construction, seen);
      token = name;
    }
    token = tokenizer.next();
  }
  return construction.list_free();
}

static void _unit_construction(
  Compiler c, Token name, Array construction, Map seen) {
  List hole = _hole_record(c, Atom.intern(name.text));
  if (!hole || hole.assoc(<kind>) != <unit>) return;
  Var binder = _hole_key(hole, "construction");
  if (binder in seen) return;
  seen[binder] = 1;
  construction.push(binder);
}
