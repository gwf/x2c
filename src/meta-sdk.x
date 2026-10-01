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
$(import "../src/sdk-errors.xmacro")

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
      if (type === %(<macro-expr>))
        type = active.expander.resolve_expression(value, active.site).cadr();
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
  if (binding) return _sdk_binding_type(binding).canonicalize();
  return value.type().canonicalize();
}

static Type _sdk_binding_type(List binding) =>
  active.expander.semantic_binding_facts()[%(type $binding)];

/** Answers `x2c.protocol.member`, declared in `lib/meta.x`. */
List x2c_protocol_member(List participant, List base, String member) {
  List conformance =
    active.expander.protocol_members_for(participant, base);
  if (!conformance) return %();
  foreach (List row, conformance.last().list().cdr())
    match (row)
      case %(?(String own) implmntd ?source ?signature *):
        if (own == member) {
          List binding = active.expander.sym.lookup(%($source), NULL);
          return binding ? %(expr $signature (ident $binding)) : %();
        }
  return %();
}

/** Answers `x2c.method.resolve`, declared in `lib/meta.x`. */
List x2c_method_resolve(List type_value, String name) {
  _sdk_guard("x2c.method.resolve");
  if (!name.is_identifier())
    $sdk.error("method.name", name);
  Type type = type_value;
  List resolution = active.expander.resolve_postfix_member(
    type, %($name), <.>, 1);
  match (resolution) {
    case %(ambiguous *packages): {
      Array notes = [];
      foreach (String package, packages) notes.push(%"package: '$package'");
      String owner = type.base_type().car().str();
      $sdk.error("method.ambiguous", owner, name, notes);
    }
    case %(method ?binding ?signature):
      return %(expr $signature (ident $binding));
  }
  return %();
}

/** Returns an expression reading each binding `declaration` declares. */
List builtin_foreach_bindings(List declaration) {
  Array result = [];
  match (declaration)
    case %((!or declare decl typedef) ? (bindings *bindings)):
      foreach (List binding, bindings) {
        List bound = binding;
        match (binding) case %(op = ?target ?): bound = target;
        match (bound) {
          case %(bind (!set ?identity (binding ? ?)) *): {
            List type = _sdk_binding_type(identity);
            result.push(%(expr $type (ident $identity)));
          }
          case %(bind ?name ?mods): {
            List row = %(
              declare ${declaration.cadr()}
                (bindings (bind $name $mods))
            );
            result.push(%(expr ${row.type_from_ast()} (ident $name)));
          }
        }
      }
  return result.list_free();
}

/** Returns the typed expression naming the function `name`, or an empty
    List when no function of that name is visible. This reads the symbol
    table only, so any compile-time Lisp evaluation may call it, including
    one outside a macro expansion. */
List builtin_foreach_reference(String name) {
  Compiler c = active.evaluator;
  if (!c) $sdk.error("reference.inactive");
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
List x2c_type_parameters(List value) {
  Type type = value.type().canonicalize();
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
  return active.expander.sym.field_order(x2c_type_resolve(value)).cdr();
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
  Type resolved = active.expander.sym.resolve_key(type.canonicalize());
  if (!resolved || !resolved.is_aggregate_tag())
    $sdk.error("fields.type", value);
  List metadata = active.expander.sym.field_order(resolved);
  if (!metadata)
    $sdk.error("fields.incomplete", value);
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
    $sdk.error("binding.spelling", syntax);
  }
  if (syntax is not <list> || syntax.is_nil())
    $sdk.error("binding.syntax", syntax);
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
        $sdk.error("binding.unknown", value);
  if (!binding_identity_try_parts(value, identity, spelling))
    $sdk.error("binding.identifier", syntax);
  Var registered =
    active.expander.semantic_binding_facts()[%(known $identity)];
  if (registered is not <string> || !registered.string().equal(spelling))
    $sdk.error("binding.unknown", value);
  return spelling;
}

/** Answers `x2c.ident`, declared in `lib/meta.x`. */
List x2c_ident(String spelling) {
  _sdk_guard("x2c.ident");
  if (!spelling.is_identifier())
    $sdk.error("ident.spelling", spelling);
  return %("x2c.ident" $spelling);
}

/** Returns a fresh binding whose spelling starts with `stem`. */
Var builtin_foreach_unique(String stem) {
  _sdk_guard("_x2c.name.unique");
  if (!stem.is_identifier())
    $sdk.error("name.stem", stem);
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
  $sdk.error("param.missing", wanted, function);
}

/** Returns the `Func` signature of the function syntax `syntax`. A native
    binding stores the same signature as an ordinary Func adapter. */
List binding_native_type(List syntax) {
  match (syntax)
    case %(function ?rtype ?declarator ?):
      return active.expander.func_signature(
        %(declare $rtype (bindings $declarator)).type_from_ast());
  return active.expander.func_signature(x2c_syntax_type(syntax));
}

/** Returns `values`, such as a Lisp-built signature, as a cached literal
    of the expanding unit. */
List binding_literal_list(List values) =>
  active.expander.cache_literal_list(values);

static Var _sdk_symbol_set(List values) {
  _sdk_guard("_x2c.symbol-set");
  foreach (Var value, values)
    if (value is not <symbol>)
      $sdk.error("symbols.type", value);
  int duplicate = -1;
  List expression = active.expander.symbol_set_expression(values, duplicate);
  if (duplicate >= 0)
    $sdk.error("symbols.duplicate", values, duplicate);
  return expression;
}

static List _sdk_meta_targets(void) => Compiler.native_meta_targets(NULL);

/* A native module's entry exports the prototypes its own sources declare,
   and a module that declares none is a mistake. */
static List _sdk_meta_declared(List paths) {
  List rows = Compiler.native_meta_targets(paths);
  if (!rows)
    $sdk.error("module.empty");
  return rows;
}

// source and literals

/** Answers `x2c.source.text`, declared in `lib/meta.x`. */
String x2c_source_text(Var value) {
  match (value) case %((text ?(String text)) (file ?) (syntax ?)): return text;
  _sdk_guard("x2c.source.text");
  Var stored = void;
  if (!active.captures ||
      !active.captures.try_get(((ulong) value.u64), stored))
    $sdk.error("source.capture", active.has_bindings, value);
  List source = stored;
  int begin = source.caddr(), end = source.last();
  return String.new_len(active.expander.text + begin, end - begin);
}

/** Answers `x2c.embed.text`, declared in `lib/meta.x`. */
String x2c_embed_text(Var requested) {
  _sdk_guard("x2c.embed.text");
  Compiler c = active.expander;
  String source_file = active.definition_file, requested_path = NULL;
  if (requested is <string>) requested_path = requested;
  else requested_path = _embed_literal(requested, source_file);
  if (!requested_path.len())
    $sdk.error("embed.empty");
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
    $sdk.error("embed.literal", requested);
  List source = stored;
  source_file = source.cadr();
  return requested_path;
}

static String Compiler._embed_source(Compiler c, String path) {
  String text;
  if (!c.read_source(path, text))
    $sdk.error("embed.read", c, path);
  return text;
}

static String Compiler._embed_file(Compiler c, String path) {
  File file = c._open_embed_file(path);
  String text = NULL;
  try text = file.string_close();
  catch %(io-fail *): $sdk.error("embed.read", c, path);
  catch %(bad-arg *):
    $sdk.error("embed.nul", c, path);
  catch %(size-limit *):
    $sdk.error("embed.limit", c, path);
  return text;
}

static File Compiler._open_embed_file(Compiler c, String path) {
  struct stat info;
  if (!stat(path, &info) && !S_ISREG(info.st_mode))
    $sdk.error("embed.file", c, path);
  File file = NULL;
  try file = path.open("r");
  catch %((!or not-found io-fail) *):
    $sdk.error("embed.open", c, path);
  if (file.stat(&info) || !S_ISREG(info.st_mode)) {
    file.close();
    $sdk.error("embed.file", c, path);
  }
  if ((uintmax_t) info.st_size >= INT_MAX) {
    file.close();
    $sdk.error("embed.limit", c, path);
  }
  return file;
}

static void Compiler._embed_reject(Compiler c, String message, String path) {
  MetaContext.reject(message, %("path: ${c.display_path(path)}"));
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
  $sdk.error("literal.type", syntax);
}

// invocations and diagnostics

/** Returns the location of the active macro invocation. */
List builtin_class_location(void) {
  if (!active.expander || !active.site)
    $sdk.error("location.inactive");
  return active.expander.token_location(active.site);
}

/** Answers `x2c.invocation.file`, declared in `lib/meta.x`. */
String x2c_invocation_file(void) =>
  builtin_class_location().assoc(<file>);

/** Answers `x2c.invocation.line`, declared in `lib/meta.x`. */
int x2c_invocation_line(void) =>
  builtin_class_location().assoc(<line>);

/** Answers `x2c.invocation.column`, declared in `lib/meta.x`. */
int x2c_invocation_column(void) =>
  builtin_class_location().assoc(<column>);

/** Answers `x2c.diagnostic.fail`, declared in `lib/meta.x`. */
void x2c_diagnostic_fail(String message, List notes) {
  _sdk_check_notes("x2c.diagnostic.fail", notes);
  MetaContext.reject(message, notes);
}

/** A warning reports where it is raised and returns, so a macro can keep
   expanding. Failure stays separate because it never returns. */
void x2c_diagnostic_warn(String message, List notes) {
  _sdk_check_notes("x2c.diagnostic.warn", notes);
  active.expander.report_warning(
    <macro>, message, active.expander.token, notes);
}

static void _sdk_check_notes(String operation, List notes) {
  _sdk_guard(operation);
  foreach (Var note, notes)
    if (note is not <string>)
      $sdk.error("notes.type", operation, note);
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
  String text = x2c_source_text(value);
  List source = active.captures[((ulong) value.u64)];
  return %((text $text) (file ${source.cadr()}) (syntax $value));
}

// built-in algorithm operations

/** Returns `expression` with the iterator chain `foreach` reads completed. */
List builtin_foreach_complete(List expression) {
  _sdk_guard("private foreach iterator completion");
  return active.expander.complete_iter_chain(expression);
}

/** Returns the collection `foreach` iterates for `expression`, promoting a
    String literal. */
List builtin_foreach_collection(List expression) {
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
  $sdk.error("reject.inactive", message);
}

// SDK operations reject use outside an active expansion.
static void _sdk_guard(String operation) {
  if (!active.expander)
    $sdk.error("expansion.inactive", operation);
}

static void _sdk_reject_value(String message, Var value) {
  MetaContext.reject(message, %("value: ${value.repr()}"));
}

// lisp primitives

/** Binds the internal primitives the compile-time SDK library wraps into
    `lisp`, under their `_x2c.` names. */
void Compiler.bind_sdk_primitives(Lisp lisp) {
  $lisp.bind(lisp, "_x2c.function.reference", builtin_foreach_reference);
  $lisp.bind(lisp, "_x2c.function.native-type", binding_native_type);
  $lisp.bind(lisp, "_x2c.literal.list", binding_literal_list);
  $lisp.bind(lisp, "_x2c.native-meta.targets", _sdk_meta_targets);
  $lisp.bind(lisp, "_x2c.native-meta.declared", _sdk_meta_declared);
  $lisp.bind(lisp, "_x2c.source.text", x2c_source_text);
  $lisp.bind(lisp, "_x2c.embed.text", x2c_embed_text);
  $lisp.bind(lisp, "_x2c.invocation.location", builtin_class_location);
  $lisp.bind(lisp, "_x2c.symbol-set", _sdk_symbol_set);
}
