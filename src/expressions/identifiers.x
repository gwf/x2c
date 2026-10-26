/*  identifiers.x -- binding identities and reference reads */

module int _identifier_needs_resolution(Compiler c, List binding) {
  String spelling = Ast.binding_spelling(binding);
  Map facts = c.semantic_binding_facts();
  int retained_parameter = %(lambda-param $binding) in facts;
  int retained_capture = %(lambda-depth $binding) in facts;
  if (c.lambda_capture_required(binding)) return 1;
  if (retained_parameter && c.local_macro_captures != NULL) return 1;
  Var type;
  if (%(automatic $binding) in facts &&
      facts.try_get(%(type $binding), type) && type is <list> &&
      type.list() !== %(<macro-expr>))
    return <auto> in type.list() && !type.list().type().base_type();
  return !spelling ||
    (c.sym.lookup($(spelling), NULL) != binding &&
     !retained_parameter && !retained_capture);
}

// identifiers

module List _resolve_identifier(
  Compiler c, Var value, Type type, Token origin) {
  if (type === %(<macro-expr>)) type = NULL;
  int read_reference = !type;
  int require_type = 0;
  List binding = _identifier_binding(c, value, type, origin, require_type);
  if (c.macro_holes && binding) {
    String name = Ast.binding_spelling(binding);
    int free = _template_free_name(c, binding);
    if (c.macro_holes[%(using $name)] is <list>)
      return %(expr (<macro-expr>) (ident (binding-global $name)));
    if (free) return %(expr (<macro-expr>) (ident (binding-name $name)));
  }
  int macro_binder = value.is_binder() ||
    (value is <list> && !value.is_nil() &&
     value.car() == <macro-bind>);
  if (!binding && macro_binder) return %(expr (<macro-expr>) (ident $value));
  if (!binding) $fail.expressions_binding_unknown(c, origin, value);
  Map binding_facts = c.semantic_binding_facts();
  String spelling = Ast.binding_spelling(binding);
  _capture_identifier(c, binding);
  int kept = 0;
  match (value) case %(binding-global *): kept = 1;
  if (_shadow_identifier(c, binding, type, spelling, binding_facts, kept))
    type = NULL;
  if (!type) type = _identifier_type(
    c, binding, spelling, binding_facts, origin);
  if (!c.macro_holes && <auto> in type && !type.base_type())
    $fail.expressions_ident_semantic(c, origin, value);
  if (!type && require_type)
    $fail.expressions_ident_semantic(c, origin, value);
  List result = %(expr $type (ident $binding));
  result = _capture_lambda_value(c, result, binding, type, read_reference);
  return _read_bound_reference(
    c, result, binding, type, read_reference, binding_facts);
}

static List _capture_lambda_value(
  Compiler c, List result, List &binding, Type &type, int &read_reference) {
  if (!c.lambda_scopes || c.macro_holes) return result;
  result = c.capture_lambda_identifier(binding, type);
  match (result)
    case %(expr ?captured_type $($source_identifier_content(
        %(?captured)))): {
      if (type.car() != <&> && captured_type.car() == <&>)
        read_reference = 1;
      type = captured_type;
      binding = captured;
    }
  return result;
}

/* Parsed identifiers arrive as spellings, while constructed syntax may carry
   producer-issued binding identities. Semantic binding facts validate those
   identities before resolution. A visible local replaces a stale local
   identity; global shadow handling instead gives the visible declaration an
   emitted alias so the original identity keeps its meaning. A template's
   free name arrives as `binding-name` and binds where the expansion lands;
   a name listed with `using` arrives as `binding-global` and keeps its
   file-scope declaration and type. */
static List _identifier_binding(
  Compiler c, Var value, Type &type, Token origin, int &require_type) {
  require_type = value is <string>;
  if (value is <string>) return c.sym.reference($(value), type);
  if (value is not <list>) return NULL;
  List name = value;
  int identity = 0;
  String spelling = NULL;
  if (Ast.try_binding(name, identity, spelling)) {
    Map facts = c.semantic_binding_facts();
    Var issued, source;
    if (!facts.try_get(%(known $identity), issued) ||
        issued is not <string> || issued.string() != spelling)
      $fail.expressions_binding_unknown(c, origin, name);
    /* A template's private name that no declaration in scope reaches
       reads its source spelling where the expansion lands. A declared one
       keeps its identity, as when lowering binds code outside the scope
       that declared it. */
    if (facts.try_get(%(source-spelling $name), source) &&
        !(%(type $name) in facts) &&
        c.sym.lookup($(spelling), NULL) != name)
      return _landed_name(c, source, type);
    return name;
  }
  match (name) {
    case %("x2c.ident" ?(String spelling)): {
      require_type = 1;
      return c.sym.reference($(spelling), type);
    }
    case %(binding-name ?(String spelling)):
      return _landed_name(c, spelling, type);
    case %(binding-global ?(String spelling)): {
      List global = c.sym.resolve_global($(spelling), type);
      return global ? global : c.sym.reference_global($(spelling));
    }
    case %((!is ? type string)):
      return c.sym.reference(name, type);
  }
  return NULL;
}

/* A name a template reads without declaring it binds where the expansion
   lands unless the template keeps it with `using`. A `Macro` local is a
   compile-time template the body composes, so an anonymous macro captures
   its value where it is written. */
static int _template_free_name(Compiler c, List binding) {
  if (!binding || c.macro_template_local(binding)) return 0;
  Var type = c.semantic_binding_facts()[%(type $binding)];
  return !(type is <list> && c.sym.is_named_value_type(type, "Macro"));
}

/* A template's name where its expansion lands: the visible declaration, or
   for a name nothing declares, one file-scope forward binding that C
   resolves. */
static List _landed_name(Compiler c, String spelling, Type &type) {
  List visible = c.sym.lookup($(spelling), type);
  return visible ? visible : c.sym.reference_global($(spelling));
}

static void _capture_identifier(Compiler c, List binding) {
  if (c.local_macro_captures == NULL || !binding ||
      !c.sym.binding_is_local_before(
        binding, c.local_macro_capture_scopes) ||
      binding in c.local_macro_captures) return;
  Var order = c.local_macro_captures[<order>];
  c.local_macro_captures[<order>] = cons(
    binding, order is <list> ? order : NULL);
  c.local_macro_captures[binding] = 1;
}

/* A visible local replaces a stale local identity. A declaration the
   active expansion introduced, such as one a caller's `Name` argument
   spells, supplies a file-scope name written in the caller's arguments,
   as it would where the expansion lands. Both return 1, since the
   identifier's type is the new binding's. Any other file-scope identity
   that a visible declaration hides, such as a name a template keeps,
   gives every visible local of its spelling, the enclosing ones too, and
   their lambda captures an emitted alias, and the visible declaration one
   if it has none. */
static int _shadow_identifier(
  Compiler c, List &binding, Type type, String spelling, Map binding_facts,
  int kept) {
  if (!spelling) return 0;
  Type visible_type = NULL;
  List visible = c.sym.lookup($(spelling), visible_type);
  if (!visible || visible == binding) return 0;
  if ((c.sym.binding_is_local(binding) &&
       !(%(lambda-depth $binding) in binding_facts)) ||
      (!kept && visible_type && _expansion_introduced(c, visible))) {
    binding = visible;
    return 1;
  }
  if (!visible_type || !(%(automatic $visible) in binding_facts) ||
      (type && !c.sym.resolve_global($(spelling), NULL)))
    return 0;
  _unshadow_visible(c, visible, spelling);
  return 0;
}

static void _unshadow_visible(Compiler c, List visible, String spelling) {
  foreach (List local in c.sym.unshadow_visible(spelling))
    c.respell_captures(local);
  if (!(%(emitted $visible) in c.semantic_binding_facts()))
    c.set_fact(%(emitted $visible), c.fresh_name("binding_shadow"));
}

/** Keeps `binding` reachable from the cursor where a later declaration of
    its spelling hides it. A hidden local takes a fresh emitted spelling;
    a hidden file-scope name makes the visible automatic locals take one.
*/
void Compiler.reveal_binding(Compiler c, List binding) {
  String spelling = NULL;
  if (!Ast.try_binding(binding, NULL, spelling)) return;
  Type visible_type = NULL;
  List visible = c.sym.lookup($(spelling), visible_type);
  if (!visible || visible == binding) return;
  if (c.sym.binding_is_local(binding)) {
    if (!(%(emitted $binding) in c.semantic_binding_facts()))
      c.set_fact(%(emitted $binding), c.fresh_name("binding_shadow"));
    c.respell_captures(binding);
  }
  else if (visible_type && %(automatic $visible) in c.semantic_binding_facts())
    _unshadow_visible(c, visible, spelling);
}

/* An active expansion issued `binding` after it began. */
static int _expansion_introduced(Compiler c, List binding) {
  int identity = 0;
  return c.macro_stack &&
         Ast.try_binding(binding, identity, NULL) &&
         identity > c.expansion_floor;
}

static Type _identifier_type(
  Compiler c, List binding, String spelling, Map facts, Token origin) {
  Var stored;
  if (facts.try_get(%(type $binding), stored) && stored is <list>)
    return stored;
  if (!spelling) return NULL;
  Type type = c.sym.get($(spelling));
  if (!type) _check_unit_static(c, spelling, origin);
  return type;
}

/* A `static` function belongs to the file that defines it, so an including
   unit replays a marker row naming that file instead of a declaration.
   Reporting the reference here names the function and its file, where C
   would otherwise report only an undefined symbol at link time. A macro body
   is the defining library's own syntax, bound wherever it expands, so only a
   reference written in an `.x` unit is reported. */
static void _check_unit_static(Compiler c, String spelling, Token origin) {
  if (!Path.is_x2c_source(c.filename)) return;
  List owner = c.sym.get($("unit-static", spelling));
  if (!owner) return;
  String file = c.display_path(Compiler.absolute_home_path(owner.car()));
  $fail.expressions_function_private(c, origin, spelling, file);
}

static List _read_bound_reference(
  Compiler c, List result, List binding, Type type,
  int read_reference, Map binding_facts) {
  if (!read_reference ||
      !(%(reference-param $binding) in binding_facts)) return result;
  if (%(optional-reference-param $binding) in binding_facts &&
      !(binding in c.present_references())) return result;
  Type value_type = cdr(type);
  return %(expr $value_type
           (parens (expr $value_type (op * $result))));
}
