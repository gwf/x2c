/*  declarations.x -- declaration rows and initializers

    Copyright (c) 2025 Gary William Flake.
*/

static keyword loop $private.loop;


// declarations

/** Parses one x2c declaration row and leaves its terminator current.
    A mixed-type comma row returns a `seq` of declarations in source order;
    a single declaration returns directly.
*/
List Compiler.parse_declaration_row(Compiler c) {
  Array declarations = [];
  loop {
    declarations.push(_declaration_group(c, 1));
    if (!_group_comma(c)) break;
    c.next();
  }
  List rows = declarations.list_free();
  if (rows ~= %(?only)) return only;
  return %(seq @rows);
}

/** Parses a declaration that sits inside an expression or a `for` header,
    such as a cast's type name, and returns it as one `(decl ...)` node.
    When `type` is not null, it receives the declared `Type`.
*/
List Compiler.parse_type_operand(Compiler c, Type *type) {
  List declaration = c.parse_simple_declaration();
  if (!c.macro_holes && _auto_storage(declaration))
    $fail.parse_auto_storage(c, c.token);
  if (type) *type = declaration.type_from_ast();
  return %(decl @(declaration.cdr()));
}

/** Parses one declaration group and leaves its terminating token current.
    Declared names are installed in `Sym` as their declarators are completed;
    the result is one `declare`, `typedef`, or initialized `dstrdecl` AST.
*/
List Compiler.parse_simple_declaration(Compiler c) => _declaration_group(c, 0);

/** Parses a non-function, non-typedef `Decl` macro argument.
    Parentheses group declarations with independent types. The invocation
    delimiter remains current; flat destructuring may omit its initializer.
*/
List Compiler.parse_declaration_argument(Compiler c) {
  if (c.test(<(>)) {
    Array declarations = [];
    do declarations.push(c.parse_declaration_argument()); while (c.test(<,>));
    c.expect(<)>);
    return %(seq @(declarations.list_free()));
  }
  List storage = _storage_class(c);
  if (storage === %(typedef))
    $fail.parse_decl_typedef(c, c.token);
  List (type, binding_type) = _declaration_types(c, storage);
  if (_destructure_starts(c))
    return _destructure_declaration(c, type, binding_type, 1);
  List binding = _declarator_init(c, binding_type, NULL);
  List declaration = _finish_declaration(c, <declare>, type, $(binding), 0);
  if (declaration.type_from_ast().is_function())
    $fail.parse_decl_function(c, c.token);
  return declaration;
}

/** Reports whether the current identifier starts a C static assertion. */
int Compiler.test_static_assert(Compiler c) =>
  c.at_word("_Static_assert");

/** Parses a C assertion declaration; native C owns constant-expression
    checks.
*/
List Compiler.parse_static_assert(Compiler c) {
  if (c.shallow) {
    _x2c_skip_shallow_expression(c, 0);
    c.expect(<;>);
    return %(c-assert);
  }
  c.next();
  c.expect(<(>);
  List condition = c.parse_assignment();
  c.expect(<,>);
  List message = c.parse_assignment();
  c.expect(<)>);
  c.expect(<;>);
  return %(c-assert $condition $message);
}

/* declaration starts

   Statement, expression, and row parsing share one recognizer of the
   declaration prefix. A row can additionally require an identifier type to
   be followed by a declarator, which resolves the one C-compatible comma
   ambiguity. */

/** Tests whether the current token can begin a declaration without consuming.
    Typedefs, package aliases, and macro-hole kinds are resolved through the
    current compiler state.
*/
int Compiler.test_declaration(Compiler c) => _test_declaration_start(c, 0);

// finishing a declaration

/** Rejects transparent references in object and function-result types.
    References inside a function's parameter list remain supported.
*/
void Compiler.check_reference_placement(Compiler c, Type type) {
  type = c.sym.normalize_declared_type(type);
  if (<&> in type || <opt-ref> in type)
    $fail.parse_reference_placement(c, NULL);
}

// declaration rows and initializers

static List _declaration_group(Compiler c, int row) {
  List storage = _storage_class(c);
  if (storage === %(typedef)) return _typedef(c, storage, row);
  List (type, binding_type) = _declaration_types(c, storage);
  if (_destructure_starts(c))
    return _destructure_declaration(c, type, binding_type, 0);
  List bindings = _declarator_list(c, binding_type, NULL, row);
  return _finish_declaration(c, <declare>, type, bindings, 0);
}

static List _typedef(Compiler c, List context, int row) {
  Token first = c.token;
  // An imported `typedef const char *(*fn)(int)` names a qualified type
  // like an object declaration does, so read the qualifiers first.
  List quals = _type_qualifiers(c);
  List spec = quals.append(_type_specifier(c));
  spec = c.sym.local_type(spec);
  List bindings = _declarator_list(c, spec, context, row);
  /* A typedef's own alignment changes every record field that names it,
     even when the record declaration has no attribute of its own. */
  if (_layout_attribute_since(c, first))
    foreach (List declarator in bindings) {
      String name = Ast.binding_spelling(declarator.cadr());
      if (name) c.sym.set(%($name "layout-attribute"), %(unknown));
    }
  return _finish_declaration(c, <typedef>, spec, bindings, 0);
}

/* Reads the qualifiers, the type specifier, and any storage macro after it,
   `int LOCAL f(void)`, and returns the declared type and the type its names
   are bound to. Source specifier text, such as `("_Noreturn")`, is written
   with the declaration but is no part of the bound type. An aggregate binds
   its short tag; the declared type keeps the body. */
module List _declaration_types(Compiler c, List storage) {
  List quals = _type_qualifiers(c);
  int managed = <auto> in storage;
  List hole = managed ? c.peek_macro_hole() : NULL;
  int inferred = managed &&
    ((c.peek(0) == <ident> &&
      (c.peek(1) == <=> || c.peek(1) == <;> || c.peek(1) == <,>)) ||
     (hole && hole.assoc(<kind>) == <name>));
  Type spec = inferred ? NULL : _type_specifier(c);
  Array trailing = [];
  // C11 6.11.5: a storage class after the type is obsolescent but legal, and
  // preprocessed source spells an expanded storage macro that way.
  loop {
    Symbol symbol = c.peek(0);
    if (symbol != <typedef> &&
        (symbol.is_storage_class() || symbol.is_inline())) {
      trailing.push(symbol);
      c.next();
      continue;
    }
    if (!_prefix_macro_words(c, 0, trailing)) break;
  }
  if (trailing.len()) storage = %( @(trailing.list_free()) @storage );
  List words = storage.filter(%!(item) => item is <symbol>);
  Type binding_type = c.sym.local_type(%( @words @quals @spec ));
  if (spec.is_aggregate_tag_body()) {
    Var (aggregate, tag, body) = spec;
    binding_type = $(@words, @quals, aggregate, tag);
  }
  return $(c.sym.local_type(%( @storage @quals @spec )), binding_type);
}

/* A typedef name after a comma is ambiguous: `int i, T;` declares another
   int, while `int i, T value;` begins a fresh declaration. Ask the same
   declaration recognizer used by every other parser entry, but require a
   declarator after an identifier type in this one ambiguous position. */
module int _group_comma(Compiler c) {
  if (c.peek(0) != <,>) return 0;
  Token comma = c.token;
  c.next();
  int result = _test_declaration_start(c, 1);
  c.token = comma;
  return result;
}

static int _test_declaration_start(
  Compiler c, int require_declarator) {
  Symbol sym = c.peek(0);
  if (c.macro_holes && sym == <$>) return _hole_starts(c);
  if (sym.is_storage_class() || sym.is_type_qualifier() ||
      sym.is_builtin_type() || sym == <inline>) return 1;
  if (sym != <ident>) return 0;
  // A leading attribute belongs to a declaration in every position.
  if (c.token.text == "__attribute__" && _attribute_starts(c)) return 1;
  /* A prefix macro contributes declaration specifiers, so `LOCAL int x = 1;`
     is a declaration wherever it is written. */
  Var definition;
  if (c.object_macros.try_get(c.token.text, definition) &&
      (definition is <list> || definition == <wrapper>))
    return 1;
  return _type_name_starts(c, require_declarator);
}

/* A type hole starts a declaration, and so does a hole of no declared kind
   that a name follows. */
static int _hole_starts(Compiler c) {
  List hole = c.peek_macro_hole();
  if (!hole) return c.meta_call_starts_declaration();
  Symbol kind = hole.assoc(<kind>);
  if (kind) return kind == <type>;
  Symbol next = c.after_hole().type;
  return next == <ident> || next == <$> || next == <@>;
}

/* An identifier that names no object starts a declaration when the token
   after it, or after a package alias's member, can follow a type name. */
static int _type_name_starts(Compiler c, int require_declarator) {
  Token head = c.token;
  String alias = c.package_alias_spelling();
  String name = alias ? alias
              : c.package_member_spelling(c.token.text);
  Type lookup = c.sym.get($(name ? name : c.token.text));
  if (lookup && !lookup.is_typedef()) return 0;
  c.next();
  if (alias) { c.next(); c.next(); }
  Symbol next = c.peek(0);
  int is_operator = c.at_word("is");
  // `int a, b __attribute__((unused));` declares `b`, not a type named `b`.
  int attribute = _attribute_starts(c);
  c.token = head;
  if (c.macro_holes && is_operator) return 0;
  if (lookup.is_typedef() && !require_declarator) return next != <.>;
  return next == <*> || next == <&> || (next == <ident> && !attribute) ||
         (!require_declarator && next == <)>) ||
         (require_declarator && (next == <^> || next.is_type_qualifier()));
}

// destructuring declarations

/* Distinguish '(ident, ...)' from an ordinary parenthesized declarator and
   from the parameters of a type name such as `Var (Var, Var)`. */
static int _destructure_starts(Compiler c) {
  Token token = c.token;
  if (token.type != <(>) return 0;
  token = Token.skip_trivia(token + 1);
  if (token.type != <ident>) return 0;
  token = Token.skip_trivia(token + 1);
  return token.type == <,> && !_parameters_follow(c);
}

static List _destructure_declaration(
  Compiler c, List type, List binding_type, int allow_uninitialized) {
  c.check_reference_placement(binding_type);
  Token origin_token = c.token;
  List bindings = _destructure_targets(c, binding_type);
  /* A foreach destructures each element rather than an initializer, so the
     same `(a, b)` spelling stands without `=`. It reduces to the
     multi-binding declaration already supported across `in` in a `for`
     header. */
  if (allow_uninitialized || c.peek(0) == <in>)
    return %(declare $type
              (bindings @(_destructure_binds(c, bindings, binding_type))));
  if (!c.test(<=>))
    $fail.parse_destructure_init(c, c.token);
  List source = c.parse_assignment();
  List result = %(dstrdecl $type (targets @bindings) $source);
  return c.anchor_origin(result, origin_token);
}

/* ( ident, ident, ... ), each declared with the destructured type. A `_`
   keeps its spelling: an initialized destructuring discards its element,
   and a foreach or uninitialized form declares it as an ordinary name. */
static List _destructure_targets(Compiler c, List binding_type) {
  Array targets = [];
  c.expect(<(>);
  loop {
    if (c.peek(0) != <ident>)
      $fail.parse_destructure_name(c, c.token);
    List ident = c.parse_basic_identifier();
    targets.push(ident ~= %("_") ? ident
                 : _destructure_target(c, ident, binding_type));
    if (!c.test(<,>)) break;
  }
  c.expect(<)>);
  return targets.list_free();
}

// The declaration of the target `ident`, a template local in a template.
static List _destructure_target(Compiler c, List ident, List binding_type) {
  if (!c.macro_holes) return c.sym.declare(NULL, ident, binding_type);
  List local = c.macro_introduced_name(ident.car());
  c.bind_template_local(local, binding_type, NULL);
  return local;
}

/* Wraps destructuring targets as the binding forms a declaration carries,
   so a foreach binder reaches the transform as a plain declaration of two
   names. */
static List _destructure_binds(Compiler c, List targets, List binding_type) {
  Array binds = [];
  foreach (List target in targets) {
    if (target ~= %("_")) target = _destructure_target(c, target, binding_type);
    binds.push(%(bind $target ()));
  }
  return binds.list_free();
}

module List _finish_declaration(
  Compiler c, Symbol tag, List base, List declarators,
  int preserved_self) {
  List before = NULL;
  if (<auto> in base && !c.macro_holes && !c.shallow)
    base = _auto_declaration(c, tag, base, declarators, before);
  if (tag == <typedef> && c.source_private > 0 &&
      !base.type().is_static()) base = %(static @base);
  if (tag == <declare>) base = _linked_static_base(c, base, declarators);
  List modifiers = NULL;
  base = Type.declaration_base(base, modifiers);
  if (modifiers) {
    Array bound = [];
    foreach (List declarator in declarators)
      bound.push(Ast.append_modifiers(declarator, modifiers));
    declarators = bound.list_free();
  }
  if (tag == <declare> || tag == <decl>)
    foreach (List declarator in declarators) {
      Type type = %(declare $base (bindings $declarator)).type_from_ast();
      c.check_reference_placement(type);
    }
  List declaration = %($tag $base (bindings @declarators));
  declaration = tag == <declare> && !preserved_self
    ? _lower_self_declaration(c, declaration)
    : declaration;
  return before ? %(seq $before $declaration) : declaration;
}

/* A file-scope function declared again with `extern` or no storage keeps the
   internal linkage of its earlier `static` declaration, as in C, so the
   declaration emits `static`. An object so declared has external linkage
   and conflicts, which C reports. */
static List _linked_static_base(Compiler c, List base, List declarators) {
  Type type = base;
  if (!c.sym.at_file_scope() || type.is_static() ||
      !declarators)
    return base;
  foreach (List declarator in declarators) {
    Type declared = %(declare $base (bindings $declarator)).type_from_ast();
    List bound = declarator;
    if (declarator ~= %(op = ?target ?)) bound = target;
    if (!declared.is_function() || !c.sym.is_file_static(bound.cadr()))
      return base;
  }
  return %(static @(base.filter(%!(item) => item != <extern>)));
}

/* Keep Self only in method metadata. The binding and AST receive the
   declaring owner, so direct calls and generated C retain the existing
   function signature. */
static List _lower_self_declaration(Compiler c, List declaration) {
  List binding = NULL;
  match (declaration) {
    case %(? ? (bindings (op = (? ?name *) ?))): binding = name;
    case %(? ? (bindings (? ?name *))): binding = name;
  }
  if (!binding) return declaration;
  List method = c.fact(%(method $binding));
  if (!method) return declaration;
  Type owner = _self_owner_type(c, method);
  if (!owner) return declaration;
  List lowered = declaration.search_replace(<self>, owner.car());
  if (lowered == declaration) {
    c.drop_fact(%(self $binding));
    return declaration;
  }
  Type signature = declaration.type_from_ast();
  if (!signature.is_function()) return declaration;
  String spelling = Ast.binding_spelling(binding);
  Type relative = signature.declared();
  Type concrete = lowered.type_from_ast().declared();
  c.set_fact(%(self $binding), relative);
  c.sym.set($(spelling), concrete);
  c.sym.set(%(self $spelling), relative);
  _lower_parameter_self(c, owner.car());
  return lowered;
}

static Type _self_owner_type(Compiler c, List method) {
  String source = method.car();
  Type declared = c.sym.get($(source));
  if (declared.is_typedef())
    return $(_type_reference(c, 0, source));
  Symbol builtin = Atom.intern(source);
  return builtin.is_builtin_type() ? $(builtin) : NULL;
}

static void _lower_parameter_self(Compiler c, Var replacement) {
  Map symbols = c.params.symbols;
  if (!symbols) return;
  foreach (List (key, original) in symbols) {
    List lowered = original.search_replace(<self>, replacement);
    if (lowered != original) {
      c.sym.put(symbols, key, lowered);
      Var binding;
      if (c.params.bindings.try_get(key, binding))
        c.set_fact(%(type $binding), lowered);
    }
  }
}

/* Collection installs a constructed declaration's names and keeps its
   initializers (see `_bind_declaration`). The full parse resolves them
   under the macro stack that constructed them. */
module List _bind_collected_initializers(
  Compiler c, List input, Var declaration, Var construction) {
  if (c.shallow) return input;
  with (c.macro_stack = construction) {
    return c.bind_syntax(declaration, <unit>, c.return_type);
  }
}

/* Completes a constructed declaration's base type, then installs each
   declarator as the parser does. Only a field may declare a bit-field.
   Collection keeps file-scope initializers for the full parse, with the
   macro stack that constructed them. Binding selects a Symbol declaration
   tag before this path runs. */
module List _bind_declaration(
  Compiler c, Symbol tag, Var base, List declarators, Symbol context) {
  int shallow = c.shallow;
  if (c.public_bodies && context == <unit>) c.shallow = 1;
  defer c.shallow = shallow;
  if (!_declaration_legal(tag, context)) return _construction_error(c);
  if (<auto> in base.list() && !c.macro_holes && !c.shallow &&
      context != <block>) $fail.parse_auto_storage(c, c.token);
  base = _finish_type(c, base);
  List field_context = context == <field> ? c.aggregate_type : NULL;
  List declaration_context = tag == <typedef> ? %(typedef) : field_context;
  Array output = [];
  int preserved_self = 0, initializes = 0;
  foreach (Var value in declarators)
    foreach (List declarator in c.evaluate_macro_rows(value)) {
      declarator = _finish_fnmods(c, declarator);
      if (context != <field> && _has_bitfield(declarator))
        return _construction_error(c);
      match (declarator) case %(op = * *): initializes = 1;
      List installed = _install_declarator(
        c, base, declaration_context, declarator, NULL, preserved_self);
      output.push(installed);
    }
  List decl = _finish_declaration(
    c, tag, base, output.list_free(), preserved_self);
  if (context == <unit>) c.record_declaration_visibility(decl);
  if (c.shallow && context == <unit> && initializes)
    return %(declaration-initialized $decl $(c.macro_stack));
  if (context == <block> && tag == <declare>)
    return c.finish_initializers(decl, c.token);
  return decl;
}

/* A typedef stands in a unit or a block, a `decl` only in a block, and any
   other declaration also in an aggregate. */
static int _declaration_legal(Symbol tag, Symbol context) {
  if (tag == <typedef>) return context == <unit> || context == <block>;
  if (tag == <decl>) return context == <block>;
  return context == <unit> || context == <block> || context == <field>;
}

static int _has_bitfield(List declarator) {
  List syntax = declarator;
  if (syntax ~= %(op = ?binding ?)) syntax = binding;
  if (syntax ~= %(bind ? ?modifiers)) {
    Type mods = modifiers;
    return mods.is_bitfield();
  }
  return 0;
}

/* Destructuring targets share one base type, so they bind as one
   declaration before the source resolves. A `_` target discards its
   element: it keeps its position and declares nothing. */
module List _bind_targets(
  Compiler c, Var base, List targets, Var source) {
  Array declarators = [];
  foreach (List target in targets)
    if (!(target ~= %("_"))) declarators.push(%(bind $target ()));
  List declaration = c.bind_syntax(
    %(declare $base
        (bindings @(declarators.list_free()))),
    <block>, c.return_type
  );
  if (declaration ~= %(declare ?bound_base (bindings *bindings))) {
    Array bound_targets = [];
    foreach (List target in targets) {
      if (target ~= %("_")) { bound_targets.push(target); continue; }
      List binding = bindings.car();
      bindings = bindings.cdr();
      if (binding ~= %(bind ?name ?)) bound_targets.push(name);
    }
    return %(dstrdecl $bound_base
             (targets @(bound_targets.list_free()))
             $(_resolve(c, source)));
  }
  return _construction_error(c);
}

/* Each typed target contributes one bound declaration. */
module List _bind_typed_targets(
  Compiler c, List parameters, Var source) {
  Array bound_parameters = [];
  foreach (List parameter in parameters)
    match (parameter)
      case %(param ?base (!set ?declarator (bind ? ?))): {
        List declaration = c.bind_syntax(
          %(declare $base (bindings $declarator)), <block>, c.return_type);
        if (declaration ~= %(declare ?bound_base (bindings ?binding)))
          bound_parameters.push(%( param $bound_base $binding ));
      }
  return %(dstrdecl (params @(bound_parameters.list_free()))
           $(_resolve(c, source)));
}
