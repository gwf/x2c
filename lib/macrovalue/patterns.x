/*  patterns.x -- macro value patterns */

// subject bindings

/* The rows `Macro.use_subject` set, or void when no call describes its
   subject. */
module Var macro_subject = void;

/* Whether the pattern being derived resolved a free reference against the
   current call's subject, which ties it to that call. */
module int threaded macro_subject_used;

/** Returns the table `Macro.use_subject` last set, or void. */
Var Macro.subject(void) => macro_subject;

/** Sets the `(SPELLING BINDING)` rows for global references and the
    `(source-spelling BINDING SPELLING)` rows for renamed local bindings in
    a compile-time call's syntax arguments. A macro value's free reference
    recognizes only the recorded global binding; with void it recognizes
    any binding of its spelling. The compiler sets these rows for each
    `meta` call and carries them through the helper. */
void Macro.use_subject(Var rows) { macro_subject = rows; }

/* The pattern for a `using` reference to `spelling`: any binding of it, or
   only the subject's file-scope binding while a call sets a subject. A free
   reference matches any binding of its spelling, since it binds where its
   expansion lands. */
static Var _free_reference(String spelling) {
  if (macro_subject is void) return %(binding ? $spelling);
  macro_subject_used = 1;
  foreach (List row in macro_subject.list())
    if (row.car() == spelling) return row.cadr();
  return %(binding-name $spelling);
}

/* pattern derivation

   A pattern is the macro's body with each parameter's projections replaced
   by its binder and each child macro call inlined. The projection keys are
   the replacement binders the compiler writes into a template. */

/** Derives the Match pattern that recognizes code this macro builds,
   capturing each parameter under the given binder. */
List Macro_pattern(Macro t, List names) {
  return _pattern(t, names, 0);
}

module List _pattern(Macro t, List names, int case_pattern) {
  List rows = _binder_rows(t, names, case_pattern);
  List body = t.assoc(<template>);
  List pattern =
    _pattern_view(_inline(t.assoc(<env>), body.replace(rows)));
  /* A one-statement block item also matches inside its `seq`. */
  if (t.assoc(<kind>) == <block-item> && body.car() == <seq> &&
      body.cdr().len() == 1)
    return %(!or $pattern (seq $pattern));
  return pattern;
}

/* The rows that replace each parameter's projections with its binder. A
   Type or captures parameter is a List splice, so its binder is a List
   binder. A name read as an expression is an identifier of its binding,
   as `_value_rows` builds it. */
static List _binder_rows(Macro t, List names, int case_pattern) {
  List rows = NULL;
  foreach (List hole in t.assoc(<parameters>).list()) {
    Var given = names.car(), kind = hole.assoc(<kind>);
    names = names.cdr();
    if (kind == <type> || kind == <captures>)
      given = Atom.intern("*" + given.str()[1:]);
    Var selected = _hidden(given);
    int sequence = hole.assoc(<sequence>);
    Var projected = sequence ? %($selected).var() : selected;
    // An explicit expression pattern owns its type constraint.
    if (!sequence && selected is <list> && selected.list().car() == <expr>)
      projected = %(!and $selected);
    if (case_pattern && kind == <name>)
      projected = %(!and $given $(_name_identity(hole)));
    Var expression = !sequence && kind == <name>
                   ? %(expr ? (ident $projected)).var() : projected;
    rows = cons(%($(_key(hole, "expression")) $expression), rows);
    rows = cons(%($(_key(hole, "value")) $projected), rows);
    rows = cons(%($(_key(hole, "source")) $projected), rows);
    rows = cons(%($(_key(hole, "member")) $selected), rows);
    rows = cons(%($(_key(hole, "splice")) ($selected)), rows);
  }
  return rows;
}

/* Derivation quotes a bare `?` or `*`, which a template writes as an
   operator, so an anonymous hole's binder passes through it under a
   hidden name and is shown again where derivation leaves it. */
static Var _hidden(Var binder) {
  if (!binder.is_binder() || binder.str().len() != 1) return binder;
  return Atom.intern(binder.str() + "__macro_anonymous");
}

static Var _shown(Var value) {
  if (!value.is_binder()) return value;
  String name = value.str();
  if (name.len() != 18 || !name.endswith("__macro_anonymous")) return value;
  return name[0] == '*' ? <*> : <?>;
}

/** Returns the binder that captures one projection of the template hole
    whose binder is `binder`. Splice and construction projections are
    always sequences; return, declarator, and member projections never
    are; source, value, and expression follow the hole's `sequence`. */
Atom Macro.binder(Var binder, String projection, int sequence) {
  if (projection == "splice" || projection == "construction") sequence = 1;
  else if (projection == "return" || projection == "declarator" ||
           projection == "member") sequence = 0;
  String prefix = sequence ? "*" : "?", name = binder.str();
  return Atom.intern(%"$(prefix)__macro_$(projection)_$(name[1:])");
}

static Atom _key(List hole, String projection) =>
  Macro.binder(hole.assoc(<binder>), projection, hole.assoc(<sequence>));

/* The second slot of a Name's declaration and reference projection keeps
   exact binding identity when a member label reaches the first slot first. */
module Atom _name_identity(List hole) =>
  Atom.intern(%"?__macro_identity_$(hole.assoc(<binder>).str()[1:])");

static List _instantiate(Macro t, List values);

/* Inlines each child macro the body calls, instantiated with its
   arguments, and drops the shell a template leaves around an
   expression. */
static Var _inline(List environment, Var tree) {
  if (tree is not <list>) return tree;
  match (tree) {
    case %(expr (<macro-expr>) (expr ?type ?body)):
      return _inline(environment, %(expr $type $body));
    case %(tpl-call (expr ? (ident ?binding)) (args *arguments)):
      return _instantiate(_child(environment, binding), arguments);
    case %(literal *): return tree;
  }
  Array parts = [];
  foreach (Var part in tree.list()) parts.push(_inline(environment, part));
  return parts.list_free();
}

/* The Macro value the environment captured for `binding`, or NULL. */
static Macro _child(List environment, Var binding) {
  foreach (List row in environment)
    if (List.compare(row.car(), binding) == 0) return row.cadr();
  return NULL;
}

/* Substitutes grouped values into the body directly. Pattern derivation
   uses this for a captured child macro; construction goes through the
   compiler's invocation rows instead. */
static List _instantiate(Macro t, List values) {
  List rows = _value_rows(t, values), body = t.assoc(<template>);
  return _inline(t.assoc(<env>), body.replace(rows));
}

/* The rows that replace each parameter's projections with its argument. A
   name read as an expression is an identifier of its binding. */
static List _value_rows(Macro t, List values) {
  List rows = NULL;
  foreach (List hole in t.assoc(<parameters>).list()) {
    int sequence = hole.assoc(<sequence>);
    Var kind = hole.assoc(<kind>);
    Var value = sequence ? values.var() : values.car();
    if (kind == <expr>)
      value = sequence ? _expr_values(values).var()
                       : _expr_value(value);
    Var expression = !sequence && kind == <name>
                   ? %(expr () (ident $value)).var() : value;
    rows = cons(%($(_key(hole, "expression")) $expression), rows);
    rows = cons(%($(_key(hole, "value")) $value), rows);
    rows = cons(%($(_key(hole, "source")) $value), rows);
    if (kind == <name>)
      rows = cons(%($(_key(hole, "member")) $value), rows);
    rows = cons(%($(_key(hole, "splice")) $value), rows);
    values = sequence ? NULL : values.cdr();
  }
  return rows;
}

// pattern views

/* Turns an instantiated body into a pattern: derived expression types
   become wildcards, literals and operators are quoted, a binder in a hole
   shell stands alone, and a free reference matches a binding of its
   spelling. */
static Var _pattern_view(Var value) {
  if (value is not <list>)
    return value == <*> || value == <?> ? %(!quote $value).var()
                                        : _shown(value);
  List node = value;
  /* Explicit Match operands already describe recognition, not source code. */
  if (node.car().is_match_op()) return node;
  match (node) {
    case %(expr ?type ?body): return _expr_view(type, body);
    case %(literal *): return %(!quote $node);
    case %(binding-name ?(String name)): return %(binding ? $name);
    case %(binding-global ?(String name)): return _free_reference(name);
    case %(op ?operator *operands):
      return %(op (!quote $operator) @(_pattern_views(operands)));
    case %(seq ?one): return _pattern_view(one);
    case %(macro-slot ?(int splice) ?form):
      return _slot_view(splice, form);
    case %(return ? ?body): return %(return ? $(_pattern_view(body)));
  }
  return _pattern_views(node);
}

/* A template's shell passes through a binder or the expression it holds;
   any other expression matches whatever type binding derived. */
static Var _expr_view(Var type, Var body) {
  int shell = type === %(<macro-expr>);
  if (shell && body.is_binder()) return _shown(body);
  if (shell && body is <list> && body.list().car().is_match_op())
    return body;
  if (shell && body is <list> && body.list().car() == <expr>)
    return _pattern_view(body);
  return %(expr ? $(_pattern_view(body)));
}

static List _pattern_views(List items) {
  Array parts = [];
  foreach (Var part in items) parts.push(_pattern_view(part));
  return parts.list_free();
}

/* A slot builds code the pattern cannot see; a spliced slot captures it
   under the sequence hole it was given. */
static Var _slot_view(int splice, Var form) {
  if (!splice) return <?>;
  Var binder = _slot_binder(form);
  return binder ? binder : <*>;
}

/* The first named `*` binder in a slot's arguments, depth first, or NULL. */
static Var _slot_binder(Var form) {
  if (form.is_binder())
    return form.str().len() > 1 && form.str()[0] == '*' &&
      _shown(form) == form ? form : NULL;
  if (form is not <list>) return NULL;
  foreach (Var child in form.list()) {
    Var binder = _slot_binder(child);
    if (binder) return binder;
  }
  return NULL;
}
