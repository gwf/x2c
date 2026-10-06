/*  callables.x -- callable values lowered to C helpers

    Copyright (c) 2026 Gary William Flake.

    A callable value that C cannot spell directly becomes a static helper
    queued with `Compiler.add_early`. Every `Func` helper shares one
    `FuncAdapter` ABI: arguments are read in index order from the argument
    vector, and the result is boxed into a `Var`. A capturing lambda copies
    its snapshots and reference addresses into a file-static context, and
    the bindings it shares by reference move into Scope cells before the
    enclosing function body is normalized.
*/

#pragma once
#include "compiler.x"

#include "adapter-memo.x"
#include "ast-rewrite.x"
#include "meta.x"
#include "grammar.x"

/* Callable conversion failures retain the shared signature-note owner. */

static macro Stmt $report.callable.shared(Expr $c, Expr $source) =>
  $c._adapter_error(
    "function conversion needs x2c_func_shared from lib/func.x",
    %("Func"), $source, NULL);

static macro Stmt $report.callable.context(Expr $c, Expr $source) =>
  $c._adapter_error(
    "function pointer conversion needs Func.new_context from lib/func.x",
    %("Func"), $source, NULL);

static macro Stmt $report.callable.native_context(
  Expr $c, Expr $target, Expr $source) =>
  $c._adapter_error(
    "native binding needs Func.context from lib/func.x",
    $target, $source, NULL);

static macro Stmt $report.callable.direct(
  Expr $c, Expr $target, Expr $source) =>
  $c._adapter_error(
    "native binding target must be a direct function",
    $target, $source,
    %("supported: a free function or Type.method designator"));

static macro Stmt $report.callable.variadic(
  Expr $c, Expr $target, Expr $source, Expr $func_type) {
  String message = $c.sym.resolve_key($target) == $func_type
    ? "function conversion to Func cannot be variadic"
    : "native binding target cannot be variadic";
  $c._adapter_error(message, $target, $source, NULL);
}

static macro Stmt $report.callable.readers(
  Expr $c, Expr $target, Expr $source) =>
  $c._adapter_error(
    "native binding needs Func argument readers from lib/func.x",
    $target, $source, NULL);

static macro Stmt $report.callable.parameter(
  Expr $c, Expr $target, Expr $source) =>
  $c._adapter_error(
    "native binding parameter type has no Var representation",
    $target, $source, NULL);

static macro Stmt $report.callback.direct(Expr $cb) =>
  $cb._fail(
    "typed callback adapter source must be a direct function",
    %("supported: a free function or Type.method designator"));

static macro Stmt $report.callback.target(Expr $cb) =>
  $cb._fail("typed callback adapter target is incomplete", NULL);

static macro Stmt $report.callback.source(Expr $cb) =>
  $cb._fail("typed callback adapter source is incomplete", NULL);

static macro Stmt $report.callback.variadic(Expr $cb) =>
  $cb._fail("typed callback adapter cannot be variadic", NULL);

static macro Stmt $report.callback.arity(
  Expr $cb, Expr $target_count, Expr $source_count) {
  String detail = "target has %d parameters; source has %d".printf(
    $target_count, $source_count);
  $cb._fail("typed callback adapter arity mismatch", %($detail));
}

static macro Stmt $report.callback.void_return(Expr $cb) =>
  $cb._fail("typed callback adapter does not support void return", NULL);

static macro Stmt $report.callback.result(Expr $cb) =>
  $cb._fail("typed callback adapter return type mismatch", NULL);

static macro Stmt $report.callback.parameter(
  Expr $cb, Expr $index, Expr $target, Expr $source) {
  String detail = "parameter %d: %s cannot adapt to %s".printf(
    $index + 1, $target.repr(), $source.repr());
  $cb._fail("typed callback adapter parameter mismatch", %($detail));
}

static macro Expression $callable.note.target(Expr $target) =>
  $target ? %"target signature: ${$target.repr()}"
          : "target signature: unresolved";

static macro Expression $callable.note.source(Expr $source) =>
  $source ? %"source signature: ${$source.repr()}"
          : "source signature: unresolved";

#include "ast.x"
#include "type.x"
#include "parse.x"
#include "expressions.x"
#include "protocol.x"
#include "transform.x"
#include "lambdas.x"

/* Helper syntax shared by every lowering below. A declarator row reuses an
   issued binding without binding it again. */

static macro Stmt $func_local(Type $type, DeclaratorRow $row) {
  $type $row;
}

static macro Expression $func_address(Expr $value) => &$value;

static macro Expression $func_size(Expr $value) => sizeof $value;

// lambda lowering

/** Lowers a resolved lambda expression to emitter-ready helper references.
    `expression` must retain the resolved `expr`, `lambda`, `params`, and
    optional `captures` rows. A noncapturing lambda becomes a static
    `Var`-returning helper. A lambda with capture rows becomes a `FuncAdapter`
    helper and a `Func` whose copied context stores value snapshots and typed
    reference addresses; capture expressions run once from left to right.
    Nested lambdas lower inside out, block fallthrough and bare returns produce
    no value, and synthesized declarations enter the early queue. Parentheses
    remain around lowered helpers; other non-lambda expressions pass through.
*/
List Compiler.lower_lambda_expr(Compiler c, List expression) {
  if (expression.car() == <at> || expression.car() == <src>)
    return Ast.rewrite_children(
      expression, %!(List child) => c.lower_lambda_expr(child));
  Macro lambda = $lambda_expression, captured = $lambda_captured;
  match (expression) {
    case %(expr ?type ${$grouped(?inner)}): {
      List lowered = c.lower_lambda_expr(inner);
      if (lowered == inner) return expression;
      Macro grouped = $grouped;
      return c.rebuild_expression(type, grouped(lowered));
    }
    case captured(?body, *captures, *entries):
      return c._captured_lambda(entries, captures, body);
    case lambda(?body, *params): {
      Type type = expression.cadr();
      /* Only a meta body leaves a noncapturing `Func` lambda unlifted. */
      if (type.match(%("Func"))) {
        Type signature = %((func ${c.lambda_param_types(params)}) "Var");
        return c.lift_func_expression(
          c.rebuild_expression(signature, lambda(body, params)));
      }
      String lname = c.fresh_name("lambda");
      List lambda_binding = c.sym.introduce(lname);
      List decl_params = _params_to_decl_params(params);
      c.add_early(
        c.wrapper_function(
          %(static "Var"), lambda_binding, decl_params.cdr(),
          c._helper_body(body, NULL).cdr()));
      return _func_bound(type, lambda_binding);
    }
  }
  return expression;
}

// Preserve typed declarators; bare lambda parameters remain Var.
static List _params_to_decl_params(List names) {
  if (!names) return %(params (param (void) (bind () ()))) ;
  Array out = [];
  foreach(Var item, names)
    match (item) {
      case %(!set ?identity (binding ? ?)):
        out.push(%(param ("Var") (bind $identity ())));
      case %(param ? ?): out.push(item);
    }
  return %(params @{out.list_free()});
}

static List Compiler._helper_body(Compiler c, List body, List setup) {
  match (body) {
    case $source_block_content(%(*items)): {
      List normalized = _block_returns(items);
      return source_block_content(%(@setup @normalized ${_no_value_return()}));
    }
    case %(expr (void) ?):
      return source_block_content(
        %(@setup (stmnt $body) ${_no_value_return()}));
  }
  List result = c.convert_expression(body, %("Var"));
  return source_block_content(%(@setup (stmnt (return $result))));
}

/* A block lambda returns void for a bare return and for
   fallthrough. Nested lambdas normalize their own returns when lowered. */
static List _block_returns(List ast) {
  if (!ast) return ast;
  match (ast) {
    case $source_any_lambda(): return ast;
    case $source_return_content(%()): return _no_value_return();
  }
  return Ast.rewrite_children(ast, _block_returns);
}

static List _no_value_return(void) => %(
    return ("Var") (expr ("Var") (literal ("Var") "void"))
  );

// captured lambdas

/* One captured lambda: its context type, the adapter that reads a copy of
   it, and the locals that evaluate each capture. Capture rows arrive
   resolved and in first-use order from `lambdas.x`. Their locals run
   before the context aggregate; value fields are snapshots and reference
   fields retain caller or cell addresses. */
static typedef struct CaptureBuild {
  Compiler c;
  List adapter, environment, signature;
  Type value_type, pointer_type;
  Map slots;
  Array field_types, locals, values;
} CaptureBuild;

static List Compiler._captured_lambda(
  Compiler c, List entries, List captures, List body) {
  CaptureBuild b = {
    .c = c, .slots = {}, .field_types = [], .locals = [], .values = []
  };
  b.adapter = c.sym.introduce(c.fresh_name("lambda"));
  List closure = c.sym.introduce(c.fresh_name("lambda_closure"));
  List argv = c.sym.introduce(c.fresh_name("lambda_argv"));
  String name = c.fresh_name("lambda_context");
  List type_binding = c.sym.introduce(name);
  b.value_type = %($name);
  b.pointer_type = %(* const $name);
  b.environment = c.sym.introduce(c.fresh_name("lambda_context_value"));
  c.set_fact(%(automatic ${b.environment}), 1);
  c.set_fact(%(type ${b.environment}), b.pointer_type);
  b.declare(type_binding, captures);
  b.publish(entries, body, closure, argv);
  return c.inline_header ? b.bridged() : b.direct();
}

static void CaptureBuild.declare(
  CaptureBuild &b, List type_binding, List captures) {
  Array fields = [];
  foreach (List capture, captures) b._field(fields, capture);
  b.c.add_early(b.c.capture_environment(type_binding, fields.list_free()));
}

/** Binds the file-static context type `name` with the field rows `fields`,
    for captured lambdas and callable defers. The complete typedef is bound
    at once, so each field keeps its member type.
*/
List Compiler.capture_environment(Compiler c, List name, List fields) {
  return c.bind_syntax(
    $!Unit{ static typedef struct $name { $fields... } $name; },
    AST_UNIT, NULL);
}

static void CaptureBuild._field(CaptureBuild &b, Array fields, List capture) {
  match (capture)
    case %(capture ?binding ?captured_type ?expression): {
      Compiler c = b.c;
      Type source_type = captured_type;
      Type storage_type = source_type.car() == <&>
                        ? source_type.cdr().type().reference()
                        : %("Var");
      List field = c.sym.introduce(c.fresh_name("lambda_capture"));
      fields.push(c.rebuild_statement($!{ $storage_type $field; }).cadr());
      b.field_types.push(storage_type);
      b.slots[binding] = %($field $storage_type);

      List temporary = c.sym.introduce(c.fresh_name("lambda_capture_value"));
      List value = c.convert_expression(expression, storage_type);
      List (base, mods) = storage_type.declaration_parts();
      Macro local = $func_local;
      List row = %(op = (bind $temporary $mods) $value);
      b.locals.push(c.rebuild_statement(local(base, row)).cadr());
      b.values.push(_func_bound(storage_type, temporary));
    }
}

/* The adapter borrows the copied context for each synchronous Func call. */
static void CaptureBuild.publish(
  CaptureBuild &b, List entries, List body, List closure, List argv) {
  Compiler c = b.c;
  List params = c.lambda_param_types(entries);
  List locals = c._func_argument_locals(
    c.sym.resolve_key(%("FuncAdapter")), entries ? params : NULL,
    entries.map(_entry_binding), closure, argv);
  List setup = c._context_local(b.value_type, b.environment, closure);
  List rewritten = c.normalize(b._rewrite(body));
  c._publish_func_adapter(
    b.adapter, closure, argv, rewritten, %(@locals $setup));
  b.signature = c.cache_literal_list(%((func $params) "Var"));
}

static List _entry_binding(List entry) {
  match (entry) {
    case %(!set ?binding (binding ? ?)): return binding;
    case %(param ? (bind ?binding *)): return binding;
  }
  return NULL;
}

/* Capture-construction expressions read through this context, but a nested
   lambda body is left alone: its own environment and lowering handle that
   body once the rewritten capture values are available. */
static List CaptureBuild._rewrite(CaptureBuild &b, List ast) {
  if (!ast) return ast;
  Macro lambda = $lambda_expression, captured = $lambda_captured;
  if (ast.car() == <expr>) {
    match (ast) {
      case captured(?body, *captures, *params): {
        List rows = b._rows(captures);
        return rows == captures ? ast
             : b.c.rebuild_expression(
               ast.cadr(), captured(body, rows, params));
      }
      case lambda(?body, *params): return ast;
      case %(expr ?source_type
          ${$source_identifier_content(%(?bound))}):
        return b._read(ast, source_type, bound);
    }
  }
  Var child;
  $ast.rewrite_children(ast, child, b._rewrite(child));
}

static List CaptureBuild._rows(CaptureBuild &b, List captures) {
  Var row;
  $ast.rewrite_children(captures, row, b._row(row));
}

static List CaptureBuild._row(CaptureBuild &b, List row) {
  match (row)
    case %(capture ?binding ?type ?expression): {
      List value = b._rewrite(expression);
      if (value != expression) return %(capture $binding $type $value);
    }
  return row;
}

static List CaptureBuild._read(
  CaptureBuild &b, List ast, Type source_type, List bound) {
  Var stored;
  if (!b.slots.try_get(bound, stored)) return ast;
  (List field, Type storage_type) = stored;
  String field_name = binding_identity_spelling(field);
  List environment = _func_bound(b.pointer_type, b.environment);
  List read = $!($storage_type){ $environment->$field_name };
  if (source_type.car() == <&>) return %(expr $source_type ${read.caddr()});
  List converted = b.c.convert_expression(read, source_type);
  match (converted)
    case %(expr ? (call "Var_pointer" ?)):
      return %(expr $source_type
               (parens (expr $source_type
                 (cast $source_type $converted))));
  return converted;
}

/* A public inline function reaches the file-static context through a
   generated bridge that copies the capture values it receives. */
static List CaptureBuild.bridged(CaptureBuild &b) {
  Compiler c = b.c;
  List bridge = c._func_bridge_binding("func_from_capture");
  Array parameters = [], factory_values = [];
  foreach (Type field_type, b.field_types) {
    List parameter = c.sym.introduce(c.fresh_name("lambda_capture"));
    parameters.push(field_type.parameter_ast(parameter));
    factory_values.push(_func_bound(field_type, parameter));
  }
  List context = c.sym.introduce(c.fresh_name("lambda_context"));
  List factory_body = c.rebuild_statement(
    $!{
      ${b._storage(context, factory_values.list_free())}
      return ${b._construct(context)};
    });
  List declaration_params = %(params @{parameters.list_free()});
  c.add_early(
    c.wrapper_function(
      %("Func"), bridge, declaration_params.cdr(), factory_body.cdr()));
  List parameter_types = b.field_types.list_free();
  Type factory_type = %((func $parameter_types) "Func");
  List call = c._func_bridge_call(
    bridge, declaration_params, factory_type, b.values.list_free());
  return b._result(NULL, call);
}

static List CaptureBuild.direct(CaptureBuild &b) {
  Compiler c = b.c;
  List context = c.sym.introduce(c.fresh_name("lambda_context"));
  List storage = b._storage(context, b.values.list_free());
  return b._result(storage, b._construct(context));
}

static List CaptureBuild._storage(CaptureBuild &b, List context, List values) {
  return b.c.rebuild_statement(
    $!{ ${b.value_type} $context = { $values... }; }).cadr();
}

static List CaptureBuild._construct(CaptureBuild &b, List context) {
  Compiler c = b.c;
  Type constructor_type = NULL;
  List constructor = c._adapter_helper("Func_new_context", constructor_type);
  Type adapter_type = c.sym.resolve_key(%("FuncAdapter"));
  return c._func_context_call(
    b.value_type, context, _func_bound(adapter_type, b.adapter),
    b.signature, _func_bound(constructor_type, constructor));
}

/* A value computed after its setup statements. */
static macro Expression $statement_value(Expr $value, Stmt $setup...) =>
  ({ $setup... $value; });

static List CaptureBuild._result(CaptureBuild &b, List storage, List value) {
  List setup = b.locals.list_free();
  if (storage) setup = setup.append(%($storage));
  Macro shape = $statement_value;
  return b.c.rebuild_expression(%("Func"), shape(value, setup));
}

// lambda cells

/* A shared lambda cell: Scope storage for one automatic binding, copied
   from its initializer or left for a later assignment. */
static macro Stmt $compiler_cell(Type $type, Name $cell, Expr $value) {
  $type *$cell = Scope_memdup((const void *)&($type)$value, sizeof($type));
}

static macro Stmt $compiler_empty_cell(Type $type, Name $cell) {
  $type *$cell = Scope_malloc(sizeof($type));
}

static macro Expression $compiler_cell_value(Name $cell) => (*$cell);

/* One callable region's cells: the automatic bindings the region owns, in
   declaration order, and the cell each shared binding moves to. */
static typedef struct CellRegion {
  Compiler c;
  Map owned, cells, values;
  Array order;
} CellRegion;

/** Prepares one resolved function body for shared mutable lambda captures.
    `declarator` must carry a resolved `bind` with `fnmod` parameters, and
    `body` must agree with the automatic-binding and type facts in `Compiler`.
    Before normal body transformation, the method rewrites explicitly shared
    parameters and locals to `Scope`-owned cells, prepares nested bodies,
    and returns the rewritten body with declaration and initializer order
    preserved.
*/
List Compiler.prepare_lambda_cells(Compiler c, List declarator, List body) {
  List entries = NULL;
  match (declarator)
    case %(bind ? ((fnmod (params *parameters)))):
      entries = parameters;
  return c._prepare_lambda_region(entries, body);
}

/* Explicit reference rows select which automatic bindings need typed cells.
   Parameters allocate at entry and locals at their declarations, preserving
   initializer order. Snapshot rows retain their separate binding
   identities. */
static List Compiler._prepare_lambda_region(
  Compiler c, List entries, List body) {
  if (!ast_contains_head(body, <lambda>)) return body;
  body = c._prepare_nested_regions(body);
  CellRegion r = {
    .c = c, .owned = {}, .cells = {}, .values = {}, .order = []};
  foreach (List entry, entries) r.own(_entry_binding(entry));
  r.collect(body);
  Map candidates = {};
  _collect_reference_captures(body, r.owned, candidates);
  if (!candidates.len()) return body;
  r.allocate(candidates);
  List rewritten = r.rewrite(body);
  return c._prepend_setup(rewritten, r.setup(entries));
}

/* Nested bodies own their local cells; their construction expressions still
   execute in the enclosing region. Capture resolution has already assigned
   each binding its value or reference mode. */
static List Compiler._prepare_nested_regions(Compiler c, List ast) {
  if (!ast) return ast;
  Macro lambda = $lambda_expression, captured = $lambda_captured;
  if (ast.car() == <expr>) {
    match (ast) {
      case captured(?body, *captures, *entries): {
        List prepared = c._prepare_lambda_region(entries, body);
        return prepared == body ? ast : c.rebuild_expression(
          ast.cadr(), captured(prepared, captures, entries));
      }
      case lambda(?body, *params): {
        List prepared = c._prepare_lambda_region(params, body);
        return prepared == body ? ast
             : c.rebuild_expression(ast.cadr(), lambda(prepared, params));
      }
    }
  }
  Var child;
  $ast.rewrite_children(
    ast, child, ast_contains_head(child, <lambda>)
      ? c._prepare_nested_regions(child) : child.list());
}

static void CellRegion.own(CellRegion &r, List binding) {
  if (!binding || binding in r.owned) return;
  Var automatic, stored_type;
  Map facts = r.c.semantic_binding_facts();
  if (!facts.try_get(%(automatic $binding), automatic) ||
      !facts.try_get(%(type $binding), stored_type))
    return;
  Type type = stored_type;
  if (!type || type.is_static()) return;
  r.owned[binding] = type;
  r.order.push(binding);
}

/* Collect only bindings owned by this callable region. Nested lambdas are
   separate regions even though their capture expressions execute here.
   Keep the manual worklist: a Func visit callback's dynamic call per node
   cost ~6% of self-translation.
   Pending sibling suffixes wait on `resume` to stay off the C stack. */
static void CellRegion.collect(CellRegion &r, List ast) {
  if (!ast) return;
  Array resume = $auto([]);
  for (;;) {
    int pruned = 0;
    match (ast) {
      case $source_any_lambda(): pruned = 1;
      case %(bind ?binding *): {
        r.own(binding);
        pruned = 1;
      }
    }
    List rest = pruned ? NULL : ast;
    for (;;) {
      while (!rest) {
        if (!resume.len()) return;
        rest = resume.take_last();
      }
      Var child = rest.car();
      rest = rest.cdr();
      if (child is <list> && !child.is_nil()) {
        if (rest) resume.push(rest);
        ast = child;
        break;
      }
    }
  }
}

static void _collect_reference_captures(List ast, Map owned, Map candidates) {
  List node;
  $ast.walk(ast, node)
    match (node) case %(capture ? (& *) (expr ? (op & ?target))): {
      List binding = Ast.lvalue_binding(target);
      Var stored;
      if (binding && owned.try_get(binding, stored)) {
        Type type = stored;
        if (type.car() != <&>) candidates[binding] = type;
      }
    }
}

/* Each candidate binding gets a cell, in declaration order. */
static void CellRegion.allocate(CellRegion &r, Map candidates) {
  Compiler c = r.c;
  foreach (List binding, r.order) {
    Var stored_type;
    if (!candidates.try_get(binding, stored_type)) continue;
    Type type = stored_type;
    List cell = c.sym.introduce(c.fresh_name("lambda_cell"));
    r.cells[binding] = %($cell $type);
    c.set_fact(%(automatic $cell), 1);
    c.set_fact(%(type $cell), type.reference());
  }
}

static List CellRegion.rewrite(CellRegion &r, List ast) {
  if (!ast) return ast;
  match (ast) {
    case %(declare ?target (bindings *bindings)): {
      List declaration = r._declaration(target, bindings);
      if (declaration) return declaration;
    }
    case %(expr ?source_type
        ${$source_identifier_content(%(?binding))}): {
      List cell = NULL;
      Type type = NULL;
      if (r._lookup(binding, cell, type)) {
        if (source_type.car() == <&>)
          return _func_bound(source_type, cell);
        return r._value(binding, cell);
      }
      return ast;
    }
  }
  Var child;
  $ast.rewrite_children(ast, child, r.rewrite(child));
}

/* Split only declarations that need cells. Keeping each cell allocation at
   its binding preserves declaration order and evaluates its initializer once;
   moving allocations to lambda construction would reorder visible effects. */
static List CellRegion._declaration(
  CellRegion &r, List target, List bindings) {
  int has_cell = 0;
  foreach (List item, bindings)
    match (item) case $source_declarator_row(%(?binding *)):
      has_cell |= binding && binding in r.cells;
  if (!has_cell) return NULL;

  Array sequence = [];
  foreach (List item, bindings) {
    List binding = NULL, initializer = NULL;
    match (item) {
      case %(bind ?matched *): binding = matched;
      case %(op = (bind ?matched *) ?value): {
        binding = matched;
        initializer = r.rewrite(value);
      }
    }
    List cell = NULL;
    Type type = NULL;
    if (r._lookup(binding, cell, type)) {
      sequence.push(r.c._cell_declaration(cell, type, initializer));
      continue;
    }
    sequence.push(%(declare $target (bindings ${r.rewrite(item)})));
  }
  return %(seq @{sequence.list_free()});
}

/* Every read of one cell binds the same `(*cell)`, so the region binds it
   once and keeps it in the cell's row. Binding opens a semantic
   transaction that copies the unit's maps; doing that per read made
   translation quadratic in the number of captured reads. */
static List CellRegion._value(CellRegion &r, List binding, List cell) {
  Var cached;
  if (r.values.try_get(binding, cached)) return cached;
  Macro shape = $compiler_cell_value;
  List value = r.c.bind_syntax(shape(cell), AST_EXPRESSION, NULL);
  r.values[binding] = value;
  return value;
}

static int CellRegion._lookup(
  CellRegion &r, List binding, List &cell, Type &type) {
  Var stored;
  if (!r.cells.try_get(binding, stored)) return 0;
  List row = stored;
  cell = row.car();
  type = row.cadr();
  return 1;
}

/* A plain initializer is the one element of the compound a cell copies. */
static List Compiler._cell_declaration(
  Compiler c, List cell, Type type, List initializer) {
  List compound = initializer;
  if (initializer && !initializer.match(%(expr ? (composite ?))))
    compound = $!( { $initializer } );
  Macro shape = initializer ? $compiler_cell : $compiler_empty_cell;
  return c.bind_syntax(shape(type, cell, compound), AST_BLOCK, NULL);
}

/* Parameters copy into their cells at entry. */
static List CellRegion.setup(CellRegion &r, List entries) {
  Array setup = [];
  foreach (List entry, entries) {
    List binding = _entry_binding(entry);
    List cell = NULL;
    Type type = NULL;
    if (!r._lookup(binding, cell, type)) continue;
    setup.push(
      r.c._cell_declaration(cell, type, _func_bound(type, binding)));
  }
  return setup.list_free();
}

static List Compiler._prepend_setup(Compiler c, List body, List setup) {
  if (!setup) return body;
  Macro shape = $statement_value;
  match (body) {
    case $source_block_content(%(*items)):
      return source_block_content(%(@setup @items));
    case %(!set ?expression (expr ?type ?)):
      return c.rebuild_expression(type, shape(expression, setup));
  }
  return body;
}

// Func values

/** Converts a resolved function-like expression to `Func` when supported.
    Existing `Func` values pass through. Direct fixed functions reuse a
    file-static handle; other function-typed and function-pointer expressions
    are evaluated once and copied into a new context-bound `Func`, with null
    pointers producing null `Func`. Lambda expressions are lowered first, and
    unrelated expressions pass through unchanged. Public inline functions
    reach the queued helpers through generated bridge functions.
*/
List Compiler.lift_func_expression(Compiler c, List expression) {
  Type type = NULL;
  List payload = NULL;
  match (expression)
    case %(expr ?matched_type ?matched_payload): {
      type = matched_type;
      payload = matched_payload;
    }
  if (!type) return c._deref_func_lift(expression, payload);
  Type func_type = c.sym.resolve_key(%("Func"));
  if (c.sym.resolve_key(type) == func_type) return expression;

  Macro lambda = $lambda_expression;
  match (expression)
    case lambda(?body, *params): {
      expression = c.lower_lambda_expr(expression);
      match (expression)
        case %(expr ?lowered_type ?lowered_payload): {
          type = lowered_type;
          payload = lowered_payload;
        }
      if (c.sym.resolve_key(type) == func_type) return expression;
    }

  Type source_type = NULL;
  List source_binding = NULL;
  if (_direct_func_source(type, payload, 0, source_type, source_binding))
    return c._direct_func_value(source_binding, source_type);

  Type pointer_type = c._func_pointer_value_type(type);
  if (pointer_type) return c._indirect_func_lift(expression, pointer_type);
  Type resolved = c.sym.resolve_key(type);
  if (resolved && resolved.is_function()) {
    Type pointer = cons(<*>, resolved);
    return c._indirect_func_lift(%(expr $pointer $payload), pointer);
  }
  return c._deref_func_lift(expression, payload);
}

/* The direct function a designator names under parentheses and address-of,
   and under casts when `through_cast` is set. */
static int _direct_func_source(
  Type type, List payload, int through_cast, Type &source_type,
  List &source_binding) {
  match (payload) {
    case $source_identifier_content(%(?binding)): {
      if (!type || type.is_pointer() || !type.is_function()) return 0;
      source_type = type;
      source_binding = binding;
      return 1;
    }
    case $source_cast_content(%(? (expr ?inner_type ?inner_payload))):
      return through_cast && _direct_func_source(
        inner_type, inner_payload, 1, source_type, source_binding);
    case $source_content_pattern($grouped, %(?inner)):
      match (inner)
        case %(expr ?inner_type ?inner_payload):
          return _direct_func_source(
            inner_type, inner_payload, through_cast, source_type,
            source_binding);
    case $source_operator_content(%(& (expr ?inner_type ?inner_payload))):
      return _direct_func_source(
        inner_type, inner_payload, through_cast, source_type,
        source_binding);
  }
  return 0;
}

static List Compiler._direct_func_value(
  Compiler c, List source_binding, Type source_type) {
  List handle = c._direct_func_handle(source_binding, source_type);
  if (!c.inline_header) return handle;

  Type key_type = source_type.canonicalize();
  List key = %(fgetter $source_binding $key_type);
  List bridge = NULL;
  List parameters = %(params (param (void) (bind () ())));
  $adapter.memo(c, key, bridge) {
    bridge = c._func_bridge_binding("func_get");
    c.add_early(
      c.wrapper_function(
        %("Func"), bridge, parameters.cdr(),
        c._func_return_body(handle)));
  }
  Type getter_type = $!Type{ Func (void) };
  return c._func_bridge_call(bridge, parameters, getter_type, NULL);
}

static List Compiler._direct_func_handle(
  Compiler c, List source_binding, Type source_type) {
  Type key_type = source_type.canonicalize();
  List key = %(fhandle $source_binding $key_type);
  List handle = NULL;
  $adapter.memo(c, key, handle) {
    List adapter = c._direct_func_adapter(
      %("Func"), source_binding, source_type);
    List signature = c._func_signature_literal(source_type);
    Type constructor_type = NULL;
    List constructor = c._adapter_helper(
      "x2c_func_shared", constructor_type);
    if (!constructor || !constructor_type)
      $report.callable.shared(c, source_type);
    handle = c.sym.introduce(c.fresh_name("func_handle"));
    List value = c._func_call(
      %("Func"), _func_bound(constructor_type, constructor),
      %(${_func_bound(%("FuncAdapter"), adapter)} $signature));
    c.add_early(
      c.rebuild_statement($!{ static Func $handle = $value; }).cadr());
  }
  return _func_bound(%("Func"), handle);
}

static List Compiler._func_bridge_binding(Compiler c, String stem) {
  String hash = "%08x".printf(c.filename.hash());
  return c.sym.introduce(c.fresh_name(%"${stem}_$hash"));
}

static List Compiler._func_bridge_call(
  Compiler c, List bridge, List parameters,
  Type function_type, List arguments) {
  List call = c._func_call(
    %("Func"), _func_bound(function_type, bridge), arguments);
  /* A call through a bridge function the unit declares where it calls. */
  return $!Func{ ({
    extern Func $bridge(${parameters.cdr()}...);
    $call;
  }) };
}

static Type Compiler._func_pointer_value_type(Compiler c, Type type) {
  Type resolved = c.sym.resolve_key(type);
  if (resolved) type = resolved;
  while (type && _func_type_qualifier(type.car())) type = type.cdr();
  if (!type || type.car() != <*>) return NULL;
  List tail = type.cdr();
  while (tail && _func_type_qualifier(tail.car())) tail = tail.cdr();
  Type pointer = cons(<*>, tail);
  return pointer.dereference().is_function() ? pointer : NULL;
}

static int _func_type_qualifier(Var value) =>
  value == <const> || value == <volatile> || value == <restrict>;

static List Compiler._indirect_func_lift(
  Compiler c, List expression, Type pointer_type) {
  if (!c.inline_header)
    return c._indirect_func_value(expression, pointer_type);

  Type key_type = pointer_type.canonicalize();
  List key = %(fpointer-factory $key_type);
  List bridge = NULL;
  $adapter.memo(c, key, bridge) {
    bridge = c._func_bridge_binding("func_from_pointer");
    List parameter = c.sym.introduce(c.fresh_name("func_pointer"));
    List parameters = %(
      params ${pointer_type.parameter_ast(parameter)}
    );
    List value = c._indirect_func_value(
      _func_bound(pointer_type, parameter), pointer_type);
    c.add_early(
      c.wrapper_function(
        %("Func"), bridge, parameters.cdr(),
        c._func_return_body(value)));
  }
  List parameters = %(
    params ${pointer_type.parameter_ast(NULL)}
  );
  Type factory_type = %((func ($pointer_type)) "Func");
  return c._func_bridge_call(bridge, parameters, factory_type, %($expression));
}

static List Compiler._indirect_func_value(
  Compiler c, List expression, Type pointer_type) {
  Type context_type = NULL;
  List context_field = NULL;
  List adapter = c._indirect_func_adapter(
    %("Func"), pointer_type, context_type, context_field);
  List signature = c._func_signature_literal(pointer_type);
  Type constructor_type = NULL;
  List constructor = c._adapter_helper("Func_new_context", constructor_type);
  if (!constructor || !constructor_type)
    $report.callable.context(c, pointer_type);

  List context = c.sym.introduce(c.fresh_name("func_pointer_context"));
  List declaration = c._func_context_declaration(
    context_type, context, expression);
  String field_name = binding_identity_spelling(context_field);
  List pointer = %(
    expr $pointer_type
      (op . ${_func_bound(context_type, context)} ($field_name)));
  List constructed = c._func_context_call(
    context_type, context, _func_bound(%("FuncAdapter"), adapter),
    signature, _func_bound(constructor_type, constructor));
  return $!Func{ ({
    $declaration ${c._func_present_statement(pointer, constructed)}
  }) };
}

static List Compiler._indirect_func_adapter(
  Compiler c, Type diagnostic_type, Type pointer_type,
  Type &out_context_type, List &out_context_field) {
  List key = %(findirect $pointer_type), result = NULL;
  $adapter.memo(c, key, result) {
    result = c._build_indirect_func_adapter(diagnostic_type, pointer_type);
  }
  (List adapter, Type context, List field) = result.cdr();
  out_context_type = context;
  out_context_field = field;
  return adapter;
}

static List Compiler._build_indirect_func_adapter(
  Compiler c, Type diagnostic_type, Type pointer_type) {
  String context_name = NULL;
  List field_binding = NULL;
  c._func_pointer_context(pointer_type, context_name, field_binding);
  Type context_type = %($context_name);
  Type context_pointer = %(* const $context_name);
  Type context_helper_type = NULL;
  if (!c._adapter_helper("Func_context", context_helper_type) ||
      !context_helper_type)
    $report.callable.native_context(c, diagnostic_type, pointer_type);
  List fn_binding = c.sym.introduce(c.fresh_name("func_binding"));
  List context_local = c.sym.introduce(c.fresh_name("func_pointer_context"));
  List context_declaration = c._context_local(
    context_type, context_local, fn_binding);
  String field_name = binding_identity_spelling(field_binding);
  List context = _func_bound(context_pointer, context_local);
  List target = $!($pointer_type){ $context->$field_name };
  List adapter = c._build_func_adapter(
    diagnostic_type, pointer_type, target, fn_binding,
    %($context_declaration));
  return %(indirect-adapter $adapter $context_type $field_binding);
}

/* Inside an adapter, `local` points at the context `fn` copied, typed as a
   `value_type` record. */
static List Compiler._context_local(
  Compiler c, Type value_type, List local, List fn) {
  Type pointer = $!Type{ const $value_type * };
  Type helper_type = NULL;
  List helper = c._adapter_helper("Func_context", helper_type);
  List call = c._func_call(
    $!Type{ const void * }, _func_bound(helper_type, helper),
    %(${_func_bound(%("Func"), fn)}));
  List cast = %(expr $pointer (cast $pointer $call));
  Macro shape = $func_local;
  return c.rebuild_statement(
    shape(
      $!Type{ const $value_type }, %(op = (bind $local (*)) $cast))).cadr();
}

static void Compiler._func_pointer_context(
  Compiler c, Type pointer_type, String &context_name,
  List &field_binding) {
  context_name = c.fresh_name("func_pointer_context");
  List context_binding = c.sym.introduce(context_name);
  field_binding = c.sym.introduce(c.fresh_name("func_pointer"));
  List (field_base, field_mods) = pointer_type.declaration_parts();
  c.add_early(
    %(
    typedef
      (static struct $context_name
        (fields
          (declare $field_base
            (bindings (bind $field_binding $field_mods)))))
      (bindings (bind $context_binding ()))
  ));
}

static List Compiler._func_context_declaration(
  Compiler c, Type context_type, List context, List expression) {
  List value = $!($context_type){ { $expression } };
  Macro storage_shape = $func_local;
  return c.rebuild_statement(
    storage_shape(context_type, %(op = (bind $context ()) $value))).cadr();
}

/* `Func.new_context(adapter, signature, &context, sizeof context)`, with
   the adapter and constructor already typed. */
static List Compiler._func_context_call(
  Compiler c, Type type, List context, List adapter, List signature,
  List constructor) {
  List value = _func_bound(type, context);
  Macro address_shape = $func_address, size_shape = $func_size;
  List address = c.rebuild_expression(type.reference(), address_shape(value));
  List size = c.rebuild_expression(%(size_t), size_shape(value));
  return c._func_call(
    %("Func"), constructor, %($adapter $signature $address $size));
}

static List Compiler._func_present_statement(
  Compiler c, List pointer, List constructed) {
  List null_binding = c.sym.reference(%("NULL"), NULL);
  List result = $!Func{
    $pointer ? $constructed : ${_func_bound(%("Func"), null_binding)} };
  return c.rebuild_statement($!{ $result; }).cadr();
}

/* A dereferenced function pointer reaches the lift untyped or typed as a
   bare pointer, possibly under parens or address-of shells; recover the
   callable type from the pointer operand. Unsupported shapes pass through. */
static List Compiler._deref_func_lift(
  Compiler c, List expression, List payload) {
  List probe = payload;
  int unwrapped = 1;
  while (unwrapped) {
    unwrapped = 0;
    match (probe) {
      case $source_content_pattern($grouped, %(?inner)):
        match (inner)
          case %(expr ? ?inner_payload): {
            probe = inner_payload;
            unwrapped = 1;
          }
      case $source_operator_content(%(& (expr ? ?inner_payload))): {
        probe = inner_payload;
        unwrapped = 1;
      }
    }
  }
  match (probe)
    case $source_operator_content(%(* (expr ?operand_type ?))): {
      Type resolved = c.sym.resolve_key(operand_type);
      if (resolved && resolved.is_pointer() &&
          resolved.dereference().is_function())
        return c._indirect_func_lift(%(expr $resolved $payload), resolved);
    }
  return expression;
}

// Func adapters

/* A record result is copied into a Var after the native call completes. */
static macro Stmt $func_record_result(
    Type $type, DeclaratorRow $row, Expr $boxed) {
  {
    $type $row;
    return $boxed;
  }
}

/* The argument readers of one adapter, with its `Func` and argument vector
   parameters. */
static typedef struct FuncReaders {
  Compiler c;
  Type diagnostic_type;
  List value, reference, fn, argv;
} FuncReaders;

/** Adapts a direct native function argument when `FuncAdapter` is expected.
    A noncapturing lambda is lowered to its direct function designator. Other
    arguments must be resolved direct designators, possibly parenthesized,
    cast, or addressed; an indirect function-pointer value is rejected.
    A function already having the adapter's pointee type passes through,
    and new helpers are cached and queued with `Compiler.add_early`.
*/
List Compiler.maybe_adapt_func_arg(
  Compiler c, List argument, List expected_type) {
  if (!c._is_func_adapter(expected_type)) return argument;
  argument = c.lower_lambda_expr(argument);
  Type arg_type = NULL, List payload = NULL;
  match (argument) {
    case %(expr ?type ?matched_payload): {
      arg_type = type;
      payload = matched_payload;
    }
    default: return argument;
  }
  if (c._is_func_adapter(arg_type)) return argument;
  Type source_type = NULL, List source_binding = NULL;
  if (!_direct_func_source(arg_type, payload, 1, source_type, source_binding))
    $report.callable.direct(c, expected_type, arg_type);
  if (c._is_func_adapter_target(source_type)) return argument;
  List adapter = c._direct_func_adapter(
    expected_type, source_binding, source_type);
  return _func_bound(expected_type, adapter);
}

static int Compiler._is_func_adapter(Compiler c, Type type) {
  if (!type) return 0;
  Type adapter = c.sym.resolve_key(%("FuncAdapter"));
  if (!adapter) return 0;
  return c.sym.resolve_key(type) == adapter;
}

/* A function already written in the adapter's own shape needs no wrapper:
   C converts the designator to a pointer at the call. */
static int Compiler._is_func_adapter_target(Compiler c, Type type) {
  if (!type) return 0;
  Type adapter = c.sym.resolve_key(%("FuncAdapter"));
  if (!adapter || !adapter.is_pointer()) return 0;
  Type pointee = adapter.dereference();
  return type.canonicalize() == pointee.canonicalize();
}

static List Compiler._direct_func_adapter(
  Compiler c, Type diagnostic_type, List source_binding, Type source_type) {
  Type key_type = source_type.canonicalize();
  List key = %(fadapt $source_binding $key_type);
  List adapter = NULL;
  $adapter.memo(c, key, adapter) {
    List target = _func_bound(source_type, source_binding);
    adapter = c._build_func_adapter(
      diagnostic_type, source_type, target, NULL, NULL);
  }
  return adapter;
}

static List Compiler._build_func_adapter(
  Compiler c, Type diagnostic_type, Type source_type,
  List target, List supplied_fn_binding, List prefix) {
  List params = NULL, Type return_type = NULL;
  source_type.function_parts(params, return_type);
  if (_typed_params_variadic(params)) {
    Type func_type = c.sym.resolve_key(%("Func"));
    $report.callable.variadic(c, diagnostic_type, source_type, func_type);
  }
  source_type = source_type.canonicalize();
  return_type = return_type.canonicalize();

  c._require_func_readers(diagnostic_type, source_type);

  String name = c.fresh_name("func_adapt");
  List adapter_binding = c.sym.introduce(name);
  List fn_binding = supplied_fn_binding
                  ? supplied_fn_binding
                  : c.sym.introduce(c.fresh_name("func_binding"));
  List argv_binding = c.sym.introduce(c.fresh_name("func_argv"));
  List names = c._auto_names(params.len());
  List locals = c._func_argument_locals(
    diagnostic_type, params, names, fn_binding, argv_binding);
  List arguments = params.zip_with(
    names, _func_bound);
  List call = c._func_call(return_type, target, arguments);
  Type resolved_result = c.sym.resolve_key(return_type);
  if (resolved_result && resolved_result.car() == <struct>)
    call = c._func_record_call(return_type, call);
  c._publish_func_adapter(
    adapter_binding, fn_binding, argv_binding, call, %(@prefix @locals));
  return adapter_binding;
}

static void Compiler._require_func_readers(
  Compiler c, Type diagnostic_type, Type source_type) {
  foreach (String helper_name,
           %("x2c_func_value_argument"
             "x2c_func_declared_reference_argument")) {
    Type helper_type = NULL;
    List helper = c._adapter_helper(helper_name, helper_type);
    if (!helper || !helper_type)
      $report.callable.readers(c, diagnostic_type, source_type);
  }
}

/* Materialize arguments in index order: C does not sequence call operands,
   and a reader failure must prevent later conversions and body effects. */
static List Compiler._func_argument_locals(
  Compiler c, Type diagnostic_type, List types, List names,
  List fn_binding, List argv_binding) {
  Type value_type = NULL, reference_type = NULL;
  List value_helper = c._adapter_helper("x2c_func_value_argument", value_type);
  List reference_helper = c._adapter_helper(
    "x2c_func_declared_reference_argument", reference_type);
  FuncReaders readers = {
    .c = c, .diagnostic_type = diagnostic_type,
    .value = _func_bound(value_type, value_helper),
    .reference = _func_bound(reference_type, reference_helper),
    .fn = fn_binding, .argv = argv_binding
  };
  Array locals = [];
  int index = 0;
  Macro local = $func_local;
  foreach (Type type, types) {
    List binding = names.car();
    names = names.cdr();
    Type storage_type = NULL;
    List value = readers.read(type, index++, storage_type);
    List (base, mods) = storage_type.declaration_parts();
    List row = %(op = (bind $binding $mods) $value);
    locals.push(c.rebuild_statement(local(base, row)).cadr());
  }
  return locals.list_free();
}

static List FuncReaders.read(
  FuncReaders &r, Type parameter_type, int index, Type &storage_type) {
  if (parameter_type.is_reference())
    return r._reference(parameter_type, index, storage_type);
  Symbol tag = r.c.sym.var_tag_for_type(parameter_type, NULL);
  Type resolved = r.c.sym.resolve_key(parameter_type);
  if (!tag && resolved &&
      (resolved.is_pointer() || resolved.car() == <struct>))
    return r._pointer(parameter_type, resolved, index, storage_type);
  return r._value(parameter_type, tag, index, storage_type);
}

static List FuncReaders._reference(
  FuncReaders &r, Type parameter_type, int index, Type &storage_type) {
  Compiler c = r.c;
  Type target = parameter_type.cdr(), pointer = target.reference();
  List picked = r._call(
    $!Type{ void * }, r.reference, index,
    %(${c.cache_literal_list(target)} ${c._type_literal(target)}));
  storage_type = pointer;
  return c.convert_expression(picked, pointer);
}

static List FuncReaders._pointer(
  FuncReaders &r, Type parameter_type, Type resolved, int index,
  Type &storage_type) {
  Compiler c = r.c;
  /* A pointer without its own Var tag and a by-value record both arrive as
     `<p48>`; the latter is the address of the record's bytes. */
  Type pointer_type = NULL;
  List pointer_helper = c._adapter_helper(
    "x2c_func_pointer_argument", pointer_type);
  List picked = r._call(
    $!Type{ void * }, _func_bound(pointer_type, pointer_helper), index, NULL);
  storage_type = parameter_type;
  if (resolved.is_pointer())
    return c.convert_expression(picked, parameter_type);
  Type record_pointer = parameter_type.reference();
  List pointer = %(expr $record_pointer (cast $record_pointer $picked));
  return $!($parameter_type){ *$pointer };
}

static List FuncReaders._value(
  FuncReaders &r, Type parameter_type, Symbol tag, int index,
  Type &storage_type) {
  if (!tag)
    $report.callable.parameter(r.c, r.diagnostic_type, parameter_type);
  List picked = r._call(
    %("Var"), r.value, index, %(${_adapter_symbol_literal(tag)}));
  storage_type = parameter_type;
  return r.c.convert_expression(picked, parameter_type);
}

/* Call a resolved adapter reader without rebinding its typed arguments. */
static List FuncReaders._call(
  FuncReaders &r, Type result_type, List target, int index,
  List details) {
  List fn = $!Func{ ${r.fn} };
  List argv = $!(const FuncArg *){ ${r.argv} };
  List arguments = %($fn $argv ${x2c_literal_int(index)} @details);
  return r.c._func_call(result_type, target, arguments);
}

/* One emitted FuncAdapter ABI. Callers order context setup around argument
   locals; the ordinary helper body owner boxes results and preserves
   no-value returns. */
static void Compiler._publish_func_adapter(
  Compiler c, List binding, List fn_binding, List argv_binding,
  List body, List setup) {
  List parameters = _named_decl_params(
    %(("Func") (* const "FuncArg")), %($fn_binding $argv_binding));
  c.add_early(
    c.wrapper_function(
      %(static "Var"), binding, parameters.cdr(),
      c._helper_body(body, setup).cdr()));
}

static List Compiler._func_record_call(
  Compiler c, Type return_type, List call) {
  /* A record result is returned as `<p48>` to a copy of its bytes. */
  Type result_type = NULL;
  List result_helper = c._adapter_helper(
    "x2c_func_record_result", result_type);
  List result = c.sym.introduce(c.fresh_name("func_record"));
  List (base, mods) = return_type.declaration_parts();
  List value = _func_bound(return_type, result);
  Macro address_shape = $func_address, size_shape = $func_size;
  List address = c.rebuild_expression(
    return_type.reference(), address_shape(value));
  List size = c.rebuild_expression(%(unsigned long), size_shape(value));
  List helper = _func_bound(result_type, result_helper);
  List boxed = c._func_call(%("Var"), helper, %($address $size));
  Macro record = $func_record_result;
  List row = %(op = (bind $result $mods) $call);
  return c.rebuild_statement(record(base, row, boxed)).cadr();
}

/** Returns the canonical signature shared by native and meta Func adapters. */
List Compiler.func_signature(Compiler c, Type type) {
  List params = NULL;
  Type result = NULL;
  type.function_parts(params, result);
  Array declared = [];
  foreach (List parameter, params) declared.push(parameter.type().declared());
  List parameter_types = params ? declared.list_free() : %((void));
  Type declared_result = result.declared();
  return %((func $parameter_types) @declared_result);
}

static List Compiler._func_signature_literal(Compiler c, Type type) =>
  c.cache_literal_list(c.func_signature(type));

static List Compiler._type_literal(Compiler c, Type type) =>
  c.cache_literal_list(c.sym.normalize_declared_type(type));

static List _adapter_symbol_literal(Symbol value) =>
  %(expr ("Symbol") "${(unsigned long) value}");

static List Compiler._adapter_helper(Compiler c, String name, Type &type) =>
  c.sym.resolve_global(%($name), type);

/* The issued identity `binding` read as a `type`. */
static List _func_bound(Type type, List binding) => $!($type){ $binding };

static List Compiler._func_call(
  Compiler c, Type type, List callee, List arguments) {
  Macro shape = $called;
  return c.rebuild_expression(type, shape(callee, arguments));
}

static List Compiler._func_return_body(Compiler c, List value) {
  Macro shape = $return_value;
  return c.rebuild_statement(shape(value)).cdr();
}

// Build fresh binding identities a0..aN.
static List Compiler._auto_names(Compiler c, int count) {
  Array out = [];
  for (int index = 0; index < count; index++)
    out.push(c.sym.introduce(%"a$index"));
  return out.list_free();
}

// Produce typed parameters from types and their binding identities.
static List _named_decl_params(List types, List names) {
  List params = types.zip_with(
    names, %!(Type type, List name) => type.parameter_ast(name));
  return %(params @params);
}

// callback adapters

/* A direct function adapted to a callback signature. The helper converts
   each callback argument to the source parameter type, calls the source,
   and converts its result to the callback result. */
static typedef struct Callback {
  Compiler c;
  Type target, source, result, source_result;
  List params, source_params, source_binding;
} Callback;

/** Lowers a resolved `tadapt` expression to a typed callback helper.
    `expression` must have the resolved shape
    `(expr TARGET (tadapt ORIGIN (expr SOURCE (ident BINDING))))`.
    Compatible helpers are cached by source binding and target type, queued
    with `Compiler.add_early`, and returned as typed identifiers; other
    expressions pass through unchanged.
*/
List Compiler.lower_typed_adapter_expr(Compiler c, List expression) {
  match (expression)
    case %(expr ?spelling (tadapt ?at (expr ?source ?payload))): {
      Callback cb = {.c = c};
      cb.source = source;
      match (payload) case %(ident ?binding): cb.source_binding = binding;
      $let(c.origin, at) {
        cb.target = c.sym.resolve_key(spelling);
        cb.split();
        cb.check_signature();
        cb.check_params();
        return cb.publish_typed(spelling);
      }
    }
  return expression;
}

/* The source is a direct function, and both signatures are complete and
   fixed. */
static void Callback.split(Callback &c) {
  Type source = c.source;
  if (!c.source_binding || !source || source.is_pointer() ||
      !source.is_function())
    $report.callback.direct(c);
  if (!c.target.function_parts(c.params, c.result))
    $report.callback.target(c);
  if (!source.function_parts(c.source_params, c.source_result))
    $report.callback.source(c);
  if (_typed_params_variadic(c.params) ||
      _typed_params_variadic(c.source_params))
    $report.callback.variadic(c);
}

static void Callback.check_signature(Callback &cb) {
  int target_count = cb.params.len(), source_count = cb.source_params.len();
  // lint: allow one-statement-braces ST-1: macro emits declaration and call
  if (target_count != source_count) {
    $report.callback.arity(cb, target_count, source_count);
  }
  cb.result = cb.result.canonicalize();
  cb.source_result = cb.source_result.canonicalize();
  if (cb.result === %(void) || cb.source_result === %(void))
    $report.callback.void_return(cb);
  if (cb.result != cb.source_result)
    $report.callback.result(cb);
}

static void Callback.check_params(Callback &cb) {
  int index = 0;
  List targets = cb.params, sources = cb.source_params;
  for (; targets;
       targets = targets.cdr(), sources = sources.cdr(), index++) {
    Type target = targets.car();
    Type source = sources.car();
    if (cb._allows(target, source)) continue;
    $report.callback.parameter(cb, index, target, source);
  }
}

// Permit matching parameter types and one dynamic extraction.
static int Callback._allows(Callback &cb, Type target, Type source) {
  target = target.canonicalize();
  source = source.canonicalize();
  if (target == source) return 1;
  with cb.c.sym {
    if (_.is_var_type(target) && _.is_var_type(source)) return 1;
    if (!_.is_var_type(target)) return 0;
    if (_.is_named_value_type(source, "Symbol")) return 1;
    return _.resolve_key(source).is_pointer();
  }
}

static void Callback._fail(Callback &cb, String message, List details) {
  cb.c._adapter_error(message, cb.target, cb.source, details);
}

static List Callback.publish_typed(Callback &cb, Type spelling) {
  Compiler c = cb.c;
  List key = %(tadapt ${cb.source_binding} ${cb.target}), binding = NULL;
  $adapter.memo(c, key, binding) {
    binding = c.sym.introduce(c.fresh_name("callback_adapt"));
    List function = cb.function(binding);
    c.set_fact(%(function $binding), 1);
    c.add_early(function);
  }
  return _func_bound(spelling, binding);
}

/* The helper `binding` names: each argument converts to its source
   parameter, and the source result converts to the callback result. */
static List Callback.function(Callback &cb, List binding) {
  Compiler c = cb.c;
  (List declarations, List arguments) = c.forward_parameters(cb.params);
  List source = $!(${cb.source}){ ${cb.source_binding} };
  List call = c._func_call(
    cb.source.apply().canonicalize(), source, arguments);
  List body = cb.result === %(void) ? %((stmnt $call))
    : %((return ${cb.result} ${c.convert_expression(call, cb.result)}));
  return c.wrapper_function(
    %(static @{cb.result}), binding, declarations, body);
}

/** Adapts a lowered noncapturing lambda helper to a typed callback.
    `argument` must be a resolved helper reference produced by
    `Compiler.lower_lambda_expr`, optionally wrapped in parentheses.
    `expected_type` must describe a fixed, nonvariadic function. Unless its
    parameters and result are already `Var`,
    a queued static helper converts callback arguments to the lowered lambda's
    original parameter types before calling it, then converts its `Var` result
    to the expected return type. Already compatible or unsupported shapes pass
    through unchanged.
*/
List Compiler.adapt_lambda_arg(Compiler c, List argument, List expected_type) {
  Callback cb = {.c = c, .target = expected_type};
  match (argument) {
    case %(expr ? ${$grouped(?inner)}): {
      List adapted = c.adapt_lambda_arg(inner, expected_type);
      if (adapted == inner) return argument;
      Macro grouped = $grouped;
      return c.rebuild_expression(expected_type, grouped(adapted));
    }
    case %(expr ?type ${$source_identifier_content(%(?binding))}): {
      cb.source = type;
      cb.source_binding = binding;
    }
    default: return argument;
  }
  List raw_params = NULL, Var return_type = void;
  if (!_lambda_adapter_signature(expected_type, raw_params, return_type) ||
      _typed_params_variadic(raw_params))
    return argument;
  int all_var = _collect_param_types(raw_params, cb.params);
  List source_params = NULL;
  cb.source.function_parts(source_params, NULL);
  _collect_param_types(source_params, cb.source_params);
  List result = return_type is <list> ? return_type : %( $return_type );
  if (all_var && result === %("Var")) return argument;
  cb.result = result;
  return cb.publish_lambda();
}

static List Callback.publish_lambda(Callback &cb) {
  Compiler c = cb.c;
  List binding = c.sym.introduce(c.fresh_name("lambda_adapt"));
  c.add_early(cb.function(binding));
  return _func_bound(cb.target, binding);
}

static int _lambda_adapter_signature(
  List expected_type, List &raw_params, Var &return_type) {
  Type expected = expected_type;
  List signature = expected.canonicalize();
  match (signature) case %((!or (!quote *) & ^) *rest): signature = rest;
  match (signature)
    case %((func (*parameters)) ?return_head *): {
      raw_params = parameters;
      return_type = return_head;
      return 1;
    }
  return 0;
}

static int _collect_param_types(List raw_params, List &out_types) {
  Array types = [], int all_var = 1;
  foreach(Var entry, raw_params) {
    Var ptype = entry;
    match (entry)
      case %(param ? ?): ptype = entry.list().type_from_ast();
    List ptype_list = ptype is <list> ? ptype : %( $ptype );
    types.push(ptype_list);
    if (all_var && ptype_list != %("Var")) all_var = 0;
  }
  out_types = types.list_free();
  return all_var;
}

static int _typed_params_variadic(List params) {
  foreach(Var value, params) {
    if (value == <...>) return 1;
    match (value) case %(...): return 1;
  }
  return 0;
}

static void Compiler._adapter_error(
  Compiler c, String message, Type target, Type source, List details) {
  String target_note = $callable.note.target(target);
  String source_note = $callable.note.source(source);
  c.report_error(<type>, message, NULL, %($target_note $source_note @details));
}
