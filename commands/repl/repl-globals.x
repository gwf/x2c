/*  repl-globals.x -- loaded scalar access through native helper calls

    Copyright (c) 2026 Gary William Flake.
*/
#pragma once
#include "repl-session.x"
#include "ast-rewrite.x"
#include "expressions.x"

/* Match the actual global binding, so parameters and locals with the same
   spelling remain ordinary native or interpreted objects. */
static List _global(ReplSession session, List expression) {
  match (expression) {
    case %(expr ? ?inner): return _global(session, inner);
    case %(parens ?inner): return _global(session, inner);
    case %(ident ?binding): {
      String name = Ast.binding_spelling(binding);
      List entry = session.inspect(name);
      if (entry && entry.car() == <global> &&
          binding == session.compiler.sym.resolve_global(%($name), NULL))
        return entry;
    }
  }
  return NULL;
}

static List _read(ReplSession session, List entry, Type type) {
  List call = session.compiler.resolve_expression(
    %(expr () (call ${entry.caddr()} (args))), NULL);
  return session.compiler.convert_expression(call, type);
}

static List _write(
  ReplSession session, List entry, Type type, List value, int operation) {
  List setter = entry.cadddr();
  if (!setter) raise %(repl (reason "loaded const global is read-only"));
  Compiler c = session.compiler;
  value = c.convert_expression(value, type);
  List call = c.resolve_expression(
    %(expr () (call $setter (args $value ${$!int{ $operation }}))), NULL);
  return c.convert_expression(call, type);
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
  Type accessor = entry.caddr().list().cadr();
  if (!accessor.apply().is_number())
    raise %(repl
      (reason "loaded global increments require a numeric type"));
  if (kind == <postfix>) return _write(
    session, entry, type, $!int{ 0 }, operator == <++> ? 1 : 2);
  Symbol applied = operator == <++> ? <+> : <->;
  List value = session.compiler.resolve_expression(
    %(expr () (op $applied ${_read(session, entry, type)} ${$!int{ 1 }})),
    NULL);
  return _write(session, entry, type, value, 0);
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
    case %(expr ?type (op ?operator ?target ?rhs)): {
      List entry = _global(session, target);
      Symbol applied = Symbol.compound_operator(operator);
      if (entry && (operator == <=> || applied)) {
        List value = _rewrite(session, rhs);
        if (applied) value = c.resolve_expression(
          %(expr () (op $applied ${_read(session, entry, type)} $value)),
          NULL);
        return _write(session, entry, type, value, 0);
      }
    }
    case %(expr ?type ((!set ?kind (!or op postfix)) ?operator ?target))
      if (operator == <++> || operator == <"--">): {
        List entry = _global(session, target);
        if (entry) return _increment(session, entry, type, operator, kind);
      }
    case %(expr ?type (ident ?)): {
      List entry = _global(session, node);
      if (entry) return _read(session, entry, type);
    }
  }
  List child;
  $ast.rewrite_children(node, child, _rewrite(session, child));
}

/** Replaces bound loaded scalar reads and writes before either prompt
    backend runs. The accessors retain the file record across reloads. */
List ReplSession.rewrite_globals(ReplSession session, List syntax) =>
  session.accessors.len() ? _rewrite(session, syntax) : syntax;
