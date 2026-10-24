/*  types.x -- type specifiers, fields and enumerators

    Copyright (c) 2025 Gary William Flake.
*/

static keyword loop $private.loop;


// declaration specifiers

/* Declaration specifiers before the qualifiers and type: storage classes
   and `inline` in source order, then `_Noreturn` and attributes as source
   text. The storage words lead, where C places them and where a declared
   type's storage is read. One storage class is allowed, except that
   `threaded` pairs with another one the way C's thread-local specifier
   pairs with `static` or `extern`. A second one stops the run, so
   `static extern` is diagnosed instead of passed to C. */
module List _storage_class(Compiler c) {
  Array storage = [], text = [], int seen_threaded = 0, seen_ordinary = 0;
  defer { storage.free(); text.free(); }
  loop {
    Symbol symbol = c.peek(0);
    String attribute = _attribute(c);
    if (attribute) text.push(%($attribute));
    else if (c.take_word("_Noreturn")) text.push(%("_Noreturn"));
    else if (symbol.is_inline() ||
             (symbol == <threaded> ? !seen_threaded++ :
              symbol.is_storage_class() && !seen_ordinary++)) {
      storage.push(symbol);
      c.next();
      // The linkage name in `extern "C" int f(void);` means nothing to C.
      if (symbol == <extern> && c.peek(0) == <lit-char*>) c.next();
    }
    else if (!_prefix_macro_words(c, 0, storage)) break;
  }
  return %( @{storage.list()} @{text.list()} );
}

module String _attribute(Compiler c) {
  if (!_attribute_starts(c)) return NULL;
  Token first = c.token, last = Token.skip_trivia(first + 1).group_close();
  c.token = last.after_group();
  return String.new_len(c.text + first.pos, last.pos + last.len - first.pos);
}

/* A GNU attribute or an attribute macro is kept as its source text. */
module int _attribute_starts(Compiler c) {
  Var definition;
  return c.peek(0) == <ident> && c.peek(1) == <(> &&
         (c.token.text == "__attribute__" ||
          (c.object_macros.try_get(c.token.text, definition) &&
           definition == <annotation>));
}

/* Source is read before preprocessing, so a macro whose body is declaration
   specifiers and attributes, such as an export annotation, still sits in a
   declaration. A specifier position of `rank`, 0 for storage classes and
   `inline`, 1 for qualifiers, and 2 for builtin types, leaves a macro with
   words of a later rank to that position; otherwise it consumes the macro
   and takes all of its words into `words`, so `int LOCAL f(void)` keeps the
   `static` of `#define LOCAL static`. */
module int _prefix_macro_words(Compiler c, int rank, Array words) {
  Var definition;
  if (c.peek(0) != <ident>) return 0;
  if (!c.object_macros.try_get(c.token.text, definition)) {
    if (rank || !_unseen_prefix(c)) return 0;
    c.next();
    return 1;
  }
  if (definition == <wrapper> && c.peek(1) == <(>) {
    /* `EXPORT(const char *) f(void);` wraps the type. The name and its
       parentheses contribute nothing; the closing one is hidden so the
       type and declarator between them parse as written. */
    Token close = Token.skip_trivia(c.token + 1).group_close();
    if (close.type != <eof>) close.type = <comment>;
    c.next();
    c.next();
    return 1;
  }
  if (definition is not <list>) return 0;
  foreach (Symbol word in definition)
    if ((word.is_type_qualifier() ? 1 : word.is_builtin_type() * 2) > rank)
      return 0;
  foreach (Symbol word in definition) words.push(word);
  c.next();
  return 1;
}

/* A collected C header may prefix a declaration with a macro defined only
   where collection cannot see it, such as on the C compile line. A name
   before a declaration keyword cannot be a type, so it expands to storage,
   visibility, or attributes and contributes nothing to the collected type. */
static int _unseen_prefix(Compiler c) {
  Symbol next = c.peek(1);
  return c.shallow && c.filename.endswith(".h") &&
         (next.is_builtin_type() || next.is_type_modifier() ||
          next.is_type_qualifier() || next.is_storage_class() ||
          next.is_inline());
}

module List _type_qualifiers(Compiler c) {
  Array quals = auto [];
  loop {
    _x2c_complete_here(c, <type>, _type_keywords());
    Symbol symbol = c.peek(0);
    if (symbol.is_type_qualifier()) {
      quals.push(symbol);
      c.next();
    }
    else if (!_prefix_macro_words(c, 1, quals)) break;
  }
  return quals;
}

module List _type_keywords(void) => %(
  "void" "char" "short" "int" "long" "float" "double"
  "signed" "unsigned" "struct" "union" "enum"
  "const" "restrict" "volatile"
);

// type specifiers

/** Parses a type specifier with qualifiers and pointer/reference modifiers.
    Returns its flat `Type` AST and leaves the first following token current.
*/
Type Compiler.parse_type_name(Compiler c) {
  List qualifiers = _type_qualifiers(c);
  List specifier = _type_specifier(c);
  List pointers = _pointer(c);
  Type type = %( @pointers @qualifiers @specifier );
  return c.sym.local_type(type);
}

module List _type_specifier(Compiler c) {
  c.require_input();
  List slot = c.try_parse_macro_slot(<type>);
  if (slot) return %($slot);
  List syntax = NULL;
  switch (c.peek(0)) {
    case <struct>: case <union>: case <enum>:
      syntax = _tagged_type(c); break;
    case <ident>:
      if (c.token.text == "Self") {
        c.next();
        syntax = %(self);
        break;
      }
      Array words = [];
      _prefix_macro_words(c, 2, words);
      syntax = words.list_free();
      if (!syntax) syntax = _typedef_name(c);
      break;
    default:
      syntax = _primitive_type(c);
  }
  return syntax;
}

static List _primitive_type(Compiler c) {
  Token start = c.token;
  Array specs = [];
  while (_is_scalar_specifier(c.peek(0))) {
    specs.push(c.peek(0));
    c.next();
  }
  Type source = specs.list_free(), scalar = source.scalar();
  if (scalar) return scalar;
  // The preprocessed shallow pass only contributes declarations. The full
  // pass over the original source reports source-level type diagnostics.
  if (c.shallow) return source;
  $fail.parse_scalar_invalid(c, start, source);
}

static int _is_scalar_specifier(Symbol symbol) {
  switch (symbol)
    case <signed>: case <unsigned>: case <short>: case <long>:
    case <char>: case <int>: case <float>: case <double>: case <void>:
      return 1;
  return 0;
}

static List _typedef_name(Compiler c) {
  String name = _package_alias_member(c);
  if (!name) name = c.package_member_spelling(c.token.text);
  if (!name) name = c.token.text;
  c.next();
  if (c.package || c.line_markers) name = _type_reference(c, 0, name);
  return %($name);
}

/* Module and package files spell their own file-scope type names bare. A
   block-scope typedef or tag of the name shadows every file-scope one;
   then the current module file's static of that name comes first. In
   package mode a bare-key miss with a prefixed hit re-spells the
   reference. ASTs carry raw strings and emit literally. */
module String _type_reference(Compiler c, Symbol tag, String name) {
  List bare = tag ? %($tag $name) : %($name);
  if (c.sym.has_local(bare)) return name;
  String own = c.scoped_spelling(c.file_prefix(), name);
  if (own != name && c.sym.get_exact(tag ? %($tag $own) : %($own)))
    return own;
  String prefixed = c.package_spelling(name);
  if (prefixed == name) return name;
  if (c.sym.get_exact(bare)) return name;
  List hit = tag ? %($tag $prefixed) : %($prefixed);
  return c.sym.get_exact(hit) ? prefixed : name;
}

// aggregates

static List _tagged_type(Compiler c) {
  Token first = c.token;
  Symbol tag = c.peek(0);
  c.next();
  _skip_attributes(c);
  List name = _tag_name(c);
  if (name && (c.package || c.line_markers))
    name = _scoped_aggregate_name(c, tag, name);
  int defines = c.peek(0) == <"{"> ||
    (c.peek(0) == <;> && (tag != <enum> || c.macro_holes));
  Var used = c.aggregate_name(tag, (name ? name : c.gensym()).car(), defines);
  List type = %($tag $used), members = NULL;
  if (c.test(<"{">)) {
    members = tag == <enum> ? c.parse_enumerators(type) : c.parse_fields(type);
    c.expect(<"}">);
    _skip_attributes(c);
    if (!c.macro_holes)
      return _publish_aggregate_type(c, tag, used, members, first);
    if (tag != <enum>) members = cons(<fields>, members);
  }
  return members ? type.append(%($members)) : type;
}

/* C places an aggregate's own attributes after its keyword and after its
   closing brace, written out or through a macro whose body is attributes.
   Collection skips them: attribute text is no part of a collected type, and
   the layout marks hold any layout they change (see Compiler.tokenize). */
static void _skip_attributes(Compiler c) {
  if (!c.shallow) return;
  loop {
    Var definition;
    if (_attribute(c)) continue;
    if (c.peek(0) != <ident> ||
        !c.object_macros.try_get(c.token.text, definition) ||
        definition != %())
      return;
    c.next();
  }
}

/* A template may spell a tag through a Name hole or compile-time Lisp,
   which publishes it; a literal tag there is a template local. */
static List _tag_name(Compiler c) {
  List slot = c.try_parse_macro_slot(<name>);
  return slot ? %($slot) : c.parse_optional_identifier();
}

/* An aggregate definition takes the prefix its declaration key carries, so
   the tag, its member keys, and the pointee spellings recorded for it agree
   in the shallow collection an importing unit reads and in the full parse. */
static List _scoped_aggregate_name(Compiler c, Symbol tag, List name) {
  // A template's tag slot supplies its exact spelling where it expands.
  if (name.car() is not <string>) return name;
  String spelling = name.car();
  if (c.peek(0) == <"{">)
    return %(${c.declared_spelling(c.private_prefix(NULL), spelling)});
  return %(${_type_reference(c, tag, spelling)});
}

/* Publishes an aggregate whose tokens start at `first`. A constructed
   aggregate passes the current token, so its attributes are in its form. An
   enum with a layout attribute can be narrower than int, so it has no int
   layout. */
static List _publish_aggregate_type(
  Compiler c, Symbol tag, Var name, List members, Token first) {
  int layout = _layout_attribute_since(c, first);
  int packed = _attribute_since(c, first, c.packed_marks);
  if (tag == <struct> && packed && c.source_private >= 0)
    $fail.parse_attribute_packed(c, first);
  List type = %($tag $name);
  List body = tag == <enum> ? members : %(fields @members);
  if (name is <list> && name.car() == <binding>)
    c.sym.bind_identity(%($tag), name, %($tag $body));
  else
    c.sym.declare_resolved(
      NULL, type, tag == <enum> ? %(enum) : %($tag $body));
  if (tag != <enum>) {
    c.sym.declare_field_order(type, members);
    if (layout) c.sym.set(%(@type "layout-attribute"), %(unknown));
    // Meta code lays out only the records x2c units define.
    if (c.source_private >= 0 && !c.filename.endswith(".h"))
      c.sym.set(%(@type "x2c-record"), %(x2c));
  }
  else {
    c.sym.set(%(@type "enumerators"), %(@type $members).type_from_ast());
    if (!layout && _enum_fits_int(type, members)) {
      c.sym.set(%(@type "int-range"), %(int));
      _record_enum_values(c, members);
    }
  }
  return %($tag $name $body);
}

module int _layout_attribute_since(Compiler c, Token first) =>
  _attribute_since(c, first, c.layout_marks);

/* Reports a layout attribute between `first` and the current token. Tokens
   outside this unit's input, such as a constructed form's, have no marks. */
static int _attribute_since(Compiler c, Token first, Array marks) {
  Token base = c.tokenizer.tokens, end = base + c.tokenizer.tokens.len();
  if (first < base || c.token >= end) return 0;
  // Marks ascend, so the ones before `first` are a prefix.
  int before = 0, count = marks.len();
  for (int high = count; before < high;) {
    int middle = (before + high) / 2;
    if ((long) marks[middle] < first - base) before = middle + 1;
    else high = middle;
  }
  return before % 2 ||
         (before < count && (long) marks[before] < c.token - base);
}

// fields

/** Parses aggregate fields in source order up to the current closing brace.
    Returns a flat field `List`, publishes delegate-field metadata, and leaves
    the closing brace unconsumed. An alias among the fields ends at the brace.
*/
List Compiler.parse_fields(Compiler c, List context) {
  Array fields = [];
  Map aliases = c.enter_alias_body();
  defer c.leave_alias_body(aliases);
  loop {
    _push_items(fields, _field_item(c, context));
    if (c.peek(0) == <"}">) return fields.list_free();
  }
}

static List _field_item(Compiler c, List context) {
  if (c.alias_form_starts())
    return c.parse_alias_member(<field>, context);
  if (c.test(<delegate>)) return _field(c, context, 1);
  return c.parse_field(context);
}

/** Parses one field for aggregate type `context` and returns its AST.
    Ordinary fields publish their binding in the aggregate's field scope and
    consume their terminating semicolon; macro forms follow their own syntax.
*/
List Compiler.parse_field(Compiler c, List context) {
  if (c.test_static_assert()) return c.parse_static_assert();
  List slot = c.try_parse_macro_slot(<field>);
  if (slot) return slot;
  List macro = _member_macro(c, context, <field>);
  if (macro) return macro;
  return _field(c, context, 0);
}

/* A macro invocation may stand for an aggregate member. It expands with
   the aggregate as the current aggregate type. */
static List _member_macro(Compiler c, List context, Symbol position) {
  if (c.peek(0) != <$> && c.peek(0) != <ident>) return NULL;
  $let(c.aggregate_type, context)
    return c.try_parse_macro_target_at(position);
}

static List _field(Compiler c, List context, int delegated) {
  List rows = _field_row(c, context);
  if (delegated) _declare_delegates(c, context, rows);
  c.expect(<;>);
  match (rows) case %(?only): return only;
  return %(seq @rows);
}

// Each declarator of a delegate field must name the field.
static void _declare_delegates(Compiler c, List context, List rows) {
  foreach (List declaration in rows)
    match (declaration)
      case %(declare ? (bindings *declarators)): {
        if (!declarators)
          $fail.parse_delegate_name(c, c.token);
        foreach (List declarator in declarators)
          match (declarator)
            case %(bind ?binding ?): _declare_delegate(c, context, binding);
      }
}

static void _declare_delegate(Compiler c, List context, Var binding) {
  String name = Ast.binding_spelling(binding);
  if (!name)
    $fail.parse_delegate_name(c, c.token);
  if (!c.macro_holes) c.sym.mark_field(context, <delegate>, name);
}

static List _field_row(Compiler c, List context) {
  Array declarations = [];
  loop {
    declarations.push(_field_group(c, context));
    if (!_group_comma(c)) break;
    c.next();
  }
  return declarations.list_free();
}

static List _field_group(Compiler c, List context) {
  List storage = _storage_class(c);
  if (<auto> in storage && !c.macro_holes && !c.shallow)
    $fail.parse_auto_storage(c, c.token);
  List (type, binding_type) = _declaration_types(c, storage);
  List binds = _declarator_list(c, binding_type, context, 1);
  return _finish_declaration(c, <declare>, type, binds, 0);
}

// named types

/** Captures a name followed by an ordinary complete type and semicolon.
    The reserved typedef identity permits fields to refer to their enclosing
    named type before its pointer or value representation is complete.
*/
List Compiler.parse_named_type(Compiler c) {
  List slot = c.try_parse_macro_slot(<named-type>);
  if (slot) return slot;
  Token start = c.token;
  String name = c.declared_spelling(c.private_prefix(NULL), c.token.text);
  c.expect(<ident>);
  List key = %($name);
  if (!c.sym.get_exact(key)) c.sym.define(key, %(typedef $name));
  if (c.test(<;>)) return %(named-type $name ());
  List qualifiers = _type_qualifiers(c);
  List base = qualifiers.append(
    _record_follows(c) ? _record_body(c, name, start) : _type_specifier(c));
  Type type = _declare_named_type(c, key, base, start);
  return %(named-type $name $type);
}

/* A named type may define its record in place, with or without `struct`
   or `union` before the brace. */
static int _record_follows(Compiler c) =>
  c.peek(0) == <"{"> ||
  ((c.peek(0) == <struct> || c.peek(0) == <union>) && c.peek(1) == <"{">);

static List _record_body(Compiler c, String name, Token start) {
  Symbol tag = c.peek(0) == <union> ? <union> : <struct>;
  if (c.peek(0) != <"{">) c.next();
  c.expect(<"{">);
  List fields = c.peek(0) == <"}">
              ? NULL : c.parse_fields(%($tag $name));
  c.expect(<"}">);
  return c.macro_holes ? %($tag $name (fields @fields))
                       : _publish_aggregate_type(c, tag, name, fields, start);
}

/* Completes a named type from the abstract declarator after its base. The
   type keeps an aggregate's body in place of its tag. */
static Type _declare_named_type(
  Compiler c, List key, List base, Token start) {
  List method = NULL;
  Token first = NULL, after = NULL;
  List declarator = _declarator(c, base, NULL, method, first, after);
  List modifiers = NULL;
  match (declarator) {
    case %(bind () ?captured): modifiers = captured;
    default: $fail.parse_named_type_abstract(c, start);
  }
  c.expect(<;>);
  Type type = %(declare $base (bindings (bind () $modifiers)))
                .type_from_ast();
  if (!c.macro_holes) c.sym.declare_resolved(%(typedef), key, type);
  Type specifier = base.type().base_type();
  if (specifier.is_aggregate_tag_body())
    type = type.list()[:type.len() - type.base_type().len()]
      .append(specifier);
  return type;
}

// enumerations

/** Parses comma-separated enumerators up to the current closing brace.
    Returns their flat source-order `List` and leaves the brace unconsumed.
    An alias among them needs no comma, and its name ends at the brace.
*/
List Compiler.parse_enumerators(Compiler c, List context) {
  Array enumerators = [];
  Map aliases = c.enter_alias_body();
  defer c.leave_alias_body(aliases);
  while (c.peek(0) != <"}">) {
    if (c.alias_form_starts()) {
      _push_items(enumerators, c.parse_alias_member(<enumerator>, context));
      continue;
    }
    if (c.shallow && c.macro_starts_target_at(<enumerator>))
      c.skip_macro_invocation();
    else _push_items(enumerators, c.parse_enumerator(context));
    if (c.peek(0) == <"}">) break;
    c.expect(<,>);
  }
  return enumerators.list_free();
}

/** Parses one enumerator for enum type `context` and returns its AST.
    Outside macro-template parsing, its binding is published immediately so
    later initializers and enumerators can resolve it.
*/
List Compiler.parse_enumerator(Compiler c, Type context) {
  List slot = c.try_parse_macro_slot(<enumerator>);
  if (slot) return slot;
  List macro = _member_macro(c, context, <enumerator>);
  if (macro) return macro;
  if (c.macro_holes) return _template_enumerator(c, context);
  if (c.peek(0) != <ident>)
    $fail.parse_enum_name(c, c.token);
  String spelling = c.token.text;
  Token origin = c.token;
  c.next();
  List binding = %($spelling), syntax = binding;
  if (c.test(<=>)) {
    List value = c.parse_conditional();
    syntax = %(op = $binding $value);
  }
  return _publish_enumerator(c, syntax, context, origin);
}

/* A template's enumerator is named by a hole, a Lisp slot, or a name each
   expansion introduces. */
static List _template_enumerator(Compiler c, Type context) {
  List name = _enumerator_name(c, context);
  List target = %(bind $name ());
  if (c.test(<=>)) return %(op = $target ${c.parse_conditional()});
  return target;
}

static List _enumerator_name(Compiler c, Type context) {
  switch (c.peek(0)) {
    case <"$(">: case <$>: return c.try_parse_macro_slot(<name>);
    case <ident>: {
      String spelling = c.token.text;
      c.next();
      List name = c.macro_introduced_name(spelling);
      c.sym.bind_identity(NULL, name, context.declaration_ast(name));
      return name;
    }
    default:
      $fail.parse_enum_name(c, c.token);
  }
}

module List _publish_enumerator(
  Compiler c, List input, Type context, Token origin) {
  input = c.evaluate_macro_slot(input);
  List target = input, initializer = NULL;
  match (input)
    case %(op = ?captured_target ?value): {
      target = captured_target;
      initializer = c.resolve_expression(value, c.token);
    }
  target = c.evaluate_macro_slot(target);
  Var name = target;
  match (target) case %(bind ?binding_name ?): name = binding_name;
  name = c.evaluate_macro_slot(name);
  String exact = _syntax_exact_name(name);
  List binding = exact ? NULL : name is <list> ? name.list() : NULL;
  String spelling = exact ? exact : Ast.binding_spelling(binding);
  if (!spelling)
    $fail.parse_syntax_position(c, origin);
  List key = %($spelling);
  if (exact) key = c.sym.declared_key(NULL, key, context);
  Symbol prior = c.sym.enumerator_owner(key);
  if (prior && binding) {
    List existing = c.sym.lookup(key, NULL);
    if (existing && existing == binding) return input;
  }
  if (prior)
    $fail.parse_enum_bound(c, origin, spelling);
  if (exact) binding = c.sym.declare(NULL, %($exact), context);
  else
    c.sym.bind_identity(NULL, binding, context.declaration_ast(binding));
  c.sym.declare_enumerator(key, <enumerator>);
  return initializer ? %(op = $binding $initializer) : binding;
}

/* Whether every enumerator of enum `type` fits in int, the width C gives an
   enum whose values do: each initializer has an integer type no wider than
   int, or is the enum itself. C requires an implicit value, the previous
   one plus one, to fit in int as well. */
static int _enum_fits_int(List type, List members) {
  foreach (List member in members) {
    match (member) {
      case %(binding *): continue;
      case %(op = ? (expr ?(Type value) *)):
        if (_fits_int(value, type)) continue;
    }
    return 0;
  }
  return 1;
}

static int _fits_int(Type value, List type) {
  if (value == type) return 1;
  X2CVarNumericInfo info;
  return Var.numeric_info(value.scalar_tag(), info) && !info.floating &&
         (info.bits < 32 || (info.bits == 32 && !info.unsigned_value));
}

/* Records how meta code computes each enumerator's value: its initializer,
   or the previous enumerator plus one, or zero for the first. */
static void _record_enum_values(Compiler c, List members) {
  List rule = %(first);
  foreach (List member in members) {
    List binding = member;
    match (member) case %(op = ?target ?value): {
      binding = target;
      rule = %(value $value);
    }
    c.set_fact(%(enum-value $binding), rule);
    rule = %(next $binding);
  }
}

// constructed types

module List _finish_type(Compiler c, List type) {
  List base = type;
  Array storage = [];
  while (base.car() is <symbol> &&
         (base.car().symbol().is_type_qualifier() ||
          base.car().symbol().is_storage_class())) {
    storage.push(base.car());
    base = base.cdr();
  }
  if (base != type &&
      (base.car() == <struct> || base.car() == <union> ||
       base.car() == <enum>))
    return c.sym.local_type(
      %(@{storage.list_free()} @{_finish_type(c, base)}));
  storage.free();
  Var whole = _finish_type_spec(c, type);
  // Binding an already constructed aggregate can preserve its whole form.
  if (whole != type || type.car() == <struct> ||
      type.car() == <union> || type.car() == <enum>) {
    List constructed = whole;
    Type finished = constructed.car() == <seq>
                  ? constructed.cdr() : constructed;
    return c.sym.local_type(finished);
  }
  Array bound = [];
  foreach (Var spec in type) {
    Var finished = _finish_type_spec(c, spec);
    if (finished is <list> && !finished.is_nil() &&
        finished.car() == <seq>)
      foreach (Var item in finished.list().cdr()) bound.push(item);
    else bound.push(finished);
  }
  Type resolved = bound.list_free();
  return c.sym.local_type(resolved);
}

static Var _finish_type_spec(Compiler c, Var spec) {
  int slot = spec is <list> && !spec.is_nil() &&
             spec.car() == <macro-slot>;
  spec = c.evaluate_macro_slot(spec);
  if (slot && spec is <list>) {
    Type type = spec.type().canonicalize();
    return %(seq @type);
  }
  if (spec is not <list>) return spec;
  match (spec) {
    case %((!or ?tag struct union) ?name):
      return %($tag ${_finish_tag_name(c, name)});
    case %((!or ?tag struct union) ?name (fields *members)):
      return _finish_aggregate_type(c, tag, name, members);
    case %(enum ?name):
      return %(enum ${_finish_tag_name(c, name)});
    case %(enum ?name (*members)):
      return _finish_aggregate_type(c, <enum>, name, members);
    // Semantic types name an expanded template typedef by its spelling.
    case %(binding ? ?(String name)): return name;
  }
  return spec;
}

static Var _finish_tag_name(Compiler c, Var name) {
  name = c.evaluate_macro_slot(name);
  String exact = _syntax_exact_name(name);
  return exact ? exact : name;
}

static List _finish_aggregate_type(
  Compiler c, Symbol tag, Var name, List members) {
  name = _finish_tag_name(c, name);
  // Each constructed anonymous body defines a distinct type.
  match (name) case %(gensym ? ?): name = c.gensym().car();
  if (tag != <enum>) name = c.aggregate_name(tag, name, 1);
  List type = %($tag $name);
  Array bound = [];
  Symbol position = tag == <enum> ? <enumerator> : <field>;
  $let(c.aggregate_type, type) {
    foreach (List member in members)
      foreach (Var row in c.evaluate_macro_rows(member))
        _push_items(bound, c.bind_syntax(row, position, c.return_type));
  }
  return _publish_aggregate_type(c, tag, name, bound.list_free(), c.token);
}
