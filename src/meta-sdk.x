/*  meta-sdk.x -- the compiler's answers to `lib/meta.x` operations

    Copyright (c) 2026 Gary William Flake.
*/

#pragma once
$(import "../lib/private-keywords.xmacro")
#include "compiler.x"

#pragma private
$(import "../src/grammar.xmacro")
#include "macros.x"
#include "meta.x"
#include <limits.h>
#include <stdint.h>
#include <sys/stat.h>

// sdk rejection

/* A rejection reports at the active invocation and never returns, so the
   rejected operation's caller cannot continue with a missing answer. With
   no active invocation it is a bad state. */
static void _sdk_reject(String message, List notes) {
  Compiler compiler = lisp_compiler;
  if (compiler)
    compiler.report_error(<macro>, message, lisp_site, notes);
  raise %(bad-state (operation "x2c SDK rejection") (why $message));
}

// SDK operations reject use outside an active expansion.
static void _sdk_guard(String operation) {
  if (!sdk_compiler)
    _sdk_reject(%"$operation used outside macro expansion", NULL);
}

// sdk syntax queries

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
  sdk_compiler.semantic_binding_facts()[
    %(type $binding)
  ];

/** Answers `x2c.protocol.member`, declared in `lib/meta.x`. */
List x2c_protocol_member(
  List participant, List base, String member) {
  List conformance =
    sdk_compiler.protocol_members_for(participant, base);
  if (!conformance) return %();
  foreach (List row, conformance.last().list().cdr()) {
    (String row_member, Symbol status, String source, Type signature,
     Symbol default_kind, Type template) = row;
    (void) default_kind; (void) template;
    if (status != <implmntd> || row_member != member) continue;
    List binding = sdk_compiler.sym.lookup(%($source), NULL);
    if (binding) return %(expr $signature (ident $binding));
    return %();
  }
  return %();
}

/** Answers `x2c.method.resolve`, declared in `lib/meta.x`. */
List x2c_method_resolve(List type_value, String name) {
  _sdk_guard("x2c.method.resolve");
  if (!name.is_identifier())
    _sdk_reject(
      "x2c.method.resolve requires an identifier String",
      %("value: ${name.repr()}"));
  Type type = type_value;
  List resolution = sdk_compiler.resolve_postfix_member(
    type, %($name), <.>, 1);
  match (resolution) {
    case %(ambiguous *packages): {
      Array notes = [];
      foreach (String package, packages)
        notes.push(%"package: '$package'");
      String owner = type.base_type().car().str();
      _sdk_reject(
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

/* This reads the symbol table only, so it serves any compile-time Lisp
   evaluation, not just an active macro expansion. */
static Var _sdk_function_reference(String name) {
  Compiler compiler = lisp_compiler;
  if (!compiler) raise %(bad-state (operation "_x2c.function.reference"));
  Type type = NULL;
  List binding = compiler.sym.lookup(%($name), type);
  if (!binding || !type || !type.is_function()) return %();
  return %(expr $type (ident $binding));
}

// sdk type queries

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
  return sdk_compiler.reverse_converter_spelling(
    base, "", participant);
}

/** Answers `x2c.type.resolve`, declared in `lib/meta.x`. */
List x2c_type_resolve(List value) {
  _sdk_guard("x2c.type.resolve");
  return sdk_compiler.sym.resolve_key(value).type_from_ast();
}

/** Answers `x2c.type.layout`, declared in `lib/meta.x`. */
List x2c_type_layout(List value) {
  _sdk_guard("x2c.type.layout");
  Type type = sdk_compiler.sym.resolve_key(value).type_from_ast();
  return sdk_compiler.sym.field_order(type).cdr();
}

/** Answers `x2c.type.value?`, declared in `lib/meta.x`. */
int x2c_type_is_value(List value) {
  _sdk_guard("x2c.type.value?");
  Type type = value.type().canonicalize();
  match (type) case %((bitfield ?) *rest): type = rest;
  foreach (String name, %("Symbol" "Var" "Atom" "String" "List"))
    if (sdk_compiler.sym.is_named_value_type(type, name)) return 1;
  return sdk_compiler.sym.resolve_key(type).is_number();
}

/** Answers `x2c.type.tag-name`, declared in `lib/meta.x`. */
Symbol x2c_type_tag_name(String name) {
  _sdk_guard("x2c.type.tag-name");
  String file = _source_file(sdk_compiler, sdk_compiler.filename);
  file = sdk_compiler.display_path(file);
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
  Type resolved = sdk_compiler.sym.resolve_key(type);
  if (!resolved || !resolved.is_aggregate_tag())
    _sdk_reject(
      "x2c.type.fields requires a struct or union Type",
      %("value: ${value.repr()}"));
  List metadata = sdk_compiler.sym.field_order(resolved);
  if (!metadata)
    _sdk_reject(
      "x2c.type.fields requires a complete struct or union Type",
      %("value: ${value.repr()}"));
  Array named = [];
  foreach (List row, metadata.cdr())
    if (row.car().truth()) named.push(row);
  return named.list_free();
}

// sdk names and functions

/** Answers `x2c.binding.spelling`, declared in `lib/meta.x`. */
String x2c_binding_spelling(Var syntax) {
  _sdk_guard("x2c.binding.spelling");
  if (syntax is <string>) {
    String spelling = syntax;
    if (spelling.is_identifier()) return spelling;
    _sdk_reject(
      "x2c.binding.spelling requires an identifier spelling",
      %("value: ${syntax.repr()}" ));
  }
  if (syntax is not <list> || syntax.is_nil())
    _sdk_reject(
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
        _sdk_reject(
          "x2c.binding.spelling requires a known binding",
          %("binding: ${value.repr()}"));
  if (!binding_identity_try_parts(value, identity, spelling))
    _sdk_reject(
      "x2c.binding.spelling requires an identifier or binding",
      %("value: ${syntax.repr()}" ));
  Var registered =
    sdk_compiler.semantic_binding_facts()[%(known $identity)];
  if (registered is not <string> || !registered.string().equal(spelling))
    _sdk_reject(
      "x2c.binding.spelling requires a known binding",
      %("binding: ${value.repr()}" ));
  return spelling;
}

/** Answers `x2c.ident`, declared in `lib/meta.x`. */
List x2c_ident(String spelling) {
  _sdk_guard("x2c.ident");
  if (!spelling.is_identifier()) _sdk_reject(
    "x2c.ident requires an identifier spelling",
    %("value: ${spelling.repr()}" ));
  return %("x2c.ident" $spelling);
}

static Var _sdk_ident_unique(String stem) {
  _sdk_guard("_x2c.name.unique");
  if (!stem.is_identifier()) _sdk_reject(
    "_x2c.name.unique requires an identifier stem",
    %("value: ${stem.repr()}" ));
  String spelling = sdk_compiler.fresh_name(%"macro_$stem");
  return sdk_compiler.sym.introduce(spelling);
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
  _sdk_reject(
    %"x2c.function.parameter cannot find '$wanted'",
    %("function: ${x2c_function_name(function).repr()}"));
}

/* A native binding stores the same signature as an ordinary Func adapter. */
static List _sdk_native_type(List syntax) {
  match (syntax)
    case %(function ?rtype ?declarator ?):
      return sdk_compiler.func_signature(
        %(declare $rtype (bindings $declarator)).type_from_ast());
  return sdk_compiler.func_signature(x2c_syntax_type(syntax));
}

/* Lisp-built signatures become cached literals of the expanding unit. */
static List _sdk_literal_list(List values) =>
  sdk_compiler.cache_literal_list(values);

static Var _sdk_symbol_set(List values) {
  _sdk_guard("_x2c.symbol-set");
  foreach (Var value, values)
    if (value is not <symbol>)
      _sdk_reject(
        "_x2c.symbol-set requires Symbols",
        %("value:" ${value.repr()}));
  int duplicate = -1;
  List expression = sdk_compiler.symbol_set_expression(
    values, duplicate);
  if (duplicate >= 0)
    _sdk_reject(
      "_x2c.symbol-set requires distinct Symbols",
      %("symbol:" ${values.getindex(duplicate).repr()}));
  return expression;
}

// sdk source and literals

/** Answers `x2c.source.text`, declared in `lib/meta.x`. */
String x2c_source_text(Var syntax) => _sdk_source_text(syntax);

static Var _sdk_source_text(Var value) {
  match (value) case %((text ?(String text)) (file ?) (syntax ?)): return text;
  _sdk_guard("x2c.source.text");
  Var stored = void;
  Var key = ((ulong) value.u64);
  if (!sdk_captures ||
      !sdk_captures.try_get(key, stored))
    _sdk_reject(
      "x2c.source.text requires complete captured syntax",
      sdk_references ? NULL : %("value: ${value.repr()}"));
  List source = stored;
  int begin = source.caddr(), end = source.last();
  return String.new_len(sdk_compiler.text + begin, end - begin);
}

/** Answers `x2c.embed.text`, declared in `lib/meta.x`. */
String x2c_embed_text(Var path) => _sdk_embed_text(path);

static Var _sdk_embed_text(Var requested) {
  Compiler compiler = sdk_compiler;
  if (!compiler)
    _sdk_reject(
      "x2c.embed.text used outside macro expansion", NULL);
  String source_file = sdk_file, requested_path = NULL;
  if (requested is <string>) requested_path = requested;
  else requested_path = _embed_literal(requested, source_file);
  if (!requested_path.len())
    _sdk_reject(
      "x2c.embed.text requires a non-empty path", NULL);
  String path = _embed_path(compiler, source_file, requested_path);
  if (compiler.sources) return _embed_source(compiler, path);
  return _embed_file(compiler, path);
}

static String _embed_literal(Var requested, String &source_file) {
  Var stored = void, syntax = requested;
  match (requested)
    case %((text ?) (file ?(String file)) (syntax ?carried)): {
      syntax = carried;
      stored = %(source $file);
    }
  if (stored is void && sdk_captures)
    sdk_captures.try_get(((ulong) requested.u64), stored);
  String requested_path = NULL;
  if (stored is void || !_literal_string(syntax, requested_path))
    _sdk_reject(
      "x2c.embed.text requires a String or captured String literal",
      %("value: ${requested.repr()}"));
  List source = stored;
  source_file = source.cadr();
  return requested_path;
}

static String _embed_source(Compiler compiler, String path) {
  String text;
  if (!compiler.read_source(path, text))
    _sdk_reject(
      "cannot read embedded text",
      %("path: ${compiler.display_path(path)}"));
  compiler.deps.merge_translation_dependency(
    path, "%08x".printf(text.hash()));
  return text;
}

static String _embed_file(Compiler compiler, String path) {
  File file = _open_embed_file(compiler, path);
  String result = _read_embed_file(compiler, path, file);
  String content_hash = "%08x".printf(result.hash());
  compiler.deps.merge_translation_dependency(path, content_hash);
  return result;
}

static File _open_embed_file(Compiler compiler, String path) {
  struct stat info;
  if (!stat(path, &info) && !S_ISREG(info.st_mode))
    _sdk_reject(
      "embedded text is not a regular file",
      %("path: ${compiler.display_path(path)}"));
  File file = NULL, int open_failed = 0;
  try file = path.open("r");
  catch %((!or not-found io-fail) *): open_failed = 1;
  if (open_failed)
    _sdk_reject(
      "cannot open embedded text",
      %("path: ${compiler.display_path(path)}"));
  if (file.stat(&info) || !S_ISREG(info.st_mode)) {
    file.close();
    _sdk_reject(
      "embedded text is not a regular file",
      %("path: ${compiler.display_path(path)}"));
  }
  if ((uintmax_t) info.st_size >= INT_MAX) {
    file.close();
    _sdk_reject(
      "embedded text exceeds the String size limit",
      %("path: ${compiler.display_path(path)}"));
  }
  return file;
}

static String _read_embed_file(Compiler compiler, String path, File file) {
  String result = NULL;
  int read_failed = 0, embedded_nul = 0, size_overflow = 0;
  try result = file.string_close();
  catch %(io-fail *): read_failed = 1;
  catch %(bad-arg *): embedded_nul = 1;
  catch %(size-limit *): size_overflow = 1;
  if (read_failed)
    _sdk_reject(
      "cannot read embedded text",
      %("path: ${compiler.display_path(path)}"));
  if (embedded_nul)
    _sdk_reject(
      "embedded text contains an embedded NUL",
      %("path: ${compiler.display_path(path)}"));
  if (size_overflow)
    _sdk_reject(
      "embedded text exceeds the String size limit",
      %("path: ${compiler.display_path(path)}"));
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
  _sdk_reject(
    "x2c.literal.value requires a String, int, or Symbol literal",
    %("value: ${syntax.repr()}"));
}

// sdk invocations and diagnostics

static Var _sdk_invocation_location(void) {
  if (!sdk_compiler || !lisp_site)
    _sdk_reject(
      "x2c invocation location used outside macro expansion", NULL);
  return sdk_compiler.token_location(lisp_site);
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
      _sdk_reject(
        "x2c.diagnostic.fail notes must be Strings",
        %("value: ${note.repr()}" ));
  _sdk_reject(message, notes);
}

/** A warning reports where it is raised and returns, so a macro can keep
   expanding. Failure stays separate because it never returns. */
void x2c_diagnostic_warn(String message, List notes) {
  _sdk_guard("x2c.diagnostic.warn");
  foreach (Var note, notes)
    if (note is not <string>)
      _sdk_reject(
        "x2c.diagnostic.warn notes must be Strings",
        %("value: ${note.repr()}" ));
  sdk_compiler.report_warning(
    <macro>, message, sdk_compiler.token, notes);
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
  Compiler c = sdk_compiler;
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
  List source = sdk_captures[((ulong) value.u64)];
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
  return sdk_compiler.complete_iter_chain(expression);
}

static Var _sdk_string_collection(List expression) {
  _sdk_guard("private foreach string conversion");
  return sdk_compiler.promote_string_literal(expression);
}
