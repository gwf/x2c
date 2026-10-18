/*  repl-native.x -- prompt functions with shared session bindings

    Copyright (c) 2026 Gary William Flake.
*/
#pragma once
#include "repl-session.x"
#include "ast-rewrite.x"
#include "callables/callables.x"
#include "expressions/expressions.x"
#include "meta-group/meta-group.x"
#include "lambdas.x"
#include "protocol/protocol.x"
#include "repl-native-types.x"

static typedef struct PromptFunction {
  ReplSession session;
  List syntax, original, body, self, context;
  Type type, body_type;
  Map captures;
  Array values;
} PromptFunction;

static List _local(Compiler c, List expression) => c.lambda_scopes
  ? c.capture_lambda_identifier(expression.caddr().cadr(), expression.cadr())
  : expression;

/* Every capture is a pointer: either a native object's address or a Func.
   The factory copies these pointers into the new function's context. */
static List _capture(
  PromptFunction &p, List binding, void *pointer, Type type) {
  Var index;
  if (!p.captures.try_get(binding, index)) {
    index = (int) p.values.len();
    p.captures[binding] = index;
    p.values.push(pointer);
  }
  List slot = %(expr (* void)
    (index ${_local(p.session.compiler, p.context)} ${$!int{ $index }}));
  return %(expr $type (cast $type $slot));
}

/* Only published session bindings need an indirect call or shared object.
   Ordinary library functions keep the compiler's native call path. */
static List _session_value(PromptFunction &p, Type type, List binding) {
  String name = Ast.binding_spelling(binding);
  Compiler c = p.session.compiler;
  Type global_type = NULL;
  List global = c.sym.resolve_global(%($name), global_type);
  if (!global || !global.equal(binding)) return NULL;
  List entry = p.session.inspect(name);
  if (type.is_function()) {
    if (!entry && !(name in p.session.accessors) &&
        name != "print" && name != "println") return NULL;
    Var callable;
    if (!p.session.evaluator.try_get(name, callable) || callable is not <func>)
      raise %(repl (reason ${%"function has no native binding: $name"}));
    return _capture(p, binding, callable.pointer(), %("Func"));
  }
  if (!entry || entry.car() != <value>) return NULL;
  Var stored;
  p.session.evaluator.try_get("C.globals", stored);
  Map globals = stored;
  Var address = globals[binding.cadr()];
  Type pointer = type.reference();
  List captured = _capture(p, binding, address.pointer(), pointer);
  return %(expr $type (op * $captured));
}

static List _rewrite_call(
  PromptFunction &p, Type result, Var target, List arguments) {
  Compiler c = p.session.compiler;
  Array rewritten = $auto([]);
  foreach (Var argument, arguments) rewritten.push(_rewrite(p, argument));
  match (target)
    case %(expr ? (ident ${p.original})):
      return %(expr $result (call (expr ${p.body_type} (ident ${p.body}))
        (args ${_local(c, p.self)} @{rewritten.list()})));
  Var callee = _rewrite(p, target);
  match (callee) case %(expr ("Func") ?): {
    /* A Func boxes each value argument by its own type, so give it the type
       the declaration names, as the native call it replaces would. The call
       passes a reference argument's own place. */
    match (target) case %(expr ((func ?declared) *) ?):
      for (int i = 0; declared && i < rewritten.len(); i++) {
        Var param = car(declared);
        declared = cdr(declared);
        if (param is <list> && !((Type) param).is_reference())
          rewritten[i] = c.convert_expression(rewritten[i], param);
      }
    List call = c.resolve_expression(
      %(expr () (call $callee (args @{rewritten.list()}))), NULL);
    return c.convert_expression(call, result);
  }
  return %(expr $result (call $callee (args @{rewritten.list()})));
}

static Var _rewrite(PromptFunction &p, Var node) {
  if (node is not <list>) return node;
  Compiler c = p.session.compiler;
  match (node) {
    case %(expr ?type (lambda ?params (captures *captures) ?body)):
      return _rewrite_lambda(p, type, params, captures, body);
    case %(expr ?type (lambda ?params ?body)):
      return _rewrite_lambda(p, type, params, NULL, body);
    case %(expr ?result (call ?target (args *arguments))):
      return _rewrite_call(p, result, target, arguments);
    case %(expr ? (parens (!set ?inner (expr ? ?)))): {
      List rewritten = _rewrite(p, inner);
      return %(expr ${rewritten.cadr()} (parens $rewritten));
    }
    case %(expr ?type (op & (expr ?(Type source) ?payload))): {
      List operand = _rewrite(p, %(expr $source $payload));
      if (source.is_function() && operand.cadr() == %("Func")) return operand;
      return %(expr $type (op & $operand));
    }
    case %(expr ?type (op ?operator (expr ?source ?payload)))
      if (operator == <"*">): {
        List operand = _rewrite(p, %(expr $source $payload));
        return source != %("Func") && operand.cadr() == %("Func") ? operand
          : %(expr $type (op $operator $operand));
      }
    case %(expr ?type (cast ?target (expr ?(Type source) ?payload))): {
      List operand = _rewrite(p, %(expr $source $payload));
      if (source != %("Func") && operand.cadr() == %("Func"))
        return c.convert_expression(operand, target);
      return %(expr $type (cast $target $operand));
    }
    case %(expr ?(Type type) (ident ?binding)): {
      if (binding == p.original) return _local(c, p.self);
      List captured = _session_value(p, type, binding);
      if (captured) return captured;
    }
  }
  /* A conditional or comma expression can now yield a Func instead of a
     native designator. Let the ordinary resolver infer that result. */
  match (node) case %(expr ?(Type type) ?content)
    if (type.is_function() ||
        (type.is_pointer() && type.dereference().is_function())): {
      List rewritten = _rewrite(p, content);
      return rewritten == content ? node
        : c.resolve_expression(%(expr () $rewritten), NULL);
    }
  List child;
  $ast.rewrite_children(node, child, _rewrite(p, child));
}

/* Global references become context reads. Resolve the newly introduced
   local through ordinary capture binding at each nested lambda. */
static List _rewrite_lambda(
  PromptFunction &p, Type type, List params, List captures, List body) {
  Compiler c = p.session.compiler;
  captures = _rewrite(p, captures);
  $let(c.lambda_scopes, c.lambda_scopes) {
    c.begin_lambda_captures(NULL, NULL);
    c.sym.push_new_scope();
    defer c.sym.pop_scope();
    body = _rewrite(p, body);
    captures = %(@captures @{c.end_lambda_captures()});
  }
  return captures
    ? %(expr ("Func") (lambda $params (captures @captures) $body))
    : %(expr $type (lambda $params $body));
}

/* This runs inside native emission isolation so adapter and literal setup
   belong to this module, while all captured values belong to the session. */
static List _prepare(Compiler c, PromptFunction &p) {
  p.session.native_type_declarations(p.syntax);
  match (p.syntax)
    case %(function ?spec (!set ?original
      (bind ?binding ((fnmod (params *params)) *mods))) ?body): {
      p.original = binding;
      p.type = %(declare $spec (bindings $original)).type_from_ast();
      p.body = c.sym.introduce("__repl_body");
      List self = c.sym.introduce("__repl_self");
      List context = c.sym.introduce("__repl_context");
      p.self = %(expr ("Func") (ident $self));
      p.context = %(expr (* * void) (ident $context));
      if (params.match(%((param (void) (bind () ()))))) params = NULL;
      List declared = %((param ("Func") (bind $self ())) @params);
      List declarator = %(bind ${p.body} ((fnmod (params @declared)) @mods));
      p.body_type = %(declare $spec (bindings $declarator)).type_from_ast();
      List rewritten, setup;
      {
        c.sym.push_new_scope();
        defer c.sym.pop_scope();
        c.sym.bind_identity(NULL, self, %("Func"));
        setup = c.bind_syntax(
          $!{ void **$context = (void **) Func.context(${p.self}); },
          <block>, NULL);
        rewritten = _rewrite(p, body);
      }
      c.add_early(%(function (static @spec) $declarator
        ${c.prepend_setup(rewritten, %($setup))}));
      List target = %(expr ${p.body_type} (ident ${p.body}));
      List adapter = c.context_func_adapter(p.type, target);
      List signature = c.cache_literal_list(c.func_signature(p.type));
      List factory = c.sym.introduce("__repl_factory");
      List captures = c.sym.introduce("__repl_captures");
      List pointer = %(expr (* void) (ident $captures));
      List made = %(expr ("FuncAdapter") (ident $adapter));
      List size = $!size_t{ ${p.values.len() * sizeof(void *)} };
      return c.bind_syntax($!Unit{
        Func $factory(void *$captures) {
          return Func.new_context($made, $signature, $pointer, $size);
        }
      }, <unit>, NULL);
    }
  return NULL;
}

/** Compiles and instantiates one typed prompt definition without publishing
    its name. Captured objects and functions retain the session's identity. */
Func ReplSession.compile_function(ReplSession session, List syntax) {
  PromptFunction prompt = {
    .session = session, .syntax = syntax, .captures = {}, .values = []};
  defer { prompt.captures.cleanup(); prompt.values.free(); }
  String failure = NULL;
  Map targets = session.compiler.stage_session_function(
    session.declarations,
    %!(Compiler c) using &prompt => _prepare(c, prompt), failure);
  if (!targets) raise %(repl (reason $failure));
  Func factory = targets["__repl_factory"];
  void **captures = Scope.malloc(prompt.values.len() * sizeof(void *));
  defer Scope.free(captures);
  for (int i = 0; i < prompt.values.len(); i++)
    captures[i] = prompt.values[i].pointer();
  FuncArg argument = FuncArg.value(Var.new(<p48>, captures));
  Func function = factory.apply(1, &argument);
  function.move(session.evaluator.storage());
  return function;
}
