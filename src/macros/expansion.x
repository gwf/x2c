/*  expansion.x -- macro expansion and hygienic names */

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
    supplies author bindings, source location, and recursion checks; the
    definition's fresh rows allocate invocation-local names. This method does
    not begin a semantic transaction.
*/
List Compiler.expand_macro_invocation_node(
  Compiler c, Var stored, List arguments, Token invocation, Symbol position) {
  Expansion x = {
    .c = c, .definition = _stored_definition(c, stored, invocation),
    .input = arguments, .invocation = invocation};
  int block_scope = x.definition.assoc(<kind>) == <decorator> &&
                    x.definition.assoc(<target>) == <block>;
  if (block_scope) c.sym.push_new_scope();
  defer if (block_scope) c.sym.pop_scope();
  with (c.token = invocation) {
    _check(x);
    List result = NULL;
    with (c.expansion_floor =
            c.macro_stack ? c.expansion_floor : c.names.next_binding,
          c.macro_stack = c.macro_stack) {
      result = _bind_expansion(x, position);
    }
    return result;
  }
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

/** Prints one invocation frame and the bound result of its expansion. */
void Compiler.print_macro_expansion(Compiler c, List frame, List result) {
  (List definition, List input, Var bindings, Token invocation) = frame;
  (void) bindings;
  List site = c.token_location(invocation);
  String source = Diagnostics.macro_definition_note(definition)
    .remove_prefix("definition: ");
  printf(
    "expansion %s:%d:%d %s\n  definition %s\n"
    "  input %s\n  result\n",
    site.assoc(<file>), site.assoc(<line>).int(),
    site.assoc(<column>).int(), definition.assoc(<name>),
    source, Diagnostics.macro_expansion_input(input).repr());
  Ast.print_dump($(result));
}

// macro expansion and hygienic names

/* The definition a node names: a visible macro, a local macro, or a Macro
   value whose references bind in this unit. */
module List _stored_definition(Compiler c, Var stored, Token invocation) {
  List definition = NULL;
  if (stored.is_atom())
    definition = _lookup(c, Atom.intern(stored.str()), invocation);
  else if (stored ~= %(local-macro ?name))
    definition = c.sym.lookup_macro(Atom.intern(name.str()));
  return definition ? definition : stored;
}

/* An identical recursive expansion, nesting deeper than 64, or more than
   10000 expansions stops the compile. A leaf template's application
   cannot recurse, so it is neither compared nor counted. An application
   compiler code makes has no invocation token. It lowers the program, so
   it is not counted either. */
static void _check(Expansion &x) {
  Compiler c = x.c;
  int leaf = x.definition.assoc(<leaf>) == 1;
  if (!leaf)
    foreach (List active in c.macro_stack) {
      (List prior, List prior_input, Var bindings, Var site) = active;
      (void) bindings, (void) site;
      if (prior == x.definition && prior_input == x.input)
        _recursion(x);
    }
  if (c.macro_stack.len() >= 64) _too_deep(x);
  if (leaf || !x.invocation) return;
  if (c.macro_count >= 10000)
    $fail.macros_expansion_count(c, x.invocation);
  c.macro_count++;
}

static void _recursion(Expansion &x) {
  Atom name = x.definition.assoc(<name>);
  String spelling = name.str();
  Var shown = Diagnostics.macro_expansion_input(x.input);
  $fail.macros_expansion_recursive(
    x.c, x.invocation, spelling,
    Diagnostics.macro_definition_note(x.definition), shown);
}

static void _too_deep(Expansion &x) {
  /* Compiler-generated applications can have no invocation token. */
  List first = x.c.macro_stack.last().list().car();
  $fail.macros_expansion_depth(
    x.c, x.invocation, Diagnostics.macro_definition_note(x.definition),
    Diagnostics.macro_definition_note(first));
}

/* Pushes this expansion's frame on the macro stack, fills the template,
   and binds the result. A failed match binds nothing. */
static List _bind_expansion(Expansion &x, Symbol position) {
  Compiler c = x.c;
  List old_stack = c.macro_stack;
  x.template = x.definition.assoc(<template>);
  /* An application compiler code makes has no invocation token. What it
     authors belongs to the source being lowered, so it carries no anchors
     of its own. */
  if (!x.invocation)
    x.template = x.template.search_replace(%(at m-origin ?node), <?node>);
  List fresh_input = _fresh_names(x, old_stack);
  List match_input = fresh_input
    ? x.input.append(%((fresh @fresh_input))) : x.input;
  List replacement_bindings = match_input.match(x.definition.assoc(<pattern>));
  int matched = !!replacement_bindings;
  replacement_bindings = replacement_bindings.append(x.direct);
  List template_bindings = NULL;
  List author_bindings = _author_bindings(
    replacement_bindings, template_bindings);
  c.macro_stack = %(
    ($(x.definition) $(x.input) $author_bindings $(x.invocation)) @old_stack
  );
  int expansion_origin = c.record_origin(x.invocation);
  int placed = c.placements.len();
  Ast constructed = matched ? _construct(x, template_bindings) : NULL;
  List result = NULL;
  with (c.origin = expansion_origin) {
    result = c.bind_syntax(
      matched ? constructed : void,
      position, c.return_type);
  }
  c.close_placements(placed, result);
  if (c.dump_expansions && x.invocation)
    result = _inspected_expansion(c, result);
  return result;
}

/* Collection retains inspection boundaries with the declaration rows, so
   replay can print each bound result without invoking its producer again. */
static List _inspected_expansion(Compiler c, List result) {
  List frame = c.macro_stack.car();
  if (!c.shallow) c.print_macro_expansion(frame, result);
  else if (result ~= %(declaration-bundle (rows *rows)))
    return %(declaration-bundle
      (rows (exp-begin $frame) @rows (exp-end)));
  return result;
}

/* Allocates each fresh name of the definition. A name meta calls read
   joins the match input as a Name capture row; the others, with the
   member holes, bind directly. Returns the Name rows. */
static List _fresh_names(Expansion &x, List old_stack) {
  Compiler c = x.c;
  Map file_locals = {};
  // The outermost active row's fourth field is its invocation token.
  Token root = old_stack ? old_stack.last().list()[3] : x.invocation;
  if (c.sym.at_file_scope()) _file_scope_locals($(x.template), file_locals);
  Array fresh_values = [];
  foreach (List fresh in x.definition.assoc(<fresh>).list()) {
    Var (binder, spelling, exposed) = fresh;
    Token owner = binder in file_locals ? root : NULL;
    if (exposed.int()) {
      List binding = _introduced_binding(c, spelling.str(), owner);
      List hole = _hole(binder, <name>, 0);
      fresh_values.push(_capture_row_project(c, hole, $(binding), 0));
    }
    else
      x.direct = cons(
        $(binder, _private_name(c, spelling.str(), owner)), x.direct);
  }
  List members = _member_bindings(
    c, x.definition.assoc(<parameters>), x.input);
  x.direct = x.direct.append(members);
  return fresh_values.list_free();
}

/* A Name hole in a member position supplies the captured spelling, so a
   template local passed there keeps the spelling its source wrote. */
static List _member_bindings(Compiler c, List parameters, List input) {
  List captures = NULL, bindings = NULL;
  match (input) {
    case %(args *rows): captures = rows;
    case %(target (args *rows) ?): captures = rows;
  }
  foreach (List parameter in parameters) {
    List capture = captures.car();
    captures = captures.cdr();
    if (parameter.assoc(<kind>) != <name> ||
        parameter.assoc(<sequence>).int())
      continue;
    Var member = _hole_key(parameter, "member");
    bindings = cons(
      $(member, _member_spelling(c, capture.assoc(<value>))), bindings);
  }
  return bindings;
}

/* The spelling a Name hole's value supplies in a member position: the
   source spelling of a renamed local or a binding, or an `x2c_ident`
   value's own. */
module Var _member_spelling(Compiler c, Var value) {
  Var spelling;
  if (value ~= %("x2c.ident" (!is ?name type string))) return name;
  if (value is not <list>) return value;
  if (c.semantic_binding_facts().try_get(%(source-spelling $value), spelling))
    return spelling;
  String name = Ast.binding_spelling(value);
  return name ? name : value;
}

/* The bindings meta calls see: the author's binders. The template
   receives the `__macro_` binders the compiler makes, so an author binder
   spelled in a template literal, such as a catch pattern's `?cause`, stays
   literal. */
static List _author_bindings(List bindings, List &template_bindings) {
  Array author = [], compiler = [];
  foreach (List pair in bindings) {
    Var binder = pair.car();
    if (binder.is_binder()) {
      String spelling = binder.str();
      if (!spelling.startswith("?__macro_") &&
          !spelling.startswith("*__macro_")) {
        author.push(pair);
        continue;
      }
    }
    compiler.push(pair);
  }
  template_bindings = compiler.list_free();
  return author.list_free();
}

/* Declaration results and collected Unit results retain their declarations
   in one bundle, as does a NamedType decorator. */
static Ast _construct(Expansion &x, List bindings) {
  List definition = x.definition;
  Ast constructed = x.template.replace(bindings);
  if (constructed &&
      (definition.assoc(<kind>) == <decl-unit> ||
       (x.c.shallow && definition.assoc(<kind>) == <unit>) ||
       definition.assoc(<target>) == <named-type>)) {
    List rows = constructed.car() == <seq>
              ? constructed.cdr() : $(constructed);
    constructed = %(declaration-bundle (rows @rows));
  }
  return constructed;
}

/* expansion names

   A fresh name gets a private spelling. At file scope a declaration with
   external or no linkage can reach another unit through a header or an
   interface, so its spelling is stable: collection and full parsing expand
   the same invocation to the same spelling. */

/* A template local's name, which keeps its source spelling. */
module List _private_name(Compiler c, String source, Token root) {
  List binding = _introduced_binding(c, source, root);
  c.set_fact(%(source-spelling $binding), source);
  return binding;
}

static List _introduced_binding(Compiler c, String source, Token root) =>
  c.sym.introduce(
    root ? _file_scope_name(c, root, source)
         : c.fresh_name(%"macro_$source"));

/* The spelling names the owning unit and the root invocation's offset, and
   counts repeats of the same name there. */
static String _file_scope_name(Compiler c, Token root, String source) {
  String key = %"macro:$(_scope_owner(c)):$(root.pos):$source";
  Var stored;
  int count = c.names.counters.try_get(key, stored) ? stored : 0;
  c.names.counters[key] = count + 1;
  c.names.issued++;
  String digest = "%08x".printf(%"$key:$count".hash());
  return %"_x2c_gensym_macro_$(source)_$digest";
}

/* The unit's owner spelling, cached per file and package. */
static String _scope_owner(Compiler c) {
  String owner = NULL;
  $memo(c.names.file_scope_owners, $(c.filename, c.package), owner) {
    owner = c.filename ? _owner_spelling(c) : "";
  }
  return owner;
}

/* Home and package paths stay portable; other paths use their canonical
   absolute identity. */
static String _owner_spelling(Compiler c) {
  String path = c.canonical_path(Path.absolute(c.filename));
  String owner = Compiler.portable_path(path);
  Var package_root = c.package ? c.package_roots[c.package] : void;
  if (package_root is not <string>) return owner;
  String prefix = %"$(c.canonical_path(Path.absolute(package_root)))/";
  if (!path.startswith(prefix)) return owner;
  return %"package:$(c.package)/$(path[prefix.len():])";
}

/* Collects the template locals that a file-scope row declares with external
   linkage or none: objects, functions, typedefs, tags, and enumerators,
   including those a nested invocation declares from this template's names. */
module void _file_scope_locals(List rows, Map locals) {
  foreach (Var row in rows) match (row) {
    case %((!or at src) ? ?inner): _file_scope_locals($(inner), locals);
    case %(api-source ? ? ?inner): _file_scope_locals($(inner), locals);
    case %(seq *inner): _file_scope_locals(inner, locals);
    case %(macro-invoke ((!quote !quote) ?(List definition))
           ?(List input) ?): {
      Map declared = {};
      _file_scope_locals($(definition.assoc(<template>)), declared);
      List bindings = NULL;
      input.try_match(definition.assoc(<pattern>), bindings);
      foreach (List pair in bindings)
        if (pair.car() in declared && pair.cadr().is_binder())
          locals[pair.cadr()] = 1;
    }
    case %(function ?type (bind ?binder ?) ?):
      if (binder.is_binder() && !type.type().is_static()) locals[binder] = 1;
    case %((!or ?kind declare typedef) ?type (bindings *rows)): {
      if (type ~= %(* (!or struct union enum) ?tag *) && tag.is_binder())
        locals[tag] = 1;
      if (type ~= %(* enum ? (*members) *))
        _file_scope_declarators(members, locals);
      if (kind == <typedef> || !type.type().is_static())
        _file_scope_declarators(rows, locals);
    }
  }
}

static void _file_scope_declarators(List declarators, Map locals) {
  foreach (Var declarator in declarators)
    if (declarator ~= $Ast.declarator_pattern(%(?binder ?)) &&
        binder.is_binder())
      locals[binder] = 1;
}
