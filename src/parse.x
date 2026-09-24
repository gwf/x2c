/*  parse.x -- x2c recursive-descent parser core

    Copyright (c) 2025 Gary William Flake.

    Converts token streams into AST nodes for declarations and top-level
    constructs. Expression, statement, and literal parsing are in their
    own modules and are invoked via the Compiler.* entry points.

    Declaration parsing recognizes initializers and finds the function
    body. Type resolution and lexical scopes use the Compiler's current
    symbol environment; failures retain positioned diagnostic context.
  */

#pragma once
$(import "../lib/private-keywords.xmacro")
#include "compiler.x"
#include "type.x"
#pragma private
#include "statements.x"
#include "expressions.x"
#include "literals.x"
#include "collect.x"
#include "macros.x"
#include "protocol.x"

/** Returns the folded package-member spelling at the current token, or NULL.
    The token must be an unshadowed imported alias followed by `.` and an
    identifier. This lookahead does not consume tokens.
*/
String Compiler.package_alias_spelling(Compiler c) {
  if (!c.package_aliases.len()) return NULL;
  if (c.peek(0) != <ident> || c.peek(1) != <.>) return NULL;
  String alias = c.token.text;
  Var package = c.package_aliases[alias];
  if (package is void || c.sym.get_exact(%($alias))) return NULL;
  Token member = c.skip_trivia_from(c.skip_trivia_from(c.token + 1) + 1);
  return member.text.is_identifier()
       ? %"${package}__${member.text}" : NULL;
}

/* Consume `alias .` and return the folded spelling. The member token stays
   current, so every caller continues down its identifier path. */
static String _package_alias_member(Compiler c) {
  String spelling = c.package_alias_spelling();
  if (!spelling) return NULL;
  String package = c.package_aliases[c.token.text];
  c.next();
  c.next();
  if (!c.sym.get_exact(%($spelling)))
    c.report_error(
      <parse>,
      %"package '$package' has no public name '${c.token.text}'",
      c.token, NULL);
  return spelling;
}

/* Accept one of two forms of dotted identifiers: TYPE.IDENTIFIER or
   IDENTIFIER.TYPE. Preserve the explicit owner/member pair for declarations
   whose mangled spellings alone would be ambiguous. */
static List _complex_identifier(
  Compiler c, List *method_identity) {
  if (method_identity) *method_identity = NULL;
  String ident = _package_alias_member(c), Symbol toktype = c.token.type;
  /* Only a declarator asks for the method identity, and there the name is
     being defined. A `with` spelling must not fold, because the declaration
     belongs to this unit and shadows the binding. */
  if (!ident && toktype == <ident> && !method_identity)
    ident = c.package_member_spelling(c.token.text);
  if (!ident) ident = c.token.text;
  Type idtype = c.sym.get(%( $ident ));
  c.next();
  if (toktype.is_builtin_type() || toktype.is_type_modifier() ||
      (toktype == <ident> && idtype.is_typedef())) {
    if (c.test(<.>)) {
      // a weaker test that accepts anything that looks like an identifier
      if (c.token.text.is_identifier()) {
        String owner = ident, member = c.token.text;
        ident = %"${owner}_$member";
        if (method_identity) *method_identity = %($owner $member);
        /* `Type.member` where an imported package declared that method on
           one of its own header's types: the header spells the type, the
           package spells the method. A declarator never folds. */
        if (!method_identity && !c.sym.get_exact(%($ident))) {
          String imported = c.imported_spelling(ident);
          if (imported) ident = imported;
        }
        c.next();
        return %( $ident );
      }
      else c.report_error(
        <parse>, "expected method name after dot",
        c.token,
        %( "typedef:" $ident "token:" ${c.token.text}  ));
    }
  }
  return %($ident);
}

/** Parses the current identifier or dotted owner/member as a one-item name.
    Package aliases and imported method spellings are folded through the
    current `Sym`, and all accepted tokens are consumed.
*/
List Compiler.parse_complex_identifier(Compiler compiler) =>
  _complex_identifier(compiler, NULL);

/** Consumes one `ident` token and returns its spelling as a one-item `List`.
*/
List Compiler.parse_basic_identifier(Compiler compiler) {
  String ident = compiler.token.text;
  compiler.expect(<ident>);
  return %($ident);
}

/** Consumes and returns the current identifier, or NULL without consuming. */
List Compiler.parse_optional_identifier(Compiler compiler) {
  if (compiler.peek(0) != <ident>) return NULL;
  String ident = compiler.token.text;
  compiler.expect(<ident>);
  return %($ident);
}

static String _syntax_exact_name(Var value) {
  if (value is <string>) return value;
  if (value is not <list>) return NULL;
  match (value) {
    case %(?(String exact)): return exact;
    case %("x2c.ident" ?(String exact)): return exact;
  }
  return NULL;
}

static List _method_self_signature(Compiler compiler, List binding) {
  Var stored;
  return compiler.semantic_binding_facts().try_get(
    %(self $binding), &stored) ? stored : NULL;
}

static List _method_identity(Compiler compiler, List binding) {
  Var stored;
  return compiler.semantic_binding_facts().try_get(
    %(method $binding), &stored) ? stored : NULL;
}

static Type _self_owner_type(Compiler compiler, List method) {
  String source = method.car();
  Type declared = compiler.sym.get(%($source));
  if (declared.is_typedef())
    return %(${_package_type_reference(compiler, 0, source)});
  Symbol builtin = Atom.intern(source);
  return builtin.is_builtin_type() ? %($builtin) : NULL;
}

static void _lower_parameter_self(Compiler compiler, Var replacement) {
  Map symbols = compiler.params.symbols;
  if (!symbols) return;
  foreach (Var (key, value), symbols) {
    List original = value;
    List lowered = original.search_replace(<self>, replacement);
    if (lowered != original) {
      symbols[key] = lowered;
      Var binding;
      if (compiler.params.bindings.try_get(key, &binding))
        compiler.semantic_binding_facts()[
          %(type $binding)
        ] = lowered;
    }
  }
}

/* Keep Self only in method metadata. The binding and AST receive the
   declaring owner, so direct calls and generated C retain the existing
   function signature. */
static List _lower_self_declaration(Compiler compiler, List declaration) {
  List items = declaration.caddr().cdr();
  if (!items || items.cdr()) return declaration;
  List target = items.car();
  if (target.car() == <op>) target = target.caddr();
  List binding = target.cadr(), method = _method_identity(compiler, binding);
  if (!method) return declaration;
  Type owner = _self_owner_type(compiler, method);
  if (!owner) return declaration;
  List lowered = declaration.search_replace(<self>, owner.car());
  if (lowered == declaration) {
    compiler.semantic_binding_facts().del(%(self $binding));
    return declaration;
  }
  Type signature = declaration.type_from_ast();
  if (!signature.is_function()) return declaration;
  String spelling = binding_identity_spelling(binding);
  Type relative = signature.declared();
  Type concrete = lowered.type_from_ast().declared();
  compiler.semantic_binding_facts()[%(self $binding)] = relative;
  compiler.sym.set(%($spelling), concrete);
  compiler.sym.set(%(self $spelling), relative);
  _lower_parameter_self(compiler, owner.car());
  return lowered;
}

/* An expanded alias may contribute pointer, array, or function modifiers.
   Keep parsed modifiers (and parameter bindings) intact and append only the
   alias's declarators. Storage still belongs on the declaration's base. */
static List _declaration_base(Type t, List *modifiers) {
  // Source specifier text, such as `("_Noreturn")`, follows the storage.
  Array storage = [], text = [], typed = [];
  defer { storage.free(); text.free(); typed.free(); }
  foreach (Var item, t)
    if (item is <list> && car(item) is <string>) text.push(item);
    else typed.push(item);
  List (base, mods) = typed.list().type().declared().declaration_parts();
  *modifiers = mods;
  if (!mods) return t;
  foreach (Var item, t)
    if (item is <symbol> &&
        (Symbol.is_storage_class(item) || Symbol.is_inline(item)))
      storage.push(item);
  return %( @{storage.list()} @{text.list()} @base );
}

static List _append_declarator_modifiers(List declarator, List modifiers) {
  if (!modifiers) return declarator;
  match (declarator) {
    case %(bind ?binding ?mods):
      return %(bind $binding (@{mods} @modifiers));
    case %(op = ?binding ?initializer):
      return %(op = ${_append_declarator_modifiers(binding, modifiers)}
               $initializer);
  }
  return declarator;
}

static List _finish_declaration(
  Compiler compiler, Symbol tag, List base, List declarators,
  int preserved_self) {
  List modifiers = NULL;
  base = _declaration_base(base, &modifiers);
  if (modifiers) {
    Array bound = [];
    foreach (List declarator, declarators)
      bound.push(_append_declarator_modifiers(declarator, modifiers));
    declarators = bound.list_free();
  }
  List declaration = %($tag $base (bindings @declarators));
  return tag == <declare> && !preserved_self
    ? _lower_self_declaration(compiler, declaration)
    : declaration;
}

// type parsing

/* A GNU attribute or an attribute macro is kept as its source text. */
static int _attribute_starts(Compiler c) {
  Var definition;
  return c.peek(0) == <ident> && c.peek(1) == <(> &&
         (c.token.text == "__attribute__" ||
          (c.object_macros.try_get(c.token.text, &definition) &&
           definition.equal(<annotation>)));
}

static String _attribute(Compiler c) {
  if (!_attribute_starts(c)) return NULL;
  Token first = c.token, last = c.skip_trivia_from(first + 1).group_close();
  c.token = last.after_group();
  return String.new_len(c.text + first.pos, last.pos + last.len - first.pos);
}

/* C places an aggregate's own attributes after its keyword and after its
   closing brace, written out or through a macro whose body is attributes.
   Collection skips them: attribute text is no part of a collected type, and
   the layout marks hold any layout they change (see Compiler.tokenize). */
static void _skip_aggregate_attributes(Compiler c) {
  if (!c.shallow) return;
  loop {
    Var definition;
    if (_attribute(c)) continue;
    if (c.peek(0) != <ident> ||
        !c.object_macros.try_get(c.token.text, &definition) ||
        !definition.equal(%()))
      return;
    c.next();
  }
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

/* Source is read before preprocessing, so a macro whose body is declaration
   specifiers and attributes, such as an export annotation, still sits in a
   declaration. A specifier position of `rank`, 0 for storage classes and
   `inline`, 1 for qualifiers, and 2 for builtin types, leaves a macro with
   words of a later rank to that position; otherwise it consumes the macro
   and takes all of its words into `words`, so `int LOCAL f(void)` keeps the
   `static` of `#define LOCAL static`. */
static int _prefix_macro_words(Compiler c, int rank, Array words) {
  Var definition;
  if (c.peek(0) != <ident>) return 0;
  if (!c.object_macros.try_get(c.token.text, &definition)) {
    if (rank || !_unseen_prefix(c)) return 0;
    c.next();
    return 1;
  }
  if (definition.equal(<wrapper>) && c.peek(1) == <(>) {
    /* `EXPORT(const char *) f(void);` wraps the type. The name and its
       parentheses contribute nothing; the closing one is hidden so the
       type and declarator between them parse as written. */
    Token close = c.skip_trivia_from(c.token + 1).group_close();
    if (close.type != <eof>) close.type = <comment>;
    c.next();
    c.next();
    return 1;
  }
  if (definition is not <list>) return 0;
  foreach (Symbol word, definition)
    if ((word.is_type_qualifier() ? 1 : word.is_builtin_type() * 2) > rank)
      return 0;
  foreach (Symbol word, definition) words.push(word);
  c.next();
  return 1;
}

/* Declaration specifiers before the qualifiers and type: storage classes
   and `inline` in source order, then `_Noreturn` and attributes as source
   text. The storage words lead, where C places them and where a declared
   type's storage is read. One storage class is allowed, except that
   `threaded` pairs with another one the way C's thread-local specifier
   pairs with `static` or `extern`. A second one stops the run, so
   `static extern` is diagnosed instead of passed to C. */
static List _storage_class(Compiler c) {
  Array storage = [], text = [], int seen_threaded = 0, seen_ordinary = 0;
  defer { storage.free(); text.free(); }
  loop {
    Symbol symbol = c.peek(0);
    String attribute = _attribute(c);
    if (attribute) text.push(%($attribute));
    else if (symbol == <ident> && c.token.text == "_Noreturn") {
      text.push(%("_Noreturn"));
      c.next();
    }
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

static List _type_completion_keywords(void) => %(
  "void" "char" "short" "int" "long" "float" "double"
  "signed" "unsigned" "struct" "union" "enum"
  "const" "restrict" "volatile"
);

static List _type_qualifiers(Compiler c) {
  Array quals = $auto([]);
  loop {
    c.__complete_here(<type>, _type_completion_keywords());
    Symbol symbol = c.peek(0);
    if (symbol.is_type_qualifier()) {
      quals.push(symbol);
      c.next();
    }
    else if (!_prefix_macro_words(c, 1, quals)) break;
  }
  return quals;
}

static int _is_scalar_specifier(Symbol symbol) {
  switch (symbol)
    case <signed>: case <unsigned>: case <short>: case <long>:
    case <char>: case <int>: case <float>: case <double>: case <void>:
      return 1;
  return 0;
}

static List _primitive_type(Compiler compiler) {
  Token start = compiler.token;
  Array specs = [];
  while (_is_scalar_specifier(compiler.peek(0))) {
    specs.push(compiler.peek(0));
    compiler.next();
  }
  Type source = specs.list_free(), scalar = source.scalar();
  if (scalar) return scalar;
  // The preprocessed shallow pass only contributes declarations. The full
  // pass over the original source reports source-level type diagnostics.
  if (compiler.shallow) return source;
  compiler.report_error(
    <type>, source ? %"invalid scalar type ${source}"
                   : "expected scalar type",
    start, NULL
  );
}

/* Package files spell their own file-scope type names bare. A bare-key
   miss with a prefixed hit re-spells the reference; ASTs carry raw
   strings and emit literally. */
static String _package_type_reference(
  Compiler compiler, Symbol tag, String name) {
  String prefixed = compiler.package_spelling(name);
  if (prefixed == name) return name;
  List bare = tag ? %($tag $name) : %($name);
  if (compiler.sym.get_exact(bare)) return name;
  List hit = tag ? %($tag $prefixed) : %($prefixed);
  return compiler.sym.get_exact(hit) ? prefixed : name;
}

/* An aggregate definition takes the prefix its declaration key carries, so
   the tag, its member keys, and the pointee spellings recorded for it agree
   in the shallow collection an importing unit reads and in the full parse. */
static List _package_aggregate_name(Compiler compiler, Symbol tag, List name) {
  // A template's tag slot supplies its exact spelling where it expands.
  if (name.car() is not <string>) return name;
  String spelling = name.car();
  if (compiler.peek(0) == <"{">)
    return %(${compiler.package_spelling(spelling)});
  return %(${_package_type_reference(compiler, tag, spelling)});
}

static List _typedef_name(Compiler compiler) {
  String name = _package_alias_member(compiler);
  if (!name) name = compiler.package_member_spelling(compiler.token.text);
  if (!name) name = compiler.token.text;
  compiler.next();
  if (compiler.package) name = _package_type_reference(compiler, 0, name);
  return %($name);
}

static List _field_declaration_row(Compiler compiler, List context) {
  Array declarations = [];
  loop {
    declarations.push(_decl_context_group(compiler, context));
    if (!_test_declaration_group_comma(compiler)) break;
    compiler.next();
  }
  return declarations.list_free();
}

static List _field(Compiler compiler, List context, int delegated) {
  List rows = _field_declaration_row(compiler, context);
  if (delegated && compiler.parsing_source_syntax()) {
    compiler.expect(<;>);
    return %(delegate @rows);
  }
  if (delegated) {
    foreach (List declaration, rows) match (declaration) {
      case %(declare ? (bindings *declarators)): {
        if (!declarators)
          compiler.report_error(
            <parse>, "delegate field requires a name", compiler.token, NULL);
        foreach (List declarator, declarators) match (declarator) {
          case %(bind ?binding ?): {
            String name = binding_identity_spelling(binding);
            if (!name)
              compiler.report_error(
                <parse>, "delegate field requires a name",
                compiler.token, NULL);
            if (!compiler.macro_holes)
              compiler.sym.declare_delegate_field(context, name);
          }
        }
      }
    }
  }
  compiler.expect(<;>);
  match (rows) case %(?only): return only;
  return %(seq @rows);
}

/* Whether every enumerator of enum `type` fits in int, the width C gives an
   enum whose values do: each initializer has an integer type no wider than
   int, or is the enum itself. C requires an implicit value, the previous
   one plus one, to fit in int as well. */
static int _enum_fits_int(List type, List members) {
  foreach (List member, members) {
    match (member) {
      case %(binding *): continue;
      case %(op = ? (expr ?(Type value) *)): {
        if (value.equal(type)) continue;
        X2CVarNumericInfo info;
        if (Var.numeric_info(value.scalar_tag(), &info) && !info.floating &&
            (info.bits < 32 || (info.bits == 32 && !info.unsigned_value)))
          continue;
      }
    }
    return 0;
  }
  return 1;
}

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

static int _layout_attribute_since(Compiler c, Token first) =>
  _attribute_since(c, first, c.layout_marks);

/* Publishes an aggregate whose tokens start at `first`. A constructed
   aggregate passes the current token, so its attributes are in its form. An
   enum with a layout attribute can be narrower than int, so it has no int
   layout. */
static List _publish_aggregate_type(
  Compiler compiler, Symbol tag, Var name, List members, Token first) {
  int layout = _layout_attribute_since(compiler, first);
  int packed = _attribute_since(compiler, first, compiler.packed_marks);
  if (tag == <struct> && packed && compiler.source_private >= 0)
    compiler.report_error(
      <parse>, "packed attributes are unsupported", first, NULL);
  List type = %($tag $name);
  List body = tag == <enum> ? members : %(fields @members);
  if (name is <list> && name.car() == <binding>)
    compiler.sym.bind_identity(%($tag), name, %($tag $body));
  else
    compiler.sym.declare(NULL, type, tag == <enum> ? %(enum) : %($tag $body));
  if (tag != <enum>) {
    compiler.sym.declare_field_order(type, members);
    if (layout) compiler.sym.set(%(@type "layout-attribute"), %(unknown));
    // Meta code lays out only the records x2c units define.
    if (compiler.source_private >= 0 && !compiler.filename.endswith(".h"))
      compiler.sym.set(%(@type "x2c-record"), %(x2c));
  }
  else if (!layout && _enum_fits_int(type, members))
    compiler.sym.set(%(@type "int-range"), %(int));
  return %($tag $name $body);
}

/** Reports whether the current identifier starts a C static assertion. */
int Compiler.test_static_assert(Compiler compiler) =>
  compiler.peek(0) == <ident> &&
  compiler.token.text == "_Static_assert";

/** Parses a C assertion declaration; native C owns constant-expression
    checks. */
List Compiler.parse_static_assert(Compiler compiler) {
  if (compiler.shallow) {
    compiler._skip_shallow_expression(0);
    compiler.expect(<;>);
    return %(c-assert);
  }
  compiler.next();
  compiler.expect(<(>);
  List condition = compiler.parse_assignment();
  compiler.expect(<,>);
  List message = compiler.parse_assignment();
  compiler.expect(<)>);
  compiler.expect(<;>);
  return %(c-assert $condition $message);
}

/** Parses one field for aggregate type `context` and returns its AST.
    Ordinary fields publish their binding in the aggregate's field scope and
    consume their terminating semicolon; macro forms follow their own syntax.
*/
List Compiler.parse_field(Compiler compiler, List context) {
  if (compiler.test_static_assert()) return compiler.parse_static_assert();
  List slot = compiler.try_parse_macro_slot(<field>);
  if (slot) return slot;
  List macro = NULL;
  if (compiler.peek(0) == <$> || compiler.peek(0) == <ident>) {
    $let(compiler.aggregate_type, context) {
      macro = compiler.try_parse_macro_target_at(AST_FIELD);
    }
  }
  if (macro) return macro;
  return _field(compiler, context, 0);
}

/** Parses aggregate fields in source order up to the current closing brace.
    Returns a flat field `List`, publishes delegate-field metadata, and leaves
    the closing brace unconsumed.
*/
List Compiler.parse_fields(Compiler c, List context) {
  Array fields = [];
  loop {
    int delegated = c.test(<delegate>);
    List field = delegated
      ? _field(c, context, 1) : c.parse_field(context);
    match (field) {
      case %(seq *rows):
        foreach (Var row, rows) fields.push(row);
      default: fields.push(field);
    }
    if (c.peek(0) == <"}">) return fields.list_free();
  }
}

/* A template may spell a tag through a Name hole or compile-time Lisp,
   which publishes it; a literal tag there is a template local. */
static List _tag_name(Compiler c) {
  List slot = c.try_parse_macro_slot(<name>);
  return slot ? %($slot) : c.parse_optional_identifier();
}

static List _struct_or_union(Compiler c) {
  Token first = c.token;
  Symbol tag = c.peek(0);
  c.next();
  _skip_aggregate_attributes(c);
  List name = _tag_name(c);
  if (name && c.package) name = _package_aggregate_name(c, tag, name);
  List usedname = name ? name : c.gensym();
  usedname = %(${c.aggregate_name(tag, usedname.car(),
    c.peek(0) == <"{"> || c.peek(0) == <;>)});
  List type = cons(tag, usedname), fields = NULL;
  if (c.test(<"{">)) {
    fields = c.parse_fields(type);
    c.expect(<"}">);
    _skip_aggregate_attributes(c);
    if (!c.macro_holes)
      return _publish_aggregate_type(c, tag, usedname.car(), fields, first);
    fields = cons(<fields>, fields);
  }
  return fields ? type.append(%($fields)): type;
}

static List _publish_enumerator(
  Compiler compiler, List input, Type context, Token origin) {
  input = compiler.evaluate_macro_slot(input);
  List target = input, initializer = NULL;
  match (input)
    case %(op = ?captured_target ?value): {
      target = captured_target;
      initializer = compiler.resolve_expression(value, compiler.token);
    }
  target = compiler.evaluate_macro_slot(target);
  Var name = target;
  match (target) case %(bind ?binding_name ?): name = binding_name;
  name = compiler.evaluate_macro_slot(name);
  String exact = _syntax_exact_name(name);
  List binding = exact ? NULL : name is <list> ? name.list() : NULL;
  String spelling = exact ? exact : binding_identity_spelling(binding);
  if (!spelling)
    compiler.report_error(
      <parse>, "syntax cannot be constructed at this position",
      origin, NULL);
  List key = %($spelling);
  Symbol prior = compiler.sym.enumerator_owner(key);
  if (prior && binding) {
    List existing = compiler.sym.lookup(key, NULL);
    if (existing && existing.equal(binding)) return input;
  }
  if (prior)
    compiler.report_error(
      <parse>,
      %"enumerator '$spelling' is already bound in this scope",
      origin, %("prior binding: '$spelling'"));
  if (exact) binding = compiler.sym.declare(NULL, key, context);
  else
    compiler.sym.bind_identity(
      NULL, binding, context.declaration_ast(binding));
  compiler.sym.declare_enumerator(key, <enumerator>);
  return initializer ? %(op = $binding $initializer) : binding;
}

/** Parses one enumerator for enum type `context` and returns its AST.
    Outside macro-template parsing, its binding is published immediately so
    later initializers and enumerators can resolve it.
*/
List Compiler.parse_enumerator(Compiler c, Type context) {
  List slot = c.try_parse_macro_slot(<enumerator>);
  if (slot) return slot;
  List macro = NULL;
  if (c.peek(0) == <$> || c.peek(0) == <ident>) {
    $let(c.aggregate_type, context) {
      macro = c.try_parse_macro_target_at(AST_ENUMERATOR);
    }
  }
  if (macro) return macro;
  if (c.macro_holes) {
    List name = NULL;
    switch (c.peek(0)) {
      case <"$(">: case <$>: name = c.try_parse_macro_slot(<name>); break;
      case <ident>: {
        String spelling = c.token.text;
        c.next();
        name = c.macro_introduced_name(spelling);
        c.sym.bind_identity(NULL, name, context.declaration_ast(name));
        break;
      }
      default:
        c.report_error(
          <parse>, "expected enumerator identifier",
          c.token, NULL);
    }
    List target = %(bind $name ());
    if (c.test(<=>)) return %(op = $target ${c.parse_conditional()});
    return target;
  }
  if (c.peek(0) != <ident>)
    c.report_error(
      <parse>, "expected enumerator identifier",
      c.token, NULL);
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

/** Parses comma-separated enumerators up to the current closing brace.
    Returns their flat source-order `List` and leaves the brace unconsumed.
*/
List Compiler.parse_enumerators(Compiler c, List context) {
  Array enumerators = [];
  while (c.peek(0) != <"}">) {
    if (c.shallow && c.macro_starts_target_at(AST_ENUMERATOR))
      c.skip_macro_invocation();
    else {
      List enumerator = c.parse_enumerator(context);
      if (enumerator.car() == <seq>)
        foreach (Var sibling, enumerator.cdr()) enumerators.push(sibling);
      else enumerators.push(enumerator);
    }
    if (c.peek(0) == <"}">) break;
    c.expect(<,>);
  }
  return enumerators.list_free();
}

static List _enum(Compiler c) {
  Token first = c.token;
  c.expect(<enum>);
  _skip_aggregate_attributes(c);
  List name = _tag_name(c);
  if (name && c.package) name = _package_aggregate_name(c, <enum>, name);
  if (name && c.macro_holes)
    name = %(${c.aggregate_name(<enum>, name.car(),
      c.peek(0) == <"{"> || c.peek(0) == <;>)});
  List usedname = name ? name : c.gensym();
  List type = cons(<enum>, usedname), enums = NULL;
  if (c.test(<"{">)) {
    enums = c.parse_enumerators(type);
    c.expect(<"}">);
    _skip_aggregate_attributes(c);
    if (!c.macro_holes)
      return _publish_aggregate_type(c, <enum>, usedname.car(), enums, first);
  }
  return enums ? type.append(%($enums)): type;
}

static List _type_specifier(Compiler c) {
  c.require_input();
  List slot = c.try_parse_macro_slot(<type>);
  if (slot) return %($slot);
  List syntax = NULL;
  switch (c.peek(0)) {
    case <struct>: case <union>:
      syntax = _struct_or_union(c); break;
    case <enum>:
      syntax = _enum(c); break;
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

/** Parses a type specifier with qualifiers and pointer/reference modifiers.
    Returns its flat `Type` AST and leaves the first following token current.
*/
Type Compiler.parse_type_name(Compiler compiler) {
  List qualifiers = _type_qualifiers(compiler);
  List specifier = _type_specifier(compiler);
  List pointers = _pointer(compiler);
  Type type = %( @pointers @qualifiers @specifier );
  return compiler.sym.local_type(type);
}

// declarators

static List _decl_context_group(Compiler c, List context) {
  List storage = _storage_class(c);
  List (type, binding_type) = _declaration_types(c, storage);
  List binds = _declarator_list(c, binding_type, context, 1);
  return _finish_declaration(c, <declare>, type, binds, 0);
}

static List _pointer(Compiler c) {
  List ptr = NULL;
  loop {
    Symbol symbol = c.peek(0);
    if (symbol == <*> || symbol == <^> || symbol == <&> ||
        symbol.is_type_qualifier()) {
      ptr = cons(symbol, ptr);
      c.next();
      continue;
    }
    Array quals = [];
    if (!_prefix_macro_words(c, 1, quals)) return ptr;
    foreach (Var qualifier, quals) ptr = cons(qualifier, ptr);
  }
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
    c.report_error(
      <parse>, "expected ']'",
      c.token,
      %("dimension:" ${expr.str()} "symbol:" ${unexpected.str()}));
  }
  c.next();
  return %((dim $expr));
}

static List _finish_parameter(
  Compiler compiler, List base, List declarator, List method_identity,
  Token source_first, Token source_after) {
  base = _finish_type(compiler, base);
  int preserved_self = 0;
  declarator = _install_declarator_node(
    compiler, base, NULL, declarator,
    method_identity, &preserved_self);
  compiler.record_source_declaration(
    declarator.cadr(), source_first, source_after);
  List modifiers = NULL;
  base = _declaration_base(base, &modifiers);
  declarator = _append_declarator_modifiers(declarator, modifiers);
  List parameter = %(param $base $declarator);
  match (declarator)
    case %(bind ?binding ?):
      if (!compiler.macro_holes && parameter.type_from_ast().car() == <&>)
        compiler.semantic_binding_facts()[
          %(reference-param $binding)] = 1;
  return parameter;
}

/** Parses one parameter and returns `(param TYPE DECLARATOR)` or `(...)`.
    Outside macro-template parsing, a named parameter is installed in the
    current `Sym` scope. The following delimiter remains current.
*/
List Compiler.parse_parameter(Compiler compiler) {
  if (compiler.test(<...>)) return %(...);
  List qual = _type_qualifiers(compiler);
  List spec = _type_specifier(compiler), type = %( @qual @spec );
  List method = NULL;
  Token first = NULL, after = NULL;
  List declarator = _declarator(
    compiler, type, NULL, &method, &first, &after);
  return _finish_parameter(compiler, type, declarator, method, first, after);
}

/** Parses a nonempty comma-separated parameter `List` in source order.
    The caller owns the parameter scope; the first non-comma delimiter remains
    current.
*/
List Compiler.parse_parameter_list(Compiler c) {
  Array parameters = $auto([]);
  while (1) {
    c.__complete_here(<type>, _type_completion_keywords());
    List parameter = c.try_parse_macro_slot(<param>);
    if (!parameter) parameter = c.parse_parameter();
    parameters.push(parameter);
    if (c.peek(0) != <,>) break;
    c.expect(<,>);
  }
  return parameters;
}

/* Parameter declarations bind into a temporary scope. The declarator cannot
   yet know whether a body follows, so keep that scope in `params`; finishing
   a definition replays it around the body, while a prototype never pushes
   the captured scope. */
static List _function_parameters(Compiler c) {
  c.next();
  c.__complete_here(<type>, _type_completion_keywords());
  if (c.peek(0) == <)>)
    c.report_error(
      <parse>, "empty parameter list; use (void)", c.token, NULL);
  SymScope saved = c.params, parsed;
  int complete = 0;
  defer { if (!complete) c.params = saved; }
  List params;
  c.sym.push_new_scope();
  {
    defer parsed = c.sym.pop_scope();
    params = c.parse_parameter_list();
  }
  if (c.peek(0) != <)>) {
    c.require_input();
    Symbol unexpected = c.peek(0);
    c.report_error(
      <parse>, "expected ')'",
      c.token,
      %("parameters:" ${params.str()} "symbol:" ${unexpected.str()}));
  }
  else c.next();
  c.params = parsed;
  complete = 1;
  return params;
}

static List _declarator_suffix(Compiler compiler) {
  List type = NULL;
  loop {
    // An attribute after a declarator modifies that declarator alone.
    String attribute = _attribute(compiler);
    if (attribute)
      type = %( @type ($attribute) );
    else if (compiler.peek(0) == <[>)
      type = %( @type  @{_array_suffix(compiler)} );
    else if (compiler.peek(0) == <:>) {
      compiler.next();
      List expr = compiler.parse_primary();
      type = %( @type (bitfield $expr) );
    }
    else if (compiler.peek(0) == <(>) {
      List params = _function_parameters(compiler);
      params = %( params @params );
      type = type ? %(fnmod $params $type) : %((fnmod $params));
    }
    else break;
  }
  return type;
}

static List _direct_declarator(
  Compiler c, Type context, List *method_identity, Token *source_first,
  Token *source_after) {
  // A member keeps its spelling in a template: C scopes it to its aggregate.
  int member = context.is_aggregate();
  // Parenthesized declarator: ( declarator )
  if (c.peek(0) == <(>) {
    c.next();
    Token first = c.token;
    List decl = _declarator(
      c, NULL, member ? context : NULL, method_identity, source_first,
      source_after);
    if (c.peek(0) != <)>) {
      c.require_input();
      /* One identifier followed by another is a parameter list whose type
         this unit cannot see, such as a package type named without its
         import alias, not a parenthesized declarator. */
      if (first.type == <ident> && c.peek(0) == <ident>)
        c.report_error(
          <parse>, %"unknown type name '${first.text}'", first,
          %("name an imported package type through its alias"));
      else
        c.report_error(<parse>, "missing closing parenthesis", c.token, NULL);
    }
    c.next();
    return decl;
  }
  if (c.macro_holes) {
    Symbol owner_token = c.peek(0), String owner_spelling = c.token.text;
    Type owner_type =
      owner_spelling ? c.sym.get(%($owner_spelling)) : NULL;
    int literal_owner =
      owner_token.is_builtin_type() ||
      owner_token.is_type_modifier() ||
      (owner_token == <ident> &&
       (owner_type.is_typedef() || c.peek(1) == <.>));
    if (literal_owner && c.peek(1) == <.> &&
        (c.parsing_source_syntax() ||
         c.peek(2) == <$> || c.peek(2) == <ident>)) {
      c.next();
      c.expect(<.>);
      Var member;
      if (c.peek(0) == <$>) member = c.try_parse_macro_slot(<name>);
      else {
        if (!c.token.text.is_identifier())
          c.report_error(<parse>, "expected method name", c.token, NULL);
        member = c.token.text;
        c.next();
      }
      return %(bind (($owner_spelling) $member) ());
    }
    List owner_hole = c.peek_macro_hole();
    if (owner_hole && owner_hole.assoc(<kind>) == <type> &&
        c.peek(2) == <.>) {
      List owner = c.try_parse_macro_slot(<type>);
      c.expect(<.>);
      Var member;
      if (c.peek(0) == <$>) member = c.try_parse_macro_slot(<name>);
      else if (c.token.text.is_identifier()) {
        member = c.token.text;
        c.next();
      }
      else
        c.report_error(
          <parse>,
          "macro method declaration requires a member name",
          c.token, NULL);
      return %(bind (($owner) $member) ());
    }
    switch (c.peek(0)) {
      case <"$(">: {
        List slot = c.try_parse_macro_slot(<name>);
        return %(bind $slot ());
      }
      case <$>:
        return %(bind ${member ? c.try_parse_macro_member()
                               : c.try_parse_macro_slot(<name>)} ());
      case <ident>: {
        String spelling = c.token.text;
        int shadows_with = !!c.with_binding();
        c.next();
        if (member) return %(bind ($spelling) ());
        if (shadows_with) c.sym.define(%($spelling), NULL);
        return %(bind ${c.macro_introduced_name(spelling)} ());
      }
    }
  }
  if (!c.token.text.is_identifier()) return %(bind () ());
  // Identifier or typedef name or method-sugar target
  Token first = c.token;
  List ident = _complex_identifier(c, method_identity);
  *source_first = first;
  *source_after = c.token;
  return %(bind $ident ());
}

/** Captures a name followed by an ordinary complete type and semicolon.
    The reserved typedef identity permits fields to refer to their enclosing
    named type before its pointer or value representation is complete.
*/
List Compiler.parse_named_type(Compiler c) {
  List slot = c.try_parse_macro_slot(<named-type>);
  if (slot) return slot;
  Token start = c.token;
  String name = c.package_spelling(c.token.text);
  c.expect(<ident>);
  List key = %($name);
  if (!c.sym.get_exact(key)) c.sym.define(key, %(typedef $name));
  if (c.test(<;>)) return %(named-type $name ());
  List qualifiers = _type_qualifiers(c), base = NULL;
  if (c.peek(0) == <"{"> ||
      ((c.peek(0) == <struct> || c.peek(0) == <union>) &&
       c.peek(1) == <"{">)) {
    Symbol tag = c.peek(0) == <union> ? <union> : <struct>;
    if (c.peek(0) != <"{">) c.next();
    c.expect(<"{">);
    List fields = c.peek(0) == <"}">
                ? NULL : c.parse_fields(%($tag $name));
    c.expect(<"}">);
    base = c.macro_holes ? %($tag $name (fields @fields))
                        : _publish_aggregate_type(c, tag, name, fields, start);
  }
  else base = _type_specifier(c);
  base = qualifiers.append(base);
  List method = NULL;
  Token first = NULL, after = NULL;
  List declarator = _declarator(c, base, NULL, &method, &first, &after);
  List modifiers = NULL;
  match (declarator) {
    case %(bind () ?captured): modifiers = captured;
    default: c.report_error(
      <parse>, "named type requires an abstract type after its name",
      start, NULL);
  }
  c.expect(<;>);
  Type type = %(declare $base (bindings (bind () $modifiers)))
                .type_from_ast();
  if (!c.macro_holes) c.sym.declare(%(typedef), key, type);
  Type specifier = base.type().base_type();
  if (specifier.is_aggregate_tag_body())
    type = type.list()[:type.len() - type.base_type().len()]
      .append(specifier);
  return %(named-type $name $type);
}

/** Installs a definition-local template binding or typedef provisionally.
    Later template types name a local typedef by its identity, so each
    expansion refers to that expansion's private typedef.
*/
void Compiler.bind_template_local(
  Compiler c, List key, List type, List context) {
  if (c.parsing_source_syntax()) {
    match (key) case %(?(String name)):
      if (!context) c.sym.set(key, %(<macro-expr>));
      else if (context === %(typedef)) {
        c.sym.set(key, %(typedef $name));
        c.sym.set(%(typedef $name), type.type_from_ast().declared());
      }
    return;
  }
  Var local = c.macro_holes && key ? c.macro_definition_locals()[key] : void;
  if (c.macro_holes && local is <string> &&
      (!context || context === %(typedef))) {
    if (context === %(typedef)) {
      c.sym.set(%($local), %(typedef $local));
      c.sym.set(%(typedef $local), %($key));
    }
    else c.sym.bind_identity(
      NULL, key,
      %(declare (<macro-expr>) (bindings (bind $key ()))));
  }
}

static List _declarator(
  Compiler compiler, List type, List context, List *method_identity_out,
  Token *source_first, Token *source_after) {
  List ptr = _pointer(compiler), method_identity = NULL;
  List (key, infix) =
    _direct_declarator(
      compiler, context, &method_identity, source_first,
      source_after).cdr();
  List sfx = _declarator_suffix(compiler);
  List modifiers = %( @infix @sfx @ptr );
  List ast = modifiers.append(type);
  // A parenthesized declarator is assembled twice. Preserve its raw key until
  // the outer call has the base type and can establish the binding once.
  List binding = key;
  compiler.bind_template_local(key, ast, context);
  if (method_identity_out) *method_identity_out = method_identity;
  return %( bind $binding $modifiers );
}

/* Install each declaration binding before resolving its initializer so later
   declarators and source-order dependency analysis share the same identity.
   `init_tokens` records the declarator's first token, not the token where
   expression parsing finishes. */
static List _declarator_init(
  Compiler c, List type, List context) {
  Token origin = c.token;
  List method = NULL;
  Token first = NULL, after = NULL;
  List bind = _declarator(c, type, context, &method, &first, &after);
  int preserved_self = 0;
  bind = _install_declarator_node(
    c, type, context, bind, method, &preserved_self);
  c.record_source_declaration(bind.cadr(), first, after);
  int function_arrow = !c.in_proto && c._at_function_arrow() &&
    %(declare $type (bindings $bind)).type_from_ast().is_function();
  if (!c.in_proto && !function_arrow && c.test(<=>)) {
    if (c.shallow) {
      c._skip_shallow_expression(1);
      return bind;
    }
    List init = c.parse_assignment(), binding = bind.cadr();
    c.check_explicit_converter(
      init, %(declare $type (bindings $bind)).type_from_ast(), 0);
    if (binding_identity_try_parts(binding, NULL, NULL)) {
      Token tokens = c.tokenizer.tokens;
      int token_index = origin - tokens;
      c.init_tokens[binding] = token_index;
    }
    return %( op = $bind $init );
  }
  return bind;
}

static List _declarator_list(
  Compiler compiler, List type, List context, int row) {
  Array bindings = $auto([]);
  loop {
    bindings.push(_declarator_init(compiler, type, context));
    if ((row && _test_declaration_group_comma(compiler)) ||
        !compiler.test(<,>))
      return bindings;
  }
}

/* Recognize the declaration prefix shared by statement, expression, and row
   parsing. A row can additionally require an identifier type to be followed
   by a declarator, which resolves the one C-compatible comma ambiguity. */
static int _test_declaration_start(Compiler c, int require_declarator) {
  Symbol sym = c.peek(0);
  if (c.macro_holes && sym == <"$(">)
    return c.macro_lisp_starts_declaration();
  if (c.macro_holes && sym == <$>) {
    List hole = c.peek_macro_hole();
    if (hole) {
      Symbol kind = hole.assoc(<kind>);
      if (kind) return kind == <type>;
      Symbol next = c.peek(2);
      return next == <ident> || next == <$> || next == <"$(">;
    }
    return c.macro_lisp_starts_declaration();
  }
  if (sym.is_storage_class() || sym.is_type_qualifier() ||
      sym.is_builtin_type() || sym == <inline>) return 1;
  if (sym != <ident>) return 0;
  // A leading attribute belongs to a declaration in every position.
  if (c.token.text == "__attribute__" && _attribute_starts(c)) return 1;
  /* A prefix macro contributes declaration specifiers, so `LOCAL int x = 1;`
     is a declaration wherever it is written. */
  Var definition;
  if (c.object_macros.try_get(c.token.text, &definition) &&
      (definition is <list> || definition.equal(<wrapper>)))
    return 1;

  Token head = c.token;
  String alias = c.package_alias_spelling();
  String name = alias ? alias
              : c.package_member_spelling(c.token.text);
  Type lookup = c.sym.get(%(${name ? name : c.token.text}));
  if (lookup && !lookup.is_typedef()) return 0;
  c.next();
  if (alias) { c.next(); c.next(); }
  Symbol next = c.peek(0);
  int is_operator = next == <ident> && c.token.text == "is";
  // `int a, b __attribute__((unused));` declares `b`, not a type named `b`.
  int attribute = _attribute_starts(c);
  c.token = head;
  if (c.macro_holes && !c.parsing_source_syntax() && is_operator) return 0;
  if (lookup.is_typedef() && !require_declarator) return next != <.>;
  return next == <*> || next == <&> || (next == <ident> && !attribute) ||
         (!require_declarator && next == <)>) ||
         (require_declarator && (next == <^> || next.is_type_qualifier()));
}

/* A typedef name after a comma is ambiguous: `int i, T;` declares another
   int, while `int i, T value;` begins a fresh declaration. Ask the same
   declaration recognizer used by every other parser entry, but require a
   declarator after an identifier type in this one ambiguous position. */
static int _test_declaration_group_comma(Compiler compiler) {
  if (compiler.peek(0) != <,>) return 0;
  Token comma = compiler.token;
  compiler.next();
  int result = _test_declaration_start(compiler, 1);
  compiler.token = comma;
  return result;
}

// Distinguish '(ident, ...)' from an ordinary parenthesized declarator.
static int _test_destructure_declaration(Compiler compiler) {
  Token token = compiler.token;
  if (token.type != <(>) return 0;
  token = compiler.skip_trivia_from(token + 1);
  if (token.type != <ident>) return 0;
  token = compiler.skip_trivia_from(token + 1);
  return token.type == <,>;
}

/* Wraps destructuring targets as the binding forms a declaration carries,
   so a foreach binder reaches the transform as a plain declaration of two
   names. */
static List _destructure_binds(List targets) {
  Array binds = [];
  foreach (List target, targets) binds.push(%(bind $target ()));
  return binds.list_free();
}

static List _destructure_declaration(
  Compiler c, List type, List binding_type, int allow_uninitialized) {
  Array targets = [];
  Token origin_token = c.token;
  c.expect(<(>);
  loop {
    if (c.peek(0) != <ident>)
      c.report_error(
        <parse>, "expected identifier in destructuring declaration",
        c.token, %("destructuring targets must be simple identifiers"));
    List ident = c.parse_basic_identifier();
    List binding = c.macro_holes
      ? ident : c.sym.declare(NULL, ident, binding_type);
    targets.push(binding);
    if (!c.test(<,>)) break;
  }
  c.expect(<)>);
  List bindings = targets.list_free();
  /* A foreach destructures each element rather than an initializer, so the
     same `(a, b)` spelling stands without `=`. It reduces to the
     multi-binding declaration `_for_statement` already knows how to
     carry across `in`. */
  if (allow_uninitialized || c.peek(0) == <in>)
    return %(declare $type (bindings @{_destructure_binds(bindings)}));
  if (!c.test(<=>))
    c.report_error(
      <parse>, "destructuring declaration requires an initializer",
      c.token, NULL);
  List source = c.parse_assignment();
  List result = %(dstrdecl $type (targets @bindings) $source);
  return c.anchor_origin(result, origin_token);
}

// declarations

static List _typedef(Compiler compiler, List context, int row) {
  Token first = compiler.token;
  // An imported `typedef const char *(*fn)(int)` names a qualified type
  // like an object declaration does, so read the qualifiers first.
  List quals = _type_qualifiers(compiler);
  List spec = quals.append(_type_specifier(compiler));
  spec = compiler.sym.local_type(spec);
  List bindings = _declarator_list(compiler, spec, context, row);
  /* A typedef's own alignment changes every record field that names it,
     even when the record declaration has no attribute of its own. */
  if (_layout_attribute_since(compiler, first))
    foreach (List declarator, bindings) {
      String name = binding_identity_spelling(declarator.cadr());
      if (name) compiler.sym.set(%($name "layout-attribute"), %(unknown));
    }
  return _finish_declaration(compiler, <typedef>, spec, bindings, 0);
}

/* Reads the qualifiers, the type specifier, and any storage macro after it,
   `int LOCAL f(void)`, and returns the declared type and the type its names
   are bound to. Source specifier text, such as `("_Noreturn")`, is written
   with the declaration but is no part of the bound type. An aggregate binds
   its short tag; the declared type keeps the body. */
static List _declaration_types(Compiler c, List storage) {
  List quals = _type_qualifiers(c);
  Type spec = _type_specifier(c);
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
  if (trailing.len()) storage = %( @{trailing.list_free()} @storage );
  List words = storage.filter(%!(item) => item is <symbol>);
  Type binding_type = c.sym.local_type(%( @words @quals @spec ));
  if (spec.is_aggregate_tag_body()) {
    Var (aggregate, tag, body) = spec;
    binding_type = %( @words @quals $aggregate $tag );
  }
  return %( ${c.sym.local_type(%( @storage @quals @spec ))} $binding_type );
}

static List _declaration_group(Compiler c, int row) {
  List storage = _storage_class(c);
  if (storage === %(typedef)) return _typedef(c, storage, row);
  List (type, binding_type) = _declaration_types(c, storage);
  if (_test_destructure_declaration(c))
    return _destructure_declaration(c, type, binding_type, 0);
  List bindings = _declarator_list(c, binding_type, NULL, row);
  return _finish_declaration(c, <declare>, type, bindings, 0);
}

/** Tests whether the current token can begin a declaration without consuming.
    Typedefs, package aliases, and macro-hole kinds are resolved through the
    current compiler state.
*/
int Compiler.test_declaration(Compiler c) => _test_declaration_start(c, 0);

/** Parses one declaration group and leaves its terminating token current.
    Declared names are installed in `Sym` as their declarators are completed;
    the result is one `declare`, `typedef`, or initialized `dstrdecl` AST.
*/
List Compiler.parse_simple_declaration(Compiler c) => _declaration_group(c, 0);

static List _declaration_rows(Compiler compiler) {
  Array declarations = [];
  loop {
    declarations.push(_declaration_group(compiler, 1));
    if (!_test_declaration_group_comma(compiler)) break;
    compiler.next();
  }
  return declarations.list_free();
}

/** Parses one x2c declaration row and leaves its terminator current.
    A mixed-type comma row returns a `seq` of declarations in source order;
    a single declaration returns directly.
*/
List Compiler.parse_declaration_row(Compiler compiler) {
  List rows = _declaration_rows(compiler);
  match (rows) case %(?only): return only;
  return %(seq @rows);
}

/* Only the complete initializer admits management. Parentheses and typed
   expression shells preserve that position; operators do not. */
static List _managed_initializer(List syntax) {
  match (syntax) {
    case %(managed-init ?value): return value;
    case %(expr ? ?inner):
      return _managed_initializer(inner);
    case %(parens ?inner): return _managed_initializer(inner);
  }
  return NULL;
}

static int _has_managed_declaration(List declaration) {
  match (declaration) {
    case %(seq *rows):
      foreach (List row, rows)
        if (_has_managed_declaration(row)) return 1;
    case %(declare ? (bindings *declarators)):
      foreach (List declarator, declarators)
        match (declarator)
          case %(op = (bind ? ?) ?value):
            if (_managed_initializer(value)) return 1;
  }
  return 0;
}

static void _append_managed_declaration(
  Compiler c, List declaration, Array output, Token origin) {
  match (declaration) {
    case %(seq *rows): {
      foreach (List row, rows)
        _append_managed_declaration(c, row, output, origin);
      return;
    }
    case %(declare ?base (bindings *declarators)): {
      Array ordinary = $auto([]);
      foreach (List declarator, declarators) {
        List initializer = NULL, binding = NULL, modifiers = NULL;
        match (declarator)
          case %(op = (bind ?name ?mods) ?value): {
            initializer = _managed_initializer(value);
            binding = name;
            modifiers = mods;
          }
        if (!initializer) {
          ordinary.push(declarator);
          continue;
        }
        Type type = modifiers.append(base).type().declared();
        match (base)
          case %(* (!or static extern threaded) *):
            c.report_error(
              <parse>, "managed initializer requires automatic local storage",
              origin, NULL);
        if (!c.protocol_members_for(type, %("Cleanup")))
          c.report_error(
            <protocol>, "managed initializer requires Cleanup participation",
            origin, %("type: ${type.repr()}"));
        if (ordinary.len()) {
          output.push(%(declare $base (bindings @{ordinary})));
          ordinary.clear();
        }
        output.push(%(declare $base
          (bindings (op = (bind $binding $modifiers) $initializer))));
        List receiver = %(expr $type (ident $binding));
        List cleanup = c.resolve_expression(
          %(expr () (call (expr () (op . $receiver ("cleanup")))
                          (args))), c.token);
        output.push(%(defer (stmnt $cleanup)));
      }
      if (ordinary.len())
        output.push(%(declare $base (bindings @{ordinary})));
      return;
    }
  }
  output.push(declaration);
}

/** Lowers managed block declarations to declaration/defer pairs in source
    order, preserving their installed bindings and the enclosing lifetime.
*/
List Compiler.finish_managed_declaration(
  Compiler c, List declaration, Token origin) {
  if (c.macro_holes || !_has_managed_declaration(declaration))
    return declaration;
  Array output = [];
  _append_managed_declaration(c, declaration, output, origin);
  return %(seq @{output.list_free()});
}

static String _lifecycle_owner(
  Compiler compiler, List binding, String member) {
  List method = _method_identity(compiler, binding);
  if (!method) return NULL;
  match (method)
    case %(?name $member): {
      String owner = name, Type owner_type = compiler.sym.get(%($owner));
      return owner_type.is_typedef() ? owner : NULL;
    }
  return NULL;
}

static void _require_lifecycle_signature(
  Compiler compiler, List decl, String name, String role) {
  match (decl)
    case %(declare (void)
           (bindings
             (bind ?
               ((fnmod (params (param (void) (bind () ())))))))):
      return;
  String message = role == "initializer"
    ? "type initializer must have signature void TYPE.initialize(void)"
    : "type shutdown must have signature void TYPE.shutdown(void)";
  compiler.report_error(
    <parse>, message, compiler.token, %("$role: $name"));
}

static String _prepare_function_lifecycle(
  Compiler c, List declaration, List binding, String *initializer_owner,
  String *shutdown_owner) {
  String name = binding_identity_spelling(binding);
  *initializer_owner = name
    ? _lifecycle_owner(c, binding, "initialize") : NULL;
  *shutdown_owner = name
    ? _lifecycle_owner(c, binding, "shutdown") : NULL;
  if (*initializer_owner) {
    _require_lifecycle_signature(c, declaration, name, "initializer");
    if (c.init_fn && c.init_fn != name)
      c.report_error(
        <parse>, "translation unit has more than one type initializer",
        c.token, %( "initializer:" $name ));
  }
  if (*shutdown_owner) {
    _require_lifecycle_signature(c, declaration, name, "shutdown");
    if (c.fini_fn && c.fini_fn != name)
      c.report_error(
        <parse>, "translation unit has more than one type shutdown",
        c.token, %( "shutdown:" $name ));
  }
  return name;
}

static void _publish_function_lifecycle(
  Compiler compiler, String name, String initializer_owner,
  String shutdown_owner) {
  if (initializer_owner) compiler.init_fn = name;
  if (shutdown_owner) compiler.fini_fn = name;
}

static List _parse_expression_function_body(Compiler compiler) {
  with compiler {
    _.expect(<=>);
    _.expect(<">">);
    Token origin = _.token;
    _.sym.push_new_scope();
    List result = NULL;
    {
      defer _.sym.pop_scope();
      List expression = _.parse_expression();
      _.expect(<;>);
      /* A `void` result has no value to return, and C rejects a returned
         value there, so the expression stands as the body's statement. */
      result = _.return_type === %(void)
             ? %(stmnt $expression) : _.finish_return_statement(expression);
    }
    return %(block ${_.anchor_origin(result, origin)});
  }
}

static List _finish_function_parts(
  Compiler c, List declaration, List rtype, List declarator,
  List binding, List syntax) {
  defer {
    c.params.symbols = NULL;
    c.params.bindings = NULL;
    c.params.enumerators = NULL;
    c.params.macros = NULL;
  }
  if (c.parsing_source_syntax()) {
    c.sym.push_scope(c.params);
    defer c.sym.pop_scope();
    List body;
    if (c._at_function_arrow()) {
      c.expect(<=>);
      c.expect(<">">);
      body = %(arrow ${c.parse_expression()});
      c.expect(<;>);
    }
    else {
      c.expect(<"{">);
      body = c.parse_compound_statement();
    }
    return %(function $rtype $declarator $body);
  }
  /* Validate lifecycle ownership before the body, but publish `init_fn` and
     `fini_fn` only after the parameter scope and body finish successfully.
     A caller's `SymTxn` can still roll those names back if a later generated
     sibling fails. */
  String initializer_owner = NULL, shutdown_owner = NULL;
  String name = _prepare_function_lifecycle(
    c, declaration, binding,
    &initializer_owner, &shutdown_owner);
  int expression_body = !syntax && c._at_function_arrow();
  if (!syntax && !expression_body) c.expect(<"{">);
  Type old_return = c.return_type, declared_return = NULL;
  match (declaration.type_from_ast())
    case %((func *) *result): declared_return = result.type().declared();
  c.return_type = declared_return;
  String old_fn = c.fn_name;
  c.fn_name = name;
  c.sym.push_scope(c.params);
  List body = NULL;
  {
    defer {
      c.sym.pop_scope();
      c.return_type = old_return;
      c.fn_name = old_fn;
    }
    if (syntax) body = c.bind_syntax(syntax, AST_BLOCK, c.return_type);
    else if (expression_body) body = _parse_expression_function_body(c);
    else body = c.parse_compound_statement();
  }
  _publish_function_lifecycle(c, name, initializer_owner, shutdown_owner);
  return %(function $rtype $declarator $body);
}

// Complete a token-parsed or generated function in its parameter scope.
static List _finish_function(
  Compiler compiler, List declaration, List syntax) {
  match (declaration)
    case %(declare ?rtype
           (bindings
             (!set ?declarator (bind ?binding ?)))):
      return _finish_function_parts(
        compiler, declaration, rtype, declarator, binding,
        syntax);
  return NULL;
}

static List _finish_function_definition(Compiler compiler, List decl) =>
  _finish_function(compiler, decl, NULL);

/** Parses one non-function, non-typedef `Decl` macro argument.
    Returns a single declaration without consuming the invocation delimiter;
    flat destructuring may omit an initializer in this position.
*/
List Compiler.parse_declaration_argument(Compiler c) {
  List storage = _storage_class(c);
  if (storage === %(typedef))
    c.report_error(
      <parse>, "Decl macro argument cannot be a typedef",
      c.token, NULL);
  List (type, binding_type) = _declaration_types(c, storage);
  if (_test_destructure_declaration(c))
    return _destructure_declaration(c, type, binding_type, 1);
  List binding = _declarator_init(c, binding_type, NULL);
  List declaration = _finish_declaration(
    c, <declare>, type, %($binding), 0);
  if (declaration.type_from_ast().is_function())
    c.report_error(
      <parse>, "Decl macro argument cannot be a function declaration",
      c.token, NULL);
  return declaration;
}

/** Parses one function declaration and its required compound body.
    The parameter bindings are active while the body is parsed, and the first
    token after the closing brace remains current.
*/
List Compiler.parse_function_definition(Compiler compiler) {
  List declaration = compiler.parse_simple_declaration();
  if (compiler.peek(0) != <"{"> && !compiler._at_function_arrow())
    compiler.report_error(
      <parse>, "Function macro argument requires a function body",
      compiler.token, NULL);
  return _finish_function_definition(compiler, declaration);
}

/** Parses one function decorator target and returns its resulting AST.
    A compatible unit macro at the current token is expanded first; otherwise
    an ordinary function definition is required.
*/
List Compiler.parse_function_target(Compiler compiler) {
  List macro = compiler.try_parse_macro_target_at(AST_UNIT);
  if (!macro) return compiler.parse_function_definition();
  match (macro) case %(seq ?function): return function;
  return macro;
}

// `as` and `with` are contextual: ordinary identifiers everywhere else.
static int _test_contextual(Compiler compiler, String word) {
  if (compiler.peek(0) != <ident> || compiler.token.text != word) return 0;
  compiler.next();
  return 1;
}

/* with Name [as Local] {, Name [as Local]}
   Each name binds a bare local spelling to one already-built package member.
   Registration runs at the name's own token so an unknown member and a
   collision both point at the spelling the developer wrote. */
static void _import_members(Compiler c, String name) {
  do {
    if (c.peek(0) != <ident>)
      c.report_error(
        <parse>, "expected a package member name after 'with'",
        c.token, NULL);
    Token member_token = c.token, local_token = member_token;
    String member = c.token.text, local = member;
    c.next();
    if (_test_contextual(c, "as")) {
      if (c.peek(0) != <ident>)
        c.report_error(
          <parse>, "expected a local name after 'as'", c.token, NULL);
      local_token = c.token;
      local = c.token.text;
      c.next();
    }
    c.register_package_member(
      name, member, local, member_token, local_token);
  } while (c.test(<,>));
}

/** Parses and registers one `import` declaration, including its semicolon.
    The alias defaults to the package name; `with` members add source-ordered
    local spellings. These spellings affect source resolution only; the package
    name in the returned AST drives the generated header include.
*/
List Compiler.parse_import_declaration(Compiler c) {
  Token start = c.token;
  c.expect(<import>);
  if (c.peek(0) != <lit-char*>)
    c.report_error(
      <parse>, "expected a quoted package name after 'import'",
      c.token, NULL);
  Token name_token = c.token;
  String name = String.new_len(
    c.token.text + 1, c.token.len - 2).unescape();
  if (!name.is_identifier())
    c.report_error(
      <parse>, "package name must be a C identifier", name_token, NULL);
  c.next();
  String alias = name;
  if (_test_contextual(c, "as")) {
    if (c.peek(0) != <ident>)
      c.report_error(
        <parse>, "expected an alias identifier after 'as'",
        c.token, NULL);
    alias = c.token.text;
    c.next();
  }
  c.collect_package(name, start);
  c.register_package_alias(name, alias, start);
  if (_test_contextual(c, "with")) _import_members(c, name);
  c.expect(<;>);
  return %(import $name $alias);
}

/** Reports whether the unit's tokens define a function named `main` at file
    scope. A script unit that does is an ordinary program: its declarations
    stay at file scope and it may not have top-level statements. Both parse
    passes read the same tokens, so they agree before either parses.
*/
int Compiler.defines_main(Compiler c) {
  for (Token token = c.skip_trivia_from(c.tokenizer.tokens);
       token.type != <eof>; token = token.after_group()) {
    Token open = c.skip_trivia_from(token + 1);
    if (token.type != <ident> || token.text != "main" || open.type != <(>)
      continue;
    Token body = open.after_group();
    if (body.type == <"{"> || (body.type == <=> &&
        c.skip_trivia_from(body + 1).type == <">">))
      return 1;
  }
  return 0;
}

/* A declaration in a script unit stays at file scope when a body follows
   its declarator, `{` for a function or aggregate and `=>` for an
   expression-bodied function, or when it ends right after a parameter list
   as a prototype does. An initialized or plain object declaration belongs
   to `main`. */
static int _script_declaration_stays(Compiler c) {
  Symbol previous = 0;
  for (Token token = c.token; token.type != <eof>;
       previous = token.type, token = token.after_group()) {
    if (token.type == <;>) return previous == <(>;
    if (token.type == <"{">) return 1;
    if (token.type == <=>)
      return c.skip_trivia_from(token + 1).type == <">">;
  }
  return 0;
}

/** Reports whether the cursor begins a protocol declaration or adoption,
    including its `meta` and `static` markers. This query does not consume
    tokens. */
int Compiler.protocol_form_starts(Compiler c) {
  int at = c.peek(0) == <ident> && c.token.text == "meta";
  if (c.peek(at) == <static>) at++;
  return c.peek(at) == <protocol>;
}

/** Reports whether the cursor begins a contextual top-level `meta`
    declaration: a function or an initialized file-static value. */
int Compiler.meta_form_is_declaration(Compiler c) {
  if (c.peek(0) != <ident> || c.token.text != "meta") return 0;
  Token head = c.token;
  c.next();
  int marker = c.test_declaration();
  c.token = head;
  return marker;
}

/** Reports whether the top-level item at the cursor is one of a script
    unit's statements, which become `main`'s body.
    Preprocessor lines, imports, protocols, compile-time definitions and
    Lisp, file-scope macro invocations, `typedef`, `static`, and `extern`
    declarations, linkage braces, type definitions, and function prototypes
    and definitions stay at file scope. This query does not consume tokens.
*/
int Compiler.script_statement_starts(Compiler c) {
  switch (c.peek(0)) {
    case <eof>: case <import>: case <protocol>: case <"$(">:
    case <typedef>: case <static>: case <extern>: case <"}">:
      return 0;
  }
  if (c.test_static_assert() || c.keyword_form_is_definition() ||
      c.macro_form_is_definition() || c.meta_form_is_declaration() ||
      c.protocol_form_starts())
    return 0;
  if (c.peek(0) == <ident> && c.token.text == "with") return 1;
  if (c.macro_starts_target_at(AST_UNIT)) return !c.macro_targets_unit();
  return !c.test_declaration() || !_script_declaration_stays(c);
}

/** Reports whether the top-level item at the cursor is a script statement
    that runs, rather than a declaration: an expression, control flow, a
    `with` block, or a statement macro. This query does not consume tokens.
*/
int Compiler.script_statement_executes(Compiler c) =>
  c.script_statement_starts() &&
  (c.peek(0) == <$> || c.token.text == "with" || !c.test_declaration());

/** Consumes one brace of a C linkage specification at file scope and reports
    whether it did. `extern "C" {` opens a group; a `}` at file scope closes
    the innermost open group, because every other file-scope form consumes
    its own braces. The declarations between them stay at file scope. The
    `#ifdef __cplusplus` arm of the usual header guard is skipped, so only an
    unguarded group reaches this operation.
*/
int Compiler.skip_linkage_brace(Compiler c) {
  if (c.peek(0) == <extern> && c.peek(1) == <lit-char*> &&
      c.peek(2) == <"{">) {
    c.next();
    c.next();
  }
  else if (c.peek(0) != <"}">) return 0;
  else if (!c.braces.len()) {
    // The group opened before an include, in an earlier segment.
    if (!c.open_linkage) return 0;
    c.open_linkage--;
    c.token = c.skip_trivia_from(c.token + 1);
    return 1;
  }
  c.next();
  return 1;
}

/* Takes the conditional groups open after the last conditional directive
   before the current top-level form. */
static void _track_conditional_arms(Compiler c) {
  Token base = c.tokenizer.tokens;
  Var stack;
  for (Token token = c.token - 1; token >= base &&
       (token.type == <space> || token.type == <comment> ||
        token.type == <preproc>); token--)
    if (c.arm_stacks.try_get((long) (token - base), &stack)) {
      c.arms = stack;
      return;
    }
}

/* Keep authored prose beside a definition without making comment text part
   of the semantic AST. Macro templates carry it until their selected body
   binds at the invocation. */
static String _definition_doc(Compiler c, Token start) {
  Token first = c.tokenizer.tokens;
  if (start <= first) return NULL;
  Token token = start - 1;
  while (token > first && token.type == <space>) token--;
  if (token.type != <comment> || token.len < 5 ||
      !token.text.startswith("/**")) return NULL;
  int lines = 0;
  for (int position = token.pos + token.len; position < start.pos;
       position++)
    if (c.text[position] == '\n' && ++lines > 1) return NULL;
  return String.new_len(token.text + 3, token.len - 5);
}

static void _definition_source(
  Compiler c, List function, int line, String doc) {
  match (function)
    case %(function ? (bind ?binding ?) ?):
      c.semantic_binding_facts()[%(api-definition $binding)] =
        %($line $doc);
}

/** Parses one top-level form and applies its source-ordered compiler effects.
    Returns its AST, or NULL when a keyword definition, top-level Lisp form,
    linkage brace, or compile-time-only `meta` function only updates compiler
    state, with the first following token current. A macro import whose
    `.xmacro` makes `meta` declarations retains their runtime forms, which
    the unit emits where it reaches them.
*/
List Compiler.parse_top_level(Compiler c) {
  if (!c.macro_holes) {
    c.update_source_visibility(c.leading_preproc());
    _track_conditional_arms(c);
  }
  if (c.skip_linkage_brace()) return NULL;
  if (c.test_static_assert()) return c.parse_static_assert();
  List slot = c.try_parse_macro_slot(<unit>);
  if (slot) return slot;
  if (c.keyword_form_is_definition()) {
    c.parse_keyword_definition();
    return NULL;
  }
  List macro = c.try_parse_macro_target_at(AST_UNIT);
  if (macro) return macro;
  if (c.protocol_form_starts()) return c.parse_protocol_declaration();
  switch (c.peek(0)) {
    case <import>:   return c.parse_import_declaration();
    case <"$(">: {
      if (c.parsing_source_syntax()) return c.parse_source_lisp();
      List imported = c.parse_macro_lisp_top_level();
      if (imported) foreach (Var definition, imported.cdr())
        c.meta_defs.push(definition);
      return NULL;
    }
    case <@>:
      c.report_error(
        <parse>, "top-level decorators are not supported", c.token,
        %( "module initialization: void TYPE.initialize(void)" ));
  }
  if (c.macro_form_is_definition()) return c.parse_macro_definition();
  Token meta = NULL;
  if (c.meta_form_is_declaration()) {
    meta = c.token;
    c.next();
  }
  Token definition_start = c.token;
  String definition_doc = _definition_doc(c, definition_start);
  List decl = c.parse_declaration_row();
  if (c.test(<;>)) {
    if (meta && decl.type_from_ast().is_function())
      c.install_native_meta_function(decl, meta);
    else if (meta) c.install_meta_declaration(decl, meta);
    c.record_declaration_visibility(decl);
    return decl;
  }
  if (c.peek(0) == <"{"> || c._at_function_arrow()) {
    match (decl) case %(seq *):
      c.report_error(
        <parse>, "a function definition cannot share a declaration row",
        c.token, NULL);
    List function;
    $let(c.meta_body, meta != NULL) {
      function = _finish_function_definition(c, decl);
    }
    if (meta) c.install_meta_function(function, meta);
    c.record_declaration_visibility(function);
    /* A `meta` function that reaches a `Meta` operation exists only inside
       the compiler, so there is no runtime form to emit. */
    if (meta && c.meta_is_comptime_only(function)) {
      _definition_source(
        c, function, definition_start.line, definition_doc);
      return NULL;
    }
    if (c.macro_holes)
      return %(api-source ${definition_start.line} $definition_doc $function);
    _definition_source(c, function, definition_start.line, definition_doc);
    return function;
  }
  c.require_input();
  Symbol unexpected = c.peek(0);
  c.report_error(
    <parse>, "expected ';', '{', or '=>'",
    c.token,
    %("token:" ${c.token.text} "symbol:" ${unexpected.str()}));
}

/** Parses one submission from the current token stream. `end_position` is
    the byte offset after supplied input, before any synthetic closing text.
    Missing required syntax raises `<incomplete>`; trailing items are rejected.
    Temporary parser scopes and captured parameters are restored on every exit.
    The caller owns the semantic transaction and commits after execution.
*/
List Compiler.parse_submission(Compiler c, int end_position) {
  Token boundary = c.input_boundary;
  SymScope params = c.params;
  int scope_count = c.sym.scope_count();
  defer {
    while (c.sym.scope_count() > scope_count) (void) c.sym.pop_scope();
    c.params = params;
    c.input_boundary = boundary;
  }
  Token token = c.token;
  while (token.type != <eof> && token.pos < end_position) token++;
  c.input_boundary = token;
  List result = c.parse_top_level();
  if (c.peek(0) != <eof>)
    c.report_error(
      <parse>, "submit one top-level item at a time", c.token, NULL);
  return result;
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
  $let(c.aggregate_type, type) {
    foreach (List member, members) {
      foreach (Var row, c.evaluate_macro_rows(member)) {
        if (tag == <enum>)
          bound.push(c.bind_syntax(row, AST_ENUMERATOR, c.return_type));
        else bound.push(c.bind_syntax(row, AST_FIELD, c.return_type));
      }
    }
  }
  return _publish_aggregate_type(
    c, tag, name, bound.list_free(), c.token);
}

static Var _finish_type_spec(Compiler compiler, Var value) {
  int slot = value is <list> && !value.is_nil() &&
             value.car() == <macro-slot>;
  value = compiler.evaluate_macro_slot(value);
  if (slot && value is <list>) {
    Type type = value.type().canonicalize();
    return %(seq @type);
  }
  if (value is not <list>) return value;
  match (value) {
    case %((!set ?tag (!or struct union)) ?name):
      return %($tag ${_finish_tag_name(compiler, name)});
    case %((!set ?tag (!or struct union)) ?name (fields *members)):
      return _finish_aggregate_type(compiler, tag, name, members);
    case %(enum ?name):
      return %(enum ${_finish_tag_name(compiler, name)});
    case %(enum ?name (*members)):
      return _finish_aggregate_type(compiler, <enum>, name, members);
    // Semantic types name an expanded template typedef by its spelling.
    case %(binding ? ?(String name)): return name;
  }
  return value;
}

static List _finish_type(Compiler compiler, List type) {
  Var whole = _finish_type_spec(compiler, type);
  if (whole != type) {
    List constructed = whole;
    Type type = constructed.car() == <seq>
              ? constructed.cdr() : constructed;
    return compiler.sym.local_type(type);
  }
  Array bound = [];
  foreach (Var spec, type) {
    Var value = _finish_type_spec(compiler, spec);
    if (value is <list> && !value.is_nil() &&
        value.car() == <seq>)
      foreach (Var item, value.list().cdr()) bound.push(item);
    else bound.push(value);
  }
  Type resolved = bound.list_free();
  return compiler.sym.local_type(resolved);
}

/* Constructed function modifiers have not passed through the parameter
   parser. Bind their parameter types in the same temporary prototype scope. */
static List _finish_declarator_parameters(Compiler compiler, List declarator) {
  match (declarator) {
    case %(op = ?binding ?value):
      return %(op = ${_finish_declarator_parameters(compiler, binding)}
               $value);
    case %(bind ?binding ?modifiers): {
      Array output = [];
      foreach (Var modifier, modifiers.list()) {
        match (modifier) {
          case %(fnmod (params *parameters)): {
            Array params = [];
            compiler.sym.push_new_scope();
            {
              defer compiler.sym.pop_scope();
              foreach (List parameter, parameters) match (parameter) {
                case %(param ?base ?declarator):
                  params.push(_finish_parameter(
                    compiler, base,
                    _finish_declarator_parameters(compiler, declarator),
                    NULL, NULL, NULL));
                default: params.push(parameter);
              }
            }
            modifier = %(fnmod (params @{params.list_free()}));
          }
        }
        output.push(modifier);
      }
      return %(bind $binding (@{output.list_free()}));
    }
  }
  return declarator;
}

static List _install_declarator_node(
  Compiler compiler, List base, List declaration_context,
  List declarator, List method_identity, int *preserved_self) {
  if (compiler.macro_holes) return declarator;
  Var name = void;
  List mods = NULL, initializer = NULL;
  match (declarator) {
    case %(op = (bind ?captured_name ?captured_mods) ?value): {
      name = captured_name;
      mods = captured_mods;
      initializer = value;
    }
    case %(bind ?captured_name ?captured_mods): {
      name = captured_name;
      mods = captured_mods;
    }
  }
  name = compiler.evaluate_macro_slot(name);
  int exact_name = 0;
  match (name)
    case %("x2c.ident" ?(String exact)):
      name = exact, exact_name = 1;
  List declaration = %(declare $base (bindings (bind () $mods)));
  List prior_binding = name is <list> ? name : NULL;
  List method = method_identity ? method_identity
              : prior_binding
                ? _method_identity(compiler, prior_binding) : NULL;
  List self_signature = prior_binding
                      ? _method_self_signature(compiler, prior_binding)
                      : NULL;
  Type declared_type = mods.append(base);
  match (name) {
    case %(((!or (!is ?owner type string)
                  (!is ?owner type symbol)
                  ((!is ?owner type string))))
           ?(String member)): {
      String owner_name =
        owner is <symbol> ? owner.symbol() : owner.str();
      name = %"${owner_name}_$member";
      method = %($owner_name $member);
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
      else compiler.report_error(
        <type>, "method name has no concrete owner",
        compiler.token, NULL);
    case %((!is ? type list) (!is ? type string)):
      compiler.report_error(
        <type>, "method name has no concrete owner",
        compiler.token, NULL);
  }
  String exact = _syntax_exact_name(name);
  if (exact_name) {
    List prior_binding = compiler.sym.current_binding(%($exact));
    Var prior = prior_binding
              ? compiler.sym.current_symbols()[%($exact)] : void;
    if (prior is <list>) {
      Type prior_type = prior;
      Type candidate = declaration.type_from_ast();
      if (!candidate.is_function() || !prior_type.is_function())
        compiler.report_error(
          <parse>, %"declaration '$exact' is already bound",
          compiler.token, %("prior binding: '$exact'"));
    }
  }
  List binding = exact
    ? compiler.sym.declare(declaration_context, %($exact), declared_type)
    : name is <list> ? name.list() : NULL;
  if (binding && !exact) {
    String spelling = binding_identity_spelling(binding);
    List visible = compiler.sym.lookup(%($spelling), NULL);
    if (visible != binding)
      compiler.sym.bind_identity(declaration_context, binding, declaration);
  }
  if (binding && method)
    compiler.semantic_binding_facts()[%(method $binding)] = method;
  else if (binding) compiler.semantic_binding_facts().del(%(method $binding));
  if (binding && self_signature) {
    compiler.semantic_binding_facts()[%(self $binding)] = self_signature;
    *preserved_self = 1;
  }
  List bound = %(bind $binding $mods);
  if (initializer)
    initializer = compiler.resolve_expression(initializer, compiler.token);
  return initializer ? %(op = $bound $initializer) : bound;
}

/** Constructs a foreign alias from one direct function declaration and target.
    `native_syntax` must resolve to a different direct identifier and, when
    typed, a function. Storage is limited to `static` or `inline`, when
    present, and variadic parameters are rejected.
*/
List Compiler.finish_foreign_alias(
  Compiler c, List declaration, List native_syntax) {
  match (declaration) {
    case %(function *):
      c.report_error(
        <parse>, "foreign alias declaration cannot have a body",
        c.token, NULL);
    /* A function returning a pointer puts its pointer modifiers after the
       fnmod. The trailing modifiers are the return type's pointer depth; the
       declaration is still one direct function. */
    case %(declare (!set ?base (*))
           (bindings
             (bind ?binding ((fnmod (params *parameters)) *)))): {
      foreach (Var part, base) {
        if (part is not <symbol>) continue;
        Symbol specifier = part;
        if (specifier.is_storage_class() && specifier != <static>)
          c.report_error(
            <parse>, "foreign alias has invalid storage class",
            c.token, %("allowed storage: static or inline"));
      }
      foreach (Var parameter, parameters)
        match (parameter) case %(...):
          c.report_error(
            <parse>, "foreign alias cannot be variadic",
            c.token, NULL);
      List native = c.resolve_expression(native_syntax, c.token);
      match (native)
        case %(expr (!set ?native_type (*))
               (ident ?native_binding)): {
          if (native_type && !native_type.type().is_function())
            c.report_error(
              <type>, "foreign alias native target is not a function",
              c.token, %("type: ${native_type.repr()}"));
          if (List.equal(binding, native_binding))
            c.report_error(
              <parse>, "foreign alias cannot name itself",
              c.token, NULL);
          return %(falias $declaration $native_binding);
        }
      c.report_error(
        <parse>, "foreign alias native target must be a direct identifier",
        c.token, NULL);
    }
  }
  c.report_error(
    <parse>, "foreign alias target must be one direct function declaration",
    c.token, NULL);
}

static void _append_declaration_rows(Array output, List syntax) {
  match (syntax) {
    case %(seq *rows):
      foreach (List row, rows) _append_declaration_rows(output, row);
    case %(declaration-bundle (rows *rows)):
      foreach (List row, rows) _append_declaration_rows(output, row);
    default: output.push(syntax);
  }
}

/** Binds parser-shaped `syntax` at `context` into current compiler state.
    The input must evaluate to a nonempty AST `List` valid for the requested
    `AstPos`. Bindings, types, scopes, and expressions are resolved in source
    order; `return_type` applies only while descendants are bound. This method
    mutates `Sym` and does not open a semantic transaction.
*/
List Compiler.bind_syntax(
  Compiler c, Var syntax, AstPos context, Type return_type) {
  Var value = c.evaluate_macro_slot(syntax);
  if (value is not <list>)
    c.report_error(<parse>, "expected syntax", c.token, NULL);
  List input = value;
  if (!input) c.report_error(<parse>, "expected syntax", c.token, NULL);
  if (context == AST_ENUMERATOR) match (input) {
    case %(!or
           (binding ? (!is ? type string))
           ((!is ? type string))
           ("x2c.ident" (!is ? type string))):
      return _publish_enumerator(c, input, c.aggregate_type, c.token);
    case %(!set ?node
           (bind ? ?)):
      return _publish_enumerator(c, node, c.aggregate_type, c.token);
    case %(!set ?node
           (op =
             (!or
               (binding ? (!is ? type string))
               ((!is ? type string))
               ("x2c.ident" (!is ? type string))
               (bind ? ?))
             ?)):
      return _publish_enumerator(c, node, c.aggregate_type, c.token);
  }
  if (context == AST_MAP_ENTRY && input.car() != <seq> &&
      input.car() != Atom.intern("macro-invoke"))
    return c.resolve_map_entry(input, c.token);
  /* Parsed templates and compile-time Lisp are the intended producers. There
     is no separate validation pass before or after expansion. The structural
     match below enforces `AstPos` and rejects unmatched shapes at
     `construction_error`; existing expression types and binding identities
     are trusted, and strings are never reparsed.

     Binding mutates the current `Sym` in visitation order. Macro invocation
     opens the surrounding `SymTxn`, allowing earlier siblings to be visible to
     later ones while preserving whole-expansion rollback on failure. */
  $let(c.return_type, return_type) with c {
    int statement_position = context == AST_BLOCK ||
                             context == AST_STATEMENT;
    match (input) {
      case %(macro-invoke ?definition ?arguments ?invocation):
        return _.expand_macro_invocation_node(
          definition, arguments,
          _.macro_invocation_site(invocation), context);
      case %(macro-slot ? ? *):
        if (_.macro_holes) return input;
      case %(src ? ?syntax): {
        return _.bind_syntax(syntax, context, _.return_type);
      }
      case %(api-source ?line ?doc ?syntax): {
        if (context != AST_UNIT) goto construction_error;
        List bound = _.bind_syntax(syntax, context, _.return_type);
        Token invocation = _.macro_stack
                         ? _.macro_stack.last().list()[3] : NULL;
        String invocation_doc = invocation
                              ? _definition_doc(_, invocation) : NULL;
        _definition_source(
          _, bound, invocation ? invocation.line : line,
          invocation_doc ? invocation_doc : doc);
        return bound;
      }
      case %(named-type ?(String name) ?type): {
        if (context != AST_UNIT) goto construction_error;
        List key = %($name);
        if (!_.sym.get_exact(key)) _.sym.define(key, %(typedef $name));
        if (!type.list()) return %(seq);
        List declaration = type.type().declaration_ast(key);
        match (declaration)
          case %(declare ?base ?bindings):
            return _.bind_syntax(%(typedef $base $bindings), context, NULL);
      }
      case %(declaration-bundle (rows *rows)): {
        if (context != AST_UNIT) goto construction_error;
        if (_.shallow) {
          _.declaration_produced = 1;
          _.run_declaration_effects();
        }
        $let(_.declaration_projection, _.declaration_projection + 1) {
          Array projected = [];
          foreach (List row, rows) {
            List bound = _.bind_syntax(row, context, _.return_type);
            _append_declaration_rows(projected, bound);
          }
          List result = projected.list_free();
          return _.shallow ? %(declaration-bundle (rows @result))
                           : %(seq @result);
        }
      }
      case %(syntax-recipe ?callback ?arguments): {
        Var result = _.evaluate_declaration_recipe(callback, arguments);
        return _.bind_syntax(result, context, _.return_type);
      }
      case %(declaration-recipe ?callback ?arguments): {
        if (context != AST_UNIT) goto construction_error;
        if (_.shallow)
          return %(declaration-pending $callback $arguments
                    ${_.freeze_declaration_syntax(_.macro_stack)}
                    ${_.source_private});
        Var result = _.evaluate_declaration_recipe(callback, arguments);
        return _.bind_syntax(result, context, _.return_type);
      }
      case %(default-forward ?child ?parent ?member *fallback): {
        if (context != AST_UNIT) goto construction_error;
        return %(declaration-forward $child $parent $member
                  $fallback ${_.source_private});
      }
      case %(default ?function): {
        if (context != AST_UNIT) goto construction_error;
        if (_.shallow)
          return %(declaration-default $function
                    ${_.freeze_declaration_syntax(_.macro_stack)}
                    ${_.source_private});
        return _.bind_syntax(function, context, _.return_type);
      }
      case %(declaration-function
               (declare ?return_type (bindings ?declarator))
               ?body ?construction): {
        if (context != AST_UNIT) goto construction_error;
        if (_.shallow) return input;
        $let(_.macro_stack, _.thaw_declaration_syntax(construction)) {
          return _.bind_syntax(
            %(function $return_type $declarator $body),
            context, _.return_type);
        }
      }
      case %(seq *items): {
        if (context == AST_STATEMENT) {
          match (items) case %(?only):
            return _.bind_syntax(only, context, _.return_type);
          _.report_error(<parse>, "expected one statement", _.token, NULL);
        }
        Array bound = [];
        foreach (Var item, items) {
          List value = _.bind_syntax(item, context, _.return_type);
          if (value.car() == <seq>)
            foreach (Var child, value.cdr()) bound.push(child);
          else bound.push(value);
        }
        return %(seq @{bound.list_free()});
      }
      case %(args *arguments): {
        if (context != AST_EXPRESSION) goto construction_error;
        Array bound = [];
        foreach (List argument, arguments)
          bound.push(_.resolve_expression(argument, _.token));
        return %(args @{bound.list_free()});
      }
      case %(c-assert ?condition ?message): {
        if (context == AST_UNIT || context == AST_BLOCK ||
            context == AST_FIELD)
          return %(c-assert
                   ${_.resolve_expression(condition, _.token)}
                   ${_.resolve_expression(message, _.token)});
        goto construction_error;
      }
      case %(falias ?declaration ?native_syntax): {
        if (context != AST_UNIT) goto construction_error;
        declaration = _.bind_syntax(declaration, AST_UNIT, _.return_type);
        return _.finish_foreign_alias(declaration, native_syntax);
      }
      case %(!set ?initializer (managed-init ?)): {
        if (context == AST_EXPRESSION)
          return _.resolve_expression(%(expr () $initializer), _.token);
        goto construction_error;
      }
      case %(!set ?expression (expr *)):
        if (context == AST_EXPRESSION)
          return _.resolve_expression(expression, _.token);
      case %((!set ?tag (!or declare decl typedef))
             ?base (bindings *declarators)):
        {
          int legal = tag == <typedef> ? context == AST_UNIT ||
                                       context == AST_BLOCK
                    : tag == <decl> ? context == AST_BLOCK
                    : context == AST_UNIT || context == AST_BLOCK ||
                      context == AST_FIELD;
          if (!legal) goto construction_error;
          base = _finish_type(_, base);
          List field_context = context == AST_FIELD
                             ? _.aggregate_type : NULL;
          List declaration_context = tag == <typedef>
                                   ? %(typedef) : field_context;
          Array output = [];
          int preserved_self = 0;
          foreach (List declarator, declarators) {
            declarator = _finish_declarator_parameters(_, declarator);
            List syntax = declarator;
            match (syntax) case %(op = ?binding ?): syntax = binding;
            match (syntax)
              case %(bind ? ?modifiers): {
                Type mods = modifiers;
                if (context != AST_FIELD && mods.is_bitfield())
                  goto construction_error;
              }
            output.push(_install_declarator_node(
              _, base, declaration_context, declarator, NULL,
              &preserved_self));
          }
          List result = _finish_declaration(
            _, tag, base, output.list_free(), preserved_self);
          if (context == AST_UNIT) _.record_declaration_visibility(result);
          if (context == AST_BLOCK && tag == <declare>)
            return _.finish_managed_declaration(result, _.token);
          return result;
      }
      case %(dstrdecl ?base (targets *targets) ?source): {
        if (context != AST_BLOCK) goto construction_error;
        Array declarators = [];
        foreach (Var target, targets) declarators.push(%(bind $target ()));
        List declaration = _.bind_syntax(
          %(declare $base
              (bindings @{declarators.list_free()})),
          context, _.return_type
        );
        match (declaration)
          case %(declare ?bound_base (bindings *bindings)): {
            Array bound_targets = [];
            foreach (List binding, bindings)
              match (binding)
                case %(bind ?name ?): bound_targets.push(name);
            return %(dstrdecl $bound_base
                     (targets @{bound_targets.list_free()})
                     ${_.resolve_expression(source, _.token)});
          }
      }
      case %(dstrdecl (params *parameters) ?source): {
        if (context != AST_BLOCK) goto construction_error;
        Array bound_parameters = [];
        foreach (List parameter, parameters)
          match (parameter)
            case %(param ?base (!set ?declarator (bind ? ?))): {
              List declaration = _.bind_syntax(
                %(declare $base (bindings $declarator)),
                context, _.return_type);
              match (declaration)
                case %(declare ?bound_base (bindings ?binding)):
                  bound_parameters.push(%( param $bound_base $binding ));
            }
        return %(dstrdecl (params @{bound_parameters.list_free()})
                 ${_.resolve_expression(source, _.token)});
      }
      case %(!set ?function
             (function ?return_type
               (bind ?function_name
                 ((fnmod (params *parameter_values)) *return_modifiers))
               ?body)): {
        if (context != AST_UNIT) goto construction_error;
        Array parameters = [];
        _.sym.push_new_scope();
        {
          defer _.params = _.sym.pop_scope();
          foreach (Var value, parameter_values) {
            foreach (Var row, _.evaluate_macro_rows(value)) match (row) {
              case %(...): parameters.push(row);
              case %(param ?base (!set ?declarator (bind ? ?))):
                parameters.push(
                  _finish_parameter(_, base, declarator, NULL, NULL, NULL));
            }
          }
        }
        List parameter_list = parameters.list_free();
        List declarator = %(
          bind $function_name
            ((fnmod (params @parameter_list)) @return_modifiers)
        );
        List declaration = _.bind_syntax(
          %(declare $return_type (bindings $declarator)),
          context, _.return_type);
        if (_.shallow) {
          match (declaration)
            case %(declare ?type (bindings (bind ?binding ?))): {
              String name = binding_identity_spelling(binding);
              // A static definition stays in its unit, as in source.
              if (type.type().is_static())
                _.sym.mark_static(%(function $name));
              else _.fn_defs[name] = 1;
              _.record_declaration_visibility(declaration);
            }
          return %(declaration-function $declaration $body
                    ${_.freeze_declaration_syntax(_.macro_stack)});
        }
        return _finish_function(_, declaration, body);
      }
      case %(!set ?node ((!or protocol adopt meta-protocol) *)):
        if (context == AST_UNIT)
          return _.publish_protocol_node(node, _.token, NULL);
      case %(!set ?definition (macrodef *)): {
        List macro_definition = definition;
        if (macro_definition.assoc(<local>).int()) {
          if (context == AST_BLOCK) {
            _.sym.define_macro(
              macro_definition.assoc(<name>), macro_definition);
            return %(seq);
          }
        }
        else if (context == AST_UNIT)
          return _.publish_macro_definition_node(macro_definition);
      }
      case %(preproc ?(String directive)): {
        if (context != AST_UNIT && context != AST_BLOCK)
          goto construction_error;
        _.update_source_visibility(%($input));
        return input;
      }
      case %(at ?origin ?node): {
        List bound = _.bind_syntax(node, context, _.return_type);
        match (bound) case %(seq ?only): bound = only;
        Var anchor = origin == <m-origin> ? _.origin : origin;
        return %(at $anchor $bound);
      }
      case %(return):
        if (statement_position) return _.finish_return_statement(NULL);
      case %(return ? ?expression):
        if (statement_position) return _.finish_return_statement(expression);
      case %((!or break continue default empty)):
        if (statement_position) return input;
      case %(case ?expression):
        if (statement_position)
          return %(case ${_.resolve_expression(expression, _.token)});
      case %((!set ?tag (!or goto label)) ?name):
        if (statement_position) return %($tag $name);
      case %(stmnt ?expression):
        if (statement_position)
          return %(stmnt ${_.resolve_expression(expression, _.token)});
      case %(defer ?body):
        if (statement_position)
          return %(defer ${_.bind_syntax(
            body, AST_STATEMENT, _.return_type
          )});
      case %(do ?body ?condition):
        if (statement_position)
          return %(do
            ${_.bind_syntax(body, AST_STATEMENT, _.return_type)}
            ${_.resolve_expression(condition, _.token)});
      case %(while ?condition ?body):
        if (statement_position)
          return %(while
            ${_.resolve_expression(condition, _.token)}
            ${_.bind_syntax(body, AST_STATEMENT, _.return_type)});
      case %(switch ?expression ?body):
        if (statement_position)
          return %(switch
            ${_.resolve_expression(expression, _.token)}
            ${_.bind_syntax(body, AST_STATEMENT, _.return_type)});
      case %(if ?condition ?ontrue):
        if (statement_position)
          return %(if
            ${_.resolve_expression(condition, _.token)}
            ${_.bind_syntax(ontrue, AST_STATEMENT, _.return_type)});
      case %(if ?condition ?ontrue ?onfalse):
        if (statement_position)
          return %(if
            ${_.resolve_expression(condition, _.token)}
            ${_.bind_syntax(ontrue, AST_STATEMENT, _.return_type)}
            ${_.bind_syntax(onfalse, AST_STATEMENT, _.return_type)});
      case %(for ?init ?condition ?increment ?body): {
        if (!statement_position) goto construction_error;
        _.sym.push_new_scope();
        defer _.sym.pop_scope();
        if (init is <list>) {
          List node = init;
          init = node.car() == <decl>
               ? _.bind_syntax(node, AST_BLOCK, _.return_type)
               : _.resolve_expression(node, _.token);
        }
        if (condition is <list>)
          condition = _.resolve_expression(condition, _.token);
        if (increment is <list>)
          increment = _.resolve_expression(increment, _.token);
        return %(for $init $condition $increment
          ${_.bind_syntax(body, AST_STATEMENT, _.return_type)});
      }
      case %(raise ?code (args *details)): {
        if (!statement_position) goto construction_error;
        Array bound = [];
        foreach (List detail, details)
          bound.push(_.resolve_expression(detail, _.token));
        return %(raise ${_.resolve_expression(code, _.token)}
                       (args @{bound.list_free()}));
      }
      case %(catchcases ?arms): {
        if (context != AST_STATEMENT) goto construction_error;
        Array bound = [];
        foreach (List arm, arms.list()) {
          List pattern = arm.car();
          _.begin_catch_arm(pattern, _.token);
          {
            defer _.sym.pop_scope();
            bound.push(%(
              $pattern
              ${_.bind_syntax(arm.cadr(), AST_STATEMENT, _.return_type)}
            ));
          }
        }
        return %(catchcases ${bound.list_free()});
      }
      case %(try ?body ?catches ?cleanup): {
        if (!statement_position) goto construction_error;
        if (catches is <list> && catches.list())
          catches = _.bind_syntax(
            catches, AST_STATEMENT, _.return_type);
        if (cleanup is <list> && cleanup.list())
          cleanup = _.bind_syntax(
            cleanup, AST_STATEMENT, _.return_type);
        return %(try
          ${_.bind_syntax(body, AST_STATEMENT, _.return_type)}
          $catches $cleanup);
      }
      case %(match ?subject ?cases): {
        if (!statement_position) goto construction_error;
        Array bound = [];
        foreach (List row, cases.list()) {
          if (row.car() == <preproc>) {
            bound.push(row);
            continue;
          }
          List pattern = row.car();
          int binds = pattern !== %(*);
          if (binds) pattern = _.resolve_expression(pattern, _.token);
          _.begin_match_arm(pattern, _.token, binds);
          {
            defer _.sym.pop_scope();
            List body = row.cadr();
            match (body) {
              case %(guarded ?statements):
                body = %(guarded ${_.bind_syntax(
                  statements, AST_STATEMENT, _.return_type)});
              default:
                body = _.bind_syntax(body, AST_STATEMENT, _.return_type);
            }
            bound.push(%($pattern $body));
          }
        }
        return %(match ${_.resolve_expression(subject, _.token)}
                       ${bound.list_free()});
      }
      case %(block *children): {
        if (!statement_position) goto construction_error;
        Array fields = [];
        _.sym.push_new_scope();
        {
          defer _.sym.pop_scope();
          foreach (Var child, children) {
            List bound = _.bind_syntax(child, AST_BLOCK, _.return_type);
            if (bound.car() == <seq>)
              foreach (Var item, bound.cdr()) fields.push(item);
            else fields.push(bound);
          }
        }
        return %(block @{fields.list_free()});
      }
      case %(group *children): {
        if (!statement_position) goto construction_error;
        Array items = [];
        foreach (Var child, children)
          items.push(_.bind_syntax(child, AST_BLOCK, _.return_type));
        return %(group @{items.list_free()});
      }
    }
  construction_error:
    _.report_error(
      <parse>, "syntax cannot be constructed at this position",
      _.token, NULL);
  }
}
