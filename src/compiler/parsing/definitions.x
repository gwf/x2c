/* top-level definitions

   Each form the full parse reads records the facts that later checks use:
   its object and function definitions, prototypes, static initializers,
   and the token span of its source. A conflict between definitions is
   reported at `site`, the form's first token, or at the cursor for a form
   without one. */

module void _record_top_level(Compiler c, List node, Token site) {
  match (node) {
    case %(declare (!set ?declared (*)) (bindings *bindings)): {
      Type type = declared;
      _record_objects(c, bindings, site);
      _record_static_object(c, type, bindings);
      _record_prototypes(c, type, bindings);
    }
    case %(function ?return_type
           (!set ?target (bind ?binding *)) ?): {
      List declaration = %(declare $return_type (bindings $target));
      _record_definition(c, declaration.type_from_ast(), binding, site);
    }
  }
}

/* An initializer makes a file-scope declaration a definition; a tentative
   one may be repeated. */
static void _record_objects(Compiler c, List bindings, Token site) {
  foreach (List row in bindings)
    match (row) case %(op = (bind (!set ?binding (binding ? ?)) ?) ?): {
      List key = %(defined $binding);
      if (key in c.semantic_binding_facts())
        _report_redefinition(c, "variable", binding, site);
      c.set_fact(key, 1);
      c.set_fact(%(arms $binding), c.arms);
    }
}

/* Reports a second definition of one file-scope name, which C rejects,
   when both sit under the same conditional arms. Definitions under
   different arms are not compared. For a variable, whose initializer moves
   into the generated init function, a duplicate under two true conditions
   is therefore not detected, and the later initializer wins. */
static void _report_redefinition(
  Compiler c, String kind, List binding, Token site) {
  Var arms;
  if (!c.semantic_binding_facts().try_get(%(arms $binding), arms) ||
      !List.equal(arms, c.arms))
    return;
  String spelling = c.unprefixed(Ast.binding_spelling(binding));
  $fail.compiler_decl_duplicate(c, site, kind, spelling);
}

/* A definition remembers the token range of the top-level form that
   produced it, and whether that form is private, for the definition walk.
   A typedef or declaration may repeat its name, so each statement keys its
   own range. */
module void _record_span(Compiler c, List node, int start, int end) {
  List key = NULL;
  match (node) {
    case %(function ? (bind ?binding ?) ?): key = binding;
    case %(falias (declare ? (bindings (bind ?binding ?))) ?): key = binding;
    case %((!or typedef declare) *): key = node;
  }
  if (key)
    c.set_fact(
      %(definition-span $key), $(start, end, c.source_private > 0));
}

/* function completion

   A function's completion fact records its contract: a prototype, a
   definition, a definition that completed a prototype, or a conflict
   between two prototypes. */

// Record only prototypes reached in positioned full-parse source order.
static void _record_prototypes(
  Compiler c, Type declared_type, List items) {
  foreach (List target in items)
    match (target)
      case %(bind ?binding ?modifiers): {
        List single = %(declare $declared_type (bindings $target));
        Type type = single.type_from_ast();
        if (type.is_function()) _record_prototype(c, binding, type, modifiers);
      }
}

static void _record_prototype(
  Compiler c, List binding, Type type, List modifiers) {
  _record_attributes(c, binding, modifiers);
  List contract = _contract(c, type, binding);
  Var stored;
  if (c.semantic_binding_facts().try_get(%(completion $binding), stored)) {
    List state = stored;
    Var (state_kind, prior_contract) = state;
    if (state_kind == <definition> || state_kind == <completed>) return;
    contract = _inherited_contract(prior_contract, contract);
    if (state_kind != <prototype> || !List.equal(prior_contract, contract)) {
      c.set_fact(%(completion $binding), %(conflict));
      return;
    }
  }
  c.set_fact(%(completion $binding), %(prototype $contract));
}

/* A source attribute on the prototype belongs to the function; the
   generator writes it on the prototype it derives from the definition. */
static void _record_attributes(
  Compiler c, List binding, List modifiers) {
  List attributes = NULL;
  foreach (Var item in modifiers)
    if (item is <list> && car(item) is <string>)
      attributes = attributes ? $(@attributes, item) : $(item);
  if (attributes)
    c.set_fact(%(attributes $binding), attributes);
}

static void _record_definition(
  Compiler c, Type type, List binding, Token site) {
  List contract = _contract(c, type, binding);
  Var stored;
  if (c.semantic_binding_facts().try_get(%(completion $binding), stored)) {
    List state = stored;
    Var (state_kind, prior_contract) = state;
    if (state_kind == <prototype>) {
      _complete_prototype(c, binding, prior_contract, contract, site);
      return;
    }
    if (state_kind == <definition> || state_kind == <completed>)
      _report_redefinition(c, "function", binding, site);
  }
  c.set_fact(%(completion $binding), %(definition $contract));
  c.set_fact(%(arms $binding), c.arms);
  String spelling = Ast.binding_spelling(binding);
  if (spelling && !type.is_static()) c.fn_defs[spelling] = 1;
}

/* A definition completes the prior prototype whose contract it matches. A
   definition without `static` after a `static` prototype keeps the
   prototype's internal linkage in C. */
static void _complete_prototype(
  Compiler c, List binding, List prior_contract, List contract, Token site) {
  contract = _inherited_contract(prior_contract, contract);
  if (prior_contract != contract) {
    String spelling = Ast.binding_spelling(binding);
    $fail.compiler_decl_prototype(c, site, spelling, prior_contract, contract);
  }
  c.set_fact(%(completion $binding), %(completed $contract));
  c.set_fact(%(arms $binding), c.arms);
}

static List _inherited_contract(List prior, List current) {
  match (prior)
    case %(function-contract ?a ?b static ?d)
      if (current == %(function-contract $a $b extern $d)):
        return prior;
  return current;
}

static List _contract(Compiler c, Type type, List binding) =>
  _completion_contract(
    type, c.fact(%(method $binding)), c.fact(%(self $binding)));

static List _completion_contract(
  Type type, List method_identity, List self_signature) {
  Symbol linkage = type.is_static() ? <static> : <extern>;
  List contract = %(
    function-contract
    $(_contract_type(type, 0))
    $(_contract_type(type, 1))
    $linkage
    $method_identity
  );
  return self_signature ? contract.append($(self_signature)) : contract;
}

static Type _contract_type(Type type, int keep_qualifiers) {
  Array kept = [];
  foreach (Var item in type) {
    if (item is <list>) kept.push(_contract_type(item, keep_qualifiers));
    else if (!_omitted_specifier(item, keep_qualifiers)) kept.push(item);
  }
  return kept.list_free();
}

// A contract omits storage classes, `inline`, and qualifiers unless kept.
static int _omitted_specifier(Var item, int keep_qualifiers) {
  if (item is not <symbol>) return 0;
  Symbol symbol = item;
  return symbol.is_storage_class() ||
         (!keep_qualifiers && symbol.is_type_qualifier()) ||
         symbol.is_inline();
}

// static initializers

static void _record_static_object(
  Compiler c, Type declared, List bindings) {
  if (!declared.is_static()) return;
  int declared_var = c.sym.is_var_type(declared);
  if (!declared_var && !_initializable_type(c, declared)) return;
  foreach (List binding_init in bindings)
    match (binding_init)
      case %(op = (bind (!set ?binding (binding ? ?)) ?)
             (expr (!set ?initializer_type (*)) ?value)): {
        if (declared_var && !_initializable_type(c, initializer_type))
          continue;
        Map references = {}, Array ordered = [];
        _collect_references(value, references, ordered);
        c.static_init_deps[binding] = ordered.list_free();
      }
}

static int _initializable_type(Compiler c, Type type) =>
  c.sym.is_string_type(type) || c.sym.is_named_value_type(type, "List") ||
  c.sym.is_array_type(type) || c.sym.is_map_type(type) ||
  c.sym.is_named_value_type(type, "Func");

static void _collect_references(Var value, Map references, Array ordered) {
  if (value is not <list> || value.is_nil()) return;
  List node = value;
  match (node)
    case %(input *arguments): {
      foreach (List argument in arguments)
        _collect_references(argument.cadr(), references, ordered);
      return;
    }
  match (node)
    case %(indexinit ? ?initializer): {
      _collect_references(initializer, references, ordered);
      return;
    }
  match (node)
    case %(expr (!set ?type (*)) $($source_identifier_content(
        %((!set ?binding (binding ? ?)))))): {
      if (!type.type().is_function()) {
        if (!(binding in references)) ordered.push(binding);
        references[binding] = 1;
      }
      return;
    }
  foreach (Var child in node) _collect_references(child, references, ordered);
}

module void _check_static_inits(Compiler c) {
  Map statics = c.sym.file_statics();
  foreach (List (binding, dependencies) in c.static_init_deps) {
    foreach (List reference in dependencies) {
      String name = Ast.binding_spelling(reference);
      if (!name || $(name) in statics) continue;
      String target = Ast.binding_spelling(binding);
      $fail.compiler_static_dependency(
        c, _init_token(c, binding), name, target);
    }
  }
}

static Token _init_token(Compiler c, List binding) {
  Var index;
  if (!c.init_tokens.try_get(binding, index)) return NULL;
  Token tokens = c.tokenizer.tokens;
  return tokens + index.integer();
}
