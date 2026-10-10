/*  construction.x -- quotation templates and constructed syntax
*/

#pragma once

module List Compiler._quotation(
  Compiler c, Token start, Symbol kind, Map holes, List type) {
  Definition d = {
    .c = c, .start = start, .kind = kind, .anonymous = 1, .local = 1,
    .quotation = 1, .type = type};
  d.naming();
  d.nested = !!c.macro_holes;
  Map enclosing = c.macro_holes;
  $let(c.macro_holes, holes) {
    d.locals = {};
    c.macro_holes[%(locals)] = d.locals;
    if (enclosing != NULL) c.macro_holes[%(enclosing)] = enclosing;
    c.macro_holes[%(quotation)] = 1;
    d.using = [];
    d.announce();
    d.body();
  }
  d.finish();
  List built = d.construction(holes);
  if (built) return built;
  /* Each local supplies one hole, a sequence included, so the quotation
     builds its pending invocation with the values already grouped. */
  List values = %(expr ("List") (nil));
  foreach (List hole, d.parameters.reverse())
    values = c._quoted_cons(
      %(expr () (ident ${_hole_name(hole).str()})), values, start);
  List definition = c.capture_macro_value(d.publish());
  List empty = %(expr ("List") (nil));
  return c._quoted_cons(
    x2c_literal_string("x2c.template"), c._quoted_cons(
      definition, c._quoted_cons(values, empty, start), start), start);
}

/* `head` consed onto the List expression `tail`. */
static List Compiler._quoted_cons(
  Compiler c, List head, List tail, Token origin) {
  List value = c.convert_expression(
    c.resolve_expression(head, origin), %("Var"));
  return %(expr ("List") (cons $value $tail));
}

/* A quotation whose template applies no other template builds its syntax
   where it is written (see "quoted syntax"). Any other quotation, or one
   whose template uses a projection only an expansion makes, returns NULL
   and keeps its definition. */
static List Definition.construction(Definition &d, Map holes) {
  Compiler c = d.c;
  if (d.type) return d.typed_construction(holes);
  if (d.kind == <type> || d.kind == <param>) return d.part_construction();
  if (!d.rebuild || d.nested || d.kind == <decl-unit> || c.runtime_literals)
    return NULL;
  Map keys = {}, file_locals = {};
  _file_scope_locals(%(${d.template}), file_locals);
  Array fresh = [];
  foreach (List row, d.fresh) {
    Var binder = row.car();
    keys[binder] = 1;
    fresh.push(%($binder ${row.cadr()} ${binder in file_locals ? 1 : 0}));
  }
  foreach (List hole, d.parameters)
    foreach (Symbol projection, %(source value expression splice member))
      keys[_hole_key(hole, projection)] = %($hole $projection);
  /* Cached pattern literals retain their values across producer sessions. */
  List quoted = %(
    "x2c.quoted" ${fresh.list_free()}
    ${c.freeze_declaration_syntax(_macro_value_names(d.template))}
  );
  List cells = c._built_cells(quoted, keys, d.start);
  return cells ? %(expr ("List") $cells) : NULL;
}

/* The List cells that build `items`: constant syntax from the literal
   cache, and a hole for each projection `keys` maps. NULL for a binder a
   quotation cannot project where it is written. */
static List Compiler._built_cells(
  Compiler c, List items, Map keys, Token start) {
  if (!items) return %(nil);
  List tail = c._built_cells(items.cdr(), keys, start);
  List head = tail ? c._built_item(items.car(), keys, start) : NULL;
  return head ? c.literal_cell(head, tail) : NULL;
}

/* An Expr hole's expression in an expression position replaces its whole
   shell, which a rebuild leaves out. */
static List Compiler._built_item(
  Compiler c, Var item, Map keys, Token start) {
  Var row;
  if (item.is_binder() && keys.try_get(item, row))
    return row is <list> ? c._built_hole(row, 0, start)
                         : c.cache_literal_var(item);
  if (item.is_binder() && item.str()[1:].startswith("__macro_")) return NULL;
  if (item is not <list> || item.is_nil()) return c.cache_literal_var(item);
  match (item) {
    case %(at m-origin ?node): item = %("x2c.at" $node);
    case %(expr (<macro-expr>) ?binder):
      if (keys.try_get(binder, row) && row is <list>)
        match (row) case %((macro-param ? (kind expr) ?) expression):
          return c._built_hole(row, 1, start);
  }
  List cells = c._built_cells(item, keys, start);
  return cells ? %(expr ("List") $cells) : NULL;
}

/* `("x2c.hole" HOLE PROJECTION VALUE)`, where VALUE is the hole's local
   and HOLE keeps only the hole's kind and cardinality. */
static List Compiler._built_hole(
  Compiler c, List row, int shell, Token start) {
  (List hole, Symbol projection) = row;
  List local = c.convert_expression(
    c.resolve_expression(
      %(expr () (ident ${_hole_name(hole).str()})), start), %("Var"));
  List cells = c.literal_cell(local, %(nil));
  Symbol selected = shell ? <shell> : projection;
  List shape = %(
    macro-param
    (kind ${hole.assoc(<kind>)})
    (sequence ${hole.assoc(<sequence>)})
  );
  foreach (Var constant, %($selected $shape "x2c.hole"))
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

static List Definition.typed_construction(Definition &d, Map holes) {
  Compiler c = d.c;
  Map keys = d.written_keys();
  match (d.rebuild.car()) case %(expr ? *content):
    return c.literal_cell(
      c.cache_literal_var(<expr>),
      c.literal_cell(d.type, c._typed_cells(content, keys, d.start)));
  /* The rebuild template of an expression that is one hole is empty; the
     definition's template names the hole, which `Macro.typed` inserts. */
  List hole = keys[d.template.last()].list().car();
  // Constant interpolation uses the same constructor without a runtime local.
  Var type = c.folded_constant(d.type), constant;
  if (type is <list> &&
      holes.try_get(%(constant ${_hole_name(hole).str()}), constant))
    return c.cache_literal_list(Macro.typed(type, constant));
  List callee = c.resolve_expression(
    %(expr () (ident "Macro_typed")), d.start);
  List value = c._hole_value(hole, d.start);
  return c.resolve_expression(
    %(expr ("List") (call $callee (args ${d.type} $value))), d.start);
}

/* `$!Type{ type-name }` and `$!Param{ parameter }` build their List where
   they are written, as a typed quotation builds its expression. */
static List Definition.part_construction(Definition &d) {
  Map keys = d.written_keys();
  match (d.rebuild.car()) case %(macro-bind ?binder):
    return d.c._typed_hole(keys[binder], d.start);
  return %(expr ("List") ${d.c._typed_cells(d.rebuild.car(), keys, d.start)});
}

/* The hole projections a quotation built where it is written fills. Such a
   quotation binds nothing, so it may declare no name and apply no
   template. */
static Map Definition.written_keys(Definition &d) {
  if (!d.rebuild || d.fresh) $report.parse.typed_quotation(d.c, d.start);
  Map keys = {};
  foreach (List hole, d.parameters)
    foreach (Symbol projection, %(source value expression splice member))
      keys[_hole_key(hole, projection)] = %($hole $projection);
  return keys;
}

/* The List cells that build `items`. A sequence or splice hole
   contributes its items to the List that holds it. */
static List Compiler._typed_cells(
  Compiler c, List items, Map keys, Token start) {
  if (!items) return %(nil);
  List tail = c._typed_cells(items.cdr(), keys, start);
  Var item = items.car(), row;
  if (item is <list> && !item.is_nil())
    return c.literal_cell(
      %(expr ("List") ${c._typed_cells(item, keys, start)}), tail);
  if (!item.is_binder() || !item.str()[1:].startswith("__macro_"))
    return c.literal_cell(c.cache_literal_var(item), tail);
  if (!keys.try_get(item, row)) $report.parse.typed_quotation(c, start);
  (List hole, Symbol projection) = row.list();
  List value = c._typed_hole(row, start);
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
static List Compiler._typed_hole(Compiler c, List row, Token start) {
  (List hole, Symbol projection) = row;
  List local = c._hole_value(hole, start);
  Symbol kind = hole.assoc(<kind>);
  int lifts = kind == <expr>;
  int expression = projection == <expression>;
  if (kind == <type>) return c._checked_type(local, start);
  if (hole.assoc(<sequence>).int())
    return lifts ? c._runtime_call("Macro_inserted_items", %($local), start)
                 : local;
  if (kind == <name> && projection == <value>)
    return c._runtime_call("Macro_declared", %($local), start);
  if (!lifts && !expression && kind != <name>) return local;
  return c._runtime_call(
    "Macro_inserted",
    %($local ${x2c_literal_int(lifts)} ${x2c_literal_int(expression)}), start);
}

module List Compiler._runtime_call(
  Compiler c, String name, List arguments, Token start) {
  List callee = c.resolve_expression(%(expr () (ident $name)), start);
  return c.resolve_expression(
    %(expr () (call $callee (args @arguments))), start);
}

static List Compiler._hole_value(Compiler c, List hole, Token start) =>
  c.resolve_expression(%(expr () (ident ${_hole_name(hole).str()})), start);

