/*  cleanup.x -- cleanup regions and the transfers that leave them

    Copyright (c) 2026 Gary William Flake.

    A cleanup region is a `defer` body, a region of a landing form such as
    a `try` body or catch arm, or the rest of a block after a static local
    whose initializer runs at runtime. Normalization turns each `defer`
    statement into a region. When a function is complete, each `try` takes
    the landing form its component answers, and one walk places each
    region's exits on every transfer that leaves it, rejects a jump into a
    region, and keeps the locals a `sigsetjmp` landing reads either
    `volatile` or escaped.
*/

#pragma once
#include "compiler.x"

#include "ast-rewrite.x"
#include "meta.x"
#include "grammar.x"

#include "ast.x"
#include "type.x"
#include "parse.x"
#include "callables.x"

/* The runtime type of a defer region's record. */
static String _record_type = "X2CCleanup";

/* The walk state for one function body: the open regions, the depths a
   `break` and `continue` unwind to, the depth the innermost switch opened
   at, and each label's region ancestry. */
static typedef struct Walk {
  Compiler c;
  Array regions;
  int break_stop, continue_stop, switch_stop, origin;
  Map labels;
} Walk;

/* The locals of one function that a transfer may leave stale: the names to
   qualify `volatile`, the pointers written through and those whose pointee
   needs the qualifier too, and the locals whose address escapes instead. */
static typedef struct Preserve {
  Compiler c;
  Map names, holders, pointers, escaped;
  int expression_landings;
} Preserve;

/* Expressions may nest one level per operator. Visit blocks without
   recursing through the expression spine; each keeps its cleanup owner. */
static Array _expression_blocks(List expression) {
  Array blocks = [];
  List node;
  $ast.walk(expression, node) if (node.car() == <block>) {
    blocks.push(node);
    continue;
  }
  return blocks;
}

/* Rebuild only the ancestors of changed blocks, from the leaves upward.
   Keys are node addresses: structural hashing would revisit the same spine. */
static List _rewrite_expression(List expression, Func rewrite) {
  Array blocks = $auto(_expression_blocks(expression));
  Map changed = $auto({});
  // The worklist visits siblings last first; initializers run in source order.
  while (blocks.len()) {
    List block = blocks.take_last();
    List replacement = rewrite(block);
    if (replacement != block) changed[(void *)block] = replacement;
  }
  return changed.len() ? ast_replace_nodes(expression, changed) : expression;
}

/* Whether a statement expression in `body`, before its regions lower,
   holds a landing form. Only a landing's rows hold source the walk
   lowers, so only they are searched. */
static int _expression_holds_landing(List body) {
  List node;
  $ast.walk(body, node) match (node) {
    case %(expr *): {
      if (ast_contains_head(node, <landing>)) return 1;
      continue;
    }
    case %(landing ? ?rows): {
      foreach (List row, rows)
        match (row) case %((!or outer region) ? ?part):
          if (_expression_holds_landing(part)) return 1;
      continue;
    }
  }
  return 0;
}

// function cleanup

/** Lowers the cleanup regions and transfers of the completed top-level
    `node`; other nodes pass through. Unit normalization calls this at
    function completion. Expressions cannot contain an unlifted function, so
    no second unit-tree traversal is needed.
*/
List Compiler.lower_cleanup(Compiler c, List node) {
  match (node) {
    case %(function *): return _lower_function(c, node);
    case %(at ?origin ?inner):
      return %(at $origin ${c.lower_cleanup(inner)});
  }
  return node;
}

/* Each function walks on its own: no loop, switch, or region spans a
   function boundary, including a lambda body lifted into a sibling. A
   `return` converts to the function's declared result, including one that
   a rule's replacement for a `try` writes. */
static List _lower_function(Compiler c, List node) {
  match (node)
    case %(function ?type ?bindings ?body): {
      List declaration = %(declare $type (bindings $bindings));
      $let(c.return_type, declared_return(declaration))
        return _lowered_function(c, type, bindings, body);
    }
  return node;
}

static List _lowered_function(
  Compiler c, List type, List bindings, List body) {
  Walk w = {.c = c, .regions = [], .labels = {}};
  Map runtime = {};
  body = _static_regions(c, body, runtime);
  _collect_labels(w, body, NULL);
  Preserve p = {
    .c = c, .names = {}, .holders = {}, .pointers = {}, .escaped = {}
  };
  _collect_writes(p, body);
  List rewritten = _rewrite(w, body);
  if (p.names.len() || p.escaped.len()) {
    p.expression_landings = _expression_holds_landing(body);
    rewritten = _preserve_locals(p, rewritten);
    bindings = _preserve_locals(p, bindings);
    rewritten = _escape_parameters(p, rewritten, bindings);
  }
  w.regions.free();
  return %(function $type $bindings $rewritten);
}

// static initializers

/* A static local whose initializer runs at runtime protects the remainder
   of its block just as a cleanup region does: a jump may not enter past the
   initializer. Keeping the canonical binding makes shadowing and generated
   syntax use the same object reference. */
static List _static_regions(Compiler c, List ast, Map runtime) {
  match (ast) {
    case %(expr *):
      return _rewrite_expression(
        ast, %!(List block) => _static_regions(c, block, runtime));
    case %((!or function localinit typedef) *): return ast;
    case %(try *): return _landing_form(c, ast, runtime);
    case %(declare ?type ?bindings):
      return _static_initializers(c, type, bindings, runtime);
    case $source_block_content(%(*statements)): {
      Array before = [];
      for (List rest = statements; rest; rest = rest.cdr()) {
        List statement = rest.car();
        if (_runtime_static_declaration(c, statement, runtime)) {
          List guard = _static_regions(c, statement, runtime);
          List body = _static_regions(c,
            source_block_content(rest.cdr()), runtime);
          before.push(%(localinit $guard $body));
          break;
        }
        before.push(_static_regions(c, statement, runtime));
      }
      return source_block_content(before.list_free());
    }
  }
  Var child;
  $ast.rewrite_children(ast, child, _static_regions(c, child, runtime));
}

/* A `try` takes its statement rule's replacement, which holds its lowered
   parts as they are and lowers only the rest. A `try` that a `defer`
   wrote is not source, so only the shipped rule lowers it. Landing rows
   and ordinary replacements both pass through static-region processing. */
static List _landing_form(Compiler c, List node, Map runtime) {
  int written = 0;
  match (node) case %(try ?body () ?finalizer kernel): {
    node = %(try $body () $finalizer);
    written = 1;
  }
  List form = written
    ? c.rewrite_written(<try>, node, c.return_type)
    : c.rewrite_lowered(
      <node>, <try>, node, AST_STATEMENT, c.return_type, NULL);
  match (form) case %(landing ?code ?rows): {
    Array parts = [];
    foreach (List row, rows)
      match (row) {
        case %((!set ?kind (!or outer region)) ?token ?part):
          parts.push(%($kind $token ${_static_regions(c, part, runtime)}));
        default: parts.push(row);
      }
    return %(landing $code ${parts.list_free()});
  }
  if (!form) return node;
  return _static_regions(c, c.lower_replacement(form, node), runtime);
}

/* The pending initializer and the emitter share one cleanup record. Its
   region ends before the initialized object protects the rest of the block. */
static List _static_initializers(
  Compiler c, Type type, List bindings, Map runtime) {
  Array output = [];
  foreach (List binding, bindings.cdr()) {
    match (binding)
      case %(op = ?declaration ?value): {
        declaration = _static_regions(c, declaration, runtime);
        List initial = _static_regions(c, value, runtime);
        if (type.is_static() && c.static_value_is_runtime(value, runtime)) {
          List record = _region_binding(c, "static_cleanup");
          initial = %(staticinit $record $initial);
        }
        output.push(%(op = $declaration $initial));
        continue;
      }
    output.push(_static_regions(c, binding, runtime));
  }
  return %(declare $type (bindings @{output.list_free()}));
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

/* The pending nodes of one static initializer, each read as a value or as
   an address. `runtime` holds the function-local statics already known to
   run at runtime, or is `NULL` at file scope. */
static typedef struct RuntimeScan {
  Compiler c;
  Map runtime;
  Array pending, modes;
} RuntimeScan;

/** Reports whether the static initializer `value` has to run at runtime,
    because it calls, allocates, or reads an object other than a function
    name. `runtime` holds the function-local statics already known to run
    that way, or is `NULL` at file scope.
*/
int Compiler.static_value_is_runtime(Compiler c, List value, Map runtime) {
  Array pending = $auto([]), modes = $auto([]);
  RuntimeScan s = {
    .c = c, .runtime = runtime, .pending = pending, .modes = modes
  };
  _push(s, value, 0);
  while (pending.len()) {
    List node = pending.take_last();
    int address = modes.take_last();
    int result = address ? _address(s, node) : _value(s, node);
    if (result > 0) return 1;
    if (result < 0)
      foreach (Var child, node) if (child is <list>) _push(s, child, 0);
  }
  return 0;
}

/* Queues `node` to be read as an address or a value; the 0 it returns
   means the caller's node is handled. */
static int _push(RuntimeScan &s, Var node, int address) {
  s.pending.push(node);
  s.modes.push(address);
  return 0;
}

/* -1 means descend, 0 means this node is handled, 1 means runtime. */
static int _value(RuntimeScan &s, List node) {
  match (node) {
    case %((!or cache call var array map varray vmap initval cons append) *):
      return 1;
    case %(expr ?type ${$source_identifier_content(%(?binding))}):
      return _identifier(s, type, binding);
    case %(expr ? ${$source_operator_content(%(& ?inner))}):
      return _push(s, inner, 1);
    case %(expr ?type (!set ?content
        ${$indexed(?receiver, ?selector)})): {
      Type native = type;
      if (native.is_array()) return _push(s, content, 1);
      if (native.is_pointer() || !(<const> in native)) return 1;
      break;
    }
    case %(expr ? ${$sizeof_expression(?operand)}):
      return _sizeof_dimensions(s, operand);
  }
  return -1;
}

static int _identifier(RuntimeScan &s, Type type, List binding) {
  if (_input(s, binding)) return 1;
  if (%(function $binding) in s.c.semantic_binding_facts()) return 0;
  Type native = type;
  return native && !native.is_enum() && !native.is_function() &&
         !native.is_array() &&
         (native.is_pointer() || !(<const> in native));
}

static int _address(RuntimeScan &s, List node) {
  match (node) {
    case %(!or (expr ? ?inner)
        ${$grouped(?inner)}
        ${$source_operator_content(%(. ?inner ?))}):
      return _push(s, inner, 1);
    case $source_identifier_content(%(?binding)): return _input(s, binding);
    case ${$indexed(%(!set ?base (expr ?type ?)), ?index)}: {
      _push(s, index, 0);
      return _push(s, base, type.list().type().is_array());
    }
    case $source_operator_content(%((!quote *) ?inner)):
      return _push(s, inner, 0);
  }
  return 1;
}

/* A runtime static or an automatic object read where the initializer runs. */
static int _input(RuntimeScan &s, List binding) =>
  (s.runtime && binding in s.runtime) ||
  _automatic_static_input(s.c, binding);

/* The operand of sizeof is unevaluated except for VLA dimensions. Inspect
   those dimensions through the same static-input classifier as an ordinary
   initializer, without evaluating calls in a fixed-size operand. */
static int _sizeof_dimensions(RuntimeScan &s, List operand) {
  List node;
  $ast.walk(operand, node) match (node) case %(dim ?dimension): {
    if (dimension && s.c.static_value_is_runtime(dimension, s.runtime))
      return 1;
    continue;
  }
  return 0;
}

static int _automatic_static_input(Compiler c, List binding) {
  Var automatic, stored;
  Map facts = c.semantic_binding_facts();
  if (!facts.try_get(%(automatic $binding), automatic) ||
      !automatic) return 0;
  if (!facts.try_get(%(type $binding), stored)) return 1;
  Type type = stored;
  return !type.is_static() && !type.is_extern() && !type.is_threaded();
}

// region walk

/* Collect each label's region ancestry before any `goto` is rewritten, so a
   jump backward to a label reads the same ancestry as a jump forward. The
   ancestry is the chain of region nodes enclosing the label, and the rewrite
   compares against the same nodes. */
static void _collect_labels(Walk &w, Var value, List path) {
  if (value is not <list> || value.is_nil()) return;
  List node = value;
  match (node) {
    case %(expr *): _collect_blocks(w, node, path);
    case %(label ?name *rest): _collect_label(w, name, rest, path);
    case %(landing ? ?rows): _collect_rows(w, rows, path);
    case %(defer ?body *): _collect_labels(w, body, cons(body, path));
    case %(localinit ?guard ?body):
      _collect_local(w, node, guard, body, path);
    case %(staticinit ? ?initial):
      _collect_labels(w, initial, cons(node, path));
    default: _collect_children(w, node, path);
  }
}

static void _collect_blocks(Walk &w, List node, List path) {
  Array blocks = $auto(_expression_blocks(node));
  foreach (List block, blocks) _collect_labels(w, block, path);
}

static void _collect_label(Walk &w, Var name, List rest, List path) {
  String spelling = _label_spelling(name);
  if (spelling) w.labels[spelling] = path;
  _collect_children(w, rest, path);
}

/* Each region a landing opens has its own identity, such as a `try` body
   and each catch arm, while its outer parts keep the enclosing path. */
static void _collect_rows(Walk &w, List rows, List path) {
  foreach (List row, rows)
    match (row) {
      case %(outer ? ?node): _collect_labels(w, node, path);
      case %(region ? ?node): _collect_labels(w, node, cons(node, path));
    }
}

static void _collect_local(
  Walk &w, List node, Var guard, Var body, List path) {
  _collect_labels(w, guard, path);
  _collect_labels(w, body, cons(node, path));
}

static void _collect_children(Walk &w, List node, List path) {
  foreach (Var child, node) _collect_labels(w, child, path);
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

/* Only a statement expression lets an expression hold transfers or
   regions, and expressions may nest arbitrarily. Position wrappers supply
   report origins. Bound returns carry one expression; the source template's
   declared-type slot is not a matching source form. */
static Var _rewrite(Walk &w, Var value) {
  if (value is not <list> || value.is_nil()) return value;
  List node = value;
  match (node) {
    case %(expr *): return _rewrite_blocks(w, node);
    case %(at ?(int origin) ?inner): return _lower_at(w, origin, inner);
    case %(defer ?body ?env ?callback ?records ?):
      return _lower_defer(w, body, env, callback, records);
    case %(landing ?code ?rows): return _lower_landing(w, code, rows);
    case %(localinit ?guard ?body):
      return _rewrite_localinit(w, node, guard, body);
    case %(staticinit ?record ?initial):
      return _rewrite_staticinit(w, node, record, initial);
    case $source_return_content(%()): return _transfer(w, 0, node);
    case $source_return_content(%((!set ?expression (expr ? ?)))):
      return _lower_return(w, node, expression);
    case %(break): return _transfer(w, w.break_stop, node);
    case %(continue): return _transfer(w, w.continue_stop, node);
    case %(goto ?label): return _transfer(w, _goto_stop(w, label), node);
    case ${$while_loop(?condition, ?body)}:
      return _rewrite_while(w, condition, body);
    case ${$do_loop(?body, ?condition)}:
      return _rewrite_do(w, body, condition);
    case ${$for_loop(?initial, ?condition, ?increment, ?body)}:
      return _rewrite_for(w, initial, condition, increment, body);
    case ${$switched(?subject, ?body)}:
      return _rewrite_switch(w, subject, body);
    case %((!or case default) *): return _case_label(w, node);
    case %(function *): return _lower_function(w.c, node);
    default: return _rewrite_children(w, node);
  }
}

static List _rewrite_blocks(Walk &w, List node) =>
  _rewrite_expression(node, %!(List block) using &w => _rewrite(w, block));

static List _rewrite_children(Walk &w, List node) {
  Var child;
  $ast.rewrite_children(node, child, _rewrite(w, child));
}

/* Lowers `inner` with `origin` as the source position of its reports. */
static Var _lower_at(Walk &w, int origin, Var inner) {
  int previous = w.origin;
  w.origin = origin;
  Var lowered = _rewrite(w, inner);
  w.origin = previous;
  return %(at $origin $lowered);
}

/* Lowers a return of `expression`, after any statement expression in it:
   only a region that runs something can change what the expression read,
   so a static-local region alone leaves the return as it is. */
static List _lower_return(Walk &w, List node, List expression) {
  List value = _rewrite(w, expression);
  if (value != expression) node = source_return_content(%($value));
  List cleanup = _unwind(w, 0);
  return cleanup ? _return_value(w, value, cleanup) : node;
}

/* Save the returned value before cleanup runs, since cleanup may change the
   state the expression read. */
static List _return_value(Walk &w, List expression, List cleanup) {
  List binding = _region_binding(w.c, "return_value");
  Type type = w.c.return_type;
  /* The declarator carries the type's pointer and array modifiers, so the
     saved value declares the way the function's result is spelled. */
  List (base, mods) = type.parts();
  List declaration = %(declare $base
    (bindings (op = (bind $binding $mods) $expression)));
  List returned = source_return_content(%((expr $type (ident $binding))));
  List statement = source_block_content(%(@cleanup $returned));
  return source_block_content(%($declaration $statement));
}

/* A function-static initializer remains in ancestry for label checks,
   although no exit runs its record. */
static List _rewrite_localinit(
  Walk &w, List node, List guard, List body) =>
  %(localinit ${_rewrite(w, guard)} ${_inside(w, NULL, node, body)});

static List _rewrite_staticinit(
  Walk &w, List node, List record, List initial) =>
  %(staticinit $record
    ${_inside(w, _defer_cleanup(w.c, record), node, initial)});

static List _rewrite_while(Walk &w, List condition, List body) =>
  %(while ${_rewrite(w, condition)} ${_bounded(w, body, 1)});

static List _rewrite_do(Walk &w, List body, List condition) =>
  %(do ${_bounded(w, body, 1)} ${_rewrite(w, condition)});

static List _rewrite_for(
  Walk &w, List initial, List condition, List increment, List body) =>
  %(for ${_rewrite(w, initial)} ${_rewrite(w, condition)}
        ${_rewrite(w, increment)} ${_bounded(w, body, 1)});

static List _rewrite_switch(Walk &w, List subject, List body) {
  int saved = w.switch_stop;
  w.switch_stop = (int) w.regions.len();
  List result = %(switch ${_rewrite(w, subject)} ${_bounded(w, body, 0)});
  w.switch_stop = saved;
  return result;
}

/* A case label is a jump target of its switch, so it may not sit inside a
   region with exits opened since the switch began; a `goto` into one is
   rejected the same way. A static initializer's region has no exits, and
   the emitter reports a switch that bypasses it. */
static List _case_label(Walk &w, List label) {
  for (int i = w.switch_stop; i < (int) w.regions.len(); i++)
    if (w.regions[i].list().car()) {
      _report_at(w,
        w.origin, "case label cannot enter a protected cleanup region",
        %("open the region inside the case's own block"));
      break;
    }
  return _rewrite_children(w, label);
}

/* Rewrite a construct's body with the transfer barriers it establishes. A
   loop bounds both `break` and `continue`; a switch bounds only `break`,
   because a `continue` inside it still targets the enclosing loop. */
static Var _bounded(Walk &w, Var body, int is_loop) {
  int saved_break = w.break_stop, saved_continue = w.continue_stop;
  w.break_stop = (int) w.regions.len();
  if (is_loop) w.continue_stop = (int) w.regions.len();
  Var result = _rewrite(w, body);
  w.break_stop = saved_break;
  w.continue_stop = saved_continue;
  return result;
}

/* Rewrite a region's body and its handlers with the region open. */
static Var _inside(Walk &w, List cleanup, List marker, Var body) {
  w.regions.push(%(${_statements(cleanup)} $marker));
  Var result = _rewrite(w, body);
  w.regions.take_last();
  return result;
}

static List _statements(List code) {
  match (code) case %(code-value ? (seq *statements) ?): return statements;
  return code;
}

/* Wrap a transfer in the cleanup it runs first. A transfer that leaves no
   region keeps its own shape. */
static List _transfer(Walk &w, int stop, List statement) {
  List cleanup = _unwind(w, stop);
  return cleanup ? source_block_content(%(@cleanup $statement)) : statement;
}

/* The statements that leave every region down to `stop`, innermost first.
   Each region runs its own statements before the next one out, so an inner
   frame leaves before an outer defer runs. */
static List _unwind(Walk &w, int stop) {
  Array statements = [];
  for (int i = (int) w.regions.len() - 1; i >= stop; i--)
    foreach (List statement, w.regions[i].list().car().list())
      statements.push(statement);
  return statements.list_free();
}

/* Reject a jump that would enter a region it did not open, and return the
   depth the jump unwinds to. */
static int _goto_stop(Walk &w, Var label) {
  String name = _label_spelling(label);
  Var stored;
  if (!name || !w.labels.try_get(name, stored)) {
    _report_at(w,
      w.origin, "goto target label is not defined in this function", NULL);
    return (int) w.regions.len();
  }
  List target = stored, source = _region_path(w);
  int source_depth = source.len(), target_depth = target.len();
  List suffix = source;
  for (int i = source_depth; i > target_depth && suffix; i--)
    suffix = suffix.cdr();
  if (target_depth > source_depth || suffix !== target) {
    _report_at(w,
      w.origin, "goto cannot enter or cross a protected cleanup region",
      %("jump only within the same region or outward"));
    return (int) w.regions.len();
  }
  return target_depth;
}

/* The open regions, innermost first. A label's ancestry is this list, and a
   jump may only leave a suffix of it. */
static List _region_path(Walk &w) {
  List path = %();
  foreach (List region, w.regions) path = cons(region.cadr(), path);
  return path;
}

/* Report at `origin`, and leave the compiler's origin as it was for whatever
   reports next. */
static void _report_at(Walk &w, int origin, String message, List note) {
  $let(w.c.origin, origin)
    w.c.report_error(<emit>, message, NULL, note);
}

/* Introduce a name this pass owns. The emitted declaration spells this
   binding, so the record a region pushes and the record its exits leave are
   one name by construction. */
static List _region_binding(Compiler c, String role) =>
  c.sym.introduce(c.fresh_name(role));

static List _address_of(String spelling, List binding) {
  Type type = %(($spelling));
  return %(expr ${type.reference()} (op & (expr $type (ident $binding))));
}

/* landings

   A construct whose parts control re-enters through `siglongjmp` takes
   the form `(landing CODE ROWS)`. The walk applies its rows in order, and
   each row's TOKEN, a binder in CODE and in the rows after it, is replaced
   by what the row lowered:

   - `(new-name TOKEN ROLE)` introduces a fresh binding for ROLE.
   - `(outer TOKEN NODE)` lowers NODE in the enclosing regions.
   - `(exits TOKEN CODE)` binds CODE as the exits of the regions after it.
     CODE holds lowered parts only, so binding lowers nothing more.
   - `(region TOKEN NODE)` lowers NODE inside a region that runs those exits
     on every transfer out of it, and that no `goto` may enter.

   CODE then binds in place of the construct. The locals that the nodes of
   `outer` and `region` rows write stay valid when control lands. */

static List _lower_landing(Walk &w, Var code, List rows) {
  Compiler c = w.c;
  Map parts = $auto({});
  List exits = NULL;
  foreach (List row, rows)
    match (row) {
      case %(new-name ?token ?(String role)):
        parts[token] = _region_binding(c, role);
      case %(outer ?token ?node):
        parts[token] = %(code-value "lowered" (seq ${_rewrite(w, node)}) ());
      case %(exits ?token ?statements):
        parts[token] = exits =
          %(code-value "lowered" ${_bind_parts(c, statements, parts)} ());
      case %(region ?token ?node): parts[token] = _region(w, exits, node);
    }
  return _bind_parts(c, code, parts);
}

/* A region's body, lowered inside the region `cleanup` leaves. */
static List _region(Walk &w, List cleanup, List body) =>
  %(code-value "lowered" ${_inside(w, cleanup, body, body)} ());

/* Binds `code` with each token `parts` maps replaced. A template's
   definition holds none, so only the values it applies are searched. */
static List _bind_parts(Compiler c, Var code, Map parts) {
  match (code) case %("x2c.template" ?definition ?values): {
    Var replaced = _replaced(values, parts);
    if (replaced != values)
      code = %("x2c.template" $definition $replaced);
    return c.bind_syntax(code, AST_BLOCK, c.return_type);
  }
  return c.bind_syntax(_replaced(code, parts), AST_BLOCK, c.return_type);
}

/* `value` with each token `parts` maps replaced. A List without one is
   returned as it is, so only the cells along a replaced path are new. */
static Var _replaced(Var value, Map parts) {
  Var part;
  if (value.is_binder() && parts.try_get(value, part)) return part;
  if (value is not <list> || value.is_nil()) return value;
  List list = value;
  Var head = _replaced(list.car(), parts), tail = _replaced(list.cdr(), parts);
  return head == list.car() && tail == list.cdr() ? value : cons(head, tail);
}

/* defer regions

   Registration and its captured addresses share the body's region scope. */

/* Lowers a defer: its record is pushed before the body and left on each
   of the body's exits. */
static List _lower_defer(
  Walk &w, List body, List env, List callback, List records) {
  Compiler c = w.c;
  c.needs_exception = 1;
  List record = _region_binding(c, "defer_record");
  List cleanup = _defer_cleanup(c, record);
  return c.bind_syntax(
    $!{ {
      ${builtin_defer_record(record, callback, env, records)}
      x2c_cleanup_push(&$record);
      ${_region(w, cleanup, body)}
      $cleanup
    }
  }, AST_BLOCK, c.return_type);
}

/* The runtime unlinks this record and calls its thunk. */
static List _defer_cleanup(Compiler c, List record) {
  List call = c.bind_syntax(
    $!{ x2c_cleanup_leave(${_address_of(_record_type, record)}); },
    AST_BLOCK, c.return_type);
  return %(code-value "lowered" (seq $call) ());
}

/** Selects the record shape; captured records keep the environment beside
    the record in the region's scope. */
List builtin_defer_record(
  List record, List callback, List environment, List records) {
  if (!environment)
    return $!{ X2CCleanup $record = {.fn = $callback, .env = 0}; };
  Type type = %(${binding_identity_spelling(environment)});
  return $!{
    $type environment = {0};
    @builtin_defer_captures(environment, $records)
    X2CCleanup $record = {.fn = $callback, .env = &environment};
  };
}

/** Writes captured addresses in the order capture selection established. */
List builtin_defer_captures(List environment, List records) {
  Array assignments = [];
  foreach (List row, records) {
    /* The capture's storage type keeps a reference parameter's own
       address; the bare binding would read through the reference. */
    List captured = $!(${row.cadr()}){ ${row.car()} };
    String field = binding_identity_spelling(row.caddr());
    assignments.push($!{ $environment.$field = (const void *)&$captured; });
  }
  return assignments.list_free();
}

// volatile locals

/* Names whose storage a transfer may leave stale: those the parts of a
   landing form write, such as a `try` body, and those a `defer` inside one
   writes through its environment. The flag covers a subtree, so a write
   outside every landing preserves nothing. A long expression chain nests
   as deeply as it is long, so the walk keeps its pending work off the C
   stack. */
static void _collect_writes(Preserve &p, List body) {
  Array pending = $auto([body]), flags = $auto([0]);
  while (pending.len()) {
    Var current = pending.take_last();
    int inside = flags.take_last();
    if (current is not <list> || current.is_nil()) continue;
    List node = current;
    if (inside) _write(p, node);
    match (node) {
      case %(function *): continue;
      case %(defer ?body ? ? ? ?written *): {
        if (inside)
          foreach (List binding, written) {
            String captured = binding_identity_spelling(binding);
            if (captured) p.names[captured] = 1;
          }
        pending.push(body);
        flags.push(inside);
        continue;
      }
      case %(landing ? ?rows): {
        foreach (List row, rows)
          match (row) case %((!or outer region) ? ?part): {
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
  if (p.holders.len()) _aliased(p, body);
}

/* `holders` gains the pointers the body writes through, whose own locals
   `_aliased` resolves. `escaped` gains the locals whose address the body
   hands to a callee. A callee's pointer parameter has no `volatile`, so
   qualifying the local would discard the qualifier at the call. Its
   address escapes at its declaration instead, which keeps its value in
   memory across a transfer. */
static void _write(Preserve &p, List node) {
  Var operand = _changed_operand(p.c, node);
  if (!operand) {
    match (node) case %(call ? (args *arguments)):
      foreach (Var argument, arguments) {
        String addressed = ast_addressed_identifier(argument);
        if (addressed) p.escaped[addressed] = 1;
      }
    return;
  }
  String name = ast_direct_identifier(operand);
  if (name) p.names[name] = 1;
  String holder = ast_indirect_identifier(operand);
  if (holder) p.holders[holder] = 1;
}

/* C requires automatic state changed after `sigsetjmp` to be volatile once
   `siglongjmp` returns. These are the source writes and the lowered update
   helpers; the operand names the object directly, or names a pointer that
   holds it. */
static Var _changed_operand(Compiler c, List node) {
  List written = Ast.written_operand(node);
  if (written) return written;
  match (node) {
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

/* Preserve the locals whose address one of `holders` took. A write through
   such a pointer changes the local without naming it, so the local needs the
   qualifier the write itself does not ask for. `pointers` gains the holders
   that resolved, because their pointee type has to carry the qualifier too. */
static void _aliased(Preserve &p, List body) {
  List node;
  $ast.walk(body, node) match (node) case %(op = ?target ?source): {
    String addressed = ast_addressed_identifier(source), holder = NULL;
    match (target) case %(bind ?binding ?):
      holder = binding_identity_spelling(binding);
    if (!holder) holder = ast_direct_identifier(target);
    if (addressed && holder && holder in p.holders) {
      p.names[addressed] = 1;
      p.pointers[holder] = 1;
    }
  }
}

static Var _preserve_locals(Preserve &p, Var value) {
  if (value is not <list> || value.is_nil()) return value;
  List node = value;
  // Only declarations and parameters carry a qualifier. A statement
  // expression's own locals follow any landing around it, so they need one
  // only when a statement expression in the function holds a landing.
  match (node) case %(expr *):
    return p.expression_landings
      ? _rewrite_expression(node, %!(List block) using &p => _preserve_locals(p, block))
      : node;
  match (node) {
    case %(param ?type ?bind):
      return %(param $type ${_binding(p, bind, p.escaped)});
    case $source_block_content(%(*statements)): return _block(p, statements);
    case %(!set ?declaration ((!or declare decl) ? (bindings *))):
      return _declaration(p, declaration, NULL);
  }
  Var child;
  $ast.rewrite_children(node, child, _preserve_locals(p, child));
}

/* Qualify the declarations and parameters the sets name. C puts a qualifier
   on the whole declaration - on the declarator for the object itself, and on
   the base type for a pointee - so a statement that qualifies any of several
   names splits into one declaration each. A local in `escaped` escapes
   right after its declaration; one declared anywhere else is qualified. */
static List _block(Preserve &p, List statements) {
  Array output = [];
  foreach (Var statement, statements) {
    int origin = 0, Var inner = statement;
    match (inner) case %(at ?(int anchor) ?wrapped): {
      origin = anchor;
      inner = wrapped;
    }
    match (inner)
      case %(!set ?declaration
             ((!or declare decl) ?type (!set ?bindings (bindings *)))):
        if (_is_automatic(declaration)) {
          _split(p, output, origin, declaration, type, bindings);
          continue;
        }
    List loop = _escape_loop(p, inner);
    if (loop) {
      output.push(origin ? %(at $origin $loop) : loop);
      continue;
    }
    output.push(_preserve_locals(p, statement));
  }
  return source_block_content(output.list_free());
}

/* Split before qualifying, so a base-type qualifier one declarator needs
   does not reach the names beside it. */
static void _split(
  Preserve &p, Array output, int origin, List declaration, Type type,
  List bindings) {
  List parts = %($declaration);
  if (_declares_name(p, bindings) || _declares_pointee(p, bindings)) {
    Symbol head = declaration.car();
    Array split = [];
    foreach (List binding, bindings.cdr())
      split.push(%($head $type (bindings $binding)));
    parts = split.list_free();
  }
  foreach (List part, parts) {
    List one = _declaration(p, part, p.escaped);
    output.push(origin ? %(at $origin $one) : one);
  }
  _escape_declared(p, output, bindings.cdr());
}

/* `escaped` is the set whose locals escape rather than take the qualifier,
   or NULL where no escape can follow the declaration. */
static List _declaration(Preserve &p, List declaration, Map escaped) {
  if (!_is_automatic(declaration)) return declaration;
  Symbol head = declaration.car();
  Type type = declaration.cadr();
  List bindings = declaration.caddr();
  if (_declares_pointee(p, bindings) &&
      !(<volatile> in type.type().flatten_all()))
    type = cons(<volatile>, type);
  Array preserved = [];
  foreach (List binding, bindings.cdr())
    match (binding) {
      case %(op = ?bind ?value):
        preserved.push(
          %(op = ${_binding(p, bind, escaped)} ${_preserve_locals(p, value)}));
      case %(bind * ): preserved.push(_binding(p, binding, escaped));
    }
  return %($head $type (bindings @{preserved.list_free()}));
}

/* Qualify one binding that a transfer may leave stale, unless `escaped`
   names it: its address escapes instead. */
static List _binding(Preserve &p, List bind, Map escaped) {
  match (bind)
    case %(bind ?name ?mods): {
      String spelling = binding_identity_spelling(name);
      if (spelling && spelling in p.names &&
          !(escaped && spelling in escaped) && !(<volatile> in mods))
        return %(bind $name ${cons(<volatile>, mods)});
    }
  return bind;
}

static int _declares_name(Preserve &p, List bindings) {
  foreach (List binding, bindings.cdr())
    match (binding)
      case $source_declarator_row(%(?name ?)): {
        String spelling = binding_identity_spelling(name);
        if (spelling && spelling in p.names) return 1;
      }
  return 0;
}

/* A pointer that holds the address of a preserved local points at a volatile
   object, so its pointee type must say so or C rejects dropping the
   qualifier. `pointers` names the holders the walk resolved, which covers a
   pointer assigned after its declaration; an initializer that takes the
   address directly says the same thing on its own. */
static int _declares_pointee(Preserve &p, List bindings) {
  foreach (List binding, bindings.cdr()) {
    List declarator = binding;
    match (binding) case %(op = ?bind ?value): {
      String addressed = ast_addressed_identifier(value);
      if (addressed && addressed in p.names) return 1;
      declarator = bind;
    }
    match (declarator) case %(bind ?name ?): {
      String spelling = binding_identity_spelling(name);
      if (spelling && spelling in p.pointers) return 1;
    }
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

/* A `for` that declares a local in `escaped` moves the declaration into a
   block around the loop, so the address escapes once, before the loop. */
static List _escape_loop(Preserve &p, List loop) {
  match (loop)
    case %(for (decl ?type (!set ?bindings (bindings *binds))) *rest): {
      Array output = [];
      _escape_declared(p, output, binds);
      List escapes = output.list_free();
      if (!escapes) return NULL;
      List declaration = _declaration(p, %(declare $type $bindings), p.escaped);
      List remaining = _preserve_locals(p, %(for () @rest));
      return source_block_content(%($declaration @escapes $remaining));
    }
  return NULL;
}

/* Escape the address of each of `binds` that `escaped` names. Once the
   runtime holds a local's address, C must assume every later call,
   `sigsetjmp` and the raise included, reads and writes the local. */
static void _escape_declared(Preserve &p, Array output, List binds) {
  Compiler c = p.c;
  foreach (List bind, binds)
    match (bind)
      case $source_declarator_row(%(?name ?)): {
        String spelling = binding_identity_spelling(name);
        if (spelling && spelling in p.escaped) {
          output.push(
            c.bind_syntax(
              $!{ x2c_exception_escaped = &$name; }, AST_BLOCK,
              c.return_type));
        }
      }
}

/* A parameter in `escaped` escapes before the function body runs. */
static List _escape_parameters(Preserve &p, List body, List bindings) {
  Array output = [];
  match (bindings) case %(bind ? ((fnmod (params *parameters)) *)):
    foreach (List parameter, parameters)
      match (parameter) case %(param ? ?bind):
        _escape_declared(p, output, %($bind));
  return p.c.prepend_setup(body, output.list_free());
}

// defer statements

/* The automatic objects a callable defer's finalizer reads: each one's
   environment field, the bindings the finalizer declares itself, and the
   captured ones it writes. */
static typedef struct DeferCaptures {
  Compiler c;
  List declared, written;
  Map captures;
  Array records;
  int unsupported;
} DeferCaptures;

/** Returns `stmts` with each `defer` statement and the statements after
    it replaced by one region; a list without `defer` returns unchanged. */
List Compiler.rewrite_defer_list(Compiler c, List stmts) {
  Macro deferred = $deferred;
  for (List suffix = stmts; suffix; suffix = suffix.cdr()) {
    List anchored = suffix.car();
    List head = Ast.without_origin(anchored);
    match (head) case deferred(?final_stmt): {
      List rest = c.rewrite_defer_list(suffix.cdr());
      List finalizer = final_stmt;
      if (c.source_map) finalizer = Ast.rewrap_origin(anchored, finalizer);
      List region = c.lower_defer_region(
        source_block_content(rest), finalizer);
      Array before = [];
      for (List item = stmts; item != suffix; item = item.cdr())
        before.push(item.car());
      before.push(Ast.rewrap_origin(anchored, region));
      return before.list_free();
    }
  }
  return stmts;
}

/** Returns the region that runs `finalizer` when `body` leaves. Ordinary
    cleanup statements take the callable chain; lexical transfers and
    unsupported capture types keep the landing-frame path.
*/
List Compiler.lower_defer_region(Compiler c, List body, List finalizer) {
  if (c.source_map && c.origin) finalizer = %(at ${c.origin} $finalizer);
  if (_defer_needs_landing(finalizer)) return _landing_region(body, finalizer);
  return _callable_defer(c, body, finalizer);
}

/* A region that lands is a `try` the kernel writes, marked `kernel` until
   the cleanup walk lowers it. */
static List _landing_region(List body, List finalizer) =>
  %(try $body () $finalizer kernel);

static int _defer_needs_landing(List ast) {
  List node;
  $ast.walk(ast, node) match (node)
    case %((!or return break continue goto try catchcases match) *):
      return 1;
  return 0;
}

/* The finalizer becomes a file-static thunk. Captured objects reach it
   through an environment of their addresses, filled where the region
   registers. */
static List _callable_defer(Compiler c, List body, List finalizer) {
  DeferCaptures d = {
    .c = c, .declared = %(), .written = %(),
    .captures = {}, .records = []
  };
  _collect_captures(d, finalizer);
  if (d.unsupported) {
    d.records.free();
    return _landing_region(body, finalizer);
  }
  List env_binding = NULL, env_local = NULL;
  List records = d.records.list_free();
  if (records) {
    env_binding = c.sym.introduce(c.fresh_name("defer_env"));
    env_local = c.sym.introduce(c.fresh_name("defer_data"));
    c.add_early(_defer_environment(c, env_binding, records));
  }
  List opaque = c.sym.introduce(c.fresh_name("defer_opaque"));
  List callback = c.sym.introduce(c.fresh_name("defer_cleanup"));
  String env_name = env_local ? binding_identity_spelling(env_local) : NULL;
  List rewritten = env_name ? _rewrite_captures(d, finalizer, env_name) : finalizer;
  c.add_early(
    _defer_callback(c, callback, opaque, env_binding, env_local, rewritten));
  if (c.fn_name)
    c.set_fact(%(defer-ownr $callback), c.fn_name);
  return %(defer $body $env_binding $callback $records ${d.written});
}

static void _collect_captures(DeferCaptures &d, List ast) {
  if (!ast || d.unsupported) return;
  match (ast)
    case %(bind ?bound *): {
      List binding = bound, known = d.declared;
      if (!(binding in known)) d.declared = cons(binding, known);
    }
  match (ast)
    case %(expr ? ${$source_identifier_content(%(?bound))}): {
      _capture(d, bound);
      return;
    }
  List modified = Ast.lvalue_binding(Ast.written_operand(ast));
  foreach (Var child, ast) if (child is <list>) _collect_captures(d, child);
  Var field;
  List changed = d.written;
  if (modified && d.captures.try_get(modified, field) &&
      !(modified in changed))
    d.written = cons(modified, changed);
}

static void _capture(DeferCaptures &d, List binding) {
  Compiler c = d.c;
  Map facts = c.semantic_binding_facts();
  if (!binding || binding in d.declared ||
      !(%(automatic $binding) in facts) || binding in d.captures) return;
  Var stored_type = facts[%(type $binding)];
  if (!_defer_type_hoistable(c, stored_type)) {
    d.unsupported = 1;
    return;
  }
  List field = c.sym.introduce(c.fresh_name("defer_capture"));
  d.captures[binding] = field;
  d.records.push(%($binding $stored_type $field));
}

// File-static cleanup thunks cannot name block-local or variably-sized types.
// Keep the existing landing-frame lowering for those uncommon cases.
static int _defer_type_hoistable(Compiler c, Type type) {
  if (!type) return 0;
  Type flat = type.flatten_all();
  if (<register> in flat || <dim> in flat) return 0;
  Type base = type.base_type();
  if (!base) return 0;
  Var first = base.car();
  if (first is <string>) return c.sym.get(%($first)) != NULL;
  if (first == <struct> || first == <union> || first == <enum>)
    return base.len() == 2 && c.sym.get(base) != NULL;
  return 1;
}

// Replace captured object references with pointer dereferences through the
// thunk environment. Expression types remain the source expression's type.
static List _rewrite_captures(
  DeferCaptures &d, List ast, String env_name) {
  if (!ast) return ast;
  match (ast)
    case %(expr ?captured_type
        ${$source_identifier_content(%(?bound))}): {
      List binding = bound;
      Var field_var;
      if (!d.captures.try_get(binding, field_var)) return ast;
      String field_name = binding_identity_spelling(field_var);
      Type type = captured_type, target = type;
      if (binding in d.written &&
          !(<volatile> in type.flatten_all()))
        target = cons(<volatile>, type);
      Type pointer = cons(<*>, target);
      String reference = %"$env_name->$field_name";
      List source = %(expr (* const void) $reference);
      List cast = %(expr $pointer (cast $pointer $source));
      List dereference = %(expr $type (op * $cast));
      return %(expr $type (parens $dereference));
    }
  List child;
  $ast.rewrite_children(ast, child, _rewrite_captures(d, child, env_name));
}

/* Bind the generated type so its fields are visible to the record template.
   Field rows remain canonical syntax: separately binding a Field template
   loses its member type before the enclosing typedef is bound. */
static List _defer_environment(
  Compiler c, List env_binding, List records) {
  Array fields = [];
  foreach (List record, records)
    fields.push(
      c.rebuild_statement($!{ const void *${record.caddr()}; }).cadr());
  return c.capture_environment(env_binding, fields.list_free());
}

/* Preserve the lowered finalizer while binding the new function entry;
   the captured variant also points its local at the environment. */
static List _defer_callback(
  Compiler c, List callback, List opaque, List env_binding,
  List env_local, List rewritten) {
  List body = %(code-value "lowered" (seq $rewritten) ());
  if (env_binding) {
    Type type = %(${binding_identity_spelling(env_binding)});
    return c.bind_syntax(
      $!Unit{ static void $callback(void *$opaque) {
        $type *$env_local = ($type *)$opaque;
        $body
      }
    }, AST_UNIT, NULL);
  }
  return c.bind_syntax(
    $!Unit{ static void $callback(void *$opaque) { $body } }, AST_UNIT, NULL);
}
