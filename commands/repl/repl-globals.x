/*  repl-globals.x -- loaded object access through native helper calls

    Copyright (c) 2026 Gary William Flake.
*/
#pragma once
#include "repl-session.x"
#include "ast-rewrite.x"
#include "expressions.x"

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
          binding == session.compiler.sym.resolve_global(%($name), NULL)) {
        path = name;
        return entry;
      }
    }
  }
  return NULL;
}

static List _global(ReplSession session, List expression) {
  String path = NULL;
  Array arguments = $auto([]);
  List global = _path(session, expression, path, arguments);
  if (!global) return NULL;
  Map paths = global.caddr();
  Var access;
  if (!paths.try_get(path, access))
    raise %(repl (reason "loaded field cannot cross the helper boundary"));
  return %(@{access.list()} ${arguments.list()});
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
    %(expr () (call ${entry.car()} (args @{entry.caddr()}))), NULL);
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
      (args @{entry.caddr()} $value ${$!int{ $operation }}))), NULL);
  return c.convert_expression(call, type);
}

/* A read-modify-write shares its evaluated indices between both calls. */
static List _indices(ReplSession session, List entry, Array setup) {
  Compiler c = session.compiler;
  Array arguments = $auto([]);
  foreach (List value, entry.caddr().list()) {
    List temporary = c.sym.introduce(c.fresh_name("repl_index"));
    setup.push(
      c.rebuild_statement($!{ long long $temporary = $value; }).cadr());
    arguments.push($!(long long){ $temporary });
  }
  return %(${entry.car()} ${entry.cadr()} ${arguments.list()});
}

static List _with_indices(List value, Array setup) => setup.len()
  ? %(expr ${value.cadr()}
      (parens (block @{setup.list()} (stmnt $value)))) : value;

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

static List _increment(
  ReplSession session, List entry, Type type, Symbol operator, Symbol kind) {
  Type accessor = entry.car().list().cadr();
  if (!accessor.apply().is_number())
    raise %(repl
      (reason "loaded global increments require a numeric type"));
  if (kind == <postfix>) return _write(
    session, entry, type, $!int{ 0 }, operator == <++> ? 1 : 2);
  Array setup = $auto([]);
  entry = _indices(session, entry, setup);
  Symbol applied = operator == <++> ? <+> : <->;
  List value = session.compiler.resolve_expression(
    %(expr () (op $applied ${_read(session, entry, type)} ${$!int{ 1 }})),
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
          %(expr () (call $callee (args ${$!int{ 0 }} ${$!int{ 0 }}))), NULL);
    case %(expr ? (call (expr ?(Type type) ?) (args *arguments))):
      _check_arguments(session, type, arguments);
    case %(expr ? (op & ?operand)):
      if (_global(session, operand))
        raise %(repl
          (reason "loaded globals cannot supply addresses or references"));
    case %(expr ?type (op ?operator ?target ?rhs))
      if (operator == <=> || Symbol.compound_operator(operator)): {
      List entry = _global(session, target);
      Symbol applied = Symbol.compound_operator(operator);
      if (entry) {
        Array setup = $auto([]);
        if (applied) entry = _indices(session, entry, setup);
        List value = _rewrite(session, rhs);
        if (applied) value = c.resolve_expression(
          %(expr () (op $applied ${_read(session, entry, type)} $value)),
          NULL);
        return _with_indices(_write(session, entry, type, value, 0), setup);
      }
    }
    case %(expr ?type ((!set ?kind (!or op postfix)) ?operator ?target))
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
