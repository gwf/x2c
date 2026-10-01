/*  macros.x -- source macros and the compile-time code they run

    A definition is a compiler-only `macrodef` List: its holes, a Match
    pattern over an invocation's capture rows, and a template of the
    binders that pattern captures. Expansion fills the template and binds
    the result through the operations that bind parsed source.

    Template slots, `$(...)` forms, and `meta` functions run in the unit's
    compile-time Lisp session, whose parent is the shared library session.
    Each evaluation installs the `MetaContext` that `meta-sdk.x` answers
    compile-time operations from.
*/

#pragma once
$(import "../lib/private-keywords.xmacro")
$(import "../src/grammar.xmacro")
$(import "../src/ast-rewrite.xmacro")
#include "compiler.x"
#pragma private
#include "expressions.x"
#include "builtins.x"
#include "linked-meta.x"
#include "literals.x"
#include "stage.x"
#include "meta-group.x"
#include "meta-helper-client.x"
#include "meta-native.x"
#include "meta-sdk.x"
#include "meta.x"
#include "parse.x"
#include "regions.x"
#include "statements.x"
#include "digest.x"
#include "script.x"
#include "toolchain.x"
#include "utils.x"
#include <dlfcn.h>
#include <unistd.h>
#include <errno.h>
#include <limits.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

/* macro definitions

   Reading a definition takes its result kind, name, signature holes, and
   body. The body becomes a template of binders, and the definition keeps
   the Match pattern whose captures fill them. */

/* One definition while it is read. `nested` marks a definition inside a
   template, which stays syntax until the template's expansion binds it.
   `locals` holds the template's own declarations and `recorded` a local
   macro's captured names, each newest first under `<order>`. */
typedef struct Definition {
  Compiler c, Token start;
  Atom name, Symbol kind, target_kind;
  List target, parameters, fresh, captures, pattern, template, origin, names;
  String file, Map locals, recorded, Array params, using;
  int open, anonymous, local, nested, imported, builtin, expression, legacy;
} Definition;

/** Parses the macro definition at the current token into a `macrodef` `List`.
    A source-level definition is published immediately; a definition inside a
    template remains syntax for later binding at its expansion site.
*/
List Compiler.parse_macro_definition(Compiler c) {
  Definition d = {.c = c, .start = c.token};
  c.expect(<ident>);
  d.head();
  d.naming();
  d.nested = !!c.macro_holes;
  // A rejected signature must not leave later declarations as templates.
  $let(c.macro_holes, {}) {
    d.locals = {};
    c.macro_holes[%(locals)] = d.locals;
    d.params = [];
    d.using = [];
    d.signature();
    d.arrow();
    d.announce();
    d.body();
  }
  d.finish();
  return d.publish();
}

/* Reads `open` and the result kind. A local definition names itself
   without `$`, and an anonymous one has no name to read. */
static void Definition.head(Definition *d) {
  Compiler c = d.c;
  d.open = c.at_word("open") && c.peek(1) == <ident>;
  if (d.open) c.next();
  if (c.peek(0) == <$>)
    c.report_error(
      <parse>, "macro definition requires a result kind before '$'",
      c.token,
      %("write the result kind between 'macro' and the macro name"));
  d.anonymous = c.peek(0) == <ident> && c.peek(1) == <(>;
  d.local = d.anonymous || (c.peek(0) == <ident> &&
            c.peek(1) == <ident> && c.peek(2) == <(>);
  if (c.peek(0) != <ident> || (!d.local && c.peek(1) != <$>))
    c.report_error(
      <parse>, "expected macro result kind before '$'", c.token, NULL);
  Token token = c.token;
  c.next();
  d.kind = _result_kind_token(c, token);
}

static void Definition.naming(Definition *d) {
  Compiler c = d.c;
  if (d.anonymous) d.name = Atom.intern(c.fresh_name("anonymous_macro"));
  else if (d.local) {
    d.name = Atom.intern(c.token.text);
    c.next();
  }
  else d.name = _name(c);
  String spelling = d.name.str();
  if (d.local && d.name == <with>)
    c.report_error(
      <macro>, "'with' cannot be a local macro name", d.start, NULL);
  if (spelling.startswith("x2c.") && !c.builtin_defs)
    c.report_error(
      <parse>, %"macro name '$spelling' is reserved",
      d.start, %("x2c.* is reserved for compiler facilities"));
  Var existing;
  if (c.import_src && c.macros.try_get(d.name, existing))
    c.report_error(
      <macro>, %"imported macro '$spelling' collides with a visible macro",
      d.start,
      %(${_definition_note(existing)}
        "import: ${c.display_path(c.import_src)}"));
}

/* Reads the parameter holes, then a `using` clause. A decorator's first
   parameter is its target. */
static void Definition.signature(Definition *d) {
  Compiler c = d.c;
  c.expect(<(>);
  if (!c.test(<)>)) {
    do d.parameter(_signature_hole(c)); while (c.test(<,>));
    c.expect(<)>);
  }
  d.check_signature();
  if (c.take_word("using")) _using_holes(c, d.using);
  if (c.peek(0) == <:>)
    c.report_error(
      <parse>,
      "macro result kind belongs after 'macro', before the '$' name",
      c.token, NULL);
}

static void Definition.parameter(Definition *d, List hole) {
  Compiler c = d.c;
  if (d.kind == <decorator> && !d.target) d.take_target(hole);
  else d.params.push(hole);
  if (hole.assoc(<sequence>).int() && c.peek(0) == <,>)
    c.report_error(
      <parse>, "sequence macro hole must be the final argument",
      c.token, NULL);
}

/* A Unit target's source stays visible to compile-time Lisp, whose
   template slots find the target hole under `(target)`. */
static void Definition.take_target(Definition *d, List hole) {
  Compiler c = d.c;
  if (!decorator_target_kinds.contains(hole.assoc(<kind>)))
    c.report_error(
      <parse>, "decorator first parameter has invalid target kind",
      d.start,
      %("expected Expression, Function, Statement, Block, Field,"
        "Unit, or NamedType"));
  if (hole.assoc(<sequence>).int())
    c.report_error(
      <parse>, "decorator target parameter must be singular", d.start,
      NULL);
  d.target = hole;
  if (hole.assoc(<kind>) != <unit>) return;
  c.macro_holes[%(source ${hole.assoc(<binder>)})] = 1;
  c.macro_holes[%(target)] = hole;
}

static const SymbolSet decorator_target_kinds =
  %<<expr function block field unit named-type>>;

/* A local macro produces no file-scope syntax, directly or through the
   target it decorates. */
static void Definition.check_signature(Definition *d) {
  Compiler c = d.c;
  if (d.kind == <decorator> && !d.target)
    c.report_error(
      <parse>, "decorator requires a first target parameter", d.start,
      NULL);
  if (!d.local) return;
  if (d.kind == <unit> || d.kind == <decl-unit>) {
    String result_spelling = _kind_spelling(d.kind);
    c.report_error(
      <macro>, %"local macros cannot have $result_spelling results",
      d.start, NULL);
  }
  if (d.kind != <decorator>) return;
  Symbol kind = d.target.assoc(<kind>);
  if (kind == <function> || kind == <unit> || kind == <named-type>) {
    String target = _kind_spelling(kind);
    c.report_error(
      <macro>, %"local decorators cannot target $target syntax", d.start,
      NULL);
  }
}

/* An Expression result, or a decorator of an expression, has an `=>`
   body. Every other result has a braced body after an optional `=>`. */
static void Definition.arrow(Definition *d) {
  Compiler c = d.c;
  if (d.target) d.target_kind = d.target.assoc(<kind>);
  d.expression = d.kind == <expression> ||
    (d.kind == <decorator> && d.target_kind == <expr>);
  if (d.expression) {
    if (c.peek(0) == <"{">) _braced_body_error(c);
    c.expect(<=>);
    c.expect(<">">);
    d.legacy = _legacy_expression_body(c);
    return;
  }
  if (c.peek(0) == <=>) {
    c.expect(<=>);
    c.expect(<">">);
  }
  if (c.peek(0) == <(>)
    c.report_error(
      <parse>,
      "parenthesized macro body requires Expression result or target",
      c.token, NULL);
  if (c.peek(0) != <"{">) _braced_body_error(c);
}

static void _braced_body_error(Compiler c) {
  c.report_error(
    <parse>,
    "braced macro body requires Statement, Block, Field, Entry, " +
    "Enumerator, Unit, or non-Expression Decorator result",
    c.token, NULL);
}

/* Records where the definition stands and publishes its signature, so an
   invocation inside the body names this macro. */
static void Definition.announce(Definition *d) {
  Compiler c = d.c;
  d.parameters = d.params.list_free();
  (void) c.record_origin(d.start);
  d.origin = c.token_location(d.start);
  d.file = home_portable_path(c.source_path(c.filename));
  d.imported = c.import_src != NULL;
  d.builtin = c.builtin_defs;
  d.publish();
}

/* Reads the body in its own scope. A local macro records the outer names
   its body captures. */
static void Definition.body(Definition *d) {
  Compiler c = d.c;
  $let(c.local_macro_captures, d.local ? {} : NULL)
  $let(c.local_macro_capture_scopes, c.sym.scope_count()) {
    d.recorded = c.local_macro_captures;
    c.sym.push_new_scope();
    defer c.sym.pop_scope();
    d.template = d.expression
               ? d.expression_body()
               : _parse_body(c, d.body_kind(), d.using);
    d.parameters = _parameter_rows(c, d.parameters);
    d.names = _recorded(d.locals);
  }
}

/* The legacy form is parenthesized. The canonical form ends at `;`, which
   an anonymous macro omits. */
static List Definition.expression_body(Definition *d) {
  Compiler c = d.c;
  if (d.legacy) {
    c.expect(<(>);
    List replacement = c.parse_expression();
    c.expect(<)>);
    return replacement;
  }
  List replacement = c.parse_expression();
  if (!d.anonymous) c.expect(<;>);
  return replacement;
}

/* A decorator's body produces what its target is, and a Function or
   Block target's body is block items. */
static Symbol Definition.body_kind(Definition *d) {
  if (d.kind != <decorator>) return d.kind;
  Symbol target = d.target_kind;
  return target == <function> || target == <block> ? <block-item> : target;
}

/* The entries a map lists under `<order>`, oldest first, or NULL. */
static List _recorded(Map m) {
  Var order = m != NULL ? m[<order>] : void;
  return order is <list> ? order.list().reverse() : NULL;
}

/* Turns the body into the stored template, then derives the fresh rows,
   captures, and pattern an invocation needs. Parsed literal names carry
   definition-only identities, so the template stores binders instead and
   each expansion allocates one fresh identity per literal spelling. */
static void Definition.finish(Definition *d) {
  d.template = _slot_binders(d.wrap());
  Map bindings = {};
  if (d.target && d.target.assoc(<kind>) == <unit>)
    d.constructed_names(bindings);
  Array locals = d.local_binders(bindings);
  d.template = _replace_bindings(d.template, bindings);
  d.check_kinds();
  d.fresh = d.fresh_rows(locals);
  d.captures = _recorded(d.recorded);
  d.pattern = d.invocation_pattern();
}

/* A Function decorator's body becomes a function with the target's return
   type and declarator, and an Expression decorator's body a parenthesized
   expression. */
static List Definition.wrap(Definition *d) {
  List replacement = d.template;
  if (d.kind != <decorator>) return replacement;
  if (d.target_kind == <expr>)
    return %(expr (<macro-expr>) (parens $replacement));
  if (d.target_kind != <function>) return replacement;
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

/* Each `(macro-bind BINDER)` slot becomes its binder. A body that is one
   expression slot keeps the `expr` around its binder. */
static List _slot_binders(List replacement) {
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
static void Definition.constructed_names(Definition *d, Map bindings) {
  Var required = _hole_key(d.target, "construction");
  foreach (List parameter, d.parameters)
    if (parameter.assoc(<kind>) == <name>) {
      Var name = _replacement_binder(parameter.assoc(<binder>), "value", 0);
      bindings[name] = %($required $name);
    }
}

/* Binds each template local to its binder and returns the locals that get
   fresh names. A tag the template only references keeps its public
   spelling. */
static Array Definition.local_binders(Definition *d, Map bindings) {
  Array fresh = [];
  foreach (Var identity, d.names) {
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

static void Definition.check_kinds(Definition *d) {
  foreach (List hole, d.parameters)
    if (!hole.assoc(<kind>)) {
      String hole_spelling = hole.assoc(<binder>).str()[1:];
      d.c.report_error(
        <parse>, %"macro hole '$hole_spelling' has no inferred kind",
        d.start, %("annotate holes used only by compile-time Lisp"));
    }
}

/* Each `using` hole and each template local gets a fresh name per
   expansion; the last field marks the names compile-time Lisp reads. */
static List Definition.fresh_rows(Definition *d, Array locals) {
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

/* Makes the definition visible: a named local macro in its scope, and a
   global one unless a template holds it. */
static List Definition.publish(Definition *d) {
  List node = d.node();
  if (d.local && !d.anonymous) d.c.sym.define_macro(d.name, node);
  else if (!d.local && !d.nested) d.c.publish_macro_definition_node(node);
  return node;
}

static List Definition.node(Definition *d) {
  List definition = %(
    macrodef
    (name ${d.name})
    (kind ${d.kind})
    (target ${d.target_kind})
    (targetp ${d.target})
    (parameters ${d.parameters})
    (fresh ${d.fresh})
    (captures ${d.captures})
    (pattern ${d.pattern})
    (template ${d.template})
    (origin ${d.origin})
    (file ${d.file})
    (imported ${d.imported})
    (builtin ${d.builtin})
    (local ${d.local})
  );
  return d.open ? definition.append(%((open 1))) : definition;
}

static Symbol _result_kind_token(Compiler compiler, Token token) {
  String spelling = token.text, Symbol kind = Symbol.new(spelling);
  if (spelling.lower() == "declaration") return <decl-unit>;
  if (kind == <statement> || kind == <block>) return <block-item>;
  if (kind == <entry>) return <map-entry>;
  if (kind == <decorator>) return kind;
  if (kind in direct_result_kinds) return kind;
  compiler.report_error(
    <parse>, %"unknown macro result kind '$spelling'",
    token, NULL);
}

static const SymbolSet direct_result_kinds =
  %<<expression field enumerator map-entry unit>>;

/* signature holes

   A signature declares each hole's binder, its optional kind, and whether
   it takes a sequence. A `using` hole is a Name that compile-time Lisp
   fills with a fresh identifier. */

/* A parameter: an optional kind, `$NAME`, and `...` for a sequence. */
static List _signature_hole(Compiler c) {
  Symbol kind = 0;
  if (c.peek(0) == <ident> && c.peek(1) == <$>) kind = _hole_kind(c);
  Token token = _hole_name_token(c);
  return _declare_hole(c, token, kind, c.test(<...>));
}

static Symbol _hole_kind(Compiler c) {
  Symbol kind = _author_kind(c.token.text);
  if (!kind) {
    String spelling = c.token.text;
    c.report_error(
      <parse>, %"unknown macro hole kind '$spelling'",
      c.token, NULL);
  }
  c.next();
  return kind;
}

static Token _hole_name_token(Compiler c) {
  c.expect(<$>);
  if (c.peek(0) != <ident>)
    c.report_error(
      <parse>, "expected macro hole name after '$'",
      c.token, NULL);
  Token name = c.token;
  c.next();
  return name;
}

static List _declare_hole(
  Compiler c, Token token, Symbol kind, int sequence) {
  String spelling = token.text, Atom name = Atom.intern(spelling);
  if (_hole_record(c, name))
    c.report_error(
      <parse>, %"duplicate macro hole '$spelling'",
      token, NULL);
  List hole = _hole(
    Atom.intern(sequence ? %"*$spelling" : %"?$spelling"),
    kind, sequence);
  c.macro_holes[name] = hole;
  return hole;
}

static void _using_holes(Compiler c, Array binders) {
  do binders.push(_using_hole(c).assoc(<binder>)); while (c.test(<,>));
}

static List _using_hole(Compiler c) =>
  _declare_hole(c, _hole_name_token(c), <name>, 0);

static List _hole(Atom binder, Symbol kind, int sequence) => %(
    macro-param
    (binder $binder)
    (kind $kind)
    (sequence $sequence)
  );

static List _hole_record(Compiler compiler, Atom name) {
  Var stored;
  if (!compiler.macro_holes.try_get(name, stored)) return NULL;
  return stored;
}

/* The final hole records, with the kinds the body inferred. */
static List _parameter_rows(Compiler compiler, List parameters) {
  Array rows = [];
  foreach (List parameter, parameters)
    rows.push(_hole_record(compiler, _hole_name(parameter)));
  return rows.list_free();
}

static Atom _hole_name(List hole) {
  String binder = hole.assoc(<binder>).str();
  return Atom.intern(binder[1:]);
}

static const SymbolSet author_kinds =
  %<<expr type decl function name literal param block field enumerator
     map-entry unit named-type catch captures match-row decl-row>>;

static Symbol _author_kind(String spelling) {
  if (spelling.lower() == "declaratorrow") return <decl-row>;
  Symbol kind = Symbol.new(spelling);
  if (kind == <statement>) return <block>;
  if (kind == <entry>) return <map-entry>;
  if (kind == <namedtype>) return <named-type>;
  if (kind == <matchrow>) return <match-row>;
  return kind in author_kinds ? kind : 0;
}

static String _kind_spelling(Symbol kind) {
  if (kind == <block-item>) return "Statement";
  if (kind == <decl-row>) return "DeclaratorRow";
  if (kind == <map-entry>) return "Entry";
  if (kind == <match-row>) return "MatchRow";
  if (kind == <named-type>) return "NamedType";
  if (kind == <decl-unit>) return "Declaration";
  return kind.str().capitalize();
}

/* definition bodies

   A braced body opens with any `using` lines and reads the items its
   result kind produces as a `seq`. */

static List _parse_body(Compiler c, Symbol result_kind, Array using) {
  c.expect(<"{">);
  _parse_body_using(c, using);
  if (result_kind == <block-item>)
    return cons(<seq>, c.parse_block_items(0).cdr());
  if (result_kind == <field>)
    return _closed_seq(
      c, c.peek(0) == <"}"> ? NULL : c.parse_fields(%(struct ())));
  if (result_kind == <enumerator>)
    return _closed_seq(c, c.parse_enumerators(%(enum ())));
  if (result_kind == <map-entry>) return _closed_seq(c, c.parse_map_entries());
  return _closed_seq(c, _unit_items(c));
}

static void _parse_body_using(Compiler c, Array binders) {
  while (c.at_word("using") && c.peek(1) == <$>) {
    c.next();
    _using_holes(c, binders);
    c.expect(<;>);
  }
}

static List _closed_seq(Compiler c, List rows) {
  c.expect(<"}">);
  return %(seq @rows);
}

/* Directives between the items stay in the body. */
static List _unit_items(Compiler c) {
  Array items = [];
  while (c.peek(0) != <"}">) {
    foreach (Var directive, c.leading_preproc()) items.push(directive);
    if (c.peek(0) == <"}">) break;
    items.push(c.parse_top_level());
  }
  return items.list_free();
}

static int _legacy_expression_body(Compiler c) {
  if (c.peek(0) != <(>) return 0;
  Token after = c.token.after_group();
  return after.type != <;> && !_extends_expression(after);
}

/* A leading parenthesized group is the complete legacy expression body when
   the following token cannot extend that expression. A semicolon always
   selects the canonical form. */
static int _extends_expression(Token token) {
  Symbol type = token.type;
  if (type.is_assignment_op()) return 1;
  switch (type) {
    case <[>: case <(>: case <"{">: case <"->">: case <.>:
    case <++>: case <-->:
    case <||>: case <&&>: case <|>: case <^>: case <&>:
    case <==>: case <!=>: case <===>: case <!==>:
    case <"<">: case <">">: case <in>: case <"<=">: case <">=">:
    case <"<<">: case <">>">: case <+>: case <->: case <*>: case </>:
    case <%>: case <@>: case <?>: case <,>:
      return 1;
  }
  return type == <ident> && (token.text == "is" || token.text == "in");
}

/* template holes

   In a template, a `$NAME` hole, a `$(...)` Lisp slot, or a `$name(...)`
   meta call stands where the grammar expects syntax of some role. The
   first role a hole of no kind fills gives it its kind. */

/** Parses a macro hole or Lisp slot for `role` while reading a template.
    Returns role-shaped syntax containing `(macro-bind ...)` or
    `(macro-slot ...)`, or NULL when ordinary grammar owns the current tokens;
    successful parsing advances the cursor.
*/
List Compiler.try_parse_macro_slot(Compiler c, Symbol role) {
  if (!c.macro_holes) return NULL;
  if (role != <expression> && role != <statement> &&
      c.peek(0) == <$> && c.peek(2) == <(> &&
      !c.peek_macro_hole() && !_peek_invocation(c))
    return _meta_call_slot(c, role);
  if (c.peek(0) == <"$(">) return _lisp_slot(c, role);
  return _hole_slot(c, role);
}

/* A meta call fills a declaration or block slot only when `...` splices
   its result there. */
static List _meta_call_slot(Compiler c, Symbol role) {
  Token arguments = c.skip_trivia_from(c.skip_trivia_from(c.token + 1) + 1);
  int follows_splice = arguments.after_group().type == <...>;
  if (!follows_splice && (role == <block> || role in declaration_roles))
    return NULL;
  List call = c.try_parse_macro_expression();
  int splice = _slot_splice(c, role in sequence_roles);
  return %(macro-slot $splice $call);
}

/* A Lisp slot fills a declaration slot only when `...` splices it. A block
   item that continues into a declaration, and a statement, keep the
   ordinary grammar. */
static List _lisp_slot(Compiler c, Symbol role) {
  int splice = _lisp_splice_follows(c);
  if (role in declaration_roles && !splice) return NULL;
  if (role == <block> && c.macro_lisp_starts_declaration()) return NULL;
  if (role == <statement>) return NULL;
  if (role == <expression>) return c.parse_macro_lisp_expression();
  return _parse_lisp_slot(c, role in sequence_roles, role);
}

/* A hole fills a slot whose role its kind accepts. A hole of no kind
   fills a typed role only when `...` follows it. */
static List _hole_slot(Compiler c, Symbol role) {
  List hole = c.peek_macro_hole();
  if (!hole ||
      (role == <argument> && !hole.assoc(<sequence>).int()) ||
      (role == <statement> && c.peek(2) == <(>)) return NULL;
  if (role == <expression> && hole.assoc(<sequence>).int())
    c.report_error(
      <parse>, "sequence insertion is not legal in an expression slot",
      c.token, NULL);
  if (!untyped_roles.contains(role)) {
    Symbol kind = hole.assoc(<kind>);
    if (!kind && c.peek(2) != <...>) return NULL;
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

/* Consumes a `...` after a slot. It is legal only where the role takes a
   sequence. */
static int _slot_splice(Compiler c, int allowed) {
  int splice = c.test(<...>);
  if (splice && !allowed)
    c.report_error(
      <parse>, "sequence insertion is not legal in this syntax slot",
      c.token, NULL);
  return splice;
}

/** Returns the registered hole descriptor at the current `$NAME`.
    Returns NULL without consuming tokens when the spelling is not a hole.
*/
List Compiler.peek_macro_hole(Compiler compiler) {
  if (compiler.peek(0) != <$> || compiler.peek(1) != <ident>) return NULL;
  Token name = compiler.skip_trivia_from(compiler.token + 1);
  return _hole_record(compiler, Atom.intern(name.text));
}

/* Consumes a hole filling `role` and returns its projection. */
static List _parse_hole(Compiler c, Symbol role) {
  Token token = c.token;
  Atom name = Atom.intern(_hole_name_token(c).text);
  List hole = _hole_record(c, name);
  if (!hole) _unbound(c, name.str(), token);
  int sequence = _hole_splice(c, role);
  if (sequence != hole.assoc(<sequence>).int())
    _cardinality_error(c, name.str(), sequence, token);
  Symbol inferred = _role_kind(role), kind = hole.assoc(<kind>);
  if (!kind) {
    hole = hole.search_replace(%(kind ?prior), %(kind $inferred));
    c.macro_holes[name] = hole;
  }
  else if (!_kind_accepts_role(kind, role)) {
    String spelling = name.str();
    c.report_error(
      <parse>, %"macro hole '$spelling' has ambiguous kind", token,
      %("first: ${_kind_spelling(kind)}"
        "also: ${_kind_spelling(inferred)}"));
  }
  String projection = _hole_projection(c, hole, role, sequence);
  return %(macro-bind ${_hole_key(hole, projection)});
}

/* A `...` after a hole splices it, and an argument may also spell the
   splice as the atom `...`. */
static int _hole_splice(Compiler c, Symbol role) {
  if (c.test(<...>)) return 1;
  if (role != <argument> || c.peek(0) != <lit-atom> ||
      c.token.text != "...")
    return 0;
  c.next();
  return 1;
}

static void _cardinality_error(
  Compiler c, String spelling, int sequence, Token token) {
  String message = sequence
    ? %"singular macro hole '$spelling' cannot be spliced"
    : %"sequence macro hole '$spelling' requires '...'";
  c.report_error(<parse>, message, token, NULL);
}

static Symbol _role_kind(Symbol role) =>
  role == <expression> || role == <argument> ? <expr> : role;

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

static int _lisp_splice_follows(Compiler compiler) =>
  compiler.peek(0) == <"$("> &&
         compiler.token.after_group().type == <...>;

/** Returns whether tokens after a Lisp form or explicit meta call continue
    a declaration. The balanced argument group is inspected without moving
    the compiler cursor; a visible source macro retains its own grammar.
*/
int Compiler.macro_lisp_starts_declaration(Compiler c) {
  Token opening = c.token;
  if (opening.type == <$>) {
    if (_peek_invocation(c)) return 0;
    opening = c.skip_trivia_from(c.skip_trivia_from(opening + 1) + 1);
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
  if (!slot || !hole || hole.assoc(<kind>) != <name> ||
      hole.assoc(<sequence>).int())
    return slot;
  return %(macro-bind ${_hole_key(hole, "member")});
}

/* A Lisp slot carries its form and the construction binders its Unit holes
   need. A slot inside a Unit decorator also carries the target's. */
static List _parse_lisp_slot(
  Compiler compiler, int allow_sequence, Symbol role) {
  String form = _lisp_form(compiler);
  int splice = _slot_splice(compiler, allow_sequence);
  Var target = compiler.macro_holes[%(target)];
  List construction = _lisp_construction(compiler, form);
  if (target is <list>) {
    Var required = _hole_key(target, "construction");
    if (role == <name>)
      construction = construction.append(%((target $required)));
    else if (role == <unit>) construction = construction.append(%($required));
  }
  return %(
    macro-slot $splice $form
    @construction
  );
}

/* The construction binder of each Unit hole the form names, once each. */
static List _lisp_construction(Compiler compiler, String form) {
  Tokenizer tokenizer = Tokenizer.new(form, <macro-lisp>);
  tokenizer.scan();
  Array construction = [];
  Map seen = {};
  Token token = tokenizer.next();
  while (token && token.type != <eof>) {
    if (token.type == <$>) {
      Token name = tokenizer.next();
      if (name && name.type == <ident>)
        _unit_construction(compiler, name, construction, seen);
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

/* template binders

   Each hole projection has a binder whose prefix gives its cardinality, and
   each declaration a template makes has a binder numbered in the order the
   template declares it. */

/* Splice and construction projections are always Lists; return, declarator,
   and member projections are always scalar; source, value, and expression
   follow the hole's own cardinality. */
static Atom _replacement_binder(Var binder, String projection, int seq) {
  if (projection == "splice" || projection == "construction") seq = 1;
  else if (projection == "return" || projection == "declarator" ||
           projection == "member") seq = 0;
  String prefix = seq ? "*" : "?", name = binder.str();
  return Atom.intern(%"${prefix}__macro_${projection}_${name[1:]}");
}

static Atom _hole_key(List hole, String projection) =>
  _replacement_binder(
    hole.assoc(<binder>), projection, hole.assoc(<sequence>));

/* A template binder names one lexical declaration, including its namespace.
   Its ordinal keeps same-spelled declarations distinct within a template. */
static Atom _local_binder(Var identity, int tag) {
  int number = 0;
  (void) binding_identity_try_parts(identity, number, NULL);
  int ordinal = INT_MAX - number;
  return Atom.intern(%"?__macro_${tag ? "tag" : "local"}_${ordinal}");
}

/* Introduces one declaration in the current lexical scope. */
static List _definition_local(Compiler c, String spelling, int tag) {
  Map locals = c.macro_definition_locals();
  Var order = locals[<order>];
  int identity = INT_MAX - (order is <list> ? order.list().len() : 0);
  List introduced = binding_identity_new(identity, spelling);
  c.semantic_binding_facts()[%(known $identity)] = spelling;
  locals[<order>] = cons(introduced, order is <list> ? order : NULL);
  locals[introduced] = spelling;
  if (tag) locals[%(tag-local $introduced)] = 1;
  return introduced;
}

/** Returns the current declaration's definition-local identity. An active
    macro-definition locals map is required. */
List Compiler.macro_introduced_name(Compiler compiler, String spelling) {
  Map locals = compiler.macro_definition_locals();
  List current = compiler.sym.current_binding(%($spelling));
  if (current && current in locals) return current;
  return _definition_local(compiler, spelling, 0);
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
    if (c.sym.get_exact(%($kind $name))) return NULL;
  }
  List local = _definition_local(c, name, 1);
  c.sym.bind_identity(%(tag), local, %($kind $local));
  if (!definition) locals[%(provisional $local)] = 1;
  return local;
}

/* Replaces each binder or binding identity that `bindings` maps. A List
   none of whose children change stays the same List. */
static Var _replace_bindings(Var value, Map bindings) {
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

static List Definition.invocation_pattern(Definition *d) {
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
static List _capture_layout(
  int sequence, List source, List value, List expression, List splice,
  List trailing) =>
  sequence ? %(capture $source $value @trailing)
           : %(capture $source $value $expression $splice @trailing);

// definition forms and keyword aliases

/** Publishes a canonical `macrodef` in source order and returns `node`.
    A later definition with the same name affects only later invocations.
*/
List Compiler.publish_macro_definition_node(Compiler compiler, List node) {
  compiler.macros[node.assoc(<name>)] = node;
  return node;
}

/** Returns whether the current tokens have macro-definition introducer form.
    This query does not consume tokens.
*/
int Compiler.macro_form_is_definition(Compiler compiler) {
  if (compiler.peek(0) != <ident> || compiler.token.text != "macro") return 0;
  if (compiler.peek(1) == <$>) return 1;
  return compiler.peek(1) == <ident> &&
    (compiler.peek(2) == <$> ||
     (compiler.peek(2) == <ident> && compiler.peek(3) == <$>));
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
int Compiler.keyword_form_is_definition(Compiler c) =>
  c.at_word("keyword") && c.peek(2) == <$>;

/** Parses and installs one source-local `keyword` alias.
    The named macro must already be visible; the alias captures that definition
    and consumes its terminating semicolon.
*/
void Compiler.parse_keyword_definition(Compiler c) {
  Token declaration = c.token;
  c.expect(<ident>);
  if (c.peek(0) != <ident>)
    c.report_error(
      <parse>, "keyword alias requires an identifier",
      c.token, NULL);
  Atom alias = Atom.intern(c.token.text);
  c.next();
  if (_fixed_alias(c, alias))
    c.report_error(
      <macro>, "built-in keyword alias cannot be replaced",
      declaration, NULL);
  Token reference = c.token;
  List definition = _lookup(c, _name(c), reference);
  Symbol kind = definition.assoc(<kind>);
  if (!alias_kinds.contains(kind)) {
    String spelling = _kind_spelling(kind);
    c.report_error(
      <macro>, %"keyword alias cannot name internal macro kind '$spelling'",
      declaration, %(${_definition_note(definition)}));
  }
  c.expect(<;>);
  c.kw_aliases[alias] = definition;
}

/* Only the built-in sources define `with` or replace a built-in alias. */
static int _fixed_alias(Compiler c, Atom alias) {
  Var existing;
  return !c.builtin_defs &&
    (alias == <with> ||
     (c.kw_aliases.try_get(alias, existing) &&
      existing.list().assoc(<builtin>).int()));
}

static const SymbolSet alias_kinds =
  %<<expression block-item field enumerator map-entry unit decorator>>;

/* Parses one keyword alias of `c`'s source into `aliases`. */
static void _record_alias(Compiler c, Map aliases) {
  Token token = c.skip_trivia_from(c.token + 1);
  Atom alias = Atom.intern(token.text);
  c.parse_keyword_definition();
  aliases[alias] = c.kw_aliases[alias];
}

/* invocation recognition

   At each syntax position the parser asks whether the tokens start an
   invocation it should claim. Recognition consumes nothing; a claimed
   invocation's name is consumed once its definition is known. */

/** Returns whether the parser claims the macro invocation at the cursor for
    `position`. A bare keyword alias is claimed only where its result fits.
    This query does not consume tokens.
*/
int Compiler.macro_starts_target_at(Compiler c, AstPos position) =>
  _claims(c, _peek_invocation(c), position);

/* An invocation is claimed where its result fits. A statement or map entry
   that does not fit parses as an expression. Elsewhere a `$` name, or an
   identifier with arguments, is claimed so that its target parser reports
   the position diagnostic; a local expression macro at block scope remains
   an expression statement. */
static int _claims(Compiler c, List definition, AstPos position) {
  Symbol kind = definition ? _result_kind(definition) : 0;
  if (kind == _position(position).kind) return 1;
  if (position == AST_STATEMENT || position == AST_MAP_ENTRY) return 0;
  if (!definition) {
    if (c.peek(0) == <$> && (position == AST_BLOCK || c.macro_holes)) {
      String name;
      _scan_name(c, name);
      Type type = name ? c.sym.get(%($name)) : NULL;
      if (type.is_function()) return 0;
    }
    return c.peek(0) == <$>;
  }
  return !_bare(c.token, definition) &&
    (position != AST_BLOCK || kind != <expression> ||
     !definition.assoc(<local>).int());
}

typedef struct MacroPos {
  Symbol kind, const char *description, int semicolon;
} MacroPos;

static const MacroPos macro_position_info[] = {
  { <unit>,       "file scope",    1 },
  { <block-item>, "block scope",   1 },
  { <field>,      "field scope",   1 },
  { <enumerator>, "an enum body",  0 },
  { <map-entry>,  "a map literal", 0 },
  { <block-item>, "block scope",   1 },
  { <expression>, "an expression", 0 }
};

static const MacroPos *_position(AstPos position) =>
  &macro_position_info[position];

static Symbol _result_kind(List definition) {
  Symbol kind = definition.assoc(<kind>);
  if (kind != <decorator>) return kind;
  Symbol target = definition.assoc(<target>);
  if (target == <function> || target == <unit> || target == <named-type>)
    return <unit>;
  if (target == <block>) return <block-item>;
  if (target == <expr>) return <expression>;
  return target;
}

/* Returns the definition invoked at the cursor without consuming tokens, or
   NULL. A `$` name invokes its visible definition. An identifier invokes the
   innermost local macro of that name, or else its keyword alias, when an
   argument list follows or the invocation is bare. */
static List _peek_invocation(Compiler c) {
  Var stored;
  if (c.peek(0) == <$>) {
    String spelling;
    _scan_name(c, spelling);
    if (!spelling ||
        !_try_definition(c, Atom.intern(spelling), !c.shallow, stored))
      return NULL;
    return stored;
  }
  if (c.peek(0) != <ident>) return NULL;
  Atom name = Atom.intern(c.token.text);
  List definition = c.sym.has_local_macros()
                  ? c.sym.lookup_macro(name) : NULL;
  if (!definition && c.kw_aliases.try_get(name, stored)) definition = stored;
  return definition && (c.peek(1) == <(> || _bare(c.token, definition))
       ? definition : NULL;
}

/* Scans the dotted name after the current `$` without consuming tokens.
   Returns the token after the name, or the token where a name component is
   missing with `spelling` set to NULL. */
static Token _scan_name(Compiler c, String &spelling) {
  Token token = c.token, String name = NULL;
  do {
    token = c.skip_trivia_from(token + 1);
    if (token.type != <ident>) {
      name = NULL;
      break;
    }
    name = name ? %"$name.${token.text}" : token.text;
    token = c.skip_trivia_from(token + 1);
  } while (token.type == <.>);
  spelling = name;
  return token;
}

/* An identifier invoking a decorator without explicit parameters has no
   argument list. */
static int _bare(Token invocation, List definition) =>
  invocation.type != <$> && definition.assoc(<kind>) == <decorator> &&
  !definition.assoc(<parameters>).list();

/* Consumes the name of an invocation claimed at `position` and returns its
   definition, or returns NULL without consuming tokens. A `$` name that is
   neither visible nor followed by arguments is a replacement variable
   missing from a template. */
static List _take_invocation(Compiler c, AstPos position) {
  List definition = _peek_invocation(c);
  if (!_claims(c, definition, position)) return NULL;
  if (c.peek(0) != <$>) {
    c.next();
    return definition;
  }
  Token invocation = c.token;
  Atom name = _name(c);
  Var existing;
  if (c.macro_holes && c.peek(0) != <(> &&
      !_try_definition(c, name, 1, existing))
    _unbound(c, name.str(), invocation);
  return _lookup(c, name, invocation);
}

static Atom _name(Compiler c) {
  String spelling;
  Token end = _scan_name(c, spelling);
  if (!spelling)
    c.report_error(
      <parse>, c.peek(1) == <ident>
        ? "expected macro name component after '.'"
        : "expected macro name after '$'",
      end, NULL);
  c.token = end;
  return Atom.intern(spelling);
}

static List _lookup(Compiler compiler, Atom name, Token invocation) {
  Var stored;
  String spelling = name.str();
  if (!_try_definition(compiler, name, 1, stored))
    compiler.report_error(
      <parse>, %"unknown or forward-referenced macro '$spelling'",
      invocation, NULL);
  return stored;
}

/* With `install_lisp`, a `lisp.` name records the Lisp binding macros as a
   dependency and installs them when the name is not yet defined. */
static int _try_definition(
  Compiler compiler, Atom name, int install_lisp, Var &stored) {
  int found = compiler.macros.try_get(name, stored);
  String spelling = name.str();
  if (!install_lisp || !spelling.startswith("lisp.")) return found;
  _use_lisp_bindings(compiler, !found);
  return found || compiler.macros.try_get(name, stored);
}

// shallow collection

/** Returns whether the macro invocation at the cursor needs shallow
    expansion. Every imported `Unit` macro qualifies. A local `Unit` macro
    qualifies only when its template contains protocol or adoption rows that
    collection must retain.
*/
int Compiler.macro_invocation_needs_shallow_expansion(Compiler c) =>
  _needs_shallow(_peek_invocation(c));

static int _needs_shallow(List definition) {
  if (!definition) return 0;
  if (definition.assoc(<kind>) == <decl-unit> ||
      definition.assoc(<target>) == <named-type>) return 1;
  if (definition.assoc(<kind>) != <unit>) return 0;
  if (definition.assoc(<imported>).int()) return 1;
  List template = definition.assoc(<template>), bindings;
  Var matched;
  return template.try_search(
    %(!or (protocol *) (adopt *)), matched, bindings);
}

/** Consumes a macro invocation name and its balanced argument list.
    The invocation terminator or following decorator target remains current.
*/
void Compiler.skip_macro_invocation(Compiler c) {
  int bare = _bare(c.token, _peek_invocation(c));
  String spelling;
  if (c.peek(0) == <$>) c.token = _scan_name(c, spelling);
  else c.next();
  if (!bare && c.peek(0) == <(>) c.token = c.token.after_group();
}

/** Consumes a NamedType target already projected by owning-source collection.
    CPP scanning does not produce the declaration or parse its fields again.
*/
int Compiler.skip_named_type_declaration(Compiler c) {
  List definition = _peek_invocation(c);
  if (!definition || definition.assoc(<target>) != <named-type>) return 0;
  c.skip_macro_invocation();
  c._skip_shallow_expression(0);
  c.expect(<;>);
  return 1;
}

/** Reports whether the macro invocation at the cursor produces file-scope
    syntax, directly or through the target it decorates. A script unit keeps
    such an invocation at file scope. This query does not consume tokens.
*/
int Compiler.macro_targets_unit(Compiler c) {
  List definition = _peek_invocation(c);
  if (!definition) return 0;
  Symbol kind = _result_kind(definition);
  return kind == <unit> || kind == <decl-unit>;
}

/* invocation arguments

   Each parameter hole captures its arguments into one capture row, and a
   captured argument records the source span it was parsed from. */

static List _invocation_arguments(
  Compiler c, List definition, Token invocation) {
  if (_bare(invocation, definition)) return %(args);
  Array arguments = [];
  // The first Param hole opens one scope for the rest of the arguments.
  int parameter_scope = 0;
  defer { if (parameter_scope) c.sym.pop_scope(); }
  c.expect(<(>);
  List descriptors = definition.assoc(<parameters>);
  for (List nodes = descriptors; nodes; nodes = nodes.cdr()) {
    List hole = nodes.car();
    Symbol kind = hole.assoc(<kind>);
    if (kind == <param> && !parameter_scope) {
      c.sym.push_new_scope();
      parameter_scope = 1;
    }
    arguments.push(_argument_row(c, hole, kind));
    if (nodes.cdr() && c.peek(0) != <)>) _argument_separator(c, kind);
  }
  if (c.peek(0) != <)>) {
    if (c.peek(0) == <,>) c.next();
    c.report_error(
      <parse>, "macro invocation has too many arguments",
      c.token, NULL);
  }
  c.expect(<)>);
  return %(args @{arguments.list_free()});
}

/* The arguments one hole captures: one, or a comma-separated sequence. A
   MatchRow hole also takes the directives around its rows. */
static List _argument_row(Compiler c, List hole, Symbol kind) {
  int sequence = hole.assoc(<sequence>);
  Array captured = [];
  if (c.peek(0) == <)> && !sequence)
    c.report_error(
      <parse>, "macro invocation has too few arguments",
      c.token, NULL);
  if (c.peek(0) != <)>) loop {
    _row_directives(c, kind, captured);
    Token first = c.token;
    Var argument = _parse_argument(c, kind);
    if (kind != <name>)
      argument = _capture_source(c, argument, first, c.token);
    captured.push(argument);
    if (!sequence || !c.test(<,>)) break;
  }
  _row_directives(c, kind, captured);
  return _capture_row(c, hole, captured.list_free());
}

static void _row_directives(Compiler c, Symbol kind, Array captured) {
  if (kind == <match-row> && c.token != c.directives_taken)
    foreach (List directive, c.leading_preproc()) captured.push(directive);
}

/* `in` may separate a declaration from what follows, as in
   `foreach (String line in lines)`. Before a literal it scans as a name,
   which cannot follow a declaration either. */
static void _argument_separator(Compiler c, Symbol kind) {
  if (kind == <decl> && (c.peek(0) == <in> || c.at_word("in"))) c.next();
  else c.expect(<,>);
}

static Var _parse_argument(Compiler c, Symbol kind) {
  if (!kind) return c.parse_assignment();
  switch (kind) {
    case <expr>:       return c.parse_assignment();
    case <type>:       return c.parse_type_name();
    case <named-type>: return c.parse_named_type();
    case <decl>:       return c.parse_declaration_argument();
    case <decl-row>:   return c.parse_declarator_argument();
    case <function>:   return c.parse_function_definition();
    case <param>:      return c.parse_parameter();
    case <block>:      return c.parse_block_item();
    case <field>:      return c.parse_field(%(struct ()));
    case <enumerator>: return c.parse_enumerator(c.aggregate_type);
    case <map-entry>:  return c.parse_map_entry();
    case <match-row>:  return c.parse_match_row_argument();
    case <unit>:       return c.parse_top_level();
    case <name>:       return _name_argument(c);
    case <literal>:    return _literal_argument(c);
  }
  c.report_error(
    <macro>, "macro argument has no parsing contract",
    c.token, NULL);
}

static Var _name_argument(Compiler c) {
  if (c.macro_holes && c.peek(0) == <$>) return _parse_hole(c, <name>);
  if (c.peek(0) != <ident>)
    c.report_error(
      <parse>, "Name macro argument requires an identifier",
      c.token, NULL);
  String spelling = c.token.text;
  c.next();
  // A visible template local passes its identity, which each expansion
  // renames.
  Map locals = c.macro_holes ? c.macro_definition_locals() : NULL;
  List local = locals != NULL
             ? c.sym.lookup(%($spelling), NULL) : NULL;
  return local && local in locals ? local : spelling;
}

static Var _literal_argument(Compiler c) {
  if (c.macro_holes && c.peek(0) == <$>) return c.parse_assignment();
  return c.parse_atomic_literal();
}

static Var _capture_source(
  Compiler compiler, Var syntax, Token first, Token after) {
  if (compiler.macro_holes || syntax is not <list> ||
      syntax.is_nil() || !first) return syntax;
  Token last = _previous_source_token(compiler, after);
  if (!last || last < first) return syntax;
  int end = last.pos + last.len;
  String file = compiler.source_path(
    compiler.filename ? compiler.filename : "<stdin>");
  List source = %(source $file ${first.pos} $end);
  return %(src $source $syntax);
}

static Token _previous_source_token(Compiler compiler, Token after) {
  Token first = (void *) compiler.tokenizer.tokens;
  if (!after || after <= first) return NULL;
  Token token = after - 1;
  while (token > first &&
         (token.type == <space> || token.type == <comment> ||
          token.type == <preproc>)) token--;
  return token;
}

/* A Block decorator's Name arguments are referenced in the block's scope,
   which opens before the arguments are read. */
static void _bind_name_arguments(
  Compiler compiler, List definition, List arguments) {
  List parameters = definition.assoc(<parameters>);
  List captures = arguments.cdr();
  while (parameters) {
    List parameter = parameters.car();
    if (parameter.assoc(<kind>) == <name>) {
      Var names = captures.car().list().assoc(<value>);
      List values = parameter.assoc(<sequence>).int()
                  ? names : %($names);
      foreach (String name, values) compiler.sym.reference(%($name), NULL);
    }
    parameters = parameters.cdr();
    captures = captures.cdr();
  }
}

/* capture rows

   A capture row keeps an argument's exact source apart from its syntax
   projections. Forwarding a template's own projection rebuilds the row it
   came from, with its Unit construction requirements, and assigns no
   source text to generated syntax. */

static List _capture_row(Compiler compiler, List hole, List sources) =>
  _capture_row_project(compiler, hole, sources, 0);

/* `retain` keeps each source as the syntax it is and forwards nothing. */
static List _capture_row_project(
  Compiler compiler, List hole, List sources, int retain) =>
  hole.assoc(<sequence>).int()
    ? _sequence_row(compiler, sources, retain)
    : _scalar_row(compiler, sources, retain);

/* A forwarded projection contributes its own sources, values, and
   construction requirements. */
static List _sequence_row(Compiler compiler, List sources, int retain) {
  Array captured_sources = [], values = [], construction = [];
  foreach (Var captured, sources) {
    List forwarded = retain ? NULL : _forwarded_capture(compiler, captured);
    match (forwarded)
      case %(capture (source *forwarded_sources)
                     (value *forwarded_values) ? ? *required): {
        foreach (Var item, forwarded_sources) captured_sources.push(item);
        foreach (Var item, forwarded_values) values.push(item);
        foreach (Var item, required) construction.push(item);
        continue;
      }
    captured_sources.push(captured);
    values.push(retain ? captured : _source_unwrap(captured));
  }
  return _capture_layout(
    1, %(source @{captured_sources.list_free()}),
    %(value @{values.list_free()}), NULL, NULL, construction.list_free());
}

/* One source may be a forwarded projection. Any other number of sources
   keeps the sequence layout. */
static List _scalar_row(Compiler compiler, List sources, int retain) {
  int singular = sources && !sources.cdr();
  Var source = singular ? sources.car() : sources;
  if (singular && !retain) {
    List forwarded = _forwarded_capture(compiler, source);
    if (forwarded) return forwarded;
  }
  Var value = retain ? source : _source_unwrap(source);
  List values = value is <list> ? value : NULL;
  if (!singular)
    return _capture_layout(
      1, %(source @sources), %(value @values), NULL, NULL, NULL);
  Var expression = _identifier_expression(value);
  return _capture_layout(
    0, %(source $source), %(value $value), %(expression $expression),
    %(splice @values), NULL);
}

static Var _identifier_expression(Var value) {
  if (value is <string>) return %(expr () (ident $value));
  if (value is <list> && !value.is_nil() &&
      binding_identity_try_parts(value, NULL, NULL))
    return %(expr () (ident $value));
  return value;
}

/* The row of a projection a template forwards as an argument. A Unit
   hole's source stands for each of its projections. */
static List _forwarded_capture(Compiler compiler, Var captured) {
  List hole = _forwarded_hole(compiler, captured);
  if (!hole) return NULL;
  Var source = _hole_key(hole, "source");
  Symbol kind = hole.assoc(<kind>);
  if (kind == <unit>)
    return _capture_layout(
      0, %(source $source), %(value $source), %(expression $source),
      %(splice), %(${_hole_key(hole, "construction")}));
  if (kind != <expr> && kind != <name>) return NULL;
  return _capture_layout(
    0, %(source $source), %(value ${_hole_key(hole, "value")}),
    %(expression ${_hole_key(hole, "expression")}),
    %(splice ${_hole_key(hole, "splice")}), NULL);
}

/* The hole whose projection binder `captured` is, when a template passes
   one of its own projections as an argument. */
static List _forwarded_hole(Compiler compiler, Var captured) {
  if (!compiler.macro_holes || captured is not <list> || captured.is_nil())
    return NULL;
  Var direct;
  match (captured) {
    case %(expr (<macro-expr>)
           (macro-bind ?slot)): direct = slot;
    case %(macro-bind ?): direct = captured.list().cadr();
  }
  if (direct is void) return NULL;
  String spelling = direct.str(), prefix = _forwarded_prefix(spelling);
  if (!prefix) return NULL;
  return _hole_record(compiler, Atom.intern(spelling[prefix.len():]));
}

static String _forwarded_prefix(String spelling) {
  foreach (String prefix, forwarded_prefixes)
    if (spelling.startswith(prefix)) return prefix;
  return NULL;
}

/* Forwarding recognizes the projection binders _capture_pattern creates, so
   the accepted prefixes come from _replacement_binder; <?> supplies its
   empty author name. */
static List _forwarded_prefix_list(void) {
  Array prefixes = [];
  Map seen = {};
  foreach (String projection, %("expression" "value" "source" "splice"))
    for (int sequence = 0; sequence <= 1; sequence++) {
      String prefix = _replacement_binder(<?>, projection, sequence).str();
      if (prefix in seen) continue;
      seen[prefix] = 1;
      prefixes.push(prefix);
    }
  return prefixes.list_free();
}

static List forwarded_prefixes = _forwarded_prefix_list();

/* `(src (source FILE BEGIN END) SYNTAX)` records one complete caller argument
   or decorator target. Constructed syntax can reproduce that List shape, so
   source access trusts only captured syntax identities registered for the
   active expansion. Forwarding preserves the registered capture. */
static int _source_capture_parts(Var value, List &?source, Var &?syntax) {
  match (value)
    case %(src ?record ?captured): {
      if (source) source = record;
      if (syntax) syntax = captured;
      return 1;
    }
  return 0;
}

static Var _source_unwrap(Var value) {
  if (value is not <list> || value.is_nil()) return value;
  return value.list().search_replace(%(src ? ?syntax), <?syntax>);
}

/* invocations at syntax positions

   A claimed invocation at file, block, statement, field, enumerator, or
   map-entry position parses its arguments; a decorator also parses the
   target that follows it. */

/** Parses a direct or keyword-alias macro at the requested syntax position.
    Returns NULL without consuming a macro hole or an invocation that
    `macro_starts_target_at` does not claim; template parsing returns a
    deferred `(seq (macro-invoke ...))`, and ordinary parsing returns the bound
    expansion.
*/
List Compiler.try_parse_macro_target_at(Compiler c, AstPos position) {
  if (c.macro_holes && c.peek_macro_hole()) return NULL;
  Token invocation = c.token;
  List definition = _take_invocation(c, position);
  return definition ? _invoke_at(c, definition, invocation, position) : NULL;
}

static List _invoke_at(
  Compiler c, List definition, Token invocation, AstPos position) {
  if (definition.assoc(<kind>) == <decorator>)
    return _decorate(c, definition, invocation, position);
  _check_position(c, definition, invocation, position);
  return _invoke_definition(c, definition, invocation, position);
}

/* A macro's result must fit where it is invoked; a Declaration result also
   fits at file scope. */
static void _check_position(
  Compiler c, List definition, Token invocation, AstPos position) {
  Symbol kind = definition.assoc(<kind>);
  const MacroPos *place = _position(position);
  if (kind == place.kind || (kind == <decl-unit> && position == AST_UNIT))
    return;
  Atom name = definition.assoc(<name>);
  String spelling = name.str(), result_kind = _kind_spelling(kind);
  String message =
    %"macro '$spelling' has result kind $result_kind and cannot be " +
    %"invoked at ${place.description}";
  c.report_error(<macro>, message, invocation, NULL);
}

/* Invocation parsing and expansion share one semantic transaction. Empty
   generated syntax and raised diagnostics therefore cannot leave provisional
   bindings, enumerators, statics, or generated-name state behind. */
static List _invoke_definition(
  Compiler compiler, List definition, Token invocation, AstPos position) {
  int deferred = !!compiler.macro_holes;
  SymTxn transaction = compiler.begin_semantic_transaction();
  defer transaction.rollback();
  List input = _invocation_arguments(compiler, definition, invocation);
  if (_position(position).semicolon) compiler.expect(<;>);
  List node = _invocation_node(compiler, definition, input, invocation);
  List result = deferred ? %(seq $node) :
    compiler.bind_syntax(node, position, compiler.return_type);
  if (result.car() != <seq> || result.len() != 1 ||
      transaction.local_macros_changed()) transaction.commit();
  return result;
}

/* Inside a template the node names its definition as the expansion will
   find it: a definition that is itself template syntax by value, a local
   macro by its local name, and any other macro by name. */
static List _invocation_node(
  Compiler compiler, List definition, List input, Token invocation) {
  Var stored = definition;
  Var site = invocation;
  if (compiler.macro_holes) {
    stored = _stored_reference(definition);
    site = <m-invoke>;
  }
  return %(macro-invoke $stored $input $site);
}

static Var _stored_reference(List definition) {
  if (definition.assoc(<template>)) return %(!quote $definition);
  if (definition.assoc(<local>).int())
    return %(local-macro ${definition.assoc(<name>)});
  return definition.assoc(<name>);
}

/* decorators

   A decorator application parses the decorator's arguments and then its
   target. Parsing the target can publish symbols before the replacement is
   known, so one semantic transaction stages the target and the expansion
   and a rejection rolls both back. */

/* One decorator application. A Block decorator standing before a
   file-scope function decorates that function's body, so one spelling
   covers a statement and a whole function; `function` holds the function
   then. */
typedef struct Decoration {
  Compiler c, List definition, function, Token invocation, start;
  AstPos position, Symbol kind;
} Decoration;

static List _decorate(
  Compiler c, List definition, Token invocation, AstPos position) {
  Decoration d = {
    .c = c, .definition = definition, .invocation = invocation,
    .position = position, .kind = definition.assoc(<target>)};
  int deferred = !!c.macro_holes;
  if (!d.on_body() && _result_kind(definition) != _position(position).kind)
    d.misplaced();
  SymTxn transaction = c.begin_semantic_transaction();
  defer transaction.rollback();
  int block_scope = !c.macro_holes && d.kind == <block>;
  if (block_scope) c.sym.push_new_scope();
  defer if (block_scope) c.sym.pop_scope();
  List node = d.node(d.arguments(block_scope));
  if (deferred) {
    transaction.commit();
    return %(seq $node);
  }
  List result = d.bind(node);
  $let(c.token, invocation) {
    transaction.commit();
  }
  return result;
}

static int Decoration.on_body(Decoration *d) =>
  d.kind == <block> && d.position == AST_UNIT;

static void Decoration.misplaced(Decoration *d) {
  Atom name = d.definition.assoc(<name>);
  String spelling = name.str(), target = _kind_spelling(d.kind);
  d.c.report_error(
    <macro>,
    %"decorator '$spelling' targets $target syntax and cannot be used here",
    d.invocation, NULL);
}

static List Decoration.arguments(Decoration *d, int block_scope) {
  Compiler c = d.c;
  List definition = d.definition;
  List arguments = _invocation_arguments(c, definition, d.invocation);
  if (block_scope) _bind_name_arguments(c, definition, arguments);
  if (c.peek(0) == <;>)
    c.report_error(
      <macro>, "decorator application must not end with ';'",
      d.invocation, %(${_definition_note(definition)}));
  if (c.peek(0) == <eof>) {
    Atom name = definition.assoc(<name>);
    String spelling = name.str();
    c.report_error(
      <macro>,
      %"decorator '$spelling' requires a following target",
      d.invocation, %(${_definition_note(definition)}));
  }
  return arguments;
}

static List Decoration.node(Decoration *d, List arguments) {
  Compiler c = d.c;
  d.start = c.token;
  List target = d.target();
  if (d.position == AST_STATEMENT) target = c.anchor_origin(target, d.start);
  List target_capture = d.capture(target);
  List input = %(
    target $arguments
    $target_capture
  );
  return _invocation_node(c, d.definition, input, d.invocation);
}

static List Decoration.target(Decoration *d) {
  Compiler c = d.c;
  if (d.on_body()) {
    d.function = c.parse_function_definition();
    match (d.function) case %(function ? ? ?body): return body;
    return NULL;
  }
  if (d.kind == <function>) return c.parse_function_target();
  if (d.kind == <named-type>) return c.parse_named_type();
  return _positional_target(c, d.position);
}

static List _positional_target(Compiler c, AstPos position) {
  switch (position) {
    case AST_UNIT:       return c.parse_top_level();
    case AST_BLOCK: case AST_STATEMENT:
      return c.parse_governed(position);
    case AST_FIELD:      return c.parse_field(c.aggregate_type);
    case AST_ENUMERATOR: return c.parse_enumerator(c.aggregate_type);
    case AST_MAP_ENTRY:  return c.parse_map_entry();
    default: __builtin_unreachable();
  }
}

/* The target's capture row. A public Unit target of one item also carries
   that item as the construction the template requires. */
static List Decoration.capture(Decoration *d, List target) {
  Compiler c = d.c;
  List targets = target.car() == <seq> ? target.cdr() : %($target);
  Array captured_targets = [];
  foreach (Var item, targets)
    captured_targets.push(_capture_source(c, item, d.start, c.token));
  List captured = captured_targets.list_free();
  List target_capture = _capture_row(
    c, d.definition.assoc(<targetp>), captured);
  if (d.kind == <unit> && !_private_target(c, target) &&
      captured && !captured.cdr())
    target_capture = target_capture.append(%((construct ${captured.car()})));
  return target_capture;
}

/* Visibility comes from a private section or from a static declaration,
   seen through a lone `seq` and a foreign alias. */
static int _private_target(Compiler c, List target) {
  int private_target = c.source_private > 0;
  List visibility_target = target;
  match (visibility_target)
    case %(seq ?only): visibility_target = only;
  match (visibility_target)
    case %(falias ?declaration ?): visibility_target = declaration;
  match (visibility_target)
    case %((!or function declare typedef) ?type *):
      private_target |= type.type().is_static();
  return private_target;
}

static List Decoration.bind(Decoration *d, List node) {
  Compiler c = d.c;
  if (!d.on_body()) return c.bind_syntax(node, d.position, c.return_type);
  return _bind_body(c, node, d.function);
}

/* The body was bound with the function's own result type; bind the
   produced items with it too, so a `return` that needs a conversion still
   gets one. */
static List _bind_body(Compiler c, List node, List decorated) {
  Type declared = _declared_result(decorated);
  List result = NULL;
  $let(c.return_type, declared) {
    result = c.bind_syntax(node, AST_BLOCK, c.return_type);
  }
  List items = result.car() == <seq> ? result.cdr() : %($result);
  match (decorated) case %(function ?rtype ?declarator ?):
    result = %(seq (function $rtype $declarator (block @items)));
  return result;
}

static Type _declared_result(List decorated) {
  Type declared = NULL;
  match (decorated) case %(function ?rtype ?declarator ?): {
    List declaration = %(declare $rtype (bindings $declarator));
    match (declaration.type_from_ast())
      case %((func *) *result_type):
        declared = result_type.type().declared();
  }
  return declared;
}

/* expression invocations

   In an expression, a `$` name without arguments is a Macro value, and a
   `$` call of a function is an explicit meta call. An Expression macro or
   decorator becomes a `macro-invoke` node that binding expands. */

/** Parses and resolves a direct or keyword-alias expression macro.
    Returns NULL without consuming an identifier that is not an applicable
    alias; a direct `$` invocation must resolve to a visible expression form.
*/
List Compiler.try_parse_macro_expression(Compiler c) {
  Token invocation = c.token;
  if (c.peek(0) == <$>) {
    List value = _named_macro_value(c, invocation);
    if (value) return value;
  }
  if (c.peek(0) == <$> && !_peek_invocation(c))
    return _parse_meta_call(c, invocation);
  List definition = _take_invocation(c, AST_EXPRESSION);
  if (!definition) return NULL;
  return c.resolve_expression(
    _expression_invocation(c, definition, invocation), invocation);
}

/* Returns the Macro value a `$` name without arguments names. Otherwise the
   cursor returns to the `$`. */
static List _named_macro_value(Compiler c, Token invocation) {
  Atom name = _name(c);
  if (c.peek(0) != <(>) {
    List value = _macro_value(c, name);
    if (value) return value;
  }
  c.token = invocation;
  return NULL;
}

static List _parse_meta_call(Compiler c, Token invocation) {
  c.next();
  List callee = c.parse_variable();
  Type signature = callee.cadr();
  if (!signature.is_function()) {
    c.token = invocation;
    Atom name = _name(c);
    (void) _lookup(c, name, invocation);
  }
  Array arguments = _meta_arguments(c, signature.car().list().cadr());
  Type result = c.macro_holes ? %(<macro-expr>) : signature.cdr();
  /* Inside a `meta` body the whole body runs at compile time, so a `$`
     call there is an ordinary call. */
  Symbol head = c.meta_body && !c.macro_holes ? <call> : <meta-call>;
  List call = %(expr $result ($head $callee
    (args @{arguments.list_free()})));
  return c.resolve_expression(call, invocation);
}

/* Each argument converts to its parameter's type, except in a template. */
static Array _meta_arguments(Compiler c, List parameters) {
  Array arguments = [];
  c.expect(<(>);
  if (c.peek(0) != <)>) loop {
    List argument = _meta_argument(c);
    if (parameters && !c.macro_holes)
      argument = c.convert_expression(argument, parameters.car());
    parameters = parameters.cdr();
    arguments.push(argument);
    if (!c.test(<,>)) break;
  }
  c.expect(<)>);
  return arguments;
}

/* A hole passed alone passes the value it captures, and a sequence hole
   passes its captured items as one List. */
static List _meta_argument(Compiler c) {
  List hole = c.peek_macro_hole();
  int direct = hole && (c.peek(2) == <,> || c.peek(2) == <)>);
  if (direct && hole.assoc(<sequence>).int()) {
    c.expect(<$>);
    c.next();
    return %(expr ("List") (meta-cap (${_hole_key(hole, "value")})));
  }
  Symbol kind = hole ? hole.assoc(<kind>) : 0;
  List argument = direct
    ? %(expr (<macro-expr>) ${_parse_hole(c, kind ? kind : <argument>)})
    : c.parse_assignment();
  if (hole && argument.match(%(expr ? (macro-bind ?)))) {
    Atom projection = _replacement_binder(hole.assoc(<binder>), "value", 0);
    argument = %(expr ("List") (meta-cap $projection));
  }
  return argument;
}

static List _expression_invocation(
  Compiler compiler, List definition, Token invocation) {
  Symbol kind = definition.assoc(<kind>);
  if (kind == <decorator> && definition.assoc(<target>) == <expr>)
    return _expression_decorator(compiler, definition, invocation);
  if (compiler.meta_body && (kind == <unit> || kind == <block-item>))
    return _template_call(compiler, definition);
  List arguments = _invocation_arguments(compiler, definition, invocation);
  if (kind != <expression>) _not_expression(compiler, definition, invocation);
  List node = _invocation_node(compiler, definition, arguments, invocation);
  return %(expr (<macro-expr>) $node);
}

/* In a `meta` body, invoking a Unit or Statement macro is a template call,
   whose syntax the meta function builds when it runs. */
static List _template_call(Compiler compiler, List definition) {
  Array arguments = [];
  compiler.expect(<(>);
  foreach (List hole, definition.assoc(<parameters>).list()) {
    if (arguments.len()) compiler.expect(<,>);
    arguments.push(compiler.parse_assignment());
  }
  compiler.expect(<)>);
  Var stored = definition.assoc(<local>).int()
    ? definition : definition.assoc(<name>);
  return %(expr ("List") (tpl-call $stored
    (args @{arguments.list_free()})));
}

static void _not_expression(
  Compiler compiler, List definition, Token invocation) {
  Symbol kind = definition.assoc(<kind>);
  String spelling = definition.assoc(<name>).str();
  String subject = kind == <decorator>
    ? %"decorator '$spelling'"
    : %"macro '$spelling'";
  compiler.report_error(
    <macro>, %"$subject cannot be invoked in an expression",
    invocation,
    kind == <decorator>
      ? %(${_definition_note(definition)})
      : NULL
  );
}

static List _expression_decorator(
  Compiler c, List definition, Token invocation) {
  List arguments = _invocation_arguments(c, definition, invocation);
  if (c.peek(0) == <;> || c.peek(0) == <eof>) {
    String spelling = definition.assoc(<name>).str();
    c.report_error(
      <macro>,
      %"decorator '$spelling' requires a following expression",
      invocation, %(${_definition_note(definition)}));
  }
  List target = c.parse_macro_expression_target();
  List input = %(
    target $arguments
    ${_capture_row(c, definition.assoc(<targetp>), %($target))}
  );
  List node = _invocation_node(c, definition, input, invocation);
  return %(expr (<macro-expr>) $node);
}

/* expansion

   Expanding an invocation node matches its capture rows against the
   definition's pattern, adds a binding for each fresh name and member
   hole, fills the template, and binds the result at the invocation's
   position with the invocation as its origin. */

/* One expansion. `direct` holds the bindings that fresh names and member
   holes add to the pattern's captures. */
typedef struct Expansion {
  Compiler c, List definition, input, template, direct, Token invocation;
} Expansion;

/** Expands canonical macro capture rows and binds the result at `position`.
    `stored` is a `macrodef` or visible macro name. The active expansion stack
    supplies Lisp bindings, source location, and recursion checks; the
    definition's fresh rows allocate invocation-local names. This method does
    not begin a semantic transaction.
*/
List Compiler.expand_macro_invocation_node(
  Compiler c, Var stored, List arguments, Token invocation, AstPos position) {
  Expansion x = {
    .c = c, .definition = _stored_definition(c, stored, invocation),
    .input = arguments, .invocation = invocation};
  int block_scope = x.definition.assoc(<kind>) == <decorator> &&
                    x.definition.assoc(<target>) == <block>;
  if (block_scope) c.sym.push_new_scope();
  defer if (block_scope) c.sym.pop_scope();
  $let(c.token, invocation) {
    x.check();
    c.macro_count++;
    List result = NULL;
    $let(c.macro_stack, c.macro_stack) {
      result = x.bind(position);
    }
    return result;
  }
}

/* The definition a node names: a visible macro, a local macro, or a Macro
   value whose references bind in this unit. */
static List _stored_definition(Compiler c, Var stored, Token invocation) {
  List definition = NULL;
  if (stored.is_atom())
    definition = _lookup(c, Atom.intern(stored.str()), invocation);
  else match (stored)
    case %(local-macro (!is ?name type atom)):
      definition = c.sym.lookup_macro(name);
  if (!definition) definition = _macro_value_bindings(c, stored);
  return definition;
}

/* An identical recursive expansion, nesting deeper than 64, or more than
   10000 expansions stops the compile. */
static void Expansion.check(Expansion *x) {
  Compiler c = x.c;
  foreach (List active, c.macro_stack) {
    (List prior, List prior_input, Var bindings, Var site) = active;
    (void) bindings, (void) site;
    if (prior.equal(x.definition) && prior_input.equal(x.input)) x.recursion();
  }
  if (c.macro_stack.len() >= 64) x.too_deep();
  if (c.macro_count >= 10000)
    c.report_error(
      <macro>, "macro expansion count exceeds 10000",
      x.invocation, NULL);
}

static void Expansion.recursion(Expansion *x) {
  Atom name = x.definition.assoc(<name>);
  String spelling = name.str();
  List captured = x.input.search_replace(
    %(capture (source ?syntax) *), <?syntax>);
  Var shown = _source_unwrap(captured);
  x.c.report_error(
    <macro>, %"identical recursive expansion of '$spelling'",
    x.invocation,
    %(${_definition_note(x.definition)} "input: ${shown.repr()}"));
}

static void Expansion.too_deep(Expansion *x) {
  /* Compiler-generated applications can have no invocation token. */
  List first = x.c.macro_stack.last().list().car();
  String first_note = %"first expansion: ${_definition_note(first)}";
  x.c.report_error(
    <macro>, "macro expansion depth exceeds 64", x.invocation,
    %(${_definition_note(x.definition)} $first_note));
}

/* Pushes this expansion's frame on the macro stack, fills the template,
   and binds the result. A failed match binds nothing. */
static List Expansion.bind(Expansion *x, AstPos position) {
  Compiler c = x.c;
  List old_stack = c.macro_stack;
  x.template = _template(c, x.definition);
  List fresh_input = x.fresh_names(old_stack);
  List match_input = fresh_input
    ? x.input.append(%((fresh @fresh_input))) : x.input;
  List replacement_bindings = match_input.match(
    x.definition.assoc(<pattern>));
  int matched = !!replacement_bindings;
  replacement_bindings = replacement_bindings.append(x.direct);
  List lisp_bindings = _lisp_bindings(replacement_bindings);
  c.macro_stack = %(
    (${x.definition} ${x.input} $lisp_bindings ${x.invocation}) @old_stack
  );
  int expansion_origin = c.record_origin(x.invocation);
  Ast constructed = matched ? x.construct(replacement_bindings) : NULL;
  List result = NULL;
  $let(c.origin, expansion_origin) {
    result = c.bind_syntax(
      matched ? constructed : void,
      position, c.return_type);
  }
  return result;
}

/* Allocates each fresh name of the definition. A name compile-time Lisp
   reads joins the match input as a Name capture row; the others, with the
   member holes, bind directly. Returns the Name rows. */
static List Expansion.fresh_names(Expansion *x, List old_stack) {
  Compiler c = x.c;
  Map file_locals = {};
  // The outermost active row's fourth field is its invocation token.
  Token root = old_stack ? old_stack.last().list()[3] : x.invocation;
  if (c.sym.at_file_scope()) _file_scope_locals(%(${x.template}), file_locals);
  Array fresh_values = [];
  foreach (List fresh, x.definition.assoc(<fresh>).list()) {
    Var (binder, spelling, lisp) = fresh;
    List binding = _introduced_binding(
      c, spelling.str(), binder in file_locals ? root : NULL);
    if (lisp.int()) {
      List hole = _hole(binder, <name>, 0);
      fresh_values.push(_capture_row(c, hole, %($binding)));
    }
    else {
      c.semantic_binding_facts()[%(source-spelling $binding)] =
        spelling.str();
      x.direct = cons(%($binder $binding), x.direct);
    }
  }
  List members = _member_bindings(
    c, x.definition.assoc(<parameters>), x.input);
  x.direct = x.direct.append(members);
  return fresh_values.list_free();
}

/* The filled template. A Declaration result, or a NamedType decorator's,
   becomes one declaration bundle. */
static Ast Expansion.construct(Expansion *x, List replacement_bindings) {
  List definition = x.definition;
  Ast constructed = x.template.replace(replacement_bindings);
  if (constructed &&
      (definition.assoc(<kind>) == <decl-unit> ||
       definition.assoc(<target>) == <named-type>)) {
    List rows = constructed.car() == <seq>
              ? constructed.cdr() : %($constructed);
    constructed = %(declaration-bundle (rows @rows));
  }
  return constructed;
}

static List _template(Compiler c, List definition) {
  List template = definition.assoc(<template>);
  if (definition.assoc(<open>) is void) return template;
  Map replacements = {}, natives = {};
  _open_references(c, template, replacements, natives);
  return _open_template(c, template, replacements, natives);
}

/* An open definition binds its free references in the unit that applies
   it. A value resolves to the unit's global declaration; a callee the unit
   does not declare becomes a native call with the result type recorded
   where the macro was defined; a typedef base resolves in the base scope.
   Hole binders and introduced locals are not references. */
static void _open_references(
  Compiler c, Var value, Map replacements, Map natives) {
  if (value is not <list> || value.is_nil()) return;
  match (value)
    case %(expr ?(List type) ${$source_identifier_content(%(?binding))}): {
      String spelling = NULL;
      if (!binding_identity_try_parts(binding, NULL, spelling)) return;
      List target = c.sym.resolve_global(%($spelling), NULL);
      if (target) replacements[binding] = target;
      else if (type && type.type().is_function())
        natives[binding] =
          %($spelling ${type.type().apply().canonicalize()});
      else replacements[binding] = c.sym.reference_global(%($spelling));
      return;
    }
  foreach (Var child, value.list())
    _open_references(c, child, replacements, natives);
}

/* Rebuilds the template once with what `_open_references` found and without
   origin markers. A replaced reference is not revisited, and a callee finds
   its native under its replacement. */
static Var _open_template(
  Compiler c, Var value, Map replacements, Map natives) {
  Var found;
  if (value is not <list> || value.is_nil()) return value;
  if (replacements.try_get(value, found)) return found;
  Macro called = $called;
  match (value) {
    case %(at m-origin ?node):
      return _open_template(c, node, replacements, natives);
    case called(?callee, *arguments):
      if (value.list().car() == <expr>)
        match (callee) case %(expr ?
            ${$source_identifier_content(%(?binding))}): {
          Var bound = replacements.getdefault(binding, binding);
          if (natives.try_get(bound, found)) {
            Var (spelling, result) = found;
            List args = _open_template(c, arguments, replacements, natives);
            return %(expr $result (call $spelling (args @args)));
          }
        }
    case %(decl ?base ?declarators): {
      Type resolved = base is <list> && base.type().is_bare_typedef_name()
        ? c.sym.resolve_base_type(base) : NULL;
      if (resolved)
        return %(decl $resolved
                 ${_open_template(c, declarators, replacements, natives)});
    }
  }
  Var child;
  $ast.rewrite_children(
    value, child, _open_template(c, child, replacements, natives));
}

/* A Name hole in a member position supplies the captured spelling, so a
   template local passed there keeps the spelling its source wrote. */
static List _member_bindings(Compiler c, List parameters, List input) {
  List captures = NULL, bindings = NULL;
  match (input) {
    case %(args *rows): captures = rows;
    case %(target (args *rows) ?): captures = rows;
  }
  foreach (List parameter, parameters) {
    List capture = captures.car();
    captures = captures.cdr();
    if (parameter.assoc(<kind>) != <name> ||
        parameter.assoc(<sequence>).int())
      continue;
    Var value = capture.assoc(<value>), spelling;
    if (value is <list> &&
        c.semantic_binding_facts().try_get(
          %(source-spelling $value), spelling))
      value = spelling;
    Var member = _hole_key(parameter, "member");
    bindings = cons(%($member $value), bindings);
  }
  return bindings;
}

/* The bindings compile-time Lisp sees: the author's binders, without the
   `__macro_` binders the compiler makes. */
static List _lisp_bindings(List bindings) {
  Array result = [];
  foreach (List pair, bindings) {
    Var binder = pair.car();
    if (binder.is_binder() &&
        !binder.str().startswith("?__macro_") &&
        !binder.str().startswith("*__macro_"))
      result.push(pair);
  }
  return result.list_free();
}

/** Resolves a stored macro invocation marker to its source token.
    Nested template markers use the active expansion's invocation; unresolved
    markers return NULL.
*/
Token Compiler.macro_invocation_site(Compiler compiler, Var site) {
  if (site is <token>) return site;
  if (site != <m-invoke> || !compiler.macro_stack) return NULL;
  List active = compiler.macro_stack.car();
  (Var definition, Var input, Var bindings, Token invocation) = active;
  (void) definition, (void) input, (void) bindings;
  return invocation;
}

/* expansion names

   A fresh name gets a private spelling. At file scope a declaration with
   external or no linkage can reach another unit through a header or an
   interface, so its spelling is stable: collection and full parsing expand
   the same invocation to the same spelling. */

static List _introduced_binding(
  Compiler compiler, String source, Token root) =>
  compiler.sym.introduce(
    root ? _file_scope_name(compiler, root, source)
         : compiler.fresh_name(%"macro_$source"));

/* The spelling names the owning unit and the root invocation's offset, and
   counts repeats of the same name there. */
static String _file_scope_name(Compiler c, Token root, String source) {
  String key = %"macro:${_scope_owner(c)}:${root.pos}:$source";
  Var stored;
  int count = c.names.counters.try_get(key, stored) ? stored : 0;
  c.names.counters[key] = count + 1;
  String digest = "%08x".printf(%"$key:$count".hash());
  return %"_x2c_macro_${source}_$digest";
}

/* The unit's owner spelling, cached per file and package. */
static String _scope_owner(Compiler c) {
  List owner_key = %(${c.filename} ${c.package});
  Var cached;
  if (c.names.file_scope_owners.try_get(owner_key, cached)) return cached;
  String owner = c.filename ? _owner_spelling(c) : "";
  c.names.file_scope_owners[owner_key] = owner;
  return owner;
}

/* Home and package paths stay portable; other paths use their canonical
   absolute identity. */
static String _owner_spelling(Compiler c) {
  String path = c.canonical_path(Path.absolute(c.filename));
  String owner = home_portable_path(path);
  Var package_root = c.package ? c.package_roots[c.package] : void;
  if (package_root is not <string>) return owner;
  String prefix = %"${c.canonical_path(Path.absolute(package_root))}/";
  if (!path.startswith(prefix)) return owner;
  return %"package:${c.package}/${path[prefix.len():]}";
}

/* Collects the template locals that a file-scope row declares with external
   linkage or none: objects, functions, typedefs, tags, and enumerators. */
static void _file_scope_locals(List rows, Map locals) {
  foreach (Var row, rows) match (row) {
    case %((!or at src) ? ?inner): _file_scope_locals(%($inner), locals);
    case %(api-source ? ? ?inner): _file_scope_locals(%($inner), locals);
    case %(seq *inner): _file_scope_locals(inner, locals);
    case %(function ?type (bind ?binder ?) ?):
      if (binder.is_binder() && !type.type().is_static()) locals[binder] = 1;
    case %((!set ?kind (!or declare typedef)) ?type (bindings *rows)): {
      match (type) case %(* (!or struct union enum) ?tag *):
        if (tag.is_binder()) locals[tag] = 1;
      match (type) case %(* enum ? (*members) *):
        _file_scope_declarators(members, locals);
      if (kind == <typedef> || !type.type().is_static())
        _file_scope_declarators(rows, locals);
    }
  }
}

static void _file_scope_declarators(List declarators, Map locals) {
  foreach (Var declarator, declarators) match (declarator)
    case %(!or (bind ?binder ?) (op = (bind ?binder ?) ?)):
      if (binder.is_binder()) locals[binder] = 1;
}

/* template slots

   A slot in a template, `$(...)` or a meta call, runs while its expansion
   binds. Its value fills the slot, and a splice slot's List becomes rows. */

/** Evaluates an active template's `(macro-slot ...)` value, or a pending
    Macro value application into the invocation that expands it.
    Non-slots and slots outside an expansion are returned unchanged. A splice
    slot's `List` result is wrapped as `(seq ...)` for its syntax position.
*/
Var Compiler.evaluate_macro_slot(Compiler c, Var value) {
  if (value is not <list>) return value;
  List slot = value;
  if (slot.car() == "x2c.template") return _helper_result(c, value);
  if (slot.car() != <macro-slot>) return value;
  if (c.macro_holes || !c.macro_stack) return value;
  return _slot_value(c, slot);
}

/* A Lisp form evaluates with the active expansion's bindings, and a meta
   call runs. A construction requirement travels with an identifier the
   slot built, and a splice slot around a Unit target replaces the target
   among the items it produced. */
static Var _slot_value(Compiler c, List slot) {
  int splice = slot.cadr();
  Var form = slot.caddr();
  List active = c.macro_stack.car();
  (List definition, Var input, List bindings, Token invocation) = active;
  (void) input;
  String source_file = _definition_file(definition);
  Var required = slot.assoc(<construct>);
  Var result = form is <list>
    ? _evaluate_meta_value(c, form, invocation, 1)
    : _eval_template_form(
      c, form, bindings, invocation, source_file, required);
  result = _helper_result(c, result);
  Var construction = slot.assoc(<target>);
  if (required is not void && splice) {
    construction = required;
    result = _replace_target(result, _source_unwrap(required), required);
  }
  if (construction is not void)
    result = _constructed_identifier(result, construction);
  return splice && result is <list> ? _slot_rows(result) : result;
}

static Var _constructed_identifier(Var result, Var construction) {
  String exact = NULL;
  match (result)
    case %("x2c.ident" ?(String spelling)):
      exact = spelling;
  if (exact) return %($construction $exact);
  return result;
}

static Var _slot_rows(Var result) {
  match (result) {
    case %(code-value ? ? ?): return result;
    case %(macro-invoke ? ? ?): return %(seq $result);
    case %(seq *): return result;
  }
  return %(seq @{result});
}

/** Evaluates a macro slot and returns its syntax as a row sequence.
    `(seq ...)` contributes its children; every other result contributes one
    row.
*/
List Compiler.evaluate_macro_rows(Compiler compiler, Var value) {
  value = compiler.evaluate_macro_slot(value);
  return value is <list> && !value.is_nil() &&
         value.list().car() == <seq>
       ? value.list().cdr() : %($value);
}

/* Scratch names for one template evaluation. The count is process-wide: a
   shared parent session holds every name its filling bound, and a child
   cannot rebind an inherited one, so a count per compiler would refuse the
   second compiler that expanded the same macro. */
static unsigned long template_serial = 0;

/* Evaluates a template's Lisp form, which reads each captured binding
   through a scratch global. */
static Var _eval_template_form(
  Compiler compiler, String form, List bindings, Token invocation,
  String source_file, Var construction) {
  if (!compiler.collect_protocols) compiler.run_declaration_effects();
  _ensure_lisp(compiler);
  unsigned long serial = template_serial++;
  /* Provenance lookup uses captured Var identity. Structural equality must
     not let constructed or selected syntax acquire a caller's source text. */
  Map source_captures = _source_captures(bindings);
  List references = _bind_references(compiler, serial, bindings);
  if (references) form = _rewrite_references(form, references);
  if (construction is not void)
    form = _with_construction(compiler, serial, form, construction);
  MetaContext *context = MetaContext.current();
  $let(context.references, !!references)
  $let(context.captures, source_captures)
  $let(context.file, source_file)
  $let(context.expansion, compiler)
    return _eval_string(compiler, form, invocation);
}

/* Binds each captured value to a scratch global and returns the
   `(spelling global)` rows, newest first. */
static List _bind_references(
  Compiler compiler, unsigned long serial, List bindings) {
  List references = NULL;
  foreach (List pair, bindings) {
    if (!pair) continue;
    Var (binder, syntax) = pair;
    String spelling = binder.str()[1:];
    String temporary = %"_x2c_meta_${serial}_$spelling";
    Var unwrapped;
    if (!_source_capture_parts(syntax, NULL, unwrapped))
      unwrapped = _source_unwrap(syntax);
    compiler.macro_lisp.set_global(temporary, unwrapped);
    references = cons(%($spelling $temporary), references);
  }
  return references;
}

/* Replaces each `$name` the references bind with its scratch global. */
static String _rewrite_references(String form, List references) {
  Tokenizer tokenizer = Tokenizer.new(form, <macro-lisp>);
  tokenizer.scan();
  Buffer rewritten = $auto(Buffer.new(0));
  int copied = 0;
  Token token = tokenizer.next();
  while (token && token.type != <eof>) {
    if (token.type != <$>) {
      token = tokenizer.next();
      continue;
    }
    Token name = tokenizer.next();
    Var replacement = name && name.type == <ident>
                    ? references.assoc(name.text) : void;
    String temporary = replacement is <string> ? replacement : NULL;
    if (temporary) {
      rewritten.write_len(form + copied, token.pos - copied);
      rewritten.write(temporary);
      copied = name.pos + name.len;
      name = tokenizer.next();
    }
    token = name;
  }
  rewritten.write_len(form + copied, form.len() - copied);
  return rewritten;
}

/* `x2c.ident` in the form builds a name that carries the construction
   requirement. */
static String _with_construction(
  Compiler compiler, unsigned long serial, String form, Var construction) {
  String temporary = %"_x2c_meta_${serial}_construction";
  compiler.macro_lisp.set_global(temporary, construction);
  return %"(let ((x2c.ident (lambda (name)
      (list $temporary name)))) $form)";
}

/* The decorator target is a value to find among the produced items, so a
   comparison finds it. Interpolating it into a pattern would read a
   binder-shaped symbol inside it, such as the `*=` operator, as a sequence
   binder. A foreign alias wraps its target, so Match recognizes that
   wrapper and the comparison still owns the target. */
static Var _replace_target(Var produced, Var target, Var required) {
  if (produced is not <list>) return void;
  List produced_items = produced;
  Array items = $auto(produced_items);
  int at = produced_items.index(target);
  if (at >= 0) {
    items[at] = required;
    return items.list();
  }
  for (int i = 0; i < (int) items.len(); i++)
    match (items[i]) case %(falias ?found ?native):
      if (found == target) {
        items[i] = %(falias $required $native);
        return items.list();
      }
  return void;
}

/** Evaluates a declaration recipe after its owning source is collected.
    The callback is a Lisp name and arguments are retained canonical values.
*/
Var Compiler.evaluate_declaration_recipe(
  Compiler compiler, Atom callback, List arguments) {
  Token invocation = compiler.token;
  match (compiler.macro_stack)
    case %((? ? ? ?token) *): invocation = token;
  return _eval_template_form(
    compiler, "(apply (eval $callback) $arguments)",
    %((?callback $callback) (?arguments $arguments)),
    invocation, compiler.filename, void);
}

/* template calls and rebuilds

   Compile-time code calls a template by name with its argument values, and
   the compiler rebuilds a pending Macro value application from bound
   children without binding them again. */

/** Returns the syntax that invokes the template `stored`, a macro name
    spelled as a String or a local definition, with `values`: what a template
    call in a staged `meta` body evaluates to. */
List x2c_template_call(Var stored, List values) =>
  _sdk_template_call(
    stored is <string> ? Atom.intern(stored.str()) : stored, values);

static List _sdk_template_call(Var stored, List values) {
  Compiler c = Compiler.expanding();
  Token site = MetaContext.current().site;
  List definition = stored.is_atom() ? _lookup(c, stored, site) : stored;
  return %(macro-invoke $stored
    ${_template_arguments(c, definition, values, site, 0)}
    m-invoke);
}

/* The capture rows of a template call's values. A scalar Lisp value in an
   Expr hole lifts to an expression first. */
static List _template_arguments(
  Compiler c, List definition, List values, Token invocation,
  int retain_syntax) {
  Array rows = [];
  List holes = definition.assoc(<parameters>);
  for (; holes; holes = holes.cdr(), values = values.cdr()) {
    List hole = holes.car();
    Var value = values.car();
    if (hole.assoc(<kind>) == <expr> &&
        (value.is_integer() || value.is_floating() || value is <string> ||
         value is <symbol>))
      value = c.lift_macro_lisp_expression(value, invocation);
    List sources = hole.assoc(<sequence>).int() ? value.list() : %($value);
    rows.push(_capture_row_project(c, hole, sources, retain_syntax));
  }
  return %(args @{rows.list_free()});
}

/* A helper's result with each template call the helper left for the
   compiler replaced by its invocation. */
static Var _helper_result(Compiler c, Var value) {
  if (value is not <list> || value.is_nil()) return value;
  match (value) {
    case %(macrodef *): return value;
    case $source_literal_content(%(*)): return value;
  }
  match (value) {
    case %("x2c.template" ?stored ?(List values)): {
      stored = _helper_result(c, stored);
      values = _helper_result(c, values);
      Token site = c.macro_invocation_site(<m-invoke>);
      if (!site) site = c.token;
      MetaContext *context = MetaContext.current();
      $let(context.expansion, c)
      $let(context.site, site)
        return _sdk_template_call(
          stored is <string> ? Atom.intern(stored.str()) : stored, values);
    }
  }
  List child;
  $ast.rewrite_children(value.list(), child, _helper_result(c, child));
}

/** Rebuilds an expression from a pending Macro value application, preserving
    its established root `type`, child stage, and source wrappers. Binding,
    capture collection, hygiene, and effects do not run. */
List Compiler.rebuild_expression(Compiler c, Type type, List application) {
  List rebuilt = _rebuild(c, application, 0, NULL);
  return %(expr $type @{rebuilt.cddr()});
}

/** Rebuilds a statement template as a canonical unbraced `seq`. Bound
    children keep their identities and origins; template-origin wrappers
    are omitted because this path does not open an invocation. */
List Compiler.rebuild_statement(Compiler c, List application) =>
  _rebuild(c, application, 1, NULL);

/** Constructs a fresh function from a Unit template after lowering. The
    caller supplies its bound name and lowered children; binding does not run. */
List Compiler.rebuild_unit_function(Compiler c, List application) {
  List function = _rebuild(c, application, 1, NULL).cadr();
  match (function) case %(api-source ? ? ?inner): return inner;
  return function;
}

/** Rebuilds a bound function through a Function decorator without binding it
    again. The template keeps the target's return type and declarator. */
List Compiler.rebuild_function(Compiler c, List target, List application) =>
  _rebuild(c, application, 1, target).cadr();

/* Substitute bound syntax into a structural template without binding it.
   The caller supplies complete children and a template with no free names,
   computed slots, or nested applications. */
static List _rebuild(
  Compiler c, List application, int statement, List target) {
  (Var marker, List definition, List values) = application;
  (void) marker;
  List arguments = _template_arguments(c, definition, values, c.token, 1);
  List input = arguments;
  if (target) {
    List target_row = _capture_row_project(
      c, definition.assoc(<targetp>), %($target), 1);
    input = %(target $arguments $target_row);
  }
  List bindings = input.match(definition.assoc(<pattern>));
  List template = definition.assoc(<template>);
  foreach (List hole, definition.assoc(<parameters>).list())
    if (hole.assoc(<kind>) == <expr>) {
      Var binder = _hole_key(hole, "expression");
      template = template.search_replace(
        %(expr (<macro-expr>) (!quote $binder)), binder);
    }
  if (statement)
    template = template.search_replace(%(at m-origin ?node), <?node>);
  return template.replace(bindings);
}

/* macro values

   A `Macro` value carries a definition as run-time data, with its
   references named by spelling. Applying it binds those names in the
   applying unit, and a producer can return code with effects into the
   application. */

/** Returns the literal expression that carries `value`, a macro definition
    or one of its references, as run-time data. */
List Compiler.macro_value_literal(Compiler c, List value) =>
  c.cache_literal_list(_macro_value_names(value));

/* A Macro value names its references by spelling, so its literal does not
   depend on how this translation numbered bindings. */
static Var _macro_value_names(Var value) {
  if (value is not <list>) return value;
  String spelling = NULL;
  if (binding_identity_try_parts(value, NULL, spelling))
    return %(binding-name $spelling);
  List child;
  $ast.rewrite_children(value.list(), child, _macro_value_names(child));
}

/* An applied Macro value binds each named reference in the applying unit's
   global scope, as a cached import does. Child template calls keep their
   names, which match the value's captured children. */
static Var _macro_value_bindings(Compiler c, Var value) {
  if (value is not <list>) return value;
  match (value) {
    case %(binding-name ?(String spelling)):
      return c.sym.reference_global(%($spelling));
    case %(tpl-call *): return value;
  }
  List child;
  $ast.rewrite_children(value.list(), child, _macro_value_bindings(c, child));
}

/* NULL for a template's hole of that name or for an unknown macro. */
static List _macro_value(Compiler c, Atom name) {
  Var stored;
  if (c.macro_holes && _hole_record(c, name)) return NULL;
  if (!_try_definition(c, name, 1, stored)) return NULL;
  List cached = c.macro_value_literal(stored);
  return %(expr ("Macro") ${cached.caddr()});
}

/** Parses `case NAME(?a, *b)` where NAME selects a macro, as `$name` or as
    a `Macro` variable, into the pattern expression that recognizes code the
    macro builds. Returns NULL without consuming tokens for any other case.
*/
List Compiler.try_parse_macro_pattern(Compiler c) {
  Token saved = c.token;
  List expression = _pattern_macro(c);
  if (!expression || c.peek(0) != <(>) {
    c.token = saved;
    return NULL;
  }
  List labels = c.cache_literal_list(_pattern_labels(c));
  List callee = c.resolve_expression(
    %(expr () (ident "Macro_case_pattern")), saved);
  return c.resolve_expression(
    %(expr ("List") (call $callee (args $expression $labels))), saved);
}

/* The Macro value a `$name` or a `Macro` variable at the cursor names. */
static List _pattern_macro(Compiler c) {
  if (c.peek(0) == <$>) return _macro_value(c, _name(c));
  if (c.peek(0) != <ident>) return NULL;
  Type type = NULL;
  List binding = c.sym.lookup(%(${c.token.text}), type);
  if (!binding || !c.sym.is_named_value_type(type, "Macro")) return NULL;
  List expression = c.resolve_expression(
    %(expr $type (ident $binding)), c.token);
  c.next();
  return expression;
}

/* The `?a` and `*b` capture labels between the parentheses. */
static List _pattern_labels(Compiler c) {
  c.expect(<(>);
  Array names = [];
  if (c.peek(0) != <)>) loop {
    int sequence = c.peek(0) == <*>;
    c.expect(sequence ? <*> : <?>);
    String name = c.token.text;
    c.expect(<ident>);
    names.push(Atom.intern(%"${sequence ? "*" : "?"}$name"));
    if (!c.test(<,>)) break;
  }
  c.expect(<)>);
  return names.list_free();
}

/** Returns an anonymous macro definition as a `Macro` value. Macro values
    the body applies are captured where the literal is written, so a later
    application applies the same children.
*/
List Compiler.capture_macro_value(Compiler c, List definition) {
  List cached = c.macro_value_literal(definition);
  List literal = %(expr ("Macro") ${cached.caddr()});
  List rows = %(expr ("List") (nil));
  int captured = 0;
  foreach (List binding, definition.assoc(<captures>).list()) {
    Type type = c.semantic_binding_facts()[%(type $binding)];
    if (!c.sym.is_named_value_type(type, "Macro")) continue;
    List pair = _captured_pair(c, binding, type);
    rows = %(expr ("List")
      (cons ${c.convert_expression(pair, %("Var"))} $rows));
    captured = 1;
  }
  if (!captured) return literal;
  List callee = c.resolve_expression(
    %(expr () (ident "Macro_close")), c.token);
  return c.resolve_expression(
    %(expr ("Macro") (call $callee (args $literal $rows))), c.token);
}

/* The `(identity value)` row of one captured Macro binding. */
static List _captured_pair(Compiler c, List binding, Type type) {
  List identity = c.macro_value_literal(binding);
  List value = c.resolve_expression(%(expr $type (ident $binding)), c.token);
  return %(expr ("List")
    (cons ${c.convert_expression(identity, %("Var"))}
      (expr ("List") (cons ${c.convert_expression(value, %("Var"))}
        (expr ("List") (nil))))));
}

/** Consumes a `(code-value STAGE CODE EFFECTS)` carrier a producer returned
    into a macro value application. Effects are applied in order under the
    application's transaction, and their tokens are replaced in the code.
    `retained` reports a bound or lowered stage, which ordinary binding
    leaves untouched. Returns 0 for any other value.
*/
int Compiler.take_code_value(
  Compiler c, Var input, Var &value, int &retained) {
  match (input) case %(code-value ?(String stage) ?code ?effects): {
    Map replacements = _code_effects(c, effects);
    value = _replace_bindings(code, replacements);
    Var binder = _carrier_binder(value);
    if (binder) _unbound(c, binder.str(), c.token);
    retained = stage != "source";
    return 1;
  }
  return 0;
}

/* Applies a carrier's effects in order and returns what replaces each
   effect's token in the code. */
static Map _code_effects(Compiler c, Var effects) {
  Map replacements = {};
  foreach (List effect, effects)
    match (effect) {
      case %(new-name ?token ?(String role)):
        replacements[token] = c.sym.introduce(c.fresh_name(role));
      case %(cleanup ?token ?placed): {
        replacements[token] = placed;
        c.needs_exception = 1;
      }
      case %(early ?key ?binding ?declaration): {
        Var cached;
        if (c.names.adapters.try_get(key, cached))
          replacements[binding] = cached;
        else {
          c.add_early(_replace_bindings(declaration, replacements));
          c.names.adapters[key] = replacements[binding];
        }
      }
    }
  return replacements;
}

/* A named binder left as a carrier's code, identifier, or declarator
   after its effects were applied, or NULL. Binders elsewhere are data,
   such as a lowered match pattern, and a bare `*` or `?` is syntax. */
static Var _carrier_binder(Var value) {
  if (value.is_binder()) return value.str().len() > 1 ? value : NULL;
  if (value is not <list>) return NULL;
  match (value) {
    case $source_identifier_content(%(?name *)):
      if (name.is_binder() && name.str().len() > 1) return name;
    case %(bind ?name *):
      if (name.is_binder() && name.str().len() > 1) return name;
    case $source_literal_content(%(*)): return NULL;
    case %((!or "x2c.template" macro-invoke macrodef) *):
      return NULL;
  }
  foreach (Var child, value.list())
    if (child is <list>) {
      Var binder = _carrier_binder(child);
      if (binder) return binder;
    }
  return NULL;
}

/* compile-time Lisp

   Each Compiler initializes one Lisp session lazily, as a child of the
   shared library session when one is published. A `$(...)` form at file
   scope evaluates there, or imports a file; in an expression its value
   lifts into syntax. */

/* An `.xmacro` import parser borrows its parent's session; the parent
   Compiler frees it. Every use records the library files as dependencies,
   and a session loads them once. */
static void _ensure_lisp(Compiler compiler) {
  int loaded = compiler.macro_lisp != NULL;
  int shared = library_session != NULL, ready = loaded || shared;
  if (!loaded) {
    compiler.macro_lisp = Lisp.kernel();
    compiler.macro_lisp.adopt(library_session);
  }
  _eval_library(
    compiler, ready, "etc/init.xlisp",
    "cannot open the compile-time Lisp environment");
  _eval_library(
    compiler, ready, "etc/lisp-values.xlisp",
    "cannot open the compile-time value operations");
  _eval_library(
    compiler, ready, "etc/compiler-sdk.xlisp",
    "cannot open the compile-time Lisp SDK");
  if (!ready) _install_builtins(compiler.macro_lisp);
  _eval_library(
    compiler, ready, "etc/builtin-core.xlisp",
    "cannot open the built-in macro support");
  if (!ready) _install_native_operations(compiler);
}

static Var _eval_string(Compiler compiler, String source, Token invocation) {
  Var result;
  MetaContext *context = MetaContext.current();
  $let(context.site, invocation)
  $let(context.evaluator, compiler) {
    /* A compiler operation called from Lisp has already reported its
       failure; wrapping the transfer would report it a second time. */
    try result = compiler.macro_lisp.eval_string(source);
    catch %(malformed (category ?category)):
      raise %(malformed (category $category));
    catch %(?code *detail):
      _report_lisp_failure(compiler, invocation, cons(code, detail), source);
  }
  return result;
}

static String _lisp_form(Compiler c) {
  Token start = c.token, close = start.group_close();
  if (close.type == <eof>)
    c.report_error(
      <parse>, "unterminated compile-time Lisp form", start, NULL);
  c.token = close.after_group();
  int begin = start.pos + start.len;
  return %"(${String.new_len(c.text + begin, close.pos - begin)})";
}

/** Consumes and evaluates one top-level compile-time Lisp form.
    `$(import ...)` loads a tracked `.xlisp` or `.xmacro` dependency; other
    results are discarded in the translation unit's Lisp session.
    Returns a `%(seq ...)` of the runtime `meta` declarations a macro import
    contributed, or NULL when the import declared nothing `meta` at all.
    The consuming unit retains them and emits the ones it reaches. An import
    whose `meta` functions are all compile-time only answers an empty `seq`,
    because the next pass still has to read it to install them.
*/
List Compiler.parse_macro_lisp_top_level(Compiler compiler) {
  Token invocation = compiler.token;
  String import_path = NULL;
  int is_import = _import_path(compiler, import_path);
  String form = _lisp_form(compiler);
  if (is_import) return _import(compiler, import_path, invocation);
  /* The shared session evaluated this file's forms once for the target and
     every unit inherits them, so evaluating this one again would only try to
     replace a name an ancestor binds. */
  if (compiler.inherited_lisp) return NULL;
  _ensure_lisp(compiler);
  _eval_string(compiler, form, invocation);
  return NULL;
}

/** Imports immediate dependencies and queues other source Lisp effects.
    Declaration projection forces preceding effects exactly once; otherwise
    full parsing keeps the ordinary source-order evaluation. */
void Compiler.parse_macro_lisp_shallow(Compiler compiler) {
  String requested = NULL;
  if (_import_path(compiler, requested)) {
    _shallow_import(compiler, requested);
    return;
  }
  Token first = compiler.token;
  String form = _lisp_form(compiler);
  /* As in full parsing, the shared session already holds an inherited
     import's forms, and running one again would rebind an ancestor's name. */
  if (compiler.inherited_lisp) return;
  compiler.queue_declaration_effect(form, first, compiler.token);
}

static void _shallow_import(Compiler compiler, String requested) {
  Token first = compiler.token;
  List imported = compiler.parse_macro_lisp_top_level();
  if (imported)
    foreach (Var definition, imported.cdr())
      compiler.meta_defs.push(definition);
  compiler.record_meta_import();
  if (compiler.package && !compiler.source_private &&
      requested.endswith(".xmacro"))
    _record_package_macro(compiler, requested, first);
}

/* A package entry records its public macro imports, which a consumer loads
   where it imports the package. */
static void _record_package_macro(
  Compiler compiler, String requested, Token first) {
  String name = compiler.package;
  String root = compiler.package_roots[name];
  String entry = compiler.filename;
  if (entry != %"$root/src/$name.x" && entry != %"$root/$name.x") return;
  String path = _canonical_path(compiler, requested);
  String source = home_portable_path(Path.absolute(entry));
  if (path.startswith(%"$root/")) path = path[root.len() + 1:];
  compiler.sym.set(
    %("source-node" (package-macro $source ${first.pos})),
    %(package-macro $name $path));
}

/** Evaluates a queued source Lisp form with its original diagnostic site. */
void Compiler.evaluate_declaration_effect(
  Compiler compiler, String form, Token invocation) {
  $let(compiler.collect_protocols, 1) {
    _ensure_lisp(compiler);
    _eval_string(compiler, form, invocation);
  }
}

/** Parses a compile-time Lisp form in an expression position.
    Macro-definition parsing records a deferred slot; ordinary parsing
    evaluates the form in the translation unit's Lisp session and lifts it.
*/
List Compiler.parse_macro_lisp_expression(Compiler compiler) {
  Token invocation = compiler.token;
  String form = _lisp_form(compiler);
  if (compiler.macro_holes) return %(expr (<macro-expr>) (macro-slot 0 $form));
  if (!compiler.collect_protocols) compiler.run_declaration_effects();
  _ensure_lisp(compiler);
  Var value = _eval_string(compiler, form, invocation);
  return compiler.lift_macro_lisp_expression(value, invocation);
}

/** Converts a compile-time Lisp value into a bound expression AST.
    Scalars, immutable values, representable Array/Map roots, compiler-issued
    identifiers, and nonempty code `List`s are accepted; `invocation` locates
    an unsupported result.
*/
List Compiler.lift_macro_lisp_expression(
  Compiler c, Var value, Token invocation) {
  List literal = c.meta_value_expression(NULL, value, invocation);
  if (literal) return literal;
  Var identifier = _sdk_identifier_result(value);
  if (identifier is not void) return %(expr () (ident $identifier));
  if (value is <list> && !value.is_nil())
    return c.bind_syntax(_helper_result(c, value), AST_EXPRESSION, NULL);
  c.report_error(
    <macro>, "compile-time Lisp result cannot fill an expression slot",
    invocation, %( "value:" ${value.repr()} ));
}

static Var _sdk_identifier_result(Var value) {
  match (value)
    case %("x2c.ident" (!is ?spelling type string)): return spelling;
  return value is <list> &&
         binding_identity_try_parts(value, NULL, NULL) ? value : void;
}

static Var _lisp_import_hook(String path) {
  MetaContext *context = MetaContext.current();
  Compiler compiler = context.evaluator;
  if (!compiler) raise %(bad-state (operation "compile-time import"));
  _import(compiler, path, context.site);
  return %();
}

/* imports

   `$(import "file")` evaluates an `.xlisp` file in the unit's session or
   reads an `.xmacro` file's definitions, aliases, and `meta` declarations.
   An import is cached only after it completes. Cached `.xmacro` aliases are
   replayed once per source alias map, while definitions and the Lisp session
   remain shared by the translation unit. CPP reads definitions and aliases;
   imported Lisp stays pending until a declaration needs its evaluation. */

/* One import while its file is read. `meta` records that the file
   contributed a `meta` declaration, which is what makes the next pass read
   it again instead of replaying a cached entry. A compile-time-only
   function installs and contributes no runtime definition, so the two are
   counted separately. */
typedef struct Import {
  Compiler c, String path, Token invocation;
  Map aliases, Array metas, int meta;
} Import;

static List _import(Compiler c, String requested, Token invocation) {
  _ensure_lisp(c);
  String path = _canonical_path(c, requested);
  c.add_translation_dependency(path);
  if (library_filling) library_imports[path] = 1;
  Var cached;
  if (c.imports.try_get(path, cached) && !_reuse_import(c, path, cached))
    return NULL;
  if (path in c.import_stack) _import_cycle(c, path, invocation);
  Import in = {.c = c, .path = path, .invocation = invocation};
  return in.read();
}

/* Applies a completed import's cache entry to this pass and answers whether
   the file must be read again. A `meta` definition is bound in the current
   symbol table and emitted where its import stands, so a pass that has not
   seen the path yet reads a `meta` file again instead of replaying it. */
static int _reuse_import(Compiler c, String path, Var cached) {
  match (cached)
    case %(imported ?aliases ?definitions ?dependencies ?(int meta)): {
      c.merge_translation_dependencies(dependencies);
      if (meta) return _forget_import(c, path, definitions);
      if (!(path in c.kw_seen)) _replay_import(c, path, aliases, definitions);
    }
  return 0;
}

/* The re-read defines this import's macros again, so the ones the previous
   pass left behind are dropped first; Definition.naming would otherwise
   report the second definition as a collision with another import. */
static int _forget_import(Compiler c, String path, Var definitions) {
  if (path in c.kw_seen) return 0;
  foreach (Var (name, definition), definitions.map()) c.macros.del(name);
  return 1;
}

static void _replay_import(
  Compiler c, String path, Var aliases, Var definitions) {
  foreach (Var (name, definition), definitions.map())
    c.macros[name] = _rebind_imported(c, definition);
  if (aliases is <map>) c.kw_aliases.merge(aliases);
  c.kw_seen[path] = 1;
}

static void _import_cycle(Compiler c, String path, Token invocation) {
  String display = c.display_path(path);
  Array notes = [ %"import: $display" ];
  foreach (Var parent, c.import_stack)
    notes.push(%"from: ${c.display_path(parent)}");
  c.report_error(
    <macro>, "compile-time import cycle",
    invocation, notes.list_free());
}

/* Reads the file and caches what it added: macros, dependencies, aliases,
   and whether it contributed `meta` declarations, which the import returns
   as a `seq`. */
static List Import.read(Import *in) {
  Compiler c = in.c;
  Map previous_definitions = c.macros.copy();
  Map previous_dependencies = c.deps.copy();
  c.import_stack.push(in.path);
  in.metas = [];
  {
    defer c.import_stack.take_last();
    in.file();
  }
  Map definitions = _changed(c.macros, previous_definitions);
  Map dependencies = _changed(c.deps, previous_dependencies);
  Var aliases = in.aliases ? in.aliases : %();
  c.imports[in.path] =
    %(imported $aliases $definitions $dependencies ${in.meta});
  c.kw_seen[in.path] = 1;
  if (!in.meta) {
    in.metas.free();
    return NULL;
  }
  List forms = in.metas.list_free();
  return %(seq @forms);
}

/* The entries of `now` whose values differ from `before`'s. */
static Map _changed(Map now, Map before) {
  Map changed = {};
  foreach (Var (key, value), now)
    if (before[key] != value) changed[key] = value;
  return changed;
}

static void Import.file(Import *in) {
  String path = in.path;
  if (path.endswith(".xlisp")) in.lisp();
  else if (path.endswith(".xmacro") || path.endswith(".xpmacro"))
    in.macros();
  else
    in.c.report_error(
      <macro>, "compile-time import requires .xlisp or .xmacro",
      in.invocation, _path_note(in.c, path));
}

/* The shared session evaluated this file once for the target, and a session
   cannot replace a name an ancestor binds. The read still reports a file
   that has gone missing. */
static void Import.lisp(Import *in) {
  Compiler c = in.c;
  String text = _read_source(
    c, in.path, "cannot open compile-time Lisp import", in.invocation);
  if (_inherited_import(in.path)) return;
  if (c.collect_protocols) _eval_string(c, text, in.invocation);
  else c.queue_declaration_effect(text, in.invocation, in.invocation);
}

/* The import parser borrows the caller's semantic maps and Lisp. Its
   diagnostics are returned to the caller before release; lasting effects
   enter the shared definitions, aliases, dependencies, literal cache, and
   Lisp session. */
static void Import.macros(Import *in) {
  Compiler c = in.c;
  in.aliases = {};
  String text = _read_source(
    c, in.path, "cannot open macro import", in.invocation);
  Compiler child = Compiler.new_shared(c);
  defer c.close_child(child);
  child.filename = in.path;
  child.collect_protocols = c.collect_protocols;
  /* The caller's collection pass parses no bodies and so keeps its
     protocol registries empty. A `meta` definition here is the one body it
     does parse, and its `foreach` is the only reader, so the import
     installs the protocols visible to it when one is asked for. */
  child.import_protocols = c.shallow;
  $let(c.diagnostics.printer, c.diagnostics.printer) {
    in.borrow(child);
    child.tokenize(text);
    while (child.peek(0) != <eof>) in.form(child);
    c.merge_translation_dependencies(child.deps);
    c.declaration_effects = child.declaration_effects;
  }
}

/* A `meta` definition the import returns is emitted by the caller when the
   caller reaches it, so its `(cache id)` references index the caller's
   keys. */
static void Import.borrow(Import *in, Compiler child) {
  Compiler c = in.c;
  child.borrow_diagnostics(c);
  child.borrow_unit_semantics(c);
  child.macros = c.macros;
  child.kw_aliases = c.kw_aliases;
  child.kw_seen = c.kw_seen;
  child.macro_lisp = c.macro_lisp;
  child.meta_group = c.meta_group;
  child.meta_group_bound = c.meta_group_bound;
  child.unit_nodes = c.unit_nodes;
  child.borrowed_lisp = 1;
  child.import_src = in.path;
  child.inherited_lisp = _inherited_import(in.path);
  child.imports = c.imports;
  child.import_stack = c.import_stack;
  child.declaration_effects = c.declaration_effects;
}

static void Import.form(Import *in, Compiler child) {
  if (child.keyword_form_is_definition()) _record_alias(child, in.aliases);
  else if (child.macro_form_is_definition()) child.parse_macro_definition();
  else if (child.meta_form_is_declaration()) in.meta_declaration(child);
  else if (child.peek(0) == <"$(">) in.lisp_form(child);
  else
    child.report_error(
      <macro>, "unexpected form in macro import", child.token, NULL);
}

static void Import.meta_declaration(Import *in, Compiler child) {
  in.meta = 1;
  List definition = child.parse_top_level();
  if (definition) in.metas.push(definition);
}

/* A nested import's own `meta` definitions belong to the same consuming
   unit. */
static void Import.lisp_form(Import *in, Compiler child) {
  if (!in.c.collect_protocols && !_import_path(child, NULL)) {
    child.parse_macro_lisp_shallow();
    return;
  }
  List nested = child.parse_macro_lisp_top_level();
  if (!nested) return;
  in.meta = 1;
  foreach (Var form, nested.cdr()) in.metas.push(form);
}

static int _import_path(Compiler compiler, String &?path) {
  Token token = compiler.skip_trivia_from(compiler.token + 1);
  /* The checked-in bootstrap still tokenizes `import` as an identifier, so
     both spellings of the same word open a compile-time import. */
  if ((token.type != <ident> && token.type != <import>) ||
      token.text != "import")
    return 0;
  token = compiler.skip_trivia_from(token + 1);
  if (token.type != <lit-char*>) return 0;
  if (path) path = String.new_len(token.text + 1, token.len - 2).unescape();
  token = compiler.skip_trivia_from(token + 1);
  return token.type == <)>;
}

/* Cached templates retain global references across symbol-table resets.
   Bind those names in the current global scope without replaying imports. */
static Var _rebind_imported(Compiler compiler, Var stored) {
  if (stored is not <list>) return stored;
  List definition = stored;
  if (definition.car() != <macrodef>) return definition;
  Map replacements = {};
  _reference_bindings(compiler, definition, replacements);
  if (!replacements.len()) return definition;
  return _replace_bindings(definition, replacements);
}

static void _reference_bindings(
  Compiler compiler, List syntax, Map replacements) {
  match (syntax)
    case %(expr ? ${$source_identifier_content(%(?binding))}): {
      String spelling = NULL;
      if (binding_identity_try_parts(binding, NULL, spelling))
        replacements[binding] = compiler.sym.reference_global(%($spelling));
      return;
    }
  foreach (Var child, syntax)
    if (child is <list>) _reference_bindings(compiler, child, replacements);
}

/** Loads the public macro imports recorded by a package entry at this
    consumer's import position. */
void Compiler.import_package_macros(
  Compiler c, String name, Token invocation) {
  foreach (List entry, _package_exports(c, name)) {
    String path = entry.cadr();
    if (!path.startswith("/")) path = %"${c.package_roots[name]}/$path";
    List imported = _import(c, path, invocation);
    if (imported)
      foreach (Var definition, imported.cdr()) c.meta_defs.push(definition);
  }
}

/* The macro imports package `name` recorded, in source order. */
static Array _package_exports(Compiler c, String name) {
  Array exports = [];
  foreach (Var (key, value), _visible_symbols(c))
    match (key)
      case %("source-node" (package-macro ? ?(int position))):
        match (value)
          case %(package-macro ?(String package) ?(String path)):
            if (package == name) exports.push(%($position $path));
  exports.sort();
  return exports;
}

// source files

/* A relative import names a file beside the importing source, or else one
   under the home's `lib/`. */
static String _canonical_path(Compiler c, String path) {
  if (!path || path[0] == '/') return c.canonical_path(path);
  String local = %"${_source_dir(c)}/$path";
  String system = %"${c.root_dir}/lib/$path";
  int use_system = !c.sources.exists(local) && c.sources.exists(system);
  return c.canonical_path(use_system ? system : local);
}

static String _source_dir(Compiler compiler) {
  String filename = compiler.import_stack.len()
                  ? compiler.import_stack[-1]
                  : compiler.filename;
  return filename ? Path.dirname(filename) : ".";
}

/** Returns the canonical path of the source `file`. A relative name that
    is not a file resolves against the home. */
String Compiler.source_path(Compiler c, String file) {
  if (!file || file.startswith("<")) return file;
  String rooted = %"${c.root_dir}/$file";
  if (file[0] != '/' && !c.sources.exists(file) && c.sources.exists(rooted))
    file = rooted;
  return c.canonical_path(file);
}

/* An absolute path; the definition keeps the home-portable spelling. */
static String _definition_file(List definition) {
  String file = definition.assoc(<file>);
  return !file || file.startswith("<") ? file : home_absolute_path(file);
}

/* Reads a compile-time source and records its content hash as a
   dependency. */
static String _read_source(
  Compiler compiler, String path, String message, Token token) {
  String text = _source_text(
    compiler, path, message, token, _path_note(compiler, path));
  compiler.deps.merge_translation_dependency(
    path, "%08x".printf(text.hash()));
  return text;
}

/* An unreadable compile-time source is a located diagnostic. */
static String _source_text(
  Compiler c, String path, String message, Token token, List notes) {
  String text = NULL;
  if (!c.read_source(path, text))
    c.report_error(<macro>, message, token, notes);
  return text;
}

/* the shared library session

   A build target fills one Lisp session with the home's compile-time
   libraries and native operations, freezes it, and makes it the parent of
   every unit's session. */

/* The paths whose top-level Lisp the shared session evaluated while it was
   being filled. A unit that reaches one of these registers the file's macro
   definitions as usual and leaves its Lisp alone: the shared session already
   holds those definitions, and a session cannot replace a name an ancestor
   binds. The key is the path the loader resolved, which is the identity the
   import cache itself uses, so a file that shadows a library name through
   another include path is a different key and evaluates normally. */
static Map library_imports = NULL, static int library_filling = 0;
static Map library_definitions = NULL;
/* The shared session's compile-time-only definitions, which have no
   runtime form in any unit that reads them. */
static Map library_comptime = NULL;

static Lisp library_session = NULL, static Scope library_scope = NULL;
static int library_hooked = 0;

/** Builds the shared compile-time session, leaving it open for the caller to
    fill and then publish. Returns the session, or null when this home cannot
    preload, in which case every unit falls back to its own load, which
    reports against the unit that needed it.

    The session is not published until `Compiler.publish_macro_library`, so a
    unit opened in between still builds its own.
*/
Lisp Compiler.open_macro_library(Compiler compiler) {
  if (library_session != NULL) return NULL;
  $scope(&library_scope) {
    if (!library_hooked) {
      Scope.shutdown_hook(_library_shutdown);
      library_hooked = 1;
    }
    Lisp shared = Lisp.kernel();
    library_imports = {};
    library_definitions = {};
    library_comptime = {};
    $let(compiler.macro_lisp, shared)
      return _fill_library(compiler, shared);
  }
}

/* A failure while filling leaves no session, so each unit loads its own. */
static Lisp _fill_library(Compiler compiler, Lisp shared) {
  library_filling = 1;
  try {
    _install_builtins(shared);
    foreach (Var (relative, message), _library_files())
      _eval_library(compiler, 0, relative, message);
    _install_native_operations(compiler);
  }
  catch %(? *): {
    library_filling = 0;
    return NULL;
  }
  return shared;
}

/* The four libraries and the message each failure reports, in the order a
   session needs them. */
static List _library_files(void) => %(
  ("etc/init.xlisp" "cannot open the compile-time Lisp environment")
  ("etc/lisp-values.xlisp" "cannot open the compile-time value operations")
  ("etc/compiler-sdk.xlisp" "cannot open the compile-time Lisp SDK")
  ("etc/builtin-core.xlisp" "cannot open the built-in macro support"));

/* A home Lisp library is evaluated once, when `loaded` is zero, but every use
   records it, so a file's dependencies do not depend on whether an earlier
   file loaded it. */
static void _eval_library(
  Compiler compiler, int loaded, String relative, String message) {
  String path = %"${compiler.root_dir}/$relative";
  compiler.add_translation_dependency(path);
  if (library_filling) library_imports[path] = 1;
  if (loaded || _inherited_import(path)) return;
  String text = _source_text(
    compiler, path, message, compiler.token, %("path:" $path));
  _eval_string(compiler, text, compiler.token);
}

/** Prepares and freezes the shared session and makes it every unit's parent.
    `shared` must be the session `Compiler.open_macro_library` returned.
*/
void Compiler.publish_macro_library(Compiler compiler, Lisp shared) {
  (void) compiler;
  library_filling = 0;
  /* A second preload for the same target finds the session published. */
  if (library_session) return;
  if (!shared) {
    library_imports = NULL;
    library_definitions = NULL;
    library_comptime = NULL;
    return;
  }
  shared.freeze();
  library_session = shared;
}

static int _inherited_import(String path) {
  /* An empty `Map` is false, so the test is for the allocation. */
  return !library_filling && library_imports != NULL &&
         path in library_imports;
}

/** Whether the shared session evaluated the file at `path`. A unit that is
    that file, as when a library is linted, inherits its Lisp forms.
*/
int Compiler.inherits_import(String path) => _inherited_import(path);

/* Records that `name` is compile-time only in `c`, and in the shared
   session when it is being filled. */
static void _record_comptime(Compiler c, String name) {
  c.meta_comptime[name] = 1;
  if (!library_filling || !(void *) library_comptime) return;
  $scope(&library_scope) library_comptime[name] = 1;
  name.try_own();
}

/** Marks the shared session's compile-time-only definitions in a fresh
    compiler pass, which reads them without defining them. */
void Compiler.inherit_library_comptime(Compiler c) {
  if (library_filling || library_comptime == NULL) return;
  foreach (String name, library_comptime.keys()) c.meta_comptime[name] = 1;
}

/** Answers whether the shared compile-time session is still being filled,
    before `lib/meta.x` has defined the syntax builders. */
int macro_library_filling(void) => library_filling;

/** Returns the published definition keys, or null before publication.
    The borrowed map is the shared session's source identity table.
*/
Map Compiler.shared_definitions(Compiler compiler) {
  (void) compiler;
  return library_session ? library_definitions : NULL;
}

/* Whether the published shared session already holds the definition of
   `name` from this file, which a unit reading the file again leaves alone. */
static int _shared_meta_definition(Compiler c, String name) {
  if (library_filling || library_definitions == NULL || !c.filename) return 0;
  String key = %"${Path.absolute(c.filename)}#$name";
  return key in library_definitions;
}

/* built-in macros

   The compiler carries two macro sources in its own image: the built-in
   macros, and the Lisp binding macros that a `lisp.` name installs on
   first use. A unit parses each source once and keeps its aliases under a
   marker. */

macro Expression $_embed_lisp_binding_macros() =>
  $(x2c.literal.string (_x2c.embed.text "../etc/lisp-bindings.xmacro"));

macro Expression $_embed_builtin_macros() =>
  $(x2c.literal.string (_x2c.embed.text "../etc/builtin-macros.xmacro"));

static String lisp_binding_macros = $_embed_lisp_binding_macros();
static String lisp_bindings_marker = NULL;
static String builtin_macros = $_embed_builtin_macros();
static String builtin_macros_marker = NULL;

/** Installs the compiler-shipped source macros into `compiler` once. */
void Compiler.install_builtin_macros(Compiler compiler) {
  if (!builtin_macros_marker) builtin_macros_marker = "_x2c.builtin.macros";
  _install_source(
    compiler, builtin_macros, "<builtin:macros>",
    builtin_macros_marker, 1);
}

static void _install_source(
  Compiler compiler, String text, String filename, String marker,
  int builtin) {
  (void) marker.try_own();
  Var installed;
  if (compiler.macros.try_get(marker, installed)) {
    compiler.kw_aliases.merge(installed);
    return;
  }
  Compiler child = Compiler.new_shared(compiler);
  defer compiler.close_child(child);
  child.filename = filename;
  child.sym = compiler.sym;
  child.fn_defs = compiler.fn_defs;
  child.macros = compiler.macros;
  child.kw_aliases = compiler.kw_aliases;
  child.builtin_defs = builtin;
  child.tokenize(text);
  Map aliases = _read_definitions(child);
  compiler.macros[marker] = aliases;
}

/* A shipped source holds only definitions and keyword aliases. */
static Map _read_definitions(Compiler child) {
  Map aliases = {};
  while (child.peek(0) != <eof>) {
    if (child.keyword_form_is_definition()) _record_alias(child, aliases);
    else if (child.macro_form_is_definition()) child.parse_macro_definition();
    else
      child.report_error(
        <macro>, "unexpected form in built-in macro source",
        child.token, NULL);
  }
  return aliases;
}

/* Every `lisp.` lookup records the bindings file, which is installed only
   when `install` is nonzero and the bindings are not yet installed. */
static void _use_lisp_bindings(Compiler compiler, int install) {
  if (!lisp_bindings_marker) lisp_bindings_marker = "_x2c.lisp.bindings";
  int loaded =
    !install || lisp_bindings_marker in compiler.macros;
  if (!loaded) _ensure_lisp(compiler);
  _eval_library(
    compiler, loaded, "etc/lisp-bindings.xlisp",
    "cannot open the native Lisp macro support");
  if (loaded) return;
  /* Signature imports may preload into the shared parent; group state starts
     only when this unit installs the binding macros. */
  compiler.macro_lisp.eval(
    %(begin (def lisp.binding.rows ()) (def lisp.binding.sealed ())));
  _install_source(
    compiler, lisp_binding_macros, "<builtin:lisp-bindings>",
    lisp_bindings_marker, 0);
}

/* native operations

   Native operations read the active expansion's context, not the session
   that owns their callable, so the shared parent owns them once. */

static void _install_native_operations(Compiler compiler) {
  _bind_primitives(compiler.macro_lisp);
  if (!Compiler.native_module_loaded(compiler_supplier))
    Compiler.add_native_module(compiler_supplier, _compiler_targets);
  foreach (Var (name, function), _compiler_targets()) {
    compiler.macro_lisp.set_global(name, function);
    Compiler.bind_meta_operation(compiler.macro_lisp, name, function);
  }
}

/* Cold declaration collection needs literals before the meta surface is
   parsed, so the runtime's own compiled builders come first. Internal
   primitives carry the `_x2c.` prefix. */
static void _bind_primitives(Lisp lisp) {
  $lisp.bind(lisp, "x2c_literal_string", x2c_literal_string);
  $lisp.bind(lisp, "x2c_literal_int", x2c_literal_int);
  $lisp.bind(lisp, "x2c_literal_symbol", x2c_literal_symbol);
  $lisp.bind(lisp, "_x2c.import-hook", _lisp_import_hook);
  $lisp.bind(lisp, "_x2c.native-meta.targets", _sdk_meta_targets);
  $lisp.bind(lisp, "_x2c.native-meta.declared", _sdk_meta_declared);
  $lisp.bind(lisp, "_x2c.tpl-call", _sdk_template_call);
  Compiler.bind_sdk_primitives(lisp);
}

/* Binds the built-in macro algorithms into `lisp` under the names its
   compile-time Lisp calls; the native Lisp binding algorithms carry the
   `_x2c.` prefix of internal primitives. */
static void _install_builtins(Lisp lisp) {
  foreach (Var (name, function), builtin_targets()) {
    String spelling = name;
    lisp.set_global(
      spelling.startswith("binding_") ? %"_x2c.$spelling" : spelling,
      function);
  }
}

/* The compiler supplies the operations `lib/meta.x` declares with a bodyless
   `meta` prototype, the `x2c_` targets, as the native module
   `compiler_supplier`, which every request selects first. */
$(import "../etc/lisp-bindings.xlisp")
macro Expression $compiler.targets() => $(lisp.native.targets
  (filter (lambda (row) (not (eq? (String.startswith (car row) "x2c_") 0)))
    (_x2c.native-meta.targets)));

static String compiler_supplier = "<compiler>";

static Map _compiler_targets(void) => $compiler.targets();

/** Binds `function`, the operation `lib/meta.x` declares as `name`, under
    its Lisp name in `lisp`. A predicate answers a Lisp truth value where the
    x2c spelling answers `int`. A definition the compile-time libraries
    already give that name wins, because it adapts the arguments.
*/
void Compiler.bind_meta_operation(Lisp lisp, String name, Var function) {
  String dotted = _meta_lisp_name(name);
  Var bound;
  if (lisp.try_get(dotted, bound)) return;
  if (name.startswith("x2c_type_is_"))
    function = lisp.eval(
      %(lambda (value) (if (eq? ((quote $function) value) 0) nil true)));
  lisp.set_global(dotted, function);
}

/* The Lisp name of the operation `lib/meta.x` declares as `name`: each `_`
   becomes `.`, a predicate `x2c_type_is_X` is `x2c.type.X?`, and two names
   keep the hyphen of their Lisp spelling. */
static String _meta_lisp_name(String name) {
  if (name == "x2c_type_tag_name") return "x2c.type.tag-name";
  if (name == "x2c_type_reverse_name") return "x2c.type.reverse-name";
  if (name.startswith("x2c_type_is_"))
    return %"x2c.type.${name[12:]}?";
  return name.replace("_", ".");
}

// diagnostics

static String _definition_note(List definition) {
  List origin = definition.assoc(<origin>);
  String file = origin.assoc(<file>);
  int line = origin.assoc(<line>),
      column = origin.assoc(<column>);
  return %"definition: $file:$line:$column";
}

static void _report_lisp_failure(
  Compiler compiler, Token invocation, List error, String source) {
  String form_note = %"form: $source", error_note = %"error: ${error.repr()}";
  compiler.report_error(
    <macro>, "compile-time Lisp evaluation failed",
    invocation, %($form_note $error_note));
}

static List _path_note(Compiler c, String path) =>
  %("path: ${c.display_path(path)}");

/* A template names a hole, projection, or replacement variable that it
   does not bind. */
static void _unbound(Compiler c, String spelling, Token token) {
  c.report_error(
    <parse>, %"unbound replacement variable '$spelling'", token, NULL);
}

// lifecycle

static void _library_shutdown(void) {
  Lisp.destroy(library_session);
  library_session = NULL;
  library_imports = NULL;
  library_definitions = NULL;
  library_comptime = NULL;
  library_scope.destroy();
  library_scope = NULL;
}

/** Ends the shared compile-time library before its build-target Context is
    reclaimed. A later target creates a fresh session in its own Context. */
void macro_library_reset(void) {
  _library_shutdown();
  library_filling = 0;
}

static void _native_module_shutdown(void) {
  native_module_scope.destroy();
  native_module_scope = NULL;
  native_modules = NULL;
  native_module_order = NULL;
}
