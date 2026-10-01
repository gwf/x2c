/*  transform.x -- x2c AST transformation pipeline

    Lowers typed expressions, literals, and control flow into the AST forms
    consumed by C emission.

    One recursive normalizer owns expressions and cleanup; `callables.x`
    lowers the lambdas and `Func` conversions it meets. Newly constructed
    nodes normalize locally; complete functions receive their transfer
    cleanup before emission. The active Compiler reports errors.
*/

#pragma once

/* CPP ignores pragma once in its main input. Define the cycle guard only
   during symbol preprocessing, so generated C keeps its declarations. */
#ifndef X2C_TRANSFORM_SOURCE
#ifdef X2CCPP
#define X2C_TRANSFORM_SOURCE
#endif

$(import "../lib/error-macros.xmacro")
#include "compiler.x"
#pragma private

$(import "../src/ast-rewrite.xmacro")
$(import "../src/adapter-memo.xmacro")
#include "meta.x"
$(import "../src/grammar.xmacro")

#include <stdio.h>

#include "ast.x"
#include "type.x"
#include "parse.x"
#include "expressions.x"
#include "string.x"
#include "symbol.x"
#include "var.x"
#include "list.x"
#include "protocol.x"
#include "regions.x"
#include "callables.x"

/* The runtime types a region's record and frame have. */
static String _frame_type = "ExceptionFrame";
static String _record_type = "X2CCleanup";
static String _handler_type = "ErrorHandler";

/* The walk state for one function body. */
typedef struct Walk {
  Compiler compiler;
  Array regions;
  int break_stop, continue_stop, origin;
  Map labels;
  Type return_type;
} *Walk;

static List _address_of(String spelling, List binding) {
  Type type = %(($spelling));
  return %(expr ${type.reference()} (op & (expr $type (ident $binding))));
}

/* Introduce a name this pass owns. The emitted declaration spells this
   binding, so the record a region pushes and the record its exits leave are
   one name by construction. */
static List _region_binding(Compiler compiler, String role) =>
  compiler.sym.introduce(compiler.fresh_name(role));

/* The runtime unlinks this record and calls its thunk. */
macro open Statement $defer_cleanup_call(Expr $record) {
  x2c_cleanup_leave($record);
}

static List _defer_cleanup(Compiler c, List record) {
  Macro shape = $defer_cleanup_call;
  List call = c.bind_syntax(
    shape(_address_of(_record_type, record)), AST_BLOCK, c.return_type);
  return %(code-value "lowered" (seq $call) ());
}

/* The first label a finalizer defines, or NULL. The statements that leave a
   region run on every path that leaves it, so a label among them would be
   defined once per path. */
static Var _finalizer_label(Var value, int origin, int &at) {
  Array pending = $auto([value]), origins = $auto([origin]);
  while (pending.len()) {
    Var current = pending.take_last();
    int here = origins.take_last();
    if (current is not <list> || current.is_nil()) continue;
    List node = current;
    match (node) {
      case %(function *): continue;
      case %(expr *): continue;
      case %(at ?(int inner) ?wrapped): {
        pending.push(wrapped);
        origins.push(inner);
        continue;
      }
      case %(label ?name *): {
        at = here;
        return name;
      }
    }
    foreach (Var child, node) {
      pending.push(child);
      origins.push(here);
    }
  }
  return NULL;
}

macro open Statement $try_close_handler(Expr $handle) {
  x2c_error_catch_close($handle);
  $handle = NULL;
}

macro open Statement $try_leave_cleanup(Expr $frame,
    Statement $before...) {
  $before...
  x2c_exception_leave($frame);
}

macro open Statement $try_finish_cleanup(Expr $frame,
    Statement $finalizer, Statement $before...) {
  if (x2c_exception_claim($frame)) {
    $before...
    $finalizer
  }
  x2c_exception_leave($frame);
}

/* A catch closes before a claimed finalizer, then the frame leaves. The
   finalizer is already lowered and retains its stage through the template. */
static List _try_cleanup(
  Compiler c, List frame, List handle, List finalizer, int has_clause) {
  Macro close = $try_close_handler;
  Type handler = %(($_handler_type));
  List before = has_clause
    ? %(${close(%(expr $handler (ident $handle)))}) : NULL;
  List address = _address_of(_frame_type, frame);
  List syntax;
  if (finalizer) {
    Macro finish = $try_finish_cleanup;
    syntax = finish(
      address, %(code-value "lowered" (seq $finalizer) ()), before);
  }
  else {
    Macro leave = $try_leave_cleanup;
    syntax = leave(address, before);
  }
  List result = c.bind_syntax(syntax, AST_BLOCK, c.return_type);
  return %(code-value "lowered" $result ());
}

static List _statements(List code) {
  match (code) case %(code-value ? (seq *statements) ?): return statements;
  return code;
}

/* The statements that leave every region down to `stop`, innermost first.
   Each region runs its own statements before the next one out, so an inner
   frame leaves before an outer defer runs. */
static List _unwind(Walk walk, int stop) {
  Array statements = [];
  for (int i = (int) walk.regions.len() - 1; i >= stop; i--)
    foreach (List statement, walk.regions[i].list().car().list())
      statements.push(statement);
  return statements.list_free();
}

/* Wrap a transfer in the cleanup it runs first. A transfer that leaves no
   region keeps its own shape. */
static List _transfer(Walk walk, int stop, List statement) {
  List cleanup = _unwind(walk, stop);
  return cleanup ? source_block_content(%(@cleanup $statement)) : statement;
}

/* The open regions, innermost first. A label's ancestry is this list, and a
   jump may only leave a suffix of it. */
static List _region_path(Walk walk) {
  List path = %();
  foreach (List region, walk.regions) path = cons(region.cadr(), path);
  return path;
}

/* A label reads as a binding, as a wrapped expression, or as the bare name
   a macro wrote. */
static String _label_spelling(Var label) {
  if (label is <string>) return label;
  if (label is not <list>) return NULL;
  List node = label;
  match (node) {
    case $source_identifier_content(%(?binding)):
      return binding_identity_spelling(binding);
    case %(expr ? ?inner): return _label_spelling(inner);
    case $source_content_pattern($grouped, %(?inner)):
      return _label_spelling(inner);
    case %(?(String name)): return name;
  }
  return binding_identity_spelling(node);
}

/* Collect each label's region ancestry before any `goto` is rewritten, so a
   jump backward to a label reads the same ancestry as a jump forward. The
   ancestry is the chain of region nodes enclosing the label, and the rewrite
   compares against the same nodes. */
static void _collect_labels(Walk walk, Var value, List path) {
  if (value is not <list> || value.is_nil()) return;
  List node = value;
  match (node) {
    // A label is a statement, and an expression nests as deeply as it is
    // long, so the walk stops here.
    case %(expr *): return;
    case %(label ?name *rest): {
      String spelling = _label_spelling(name);
      if (spelling) walk.labels[spelling] = path;
      foreach (Var child, rest) _collect_labels(walk, child, path);
      return;
    }
    /* Each region a construct opens has its own identity: a `try` protects
       its body and each catch arm separately, while its guards and its
       finalizer run outside the region and keep the enclosing path. */
    case %(try ?body ?clause ?finalizer *): {
      _collect_labels(walk, body, cons(body, path));
      match (clause)
        case %(catchcases ?records ?handle):
          foreach (List record, records) {
            _collect_labels(walk, record.car(), path);
            List arm = record.cadr();
            _collect_labels(walk, arm, cons(arm, path));
          }
      _collect_labels(walk, finalizer, path);
      return;
    }
    case %(defer ?body *): {
      _collect_labels(walk, body, cons(body, path));
      return;
    }
    case %(localinit ?guard ?body): {
      _collect_labels(walk, guard, path);
      _collect_labels(walk, body, cons(node, path));
      return;
    }
  }
  foreach (Var child, node) _collect_labels(walk, child, path);
}

/* Report at `origin`, and leave the compiler's origin as it was for whatever
   reports next. */
static void _report_at(Walk w, int origin, String message, List note) {
  $let(w.compiler.origin, origin)
    w.compiler.report_error(<emit>, message, NULL, note);
}

/* Reject a jump that would enter a region it did not open, and return the
   depth the jump unwinds to. */
static int _goto_stop(Walk walk, Var label) {
  String name = _label_spelling(label);
  Var stored;
  if (!name || !walk.labels.try_get(name, stored)) {
    _report_at(
      walk, walk.origin, "goto target label is not defined in this function",
      NULL);
    return (int) walk.regions.len();
  }
  List target = stored, source = _region_path(walk);
  int source_depth = source.len(), target_depth = target.len();
  List suffix = source;
  for (int i = source_depth; i > target_depth && suffix; i--)
    suffix = suffix.cdr();
  if (target_depth > source_depth || suffix !== target) {
    _report_at(
      walk, walk.origin,
      "goto cannot enter or cross a protected cleanup region",
      %("jump only within the same region or outward"));
    return (int) walk.regions.len();
  }
  return target_depth;
}

/* C requires automatic state changed after `sigsetjmp` to be volatile once
   `siglongjmp` returns. These are the forms that change their left operand;
   the operand names the object directly, or names a pointer that holds it. */
static Var _changed_operand(Compiler c, List node) {
  match (node) {
    case $source_operator_content(%(?operator ?target *)): {
      if (operator is <symbol> && ast_changes_left_operand(operator))
        return target;
      return NULL;
    }
    case $source_postfix_content(%(? ?target)): return target;
    case %(call ?(String helper)
                (args (expr ? (op & (parens ?target))) *)): {
      if (helper == "x2c_var_update_volatile"
          || helper == "x2c_var_postfix_volatile"
          || helper == "Var_update" || helper == "Var_postfix") return target;
      Type native = c.sym.resolve_numeric_type(target.list().cadr());
      if (native && helper == native.var_numeric_update_helper())
        return target;
      foreach (Var (key, value), c.protocol_helpers)
        match (key)
          case %("protocol-update-helper" *):
            if (value == helper) return target;
    }
  }
  return NULL;
}

static int _automatic_static_input(Compiler c, List binding) {
  Var automatic, stored;
  Map facts = c.semantic_binding_facts();
  if (!facts.try_get(%(automatic $binding), automatic) ||
      !automatic.truth()) return 0;
  if (!facts.try_get(%(type $binding), stored)) return 1;
  Type type = stored;
  return !type.is_static() && !type.is_extern() && !type.is_threaded();
}

/* The operand of sizeof is unevaluated except for VLA dimensions. Inspect
   those dimensions through the same static-input classifier as an ordinary
   initializer, without evaluating calls in a fixed-size operand. */
static int _runtime_sizeof_dimensions(Compiler c, List operand, Map runtime) {
  Array pending = $auto([operand]);
  while (pending.len()) {
    List node = pending.take_last();
    match (node)
      case %(dim ?dimension): {
        if (dimension && c.static_value_is_runtime(dimension, runtime))
          return 1;
        continue;
      }
    foreach (Var child, node)
      if (child is <list>) pending.push(child);
  }
  return 0;
}

static int _runtime_address(
  Compiler c, List node, Map runtime, Array pending, Array modes) {
  match (node) {
    case %(!or (expr ? ?inner)
        ${$source_content_pattern($grouped, %(?inner))}
        ${$source_operator_content(%(. ?inner ?))}): {
      pending.push(inner);
      modes.push(1);
      return 0;
    }
    case $source_identifier_content(%(?binding)):
      return (runtime && binding in runtime) ||
             _automatic_static_input(c, binding);
    case $source_pattern_with($indexed, %(?receiver ?selector),
        %((?receiver (!set ?base (expr ?type ?)))
          (?selector ?index))): {
      pending.push(index);
      modes.push(0);
      pending.push(base);
      modes.push(type.list().type().is_array());
      return 0;
    }
    case $source_operator_content(%((!quote *) ?inner)): {
      pending.push(inner);
      modes.push(0);
      return 0;
    }
  }
  return 1;
}

/* -1 means descend, 0 means this node is handled, 1 means runtime. */
static int _runtime_value(
  Compiler c, List node, Map runtime, Array pending, Array modes) {
  match (node) {
    case %((!or cache call var array map varray vmap initval cons append) *):
      return 1;
    case %(expr ?type ${$source_identifier_content(%(?binding))}): {
      if ((runtime && binding in runtime) ||
          _automatic_static_input(c, binding)) return 1;
      if (%(function $binding) in c.semantic_binding_facts()) return 0;
      Type native = type;
      if (native && !native.is_enum() && !native.is_function() &&
          !native.is_array() &&
          (native.is_pointer() || !native.contains(<const>))) return 1;
      return 0;
    }
    case %(expr ? ${$source_operator_content(%(& ?inner))}): {
      pending.push(inner);
      modes.push(1);
      return 0;
    }
    case %(expr ?type (!set ?content
        ${$source_content_pattern($indexed, %(?receiver ?selector))})): {
      Type native = type;
      if (native.is_array()) {
        pending.push(content);
        modes.push(1);
        return 0;
      }
      if (native.is_pointer() || !native.contains(<const>)) return 1;
      break;
    }
    case %(expr ? ${$source_content_pattern(
        $sizeof_expression, %(?operand))}):
      return _runtime_sizeof_dimensions(c, operand, runtime);
  }
  return -1;
}

/** Reports whether the static initializer `value` has to run at runtime,
    because it calls, allocates, or reads an object other than a function
    name. `runtime` holds the function-local statics already known to run
    that way, or is `NULL` at file scope.
*/
int Compiler.static_value_is_runtime(Compiler c, List value, Map runtime) {
  Array pending = $auto([]), modes = $auto([]);
  pending.push(value);
  modes.push(0);
  while (pending.len()) {
    List node = pending.take_last();
    int address = modes.take_last();
    if (address) {
      if (_runtime_address(c, node, runtime, pending, modes)) return 1;
      continue;
    }
    int result = _runtime_value(c, node, runtime, pending, modes);
    if (result >= 0) {
      if (result) return 1;
      continue;
    }
    foreach (Var child, node)
      if (child is <list>) {
        pending.push(child);
        modes.push(0);
      }
  }
  return 0;
}

static int _runtime_static_declaration(
  Compiler c, List node, Map runtime) {
  int found = 0;
  match (node) {
    case %(at ? ?body): return _runtime_static_declaration(c, body, runtime);
    case %(declare (!set ?type (*)) (bindings *bindings)):
      if (type.list().type().is_static())
        foreach (List binding, bindings)
          match (binding)
            case %(op = (bind ?name ?) ?value):
              if (c.static_value_is_runtime(value, runtime)) {
                runtime[name] = 1;
                found = 1;
              }
  }
  return found;
}

/* A static local whose initializer runs at runtime protects the remainder
   of its block just as a cleanup region does: a jump may not enter past the
   initializer. Keeping the canonical binding makes shadowing and generated
   syntax use the same object reference. */
static List _static_regions(Compiler c, List ast, Map runtime) {
  match (ast) {
    case %((!or function localinit expr declare typedef) *): return ast;
    case $source_block_content(%(*statements)): {
      Array before = [];
      foreach (List statement, statements) {
        if (_runtime_static_declaration(c, statement, runtime)) {
          List rest = statements;
          for (int i = 0; i <= before.len(); i++) rest = rest.cdr();
          List body = _static_regions(c, source_block_content(rest), runtime);
          before.push(%(localinit $statement $body));
          return source_block_content(before.list_free());
        }
        before.push(_static_regions(c, statement, runtime));
      }
      return source_block_content(before.list_free());
    }
  }
  Var child;
  $ast.rewrite_children(ast, child, _static_regions(c, child, runtime));
}

/* Names whose storage a transfer may leave stale: those a `try` body writes,
   and those a `defer` inside one writes through its environment. The flag
   covers a subtree, so a write outside every `try` preserves nothing.
   `holders` gains the pointers the body writes through, whose own locals
   `_collect_aliased` resolves.

   `escaped` gains the locals whose address the body hands to a callee. A
   callee's pointer parameter has no `volatile`, so qualifying the local
   would discard the qualifier at the call. Its address escapes at its
   declaration instead, which keeps its value in memory across a transfer. */
static void _preserved_write(
  Compiler c, List node, Map names, Map holders, Map escaped) {
  Var operand = _changed_operand(c, node);
  if (!operand) {
    match (node) case %(call ? (args *arguments)):
      foreach (Var argument, arguments) {
        String addressed = ast_addressed_identifier(argument);
        if (addressed) escaped[addressed] = 1;
      }
    return;
  }
  String name = ast_direct_identifier(operand);
  if (name) names[name] = 1;
  String holder = ast_indirect_identifier(operand);
  if (holder) holders[holder] = 1;
}

static void _collect_preserved(
  Compiler c, Var value, int in_try, Map names, Map holders, Map escaped) {
  /* A long expression chain nests as deeply as it is long, so the walk keeps
     its pending work off the C stack. */
  Array pending = $auto([value]), flags = $auto([in_try]);
  while (pending.len()) {
    Var current = pending.take_last();
    int inside = flags.take_last();
    if (current is not <list> || current.is_nil()) continue;
    List node = current;
    if (inside) _preserved_write(c, node, names, holders, escaped);
    match (node) {
      case %(function *): continue;
      case %(defer ?body ? ? ? ?written *): {
        if (inside)
          foreach (List binding, written) {
            String captured = binding_identity_spelling(binding);
            if (captured) names[captured] = 1;
          }
        pending.push(body);
        flags.push(inside);
        continue;
      }
      case %(try ?body ?clause ?finalizer *): {
        foreach (Var part, %($body $clause $finalizer)) {
          pending.push(part);
          flags.push(1);
        }
        continue;
      }
    }
    foreach (Var child, node) {
      pending.push(child);
      flags.push(inside);
    }
  }
}

/* Preserve the locals whose address one of `holders` took. A write through
   such a pointer changes the local without naming it, so the local needs the
   qualifier the write itself does not ask for. `pointers` gains the holders
   that resolved, because their pointee type has to carry the qualifier too. */
static void _collect_aliased(
  Var value, Map holders, Map names, Map pointers) {
  Array pending = $auto([value]);
  while (pending.len()) {
    Var current = pending.take_last();
    if (current is not <list> || current.is_nil()) continue;
    List node = current;
    match (node) case %(op = ?target ?source): {
      String addressed = ast_addressed_identifier(source), holder = NULL;
      match (target) case %(bind ?binding ?):
        holder = binding_identity_spelling(binding);
      if (!holder) holder = ast_direct_identifier(target);
      if (addressed && holder && holder in holders) {
        names[addressed] = 1;
        pointers[holder] = 1;
      }
    }
    foreach (Var child, node) pending.push(child);
  }
}

/* Rewrite a construct's body with the transfer barriers it establishes. A
   loop bounds both `break` and `continue`; a switch bounds only `break`,
   because a `continue` inside it still targets the enclosing loop. */
static Var _bounded(Walk walk, Var body, int is_loop) {
  int saved_break = walk.break_stop, saved_continue = walk.continue_stop;
  walk.break_stop = (int) walk.regions.len();
  if (is_loop) walk.continue_stop = (int) walk.regions.len();
  Var result = _rewrite(walk, body);
  walk.break_stop = saved_break;
  walk.continue_stop = saved_continue;
  return result;
}

/* Rewrite a region's body and its handlers with the region open. */
static Var _inside(Walk walk, List cleanup, List marker, Var body) {
  walk.regions.push(%(${_statements(cleanup)} $marker));
  Var result = _rewrite(walk, body);
  walk.regions.take_last();
  return result;
}

/* Qualify one binding that a transfer may leave stale, unless `escaped`
   names it: its address escapes instead. */
static List _preserve_binding(List bind, Map names, Map escaped) {
  match (bind)
    case %(bind ?name ?mods): {
      String spelling = binding_identity_spelling(name);
      if (spelling && spelling in names &&
          !(escaped && spelling in escaped) && !mods.contains(<volatile>))
        return %(bind $name ${cons(<volatile>, mods)});
    }
  return bind;
}

/* Once the runtime holds a local's address, C must assume every later call,
   `sigsetjmp` and the raise included, reads and writes the local. */
macro open Statement $escape_local(Expr $local) {
  x2c_exception_escaped = &$local;
}

/* Escape the address of each of `binds` that `escaped` names. */
static void _escape_declared(
  Compiler c, Array output, List binds, Map escaped) {
  Macro escape = $escape_local;
  foreach (List bind, binds)
    match (bind)
      case %(!or (bind ?name ?) (op = (bind ?name ?) ?)): {
        String spelling = binding_identity_spelling(name);
        if (spelling && spelling in escaped) {
          Type type = c.semantic_binding_facts()[%(type $name)];
          output.push(c.bind_syntax(
            escape(%(expr $type (ident $name))), AST_BLOCK, c.return_type));
        }
      }
}

static int _declares_preserved(List bindings, Map names) {
  foreach (List binding, bindings.cdr())
    match (binding)
      case %(!or (bind ?name ?) (op = (bind ?name ?) ?)): {
        String spelling = binding_identity_spelling(name);
        if (spelling && spelling in names) return 1;
      }
  return 0;
}

/* Static, extern, threaded, and typedef declarations do not have automatic
   storage, so a transfer cannot leave them stale. */
static int _is_automatic(List declaration) {
  Type type = declaration.cadr();
  return !type.is_static() && !type.is_extern() && !type.is_typedef() &&
         !type.is_threaded();
}

/* A pointer that holds the address of a preserved local points at a volatile
   object, so its pointee type must say so or C rejects dropping the
   qualifier. `pointers` names the holders the walk resolved, which covers a
   pointer assigned after its declaration; an initializer that takes the
   address directly says the same thing on its own. */
static int _declares_pointee(List bindings, Map names, Map pointers) {
  foreach (List binding, bindings.cdr()) {
    List declarator = binding;
    match (binding) case %(op = ?bind ?value): {
      String addressed = ast_addressed_identifier(value);
      if (addressed && addressed in names) return 1;
      declarator = bind;
    }
    match (declarator) case %(bind ?name ?): {
      String spelling = binding_identity_spelling(name);
      if (spelling && spelling in pointers) return 1;
    }
  }
  return 0;
}

/* Qualify the declarations and parameters the sets name. C puts a qualifier
   on the whole declaration - on the declarator for the object itself, and on
   the base type for a pointee - so a statement that qualifies any of several
   names splits into one declaration each. A local in `escaped` escapes
   right after its declaration; one declared anywhere else is qualified. */
static List _preserve_block(
  Compiler c, List statements, Map names, Map pointers, Map escaped) {
  Array output = [];
  foreach (Var statement, statements) {
    int origin = 0, Var inner = statement;
    match (inner) case %(at ?(int anchor) ?wrapped): {
      origin = anchor;
      inner = wrapped;
    }
    /* Split before qualifying, so a base-type qualifier one declarator
       needs does not reach the names beside it. */
    match (inner)
      case %(!set ?declaration
             ((!or declare decl) ?type (!set ?bindings (bindings *)))):
        if (_is_automatic(declaration)) {
          List parts = %($declaration);
          if (_declares_preserved(bindings, names) ||
              _declares_pointee(bindings, names, pointers)) {
            Symbol head = declaration.car();
            Array split = [];
            foreach (List binding, bindings.cdr())
              split.push(%($head $type (bindings $binding)));
            parts = split.list_free();
          }
          foreach (List part, parts) {
            List one = _preserve_declaration(part, names, pointers, escaped);
            output.push(origin ? %(at $origin $one) : one);
          }
          _escape_declared(c, output, bindings.cdr(), escaped);
          continue;
        }
    List loop = _escape_loop(c, inner, names, pointers, escaped);
    if (loop) {
      output.push(origin ? %(at $origin $loop) : loop);
      continue;
    }
    output.push(_preserve(c, statement, names, pointers, escaped));
  }
  return source_block_content(output.list_free());
}

/* A `for` that declares a local in `escaped` moves the declaration into a
   block around the loop, so the address escapes once, before the loop. */
static List _escape_loop(
  Compiler c, List loop, Map names, Map pointers, Map escaped) {
  match (loop)
    case %(for (decl ?type (!set ?bindings (bindings *binds))) *rest): {
      Array output = [];
      _escape_declared(c, output, binds, escaped);
      List escapes = output.list_free();
      if (!escapes) return NULL;
      List declaration = _preserve_declaration(
        %(declare $type $bindings), names, pointers, escaped);
      List remaining = _preserve(c, %(for () @rest), names, pointers, escaped);
      return source_block_content(%($declaration @escapes $remaining));
    }
  return NULL;
}

static List _preserve_declaration(
  List declaration, Map names, Map pointers, Map escaped) {
  if (!_is_automatic(declaration)) return declaration;
  Symbol head = declaration.car();
  Type type = declaration.cadr();
  List bindings = declaration.caddr();
  if (_declares_pointee(bindings, names, pointers) &&
      !type.type().flatten_all().contains(<volatile>))
    type = cons(<volatile>, type);
  Array preserved = [];
  foreach (List binding, bindings.cdr())
    match (binding) {
      case %(op = ?bind ?value):
        preserved.push(
          %(op = ${_preserve_binding(bind, names, escaped)} $value));
      case %(bind * ):
        preserved.push(_preserve_binding(binding, names, escaped));
    }
  return %($head $type (bindings @{preserved.list_free()}));
}

static Var _preserve(
  Compiler c, Var value, Map names, Map pointers, Map escaped) {
  if (value is not <list> || value.is_nil()) return value;
  List node = value;
  // Only declarations and parameters carry a qualifier, and neither appears
  // inside an expression.
  match (node) case %(expr *): return value;
  match (node) {
    case %(param ?type ?bind):
      return %(param $type ${_preserve_binding(bind, names, escaped)});
    case $source_block_content(%(*statements)):
      return _preserve_block(c, statements, names, pointers, escaped);
    case %(!set ?declaration ((!or declare decl) ? (bindings *))):
      return _preserve_declaration(declaration, names, pointers, NULL);
  }
  Var child;
  $ast.rewrite_children(
    node, child, _preserve(c, child, names, pointers, escaped));
}

/* A parameter in `escaped` escapes before the function body runs. */
static List _escape_parameters(
  Compiler c, List body, List bindings, Map escaped) {
  Array output = [];
  match (bindings) case %(bind ? ((fnmod (params *parameters)) *)):
    foreach (List parameter, parameters)
      match (parameter) case %(param ? ?bind):
        _escape_declared(c, output, %($bind), escaped);
  List escapes = output.list_free();
  if (escapes)
    match (body) case $source_block_content(%(*statements)):
      return source_block_content(%(@escapes @statements));
  return body;
}

/* Save the returned value before cleanup runs, since cleanup may change the
   state the expression read. */
static List _return_value(Walk walk, List expression, List cleanup) {
  List binding = _region_binding(walk.compiler, "return_value");
  Type type = walk.return_type;
  /* The declarator carries the type's pointer and array modifiers, so the
     saved value declares the way the function's result is spelled. */
  List (base, mods) = type.declaration_parts();
  List declaration = %(declare $base
    (bindings (op = (bind $binding $mods) $expression)));
  List returned = source_return_content(%((expr $type (ident $binding))));
  List statement = source_block_content(%(@cleanup $returned));
  return source_block_content(%($declaration $statement));
}

/* A try region's body or catch arm, lowered inside the region `cleanup`
   leaves. */
static List _try_region(Walk walk, List cleanup, List body) =>
  %(code-value "lowered" ${_inside(walk, cleanup, body, body)} ());

/* --- try -------------------------------------------------------------------
   A try region: its frame, its catch site, its landing and its exits, each
   written by a template below. A clause's facts are
   `(HANDLE STATE (ARM...) PATTERN...)`: the handler the parser introduced,
   the catch site's initial state, the lowered arms, and the patterns of
   the filtered arms, which precede the default arm. */

/* The template names must be bound before builtins registers their slots. */
List builtin_try_catch_site(List frame, List clause);
List builtin_catch_patterns(List patterns, List items);
List builtin_try_landing(List frame, List clause, List cleanup);
List builtin_catch_cases(List selected, List arms);
List builtin_try_cleanup_placement(Var cleanup);

/* A try region pushes its frame and lands on it when something raises. */
macro open Statement $compiler_try(Name $frame, Expr $clause,
    Statement $body, Statement $cleanup) {
  {
    ExceptionFrame $frame;
    $builtin_try_catch_site($frame, $clause)...
    x2c_exception_push(&$frame);
    if (!sigsetjmp($frame.env, 0)) $body
    else {
      x2c_exception_landed(&$frame);
      $builtin_try_landing($frame, $clause, $cleanup)...
    }
    $builtin_try_cleanup_placement($cleanup)...
  }
}

macro open Statement $catch_site(Name $frame, Name $handle, Expr $count,
    Expr $fallback, Expr $state, Expr $patterns...) {
  static MatchCaptureSite arms[$count];
  Var patterns[$count];
  static ErrorCatchSite site = {arms, $fallback, $count, $state, -1};
  if (x2c_error_catch_site_pending(&site)) {
    $builtin_catch_patterns(patterns, $patterns)...
  }
  volatile ErrorHandler $handle =
    x2c_error_catch_site_push(&$frame, &site, patterns);
}

/* One arm's pattern, prepared into its slot. */
macro open Statement $catch_pattern(Expr $patterns, Expr $index,
    Expr $pattern) {
  $patterns[$index] = $pattern;
}

/* A landing that hands a raised error to the arm its handler selected. */
macro open Statement $catch_landing(Name $frame, Name $handle,
    Statement $unhandled, Statement $arms...) {
  if (x2c_exception_is_error_target(&$frame)) {
    int selected = x2c_error_catch_selected($handle);
    x2c_error_catch_detach($handle);
    x2c_exception_mark_handled(&$frame);
    $builtin_catch_cases(selected, $arms)...
  }
  else $unhandled
}

/* One catch arm, chosen by its index. Each arm is its own statement, so a
   `break` or `continue` in it still reaches the enclosing loop, and only
   one test holds because `selected` does not change. */
macro open Statement $catch_case(Expr $selected, Expr $index,
    Statement $arm) {
  if ($selected == $index) $arm
}

/* A landing no catch arm handles: the region's exits run, and control does
   not come back. */
macro open Statement $try_unhandled(Statement $cleanup) {
  { $cleanup __builtin_unreachable(); }
}

/** Returns the catch site `frame` pushes for the clause `clause`
    describes, or nothing for a try without one; the `$compiler_try`
    template calls this in a slot. */
List builtin_try_catch_site(List frame, List clause) {
  Macro site = $catch_site;
  match (clause)
    case %(?handle ?(String state) ?(List arms) *patterns): {
      int count = arms.len(), filtered = patterns.len();
      return site(
        frame, handle, x2c_literal_int(count),
        x2c_literal_int(filtered < count ? filtered : -1),
        %(expr (int) $state), patterns);
    }
  return NULL;
}

/** Returns one `$catch_pattern` for each of `items`, prepared into the
    catch site's `patterns`; `$catch_site` calls this in a slot. */
List builtin_catch_patterns(List patterns, List items) {
  Macro prepare = $catch_pattern;
  Array prepared = [];
  int index = 0;
  foreach (List pattern, items)
    prepared.push(prepare(patterns, x2c_literal_int(index++), pattern));
  return prepared.list_free();
}

/** Returns what runs when `frame` lands: the catch arm the clause's
    handler selected, or `cleanup` and no return; the `$compiler_try`
    template calls this in a slot. */
List builtin_try_landing(List frame, List clause, List cleanup) {
  Macro unhandled = $try_unhandled, landing = $catch_landing;
  List otherwise = unhandled(cleanup);
  match (clause)
    case %(?handle ? ?arms *):
      return landing(frame, handle, otherwise, arms);
  return otherwise;
}

/** Returns one `$catch_case` for each lowered arm of `arms`, numbered in
    order and tested against `selected`; `$catch_landing` calls this in a
    slot. */
List builtin_catch_cases(List selected, List arms) {
  Macro choice = $catch_case;
  Array cases = [];
  int index = 0;
  foreach (List arm, arms)
    cases.push(choice(selected, x2c_literal_int(index++), arm));
  return cases.list_free();
}

/* The facts `$compiler_try` writes a try's catch site and landing from,
   or NULL for a try without catches. Each arm is its own region, which a
   jump from the body may not enter, and leaves `cleanup` on its exits. A
   pattern with a dynamic part is prepared again on each entry. */
static List _catch_clause(
  Walk walk, List handle, List cleanup, List records) {
  if (!records) return NULL;
  String state = "ERROR_CATCH_PENDING";
  Array arms = [], patterns = [];
  foreach (List record, records) {
    List pattern = record.car();
    if (pattern) {
      if (!walk.compiler.match_pattern_is_static(pattern))
        state = "ERROR_CATCH_TRANSIENT";
      patterns.push(pattern);
    }
    arms.push(_try_region(walk, cleanup, record.cadr()));
  }
  return %($handle $state ${arms.list_free()} @{patterns.list_free()});
}

/* Reports a label the finalizer defines: it runs on every path that
   leaves its region, so the label would be defined once for each. */
static void _check_finalizer_label(Walk walk, List finalizer) {
  int labelled_at = walk.origin;
  Var labelled = _finalizer_label(finalizer, walk.origin, labelled_at);
  if (!labelled) return;
  String name = _label_spelling(labelled);
  _report_at(
    walk, labelled_at, "a finally body cannot define a label",
    %("a finalizer runs on every path that leaves its region, so '${
      name ? name : "this label"}' would be defined once for each"));
}

/* Lowers the parsed try `node`: its body, its catch arms, which may be
   NULL, and its finalizer, which may be NULL. */
static List _lower_try(
  Walk walk, List node, List body, List arms, List finalizer) {
  Compiler c = walk.compiler;
  _check_finalizer_label(walk, finalizer);
  List frame = _region_binding(c, "exception_frame");
  List handle = arms ? catch_handle(node) : NULL;
  List cleanup = _try_cleanup(
    c, frame, handle, _rewrite(walk, finalizer), !!arms);
  List lowered = _try_region(walk, cleanup, body);
  Macro shape = $compiler_try;
  return c.bind_syntax(
    shape(
      frame, _catch_clause(walk, handle, cleanup, arms), lowered, cleanup),
    AST_BLOCK, c.return_type);
}

/* --- defer -----------------------------------------------------------------
   Registration and its captured addresses share the body's region scope. */

List builtin_defer_record(
  List record, List callback, List environment, List records);
List builtin_defer_captures(List environment, List records);

macro open Statement $compiler_defer(Name $record, Expr $callback,
    Expr $environment, Expr $records, Statement $body, Statement $cleanup) {
  {
    $builtin_defer_record($record, $callback, $environment, $records)...
    x2c_cleanup_push(&$record);
    $body
    $builtin_try_cleanup_placement($cleanup)...
  }
}

macro open Statement $defer_plain(Name $record, Expr $callback) {
  X2CCleanup $record = {.fn = $callback, .env = 0};
}

macro open Statement $defer_captured(Name $record, Expr $callback,
    Type $type, Expr $records) {
  $type environment = {0};
  $builtin_defer_captures(environment, $records)...
  X2CCleanup $record = {.fn = $callback, .env = &environment};
}

macro open Statement $defer_capture(Expr $environment, Name $field,
    Expr $source) {
  $environment.$field = (const void *)&$source;
}

/** Selects the record shape; captured records keep the environment beside
    the record in the region's scope. */
List builtin_defer_record(
  List record, List callback, List environment, List records) {
  Macro plain = $defer_plain, captured = $defer_captured;
  if (!environment) return plain(record, callback);
  Type type = %(${binding_identity_spelling(environment)});
  return captured(record, callback, type, records);
}

/** Writes captured addresses in the order capture selection established. */
List builtin_defer_captures(List environment, List records) {
  Macro capture = $defer_capture;
  Array assignments = [];
  foreach (List row, records) {
    List source = %(expr ${row.cadr()} (ident ${row.car()}));
    assignments.push(
      capture(environment, binding_identity_spelling(row.caddr()), source));
  }
  return assignments.list_free();
}

/* Lowers a defer: its record is pushed before the body and left on each
   of the body's exits. */
static List _lower_defer(
  Walk walk, List body, List env, List callback, List records) {
  Compiler c = walk.compiler;
  c.needs_exception = 1;
  List record = _region_binding(c, "defer_record");
  List cleanup = _defer_cleanup(c, record);
  List function = %(expr ((func ((* void))) void) (ident $callback));
  Macro shape = $compiler_defer;
  return c.bind_syntax(
    shape(
      record, function, env, records,
      _try_region(walk, cleanup, body), cleanup),
    AST_BLOCK, c.return_type);
}

/* Lowers `inner` with `origin` as the source position of its reports. */
static Var _lower_at(Walk walk, int origin, Var inner) {
  int previous = walk.origin;
  walk.origin = origin;
  Var lowered = _rewrite(walk, inner);
  walk.origin = previous;
  return %(at $origin $lowered);
}

/* Lowers a return of `expression`: only a region that runs something can
   change what the expression read, so a static-local region alone leaves
   the return as it is. */
static List _lower_return(Walk walk, List node, List expression) {
  List cleanup = _unwind(walk, 0);
  return cleanup ? _return_value(walk, expression, cleanup) : node;
}

/* A function-static initializer remains in ancestry for label checks,
   although no exit runs its record. */
static List _rewrite_localinit(Walk walk, List node, List guard, List body) =>
  %(localinit ${_rewrite(walk, guard)} ${_inside(walk, NULL, node, body)});

static List _rewrite_while(Walk walk, List condition, List body) =>
  %(while ${_rewrite(walk, condition)} ${_bounded(walk, body, 1)});

static List _rewrite_do(Walk walk, List body, List condition) =>
  %(do ${_bounded(walk, body, 1)} ${_rewrite(walk, condition)});

static List _rewrite_for(
  Walk walk, List initial, List condition, List increment, List body) =>
  %(for ${_rewrite(walk, initial)} ${_rewrite(walk, condition)}
        ${_rewrite(walk, increment)} ${_bounded(walk, body, 1)});

static List _rewrite_switch(Walk walk, List subject, List body) =>
  %(switch ${_rewrite(walk, subject)} ${_bounded(walk, body, 0)});

/* A match arm's break exits the match; continue reaches the loop. */
static List _rewrite_matchcases(Walk walk, List subject, List records) =>
  %(matchcases ${_rewrite(walk, subject)}
               ${_bounded(walk, records, 0)});

/* Expressions cannot hold transfers or regions and may nest arbitrarily.
   Position wrappers supply report origins. Bound returns carry one expression;
   the source template's declared-type slot is not a matching source form. */
static Var _rewrite(Walk walk, Var value) {
  if (value is not <list> || value.is_nil()) return value;
  List node = value;
  match (node) case %(expr *): return value;
  Macro caught = $caught, tried = $tried;
  Macro while_loop = $while_loop, do_loop = $do_loop;
  Macro switched = $switched;
  match (node) {
    case %(at ?(int origin) ?inner): return _lower_at(walk, origin, inner);
    case %(defer ?body ?env ?callback ?records ?):
      return _lower_defer(walk, body, env, callback, records);
    case caught(?body, ?finalizer, *arms):
      return _lower_try(walk, node, body, arms, finalizer);
    case tried(?body, ?finalizer):
      return _lower_try(walk, node, body, NULL, finalizer);
    case %(localinit ?guard ?body):
      return _rewrite_localinit(walk, node, guard, body);
    case $source_return_content(%()): return _transfer(walk, 0, node);
    case $source_return_content(%((!set ?expression (expr ? ?)))):
      return _lower_return(walk, node, expression);
    case %(break): return _transfer(walk, walk.break_stop, node);
    case %(continue): return _transfer(walk, walk.continue_stop, node);
    case %(goto ?label): return _transfer(walk, _goto_stop(walk, label), node);
    case while_loop(?condition, ?body):
      return _rewrite_while(walk, condition, body);
    case do_loop(?body, ?condition):
      return _rewrite_do(walk, body, condition);
    case $source_pattern($for_loop,
        %(?initial ?condition ?increment ?body)):
      return _rewrite_for(walk, initial, condition, increment, body);
    case switched(?subject, ?body):
      return _rewrite_switch(walk, subject, body);
    case %(matchcases ?subject ?records):
      return _rewrite_matchcases(walk, subject, records);
    case %(function *): return _function(walk.compiler, node);
  }
  Var child;
  $ast.rewrite_children(node, child, _rewrite(walk, child));
}

/* Each function walks on its own: no loop, switch, or region spans a
   function boundary, including a lambda body lifted into a sibling. */
static List _function(Compiler compiler, List node) {
  match (node)
    case %(function ?type ?bindings ?body): {
      List declaration = %(declare $type (bindings $bindings));
      struct Walk state = {
        compiler, [], 0, 0, 0, {},
        cdr(declaration.type_from_ast()).type().declared()
      };
      Walk walk = &state;
      Map runtime = {};
      body = _static_regions(compiler, body, runtime);
      _collect_labels(walk, body, NULL);
      Map preserved = {}, holders = {}, pointers = {}, escaped = {};
      _collect_preserved(compiler, body, 0, preserved, holders, escaped);
      if (holders.len())
        _collect_aliased(body, holders, preserved, pointers);
      List rewritten = _rewrite(walk, body);
      if (preserved.len() || escaped.len()) {
        rewritten = _preserve(
          compiler, rewritten, preserved, pointers, escaped);
        bindings = _preserve(
          compiler, bindings, preserved, pointers, escaped);
        rewritten = _escape_parameters(
          compiler, rewritten, bindings, escaped);
      }
      state.regions.free();
      return %(function $type $bindings $rewritten);
    }
  return node;
}

/* Unit normalization calls this at function completion. Expressions cannot
   contain an unlifted function, so no second unit-tree traversal is needed. */
static List _cleanup_unit(Compiler compiler, List node) {
  match (node) {
    case %(function *): return _function(compiler, node);
    case %(at ?origin ?inner):
      return %(at $origin ${_cleanup_unit(compiler, inner)});
  }
  return node;
}

// type coercion passes

static List _to_var(Compiler compiler, List expr) =>
  compiler.convert_expression(expr, %("Var"));

static List _symbol_expression(Symbol value) =>
  %(expr ("Symbol") "${(unsigned long) value}");

static List _truthy_expression(Compiler compiler, List expr) {
  if (!expr) return expr;
  List resolved = compiler.resolve_protocol_member(expr.cadr(), "truth");
  if (!resolved) return expr;
  (List binding, Type signature) = resolved;
  return %(expr (int) (call (expr $signature (ident $binding)) (args $expr)));
}

// call and binding passes

typedef enum PrintfLength {
  _printf_default,
  _printf_hh,
  _printf_h,
  _printf_l,
  _printf_ll,
  _printf_j,
  _printf_z,
  _printf_t,
  _printf_L
} PrintfLength;

static int _iter_immediate_consumer(String name) =>
  name == "Iter_try_next" || name == "Iter_next" ||
         name == "Iter_list" || name == "Iter_array" ||
         name == "Iter_foldl" || name == "Iter_any" ||
         name == "Iter_all" || name == "Iter_find" ||
         name == "Iter_count" || name == "Iter_sum" ||
         name == "Iter_product" || name == "Iter_min" ||
         name == "Iter_max";

static int _printf_has_var(Compiler compiler, List args, int first_value) {
  int index = 0;
  foreach (List arg, args) {
    if (index++ < first_value) continue;
    if (compiler.sym.is_var_type(arg.cadr())) return 1;
  }
  return 0;
}

static void _printf_error(Compiler compiler, String family, String message) {
  String note = "printf-family call: %s".printf(family);
  compiler.report_error(<xform>, message, NULL, %($note));
}

static int _printf_is_digit(int ch) => ch >= '0' && ch <= '9';

static int _printf_valid_length(PrintfLength length, int conversion) {
  switch (conversion) {
    case 'd': case 'i': case 'o': case 'u': case 'x': case 'X':
      return length != _printf_L;
    case 'f': case 'F': case 'e': case 'E':
    case 'g': case 'G': case 'a': case 'A':
      return length == _printf_default || length == _printf_l ||
             length == _printf_L;
    case 'c': case 's':
      return length == _printf_default || length == _printf_l;
    case 'p': return length == _printf_default;
    case 'n': return length != _printf_L;
    default:  return 0;
  }
}

static Type _printf_integer_type(PrintfLength length, int is_unsigned) {
  switch (length) {
    case _printf_j: case _printf_z: case _printf_t: return NULL;
    case _printf_hh: case _printf_h: return %(int);
    case _printf_l:  return is_unsigned ? %(unsigned long) : %(long);
    case _printf_ll:
      return is_unsigned ? %(unsigned long long) : %(long long);
    default: return is_unsigned ? %(unsigned) : %(int);
  }
}

/* Native arguments retain C calling semantics. */
static void _lower_printf_value(
  Compiler compiler, Array values, int index, String family,
  PrintfLength length, int conversion) {
  List arg = values[index];
  if (!compiler.sym.is_var_type(arg.cadr())) return;

  Type target = NULL;
  if (conversion == 'd' || conversion == 'i')
    target = _printf_integer_type(length, 0);
  else if (conversion == 'o' || conversion == 'u' ||
           conversion == 'x' || conversion == 'X')
    target = _printf_integer_type(length, 1);
  else if (conversion == 'f' || conversion == 'F' ||
           conversion == 'e' || conversion == 'E' ||
           conversion == 'g' || conversion == 'G' ||
           conversion == 'a' || conversion == 'A')
    target = length == _printf_L ? %(long double) : %(double);
  else if (conversion == 'c' && length == _printf_default) target = %(int);
  else if (conversion == 's' && length == _printf_default) {
    values[index] = %(expr ("String") (call "Var_str" (args $arg)));
    return;
  }
  if (target) {
    values[index] = compiler.convert_expression(arg, target);
    return;
  }

  String message =
    "cannot infer a native argument for Var at %%%c"
      .printf(conversion);
  _printf_error(
    compiler, family,
    %"$message; use an explicit converter for this format conversion");
}

static void _lower_printf_star(
  Compiler compiler, Array values, int index, String family) {
  if (index >= values.len())
    _printf_error(compiler, family, "format consumes a missing '*' argument");
  List arg = values[index];
  if (compiler.sym.is_var_type(arg.cadr()))
    values[index] = compiler.convert_expression(arg, %(int));
}

typedef struct PrintfWalk {
  Compiler compiler;
  Array values;
  String format, family;
  int cursor, end, value_index;
} PrintfWalk;

static void _printf_position(PrintfWalk *walk) {
  int probe = walk.cursor;
  while (probe < walk.end && _printf_is_digit(walk.format[probe])) probe++;
  if (probe < walk.end && walk.format[probe] == '$')
    _printf_error(
      walk.compiler, walk.family,
      "positional formats cannot infer Var argument types");
}

static void _printf_width(PrintfWalk *walk) {
  while (walk.cursor < walk.end &&
         (walk.format[walk.cursor] == '-' ||
          walk.format[walk.cursor] == '+' ||
          walk.format[walk.cursor] == ' ' ||
          walk.format[walk.cursor] == '#' ||
          walk.format[walk.cursor] == '0'))
    walk.cursor++;
  if (walk.cursor < walk.end && walk.format[walk.cursor] == '*') {
    walk.cursor++;
    _printf_position(walk);
    _lower_printf_star(
      walk.compiler, walk.values, walk.value_index++, walk.family);
  }
  else while (walk.cursor < walk.end &&
              _printf_is_digit(walk.format[walk.cursor])) walk.cursor++;
}

static void _printf_precision(PrintfWalk *walk) {
  if (walk.cursor >= walk.end || walk.format[walk.cursor] != '.') return;
  walk.cursor++;
  if (walk.cursor < walk.end && walk.format[walk.cursor] == '*') {
    walk.cursor++;
    _printf_position(walk);
    _lower_printf_star(
      walk.compiler, walk.values, walk.value_index++, walk.family);
  }
  else while (walk.cursor < walk.end &&
              _printf_is_digit(walk.format[walk.cursor])) walk.cursor++;
}

static PrintfLength _printf_length(PrintfWalk *walk) {
  PrintfLength length = _printf_default;
  if (walk.cursor + 1 < walk.end && walk.format[walk.cursor] == 'h' &&
      walk.format[walk.cursor + 1] == 'h') {
    length = _printf_hh;
    walk.cursor += 2;
  }
  else if (walk.cursor + 1 < walk.end &&
           walk.format[walk.cursor] == 'l' &&
           walk.format[walk.cursor + 1] == 'l') {
    length = _printf_ll;
    walk.cursor += 2;
  }
  else if (walk.cursor < walk.end) {
    switch (walk.format[walk.cursor]) {
      case 'h': length = _printf_h; walk.cursor++; break;
      case 'l': length = _printf_l; walk.cursor++; break;
      case 'j': length = _printf_j; walk.cursor++; break;
      case 'z': length = _printf_z; walk.cursor++; break;
      case 't': length = _printf_t; walk.cursor++; break;
      case 'L': length = _printf_L; walk.cursor++; break;
    }
  }
  return length;
}

static void _printf_conversion(PrintfWalk *walk) {
  _printf_position(walk);
  _printf_width(walk);
  _printf_precision(walk);
  PrintfLength length = _printf_length(walk);
  if (walk.cursor >= walk.end)
    _printf_error(walk.compiler, walk.family, "incomplete format conversion");
  int conversion = walk.format[walk.cursor++];
  if (!_printf_valid_length(length, conversion)) {
    String message =
      "unsupported or malformed format conversion %%%c".printf(conversion);
    _printf_error(walk.compiler, walk.family, message);
  }
  if (walk.value_index >= walk.values.len()) {
    String message =
      "format conversion %%%c consumes a missing argument".printf(conversion);
    _printf_error(walk.compiler, walk.family, message);
  }
  _lower_printf_value(
    walk.compiler, walk.values, walk.value_index++, walk.family,
    length, conversion);
}

static void _printf_scan(PrintfWalk *walk, int raw) {
  while (walk.cursor < walk.end) {
    if (raw && walk.format[walk.cursor] == '\\') {
      walk.cursor += walk.cursor + 1 < walk.end ? 2 : 1;
      continue;
    }
    if (walk.format[walk.cursor++] != '%') continue;
    if (walk.cursor >= walk.end)
      _printf_error(
        walk.compiler, walk.family, "incomplete format conversion");
    if (walk.format[walk.cursor] == '%') {
      walk.cursor++;
      continue;
    }
    _printf_conversion(walk);
  }
}

// Align static format conversions with variadic arguments and lower only
// Var crossings. The parser understands the standard output grammar far
// enough to preserve native arguments around the safe automatic subset.
static List _lower_printf_vars(Compiler c, List ast) {
  (List callee, List args_node) = ast.cdr();
  const PrintfFn *info = callee.printf_family();
  if (!info) return ast;
  List args = args_node.cdr();
  if (!_printf_has_var(c, args, info.first_arg)) return ast;

  Array values = [];
  foreach (Var arg, args) values.push(arg);
  String family = (String) info.name;
  if (info.fmt_arg >= values.len())
    _printf_error(c, family, "call has no format argument");
  List format_arg = values[info.fmt_arg], int raw = 0;
  String format = c.printf_static_format(format_arg, raw);
  if (!format)
    _printf_error(
      c, family,
      "Var arguments require a single static format literal");

  PrintfWalk walk = {
    .compiler = c, .values = values, .format = format, .family = family,
    .cursor = raw ? 1 : 0,
    .end = raw ? format.len() - 1 : format.len(),
    .value_index = info.first_arg,
  };
  _printf_scan(&walk, raw);

  for (int i = walk.value_index; i < values.len(); i++) {
    List arg = values[i];
    if (c.sym.is_var_type(arg.cadr()))
      _printf_error(
        c, family,
        "Var argument has no corresponding format conversion");
  }
  List newargs = values.list_free();
  return %(call $callee (args @newargs));
}

static List _typed_call(
  Compiler compiler, List callee, List params, List args) {
  String callee_name = NULL;
  match (callee) {
    case %(expr ? ${$source_identifier_content(%(?binding))}):
      callee_name = binding_identity_spelling(binding);
  }
  int list_varargs = callee_name == "List_list_n";
  if (compiler.fn_name && _iter_immediate_consumer(callee_name) && args)
    args = cons(compiler.complete_iter_chain(args.car()), args.cdr());
  Array values = [], int arg_index = 0;
  for (List p = params, a = args; a;
       p = p.cdr(), a = a.cdr(), arg_index++) {
    List param = (p ? p.car().list() : NULL), arg = a.car();
    List expected = param;
    if (list_varargs && arg_index > 0) expected = %("Var");
    if (param && param.car() == <param>) expected = param.type_from_ast();
    arg = compiler.maybe_adapt_func_arg(arg, expected);
    List converted = expected
      ? compiler.convert_expression(arg, expected)
      : compiler.lower_lambda_expr(arg);
    values.push(converted);
  }
  List newargs = values.list_free();
  Macro called = $called;
  return compiler.rebuild_expression(
    NULL, called(callee, newargs)).caddr();
}

static List _call(Compiler compiler, List ast) {
  ast = _lower_printf_vars(compiler, ast);
  match (ast)
    case $source_pattern($called, %(?callee *arguments)):
      match (callee.cadr()) {
        case %((func ?parameters) *):
          return _typed_call(compiler, callee, parameters, arguments);
        case %((!or (!quote *) & ^) (func ?parameters) *):
          return _typed_call(compiler, callee, parameters, arguments);
      }
  return ast;
}

/* A resolved bracket read is a semantic marker, distinct from the parsed
   `$indexed` source form. Keep its one structural projection here. */
static int _resolved_index_parts(
  List expr, List &base, Type &base_type, List &selector) {
  match (expr)
    case %(expr ? (getindex (!set ?matched_base (expr ?type ?))
                            ?matched_selector)): {
      base = matched_base;
      base_type = type;
      selector = matched_selector;
      return 1;
    }
  return 0;
}

// Inject conversions so assignment RHS matches the annotated LHS type.
static List _assignment(
  Compiler compiler, Symbol op, List lhs, List rhs) {
  if (lhs.match(%(expr ? (slice *))))
    compiler.report_error(
      <xform>, "slice expressions are not assignable",
      NULL, %("call the collection's setslice method explicitly"));
  List base, index;
  Type base_type;
  if (_resolved_index_parts(lhs, base, base_type, index)) {
    /* String is immutable and interned, so an in-place bracket write
       would mutate shared storage and leave its cached header hash
       stale. A raw write bypasses that invariant, while generic
       setindex returns a copy that this assignment would discard. */
    if (compiler.sym.is_string_type(base_type)) {
      String note = "String is immutable: use the copy-producing " +
                    "String.withindex, or bind a char * to write a " +
                    "transient String.malloc buffer";
      compiler.report_error(
        <xform>, "String does not support bracket assignment", NULL,
        %($note));
    }
    if (!compiler.resolve_protocol_member(base_type, "setindex"))
      compiler.report_error(
        <xform>, %"type $base_type does not support bracket assignment",
        NULL, %("use an explicit copy-producing method where available"));
    return %(setindex $base $index $rhs);
  }
  rhs = compiler.convert_expression(rhs, lhs.cadr());
  return %(op $op $lhs $rhs);
}

static List _declaration(Compiler compiler, List ast) {
  match (ast) {
    case %((!set ?head (!or declare decl)) ?target
           (bindings *bound_list)): {
      Array values = [], List new_bind = NULL;
      foreach (Ast binding, bound_list) {
        new_bind = binding;
        match (binding)
          case %(op = (bind ?var ?mods) ?rhs): {
            Type target_type = %(declare $target
              (bindings (bind $var $mods))).type_from_ast();
            List native_target = %(expr $target_type (ident $var));
            List converted = compiler.convert_initializer(
              rhs, target_type, native_target);
            new_bind = %(
              op = (bind $var $mods) $converted
            );
            if (target_type.type().is_static())
              match (converted)
                case %(expr ("Func")
                       (ident (!set ?dependency (binding ? ?)))):
                  compiler.static_init_deps[var] = %($dependency);
          }
        values.push(new_bind);
      }
      List new_bindings = values.list_free();
      return %($head $target (bindings @new_bindings));
    }
  }
  return ast;
}

// A `Var` subscript of a native pointer or array reads as an integer.
static List _index(Compiler compiler, List ast) {
  Macro indexed = $indexed;
  match (ast)
    case $source_pattern($indexed, %(?base ?selector)):
      match (selector)
        case %(expr ?type ?)
          if (compiler.sym.is_var_type(type)): {
            List converted = compiler.convert_expression(selector, %(long));
            return compiler.rebuild_expression(
              NULL, indexed(base, converted)).caddr();
          }
  return ast;
}

static List _destructure_source(
  Compiler compiler, List source, Type source_type) {
  // An integer, floating, or enumeration source cannot destructure. Reject
  // it before converting so the report names the construct the user wrote;
  // convert_expression would instead diagnose an integer reaching a
  // pointer.
  if (compiler.sym.resolve_numeric_type(source_type.canonicalize()))
    compiler.report_error(
      <type>, "destructuring requires a List source", NULL,
      %(("source type" $source_type)));
  List converted = compiler.convert_expression(source, %("List"));
  Type converted_type = NULL;
  match (converted)
    case %(expr ?type ?): converted_type = type;
  if (!compiler.sym.is_named_value_type(converted_type, "List"))
    compiler.report_error(
      <type>, "destructuring requires a List source", NULL,
      %(("source type" $source_type)));
  return %(code-value "bound" $converted ());
}

// Read one element from the issued List temporary.
static List _destructure_element(List temporary, int index) {
  String text = %"$index";
  return %(expr ("Var")
           (getindex (expr ("List") (ident $temporary))
                     (literal (int) $text)));
}

macro open Expression $destructure_write(
    Expr $target, Expr $value) => $target = $value;

macro open Statement $destructure_targets(
    Type $type, DeclaratorRow $rows...) {
  $type $rows...;
}

macro open Statement $destructure_typed_target(
    Type $type, DeclaratorRow $row, Expr $value) {
  $type $row = $value;
}

macro open Statement $destructure_sequence(Statement $items...) {
  $items...
}

static List _destructure_expression_statement(
  Compiler compiler, List expression) {
  Macro shape = $expression_statement;
  return compiler.rebuild_statement(shape(expression)).cadr();
}

// Preserve typed targets, including the indirection of mutable lambda
// captures, while constructing their writes in source order.
static List _destructure_assignments(
  Compiler compiler, List targets, List temporary) {
  int index = 0;
  Macro shape = $destructure_write;
  return targets.map(
    %!(List target) using &index => {
      match (target)
        case %(expr ?type ?): {
          List value = _destructure_element(temporary, index++);
          List expression = compiler.rebuild_expression(
            type, shape(target, value));
          return _destructure_expression_statement(compiler, expression);
        }
    });
}

macro open Statement $destructure_statement(Name $temporary, Expr $source,
    Statement $assignments...) {
  {
    List $temporary = $source;
    $assignments...
  }
}

macro open Statement $destructure_declarations(
    Name $temporary, Expr $source, Statement $assignments...) {
  List $temporary = $source;
  $assignments...
}

// A discarded destructuring result retains its own block scope.
static List _destructure_statement(Compiler compiler, List ast) {
  match (ast) {
    case %(stmnt (expr ?
             (dstrasgn (targets *targets)
                       (!set ?source (expr ?source_type ?))))): {
      List temporary = compiler.sym.introduce(
        compiler.fresh_name("destructure"));
      Macro shape = $destructure_statement;
      return compiler.bind_syntax(
        shape(
          temporary, _destructure_source(compiler, source, source_type),
          _destructure_assignments(compiler, targets, temporary)),
        AST_BLOCK, compiler.return_type);
    }
  }
  return ast;
}

// Keep parser-bound targets out of rebinding so their names retain scope and
// emitted identity; bind only the new temporary and unbound writes.
static List _named_destructure(
  Compiler compiler, Type type, List targets, List source,
  Type source_type) {
  List temporary = compiler.sym.introduce(
    compiler.fresh_name("destructure"));
  Array declarations = [], expressions = [];
  foreach (List ident, targets) {
    declarations.push(%(bind $ident ()));
    expressions.push(%(expr $type (ident $ident)));
  }
  Macro target_shape = $destructure_targets;
  List target_decl = compiler.rebuild_statement(
    target_shape(type, declarations.list_free())).cadr();
  List assignments = _destructure_assignments(
    compiler, expressions.list_free(), temporary);
  Macro shape = $destructure_declarations;
  List tail = compiler.bind_syntax(
    shape(
      temporary, _destructure_source(compiler, source, source_type),
      assignments),
    AST_BLOCK, compiler.return_type);
  Macro sequence = $destructure_sequence;
  return compiler.rebuild_statement(
    sequence(cons(target_decl, tail.cdr())));
}

static List _typed_destructure(
  Compiler compiler, List parameters, List source, Type source_type) {
  List temporary = compiler.sym.introduce(
    compiler.fresh_name("destructure"));
  Array declarations = [];
  int index = 0;
  Macro target_shape = $destructure_typed_target;
  foreach (List parameter, parameters) match (parameter) {
    case %(param ?type ?bind): {
      List value = _destructure_element(temporary, index++);
      declarations.push(
        compiler.rebuild_statement(target_shape(type, bind, value)).cadr());
    }
  }
  Macro shape = $destructure_declarations;
  List temp = compiler.bind_syntax(
    shape(temporary, _destructure_source(compiler, source, source_type)),
    AST_BLOCK, compiler.return_type);
  Macro sequence = $destructure_sequence;
  return compiler.rebuild_statement(
    sequence(cons(temp, declarations.list_free())));
}

static List _destructure_declaration(Compiler compiler, List ast) {
  match (ast) {
    case %(dstrdecl ?type (targets *targets)
                    (!set ?source (expr ?source_type ?))):
      return _named_destructure(
        compiler, type, targets, source, source_type);
    case %(dstrdecl (params *parameters)
                    (!set ?source (expr ?source_type ?))):
      return _typed_destructure(
        compiler, parameters, source, source_type);
  }
  return ast;
}

/* Cell rewriting needs declaration sites, so lower destructuring
   with its existing transformation before analyzing a function body. */
static List _lower_lambda_destructuring(Compiler compiler, List ast) {
  if (!ast) return ast;
  match (ast) {
    case %(dstrdecl *):
      return _destructure_declaration(compiler, ast);
  }
  // The recursion below then only descends into subtrees it will rewrite.
  if (!ast_contains_head(ast, <dstrdecl>)) return ast;
  return Ast.rewrite_children(
    ast, %!(List child) => _lower_lambda_destructuring(compiler, child));
}

static List _value_declaration(Type type, List binding, List value) {
  (List base, List mods) = type.declaration_parts();
  return value
    ? %(declare $base (bindings (op = (bind $binding $mods) $value)))
    : %(declare $base (bindings (bind $binding $mods)));
}

/* Keep the source's exact static type and value in one result temporary,
   then convert it to List once for the left-to-right assignments. */
static List _destructure_value(Compiler compiler, List ast) {
  match (ast) {
    case %(dstrasgn (targets *targets)
                    (!set ?source (expr ?type ?))): {
      List result = compiler.sym.introduce(
        compiler.fresh_name("destructure_result"));
      List temporary = compiler.sym.introduce(
        compiler.fresh_name("destructure"));
      List result_expr = %(expr $type (ident $result));
      List converted = _destructure_source(
        compiler, result_expr, type);
      List assignments = _destructure_assignments(
        compiler, targets, temporary);
      Macro shape = macro Statement(
        Type $type, Name $result, Expr $source, Name $temporary,
        Expr $converted) {
        $type $result = $source;
        List $temporary = $converted;
      };
      List bindings = compiler.bind_syntax(
        shape(type, result, %(code-value "bound" $source ()),
          temporary, converted),
        AST_BLOCK, compiler.return_type);
      // x2c has no source spelling for this native statement expression.
      return %(parens (block @{bindings.cdr()} @assignments
                             ${_destructure_expression_statement(
                               compiler, result_expr)}));
    }
  }
  return ast;
}
static List _return(Compiler compiler, List ast) {
  Macro returned = $return_value;
  match (ast)
    case returned(?expression):
      return source_return_content(%(${compiler.convert_expression(
        expression, source_return_type(ast))}));
  return ast;
}

// (match expr ((pattern body) ...))
static List _match_cases(Compiler compiler, List ast) {
  List (expr, cases) = ast.cdr();
  expr = compiler.convert_expression(expr, %("List"));
  Array values = [];
  foreach (List rec, cases) {
    if (rec.car() == <preproc>) values.push(rec);
    else
      values.push(%(${compiler.match_pattern_binders(rec.car(), NULL)} @rec));
  }
  List result = values.list_free();
  return %(matchcases $expr $result);
}

// operator passes

static List _comparison(
  Compiler compiler, List ast, Symbol op, List lhs, List rhs) {
  (Var lhs_tag, Type lhs_type) = lhs;
  (Var rhs_tag, Type rhs_type) = rhs;
  (void) lhs_tag; (void) rhs_tag;
  if (!compiler.sym.is_var_type(lhs_type) &&
      !compiler.sym.is_var_type(rhs_type)) {
    if (op == <===>) return %(op == $lhs $rhs);
    if (op == <!==>) return %(op != $lhs $rhs);
    return ast;
  }
  lhs = compiler.convert_expression(lhs, %("Var"));
  rhs = compiler.convert_expression(rhs, %("Var"));
  switch (op) {
    case <==>:  return %(call "Var_equal" (args $lhs $rhs));
    case <!=>:  return %(expr (int)
                          (op ! (call "Var_equal" (args $lhs $rhs))));
    case <===>: return %(call "Var_same" (args $lhs $rhs));
    case <!==>: return %(expr (int)
                          (op ! (call "Var_same" (args $lhs $rhs))));
  }
  List call = %(call "Var_compare" (args $lhs $rhs));
  List zero = %(expr (int) (literal (int) "0"));
  return %(expr (int) (op $op $call $zero));
}

/* The dynamic binary operators are exactly those with a compound assignment
   spelling; `Var_binary` and `Var_update` accept the same operators. */
static int _dynamic_binary_operator(Symbol op) =>
  op.compound_assignment() != 0;

static int _raw_string_type(Type type) {
  type = type ? type.canonicalize() : NULL;
  return type && type.match(%((!or (dim *) (!quote *)) char));
}

static int _string_operand(Compiler compiler, Type type) =>
  compiler.sym.is_string_type(type)
      || _raw_string_type(type);

// Identify only the built-in helper family. Protocol resolution still
// handles every bracket form.
static Symbol _indexed_builtin_helper(Compiler compiler, Type type) {
  if (compiler.sym.is_array_type(type)) return <array>;
  if (compiler.sym.is_map_type(type)) return <map>;
  return 0;
}

// Helper-backed indexes bypass getindex lowering.
static int _indexed_parts(
  Compiler compiler, List expr, Symbol &owner, List &base, List &selector) {
  Type base_type;
  if (!_resolved_index_parts(expr, base, base_type, selector)) return 0;
  owner = _indexed_builtin_helper(compiler, base_type);
  return 1;
}

static void _convert_indexed_parts(
  Compiler compiler, Symbol owner, List &base, List &selector) {
  if (owner == <array>) {
    base = compiler.convert_expression(base, %("Array"));
    selector = compiler.convert_expression(selector, %(int));
  }
  else {
    base = compiler.convert_expression(base, %("Map"));
    selector = compiler.convert_expression(selector, %("Var"));
  }
}

static int _indexed_rhs_allowed(Compiler compiler, Symbol op, List rhs) {
  Type type = rhs.cadr();
  if (compiler.sym.is_var_type(type)) return 1;
  if (compiler.sym.resolve_numeric_type(type)) return 1;
  return op == <+> && _string_operand(compiler, type);
}

static List _indexed_call_expr(
  Compiler compiler, List resolved, List arguments) {
  (List binding, Type signature) = resolved;
  Macro called = $called;
  List callee = %(expr $signature (ident $binding));
  return compiler.rebuild_expression(
    signature.cdr(), called(callee, arguments));
}

// Preserve x2c source order across C's unspecified call-argument order.
static List _sequenced_protocol_call(
  Compiler compiler, List resolved, List arguments) {
  Type signature = resolved.cadr();
  List parameters = signature.car().list().cadr();
  Array converted = [];
  for (List actual = arguments, expected = parameters;
       actual && expected;
       actual = actual.cdr(), expected = expected.cdr()) {
    List value = compiler.convert_expression(actual.car(), expected.car());
    /* A C macro such as raylib's WHITE expands to an expression x2c has no
       type for, and the sequencing temporary still has to declare one. The
       parameter's type is the type the value is about to be passed as. */
    (Var expr_tag, Type value_type, Var body) = value;
    (void) expr_tag;
    if (!value_type) value = %(expr ${expected.car()} $body);
    converted.push(value);
  }
  Array declarations = [], arguments_out = [];
  foreach (List value, converted) {
    Type type = value.cadr();
    List temporary = compiler.sym.introduce(
      compiler.fresh_name("protocol_arg"));
    declarations.push(_value_declaration(type, temporary, value));
    arguments_out.push(%(expr $type (ident $temporary)));
  }
  converted.free();
  List call = _indexed_call_expr(
    compiler, resolved, arguments_out.list_free());
  return %(parens (block @{declarations.list_free()} (stmnt $call)));
}

/* Compound, prefix and postfix brackets share the same resolved element,
   protocol lookup, and built-in conversion. A missing rhs means postfix. */
static List _indexed_resolution(
  Compiler c, Type base_type, Symbol owner, Symbol op, List rhs) {
  int postfix = !rhs;
  List resolved = c.resolve_protocol_member(
    base_type, postfix ? "postfixindex" : "updateindex");
  if (!resolved) {
    String type = base_type.repr();
    String message = postfix
      ? %"type $type does not support indexed increment or decrement"
      : %"type $type does not support indexed compound assignment";
    c.report_error(<xform>, message, NULL, NULL);
  }
  if (owner && !postfix && !_indexed_rhs_allowed(c, op, rhs)) {
    (Var rhs_tag, Type rhs_type) = rhs;
    (void) rhs_tag;
    String details = %"right type: ${rhs_type.repr()}";
    String message = op == <+>
      ? "indexed += requires a numeric, Var, or String operand"
      : "indexed compound assignment requires a numeric or Var operand";
    c.report_error(<xform>, message, NULL, %($details));
  }
  return resolved;
}

static List _indexed_change(
  Compiler c, List target, Symbol op, List rhs) {
  Symbol owner, List base, selector;
  if (!_indexed_parts(c, target, owner, base, selector)) return NULL;
  int postfix = !rhs;
  (Var base_tag, Type base_type) = base;
  (void) base_tag;
  List resolved = _indexed_resolution(c, base_type, owner, op, rhs);

  List operation = _symbol_expression(op);
  List arguments = postfix
    ? %($base $selector $operation)
    : %($base $selector $operation $rhs);
  if (!owner) return _sequenced_protocol_call(c, resolved, arguments);
  _convert_indexed_parts(c, owner, base, selector);
  String helper = owner == <array>
    ? (postfix ? "Array_postfixindex" : "Array_updateindex")
    : (postfix ? "Map_postfixindex" : "Map_updateindex");
  if (!postfix) rhs = c.convert_expression(rhs, %("Var"));
  arguments = postfix
    ? %($base $selector $operation)
    : %($base $selector $operation $rhs);
  return %(call $helper (args @arguments));
}

static List _dynamic_binary(
  Compiler c, List ast, Symbol op, List lhs, List rhs) {
  (Var lhs_tag, Type lhs_type) = lhs;
  (Var rhs_tag, Type rhs_type) = rhs;
  (void) lhs_tag; (void) rhs_tag;
  int lhs_is_var = c.sym.is_var_type(lhs_type);
  int rhs_is_var = c.sym.is_var_type(rhs_type);
  if (!lhs_is_var && !rhs_is_var) return ast;
  int string_plus = op == <+>
                 && (lhs_is_var || _string_operand(c, lhs_type))
                 && (rhs_is_var || _string_operand(c, rhs_type));
  if (!string_plus &&
      ((!lhs_is_var && !c.sym.resolve_numeric_type(lhs_type)) ||
       (!rhs_is_var && !c.sym.resolve_numeric_type(rhs_type)))) {
    String left_type = lhs_type.repr(), right_type = rhs_type.repr();
    String details =
      %"operator: $op left type: $left_type right type: $right_type";
    c.report_error(
      <xform>, "dynamic numeric operators require numeric operands",
      NULL, %($details));
  }
  lhs = c.convert_expression(lhs, %("Var"));
  rhs = c.convert_expression(rhs, %("Var"));
  return %(call "Var_binary" (args $lhs ${_symbol_expression(op)} $rhs));
}

/* One protocol-member update. `x += y`, `++x`, and `x++` all resolve the
   operator's member on the receiver type, convert the right operand to the
   member's declared parameter, and ask for the update helper. A null `rhs`
   is a postfix update, which reads the receiver before the helper runs.
   The converted operand stays in `*rhs` when no helper exists, so a caller
   continues into the dynamic path with the operand it already built. */
static List _update_call(
  List target, List operator, List value, String helper) {
  Type type = target.cadr();
  List address = %(expr ${type.reference()} (op & (parens $target)));
  return value ? %(call $helper (args $address $operator $value))
               : %(call $helper (args $address $operator));
}

static List _protocol_update(
  Compiler c, Type type, Symbol op, List arg, List &?rhs, Symbol spelled) {
  Symbol member = c.operator_member(op);
  if (!member) return NULL;
  String member_name = member;
  List resolved = c.resolve_protocol_member(type, member_name);
  if (!resolved) return NULL;
  if (rhs) {
    List converted = NULL;
    match (resolved)
      case %(? ((func (? ?parameter *)) ?)):
        converted = c.convert_expression(rhs, parameter);
    if (!converted) return NULL;
    rhs = converted;
  }
  String helper = c.protocol_update_helper(type, member_name, !rhs);
  if (!helper) return NULL;
  List spell = _symbol_expression(spelled);
  if (!rhs) return _update_call(arg, spell, NULL, helper);
  List value = rhs;
  return _update_call(arg, spell, value, helper);
}

static void _dynamic_rhs(
  Compiler c, Symbol op, Type lhs_type, Type rhs_type, int rhs_is_var) {
  if (lhs_type.is_bitfield())
    c.report_error(
      <xform>, "dynamic compound assignment cannot target a bitfield",
      NULL, NULL);
  int rhs_allowed = rhs_is_var || c.sym.resolve_numeric_type(rhs_type) ||
                    (op == <+> && _string_operand(c, rhs_type));
  if (!rhs_allowed) {
    String details = %"right type: ${rhs_type.repr()}";
    c.report_error(
      <xform>,
      op == <+>
        ? "dynamic += requires a numeric, Var, or String operand"
        : "dynamic compound assignment requires a numeric or Var operand",
      NULL, %($details));
  }
}

static String _dynamic_helper(Compiler c, Type lhs_type) {
  Type scalar = c.sym.resolve_numeric_type(lhs_type);
  if (scalar && scalar.is_enum())
    c.report_error(
      <xform>, "dynamic compound assignment cannot target an enum",
      NULL, NULL);
  String helper = scalar ? scalar.var_numeric_update_helper() : NULL;
  if (!helper) {
    String details = %"left type: ${lhs_type.repr()}";
    c.report_error(
      <xform>, "dynamic compound assignment requires a numeric lvalue",
      NULL, %($details));
  }
  return helper;
}

static List _dynamic_compound(
  Compiler c, List ast, Symbol op, List lhs, List rhs) {
  (Var lhs_tag, Type lhs_type) = lhs;
  (Var rhs_tag, Type rhs_type) = rhs;
  (void) lhs_tag; (void) rhs_tag;
  int lhs_is_var = c.sym.is_var_type(lhs_type);
  int rhs_is_var = c.sym.is_var_type(rhs_type);
  if (_indexed_builtin_helper(c, lhs_type)) {
    String type = lhs_type.repr();
    c.report_error(
      <xform>, %"container type $type does not support compound assignment",
      NULL, %("update an indexed element instead"));
  }
  /* Without this rejection a nonmatching String compound falls through to
     native pointer arithmetic on an interned String. Concatenation itself
     lowers through the protocol member below like any adopter, resolved
     against canonical String because Var(String) adoption is exact while
     String typedefs still spell the same lvalue. */
  Type member_type = lhs_type;
  if (c.sym.is_string_type(lhs_type)) {
    if (op != <+> || !_string_operand(c, rhs_type))
      c.report_error(
        <xform>, "String compound assignment supports only String +=",
        NULL, NULL);
    member_type = %("String");
  }
  if (!lhs_is_var) {
    List updated = _protocol_update(c, member_type, op, lhs, rhs, op);
    if (updated) return updated;
    (rhs_tag, rhs_type) = rhs;
  }
  if (!lhs_is_var && !rhs_is_var) return ast;
  _dynamic_rhs(c, op, lhs_type, rhs_type, rhs_is_var);

  String helper = "x2c_var_update_volatile";
  if (!lhs_is_var) helper = _dynamic_helper(c, lhs_type);

  rhs = c.convert_expression(rhs, %("Var"));
  return _update_call(lhs, _symbol_expression(op), rhs, helper);
}

static List _binary_operator(
  Compiler c, List ast, Symbol operator, List lhs, List rhs) {
  Symbol compound = Symbol.compound_operator(operator);
  if (compound) {
    List indexed = _indexed_change(c, lhs, compound, rhs);
    if (indexed) return indexed;
    return _dynamic_compound(c, ast, compound, lhs, rhs);
  }
  switch (operator) {
    case <=>: return _assignment(c, operator, lhs, rhs);
    case <==>:  case <!=>:  case <===>: case <!==>:
    case <"<">: case <"<=">: case <">">:  case <">=">:
      return _comparison(c, ast, operator, lhs, rhs);
  }
  if (_dynamic_binary_operator(operator))
    return _dynamic_binary(c, ast, operator, lhs, rhs);
  return ast;
}

static List _unary_change(
  Compiler c, List ast, Symbol operator, List argument, Type type) {
  Symbol binary = operator == <++> ? <+> : <->;
  List one = %(expr (int) (literal (int) "1"));
  List indexed = _indexed_change(c, argument, binary, one);
  if (indexed) return indexed;
  if (!c.sym.is_var_type(type)) {
    List updated = _protocol_update(
      c, type, binary, argument, one, binary);
    if (updated) return updated;
  }
  if (c.sym.is_var_type(type)) {
    one = c.convert_expression(one, %("Var"));
    return _update_call(
      argument, _symbol_expression(binary), one,
      "x2c_var_update_volatile");
  }
  return ast;
}

static List _operator(Compiler c, List ast) {
  List truthy = _truthy(c, ast);
  if (truthy != ast) return truthy;
  match (ast) {
    case $source_operator_content(%(?operator
             (!set ?lhs (expr ? ?)) (!set ?rhs (expr ? ?)))):
      return _binary_operator(c, ast, operator, lhs, rhs);
    case $source_operator_content(%(
             (!set ?operator (!or + - ~))
             (!set ?argument (expr ?argument_type ?)))): {
      if (c.sym.is_var_type(argument_type))
        c.report_error(
          <xform>, "dynamic unary numeric operators are not supported",
          NULL, %("use Var.binary with an explicit numeric operand"));
      return ast;
    }
    case $source_operator_content(%(
             (!set ?operator (!or ++ --))
             (!set ?argument (expr ?argument_type ?)))):
      return _unary_change(c, ast, operator, argument, argument_type);
  }
  return ast;
}

static List _postfix(Compiler compiler, List ast) {
  match (ast)
    case $source_postfix_content(%(?operator
           (!set ?argument (expr ?argument_type ?)))): {
      Symbol op = operator, List arg = argument;
      Type type = argument_type;
      List indexed = _indexed_change(compiler, arg, op, NULL);
      if (indexed) return indexed;
      if (!compiler.sym.is_var_type(type)) {
        Symbol binary = op == <++> ? <+> : <->;
        List updated =
          _protocol_update(compiler, type, binary, arg, NULL, op);
        if (updated) return updated;
      }
      if (compiler.sym.is_var_type(type)) {
        List address = %(expr (* "Var") (op & (parens $arg)));
        return %(call "x2c_var_postfix_volatile"
                      (args $address ${_symbol_expression(op)}));
      }
      return ast;
    }
  return ast;
}

static List _truthy(Compiler compiler, List ast) {
  Macro if_then = $if_then, if_else = $if_else;
  Macro while_loop = $while_loop, do_loop = $do_loop;
  Macro for_loop = $for_loop;
  match (ast) {
    case if_then(?condition, ?yes):
      return compiler.rebuild_statement(
        if_then(_truthy_expression(compiler, condition), yes)).cadr();
    case if_else(?condition, ?yes, ?no):
      return compiler.rebuild_statement(
        if_else(_truthy_expression(compiler, condition), yes, no)).cadr();
    case while_loop(?condition, ?body):
      return compiler.rebuild_statement(
        while_loop(_truthy_expression(compiler, condition), body)).cadr();
    case do_loop(?body, ?condition):
      return compiler.rebuild_statement(
        do_loop(body, _truthy_expression(compiler, condition))).cadr();
    case for_loop(?init, ?condition, ?increment, ?body):
      return compiler.rebuild_statement(
        for_loop(
          init, _truthy_expression(compiler, condition), increment,
          body)).cadr();
    case $source_operator_content(%(
           (!set ?operator (!or && ||)) ?lhs ?rhs)): {
      List left = _truthy_expression(compiler, lhs);
      List right = _truthy_expression(compiler, rhs);
      return source_operator_content(%($operator $left $right));
    }
    case $source_operator_content(%(? ?condition ?ontrue ?onfalse)):
      return source_operator_content(%(
        ? ${_truthy_expression(compiler, condition)} $ontrue $onfalse));
    case $source_operator_content(%(! ?condition)):
      return source_operator_content(%(
        ! ${_truthy_expression(compiler, condition)}));
  }
  return ast;
}

// collection passes

/* The converted Var values enter the native counted constructors unchanged.
   Empty literals need only allocate their container. */
macro open Expression $var_array(Expr $count, Expr $values...) =>
  Array.update_n(Array.new(), $count, $values...);

macro open Expression $empty_var_array() => Array.new();

macro open Expression $var_map(Expr $count, Expr $entries...) =>
  Map.update_n(Map.new(), $count, $entries...);

macro open Expression $empty_var_map() => Map.new();

/* The containing typed expression already fixes the result type. */
static List _var_literal_content(Compiler compiler, List application) {
  List bound = compiler.bind_syntax(application, AST_EXPRESSION, NULL);
  match (bound) case %(expr ? ?content): return content;
  __builtin_unreachable();
}

static List _var_array_literal(Compiler compiler, List values) {
  if (!values) {
    Macro empty = $empty_var_array;
    return _var_literal_content(compiler, empty());
  }
  Macro shape = $var_array;
  return _var_literal_content(
    compiler, shape(x2c_literal_int(values.len()), values));
}

static List _var_map_literal(Compiler compiler, List entries) {
  if (!entries) {
    Macro empty = $empty_var_map;
    return _var_literal_content(compiler, empty());
  }
  Macro shape = $var_map;
  return _var_literal_content(
    compiler, shape(x2c_literal_int(entries.len() / 2), entries));
}

// Normalize cons nodes so head and tail carry expected runtime types.
static List _cons(Compiler compiler, List ast) {
  List (head, tail) = ast.cdr();
  head = compiler.convert_expression(head, %("Var"));
  tail = compiler.convert_expression(tail, %("List"));
  return %(cons $head $tail);
}

/* A literal element is a `Var`, and an empty brace there is an empty Map. */
static List _literal_element(Compiler c, List element) {
  if (element.match(%(expr ? (composite (commas)))))
    element = %(expr ("Map") (map));
  return c.convert_expression(element, %("Var"));
}

/** Converts an array literal to source-ordered Var arguments for its
    counted constructor. */
List transform_array_literal(Compiler compiler, List ast) {
  Array values = [];
  foreach (List elem, ast.cdr())
    values.push(_literal_element(compiler, elem));
  return _var_array_literal(compiler, values.list_free());
}

/** Converts a map literal to alternating Var key/value arguments for its
    counted constructor. */
List transform_map_literal(Compiler compiler, List ast) {
  List elems = ast.cdr(), Array values = [];
  foreach (List entry, elems) {
    List (key, val) = entry.cdr();
    values.push(_literal_element(compiler, key));
    values.push(_literal_element(compiler, val));
  }
  return _var_map_literal(compiler, values.list_free());
}

static List _append(Compiler compiler, List ast) {
  List (lhs, rhs) = ast.cdr();
  if (compiler.sym.is_var_type(lhs.cadr()))
    lhs = %(expr ("List") (call "Var_list" (args $lhs)));
  else lhs = compiler.convert_expression(lhs, %("List"));
  return %(append $lhs $rhs);
}

// string passes

static List _process_raw_segment(Compiler compiler, List seg) {
  String raw = seg.cadr(), literal = %"\"${raw.escape()}\"";
  List constructor = compiler.sym.reference(%("String_new"), NULL);
  return %(expr ("String") (call
           (expr ((func ((* char))) "String") (ident $constructor))
           (args (expr (* char) (literal (* char) $literal)))));
}

static List _build_cons_list(List list) {
  if (!list) return %(nil);
  List head = list.car(), tail = _build_cons_list(list.cdr());
  return %(cons $head $tail);
}

static List _segment_value(Compiler compiler, List seg) {
  Symbol kind = seg.car();
  switch (kind) {
    case <segraw>: seg = _process_raw_segment(compiler, seg); break;
    case <segvar>:
    case <segexp>: seg = compiler.convert_segment_to_string(seg.cadr()); break;
    case <cache>: seg = %(expr ("String") $seg); break;
  }
  return compiler.convert_expression(seg, %("Var"));
}

static List _join_segments(
  Compiler compiler, List segments, int segment_count) {
  // Keep nested cons expressions below host-C bracket-depth limits.
  if (segment_count <= 128) {
    segments = _build_cons_list(segments);
    return %("String_join(NULL, " (expr ("List") $segments) ")");
  }
  String count = %"${segment_count}U";
  Type signature = NULL;
  List binding = compiler.sym.reference(%("List_list_n"), signature);
  List list = %(expr ("List")
    (call (expr $signature (ident $binding))
          (args (expr (unsigned) (literal (unsigned) $count)) @segments)));
  return %("String_join(NULL, " $list ")");
}

static List _string_segments(Compiler compiler, List ast) {
  /* A lone constant segment is already the whole string. Reuse the parsed
     literal's cache slot instead of joining a one-element List at runtime.
     Macro-generated literals arrive in this shape. Raise details are
     excluded: their cache slots would fill inside _file_init_ constructors,
     where re-entrant string-pool bootstrap can hand back NULL Strings. */
  match (ast) {
    case $source_string_content(
        %((segexp (expr ("String") (literal ("String") ?text))))):
      if (!compiler.runtime_literals)
        return compiler.cache(
          %(string (expr ("String") (literal ("String") $text))));
  }
  Array values = [];
  foreach (List seg, ast.cdr()) values.push(_segment_value(compiler, seg));
  int segment_count = values.len();
  List segments = values.list_free();
  return _join_segments(compiler, segments, segment_count);
}

// Look through the `(at N ...)` anchors a node arrived wrapped in.
// Every block statement carries one so that a transform-phase diagnostic
// can name its line. A pass that dispatches on a statement tag has to see
// the statement, not the anchor.
static List _without_origin(List ast) {
  while (ast) {
    match (ast) {
      case %(at ? ?inner): ast = inner;
      default: return ast;
    }
  }
  return ast;
}

// Put a replacement statement back under the anchors of the statement it
// replaces, so a rewrite does not lose the node's source position.
static List _rewrap_origin(List original, List replacement) {
  match (original)
    case %(at ?origin ?inner):
      return %(at $origin ${_rewrap_origin(inner, replacement)});
  return replacement;
}

// defer passes

static int _defer_needs_landing(List ast) {
  if (!ast) return 0;
  match (ast)
    case %((!or return break continue goto try catchcases
                 match matchcases) *): return 1;
  foreach (Var child, ast)
    if (child is <list> && _defer_needs_landing(child)) return 1;
  return 0;
}

// File-static cleanup thunks cannot name block-local or variably-sized types.
// Keep the existing landing-frame lowering for those uncommon cases.
static int _defer_type_hoistable(Compiler compiler, Type type) {
  if (!type) return 0;
  Type flat = type.flatten_all();
  if (<register> in flat || <dim> in flat) return 0;
  Type base = type.base_type();
  if (!base) return 0;
  Var first = base.car();
  if (first is <string>) return compiler.sym.get(%($first)) != NULL;
  if (first == <struct> || first == <union> || first == <enum>)
    return base.len() == 2 && compiler.sym.get(base) != NULL;
  return 1;
}

static List _defer_direct_binding(Var value) {
  if (value is not <list>) return NULL;
  List ast = value;
  match (ast) {
    case $source_identifier_content(%(?binding)): return binding;
    case %(expr ? ?inner):  return _defer_direct_binding(inner);
    case $source_content_pattern($grouped, %(?inner)):
      return _defer_direct_binding(inner);
    case $source_operator_content(%(. ?inner *)):
      return _defer_direct_binding(inner);
  }
  return NULL;
}

typedef struct DeferCaptures {
  Compiler compiler;
  List declared, written;
  Map captures;
  Array records;
  int unsupported;
} DeferCaptures;

static void _defer_capture_ident(DeferCaptures *state, List binding) {
  Var automatic, existing, stored_type;
  if (!binding || state.declared.contains(binding) ||
      !state.compiler.semantic_binding_facts().try_get(
        %(automatic $binding), automatic) ||
      state.captures.try_get(binding, existing)) return;
  stored_type = state.compiler.semantic_binding_facts()[%(type $binding)];
  if (!_defer_type_hoistable(state.compiler, stored_type)) {
    state.unsupported = 1;
    return;
  }
  String field_name = state.compiler.fresh_name("defer_capture");
  List field = state.compiler.sym.introduce(field_name);
  state.captures[binding] = field;
  state.records.push(%($binding $stored_type $field));
}

static void _defer_collect_captures(DeferCaptures *state, List ast) {
  if (!ast || state.unsupported) return;
  match (ast)
    case %(bind ?bound *): {
      List binding = bound, known = state.declared;
      if (!known.contains(binding)) state.declared = cons(binding, known);
    }
  match (ast)
    case %(expr ? ${$source_identifier_content(%(?bound))}): {
      _defer_capture_ident(state, bound);
      return;
    }
  List modified = NULL;
  match (ast) {
    case $source_operator_content(%(?operator ?target *)):
      if (operator is <symbol> && ast_changes_left_operand(operator))
        modified = _defer_direct_binding(target);
    case $source_postfix_content(%(? ?target)):
      modified = _defer_direct_binding(target);
  }
  foreach (Var child, ast)
    if (child is <list>)
      _defer_collect_captures(state, child);
  Var field;
  List changed = state.written;
  if (modified && state.captures.try_get(modified, field) &&
      !changed.contains(modified))
    state.written = cons(modified, changed);
}

// Replace captured object references with pointer dereferences through the
// thunk environment. Expression types remain the source expression's type.
static List _defer_rewrite_captures(
  List ast, Map captures, List written, String env_name) {
  if (!ast) return ast;
  match (ast)
    case %(expr ?captured_type
        ${$source_identifier_content(%(?bound))}): {
      List binding = bound;
      Var field_var;
      if (captures.try_get(binding, field_var)) {
        String field_name = binding_identity_spelling(field_var);
        Type type = captured_type, target = type;
        if (binding in written &&
            !type.flatten_all().contains(<volatile>))
          target = cons(<volatile>, type);
        Type pointer = cons(<*>, target);
        String reference = %"$env_name->$field_name";
        List source = %(expr (* const void) $reference);
        List cast = %(expr $pointer (cast $pointer $source));
        List dereference = %(expr $type (op * $cast));
        return %(expr $type (parens $dereference));
      }
      return ast;
    }
  List child;
  $ast.rewrite_children(ast, child,
    _defer_rewrite_captures(child, captures, written, env_name));
}

/* The body is already lowered; these templates supply its generated entry
   and the captured variant's environment pointer. */
macro open Unit $defer_callback(Name $callback, Name $opaque,
    Statement $body) {
  static void $callback(void *$opaque) { $body }
}

macro open Unit $defer_captured_callback(Type $type, Name $callback,
    Name $opaque, Name $local, Statement $body) {
  static void $callback(void *$opaque) {
    $type *$local = ($type *)$opaque;
    $body
  }
}

/* Bind the generated type so its fields are visible to the record template.
   Field rows remain canonical syntax: separately binding a Field template
   loses its member type before the enclosing typedef is bound. */
static List _defer_environment_unit(
  Compiler c, List env_binding, List records) {
  Array fields = [];
  foreach (List record, records) {
    List field = record.caddr();
    fields.push(%(declare (const void) (bindings (bind $field (*)))));
  }
  return c.capture_environment(env_binding, fields.list_free());
}

/* Preserve the lowered finalizer while binding the new function entry. */
static List _defer_callback_unit(
  Compiler c, List callback, List opaque, List env_binding,
  List env_local, List rewritten) {
  List body = %(code-value "lowered" (seq $rewritten) ());
  if (env_binding) {
    Type env_type = %(${binding_identity_spelling(env_binding)});
    Macro captured = $defer_captured_callback;
    return c.bind_syntax(
      captured(env_type, callback, opaque, env_local, body),
      AST_UNIT, NULL);
  }
  Macro plain = $defer_callback;
  return c.bind_syntax(plain(callback, opaque, body), AST_UNIT, NULL);
}

static List _lower_callable_defer(
  Compiler c, List body, List finalizer) {
  DeferCaptures state = {
    .compiler = c, .declared = %(), .written = %(),
    .captures = {}, .records = [], .unsupported = 0,
  };
  _defer_collect_captures(&state, finalizer);
  if (state.unsupported) {
    state.records.free();
    return %(try $body () $finalizer);
  }

  List env_binding = NULL, env_local = NULL, String env_name = NULL;
  List record_list = state.records.list_free();
  if (record_list) {
    env_name = c.fresh_name("defer_env");
    env_binding = c.sym.introduce(env_name);
    env_local = c.sym.introduce(c.fresh_name("defer_data"));
    c.add_early(_defer_environment_unit(c, env_binding, record_list));
  }

  List opaque = c.sym.introduce(c.fresh_name("defer_opaque"));
  List callback = c.sym.introduce(c.fresh_name("defer_cleanup"));
  String env_local_name = env_local
                        ? binding_identity_spelling(env_local) : NULL;
  List rewritten = env_local_name
                 ? _defer_rewrite_captures(
                   finalizer, state.captures, state.written, env_local_name)
                 : finalizer;
  c.add_early(
    _defer_callback_unit(
      c, callback, opaque, env_binding, env_local, rewritten));
  if (c.fn_name)
    c.semantic_binding_facts()[%(defer-ownr $callback)] =
      c.fn_name;

  return %(defer $body $env_binding $callback $record_list ${state.written});
}

// Choose the callable chain for ordinary cleanup statements and retain the
// landing-frame path for lexical transfers or unsupported capture types.
static List _lower_defer_region(
  Compiler compiler, List body, List finalizer) {
  if (compiler.source_map && compiler.origin)
    finalizer = %(at ${compiler.origin} $finalizer);
  if (_defer_needs_landing(finalizer))
    return %(try $body () $finalizer);
  return _lower_callable_defer(compiler, body, finalizer);
}

static List _rewrite_defer_list(Compiler compiler, List stmts) {
  if (!stmts) return stmts;
  int has_defer = 0;
  Macro deferred = $deferred;
  foreach (List statement, stmts) {
    List head = _without_origin(statement);
    match (head) case deferred(?finalizer): has_defer = 1;
    if (has_defer) break;
  }
  if (!has_defer) return stmts;
  Array suffixes = $auto([]);
  for (List suffix = stmts; suffix; suffix = suffix.cdr())
    suffixes.push(suffix);
  List result = stmts;
  int tail_changed = 0;
  for (int i = (int) suffixes.len() - 1; i >= 0; i--) {
    List suffix = suffixes[i];
    List anchored = suffix.car();
    List tail = tail_changed ? result : suffix.cdr();
    List head = _without_origin(anchored);
    match (head) case deferred(?final_stmt): {
      List body = source_block_content(tail), finalizer = final_stmt;
      if (compiler.source_map)
        finalizer = _rewrap_origin(anchored, finalizer);
      List region = _lower_defer_region(compiler, body, finalizer);
      result = %( ${_rewrap_origin(anchored, region)} );
      tail_changed = 1;
      continue;
    }
    if (tail_changed) result = cons(anchored, result);
  }
  return result;
}

static int _raise_detail_type_allowed(Compiler compiler, Type type) {
  if (!type) return 0;
  with compiler.sym {
    if (_.is_var_type(type) ||
        _.is_string_type(type) ||
        _.is_named_value_type(type, "List") ||
        _.is_named_value_type(type, "Symbol") ||
        _.is_named_value_type(type, "Atom"))
      return 1;
    return !!_.resolve_numeric_type(type);
  }
}

static Type _raise_nested_invalid_type(Compiler compiler, Var node) {
  if (node is not <list>) return NULL;
  List ast = node;
  match (ast)
    case %(expr ?expr_type ?value): {
      Type type = expr_type;
      if (!_raise_detail_type_allowed(compiler, type)) return type;
      if (compiler.sym.is_var_type(type)) {
        List payload = value;
        match (payload)
          case %(call ?(String callee) ?arguments):
            if (callee.endswith("_var"))
              return _raise_nested_invalid_type(compiler, arguments);
        return NULL;
      }
      if (!compiler.sym.is_named_value_type(type, "List")) return NULL;
      return _raise_nested_invalid_type(compiler, value);
    }
  foreach (Var child, ast) {
    Type invalid = _raise_nested_invalid_type(compiler, child);
    if (invalid) return invalid;
  }
  return NULL;
}

static List _raise(
  Compiler compiler, List ast, Var cause, List arguments) {
  Array values = [], int index = 0;
  List code = compiler.convert_expression(cause, %("Symbol"));
  int changed = code != cause;
  foreach (List value, arguments) {
    Type invalid = NULL;
    if (index & 1) value = compiler.promote_string_literal(value);
    if (index & 1)
      match (value)
        case %(expr ?value_type ?content): {
          Type type = value_type;
          if (!_raise_detail_type_allowed(compiler, type)) invalid = type;
          else if (compiler.sym.is_named_value_type(type, "List"))
            invalid = _raise_nested_invalid_type(compiler, content);
        }
    if (invalid) {
      String message = %"raise detail type ${invalid.repr()} is not immutable";
      List location = compiler.origin_location(compiler.origin);
      compiler.diagnostics.report(
        <type>, message, location,
        %("use a numeric value, enum, Symbol, Atom, String, List, or Var"));
      // Null replaces the reported detail, so a later pass never sees it.
      value = %(expr ("Var") (call "Var_null" (args)));
    }
    List converted = compiler.convert_expression(value, %("Var"));
    if (converted != value) changed = 1;
    values.push(converted);
    index++;
  }
  if (!changed) {
    values.free();
    return ast;
  }
  List converted = values.list_free();
  return %(raise $code (args @converted));
}

// Lower bracket reads into helper calls with method-call conversions.
static List _nominal_getindex(Compiler compiler, Type type) {
  if (!type.is_typedef_name()) return NULL;
  if (compiler.sym.is_array_type(type) ||
      compiler.sym.is_map_type(type))
    return NULL;
  match (type)
    case %(?(String nominal)): {
      String source = %"${nominal}_getindex";
      Type signature = compiler.sym.get(%($source));
      match (signature)
        case %((func ($type ?)) ?):
          return %(${compiler.sym.reference(%($source), NULL)}
                   $signature);
    }
  return NULL;
}

static List _cast(Compiler compiler, List ast) {
  match (ast)
    case $source_cast_content(
        %((!set ?declarator (decl *parts))
          (!set ?expression (expr ?source_type ?)))): {
    List declaration = %(declare @parts);
    Type type = declaration.type_from_ast();
    List operand = expression;
    if (operand.match(%(expr ? (composite *)))) {
      Type native = type;
      match (declaration)
        case %(declare ?base (bindings (bind ? ?mods))):
          native = mods.list().append(base);
      return compiler.convert_compound_literal(operand, type, native);
    }
    int source_var = compiler.sym.is_var_type(source_type);
    int target_var = compiler.sym.is_var_type(type);
    int unresolved = 0;
    match (expression)
      case %(expr () ${$source_identifier_content(%(?name))}):
        unresolved = 1;
    int target_func = source_type &&
      compiler.sym.resolve_key(type) === compiler.sym.resolve_key(%("Func"));
    if (type !== %(void) &&
        (source_var || target_func ||
         (target_var && (source_type || unresolved))))
      return compiler.convert_expression(expression, type);
    return %(cast $type $expression);
  }
  match (ast)
    case $source_cast_content(
        %(?target (!set ?value (expr ? (composite *))))):
      return compiler.convert_compound_literal(value, target, target);
  return ast;
}

// transform driver

static List _match_records(Compiler compiler, List records) {
  Array transformed = [];
  foreach (List record, records)
    match (record) {
      case %(preproc ?): transformed.push(record);
      case %(*prefix ?body):
        transformed.push(%(@prefix ${compiler.normalize(body)}));
    }
  return transformed.list_free();
}

/* Only top-level and block sequences absorb `(seq ...)` replacements.
   Children transform left to right, then reverse assembly preserves source
   order while allocating generated splice origins from right to left. */
static Ast _sequence(Compiler compiler, Ast ast) {
  Array transformed = $auto([]);
  foreach (List value, ast) {
    List source = _without_origin(value);
    List lowered = source.match(%(defer ?))
      ? value : compiler.normalize(value);
    if (!compiler.fn_name) lowered = _cleanup_unit(compiler, lowered);
    transformed.push(lowered);
  }
  Ast tail = NULL;
  for (int i = (int) transformed.len() - 1; i >= 0; i--) {
    Ast node = transformed[i];
    List payload = _without_origin(node);
    match (node)
      case %(at ?parent ?):
        match (payload)
          case %(seq *items): {
            Array anchored = [];
            foreach (List item, items) {
              compiler.origins.push(%(generated $parent splice));
              int generated = compiler.origins.len();
              anchored.push(%(at $generated $item));
            }
            tail = anchored.list_free().append(tail);
            continue;
          }
    match (node)
      case %(seq *items): {
        tail = items.append(tail);
        continue;
      }
    tail = cons(node, tail);
  }
  return tail;
}

static Ast _children(Compiler compiler, Ast ast) {
  List child;
  $ast.rewrite_children(ast, child, compiler.normalize(child));
}

/* Normalize synthesized sequences before their containing block absorbs
   pending defer markers. Matches retain their specialized record driver. */
static Ast _finish(Compiler compiler, Ast ast) {
  match (ast) {
    case %(seq *items):
      return %(seq @{_sequence(compiler, items)});
    case %(matchcases ?subject ?records): {
      List new_subject = compiler.normalize(subject);
      List new_records = _match_records(compiler, records);
      return %(matchcases $new_subject $new_records);
    }
    case $source_block_content(%(*body)): {
      List lowered = _sequence(compiler, body);
      List deferred = _rewrite_defer_list(compiler, lowered);
      if (deferred != lowered) lowered = _sequence(compiler, deferred);
      return source_block_content(lowered);
    }
  }
  return _children(compiler, ast);
}

/* A left-leaning operator chain nests one (expr (op ...)) level per source
   term, so child-first transformation would recurse once per term. Walk down
   the spine while each level survives its operator rewrites unchanged,
   transform the deepest term, and rebuild upward. Entered only for chain
   heads, with expression rewrites already applied. */
static List _op_chain_first(List ast) {
  match (ast)
    case %(expr ? ?content):
      match (content)
        case $source_operator_content(%(? ?first *rest)):
          if (first is <list>) {
            List operand = first;
            match (operand)
              case %(expr ? ?inner):
                match (inner)
                  case $source_operator_content(%(*parts)):
                    return operand;
          }
  return NULL;
}

static Ast _op_chain(Compiler compiler, Ast ast) {
  Array levels = $auto([]);
  Array types = $auto([]);
  Ast rebuilt = NULL;
  for (;;) {
    List first = _op_chain_first(ast);
    if (!first) {
      rebuilt = _finish(compiler, ast);
      break;
    }
    Var type = ast.cadr();
    if (type is <list>) type = compiler.normalize(type);
    List opnode = ast.caddr();
    List rewritten = _operator(compiler, opnode);
    if (rewritten != opnode) {
      rebuilt = %(expr $type ${compiler.normalize(rewritten)});
      break;
    }
    types.push(type);
    levels.push(ast);
    ast = compiler.lower_typed_adapter_expr(first);
    ast = compiler.lower_lambda_expr(ast);
  }
  for (int i = (int) levels.len() - 1; i >= 0; i--)
    match (levels[i].caddr())
      case $source_operator_content(%(?operator ? *rest)): {
        Array parts = [];
        if (operator is <list>) parts.push(compiler.normalize(operator));
        else parts.push(operator);
        parts.push(rebuilt);
        foreach (Var operand, rest) {
          if (operand is <list>) parts.push(compiler.normalize(operand));
          else parts.push(operand);
        }
        rebuilt = source_operator_expression(types[i], parts.list_free());
      }
  return rebuilt;
}

/* Callers supply bound, typed canonical nodes, and transform helpers construct
   the normalized shapes consumed by the emitter. A helper rewrites only its
   current node: this dispatcher recurses into returned children, while
   _sequence alone splices `(seq ...)` results into a sequence. */
static Ast _function_node(
  Compiler c, List return_type, List declarator, List binding, List body) {
  String owner = binding_identity_spelling(binding);
  Var stored_owner;
  if (c.semantic_binding_facts().try_get(
    %(defer-ownr $binding), stored_owner))
    owner = stored_owner;
  String previous = c.fn_name;
  int previous_inline = c.inline_header;
  c.fn_name = owner;
  Type function_type = return_type;
  c.inline_header = function_type.is_inline() &&
                    !function_type.is_static();
  List new_return = c.normalize(return_type);
  List new_decl = c.normalize(declarator);
  List prepared_body = _lower_lambda_destructuring(c, body);
  prepared_body = c.prepare_lambda_cells(declarator, prepared_body);
  List new_body = c.normalize(prepared_body);
  List transformed = %(function $new_return $new_decl $new_body);
  c.fn_name = previous;
  c.inline_header = previous_inline;
  return transformed;
}

static Ast _getindex_node(
  Compiler c, List expression, Type type, List index) {
  List resolved = _nominal_getindex(c, type);
  if (!resolved) resolved = c.resolve_protocol_member(type, "getindex");
  if (!resolved)
    c.report_error(
      <xform>, %"type $type does not support bracket indexing", NULL, NULL);
  return c.normalize(
    _indexed_call_expr(c, resolved, %($expression $index)).caddr());
}

static Ast _setindex_node(
  Compiler c, List expression, Type type, List index, List value) {
  List resolved = c.resolve_protocol_member(type, "setindex");
  if (!resolved)
    c.report_error(
      <xform>, %"type $type does not support bracket assignment", NULL, NULL);
  if (!_indexed_builtin_helper(c, type))
    return c.normalize(
      _sequenced_protocol_call(c, resolved, %($expression $index $value)));
  return c.normalize(
    _indexed_call_expr(
      c, resolved, %($expression $index $value)).caddr());
}

static Ast _slice_node(
  Compiler c, List expression, Type type, List start, List stop, List step) {
  String nominal = NULL;
  match (type)
    case %(?(String name)): nominal = name;
  if (!nominal)
    c.report_error(
      <xform>, %"type $type does not support slicing", NULL, NULL);
  String fnname = %"${nominal}_getslice";
  if (!c.sym.get(%($fnname)))
    c.report_error(
      <xform>, %"type $type does not support slicing", NULL, %());
  String none = "-2147483648";
  start = start ? start : %(literal (int) $none);
  stop = stop ? stop : %(literal (int) $none);
  step = step ? step : %(literal (int) "1");
  return c.normalize(%(call "$fnname" (args $expression $start $stop $step)));
}

static Ast _defer_node(Compiler c, Ast ast) {
  match (ast)
    case %(defer ?finalizer):
      return _lower_defer_region(c, source_block_content(%()), finalizer);
  return ast;
}

static Ast _raise_node(Compiler c, Ast ast) {
  // Raise details intern at raise time, never in constructors.
  int old_runtime = c.runtime_literals;
  c.runtime_literals = 1;
  match (ast)
    case %(raise ?cause (args *arguments)):
      ast = _raise(c, ast, cause, arguments);
  ast = _children(c, ast);
  c.runtime_literals = old_runtime;
  return ast;
}

static Ast _block_node(Compiler c, Ast ast) {
  List statements = ast.cdr();
  List body = _rewrite_defer_list(c, statements);
  return body !== statements ? source_block_content(body) : ast;
}

static Ast _step(Compiler c, Ast ast) {
  if (!ast) return NULL;
  match (ast)
    case %(managed-init ?):
      c.report_error(
        <parse>,
        "managed initializer requires a complete block-local initializer",
        NULL, NULL);
  Var head = ast.car();
  if (head is not <symbol>) return _children(c, ast);
  match (ast) {
    case %(at ?origin ?inner): {
      int occurrence = origin;
      List transformed = NULL;
      $let(c.origin, occurrence) {
        transformed = c.normalize(inner);
      }
      if (transformed == inner) return ast;
      c.origins.push(%(generated $occurrence xform));
      int generated = c.origins.len();
      return %(at $generated $transformed);
    }
    case %(function ?return_type
           (!set ?declarator (bind ?binding ?)) ?body):
      return _function_node(c, return_type, declarator, binding, body);
    case %(getindex
           (!set ?expression (expr ?matched_type ?)) ?index):
      return _getindex_node(c, expression, matched_type, index);
    case %(setindex
           (!set ?expression (expr ?matched_type ?)) ?index ?value):
      return _setindex_node(c, expression, matched_type, index, value);
    case %(slice
           (!set ?expression
             (expr (!set ?matched_type (*)) ?))
           ?start ?stop ?step):
      return _slice_node(c, expression, matched_type, start, stop, step);
  }
  Symbol tag = head;
  Ast next = ast;
  switch (tag) {
    case <protocol>: case <adopt>: case <macrodef>: case <literal>:
      return ast;
    case <expr>: {
      Ast expression = c.lower_typed_adapter_expr(ast);
      expression = c.lower_lambda_expr(expression);
      if (_op_chain_first(expression)) return _op_chain(c, expression);
      if (expression != ast) return c.normalize(expression);
      return _finish(c, expression);
    }
    case <array>: case <varray>: next = transform_array_literal(c, ast); break;
    case <map>: case <vmap>: next = transform_map_literal(c, ast); break;
    case <cast>: next = _cast(c, ast); break;
    case <index>: next = _index(c, ast); break;
    case <cons>: next = _cons(c, ast); break;
    case <append>: next = _append(c, ast); break;
    case <var>: next = _to_var(c, ast.cadr()); break;
    case <segments>: next = _string_segments(c, ast); break;
    case <declare>: case <decl>: next = _declaration(c, ast); break;
    case <dstrdecl>: next = _destructure_declaration(c, ast); break;
    case <stmnt>: next = _destructure_statement(c, ast); break;
    case <dstrasgn>: next = _destructure_value(c, ast); break;
    case <match>: next = _match_cases(c, ast); break;
    case <defer>: next = _defer_node(c, ast); break;
    case <block>: next = _block_node(c, ast); break;
    case <return>: next = _return(c, ast); break;
    case <raise>: return _raise_node(c, ast);
    case <if>: case <while>: case <do>: case <for>:
      next = _truthy(c, ast); break;
    case <call>: next = _call(c, ast); break;
    case <op>: next = _operator(c, ast); break;
    case <postfix>: next = _postfix(c, ast); break;
  }
  if (next != ast) return c.normalize(next);
  return _finish(c, ast);
}

/** Normalizes one bound and typed node. Newly constructed syntax is
    normalized where it is produced; children enter the same operation, so
    completed units do not require another unit walk.
*/
Ast Compiler.normalize(Compiler c, Ast ast) {
  return _step(c, ast);
}

/** Lowers a bound and typed top-level AST to the normalized form consumed by
    emission. `compiler` must own the AST's bindings, origins, and conversion
    state. Current-node rewrites finish before child traversal; containing
    blocks absorb cleanup markers produced by declaration rewrites. Early
    declarations are lowered and appended after the input units. The call
    may add generated origins or diagnostics to `compiler`.
*/
List Compiler.transform(Compiler compiler, List ast) {
  /* Regions are read before lowering, while `$scope`, `$auto`, and the
     `defer` beside each region are still the forms the parser produced. */
  compiler.check_regions(ast);
  List newast = _sequence(compiler, ast);
  // Merge and lower synthesized lambda siblings.
  Array generated = [];
  while (compiler.early_decls.len()) {
    List items = compiler.early_decls;
    compiler.early_decls.clear();
    List lowered = _sequence(compiler, items);
    foreach (Var sibling, lowered) generated.push(sibling);
  }
  if (generated.len()) newast = newast.append(generated.list_free());
  return newast;
}

#endif
