/*  definitions.x -- macro definitions, holes, and compile-time effects
*/

#pragma once

/* macro definitions

   Reading a definition takes its result kind, name, signature holes, and
   body. Its signature is visible before the body is read, so the body can
   invoke the macro it defines. */

/** Parses the macro definition at the current token into a `macrodef` `List`.
    A source-level definition is published immediately; a definition inside a
    template remains syntax for later binding at its expansion site.
*/
List Compiler.parse_macro_definition(Compiler c) {
  Definition d = {.c = c, .start = c.token};
  d.storage = c.test(<static>) || c.source_private;
  c.expect(<ident>);
  d.head();
  d.naming();
  d.nested = !!c.macro_holes;
  Map enclosing = c.macro_holes;
  // A rejected signature must not leave later declarations as templates.
  $let(c.macro_holes, {}) {
    d.locals = {};
    c.macro_holes[%(locals)] = d.locals;
    if (enclosing != NULL) c.macro_holes[%(enclosing)] = enclosing;
    d.using = [];
    d.signature();
    d.arrow();
    d.announce();
    d.body();
  }
  d.finish();
  return d.publish();
}

/* Signature collection retains invocation categories and alias targets locally.
   The temporary signature cache owns these descriptors; no body is bound. */
void Compiler.collect_signature_macro_definition(Compiler c) {
  Definition d = {.c = c, .start = c.token};
  d.storage = c.test(<static>) || c.source_private;
  c.expect(<ident>);
  d.head();
  d.naming();
  $let(c.macro_holes, {}) {
    d.locals = {};
    c.macro_holes[%(locals)] = d.locals;
    d.using = [];
    d.signature();
    d.arrow();
    d.announce();
  }
  (void) d.publish();
  if (c.peek(0) == <"{"> || c._legacy_expression_body()) {
    c.token = c.token.after_group();
    return;
  }
  c._skip_shallow_expression(0);
  c.expect(<;>);
}

/* Reads the result kind. A local definition names itself without `$`, and
   an anonymous one has no name to read. */
static void Definition.head(Definition &d) {
  Compiler c = d.c;
  if (c.peek(0) == <$>)
    $report.parse.macro_result(c);
  d.anonymous = c.peek(0) == <ident> && c.peek(1) == <(>;
  d.local = d.anonymous || (c.peek(0) == <ident> &&
            c.peek(1) == <ident> && c.peek(2) == <(>);
  if (c.peek(0) != <ident> || (!d.local && c.peek(1) != <$>))
    $report.parse.macro_kind(c);
  Token token = c.token;
  c.next();
  d.kind = c._result_kind_token(token);
}

module Symbol Compiler._result_kind_token(Compiler c, Token token) {
  const MacroCategory *category = _category(token.text);
  if (!category || !category.result)
    $report.parse.macro_unknown_kind(c, token.text, token);
  return category.result;
}

module void Definition.naming(Definition &d) {
  Compiler c = d.c;
  if (d.anonymous) d.name = Atom.intern(c.fresh_name("anonymous_macro"));
  else if (d.local) {
    d.name = Atom.intern(c.token.text);
    c.next();
  }
  else d.name = c._name();
  String spelling = d.name.str();
  if (d.local && d.name == <with>)
    $report.macro.name_with(c, d.start);
  if (spelling.startswith("x2c.") && !c.builtin_defs)
    $report.parse.macro_reserved(c, spelling, d.start);
}

/* Reads the parameter holes, then a `using` clause. A decorator's first
   parameter is its target. */
static void Definition.signature(Definition &d) {
  Compiler c = d.c;
  Array params = [];
  c.expect(<(>);
  if (!c.test(<)>)) {
    do d.parameter(params, c._signature_hole()); while (c.test(<,>));
    c.expect(<)>);
  }
  d.parameters = params.list_free();
  d.check_signature();
  if (c.take_word("using")) c._using_clause(d.using);
  if (c.peek(0) == <:>)
    $report.parse.macro_kind_order(c);
}

static void Definition.parameter(Definition &d, Array params, List hole) {
  Compiler c = d.c;
  if (d.kind == <decorator> && !d.target) d.take_target(hole);
  else params.push(hole);
  if (hole.assoc(<sequence>).int() && c.peek(0) == <,>)
    $report.parse.hole_final(c);
}

/* A Unit target's source stays visible to compile-time Lisp, whose
   template slots find the target hole under `(target)`. */
static void Definition.take_target(Definition &d, List hole) {
  Compiler c = d.c;
  if (!_decorator_target(hole.assoc(<kind>)))
    $report.parse.decorator_kind(c, d.start);
  if (hole.assoc(<sequence>).int())
    $report.parse.decorator_singular(c, d.start);
  d.target = hole;
  if (hole.assoc(<kind>) != <unit>) return;
  c.macro_holes[%(source ${hole.assoc(<binder>)})] = 1;
  c.macro_holes[%(target)] = hole;
}

/* A local macro produces no file-scope syntax, directly or through the
   target it decorates. */
static void Definition.check_signature(Definition &d) {
  Compiler c = d.c;
  if (d.kind == <decorator> && !d.target)
    $report.parse.decorator_target(c, d.start);
  if (!d.local) return;
  if (d.kind == <unit> || d.kind == <decl-unit>) {
    String result_spelling = _kind_spelling(d.kind);
    $report.macro.local_result(c, result_spelling, d.start);
  }
  if (d.kind != <decorator>) return;
  Symbol kind = d.target_kind();
  if (kind == <function> || kind == <unit> || kind == <named-type>) {
    String target = _kind_spelling(kind);
    $report.macro.local_target(c, target, d.start);
  }
}

/* An Expression result, or a decorator of an expression, has an `=>`
   body. A Stmt result has a braced body or an `=>` expression statement.
   Every other result has a braced body after an optional `=>`. */
static void Definition.arrow(Definition &d) {
  Compiler c = d.c;
  if (d.has_expression_body()) {
    if (c.peek(0) == <"{">) d.body_error();
    c.expect(<=>);
    c.expect(<">">);
    return;
  }
  if (c.peek(0) == <=>) {
    c.expect(<=>);
    c.expect(<">">);
    if (d.kind == <block-item>) return;
  }
  if (c.peek(0) == <(>)
    $report.parse.macro_paren_body(c);
  if (c.peek(0) != <"{">) d.body_error();
}

static int Definition.has_expression_body(Definition &d) =>
  d.kind == <expression> ||
  (d.kind == <decorator> && d.target_kind() == <expr>);

static Symbol Definition.target_kind(Definition &d) {
  if (!d.target) return 0;
  return d.target.assoc(<kind>);
}

/* Reports the body forms the result kind accepts. */
static void Definition.body_error(Definition &d) {
  String form = d.has_expression_body() ? "'=> expression;'"
              : d.kind == <block-item> ? "'{ ... }' or '=> expression;'"
              : "'{ ... }'";
  $report.parse.macro_body(d.c, _kind_spelling(d.kind), form);
}

/* Records where the definition stands and shows its signature, so an
   invocation inside the body names this macro. */
module void Definition.announce(Definition &d) {
  Compiler c = d.c;
  (void) c.record_origin(d.start);
  d.origin = c.token_location(d.start);
  d.file = home_portable_path(c.source_path(c.filename));
  d.show(d.node());
}

/* Reads the body in its own scope, with the kinds it infers for the holes.
   A local macro records the outer names its body captures. A `return` in
   the body is typed where the expansion lands, as at file scope; a
   retained rebuild keeps the type a `return` records. Collection reads the
   whole template, initializers included, as the full parse does. */
module void Definition.body(Definition &d) {
  Compiler c = d.c;
  $let(c.shallow, 0)
  $let(c.return_type, NULL)
  $let(c.runtime_literals, c.runtime_literals || d.anonymous)
  $let(c.local_macro_captures, d.local ? {} : NULL)
  $let(c.local_macro_capture_scopes, c.sym.scope_count()) {
    c.sym.push_new_scope();
    defer c.sym.pop_scope();
    d.template = d.read_body();
    if (d.quotation) d.parameters = _quoted_holes(c);
    d.parameters = c._parameter_rows(d.parameters);
    d.captures = _recorded(c.local_macro_captures);
  }
}

/* A Stmt result's body after `=>` is one arrow statement. */
static List Definition.read_body(Definition &d) {
  Compiler c = d.c;
  if (d.kind == <type> || d.kind == <param>) return d.part_body();
  if (d.has_expression_body()) return d.expression_body();
  if (c.peek(0) == <"{">) return c._parse_body(d.body_kind(), d.using);
  return c._arrow_statement(d.anonymous);
}

/* A Stmt arrow's statement is a Stmt macro or decorator invocation, or else
   an expression statement. An anonymous macro's statement omits its `;`,
   which ends the enclosing declaration, and so does a decorator's target
   there. */
module List Compiler._arrow_statement(Compiler c, int open) {
  List macro = c._target_at(AST_STATEMENT, open);
  if (macro) return macro;
  List expression = c.parse_expression();
  if (!open) c.expect(<;>);
  return %(seq (stmnt $expression));
}

/* The legacy form is parenthesized, and a quotation's body is a
   parenthesized or braced group. The canonical form ends at `;`, which an
   anonymous macro omits. */
static List Definition.expression_body(Definition &d) {
  Compiler c = d.c;
  if (d.quotation || c._legacy_expression_body()) {
    int braced = d.quotation && c.peek(0) == <"{">;
    c.expect(braced ? <"{"> : <(>);
    List replacement = c.parse_expression();
    c.expect(braced ? <"}"> : <)>);
    return replacement;
  }
  List replacement = c.parse_expression();
  if (!d.anonymous) c.expect(<;>);
  return replacement;
}

/* A Type quotation's body is a type name, and a Param quotation's body is
   one parameter. */
static List Definition.part_body(Definition &d) {
  Compiler c = d.c;
  c.expect(<"{">);
  List body = NULL;
  if (d.kind == <param>) {
    body = c.try_parse_macro_slot(<param>);
    if (!body) body = c.parse_parameter();
  }
  else c.parse_type_operand(&body);
  c.expect(<"}">);
  return body;
}

/* A decorator's body produces what its target is, and a Function or
   Block target's body is block items. */
static Symbol Definition.body_kind(Definition &d) {
  if (d.kind != <decorator>) return d.kind;
  Symbol target = d.target_kind();
  return target == <function> || target == <block> ? <block-item> : target;
}

/* The entries a map lists under `<order>`, oldest first, or NULL. */
static List _recorded(Map m) {
  Var order = m != NULL ? m[<order>] : void;
  return order is <list> ? order.list().reverse() : NULL;
}

/* definition templates

   Finishing a definition turns its body into the stored template, derives
   the rows an invocation needs, and makes the `macrodef` visible. */

/* Turns the body into the stored template, then derives the fresh rows
   and pattern an invocation needs. Parsed literal names carry
   definition-only identities, so the template stores binders instead and
   each expansion allocates one fresh identity per literal spelling. */
module void Definition.finish(Definition &d) {
  d.template = _slot_binders(d.wrap());
  Map bindings = {};
  if (d.target_kind() == <unit>) d.constructed_names(bindings);
  Array locals = d.local_binders(bindings);
  d.template = _replace_bindings(d.template, bindings);
  d.check_kinds();
  d.fresh = d.fresh_rows(locals);
  d.pattern = d.invocation_pattern();
  Map uses = _binder_uses(d.template);
  if (!(void *) uses) return;
  d.rebuild = %(${d.rebuild_template()} ${d.rebuild_keys(uses)});
  d.leaf = !d.nested && d.uses_holes_once(uses);
}

/* A Function decorator's body becomes a function with the target's return
   type and declarator, and an Expression decorator's body a parenthesized
   expression. */
static List Definition.wrap(Definition &d) {
  List replacement = d.template;
  if (d.kind != <decorator>) return replacement;
  Symbol target = d.target_kind();
  if (target == <expr>) return %(expr (<macro-expr>) (parens $replacement));
  if (target != <function>) return replacement;
  Var return_binder = _hole_key(d.target, "return");
  Var declarator_binder = _hole_key(d.target, "declarator");
  match (replacement)
    case %(seq *body):
      return %(
        seq
          (function $return_binder $declarator_binder (block @body))
      );
  return replacement;
}

/* Each nested `(macro-bind BINDER)` slot becomes its binder. A whole slot
   keeps a List shell: `expr` for an expression, `macro-bind` otherwise. */
static List _slot_binders(List replacement) {
  match (replacement) case %(macro-bind ?): return replacement;
  List bindings;
  Var expression_slot = %(
    expr (<macro-expr>) (macro-bind ?binder)
  );
  if (replacement.try_match(expression_slot, bindings))
    return replacement.search_replace(%(macro-bind ?binder), <?binder>);
  return replacement.search_replace(
    %(!or
      (expr (<macro-expr>) (macro-bind ?binder))
      (macro-bind ?binder)),
    <?binder>
  );
}

/* A Unit target requires construction, which each Name hole's value
   carries. */
static void Definition.constructed_names(Definition &d, Map bindings) {
  Var required = _hole_key(d.target, "construction");
  foreach (List parameter, d.parameters)
    if (parameter.assoc(<kind>) == <name>) {
      Var name = Macro.binder(parameter.assoc(<binder>), "value", 0);
      bindings[name] = %($required $name);
    }
}

/* Binds each template local to its binder and returns the locals that get
   fresh names. A tag the template only references keeps its public
   spelling. */
static Array Definition.local_binders(Definition &d, Map bindings) {
  Array fresh = [];
  foreach (Var identity, _recorded(d.locals)) {
    if (%(provisional $identity) in d.locals) {
      bindings[identity] = d.locals[identity];
      continue;
    }
    bindings[identity] = _local_binder(
      identity, %(tag-local $identity) in d.locals);
    fresh.push(identity);
  }
  return fresh;
}

static void Definition.check_kinds(Definition &d) {
  foreach (List hole, d.parameters)
    if (!hole.assoc(<kind>)) {
      String hole_spelling = hole.assoc(<binder>).str()[1:];
      $report.parse.hole_untyped(d.c, hole_spelling, d.start);
    }
}

/* Each `using` hole and each template local gets a fresh name per
   expansion; the last field marks the names compile-time Lisp reads. */
static List Definition.fresh_rows(Definition &d, Array locals) {
  Array fresh = [];
  foreach (Var binder, d.using.list_free())
    fresh.push(%($binder ${binder.str()[1:]} 1));
  foreach (Var identity, locals) {
    Var spelling = d.locals[identity];
    Atom binder = _local_binder(
      identity, %(tag-local $identity) in d.locals);
    fresh.push(%($binder $spelling 0));
  }
  return fresh.list_free();
}

/* The number of uses of each binder in a template, or NULL when the
   template can apply templates: it holds a slot, a nested invocation or
   definition, or a Macro value. Such a template has no rebuild row, so a
   definition holds no second copy of another definition. */
static Map _binder_uses(List template) {
  Map uses = {};
  List syntax;
  $ast.walk(template, syntax) {
    match (syntax)
      case %((!or macro-invoke macro-slot meta-call tpl-call macro-value
                  "x2c.template" macrodef syntax-recipe declaration-recipe)
             *):
        return NULL;
    foreach (Var item, syntax)
      if (item.is_binder()) uses[item] = uses.getdefault(item, 0) + 1;
  }
  return uses;
}

/* The template a rebuild fills. An Expr hole's binder stands for its whole
   expression, without the `(expr (<macro-expr>) ...)` shell, and no
   template-origin wrapper remains, because a rebuild opens no invocation. */
static List Definition.rebuild_template(Definition &d) {
  Map expressions = {};
  foreach (List hole, d.parameters)
    if (hole.assoc(<kind>) == <expr>)
      expressions[_hole_key(hole, "expression")] = 1;
  return _rebuild_syntax(d.template, expressions);
}

static Var _rebuild_syntax(Var syntax, Map expressions) {
  if (syntax is not <list> || syntax.is_nil()) return syntax;
  match (syntax) {
    case %(at m-origin ?node): return _rebuild_syntax(node, expressions);
    case %(expr (<macro-expr>) ?binder):
      if (binder in expressions) return binder;
  }
  List child;
  $ast.rewrite_children(
    syntax.list(), child, _rebuild_syntax(child, expressions));
}

/* For each hole, the target's last, the binders of the projections the
   template uses, in capture-row order: source, value, expression, and
   splice, then a Function value's return type and declarator. `?` marks a
   projection the template does not use. */
static List Definition.rebuild_keys(Definition &d, Map uses) {
  List holes = d.target ? d.parameters.append(%(${d.target})) : d.parameters;
  Array keys = [];
  foreach (List hole, holes) {
    Array used = [];
    foreach (String projection,
             %("source" "value" "expression" "splice" "return" "declarator"))
      used.push(_used(uses, hole, projection, <?>));
    keys.push(used.list_free());
  }
  return keys.list_free();
}

/* Whether the template uses each hole, the target's included, at most
   once. A leaf template applies no templates and uses each hole once, so
   its application cannot recurse or multiply the applications its
   arguments hold. A definition inside a template is never a leaf, because
   its template can hold the enclosing template's holes. */
static int Definition.uses_holes_once(Definition &d, Map uses) {
  List holes = d.target ? cons(d.target, d.parameters) : d.parameters;
  foreach (List hole, holes) {
    int count = 0;
    foreach (String projection,
             %("source" "value" "expression" "splice" "member" "return"
               "declarator" "construction"))
      count += uses.getdefault(_hole_key(hole, projection), 0).int();
    if (count > 1) return 0;
  }
  return 1;
}

/* Makes the finished definition visible in place of its signature. */
module List Definition.publish(Definition &d) {
  List node = d.node();
  $let(d.c.token, d.start) d.show(node);
  return node;
}

/* A named local macro is visible in its scope, and a global one unless a
   template holds it. */
static void Definition.show(Definition &d, List node) {
  if (d.local && !d.anonymous) d.c.sym.define_macro(d.name, node);
  else if (!d.local && !d.nested) d.c.publish_macro_definition_node(node);
}

static List Definition.node(Definition &d) {
  Compiler c = d.c;
  List definition = %(
    macrodef
    (name ${d.name})
    (kind ${d.kind})
    (target ${d.target_kind()})
    (targetp ${d.target})
    (parameters ${d.parameters})
    (fresh ${d.fresh})
    (captures ${d.captures})
    (pattern ${d.pattern})
    (template ${d.template})
    (rebuild ${d.rebuild})
    (leaf ${d.leaf})
    (origin ${d.origin})
    (file ${d.file})
    (builtin ${c.builtin_defs})
    (local ${d.local})
    (static ${d.storage})
  );
  return definition;
}

/* signature holes

   A signature declares each hole's binder, its optional kind, and whether
   it takes a sequence. A `using` hole is a Name that compile-time Lisp
   fills with a fresh identifier. */

/* A parameter: an optional kind, `$NAME` or sequence `@NAME`. */
static List Compiler._signature_hole(Compiler c) {
  Symbol kind = 0;
  if (c.peek(0) == <ident> && (c.peek(1) == <$> || c.peek(1) == <@>))
    kind = c._hole_kind();
  int sequence = c.peek(0) == <@>;
  Token token = c._hole_name_token(sequence ? <@> : <$>);
  return c._declare_hole(token, kind, sequence);
}

static Symbol Compiler._hole_kind(Compiler c) {
  const MacroCategory *category = _category(c.token.text);
  Symbol kind = category ? category.hole : 0;
  if (!kind) {
    String spelling = c.token.text;
    $report.parse.hole_unknown_kind(c, spelling);
  }
  c.next();
  return kind;
}

static Token Compiler._hole_name_token(Compiler c, Symbol prefix) {
  c.expect(prefix);
  if (c.peek(0) != <ident>)
    $report.parse.hole_name(c);
  Token name = c.token;
  c.next();
  return name;
}

static List Compiler._declare_hole(
  Compiler c, Token token, Symbol kind, int sequence) {
  String spelling = token.text;
  if (c._hole_record(Atom.intern(spelling)))
    $report.parse.hole_duplicate(c, spelling, token);
  return c._record_hole(spelling, kind, sequence);
}

static List Compiler._record_hole(
  Compiler c, String spelling, Symbol kind, int sequence) {
  List hole = _hole(
    Atom.intern(sequence ? %"*$spelling" : %"?$spelling"),
    kind, sequence);
  c.macro_holes[Atom.intern(spelling)] = hole;
  return hole;
}

static void Compiler._using_holes(Compiler c, Array binders) {
  do binders.push(c._using_hole().assoc(<binder>)); while (c.test(<,>));
}

static List Compiler._using_hole(Compiler c) =>
  c._declare_hole(c._hole_name_token(<$>), <name>, 0);

module List _hole(Atom binder, Symbol kind, int sequence) => %(
    macro-param
    (binder $binder)
    (kind $kind)
    (sequence $sequence)
  );

module List Compiler._hole_record(Compiler c, Atom name) {
  Var stored;
  if (!c.macro_holes.try_get(name, stored)) return NULL;
  return stored;
}

/* The final hole records, with the kinds the body inferred. */
static List Compiler._parameter_rows(Compiler c, List parameters) {
  Array rows = [];
  foreach (List parameter, parameters)
    rows.push(c._hole_record(_hole_name(parameter)));
  return rows.list_free();
}

module Atom _hole_name(List hole) {
  String binder = hole.assoc(<binder>).str();
  return Atom.intern(binder[1:]);
}

/* definition bodies

   A braced body opens with any `using` lines and reads the items its
   result kind produces as a `seq`. */

static List Compiler._parse_body(Compiler c, Symbol result_kind, Array using) {
  c.expect(<"{">);
  c._parse_body_using(using);
  if (result_kind == <block-item>)
    return cons(<seq>, c.parse_block_items(0).cdr());
  if (result_kind == <field>)
    return c._closed_seq(
      c.peek(0) == <"}"> ? NULL : c.parse_fields(%(struct ())));
  if (result_kind == <enumerator>)
    return c._closed_seq(c.parse_enumerators(%(enum ())));
  if (result_kind == <map-entry>) return c._closed_seq(c.parse_map_entries());
  return c._closed_seq(c._unit_items());
}

/* `using $name;` makes a fresh private name for each expansion. `using
   name;` keeps the file-scope declaration `name` has where the macro is
   written, wherever the expansion lands. */
static void Compiler._parse_body_using(Compiler c, Array binders) {
  while (c.at_word("using") &&
         (c.peek(1) == <$> || c.peek(1) == <ident>)) {
    c.next();
    c._using_clause(binders);
    c.expect(<;>);
  }
}

/* One `using` list: fresh names, or file-scope names. An Expression
   macro, which has no braced body, writes it after its signature. */
static void Compiler._using_clause(Compiler c, Array binders) {
  if (c.peek(0) == <$>) c._using_holes(binders);
  else c._using_names();
}

static void Compiler._using_names(Compiler c) {
  do {
    String spelling = c.token.text;
    c.expect(<ident>);
    /* A name no x2c declaration supplies is a native name left to C. */
    List binding = c.sym.reference_global(%($spelling));
    c.macro_holes[%(using ${binding_identity_spelling(binding)})] = binding;
  } while (c.test(<,>));
}

static List Compiler._closed_seq(Compiler c, List rows) {
  c.expect(<"}">);
  return %(seq @rows);
}

/* Directives between the items stay in the body. */
static List Compiler._unit_items(Compiler c) {
  Array items = [];
  while (c.peek(0) != <"}">) {
    foreach (Var directive, c.leading_preproc()) items.push(directive);
    if (c.peek(0) == <"}">) break;
    items.push(c.parse_top_level());
  }
  return items.list_free();
}

static int Compiler._legacy_expression_body(Compiler c) {
  if (c.peek(0) != <(>) return 0;
  Token after = c.token.after_group();
  return after.type != <;> && !_extends_expression(after);
}

/* A leading parenthesized group is the complete legacy expression body when
   the following token cannot extend that expression. A semicolon always
   selects the canonical form. */
static int _extends_expression(Token token) {
  Symbol type = token.type;
  return type.binary_precedence() || type.is_assignment_op() ||
         type in operand_continuations ||
         (type == <ident> && (token.text == "is" || token.text == "in"));
}

/* After a complete operand, a postfix operator, a brace initializer, the
   conditional, or a comma continues the expression. */
static const SymbolSet operand_continuations =
  %<<"[" "(" "{" "->" "." "++" "--" "?" ",">>;

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
    return c._meta_call_slot(role);
  if (role != <expression> && role != <statement> &&
      c.peek(0) == <$> && c.peek(2) == <(> &&
      !c.peek_macro_hole() && !c._peek_invocation())
    return c._meta_call_slot(role);
  if (c.peek(0) == <"$("> || c.peek(0) == <"@(">)
    return c._lisp_slot(role);
  return c._hole_slot(role);
}

/* The callable supplies syntax in the requested insertion position. */
static List Compiler._meta_call_slot(Compiler c, Symbol role) {
  int sequence = c.peek(0) == <@>;
  if (sequence && !(role in sequence_roles))
    $report.parse.splice_position(c);
  if (!sequence && (role == <block> || role in declaration_roles))
    return NULL;
  List definition = c._peek_invocation();
  if (sequence && definition && _result_kind(definition) != <expression>)
    return c._target_at(_slot_position(role), 1);
  List call = c.try_parse_macro_expression();
  return %(macro-slot $sequence $call);
}

/* A result macro keeps the ordinary position's kind and decorator rules. */
static AstPos _slot_position(Symbol role) {
  switch (role) {
    case <unit>:       return AST_UNIT;
    case <block>:      return AST_BLOCK;
    case <field>:      return AST_FIELD;
    case <enumerator>: return AST_ENUMERATOR;
    case <map-entry>:  return AST_MAP_ENTRY;
    default:           return AST_EXPRESSION;
  }
}

/* A Lisp slot fills a declaration slot only when @ splices it. A block
   item that continues into a declaration, and a statement, keep the
   ordinary grammar. */
static List Compiler._lisp_slot(Compiler c, Symbol role) {
  int splice = c.peek(0) == <"@(">;
  if (splice && !(role in sequence_roles))
    $report.parse.splice_position(c);
  if (role in declaration_roles && !splice) return NULL;
  if (!splice && role == <block> && c.macro_lisp_starts_declaration())
    return NULL;
  if (role == <statement>) return NULL;
  if (role == <expression>) return c.parse_macro_lisp_expression();
  return c._parse_lisp_slot(role);
}

/* A hole fills a slot whose role its kind accepts. A sequence hole of no
   kind takes the slot's kind. */
static List Compiler._hole_slot(Compiler c, Symbol role) {
  List hole = c.peek_macro_hole();
  if (!hole ||
      (role == <argument> && !hole.assoc(<sequence>).int()) ||
      (role == <statement> && c.after_hole().type == <(>)) return NULL;
  if (role == <expression> && hole.assoc(<sequence>).int())
    $report.parse.splice_expr(c);
  if (!(role in untyped_roles)) {
    Symbol kind = hole.assoc(<kind>);
    if (!kind && c.peek(0) != <@> && c.peek(0) != <"@{"> &&
        !c._quoted_role(role))
      return NULL;
    if (kind && !_kind_accepts_role(kind, role)) return NULL;
  }
  List syntax = c._parse_hole(role);
  return syntax && role == <expression>
       ? %(expr (<macro-expr>) $syntax) : syntax;
}

static const SymbolSet declaration_roles =
  %<<field enumerator map-entry unit>>;
static const SymbolSet sequence_roles =
  %<<argument block field enumerator map-entry param unit catch match-row
     decl-row>>;
static const SymbolSet untyped_roles = %<<expression argument type>>;
static const SymbolSet quoted_roles = %<<statement block name param>>;

/** Returns the registered hole descriptor for a named or expression hole.
    `$NAME` and `${expression}` insert one value; `@NAME` and `@{expression}`
    splice a sequence. Returns NULL without consuming a non-hole spelling.
*/
List Compiler.peek_macro_hole(Compiler c) {
  Symbol prefix = c.peek(0);
  if (prefix == <"@{">) return c._expression_hole(c.token);
  if (prefix != <$> && prefix != <@>) return NULL;
  if (c.peek(1) == <"{">) return c._expression_hole(c.token);
  if (c.peek(1) != <ident>) return NULL;
  Token name = Token.skip_trivia(c.token + 1);
  List hole = c._hole_record(Atom.intern(name.text));
  return hole ? hole : c._quoted_hole(name.text, c.token);
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

/* Returns NULL if the quotation registered no expression at this offset. */
static List Compiler._expression_hole(Compiler c, Token prefix) {
  Var name;
  if (!c.macro_holes ||
      !c.macro_holes.try_get(%(expression ${prefix.pos}), name))
    return NULL;
  List hole = c._hole_record(Atom.intern(name));
  return hole ? hole : c._quoted_hole(name, prefix);
}

/* A quotation's hole takes its kind from a name position, or from a
   parameter or statement position where it stands alone, which no
   annotation can give it. A hole that a declarator follows is a parameter's
   type, and one that an operator, `;`, or a postfix form follows is an
   expression. */
static int Compiler._quoted_role(Compiler c, Symbol role) {
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
static List Compiler._quoted_hole(
  Compiler c, String spelling, Token prefix) {
  if (!c.macro_holes || !(%(quotation) in c.macro_holes)) return NULL;
  Type type = NULL;
  List local = c.sym.lookup(%($spelling), type);
  if (!local || !c.sym.binding_is_local(local)) return NULL;
  Symbol kind = c.sym.is_named_value_type(type, "Type") ? <type> : 0;
  int sequence = prefix.type == <@> || prefix.type == <"@{">;
  List hole = c._record_hole(spelling, kind, sequence);
  Var quoted = c.macro_holes[%(quoted)];
  c.macro_holes[%(quoted)] =
    cons(hole, quoted is <list> ? quoted.list() : NULL);
  return hole;
}

/* A quotation's holes in the order its body first names them. */
static List _quoted_holes(Compiler c) {
  Var quoted = c.macro_holes[%(quoted)];
  return quoted is <list> ? quoted.list().reverse() : NULL;
}

/* Consumes a hole filling `role` and returns its projection. */
module List Compiler._parse_hole(Compiler c, Symbol role) {
  Token token = c.token;
  List hole = c.peek_macro_hole();
  if (!hole) c._unbound(c._hole_name_token(token.type).text, token);
  c.token = c.after_hole();
  Atom name = _hole_name(hole);
  int sequence = token.type == <@> ||
                 token.type == <"@{">;
  if (sequence != hole.assoc(<sequence>).int())
    c._cardinality_error(name.str(), sequence, token);
  if (sequence && !(role in sequence_roles))
    $report.parse.splice_position(c);
  Symbol inferred = _role_kind(role), kind = hole.assoc(<kind>);
  if (!kind) {
    hole = hole.search_replace(%(kind ?prior), %(kind $inferred));
    c.macro_holes[name] = hole;
  }
  else if (!_kind_accepts_role(kind, role)) {
    String spelling = name.str();
    $report.parse.hole_ambiguous(
      c,
      spelling, token, _kind_spelling(kind), _kind_spelling(inferred));
  }
  String projection = c._hole_projection(hole, role, sequence);
  return %(macro-bind ${_hole_key(hole, projection)});
}

static void Compiler._cardinality_error(
  Compiler c, String spelling, int sequence, Token token) {
  $report.parse.hole_cardinality(c, sequence, spelling, token);
}

static Symbol _role_kind(Symbol role) {
  if (role == <expression> || role == <argument>) return <expr>;
  return role == <statement> ? <block> : role;
}

/* A decorator's Unit target projects its source; a sequence, a type, or
   a captures list projects its splice; other holes project their
   expression or value. */
static String Compiler._hole_projection(
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
    if (c._peek_invocation()) return 0;
    opening = Token.skip_trivia(Token.skip_trivia(opening + 1) + 1);
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
  if (hole) hole = c._hole_record(_hole_name(hole));
  if (!slot || !hole || hole.assoc(<kind>) != <name> ||
      hole.assoc(<sequence>).int())
    return slot;
  return %(macro-bind ${_hole_key(hole, "member")});
}

/* A Lisp slot carries its form and the construction binders its Unit holes
   need. A slot inside a Unit decorator also carries the target's. */
static List Compiler._parse_lisp_slot(Compiler c, Symbol role) {
  int sequence = c.peek(0) == <"@(">;
  String form = c._lisp_form();
  Var target = c.macro_holes[%(target)];
  List construction = c._lisp_construction(form);
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
static List Compiler._lisp_construction(Compiler c, String form) {
  Tokenizer tokenizer = Tokenizer.new(form, <macro-lisp>);
  tokenizer.scan();
  Array construction = [];
  Map seen = {};
  Token token = tokenizer.next();
  while (token && token.type != <eof>) {
    if (token.type == <$>) {
      Token name = tokenizer.next();
      if (name && name.type == <ident>)
        c._unit_construction(name, construction, seen);
      token = name;
    }
    token = tokenizer.next();
  }
  return construction.list_free();
}

static void Compiler._unit_construction(
  Compiler c, Token name, Array construction, Map seen) {
  List hole = c._hole_record(Atom.intern(name.text));
  if (!hole || hole.assoc(<kind>) != <unit>) return;
  Var binder = _hole_key(hole, "construction");
  if (binder in seen) return;
  seen[binder] = 1;
  construction.push(binder);
}

/* template binders

   Each hole projection has a binder whose prefix gives its cardinality, and
   each declaration a template makes has a binder numbered in the order the
   template declares it. */

module Atom _hole_key(List hole, String projection) =>
  Macro.binder(hole.assoc(<binder>), projection, hole.assoc(<sequence>));

/* A template binder names one lexical declaration, including its namespace.
   Its ordinal keeps same-spelled declarations distinct within a template. */
static Atom _local_binder(Var identity, int tag) {
  int number = 0;
  (void) binding_identity_try_parts(identity, number, NULL);
  int ordinal = INT_MAX - number;
  return Atom.intern(%"?__macro_${tag ? "tag" : "local"}_${ordinal}");
}

/* Introduces one declaration in the current lexical scope. */
static List Compiler._definition_local(Compiler c, String spelling, int tag) {
  Map locals = c.macro_definition_locals();
  Var order = locals[<order>];
  int identity = INT_MAX - (order is <list> ? order.list().len() : 0);
  List introduced = binding_identity_new(identity, spelling);
  c.set_fact(%(known $identity), spelling);
  locals[<order>] = cons(introduced, order is <list> ? order : NULL);
  locals[introduced] = spelling;
  if (tag) locals[%(tag-local $introduced)] = 1;
  return introduced;
}

/** Returns the current declaration's definition-local identity. An active
    macro-definition locals map is required. */
List Compiler.macro_introduced_name(Compiler c, String spelling) {
  Map locals = c.macro_definition_locals();
  List current = c.sym.current_binding(%($spelling));
  if (current && current in locals) return current;
  return c._definition_local(spelling, 0);
}

/** Returns a template's local binding for tag `name` of `kind`, or NULL
    when it names a visible public tag. A tag the template defines or
    declares is a template local, apart from ordinary names of the same
    spelling. A tag it only references keeps its public spelling unless the
    template later defines or declares it.
*/
List Compiler.macro_tag_name(
  Compiler c, Symbol kind, String name, int definition) {
  Map locals = c.macro_definition_locals();
  List key = %(tag $name);
  List current = c.sym.current_binding(key);
  if (current && current in locals) {
    if (definition) locals.del(%(provisional $current));
    return current;
  }
  if (!definition) {
    List visible = c.sym.lookup(key, NULL);
    if (visible && visible in locals) return visible;
    /* A name the body passed to a nested macro's Name hole is the body's
       own in every namespace, including the tag that macro declares. */
    Var named = locals[%(name-argument $name)];
    if (named is <list>) return named;
    if (c.sym.get_exact(%($kind $name))) return NULL;
  }
  List local = c._definition_local(name, 1);
  c.sym.bind_identity(%(tag), local, %($kind $local));
  if (!definition) locals[%(provisional $local)] = 1;
  return local;
}

/* Replaces each binder or binding identity that `bindings` maps. A List
   none of whose children change stays the same List. */
module Var _replace_bindings(Var value, Map bindings) {
  int candidate = value.is_binder();
  if (!candidate && value is <list> && !value.is_nil())
    candidate = binding_identity_try_parts(value, NULL, NULL);
  Var replacement;
  if (candidate && bindings.try_get(value, replacement)) return replacement;
  if (value is not <list> || value.is_nil()) return value;
  Array items = $auto([]);
  int changed = 0;
  foreach (Var child, value.list()) {
    Var item = _replace_bindings(child, bindings);
    changed |= item != child;
    items.push(item);
  }
  return changed ? items.list().var() : value;
}

/* invocation patterns

   An invocation's capture rows match the definition's pattern: an `args`
   row per parameter, a decorator's target row, and a Name row for each
   fresh name compile-time Lisp reads. Each row binds only the projections
   the template uses. */

static List Definition.invocation_pattern(Definition &d) {
  Map binders = {};
  _template_binders(d.template, binders);
  Array arguments = [];
  foreach (List parameter, d.parameters)
    arguments.push(_capture_pattern(parameter, binders));
  List invocation = d.kind == <decorator>
    ? %(
      target (args @{arguments.list_free()})
      ${_capture_pattern(d.target, binders)}
    ) : %(args @{arguments.list_free()});
  List captures = _fresh_patterns(d.fresh, binders);
  return captures ? invocation.append(%((fresh @captures))) : invocation;
}

static void _template_binders(Var value, Map binders) {
  if (value.is_binder()) {
    binders[value] = 1;
    return;
  }
  if (value is not <list>) return;
  foreach (Var child, value.list()) _template_binders(child, binders);
}

static List _fresh_patterns(List fresh, Map binders) {
  Array fresh_patterns = [];
  foreach (Var row, fresh) {
    Var (binder, spelling, lisp) = row;
    (void) spelling;
    if (lisp.int())
      fresh_patterns.push(_capture_pattern(_hole(binder, <name>, 0), binders));
  }
  return fresh_patterns.list_free();
}

/* A hole has source, value, expression, and splice projections. A singular
   Function hole also has return and declarator projections, while a Unit hole
   may carry construction requirements. The stored Match pattern binds only
   projections used by the template; the author binder exposes the captured
   value to compile-time Lisp. */
static List _capture_pattern(List hole, Map binders) {
  Var author = hole.assoc(<binder>);
  int sequence = hole.assoc(<sequence>);
  Var one = sequence ? <*>.var() : <?>.var();
  Var source = _used(binders, hole, "source", one);
  Var value = _used(binders, hole, "value", one);
  Var expression = _used(binders, hole, "expression", one);
  Var splice = _used(binders, hole, "splice", <*>);
  if (!sequence && hole.assoc(<kind>) == <function>)
    value = %(
      !and $value
      (function
        ${_used(binders, hole, "return", <?>)}
        ${_used(binders, hole, "declarator", <?>)}
        ?)
    );
  List trailing = NULL;
  if (hole.assoc(<kind>) == <unit>) trailing = _unit_trailing(hole, binders);
  return _capture_layout(
    sequence,
    %(!and (source $author) (source $source)),
    sequence ? %(!and (value $value) (value $expression) (value $splice))
             : %(value $value),
    %(expression $expression), %(splice $splice), trailing);
}

/* The binder of a projection the template uses, or `otherwise`. */
static Var _used(Map binders, List hole, String projection, Var otherwise) {
  Var binder = _hole_key(hole, projection);
  return binder in binders ? binder : otherwise;
}

/* A Unit hole's row carries its construction binder when the template
   reads the hole or its construction. */
static List _unit_trailing(List hole, Map binders) {
  Var author = hole.assoc(<binder>);
  Var construction = _hole_key(hole, "construction");
  int used = author in binders || construction in binders;
  foreach (String role, %("source" "value" "splice"))
    used |= _hole_key(hole, role) in binders;
  return used ? %($construction) : NULL;
}

/* A scalar capture has source, value, expression, and splice fields; a
   sequence capture has source and value. Any Unit construction requirements
   follow. Patterns and rows share this layout. */
module List _capture_layout(
  int sequence, List source, List value, List expression, List splice,
  List trailing) =>
  sequence ? %(capture $source $value @trailing)
           : %(capture $source $value $expression $splice @trailing);

// definition forms and keyword aliases

/** Publishes a canonical `macrodef` in source order and returns `node`.
    A later definition with the same name affects only later invocations.
*/
List Compiler.publish_macro_definition_node(Compiler c, List node) {
  c.macros[node.assoc(<name>)] = node;
  if (c.shallow && !c.macro_holes &&
      !node.assoc(<static>).equal(1) && !node.assoc(<local>).int())
    c.record_compile_time_effect(
      %(compile-time macrodef ${c.freeze_declaration_syntax(node)}), c.token);
  return node;
}

/** Records a public source effect where its completed definition stands. */
void Compiler.record_compile_time_effect(
  Compiler c, List row, Token start) {
  if (!c.shallow || c.source_private || c.macro_holes ||
      !c.sym.at_file_scope() ||
      c.builtin_defs || !c.filename ||
      c.filename.startswith("<builtin:")) return;
  String source = home_portable_path(Path.absolute(c.filename));
  if (c.source_module) {
    if (!c.module_owner)
      c.report_error(<parse>, "module declaration has no owning module", start, NULL);
    row = %(compile-time module ${home_portable_path(c.module_owner)} $row);
  }
  List key = %("source-node" (compile-time $source ${start.pos}));
  List previous = c.sym.get(key);
  if (previous) row = %(compile-time effects $previous $row);
  c.sym.set(key, row);
}

/** Installs included compile-time definitions in their source order.
    Keyword aliases retain the definition visible when their source declared
    them, even if a later macro definition uses the same name.
*/
void Compiler.install_compile_time_effects(Compiler c, List rows) {
  foreach (List row, rows) match (row) {
    case %(compile-time module ?owner ?effect):
      if (c.module_accessible(c.canonical_path(home_absolute_path(owner))))
        c.install_compile_time_effects(%($effect));
    case %(compile-time effects *effects):
      c.install_compile_time_effects(effects);
    case %(compile-time macrodef ?definition): {
      Var name = c.thaw_declaration_syntax(definition.list().assoc(<name>));
      c.macros[name] = %(imported-macro $definition);
    }
    case %(compile-time keyword ?alias ?definition): {
      if (!c.kw_aliases) c.kw_aliases = {};
      c.kw_aliases[alias] = %(imported-macro $definition);
    }
    case %(compile-time rewrite *): c._install_rewrite(row);
    case %(compile-time lisp ?form (source ?path ?site)): {
      if (c.signature_only) continue;
      Token token = c.thaw_declaration_syntax(site);
      String file = home_absolute_path(path), text = NULL;
      c.read_source(file, text);
      $let(c.filename, file)
      $let(c.text, text)
      $let(c.line_markers, NULL) {
        if (c.shallow) c.queue_declaration_effect(form, token, NULL);
        else c.evaluate_declaration_effect(form, token);
      }
    }
    case %(compile-time import ?path (source ?source ?site)): {
      if (c.signature_only) continue;
      Token token = c.thaw_declaration_syntax(site);
      String file = home_absolute_path(source), text = NULL;
      c.read_source(file, text);
      $let(c.filename, file)
      $let(c.text, text)
      $let(c.line_markers, NULL)
        c._import(home_absolute_path(path), token);
    }
    case %(project-meta *): c.install_project_meta_effect(row);
  }
}

/** Returns whether the current tokens have macro-definition introducer form.
    This query does not consume tokens.
*/
int Compiler.macro_form_is_definition(Compiler c) {
  Token token = c.token;
  int offset = c.peek(0) == <static>;
  if (offset) token = Token.skip_trivia(token + 1);
  if (c.peek(offset) != <ident> || token.text != "macro") return 0;
  if (c.peek(offset + 1) == <$>) return 1;
  return c.peek(offset + 1) == <ident> &&
    (c.peek(offset + 2) == <$> ||
     (c.peek(offset + 2) == <ident> && c.peek(offset + 3) == <$>));
}

/** Returns whether the current tokens begin a local macro definition.
    This query does not consume tokens.
*/
int Compiler.local_macro_form_is_definition(Compiler c) {
  /* The `<(>` literal keeps this body braced: the API reference generator
     reads it as an unbalanced parenthesis and drops the rest of the file. */
  return c.at_word("macro") && c.peek(1) == <ident> &&
         c.peek(2) == <ident> && c.peek(3) == <(>;
}

/** Returns whether the current tokens begin a `keyword NAME $macro` alias.
    This query does not consume tokens.
*/
int Compiler.keyword_form_is_definition(Compiler c) {
  Token token = c.token;
  int offset = c.peek(0) == <static>;
  if (offset) token = Token.skip_trivia(token + 1);
  return c.peek(offset) == <ident> && token.text == "keyword" &&
         c.peek(offset + 2) == <$>;
}

/** Parses and installs one source-local `keyword` alias.
    The named macro must already be visible; the alias captures that definition
    and consumes its terminating semicolon.
*/
void Compiler.parse_keyword_definition(Compiler c) {
  Token declaration = c.token;
  int storage = c.test(<static>) || c.source_private;
  c.expect(<ident>);
  if (c.peek(0) != <ident>)
    $report.parse.keyword_name(c);
  Atom alias = Atom.intern(c.token.text);
  c.next();
  if (c._fixed_alias(alias))
    $report.macro.keyword_builtin(c, declaration);
  Token reference = c.token;
  List definition = c._lookup(c._name(), reference);
  Symbol kind = definition.assoc(<kind>);
  if (!(kind in alias_kinds)) {
    String spelling = _kind_spelling(kind);
    $report.macro.keyword_internal(
      c,
      spelling, declaration, _definition_note(definition));
  }
  c.expect(<;>);
  c.kw_aliases[alias] = definition;
  if (!storage)
    c.record_compile_time_effect(
      %(compile-time keyword $alias
        ${c.freeze_declaration_syntax(definition)}), declaration);
}

/* Only the built-in sources define `with` or replace a built-in alias. */
static int Compiler._fixed_alias(Compiler c, Atom alias) {
  Var existing;
  return !c.builtin_defs &&
    (alias == <with> ||
     (c._try_macro(c.kw_aliases, alias, existing) &&
      existing.list().assoc(<builtin>).int()));
}

static const SymbolSet alias_kinds =
  %<<expression block-item field enumerator map-entry unit decorator>>;

/* Parses one keyword alias of `c`'s source into `aliases`. */
module void Compiler._record_alias(Compiler c, Map aliases) {
  Token token = c.token;
  if (token.type == <static>) token = Token.skip_trivia(token + 1);
  token = Token.skip_trivia(token + 1);
  Atom alias = Atom.intern(token.text);
  c.parse_keyword_definition();
  aliases[alias] = c.kw_aliases[alias];
}

