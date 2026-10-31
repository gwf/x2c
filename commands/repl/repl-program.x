/*  repl-program.x -- native library programs and retained declarations

    Copyright (c) 2026 Gary William Flake.
*/
#pragma once
#include "repl-types.x"
#include "collect/collect.x"
#include "generate/generate.x"
#include "emit/emit.x"
#include "format.x"
#include "cpp/cpp.x"
#include "project/project.x"
#include "utils.x"
#include <dlfcn.h>
#include <stdio.h>

static typedef struct ProgramBuild {
  ReplProgram program;
  Frontend frontend;
  Compiler documentation;
  Array roots, headers, objects, exports, includes;
  Map seen, units, fingerprints, packages;
} ProgramBuild;

static String _program_command(List words) {
  String output = NULL, errors = NULL;
  int status = tool_capture(words, output, errors);
  return status ? errors ? errors : %"native build exited with status $status"
                : NULL;
}

static List _program_options(CliRequest request) {
  Array words = [];
  foreach (String directory, request.include_dirs) {
    words.push("--x-include-dir"); words.push(directory);
  }
  foreach (String directory, request.package_dirs) {
    words.push("--package-dir"); words.push(directory);
  }
  foreach (String module, request.native_modules) {
    words.push("--native-module"); words.push(module);
  }
  foreach (String argument, request.cpp_args) words.push(argument);
  foreach (String argument, request.cc_args) {
    words.push("-Xcc"); words.push(argument);
  }
  if (request.cc) { words.push("--cc"); words.push(request.cc); }
  if (request.meta_cc) { words.push("--meta-cc"); words.push(request.meta_cc); }
  if (request.ar) { words.push("--ar"); words.push(request.ar); }
  if (request.live_symbols) words.push("--live-symbols");
  if (request.cpp_symbols) words.push("--cpp-symbols");
  return words.list_free();
}

static String _program_text(Compiler c, List syntax) =>
  String.new(c.code_pretty_string(c.emit($(syntax), NULL), NULL));

static List _program_span(Compiler c, List node) {
  match (node) case %(function ? (bind ?binding ?) ?):
    return c.fact(%(definition-span $binding));
  return c.fact(%(definition-span $node));
}

static String _program_origin(Compiler c, List span, int &line) {
  if (!span) { line = 1; return Path.absolute(c.filename); }
  Token tokens = c.tokenizer.tokens;
  Token first = tokens + span.car().integer();
  line = first.line;
  String file = c.token_source(first, line);
  return Path.absolute(file ? file : c.filename);
}

static int _program_owned(Compiler c, List node, String path) {
  int line = 1;
  return _program_origin(c, _program_span(c, node), line) == path;
}

static String _program_lines(String text, int first, int after) {
  int line = 1, begin = 0, end = text.len();
  for (int i = 0; i < text.len(); i++) {
    if (line == first) { begin = i; break; }
    if (text[i] == '\n') line++;
  }
  for (int i = begin; i < text.len(); i++)
    if (text[i] == '\n' && ++line > after) { end = i; break; }
  return text[begin:end];
}

static String _program_slice(Compiler c, List span) {
  if (!span) return NULL;
  Token tokens = c.tokenizer.tokens;
  Token first = tokens + span.car().integer();
  Token after = tokens + span.cadr().integer() - 1;
  if (c.line_markers) {
    int line = first.line, last = after.line;
    String file = c.token_source(first, line);
    if (file != c.token_source(after, last)) return NULL;
    String source = NULL;
    if (!c.sources.read(file, source)) return NULL;
    return _program_lines(source, line, last);
  }
  return c.text[first.pos:after.pos + after.len];
}

static String _program_declaration(Compiler c, Type type, String name) =>
  _program_text(c, type.declaration_ast($(name))).strip(NULL);

static int _program_private(Compiler c, String name, Type type) =>
  type.is_static() || $(name) in c.sym.file_statics() ||
  %(function $name) in c.sym.file_statics();

static int _program_visible(Compiler c, String path, String name, Type type) =>
  !_program_private(c, name, type) || path.endswith(".c") ||
  (path.endswith(".h") && type.is_inline());

static int _program_static_export(List row) =>
  row.len() >= 3 && row[2] == <private>;

static void _program_family(Map all, Map selected, Type type) {
  List parameters = NULL;
  Type result = NULL;
  if (type.function_parts(parameters, result)) {
    foreach (Type parameter, parameters) _program_family(all, selected, parameter);
    _program_family(all, selected, result);
    return;
  }
  Type base = type.base_type();
  List family = NULL;
  match (base) {
    case %(?(String name)): family = %(typedef $name);
    case %((!or ?tag struct union enum) ?name *): family = $(tag, name);
  }
  if (!family || family in selected) return;
  Var found;
  if (all.try_get(family, found)) selected[family] = found;
  else return;
  foreach (Var (key, value), all) {
    if (key is not <list>) continue;
    List parts = key;
    if (parts.len() >= 2 && parts[:2] == family) {
      selected[key] = value;
      if (parts.len() == 3 && value is <list>)
        _program_family(all, selected, value);
    }
  }
  if (family.car() == <typedef>) {
    Type target = found;
    List key = $(family.cadr());
    if (all.try_get(key, found)) selected[key] = found;
    if (target) _program_family(all, selected, target);
  }
  foreach (Var part, type)
    if (part is <list>) _program_family(all, selected, part);
}

static String _program_documentation(Compiler c, int line) {
  for (Token token = c.tokenizer.tokens; token.type != <eof>; token++)
    if (token.line >= line && !(token.type in %<space comment preproc>))
      return c.definition_doc(token);
  return NULL;
}

static void _program_symbol(
  ProgramBuild &b, Compiler c, String path, String name, Type type,
  List syntax, String declaration, String body, int line) {
  int file_static = path.endswith(".c") && _program_private(c, name, type);
  int inline_body = type.is_inline();
  type = type.declared();
  ReplProgram program = b.program;
  Var prior;
  if (program.symbols.try_get($(name), prior) && !prior.equal(type))
    raise %(repl (reason $(%"conflicting declaration: $name")));
  program.symbols[$(name)] = type;
  _program_family(c.sym.unit_symbols(), program.symbols, type);
  Symbol kind = type.is_typedef() ? <type> : type.is_function() ? <native>
                                                                : <global>;
  program.descriptions[name] = {
    "name": name, "kind": kind, "type": type, "path": path,
    "source": program.sources[path], "declaration": declaration ? declaration : "",
    "body": body ? body : "", "line": line,
    "end_line": line + (body ? body.count("\n") : 0), "syntax": syntax};
  String documentation = _program_documentation(b.documentation, line);
  if (documentation) program.descriptions[name].map()["documentation"] = documentation;
  if (kind != <type> && !(name in b.units)) {
    b.units[name] = 1;
    String native = c.emitted_binding_name(c.sym.resolve_global($(name), NULL));
    b.exports.push(file_static ? $(name, native ? native : name, <private>)
      : path.endswith(".h") && !inline_body
        ? $(name, native ? native : name, <dynamic>)
        : $(name, native ? native : name));
  }
}

static String _program_type_name(List family) =>
  family.car() == <typedef> ? family.cadr().str()
                           : %"$(family.car()) $(family.cadr())";

static void _program_describe(ProgramBuild &b, ParsedUnit &unit, String path) {
  Compiler c = unit.compiler;
  ReplProgram program = b.program;
  Map definitions = {}, functions = {};
  foreach (List node, unit.ast)
    match (node) case %(function ? (bind ?binding ?) ?):
      functions[Ast.binding_spelling(binding)] = node;
  foreach (List row, c.definition_rows(unit.ast))
    match (row) case %(function ?name ?display ?type ?parameters ?line ?doc
                                 ? ?origin ?declarator ?span): {
      if (!_program_visible(c, path, name, type)) continue;
      int source_line = 1;
      if (_program_origin(c, span, source_line) != path) continue;
      List function = functions[name];
      String declaration = function
        ? _program_text(c, %(declare $(function.cadr())
                                  (bindings $(function.caddr())))).strip(NULL)
        : _program_declaration(c, type, name);
      _program_symbol(b, c, path, name, type, row, declaration,
                      _program_slice(c, span), source_line);
      Map description = b.program.descriptions[name];
      description["display"] = display;
      description["parameters"] = parameters;
      if (doc is <string> && doc.str().len()) description["documentation"] = doc;
      definitions[name] = 1;
    }
  foreach (List node, unit.ast) {
    if (!_program_owned(c, node, path)) continue;
    List spec = NULL, bindings = NULL;
    match (node) {
      case %((!or ?kind typedef declare) ?base (bindings *rows)): {
        spec = kind == <typedef> ? %(typedef @base) : base;
        bindings = rows;
      }
      default: continue;
    }
    _program_family(c.sym.unit_symbols(), program.symbols, spec);
    foreach (List row, bindings) {
      match (row) case %(op = ?target ?): row = target;
      match (row) case %(bind ?binding ?): {
        String name = Ast.binding_spelling(binding);
        if (!name || name in definitions) continue;
        Type type = c.sym.get_exact($(name));
        if (!type || !_program_visible(c, path, name, type)) continue;
        List span = _program_span(c, node);
        int line = 1;
        (void) _program_origin(c, span, line);
        String declaration = type.is_function() || type.is_typedef()
          ? _program_text(c, node).strip(NULL)
          : _program_declaration(c, type, name);
        _program_symbol(b, c, path, name, type, node, declaration,
                        type.is_function() ? NULL : _program_slice(c, span), line);
      }
    }
  }
  foreach (Var (key, value), program.symbols) {
    List family = key;
    if (family.len() != 2 ||
        !(family.car() in %<struct union enum typedef>) ||
        family.cadr() is not <string>) continue;
    String name = family.cadr(), key = _program_type_name(family);
    if (key in program.descriptions) continue;
    Type type = family.car() == <typedef> ? c.sym.get_exact($(name)) : family;
    Map description = {
      "name": name, "kind": <type>, "type": type,
      "path": path, "source": program.sources[path],
      "declaration": _program_declaration(c, type, name),
      "body": "", "line": 1, "end_line": 1};
    foreach (Var (binding, source), c.source_definitions) {
      List row = source;
      if (Ast.binding_spelling(binding) != name || row.len() < 4) continue;
      String file = row[0], text = NULL;
      if (!c.sources.read(file, text)) continue;
      int first = row[1], after = row[2];
      description["path"] = file;
      description["source"] = text;
      description["body"] = text[first:after];
      description["line"] = 1 + text[:first].count("\n");
      description["end_line"] = 1 + text[:after].count("\n");
      program.sources[file] = text;
      break;
    }
    program.descriptions[key] = description;
  }
  foreach (List node, unit.ast) {
    List spec = NULL;
    match (node) {
      case %((!or typedef declare) ?type ?): spec = type;
      default: continue;
    }
    Type base = spec.type().base_type();
    if (!(base.car() in %<struct union enum>) || base.len() < 3 ||
        base.cadr() is not <string>) continue;
    String name = base.cadr();
    List family = $(base.car(), name);
    if (!(family in program.symbols)) continue;
    String body = _program_slice(c, _program_span(c, node));
    if (!body) continue;
    int line = 1;
    String file = _program_origin(c, _program_span(c, node), line);
    String key = _program_type_name(family);
    Map description = program.descriptions[key];
    if (!description) description = {"name": name, "kind": <type>, "type": family};
    description["path"] = file;
    description["body"] = body;
    description["declaration"] = body;
    description["line"] = line;
    description["end_line"] = line + body.count("\n");
    String text = NULL;
    if (c.sources.read(file, text)) {
      program.sources[file] = text;
      description["source"] = text;
    }
    program.descriptions[key] = description;
  }
  foreach (Var (key, value), c.sym.unit_symbols()) {
    if (key is not <list> || value is not <list> ||
        !key.list().match(%(?(String name)))) continue;
    String name = key.list().car();
    Type type = value;
    if (!type.is_enum() || !(type.base_type() in program.symbols) ||
        name in program.descriptions) continue;
    program.symbols[key] = type;
    program.descriptions[name] = {
      "name": name, "kind": <constant>, "type": type, "path": path,
      "source": program.sources[path], "declaration":
        _program_declaration(c, type, name), "body": "", "line": 1,
      "end_line": 1};
  }
}

/* Native C declarations retain their authored aggregate attributes. */
static String _program_c_header(Compiler c, List ast) {
  Buffer text = auto Buffer.new(0);
  text.write("#pragma once\n#include \"x2c.h\"\n");
  String original = NULL;
  if (c.line_markers && c.sources.read(c.filename, original)) {
    Tokenizer tokens = auto Tokenizer.new(original, <x2c>);
    tokens.scan();
    for (Token token = tokens.tokens; token.type != <eof>; token++)
      if (token.type == <preproc>) { text.write(token.text); text.write("\n"); }
  }
  foreach (List node, ast) {
    if (!_program_owned(c, node, Path.absolute(c.filename))) continue;
    match (node) {
      case %(preproc ?directive): {
        text.write(directive); text.write("\n");
      }
      case %(typedef *): {
        String source = _program_slice(c, _program_span(c, node));
        if (source) { text.write(source); text.write("\n"); }
      }
      case %(declare ?spec (bindings *rows)): {
        foreach (List row, rows) {
          match (row) case %(op = ?target ?): row = target;
          match (row) case %(bind ?binding ?): {
            String name = Ast.binding_spelling(binding);
            if (!name) {
              String source = _program_slice(c, _program_span(c, node));
              if (source) { text.write(source); text.write("\n"); }
              continue;
            }
            Type type = c.sym.get_exact($(name));
            if (!type) continue;
            if (!type.is_function()) text.write("extern ");
            text.write(_program_declaration(c, type.declared(), name));
            text.write("\n");
          }
        }
      }
      case %(function ?spec (bind ?binding ?) ?): {
        String name = Ast.binding_spelling(binding);
        Type type = c.sym.get_exact($(name));
        if (!type) continue;
        text.write(_program_declaration(c, type.declared(), name));
        text.write("\n");
      }
    }
  }
  return text;
}

static void _program_macro(
  ReplProgram program, Compiler c, String root, String name, Var raw) {
  String body = NULL, parameters = "";
  List site = NULL;
  match (raw) {
    case %(object ? ?replacement ?origin): { body = replacement; site = origin; }
    case %(function ? ?names ?variadic ?replacement ?origin): {
      parameters = "(" + ", ".join(names) +
        (variadic ? (names ? ", ..." : "...") : "") + ")";
      body = replacement;
      site = origin;
    }
    default: return;
  }
  String path = site.car(), source = NULL;
  if (!path.startswith("<")) {
    path = Path.resolved_absolute(path);
    Var cached = program.sources[path];
    if (cached is <string>) source = cached;
    else if (c.sources.read(path, source)) program.sources[path] = source;
  }
  String declaration = %"#define $name$parameters$(body.len() ? " " : "")$body";
  program.descriptions[name] = {
    "name": name, "kind": <macro>, "type": NULL,
    "path": path, "source": source, "line": site.cadr(),
    "end_line": site.cadr(), "declaration": declaration,
    "body": declaration, "dependency": path != root};
}

/* The ordinary driver links imported package archives. Keep their native
   client flags and pinned headers for later submissions in the same program. */
static void _program_packages(ProgramBuild &b, ParsedUnit &unit) {
  ReplProgram program = b.program;
  foreach (Var (name, raw), unit.compiler.package_roots) {
    String root = unit.context.export(raw), response = %"$root/builds/$name.native.rsp";
    if (root in b.packages) continue;
    b.packages[root] = 1;
    foreach (String directory, $(%"$root/builds", %"$root/src"))
      if (!(directory in b.includes)) b.includes.push(unit.context.export(directory));
    if (!Path.is_file(response)) continue;
    CliRequest native = CliRequest.package_options(response, root);
    program.cc_args = unit.context.export(program.cc_args.append(native.cc_args));
    program.ld_args = unit.context.export(program.ld_args.append(native.ld_args));
    String module = %"$root/builds/$name.module";
    if (Path.is_file(module))
      program.dependencies[unit.context.export(module)] =
        unit.context.export(Path.content_identity(module));
  }
  b.frontend.toolchain.cc_args = program.cc_args;
  b.frontend.toolchain.ld_args = program.ld_args;
}

/* Getters share the original translation unit, so C retains one instance of
   each static function, object, and function-local static. */
static String _program_c_input(
  String path, Array exports, String directory, int unit) {
  Array code = [%"#include $(path.repr())\n"];
  for (int i = 0; i < exports.len(); i++) {
    List row = exports[i];
    if (!_program_static_export(row)) continue;
    String getter = %"x2c_repl_unit_$(unit)_address_$i";
    code.push(%"void *$getter(void) { return (void *) &$(row.cadr()); }\n");
    exports[i] = $(row.car(), getter, <private>);
  }
  if (code.len() == 1) return path;
  String source = %"$directory/unit-$unit.c";
  Path.write_text(source, "".join(code));
  return source;
}

static String _program_unit(ProgramBuild &b, String path, String &input) {
  input = path;
  b.seen[path] = 1;
  ReplProgram program = b.program;
  Frontend frontend = b.frontend;
  struct CliRequest options = *frontend.request;
  options.source_facts = 1;
  struct Frontend configured = *frontend;
  configured.request = &options;
  ParsedUnit unit;
  int opened = Frontend.start(&configured, path, unit);
  defer unit.close();
  Compiler c = unit.compiler;
  int native = !Path.is_x2c_source(path);
  if (opened && native) {
    opened = unit.collect_native(&configured);
    if (opened) unit.ast = c.full_parse_native(unit.globals);
    opened = opened && !c.error_count();
  }
  else opened = opened && unit.collect(&configured) && unit.parse();
  if (!opened) {
    foreach (List diagnostic, c.diagnostics()) c.print_diagnostic(diagnostic);
    return %"$path: x2c could not collect its declarations";
  }
  struct ReplProgram collected = {
    .symbols = {}, .descriptions = {}, .sources = {}, .macros = {}};
  ProgramBuild local = b;
  local.program = &collected;
  local.exports = [];
  local.units = {};
  String original = c.source_texts[path];
  collected.sources[path] = original ? original : c.text;
  Tokenizer authored = auto Tokenizer.new(original ? original : c.text, <x2c>);
  authored.scan();
  struct Compiler documentation = *c;
  documentation.text = original ? original : c.text;
  documentation.tokenizer = authored;
  local.documentation = &documentation;
  foreach (Var (file, text), c.source_texts) collected.sources[file] = text;
  _program_describe(local, unit, path);
  Map inline_bodies = {};
  if (native && path.endswith(".h"))
    foreach (List node, unit.ast)
      match (node) case %(function ?spec (bind ?binding ?) ?):
        if (spec.type().is_inline()) inline_bodies[Ast.binding_spelling(binding)] = 1;
  if (native)
    foreach (Var (key, value), c.sym.unit_symbols()) {
      if (key is not <list> || value is not <list>) continue;
      List parts = key;
      if (parts ~= %(?(String name))) {
        Type type = value;
        int inline_body = name in inline_bodies;
        if (_program_private(c, name, type) &&
            !(path.endswith(".h") && inline_body)) continue;
        collected.symbols[key] = type.declared();
        if (!type.is_typedef() && !c.sym.enumerator_owner($(name)) &&
            !(name in local.units)) {
          local.units[name] = 1;
          String emitted = c.emitted_binding_name(c.sym.resolve_global($(name), NULL));
          local.exports.push(inline_body ? $(name, emitted ? emitted : name)
            : $(name, emitted ? emitted : name, <dynamic>));
        }
      }
      else if (parts.car() in %<struct union enum typedef>)
        collected.symbols[key] = value;
    }
  if (!native) {
    Array names = [];
    foreach (List row, local.exports) names.push(row.car());
    collected.symbols.merge(c.callable_symbols(names));
    _program_packages(b, unit);
  }
  foreach (List row, local.exports) {
    String name = row.car();
    List prior = b.units[name];
    if (prior && (_program_static_export(row) ||
                  _program_static_export(prior.cadr())))
      return %"ambiguous file-local name $name: $(prior.car()) and $path";
  }
  if (path.endswith(".c"))
    input = unit.context.export(_program_c_input(
      path, local.exports, program.directory, b.headers.len()));
  program.symbols.merge(unit.context.export(collected.symbols));
  foreach (List row, (Array) unit.context.export(local.exports))
    if (!(row.car() in b.units)) {
      b.units[row.car()] = unit.context.export($(path, row));
      b.exports.push(row);
    }
  String header = %"$(program.directory)/unit-$(b.headers.len()).h";
  if (path.endswith(".h"))
    Path.write_text(header, %"#pragma once\n#include $(path.repr())\n");
  else if (Path.is_x2c_source(path)) {
    List code = c.generate_code_text(c.transform(unit.ast),
                                    %"unit-$(b.headers.len())");
    Path.write_text(header, code.cadr());
  }
  else Path.write_text(header, _program_c_header(c, unit.ast));
  b.headers.push(unit.context.export($(header, Path.dirname(path))));
  foreach (Var (dependency, hash), c.deps) {
    String file = dependency;
    if (file.startswith("search:") || !Path.is_file(file)) continue;
    if (!(file in b.fingerprints))
      b.fingerprints[unit.context.export(file)] =
        unit.context.export(Path.content_identity(file));
    String home = Compiler.home_dir();
    String package = Compiler.package_directory(frontend.request.package_roots(), file);
    if (Path.is_x2c_source(file) &&
        !(package && Compiler.is_package_source(package, file)) &&
        !(home && (file.startswith(%"$home/lib/") ||
                   file.startswith(%"$home/src/") ||
                   file.startswith(%"$home/etc/"))) && !(file in b.seen))
      b.roots.push(unit.context.export(file));
  }
  List macros = native ? c.command_macros
    : c.included_macros(path, 0, Path.dirname(path), NULL);
  foreach (List row, macros) {
    String name = row.car();
    program.macros[unit.context.export(name)] = unit.context.export(row.cadr());
    _program_macro(&collected, c, path, name, row.cadr());
  }
  program.descriptions.merge(unit.context.export(collected.descriptions));
  program.sources.merge(unit.context.export(collected.sources));
  return NULL;
}

static String _program_native_build(
  ProgramBuild &b, CliRequest request, List sources, Symbol kind,
  String output, String directory) {
  String driver = Compiler.driver_executable();
  if (!driver) return "the matching x2c compiler is unavailable";
  Array command = [driver, "build", "--plain", "--kind",
    kind == <module> ? "meta-module" : "static-library",
    "--build-dir", directory, "--output", output, "-Xcc", "-fPIC"];
  foreach (String option, _program_options(request)) command.push(option);
  foreach (String directory, b.includes) {
    command.push("--c-include-dir"); command.push(directory);
  }
  if (kind == <module>) {
    command.push("-Wl,-t");
    foreach (String option, request.ld_args) command.push(option);
#ifdef __APPLE__
    foreach (List row, b.exports)
      if (row.len() >= 3 && row[2] == <dynamic>) {
        command.push("-Xlinker"); command.push("-U");
        command.push("-Xlinker"); command.push("_" + row.cadr().str());
      }
#endif
  }
  foreach (String source, sources) {
    if (kind == <module> && source.endswith(".a")) {
#ifdef __APPLE__
      command.push("-Xlinker"); command.push("-force_load");
      command.push("-Xlinker"); command.push(source);
#else
      command.push("-Xlinker"); command.push("--whole-archive");
      command.push("-Xlinker"); command.push(source);
      command.push("-Xlinker"); command.push("--no-whole-archive");
#endif
    }
    else command.push(source);
  }
  String captured = NULL, errors = NULL;
  int status = tool_capture(command, captured, errors);
  if (status) return errors ? errors : %"native build exited with status $status";
  if (kind == <module>) {
    if (captured) _program_link_dependencies(b.program, captured);
    if (errors) _program_link_dependencies(b.program, errors);
  }
  return NULL;
}

/* Each manifest dependency keeps its own compiler and native options. */
static CliRequest _program_request(ProgramBuild &b, String &failure) {
  CliRequest command = b.frontend.request;
  if (!command.manifest && !command.target && !command.profile) return command;
  struct CliRequest planning = *command;
  planning.inputs = NULL;
  if (!planning.sources) planning.sources = SourceView.new();
  ProjectBuild plan = ProjectBuild.plan(&planning);
  Map products = {};
  int index = 0;
  for (ProjectBuild node = plan; node; node = node.next) {
    CliRequest request = node.request;
    request.inputs = request.inputs.map(%!(String path) =>
      path in products ? products[path].str() : path);
    request.native_modules = request.native_modules.map(
      %!(String path) =>
        path in products ? products[path].str() : path);
    if (!node.next) return request;
    String directory = %"$(b.program.directory)/dependency-$index";
    String suffix = request.kind == <module> ? ".module" : ".a";
    String output = %"$(b.program.directory)/dependency-$index$suffix";
    failure = _program_native_build(b, request, request.inputs, request.kind,
                                    output, directory);
    if (failure) return NULL;
    if (request.output) products[request.output] = output;
    _program_generated_dirs(%"$directory/gen", b.includes);
    index++;
  }
  return command;
}

/* Main's native signature stays in the program; only the prompt entry takes
   an Array. The generated ordinary function keeps argument storage native. */
static String _program_main(ProgramBuild &b) {
  ReplProgram program = b.program;
  if (!(%("main") in program.symbols)) return NULL;
  Compiler c = Compiler.new();
  c.sym.reset(program.symbols);
  List parameters = NULL;
  Type result = NULL;
  Type type = program.symbols[%("main")];
  type.function_parts(parameters, result);
  if (c.sym.normalize_declared_type(result).canonicalize() != %(int))
    return "loaded main must take void or (int, char **) and return int";
  if (!parameters) return NULL;
  if (parameters.len() != 2)
    return "loaded main must take void or (int, char **) and return int";
  Type count = c.sym.normalize_declared_type(parameters.car()).canonicalize();
  Type values = c.sym.normalize_declared_type(parameters.cadr());
  if (values.is_array()) values = values.dereference().reference();
  if (count != %(int) || values.canonicalize() != %(* * char))
    return "loaded main must take void or (int, char **) and return int";
  String entry = "x2c_repl_program_main";
  String source = %"$(program.directory)/main-entry.x";
  Path.write_text(source,
    "int main(int argc, char **argv);\n"
    "int x2c_repl_program_main(Array values) {\n"
    "  int count = values.len();\n"
    "  char **argv = xcalloc((size_t) count + 1, sizeof(char *));\n"
    "  for (int i = 0; i < count; i++) {\n"
    "    String text = values[i];\n"
    "    size_t size = text.len();\n"
    "    argv[i] = xcalloc(size + 1, 1);\n"
    "    if (size) memcpy(argv[i], (char *) text, size);\n"
    "  }\n"
    "  return main(count, argv);\n"
    "}\n");
  b.objects.push(source);
  for (int i = 0; i < b.exports.len(); i++)
    if (b.exports[i].list().car() == "main") b.exports[i] = $("main", entry);
  Type adapted = %((func (("Array"))) int);
  program.symbols[%("main")] = adapted;
  Map description = program.descriptions["main"];
  description["type"] = adapted;
  description["declaration"] = "int main(Array values);";
  description["parameters"] = %("values");
  return NULL;
}

static String _program_exports(ProgramBuild &b) {
  ReplProgram program = b.program;
  Array code = ["#include \"x2c.h\"\n"];
  int index = 0;
  foreach (List pair, b.headers) {
    String header = pair.car();
    code.push(%"#include $(header.repr())\n");
  }
  foreach (List row, b.exports)
    if (_program_static_export(row))
      code.push(%"extern void *$(row.cadr())(void);\n");
    else if (row.len() >= 3 && row[2] == <dynamic>) {
      String name = row.cadr();
#ifdef __APPLE__
      String attribute = "weak_import";
#else
      String attribute = "weak";
#endif
      code.push(%"extern __typeof__($name) $name __attribute__(($attribute));\n");
    }
  code.push("extern int x2c_repl_program_main(Array values);\n");
  code.push("void *x2c_repl_program_address(unsigned index) {\n  switch(index) {\n");
  foreach (List row, b.exports) {
    String name = row.cadr();
    String address = _program_static_export(row)
      ? %"$name()" : %"(void *) &$name";
    code.push(%"    case $index: return $address;\n");
    index++;
  }
  code.push("  }\n  return 0;\n}\n");
  code.push(%"int x2c_repl_program_count(void) { return $(b.exports.len()); }\n");
  String source = %"$(program.directory)/addresses.c";
  Path.write_text(source, "".join(code));
  if (!(program.directory in b.includes)) b.includes.push(program.directory);
  foreach (List pair, b.headers)
    if (!(pair.cadr() in b.includes)) b.includes.push(pair.cadr());
  b.objects.push(source);
  String entry = %"$(program.directory)/program-entry.x";
  Path.write_text(entry, "meta int x2c_repl_program_count(void);\n");
  b.objects.push(entry);
  program.exports = b.exports;
  return NULL;
}

static void _program_generated_dirs(Path directory, Array into) {
  if (!directory.is_dir()) return;
  int headers = 0;
  foreach (String name, directory.list_dir()) {
    Path path = directory.join(name);
    if (path.is_dir()) _program_generated_dirs(path, into);
    else if (path.endswith(".h")) headers = 1;
  }
  if (headers && !(directory in into)) into.push(directory);
}

static String _program_header(ProgramBuild &b) {
  ReplProgram program = b.program;
  String source = %"$(program.directory)/declarations.c";
  String expanded = %"$(program.directory)/declarations.i";
  Buffer text = auto Buffer.new(0);
  text.write("#include \"x2c.h\"\n#include \"meta.h\"\n");
  text.write("#line 1 \"x2c-repl-declarations\"\n");
  foreach (List pair, b.headers)
    text.printf("#include %s\n", ((String) pair.car()).repr());
  Path.write_text(source, text);
  Array directories = b.includes.copy();
  if (!(program.directory in directories)) directories.push(program.directory);
  foreach (List pair, b.headers)
    if (!(pair.cadr() in directories)) directories.push(pair.cadr());
  ToolAction preprocess = b.frontend.toolchain.preprocess_action(
    source, expanded, directories);
  String failure = _program_command($(@(preprocess.arguments), "-dD"));
  if (failure) return failure;
  String result = Path.read_text(expanded);
  int marker = result.find("\"x2c-repl-declarations\"");
  if (marker < 0) return "the native declaration snapshot has no source marker";
  int start = result[marker:].find("\n");
  if (start >= 0) start += marker;
  program.header = %"$(program.directory)/program.h";
  Path.write_text(program.header,
    "#pragma once\n" + (start < 0 ? "" : result[start + 1:]));
  return NULL;
}

static String _program_open(ReplProgram program) {
  program.handle = dlopen(program.module, RTLD_NOW | RTLD_LOCAL);
  if (!program.handle) return String.new(dlerror());
  void *(*address)(unsigned) =
    (void *(*)(unsigned)) dlsym(program.handle, "x2c_repl_program_address");
  if (!address) return "the native program has no address table";
  unsigned index = 0;
  program.addresses = {};
  Compiler declarations = Compiler.new();
  declarations.sym.reset(program.symbols);
  foreach (List row, program.exports) {
    String name = row.car();
    void *target = address(index);
    index++;
    if (target) program.addresses[name] = target;
    else {
      Map description = program.descriptions[name];
      if (!description) {
        Type type = program.symbols[$(name)];
        description = program.descriptions[name] = {
          "name": name, "kind": type.is_function() ? <native> : <global>,
          "type": type, "declaration": _program_declaration(declarations, type, name),
          "body": "", "dependency": 1};
      }
      description["unavailable"] = 1;
    }
  }
  return NULL;
}

/* Explicit native modules stay outside the retained program artifact. */
static void _program_native_dependencies(ReplProgram program, CliRequest request) {
  foreach (String path, request.native_modules)
    if (Path.is_file(path)) {
      String file = Path.resolved_absolute(path);
      if (!file.startswith(%"$(program.directory)/"))
        program.dependencies[file] = Path.content_identity(file);
    }
}

/* The native linker identifies the files it selected, including -L/-l and
   linker forwarding options. Static archives are baked into the artifact. */
static void _program_link_dependencies(ReplProgram program, String text) {
  foreach (String line, text.split("\n")) {
    String file = line.strip(NULL);
    if (!(file.endswith(".dylib") || ".so" in Path.basename(file) ||
          ".framework/" in file) || !Path.is_file(file)) continue;
    file = Path.resolved_absolute(file);
    if (!file.startswith(%"$(program.directory)/"))
      program.dependencies[file] = Path.content_identity(file);
  }
}

/* Selection reads declarations before building. Only explicitly added main
   roots can retire an earlier program root; startup keeps ordinary conflicts. */
static int _program_has_main(Frontend frontend, String path, String &failure) {
  if (!(Path.is_x2c_source(path) || path.endswith(".c"))) return 0;
  ParsedUnit unit;
  int opened = frontend.start(path, unit);
  defer unit.close();
  Compiler c = unit.compiler;
  if (opened && Path.is_x2c_source(path))
    opened = unit.collect(frontend) && unit.parse();
  else if (opened) {
    opened = unit.collect_native(frontend);
    if (opened) unit.ast = c.full_parse_native(unit.globals);
    opened = opened && !c.error_count();
  }
  if (!opened) {
    foreach (List diagnostic, c.diagnostics()) c.print_diagnostic(diagnostic);
    failure = %"$path: x2c could not collect its declarations";
    return 0;
  }
  foreach (List node, unit.ast)
    match (node) case %(function ? (bind (binding ? "main") ?) ?):
      if (_program_owned(c, node, path)) return 1;
  return 0;
}

static List _program_select_roots(
  Frontend frontend, List roots, List requested, String &failure) {
  Map additions = {};
  int has_main = 0;
  foreach (String root, requested) {
    String path = Path.resolved_absolute(root);
    additions[path] = 1;
    has_main |= _program_has_main(frontend, path, failure);
    if (failure) return NULL;
  }
  if (!has_main) return roots;
  Array selected = [];
  foreach (String root, roots) {
    String path = Path.resolved_absolute(root);
    if (!(path in additions) && _program_has_main(frontend, path, failure))
      continue;
    if (failure) return NULL;
    selected.push(root);
  }
  return selected.list_free();
}

/** Builds one native program in `directory`, which the caller creates and
    removes. Main-bearing `requested` roots replace earlier main-bearing
    roots; a NULL selection keeps ordinary startup conflicts. The program
    keeps only these roots; each build derives a manifest's inputs again.
*/
ReplProgram repl_program_build_selected(
  Frontend frontend, String directory, List roots, List requested,
  String &failure) {
  failure = NULL;
  ReplProgram program = xcalloc(1, sizeof(struct ReplProgram));
  *program = (struct ReplProgram) {
    .directory = directory, .symbols = {}, .addresses = {},
    .descriptions = {}, .sources = {}, .dependencies = {}, .macros = {},
    .cc_args = frontend.request.cc_args, .ld_args = frontend.request.ld_args};
  ProgramBuild build = {
    .program = program, .frontend = frontend, .roots = [], .headers = [],
    .objects = [], .exports = [], .includes = [], .seen = {}, .units = {},
    .fingerprints = {}, .packages = {}};
  CliRequest request = _program_request(build, failure);
  if (!request) return NULL;
  List derived = NULL;
  if (request != frontend.request) {
    frontend = Frontend.new(request);
    build.frontend = frontend;
    program.cc_args = request.cc_args;
    program.ld_args = request.ld_args;
    derived = request.inputs;
  }
  _program_native_dependencies(program, request);
  if (requested) roots = _program_select_roots(frontend, roots, requested, failure);
  if (failure) return NULL;
  Array native = [], source = [];
  foreach (String root, roots.append(derived)) {
    String path = Path.resolved_absolute(root);
    if (!Path.is_file(path)) { failure = %"cannot read input file: $root"; return NULL; }
    if (path.endswith(".o") || path.endswith(".a") || path.endswith(".so") ||
        path.endswith(".dylib")) {
      native.push(path);
      if (path.endswith(".so") || path.endswith(".dylib"))
        program.dependencies[path] = Path.content_identity(path);
    }
    else build.roots.push(path);
  }
  for (int i = 0; i < build.roots.len(); i++) {
    String path = build.roots[i], input = NULL;
    if (path in build.seen) continue;
    failure = _program_unit(build, path, input);
    if (failure) return NULL;
    if (!path.endswith(".h") && !(input in source)) source.push(input);
  }
  failure = _program_main(build);
  if (failure) return NULL;
  failure = _program_exports(build);
  if (failure) return NULL;
  program.module = %"$(program.directory)/program.module";
  List inputs = %(@source @(native.list()) @(build.objects.list()));
  String native_directory = %"$(program.directory)/native";
  failure = _program_native_build(build, request, inputs, <module>,
                                  program.module, native_directory);
  if (failure) return NULL;
  _program_generated_dirs(%"$native_directory/gen", build.includes);
  failure = _program_header(build);
  if (failure) return NULL;
  program.roots = roots;
  foreach (Var (file, before), build.fingerprints)
    if (Path.content_identity(file) != before) {
      failure = %"$file changed while loading; load it again";
      return NULL;
    }
  failure = _program_open(program);
  return failure ? NULL : program;
}

/** Publishes native addresses and compiler-owned declaration rows in a worker. */
void repl_program_bind(ReplProgram program, ReplSession session) {
  session.program = program;
  session.frontend.request.cc_args = program.cc_args;
  session.frontend.request.ld_args = program.ld_args;
  session.frontend.toolchain = Toolchain.new(session.frontend.request);
  foreach (Var (key, value), program.symbols)
    session.compiler.sym.define_global(key, value);
  foreach (Var (key, value), program.symbols)
    if (key is <list> && key.list().len() == 1 && value is <list> &&
        ((Type) value).is_enum() && !(key.list().car() in program.addresses))
      session.compiler.sym.declare_enumerator(key, <enumerator>);
  foreach (Var (name, description), program.descriptions) {
    session.descriptions[name] = description;
    Symbol kind = description.map()["kind"];
    String path = description.map()["path"];
    session.names[name] = %($kind (source $path));
  }
  foreach (Var (name, address), program.addresses)
    session.addresses[name] = address;
  session.declarations.push(%(preproc $(%"#include $(program.header.repr())")));
}

/** Returns the changed explicit native dependency, or NULL when unchanged. */
String repl_program_changed(ReplProgram program) {
  foreach (Var (path, identity), program.dependencies)
    if (Path.content_identity(path) != identity)
      return %"native dependency changed: $path; use :reload";
  return NULL;
}

/* Source files have one snapshot entry; a descriptor's shared in-process
   source reference must not duplicate that entire file on the wire. */
static Map _program_snapshot_descriptions(ReplProgram program) {
  Map descriptions = {};
  foreach (Var (name, raw), program.descriptions) {
    Map description = raw.map().copy();
    description.del("source");
    descriptions[name] = description;
  }
  return descriptions;
}

/** Exports retained artifacts and descriptions, excluding process addresses. */
List repl_program_snapshot(ReplProgram p) =>
  $(p.directory, p.module, p.header, p.roots, p.exports,
    p.symbols, _program_snapshot_descriptions(p), p.sources, p.dependencies, p.macros,
    p.cc_args, p.ld_args);

/** Reopens an exact retained native program and recreates its addresses. */
ReplProgram repl_program_restore(List snapshot, String &failure) {
  ReplProgram p = xcalloc(1, sizeof(struct ReplProgram));
  p.directory = snapshot[0]; p.module = snapshot[1]; p.header = snapshot[2];
  p.roots = snapshot[3]; p.exports = snapshot[4];
  p.symbols = snapshot[5]; p.descriptions = snapshot[6]; p.sources = snapshot[7];
  p.dependencies = snapshot[8]; p.macros = snapshot[9];
  p.cc_args = snapshot[10]; p.ld_args = snapshot[11];
  foreach (Var (name, raw), p.descriptions) {
    Map description = raw;
    Var path = description["path"], source;
    if (path is <string> && p.sources.try_get(path, source))
      description["source"] = source;
  }
  failure = repl_program_changed(p);
  if (!failure) failure = _program_open(p);
  return failure ? NULL : p;
}
