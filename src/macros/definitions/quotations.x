/*  quotations.x -- macro definition quotations */

static const SymbolSet quoted_roles = %<<statement block name param>>;

/* quotations

   `$!( expression )`, `$!{ items }`, and `$!Kind{ ... }` are anonymous
   macros applied where they are written. A `$name` in the body names the
   visible local `name`: its first use declares a hole, and the quotation
   applies to that local's value. An `@name` splices the local's sequence.
   `$(expression)` and `@(expression)` declare hidden locals before building
   the code, for singular and sequence insertion. A typed
   quotation, `$!T{ expression }` or `$!(T){ expression }`, builds its code
   where it is written (see "typed quotations"), and so do
   `$!Type{ type-name }` and `$!Param{ parameter }`. */

/** Parses a quotation at `$!` into the code it builds from the locals its
    body names.
*/
List Compiler.parse_macro_quotation(Compiler c) {
  Token start = c.token;
  c.expect(<$>);
  c.expect(<!>);
  int typed = _typed_quotation(c);
  Symbol kind = typed || c.peek(0) == <(> ? <expression> : <block-item>;
  if (!typed && c.peek(0) == <ident>) {
    kind = _quotation_kind(c, c.token);
    c.next();
  }
  c.sym.push_new_scope();
  defer c.sym.pop_scope();
  Map holes = {};
  List locals = NULL, type = NULL;
  if (typed) {
    if (c.macro_holes && %(quotation) in c.macro_holes)
      $fail.macros_typed_quotation_nested(c, start);
    if (c.macro_holes) $fail.macros_typed_quotation(c, start);
    if (c.peek(0) == <(>) locals = _expression_holes(c, holes);
    type = _quoted_type(c, holes);
  }
  if (!c.macro_holes) locals = locals.append(_expression_holes(c, holes));
  List built = _quotation(c, start, kind, holes, type);
  if (typed && !(%(dynamic) in holes) && c.folded_constant(built) is not void)
    return built;
  return locals
       ? %(expr ("List") (parens (block @locals (stmnt $built))))
       : built;
}

// macro definition quotations

/* The kind a quotation builds: one a result kind names, or a type or one
   parameter, which only a hole kind names. */
static Symbol _quotation_kind(Compiler c, Token token) {
  const MacroCategory *category = _category(token.text);
  if (category && (category.hole == <type> || category.hole == <param>))
    return category.hole;
  return _result_kind_token(c, token);
}

/* Whether the quotation after `$!` states its type: `T{` where the
   identifier `T` names no kind, or a group that a brace follows. A type
   keyword such as `int` is an identifier here. */
static int _typed_quotation(Compiler c) {
  if (c.token.text.is_identifier())
    return c.peek(1) == <"{"> && !_category(c.token.text);
  return c.peek(0) == <(> && c.token.after_group().type == <"{">;
}

/* Declares a hidden local for each `$(expression)` or `@(expression)` in
   the body, in source order, and records its name under the sigil's position.
   A nested quotation's holes are its own, and `case $($name(...))` is
   a macro pattern. */
static List _expression_holes(Compiler c, Map holes) {
  Token saved = c.token, close = c.token.group_close();
  Array locals = [];
  Symbol last = 0;
  for (Token t = Token.skip_trivia(saved + 1); t < close;
       t = Token.skip_trivia(t + 1)) {
    Token group = t + 1, next = Token.skip_trivia(group);
    if (t.type == <$> && next.type == <!>) {
      next = Token.skip_trivia(next + 1);
      if (next.text.is_identifier()) next = Token.skip_trivia(next + 1);
      t = next.group_close();
      Token typed = next.after_group();
      if (next.type == <(> && typed.type == <"{">) t = typed.group_close();
    }
    else if ((t.type == <@> || t.type == <$>) && group.type == <(> &&
             (last != <case> || Token.skip_trivia(group + 1).type != <$>)) {
      c.token = group;
      locals.push(_hole_local(c, holes, t.pos));
      t = group.group_close();
    }
    last = t.type;
  }
  c.token = saved;
  return locals.list_free();
}

/* The declaration of the hidden local that `(expression)` at the cursor
   initializes. The local takes the expression's type, and the quotation
   boxes its value, so an expression without an x2c type reports where it
   is written. */
static List _hole_local(Compiler c, Map holes, int position) {
  c.expect(<(>);
  Token origin = c.token;
  List value = c.parse_expression();
  if (!value.cadr()) $fail.expressions_var_unresolved(c, origin);
  c.expect(<)>);
  String name = c.fresh_name("hole");
  holes[%(expression $position)] = name;
  Var constant = c.folded_constant(value);
  if (constant is void) holes[%(dynamic)] = 1;
  else holes[%(constant $name)] = constant;
  return c.bind_syntax(
    %(declare $(value.cadr())
      (bindings (op = (bind $(c.sym.introduce(name)) ()) $value))),
    <block>, c.return_type);
}

/* The expression that computes a typed quotation's type: the identifier at
   the cursor, or the group there, which holds a type or a `$name` local or
   `$(expression)` hole whose value is the type. */
static List _quoted_type(Compiler c, Map holes) {
  if (c.peek(0) != <(>) return _quoted_type_name(c);
  c.expect(<(>);
  Token origin = c.token;
  List type = NULL;
  if (c.peek(0) == <$>) {
    Var name = c.peek(1) == <(>
             ? holes[%(expression $(c.token.pos))]
             : Token.skip_trivia(c.token + 1).text;
    c.token = c.after_hole();
    type = _checked_type(
      c,
      c.resolve_expression(%(expr () (ident $(name.str()))), origin), origin);
  }
  else type = _quoted_type_name(c);
  c.expect(<)>);
  return type;
}

static List _quoted_type_name(Compiler c) {
  Type parsed = NULL;
  c.parse_type_operand(&parsed);
  return c.cache_literal_list(parsed);
}

static List _quotation(
  Compiler c, Token start, Symbol kind, Map holes, List type) {
  Definition d = {
    .c = c, .start = start, .kind = kind, .anonymous = 1, .local = 1,
    .quotation = 1, .type = type};
  _naming(d);
  d.nested = !!c.macro_holes;
  Map enclosing = c.macro_holes;
  with (c.macro_holes = holes) {
    d.locals = {};
    c.macro_holes[%(locals)] = d.locals;
    if (enclosing != NULL) c.macro_holes[%(enclosing)] = enclosing;
    c.macro_holes[%(quotation)] = 1;
    d.using = [];
    _announce(d);
    _body(d);
  }
  _finish(d);
  List built = _construction(d, holes);
  if (built) return built;
  /* Each local supplies one hole, a sequence included, so the quotation
     builds its pending invocation with the values already grouped. */
  List values = %(expr ("List") (nil));
  foreach (List hole in d.parameters.reverse())
    values = _quoted_cons(
      c, %(expr () (ident $(_hole_name(hole).str()))), values, start);
  List definition = c.capture_macro_value(_publish(d));
  List empty = %(expr ("List") (nil));
  return _quoted_cons(
    c, $!String{ $("x2c.template") }, _quoted_cons(
      c, definition, _quoted_cons(c, values, empty, start), start), start);
}

/* `head` consed onto the List expression `tail`. */
static List _quoted_cons(
  Compiler c, List head, List tail, Token origin) {
  List value = c.convert_expression(
    c.resolve_expression(head, origin), %("Var"));
  return %(expr ("List") (cons $value $tail));
}

/* A quotation whose template applies no other template builds its syntax
   where it is written (see "quoted syntax"). Any other quotation, or one
   whose template uses a projection only an expansion makes, returns NULL
   and keeps its definition. */
static List _construction(Definition &d, Map holes) {
  Compiler c = d.c;
  if (d.type) return _typed_construction(d, holes);
  if (d.kind == <type> || d.kind == <param>) return _part_construction(d);
  if (!d.rebuild || d.nested || d.kind == <decl-unit> || c.runtime_literals)
    return NULL;
  Map keys = {}, file_locals = {};
  _file_scope_locals($(d.template), file_locals);
  Array fresh = [];
  foreach (List row in d.fresh) {
    Var binder = row.car();
    keys[binder] = 1;
    fresh.push($(binder, row.cadr(), binder in file_locals ? 1 : 0));
  }
  foreach (List hole in d.parameters)
    foreach (Symbol projection in %(source value expression splice member))
      keys[_hole_key(hole, projection)] = $(hole, projection);
  /* Cached pattern literals retain their values across producer sessions. */
  List quoted = $(
    "x2c.quoted", fresh.list_free(),
    c.freeze_declaration_syntax(_macro_value_names(d.template)));
  List cells = _built_cells(c, quoted, keys, d.start);
  return cells ? %(expr ("List") $cells) : NULL;
}

/* The List cells that build `items`: constant syntax from the literal
   cache, and a hole for each projection `keys` maps. NULL for a binder a
   quotation cannot project where it is written. */
static List _built_cells(
  Compiler c, List items, Map keys, Token start) {
  if (!items) return %(nil);
  List tail = _built_cells(c, items.cdr(), keys, start);
  List head = tail ? _built_item(c, items.car(), keys, start) : NULL;
  return head ? c.literal_cell(head, tail) : NULL;
}

/* An Expr hole's expression in an expression position replaces its whole
   shell, which a rebuild leaves out. */
static List _built_item(
  Compiler c, Var item, Map keys, Token start) {
  Var row;
  if (item.is_binder() && keys.try_get(item, row))
    return row is <list> ? _built_hole(c, row, 0, start)
                         : c.cache_literal_var(item);
  if (item.is_binder() && item.str()[1:].startswith("__macro_")) return NULL;
  if (item is not <list> || item.is_nil()) return c.cache_literal_var(item);
  match (item) {
    case %(at m-origin ?node): item = $("x2c.at", node);
    case %(expr (<macro-expr>) ?binder):
      /* The List pattern itself rejects other value tags. */
      if (keys.try_get(binder, row) &&
          row ~= %((macro-param ? (kind expr) ?) expression))
        return _built_hole(c, row, 1, start);
  }
  List cells = _built_cells(c, item, keys, start);
  return cells ? %(expr ("List") $cells) : NULL;
}

/* `("x2c.hole" HOLE PROJECTION VALUE)`, where VALUE is the hole's local
   and HOLE keeps only the hole's kind and cardinality. */
static List _built_hole(
  Compiler c, List row, int shell, Token start) {
  (List hole, Symbol projection) = row;
  List local = c.convert_expression(
    c.resolve_expression(
      %(expr () (ident $(_hole_name(hole).str()))), start), %("Var"));
  List cells = c.literal_cell(local, %(nil));
  Symbol selected = shell ? <shell> : projection;
  List shape = %(
    macro-param
    (kind $(hole.assoc(<kind>)))
    (sequence $(hole.assoc(<sequence>)))
  );
  foreach (Var constant in %($selected $shape "x2c.hole"))
    cells = c.literal_cell(c.cache_literal_var(constant), cells);
  return %(expr ("List") $cells);
}

/* typed quotations

   `$!T{ expression }`, where `T` names no kind, and
   `$!(T){ expression }` build `(expr T CONTENT)` where they are written,
   from the template a rebuild fills: constant syntax from the literal
   cache, and each hole's value inserted as a rebuild inserts it. A typed
   quotation binds nothing, so it may declare no name and apply no
   template. */

static List _typed_construction(Definition &d, Map holes) {
  Compiler c = d.c;
  Map keys = _written_keys(d);
  match (d.rebuild.car()) case %(expr ? *content):
    return c.literal_cell(
      c.cache_literal_var(<expr>),
      c.literal_cell(d.type, _typed_cells(c, content, keys, d.start)));
  /* The rebuild template of an expression that is one hole is empty; the
     definition's template names the hole, which `Macro.typed` inserts. */
  List hole = keys[d.template.last()].list().car();
  // Constant interpolation uses the same constructor without a runtime local.
  Var type = c.folded_constant(d.type), constant;
  if (type is <list> &&
      holes.try_get(%(constant $(_hole_name(hole).str())), constant))
    return c.cache_literal_list(Macro.typed(type, constant));
  List callee = c.resolve_expression(
    %(expr () (ident "Macro_typed")), d.start);
  List value = _hole_value(c, hole, d.start);
  return c.resolve_expression(
    %(expr ("List") (call $callee (args $(d.type) $value))), d.start);
}

/* `$!Type{ type-name }` and `$!Param{ parameter }` build their List where
   they are written, as a typed quotation builds its expression. */
static List _part_construction(Definition &d) {
  Map keys = _written_keys(d);
  if (d.rebuild.car() ~= %(macro-bind ?binder))
    return _typed_hole(d.c, keys[binder], d.start);
  return %(expr ("List") $(_typed_cells(d.c, d.rebuild.car(), keys, d.start)));
}

/* The hole projections a quotation built where it is written fills. Such a
   quotation binds nothing, so it may declare no name and apply no
   template. */
static Map _written_keys(Definition &d) {
  if (!d.rebuild || d.fresh) $fail.macros_typed_quotation(d.c, d.start);
  Map keys = {};
  foreach (List hole in d.parameters)
    foreach (Symbol projection in %(source value expression splice member))
      keys[_hole_key(hole, projection)] = $(hole, projection);
  return keys;
}

/* The List cells that build `items`. A sequence or splice hole
   contributes its items to the List that holds it. */
static List _typed_cells(
  Compiler c, List items, Map keys, Token start) {
  if (!items) return %(nil);
  List tail = _typed_cells(c, items.cdr(), keys, start);
  Var item = items.car(), row;
  if (item is <list> && !item.is_nil())
    return c.literal_cell(
      %(expr ("List") $(_typed_cells(c, item, keys, start))), tail);
  if (!item.is_binder() || !item.str()[1:].startswith("__macro_"))
    return c.literal_cell(c.cache_literal_var(item), tail);
  if (!keys.try_get(item, row)) $fail.macros_typed_quotation(c, start);
  (List hole, Symbol projection) = row.list();
  List value = _typed_hole(c, row, start);
  if (projection == <splice> || hole.assoc(<sequence>).int())
    value = %(splice $value);
  return c.literal_cell(value, tail);
}

/* One use of a hole: its local, which `Macro.inserted` lifts in an
   expression hole, makes an identifier where code takes an expression, and
   makes a spelling in a Name hole's member position. A Name hole that
   declares inserts the name `Macro.declared` makes. An expression sequence
   lifts each item as `Macro.inserted_items` does. A type inserts its
   syntax once it is checked, and other syntax inserts as it is. */
static List _typed_hole(Compiler c, List row, Token start) {
  (List hole, Symbol projection) = row;
  List local = _hole_value(c, hole, start);
  Symbol kind = hole.assoc(<kind>);
  int lifts = kind == <expr>;
  int expression = projection == <expression>;
  if (kind == <type>) return _checked_type(c, local, start);
  if (hole.assoc(<sequence>).int())
    return lifts ? _runtime_call(c, "Macro_inserted_items", $(local), start)
                 : local;
  if (kind == <name> && projection == <value>)
    return _runtime_call(c, "Macro_declared", $(local), start);
  if (!lifts && !expression && kind != <name>) return local;
  return _runtime_call(
    c, "Macro_inserted",
    $(local, $!int{ $lifts }, $!int{ $expression }), start);
}

/* The `Type` expression `type`, which a `meta` function checks names its
   type with a String before a typed quotation inserts it:
   `type_name_error(type) ? (x2c_diagnostic_fail(...), type) : type`. */
static List _checked_type(Compiler c, List type, Token origin) {
  if (!c.meta_body) return type;
  List error = _runtime_call(c, "type_name_error", $(type), origin);
  List fail = _runtime_call(
    c, "x2c_diagnostic_fail", %($error (expr ("List") (nil))), origin);
  return c.resolve_expression(
    %(expr () (op ? $error
      (expr ("Type") (commas $fail $type)) $type)),
    origin);
}

static List _runtime_call(
  Compiler c, String name, List arguments, Token start) {
  List callee = c.resolve_expression(%(expr () (ident $name)), start);
  return c.resolve_expression(
    %(expr () (call $callee (args @arguments))), start);
}

static List _hole_value(Compiler c, List hole, Token start) =>
  c.resolve_expression(%(expr () (ident $(_hole_name(hole).str()))), start);

/* Returns NULL if the quotation registered no expression at this offset. */
module List _expression_hole(Compiler c, Token prefix) {
  Var name;
  if (!c.macro_holes ||
      !c.macro_holes.try_get(%(expression $(prefix.pos)), name))
    return NULL;
  List hole = _hole_record(c, Atom.intern(name));
  return hole ? hole : _quoted_hole(c, name, prefix);
}

/* A quotation's hole takes its kind from a name position, or from a
   parameter or statement position where it stands alone, which no
   annotation can give it. A hole that a declarator follows is a parameter's
   type, and one that an operator, `;`, or a postfix form follows is an
   expression. */
module int _quoted_role(Compiler c, Symbol role) {
  if (!(%(quotation) in c.macro_holes) || !(role in quoted_roles)) return 0;
  if (role == <name>) return 1;
  Token after = c.after_hole();
  if (role == <param>)
    return after.type == <,> || after.type == <)> || after.type == <"}">;
  return after.type != <;> && !_extends_expression(after);
}

/* A `$name` or `@name` in a quotation's body that names a visible local
   declares a singular or sequence hole. A local declared `Type` fills a type
   hole, which no position can tell from a statement before a name. */
module List _quoted_hole(
  Compiler c, String spelling, Token prefix) {
  if (!c.macro_holes || !(%(quotation) in c.macro_holes)) return NULL;
  Type type = NULL;
  List local = c.sym.lookup($(spelling), type);
  if (!local || !c.sym.binding_is_local(local)) return NULL;
  Symbol kind = c.sym.is_named_value_type(type, "Type") ? <type> : 0;
  int sequence = prefix.type == <@> || prefix.type == <"@(">;
  List hole = _record_hole(c, spelling, kind, sequence);
  Var quoted = c.macro_holes[%(quoted)];
  c.macro_holes[%(quoted)] =
    cons(hole, quoted is <list> ? quoted.list() : NULL);
  return hole;
}

/* A quotation's holes in the order its body first names them. */
module List _quoted_holes(Compiler c) {
  Var quoted = c.macro_holes[%(quoted)];
  return quoted is <list> ? quoted.list().reverse() : NULL;
}
