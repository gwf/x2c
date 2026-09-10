/*  macros.x -- compile-time macro definitions and expression expansion

    Macro definitions are compiler-only records. Their patterns and
    replacements are canonical `List`s. Expansion uses the same `List`
    operations that parsed source uses.
*/

#pragma once
$(import "../lib/private-keywords.xmacro")
#include "compiler.x"
#pragma private
#include "expressions.x"
#include "literals.x"
#include "parse.x"
#include "statements.x"
#include "utils.x"
#include <limits.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

/* Native Lisp callbacks have no Compiler parameter, so these values hold
   dynamically scoped evaluation context. Lisp entry points restore the
   relevant frame after nested import evaluation; captured-source entries are
   valid only while their expansion is active. */
static Compiler macro_sdk_compiler = NULL;
static String macro_sdk_source_file = NULL, macro_sdk_failure_message = NULL;
static List macro_sdk_failure_notes = NULL;
static Map macro_sdk_source_captures = NULL;
static int macro_sdk_has_references = 0;
static Compiler macro_import_compiler = NULL;
static Token macro_import_invocation = NULL;

macro Expression $_embed_lisp_binding_macros() => (
  $(x2c.literal.string (x2c._embed.text "../etc/lisp-bindings.xmacro"))
)

macro Expression $_embed_builtin_macros() => (
  $(x2c.literal.string (x2c._embed.text "../etc/builtin-macros.xmacro"))
)

static String lisp_binding_macros = $_embed_lisp_binding_macros();
static String lisp_binding_macros_marker = NULL;
static String builtin_macros = $_embed_builtin_macros();
static String builtin_macros_marker = NULL;

static void _install_source(
  Compiler compiler, String text, String filename, String marker,
  int builtin) {
  (void) marker.try_own();
  if (compiler.macros.contains(marker)) return;
  Compiler definitions = Compiler.new_shared(compiler);
  defer compiler.close_child(definitions);
  definitions.filename = filename;
  definitions.sym = compiler.sym;
  definitions.fn_defs = compiler.fn_defs;
  definitions.macros = compiler.macros;
  definitions.kw_aliases = compiler.kw_aliases;
  definitions.builtin_defs = builtin;
  definitions.tokenize(text);
  while (definitions.peek(0) != <eof>) {
    if (definitions.keyword_form_is_definition())
      definitions.parse_keyword_definition();
    else if (definitions.macro_form_is_definition())
      definitions.parse_macro_definition();
    else
      definitions.report_error(
        <macro>, "unexpected form in built-in macro source",
        definitions.token, NULL);
  }
  compiler.macros[marker] = 1;
}

static void _install_lisp_bindings(Compiler compiler) {
  if (!lisp_binding_macros_marker)
    lisp_binding_macros_marker = String.new("_x2c.lisp.bindings");
  if (compiler.macros.contains(lisp_binding_macros_marker)) return;
  _ensure_lisp(compiler);
  _eval_library(
    compiler, "etc/lisp-bindings.xlisp",
    "cannot open the native Lisp macro support");
  _install_source(
    compiler, lisp_binding_macros, "<builtin:lisp-bindings>",
    lisp_binding_macros_marker, 0);
}

static int _try_definition(
  Compiler compiler, Atom name, int install_lisp, Var *stored) {
  if (compiler.macros.try_get(name, stored)) return 1;
  String spelling = name.str();
  if (!install_lisp || !spelling.startswith("lisp.")) return 0;
  _install_lisp_bindings(compiler);
  return compiler.macros.try_get(name, stored);
}

/** Installs the compiler-shipped source macros into `compiler` once. */
void Compiler.install_builtin_macros(Compiler compiler) {
  if (!builtin_macros_marker)
    builtin_macros_marker = String.new("_x2c.builtin.macros");
  _install_source(
    compiler, builtin_macros, "<builtin:macros>",
    builtin_macros_marker, 1);
}

static Var _sdk_reject(String message, List notes) {
  macro_sdk_failure_message = message;
  macro_sdk_failure_notes = notes;
  return void;
}

/* SDK operations reject use outside an active expansion. The guard returns
   from its caller. A helper cannot do that, so this is a statement macro. */
macro Statement $_sdk_guard(Expr $operation) => {
  if (!macro_sdk_compiler)
    return _sdk_reject(%"${$operation} used outside macro expansion", NULL);
}

static List _sdk_binding_type(List binding) =>
  macro_sdk_compiler.semantic_binding_facts()[
    %(type $binding)
  ];

static Var _sdk_syntax_type(List value) {
  $_sdk_guard("x2c.syntax.type");
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
    match (value)
      case %((!or ident bind) (*) *): binding = value.cadr();
  if (binding) {
    Type type = _sdk_binding_type(binding);
    return type.canonicalize();
  }
  return value.type().canonicalize();
}

static Var _sdk_declaration_bindings(List declaration) {
  Array result = %[];
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

static Var _sdk_function_reference(String name) {
  Type type = NULL;
  List binding = macro_sdk_compiler.sym.lookup(%($name), &type);
  if (!binding || !type || !type.is_function()) return %();
  return %(expr $type (ident $binding));
}

static Var _sdk_protocol_member(
  List participant, List base, String member) {
  List conformance =
    macro_sdk_compiler.protocol_members_for(participant, base);
  if (!conformance) return %();
  foreach (List row, conformance.last().list().cdr()) {
    (String row_member, Symbol status, String source, Type signature,
     Symbol default_kind, Type template) = row;
    (void) default_kind; (void) template;
    if (status != <implmntd> || row_member != member) continue;
    List binding = macro_sdk_compiler.sym.lookup(%($source), NULL);
    if (binding) return %(expr $signature (ident $binding));
    return %();
  }
  return %();
}

static Var _sdk_type_integral(List value) {
  if (value.type().is_integral()) return <true>;
  return %();
}

static Var _sdk_type_pointer(List value) {
  if (value.type().canonicalize().is_pointer()) return <true>;
  return %();
}

static Var _sdk_type_element(List value) =>
  value.type().canonicalize().dereference().canonicalize();

static List _sdk_function_type_parameters(Type type) {
  while (type.is_pointer() || type.is_array()) type = type.dereference();
  return type.match_replace(%((func ?params) *), <?params>);
}

static Var _sdk_type_parameters(List value) => _sdk_function_type_parameters(
    value.type().canonicalize());

static Var _sdk_type_return(List value) =>
  value.type().canonicalize().apply().canonicalize().var();

static Var _sdk_complete_iter_chain(List expression) {
  $_sdk_guard("private foreach iterator completion");
  return macro_sdk_compiler.complete_iter_chain(expression);
}

static Var _sdk_type_fields(List value) {
  $_sdk_guard("x2c.type.fields");
  Type type = value;
  type = type.canonicalize();
  Type resolved = macro_sdk_compiler.sym.resolve_key(type);
  if (!resolved || !resolved.is_aggregate_tag())
    return _sdk_reject(
      "x2c.type.fields requires a struct or union Type",
      %("value: ${value.repr()}"));
  List metadata = macro_sdk_compiler.sym.field_order(resolved);
  if (!metadata)
    return _sdk_reject(
      "x2c.type.fields requires a complete struct or union Type",
      %("value: ${value.repr()}"));
  Array named = %[];
  foreach (List row, metadata.cdr())
    if (row.car().truth()) named.push(row);
  return named.list_free();
}

static Var _sdk_binding_spelling(Var syntax) {
  $_sdk_guard("x2c.binding.spelling");
  if (syntax is <string>) {
    String spelling = syntax;
    if (spelling.is_identifier()) return spelling;
    return _sdk_reject(
      "x2c.binding.spelling requires an identifier spelling",
      %("value: ${syntax.repr()}" ));
  }
  if (syntax is not <list> || syntax.is_nil()) {
    return _sdk_reject(
      "x2c.binding.spelling requires binding syntax",
      %("value: ${syntax.repr()}" ));
  }
  List value = syntax;
  match (value)
    case %(expr ? (? *)): value = value.caddr();
  match (value) {
    case %(ident (*)):     value = value.cadr();
    case %(bind (*) ?):    value = value.cadr();
  }
  match (value)
    case %((!is ?name type string)): return name;
  int identity = 0, String spelling = NULL;
  match (value)
    case %(binding ?id (!is ? type string)):
      if (!id.is_integer() || id.integer() > INT_MAX)
        return _sdk_reject(
          "x2c.binding.spelling requires a known binding",
          %("binding: ${value.repr()}"));
  if (!binding_identity_try_parts(value, &identity, &spelling))
    return _sdk_reject(
      "x2c.binding.spelling requires an identifier or binding",
      %("value: ${syntax.repr()}" ));
  Var registered =
    macro_sdk_compiler.semantic_binding_facts()[%(known $identity)];
  if (registered is not <string> || !registered.string().equal(spelling))
    return _sdk_reject(
      "x2c.binding.spelling requires a known binding",
      %("binding: ${value.repr()}" ));
  return spelling;
}

static Var _sdk_source_text(Var value) {
  $_sdk_guard("x2c.source.text");
  Var stored = void;
  Var key = ((ulong) value.u64);
  if (!macro_sdk_source_captures ||
      !macro_sdk_source_captures.try_get(key, &stored))
    return _sdk_reject(
      "x2c.source.text requires complete captured syntax",
      macro_sdk_has_references ? NULL : %("value: ${value.repr()}"));
  List source = stored;
  int begin = source.caddr().int(), end = source.last().int();
  return String.new_len(macro_sdk_compiler.text + begin, end - begin);
}

static Var _sdk_diagnostic_fail(String message, List notes) {
  $_sdk_guard("x2c.diagnostic.fail");
  foreach (Var note, notes)
    if (note is not <string>)
      return _sdk_reject(
        "x2c.diagnostic.fail notes must be Strings",
        %("value: ${note.repr()}" ));
  macro_sdk_failure_message = message;
  macro_sdk_failure_notes = notes;
  return void;
}

static Var _sdk_ident(String spelling) {
  $_sdk_guard("x2c.ident");
  if (!spelling.is_identifier()) return _sdk_reject(
    "x2c.ident requires an identifier spelling",
    %("value: ${spelling.repr()}" ));
  return %("x2c.ident" $spelling);
}

static Var _sdk_ident_unique(String stem) {
  $_sdk_guard("private foreach name allocation");
  if (!stem.is_identifier()) return _sdk_reject(
    "foreach name allocation requires an identifier stem",
    %("value: ${stem.repr()}" ));
  String spelling = macro_sdk_compiler.fresh_name(%"macro_$stem");
  return macro_sdk_compiler.sym.introduce(spelling);
}

static Var _sdk_invocation_location(void) {
  if (!macro_sdk_compiler || !macro_import_invocation)
    return _sdk_reject(
      "x2c invocation location used outside macro expansion", NULL);
  return macro_sdk_compiler.token_location(macro_import_invocation);
}

static Var _sdk_method_resolve(List type_value, String name) {
  $_sdk_guard("x2c.method.resolve");
  if (!name.is_identifier())
    return _sdk_reject(
      "x2c.method.resolve requires an identifier String",
      %("value: ${name.repr()}"));
  Type type = type_value;
  List resolution = macro_sdk_compiler.resolve_postfix_member(
    type, %($name), <.>, 1);
  match (resolution) {
    case %(ambiguous *packages): {
      List notes = NULL;
      foreach (String package, packages)
        notes = cons(%"package: '$package'", notes);
      String owner = type.base_type().car().str();
      return _sdk_reject(
        %"method '$owner.$name' is provided by multiple imported packages",
        notes.reverse());
    }
    case %(method ?binding ?signature):
      return %(expr $signature (ident $binding));
  }
  return %();
}

static Var _sdk_function_name(List function) {
  List identity = function.match_replace(
    %(function ? (bind ?binding ?) ?), <?binding>);
  return _sdk_binding_spelling(identity);
}

static Var _sdk_function_type(List function) {
  List declaration = function.match_replace(
    %(function ?rtype ?declarator ?),
    %(declare ?rtype (bindings ?declarator)));
  Type type = declaration.type_from_ast();
  return type.canonicalize();
}

static int _lisp_value_type(Type type) {
  match (type)
    case %((!or "Var" "Symbol" "String" "List" "Array" "Map"
                "File" "Iter" "Func")): return 1;
  return 0;
}

static Type _lisp_resolve_type(Type type) {
  type = type.canonicalize();
  for (int hops = 0; hops < 128; hops++) {
    if (_lisp_value_type(type)) return type;
    if (!type.is_bare_typedef_name() && !type.is_typedef()) return type;
    Type next = NULL;
    macro_sdk_compiler.sym.resolve_global(type, &next);
    if (!next || next == type) return type;
    type = next.canonicalize();
  }
  return type;
}

static Var _sdk_native_function_type(List syntax) {
  Var value = void;
  match (syntax) {
    case %(function ? ? ?): value = _sdk_function_type(syntax);
    default: value = _sdk_syntax_type(syntax);
  }
  Type type = value.type().canonicalize();
  List source_parameters = _sdk_function_type_parameters(type);
  Type source_result = type.apply(), Array parameters = %[];
  foreach (Var parameter, source_parameters)
    parameters.push(_lisp_resolve_type(parameter.list()));
  Type result = _lisp_resolve_type(source_result);
  List resolved = cons(%(func ${parameters.list_free()}), result);
  return resolved;
}

static Var _sdk_function_parameter(List function, String wanted) {
  List parameters = function.match_replace(
    %(function ? (bind ? ((fnmod (params *bound)) *)) ?), %(*bound));
  foreach (List parameter, parameters) {
    match (parameter) {
      case %(param ? (bind ?identity *)):
        if (_sdk_binding_spelling(identity).string() == wanted) {
          Type type = parameter.type_from_ast().canonicalize();
          return %(expr $type (ident $identity));
        }
    }
  }
  return _sdk_reject(
    %"x2c.function.parameter cannot find '$wanted'",
    %("function: ${_sdk_function_name(function).repr()}"));
}

static Var _sdk_function_body(List function) =>
  function.match_replace(%(function ? ? (block *body)), %(*body));

static void _report_lisp_failure(
  Compiler compiler, Token invocation, List error, String source) {
  if (macro_sdk_failure_message)
    compiler.report_error(
      <macro>, macro_sdk_failure_message,
      invocation, macro_sdk_failure_notes);
  String form_note = %"form: $source", error_note = %"error: ${error.repr()}";
  compiler.report_error(
    <macro>, "compile-time Lisp evaluation failed",
    invocation, %($form_note $error_note));
}

static Var _eval_string(
  Compiler compiler, String source, Token invocation) {
  Var result;
  Compiler previous = macro_import_compiler;
  Token old_invocation = macro_import_invocation;
  macro_import_compiler = compiler;
  macro_import_invocation = invocation;
  {
    defer {
      macro_import_compiler = previous;
      macro_import_invocation = old_invocation;
    }
    try result = compiler.macro_lisp.eval_string(source);
    catch %(?code *detail):
      _report_lisp_failure(compiler, invocation, cons(code, detail), source);
  }
  return result;
}

static Var _eval_file(Compiler compiler, File source, Token invocation) {
  Var result = void;
  Compiler previous = macro_import_compiler;
  Token old_invocation = macro_import_invocation;
  macro_import_compiler = compiler;
  macro_import_invocation = invocation;
  {
    defer {
      macro_import_compiler = previous;
      macro_import_invocation = old_invocation;
    }
    try result = compiler.macro_lisp.eval_file(source);
    catch %(?code *detail):
      _report_lisp_failure(
        compiler, invocation, cons(code, detail), "<file>");
  }
  return result;
}

static Var _lisp_import_hook(String path) {
  Compiler compiler = macro_import_compiler;
  if (!compiler) raise %(bad-state (operation "compile-time import"));
  _import(compiler, path, macro_import_invocation);
  return %();
}

/** Returns whether the current tokens have macro-definition introducer form.
    This query does not consume tokens.
*/
int Compiler.macro_form_is_definition(Compiler compiler) {
  if (compiler.peek(0) != <ident> || compiler.token.text != "macro") return 0;
  if (compiler.peek(1) == <$>) return 1;
  return compiler.peek(1) == <ident> && compiler.peek(2) == <$>;
}

/** Returns whether the current tokens begin a local macro definition.
    This query does not consume tokens.
*/
int Compiler.local_macro_form_is_definition(Compiler compiler) {
  return compiler.peek(0) == <ident> &&
         compiler.token.text == "macro" &&
         compiler.peek(1) == <ident> &&
         compiler.peek(2) == <ident> &&
         compiler.peek(3) == <(>;
}

/** Returns whether the current tokens begin a `keyword NAME $macro` alias.
    This query does not consume tokens.
*/
int Compiler.keyword_form_is_definition(Compiler compiler) =>
  compiler.peek(0) == <ident> &&
         compiler.token.text == "keyword" &&
         compiler.peek(2) == <$>;

static void _skip_balanced_tokens(
  Compiler compiler, Symbol open, Symbol close) {
  int depth = 0;
  if (compiler.peek(0) == open) {
    depth = 1;
    compiler.next();
  }
  while (depth && compiler.peek(0) != <eof>) {
    Symbol token = compiler.peek(0);
    if (token == open) depth++;
    else if (token == close) depth--;
    compiler.next();
  }
}

/** Consumes a direct macro name and its balanced argument list.
    The invocation terminator remains current for the shallow parser.
*/
void Compiler.skip_macro_invocation(Compiler compiler) {
  compiler.expect(<$>);
  while (compiler.peek(0) == <ident> || compiler.peek(0) == <.>)
    compiler.next();
  _skip_balanced_tokens(compiler, <(>, <)>);
}

static Atom _name(Compiler c) {
  c.expect(<$>);
  if (c.peek(0) != <ident>)
    c.report_error(<parse>, "expected macro name after '$'", c.token, NULL);
  String spelling = c.token.text;
  c.next();
  while (c.test(<.>)) {
    if (c.peek(0) != <ident>)
      c.report_error(
        <parse>, "expected macro name component after '.'",
        c.token, NULL);
    spelling = %"$spelling.${c.token.text}";
    c.next();
  }
  return Atom.intern(spelling);
}

static List _peek_definition(Compiler c) {
  Token token = c.skip_trivia_from(c.token + 1);
  if (c.peek(0) != <$> || token.type != <ident>) return NULL;
  String spelling = token.text;
  token = c.skip_trivia_from(token + 1);
  while (token.type == <.>) {
    token = c.skip_trivia_from(token + 1);
    if (token.type != <ident>) return NULL;
    spelling = %"$spelling.${token.text}";
    token = c.skip_trivia_from(token + 1);
  }
  Var stored;
  Atom name = Atom.intern(spelling);
  if (!_try_definition(c, name, !c.shallow, &stored)) return NULL;
  return stored;
}

static int _definition_needs_shallow_expansion(List definition) {
  if (!definition || definition.assoc(<kind>) != <unit>) return 0;
  if (definition.assoc(<imported>).int()) return 1;
  List template = definition.assoc(<template>), bindings;
  Var matched;
  return template.try_search(
    %(!or (protocol *) (adopt *)), &matched, &bindings);
}

/** Returns whether the current direct invocation needs shallow expansion.
    Every imported `Unit` macro qualifies. A local `Unit` macro qualifies only
    when its template contains protocol or adoption rows that collection must
    retain.
*/
int Compiler.macro_invocation_needs_shallow_expansion(Compiler compiler) =>
  _definition_needs_shallow_expansion(
    _peek_definition(compiler));

typedef struct MacroPos {
  Symbol kind, const char *description, int semicolon;
} MacroPos;

static const MacroPos macro_position_info[] = {
  { <unit>,       "file scope",    1 },
  { <block-item>, "block scope",   1 },
  { <field>,      "field scope",   1 },
  { <enumerator>, "an enum body",  0 },
  { <map-entry>,  "a map literal", 0 },
  { <block-item>, "block scope",   1 },
  { <expression>, "an expression", 0 }
};

static const MacroPos *_position(AstPos position) =>
  &macro_position_info[position];

static Symbol _decorator_result_kind(Symbol target_kind) {
  if (target_kind == <function> || target_kind == <unit>) return <unit>;
  if (target_kind == <block>) return <block-item>;
  if (target_kind == <expr>) return <expression>;
  return target_kind;
}

/** Returns whether the current direct macro can start at `position`.
    The current definition and any decorator target kind determine the result;
    this query does not consume tokens.
*/
int Compiler.macro_starts_target_at(Compiler compiler, AstPos position) {
  List definition = _peek_definition(compiler);
  if (!definition) return 0;
  Symbol kind = definition.assoc(<kind>);
  return kind == _position(position).kind ||
    (position == AST_STATEMENT && kind == <decorator> &&
     definition.assoc(<target>) == <block>);
}

static String _source_dir(Compiler compiler) {
  String filename = compiler.import_stack.len()
                  ? compiler.import_stack[-1].str()
                  : compiler.filename;
  return filename ? x2c_path_dir(filename) : %".";
}

static String _source_file(Compiler compiler, String file) {
  if (!file || file.startswith("<")) return file;
  char resolved[PATH_MAX];
  if (compiler.sources && compiler.sources.exists(file))
    return SourceView.path(file);
  if (realpath(file, resolved)) return %"$resolved";
  if (file[0] != '/') {
    String rooted = %"${compiler.root_dir}/$file";
    if (realpath(rooted, resolved)) return %"$resolved";
  }
  return file;
}

static String _embed_path(
  Compiler compiler, String source_file, String requested) {
  String candidate = requested;
  if (requested[0] != '/') {
    String base = _source_file(compiler, source_file);
    candidate = %"${x2c_path_dir(base)}/$requested";
  }
  if (compiler.sources) return SourceView.path(candidate);
  char resolved[PATH_MAX];
  return realpath(candidate, resolved) ? %"$resolved" : candidate;
}

static String _canonical_path(Compiler compiler, String path) {
  String candidate = path;
  if (path && path[0] != '/')
    candidate = %"${_source_dir(compiler)}/$path";
  char resolved[PATH_MAX];
  if (compiler.sources && compiler.sources.exists(candidate))
    return SourceView.path(candidate);
  if (realpath(candidate, resolved)) return %"$resolved";
  if (path && path[0] != '/') {
    String system = %"${compiler.root_dir}/lib/$path";
    if (compiler.sources && compiler.sources.exists(system))
      return SourceView.path(system);
    if (realpath(system, resolved)) return %"$resolved";
  }
  return candidate;
}

static int _literal_string(Var syntax, String *value) {
  match (syntax)
    case %(expr ? (literal ? (!is ?text type string))): {
      String source = text;
      int quoted = source.len() >= 2 && source[0] == '"' &&
        source[source.len() - 1] == '"';
      int percent_quoted = source.len() >= 3 && source[0] == '%' &&
        source[1] == '"' && source[source.len() - 1] == '"';
      if (quoted || percent_quoted) {
        *value = source.parse();
        return 1;
      }
    }
  return 0;
}

static Var _sdk_embed_text(Var requested) {
  Compiler compiler = macro_sdk_compiler;
  if (!compiler)
    return _sdk_reject(
      "x2c.embed.text used outside macro expansion", NULL);
  String source_file = macro_sdk_source_file, requested_path = NULL;
  if (requested is <string>) requested_path = requested;
  else {
    Var stored = void;
    Var key = ((ulong) requested.u64);
    if (!macro_sdk_source_captures ||
        !macro_sdk_source_captures.try_get(key, &stored) ||
        !_literal_string(requested, &requested_path))
      return _sdk_reject(
        "x2c.embed.text requires a String or captured String literal",
        %("value: ${requested.repr()}"));
    List source = stored;
    source_file = source.cadr();
  }
  if (!requested_path.len())
    return _sdk_reject(
      "x2c.embed.text requires a non-empty path", NULL);
  String path = _embed_path(compiler, source_file, requested_path);
  if (compiler.sources) {
    String text;
    if (!compiler.read_source(path, &text))
      return _sdk_reject(
        "cannot read embedded text",
        %("path: ${compiler.display_path(path)}"));
    compiler.deps.merge_translation_dependency(
      path, %"%08x".printf(String.hash(text)));
    return text;
  }
  struct stat info;
  if (!stat(path, &info) && !S_ISREG(info.st_mode))
    return _sdk_reject(
      "embedded text is not a regular file",
      %("path: ${compiler.display_path(path)}"));
  File file = NULL, int open_failed = 0;
  try file = path.open("r");
  catch %(not-found *): open_failed = 1;
  catch %(io-fail *): open_failed = 1;
  if (open_failed)
    return _sdk_reject(
      "cannot open embedded text",
      %("path: ${compiler.display_path(path)}"));
  if (file.stat(&info) || !S_ISREG(info.st_mode)) {
    file.close();
    return _sdk_reject(
      "embedded text is not a regular file",
      %("path: ${compiler.display_path(path)}"));
  }
  if ((uintmax_t) info.st_size >= INT_MAX) {
    file.close();
    return _sdk_reject(
      "embedded text exceeds the String size limit",
      %("path: ${compiler.display_path(path)}"));
  }
  String result = NULL;
  int read_failed = 0, embedded_nul = 0, size_overflow = 0;
  try result = file.string_close();
  catch %(io-fail *): read_failed = 1;
  catch %(bad-arg *): embedded_nul = 1;
  catch %(size-limit *): size_overflow = 1;
  if (read_failed)
    return _sdk_reject(
      "cannot read embedded text",
      %("path: ${compiler.display_path(path)}"));
  if (embedded_nul)
    return _sdk_reject(
      "embedded text contains an embedded NUL",
      %("path: ${compiler.display_path(path)}"));
  if (size_overflow)
    return _sdk_reject(
      "embedded text exceeds the String size limit",
      %("path: ${compiler.display_path(path)}"));
  String content_hash = %"%08x".printf(String.hash(result));
  compiler.deps.merge_translation_dependency(path, content_hash);
  return result;
}

static Var _sdk_literal_string(Var syntax) {
  $_sdk_guard("private native Lisp literal query");
  String value = NULL;
  if (_literal_string(syntax, &value)) return value;
  return _sdk_reject(
    "native Lisp binding name requires a String literal",
    %("value: ${syntax.repr()}"));
}

/* This catches the open failure, so an unreadable compile-time Lisp path
   becomes a located diagnostic instead of an error transfer. */
static File _open(
  Compiler compiler, String path, String message, Token token, List notes) {
  File source = NULL, int failed = 0;
  try source = path.open("r");
  catch %(not-found *): failed = 1;
  catch %(io-fail *): failed = 1;
  if (failed) compiler.report_error(<macro>, message, token, notes);
  return source;
}

static String _read_source(
  Compiler compiler, String path, String message, Token token, List notes) {
  if (compiler.sources) {
    String text;
    if (!compiler.read_source(path, &text))
      compiler.report_error(<macro>, message, token, notes);
    return text;
  }
  return _open(compiler, path, message, token, notes).string_close();
}

static void _eval_library(
  Compiler compiler, String relative, String message) {
  String path = %"${compiler.root_dir}/$relative";
  if (compiler.sources) {
    String text = _read_source(
      compiler, path, message, compiler.token, %("path:" $path));
    compiler.add_translation_dependency(path);
    _eval_string(compiler, text, compiler.token);
    return;
  }
  File source = _open(
    compiler, path, message, compiler.token, %("path:" $path));
  compiler.add_translation_dependency(path);
  defer source.close();
  _eval_file(compiler, source, compiler.token);
}

/* Each Compiler initializes one Lisp session lazily. An `.xmacro` import
   parser borrows that session; the parent Compiler frees it. */
static void _ensure_lisp(Compiler compiler) {
  macro Statement install(
    Expr $name, Expr $function, Expr $signature
  ) => {
    Func callable = Func.new($function, $signature);
    compiler.macro_lisp.set_global($name, Func.var(callable));
  }

  with compiler {
    if (_.macro_lisp) return;
    _.macro_lisp = Lisp.new_bare();
    _eval_library(
      _, "etc/init.xlisp",
      "cannot open the compile-time Lisp environment");
    _eval_library(
      _, "etc/compiler-sdk.xlisp",
      "cannot open the compile-time Lisp SDK");
    _eval_library(
      _, "etc/builtin-macros.xlisp",
      "cannot open the built-in macro support");
    install("_x2c.import-hook",
            _lisp_import_hook, %((func (("String"))) "Var"));
    install("x2c.syntax.type",
            _sdk_syntax_type, %((func (("List"))) "Var"));
    install("_x2c.foreach.declaration-bindings",
            _sdk_declaration_bindings,
            %((func (("List"))) "Var"));
    install("x2c.binding.spelling",
            _sdk_binding_spelling, %((func (("Var"))) "Var"));
    install("x2c._source.text",
            _sdk_source_text, %((func (("Var"))) "Var"));
    install(
      "x2c.diagnostic.fail", _sdk_diagnostic_fail,
      %((func (("String") ("List"))) "Var")
    );
    install("x2c.ident",
            _sdk_ident, %((func (("String"))) "Var"));
    install("_x2c.foreach.ident-unique",
            _sdk_ident_unique, %((func (("String"))) "Var"));
    install("x2c._invocation.location",
            _sdk_invocation_location,
            %((func ((void))) "Var"));
    install("x2c.method.resolve",
            _sdk_method_resolve,
            %((func (("List") ("String"))) "Var"));
    install("x2c._symbol-set",
            _sdk_symbol_set, %((func (("List"))) "Var"));
    install("x2c._embed.text",
            _sdk_embed_text, %((func (("Var"))) "Var"));
    install("_x2c.literal.string",
            _sdk_literal_string, %((func (("Var"))) "Var"));
    install("x2c.function.name",
            _sdk_function_name, %((func (("List"))) "Var"));
    install("_x2c.foreach.function-reference",
            _sdk_function_reference,
            %((func (("String"))) "Var"));
    install("_x2c.function.native-type",
            _sdk_native_function_type,
            %((func (("List"))) "Var"));
    install("x2c.function.parameter",
            _sdk_function_parameter,
            %((func (("List") ("String"))) "Var"));
    install("x2c.function.body",
            _sdk_function_body, %((func (("List"))) "Var"));
    install("_x2c.foreach.protocol-member",
            _sdk_protocol_member,
            %((func (("List") ("List") ("String"))) "Var"));
    install("_x2c.type.integral?",
            _sdk_type_integral,
            %((func (("List"))) "Var"));
    install("_x2c.type.pointer?",
            _sdk_type_pointer, %((func (("List"))) "Var"));
    install("_x2c.type.element",
            _sdk_type_element, %((func (("List"))) "Var"));
    install("_x2c.type.parameters",
            _sdk_type_parameters,
            %((func (("List"))) "Var"));
    install("_x2c.type.return",
            _sdk_type_return, %((func (("List"))) "Var"));
    install("_x2c.foreach.complete-iter-chain",
            _sdk_complete_iter_chain,
            %((func (("List"))) "Var"));
    install("x2c.type.fields",
            _sdk_type_fields, %((func (("List"))) "Var"));
  }
}

static String _lisp_form(Compiler c) {
  Token start = c.token;
  c.expect(<"$(">);
  int depth = 1;
  Token close = NULL;
  while (depth && c.peek(0) != <eof>) {
    Symbol token = c.peek(0);
    if (token == <(>) depth++;
    else if (token == <)>) {
      depth--;
      if (!depth) close = c.token;
    }
    c.next();
  }
  if (!close)
    c.report_error(
      <parse>, "unterminated compile-time Lisp form",
      start, NULL);
  int begin = start.pos + start.len, length = close.pos - begin;
  String body = String.new_len(c.text + begin, length);
  return %"($body)";
}

/** Consumes one balanced compile-time Lisp form without evaluating it. */
void Compiler.skip_macro_lisp(Compiler compiler) {
  (void) _lisp_form(compiler);
}

static int _import_path(Compiler compiler, String *path) {
  Token token = compiler.skip_trivia_from(compiler.token + 1);
  /* The checked-in bootstrap still tokenizes `import` as an identifier, so
     both spellings of the same word open a compile-time import. */
  if ((token.type != <ident> && token.type != <import>) ||
      token.text != "import")
    return 0;
  token = compiler.skip_trivia_from(token + 1);
  if (token.type != <lit-char*>) return 0;
  if (path) *path = String.new_len(token.text + 1, token.len - 2).unescape();
  token = compiler.skip_trivia_from(token + 1);
  return token.type == <)>;
}

/* An import is cached only after it completes. Cached `.xmacro` aliases are
   replayed once per source alias map, while definitions and the Lisp session
   remain shared by the translation unit. */
static void _import(
  Compiler c, String requested, Token invocation) {
  _ensure_lisp(c);
  String path = _canonical_path(c, requested);
  c.add_translation_dependency(path);
  Var cached;
  if (c.imports.try_get(path, &cached)) {
    if (!c.kw_seen.contains(path) && cached is <map>) {
      Map.merge(c.kw_aliases, cached);
      c.kw_seen[path] = 1;
    }
    return;
  }
  if (c.import_stack.contains(path)) {
    String display = c.display_path(path);
    Array notes = %[ "import: $display" ];
    foreach (Var parent, c.import_stack)
      notes.push(%"from: ${c.display_path(parent.str())}");
    c.report_error(
      <macro>, "compile-time import cycle",
      invocation, notes.list_free());
  }
  c.import_stack.push(path);
  Map imported_aliases = NULL;
  {
    defer c.import_stack.take_last();
    if (path.endswith(".xlisp")) {
      if (c.sources) {
        String text = _read_source(
          c, path, "cannot open compile-time Lisp import", invocation,
          %( "path: ${c.display_path(path)}" ));
        _eval_string(c, text, invocation);
      }
      else {
        File source = _open(
          c, path, "cannot open compile-time Lisp import", invocation,
          %( "path: ${c.display_path(path)}" ));
        defer source.close();
        _eval_file(c, source, invocation);
      }
    }
    else if (path.endswith(".xmacro")) {
      imported_aliases = %{};
      String text = _read_source(
        c, path, "cannot open macro import", invocation,
        %( "path: ${c.display_path(path)}" ));
      /* The import parser borrows the caller's semantic maps and Lisp. Its
         diagnostics are returned to the caller before release; lasting
         effects enter the shared definitions, aliases, dependencies, and
         Lisp session. */
      Compiler imported = Compiler.new_shared(c);
      defer c.close_child(imported);
      imported.filename = path;
      DiagnosticEmitter emitter = c.diagnostics.emit;
      void *diagnostic_owner = c.diagnostics.owner;
      imported.borrow_diagnostics(c);
      defer c.diagnostics.set_emitter(emitter, diagnostic_owner);
      imported.sym = c.sym;
      imported.fn_defs = c.fn_defs;
      imported.macros = c.macros;
      imported.kw_aliases = c.kw_aliases;
      imported.kw_seen = c.kw_seen;
      imported.macro_lisp = c.macro_lisp;
      imported.borrowed_lisp = 1;
      imported.import_src = path;
      imported.imports = c.imports;
      imported.import_stack = c.import_stack;
      imported.tokenize(text);
      while (imported.peek(0) != <eof>) {
        if (imported.keyword_form_is_definition()) {
          Token alias_token = imported.skip_trivia_from(imported.token + 1);
          Atom alias = Atom.intern(alias_token.text);
          imported.parse_keyword_definition();
          imported_aliases[alias] = imported.kw_aliases[alias];
        }
        else if (imported.macro_form_is_definition())
          imported.parse_macro_definition();
        else if (imported.peek(0) == <"$(">)
          imported.parse_macro_lisp_top_level();
        else
          imported.report_error(
            <macro>, "unexpected form in macro import",
            imported.token, NULL);
      }
      c.merge_translation_dependencies(imported.deps);
    }
    else
      c.report_error(
        <macro>, "compile-time import requires .xlisp or .xmacro",
        invocation,
        %( "path: ${c.display_path(path)}" ));
  }
  if (imported_aliases) {
    c.imports[path] = imported_aliases;
    c.kw_seen[path] = 1;
  }
  else c.imports[path] = 1;
}

/** Consumes and evaluates one top-level compile-time Lisp form.
    `$(import ...)` loads a tracked `.xlisp` or `.xmacro` dependency; other
    results are discarded in the translation unit's Lisp session.
*/
void Compiler.parse_macro_lisp_top_level(Compiler compiler) {
  Token invocation = compiler.token;
  String import_path = NULL;
  int is_import = _import_path(compiler, &import_path);
  String form = _lisp_form(compiler);
  if (is_import) {
    _import(compiler, import_path, invocation);
    return;
  }
  _ensure_lisp(compiler);
  _eval_string(compiler, form, invocation);
}

/** Processes a top-level Lisp form during shallow collection.
    Imports run so their definitions and Lisp effects are available; every
    other form is only consumed.
*/
void Compiler.parse_macro_lisp_shallow(Compiler compiler) {
  if (_import_path(compiler, NULL))
    compiler.parse_macro_lisp_top_level();
  else compiler.skip_macro_lisp();
}

static Var _sdk_identifier_result(Var value) {
  match (value)
    case %("x2c.ident" (!is ?spelling type string)): return spelling;
  return value is <list> &&
         binding_identity_try_parts(value, NULL, NULL) ? value : void;
}

static Var _sdk_symbol_set(List values) {
  $_sdk_guard("x2c._symbol-set");
  foreach (Var value, values)
    if (value is not <symbol>)
      return _sdk_reject(
        "x2c._symbol-set requires Symbols",
        %("value:" ${value.repr()}));
  int duplicate = -1;
  List expression = macro_sdk_compiler.symbol_set_expression(
    values, &duplicate);
  if (duplicate >= 0)
    return _sdk_reject(
      "x2c._symbol-set requires distinct Symbols",
      %("symbol:" ${values.getindex(duplicate).repr()}));
  return expression;
}

/** Converts a compile-time Lisp value into a bound expression AST.
    Integers, `String`s, `Symbol`s, compiler-issued identifiers, and nonempty
    syntax `List`s are accepted; `invocation` locates an unsupported result.
*/
List Compiler.lift_macro_lisp_expression(
  Compiler compiler, Var value, Token invocation) {
  if (value.is_integer()) return %(expr (int) (literal (int) ${value.str()}));
  if (value is <string>)
    return %(expr (* char) (literal (* char) ${value.repr()}));
  if (value is <symbol>)
    return %(expr ("Symbol") (literal ("Symbol")
                  ${value.symbol().str()} ${value.symbol()}));
  Var identifier = _sdk_identifier_result(value);
  if (identifier is not void) return %(expr () (ident $identifier));
  if (value is <list> && !value.is_nil())
    return compiler.bind_syntax(value, AST_EXPRESSION, NULL);
  compiler.report_error(
    <macro>, "compile-time Lisp result cannot fill an expression slot",
    invocation, %( "value:" ${value.repr()} ));
}

/** Parses a compile-time Lisp form in an expression position.
    Macro-definition parsing records a deferred slot; ordinary parsing
    evaluates the form in the translation unit's Lisp session and lifts it.
*/
List Compiler.parse_macro_lisp_expression(Compiler compiler) {
  Token invocation = compiler.token;
  String form = _lisp_form(compiler);
  if (compiler.macro_holes) return %(expr (<macro-expr>) (macro-slot 0 $form));
  _ensure_lisp(compiler);
  Var value = _eval_string(compiler, form, invocation);
  return compiler.lift_macro_lisp_expression(value, invocation);
}

static List _lisp_construction(Compiler compiler, String form) {
  Tokenizer tokenizer = Tokenizer.new_mode(form, <macro-lisp>);
  tokenizer.scan();
  Array construction = %[];
  Map seen = %{};
  Token token = tokenizer.next();
  while (token && token.type != <eof>) {
    if (token.type == <$>) {
      Token name = tokenizer.next();
      if (name && name.type == <ident>) {
        List hole = _hole_record(compiler, Atom.intern(name.text));
        if (hole && hole.assoc(<kind>) == <unit>) {
          Var binder = _replacement_binder(
            hole.assoc(<binder>), "construction", 1);
          if (!seen.contains(binder)) {
            seen[binder] = 1;
            construction.push(binder);
          }
        }
      }
      token = name;
    }
    token = tokenizer.next();
  }
  return construction.list_free();
}

static List _parse_lisp_slot(
  Compiler compiler, int allow_sequence, Symbol role) {
  String form = _lisp_form(compiler);
  int splice = compiler.test(<...>);
  if (splice && !allow_sequence)
    compiler.report_error(
      <parse>, "sequence insertion is not legal in this syntax slot",
      compiler.token, NULL);
  Var target = compiler.macro_holes[%(target)];
  List construction = _lisp_construction(compiler, form);
  if (target is <list>) {
    Var binder = target.list().assoc(<binder>);
    if (role == <name>) {
      Var required = _replacement_binder(binder, "construction", 1);
      construction = construction.append(%((target $required)));
    }
    else if (role == <unit>) {
      Var required = _replacement_binder(binder, "construction", 1);
      construction = construction.append(%($required));
    }
  }
  return %(
    macro-slot $splice $form
    @construction
  );
}

static Var _eval_template_form(
  Compiler compiler, String form, List bindings, Token invocation,
  String source_file, Var construction) {
  _ensure_lisp(compiler);
  /* Provenance lookup uses captured Var identity. Structural equality must
     not let constructed or selected syntax acquire a caller's source text. */
  List references = NULL, Map source_captures = %{};
  foreach (List pair, bindings) {
    if (!pair) continue;
    Var (binder, syntax) = pair;
    String spelling = binder.str()[1:];
    String temporary =
      %"_x2c_meta_${compiler.macro_count}_$spelling";
    Var unwrapped = _source_unwrap(syntax);
    List source = NULL;
    if (_source_capture_parts(syntax, &source, &unwrapped)) {
      Var key = ((ulong) unwrapped.u64);
      source_captures[key] = source;
    }
    compiler.macro_lisp.set_global(temporary, unwrapped);
    references = cons(%($spelling $temporary), references);
  }
  if (references) {
    Tokenizer tokenizer = Tokenizer.new_mode(form, <macro-lisp>);
    tokenizer.scan();
    Buffer rewritten = Buffer.new(0);
    defer rewritten.free();
    int copied = 0;
    Token token = tokenizer.next();
    while (token && token.type != <eof>) {
      if (token.type == <$>) {
        Token name = tokenizer.next();
        Var replacement = name && name.type == <ident>
                        ? references.assoc(name.text) : void;
        String temporary = replacement is <string>
                         ? replacement.str() : NULL;
        if (temporary) {
          rewritten.write_len(form + copied, token.pos - copied);
          rewritten.write(temporary);
          copied = name.pos + name.len;
          token = tokenizer.next();
          continue;
        }
        token = name;
        continue;
      }
      token = tokenizer.next();
    }
    rewritten.write_len(form + copied, form.len() - copied);
    form = rewritten;
  }
  if (construction is not void) {
    String temporary = %"_x2c_meta_${
      compiler.macro_count}_construction";
    compiler.macro_lisp.set_global(temporary, construction);
    form = %"(let ((x2c.ident (lambda (name)
      (list $temporary name)))) $form)";
  }
  Compiler previous = macro_sdk_compiler;
  String old_src_file = macro_sdk_source_file;
  String old_failure = macro_sdk_failure_message;
  List old_notes = macro_sdk_failure_notes;
  Map old_sources = macro_sdk_source_captures;
  int old_has_references = macro_sdk_has_references;
  macro_sdk_compiler = compiler;
  macro_sdk_source_file = source_file;
  macro_sdk_failure_message = NULL;
  macro_sdk_failure_notes = NULL;
  macro_sdk_source_captures = source_captures;
  macro_sdk_has_references = !!references;
  Var result = void;
  {
    defer {
      macro_sdk_compiler = previous;
      macro_sdk_source_file = old_src_file;
      macro_sdk_failure_message = old_failure;
      macro_sdk_failure_notes = old_notes;
      macro_sdk_source_captures = old_sources;
      macro_sdk_has_references = old_has_references;
    }
    result = _eval_string(compiler, form, invocation);
    if (macro_sdk_failure_message) {
      String message = macro_sdk_failure_message;
      List notes = macro_sdk_failure_notes;
      macro_sdk_compiler = previous;
      macro_sdk_source_file = old_src_file;
      macro_sdk_failure_message = old_failure;
      macro_sdk_failure_notes = old_notes;
      macro_sdk_source_captures = old_sources;
      macro_sdk_has_references = old_has_references;
      compiler.report_error(<macro>, message, invocation, notes);
    }
  }
  return result;
}

/** Evaluates an active template's `(macro-slot ...)` value.
    Non-slots and slots outside an expansion are returned unchanged. A splice
    slot's `List` result is wrapped as `(seq ...)` for its syntax position.
*/
Var Compiler.evaluate_macro_slot(Compiler compiler, Var value) {
  if (value is not <list>) return value;
  List slot = value;
  if (slot.car() != <macro-slot>) return value;
  if (compiler.macro_holes || !compiler.macro_stack) return value;
  int splice = slot.cadr().int();
  String form = slot.caddr();
  List active = compiler.macro_stack.car();
  (List definition, Var input, List bindings, Token invocation) = active;
  (void) input;
  String source_file = definition.assoc(<file>);
  Var required = slot.assoc(<construct>);
  Var result = _eval_template_form(
    compiler, form, bindings, invocation, source_file, required);
  Var construction = slot.assoc(<target>);
  if (required is not void && splice) {
    construction = required;
    Var target = _source_unwrap(required);
    Var evaluated = result;
    result = void;
    match (evaluated)
      case %(*before $target *after):
        result = %(@before $required @after);
    if (result is void)
      evaluated.list().try_match_replace(
        %(*before (falias $target ?native) *after),
        %(*before (falias $required ?native) *after),
        &result
      );
  }
  if (construction is not void) {
    String exact = NULL;
    match (result)
      case %("x2c.ident" (!is ?spelling type string)):
        exact = spelling;
    if (exact) result = %($construction $exact);
  }
  return splice && result is <list>
    ? %(seq @{result}).var() : result;
}

/** Evaluates a macro slot and returns its syntax as a row sequence.
    `(seq ...)` contributes its children; every other result contributes one
    row.
*/
List Compiler.evaluate_macro_rows(Compiler compiler, Var value) {
  value = compiler.evaluate_macro_slot(value);
  return value is <list> && !value.is_nil() &&
         value.list().car() == <seq>
       ? value.list().cdr() : %($value);
}

static List _introduced_binding(
  Compiler compiler, Map introduced, String source) {
  Var stored;
  if (introduced.try_get(source, &stored)) return stored;
  List binding = compiler.sym.introduce(
    compiler.fresh_name(%"macro_$source"));
  introduced[source] = binding;
  return binding;
}

static Atom _replacement_binder(Var binder, String projection, int seq) {
  String prefix = seq ? "*" : "?", name = binder.str();
  return Atom.intern(%"${prefix}__macro_${projection}_${name[1:]}");
}

static Atom _local_binder(String name) => Atom.intern(%"?__macro_local_$name");

static Var _replace_definition_bindings(Var value, Map bindings) {
  int candidate = value.is_binder();
  if (!candidate && value is <list> && !value.is_nil())
    candidate = binding_identity_try_parts(value, NULL, NULL);
  Var replacement;
  if (candidate && bindings.try_get(value, &replacement)) return replacement;
  if (value is not <list> || value.is_nil()) return value;
  Array items = %[];
  defer items.free();
  int changed = 0;
  foreach (Var child, value.list()) {
    Var item = _replace_definition_bindings(child, bindings);
    changed |= item != child;
    items.push(item);
  }
  return changed ? items.list().var() : value;
}

/** Returns the definition-local binding identity for `spelling`.
    Repeated uses share one identity while the template is parsed. An active
    macro-definition locals map is required.
*/
List Compiler.macro_introduced_name(Compiler compiler, String spelling) {
  Map locals = compiler.macro_definition_locals();
  Var stored;
  if (locals.try_get(spelling, &stored)) return stored;
  Var order = locals[<order>];
  int identity = INT_MAX - (order is <list> ? order.list().len() : 0);
  List introduced = binding_identity_new(identity, spelling);
  compiler.semantic_binding_facts()[%(known $identity)] = spelling;
  locals[<order>] = cons(spelling, order is <list> ? order.list() : NULL);
  locals[spelling] = introduced;
  locals[introduced] = spelling;
  return introduced;
}

static void _template_binders(Var value, Map binders) {
  if (value.is_binder()) {
    binders[value] = 1;
    return;
  }
  if (value is not <list>) return;
  foreach (Var child, value.list()) _template_binders(child, binders);
}

static Var _projection(Map binders, Var binder, Var otherwise) =>
  binders.contains(binder) ? binder : otherwise;

/* A hole has source, value, expression, and splice projections. A singular
   Function hole also has return and declarator projections, while a Unit hole
   may carry construction requirements. The stored Match pattern binds only
   projections used by the template; the author binder exposes the captured
   value to compile-time Lisp. */
static List _capture_pattern(List hole, Map binders) {
  Var author = hole.assoc(<binder>);
  int sequence = hole.assoc(<sequence>).int();
  Var source_binder = _replacement_binder(author, "source", sequence);
  Var value_binder = _replacement_binder(author, "value", sequence);
  Var expression_binder = _replacement_binder(
    author, "expression", sequence);
  Var splice_binder = _replacement_binder(author, "splice", 1);
  Var one = sequence ? <*>.var() : <?>.var();
  Var source = _projection(binders, source_binder, one);
  Var value = _projection(binders, value_binder, one);
  Var expression = _projection(binders, expression_binder, one);
  Var splice = _projection(binders, splice_binder, <*>);
  if (!sequence && hole.assoc(<kind>) == <function>) {
    Var result = _replacement_binder(author, "return", 0);
    Var declarator = _replacement_binder(author, "declarator", 0);
    value = %(
      !and $value
      (function
        ${_projection(binders, result, <?>)}
        ${_projection(binders, declarator, <?>)}
        ?)
    );
  }
  List source_pattern = %(
    !and (source $author) (source $source)
  );
  List capture = sequence
    ? %(
      capture $source_pattern
              (!and (value $value) (value $expression) (value $splice))
    )
    : %(
      capture $source_pattern (value $value)
              (expression $expression) (splice $splice)
    );
  Var construction = _replacement_binder(author, "construction", 1);
  if (hole.assoc(<kind>) == <unit> &&
      (binders.contains(author) ||
       binders.contains(source_binder) ||
       binders.contains(value_binder) ||
       binders.contains(splice_binder) ||
       binders.contains(construction))) {
    capture = capture.append(%($construction));
  }
  return capture;
}

static List _invocation_pattern(
  Symbol kind, List target, List parameters, List fresh, List template) {
  Map binders = %{};
  _template_binders(template, binders);
  Array arguments = %[];
  foreach (List parameter, parameters)
    arguments.push(_capture_pattern(parameter, binders));
  List invocation = kind == <decorator>
    ? %(
      target (args @{arguments.list_free()})
      ${_capture_pattern(target, binders)}
    ) : %(args @{arguments.list_free()});
  Array fresh_patterns = %[];
  foreach (Var row, fresh) {
    Var (binder, spelling, lisp) = row;
    (void) spelling;
    if (lisp.int()) {
      List hole = %(
        macro-param (binder $binder) (kind name)
                    (sequence 0)
      );
      fresh_patterns.push(_capture_pattern(hole, binders));
    }
  }
  List captures = fresh_patterns.list_free();
  return captures ? invocation.append(%((fresh @captures))) : invocation;
}

/* Forwarding recognizes the projection binders _capture_pattern creates, so
   the accepted prefixes come from _replacement_binder; <?> supplies its
   empty author name. */
static List _forwarded_prefix_list(void) {
  Array prefixes = %[];
  foreach (String projection, %("expression" "value" "source" "splice"))
    for (int sequence = 0; sequence <= 1; sequence++)
      prefixes.push(_replacement_binder(<?>, projection, sequence).str());
  return prefixes.list_free();
}

static List forwarded_prefixes = _forwarded_prefix_list();

static List _forwarded_capture(Compiler compiler, Var captured) {
  if (!compiler.macro_holes || captured is not <list> || captured.is_nil())
    return NULL;
  Var direct;
  match (captured) {
    case %(expr (<macro-expr>)
           (macro-bind ?slot)): direct = slot;
    case %(macro-bind ?): direct = captured.list().cadr();
  }
  if (direct is void) return NULL;
  String spelling = direct.str(), prefix = NULL;
  foreach (String candidate, forwarded_prefixes)
    if (spelling.startswith(candidate)) {
      prefix = candidate;
      break;
    }
  if (!prefix) return NULL;
  List hole = _hole_record(
    compiler, Atom.intern(spelling[prefix.len():]));
  if (!hole) return NULL;
  Var author = hole.assoc(<binder>);
  int sequence = hole.assoc(<sequence>).int();
  Var source = _replacement_binder(author, "source", sequence);
  if (hole.assoc(<kind>) == <unit>) {
    Var construction = _replacement_binder(author, "construction", 1);
    return %(
      capture (source $source) (value $source)
              (expression $source) (splice) $construction
    );
  }
  if (hole.assoc(<kind>) != <expr>) return NULL;
  Var value = _replacement_binder(author, "value", sequence);
  Var expression = _replacement_binder(author, "expression", sequence);
  Var splice = _replacement_binder(author, "splice", 1);
  return %(
    capture (source $source) (value $value)
            (expression $expression) (splice $splice)
  );
}

/* Capture rows keep exact source apart from syntax projections. Forwarding a
   macro projection reconstructs its original row instead of assigning source
   text to generated syntax; Unit construction requirements travel with it. */
static List _capture_row(Compiler compiler, List hole, List sources) {
  int sequence = hole.assoc(<sequence>).int();
  int singular = !sequence && sources && !sources.cdr();
  Var source = singular ? sources.car() : sources.var();
  if (singular) {
    List forwarded = _forwarded_capture(compiler, source);
    if (forwarded) return forwarded;
  }
  if (sequence) {
    Array captured_sources = %[], values = %[], construction = %[];
    foreach (Var captured, sources) {
      List forwarded = _forwarded_capture(compiler, captured);
      match (forwarded)
        case %(capture (source *forwarded_sources)
                       (value *forwarded_values) ? ? *required): {
          foreach (Var item, forwarded_sources) captured_sources.push(item);
          foreach (Var item, forwarded_values) values.push(item);
          foreach (Var item, required) construction.push(item);
          continue;
        }
      captured_sources.push(captured);
      values.push(_source_unwrap(captured));
    }
    return %(
      capture (source @{captured_sources.list_free()})
              (value @{values.list_free()})
              @{construction.list_free()}
    );
  }
  Var value = _source_unwrap(source), expression = value;
  if (singular) {
    if (value is <string>) expression = %(expr () (ident $value));
    else if (value is <list> && !value.is_nil() &&
             binding_identity_try_parts(value, NULL, NULL))
      expression = %(expr () (ident $value));
  }
  List values = value is <list> ? value.list() : NULL;
  if (!singular)
    return %(
      capture (source @sources) (value @values)
    );
  return %(
    capture (source $source) (value $value)
            (expression $expression) (splice @values)
  );
}

static List _lisp_bindings(List bindings) {
  List result = NULL;
  foreach (List pair, bindings) {
    Var binder = pair.car();
    if (binder.is_binder() &&
        !binder.str().startswith("?__macro_") &&
        !binder.str().startswith("*__macro_"))
      result = cons(pair, result);
  }
  return result.reverse();
}

static String _kind_spelling(Symbol kind) {
  if (kind == <block-item>) return "Statement";
  if (kind == <map-entry>) return "Entry";
  return kind.str().capitalize();
}

static Symbol _author_kind(String spelling) {
  Symbol kind = Symbol.new(spelling);
  if (kind == <statement>) return <block>;
  if (kind == <entry>) return <map-entry>;
  return %(expr type decl function name
           literal param block field enumerator
           map-entry unit).contains(kind)
       ? kind : 0;
}

static int _kind_accepts_role(Symbol kind, Symbol role) {
  Symbol expected = role == <statement> ? <block> : role;
  if (expected == <expression> || expected == <argument>)
    return %(expr name literal).contains(kind);
  return kind == expected ||
    (expected == <field> && kind == <decl>) ||
    (expected == <block> && kind == <decl>) ||
    (expected == <unit> &&
     (kind == <decl> || kind == <function>));
}

static List _hole_record(Compiler compiler, Atom name) {
  Var stored;
  if (!compiler.macro_holes.try_get(name, &stored)) return NULL;
  return stored;
}

static List _hole(Atom binder, Symbol kind, int sequence) => %(
    macro-param
    (binder $binder)
    (kind $kind)
    (sequence $sequence)
  );

static List _parse_signature_hole(Compiler c, int using_hole) {
  Symbol kind = using_hole ? <name> : 0;
  if (!using_hole && c.peek(0) == <ident> && c.peek(1) == <$>) {
    kind = _author_kind(c.token.text);
    if (!kind) {
      String spelling = c.token.text;
      c.report_error(
        <parse>, %"unknown macro hole kind '$spelling'",
        c.token, NULL);
    }
    c.next();
  }
  c.expect(<$>);
  if (c.peek(0) != <ident>)
    c.report_error(
      <parse>, "expected macro hole name after '$'",
      c.token, NULL);
  Token token = c.token;
  String spelling = token.text, Atom name = Atom.intern(spelling);
  c.next();
  int sequence = !using_hole && c.test(<...>);
  if (_hole_record(c, name))
    c.report_error(
      <parse>, %"duplicate macro hole '$spelling'",
      token, NULL);
  List hole = _hole(
    Atom.intern(sequence ? %"*$spelling" : %"?$spelling"),
    kind, sequence);
  c.macro_holes[name] = hole;
  return hole;
}

/** Returns the registered hole descriptor at the current `$NAME`.
    Returns NULL without consuming tokens when the spelling is not a hole.
*/
List Compiler.peek_macro_hole(Compiler compiler) {
  if (compiler.peek(0) != <$> || compiler.peek(1) != <ident>) return NULL;
  Token name = compiler.skip_trivia_from(compiler.token + 1);
  return _hole_record(compiler, Atom.intern(name.text));
}

static List _parse_hole(Compiler c, Symbol role) {
  Token token = c.token;
  c.expect(<$>);
  if (c.peek(0) != <ident>)
    c.report_error(
      <parse>, "expected macro hole name after '$'",
      c.token, NULL);
  Atom name = Atom.intern(c.token.text);
  c.next();
  List hole = _hole_record(c, name);
  if (!hole) {
    String spelling = name.str();
    c.report_error(
      <parse>, %"unbound replacement variable '$spelling'",
      token, NULL);
  }
  int sequence = c.test(<...>);
  if (sequence != hole.assoc(<sequence>).int()) {
    String spelling = name.str();
    String message = sequence
      ? %"singular macro hole '$spelling' cannot be spliced"
      : %"sequence macro hole '$spelling' requires '...'";
    c.report_error(<parse>, message, token, NULL);
  }
  Symbol inferred = role == <expression> || role == <argument>
    ? <expr> : role;
  Symbol kind = hole.assoc(<kind>);
  if (!kind) {
    hole = hole.search_replace(%(kind ?prior), %(kind $inferred));
    c.macro_holes[name] = hole;
  }
  else if (!_kind_accepts_role(kind, role)) {
    String spelling = name.str();
    c.report_error(
      <parse>, %"macro hole '$spelling' has ambiguous kind",
      token,
      %("first: ${_kind_spelling(kind)}"
        "also: ${_kind_spelling(inferred)}" )
    );
  }
  Var binder = hole.assoc(<binder>);
  int splice = sequence || role == <type>;
  int preserve_source = c.macro_holes.contains(%(source $binder));
  String projection = preserve_source ? "source" : splice ? "splice" :
    %(expression argument expr).contains(role) ? "expression" : "value";
  int list_binder = preserve_source
                  ? binder.is_list_binder() : splice;
  Atom replacement = _replacement_binder(
    binder, projection, list_binder);
  return %(macro-bind $replacement);
}

static Token _after_lisp_form(Compiler compiler) {
  Token token = compiler.token;
  int depth = 1;
  while (depth && token.type != <eof>) {
    token = compiler.skip_trivia_from(token + 1);
    if (token.type == <(>) depth++;
    else if (token.type == <)>) depth--;
  }
  return depth ? token : compiler.skip_trivia_from(token + 1);
}

static int _lisp_splice_follows(Compiler compiler) =>
  compiler.peek(0) == <"$("> &&
         _after_lisp_form(compiler).type == <...>;

/** Returns whether tokens after the current Lisp form continue a declaration.
    The balanced form and following trivia are inspected without moving the
    compiler cursor.
*/
int Compiler.macro_lisp_starts_declaration(Compiler compiler) {
  Token token = _after_lisp_form(compiler);
  return token.type == <$> || token.type == <ident> ||
         token.type == <*> || token.type == <(>;
}

/** Parses a macro hole or Lisp slot for `role` while reading a template.
    Returns role-shaped syntax containing `(macro-bind ...)` or
    `(macro-slot ...)`, or NULL when ordinary grammar owns the current tokens;
    successful parsing advances the cursor.
*/
List Compiler.try_parse_macro_slot(Compiler compiler, Symbol role) {
  if (!compiler.macro_holes) return NULL;
  if (compiler.peek(0) == <"$(">) {
    int splice = _lisp_splice_follows(compiler);
    if (%(field enumerator map-entry unit).contains(role) && !splice)
      return NULL;
    if (role == <block> && compiler.macro_lisp_starts_declaration())
      return NULL;
    if (role == <statement>) return NULL;
    if (role == <expression>) return compiler.parse_macro_lisp_expression();
    int allow_sequence =
      %(argument block field enumerator map-entry param unit)
        .contains(role);
    return _parse_lisp_slot(compiler, allow_sequence, role);
  }
  List hole = compiler.peek_macro_hole();
  if (!hole ||
      (role == <argument> && !hole.assoc(<sequence>).int()) ||
      (role == <statement> && compiler.peek(2) == <(>)) return NULL;
  if (role == <expression> && hole.assoc(<sequence>).int())
    compiler.report_error(
      <parse>, "sequence insertion is not legal in an expression slot",
      compiler.token, NULL);
  if (!%(expression argument type).contains(role)) {
    Symbol kind = hole.assoc(<kind>);
    if (!kind && compiler.peek(2) != <...>) return NULL;
    if (kind && !_kind_accepts_role(kind, role)) return NULL;
  }
  List syntax = _parse_hole(compiler, role);
  return syntax && role == <expression>
       ? %(expr (<macro-expr>) $syntax) : syntax;
}

static List _parse_body(Compiler c, Symbol result_kind) {
  c.expect(<"{">);
  if (result_kind == <block-item>) {
    List block = c.parse_block_items(0);
    return cons(<seq>, block.cdr());
  }
  if (result_kind == <field>) {
    List fields = c.peek(0) == <"}">
      ? NULL : c.parse_fields(%(struct ()));
    c.expect(<"}">);
    return %(seq @fields);
  }
  if (result_kind == <enumerator>) {
    List enumerators = c.parse_enumerators(%(enum ()));
    c.expect(<"}">);
    return %(seq @enumerators);
  }
  if (result_kind == <map-entry>) {
    List entries = c.parse_map_entries();
    c.expect(<"}">);
    return %(seq @entries);
  }
  Array items = %[];
  while (c.peek(0) != <"}">) {
    foreach (Var directive, c.leading_preproc()) items.push(directive);
    if (c.peek(0) == <"}">) break;
    items.push(c.parse_top_level());
  }
  c.expect(<"}">);
  List replacement = %(seq @{items.list_free()});
  return replacement;
}

static Symbol _result_kind_token(Compiler compiler, Token token) {
  String spelling = token.text, Symbol kind = Symbol.new(spelling);
  if (kind == <statement> || kind == <block>) return <block-item>;
  if (kind == <entry>) return <map-entry>;
  if (kind == <decorator>) return kind;
  if (%(expression field enumerator map-entry unit).contains(kind))
    return kind;
  compiler.report_error(
    <parse>, %"unknown macro result kind '$spelling'",
    token, NULL);
}

static Atom _hole_name(List hole) {
  String binder = hole.assoc(<binder>).str();
  return Atom.intern(binder[1:]);
}

static List _parameter_rows(Compiler compiler, List parameters) {
  Array rows = %[];
  foreach (List parameter, parameters)
    rows.push(_hole_record(compiler, _hole_name(parameter)));
  return rows.list_free();
}

static List _definition(
  Atom name, Symbol kind, Symbol target_kind, List target_parameter,
  List parameters, List fresh, List captures, List pattern, List template,
  List origin, String source_file, int imported, int builtin, int local) => %(
    macrodef
    (name $name)
    (kind $kind)
    (target $target_kind)
    (targetp $target_parameter)
    (parameters $parameters)
    (fresh $fresh)
    (captures $captures)
    (pattern $pattern)
    (template $template)
    (origin $origin)
    (file $source_file)
    (imported $imported)
    (builtin $builtin)
    (local $local)
  );

/** Parses the macro definition at the current token into a `macrodef` `List`.
    A source-level definition is published immediately; a definition inside a
    template remains syntax for later binding at its expansion site.
*/
List Compiler.parse_macro_definition(Compiler c) {
  Token start = c.token;
  c.expect(<ident>);
  if (c.peek(0) == <$>)
    c.report_error(
      <parse>, "macro definition requires a result kind before '$'",
      c.token,
      %("write the result kind between 'macro' and the macro name"));
  int local = c.peek(0) == <ident> &&
              c.peek(1) == <ident> && c.peek(2) == <(>;
  if (c.peek(0) != <ident> || (!local && c.peek(1) != <$>))
    c.report_error(
      <parse>, "expected macro result kind before '$'",
      c.token, NULL);
  Token kind_token = c.token;
  c.next();
  Symbol result_kind = _result_kind_token(c, kind_token);
  Atom name;
  if (local) {
    name = Atom.intern(c.token.text);
    c.next();
  }
  else name = _name(c);
  String spelling = name.str();
  if (local && name == <with>)
    c.report_error(
      <macro>, "'with' cannot be a local macro name", start, NULL);
  if (spelling.startswith("x2c.") && !c.builtin_defs)
    c.report_error(
      <parse>, %"macro name '$spelling' is reserved",
      start, %("x2c.* is reserved for compiler facilities"));
  Var existing;
  if (c.import_src &&
      c.macros.try_get(name, &existing)) {
    List previous = existing;
    c.report_error(
      <macro>, %"imported macro '$spelling' collides with a visible macro",
      start,
      %(${_definition_note(previous)}
        "import: ${c.display_path(
          c.import_src)}")
    );
  }

  Map old_holes = c.macro_holes;
  c.macro_holes = %{};
  Map definition_locals = %{};
  c.macro_holes[%(locals)] = definition_locals;
  List parameters = NULL, using_holes = NULL;
  List target_hole = NULL;
  c.expect(<(>); if (!c.test(<)>)) {
    int first = 1;
    loop {
      List hole = _parse_signature_hole(c, 0);
      if (result_kind == <decorator> && first) {
        if (!%(expr function block field unit)
               .contains(hole.assoc(<kind>)))
          c.report_error(
            <parse>,
            "decorator first parameter has invalid target kind",
            start,
            %(
              "expected Expression, Function, Statement, Block, Field, or Unit"
            )
          );
        if (hole.assoc(<sequence>).int())
          c.report_error(
            <parse>, "decorator target parameter must be singular",
            start, NULL);
        target_hole = hole;
        if (hole.assoc(<kind>) == <unit>) {
          c.macro_holes[%(source ${hole.assoc(<binder>)})] = 1;
          c.macro_holes[%(target)] = hole;
        }
      }
      else parameters = cons(hole, parameters);
      first = 0;
      if (hole.assoc(<sequence>).int() && c.peek(0) == <,>)
        c.report_error(
          <parse>, "sequence macro hole must be the final argument",
          c.token, NULL);
      if (!c.test(<,>)) break;
    }
    c.expect(<)>);
  }
  if (result_kind == <decorator> && !target_hole)
    c.report_error(
      <parse>,
      "decorator requires a first target parameter",
      start, NULL);
  if (local && result_kind == <unit>)
    c.report_error(
      <macro>, "local macros cannot have Unit results", start, NULL);
  if (local && result_kind == <decorator> &&
      (target_hole.assoc(<kind>) == <function> ||
       target_hole.assoc(<kind>) == <unit>)) {
    String target = _kind_spelling(target_hole.assoc(<kind>));
    c.report_error(
      <macro>, %"local decorators cannot target $target syntax",
      start, NULL);
  }
  if (c.peek(0) == <ident> && c.token.text == "using") {
    c.next();
    loop {
      List hole = _parse_signature_hole(c, 1);
      using_holes = cons(hole.assoc(<binder>), using_holes);
      if (!c.test(<,>)) break;
    }
  }
  if (c.peek(0) == <:>)
    c.report_error(
      <parse>,
      "macro result kind belongs after 'macro', before the '$' name",
      c.token, NULL);
  c.expect(<=>);
  c.expect(<">">);
  Symbol target_kind = 0;
  if (target_hole) target_kind = target_hole.assoc(<kind>);
  int expression_result = result_kind == <expression> ||
    (result_kind == <decorator> && target_kind == <expr>);
  if (c.peek(0) == <(>) {
    if (!expression_result)
      c.report_error(
        <parse>,
        "parenthesized macro body requires Expression result or target",
        c.token, NULL);
  }
  else if (c.peek(0) == <"{">) {
    if (expression_result)
      c.report_error(
        <parse>,
        "braced macro body requires Statement, Block, Field, Entry, " +
        "Enumerator, Unit, or non-Expression Decorator result",
        c.token, NULL
      );
  }
  else
    c.report_error(
      <parse>, "expected parenthesized or braced macro body",
      c.token, NULL);

  parameters = parameters.reverse();
  using_holes = using_holes.reverse();
  (void) c.record_origin(start);
  List origin = c.token_location(start);
  String source_file = _source_file(c, c.filename);
  int imported = c.import_src != NULL, builtin = c.builtin_defs;
  List definition = _definition(
    name, result_kind, target_kind,
    target_hole, parameters, NULL, NULL,
    NULL, NULL, origin, source_file, imported, builtin, local);
  if (local) c.sym.define_macro(name, definition);
  else if (!old_holes) c.macros[name] = definition;

  Map old_local_macro_captures = c.local_macro_captures;
  int old_local_macro_capture_scopes = c.local_macro_capture_scopes;
  c.local_macro_captures = local ? %{} : NULL;
  Map definition_captures = c.local_macro_captures;
  c.local_macro_capture_scopes = c.sym.scope_count();
  c.sym.push_new_scope();
  List replacement = NULL, local_names = NULL;
  {
    defer {
      c.sym.pop_scope();
      c.macro_holes = old_holes;
      c.local_macro_captures = old_local_macro_captures;
      c.local_macro_capture_scopes = old_local_macro_capture_scopes;
    }
    if (expression_result) {
      c.expect(<(>); replacement = c.parse_expression(); c.expect(<)>);
    }
    else {
      Symbol replacement_kind = result_kind;
      if (result_kind == <decorator>)
        replacement_kind =
          target_kind == <function> || target_kind == <block>
            ? <block-item> : target_kind;
      replacement = _parse_body(c, replacement_kind);
    }
    parameters = _parameter_rows(c, parameters);
    Var local_order = definition_locals[<order>];
    local_names = local_order is <list>
                ? local_order.list().reverse() : NULL;
  }

  if (result_kind == <decorator> && target_kind == <function>) {
    Var target_binder = target_hole.assoc(<binder>);
    Var return_binder = _replacement_binder(
      target_binder, "return", 0);
    Var declarator_binder = _replacement_binder(
      target_binder, "declarator", 0);
    match (replacement)
      case %(seq *body):
        replacement = %(
          seq
            (function $return_binder $declarator_binder (block @body))
        );
  }
  else if (result_kind == <decorator> && target_kind == <expr>)
    replacement = %(expr (<macro-expr>) (parens $replacement));

  List bindings;
  Var expression_slot = %(
    expr (<macro-expr>) (macro-bind ?binder)
  );
  if (replacement.try_match(expression_slot, &bindings))
    replacement = replacement.search_replace(
      %(macro-bind ?binder), <?binder>);
  else replacement = replacement.search_replace(
    %(!or
      (expr (<macro-expr>) (macro-bind ?binder))
      (macro-bind ?binder)),
    <?binder>
  );
  /* Parsed literal names carry definition-only identities. Store binders in
     the template instead, so each expansion can allocate one fresh semantic
     identity per literal spelling and reuse it throughout that expansion. */
  Map definition_bindings = %{};
  if (target_hole && target_hole.assoc(<kind>) == <unit>) {
    Var required = _replacement_binder(
      target_hole.assoc(<binder>), "construction", 1);
    foreach (List parameter, parameters)
      if (parameter.assoc(<kind>) == <name>) {
        Var name = _replacement_binder(
          parameter.assoc(<binder>), "value", 0);
        Var constructed = %($required $name);
        definition_bindings[name] = constructed;
      }
  }
  foreach (Var local, local_names) {
    Var identity = definition_locals[local];
    Var binder = _local_binder(local.str());
    definition_bindings[identity] = binder;
  }
  replacement = _replace_definition_bindings(
    replacement, definition_bindings);
  foreach (Var stored, parameters) {
    List hole = stored;
    if (!hole.assoc(<kind>)) {
      String hole_spelling = hole.assoc(<binder>).str()[1:];
      c.report_error(
        <parse>,
        %"macro hole '$hole_spelling' has no inferred kind",
        start, %("annotate holes used only by compile-time Lisp"));
    }
  }
  Array fresh = %[];
  foreach (Var binder, using_holes)
    fresh.push(%($binder ${binder.str()[1:]} 1));
  foreach (Var local, local_names)
    fresh.push(%(${_local_binder(local.str())} $local 0));
  List fresh_rows = fresh.list_free();
  Var capture_order = (void *) definition_captures != NULL
    ? definition_captures[<order>] : void;
  List captures = capture_order is <list>
                ? capture_order.list().reverse() : NULL;
  List pattern = _invocation_pattern(
    result_kind, target_hole, parameters, fresh_rows, replacement);
  definition = _definition(
    name, result_kind, target_kind, target_hole, parameters,
    fresh_rows, captures,
    pattern, replacement, origin, source_file, imported, builtin, local);
  if (local) c.sym.define_macro(name, definition);
  else if (!old_holes) c.publish_macro_definition_node(definition);
  return definition;
}

/** Publishes a canonical `macrodef` in source order and returns `node`.
    A later definition with the same name affects only later invocations.
*/
List Compiler.publish_macro_definition_node(Compiler compiler, List node) {
  compiler.macros[node.assoc(<name>)] = node;
  return node;
}

static List _lookup(Compiler compiler, Atom name, Token invocation) {
  Var stored;
  String spelling = name.str();
  if (!_try_definition(compiler, name, 1, &stored))
    compiler.report_error(
      <parse>, %"unknown or forward-referenced macro '$spelling'",
      invocation, NULL);
  return stored;
}

static List _keyword_alias_lookup(Compiler compiler) {
  if (compiler.peek(0) != <ident>) return NULL;
  Atom name = Atom.intern(compiler.token.text);
  List local = compiler.sym.has_local_macros()
             ? compiler.sym.lookup_macro(name) : NULL;
  if (local) return local;
  Var stored;
  if (!compiler.kw_aliases.try_get(name, &stored))
    return NULL;
  return stored;
}

static int _keyword_alias_requires_arguments(List definition) =>
  definition.assoc(<kind>) != <decorator> ||
         definition.assoc(<parameters>).list();

static int _keyword_alias_invocation_follows(
  Compiler compiler, List definition) {
  return definition &&
    (!_keyword_alias_requires_arguments(definition) ||
     compiler.peek(1) == <(>);
}

/** Parses and installs one source-local `keyword` alias.
    The named macro must already be visible; the alias captures that definition
    and consumes its terminating semicolon.
*/
void Compiler.parse_keyword_definition(Compiler c) {
  Token declaration = c.token;
  c.expect(<ident>);
  if (c.peek(0) != <ident>)
    c.report_error(
      <parse>, "keyword alias requires an identifier",
      c.token, NULL);
  Atom alias = Atom.intern(c.token.text);
  c.next();
  Var existing;
  if (!c.builtin_defs &&
      (alias == <with> ||
       (c.kw_aliases.try_get(alias, &existing) &&
        existing.list().assoc(<builtin>).int())))
    c.report_error(
      <macro>, "built-in keyword alias cannot be replaced",
      declaration, NULL);
  Token reference = c.token;
  Atom name = _name(c);
  List definition = _lookup(c, name, reference);
  if (!%(expression block-item field enumerator map-entry
         unit decorator)
       .contains(definition.assoc(<kind>)))
    c.report_error(
      <macro>, %"keyword alias cannot name internal macro kind '${
        _kind_spelling(definition.assoc(<kind>))}'",
      declaration, %(${_definition_note(definition)})
    );
  c.expect(<;>);
  c.kw_aliases[alias] = definition;
}

static int _keyword_alias_is_expression(Compiler compiler, List definition) {
  if (!_keyword_alias_invocation_follows(compiler, definition)) return 0;
  if (_keyword_alias_requires_arguments(definition)) return 1;
  return definition.assoc(<kind>) == <expression> ||
    (definition.assoc(<kind>) == <decorator> &&
     definition.assoc(<target>) == <expr>);
}

static int _keyword_alias_targets_at(
  Compiler compiler, List definition, AstPos position) {
  if (!_keyword_alias_invocation_follows(compiler, definition)) return 0;
  Symbol kind = definition.assoc(<kind>);
  Symbol target_kind = definition.assoc(<target>);
  if (position == AST_STATEMENT && definition.assoc(<local>).int() &&
      (kind == <expression> ||
       (kind == <decorator> && target_kind == <expr>))) return 0;
  if (position == AST_MAP_ENTRY) return kind == <map-entry>;
  if (_keyword_alias_requires_arguments(definition)) {
    if (position != AST_BLOCK) return 1;
    return kind != <expression> &&
      (kind != <decorator> || target_kind != <expr>);
  }
  Symbol expected = _position(position).kind;
  return kind == expected ||
    (kind == <decorator> &&
     _decorator_result_kind(target_kind) == expected);
}

/** Returns whether the parser should claim the current alias at `position`.
    An argument-taking invocation may be claimed before result-kind validation
    so target parsing can report a wrong-position diagnostic. Bare forms must
    already fit the position. This query does not consume tokens.
*/
int Compiler.keyword_alias_starts_target_at(
  Compiler compiler, AstPos position) => _keyword_alias_targets_at(
    compiler, _keyword_alias_lookup(compiler), position);

/** Returns whether the current keyword alias needs shallow expansion.
    A visible invocation qualifies when its captured `Unit` definition is
    imported, or when its local template contains protocol or adoption rows.
*/
int Compiler.keyword_alias_needs_shallow_expansion(Compiler compiler) {
  List definition = _keyword_alias_lookup(compiler);
  return _keyword_alias_invocation_follows(compiler, definition) &&
         _definition_needs_shallow_expansion(definition);
}

/** Consumes the current keyword alias and any required argument list.
    Its terminator or following decorator target remains current.
*/
void Compiler.skip_keyword_alias(Compiler compiler) {
  List definition = _keyword_alias_lookup(compiler);
  if (!definition)
    compiler.report_error(
      <parse>, "expected keyword alias", compiler.token, NULL);
  compiler.next();
  if (_keyword_alias_requires_arguments(definition))
    _skip_balanced_tokens(compiler, <(>, <)>);
}

/* `(src (source FILE BEGIN END) SYNTAX)` records one complete caller argument
   or decorator target. Constructed syntax can reproduce that List shape, so
   source access trusts only captured syntax identities registered for the
   active expansion. Forwarding preserves the registered capture. */
static int _source_capture_parts(Var value, List *source, Var *syntax) {
  match (value)
    case %(src ?record ?captured): {
      if (source) *source = record;
      if (syntax) *syntax = captured;
      return 1;
    }
  return 0;
}

static Var _source_unwrap(Var value) {
  if (value is not <list> || value.is_nil()) return value;
  return value.list().search_replace(%(src ? ?syntax), <?syntax>);
}

static Token _previous_source_token(Compiler compiler, Token after) {
  Token first = (void *) compiler.tokenizer.tokens;
  if (!after || after <= first) return NULL;
  Token token = after - 1;
  while (token > first &&
         (token.type == <space> || token.type == <comment> ||
          token.type == <preproc>)) token--;
  return token;
}

static Var _capture_source(
  Compiler compiler, Var syntax, Token first, Token after) {
  if (compiler.macro_holes || syntax is not <list> ||
      syntax.is_nil() || !first) return syntax;
  Token last = _previous_source_token(compiler, after);
  if (!last || last < first) return syntax;
  int end = last.pos + last.len;
  String file = _source_file(
    compiler, compiler.filename ? compiler.filename : %"<stdin>");
  List source = %(source $file ${first.pos} $end);
  Var result = %(src $source $syntax);
  return result;
}

static Var _parse_argument(Compiler c, Symbol kind) {
  if (!kind) return c.parse_assignment();
  switch (kind) {
    case <expr>: return c.parse_assignment();
    case <type>: return c.parse_type_name();
    case <decl>: return c.parse_declaration_argument();
    case <function>: return c.parse_function_definition();
    case <param>: return c.parse_parameter();
    case <block>: return c.parse_block_item();
    case <field>: return c.parse_field(%(struct ()));
    case <enumerator>: return c.parse_enumerator(c.aggregate_type);
    case <map-entry>: return c.parse_map_entry();
    case <unit>: return c.parse_top_level();
    case <name>: {
      if (c.macro_holes && c.peek(0) == <$>)
        return _parse_hole(c, <name>);
      if (c.peek(0) != <ident>)
        c.report_error(
          <parse>, "Name macro argument requires an identifier",
          c.token, NULL);
      String spelling = c.token.text;
      c.next();
      return spelling;
    }
    case <literal>:
      if (c.macro_holes && c.peek(0) == <$>) return c.parse_assignment();
      return c.parse_atomic_literal();
  }
  c.report_error(
    <macro>, "macro argument has no parsing contract",
    c.token, NULL);
}

static List _invocation_arguments(Compiler c, List definition) {
  Array arguments = %[];
  c.expect(
    <(>);
  List descriptors = definition.assoc(<parameters>);
  for (List nodes = descriptors; nodes; nodes = nodes.cdr()) {
    List hole = nodes.car();
    Symbol kind = hole.assoc(<kind>);
    int sequence = hole.assoc(<sequence>).int();
    Array captured = %[];
    if (c.peek(0) == <)> && !sequence)
      c.report_error(
        <parse>, "macro invocation has too few arguments",
        c.token, NULL);
    if (c.peek(0) != <)>) {
      loop {
        Token first = c.token;
        Var argument = _parse_argument(c, kind);
        if (kind != <name>)
          argument = _capture_source(c, argument, first, c.token);
        captured.push(argument);
        if (!sequence || !c.test(<,>)) break;
      }
    }
    List capture = _capture_row(c, hole, captured.list_free());
    arguments.push(capture);
    if (nodes.cdr() && c.peek(0) != <)>)
      c.expect(<,>);
  }
  if (c.peek(0) != <)>) {
    if (c.peek(0) == <,>) c.next();
    c.report_error(
      <parse>, "macro invocation has too many arguments",
      c.token, NULL);
  }
  c.expect(<)>);
  List result = %(args @{arguments.list_free()});
  return result;
}

static void _bind_name_arguments(
  Compiler compiler, List definition, List arguments) {
  List parameters = definition.assoc(<parameters>);
  List captures = arguments.cdr();
  while (parameters) {
    List parameter = parameters.car();
    if (parameter.assoc(<kind>) == <name>) {
      Var names = captures.car().list().assoc(<value>);
      List values = parameter.assoc(<sequence>).int()
                  ? names.list() : %($names);
      foreach (String name, values)
        compiler.sym.reference(%($name), NULL);
    }
    parameters = parameters.cdr();
    captures = captures.cdr();
  }
}

static List _invocation_node(
  Compiler compiler, List definition, List input, Token invocation) {
  Var stored = definition;
  Var site = invocation;
  if (compiler.macro_holes) {
    stored = definition.assoc(<template>)
      ? %(!quote $definition).var()
      : definition.assoc(<local>).int()
        ? %(local-macro ${definition.assoc(<name>)}).var()
        : definition.assoc(<name>);
    site = <m-invoke>;
  }
  return %(macro-invoke $stored $input $site);
}

/** Resolves a stored macro invocation marker to its source token.
    Nested template markers use the active expansion's invocation; unresolved
    markers return NULL.
*/
Token Compiler.macro_invocation_site(Compiler compiler, Var site) {
  if (site is <token>) return site;
  if (site != <m-invoke> || !compiler.macro_stack) return NULL;
  List active = compiler.macro_stack.car();
  (Var definition, Var input, Var bindings, Token invocation) = active;
  (void) definition, (void) input, (void) bindings;
  return invocation;
}

static String _definition_note(List definition) {
  List origin = definition.assoc(<origin>);
  String file = origin.assoc(<file>);
  int line = origin.assoc(<line>).int(),
      column =
    origin.assoc(<column>).int();
  return %"definition: $file:$line:$column";
}

/** Expands canonical macro capture rows and binds the result at `position`.
    `stored` is a `macrodef` or visible macro name. The active expansion stack
    supplies Lisp bindings, source location, and recursion checks; the
    definition's fresh rows allocate invocation-local names. This method does
    not begin a semantic transaction.
*/
List Compiler.expand_macro_invocation_node(
  Compiler compiler, Var stored, List arguments, Token invocation,
  AstPos position) {
  List definition = NULL;
  if (stored.is_atom())
    definition = _lookup(
      compiler, Atom.intern(stored.str()), invocation);
  else match (stored)
    case %(local-macro (!is ?name type atom)):
      definition = compiler.sym.lookup_macro(name);
  if (!definition) definition = stored;
  List input = arguments;
  with compiler {
    int block_scope = definition.assoc(<kind>) == <decorator> &&
                      definition.assoc(<target>) == <block>;
    if (block_scope) _.sym.push_new_scope();
    defer if (block_scope) _.sym.pop_scope();
    Token old_token = _.token;
    _.token = invocation;
    defer _.token = old_token;
    Atom name = definition.assoc(<name>);
    foreach (List active, _.macro_stack) {
      (List prior, List prior_input, Var bindings, Var site) = active;
      (void) bindings, (void) site;
      if (List.equal(prior, definition) &&
          List.equal(prior_input, input)) {
        String spelling = name.str();
        _.report_error(
          <macro>, %"identical recursive expansion of '$spelling'",
          invocation,
          %(${_definition_note(definition)}
            "input: ${_source_unwrap(input.search_replace(
              %(capture (source ?syntax) *), <?syntax>
            )).repr()}")
        );
      }
    }
    if (_.macro_stack.len() >= 64) {
      String first_note =
        %"first expansion: ${
          compiler.macro_stack.last().repr()
        }";
      _.report_error(
        <macro>, "macro expansion depth exceeds 64",
        invocation,
        %(${_definition_note(definition)}
          "input: ${input.repr()}" $first_note)
      );
    }
    if (_.macro_count >= 10000)
      _.report_error(
        <macro>, "macro expansion count exceeds 10000",
        invocation, NULL);

    _.macro_count++;
    List old_stack = _.macro_stack;
    List result = NULL;
    {
      defer {
        _.macro_stack = old_stack;
      }
      List template = definition.assoc(<template>);
      Map introduced = %{};
      Array fresh_values = %[];
      List direct_bindings = NULL;
      foreach (List fresh, definition.assoc(<fresh>).list()) {
        Var (binder, spelling, lisp) = fresh;
        List binding = _introduced_binding(
          _, introduced, spelling.str());
        if (lisp.int()) {
          List hole = _hole(binder, <name>, 0);
          fresh_values.push(_capture_row(_, hole, %($binding)));
        }
        else direct_bindings = cons(%($binder $binding), direct_bindings);
      }
      List fresh_input = fresh_values.list_free();
      List match_input = fresh_input
        ? input.append(%((fresh @fresh_input))) : input;
      List replacement_bindings = match_input.match(
        definition.assoc(<pattern>));
      int matched = !!replacement_bindings;
      replacement_bindings = replacement_bindings.append(direct_bindings);
      List lisp_bindings = _lisp_bindings(replacement_bindings);
      Var stored = definition;
      _.macro_stack = %(
        ($stored $input $lisp_bindings $invocation) @old_stack
      );
      int expansion_origin = _.record_origin(invocation);
      Ast constructed = matched
                      ? template.replace(replacement_bindings) : NULL;
      int old_origin = _.origin;
      _.origin = expansion_origin;
      {
        defer _.origin = old_origin;
        result = _.bind_syntax(
          matched ? constructed.var() : void,
          position, _.return_type);
      }
    }
    return result;
  }
}

/* Invocation parsing and expansion share one semantic transaction. Empty
   generated syntax and raised diagnostics therefore cannot leave provisional
   bindings, enumerators, statics, or generated-name state behind. */
static List _invoke_definition(
  Compiler compiler, List definition, Token invocation, AstPos position,
  int bare) {
  int deferred = !!compiler.macro_holes;
  SymTxn transaction = compiler.begin_semantic_transaction();
  defer transaction.rollback();
  List input = bare
    ? %(args) : _invocation_arguments(compiler, definition);
  if (_position(position).semicolon) compiler.expect(<;>);
  List node = _invocation_node(compiler, definition, input, invocation);
  List result = deferred ? %(seq $node) :
    compiler.bind_syntax(node, position, compiler.return_type);
  if (result.car() != <seq> || result.len() != 1 ||
      transaction.local_macros_changed()) transaction.commit();
  return result;
}

static List _parse_expression_decorator(
  Compiler c, List definition, Token invocation, int bare) {
  List arguments = bare
    ? %(args) : _invocation_arguments(c, definition);
  if (c.peek(0) == <;> || c.peek(0) == <eof>) {
    String spelling = definition.assoc(<name>).str();
    c.report_error(
      <macro>,
      %"decorator '$spelling' requires a following expression",
      invocation, %(${_definition_note(definition)}));
  }
  List target = c.parse_macro_expression_target();
  List input = %(
    target $arguments
    ${_capture_row(
      c, definition.assoc(<targetp>), %($target)
    )}
  );
  return %(expr (<macro-expr>) ${_invocation_node(
    c, definition, input, invocation
  )});
}

static List _parse_expression_definition(
  Compiler compiler, List definition, Token invocation, int bare) {
  Symbol kind = definition.assoc(<kind>);
  if (kind == <decorator> && definition.assoc(<target>) == <expr>)
    return _parse_expression_decorator(
      compiler, definition, invocation, bare);
  List arguments = _invocation_arguments(compiler, definition);
  if (kind != <expression>) {
    String spelling = definition.assoc(<name>).str();
    String subject = kind == <decorator>
      ? %"decorator '$spelling'"
      : %"macro '$spelling'";
    compiler.report_error(
      <macro>, %"$subject cannot be invoked in an expression",
      invocation,
      kind == <decorator>
        ? %(${_definition_note(definition)})
        : NULL
    );
  }
  return %(expr (<macro-expr>) ${_invocation_node(
    compiler, definition, arguments, invocation
  )});
}

/** Parses and resolves a direct or keyword-alias expression macro.
    Returns NULL without consuming an identifier that is not an applicable
    alias; a direct `$` invocation must resolve to a visible expression form.
*/
List Compiler.try_parse_macro_expression(Compiler c) {
  Token invocation = c.token;
  List definition;
  int bare = 0;
  if (c.peek(0) == <$>) {
    Atom name = _name(c);
    if (c.macro_holes && c.peek(0) != <(>) {
      Var existing;
      if (!_try_definition(c, name, 1, &existing)) {
        String spelling = name.str();
        c.report_error(
          <parse>, %"unbound replacement variable '$spelling'",
          invocation, NULL);
      }
    }
    definition = _lookup(c, name, invocation);
  }
  else {
    definition = _keyword_alias_lookup(c);
    if (!_keyword_alias_is_expression(c, definition)) return NULL;
    c.next();
    bare = !_keyword_alias_requires_arguments(definition);
  }
  return c.resolve_expression(
    _parse_expression_definition(
      c, definition, invocation, bare), invocation
  );
}

static List _parse_target_definition(
  Compiler c, List definition, Token invocation, AstPos position,
  int bare) {
  int deferred = !!c.macro_holes;
  Atom name = definition.assoc(<name>);
  Symbol kind = definition.assoc(<kind>);
  Symbol target_kind = definition.assoc(<target>);
  const MacroPos *place = _position(position);
  if (kind != <decorator>) {
    if (kind != place.kind) {
      String spelling = name.str();
      String result_kind = _kind_spelling(kind);
      String message =
        %"macro '$spelling' has result kind $result_kind and cannot be " +
        %"invoked at ${place.description}";
      c.report_error(<macro>, message, invocation, NULL);
    }
    return _invoke_definition(
      c, definition, invocation, position, bare);
  }
  Symbol expected = _decorator_result_kind(target_kind);
  if (expected != place.kind) {
    String spelling = name.str();
    c.report_error(
      <macro>,
      %"decorator '$spelling' targets ${
        _kind_spelling(target_kind)} syntax and cannot be used here",
      invocation, NULL
    );
  }
  /* Parsing the decorator target can publish symbols before replacement is
     known. Stage the target and expansion together so rejection rolls both
     back. */
  SymTxn transaction = c.begin_semantic_transaction();
  defer transaction.rollback();
  {
    List arguments = NULL, target = NULL;
    Token target_start = NULL;
    int block_scope = !c.macro_holes && target_kind == <block>;
    if (block_scope) c.sym.push_new_scope();
    defer if (block_scope) c.sym.pop_scope();
    arguments = bare
      ? %(args)
      : _invocation_arguments(c, definition);
    if (block_scope) _bind_name_arguments(c, definition, arguments);
    if (c.peek(0) == <;>)
      c.report_error(
        <macro>, "decorator application must not end with ';'",
        invocation, %(${_definition_note(definition)}));
    if (c.peek(0) == <eof>) {
      String spelling = name.str();
      c.report_error(
        <macro>,
        %"decorator '$spelling' requires a following target",
        invocation, %(${_definition_note(definition)}));
    }
    target_start = c.token;
    if (target_kind == <function>) target = c.parse_function_target();
    else switch (position) {
      case AST_UNIT:       target = c.parse_top_level(); break;
      case AST_BLOCK:      target = c.parse_block_item(); break;
      case AST_FIELD:      target = c.parse_field(c.aggregate_type); break;
      case AST_ENUMERATOR:
        target = c.parse_enumerator(c.aggregate_type); break;
      case AST_MAP_ENTRY:  target = c.parse_map_entry(); break;
      case AST_STATEMENT:  target = c.parse_statement(); break;
      default: __builtin_unreachable();
    }
    if (position == AST_STATEMENT)
      target = c.anchor_origin(target, target_start);
    List targets = target.car() == <seq> ? target.cdr() : %($target);
    Array captured_targets = %[];
    foreach (Var item, targets)
      captured_targets.push(
        _capture_source(c, item, target_start, c.token));
    List captured = captured_targets.list_free();
    List target_capture = _capture_row(
      c, definition.assoc(<targetp>), captured);
    int private_target = c.source_private > 0;
    List visibility_target = target;
    match (visibility_target)
      case %(seq ?only): visibility_target = only;
    match (visibility_target)
      case %(falias ?declaration ?): visibility_target = declaration;
    match (visibility_target)
      case %((!or function declare typedef) ?type *):
        private_target |= type.type().is_static();
    if (target_kind == <unit> && !private_target &&
        captured && !captured.cdr())
      target_capture = target_capture.append(
        %(
        (construct ${captured.car()})
      ));
    List input = %(
      target $arguments
      $target_capture
    );
    List node = _invocation_node(c, definition, input, invocation);
    if (deferred) {
      transaction.commit();
      return %(seq $node);
    }
    List result = c.bind_syntax(node, position, c.return_type);
    Token after = c.token;
    c.token = invocation;
    {
      defer c.token = after;
      transaction.commit();
    }
    return result;
  }
}

/** Parses a direct or keyword-alias macro at the requested syntax position.
    Returns NULL without consuming a macro hole or inapplicable identifier;
    template parsing returns a deferred `(seq (macro-invoke ...))`, and
    ordinary parsing returns the bound expansion.
*/
List Compiler.try_parse_macro_target_at(Compiler compiler, AstPos position) {
  Token invocation = compiler.token;
  List definition;
  int bare = 0;
  if (compiler.peek(0) == <$>) {
    if (compiler.macro_holes && compiler.peek_macro_hole()) return NULL;
    definition = _lookup(compiler, _name(compiler), invocation);
  }
  else {
    definition = _keyword_alias_lookup(compiler);
    if (!_keyword_alias_targets_at(
      compiler, definition, position)) return NULL;
    compiler.next();
    bare = !_keyword_alias_requires_arguments(definition);
  }
  return _parse_target_definition(
    compiler, definition, invocation, position, bare);
}
