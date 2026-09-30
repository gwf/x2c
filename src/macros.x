/*  macros.x -- source macros and the compile-time code they run

    A definition is a compiler-only `macrodef` List: its holes, a Match
    pattern over an invocation's capture rows, and a template of the
    binders that pattern captures. Expansion fills the template and binds
    the result through the operations that bind parsed source.

    Template slots, `$(...)` forms, and `meta` functions run in the unit's
    compile-time Lisp session, whose parent is the shared library session.
    A native operation has no Compiler parameter, so it reads the active
    compiler from the dynamically scoped statics below.
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

// expansion context

/* Native Lisp callbacks have no Compiler parameter, so these values hold
   dynamically scoped evaluation context. Lisp entry points restore the
   relevant frame after nested import evaluation; captured-source entries are
   valid only while their expansion is active. */
static Compiler sdk_compiler = NULL;
static String sdk_file = NULL;
static Map sdk_captures = NULL;
static int sdk_references = 0;
static Compiler lisp_compiler = NULL;
static Token lisp_site = NULL;

/** Returns the compiler running the current compile-time call. A slot
    function compiled into the compiler reads its facts through it. */
Compiler Compiler.expanding(void) =>
  sdk_compiler ? sdk_compiler : lisp_compiler;

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
  d.open = c.peek(0) == <ident> && c.token.text == "open" &&
           c.peek(1) == <ident>;
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
  if (c.peek(0) == <ident> && c.token.text == "using") {
    c.next();
    _using_holes(c, d.using);
  }
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
  d.file = home_portable_path(_source_file(c, c.filename));
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
  while (c.peek(0) == <ident> && c.token.text == "using" &&
         c.peek(1) == <$>) {
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
  return c.peek(0) == <ident> && c.token.text == "macro" &&
         c.peek(1) == <ident> && c.peek(2) == <ident> && c.peek(3) == <(>;
}

/** Returns whether the current tokens begin a `keyword NAME $macro` alias.
    This query does not consume tokens.
*/
int Compiler.keyword_form_is_definition(Compiler c) =>
  c.peek(0) == <ident> && c.token.text == "keyword" && c.peek(2) == <$>;

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
  if (kind == <decl> && (c.peek(0) == <in> || c.token.text == "in")) c.next();
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
  String file = _source_file(
    compiler, compiler.filename ? compiler.filename : "<stdin>");
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
  template = _replace_bindings(template, replacements);
  template = _open_natives(c, template, natives);
  return template.search_replace(%(at m-origin ?node), <?node>);
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
    case %(expr ?(List type) (ident ?binding)): {
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

static Var _open_natives(Compiler c, Var value, Map natives) {
  if (value is not <list> || value.is_nil()) return value;
  Macro called = $called;
  match (value) {
    case called(?callee, *arguments):
      if (value.list().car() == <expr>)
        match (callee) case %(expr ? (ident ?binding)): {
          Var native;
          if (natives.try_get(binding, native))
            return _native_call(c, native, arguments, natives);
        }
    case %(decl ?base ?declarators): {
      Type resolved = base is <list> && base.type().is_bare_typedef_name()
        ? c.sym.resolve_base_type(base) : NULL;
      if (resolved)
        return %(decl $resolved ${_open_natives(c, declarators, natives)});
    }
  }
  Array items = $auto([]);
  foreach (Var child, value.list())
    items.push(_open_natives(c, child, natives));
  return items.list();
}

static List _native_call(Compiler c, Var native, List arguments, Map natives) {
  Var (callee, result) = native;
  List args = _open_natives(c, arguments, natives);
  return %(expr $result (call $callee (args @args)));
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
  $let(sdk_references, !!references)
  $let(sdk_captures, source_captures)
  $let(sdk_file, source_file)
  $let(sdk_compiler, compiler)
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
  List definition = stored.is_atom()
    ? _lookup(c, stored, lisp_site) : stored;
  return %(macro-invoke $stored
    ${_template_arguments(c, definition, values, lisp_site, 0)}
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
    case %(literal *): return value;
  }
  Array parts = [];
  foreach (Var part, (List) value) parts.push(_helper_result(c, part));
  List resolved = parts.list_free();
  match (resolved) {
    case %("x2c.template" ?stored ?(List values)): {
      Token site = c.macro_invocation_site(<m-invoke>);
      if (!site) site = c.token;
      $let(sdk_compiler, c)
      $let(lisp_site, site)
        return _sdk_template_call(
          stored is <string> ? Atom.intern(stored.str()) : stored, values);
    }
  }
  return resolved;
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
  Array parts = $auto([]);
  int changed = 0;
  foreach (Var child, value.list()) {
    Var part = _macro_value_names(child);
    changed |= part != child;
    parts.push(part);
  }
  return changed ? parts.list().var() : value;
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
  Array parts = $auto([]);
  int changed = 0;
  foreach (Var child, value.list()) {
    Var part = _macro_value_bindings(c, child);
    changed |= part != child;
    parts.push(part);
  }
  return changed ? parts.list().var() : value;
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
    case %((!or ident bind) ?name *):
      if (name.is_binder() && name.str().len() > 1) return name;
    case %((!or "x2c.template" macro-invoke macrodef literal) *):
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
  $let(lisp_site, invocation)
  $let(lisp_compiler, compiler) {
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
  Compiler compiler = lisp_compiler;
  if (!compiler) raise %(bad-state (operation "compile-time import"));
  _import(compiler, path, lisp_site);
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
    case %(expr ? (ident ?binding)): {
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

/* A relative source name that is not a file resolves against the home. */
static String _source_file(Compiler c, String file) {
  if (!file || file.startswith("<")) return file;
  String rooted = %"${c.root_dir}/$file";
  if (file[0] != '/' && !c.sources.exists(file) && c.sources.exists(rooted))
    file = rooted;
  return c.canonical_path(file);
}

static String _embed_path(Compiler c, String source_file, String requested) {
  if (requested[0] == '/') return c.canonical_path(requested);
  String base = Path.dirname(_source_file(c, source_file));
  return c.canonical_path(%"$base/$requested");
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
  $lisp.bind(lisp, "_x2c.function.reference", _sdk_function_reference);
  $lisp.bind(lisp, "_x2c.function.native-type", _sdk_native_type);
  $lisp.bind(lisp, "_x2c.literal.list", _sdk_literal_list);
  $lisp.bind(lisp, "_x2c.native-meta.targets", _sdk_meta_targets);
  $lisp.bind(lisp, "_x2c.native-meta.declared", _sdk_meta_declared);
  $lisp.bind(lisp, "_x2c.foreach.complete-iter-chain", _sdk_iter_chain);
  $lisp.bind(lisp, "_x2c.foreach.string-collection", _sdk_string_collection);
  $lisp.bind(lisp, "_x2c.source.text", _sdk_source_text);
  $lisp.bind(lisp, "_x2c.embed.text", _sdk_embed_text);
  $lisp.bind(lisp, "_x2c.invocation.location", _sdk_invocation_location);
  $lisp.bind(lisp, "_x2c.symbol-set", _sdk_symbol_set);
  $lisp.bind(lisp, "_x2c.tpl-call", _sdk_template_call);
  $lisp.bind(lisp, "_x2c.name.unique", _sdk_ident_unique);
  $lisp.bind(lisp, "_x2c.declaration.bindings", _sdk_bindings);
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

/* meta functions

   A bodied `meta` function runs at compile time through a stub in the
   unit's session. The stub calls the function's compiled copy in the
   project's helper, or in the REPL the group's native code. */

/** Applies a contextual `meta` marker to one initialized file-static value.
    The unit's staged `meta` group holds the compile-time instance, which
    its module initializes for each unit. */
void Compiler.install_meta_declaration(
  Compiler c, List declaration, Token marker) {
  match (declaration) {
    case %(declare ?spec
           (bindings
             (op = (bind (binding ? ?(String name)) *) ?))): {
      if (!spec.type().is_static())
        c.report_error(
          <parse>, "a meta value must have file-static storage", marker,
          %("declaration: '$name'"));
      if (c.groups_meta()) c.meta_group.push(%(static $declaration));
      return;
    }
  }
  c.report_error(
    <parse>, "meta requires a function or one initialized static value",
    marker, NULL);
}

/** Installs a bodied `meta` function. The project meta build compiled it
    into the project's helper, so the session holds a stub that calls it
    there; the REPL's stub stages the session's group at the first call
    instead, and the project meta build's own parse only groups it. A
    function whose body reaches a compiler operation, a template, or a
    compile-time-only function has no runtime form. A body that lets its
    own storage outlive a call is rejected where the storage leaves.
*/
void Compiler.install_meta_function(Compiler c, List fn, Token marker) {
  if (!c.collect_protocols) c.run_declaration_effects();
  _ensure_lisp(c);
  c.check_meta_regions(fn);
  match (fn)
    case %(function ? (bind (binding ? ?(String name)) *) ?): {
      if (c.meta_reaches_compile_time(fn)) _record_comptime(c, name);
      if (c.macro_holes) return;
      c.group_meta_function(fn);
      if (c.meta_build) return;
      if (!macro_library_filling() && !_shared_meta_definition(c, name))
        _install_stub(c, name, marker);
    }
}

/* A session refuses to replace a name an ancestor binds, which reaches the
   developer here, at the marker. */
static void _install_stub(Compiler c, String name, Token marker) {
  Type type = ((List) c.meta_group[-1]).last();
  try c.macro_lisp.set_global(
    name,
    Func.new_context(
      _meta_stub, c.func_signature(type), (char *) name, name.len() + 1));
  catch %(?code *detail): {
    List cause = cons(code, detail);
    c.report_error(
      <macro>, "this meta function could not be installed", marker,
      %("reason: ${cause.repr()}"));
  }
}

/* Adapts a call of a bodied `meta` function's session binding, whose
   context holds the function's name, to a call in the project's helper,
   or in the REPL to a call of the group's native code, which the first
   call stages and binds under the name. */
static Var _meta_stub(Func function, const FuncArg *argv) {
  Array values = _stub_arguments(function, argv);
  String name = String.new((const char *) Func.context(function));
  Token site;
  Compiler c = _stub_compiler(name, site);
  List rows = _subject_rows(c, values);
  Var previous = Macro.subject();
  Macro.use_subject(rows);
  defer Macro.use_subject(previous);
  if (!c.groups_meta())
    return c.meta_helper_call(name, site, values.list_free());
  c.bind_meta_group(name, site);
  Var bound;
  c.macro_lisp.try_get(name, bound);
  return _meta_apply(c, bound, values.list_free());
}

static Array _stub_arguments(Func function, const FuncArg *argv) {
  List parameters = Func.signature(function).car().list().cadr();
  if (parameters.equal(%((void)))) parameters = NULL;
  Array values = [];
  for (int i = 0; i < parameters.len(); i++)
    values.push(argv[i].data.value);
  return values;
}

/* The compiler that runs a stub's call, and where the call stands. */
static Compiler _stub_compiler(String name, Token &site) {
  Compiler c = Compiler.expanding();
  if (!c) _sdk_reject(%"$name used outside compilation", NULL);
  site = lisp_site ? lisp_site : c.token;
  return c;
}

/* The caller's global bindings and source-name projections for bindings in
   the arguments, carried through the existing helper subject context. */
static List _subject_rows(Compiler c, Array values) {
  Map globals = {}, source_names = {};
  foreach (Var value, values)
    _subject_globals(c, value, globals, source_names);
  Array rows = [];
  foreach (Var (spelling, binding), globals) rows.push(%($spelling $binding));
  foreach (Var (binding, spelling), source_names)
    rows.push(%(source-spelling $binding $spelling));
  return rows.list_free();
}

/* Records global identities and source spellings from argument syntax. */
static void _subject_globals(
  Compiler c, Var value, Map globals, Map source_names) {
  if (value is not <list>) return;
  String spelling = NULL;
  if (binding_identity_try_parts(value, NULL, spelling)) {
    Var source;
    if (c.semantic_binding_facts().try_get(
          %(source-spelling $value), source))
      source_names[value] = source;
    List global = c.sym.resolve_global(%($spelling), NULL);
    if (global && List.compare(global, value) == 0)
      globals[spelling] = value;
    return;
  }
  foreach (Var child, value.list())
    _subject_globals(c, child, globals, source_names);
}

/* Calls the session value `function` with the evaluated `arguments`. */
static Var _meta_apply(Compiler c, Var function, List arguments) {
  Array quoted = [%(quote $function)];
  foreach (Var argument, arguments) quoted.push(%(quote $argument));
  return c.macro_lisp.eval(quoted.list_free());
}

/* explicit meta calls

   A `$f(...)` call of a `meta` function outside a `meta` body runs at
   compile time, and its value becomes syntax at the call. */

/** Executes an explicit meta call and inserts its result at a code
    boundary. */
List Compiler.evaluate_meta_expression(
  Compiler c, List expression, Token site) {
  Var value = _evaluate_meta_value(c, expression, site, 0);
  if (value is void && c.meta_build) {
    List placeholder = %(expr (int) (literal (int) "0"));
    c.meta_group.push(%(later $placeholder));
    return placeholder;
  }
  Type declared = expression.cadr();
  match (expression) case %(expr ? (meta-call (expr ?signature ?) ?)):
    declared = signature.cdr();
  if (declared === %(void))
    return %(expr (void) (cast (void) (expr (int) (literal (int) "0"))));
  if (c.macro_stack && value is <list>)
    return c.lift_macro_lisp_expression(value, site);
  List result = c.meta_value_expression(declared, value, site);
  return result ? result : c.lift_macro_lisp_expression(value, site);
}

/* Evaluates the explicit meta call `expression` at `site` with the active
   expansion's captures visible to the SDK. */
static Var _evaluate_meta_value(
  Compiler c, List expression, Token site, int slot) {
  if (!c.collect_protocols) c.run_declaration_effects();
  _ensure_lisp(c);
  List active = c.macro_stack ? c.macro_stack.car() : NULL;
  List bindings = active ? active.caddr() : NULL;
  String source_file = active ? _definition_file(active.car()) : c.filename;
  $let(sdk_references, !!bindings)
  $let(sdk_captures, _source_captures(bindings))
  $let(sdk_file, source_file)
  $let(sdk_compiler, c)
  $let(lisp_compiler, c)
  $let(lisp_site, site)
    return _run_meta_call(c, expression, site, slot);
}

/* The project meta build's own parse leaves a project function's call for
   the translation: an expression takes a placeholder, and a template
   `slot`, which has none, is reported. */
static Var _run_meta_call(Compiler c, List expression, Token site, int slot) {
  Var value;
  try value = _meta_call_value(c, expression, site);
  catch %(meta-later *): {
    value = void;
    if (slot)
      c.report_error(
        <macro>, "this meta call is left for the translation", site, NULL);
  }
  catch %(malformed (category ?category)):
    raise %(malformed (category $category));
  catch %(call-stack *):
    c.report_error(
      <macro>, "explicit meta call was stopped", site,
      %("reason: its compile-time form nested too deep"));
  catch %(?code *detail):
    _report_lisp_failure(c, site, cons(code, detail), meta_call_form);
  return value;
}

/* Both entry forms expose source only for complete captures in the active
   expansion. The keys are the same unwrapped values passed to the helper. */
static Map _source_captures(List bindings) {
  Map captures = {};
  foreach (List pair, bindings) {
    List source;
    Var syntax;
    if (pair && _source_capture_parts(pair.cadr(), source, syntax))
      captures[((ulong) syntax.u64)] = source;
  }
  return captures;
}

/* The last call a `$` expression made, as a failure reports it. */
static String meta_call_form = NULL;

/* Calls a `meta` function named at a code boundary with its evaluated
   arguments. */
static Var _meta_call_value(Compiler c, List expression, Token site) {
  match (expression)
    case %(expr ? (meta-call (expr ?callee (ident (binding ? ?(String name))))
                             (args *arguments))): {
      Array values = _meta_values(c, callee, arguments, site);
      Var function = _meta_function(c, name, site);
      List applied = values.list_free();
      meta_call_form = cons(Atom.intern(name), applied).repr();
      meta_call_form.try_own();
      return _meta_apply(c, function, applied);
    }
  c.report_error(
    <macro>, "explicit meta call cannot be resolved", site,
    %("only a call to a meta function runs at compile time"));
}

/* Each argument evaluates as the type its parameter declares wants. */
static Array _meta_values(
  Compiler c, Var callee, List arguments, Token site) {
  List params = NULL;
  match (callee) case %((func ?declared) *): params = declared;
  Array values = [];
  foreach (List argument, arguments) {
    Type want = NULL;
    if (params) {
      want = params.car();
      params = params.cdr();
    }
    values.push(c.meta_argument(argument, want, site, _meta_call_value));
  }
  return values;
}

/* The session's binding of `name`, binding an included native function on
   first use. The project meta build's own parse has no helper yet, so a
   call to a project function there is left for the translation. */
static Var _meta_function(Compiler c, String name, Token site) {
  Var function = void;
  if (!c.macro_lisp.try_get(name, function) && c.bind_native_meta(name))
    c.macro_lisp.try_get(name, function);
  if (function is void && c.meta_build) raise %(meta-later (name $name));
  if (function is void)
    c.report_error(
      <macro>, "explicit meta call cannot be resolved", site,
      %("no binding for $name"));
  return function;
}

/* native meta functions

   A bodyless `meta` prototype declares a native function compile-time code
   may call. Its advertisement reaches other units through their
   interfaces, and each binds the function on first use. */

/** The shallow interface retains the advertisement separately from the C
    declaration. That lets a client install the trusted evaluator binding
    without repeating the marker in every translation unit. */
void Compiler.record_native_meta_effect(
  Compiler c, List declaration, Token marker) {
  String path = home_portable_path(Path.absolute(c.filename));
  List key = %("source-node" (declaration $path ${marker.pos}));
  if (declaration.type_from_ast().is_function()) {
    Type type = declaration.type_from_ast().canonicalize();
    String name = _native_meta_name(c, declaration, marker);
    List signature = c.func_signature(type);
    c.sym.set(key, %(native-meta $name $signature));
  }
}

static String _native_meta_name(Compiler c, List declaration, Token marker) {
  String name = NULL;
  match (declaration)
    case %(declare ? (bindings (bind (binding ? ?(String spelling)) *))):
      name = spelling;
  if (!name)
    c.report_error(
      <parse>, "native meta function requires one direct name", marker, NULL);
  return name;
}

/** Records the native advertisements retained by included interfaces. Each
    binds on first use, so a unit with no compile-time code pays nothing. */
void Compiler.install_native_meta_effects(Compiler c, Map globs) {
  String unit = Path.absolute(c.filename);
  foreach (Var (key, value), globs) {
    if (_local_effect(unit, key)) continue;
    foreach (List row, _native_meta_rows(c, value)) {
      (String name, List signature) = row;
      c.native_meta[name] = signature;
      _certify_native_meta(c, name, signature, NULL);
    }
  }
}

static int _local_effect(String unit, Var key) {
  match (key)
    case %("source-node" (declaration ?(String path) ?)):
      return home_absolute_path(path).equal(unit);
  return 0;
}

/** Binds an included native `meta` function the first time compile-time
    code calls `name`. Returns whether the macro session now binds it. A
    macro import can call one during the caller's collection pass, before
    the parse installs the advertisements, so the first lookup there
    installs the ones visible so far. */
int Compiler.bind_native_meta(Compiler c, String name) {
  Var signature, bound;
  if (!c.native_meta.len())
    c.install_native_meta_effects(_visible_symbols(c));
  if (!c.native_meta.try_get(name, signature)) return 0;
  _bind_native_meta(c, name, signature, NULL);
  return c.macro_lisp.try_get(name, bound);
}

/* The unit's base symbols with the current scope's rows merged in. */
static Map _visible_symbols(Compiler c) {
  Map symbols = c.sym.base_symbols();
  Map current = c.sym.current_symbols();
  if (current) symbols.merge(current);
  return symbols;
}

/** Installs a prototype-only `meta` function from the compiler's trusted
    native target registry. The declaration keeps its ordinary runtime form.
*/
void Compiler.install_native_meta_function(
  Compiler c, List declaration, Token marker) {
  Type type = declaration.type_from_ast().canonicalize();
  String name = _native_meta_name(c, declaration, marker);
  if (!c.collect_protocols) c.run_declaration_effects();
  _ensure_lisp(c);
  List signature = c.func_signature(type);
  c.native_meta[name] = signature;
  _bind_native_meta(c, name, signature, marker);
}

/* One declared native function while it binds. An iterator operation's
   `target` is `NAME_into`, and `suppliers` lists the selected modules that
   define the target. */
typedef struct NativeBinding {
  Compiler c, String name, target, List signature, suppliers, Token marker;
  int iterator;
} NativeBinding;

/* Binds a declared native function to the compiler's own linked target of
   the same name, or an iterator operation to its `_into` target, or else to
   a selected native module's target. A declaration with neither binds
   nothing, and a meta body that calls it reports the missing binding. */
static void _bind_native_meta(
  Compiler c, String name, List signature, Token marker) {
  _certify_native_meta(c, name, signature, marker);
  int iterator = _iterator_operation(signature);
  String target = iterator ? %"${name}_into" : name;
  NativeBinding n = {
    .c = c, .name = name, .target = target, .signature = signature,
    .suppliers = _native_module_suppliers(target), .marker = marker,
    .iterator = iterator};
  Var bound, function;
  int present = c.macro_lisp.try_get(name, bound);
  if (present && !iterator) function = bound;
  else {
    try function = n.linked();
    catch %(no-symbol *): {
      /* Staged code that calls it cannot link; the call reports why. */
      if (!n.suppliers) {
        c.meta_group_bound[%"<unbound $name>"] = 1;
        return;
      }
      function = n.module_target();
    }
  }
  n.check(function);
  if (!present) n.install(function);
}

/* The compiler's own linked target, which hides any module's. */
static Var NativeBinding.linked(NativeBinding *n) {
  Compiler c = n.c;
  Var function = c.macro_lisp.eval(
    %(bind ${n.target} (quote ${n.signature})));
  if (n.suppliers)
    c.report_warning(
      <native>, "the compiler's own function hides a native module's",
      n.marker, %("name: ${n.name}"));
  return function;
}

static Var NativeBinding.module_target(NativeBinding *n) {
  String first = n.suppliers.car();
  return ((Map) native_modules[first])[n.target];
}

/* A second module that defines the function is reported, and the
   declaration must match the target it binds. */
static void NativeBinding.check(NativeBinding *n, Var function) {
  Compiler c = n.c;
  String name = n.name;
  List suppliers = n.suppliers;
  if (suppliers.cdr() &&
      function.equal(((Map) native_modules[suppliers.car()])[n.target]))
    c.report_warning(
      <native>, "more than one native module defines this function",
      n.marker, %("name: $name" "supplied by: ${suppliers.car()}"
                  "also defined by: ${", ".join(suppliers.cdr())}"));
  if (!c.native_meta_accepts(function, n.signature))
    c.report_error(
      <type>, "native meta function declaration does not match its target",
      n.marker, %("name: $name" "signature: ${n.signature.repr()}"));
}

/* An iterator operation binds through a call that allocates the
   destination a call omits. */
static void NativeBinding.install(NativeBinding *n, Var function) {
  Compiler c = n.c;
  if (n.iterator) {
    int arity = n.signature.car().list().cadr().list().len() - 1;
    function = c.macro_lisp.eval(
      %(C.iterator.call (quote $function) $arity));
  }
  c.macro_lisp.set_global(n.name, function);
}

/** Answers whether the native target `function` matches the declared
    `signature`. A declared `Func` parameter matches a target's `Var`
    parameter, which takes the compile-time callable and adapts it. Aliases
    of one native type match each other. */
int Compiler.native_meta_accepts(Compiler c, Var function, List signature) {
  if (function is not <func>) return 0;
  List target = _native_signature_type(
    c, ((Func) function.pointer()).signature());
  match (signature)
    case %((func ?(List parameters)) *result): {
      List boxed = parameters.search_replace(%("Func"), %("Var"));
      return target.equal(_native_signature_type(c, signature)) ||
             target.equal(_native_signature_type(c, %((func $boxed) @result)));
    }
  return 0;
}

/* The native type a signature names: each parameter, reference target,
   and result with its aliases resolved. */
static List _native_signature_type(Compiler c, List signature) {
  match (signature)
    case %((func ?(List parameters)) *result): {
      Array resolved = [];
      foreach (Type parameter, parameters)
        resolved.push(_native_parameter(c, parameter));
      Type native = c.sym.normalize_declared_type(result);
      return %((func ${resolved.list_free()}) @native);
    }
  return signature;
}

static List _native_parameter(Compiler c, Type parameter) {
  if (parameter.car() == <&> || parameter.car() == <opt-ref>)
    return cons(
      parameter.car(), c.sym.normalize_declared_type(parameter.cdr()));
  return c.sym.normalize_declared_type(parameter);
}

/** Returns the selected file-backed native module that supplies `name`,
    with its native `type`, or NULL for a linked or absent target. */
String Compiler.native_meta_module(Compiler c, String name, Type &type) {
  if (!c.bind_native_meta(name)) return NULL;
  List suppliers = _native_module_suppliers(name);
  if (!suppliers) return NULL;
  String path = suppliers.car();
  if (!path.startswith("/")) return NULL;
  Var target = ((Map) native_modules[path])[name];
  Var bound;
  if (!c.macro_lisp.try_get(name, bound) || !bound.equal(target)) return NULL;
  type = ((Func) target.pointer()).signature();
  return path;
}

/* The paths of the selected native modules that define `name`, in order. */
static List _native_module_suppliers(String name) =>
  native_module_order.filter(
    %!(String path) => name in ((Map) native_modules[path]));

/* native lifetimes

   A `meta` body's region walk needs to know what a native function's
   result owns. A function without a runtime row takes the summary its
   signature implies, or is rejected where it is declared. */

/* A native function without a runtime row takes the summary its signature
   implies, so a `meta` body's walk knows what its result owns. */
static void _certify_native_meta(
  Compiler c, String name, List signature, Token marker) {
  if (Compiler.has_region_row(name)) return;
  List summary = _native_meta_summary(c, signature);
  if (summary) {
    c.meta_regions[name] = summary;
    return;
  }
  if (marker)
    c.report_error(
      <type>, "unproved native meta lifetime", marker,
      %("name: $name" "signature: ${signature.repr()}"
        "it might return or keep its argument; ownership cannot be inferred"));
}

/* The region summary of a native function without a runtime row, from its
   signature: a returned handle is a fresh allocation in the active Scope,
   and a handle argument is borrowed for the call. A function that takes a
   handle and returns one, neither owned by its cleanup, might return or
   keep its argument, so it has none. */
static List _native_meta_summary(Compiler c, List signature) {
  match (signature) case %((func ?(List parameters)) *result): {
    int takes = 0, gives = _native_handle(c, result, 0);
    foreach (List parameter, parameters)
      takes = takes ||
              (_native_handle(c, parameter, 1) &&
               !_native_owned(c, parameter));
    if (takes && gives && !_native_owned(c, result)) return NULL;
    return gives ? %(1 ()) : %(0 ());
  }
  return %(0 ());
}

/* Whether a signature type is a native handle: storage the evaluator
   cannot hold as a value, so its lifetime is unknown without a region row.
   Scalars and the value types are not; a parameter pointing at one is an
   input or an output the call finishes with before it returns. */
static int _native_handle(Compiler c, List type, int parameter) {
  match (type) {
    case %((!quote *) *pointee) if (parameter):
      return pointee.equal(%(void)) || _native_handle(c, pointee, 0);
    case %((!or "Var" "Symbol" "String" "List" "Array" "Map" "Func")):
      return 0;
  }
  Symbol tag = c.sym.var_tag_for_type(type, NULL);
  if (tag == <var> || tag == <symbol> || tag == <string> ||
      tag == <list> || tag == <array> || tag == <map> || tag == <func>)
    return 0;
  type = c.sym.normalize_declared_type(type);
  foreach (Var part, type) if (part is not Symbol || part == <*>) return 1;
  return 0;
}

/* Whether a handle's own cleanup owns it: a runtime class, or a type that
   adopts `Var` or `Cleanup`. A signature spells a `typedef struct X *X`
   handle as its pointer, so the adoption is read from the typedef `X`. */
static int _native_owned(Compiler c, List type) {
  match (type) case %((!quote *) struct ?(String tag)): type = %($tag);
  return c.sym.var_tag_for_type(type, NULL) ||
         c.protocol_members_for(type, %("Var")) ||
         c.protocol_members_for(type, %("Cleanup"));
}

/* native target inventory

   The native functions interface rows advertise, as `lib/lisp.x`
   generates its target inventory from them. */

/* Returns the declared native targets advertised by `meta` interface rows,
   in the row form `lib/lisp.x` generates its target inventory from, or only
   those declared in the files `paths` names when it is not empty. Sorting
   makes that inventory independent of Map order. */
static List _native_meta_targets(List paths) {
  Compiler compiler = Compiler.expanding();
  if (!compiler) return %();
  Map selected = {};
  foreach (Var (key, value), compiler.sym.base_symbols()) {
    if (paths && !_declared_in(key, paths)) continue;
    foreach (List row, _native_meta_rows(compiler, value)) {
      (String name, List signature) = row;
      if (_takes_callback(signature)) continue;
      String into = %"${name}_into";
      selected[name] = _iterator_operation(signature)
        ? %($name (as $into)) : %($name);
    }
  }
  Array names = selected.keys();
  List rows = %();
  foreach (String name, names.sort()) rows = cons(selected[name], rows);
  return rows.reverse();
}

/* Whether the symbol row under `key` was declared in one of the absolute
   source `paths`. */
static int _declared_in(Var key, List paths) {
  match (key)
    case %("source-node" (declaration ?(String path) ?)):
      return home_absolute_path(path) in paths;
  return 0;
}

/* The native functions one symbol row makes available to compile-time code,
   as `(name signature)` rows: a bodyless `meta` prototype, or each witness
   of a `meta protocol` adoption. */
static List _native_meta_rows(Compiler c, Var row) {
  match (row) {
    case %(native-meta ?name ?signature): return %(($name $signature));
    case %(meta-protocol ?(Type base) ?(Type participant)):
      return _witness_rows(c, base, participant);
  }
  return %();
}

/* The witnesses include the forwarding function the conformance generates
   for a base default. An adoption that does not resolve makes none
   available. */
static List _witness_rows(Compiler c, Type base, Type participant) {
  List conformance = c.protocol_members_for(participant, base);
  List rows = %();
  if (!conformance) return rows;
  foreach (List member, conformance.last().list().cdr())
    match (member) {
      case %(? implmntd ?(String name) ?(Type type) *):
        rows = cons(%($name ${c.func_signature(type)}), rows);
      case %(?(String name) base-dflt ? ?(Type type) ordinary ?): {
        String forward = %"${participant.car()}_$name";
        rows = cons(%($forward ${c.func_signature(type)}), rows);
      }
    }
  return rows;
}

/* A Lisp callable reaches native code as a `Var`, so a native function that
   takes a `Func` binds through an adapter row in `lib/lisp.x`. */
static int _takes_callback(List signature) {
  match (signature)
    case %((func ?(List parameters)) *): return %("Func") in parameters;
  return 0;
}

/* An iterator operation takes its destination last. Its native target is
   `NAME_into`, and compile-time code calls it through `NAME`, which
   allocates the destination when a call omits it. */
static int _iterator_operation(List signature) {
  match (signature)
    case %((func ?(List parameters)) "Iter"):
      return parameters && parameters.last().equal(%("Iter"));
  return 0;
}

static List _sdk_meta_targets(void) => _native_meta_targets(NULL);

/* A native module's entry exports the prototypes its own sources declare,
   and a module that declares none is a mistake. */
static List _sdk_meta_declared(List paths) {
  List rows = _native_meta_targets(paths);
  if (!rows)
    _sdk_reject(
      "native module sources declare no meta function",
      %("declare each exported function with a bodyless meta prototype"));
  return rows;
}

/* linked meta definitions

   The shipped `meta` definitions compiled into the compiler
   (`src/linked-meta.x`) are a native module no request selects. A unit's
   definition binds its linked copy when the definition texts hash the
   same. */

static String linked_supplier = "<linked>";
static Map linked_hashes = NULL;

/** Binds the bodied `meta` definition `fn`, of function type `type`, to the
    compiler's linked copy of it when the two definition texts hash the
    same, instead of staging it. Returns whether it did; an edited
    definition is staged as user code.
*/
int Compiler.bind_linked_meta(Compiler c, List fn, Type type) {
  String name = NULL;
  match (fn)
    case %(function ? (bind (binding ? ?(String own)) *) ?): name = own;
  if (!name) return 0;
  Map linked = _linked_module();
  Var function, bound;
  if (!linked.try_get(name, function)) return 0;
  if (!_linked_copy(c, name, linked)) return 0;
  if (!c.collect_protocols) c.run_declaration_effects();
  _ensure_lisp(c);
  if (!c.native_meta_accepts(function, c.func_signature(type))) return 0;
  /* The shared session binds the copy once for every unit that imports the
     same file. */
  if (!c.macro_lisp.try_get(name, bound) || bound.equal(%()))
    c.macro_lisp.set_global(name, function);
  if (c.meta_reaches_compile_time(fn)) _record_comptime(c, name);
  return 1;
}

/* The linked module's targets, loaded with the definition hashes on first
   use. */
static Map _linked_module(void) {
  if (!Compiler.native_module_loaded(linked_supplier)) {
    Compiler.add_native_module(linked_supplier, linked_meta_targets);
    $scope(&native_module_scope) linked_hashes = linked_meta_hashes();
  }
  return native_modules[linked_supplier];
}

/* A row without a hash is the runtime library's own compiled definition
   of a `lib/meta.x` builder, which has no copy to compare; only
   `lib/meta.x` itself binds it. */
static int _linked_copy(Compiler c, String name, Map linked) {
  if (name in linked_hashes) return _linked_texts_match(c, name, linked, {});
  return c.filename &&
    Path.absolute(c.filename) == %"${x2c_get_root()}/lib/meta.x";
}

/* Whether the unit's definition `name` and every definition of the unit it
   reaches through references are the texts compiled into the linked
   copies, which freeze their callees into their own code. A reached
   runtime builder without a hash is the runtime's own definition. */
static int _linked_texts_match(
  Compiler c, String name, Map linked, Map reached) {
  Var hash, own, names;
  if (name in reached || !c.meta_hashes.try_get(name, own)) return 1;
  reached[name] = 1;
  if (linked_hashes.try_get(name, hash)) {
    if (!hash.equal(own)) return 0;
  }
  else if (!(name in linked)) return 0;
  if (c.meta_calls.try_get(name, names))
    foreach (String callee, (List) names)
      if (!_linked_texts_match(c, callee, linked, reached)) return 0;
  return 1;
}

/** Answers `x2c.meta.definition.hashes`, declared in `lib/meta.x`. */
Map x2c_meta_definition_hashes(void) {
  _sdk_guard("x2c.meta.definition.hashes");
  return sdk_compiler.meta_hashes;
}

/* native modules

   A native module is a shared library whose entry returns its targets.
   Loading runs its code inside the compiler, so a module loads only on
   request, once per process, and never unloads. */

/* Each loaded native module's name-to-`Func` Map by absolute path, and the
   paths the current request names, in its order. A module stays loaded for
   the process, so its Map lives in a Scope that lasts as long, while each
   request binds only the modules it names. */
static Map native_modules = NULL;
static List native_module_order = NULL;
static Scope native_module_scope = NULL;

/** Selects the loaded native modules, by absolute path, that bodyless `meta`
    prototypes bind in the current request. The first module in `paths`
    that defines a name supplies it.
*/
void Compiler.select_native_modules(List paths) {
  if (!Compiler.native_module_loaded(compiler_supplier))
    Compiler.add_native_module(compiler_supplier, _compiler_targets);
  Array linked = [];
  for (struct _Extension *e = extensions; e; e = e.next) {
    String key = %"<${String.new(e.name)}>";
    if (!Compiler.native_module_loaded(key))
      Compiler.add_native_module(key, e.targets);
    linked.push(key);
  }
  paths = %($compiler_supplier @paths @{linked.list_free()});
  paths.try_own();
  native_module_order = paths;
}

/** Selects package `name`'s native module, when it has one, after the
    modules already selected, and records it as a prerequisite of the unit.
    The module is `<root>/builds/<name>.module`; a worker loads it itself
    when the process has not. A module from another compiler, or one on a
    platform that loads none, is reported at the import `token`.
*/
void Compiler.select_package_module(
  Compiler c, String name, String root, Token token) {
  String module = %"$root/builds/$name.module";
  if (Compiler.links_extension(name) || !Path.is_file(module)) return;
  if (!X2C_NATIVE_MODULES)
    c.report_error(
      <driver>, "native modules are not supported on this platform", token,
      %("package: $name" "module: $module"));
  c.add_translation_dependency(module);
  if (!Compiler.native_module_loaded(module))
    _load_package_module(c, name, module, token);
  if (module in native_module_order) return;
  $scope(&native_module_scope) {
    native_module_order = native_module_order.append(%($module));
    native_module_order.try_own();
  }
}

static void _load_package_module(
  Compiler c, String name, String module, Token token) {
  if (_module_stamp(module) != 1)
    c.report_error(
      <driver>,
      %"package '$name' was built by another compiler; rebuild it", token,
      %("module: $module"));
  _open_native_module(module);
}

/** Loads the native module at `path` once per process and returns its
    absolute path. Loading runs the module's code inside the compiler, so it
    happens only on request. A module from another compiler, a file that is
    not a module, or an unsupported platform prints a diagnostic and exits.
*/
String Compiler.load_native_module(String path) {
  if (!X2C_NATIVE_MODULES)
    x2c_driver_error("native modules are not supported on this platform");
  String absolute = Path.absolute(path);
  if (Compiler.native_module_loaded(absolute)) return absolute;
  int stamp = _module_stamp(path);
  if (stamp < 0) x2c_driver_error(%"not an x2c native module: $path");
  if (!stamp)
    x2c_driver_error(
      %"native module '$path' was built by another compiler; rebuild it");
  _open_native_module(absolute);
  return absolute;
}

/** Loads the native module at absolute `path` when this compiler built it
    and the platform loads modules. A process that loads a module before it
    forks translation workers lets them inherit it; anything else is left
    for the import to report.
*/
void Compiler.preload_native_module(String path) {
  if (X2C_NATIVE_MODULES && !Compiler.native_module_loaded(path) &&
      _module_stamp(path) == 1)
    _open_native_module(path);
}

/* Reads the stamp in the bytes of the module at `path`. Loading runs a
   module's code, so a module from another compiler is rejected before it
   is loaded. */
static int _module_stamp(String path) {
  String expected = build_module_stamp();
  if (!expected)
    x2c_driver_error(
      %"cannot read the running compiler to check native module '$path'");
  File input = fopen(path, "rb");
  if (!input)
    x2c_driver_error(
      %"cannot read native module '$path': ${String.new(strerror(errno))}");
  fseek(input, 0, SEEK_END);
  long end = ftell(input);
  rewind(input);
  char *data = Scope.malloc(end > 0 ? (size_t) end : 1);
  size_t size = end > 0 ? fread(data, 1, (size_t) end, input) : 0;
  input.close();
  int stamp = _stamp_in(data, size, expected);
  Scope.free(data);
  return stamp;
}

/* 1 when the bytes hold one stamp and it names the running compiler, 0
   when it names another compiler or there is more than one, and -1 when
   they hold none. */
static int _stamp_in(char *data, size_t size, String expected) {
  String marker = "x2c-module-stamp:";
  int stamps = 0, current = 0, width = expected.len();
  for (size_t i = 0; i + marker.len() <= size; i++)
    if (!memcmp(data + i, marker, marker.len())) {
      stamps++;
      current = i + width <= size && !memcmp(data + i, expected, width);
    }
  return !stamps ? -1 : stamps == 1 && current;
}

/* Opens the module at absolute `path`, whose stamp was checked, and records
   its targets. A module is never unloaded, because its Funcs borrow its
   code. */
static void _open_native_module(String path) {
  void *handle = _module_handle(path);
  if (!handle)
    x2c_driver_error(
      %"cannot load native module '$path': ${String.new(dlerror())}");
  Map (*entry)(void) = (Map (*)(void)) dlsym(handle, "x2c_module_targets");
  if (!entry) x2c_driver_error(%"not an x2c native module: $path");
  Compiler.add_native_module(path, entry);
}

/* The module's constructors allocate its Funcs and literals, which last
   as long as its code. */
static void *_module_handle(String path) {
  $scope(&native_module_scope) return dlopen(path, RTLD_NOW | RTLD_LOCAL);
}

/** Records the name-to-`Func` Map that the entry of the native module loaded
    from absolute `path` returns. The Funcs, names, signatures, and path last
    for the process.
*/
void Compiler.add_native_module(String path, Map (*entry)(void)) {
  Map targets = _module_targets(path, entry);
  path.try_own();
  foreach (Var (name, target), targets) {
    name.string().try_own();
    ((Func) target.pointer()).signature().try_own();
  }
}

static Map _module_targets(String path, Map (*entry)(void)) {
  $scope(&native_module_scope) {
    if (!(void *) native_modules) {
      Scope.shutdown_hook(_native_module_shutdown);
      native_modules = {};
    }
    Map targets = entry();
    native_modules[path] = targets;
    return targets;
  }
}

/** Reports whether the native module at absolute `path` is loaded. */
int Compiler.native_module_loaded(String path) =>
  (void *) native_modules && path in native_modules;

/** Returns the name-to-`Func` Map of the loaded native module at absolute
    `path`. */
Map Compiler.native_module_targets(String path) => native_modules[path];

/** Reports whether the compiler itself supplies the native function `name`.
    Such a function exists only inside a compiler, so a `meta` function that
    reaches it has no runtime form.
*/
int Compiler.supplies_native_meta(String name) {
  Var targets;
  return (void *) native_modules &&
         native_modules.try_get(compiler_supplier, targets) &&
         name in ((Map) targets);
}

/* linked extensions

   The packages whose compile-time parts are linked into the compiler. Each
   registers from a constructor, before the runtime starts, so the list is
   plain C storage that lasts for the process. */

static struct _Extension {
  const char *name;
  Map (*targets)(void);
  struct _Extension *next;
} *extensions = NULL;

/** Registers package `name`'s compile-time part, linked into the compiler,
    whose `targets` returns its name-to-`Func` Map. The registration unit
    `x2c build --extension` generates calls it from a constructor.
*/
void x2c_register_extension(const char *name, Map (*targets)(void)) {
  struct _Extension *extension = malloc(sizeof *extension);
  if (!extension) abort();
  *extension = (struct _Extension) { name, targets, extensions };
  extensions = extension;
}

/** Reports whether package `name`'s compile-time part is linked into the
    compiler, so its import loads no module. */
int Compiler.links_extension(String name) {
  for (struct _Extension *e = extensions; e; e = e.next)
    if (!strcmp(name, e.name)) return 1;
  return 0;
}

/** Returns the archive of the linked packages' objects that the build of
    this compiler kept beside it, named by the compiler's identity, or NULL
    when the compiler links none. Project meta code links it. */
String Compiler.extension_archive(void) =>
  extensions ? %"${x2c_get_executable()}.extensions/"
               + %"${x2c_compiler_identity()}.a" : NULL;

// sdk rejection

/* A rejection reports at the active invocation and never returns, so the
   rejected operation's caller cannot continue with a missing answer. With
   no active invocation it is a bad state. */
static void _sdk_reject(String message, List notes) {
  Compiler compiler = lisp_compiler;
  if (compiler)
    compiler.report_error(<macro>, message, lisp_site, notes);
  raise %(bad-state (operation "x2c SDK rejection") (why $message));
}

// SDK operations reject use outside an active expansion.
static void _sdk_guard(String operation) {
  if (!sdk_compiler)
    _sdk_reject(%"$operation used outside macro expansion", NULL);
}

// sdk syntax queries

/** Answers `x2c.syntax.type`, declared in `lib/meta.x`. */
List x2c_syntax_type(List value) {
  _sdk_guard("x2c.syntax.type");
  match (value) {
    case %(expr ? ?): {
      Type type = value.cadr();
      return type.canonicalize();
    }
    case %(param ? ?):  return value.type_from_ast().canonicalize();
    case %((!or declare decl typedef) *):
      return value.type_from_ast().canonicalize();
  }
  List binding = NULL;
  if (binding_identity_try_parts(value, NULL, NULL)) binding = value;
  else
    match (value)
      case %((!or ident bind) (*) *): binding = value.cadr();
  if (binding) {
    Type type = _sdk_binding_type(binding);
    return type.canonicalize();
  }
  return value.type().canonicalize();
}

static List _sdk_binding_type(List binding) =>
  sdk_compiler.semantic_binding_facts()[
    %(type $binding)
  ];

/** Answers `x2c.protocol.member`, declared in `lib/meta.x`. */
List x2c_protocol_member(
  List participant, List base, String member) {
  List conformance =
    sdk_compiler.protocol_members_for(participant, base);
  if (!conformance) return %();
  foreach (List row, conformance.last().list().cdr()) {
    (String row_member, Symbol status, String source, Type signature,
     Symbol default_kind, Type template) = row;
    (void) default_kind; (void) template;
    if (status != <implmntd> || row_member != member) continue;
    List binding = sdk_compiler.sym.lookup(%($source), NULL);
    if (binding) return %(expr $signature (ident $binding));
    return %();
  }
  return %();
}

/** Answers `x2c.method.resolve`, declared in `lib/meta.x`. */
List x2c_method_resolve(List type_value, String name) {
  _sdk_guard("x2c.method.resolve");
  if (!name.is_identifier())
    _sdk_reject(
      "x2c.method.resolve requires an identifier String",
      %("value: ${name.repr()}"));
  Type type = type_value;
  List resolution = sdk_compiler.resolve_postfix_member(
    type, %($name), <.>, 1);
  match (resolution) {
    case %(ambiguous *packages): {
      Array notes = [];
      foreach (String package, packages)
        notes.push(%"package: '$package'");
      String owner = type.base_type().car().str();
      _sdk_reject(
        %"method '$owner.$name' is provided by multiple imported packages",
        notes.list_free());
    }
    case %(method ?binding ?signature):
      return %(expr $signature (ident $binding));
  }
  return %();
}

static Var _sdk_bindings(List declaration) {
  Array result = [];
  match (declaration)
    case %((!or declare decl typedef) ? (bindings *bindings)):
      foreach (List binding, bindings)
        match (binding) {
          case %(bind (!set ?identity (binding ? ?)) *): {
            List bound = identity;
            List type = _sdk_binding_type(bound);
            result.push(%(expr $type (ident $bound)));
          }
          case %(op = (bind (!set ?identity (binding ? ?)) *) ?): {
            List bound = identity;
            List type = _sdk_binding_type(bound);
            result.push(%(expr $type (ident $bound)));
          }
          case %(bind ?name ?mods): {
            List row = %(
              declare ${declaration.cadr()}
                (bindings (bind $name $mods))
            );
            result.push(%(expr ${row.type_from_ast()} (ident $name)));
          }
          case %(op = (bind ?name ?mods) ?): {
            List row = %(
              declare ${declaration.cadr()}
                (bindings (bind $name $mods))
            );
            result.push(%(expr ${row.type_from_ast()} (ident $name)));
          }
        }
  return result.list_free();
}

/* This reads the symbol table only, so it serves any compile-time Lisp
   evaluation, not just an active macro expansion. */
static Var _sdk_function_reference(String name) {
  Compiler compiler = lisp_compiler;
  if (!compiler) raise %(bad-state (operation "_x2c.function.reference"));
  Type type = NULL;
  List binding = compiler.sym.lookup(%($name), type);
  if (!binding || !type || !type.is_function()) return %();
  return %(expr $type (ident $binding));
}

// sdk type queries

/** Answers `x2c.type.integral?`, declared in `lib/meta.x`. */
int x2c_type_is_integral(List value) => value.type().is_integral();

/** Answers `x2c.type.pointer?`, declared in `lib/meta.x`. */
int x2c_type_is_pointer(List value) =>
  value.type().canonicalize().is_pointer();

/** Answers `x2c.type.element`, declared in `lib/meta.x`. */
List x2c_type_element(List value) =>
  value.type().canonicalize().dereference().canonicalize();

/** Answers `x2c.type.parameters`, declared in `lib/meta.x`. */
List x2c_type_parameters(List value) =>
  _sdk_function_type_parameters(value.type().canonicalize());

static List _sdk_function_type_parameters(Type type) {
  while (type.is_pointer() || type.is_array()) type = type.dereference();
  return type.match_replace(%((func ?params) *), <?params>);
}

/** Answers `x2c.type.return`, declared in `lib/meta.x`. */
List x2c_type_return(List value) =>
  value.type().canonicalize().apply().canonicalize();

/** Answers `x2c.type.parts`, declared in `lib/meta.x`. */
List x2c_type_parts(List value) => value.type().declaration_parts();

/** Answers `x2c.type.reverse-name`, declared in `lib/meta.x`. */
String x2c_type_reverse_name(String base, String participant) {
  _sdk_guard("x2c.type.reverse-name");
  return sdk_compiler.reverse_converter_spelling(
    base, "", participant);
}

/** Answers `x2c.type.resolve`, declared in `lib/meta.x`. */
List x2c_type_resolve(List value) {
  _sdk_guard("x2c.type.resolve");
  return sdk_compiler.sym.resolve_key(value).type_from_ast();
}

/** Answers `x2c.type.layout`, declared in `lib/meta.x`. */
List x2c_type_layout(List value) {
  _sdk_guard("x2c.type.layout");
  Type type = sdk_compiler.sym.resolve_key(value).type_from_ast();
  return sdk_compiler.sym.field_order(type).cdr();
}

/** Answers `x2c.type.value?`, declared in `lib/meta.x`. */
int x2c_type_is_value(List value) {
  _sdk_guard("x2c.type.value?");
  Type type = value.type().canonicalize();
  match (type) case %((bitfield ?) *rest): type = rest;
  foreach (String name, %("Symbol" "Var" "Atom" "String" "List"))
    if (sdk_compiler.sym.is_named_value_type(type, name)) return 1;
  return sdk_compiler.sym.resolve_key(type).is_number();
}

/** Answers `x2c.type.tag-name`, declared in `lib/meta.x`. */
Symbol x2c_type_tag_name(String name) {
  _sdk_guard("x2c.type.tag-name");
  String file = _source_file(sdk_compiler, sdk_compiler.filename);
  file = sdk_compiler.display_path(file);
  String identity = %"$file:$name";
  unsigned hash = identity.hash();
  const char *alphabet = "abcdefghijklmnopqrstuvwxyz*+?!-";
  char encoded[9] = { 'c' };
  for (int i = 1; i < 8; i++) {
    encoded[i] = alphabet[hash % 31];
    hash /= 31;
  }
  return Symbol.new(encoded);
}

/** Answers `x2c.type.fields`, declared in `lib/meta.x`. */
List x2c_type_fields(List value) {
  _sdk_guard("x2c.type.fields");
  Type type = value;
  type = type.canonicalize();
  Type resolved = sdk_compiler.sym.resolve_key(type);
  if (!resolved || !resolved.is_aggregate_tag())
    _sdk_reject(
      "x2c.type.fields requires a struct or union Type",
      %("value: ${value.repr()}"));
  List metadata = sdk_compiler.sym.field_order(resolved);
  if (!metadata)
    _sdk_reject(
      "x2c.type.fields requires a complete struct or union Type",
      %("value: ${value.repr()}"));
  Array named = [];
  foreach (List row, metadata.cdr())
    if (row.car().truth()) named.push(row);
  return named.list_free();
}

// sdk names and functions

/** Answers `x2c.binding.spelling`, declared in `lib/meta.x`. */
String x2c_binding_spelling(Var syntax) {
  _sdk_guard("x2c.binding.spelling");
  if (syntax is <string>) {
    String spelling = syntax;
    if (spelling.is_identifier()) return spelling;
    _sdk_reject(
      "x2c.binding.spelling requires an identifier spelling",
      %("value: ${syntax.repr()}" ));
  }
  if (syntax is not <list> || syntax.is_nil())
    _sdk_reject(
      "x2c.binding.spelling requires binding syntax",
      %("value: ${syntax.repr()}" ));
  List value = syntax;
  match (value)
    case %(expr ? (? *)): value = value.caddr();
  match (value) {
    case %(ident (*)):     value = value.cadr();
    case %(bind (*) ?):    value = value.cadr();
  }
  match (value)
    case %((!is ?name type string)): return name;
  return _binding_spelling(value, syntax);
}

static String _binding_spelling(List value, Var syntax) {
  int identity = 0, String spelling = NULL;
  match (value)
    case %(binding ?id (!is ? type string)):
      if (!id.is_integer() || id.integer() > INT_MAX)
        _sdk_reject(
          "x2c.binding.spelling requires a known binding",
          %("binding: ${value.repr()}"));
  if (!binding_identity_try_parts(value, identity, spelling))
    _sdk_reject(
      "x2c.binding.spelling requires an identifier or binding",
      %("value: ${syntax.repr()}" ));
  Var registered =
    sdk_compiler.semantic_binding_facts()[%(known $identity)];
  if (registered is not <string> || !registered.string().equal(spelling))
    _sdk_reject(
      "x2c.binding.spelling requires a known binding",
      %("binding: ${value.repr()}" ));
  return spelling;
}

/** Answers `x2c.ident`, declared in `lib/meta.x`. */
List x2c_ident(String spelling) {
  _sdk_guard("x2c.ident");
  if (!spelling.is_identifier()) _sdk_reject(
    "x2c.ident requires an identifier spelling",
    %("value: ${spelling.repr()}" ));
  return %("x2c.ident" $spelling);
}

static Var _sdk_ident_unique(String stem) {
  _sdk_guard("_x2c.name.unique");
  if (!stem.is_identifier()) _sdk_reject(
    "_x2c.name.unique requires an identifier stem",
    %("value: ${stem.repr()}" ));
  String spelling = sdk_compiler.fresh_name(%"macro_$stem");
  return sdk_compiler.sym.introduce(spelling);
}

/** Answers `x2c.function.name`, declared in `lib/meta.x`. */
String x2c_function_name(List function) {
  List identity = function.match_replace(
    %(function ? (bind ?binding ?) ?), <?binding>);
  return x2c_binding_spelling(identity);
}

/** Answers `x2c.function.parameter`, declared in `lib/meta.x`. */
List x2c_function_parameter(List function, String wanted) {
  List parameters = function.match_replace(
    %(function ? (bind ? ((fnmod (params *bound)) *)) ?), %(*bound));
  foreach (List parameter, parameters) {
    match (parameter) {
      case %(param ? (bind ?identity *)):
        if (x2c_binding_spelling(identity) == wanted) {
          Type type = parameter.type_from_ast().canonicalize();
          return %(expr $type (ident $identity));
        }
    }
  }
  _sdk_reject(
    %"x2c.function.parameter cannot find '$wanted'",
    %("function: ${x2c_function_name(function).repr()}"));
}

/* A native binding stores the same signature as an ordinary Func adapter. */
static List _sdk_native_type(List syntax) {
  match (syntax)
    case %(function ?rtype ?declarator ?):
      return sdk_compiler.func_signature(
        %(declare $rtype (bindings $declarator)).type_from_ast());
  return sdk_compiler.func_signature(x2c_syntax_type(syntax));
}

/* Lisp-built signatures become cached literals of the expanding unit. */
static List _sdk_literal_list(List values) =>
  sdk_compiler.cache_literal_list(values);

static Var _sdk_symbol_set(List values) {
  _sdk_guard("_x2c.symbol-set");
  foreach (Var value, values)
    if (value is not <symbol>)
      _sdk_reject(
        "_x2c.symbol-set requires Symbols",
        %("value:" ${value.repr()}));
  int duplicate = -1;
  List expression = sdk_compiler.symbol_set_expression(
    values, duplicate);
  if (duplicate >= 0)
    _sdk_reject(
      "_x2c.symbol-set requires distinct Symbols",
      %("symbol:" ${values.getindex(duplicate).repr()}));
  return expression;
}

// sdk source and literals

/** Answers `x2c.source.text`, declared in `lib/meta.x`. */
String x2c_source_text(Var syntax) => _sdk_source_text(syntax);

static Var _sdk_source_text(Var value) {
  match (value) case %((text ?(String text)) (file ?) (syntax ?)): return text;
  _sdk_guard("x2c.source.text");
  Var stored = void;
  Var key = ((ulong) value.u64);
  if (!sdk_captures ||
      !sdk_captures.try_get(key, stored))
    _sdk_reject(
      "x2c.source.text requires complete captured syntax",
      sdk_references ? NULL : %("value: ${value.repr()}"));
  List source = stored;
  int begin = source.caddr(), end = source.last();
  return String.new_len(sdk_compiler.text + begin, end - begin);
}

/** Answers `x2c.embed.text`, declared in `lib/meta.x`. */
String x2c_embed_text(Var path) => _sdk_embed_text(path);

static Var _sdk_embed_text(Var requested) {
  Compiler compiler = sdk_compiler;
  if (!compiler)
    _sdk_reject(
      "x2c.embed.text used outside macro expansion", NULL);
  String source_file = sdk_file, requested_path = NULL;
  if (requested is <string>) requested_path = requested;
  else requested_path = _embed_literal(requested, source_file);
  if (!requested_path.len())
    _sdk_reject(
      "x2c.embed.text requires a non-empty path", NULL);
  String path = _embed_path(compiler, source_file, requested_path);
  if (compiler.sources) return _embed_source(compiler, path);
  return _embed_file(compiler, path);
}

static String _embed_literal(Var requested, String &source_file) {
  Var stored = void, syntax = requested;
  match (requested)
    case %((text ?) (file ?(String file)) (syntax ?carried)): {
      syntax = carried;
      stored = %(source $file);
    }
  if (stored is void && sdk_captures)
    sdk_captures.try_get(((ulong) requested.u64), stored);
  String requested_path = NULL;
  if (stored is void || !_literal_string(syntax, requested_path))
    _sdk_reject(
      "x2c.embed.text requires a String or captured String literal",
      %("value: ${requested.repr()}"));
  List source = stored;
  source_file = source.cadr();
  return requested_path;
}

static String _embed_source(Compiler compiler, String path) {
  String text;
  if (!compiler.read_source(path, text))
    _sdk_reject(
      "cannot read embedded text",
      %("path: ${compiler.display_path(path)}"));
  compiler.deps.merge_translation_dependency(
    path, "%08x".printf(text.hash()));
  return text;
}

static String _embed_file(Compiler compiler, String path) {
  File file = _open_embed_file(compiler, path);
  String result = _read_embed_file(compiler, path, file);
  String content_hash = "%08x".printf(result.hash());
  compiler.deps.merge_translation_dependency(path, content_hash);
  return result;
}

static File _open_embed_file(Compiler compiler, String path) {
  struct stat info;
  if (!stat(path, &info) && !S_ISREG(info.st_mode))
    _sdk_reject(
      "embedded text is not a regular file",
      %("path: ${compiler.display_path(path)}"));
  File file = NULL, int open_failed = 0;
  try file = path.open("r");
  catch %((!or not-found io-fail) *): open_failed = 1;
  if (open_failed)
    _sdk_reject(
      "cannot open embedded text",
      %("path: ${compiler.display_path(path)}"));
  if (file.stat(&info) || !S_ISREG(info.st_mode)) {
    file.close();
    _sdk_reject(
      "embedded text is not a regular file",
      %("path: ${compiler.display_path(path)}"));
  }
  if ((uintmax_t) info.st_size >= INT_MAX) {
    file.close();
    _sdk_reject(
      "embedded text exceeds the String size limit",
      %("path: ${compiler.display_path(path)}"));
  }
  return file;
}

static String _read_embed_file(Compiler compiler, String path, File file) {
  String result = NULL;
  int read_failed = 0, embedded_nul = 0, size_overflow = 0;
  try result = file.string_close();
  catch %(io-fail *): read_failed = 1;
  catch %(bad-arg *): embedded_nul = 1;
  catch %(size-limit *): size_overflow = 1;
  if (read_failed)
    _sdk_reject(
      "cannot read embedded text",
      %("path: ${compiler.display_path(path)}"));
  if (embedded_nul)
    _sdk_reject(
      "embedded text contains an embedded NUL",
      %("path: ${compiler.display_path(path)}"));
  if (size_overflow)
    _sdk_reject(
      "embedded text exceeds the String size limit",
      %("path: ${compiler.display_path(path)}"));
  return result;
}

static int _literal_string(Var syntax, String &value) {
  match (syntax)
    case %(expr ? (literal ? ?(String source))): {
      int quoted = source.len() >= 2 && source[0] == '"' &&
        source[source.len() - 1] == '"';
      int percent_quoted = source.len() >= 3 && source[0] == '%' &&
        source[1] == '"' && source[source.len() - 1] == '"';
      if (quoted || percent_quoted) {
        value = source.parse();
        return 1;
      }
    }
  return 0;
}

/** Answers `x2c.literal.value`, declared in `lib/meta.x`. */
Var x2c_literal_value(Var syntax) {
  _sdk_guard("x2c.literal.value");
  String value = NULL;
  if (_literal_string(syntax, value)) return value;
  match (syntax) case %(expr ? (literal (int) ?(String digits))): {
    long parsed = 0;
    if (digits.try_long(&parsed)) return parsed;
  }
  match (syntax) case %(expr ? (literal ("Symbol") ? ?(Symbol tag))): {
    Symbol found = tag;
    return found;
  }
  _sdk_reject(
    "x2c.literal.value requires a String, int, or Symbol literal",
    %("value: ${syntax.repr()}"));
}

// sdk invocations and diagnostics

static Var _sdk_invocation_location(void) {
  if (!sdk_compiler || !lisp_site)
    _sdk_reject(
      "x2c invocation location used outside macro expansion", NULL);
  return sdk_compiler.token_location(lisp_site);
}

/** Answers `x2c.invocation.file`, declared in `lib/meta.x`. */
String x2c_invocation_file(void) =>
  ((List) _sdk_invocation_location()).assoc(<file>);

/** Answers `x2c.invocation.line`, declared in `lib/meta.x`. */
int x2c_invocation_line(void) =>
  ((List) _sdk_invocation_location()).assoc(<line>);

/** Answers `x2c.invocation.column`, declared in `lib/meta.x`. */
int x2c_invocation_column(void) =>
  ((List) _sdk_invocation_location()).assoc(<column>);

/** Answers `x2c.diagnostic.fail`, declared in `lib/meta.x`. */
void x2c_diagnostic_fail(String message, List notes) {
  _sdk_guard("x2c.diagnostic.fail");
  foreach (Var note, notes)
    if (note is not <string>)
      _sdk_reject(
        "x2c.diagnostic.fail notes must be Strings",
        %("value: ${note.repr()}" ));
  _sdk_reject(message, notes);
}

/** A warning reports where it is raised and returns, so a macro can keep
   expanding. Failure stays separate because it never returns. */
void x2c_diagnostic_warn(String message, List notes) {
  _sdk_guard("x2c.diagnostic.warn");
  foreach (Var note, notes)
    if (note is not <string>)
      _sdk_reject(
        "x2c.diagnostic.warn notes must be Strings",
        %("value: ${note.repr()}" ));
  sdk_compiler.report_warning(
    <macro>, message, sdk_compiler.token, notes);
}

// meta parameter descriptions

/** Returns what a `meta` parameter declared `Type` receives for the captured
    syntax `value`: `((name N) (kind K) (type T) (fields F) (methods M))`.
    `T` is the canonical type of `value` and `N` its name, or "" when it has
    none. `K` is `struct`, `union`, `enum`, `pointer`, `scalar`, or `other`,
    `F` lists the `(name type)` rows of a struct or union's named fields,
    and `M` the names of its direct dotted methods. */
List meta_type_description(Var value) {
  Type type = x2c_syntax_type(value);
  Type shape = x2c_type_resolve(type);
  String name = "";
  match (type) {
    case %(?(String own)): name = own;
    case %((!or struct union enum) ?(String own)): name = own;
    default:
      if (_symbol_words(type) && !type.is_pointer()) {
        Array words = [];
        foreach (Var word, type) words.push(word.str());
        name = " ".join(words);
      }
  }
  Var kind = <other>;
  List fields = %();
  match (shape) {
    case %((!or struct union enum) *): kind = shape.car();
    default:
      if (shape.is_pointer()) kind = <pointer>;
      else if (_symbol_words(shape)) kind = <scalar>;
  }
  if (kind == <struct> || kind == <union>) fields = x2c_type_fields(type);
  Compiler c = sdk_compiler;
  Array methods = [];
  foreach (String member, c.postfix_completions(type, <.>))
    match (c.resolve_postfix_member(type, %($member), <.>, 1))
      case %(method * *): methods.push(member);
  return %((name $name) (kind $kind) (type $type) (fields $fields)
           (methods ${methods.list_free()}));
}

/* Whether the type `type` is spelled by keywords alone, such as `(int)`. */
static int _symbol_words(List type) {
  foreach (Var word, type) if (word is not <symbol>) return 0;
  return type != NULL;
}

/** Returns what a `meta` parameter declared `Source` receives for the
    captured syntax `value`: `((text T) (file F) (syntax value))`, where `T`
    is the text the developer wrote and `F` the file it is in. */
List meta_source_description(Var value) {
  String text = _sdk_source_text(value);
  List source = sdk_captures[((ulong) value.u64)];
  return %((text $text) (file ${source.cadr()}) (syntax $value));
}

// built-in algorithm operations

/** Returns the typed expression naming the function `name`, or an empty
    List when no function of that name is visible. */
List builtin_foreach_reference(String name) => _sdk_function_reference(name);

/** Returns a fresh binding whose spelling starts with `name`. */
Var builtin_foreach_unique(String name) => _sdk_ident_unique(name);

/** Returns `expression` with the iterator chain `foreach` reads completed. */
List builtin_foreach_complete(List expression) =>
  _sdk_iter_chain(expression);

/** Returns the collection `foreach` iterates for `expression`, promoting a
    String literal. */
List builtin_foreach_collection(List expression) =>
  _sdk_string_collection(expression);

/** Returns an expression reading each binding `declaration` declares. */
List builtin_foreach_bindings(List declaration) =>
  _sdk_bindings(declaration);

/** Returns the location of the active macro invocation. */
List builtin_class_location(void) => _sdk_invocation_location();

/** Returns the `Func` signature of the function syntax `function`. */
List binding_native_type(List function) =>
  _sdk_native_type(function);

/** Returns `values` as a cached literal of the expanding unit. */
List binding_literal_list(List values) => _sdk_literal_list(values);

static Var _sdk_iter_chain(List expression) {
  _sdk_guard("private foreach iterator completion");
  return sdk_compiler.complete_iter_chain(expression);
}

static Var _sdk_string_collection(List expression) {
  _sdk_guard("private foreach string conversion");
  return sdk_compiler.promote_string_literal(expression);
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
