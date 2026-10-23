/*  values.x -- Macro values, code carriers and placement */

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
   depend on how this translation numbered bindings; each resolves where the
   value's expansion lands. */
module Var _macro_value_names(Var value) {
  if (value is not <list>) return value;
  String spelling = NULL;
  if (Ast.try_binding(value, NULL, spelling))
    return %(binding-name $spelling);
  List child;
  $ast.rewrite_children(value.list(), child, _macro_value_names(child));
}

/* NULL for a template's hole of that name or for an unknown macro. */
module List _macro_value(Compiler c, Atom name) {
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
  if (c.peek(0) == <$> && c.peek(1) == <"{">) return NULL;
  Token saved = c.token;
  List expression = _pattern_macro(c);
  if (!expression || c.peek(0) != <(>) {
    c.token = saved;
    return NULL;
  }
  if (saved.type == <$> && !_simple_labels(c)) {
    c.token = saved;
    return c.try_parse_macro_subpattern(0);
  }
  List names = _pattern_labels(c);
  List labels = c.cache_literal_list(names);
  List shape = _case_shape(c, saved, names);
  if (shape)
    return c.resolve_expression(
      $!( Macro_case_shape($expression, $labels, $shape) ), saved);
  return c.resolve_expression(
    $!( Macro_case_pattern($expression, $labels) ), saved);
}

/* The pattern a `case` on the macro `$NAME` at `at` tests for `names`,
   cached, or NULL for a `Macro` variable or a pattern that resolves a
   reference against the subject of each call. */
static List _case_shape(Compiler c, Token at, List names) {
  String spelling = NULL;
  Var stored;
  if (!c.macro_pattern_at(at, spelling, stored)) return NULL;
  Macro shape = _macro_value_names(stored);
  List derived = shape.matcher(names).pattern;
  return derived ? c.cache_literal_list(derived) : NULL;
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

/** Returns the `(` after a visible macro's `$NAME` at `at`, storing its
    spelling and definition, or NULL. The cursor does not move.
*/
Token Compiler.macro_pattern_at(
  Compiler c, Token at, String &spelling, Var &stored) {
  if (at.type != <$>) return NULL;
  Token saved = c.token;
  c.token = at;
  Token end = _scan_name(c, spelling);
  c.token = saved;
  if (!spelling || end.type != <(> ||
      !_try_definition(c, Atom.intern(spelling), 1, stored) ||
      stored is not <list> || stored.list().car() != <macrodef>)
    return NULL;
  return end;
}

/* Whether the parenthesized labels at the cursor are all `?name` or
   `*name` binders. */
static int _simple_labels(Compiler c) {
  int at = 1;
  if (c.peek(at) == <)>) return 1;
  loop {
    if ((c.peek(at) != <?> && c.peek(at) != <*>) ||
        c.peek(at + 1) != <ident>)
      return 0;
    if (c.peek(at + 2) == <)>) return 1;
    if (c.peek(at + 2) != <,>) return 0;
    at += 3;
  }
}

/** Parses `$NAME(P, ...)` in a pattern, where each argument is a pattern,
    into the pattern for code NAME builds with each argument pattern in its
    hole. It matches the shelled expression or its bare content; `content`
    selects the content alone, for a position whose pattern already writes
    the `(expr TYPE ...)` shell. Returns NULL without consuming tokens when
    no macro NAME is visible.
*/
List Compiler.try_parse_macro_subpattern(Compiler c, int content) {
  Token start = c.token;
  String spelling = NULL;
  Var stored;
  Token end = c.macro_pattern_at(start, spelling, stored);
  if (!end) return NULL;
  c.token = end;
  Macro shape = _macro_value_names(stored);
  List patterns = c.parse_macro_pattern_arguments();
  int expected = shape.assoc(<parameters>).list().len();
  if (patterns.len() != expected)
    $fail.macros_macro_pattern_arity(c, start, spelling, expected);
  return c.cache_literal_list(_macro_subpattern(shape, patterns, content));
}

/* `shape`'s pattern with each argument pattern in its hole. A binder
   stands in its hole directly; any other pattern replaces a private binder
   there, spliced for a sequence or Type hole. */
static List _macro_subpattern(Macro shape, List patterns, int content) {
  Array names = [];
  Map replacements = {};
  List spelled = patterns.flatten_all();
  int index = 0;
  foreach (List hole in shape.assoc(<parameters>).list()) {
    Var pattern = patterns.car();
    patterns = patterns.cdr();
    if (pattern.is_binder()) {
      names.push(pattern);
      continue;
    }
    Symbol kind = hole.assoc(<kind>);
    int list = hole.assoc(<sequence>).int() || kind == <type> ||
               kind == <captures>;
    Atom binder = _unused_binder(list ? "*" : "?", spelled, index);
    names.push(binder);
    replacements[binder] = pattern;
  }
  List pattern = _substitute_binders(
    shape.pattern(names.list_free()), replacements);
  match (pattern)
    case %(expr ? ?body): return content ? body : %(!or $pattern $body);
  return pattern;
}

/* A private binder that no argument pattern spells with either sigil. */
static Atom _unused_binder(String sigil, List spelled, int &index) {
  loop {
    String name = %"__pattern_${index++}";
    if (!(Atom.intern("?" + name) in spelled) &&
        !(Atom.intern("*" + name) in spelled))
      return Atom.intern(sigil + name);
  }
}

/* Replaces each private binder with its argument pattern, splicing a List
   binder's elements, without interpreting the pattern's guards. */
static Var _substitute_binders(Var value, Map replacements) {
  if (value is not <list> || value.is_nil()) return value;
  Array items = [];
  foreach (Var child in value.list()) {
    Var replacement;
    if (child.is_binder() && replacements.try_get(child, replacement)) {
      if (child.str().startswith("*") && replacement is <list>)
        foreach (Var item in replacement.list()) items.push(item);
      else items.push(replacement);
    }
    else items.push(_substitute_binders(child, replacements));
  }
  return items.list_free();
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
  foreach (List binding in definition.assoc(<captures>).list()) {
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
    into a macro value application, or that `Compiler.bind_code_value`
    binds as one. Effects are applied in order under the application's
    transaction, and their tokens are replaced in the code.
    `retained` reports a bound or lowered stage, which ordinary binding
    leaves untouched. Lowered code is not searched for a leftover binder.
    Returns 0 for any other value.
*/
int Compiler.take_code_value(
  Compiler c, Var input, Var &value, int &retained) {
  match (input) case %(code-value ?(String stage) ?code ?effects): {
    Map replacements = _code_effects(c, effects);
    value = replacements.len() ? _replace_bindings(code, replacements) : code;
    retained = stage != "source";
    if (stage != "lowered") {
      Var binder = _carrier_binder(value);
      if (binder) _unbound(c, binder.str(), c.token);
    }
    return 1;
  }
  return 0;
}

/* Applies a carrier's effects in order and returns what replaces each
   effect's token in the code. */
static Map _code_effects(Compiler c, Var effects) {
  Map replacements = {};
  foreach (List effect in effects)
    match (effect) {
      case %(rewrite ?point ?kind ?name ?shape ?holes): {
        _register_rewrite(
          c, _rewrite_rule(point, kind, name, shape, holes, 0, 1));
        _record_compile_time_effect(
          c, %(compile-time rewrite $point ${c.freeze_declaration_syntax(kind)}
            $name ${c.freeze_declaration_syntax(shape)}
            ${c.freeze_declaration_syntax(holes)}), c.token);
      }
      case %(new-name ?token ?(String role)):
        replacements[token] = c.sym.introduce(c.fresh_name(role));
      case %(cleanup ?token ?placed): {
        replacements[token] = placed;
        c.needs_exception = 1;
      }
      default:
        $fail.macros_code_effect(c, c.token, effect);
    }
  return replacements;
}

/** Places `code` where `where` says, under the active expansion's
    transaction: `(after-statement)` after the enclosing block item or
    initialized declarator; `(block-exit)` on every exit from the enclosing
    block from that point on, as a `defer` placed after it;
    `(function-entry)` at the entry of the enclosing function, at parse or
    transform time, in placement order before its first statement;
    `(unit-support)` among the unit's support declarations, once per KEY
    with `(unit-support KEY)`; or `(unit-init)` in the unit's file
    initialization, in AREA with `(unit-init AREA)`. */
void Compiler.place(Compiler c, List where, Var code) {
  match (where) {
    case %(after-statement): c.place_after(code);
    case %(function-entry): c.place_entry(code);
    case %(block-exit): {
      Macro deferred = $deferred;
      c.place_after(deferred(code));
    }
    case %(unit-support): _place_support(c, code);
    case %(unit-support ?key): {
      Var placed;
      $adapter.memo(c, %(unit-support $key), placed) {
        _place_support(c, code);
        placed = 1;
      }
    }
    case %(unit-init):
      c.add_init(<finish>, c.bind_syntax(code, <block>, NULL));
    case %(unit-init (!set ?area (!or protocol prepare statics finish))):
      c.add_init(area, c.bind_syntax(code, <block>, NULL));
    default: $fail.macros_placement(c, c.token, where);
  }
}

/* Adds the file-scope `code` a placement gives to the unit's support. It
   binds at file scope whatever local scope is open. */
static void _place_support(Compiler c, Var code) {
  Block local = c.sym.close_local_scopes();
  defer c.sym.reopen_scopes(local);
  c.add_support(_written_support(c, c.bind_syntax(code, <unit>, NULL)));
}

/** Binds a code-value carrier that a meta call returned outside a macro
    value application as an application binds it, under a transaction that
    also covers its effects. */
List Compiler.bind_code_value(
  Compiler c, List carrier, Symbol position, Type return_type) {
  List bound = NULL;
  $let(c.macro_application, c.macro_application + 1) {
    SymTxn transaction = { 0 };
    if (c.recovery_depth > 0)
      transaction = c.begin_semantic_transaction();
    defer transaction.rollback();
    bound = c.bind_syntax(carrier, position, return_type);
    transaction.commit();
  }
  return bound;
}

/* A named binder left as a carrier's code, identifier, or declarator
   after its effects were applied, or NULL. Binders elsewhere are data,
   such as a lowered match pattern, and a bare `*` or `?` is syntax. A
   carrier the code holds is searched when it is taken. */
static Var _carrier_binder(Var value) {
  if (value.is_binder()) return value.str().len() > 1 ? value : NULL;
  if (value is not <list>) return NULL;
  match (value) {
    case $source_identifier_content(%(?name *)):
      if (name.is_binder() && name.str().len() > 1) return name;
    case %(bind ?name *):
      if (name.is_binder() && name.str().len() > 1) return name;
    case $source_literal_content(%(*)): return NULL;
    case %((!or "x2c.template" "x2c.quoted" macro-invoke macrodef
                code-value) *):
      return NULL;
  }
  foreach (Var child in value.list())
    if (child is <list>) {
      Var binder = _carrier_binder(child);
      if (binder) return binder;
    }
  return NULL;
}
