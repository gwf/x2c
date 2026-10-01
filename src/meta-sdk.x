/*  meta-sdk.x -- the compiler's answers to `lib/meta.x` operations

    Copyright (c) 2026 Gary William Flake.

    Compile-time code asks the compiler about syntax, types, names, and
    source through the operations `lib/meta.x` declares, and the built-in
    macros ask through their own entries here. A native operation has no
    Compiler parameter, so each answer reads the running call's
    `MetaContext`, which the evaluations in `macros.x` install for their
    extent. An operation that cannot answer reports at the active
    invocation and never returns.
*/

#pragma once
$(import "../lib/private-keywords.xmacro")
#include "compiler.x"

/** What the running compile-time call answers from. `expander` is the
    compiler of the active macro expansion, `definition_file` the source of
    its definition, `captures` its complete captured syntax by identity, and
    `has_bindings` whether it bound captured values. `evaluator` is the
    compiler evaluating Lisp and `site` where that evaluation stands, which
    a nested import changes without an expansion. Each evaluation installs
    its part with `$let`, so a captured entry is valid only while its
    expansion is active. */
typedef struct MetaContext {
  Compiler expander, evaluator;
  String definition_file;
  Map captures;
  int has_bindings;
  Token site;
} MetaContext;

#pragma private
$(import "../src/grammar.xmacro")
#include "macros.x"
#include "meta.x"
#include <limits.h>
#include <stdint.h>
#include <sys/stat.h>

// the running call

static MetaContext active;

/** Returns the context of the running compile-time call, which an
    evaluation changes with `$let` for its own extent. */
MetaContext *MetaContext.current(void) => &active;

/** Returns the compiler running the current compile-time call. A slot
    function compiled into the compiler reads its facts through it. */
Compiler Compiler.expanding(void) =>
  active.expander ? active.expander : active.evaluator;

// syntax queries

/** Answers `x2c.syntax.type`, declared in `lib/meta.x`. */
List x2c_syntax_type(List value) {
  _sdk_guard("x2c.syntax.type");
  match (value) {
    case %(expr ? ?): {
      Type type = value.cadr();
      return type.canonicalize();
    }
    case %(param ? ?):  return value.type_from_ast().canonicalize();
    case %((!or declare decl typedef) *):
      return value.type_from_ast().canonicalize();
  }
  List binding = NULL;
  if (binding_identity_try_parts(value, NULL, NULL)) binding = value;
  else
    match (value) {
      case $source_identifier_content(%((*) *)):
        binding = value.cadr();
      case %(bind (*) *): binding = value.cadr();
    }
  if (binding) {
    Type type = _sdk_binding_type(binding);
    return type.canonicalize();
  }
  return value.type().canonicalize();
}

static List _sdk_binding_type(List binding) =>
  active.expander.semantic_binding_facts()[
    %(type $binding)
  ];

/** Answers `x2c.protocol.member`, declared in `lib/meta.x`. */
List x2c_protocol_member(List participant, List base, String member) {
  List conformance =
    active.expander.protocol_members_for(participant, base);
  if (!conformance) return %();
  foreach (List row, conformance.last().list().cdr()) {
    (String row_member, Symbol status, String source, Type signature,
     Symbol default_kind, Type template) = row;
    (void) default_kind; (void) template;
    if (status != <implmntd> || row_member != member) continue;
    List binding = active.expander.sym.lookup(%($source), NULL);
    if (binding) return %(expr $signature (ident $binding));
    return %();
  }
  return %();
}

/** Answers `x2c.method.resolve`, declared in `lib/meta.x`. */
List x2c_method_resolve(List type_value, String name) {
  _sdk_guard("x2c.method.resolve");
  if (!name.is_identifier())
    MetaContext.reject(
      "x2c.method.resolve requires an identifier String",
      %("value: ${name.repr()}"));
  Type type = type_value;
  List resolution = active.expander.resolve_postfix_member(
    type, %($name), <.>, 1);
  match (resolution) {
    case %(ambiguous *packages): {
      Array notes = [];
      foreach (String package, packages) notes.push(%"package: '$package'");
      String owner = type.base_type().car().str();
      MetaContext.reject(
        %"method '$owner.$name' is provided by multiple imported packages",
        notes.list_free());
    }
    case %(method ?binding ?signature):
      return %(expr $signature (ident $binding));
  }
  return %();
}

static Var _sdk_bindings(List declaration) {
  Array result = [];
  match (declaration)
    case %((!or declare decl typedef) ? (bindings *bindings)):
      foreach (List binding, bindings)
        match (binding) {
          case %(bind (!set ?identity (binding ? ?)) *): {
            List bound = identity;
            List type = _sdk_binding_type(bound);
            result.push(%(expr $type (ident $bound)));
          }
          case %(op = (bind (!set ?identity (binding ? ?)) *) ?): {
            List bound = identity;
            List type = _sdk_binding_type(bound);
            result.push(%(expr $type (ident $bound)));
          }
          case %(bind ?name ?mods): {
            List row = %(
              declare ${declaration.cadr()}
                (bindings (bind $name $mods))
            );
            result.push(%(expr ${row.type_from_ast()} (ident $name)));
          }
          case %(op = (bind ?name ?mods) ?): {
            List row = %(
              declare ${declaration.cadr()}
                (bindings (bind $name $mods))
            );
            result.push(%(expr ${row.type_from_ast()} (ident $name)));
          }
        }
  return result.list_free();
}

/* This reads the symbol table only, so any compile-time Lisp evaluation
   may call it, including one outside a macro expansion. */
static Var _sdk_function_reference(String name) {
  Compiler c = active.evaluator;
  if (!c) raise %(bad-state (operation "_x2c.function.reference"));
  Type type = NULL;
  List binding = c.sym.lookup(%($name), type);
  if (!binding || !type || !type.is_function()) return %();
  return %(expr $type (ident $binding));
}

// type queries

/** Answers `x2c.type.integral?`, declared in `lib/meta.x`. */
int x2c_type_is_integral(List value) => value.type().is_integral();

/** Answers `x2c.type.pointer?`, declared in `lib/meta.x`. */
int x2c_type_is_pointer(List value) =>
  value.type().canonicalize().is_pointer();

/** Answers `x2c.type.element`, declared in `lib/meta.x`. */
List x2c_type_element(List value) =>
  value.type().canonicalize().dereference().canonicalize();

/** Answers `x2c.type.parameters`, declared in `lib/meta.x`. */
List x2c_type_parameters(List value) =>
  _sdk_function_type_parameters(value.type().canonicalize());

static List _sdk_function_type_parameters(Type type) {
  while (type.is_pointer() || type.is_array()) type = type.dereference();
  return type.match_replace(%((func ?params) *), <?params>);
}

/** Answers `x2c.type.return`, declared in `lib/meta.x`. */
List x2c_type_return(List value) =>
  value.type().canonicalize().apply().canonicalize();

/** Answers `x2c.type.parts`, declared in `lib/meta.x`. */
List x2c_type_parts(List value) => value.type().declaration_parts();

/** Answers `x2c.type.reverse-name`, declared in `lib/meta.x`. */
String x2c_type_reverse_name(String base, String participant) {
  _sdk_guard("x2c.type.reverse-name");
  return active.expander.reverse_converter_spelling(base, "", participant);
}

/** Answers `x2c.type.resolve`, declared in `lib/meta.x`. */
List x2c_type_resolve(List value) {
  _sdk_guard("x2c.type.resolve");
  return active.expander.sym.resolve_key(value).type_from_ast();
}

/** Answers `x2c.type.layout`, declared in `lib/meta.x`. */
List x2c_type_layout(List value) {
  _sdk_guard("x2c.type.layout");
  Type type = active.expander.sym.resolve_key(value).type_from_ast();
  return active.expander.sym.field_order(type).cdr();
}

/** Answers `x2c.type.value?`, declared in `lib/meta.x`. */
int x2c_type_is_value(List value) {
  _sdk_guard("x2c.type.value?");
  Type type = value.type().canonicalize();
  match (type) case %((bitfield ?) *rest): type = rest;
  foreach (String name, %("Symbol" "Var" "Atom" "String" "List"))
    if (active.expander.sym.is_named_value_type(type, name)) return 1;
  return active.expander.sym.resolve_key(type).is_number();
}

/** Answers `x2c.type.tag-name`, declared in `lib/meta.x`. */
Symbol x2c_type_tag_name(String name) {
  _sdk_guard("x2c.type.tag-name");
  String file = active.expander.source_path(active.expander.filename);
  file = active.expander.display_path(file);
  String identity = %"$file:$name";
  unsigned hash = identity.hash();
  const char *alphabet = "abcdefghijklmnopqrstuvwxyz*+?!-";
  char encoded[9] = { 'c' };
  for (int i = 1; i < 8; i++) {
    encoded[i] = alphabet[hash % 31];
    hash /= 31;
  }
  return Symbol.new(encoded);
}

/** Answers `x2c.type.fields`, declared in `lib/meta.x`. */
List x2c_type_fields(List value) {
  _sdk_guard("x2c.type.fields");
  Type type = value;
  type = type.canonicalize();
  Type resolved = active.expander.sym.resolve_key(type);
  if (!resolved || !resolved.is_aggregate_tag())
    MetaContext.reject(
      "x2c.type.fields requires a struct or union Type",
      %("value: ${value.repr()}"));
  List metadata = active.expander.sym.field_order(resolved);
  if (!metadata)
    MetaContext.reject(
      "x2c.type.fields requires a complete struct or union Type",
      %("value: ${value.repr()}"));
  Array named = [];
  foreach (List row, metadata.cdr()) if (row.car().truth()) named.push(row);
  return named.list_free();
}

// names and functions

/** Answers `x2c.binding.spelling`, declared in `lib/meta.x`. */
String x2c_binding_spelling(Var syntax) {
  _sdk_guard("x2c.binding.spelling");
  if (syntax is <string>) {
    String spelling = syntax;
    if (spelling.is_identifier()) return spelling;
    MetaContext.reject(
      "x2c.binding.spelling requires an identifier spelling",
      %("value: ${syntax.repr()}" ));
  }
  if (syntax is not <list> || syntax.is_nil())
    MetaContext.reject(
      "x2c.binding.spelling requires binding syntax",
      %("value: ${syntax.repr()}" ));
  List value = syntax;
  match (value)
    case %(expr ? (? *)): value = value.caddr();
  match (value) {
    case $source_identifier_content(%((*))):
      value = value.cadr();
    case %(bind (*) ?):    value = value.cadr();
  }
  match (value)
    case %((!is ?name type string)): return name;
  return _binding_spelling(value, syntax);
}

static String _binding_spelling(List value, Var syntax) {
  int identity = 0, String spelling = NULL;
  match (value)
    case %(binding ?id (!is ? type string)):
      if (!id.is_integer() || id.integer() > INT_MAX)
        MetaContext.reject(
          "x2c.binding.spelling requires a known binding",
          %("binding: ${value.repr()}"));
  if (!binding_identity_try_parts(value, identity, spelling))
    MetaContext.reject(
      "x2c.binding.spelling requires an identifier or binding",
      %("value: ${syntax.repr()}" ));
  Var registered =
    active.expander.semantic_binding_facts()[%(known $identity)];
  if (registered is not <string> || !registered.string().equal(spelling))
    MetaContext.reject(
      "x2c.binding.spelling requires a known binding",
      %("binding: ${value.repr()}" ));
  return spelling;
}

/** Answers `x2c.ident`, declared in `lib/meta.x`. */
List x2c_ident(String spelling) {
  _sdk_guard("x2c.ident");
  if (!spelling.is_identifier()) MetaContext.reject(
    "x2c.ident requires an identifier spelling",
    %("value: ${spelling.repr()}" ));
  return %("x2c.ident" $spelling);
}

static Var _sdk_ident_unique(String stem) {
  _sdk_guard("_x2c.name.unique");
  if (!stem.is_identifier()) MetaContext.reject(
    "_x2c.name.unique requires an identifier stem",
    %("value: ${stem.repr()}" ));
  String spelling = active.expander.fresh_name(%"macro_$stem");
  return active.expander.sym.introduce(spelling);
}

/** Answers `x2c.meta.definition.hashes`, declared in `lib/meta.x`. */
Map x2c_meta_definition_hashes(void) {
  _sdk_guard("x2c.meta.definition.hashes");
  return active.expander.meta_hashes;
}

/** Answers `x2c.function.name`, declared in `lib/meta.x`. */
String x2c_function_name(List function) {
  List identity = function.match_replace(
    %(function ? (bind ?binding ?) ?), <?binding>);
  return x2c_binding_spelling(identity);
}

/** Answers `x2c.function.parameter`, declared in `lib/meta.x`. */
List x2c_function_parameter(List function, String wanted) {
  List parameters = function.match_replace(
    %(function ? (bind ? ((fnmod (params *bound)) *)) ?), %(*bound));
  foreach (List parameter, parameters) {
    match (parameter) {
      case %(param ? (bind ?identity *)):
        if (x2c_binding_spelling(identity) == wanted) {
          Type type = parameter.type_from_ast().canonicalize();
          return %(expr $type (ident $identity));
        }
    }
  }
  MetaContext.reject(
    %"x2c.function.parameter cannot find '$wanted'",
    %("function: ${x2c_function_name(function).repr()}"));
}

/* A native binding stores the same signature as an ordinary Func adapter. */
static List _sdk_native_type(List syntax) {
  match (syntax)
    case %(function ?rtype ?declarator ?):
      return active.expander.func_signature(
        %(declare $rtype (bindings $declarator)).type_from_ast());
  return active.expander.func_signature(x2c_syntax_type(syntax));
}

/* Lisp-built signatures become cached literals of the expanding unit. */
static List _sdk_literal_list(List values) =>
  active.expander.cache_literal_list(values);

static Var _sdk_symbol_set(List values) {
  _sdk_guard("_x2c.symbol-set");
  foreach (Var value, values)
    if (value is not <symbol>)
      MetaContext.reject(
        "_x2c.symbol-set requires Symbols",
        %("value:" ${value.repr()}));
  int duplicate = -1;
  List expression = active.expander.symbol_set_expression(values, duplicate);
  if (duplicate >= 0)
    MetaContext.reject(
      "_x2c.symbol-set requires distinct Symbols",
      %("symbol:" ${values.getindex(duplicate).repr()}));
  return expression;
}

static List _sdk_meta_targets(void) => Compiler.native_meta_targets(NULL);

/* A native module's entry exports the prototypes its own sources declare,
   and a module that declares none is a mistake. */
static List _sdk_meta_declared(List paths) {
  List rows = Compiler.native_meta_targets(paths);
  if (!rows)
    MetaContext.reject(
      "native module sources declare no meta function",
      %("declare each exported function with a bodyless meta prototype"));
  return rows;
}

// source and literals

/** Answers `x2c.source.text`, declared in `lib/meta.x`. */
String x2c_source_text(Var syntax) => _sdk_source_text(syntax);

static Var _sdk_source_text(Var value) {
  match (value) case %((text ?(String text)) (file ?) (syntax ?)): return text;
  _sdk_guard("x2c.source.text");
  Var stored = void;
  Var key = ((ulong) value.u64);
  if (!active.captures ||
      !active.captures.try_get(key, stored))
    MetaContext.reject(
      "x2c.source.text requires complete captured syntax",
      active.has_bindings ? NULL : %("value: ${value.repr()}"));
  List source = stored;
  int begin = source.caddr(), end = source.last();
  return String.new_len(active.expander.text + begin, end - begin);
}

/** Answers `x2c.embed.text`, declared in `lib/meta.x`. */
String x2c_embed_text(Var path) => _sdk_embed_text(path);

static Var _sdk_embed_text(Var requested) {
  Compiler c = active.expander;
  if (!c)
    MetaContext.reject("x2c.embed.text used outside macro expansion", NULL);
  String source_file = active.definition_file, requested_path = NULL;
  if (requested is <string>) requested_path = requested;
  else requested_path = _embed_literal(requested, source_file);
  if (!requested_path.len())
    MetaContext.reject("x2c.embed.text requires a non-empty path", NULL);
  String path = c._embed_path(source_file, requested_path);
  String text = c.sources ? c._embed_source(path) : c._embed_file(path);
  c.deps.merge_translation_dependency(path, "%08x".printf(text.hash()));
  return text;
}

static String Compiler._embed_path(
  Compiler c, String source_file, String requested) {
  if (requested[0] == '/') return c.canonical_path(requested);
  String base = Path.dirname(c.source_path(source_file));
  return c.canonical_path(%"$base/$requested");
}

static String _embed_literal(Var requested, String &source_file) {
  Var stored = void, syntax = requested;
  match (requested)
    case %((text ?) (file ?(String file)) (syntax ?carried)): {
      syntax = carried;
      stored = %(source $file);
    }
  if (stored is void && active.captures)
    active.captures.try_get(((ulong) requested.u64), stored);
  String requested_path = NULL;
  if (stored is void || !_literal_string(syntax, requested_path))
    MetaContext.reject(
      "x2c.embed.text requires a String or captured String literal",
      %("value: ${requested.repr()}"));
  List source = stored;
  source_file = source.cadr();
  return requested_path;
}

static String Compiler._embed_source(Compiler c, String path) {
  String text;
  if (!c.read_source(path, text))
    MetaContext.reject(
      "cannot read embedded text",
      %("path: ${c.display_path(path)}"));
  return text;
}

static String Compiler._embed_file(Compiler c, String path) {
  File file = c._open_embed_file(path);
  return c._read_embed_file(path, file);
}

static File Compiler._open_embed_file(Compiler c, String path) {
  struct stat info;
  if (!stat(path, &info) && !S_ISREG(info.st_mode))
    MetaContext.reject(
      "embedded text is not a regular file",
      %("path: ${c.display_path(path)}"));
  File file = NULL, int open_failed = 0;
  try file = path.open("r");
  catch %((!or not-found io-fail) *): open_failed = 1;
  if (open_failed)
    MetaContext.reject(
      "cannot open embedded text",
      %("path: ${c.display_path(path)}"));
  if (file.stat(&info) || !S_ISREG(info.st_mode)) {
    file.close();
    MetaContext.reject(
      "embedded text is not a regular file",
      %("path: ${c.display_path(path)}"));
  }
  if ((uintmax_t) info.st_size >= INT_MAX) {
    file.close();
    MetaContext.reject(
      "embedded text exceeds the String size limit",
      %("path: ${c.display_path(path)}"));
  }
  return file;
}

static String Compiler._read_embed_file(Compiler c, String path, File file) {
  String result = NULL;
  int read_failed = 0, embedded_nul = 0, size_overflow = 0;
  try result = file.string_close();
  catch %(io-fail *): read_failed = 1;
  catch %(bad-arg *): embedded_nul = 1;
  catch %(size-limit *): size_overflow = 1;
  if (read_failed)
    MetaContext.reject(
      "cannot read embedded text",
      %("path: ${c.display_path(path)}"));
  if (embedded_nul)
    MetaContext.reject(
      "embedded text contains an embedded NUL",
      %("path: ${c.display_path(path)}"));
  if (size_overflow)
    MetaContext.reject(
      "embedded text exceeds the String size limit",
      %("path: ${c.display_path(path)}"));
  return result;
}

static int _literal_string(Var syntax, String &value) {
  match (syntax)
    case %(expr ? ?content): {
      match (content)
        case $source_literal_content(%(? ?source)): {
          if (source is not <string>) break;
          String text = source;
          int quoted = text.len() >= 2 && text[0] == '"' &&
            text[text.len() - 1] == '"';
          int percent_quoted = text.len() >= 3 && text[0] == '%' &&
            text[1] == '"' && text[text.len() - 1] == '"';
          if (quoted || percent_quoted) {
            value = text.parse();
            return 1;
          }
        }
    }
  return 0;
}

/** Answers `x2c.literal.value`, declared in `lib/meta.x`. */
Var x2c_literal_value(Var syntax) {
  _sdk_guard("x2c.literal.value");
  String value = NULL;
  if (_literal_string(syntax, value)) return value;
  match (syntax) case %(expr ? ${$source_literal_content(
      %((int) ?digits))}): {
    if (digits is not <string>) break;
    String text = digits;
    long parsed = 0;
    if (text.try_long(&parsed)) return parsed;
  }
  match (syntax) case %(expr ? ${$source_literal_content(
      %(("Symbol") ? ?tag))}): {
    if (tag is not <symbol>) break;
    Symbol found = tag;
    return found;
  }
  MetaContext.reject(
    "x2c.literal.value requires a String, int, or Symbol literal",
    %("value: ${syntax.repr()}"));
}

// invocations and diagnostics

static Var _sdk_invocation_location(void) {
  if (!active.expander || !active.site)
    MetaContext.reject(
      "x2c invocation location used outside macro expansion", NULL);
  return active.expander.token_location(active.site);
}

/** Answers `x2c.invocation.file`, declared in `lib/meta.x`. */
String x2c_invocation_file(void) =>
  ((List) _sdk_invocation_location()).assoc(<file>);

/** Answers `x2c.invocation.line`, declared in `lib/meta.x`. */
int x2c_invocation_line(void) =>
  ((List) _sdk_invocation_location()).assoc(<line>);

/** Answers `x2c.invocation.column`, declared in `lib/meta.x`. */
int x2c_invocation_column(void) =>
  ((List) _sdk_invocation_location()).assoc(<column>);

/** Answers `x2c.diagnostic.fail`, declared in `lib/meta.x`. */
void x2c_diagnostic_fail(String message, List notes) {
  _sdk_guard("x2c.diagnostic.fail");
  foreach (Var note, notes)
    if (note is not <string>)
      MetaContext.reject(
        "x2c.diagnostic.fail notes must be Strings",
        %("value: ${note.repr()}" ));
  MetaContext.reject(message, notes);
}

/** A warning reports where it is raised and returns, so a macro can keep
   expanding. Failure stays separate because it never returns. */
void x2c_diagnostic_warn(String message, List notes) {
  _sdk_guard("x2c.diagnostic.warn");
  foreach (Var note, notes)
    if (note is not <string>)
      MetaContext.reject(
        "x2c.diagnostic.warn notes must be Strings",
        %("value: ${note.repr()}" ));
  active.expander.report_warning(
    <macro>, message, active.expander.token, notes);
}

// meta parameter descriptions

/** Returns what a `meta` parameter declared `Type` receives for the captured
    syntax `value`: `((name N) (kind K) (type T) (fields F) (methods M))`.
    `T` is the canonical type of `value` and `N` its name, or "" when it has
    none. `K` is `struct`, `union`, `enum`, `pointer`, `scalar`, or `other`,
    `F` lists the `(name type)` rows of a struct or union's named fields,
    and `M` the names of its direct dotted methods. */
List meta_type_description(Var value) {
  Type type = x2c_syntax_type(value);
  Type shape = x2c_type_resolve(type);
  String name = "";
  match (type) {
    case %(?(String own)): name = own;
    case %((!or struct union enum) ?(String own)): name = own;
    default:
      if (_symbol_words(type) && !type.is_pointer()) {
        Array words = [];
        foreach (Var word, type) words.push(word.str());
        name = " ".join(words);
      }
  }
  Var kind = <other>;
  List fields = %();
  match (shape) {
    case %((!or struct union enum) *): kind = shape.car();
    default:
      if (shape.is_pointer()) kind = <pointer>;
      else if (_symbol_words(shape)) kind = <scalar>;
  }
  if (kind == <struct> || kind == <union>) fields = x2c_type_fields(type);
  Compiler c = active.expander;
  Array methods = [];
  foreach (String member, c.postfix_completions(type, <.>))
    match (c.resolve_postfix_member(type, %($member), <.>, 1))
      case %(method * *): methods.push(member);
  return %((name $name) (kind $kind) (type $type) (fields $fields)
           (methods ${methods.list_free()}));
}

/* Whether the type `type` is spelled by keywords alone, such as `(int)`. */
static int _symbol_words(List type) {
  foreach (Var word, type) if (word is not <symbol>) return 0;
  return type != NULL;
}

/** Returns what a `meta` parameter declared `Source` receives for the
    captured syntax `value`: `((text T) (file F) (syntax value))`, where `T`
    is the text the developer wrote and `F` the file it is in. */
List meta_source_description(Var value) {
  String text = _sdk_source_text(value);
  List source = active.captures[((ulong) value.u64)];
  return %((text $text) (file ${source.cadr()}) (syntax $value));
}

// built-in algorithm operations

/** Returns the typed expression naming the function `name`, or an empty
    List when no function of that name is visible. */
List builtin_foreach_reference(String name) => _sdk_function_reference(name);

/** Returns a fresh binding whose spelling starts with `name`. */
Var builtin_foreach_unique(String name) => _sdk_ident_unique(name);

/** Returns `expression` with the iterator chain `foreach` reads completed. */
List builtin_foreach_complete(List expression) =>
  _sdk_iter_chain(expression);

/** Returns the collection `foreach` iterates for `expression`, promoting a
    String literal. */
List builtin_foreach_collection(List expression) =>
  _sdk_string_collection(expression);

/** Returns an expression reading each binding `declaration` declares. */
List builtin_foreach_bindings(List declaration) =>
  _sdk_bindings(declaration);

/** Returns the location of the active macro invocation. */
List builtin_class_location(void) => _sdk_invocation_location();

/** Returns the `Func` signature of the function syntax `function`. */
List binding_native_type(List function) =>
  _sdk_native_type(function);

/** Returns `values` as a cached literal of the expanding unit. */
List binding_literal_list(List values) => _sdk_literal_list(values);

static Var _sdk_iter_chain(List expression) {
  _sdk_guard("private foreach iterator completion");
  return active.expander.complete_iter_chain(expression);
}

static Var _sdk_string_collection(List expression) {
  _sdk_guard("private foreach string conversion");
  return active.expander.promote_string_literal(expression);
}

// rejection

/** Reports `message` and `notes` at the active invocation and never
    returns, so the rejected operation's caller cannot continue with a
    missing answer. With no active invocation it is a bad state. */
void MetaContext.reject(String message, List notes) {
  Compiler c = active.evaluator;
  if (c) c.report_error(<macro>, message, active.site, notes);
  raise %(bad-state (operation "x2c SDK rejection") (why $message));
}

// SDK operations reject use outside an active expansion.
static void _sdk_guard(String operation) {
  if (!active.expander)
    MetaContext.reject(%"$operation used outside macro expansion", NULL);
}

// lisp primitives

/** Binds the internal primitives the compile-time SDK library wraps into
    `lisp`, under their `_x2c.` names. */
void Compiler.bind_sdk_primitives(Lisp lisp) {
  $lisp.bind(lisp, "_x2c.function.reference", _sdk_function_reference);
  $lisp.bind(lisp, "_x2c.function.native-type", _sdk_native_type);
  $lisp.bind(lisp, "_x2c.literal.list", _sdk_literal_list);
  $lisp.bind(lisp, "_x2c.native-meta.targets", _sdk_meta_targets);
  $lisp.bind(lisp, "_x2c.native-meta.declared", _sdk_meta_declared);
  $lisp.bind(lisp, "_x2c.foreach.complete-iter-chain", _sdk_iter_chain);
  $lisp.bind(lisp, "_x2c.foreach.string-collection", _sdk_string_collection);
  $lisp.bind(lisp, "_x2c.source.text", _sdk_source_text);
  $lisp.bind(lisp, "_x2c.embed.text", _sdk_embed_text);
  $lisp.bind(lisp, "_x2c.invocation.location", _sdk_invocation_location);
  $lisp.bind(lisp, "_x2c.symbol-set", _sdk_symbol_set);
  $lisp.bind(lisp, "_x2c.name.unique", _sdk_ident_unique);
  $lisp.bind(lisp, "_x2c.declaration.bindings", _sdk_bindings);
}
