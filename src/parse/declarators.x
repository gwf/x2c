/*  declarators.x -- declarators and parameters

    Copyright (c) 2025 Gary William Flake.
*/

static keyword loop $private.loop;

// declarators

/** Parses one declarator row for a macro argument without installing it.
    Its enclosing declaration supplies the base type when expanded.
*/
List Compiler.parse_declarator_argument(Compiler c) {
  List slot = c.try_parse_macro_slot(<decl-row>);
  if (slot) return slot;
  List method = NULL;
  Token first = NULL, after = NULL;
  List bind = _declarator(c, NULL, NULL, method, first, after);
  if (c.test(<=>)) return %(op = $bind $(c.parse_assignment()));
  return bind;
}

// parameters

/** Parses a nonempty comma-separated parameter `List` in source order.
    The caller owns the parameter scope; the first non-comma delimiter remains
    current.
*/
List Compiler.parse_parameter_list(Compiler c) {
  Array parameters = auto [];
  while (1) {
    _x2c_complete_here(c, <type>, _type_keywords());
    List parameter = c.try_parse_macro_slot(<param>);
    if (!parameter) parameter = c.parse_parameter();
    parameters.push(parameter);
    if (c.peek(0) != <,>) break;
    c.expect(<,>);
  }
  return parameters;
}

/** Parses one parameter and returns `(param TYPE DECLARATOR)` or `(...)`.
    Outside macro-template parsing, a named parameter is installed in the
    current `Sym` scope. The following delimiter remains current.
*/
List Compiler.parse_parameter(Compiler c) {
  if (c.test(<...>)) return %(...);
  List qual = _type_qualifiers(c), spec = _type_specifier(c);
  List type = %( @qual @spec );
  int rest = (type == %("List") || type == %("Map")) && c.test(<@>);
  if (rest) type = %(.... @type);
  List method = NULL;
  Token first = NULL, after = NULL;
  List declarator = _declarator(c, type, NULL, method, first, after);
  if (rest && (declarator.caddr() || c.peek(0) == <,>))
    c.report_error(<parse>, "rest parameter must be a final name",
      c.token, NULL);
  return _finish_parameter(c, type, declarator, method, first, after);
}

/* template declarators

   In a macro template a declarator may name its binding through a
   meta-call slot, a Name hole, a member hole, or a name each expansion
   introduces. A method's owner may be a literal type or a type hole. */

/** Installs a definition-local template binding or typedef provisionally.
    Later template types name a local typedef by its identity, so each
    expansion refers to that expansion's private typedef.
*/
void Compiler.bind_template_local(
  Compiler c, List key, List type, List context) {
  Var local = c.macro_holes && key ? c.macro_definition_locals()[key] : void;
  if (c.macro_holes && local is <string> &&
      (!context || context === %(typedef))) {
    if (context === %(typedef)) {
      c.sym.set($(local), %(typedef $local));
      c.sym.set(%(typedef $local), $(key));
    }
    else c.sym.bind_identity(
      NULL, key,
      %(declare (<macro-expr>) (bindings (bind $key ()))));
  }
}

/** Binds one constructed parameter in the current scope, including nested
    function modifiers and reference parameter facts.
*/
List Compiler.bind_parameter(Compiler c, List base, List declarator) =>
  _finish_parameter(c, base, _finish_fnmods(c, declarator), NULL, NULL, NULL);

// identifiers

/** Parses the current identifier or dotted owner/member as a one-item name.
    Package aliases and imported method spellings are folded through the
    current `Sym`, and all accepted tokens are consumed.
*/
List Compiler.parse_complex_identifier(Compiler c) =>
  _complex_identifier(c, NULL);

/** Returns the folded package-member spelling at the current token, or NULL.
    The token must be an unshadowed imported alias followed by `.` and an
    identifier. This lookahead does not consume tokens.
*/
String Compiler.package_alias_spelling(Compiler c) {
  if (!c.package_aliases.len()) return NULL;
  if (c.peek(0) != <ident> || c.peek(1) != <.>) return NULL;
  String alias = c.token.text;
  Var package = c.package_aliases[alias];
  if (package is void || c.sym.get_exact($(alias))) return NULL;
  Token member = Token.skip_trivia(Token.skip_trivia(c.token + 1) + 1);
  return member.text.is_identifier()
       ? %"$(package)__$(member.text)" : NULL;
}

/** Consumes and returns the current identifier, or NULL without consuming. */
List Compiler.parse_optional_identifier(Compiler c) =>
  c.peek(0) == <ident> ? c.parse_basic_identifier() : NULL;

/** Consumes one `ident` token and returns its spelling as a one-item `List`.
*/
List Compiler.parse_basic_identifier(Compiler c) {
  String ident = c.token.text;
  c.expect(<ident>);
  return $(ident);
}

// declarators and parameters

module List _declarator(
  Compiler c, List type, List context, List &method_identity_out,
  Token &source_first, Token &source_after) {
  List ptr = _pointer(c), method_identity = NULL;
  List (key, infix) =
    _direct_declarator(
      c, context, method_identity, source_first,
      source_after).cdr();
  List sfx = _declarator_suffix(
    c, c.load_source && !c.return_type && key == %("main"));
  List modifiers = %( @infix @sfx @ptr );
  List ast = modifiers.append(type);
  // A parenthesized declarator is assembled twice. Preserve its raw key until
  // the outer call has the base type and can establish the binding once.
  c.bind_template_local(key, ast, context);
  method_identity_out = method_identity;
  return %( bind $key $modifiers );
}

static List _direct_declarator(
  Compiler c, Type context, List &method_identity, Token &source_first,
  Token &source_after) {
  // A member keeps its spelling in a template: C scopes it to its aggregate.
  int member = context.is_aggregate();
  if (c.peek(0) == <(> && _parameters_follow(c)) return %(bind () ());
  if (c.peek(0) == <(>)
    return _parenthesized(
      c, member ? context : NULL, method_identity, source_first,
      source_after);
  if (c.macro_holes) {
    List bind = _template_declarator(c, member);
    if (bind) return bind;
  }
  if (!c.token.text.is_identifier()) return %(bind () ());
  Token first = c.token;
  List ident = _complex_identifier(c, method_identity);
  source_first = first;
  source_after = c.token;
  return %(bind $ident ());
}

// Carries the source span across a nested declarator.
static List _parenthesized(
  Compiler c, List context, List &method_identity, Token &source_first,
  Token &source_after) {
  c.next();
  Token first = c.token;
  List decl = _declarator(
    c, NULL, context, method_identity, source_first, source_after);
  if (c.peek(0) != <)>) {
    c.require_input();
    /* One identifier followed by another is a parameter list whose type
       this unit cannot see, such as a package type named without its
       import alias, not a parenthesized declarator. */
    if (first.type == <ident> && c.peek(0) == <ident>)
      $fail.parse_type_unknown(c, first);
    else
      $fail.parse_paren_unclosed(c, c.token);
  }
  c.next();
  return decl;
}

static List _declarator_suffix(Compiler c, int loaded_main) {
  List type = NULL;
  loop {
    // An attribute after a declarator modifies that declarator alone.
    String attribute = _attribute(c);
    if (attribute)
      type = %( @type ($attribute) );
    else if (c.peek(0) == <[>)
      type = %( @type  @(_array_suffix(c)) );
    else if (c.peek(0) == <:>) {
      c.next();
      List expr = c.parse_primary();
      type = %( @type (bitfield $expr) );
    }
    else if (c.peek(0) == <(>) {
      List params = _function_parameters(c, loaded_main);
      params = %( params @params );
      type = type ? %(fnmod $params $type) : %((fnmod $params));
    }
    else break;
  }
  return type;
}



/* Parameter declarations bind into a temporary scope. Whether a body
   follows is not yet determined, so keep that scope in `params`; finishing
   a definition replays it around the body, while a prototype never pushes
   the captured scope. */
static List _function_parameters(Compiler c, int loaded_main) {
  c.next();
  _x2c_complete_here(c, <type>, _type_keywords());
  if (c.peek(0) == <)> && !loaded_main)
    $fail.parse_params_empty(c, c.token);
  SymScope saved = c.params, parsed;
  int complete = 0;
  defer { if (!complete) c.params = saved; }
  List params;
  c.sym.push_new_scope();
  {
    defer parsed = c.sym.pop_scope();
    params = c.peek(0) == <)> ? %((param (void) (bind () ())))
                            : c.parse_parameter_list();
  }
  if (c.peek(0) != <)>) {
    c.require_input();
    Symbol unexpected = c.peek(0);
    $fail.parse_params_close(c, c.token, params, unexpected);
  }
  else c.next();
  c.params = parsed;
  complete = 1;
  return params;
}

module List _pointer(Compiler c) {
  List ptr = NULL;
  loop {
    Symbol symbol = c.peek(0);
    if (symbol == <*> || symbol == <^> || symbol == <&> ||
        symbol.is_type_qualifier()) {
      c.next();
      int optional = symbol == <&> && c.peek(0) == <?>;
      ptr = cons(optional ? <opt-ref> : symbol, ptr);
      if (optional) c.next();
      continue;
    }
    if (symbol != <ident> || !(c.token.text in c.object_macros))
      return ptr;
    Array quals = auto [];
    if (!_prefix_macro_words(c, 1, quals)) return ptr;
    foreach (Symbol qualifier in quals) ptr = cons(qualifier, ptr);
  }
}

/* Whether the `(` at the cursor opens the parameters of a declarator with
   no name, as in the type name `int (int)`: a `)`, or a type that is no
   name to declare, follows it. As in C, a typedef name there is a type. */
module int _parameters_follow(Compiler c) {
  Token head = c.token;
  c.next();
  Symbol next = c.peek(0);
  Type lookup = c.sym.get($(c.token.text));
  int named = next == <ident> && !lookup.is_typedef() &&
              !(c.signature_only && c.test_declaration());
  int parameters = next == <)> || (!named && c.test_declaration());
  c.token = head;
  return parameters;
}

static List _array_suffix(Compiler c) {
  c.next();
  if (c.peek(0) == <]>) {
    c.next();
    return %((dim));
  }
  List expr = c.parse_expression();
  if (c.peek(0) != <]>) {
    c.require_input();
    Symbol unexpected = c.peek(0);
    $fail.parse_dimension_close(c, c.token, expr, unexpected);
  }
  c.next();
  return %((dim $expr));
}



// Returns NULL for another token, which takes the ordinary identifier path.
static List _template_declarator(Compiler c, int member) {
  List method = _literal_method(c);
  if (!method) method = _hole_method(c);
  if (method) return method;
  switch (c.peek(0)) {
    case <$>:
      return %(bind $(member ? c.try_parse_macro_member()
                             : c.try_parse_macro_slot(<name>)) ());
    case <ident>: {
      String spelling = c.token.text;
      int shadows_alias = !!c.alias_expression();
      c.next();
      if (member) return %(bind ($spelling) ());
      if (shadows_alias) c.sym.define($(spelling), NULL);
      return %(bind $(c.macro_introduced_name(spelling)) ());
    }
  }
  return NULL;
}

// `Type.member`, where the member may be a Name hole.
static List _literal_method(Compiler c) {
  Symbol owner_token = c.peek(0), String owner_spelling = c.token.text;
  Type owner_type =
    owner_spelling ? c.sym.get($(owner_spelling)) : NULL;
  int literal_owner =
    owner_token.is_builtin_type() ||
    owner_token.is_type_modifier() ||
    (owner_token == <ident> &&
     (owner_type.is_typedef() || c.peek(1) == <.>));
  if (!literal_owner || c.peek(1) != <.> ||
      (c.peek(2) != <$> && c.peek(2) != <ident>))
    return NULL;
  c.next();
  return %(bind (($owner_spelling) $(_method_member(c))) ());
}

// `$T.member`, where `$T` is a type hole.
static List _hole_method(Compiler c) {
  List owner_hole = c.peek_macro_hole();
  if (!owner_hole || owner_hole.assoc(<kind>) != <type> ||
      c.after_hole().type != <.>)
    return NULL;
  List owner = c.try_parse_macro_slot(<type>);
  return %(bind (($owner) $(_method_member(c))) ());
}

// The member after a method owner's `.`: a Name hole or an identifier.
static Var _method_member(Compiler c) {
  c.expect(<.>);
  if (c.peek(0) == <$>) return c.try_parse_macro_slot(<name>);
  if (!c.token.text.is_identifier()) $fail.parse_macro_member(c, c.token);
  String member = c.token.text;
  c.next();
  return member;
}

module List _finish_parameter(
  Compiler c, List base, List declarator, List method_identity,
  Token source_first, Token source_after) {
  List rest = base, container = rest.type().rest_container();
  base = _finish_type(c, container ? container : base);
  if (<auto> in base && !c.macro_holes && !c.shallow)
    $fail.parse_auto_storage(c, c.token);
  int preserved_self = 0;
  declarator = _install_declarator(
    c, base, NULL, declarator,
    method_identity, preserved_self);
  c.record_source_declaration(declarator.cadr(), source_first, source_after, 0);
  List modifiers = NULL;
  base = Type.declaration_base(base, modifiers);
  declarator = Ast.append_modifiers(declarator, modifiers);
  if (container) base = rest;
  List parameter = %(param $base $declarator);
  if (declarator ~= %(bind ?binding ?) && !c.macro_holes)
    _parameter_facts(c, binding, parameter);
  return parameter;
}

/* declarator installation

   A declarator's name is an exact spelling, a constructed binding identity,
   or a method's owner and member. Installation binds it in the current
   scope, records the method it declares, and resolves its initializer
   outside collection. */

module List _install_declarator(
  Compiler c, List base, List context, List declarator,
  List method_identity, int &preserved_self) {
  if (c.macro_holes) return declarator;
  Var name = void;
  List mods = NULL, initializer = NULL;
  match (declarator) {
    case %(op = (bind ?captured_name ?captured_mods) ?value):
      name = captured_name, mods = captured_mods, initializer = value;
    case %(bind ?captured_name ?captured_mods):
      name = captured_name, mods = captured_mods;
  }
  int exact_name = 0;
  name = _declared_name(c, name, exact_name);
  List declaration = %(declare $base (bindings (bind () $mods)));
  /* The List destination maps other value tags to nil. */
  List prior = name;
  List method = method_identity ? method_identity
              : prior ? c.fact(%(method $prior)) : NULL;
  List self_signature = prior ? c.fact(%(self $prior)) : NULL;
  Type declared_type = mods.append(base);
  name = _method_spelling(c, name, declared_type, method, exact_name);
  String exact = _syntax_exact_name(name);
  _check_rebinding(c, exact, exact_name, declaration);
  List binding = exact ? c.sym.declare(context, $(exact), declared_type)
               : name is <list> ? name.list() : NULL;
  if (binding && !exact) _bind_identity(c, context, binding, declaration);
  if (binding)
    _method_facts(c, binding, method, self_signature, preserved_self);
  if (binding && method && c.token && !declared_type.is_static()) {
    String path = Compiler.portable_path(Path.absolute(c.filename));
    String owner = c.package_spelling(method.car());
    c.sym.set(
      %("source-node" (interface-types $path $(c.token.pos) $exact)),
      %(interface-types $exact (($owner))));
  }
  List bound = %(bind $binding $mods);
  if (initializer && !c.shallow) {
    c.enter((Ancestor){ .what = <declarator>, .base = base, .node = bound });
    initializer = c.resolve_expression(initializer, c.token);
    c.ancestors.pop();
  }
  return initializer ? %(op = $bound $initializer) : bound;
}

// A name after its macro slot; `("x2c.ident" NAME)` is an exact spelling.
static Var _declared_name(Compiler c, Var name, int &exact_name) {
  name = c.evaluate_macro_slot(name);
  if (name ~= %("x2c.ident" ?(String exact)))
    name = exact, exact_name = 1;
  return name;
}

/* Folds a literal owner and its member into the C spelling and records
   the method. A constructed source owner is no concrete owner, so only a
   static method declares its member as an exact spelling. */
static Var _method_spelling(
  Compiler c, Var name, Type declared_type, List &method, int &exact_name) {
  match (name) {
    case %(((!or (!is ?owner type string)
                  (!is ?owner type symbol)
                  ((!is ?owner type string))))
           ?(String member)): {
      String owner_name =
        owner is <symbol> ? owner.symbol() : owner.str();
      name = %"$(owner_name)_$member";
      if (c.package) {
        String prefix = %"$(c.package)__";
        if (owner_name.startswith(prefix))
          owner_name = owner_name[prefix.len():];
      }
      method = $(owner_name, member);
    }
    case %((!or
              (src (source (!is ? type string) ? ?) ?)
              (construct
                (src (source (!is ? type string) ? ?) ?)))
           ?(String member)):
      if (declared_type.is_static()) {
        name = member;
        exact_name = 1;
      }
      else $fail.parse_method_owner(c, c.token);
    case %((!is ? type list) (!is ? type string)):
      $fail.parse_method_owner(c, c.token);
  }
  return name;
}

/* An exact spelling, or a name a parameter holds, may be declared again only
   as another prototype of a function. An alias's name is not declared again
   in its scope. */
static void _check_rebinding(
  Compiler c, String exact, int exact_name, List declaration) {
  if (exact && c.scope_declares_alias(exact))
    $fail.parse_decl_bound(c, c.token, exact);
  List existing = exact ? c.sym.current_binding($(exact)) : NULL;
  if (exact_name || (existing &&
      %(parameter $existing) in c.semantic_binding_facts())) {
    Var prior = existing
              ? c.sym.current_symbols()[$(exact)] : void;
    if (prior is <list>) {
      Type prior_type = prior;
      Type candidate = declaration.type_from_ast();
      if (!candidate.is_function() || !prior_type.is_function())
        $fail.parse_decl_bound(c, c.token, exact);
    }
  }
}

// Binds a constructed identity unless it is already its spelling's binding.
static void _bind_identity(
  Compiler c, List context, List binding, List declaration) {
  String spelling = Ast.binding_spelling(binding);
  List visible = c.sym.lookup($(spelling), NULL);
  if (visible != binding) c.sym.bind_identity(context, binding, declaration);
}

/* Records the method a binding declares, or drops a stale one, and keeps
   the Self signature an earlier declaration recorded. */
static void _method_facts(
  Compiler c, List binding, List method, List self, int &preserved_self) {
  if (method) c.set_fact(%(method $binding), method);
  else c.drop_fact(%(method $binding));
  if (!self) return;
  c.set_fact(%(self $binding), self);
  preserved_self = 1;
}

// Records a parameter binding and whether it is a reference, or optional.
static void _parameter_facts(Compiler c, Var binding, List parameter) {
  if (binding) c.set_fact(%(parameter $binding), 1);
  Type type = parameter.type_from_ast();
  if (type.is_reference())
    c.set_fact(%(reference-param $binding), 1);
  if (type.is_optional_reference())
    c.set_fact(%(optional-reference-param $binding), 1);
}

/* Accept one of two forms of dotted identifiers: TYPE.IDENTIFIER or
   IDENTIFIER.TYPE. Preserve the explicit owner/member pair for declarations
   whose mangled spellings alone would be ambiguous. */
static List _complex_identifier(Compiler c, List &?method_identity) {
  if (method_identity) method_identity = NULL;
  String ident = _package_alias_member(c), Symbol toktype = c.token.type;
  /* Only a declarator asks for the method identity, and there the name is
     being defined. A `with` spelling must not fold, because the declaration
     belongs to this unit and shadows the binding. */
  if (!ident && toktype == <ident> && !method_identity)
    ident = c.package_member_spelling(c.token.text);
  if (!ident) ident = c.token.text;
  Type idtype = c.sym.get($(ident));
  c.next();
  if ((toktype.is_builtin_type() || toktype.is_type_modifier() ||
       (toktype == <ident> &&
        (idtype.is_typedef() || (c.signature_only && method_identity)))) &&
      c.test(<.>))
    return _member_name(c, ident, method_identity);
  return $(ident);
}

/* The member after `TYPE.` spells a method, which a declarator records as
   its owner and member. Elsewhere an imported package may have declared
   the method on one of its own header's types: the header spells the type,
   and the package spells the method. */
static List _member_name(
  Compiler c, String owner, List &?method_identity) {
  // Keyword tokens may also spell method members.
  if (!c.token.text.is_identifier())
    $fail.parse_method_member(c, c.token, owner);
  String member = c.token.text, ident = %"$(owner)_$member";
  if (method_identity) method_identity = $(owner, member);
  if (!method_identity && !c.sym.get_exact($(ident))) {
    String imported = c.imported_spelling(ident);
    if (imported) ident = imported;
  }
  c.next();
  return $(ident);
}

/* Consume `alias .` and return the folded spelling. The member token stays
   current, so every caller continues down its identifier path. */
module String _package_alias_member(Compiler c) {
  String spelling = c.package_alias_spelling();
  if (!spelling) return NULL;
  String package = c.package_aliases[c.token.text];
  c.next();
  c.next();
  if (!c.sym.get_exact($(spelling)))
    $fail.parse_package_member(c, c.token, package, c.token.text);
  return spelling;
}

module String _syntax_exact_name(Var value) {
  if (value is <string>) return value;
  if (value is not <list>) return NULL;
  match (value) {
    case %(?(String exact)): return exact;
    case %("x2c.ident" ?(String exact)): return exact;
  }
  return NULL;
}

/* Constructed function modifiers have not passed through the parameter
   parser. Bind their parameter types in the same temporary prototype scope. */
module List _finish_fnmods(Compiler c, List declarator) {
  match (declarator) {
    case %(op = ?binding ?value):
      return %(op = $(_finish_fnmods(c, binding)) $value);
    case %(bind ?binding ?modifiers): {
      Array output = [];
      foreach (Var modifier in modifiers.list())
        output.push(_finish_fnmod(c, modifier));
      return %(bind $binding (@(output.list_free())));
    }
  }
  return declarator;
}

static Var _finish_fnmod(Compiler c, Var modifier) {
  if (modifier ~= %(fnmod (params *parameters)))
    return %(fnmod (params @(_finish_prototype(c, parameters))));
  return modifier;
}

static List _finish_prototype(Compiler c, List parameters) {
  Array params = [];
  c.sym.push_new_scope();
  {
    defer c.sym.pop_scope();
    foreach (List parameter in parameters) match (parameter) {
      case %(param ?base ?declarator):
        params.push(c.bind_parameter(base, declarator));
      default: params.push(parameter);
    }
  }
  return params.list_free();
}



module List _declarator_list(Compiler c, List type, List context, int row) {
  Array bindings = auto [];
  loop {
    bindings.push(_declarator_init(c, type, context));
    if ((row && _group_comma(c)) ||
        !c.test(<,>))
      return bindings;
  }
}

/* Install each declaration binding before resolving its initializer so later
   declarators and source-order dependency analysis share the same identity. */
module List _declarator_init(Compiler c, List type, List context) {
  // A computed declarator name still needs ordinary binding.
  List slot = c.peek_macro_hole() || c.peek(0) == <@>
    ? c.try_parse_macro_slot(<decl-row>) : NULL;
  if (slot) {
    if (c.test(<=>)) return %(op = $slot $(c.parse_assignment()));
    return slot;
  }
  Token origin = c.token;
  List method = NULL;
  Token first = NULL, after = NULL;
  List bind = _declarator(c, type, context, method, first, after);
  int preserved_self = 0;
  bind = _install_declarator(c, type, context, bind, method, preserved_self);
  if (c.source_facts) {
    Type declared = %(declare $type (bindings $bind)).type_from_ast();
    int external = !context && !type.type().is_static() &&
      !c.sym.is_file_static(bind.cadr()) &&
      (c.sym.at_file_scope() || type.type().is_extern() || declared.is_function());
    c.record_source_declaration(bind.cadr(), first, after, external);
  }
  int function_arrow = !c.in_proto && _x2c_at_function_arrow(c) &&
    %(declare $type (bindings $bind)).type_from_ast().is_function();
  if (!c.in_proto && !function_arrow && c.test(<=>))
    return _initialized(c, type, bind, origin);
  return bind;
}

/* Collection skips an initializer. `init_tokens` records the declarator's
   first token, not the token where expression parsing finishes. */
static List _initialized(Compiler c, List type, List bind, Token origin) {
  List binding = bind.cadr();
  if (Ast.try_binding(binding, NULL, NULL)) {
    Token tokens = c.tokenizer.tokens;
    c.init_tokens[binding] = origin - tokens;
  }
  if (c.shallow && !c.capture_unit) {
    _x2c_skip_shallow_expression(c, 1);
    return bind;
  }
  c.enter((Ancestor){ .what = <declarator>, .base = type, .node = bind });
  int managed = c.test(<auto>);
  List init = c.parse_assignment();
  if (managed)
    init = c.bind_syntax($!( $auto($init) ), <expression>, c.return_type);
  c.ancestors.pop();
  c.check_explicit_converter(
    init, %(declare $type (bindings $bind)).type_from_ast(), 0);
  return %( op = $bind $init );
}
