/*  expansion.x -- macro invocation, expansion, and syntax landing
*/

#pragma once

/* expansion

   Expanding an invocation node matches its capture rows against the
   definition's pattern, adds a binding for each fresh name and member
   hole, fills the template, and binds the result at the invocation's
   position with the invocation as its origin. */

/* One expansion. `direct` holds the bindings that fresh names and member
   holes add to the pattern's captures. */
static typedef struct Expansion {
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
    .c = c, .definition = c._stored_definition(stored, invocation),
    .input = arguments, .invocation = invocation};
  int block_scope = x.definition.assoc(<kind>) == <decorator> &&
                    x.definition.assoc(<target>) == <block>;
  if (block_scope) c.sym.push_new_scope();
  defer if (block_scope) c.sym.pop_scope();
  $let(c.token, invocation) {
    x.check();
    List result = NULL;
    $let(c.expansion_floor,
         c.macro_stack ? c.expansion_floor : c.names.next_binding)
    $let(c.macro_stack, c.macro_stack) {
      result = x.bind(position);
    }
    return result;
  }
}

/* The definition a node names: a visible macro, a local macro, or a Macro
   value whose references bind in this unit. */
module List Compiler._stored_definition(
  Compiler c, Var stored, Token invocation) {
  List definition = NULL;
  if (stored.is_atom())
    definition = c._lookup(Atom.intern(stored.str()), invocation);
  else match (stored)
    case %(local-macro ?name):
      definition = c.sym.lookup_macro(Atom.intern(name.str()));
  return definition ? definition : stored;
}

/* An identical recursive expansion, nesting deeper than 64, or more than
   10000 expansions stops the compile. A leaf template's application
   cannot recurse, so it is neither compared nor counted. An application
   compiler code makes has no invocation token. It lowers the program, so
   it is not counted either. */
static void Expansion.check(Expansion &x) {
  Compiler c = x.c;
  int leaf = x.definition.assoc(<leaf>) == 1;
  if (!leaf)
    foreach (List active, c.macro_stack) {
      (List prior, List prior_input, Var bindings, Var site) = active;
      (void) bindings, (void) site;
      if (prior == x.definition && prior_input == x.input)
        x.recursion();
    }
  if (c.macro_stack.len() >= 64) x.too_deep();
  if (leaf || !x.invocation) return;
  if (c.macro_count >= 10000)
    $report.macro.expansion_count(c, x.invocation);
  c.macro_count++;
}

static void Expansion.recursion(Expansion &x) {
  Atom name = x.definition.assoc(<name>);
  String spelling = name.str();
  List captured = x.input.search_replace(
    %(capture (source ?syntax) *), <?syntax>);
  Var shown = _source_unwrap(captured);
  $report.macro.expansion_recursive(
    x.c,
    spelling, x.invocation, _definition_note(x.definition), shown);
}

static void Expansion.too_deep(Expansion &x) {
  /* Compiler-generated applications can have no invocation token. */
  List first = x.c.macro_stack.last().list().car();
  $report.macro.expansion_depth(
    x.c,
    x.invocation, _definition_note(x.definition), _definition_note(first));
}

/* Pushes this expansion's frame on the macro stack, fills the template,
   and binds the result. A failed match binds nothing. */
static List Expansion.bind(Expansion &x, AstPos position) {
  Compiler c = x.c;
  List old_stack = c.macro_stack;
  x.template = x.definition.assoc(<template>);
  /* An application compiler code makes has no invocation token. What it
     authors belongs to the source being lowered, so it carries no anchors
     of its own. */
  if (!x.invocation)
    x.template = x.template.search_replace(%(at m-origin ?node), <?node>);
  List fresh_input = x.fresh_names(old_stack);
  List match_input = fresh_input
    ? x.input.append(%((fresh @fresh_input))) : x.input;
  List replacement_bindings = match_input.match(
    x.definition.assoc(<pattern>));
  int matched = !!replacement_bindings;
  replacement_bindings = replacement_bindings.append(x.direct);
  List template_bindings = NULL;
  List lisp_bindings = _lisp_bindings(
    replacement_bindings, template_bindings);
  c.macro_stack = %(
    (${x.definition} ${x.input} $lisp_bindings ${x.invocation}) @old_stack
  );
  int expansion_origin = c.record_origin(x.invocation);
  int placed = c.placements.len();
  Ast constructed = matched ? x.construct(template_bindings) : NULL;
  List result = NULL;
  $let(c.origin, expansion_origin) {
    result = c.bind_syntax(
      matched ? constructed : void,
      position, c.return_type);
  }
  c.close_placements(placed, result);
  return result;
}

/* Allocates each fresh name of the definition. A name compile-time Lisp
   reads joins the match input as a Name capture row; the others, with the
   member holes, bind directly. Returns the Name rows. */
static List Expansion.fresh_names(Expansion &x, List old_stack) {
  Compiler c = x.c;
  Map file_locals = {};
  // The outermost active row's fourth field is its invocation token.
  Token root = old_stack ? old_stack.last().list()[3] : x.invocation;
  if (c.sym.at_file_scope()) _file_scope_locals(%(${x.template}), file_locals);
  Array fresh_values = [];
  foreach (List fresh, x.definition.assoc(<fresh>).list()) {
    Var (binder, spelling, lisp) = fresh;
    Token owner = binder in file_locals ? root : NULL;
    if (lisp.int()) {
      List binding = c._introduced_binding(spelling.str(), owner);
      List hole = _hole(binder, <name>, 0);
      fresh_values.push(c._capture_row_project(hole, %($binding), 0));
    }
    else
      x.direct = cons(
        %($binder ${c._private_name(spelling.str(), owner)}), x.direct);
  }
  List members = c._member_bindings(x.definition.assoc(<parameters>), x.input);
  x.direct = x.direct.append(members);
  return fresh_values.list_free();
}

/* A Name hole in a member position supplies the captured spelling, so a
   template local passed there keeps the spelling its source wrote. */
static List Compiler._member_bindings(
  Compiler c, List parameters, List input) {
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
    Var member = _hole_key(parameter, "member");
    bindings = cons(
      %($member ${c._member_spelling(capture.assoc(<value>))}), bindings);
  }
  return bindings;
}

/* The spelling a Name hole's value supplies in a member position: the
   source spelling of a renamed local or a binding, or an `x2c_ident`
   value's own. */
static Var Compiler._member_spelling(Compiler c, Var value) {
  Var spelling;
  match (value) case %("x2c.ident" (!is ?name type string)): return name;
  if (value is not <list>) return value;
  if (c.semantic_binding_facts().try_get(%(source-spelling $value), spelling))
    return spelling;
  String name = binding_identity_spelling(value);
  return name ? name : value;
}

/* The bindings compile-time Lisp sees: the author's binders. The template
   receives the `__macro_` binders the compiler makes, so an author binder
   spelled in a template literal, such as a catch pattern's `?cause`, stays
   literal. */
static List _lisp_bindings(List bindings, List &template_bindings) {
  Array lisp = [], compiler = [];
  foreach (List pair, bindings) {
    Var binder = pair.car();
    if (binder.is_binder() &&
        !binder.str().startswith("?__macro_") &&
        !binder.str().startswith("*__macro_"))
      lisp.push(pair);
    else
      compiler.push(pair);
  }
  template_bindings = compiler.list_free();
  return lisp.list_free();
}

/* Declaration results and collected Unit results retain their declarations
   in one bundle, as does a NamedType decorator. */
static Ast Expansion.construct(Expansion &x, List bindings) {
  List definition = x.definition;
  Ast constructed = x.template.replace(bindings);
  if (constructed &&
      (definition.assoc(<kind>) == <decl-unit> ||
       (x.c.shallow && definition.assoc(<kind>) == <unit>) ||
       definition.assoc(<target>) == <named-type>)) {
    List rows = constructed.car() == <seq>
              ? constructed.cdr() : %($constructed);
    constructed = %(declaration-bundle (rows @rows));
  }
  return constructed;
}

/** Resolves a stored macro invocation marker to its source token.
    Nested template markers use the active expansion's invocation; unresolved
    markers return NULL.
*/
Token Compiler.macro_invocation_site(Compiler c, Var site) {
  if (site is <token>) return site;
  if (site != <m-invoke> || !c.macro_stack) return NULL;
  List active = c.macro_stack.car();
  (Var definition, Var input, Var bindings, Token invocation) = active;
  (void) definition, (void) input, (void) bindings;
  return invocation;
}

/* expansion names

   A fresh name gets a private spelling. At file scope a declaration with
   external or no linkage can reach another unit through a header or an
   interface, so its spelling is stable: collection and full parsing expand
   the same invocation to the same spelling. */

static List Compiler._introduced_binding(
  Compiler c, String source, Token root) =>
  c.sym.introduce(
    root ? c._file_scope_name(root, source)
         : c.fresh_name(%"macro_$source"));

/* A template local's name, which keeps its source spelling. */
static List Compiler._private_name(Compiler c, String source, Token root) {
  List binding = c._introduced_binding(source, root);
  c.set_fact(%(source-spelling $binding), source);
  return binding;
}

/* The spelling names the owning unit and the root invocation's offset, and
   counts repeats of the same name there. */
static String Compiler._file_scope_name(
  Compiler c, Token root, String source) {
  String key = %"macro:${c._scope_owner()}:${root.pos}:$source";
  Var stored;
  int count = c.names.counters.try_get(key, stored) ? stored : 0;
  c.names.counters[key] = count + 1;
  c.names.issued++;
  String digest = "%08x".printf(%"$key:$count".hash());
  return %"_x2c_macro_${source}_$digest";
}

/* The unit's owner spelling, cached per file and package. */
static String Compiler._scope_owner(Compiler c) {
  String owner = NULL;
  $memo(c.names.file_scope_owners, %(${c.filename} ${c.package}), owner) {
    owner = c.filename ? c._owner_spelling() : "";
  }
  return owner;
}

/* Home and package paths stay portable; other paths use their canonical
   absolute identity. */
static String Compiler._owner_spelling(Compiler c) {
  String path = c.canonical_path(Path.absolute(c.filename));
  String owner = home_portable_path(path);
  Var package_root = c.package ? c.package_roots[c.package] : void;
  if (package_root is not <string>) return owner;
  String prefix = %"${c.canonical_path(Path.absolute(package_root))}/";
  if (!path.startswith(prefix)) return owner;
  return %"package:${c.package}/${path[prefix.len():]}";
}

/* Collects the template locals that a file-scope row declares with external
   linkage or none: objects, functions, typedefs, tags, and enumerators,
   including those a nested invocation declares from this template's names. */
module void _file_scope_locals(List rows, Map locals) {
  foreach (Var row, rows) match (row) {
    case %((!or at src) ? ?inner): _file_scope_locals(%($inner), locals);
    case %(api-source ? ? ?inner): _file_scope_locals(%($inner), locals);
    case %(seq *inner): _file_scope_locals(inner, locals);
    case %(macro-invoke ((!quote !quote) ?(List definition))
           ?(List input) ?): {
      Map declared = {};
      _file_scope_locals(%(${definition.assoc(<template>)}), declared);
      List bindings = NULL;
      input.try_match(definition.assoc(<pattern>), bindings);
      foreach (List pair, bindings)
        if (pair.car() in declared && pair.cadr().is_binder())
          locals[pair.cadr()] = 1;
    }
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
    case $source_declarator_row(%(?binder ?)):
      if (binder.is_binder()) locals[binder] = 1;
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
  c._claims(c._peek_invocation(), position);

/* An invocation is claimed where its result fits. A statement or map entry
   that does not fit parses as an expression. Elsewhere a `$` name, or an
   identifier with arguments, is claimed so that its target parser reports
   the position diagnostic; a local expression macro at block scope remains
   an expression statement. */
static int Compiler._claims(Compiler c, List definition, AstPos position) {
  Symbol kind = definition ? _result_kind(definition) : 0;
  if (kind == _position(position).kind) return 1;
  if (position == AST_STATEMENT || position == AST_MAP_ENTRY) return 0;
  if (!definition) {
    if (c.peek(0) == <$> && (position == AST_BLOCK || c.macro_holes)) {
      String name;
      c._scan_name(name);
      Type type = name ? c.sym.get(%($name)) : NULL;
      if (type.is_function()) return 0;
    }
    return c.peek(0) == <$>;
  }
  return !_bare(c.token, definition) &&
    (position != AST_BLOCK || kind != <expression> ||
     !definition.assoc(<local>).int());
}

static typedef struct MacroPos {
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

module Symbol _result_kind(List definition) {
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
module List Compiler._peek_invocation(Compiler c) {
  Var stored;
  if (c.peek(0) == <$> || c.peek(0) == <@>) {
    String spelling;
    c._scan_name(spelling);
    if (!spelling ||
        !c._try_definition(Atom.intern(spelling), !c.shallow, stored))
      return NULL;
    return stored;
  }
  if (c.peek(0) != <ident>) return NULL;
  Atom name = Atom.intern(c.token.text);
  List definition = c.sym.has_local_macros()
                  ? c.sym.lookup_macro(name) : NULL;
  if (!definition && c._try_macro(c.kw_aliases, name, stored))
    definition = stored;
  return definition && (c.peek(1) == <(> || _bare(c.token, definition))
       ? definition : NULL;
}

/* Scans the dotted name after the current `$` without consuming tokens.
   A component after a dot may be a keyword, as in `$error.arg.void`.
   Returns the token after the name, or the token where a name component is
   missing with `spelling` set to NULL. */
module Token Compiler._scan_name(Compiler c, String &spelling) {
  Token token = c.token, String name = NULL;
  do {
    token = Token.skip_trivia(token + 1);
    if (token.type != <ident> &&
        !(name && scan_keyword_type(token.text, token.text.len()))) {
      name = NULL;
      break;
    }
    name = name ? %"$name.${token.text}" : token.text;
    token = Token.skip_trivia(token + 1);
  } while (token.type == <.>);
  spelling = name;
  return token;
}

/* An identifier invoking a decorator without explicit parameters has no
   argument list. */
static int _bare(Token invocation, List definition) =>
  invocation.type != <$> && invocation.type != <@> &&
  definition.assoc(<kind>) == <decorator> &&
  !definition.assoc(<parameters>).list();

/* Consumes the name of an invocation claimed at `position` and returns its
   definition, or returns NULL without consuming tokens. A `$` name that is
   neither visible nor followed by arguments is a replacement variable
   missing from a template. */
static List Compiler._take_invocation(Compiler c, AstPos position) {
  List definition = c._peek_invocation();
  if (!c._claims(definition, position)) return NULL;
  if (c.peek(0) != <$> && c.peek(0) != <@>) {
    c.next();
    return definition;
  }
  Token invocation = c.token;
  Atom name = c._name();
  Var existing;
  if (c.macro_holes && c.peek(0) != <(> &&
      !c._try_definition(name, 1, existing))
    c._unbound(name.str(), invocation);
  return c._lookup(name, invocation);
}

module Atom Compiler._name(Compiler c) {
  String spelling;
  Token end = c._scan_name(spelling);
  if (!spelling)
    $report.parse.macro_name(c, end);
  c.token = end;
  return Atom.intern(spelling);
}

module List Compiler._lookup(Compiler c, Atom name, Token invocation) {
  Var stored;
  String spelling = name.str();
  if (!c._try_definition(name, 1, stored))
    $report.parse.macro_unbound(c, spelling, invocation);
  return stored;
}

/* With `install_lisp`, a `lisp.` name records the Lisp binding macros as a
   dependency and installs them when the name is not yet defined. */
module int Compiler._try_definition(
  Compiler c, Atom name, int install_lisp, Var &stored) {
  int found = c._try_macro(c.macros, name, stored);
  String spelling = name.str();
  if (!install_lisp || !spelling.startswith("lisp.")) return found;
  c._use_lisp_bindings(!found);
  return found || c._try_macro(c.macros, name, stored);
}

/* Includes publish names immediately. Decode a template into this unit's
   bindings only when it is used, keeping the result in the same name map. */
module int Compiler._try_macro(
  Compiler c, Map definitions, Atom name, Var &stored) {
  if (!definitions.try_get(name, stored)) return 0;
  match (stored) case %(imported-macro ?definition): {
    stored = c._rebind_imported(c.thaw_declaration_syntax(definition));
    c.sym.put(definitions, name, stored);
  }
  return 1;
}

// shallow collection

/** Returns how collection treats the macro invocation at the cursor.
    `<required>` covers every file-scope `Unit` macro, declaration-unit macro,
    named-type decorator, and local `Unit` macro whose template contains
    protocol or adoption rows. `<tried>` covers Unit decorators and other
    local `Unit` macros. Other invocations return zero.
*/
Symbol Compiler.macro_invocation_collection(Compiler c) =>
  _collection(c._peek_invocation());

static Symbol _collection(List definition) {
  if (!definition) return 0;
  if (definition.assoc(<kind>) == <decl-unit> ||
      definition.assoc(<target>) == <named-type>) return <required>;
  if (definition.assoc(<target>) == <unit>) return <tried>;
  if (definition.assoc(<kind>) != <unit>) return 0;
  if (!definition.assoc(<local>).int()) return <required>;
  List template = definition.assoc(<template>), bindings;
  Var matched;
  if (template.try_search(%(!or (protocol *) (adopt *)), matched, bindings))
    return <required>;
  return <tried>;
}

/** Consumes a macro invocation name and its balanced argument list.
    The invocation terminator or following decorator target remains current.
*/
void Compiler.skip_macro_invocation(Compiler c) {
  int bare = _bare(c.token, c._peek_invocation());
  String spelling;
  if (c.peek(0) == <$>) c.token = c._scan_name(spelling);
  else c.next();
  if (!bare && c.peek(0) == <(>) c.token = c.token.after_group();
}

/** Collects a NamedType signature without executing its decorator.
    CPP and hash scanning skip targets already projected by their owner.
*/
int Compiler.skip_named_type_declaration(Compiler c) {
  List definition = c._peek_invocation();
  if (!definition || definition.assoc(<target>) != <named-type>) return 0;
  c.skip_macro_invocation();
  if (c.signature_only == SIGNATURE_DECLARATIONS) {
    (void) c.parse_named_type();
    return 1;
  }
  c._skip_shallow_expression(0);
  c.expect(<;>);
  return 1;
}

/** Reports whether the macro invocation at the cursor produces file-scope
    syntax, directly or through the target it decorates. A script unit keeps
    such an invocation at file scope. This query does not consume tokens.
*/
int Compiler.macro_targets_unit(Compiler c) {
  List definition = c._peek_invocation();
  if (!definition) return 0;
  Symbol kind = _result_kind(definition);
  return kind == <unit> || kind == <decl-unit>;
}

/* invocation arguments

   Each parameter hole captures its arguments into one capture row, and a
   captured argument records the source span it was parsed from. */

static List Compiler._invocation_arguments(
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
    arguments.push(c._argument_row(hole, kind));
    if (nodes.cdr() && c.peek(0) != <)>) c._argument_separator(kind);
  }
  if (c.peek(0) != <)>) {
    if (c.peek(0) == <,>) c.next();
    $report.parse.macro_extra_args(c);
  }
  c.expect(<)>);
  return %(args @{arguments.list_free()});
}

/* The arguments one hole captures: one, or a comma-separated sequence. A
   MatchRow hole also takes the directives around its rows. */
static List Compiler._argument_row(Compiler c, List hole, Symbol kind) {
  int sequence = hole.assoc(<sequence>);
  Array captured = [];
  if (c.peek(0) == <)> && !sequence)
    $report.parse.macro_missing_args(c);
  if (c.peek(0) != <)>) loop {
    c._row_directives(kind, captured);
    Token first = c.token;
    Var argument = c._parse_argument(kind);
    if (kind != <name>) argument = c._capture_source(argument, first, c.token);
    captured.push(argument);
    if (!sequence || !c.test(<,>)) break;
  }
  c._row_directives(kind, captured);
  return c._capture_row_project(hole, captured.list_free(), 0);
}

static void Compiler._row_directives(Compiler c, Symbol kind, Array captured) {
  if (kind == <match-row> && c.token != c.directives_taken)
    foreach (List directive, c.leading_preproc()) captured.push(directive);
}

/* `in` may separate a declaration from what follows, as in
   `foreach (String line in lines)`. Before a literal it scans as a name,
   which cannot follow a declaration either. */
static void Compiler._argument_separator(Compiler c, Symbol kind) {
  if (kind == <decl> && (c.peek(0) == <in> || c.at_word("in"))) c.next();
  else c.expect(<,>);
}

static Var Compiler._parse_argument(Compiler c, Symbol kind) {
  // Captures retain complete syntax even while collection skips other bodies.
  $let(c.shallow, 0) {
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
      case <name>:       return c._name_argument();
      case <literal>:    return c._literal_argument();
    }
    $report.macro.argument_contract(c);
  }
}

/* A caller's name is a spelling, resolved where the expansion places it.
   A name a template writes is private to each expansion: a nested
   declaration made from it is that expansion's, and a reference that no
   such declaration reaches reads its spelling where the expansion lands. */
static Var Compiler._name_argument(Compiler c) {
  if (c.macro_holes && c.peek(0) == <$>) return c._parse_hole(<name>);
  if (c.peek(0) != <ident>)
    $report.parse.name_identifier(c);
  String spelling = c.token.text;
  c.next();
  if (!c.macro_holes) return spelling;
  List visible = c.sym.lookup(%($spelling), NULL);
  if (visible && visible in c.macro_definition_locals()) return visible;
  List local = c.macro_introduced_name(spelling);
  c.bind_template_local(local, NULL, NULL);
  c.macro_definition_locals()[%(name-argument $spelling)] = local;
  return local;
}

static Var Compiler._literal_argument(Compiler c) {
  if (c.macro_holes && c.peek(0) == <$>) return c.parse_assignment();
  return c.parse_atomic_literal();
}

static Var Compiler._capture_source(
  Compiler c, Var syntax, Token first, Token after) {
  if (c.macro_holes || syntax is not <list> ||
      syntax.is_nil() || !first) return syntax;
  Token last = c._previous_source_token(after);
  if (!last || last < first) return syntax;
  int end = last.pos + last.len;
  String file = c.source_path(c.filename ? c.filename : "<stdin>");
  List source = %(source $file ${first.pos} $end);
  return %(src $source $syntax);
}

static Token Compiler._previous_source_token(Compiler c, Token after) {
  Token first = (void *) c.tokenizer.tokens;
  if (!after || after <= first) return NULL;
  Token token = after - 1;
  while (token > first &&
         (token.type == <space> || token.type == <comment> ||
          token.type == <preproc>)) token--;
  return token;
}

/* A Block decorator's Name arguments are referenced in the block's scope,
   which opens before the arguments are read. */
static void Compiler._bind_name_arguments(
  Compiler c, List definition, List arguments) {
  List parameters = definition.assoc(<parameters>);
  List captures = arguments.cdr();
  while (parameters) {
    List parameter = parameters.car();
    if (parameter.assoc(<kind>) == <name>) {
      Var names = captures.car().list().assoc(<value>);
      List values = parameter.assoc(<sequence>).int()
                  ? names : %($names);
      foreach (Var value, values) {
        String name = value is <list>
          ? binding_identity_spelling(value) : value;
        c.sym.reference(%($name), NULL);
      }
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

/* `retain` keeps each source as the syntax it is and forwards nothing. */
static List Compiler._capture_row_project(
  Compiler c, List hole, List sources, int retain) =>
  hole.assoc(<sequence>).int()
    ? c._sequence_row(sources, retain)
    : c._scalar_row(sources, retain);

/* A forwarded projection contributes its own sources, values, and
   construction requirements. */
static List Compiler._sequence_row(Compiler c, List sources, int retain) {
  Array captured_sources = [], values = [], construction = [];
  foreach (Var captured, sources) {
    List forwarded = retain ? NULL : c._forwarded_capture(captured);
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
static List Compiler._scalar_row(Compiler c, List sources, int retain) {
  int singular = sources && !sources.cdr();
  Var source = singular ? sources.car() : sources;
  if (singular && !retain) {
    List forwarded = c._forwarded_capture(source);
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
  match (value) case %("x2c.ident" ?): return %(expr () (ident $value));
  if (value is <list> && !value.is_nil() &&
      binding_identity_try_parts(value, NULL, NULL))
    return %(expr () (ident $value));
  return value;
}

/* The row of a projection a template forwards as an argument. A Unit
   hole's source stands for each of its projections. */
static List Compiler._forwarded_capture(Compiler c, Var captured) {
  List hole = c._forwarded_hole(captured);
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
static List Compiler._forwarded_hole(Compiler c, Var captured) {
  if (!c.macro_holes || captured is not <list> || captured.is_nil())
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
  return c._hole_record(Atom.intern(spelling[prefix.len():]));
}

static String _forwarded_prefix(String spelling) {
  foreach (String prefix, forwarded_prefixes)
    if (spelling.startswith(prefix)) return prefix;
  return NULL;
}

/* Forwarding recognizes the projection binders _capture_pattern creates, so
   the accepted prefixes come from Macro.binder; <?> supplies its
   empty author name. */
static List _forwarded_prefix_list(void) {
  Array prefixes = [];
  Map seen = {};
  foreach (String projection, %("expression" "value" "source" "splice"))
    for (int sequence = 0; sequence <= 1; sequence++) {
      String prefix = Macro.binder(<?>, projection, sequence).str();
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

/* `value` without its source wrappers. A pending invocation or quotation
   inside it keeps its own capture rows or holes, so nested applications
   unwrap each argument once. */
static Var _source_unwrap(Var value) {
  if (value is not <list> || value.is_nil()) return value;
  match (value) {
    case %(src ? ?syntax): return _source_unwrap(syntax);
    case %((!or macro-invoke "x2c.quoted") *): return value;
  }
  List child;
  $ast.rewrite_children(value.list(), child, _source_unwrap(child));
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
List Compiler.try_parse_macro_target_at(Compiler c, AstPos position) =>
  c._target_at(position, 0);

/* An `open` statement omits its final `;`, as an anonymous Stmt arrow's
   statement does. */
module List Compiler._target_at(Compiler c, AstPos position, int open) {
  if (c.macro_holes && c.peek_macro_hole()) return NULL;
  Token invocation = c.token;
  List definition = c._take_invocation(position);
  if (!definition) return NULL;
  if (definition.assoc(<kind>) == <decorator>)
    return c._decorate(definition, invocation, position, open);
  c._check_position(definition, invocation, position);
  return c._invoke_definition(definition, invocation, position, open);
}

/* A macro's result must fit where it is invoked; a Declaration result also
   fits at file scope. */
static void Compiler._check_position(
  Compiler c, List definition, Token invocation, AstPos position) {
  Symbol kind = definition.assoc(<kind>);
  const MacroPos *place = _position(position);
  if (kind == place.kind || (kind == <decl-unit> && position == AST_UNIT))
    return;
  Atom name = definition.assoc(<name>);
  String spelling = name.str(), result_kind = _kind_spelling(kind);
  $report.macro.result_position(
    c,
    spelling, result_kind, place.description, invocation);
}

/* Invocation parsing and expansion share one semantic transaction. Empty
   generated syntax and raised diagnostics therefore cannot leave provisional
   bindings, enumerators, statics, or generated-name state behind. */
static List Compiler._invoke_definition(
  Compiler c, List definition, Token invocation, AstPos position, int open) {
  int deferred = !!c.macro_holes || c.signature_only == SIGNATURE_DECLARATIONS;
  SymTxn transaction = c.begin_semantic_transaction();
  defer transaction.rollback();
  List input = c._invocation_arguments(definition, invocation);
  if (_position(position).semicolon && !open) c.expect(<;>);
  List node = c._invocation_node(definition, input, invocation);
  List result = deferred ? %(seq $node) :
    c.bind_syntax(node, position, c.return_type);
  if (result.car() != <seq> || result.len() != 1 ||
      transaction.local_macros_changed()) transaction.commit();
  return result;
}

/* Inside a template the node names its definition as the expansion will
   find it: a definition that is itself template syntax by value, a local
   macro by its local name, and any other macro by name. */
static List Compiler._invocation_node(
  Compiler c, List definition, List input, Token invocation) {
  Var stored = definition;
  Var site = invocation;
  if (c.macro_holes) {
    stored = c._stored_reference(definition);
    site = <m-invoke>;
  }
  return %(macro-invoke $stored $input $site);
}

/* A template names a visible local macro, so its expansion applies the
   definition published where it lands, with that expansion's names. */
static Var Compiler._stored_reference(Compiler c, List definition) {
  Atom name = definition.assoc(<name>);
  if (definition.assoc(<local>).int() &&
      c.sym.lookup_macro(name) == definition)
    return %(local-macro $name);
  if (definition.assoc(<template>)) return %(!quote $definition);
  return name;
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
static typedef struct Decoration {
  Compiler c, List definition, function, Token invocation, start;
  AstPos position, Symbol kind, int open;
} Decoration;

static List Compiler._decorate(
  Compiler c, List definition, Token invocation, AstPos position, int open) {
  Decoration d = {
    .c = c, .definition = definition, .invocation = invocation,
    .position = position, .kind = definition.assoc(<target>), .open = open};
  int deferred = !!c.macro_holes || c.signature_only == SIGNATURE_DECLARATIONS;
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

static int Decoration.on_body(Decoration &d) =>
  d.kind == <block> && d.position == AST_UNIT;

static void Decoration.misplaced(Decoration &d) {
  Atom name = d.definition.assoc(<name>);
  String spelling = name.str(), target = _kind_spelling(d.kind);
  $report.macro.decorator_position(d.c, spelling, target, d.invocation);
}

static List Decoration.arguments(Decoration &d, int block_scope) {
  Compiler c = d.c;
  List definition = d.definition;
  List arguments = c._invocation_arguments(definition, d.invocation);
  if (block_scope) c._bind_name_arguments(definition, arguments);
  if (c.peek(0) == <;>)
    $report.macro.decorator_semicolon(
      c,
      d.invocation, _definition_note(definition));
  if (c.peek(0) == <eof>) {
    Atom name = definition.assoc(<name>);
    String spelling = name.str();
    $report.macro.decorator_target(
      c,
      spelling, d.invocation, _definition_note(definition));
  }
  return arguments;
}

static List Decoration.node(Decoration &d, List arguments) {
  Compiler c = d.c;
  d.start = c.token;
  List target = d.target();
  if (d.position == AST_STATEMENT) target = c.anchor_origin(target, d.start);
  List target_capture = d.capture(target);
  List input = %(
    target $arguments
    $target_capture
  );
  return c._invocation_node(d.definition, input, d.invocation);
}

static List Decoration.target(Decoration &d) {
  Compiler c = d.c;
  if (d.on_body()) {
    d.function = c.parse_function_definition();
    match (d.function) case %(function ? ? ?body): return body;
    return NULL;
  }
  if (d.kind == <function>) return c.parse_function_target();
  if (d.kind == <named-type>) return c.parse_named_type();
  if (d.open) return c._arrow_statement(1);
  return c._positional_target(d.position);
}

static List Compiler._positional_target(Compiler c, AstPos position) {
  switch (position) {
    case AST_UNIT:
      $let(c.capture_unit, 1) return c.parse_top_level();
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
static List Decoration.capture(Decoration &d, List target) {
  Compiler c = d.c;
  List targets = target.car() == <seq> ? target.cdr() : %($target);
  Array captured_targets = [];
  foreach (Var item, targets)
    captured_targets.push(c._capture_source(item, d.start, c.token));
  List captured = captured_targets.list_free();
  List target_capture =
    c._capture_row_project(d.definition.assoc(<targetp>), captured, 0);
  if (d.kind == <unit> && !c._private_target(target) &&
      captured && !captured.cdr())
    target_capture = target_capture.append(%((construct ${captured.car()})));
  return target_capture;
}

/* Visibility comes from a static declaration,
   seen through a lone `seq` and a foreign alias. */
static int Compiler._private_target(Compiler c, List target) {
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

static List Decoration.bind(Decoration &d, List node) {
  Compiler c = d.c;
  if (!d.on_body()) return c.bind_syntax(node, d.position, c.return_type);
  return c._bind_body(node, d.function);
}

/* The body was bound with the function's own result type; bind the
   produced items with it too, so a `return` that needs a conversion still
   gets one. */
static List Compiler._bind_body(Compiler c, List node, List decorated) {
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
    List value = c._named_macro_value(invocation);
    if (value) return value;
  }
  if ((c.peek(0) == <$> || c.peek(0) == <@>) && !c._peek_invocation())
    return c._parse_meta_call(invocation);
  List definition = c._take_invocation(AST_EXPRESSION);
  if (!definition) return NULL;
  return c.resolve_expression(
    c._expression_invocation(definition, invocation), invocation);
}

/* Returns the Macro value a `$` name without arguments names. Otherwise the
   cursor returns to the `$`. */
static List Compiler._named_macro_value(Compiler c, Token invocation) {
  Atom name = c._name();
  if (c.peek(0) != <(>) {
    List value = c._macro_value(name);
    if (value) return value;
  }
  c.token = invocation;
  return NULL;
}

static List Compiler._parse_meta_call(Compiler c, Token invocation) {
  c.next();
  /* A meta function is called by its compile-time binding, even from a
     template, whose other free names bind where the expansion lands. */
  List callee = NULL;
  $let(c.macro_holes, NULL) callee = c.parse_variable();
  Type signature = callee.cadr();
  if (!signature.is_function()) {
    c.token = invocation;
    Atom name = c._name();
    (void) c._lookup(name, invocation);
  }
  Array arguments = c._meta_arguments(signature.car().list().cadr());
  Type result = c.macro_holes ? %(<macro-expr>) : signature.cdr();
  /* Inside a `meta` body the whole body runs at compile time, so a `$`
     call there is an ordinary call. */
  Symbol head = c.meta_body && !c.macro_holes ? <call> : <meta-call>;
  List call = %(expr $result ($head $callee
    (args @{arguments.list_free()})));
  return c.resolve_expression(call, invocation);
}

/* Each argument converts to its parameter's type, except in a template. */
static Array Compiler._meta_arguments(Compiler c, List parameters) {
  Array arguments = [];
  c.expect(<(>);
  if (c.peek(0) != <)>) loop {
    List argument = c._meta_argument();
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
static List Compiler._meta_argument(Compiler c) {
  List hole = c.peek_macro_hole();
  Symbol next = hole ? c.after_hole().type : 0;
  int direct = next == <,> || next == <)>;
  if (direct && hole.assoc(<sequence>).int()) {
    c.expect(<$>);
    c.next();
    return %(expr ("List") (meta-cap (${_hole_key(hole, "value")})));
  }
  Symbol kind = hole ? hole.assoc(<kind>) : 0;
  List argument = direct
    ? %(expr (<macro-expr>) ${c._parse_hole(kind ? kind : <argument>)})
    : c.parse_assignment();
  if (hole && argument.match(%(expr ? (macro-bind ?)))) {
    Atom projection = Macro.binder(hole.assoc(<binder>), "value", 0);
    argument = %(expr ("List") (meta-cap $projection));
  }
  return argument;
}

static List Compiler._expression_invocation(
  Compiler c, List definition, Token invocation) {
  Symbol kind = definition.assoc(<kind>);
  if (kind == <decorator> && definition.assoc(<target>) == <expr>)
    return c._expression_decorator(definition, invocation);
  if (c.meta_body && (kind == <unit> || kind == <block-item>))
    return c._template_call(definition);
  List arguments = c._invocation_arguments(definition, invocation);
  if (kind != <expression>) c._not_expression(definition, invocation);
  List node = c._invocation_node(definition, arguments, invocation);
  return %(expr (<macro-expr>) $node);
}

/* In a `meta` body, invoking a Unit or Stmt macro is a template call,
   whose syntax the meta function builds when it runs. */
static List Compiler._template_call(Compiler c, List definition) {
  Array arguments = [];
  c.expect(<(>);
  foreach (List hole, definition.assoc(<parameters>).list()) {
    if (arguments.len()) c.expect(<,>);
    arguments.push(c.parse_assignment());
  }
  c.expect(<)>);
  Var stored = definition.assoc(<local>).int()
    ? definition : definition.assoc(<name>);
  return %(expr ("List") (tpl-call $stored
    (args @{arguments.list_free()})));
}

static void Compiler._not_expression(
  Compiler c, List definition, Token invocation) {
  Symbol kind = definition.assoc(<kind>);
  String spelling = definition.assoc(<name>).str();
  $report.macro.result_expr(
    c,
    kind, spelling, invocation, _definition_note(definition));
}

static List Compiler._expression_decorator(
  Compiler c, List definition, Token invocation) {
  List arguments = c._invocation_arguments(definition, invocation);
  if (c.peek(0) == <;> || c.peek(0) == <eof>) {
    String spelling = definition.assoc(<name>).str();
    $report.macro.decorator_expr(
      c,
      spelling, invocation, _definition_note(definition));
  }
  List target = c.parse_macro_expression_target();
  List input = %(
    target $arguments
    ${c._capture_row_project(definition.assoc(<targetp>), %($target), 0)}
  );
  List node = c._invocation_node(definition, input, invocation);
  return %(expr (<macro-expr>) $node);
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
  if (slot.car() == "x2c.template") return c._helper_result(value);
  if (slot.car() != <macro-slot>) return value;
  if (c.macro_holes || !c.macro_stack) return value;
  return c._slot_value(slot);
}

/* A Lisp form evaluates with the active expansion's bindings, and a meta
   call runs. A construction requirement travels with an identifier the
   slot built, and a splice slot around a Unit target replaces the target
   among the items it produced. */
static Var Compiler._slot_value(Compiler c, List slot) {
  int splice = slot.cadr();
  Var form = slot.caddr();
  List active = c.macro_stack.car();
  (List definition, Var input, List bindings, Token invocation) = active;
  (void) input;
  String source_file = _definition_file(definition);
  Var required = slot.assoc(<construct>);
  Var result = form is <list>
    ? c.evaluate_meta_value(form, invocation, 1)
    : c._eval_template_form(form, bindings, invocation, source_file, required);
  result = c._helper_result(result);
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
    case %(!or (macro-invoke ? ? ?) ("x2c.quoted" ? ?)):
      return %(seq $result);
    case %(seq *): return result;
  }
  return %(seq @{result});
}

/** Evaluates a macro slot and returns its syntax as a row sequence.
    `(seq ...)` contributes its children; every other result contributes one
    row.
*/
List Compiler.evaluate_macro_rows(Compiler c, Var value) {
  value = c.evaluate_macro_slot(value);
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
static Var Compiler._eval_template_form(
  Compiler c, String form, List bindings, Token invocation,
  String source_file, Var construction) {
  c.run_declaration_effects();
  c.ensure_macro_lisp();
  unsigned long serial = template_serial++;
  /* Provenance lookup uses captured Var identity. Structural equality must
     not let constructed or selected syntax acquire a caller's source text. */
  Map source_captures = _source_captures(bindings);
  List references = c._bind_references(serial, bindings);
  if (references) form = _rewrite_references(form, references);
  if (construction is not void)
    form = c._with_construction(serial, form, construction);
  MetaContext *context = MetaContext.current();
  $let(context.has_bindings, !!references)
  $let(context.captures, source_captures)
  $let(context.definition_file, source_file)
  $let(context.expander, c)
    return c._eval_string(form, invocation);
}

/** Evaluates the explicit meta call `expression` at `site` with the active
    expansion's captures visible to the SDK. A nonzero `slot` marks a
    template slot, which reports a call the project meta build leaves. */
Var Compiler.evaluate_meta_value(
  Compiler c, List expression, Token site, int slot) {
  if (!c.collect_protocols) c.run_declaration_effects();
  c.ensure_macro_lisp();
  List active = c.macro_stack ? c.macro_stack.car() : NULL;
  List bindings = active ? active.caddr() : NULL;
  String source_file = active ? _definition_file(active.car()) : c.filename;
  MetaContext *context = MetaContext.current();
  $let(context.has_bindings, !!bindings)
  $let(context.captures, _source_captures(bindings))
  $let(context.definition_file, source_file)
  $let(context.expander, c)
  $let(context.evaluator, c)
  $let(context.site, site)
    return c.run_meta_call(expression, site, slot);
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

/* Binds each captured value to a scratch global and returns the
   `(spelling global)` rows, newest first. */
static List Compiler._bind_references(
  Compiler c, unsigned long serial, List bindings) {
  List references = NULL;
  foreach (List pair, bindings) {
    if (!pair) continue;
    Var (binder, syntax) = pair;
    String spelling = binder.str()[1:];
    String temporary = %"_x2c_meta_${serial}_$spelling";
    Var unwrapped;
    if (!_source_capture_parts(syntax, NULL, unwrapped))
      unwrapped = _source_unwrap(syntax);
    c.macro_lisp.set_global(temporary, unwrapped);
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
static String Compiler._with_construction(
  Compiler c, unsigned long serial, String form, Var construction) {
  String temporary = %"_x2c_meta_${serial}_construction";
  c.macro_lisp.set_global(temporary, construction);
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
  Compiler c, Atom callback, List arguments) {
  Token invocation = c.token;
  match (c.macro_stack)
    case %((? ? ? ?token) *): invocation = token;
  return c._eval_template_form(
    "(apply (eval $callback) $arguments)",
    %((?callback $callback) (?arguments $arguments)),
    invocation, c.filename, void);
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
  List definition = stored.is_atom() ? c._lookup(stored, site) : stored;
  return %(macro-invoke $stored
    ${c._template_arguments(definition, values, site, 0)}
    m-invoke);
}

/* The capture rows of a template call's values. A scalar Lisp value in an
   Expr hole lifts to an expression first. */
static List Compiler._template_arguments(
  Compiler c, List definition, List values, Token invocation,
  int retain_syntax) {
  Array rows = [];
  List holes = definition.assoc(<parameters>);
  for (; holes; holes = holes.cdr(), values = values.cdr())
    rows.push(
      c._hole_row(holes.car(), values.car(), invocation, retain_syntax));
  return %(args @{rows.list_free()});
}

/* One hole's capture row of `value`. Each scalar Lisp value an Expr hole
   or sequence holds lifts to an expression first. A Type hole's type names
   its type with a String. */
static List Compiler._hole_row(
  Compiler c, List hole, Var value, Token invocation, int retain_syntax) {
  Symbol kind = hole.assoc(<kind>);
  int lifts = kind == <expr>;
  String error = kind == <type> && value is <list>
               ? type_name_error(value) : NULL;
  if (error) $report.macro.type_name(c, error, invocation);
  if (!hole.assoc(<sequence>).int())
    return c._capture_row_project(
      hole, %(${lifts ? c._lifted(value, invocation) : value}), retain_syntax);
  List sources = value;
  if (lifts) {
    Array lifted = [];
    foreach (Var item, sources) lifted.push(c._lifted(item, invocation));
    sources = lifted.list_free();
  }
  return c._capture_row_project(hole, sources, retain_syntax);
}

/* A number, String, or Symbol becomes the literal expression that holds
   it; other values are already syntax. */
static Var Compiler._lifted(Compiler c, Var value, Token invocation) =>
  value.is_integer() || value.is_floating() || value is <string> ||
  value is <symbol> ? c.lift_macro_lisp_expression(value, invocation) : value;

/* A helper's result with each template call the helper left for the
   compiler replaced by its invocation. */
module Var Compiler._helper_result(Compiler c, Var value) {
  if (value is not <list> || value.is_nil()) return value;
  match (value) {
    case %((!or macrodef "x2c.quoted") *): return value;
    case %(code-value "lowered" *): return value;
    case $source_literal_content(%(*)): return value;
  }
  match (value) {
    case %("x2c.template" ?stored ?(List values)): {
      stored = c._helper_result(stored);
      values = c._helper_result(values);
      Token site = c.macro_invocation_site(<m-invoke>);
      if (!site) site = c.token;
      MetaContext *context = MetaContext.current();
      $let(context.expander, c)
      $let(context.site, site)
        return _sdk_template_call(
          stored is <string> ? Atom.intern(stored.str()) : stored, values);
    }
  }
  List child;
  $ast.rewrite_children(value.list(), child, c._helper_result(child));
}

/** Rebuilds an expression from a pending Macro value application, preserving
    its established root `type`, child stage, and source wrappers. Binding,
    capture collection, hygiene, and effects do not run, and a statement
    expression's template-origin wrappers are omitted. */
List Compiler.rebuild_expression(Compiler c, Type type, List application) {
  List rebuilt = c._rebuild(application, NULL);
  return %(expr $type @{rebuilt.cddr()});
}

/** Rebuilds a statement template as a canonical unbraced `seq`. Bound
    children keep their identities and origins; template-origin wrappers
    are omitted because this path does not open an invocation. */
List Compiler.rebuild_statement(Compiler c, List application) =>
  c._rebuild(application, NULL);

/** Constructs a fresh function from a Unit template after lowering. The
    caller supplies its bound name and lowered children; binding does not
    run. */
List Compiler.rebuild_unit_function(Compiler c, List application) {
  List function = c._rebuild(application, NULL).cadr();
  match (function) case %(api-source ? ? ?inner): return inner;
  return function;
}

/** Rebuilds a bound function through a Function decorator without binding it
    again. The template keeps the target's return type and declarator. */
List Compiler.rebuild_function(Compiler c, List target, List application) =>
  c._rebuild(application, target).cadr();

/* Substitute bound syntax into a structural template without binding it.
   The caller supplies complete children and a template with no free names,
   computed slots, or nested applications. The definition's rebuild row
   holds the template and, for each hole, the binders of the projections
   it uses. Quoted syntax fills its own holes and keeps their values. */
static List Compiler._rebuild(
  Compiler c, List application, List target) {
  match (application) case %("x2c.quoted" ? ?syntax): {
    Landing landing = {.c = c, .site = c.token, .retain = 1};
    return landing.fill(syntax);
  }
  (Var marker, List definition, List values) = application;
  (void) marker;
  List rebuild = definition.assoc(<rebuild>);
  (List template, List keys) = rebuild;
  List rows = c._template_arguments(definition, values, c.token, 1).cdr();
  if (target)
    rows = rows.append(
      %(${c._capture_row_project(
        definition.assoc(<targetp>), %($target), 1)}));
  List bindings = NULL;
  foreach (List row, rows) {
    bindings = _row_bindings(keys.car(), row, bindings);
    keys = keys.cdr();
  }
  return template.replace(bindings);
}

static List _row_bindings(List keys, List row, List bindings) {
  List fields = _row_fields(row);
  foreach (Var binder, keys) {
    if (binder != <?>) bindings = %(($binder ${fields.car()}) @bindings);
    fields = fields.cdr();
  }
  return bindings;
}

/* A capture row's source, value, expression, splice, return, and
   declarator projections. A sequence's value stands for its expression
   and splice, and a singular Function hole's value also supplies its
   return type and declarator. */
static List _row_fields(List row) {
  match (row) {
    case %(capture (source *sources) (value *values)):
      return %($sources $values $values $values () ());
    case %(capture (source ?source) (value ?value) (expression ?expression)
                   (splice *splice)): {
      List result = NULL, declarator = NULL;
      match (value) case %(function ?returned ?declared ?): {
        result = returned;
        declarator = declared;
      }
      return %($source $value $expression $splice $result $declarator);
    }
  }
  return NULL;
}

/* quoted syntax

   A quotation whose template applies no other template builds that
   template where it is written, as `("x2c.quoted" FRESH SYNTAX)`. Each
   use of a hole is `("x2c.hole" HOLE PROJECTION VALUE)`, holding the
   local's value, and each origin anchor is `("x2c.at" NODE)`. A FRESH
   row is `(BINDER SPELLING FILE)`, where FILE marks a name that a
   file-scope row declares with linkage. Landing fills the syntax as an
   expansion fills its template: it names the private binders, projects
   each hole as a capture row would, and keeps anchors only where an
   invocation lands it. Recovery gives binding a semantic transaction.
   It counts no expansion, since the template applies nothing. */

/* One landing of quoted syntax. `retain` keeps each hole's value as the
   syntax it is, as a rebuild does. */
static typedef struct Landing {
  Compiler c, Map names, Token site, int anchored, retain;
} Landing;

/** Binds quoted `syntax` with its `fresh` rows at `position`, as the
    expansion of its quotation would. */
List Compiler.land_quotation(
  Compiler c, List fresh, Var syntax, AstPos position, Type return_type) {
  Token site = c.macro_invocation_site(<m-invoke>);
  Landing landing = {
    .c = c, .site = site ? site : c.token, .anchored = !!site};
  List bound = NULL;
  $let(c.macro_application, c.macro_application + 1) {
    SymTxn transaction = { 0 };
    if (c.recovery_depth > 0)
      transaction = c.begin_semantic_transaction();
    defer transaction.rollback();
    landing.names = c._private_names(fresh);
    Var filled = landing.fill(c.thaw_declaration_syntax(syntax));
    $let(c.token, site)
    $let(c.origin, c.record_origin(site))
      bound = c.bind_syntax(filled, position, return_type);
    transaction.commit();
  }
  if (position == AST_BLOCK || position == AST_STATEMENT ||
      position == AST_UNIT)
    match (bound) case %(seq ?item): return item;
  return bound;
}

/* Each fresh binder's private name. */
static Map Compiler._private_names(Compiler c, List fresh) {
  if (!fresh) return NULL;
  Map names = {};
  // The outermost active row's fourth field is its invocation token.
  Token root = c.macro_stack ? c.macro_stack.last().list()[3] : NULL;
  int file_scope = c.sym.at_file_scope();
  foreach (List row, fresh) {
    (Var binder, Var spelling, Var file) = row;
    names[binder] = c._private_name(
      spelling.str(), file_scope && file.int() ? root : NULL);
  }
  return names;
}

/* The filled syntax. A hole that is a sequence or a splice contributes
   its items to the List that holds it. */
static Var Landing.fill(Landing &l, Var syntax) {
  Var name;
  if (syntax.is_binder())
    return (void *) l.names && l.names.try_get(syntax, name) ? name : syntax;
  if (syntax is not <list> || syntax.is_nil()) return syntax;
  List node = syntax;
  // Only the quoted forms have a String head.
  if (node.car() is <string>)
    match (node) {
      case %("x2c.at" ?inner): {
        Var filled = l.fill(inner);
        return l.anchored ? %(at m-origin $filled).var() : filled;
      }
      case %("x2c.hole" ?(List hole) ?projection ?value):
        return l.hole(hole, projection, value);
    }
  Array items = NULL;
  int index = 0;
  foreach (Var item, node) {
    List spliced = NULL;
    int splices = l.splices(item, spliced);
    Var filled = splices ? void : l.fill(item);
    if (!(void *) items && (splices || filled != item)) {
      items = [];
      List prior = node;
      for (int i = 0; i < index; i++, prior = prior.cdr())
        items.push(prior.car());
    }
    if (splices) foreach (Var each, spliced) items.push(each);
    else if ((void *) items) items.push(filled);
    index++;
  }
  return (void *) items ? items.list_free().var() : syntax;
}

/* Whether `item` is a sequence or splice hole, whose items it sets. */
static int Landing.splices(Landing &l, Var item, List &spliced) {
  if (item is not <list> || item.is_nil() || item.list().car() is not <string>)
    return 0;
  match (item) case %("x2c.hole" ?(List hole) ?projection ?value):
    if (projection == <splice> || hole.assoc(<sequence>).int()) {
      spliced = l.hole(hole, projection, value);
      return 1;
    }
  return 0;
}

/* A hole's projection of its value, as an expansion's capture row holds
   it. A shell is an Expr hole's expression in an expression position,
   which a rebuild leaves bare. */
static Var Landing.hole(Landing &l, List hole, Symbol projection, Var value) {
  Compiler c = l.c;
  if (projection == <member>) return c._member_spelling(value);
  if (!l.retain) value = c._helper_result(value);
  List row = c._hole_row(hole, value, l.site, l.retain);
  Symbol field = projection == <shell> ? <expression> : projection;
  Var projected = _row_fields(row)[
    %(source value expression splice).index(field)];
  if (projection != <shell> || l.retain) return projected;
  return %(expr (<macro-expr>) $projected);
}

