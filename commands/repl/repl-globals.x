/*  repl-globals.x -- loaded object access through native helper calls

    Copyright (c) 2026 Gary William Flake.
*/
#pragma once
#include "repl-session.x"
#include "ast-rewrite.x"
#include "expressions/expressions.x"
#include "collect/collect.x"

/* Follow only field and index selections rooted at the actual published
   binding. Locals with the same spelling remain ordinary objects. */
static List _path(
  ReplSession session, List expression, String &path, Array arguments) {
  match (expression) {
    case %(expr ? ?inner): return _path(session, inner, path, arguments);
    case %(parens ?inner): return _path(session, inner, path, arguments);
    case %(index ?base ?index): {
      List entry = _path(session, base, path, arguments);
      if (!entry) return NULL;
      Sym symbols = session.compiler.sym;
      Type type = index.cadr();
      if (!symbols.resolve_numeric_type(type).is_integral() &&
          !symbols.is_named_value_type(type, "bool") &&
          !symbols.is_named_value_type(type, "_Bool"))
        raise %(repl (reason "loaded array indices must be integers"));
      path += "[]";
      arguments.push(_rewrite(session, index));
      return entry;
    }
    case %(op . ?base (?(String field))): {
      List entry = _path(session, base, path, arguments);
      if (entry) path += "." + field;
      return entry;
    }
    case %(ident ?binding): {
      String name = Ast.binding_spelling(binding);
      List entry = session.inspect(name);
      if (entry && entry.car() == <global> &&
          binding == session.compiler.sym.resolve_global($(name), NULL)) {
        path = name;
        return entry;
      }
    }
  }
  return NULL;
}

static List _global(ReplSession session, List expression) {
  String path = NULL;
  Array arguments = auto [];
  List global = _path(session, expression, path, arguments);
  if (!global) return NULL;
  Map paths = global.caddr();
  Var access;
  if (!paths.try_get(path, access))
    raise %(repl (reason "loaded field cannot cross the helper boundary"));
  return $(@(access.list()), arguments.list());
}

static int _snapshot(List entry) {
  Type type = entry.car().list().cadr();
  return type.apply() == %("Var");
}

static List _read(ReplSession session, List entry, Type type) {
  if (_snapshot(entry) && type != %("Var"))
    raise %(repl (reason
      "loaded aggregates support field access and whole-object inspection"));
  List call = session.compiler.resolve_expression(
    %(expr () (call $(entry.car()) (args @(entry.caddr())))), NULL);
  if (type.is_bitfield()) type = type.base_type();
  return session.compiler.convert_expression(call, type);
}

static List _write(
  ReplSession session, List entry, Type type, List value, int operation) {
  List setter = entry.cadr();
  if (_snapshot(entry))
    raise %(repl (reason "assign loaded fields or elements individually"));
  if (!setter) raise %(repl (reason "loaded const global is read-only"));
  Compiler c = session.compiler;
  if (type.is_bitfield()) type = type.base_type();
  value = c.convert_expression(value, type);
  List call = c.resolve_expression(
    %(expr () (call $setter
      (args @(entry.caddr()) $value $($!int{ $operation })))), NULL);
  return c.convert_expression(call, type);
}

/* A read-modify-write shares its evaluated indices between both calls. */
static List _indices(ReplSession session, List entry, Array setup) {
  Compiler c = session.compiler;
  Array arguments = auto [];
  foreach (List value, entry.caddr().list()) {
    List temporary = c.sym.introduce(c.fresh_name("repl_index"));
    setup.push(
      c.rebuild_statement($!{ long long $temporary = $value; }).cadr());
    arguments.push($!(long long){ $temporary });
  }
  return $(entry.car(), entry.cadr(), arguments.list());
}

static List _with_indices(List value, Array setup) => setup.len()
  ? %(expr $(value.cadr())
      (parens (block @(setup.list()) (stmnt $value)))) : value;

/** Replaces a whole loaded aggregate only at the prompt's display position.
    Other value uses retain the existing native data-crossing restrictions. */
List ReplSession.inspect_global(ReplSession session, List expression) {
  List entry = _global(session, expression);
  return entry && _snapshot(entry)
    ? _read(session, entry, %("Var")) : expression;
}

static List _addressed_global(ReplSession session, List expression) {
  match (expression) {
    case %(expr ? ?inner): return _addressed_global(session, inner);
    case %(cast ? ?inner): return _addressed_global(session, inner);
    case %(parens ?inner): return _addressed_global(session, inner);
    case %(op & ?inner): return _global(session, inner);
  }
  return NULL;
}

static void _check_arguments(
  ReplSession session, Type type, List arguments) {
  List parameters = NULL;
  if (type.is_pointer()) type = type.dereference();
  if (!type.function_parts(parameters, NULL)) return;
  while (parameters && arguments) {
    Type parameter = parameters.car();
    if (parameter.is_reference() && _global(session, arguments.car()))
      raise %(repl
        (reason "loaded globals cannot supply addresses or references"));
    parameters = parameters.cdr();
    arguments = arguments.cdr();
  }
}

/* Construct protocol Lists in source order. These are data expressions,
   not pointers or evaluator forms sent to the helper. */
static List _argument_list(Compiler c, List values) {
  if (!values) return %(expr ("List") (nil));
  List head = values.car(), tail = _argument_list(c, values.cdr());
  return c.resolve_expression($!List{ cons($head, $tail) }, NULL);
}

static List _object_argument(
  ReplSession session, Type parameter, List argument) {
  Compiler c = session.compiler;
  Type wanted = c.sym.normalize_declared_type(parameter);
  while (wanted.car() is <symbol> &&
         wanted.car().symbol().is_type_qualifier()) wanted = wanted.cdr();
  Type source = c.sym.normalize_declared_type(argument.cadr());
  int reference = wanted.is_reference();
  int record = c.sym.resolve_key(wanted).canonicalize().is_aggregate();
  List object = argument;
  if (!reference && !record) {
    if (!wanted.is_pointer()) return NULL;
    match (argument) {
      case %(expr ? (op & ?operand)): object = operand;
      case %(expr ? (parens ?inner)):
        return _object_argument(session, parameter, inner);
      default: if (!source.is_array()) return NULL;
    }
  }
  String path = NULL;
  Array indices = auto [];
  List entry = _path(session, object, path, indices);
  if (!entry) return NULL;
  Type object_type = object.cadr();
  if (object_type.is_bitfield())
    raise %(repl (reason "loaded bitfields cannot supply addresses"));
  // Ordinary conversion checks pointer compatibility and const qualifiers.
  List checked = argument;
  if (!reference && source.is_array()) {
    source = source.dereference().reference();
    checked = %(expr $source $(argument.caddr()));
  }
  (void) c.convert_expression(checked, parameter);
  if (record && c.sym.resolve_key(source).canonicalize() !=
                c.sym.resolve_key(wanted).canonicalize())
    raise %(repl (reason "loaded record argument has a different type"));
  auto Array setup = [], values = [];
  foreach (List index, indices) {
    List temporary = c.sym.introduce(c.fresh_name("repl_index"));
    setup.push(c.rebuild_statement($!{ long long $temporary = $index; }).cadr());
    values.push(%(expr (long long) (ident $temporary)));
  }
  List selected = _argument_list(c, values);
  Symbol tag = c.sym.var_tag_for_type(parameter, NULL);
  if (!tag) tag = <p48>;
  List descriptor = _argument_list(c, $(
    $!Symbol{ $(<object>) }, $!String{ $path }, selected, $!int{ $reference },
    $!Symbol{ $tag }));
  return _with_indices(descriptor, setup);
}

/* A complete typed call is selected before its object arguments become
   scalar getters. Its native callee and objects share the session helper. */
static List _loaded_call(
  ReplSession session, List callee, List arguments) {
  Compiler c = session.compiler;
  List binding = NULL;
  match (callee) {
    case %(expr ? (parens ?inner)):
      return _loaded_call(session, inner, arguments);
    case %(expr ? (ident ?found)): binding = found;
  }
  if (!binding) return NULL;
  String name = Ast.binding_spelling(binding);
  List entry = session.inspect(name);
  if (!entry || entry.car() != <native> ||
      binding != c.sym.resolve_global($(name), NULL)) return NULL;
  List adapter = entry.assoc(<objects>);
  if (!adapter) return NULL;
  Type type = c.loaded_call_type(callee.cadr());
  List parameters = NULL;
  type.function_parts(parameters, NULL);
  if (parameters && parameters.last() == %(....))
    arguments = c.pack_rest_arguments(parameters, arguments);
  if (parameters.len() != arguments.len()) return NULL;
  Array selected = auto [];
  int objects = 0;
  List remaining = parameters;
  foreach (List argument, arguments) {
    List object = _object_argument(session, remaining.car(), argument);
    remaining = remaining.cdr();
    selected.push(object);
    objects |= !!object;
  }
  if (!objects) return NULL;
  auto Array values = [], setup = [];
  int i = 0;
  foreach (List argument, arguments) {
    List value = selected[i++];
    if (!value) {
      Type parameter = parameters.car();
      int rest = parameter == %(....);
      List converted = c.convert_expression(
        _rewrite(session, argument), rest ? %("List") : parameter);
      Symbol kind = rest ? <splice> : <value>;
      value = _argument_list(c, $( $!Symbol{ $kind } , converted));
    }
    parameters = parameters.cdr();
    List temporary = c.sym.introduce(c.fresh_name("repl_argument"));
    setup.push(c.rebuild_statement($!{ List $temporary = $value; }).cadr());
    values.push(%(expr ("List") (ident $temporary)));
  }
  List packed = _argument_list(c, values);
  List call = c.resolve_expression(%(expr () (call $adapter (args $packed))), NULL);
  return _with_indices(call, setup);
}

static List _increment(
  ReplSession session, List entry, Type type, Symbol operator, Symbol kind) {
  Type accessor = entry.car().list().cadr();
  if (!accessor.apply().is_number())
    raise %(repl
      (reason "loaded global increments require a numeric type"));
  if (kind == <postfix>) return _write(
    session, entry, type, $!int{ 0 }, operator == <++> ? 1 : 2);
  Array setup = auto [];
  entry = _indices(session, entry, setup);
  Symbol applied = operator == <++> ? <+> : <->;
  List value = session.compiler.resolve_expression(
    %(expr () (op $applied $(_read(session, entry, type)) $($!int{ 1 }))),
    NULL);
  return _with_indices(_write(session, entry, type, value, 0), setup);
}

static Var _rewrite(ReplSession session, Var node) {
  if (node is not <list>) return node;
  Compiler c = session.compiler;
  match (node) {
    case %(stmnt (expr ? (dstrasgn (targets *targets) ?))):
      foreach (List target, targets)
        if (_global(session, target)) return _rewrite(
          session,
          c.rewrite(<node>, <stmnt>, node, <statement>, NULL, NULL));
    case %(expr ?type (dstrasgn (targets *targets) ?)):
      foreach (List target, targets)
        if (_global(session, target)) return _rewrite(
          session,
          c.rewrite(<literal>, <dstrasgn>, node, <expression>, type, NULL));
    /* Dynamic calls prepare both value and reference alternatives. A remote
       object supplies a value, never an address, including optional refs. */
    case %(expr ? (call (!set ?callee
        (expr ? (ident (!set ?binding (binding ? "FuncArg_reference")))))
        (args ?address ?)))
      if (binding == c.sym.resolve_global(%("FuncArg_reference"), NULL) &&
          _addressed_global(session, address)):
        return c.resolve_expression(
          %(expr () (call $callee (args $($!int{ 0 }) $($!int{ 0 })))), NULL);
    case %(expr ? (call (!set ?callee (expr ?(Type type) ?))
                              (args *arguments))): {
      List call = _loaded_call(session, callee, arguments);
      if (call) return call;
      _check_arguments(session, type, arguments);
    }
    case %(expr ? (op & ?operand)):
      if (_global(session, operand))
        raise %(repl
          (reason "loaded globals cannot supply addresses or references"));
    case %(expr ?type (op ?operator ?target ?rhs))
      if (operator == <=> || Symbol.compound_operator(operator)): {
      List entry = _global(session, target);
      Symbol applied = Symbol.compound_operator(operator);
      if (entry) {
        Array setup = auto [];
        if (applied) entry = _indices(session, entry, setup);
        List value = _rewrite(session, rhs);
        if (applied) value = c.resolve_expression(
          %(expr () (op $applied $(_read(session, entry, type)) $value)),
          NULL);
        return _with_indices(_write(session, entry, type, value, 0), setup);
      }
    }
    case %(expr ?type ((!or ?kind op postfix) ?operator ?target))
      if (operator == <++> || operator == <"--">): {
        List entry = _global(session, target);
        if (entry) return _increment(session, entry, type, operator, kind);
      }
    case %(expr ?type (!or (ident ?) (index ? ?) (op . ? ?))): {
      List entry = _global(session, node);
      if (entry) return _read(session, entry, type);
    }
  }
  List child;
  $ast.rewrite_children(node, child, _rewrite(session, child));
}

/** Replaces bound loaded object reads and writes before either prompt
    backend runs. The accessors retain the file record across reloads. */
List ReplSession.rewrite_globals(ReplSession session, List syntax) =>
  session.accessors.len() ? _rewrite(session, syntax) : syntax;
