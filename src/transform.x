/*  transform.x -- x2c AST transformation pipeline

    Lowers typed expressions, literals, and statements into the AST forms
    consumed by C emission. One recursive normalizer rewrites each node
    where it is produced, and children enter the same operation, so a unit
    is walked once. `callables.x` lowers the lambdas and `Func` conversions
    it meets, and `cleanup.x` lowers each completed function's cleanup
    regions. The active Compiler reports errors.
*/

#pragma once

/* CPP ignores pragma once in its main input. Define the cycle guard only
   during symbol preprocessing, so generated C keeps its declarations. */
#ifndef X2C_TRANSFORM_SOURCE
#ifdef X2CCPP
#define X2C_TRANSFORM_SOURCE
#endif

#include "compiler.x"

#include "ast-rewrite.x"
#include "meta.x"
#include "grammar.x"

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
#include "cleanup.x"

/* transform diagnostics. */

static macro Stmt $report.xform.slice_unsupported(
  Expr $c, Expr $type, Expr $notes) =>
  $c.report_error(
    <xform>, %"type ${$type} does not support slicing",
    NULL, $notes);

static macro Stmt $report.type.destructure_list(Expr $c, Expr $source_type) =>
  $c.report_error(
    <type>, "destructuring requires a List source",
    NULL, %(("source type" ${$source_type})));

static macro Stmt $report.xform.slice_assignment(Expr $c) =>
  $c.report_error(
    <xform>, "slice expressions are not assignable",
    NULL, %("call the collection's setslice method explicitly"));

static macro Stmt $report.xform.string_compound(Expr $c) =>
  $c.report_error(
    <xform>, "String compound assignment supports only String +=",
    NULL, NULL);

static macro Stmt $report.xform.container_compound(Expr $c, Expr $lhs_type) {
  {
    String type = $lhs_type.repr();
    $c.report_error(
      <xform>, %"container type $type does not support compound assignment",
      NULL, %("update an indexed element instead"));
  }
}

// normalization

/** Lowers a bound and typed top-level AST to the normalized form consumed by
    emission. `c` must own the AST's bindings, origins, and conversion
    state. Current-node rewrites finish before child traversal; containing
    blocks absorb cleanup markers produced by declaration rewrites. Pending
    support declarations are lowered and appended after the input units. Their
    storage determines their interface visibility. The call may add
    generated origins or diagnostics to `c`.
*/
List Compiler.transform(Compiler c, List ast) {
  /* Regions are read before lowering, while `$scope`, `$auto`, and the
     `defer` beside each region are still the forms the parser produced. */
  c.check_regions(ast);
  List newast = c._sequence(ast, 0);
  // Merge and lower synthesized lambda siblings.
  Array generated = [], support = c.pending.area(<support>);
  while (support) {
    List items = support;
    support.clear();
    foreach (Var sibling, c._sequence(items, 0)) generated.push(sibling);
  }
  if (generated) newast = newast.append(generated.list_free());
  return newast;
}

/** Normalizes one bound and typed node. Newly constructed syntax is
    normalized where it is produced; children enter the same operation, so
    completed units do not require another unit walk.
*/
Ast Compiler.normalize(Compiler c, Ast ast) => c._step(ast);

static Ast Compiler._step(Compiler c, Ast ast) {
  if (!ast) return NULL;
  if (c.slot_watch) {
    Ast watched = c.watched_step(ast);
    if (watched) return watched;
  }
  Var head = ast.car();
  if (head is not <symbol>) return c._default_node(ast);
  match (ast) {
    case %(at ?origin ?inner): return c._at_node(ast, origin, inner);
    case %(function ?return_type
           (!set ?declarator (bind ?binding ?)) ?body):
      return c._function_node(ast, return_type, declarator, binding, body);
    case %(slice
           (!set ?expression
             (expr (!set ?matched_type (*)) ?))
           ?start ?stop ?step):
      return c._slice_node(expression, matched_type, start, stop, step);
  }
  return c._step_tag(ast, head);
}

// Tag-only lowering does not retain the typed-pattern capture buffer.
static Ast Compiler._step_tag(Compiler c, Ast ast, Symbol tag) {
  Ast next = ast;
  switch (tag) {
    case <protocol>: case <adopt>: case <macrodef>: case <literal>:
      return ast;
    case <expr>: return c._expression_node(ast);
    case <array>: case <varray>: case <map>: case <vmap>:
      return c._collection_literal(ast, tag);
    case <cast>: next = c._cast(ast); break;
    case <index>: next = c._index(ast); break;
    case <cons>: case <append>: return c._ordered_list(ast);
    case <var>: next = c._to_var(ast.cadr()); break;
    case <segments>: next = c._string_segments(ast); break;
    case <declare>: case <decl>: next = c._declaration(ast); break;
    case <dstrdecl>: next = c._destructure_declaration(ast); break;
    case <stmnt>: next = c._destructure_statement(ast); break;
    case <dstrasgn>: next = c._destructure_value(ast); break;
    case <match>: next = c._match_cases(ast); break;
    case <defer>: next = c._defer_node(ast); break;
    case <return>: next = c._return(ast); break;
    case <raise>: return c._raise_node(ast);
    case <switch>: next = c._statement_rewrite(ast, tag); break;
    case <if>: case <while>: case <do>: case <for>:
      next = c._truthy(ast); break;
    case <call>: next = c._call(ast); break;
    case <op>: next = c._operator(ast); break;
    case <postfix>: next = c._postfix(ast); break;
    default: return c._default_node(ast);
  }
  if (next != ast) return c._step(next);
  return c._default_node(ast);
}

/* Ordinary registered patterns may replace a typed statement. */
static Ast Compiler._statement_rewrite(Compiler c, Ast ast, Symbol tag) {
  List rewritten = c.rewrite_rules ? c.lower_rewrite(
    <node>, tag, ast, AST_STATEMENT, c.return_type, NULL) : NULL;
  return rewritten ? rewritten : ast;
}

static Ast Compiler._default_node(Compiler c, Ast ast) {
  Var head = ast.car();
  if (head == <seq> || head == <matchcases> ||
      head == <parens> || head == <block>) return c._finish(ast);
  return c._children(ast);
}

/* Normalize synthesized sequences before their containing block absorbs
   pending defer markers. Matches retain their specialized record driver. */
static Ast Compiler._finish(Compiler c, Ast ast) {
  match (ast) {
    case %(seq *items):
      return %(seq @{c._sequence(items, 0)});
    case %(matchcases ?subject ?records): {
      List new_subject = c._step(subject);
      List new_records = c._match_records(records);
      return %(matchcases $new_subject $new_records);
    }
    case %(parens (at ?origin ?inner)):
      return c._step(%(at $origin (parens $inner)));
    case %(parens (block *body)):
      return %(parens ${c._block_node(body, 1)});
    case $source_block_content(%(*body)): return c._block_node(body, 0);
  }
  return c._children(ast);
}

/* Only top-level and block sequences absorb `(seq ...)` replacements.
   Children transform left to right, then reverse assembly preserves source
   order while allocating generated splice origins from right to left. */
static Ast Compiler._sequence(Compiler c, Ast ast, int value_tail) {
  Array transformed = $auto([]);
  for (List cursor = ast; cursor; cursor = cursor.cdr())
    transformed.push(
      c._sequence_item(cursor.car(), value_tail && !cursor.cdr()));
  Ast tail = NULL;
  for (int i = (int) transformed.len() - 1; i >= 0; i--)
    tail = c._sequence_tail(transformed[i], tail);
  return tail;
}

static Ast Compiler._sequence_item(Compiler c, Ast value, int value_tail) {
  Ast lowered;
  match (Ast.without_origin(value)) {
    case %(stmnt ?expr) if (value_tail):
      lowered = c._statement_value(value, expr);
    case %(defer ?): lowered = value;
    default: lowered = c._step(value);
  }
  if (!c.fn_name) lowered = c.lower_cleanup(lowered);
  return lowered;
}

static Ast Compiler._statement_value(Compiler c, Ast value, Var expression) {
  Ast result = c._step(Ast.rewrap_origin(value, expression));
  return Ast.rewrap_origin(result, %(stmnt ${Ast.without_origin(result)}));
}

static Ast Compiler._sequence_tail(Compiler c, Ast node, Ast tail) {
  match (node) {
    case %(at ?parent ?): return c._anchored_sequence(node, tail, parent);
    case %(seq *items): return items.append(tail);
  }
  return cons(node, tail);
}

static Ast Compiler._anchored_sequence(
  Compiler c, Ast node, Ast tail, Var parent) {
  match (Ast.without_origin(node))
    case %(seq *items): return c._splice_items(items, parent).append(tail);
  return cons(node, tail);
}

static List Compiler._splice_items(Compiler c, List items, Var parent) {
  Array anchored = [];
  foreach (List item, items) {
    c.origins.push(%(generated $parent splice));
    int generated = c.origins.len();
    anchored.push(%(at $generated $item));
  }
  return anchored.list_free();
}

static Ast Compiler._children(Compiler c, Ast ast) {
  List child;
  $ast.rewrite_children(ast, child, c._step(child));
}

static List Compiler._match_records(Compiler c, List records) {
  Array transformed = [];
  foreach (List record, records)
    match (record) {
      case %(preproc ?): transformed.push(record);
      case %(?binders ?pattern ?body): {
        List lowered = c._step(pattern);
        transformed.push(%($binders $lowered ${c._step(body)}));
      }
    }
  return transformed.list_free();
}

/* node rewrites

   Callers supply bound, typed canonical nodes, and each helper builds the
   normalized shape the emitter consumes. A helper rewrites only its current
   node: `_step` recurses into returned children, while `_sequence` alone
   splices `(seq ...)` results into a sequence. */

/* A position wrapper lowers its node at that origin, and a changed node
   gets a generated origin. */
static Ast Compiler._at_node(Compiler c, Ast ast, int occurrence, List inner) {
  List transformed = NULL;
  $let(c.origin, occurrence) {
    transformed = c._step(inner);
  }
  if (transformed == inner) return ast;
  c.origins.push(%(generated $occurrence xform));
  int generated = c.origins.len();
  return %(at $generated $transformed);
}

/* A function rule sees the bound and typed definition before its body
   lowers. Rules keyed by its return type come before those keyed by none. */
static List Compiler._function_rewrite(
  Compiler c, List function, List return_type) {
  List replaced = c.lower_rewrite(
    <function>, return_type, function, AST_UNIT, NULL, NULL);
  return replaced ? replaced : c.lower_rewrite(
    <function>, <any>, function, AST_UNIT, NULL, NULL);
}

static Ast Compiler._function_node(
  Compiler c, List function, List return_type, List declarator,
  List binding, List body) {
  List replaced = c._function_rewrite(function, return_type);
  if (replaced) return replaced;
  String owner = binding_identity_spelling(binding);
  Var stored_owner;
  if (c.semantic_binding_facts().try_get(%(defer-ownr $binding), stored_owner))
    owner = stored_owner;
  Type function_type = return_type;
  int inline_header = function_type.is_inline() && !function_type.is_static();
  List transformed;
  $let(c.fn_name, owner) $let(c.inline_header, inline_header) {
    List new_return = c._step(return_type);
    List new_decl = c._step(declarator);
    List prepared_body = c._lower_lambda_destructuring(body);
    prepared_body = c.prepare_lambda_cells(declarator, prepared_body);
    List new_body = c._step(prepared_body);
    transformed = %(function $new_return $new_decl $new_body);
  }
  return transformed;
}

static Ast Compiler._slice_node(
  Compiler c, List expression, Type type, List start, List stop, List step) {
  String nominal = NULL;
  match (type)
    case %(?(String name)): nominal = name;
  if (!nominal)
    $report.xform.slice_unsupported(c, type, NULL);
  String fnname = %"${nominal}_getslice";
  if (!c.sym.get(%($fnname)))
    $report.xform.slice_unsupported(c, type, %());
  String none = "-2147483648";
  start = start ? start : %(literal (int) $none);
  stop = stop ? stop : %(literal (int) $none);
  step = step ? step : %(literal (int) "1");
  return c._step(%(call "$fnname" (args $expression $start $stop $step)));
}

/* Access admission has established the getter signature, but its target is
   still intact here. Dispatch before lowering a read or an enclosing
   update. */
static List _access_source(List expression) {
  match (expression) {
    case %(expr ?type (getindex ?base ?key)):
      return %(expr $type (index $base $key));
    case %(expr ?type (parens ?inner)):
      return %(expr $type (parens ${_access_source(inner)}));
  }
  return expression;
}

/* Access and call rules see a typed expression before its children lower.
   A call is keyed by the spelling of its callee. */
static List Compiler._expression_rewrite(Compiler c, List expression) {
  if (!c.rewrite_rules) return NULL;
  Symbol point = <access>;
  Var kind = 0;
  List source = expression;
  match (expression) {
    case %(expr ? (call (expr ? (ident ?binding)) ?)): {
      point = <call>;
      kind = binding_identity_spelling(binding);
    }
    case %(expr ? (getindex ? ?)): {
      kind = <read>;
      source = _access_source(expression);
    }
    case %(expr ?type (op ?operator ?left ?right)):
      if (operator.symbol().is_assignment_op()) {
        List target = _access_source(left);
        if (target == left) return NULL;
        kind = operator;
        source = source_operator_expression(type, %($operator $target $right));
      }
    case %(expr ?type (op (!set ?operator (!or ++ --)) ?operand)): {
      List target = _access_source(operand);
      if (target == operand) return NULL;
      kind = <prefix>;
      source = source_operator_expression(type, %($operator $target));
    }
    case %(expr ?type (postfix ?operator ?operand)): {
      List target = _access_source(operand);
      if (target == operand) return NULL;
      kind = <postfix>;
      source = source_postfix_expression(type, %($operator $target));
    }
  }
  return kind ? c.lower_rewrite(
    point, kind, source, AST_EXPRESSION, expression.cadr(), NULL) : NULL;
}

static Ast Compiler._expression_node(Compiler c, Ast ast) {
  Var content = ast.caddr();
  if (content is <list> && content.list().car() == <var>)
    return c._step(c._to_var(content.list().cadr()));
  List rewritten = c._expression_rewrite(ast);
  if (rewritten) return rewritten;
  Ast expression = c.lower_typed_adapter_expr(ast);
  expression = c.lower_lambda_expr(expression);
  if (_op_chain_first(expression)) return c._op_chain(expression);
  if (expression != ast) return c._step(expression);
  return c._default_node(expression);
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

static Ast Compiler._op_chain(Compiler c, Ast ast) {
  Array levels = $auto([]);
  Array types = $auto([]);
  Ast rebuilt = NULL;
  for (;;) {
    List first = _op_chain_first(ast);
    if (!first) {
      rebuilt = c._finish(ast);
      break;
    }
    Var type = ast.cadr();
    if (type is <list>) type = c._step(type);
    List opnode = ast.caddr();
    List rewritten = c._operator(opnode);
    if (rewritten != opnode) {
      rebuilt = %(expr $type ${c._step(rewritten)});
      break;
    }
    types.push(type);
    levels.push(ast);
    ast = c.lower_typed_adapter_expr(first);
    ast = c.lower_lambda_expr(ast);
  }
  for (int i = (int) levels.len() - 1; i >= 0; i--)
    match (levels[i].caddr())
      case $source_operator_content(%(?operator ? *rest)): {
        Array parts = [];
        if (operator is <list>) parts.push(c._step(operator));
        else parts.push(operator);
        parts.push(rebuilt);
        foreach (Var operand, rest) {
          if (operand is <list>) parts.push(c._step(operand));
          else parts.push(operand);
        }
        rebuilt = source_operator_expression(types[i], parts.list_free());
      }
  return rebuilt;
}

static Ast Compiler._defer_node(Compiler c, Ast ast) {
  match (ast)
    case %(defer ?finalizer):
      return c.lower_defer_region(source_block_content(%()), finalizer);
  return ast;
}

/* A value block lowers its final expression as a value, including an
   assignment whose ordinary statement form discards its result. */
static Ast Compiler._block_node(
  Compiler c, List statements, int value_tail) {
  List body = c.rewrite_defer_list(statements);
  List lowered = c._sequence(body, value_tail);
  List deferred = c.rewrite_defer_list(lowered);
  if (deferred != lowered) lowered = c._sequence(deferred, value_tail);
  return source_block_content(lowered);
}

static Ast Compiler._raise_node(Compiler c, Ast ast) {
  // Raise details intern at raise time, never in constructors.
  $let(c.runtime_literals, 1) {
    match (ast)
      case %(raise ?cause (args *arguments)):
        ast = c._raise(ast, cause, arguments);
    ast = c._children(ast);
    match (ast)
      case %(raise ?cause (args *arguments)):
        ast = c._ordered_raise(cause, arguments);
  }
  return ast;
}

// collection literals

/* A collection literal lowers through the literal rule for its head. The
   constructor call that rule returns receives the literal's parts as its
   `Var` arguments, or as C values with no x2c type, which pass as `Var`;
   they keep their source order. */
static Ast Compiler._collection_literal(Compiler c, Ast ast, Symbol tag) {
  int map = tag == <map> || tag == <vmap>;
  Type type = map ? %("Map") : %("Array");
  Symbol head = map ? <map> : <array>;
  List lowered = c.lower_rewrite(
    <literal>, head, %(expr $type ($head @{ast.cdr()})), AST_EXPRESSION,
    type, NULL);
  match (lowered) case %(expr ? (call ?callee (args *arguments))): {
    Array values = $auto([]), orders = $auto([]);
    foreach (List argument, arguments) {
      Type passed = argument.cadr();
      values.push(argument);
      orders.push(!passed || passed == %("Var") ? c._part_order(argument) : 0);
    }
    List declarations = c._ordered_parts(values, orders);
    if (declarations) {
      List call = %(call $callee (args @{values.list()}));
      return c._step(_ordered(declarations, type, call));
    }
  }
  return lowered.caddr();
}

static List Compiler._to_list(Compiler c, List expr) =>
  c.convert_expression(expr, %("List"));

static List Compiler._spliced(Compiler c, List expr) {
  if (c.sym.is_var_type(expr.cadr()))
    return %(expr ("List") (call "Var_list" (args $expr)));
  return c._to_list(expr);
}

/* literal order

   A literal evaluates its parts once each, left to right, though C leaves
   the order of its constructor's arguments unspecified. Once two or more
   parts read state, each part that reads state, through the last one that
   may change state, moves into a temporary. A part's order is 0 when it is
   constant, 1 when it only reads state, and 2 when it may change state. A
   builtin boxer or scalar formatter reads what its argument reads. Custom
   converters and dynamic nested literal construction may change state. */
static int Compiler._part_order(Compiler c, Var part) {
  if (part is not <list>) return 0;
  List node = part;
  match (node) {
    case %(!or (cache ?) (literal *) (nil) (segraw ?)): return 0;
    case %(expr () (ident ?)): return 2;
    case $source_identifier_content(%(?)): return 1;
    case %(cons ?head ?tail):
      return c._part_order(head) || c._part_order(tail) ? 2 : 0;
    case %(expr ? (call ? (args ?argument))):
      return c.is_builtin_converter_call(node)
        ? c._part_order(argument) : 2;
    case %(!or (expr ? ?inner) (cast ? ?inner) ((!or segvar segexp) ?inner)
        ${$grouped(?inner)}):
      return c._part_order(inner);
    case $source_operator_content(%((!or . (!quote ->)) ?inner ?)): {
      int order = c._part_order(inner);
      return order > 1 ? order : 1;
    }
  }
  return 2;
}

/* The number of leading parts that move, or zero. */
static int _ordered_count(Array orders) {
  int reads = 0, count = 0;
  for (int i = 0; i < orders.len(); i++) {
    int order = orders[i];
    if (order) reads++;
    if (order > 1) count = i + 1;
  }
  return reads < 2 ? 0 : count;
}

/* Moves the parts that need it into temporaries and returns their
   declarations, or NULL when the parts stay in place. */
static List Compiler._ordered_parts(Compiler c, Array values, Array orders) {
  int count = _ordered_count(orders);
  if (!count) return NULL;
  Array declarations = [];
  for (int i = 0; i < count; i++)
    if ((int) orders[i])
      values[i] = c._sequenced(
        _passed_as(values[i], %("Var")), "literal_part", declarations);
  return declarations.list_free();
}

static List _ordered(List declarations, Type type, List content) =>
  declarations ? _statement_expression(declarations, %(expr $type $content))
               : content;

/* A List chain's parts are its cons heads and spliced Lists in source
   order, then its final tail. Convert before classifying each part, so an
   implicit custom converter participates in the same ordering as a call. */
static List Compiler._ordered_list(Compiler c, List chain) {
  Array kinds = $auto([]), values = $auto([]), orders = $auto([]);
  List node = chain;
  for (List cell = _list_cell(node); cell; cell = _list_cell(node)) {
    (Symbol kind, List part, List rest) = cell;
    List value = kind == <cons> ? c._to_var(part)
      : _passed_as(c._spliced(part), %("List"));
    value = c._step(value);
    kinds.push(kind);
    values.push(value);
    orders.push(c._part_order(value));
    node = rest;
  }
  node = c._step(_passed_as(c._to_list(node), %("List")));
  kinds.push(<nil>);
  values.push(node);
  orders.push(c._part_order(node));
  List declarations = c._ordered_parts(values, orders);
  List rebuilt = values.take_last();
  for (int i = (int) values.len() - 1; i >= 0; i--)
    rebuilt = %(expr ("List") (${kinds[i]} ${values[i]} $rebuilt));
  return _ordered(declarations, %("List"), rebuilt.caddr());
}

static List _list_cell(List node) {
  match (node) {
    case %((!or cons append) ? ?): return node;
    case %(expr ? (!set ?cell ((!or cons append) ? ?))): return cell;
  }
  return NULL;
}

// casts and bracket reads

static List Compiler._cast(Compiler c, List ast) {
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
        return c.convert_compound_literal(operand, type, native);
      }
      int source_var = c.sym.is_var_type(source_type);
      int target_var = c.sym.is_var_type(type);
      int unresolved = 0;
      match (expression)
        case %(expr () ${$source_identifier_content(%(?name))}):
          unresolved = 1;
      int target_func = source_type &&
        c.sym.resolve_key(type) === c.sym.resolve_key(%("Func"));
      if (type !== %(void) &&
          (source_var || target_func ||
           (target_var && (source_type || unresolved))))
        return c.convert_expression(expression, type);
      return %(cast $type $expression);
    }
  match (ast)
    case $source_cast_content(%(?target (!set ?value (expr ? (composite *))))):
      return c.convert_compound_literal(value, target, target);
  return ast;
}

// A `Var` subscript of a native pointer or array reads as an integer.
static List Compiler._index(Compiler c, List ast) {
  Macro indexed = $indexed;
  match (ast)
    case ${$indexed(?base, %(!set ?selector (expr ?type ?)))}
        if (c.sym.is_var_type(type)): {
      List converted = c.convert_expression(selector, %(long));
      return c.rebuild_expression(NULL, indexed(base, converted)).caddr();
    }
  return ast;
}

// interpolated strings

static List Compiler._string_segments(Compiler c, List ast) {
  /* A lone constant segment is already the whole string. Reuse the parsed
     literal's cache slot instead of joining a one-element List at runtime.
     Macro-generated literals arrive in this shape. Raise details are
     excluded: their cache slots would fill inside _file_init_ constructors,
     where re-entrant string-pool bootstrap can hand back NULL Strings. */
  match (ast) {
    case $source_string_content(
        %((segexp (expr ("String") (literal ("String") ?text))))):
      if (!c.runtime_literals)
        return c.cache(%(string (expr ("String") (literal ("String") $text))));
  }
  Array values = [], orders = $auto([]);
  foreach (List seg, ast.cdr()) {
    List value = c._step(c._segment_value(seg));
    values.push(value);
    orders.push(c._part_order(value));
  }
  List declarations = c._ordered_parts(values, orders);
  int segment_count = values.len();
  List joined = c._join_segments(values.list_free(), segment_count);
  return _ordered(declarations, %("String"), joined);
}

static List Compiler._join_segments(
  Compiler c, List segments, int segment_count) {
  // Keep nested cons expressions below host-C bracket-depth limits.
  if (segment_count <= 128) {
    segments = _build_cons_list(segments);
    return %("String_join(NULL, " (expr ("List") $segments) ")");
  }
  String count = %"${segment_count}U";
  Type signature = NULL;
  List binding = c.sym.reference(%("List_list_n"), signature);
  List list = %(expr ("List")
    (call (expr $signature (ident $binding))
          (args (expr (unsigned) (literal (unsigned) $count)) @segments)));
  return %("String_join(NULL, " $list ")");
}

static List Compiler._segment_value(Compiler c, List seg) {
  Symbol kind = seg.car();
  switch (kind) {
    case <segraw>: seg = c._process_raw_segment(seg); break;
    case <segvar>:
    case <segexp>: seg = c.convert_segment_to_string(seg.cadr()); break;
    case <cache>: seg = %(expr ("String") $seg); break;
  }
  return c.convert_expression(seg, %("Var"));
}

static List _build_cons_list(List list) {
  if (!list) return %(nil);
  List head = list.car(), tail = _build_cons_list(list.cdr());
  return %(cons $head $tail);
}

static List Compiler._process_raw_segment(Compiler c, List seg) {
  String raw = seg.cadr(), literal = %"\"${raw.escape()}\"";
  List constructor = c.sym.reference(%("String_new"), NULL);
  return %(expr ("String") (call
           (expr ((func ((* char))) "String") (ident $constructor))
           (args (expr (* char) (literal (* char) $literal)))));
}

// declarations and statements

static macro Stmt $destructure_typed_target(
    Type $type, DeclaratorRow $row, Expr $value) {
  $type $row = $value;
}

static macro Stmt $destructure_sequence(Stmt @items) {
  @items
}

static macro Stmt $destructure_declarations(
    Name $temporary, Expr $source, Stmt @assignments) {
  List $temporary = $source;
  @assignments
}

static List Compiler._declaration(Compiler c, List ast) {
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
            List native_target = $!($target_type){ $var };
            List converted = c.convert_initializer(
              rhs, target_type, native_target);
            new_bind = %(op = (bind $var $mods) $converted);
            if (target_type.type().is_static())
              match (converted)
                case %(expr ("Func")
                       (ident (!set ?dependency (binding ? ?)))):
                  c.static_init_deps[var] = %($dependency);
          }
        values.push(new_bind);
      }
      List new_bindings = values.list_free();
      return %($head $target (bindings @new_bindings));
    }
  }
  return ast;
}

static List Compiler._destructure_declaration(Compiler c, List ast) {
  match (ast) {
    case %(dstrdecl ?type (targets *targets)
                    (!set ?source (expr ?source_type ?))):
      return c._named_destructure(type, targets, source, source_type);
    case %(dstrdecl (params *parameters)
                    (!set ?source (expr ?source_type ?))):
      return c._typed_destructure(parameters, source, source_type);
  }
  return ast;
}

/* Cell rewriting needs declaration sites, so lower destructuring
   with its existing transformation before analyzing a function body. */
static List Compiler._lower_lambda_destructuring(Compiler c, List ast) {
  if (!ast) return ast;
  match (ast) {
    case %(dstrdecl *):
      return c._destructure_declaration(ast);
  }
  // The recursion below then only descends into subtrees it will rewrite.
  if (!ast_contains_head(ast, <dstrdecl>)) return ast;
  return Ast.rewrite_children(
    ast, %!(List child) => c._lower_lambda_destructuring(child));
}

// A discarded destructuring result retains its own block scope.
static List Compiler._destructure_statement(Compiler c, List ast) {
  match (ast) {
    case %(stmnt (expr ?
             (dstrasgn (targets *targets)
                       (!set ?source (expr ?source_type ?))))): {
      List temporary = c.sym.introduce(c.fresh_name("destructure"));
      return c.bind_syntax(
        $!{
          {
            List $temporary = ${c._destructure_source(source, source_type)};
            @{c._destructure_assignments(targets, temporary)}
          }
        }, AST_BLOCK, c.return_type);
    }
  }
  return ast;
}

/* Keep the source's exact static type and value in one result temporary,
   then convert it to List once for the left-to-right assignments. */
static List Compiler._destructure_value(Compiler c, List ast) {
  match (ast) {
    case %(dstrasgn (targets *targets)
                    (!set ?source (expr ?type ?))): {
      List result = c.sym.introduce(c.fresh_name("destructure_result"));
      List temporary = c.sym.introduce(c.fresh_name("destructure"));
      List result_expr = $!($type){ $result };
      List converted = c._destructure_source(result_expr, type);
      List assignments = c._destructure_assignments(targets, temporary);
      Macro shape = macro Expression(
        Type $type, Name $result, Expr $source, Name $temporary,
        Expr $converted, Stmt @assignments) => ({
        $type $result = $source;
        List $temporary = $converted;
        @assignments
        $result;
      });
      List bound = c.bind_syntax(
        shape(
          type, result, %(code-value "bound" $source ()),
          temporary, converted, assignments),
        AST_EXPRESSION, NULL);
      return bound.caddr();
    }
  }
  return ast;
}

static List _value_declaration(Type type, List binding, List value) {
  (List base, List mods) = type.declaration_parts();
  return value
    ? %(declare $base (bindings (op = (bind $binding $mods) $value)))
    : %(declare $base (bindings (bind $binding $mods)));
}

// Keep parser-bound targets out of rebinding so their names retain scope and
// emitted identity; bind only the new temporary and unbound writes.
static List Compiler._named_destructure(
  Compiler c, Type type, List targets, List source, Type source_type) {
  List temporary = c.sym.introduce(c.fresh_name("destructure"));
  Array declarations = [], expressions = [];
  foreach (List ident, targets) {
    declarations.push(%(bind $ident ()));
    expressions.push($!($type){ $ident });
  }
  List target_decl =
    c.rebuild_statement($!{ $type @{declarations.list_free()}; }).cadr();
  List assignments = c._destructure_assignments(
    expressions.list_free(), temporary);
  Macro shape = $destructure_declarations;
  List tail = c.bind_syntax(
    shape(temporary, c._destructure_source(source, source_type), assignments),
    AST_BLOCK, c.return_type);
  Macro sequence = $destructure_sequence;
  return c.rebuild_statement(sequence(cons(target_decl, tail.cdr())));
}

static List Compiler._typed_destructure(
  Compiler c, List parameters, List source, Type source_type) {
  List temporary = c.sym.introduce(c.fresh_name("destructure"));
  Array declarations = [];
  int index = 0;
  Macro target_shape = $destructure_typed_target;
  foreach (List parameter, parameters) match (parameter) {
    case %(param ?type ?bind): {
      List value = _destructure_element(temporary, index++);
      declarations.push(
        c.rebuild_statement(target_shape(type, bind, value)).cadr());
    }
  }
  Macro shape = $destructure_declarations;
  List temp = c.bind_syntax(
    shape(temporary, c._destructure_source(source, source_type)),
    AST_BLOCK, c.return_type);
  Macro sequence = $destructure_sequence;
  return c.rebuild_statement(sequence(cons(temp, declarations.list_free())));
}

static List Compiler._destructure_source(
  Compiler c, List source, Type source_type) {
  // An integer, floating, or enumeration source cannot destructure. Reject
  // it before converting so the report names the construct the user wrote;
  // convert_expression would instead diagnose an integer reaching a
  // pointer.
  if (c.sym.resolve_numeric_type(source_type.canonicalize()))
    $report.type.destructure_list(c, source_type);
  List converted = c.convert_expression(source, %("List"));
  Type converted_type = NULL;
  match (converted)
    case %(expr ?type ?): converted_type = type;
  if (!c.sym.is_named_value_type(converted_type, "List"))
    $report.type.destructure_list(c, source_type);
  return %(code-value "bound" $converted ());
}

// Read one element from the issued List temporary.
static List _destructure_element(List temporary, int index) {
  String text = %"$index";
  return %(expr ("Var")
           (getindex (expr ("List") (ident $temporary))
                     (literal (int) $text)));
}

// Preserve typed targets, including the indirection of mutable lambda
// captures, while constructing their writes in source order.
static List Compiler._destructure_assignments(
  Compiler c, List targets, List temporary) {
  int index = 0;
  return targets.map(
    %!(List target) using &index => {
      match (target)
        case %(expr ?type ?): {
          List expression =
            $!($type){ $target = ${_destructure_element(temporary, index++)} };
          return c._as_statement(expression);
        }
    });
}

static List Compiler._as_statement(Compiler c, List expression) {
  Macro shape = $expression_statement;
  return c.rebuild_statement(shape(expression)).cadr();
}

// (match expr ((pattern body) ...))
static List Compiler._match_cases(Compiler c, List ast) {
  List (expr, cases) = ast.cdr();
  expr = c.convert_expression(expr, %("List"));
  Array values = [];
  foreach (List rec, cases) {
    if (rec.car() == <preproc>) values.push(rec);
    else
      values.push(%(${c.match_pattern_binders(rec.car(), NULL)} @rec));
  }
  List result = values.list_free();
  return %(matchcases $expr $result);
}

static List Compiler._return(Compiler c, List ast) {
  Macro returned = $return_value;
  match (ast)
    case returned(?expression): {
      List value = c.convert_expression(expression, source_return_type(ast));
      return source_return_content(%($value));
    }
  return ast;
}

// raise details

static List Compiler._ordered_raise(
  Compiler c, List cause, List arguments) {
  Array values = [cause], orders = $auto([c._part_order(cause)]);
  foreach (List argument, arguments) {
    values.push(argument);
    orders.push(c._part_order(argument));
  }
  List declarations = c._ordered_parts(values, orders);
  List parts = values.list_free();
  List raised = %(raise ${parts.car()} (args @{parts.cdr()}));
  return declarations ? %(block @declarations $raised) : raised;
}

static List Compiler._raise(Compiler c, List ast, Var cause, List arguments) {
  Array values = [], int index = 0;
  List code = c.convert_expression(cause, %("Symbol"));
  int changed = code != cause;
  foreach (List value, arguments) {
    Type invalid = NULL;
    if (index & 1) value = c.promote_string_literal(value);
    if (index & 1)
      match (value)
        case %(expr ?value_type ?content): {
          Type type = value_type;
          if (!c._raise_detail_type_allowed(type)) invalid = type;
          else if (c.sym.is_named_value_type(type, "List"))
            invalid = c._raise_nested_invalid_type(content);
        }
    if (invalid) {
      String message = %"raise detail type ${invalid.repr()} is not immutable";
      List location = c.origin_location(c.origin);
      c.diagnostics.report(
        <type>, message, location,
        %("use a numeric value, enum, Symbol, Atom, String, List, or Var"));
      // Null replaces the reported detail, so a later pass never sees it.
      value = %(expr ("Var") (call "Var_null" (args)));
    }
    List converted = c.convert_expression(value, %("Var"));
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

static int Compiler._raise_detail_type_allowed(Compiler c, Type type) {
  if (!type) return 0;
  with c.sym {
    if (_.is_var_type(type) ||
        _.is_string_type(type) ||
        _.is_named_value_type(type, "List") ||
        _.is_named_value_type(type, "Symbol") ||
        _.is_named_value_type(type, "Atom"))
      return 1;
    return !!_.resolve_numeric_type(type);
  }
}

static Type Compiler._raise_nested_invalid_type(Compiler c, Var node) {
  if (node is not <list>) return NULL;
  List ast = node;
  match (ast)
    case %(expr ?expr_type ?value): {
      Type type = expr_type;
      if (!c._raise_detail_type_allowed(type)) return type;
      if (c.sym.is_var_type(type)) {
        List payload = value;
        match (payload)
          case %(call ?(String callee) ?arguments):
            if (callee.endswith("_var"))
              return c._raise_nested_invalid_type(arguments);
        return NULL;
      }
      if (!c.sym.is_named_value_type(type, "List")) return NULL;
      return c._raise_nested_invalid_type(value);
    }
  foreach (Var child, ast) {
    Type invalid = c._raise_nested_invalid_type(child);
    if (invalid) return invalid;
  }
  return NULL;
}

// calls

static List Compiler._call(Compiler c, List ast) {
  match (ast)
    case ${$called(?callee, *arguments)}:
      match (callee.cadr()) {
        case %((func ?parameters) *):
          return c._typed_call(callee, parameters, arguments);
        case %((!or (!quote *) & ^) (func ?parameters) *):
          return c._typed_call(callee, parameters, arguments);
      }
  return ast;
}

static List Compiler._typed_call(
  Compiler c, List callee, List params, List args) {
  String callee_name = NULL;
  match (callee) {
    case %(expr ? ${$source_identifier_content(%(?binding))}):
      callee_name = binding_identity_spelling(binding);
  }
  int list_varargs = callee_name == "List_list_n";
  if (c.fn_name && _iter_immediate_consumer(callee_name) && args)
    args = cons(c.complete_iter_chain(args.car()), args.cdr());
  Array values = [], int arg_index = 0;
  for (List p = params, a = args; a;
       p = p.cdr(), a = a.cdr(), arg_index++) {
    List param = (p ? p.car().list() : NULL), arg = a.car();
    List expected = param;
    if (list_varargs && arg_index > 0) expected = %("Var");
    if (param && param.car() == <param>) expected = param.type_from_ast();
    arg = c.maybe_adapt_func_arg(arg, expected);
    List converted = expected
      ? c.convert_expression(arg, expected)
      : c.lower_lambda_expr(arg);
    values.push(converted);
  }
  List newargs = values.list_free();
  Macro called = $called;
  return c.rebuild_expression(NULL, called(callee, newargs)).caddr();
}

static int _iter_immediate_consumer(String name) =>
  name == "Iter_try_next" || name == "Iter_next" ||
         name == "Iter_list" || name == "Iter_array" ||
         name == "Iter_foldl" || name == "Iter_any" ||
         name == "Iter_all" || name == "Iter_find" ||
         name == "Iter_count" || name == "Iter_sum" ||
         name == "Iter_product" || name == "Iter_min" ||
         name == "Iter_max";

// operators

static List Compiler._operator(Compiler c, List ast) {
  List truthy = c._truthy(ast);
  if (truthy != ast) return truthy;
  match (ast) {
    case $source_operator_content(%(?operator
             (!set ?lhs (expr ?lhs_type ?)) (!set ?rhs (expr ?rhs_type ?)))):
      return c._binary_operator(ast, operator, lhs, lhs_type, rhs, rhs_type);
    case $source_operator_content(%(
             (!set ?operator (!or + - ~))
             (!set ?argument (expr ?argument_type ?)))):
      if (c.sym.is_var_type(argument_type))
        return c._dynamic(<unary>, %($operator ("Var")), argument_type,
          source_operator_content(%($operator $argument)));
    case $source_operator_content(%(
             (!set ?operator (!or ++ --))
             (!set ?argument (expr ?argument_type ?)))):
      return c._change(ast, operator, argument, argument_type, 0);
  }
  return ast;
}

static List Compiler._postfix(Compiler c, List ast) {
  match (ast)
    case $source_postfix_content(%(?operator
           (!set ?argument (expr ?argument_type ?)))):
      return c._change(ast, operator, argument, argument_type, 1);
  return ast;
}

/* `++` and `--` through a protocol member or on a `Var`. A postfix change
   has no right operand and yields the value before the change. */
static List Compiler._change(
  Compiler c, List ast, Symbol op, List arg, Type type, int postfix) {
  if (!c.sym.is_var_type(type)) {
    Symbol binary = op == <++> ? <+> : <->;
    List one = x2c_literal_int(1);
    List updated = postfix
      ? c._protocol_update(type, binary, arg, NULL, op)
      : c._protocol_update(type, binary, arg, one, binary);
    return updated ? updated : ast;
  }
  return postfix
    ? c._dynamic(<unary>, %(postfix $op ("Var")), type,
        source_postfix_content(%($op $arg)))
    : c._dynamic(<unary>, %($op ("Var")), type,
        source_operator_content(%($op $arg)));
}

/* An operation with a `Var` operand lowers through the rule a component
   registered for its operator on `Var`. The rule's replacement normalizes
   here like any other node. */
static List Compiler._dynamic(
  Compiler c, Symbol point, List kind, Type type, List operation) {
  List rewritten = c.rewrite(
    point, kind, %(expr $type $operation), AST_EXPRESSION, type, NULL);
  return rewritten ? rewritten.caddr() : operation;
}

static List Compiler._truthy(Compiler c, List ast) {
  Macro if_then = $if_then, if_else = $if_else;
  Macro while_loop = $while_loop, do_loop = $do_loop;
  Macro for_loop = $for_loop;
  match (ast) {
    case if_then(?condition, ?yes):
      return c.rebuild_statement(
        if_then(c._truthy_expression(condition), yes)).cadr();
    case if_else(?condition, ?yes, ?no):
      return c.rebuild_statement(
        if_else(c._truthy_expression(condition), yes, no)).cadr();
    case while_loop(?condition, ?body):
      return c.rebuild_statement(
        while_loop(c._truthy_expression(condition), body)).cadr();
    case do_loop(?body, ?condition):
      return c.rebuild_statement(
        do_loop(body, c._truthy_expression(condition))).cadr();
    case for_loop(?init, ?condition, ?increment, ?body):
      return c.rebuild_statement(
        for_loop(
          init, c._truthy_expression(condition), increment,
          body)).cadr();
    case $source_operator_content(%((!set ?operator (!or && ||)) ?lhs ?rhs)): {
      List left = c._truthy_expression(lhs);
      List right = c._truthy_expression(rhs);
      return source_operator_content(%($operator $left $right));
    }
    case $source_operator_content(%(? ?condition ?ontrue ?onfalse)): {
      List test = c._truthy_expression(condition);
      return source_operator_content(%(? $test $ontrue $onfalse));
    }
    case $source_operator_content(%(! ?condition)):
      return source_operator_content(%(! ${c._truthy_expression(condition)}));
  }
  return ast;
}

static List Compiler._truthy_expression(Compiler c, List expr) {
  if (!expr) return expr;
  List resolved = c.resolve_protocol_member(expr.cadr(), "truth");
  if (!resolved) return expr;
  (List binding, Type signature) = resolved;
  List callee = $!($signature){ $binding };
  return $!int{ $callee($expr) };
}

static List Compiler._to_var(Compiler c, List expr) =>
  c.convert_expression(expr, %("Var"));

static List _symbol_expression(Symbol value) =>
  %(expr ("Symbol") "${(unsigned long) value}");

// Inject conversions so assignment RHS matches the annotated LHS type.
static List Compiler._assignment(Compiler c, Symbol op, List lhs, List rhs) {
  if (lhs.match(%(expr ? (slice *))))
    $report.xform.slice_assignment(c);
  rhs = c.convert_expression(rhs, lhs.cadr());
  return %(op $op $lhs $rhs);
}

static List Compiler._comparison(
  Compiler c, List ast, Symbol op, List lhs, Type lhs_type, List rhs,
  Type rhs_type) {
  if (!c.sym.is_var_type(lhs_type) &&
      !c.sym.is_var_type(rhs_type)) {
    if (op == <===>) return %(op == $lhs $rhs);
    if (op == <!==>) return %(op != $lhs $rhs);
    return ast;
  }
  lhs = c.convert_expression(lhs, %("Var"));
  rhs = c.convert_expression(rhs, %("Var"));
  switch (op) {
    case <==>:  return $!int{ Var_equal($lhs, $rhs) }.caddr();
    case <!=>:  return $!int{ !Var_equal($lhs, $rhs) };
    case <===>: return $!int{ Var_same($lhs, $rhs) }.caddr();
    case <!==>: return $!int{ !Var_same($lhs, $rhs) };
  }
  List call = %(call "Var_compare" (args $lhs $rhs));
  List zero = x2c_literal_int(0);
  return %(expr (int) (op $op $call $zero));
}

static List Compiler._binary_operator(
  Compiler c, List ast, Symbol operator, List lhs, Type lhs_type, List rhs,
  Type rhs_type) {
  Symbol compound = Symbol.compound_operator(operator);
  if (compound)
    return c._compound(ast, compound, lhs, lhs_type, rhs, rhs_type);
  switch (operator) {
    case <=>: return c._assignment(operator, lhs, rhs);
    case <==>:  case <!=>:  case <===>: case <!==>:
    case <"<">: case <"<=">: case <">">:  case <">=">:
      return c._comparison(ast, operator, lhs, lhs_type, rhs, rhs_type);
  }
  /* The dynamic binary operators are exactly those with a compound
     assignment spelling; `Var_binary` accepts the same operators. */
  if (operator.compound_assignment() &&
      (c.sym.is_var_type(lhs_type) || c.sym.is_var_type(rhs_type)))
    return c._dynamic(<binary>, %($operator ("Var")), %("Var"),
      source_operator_content(%($operator $lhs $rhs)));
  return ast;
}

static List Compiler._compound(
  Compiler c, List ast, Symbol op, List lhs, Type lhs_type, List rhs,
  Type rhs_type) {
  int lhs_is_var = c.sym.is_var_type(lhs_type);
  if (c._indexed_builtin_helper(lhs_type))
    $report.xform.container_compound(c, lhs_type);
  /* Without this rejection a nonmatching String compound falls through to
     native pointer arithmetic on an interned String. Concatenation itself
     lowers through the protocol member below like any adopter, resolved
     against canonical String because Var(String) adoption is exact while
     String typedefs still spell the same lvalue. */
  Type member_type = lhs_type;
  if (c.sym.is_string_type(lhs_type)) {
    if (op != <+> || !c._string_operand(rhs_type))
      $report.xform.string_compound(c);
    member_type = %("String");
  }
  if (!lhs_is_var) {
    List converted = rhs;
    List updated = c._protocol_update(member_type, op, lhs, converted, op);
    if (updated) return updated;
  }
  if (!lhs_is_var && !c.sym.is_var_type(rhs_type)) return ast;
  Symbol assignment = op.compound_assignment();
  return c._dynamic(<binary>, %($assignment ("Var")), lhs_type,
    source_operator_content(%($assignment $lhs $rhs)));
}

static int Compiler._string_operand(Compiler c, Type type) =>
  c.sym.is_string_type(type)
      || type.canonicalize().is_char_pointer_like();

/* evaluation order

   C leaves the order of call arguments unspecified. A value that x2c
   evaluates in source order moves into a temporary, declared ahead of the
   expression that uses it inside a statement expression. */
static List Compiler._sequenced(
  Compiler c, List value, String stem, Array declarations) {
  Type type = value.cadr();
  List temporary = c.sym.introduce(c.fresh_name(stem));
  declarations.push(_value_declaration(type, temporary, value));
  return $!($type){ $temporary };
}

/* A C macro such as raylib's WHITE expands to an expression x2c has no
   type for, and a temporary still has to declare one: the type the value is
   about to be passed as. */
static List _passed_as(List value, Type type) {
  match (value) case %(expr () ?body): return %(expr $type $body);
  return value;
}

static List _statement_expression(List declarations, List expression) =>
  %(parens (block @declarations (stmnt $expression)));

/** Calls the typed callable `callee` with `arguments`, each converted to
    its parameter and evaluated once, in source order, as a statement
    expression. */
List Compiler.call_in_order(Compiler c, List callee, List arguments) {
  Type signature = callee.cadr();
  List parameters = signature.car().list().cadr();
  Array converted = [];
  for (List actual = arguments, expected = parameters;
       actual && expected;
       actual = actual.cdr(), expected = expected.cdr()) {
    List value = c.convert_expression(actual.car(), expected.car());
    converted.push(_passed_as(value, expected.car()));
  }
  Array declarations = [], arguments_out = [];
  foreach (List value, converted)
    arguments_out.push(c._sequenced(value, "protocol_arg", declarations));
  converted.free();
  Macro called = $called;
  List call = c.rebuild_expression(
    signature.cdr(), called(callee, arguments_out.list_free()));
  return _statement_expression(declarations.list_free(), call);
}

static List Compiler._protocol_update(
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

#endif
