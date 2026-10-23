/*  templates.x -- macro definition templates */

/* definition templates

   Finishing a definition turns its body into the stored template, derives
   the rows an invocation needs, and makes the `macrodef` visible. */

/* Turns the body into the stored template, then derives the fresh rows
   and pattern an invocation needs. Parsed literal names carry
   definition-only identities, so the template stores binders instead and
   each expansion allocates one fresh identity per literal spelling. */
module void _finish(Definition &d) {
  d.template = _slot_binders(_wrap(d));
  Map bindings = {};
  if (_target_kind(d) == <unit>) _constructed_names(d, bindings);
  Array locals = _local_binders(d, bindings);
  d.template = _replace_bindings(d.template, bindings);
  _check_kinds(d);
  d.fresh = _fresh_rows(d, locals);
  d.pattern = _invocation_pattern(d);
  Map uses = _binder_uses(d.template);
  if (!(void *) uses) return;
  d.rebuild = %(${_rebuild_template(d)} ${_rebuild_keys(d, uses)});
  d.leaf = !d.nested && _uses_holes_once(d, uses);
}

/* A Function decorator's body becomes a function with the target's return
   type and declarator, and an Expression decorator's body a parenthesized
   expression. */
static List _wrap(Definition &d) {
  List replacement = d.template;
  if (d.kind != <decorator>) return replacement;
  Symbol target = _target_kind(d);
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
static void _constructed_names(Definition &d, Map bindings) {
  Var required = _hole_key(d.target, "construction");
  foreach (List parameter in d.parameters)
    if (parameter.assoc(<kind>) == <name>) {
      Var name = Macro.binder(parameter.assoc(<binder>), "value", 0);
      bindings[name] = %($required $name);
    }
}

/* Binds each template local to its binder and returns the locals that get
   fresh names. A tag the template only references keeps its public
   spelling. */
static Array _local_binders(Definition &d, Map bindings) {
  Array fresh = [];
  foreach (List identity in _recorded(d.locals)) {
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

static void _check_kinds(Definition &d) {
  foreach (List hole in d.parameters)
    if (!hole.assoc(<kind>)) {
      String hole_spelling = hole.assoc(<binder>).str()[1:];
      $fail.macros_hole_untyped(d.c, d.start, hole_spelling);
    }
}

/* Each `using` hole and each template local gets a fresh name per
   expansion; the last field marks the names compile-time Lisp reads. */
static List _fresh_rows(Definition &d, Array locals) {
  Array fresh = [];
  foreach (Atom binder in d.using.list_free())
    fresh.push(%($binder ${binder.str()[1:]} 1));
  foreach (List identity in locals) {
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
    foreach (Var item in syntax)
      if (item.is_binder()) uses[item] = uses.getdefault(item, 0) + 1;
  }
  return uses;
}

/* The template a rebuild fills. An Expr hole's binder stands for its whole
   expression, without the `(expr (<macro-expr>) ...)` shell, and no
   template-origin wrapper remains, because a rebuild opens no invocation. */
static List _rebuild_template(Definition &d) {
  Map expressions = {};
  foreach (List hole in d.parameters)
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
static List _rebuild_keys(Definition &d, Map uses) {
  List holes = d.target ? d.parameters.append(%(${d.target})) : d.parameters;
  Array keys = [];
  foreach (List hole in holes) {
    Array used = [];
    foreach (String projection in
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
static int _uses_holes_once(Definition &d, Map uses) {
  List holes = d.target ? cons(d.target, d.parameters) : d.parameters;
  foreach (List hole in holes) {
    int count = 0;
    foreach (String projection in
             %("source" "value" "expression" "splice" "member" "return"
               "declarator" "construction"))
      count += uses.getdefault(_hole_key(hole, projection), 0).int();
    if (count > 1) return 0;
  }
  return 1;
}

/* Makes the finished definition visible in place of its signature. */
module List _publish(Definition &d) {
  List node = _definition_node(d);
  $let(d.c.token, d.start) _show(d, node);
  return node;
}

/* A named local macro is visible in its scope, and a global one unless a
   template holds it. */
module void _show(Definition &d, List node) {
  if (d.local && !d.anonymous) d.c.sym.define_macro(d.name, node);
  else if (!d.local && !d.nested) d.c.publish_macro_definition_node(node);
}

module List _definition_node(Definition &d) {
  Compiler c = d.c;
  List definition = %(
    macrodef
    (name ${d.name})
    (kind ${d.kind})
    (target ${_target_kind(d)})
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
  (void) Ast.try_binding(identity, number, NULL);
  int ordinal = INT_MAX - number;
  return Atom.intern(%"?__macro_${tag ? "tag" : "local"}_${ordinal}");
}

/* Introduces one declaration in the current lexical scope. */
static List _definition_local(Compiler c, String spelling, int tag) {
  Map locals = c.macro_definition_locals();
  Var order = locals[<order>];
  int identity = INT_MAX - (order is <list> ? order.list().len() : 0);
  List introduced = Ast.binding(identity, spelling);
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
  return _definition_local(c, spelling, 0);
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
  List local = _definition_local(c, name, 1);
  c.sym.bind_identity(%(tag), local, %($kind $local));
  if (!definition) locals[%(provisional $local)] = 1;
  return local;
}

/* Replaces each binder or binding identity that `bindings` maps. A List
   none of whose children change stays the same List, and only a changed
   List is copied. */
module Var _replace_bindings(Var value, Map bindings) {
  Var replacement;
  if (value is not <list> || value.is_nil())
    return value.is_binder() && bindings.try_get(value, replacement)
      ? replacement : value;
  if (Ast.try_binding(value, NULL, NULL) &&
      bindings.try_get(value, replacement))
    return replacement;
  List original = value;
  Array items = NULL;
  for (List cursor = original; cursor; cursor = cursor.cdr()) {
    Var child = cursor.car(), item = _replace_bindings(child, bindings);
    if (!(void *) items && item !== child) {
      items = [];
      for (List prefix = original; prefix != cursor; prefix = prefix.cdr())
        items.push(prefix.car());
    }
    if ((void *) items) items.push(item);
  }
  return (void *) items ? items.list_free().var() : value;
}

/* invocation patterns

   An invocation's capture rows match the definition's pattern: an `args`
   row per parameter, a decorator's target row, and a Name row for each
   fresh name compile-time Lisp reads. Each row binds only the projections
   the template uses. */

static List _invocation_pattern(Definition &d) {
  Map binders = {};
  _template_binders(d.template, binders);
  Array arguments = [];
  foreach (List parameter in d.parameters)
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
  foreach (Var child in value.list()) _template_binders(child, binders);
}

static List _fresh_patterns(List fresh, Map binders) {
  Array fresh_patterns = [];
  foreach (List row in fresh) {
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
  foreach (String role in %("source" "value" "splice"))
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
