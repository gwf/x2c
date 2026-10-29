/*  repl-inspect.x -- native values and library exploration

    Copyright (c) 2026 Gary William Flake.
*/
#pragma once
#include "repl-types.x"
#include "expressions/expressions.x"
#include "emit/emit.x"
#include "format.x"
#include "buffer.x"
#include "ast-rewrite.x"

List ReplSession.resolve(ReplSession session, String expression);

static String _declaration(Compiler c, Type type, List binding) =>
  String.new(c.code_pretty_string(
    c.emit($(type.declaration_ast(binding)), NULL), NULL)).strip(NULL);

static String _type_text(Compiler c, Type type) =>
  _declaration(c, type.declared(), NULL).rstrip(";");

static Map _description(ReplSession session, String name) {
  Var entry;
  if (session.descriptions.try_get(name, entry)) return entry;
  Compiler c = session.compiler;
  List expression = session.resolve(name);
  match (expression) case %(expr ? (ident ?binding)): {
    String spelling = Ast.binding_spelling(binding);
    if (spelling && session.descriptions.try_get(spelling, entry))
      return entry;
  }
  int dot = name.rfind(".");
  if (dot >= 0) {
    Type receiver = _query_type(session, name[:dot]);
    if (!receiver) return NULL;
    Map methods = auto {};
    _methods(c, receiver, NULL, methods, {});
    Array rows = methods[name[dot + 1:]];
    if (rows && rows.len() == 1) {
      String spelling = Ast.binding_spelling(rows[0].list().car());
      if (session.descriptions.try_get(spelling, entry)) return entry;
    }
  }
  return NULL;
}

static String _named_declaration(
  Compiler c, String name, Type type, List syntax) {
  syntax = Ast.without_origin(syntax);
  match (syntax) {
    case %(function ?spec ?bound ?):
      return String.new(c.code_pretty_string(
        c.emit(%((declare $spec (bindings $bound))), NULL), NULL)).strip(NULL);
    case %((!or declare typedef) *):
      return String.new(c.code_pretty_string(c.emit($(syntax), NULL), NULL))
        .strip(NULL);
  }
  return _declaration(c, type, $(name));
}

/** Retains the submitted definition beside its successfully published name. */
void ReplSession.describe(
  ReplSession session, String name, List syntax, String source) {
  Compiler c = session.compiler;
  List entry = session.names[name];
  Type type = c.sym.get_exact($(name));
  if (!type) type = c.sym.get_exact(%(typedef $name));
  session.descriptions[name] = {
    "name": name, "kind": entry ? entry.car() : <value>, "type": type,
    "path": "prompt", "source": source, "body": source, "syntax": syntax,
    "declaration": _named_declaration(c, name, type, syntax),
    "line": 1, "end_line": source.split("\n").len()
  };
  foreach (List row in c.definition_rows($(Ast.without_origin(syntax))))
    match (row) case %(function $name ?display ? ? ?line ?doc *): {
      Map description = session.descriptions[name];
      description["display"] = display;
      description["line"] = line;
      if (doc is <string>) description["documentation"] = doc;
    }
}

static Map _symbol_descriptions(ReplSession session, int all) {
  Map descriptions = session.descriptions.copy();
  if (!all) return descriptions;
  foreach (List row in session.compiler.sym.visible_symbols()) {
    (String name, Var raw) = row;
    if (name in descriptions || raw is not <list>) continue;
    Type type = raw;
    descriptions[name] = {
      "name": name, "type": type, "path": "runtime/dependency",
      "kind": type.is_function() ? <function>
          : type.is_typedef() ? <type> : <value>,
      "declaration": _declaration(session.compiler, type, $(name))
    };
  }
  return descriptions;
}

/** Lists readable declarations from the selected namespace and filters. */
String ReplSession.symbol_text(
  ReplSession session, String prefix, Symbol kind, String path, int all) {
  Map descriptions = auto _symbol_descriptions(session, all);
  Array names = auto [];
  foreach (String name in descriptions.keys()) names.push(name);
  Buffer out = auto Buffer.new(0);
  foreach (String name in names.sort()) {
    Map row = descriptions[name];
    Symbol row_kind = row["kind"];
    String origin = row["path"], declaration = row["declaration"];
    String display = row["display"];
    if (prefix && !name.startswith(prefix) &&
        (!display || !display.startswith(prefix))) continue;
    if (kind && row_kind != kind &&
        !(kind == <function> && row_kind == <native>)) continue;
    if (path && origin != path &&
        (!origin || Path.absolute(origin) != Path.absolute(path))) continue;
    out.printf("%-9s %s", row_kind == <native> ? "function" : row_kind.str(),
               display && display != name ? display
                 : declaration ? declaration : name);
    if (display && display != name && declaration)
      out.printf("  %s", declaration);
    if (origin) out.printf("  [%s]", origin);
    out.newline();
  }
  return out;
}

static Type _query_type(ReplSession session, String text) {
  Compiler c = session.compiler;
  if (c.sym.get_exact(%(typedef $text))) return $(text);
  foreach (Symbol tag in %<<struct union enum>>) {
    String prefix = tag.str() + " ";
    if (text.startswith(prefix)) {
      Type type = $(tag, text.remove_prefix(prefix).strip(NULL));
      if (c.sym.field_order(type) ||
          c.sym.get(%(@type "enumerators"))) return type;
    }
  }
  List expression = session.resolve(text);
  return expression ? expression.cadr() : NULL;
}

static Type _shape(Compiler c, Type type) =>
  c.sym.resolve_key(c.sym.normalize_declared_type(type).canonicalize());

static void _field_rows(Compiler c, Type type, Buffer out) {
  foreach (String name in c.postfix_completions(type, <.>)) {
    List selected = c.resolve_postfix_member(type, $(name), <.>, 1, NULL);
    match (selected) case %(field ? ?member):
      out.printf("  field    %s\n", _declaration(c, member, $(name)));
  }
}

static Type _identity(Compiler c, Type type) {
  type = c.sym.normalize_declared_type(type).canonicalize();
  while (type.is_pointer() || type.is_array())
    type = c.sym.normalize_declared_type(type.dereference()).canonicalize();
  return c.sym.resolve_key(type);
}

static int _related(Compiler c, Type candidate, Type sought) {
  Type identity = _identity(c, sought);
  if (!identity || identity == %(void)) return 0;
  return _identity(c, candidate) == identity;
}

static void _related_functions(
  ReplSession session, Type type, Buffer out, Map shown) {
  Compiler c = session.compiler;
  foreach (List row in c.sym.visible_symbols()) {
    (String name, Var raw) = row;
    if (raw is not <list> || name in shown) continue;
    Type signature = raw, result = NULL;
    List parameters = NULL;
    if (!signature.function_parts(parameters, result)) continue;
    int position = 0, related = _related(c, result, type);
    foreach (Type parameter in parameters) {
      position++;
      if (_related(c, parameter, type)) related = 1;
    }
    if (!related) continue;
    Map description = session.descriptions[name];
    String declaration = description ? description["declaration"] : NULL;
    out.printf("  function %s\n",
      declaration ? declaration : _declaration(c, signature, $(name)));
    if (_related(c, result, type)) out.write("           returns this type\n");
    position = 0;
    foreach (Type parameter in parameters) {
      position++;
      if (_related(c, parameter, type))
        out.printf("           argument %d\n", position);
    }
  }
}

static void _methods(
  Compiler c, Type type, String path, Map methods, Map visited) {
  Type identity = type.canonicalize();
  if (identity in visited) return;
  Map active = auto visited.copy();
  active[identity] = 1;
  foreach (String name in c.postfix_completions(type, <.>)) {
    List resolved = c.resolve_postfix_member(type, $(name), <.>, 1, NULL);
    match (resolved) case %(method ?binding ?signature): {
      if (!path) methods[name] = [$(binding, signature, "")];
      else {
        Array rows = methods[name];
        if (!rows) rows = methods[name] = [];
        if (!rows.len() || rows[0].list()[2].str())
          rows.push($(binding, signature, path));
      }
    }
  }
  Type shape = _shape(c, type);
  if (shape.is_pointer()) shape = _shape(c, shape.dereference());
  foreach (List row in c.sym.marked_fields(shape, <delegate>)) {
    (String name, Type field) = row;
    _methods(c, field, path ? path + "." + name : name, methods, active);
  }
}

/** Lists direct and unambiguous delegated names for receiver completion. */
List repl_member_candidates(Compiler c, Type type) {
  Map methods = auto {};
  _methods(c, type, NULL, methods, {});
  Map names = auto {};
  foreach (String name in c.postfix_completions(type, <.>)) names[name] = 1;
  foreach (Var (name, raw) in methods)
    if (raw.array().len() == 1) names[name] = 1;
  Array sorted = auto [], candidates = [];
  foreach (String name in names.keys()) sorted.push(name);
  foreach (String name in sorted.sort()) candidates.push(%(member $name));
  return candidates.list_free();
}

static void _method_rows(Compiler c, Type type, Buffer out, Map shown) {
  Map methods = auto {};
  _methods(c, type, NULL, methods, {});
  Array names = auto [];
  foreach (String name in methods.keys()) names.push(name);
  foreach (String name in names.sort()) {
    Array rows = methods[name];
    if (rows.len() > 1) {
      out.printf("  ambiguous method %s", name);
      foreach (List row in rows) out.printf(" via %s", row[2]);
      out.newline();
      continue;
    }
    List row = rows[0];
    (List binding, Type signature, String path) = row;
    String spelling = Ast.binding_spelling(binding);
    shown[spelling] = 1;
    out.printf("  method   %s", _declaration(c, signature, $(name)));
    if (path) out.printf("  [via %s]", path);
    out.newline();
  }
}

/** Lists fields, methods, and C functions involving a receiver's type. */
String ReplSession.members(ReplSession session, String text) {
  Type type = _query_type(session, text);
  if (!type) return NULL;
  Buffer out = auto Buffer.new(0);
  out.printf("%s\n", _type_text(session.compiler, type));
  _field_rows(session.compiler, type, out);
  Map shown = auto {};
  _method_rows(session.compiler, type, out, shown);
  _related_functions(session, type, out, shown);
  return out;
}

/** Describes a declaration or expression type without executing input. */
String ReplSession.info(ReplSession session, String text) {
  Map description = _description(session, text);
  Buffer out = auto Buffer.new(0);
  if (description) {
    String declaration = description["declaration"], path = description["path"];
    String display = description["display"], name = description["name"];
    if (display && display != name) out.printf("%s\n", display);
    out.printf("%s\n", declaration ? declaration : text);
    if (path) {
      out.printf("source: %s", path);
      if (description["line"] is not void)
        out.printf(":%d", description["line"].int());
      out.newline();
    }
    String documentation = description["documentation"];
    if (documentation) out.printf("%s\n", documentation);
    out.write("execution: native\n");
    Type type = description["type"];
    if (type && !type.is_function()) {
      _field_rows(session.compiler, type, out);
      Map shown = auto {};
      _method_rows(session.compiler, type, out, shown);
    }
    return out;
  }
  Type type = _query_type(session, text);
  if (!type) return NULL;
  out.printf("%s\n", _type_text(session.compiler, type));
  _field_rows(session.compiler, type, out);
  Map shown = auto {};
  _method_rows(session.compiler, type, out, shown);
  return out;
}

/** Shows the retained authored definition or its available declaration. */
String ReplSession.source(ReplSession session, String name) {
  Map row = _description(session, name);
  if (!row) return NULL;
  String body = row["body"], path = row["path"];
  Buffer out = auto Buffer.new(0);
  out.printf("%s", path ? path : "<unknown>");
  if (row["line"] is not void) out.printf(":%d", row["line"].int());
  out.newline();
  if (body) out.printf("%s\n", body.rstrip("\n"));
  else {
    out.write("definition unavailable; declaration follows\n");
    out.printf("%s\n", row["declaration"]);
  }
  return out;
}

/** Displays known value containers without invoking user representation hooks. */
Buffer repl_inspect_value(Buffer out, Var value, int depth, int *remaining) {
  if (value is <string>) return String.write_repr(value, out);
  if (value is <symbol>) return Symbol.write_repr(value, out);
  if (value is not <array> && value is not <map> && value is not <list>)
    return value.fallback_write_repr(out);
  if (depth <= 0) return out.write("...");
  int separator = 0;
  if (value is <list>) {
    out.write("(");
    List items = value;
    while (items && *remaining > 0) {
      if (separator++) out.write(" ");
      (*remaining)--;
      repl_inspect_value(out, items.car(), depth - 1, remaining);
      items = items.cdr();
    }
    if (items) out.write("...");
    return out.write(")");
  }
  if (value is <array>) {
    Array items = value;
    out.write("[ ");
    size_t index = 0;
    while (index < items.len() && *remaining > 0) {
      if (separator++) out.write(", ");
      (*remaining)--;
      repl_inspect_value(out, items[index++], depth - 1, remaining);
    }
    if (index < items.len()) out.write("...");
    return out.write(" ]");
  }
  Map items = value;
  out.write("{ ");
  unsigned cursor = 0;
  Var key, item;
  while (*remaining > 0 && items.try_next(cursor, key, item)) {
    if (separator++) out.write(", ");
    (*remaining)--;
    repl_inspect_value(out, key, depth - 1, remaining);
    out.write(": ");
    repl_inspect_value(out, item, depth - 1, remaining);
  }
  if (*remaining <= 0 && items.try_next(cursor, key, item)) out.write("...");
  return out.write(" }");
}

static List _write(List output, String text) => $!{ $output.write($text); };

static int _builtin_value(Compiler c, Type type) {
  foreach (String name in %("Var" "String" "Symbol" "List" "Array" "Map"))
    if (c.sym.is_named_value_type(type, name)) return 1;
  return 0;
}

static List _render_array(
  Compiler c, Type type, List expression, List output,
  List remaining, int depth) {
  List index = c.sym.introduce(c.fresh_name("repl_index"));
  List position = %(expr (unsigned long long) (ident $index));
  Type element = type.dereference();
  List selected = %(expr $element (index $expression $position));
  List item = _render_value(c, element, selected, output, remaining, depth - 1);
  return $!{
    $output.write("[ ");
    unsigned long long $index = 0;
    for (; $position < sizeof($expression) / sizeof($expression[0]) &&
           $remaining > 0; $position++) {
      if ($position) $output.write(", ");
      $remaining--;
      @($(item))
    }
    if ($position < sizeof($expression) / sizeof($expression[0]))
      $output.write("...");
    $output.write(" ]");
  };
}

static void _render_fields(
  Compiler c, Type shape, List expression, List output,
  List remaining, int depth, List separated, List truncated, Array statements) {
  foreach (List row in c.sym.field_order(shape).cdr()) {
    (String name, Type member) = row;
    Type member_shape = _shape(c, member);
    if (!name && (member_shape ~= %(struct *))) {
      _render_fields(c, member_shape, expression, output, remaining, depth,
                     separated, truncated, statements);
      continue;
    }
    if (!name && !(member_shape ~= %(union *))) continue;
    List selected = name
      ? %(expr $member (op . $expression ($name))) : NULL;
    List value = !name ? _render_union(c, member_shape, output)
      : <volatile> in c.sym.normalize_declared_type(member)
        ? _write(output, "<volatile>")
        : _render_value(c, member, selected, output, remaining, depth - 1);
    if (!name) name = "<anonymous union>";
    String label = name + ": ";
    statements.push($!{
      if ($remaining > 0) {
        if ($separated) $output.write(", ");
        $separated = 1;
        $output.write($label);
        $remaining--;
        @($(value))
      }
      else $truncated = 1;
    });
  }
}

static List _render_struct(
  Compiler c, Type shape, List expression, List output,
  List remaining, int depth) {
  if (!c.sym.field_order(shape)) return _write(output, "<opaque>");
  Array statements = [];
  List separator = c.sym.introduce(c.fresh_name("repl_separator"));
  List separated = %(expr (int) (ident $separator));
  List truncation = c.sym.introduce(c.fresh_name("repl_truncated"));
  List truncated = %(expr (int) (ident $truncation));
  _render_fields(c, shape, expression, output, remaining, depth,
                 separated, truncated, statements);
  return $!{
    $output.write("{ ");
    int $separator = 0, $truncation = 0;
    @(statements.list_free())
    if ($truncated) $output.write(", ...");
    $output.write(" }");
  };
}

static List _render_union(Compiler c, Type shape, List output) {
  Buffer text = auto Buffer.new(0);
  text.write("{ members: ");
  int separator = 0;
  foreach (List row in c.sym.field_order(shape).cdr()) {
    String name = row.car();
    if (!name) continue;
    if (separator++) text.write(", ");
    text.write(name);
  }
  text.write("; select a member to inspect }");
  return _write(output, text);
}

static List _render_value(
  Compiler c, Type type, List expression, List output,
  List remaining, int depth) {
  if (type.is_bitfield()) {
    type = type.base_type();
    expression = %(expr $type (cast $type $expression));
  }
  Type shape = _shape(c, type);
  if (type.canonicalize() == %(void)) return _write(output, "void");
  if (_builtin_value(c, type))
    return $!{
      repl_inspect_value($output, (Var) $expression, $depth, &$remaining);
    };
  if (c.sym.resolve_numeric_type(type) ||
      c.sym.is_named_value_type(type, "bool") ||
      c.sym.is_named_value_type(type, "_Bool"))
    return $!{ ((Var) $expression).fallback_write_repr($output); };
  if (shape.is_pointer() || shape.is_function())
    return $!{ $output.printf("%p", (void *) $expression); };
  if (depth <= 0) return _write(output, "...");
  if (shape.is_array())
    return _render_array(c, shape, expression, output, remaining, depth);
  if (shape ~= %(struct *))
    return _render_struct(c, shape, expression, output, remaining, depth);
  if (shape ~= %(union *)) return _render_union(c, shape, output);
  return _write(output, "<unavailable>");
}

/** Builds native display code over an already captured typed value. */
List repl_render(
  Compiler c, Type type, List expression, List output, int depth, int limit) {
  List bound = c.sym.introduce(c.fresh_name("repl_remaining"));
  List remaining = %(expr (int) (ident $bound));
  List body = _render_value(c, type, expression, output, remaining, depth);
  List writer = c.sym.introduce("repl_inspect_value");
  String label = _type_text(c, type) + " ";
  List written = $!{
    Buffer $writer(Buffer, Var, int, int *);
    int $bound = $limit;
    $output.write($label);
    @($(body))
  };
  return %(block $written);
}
