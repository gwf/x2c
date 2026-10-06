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

static macro Stmt $report.parse.init_incomplete(Expr $c) =>
  $c.report_error(
    <parse>,
    "managed initializer requires a complete block-local initializer",
    NULL, NULL);

static macro Stmt $report.xform.index_unsupported(Expr $c, Expr $type) =>
  $c.report_error(
    <xform>, %"type ${$type} does not support bracket indexing",
    NULL, NULL);

static macro Stmt $report.xform.index_assignment(Expr $c, Expr $type) =>
  $c.report_error(
    <xform>, %"type ${$type} does not support bracket assignment",
    NULL, NULL);

static macro Stmt $report.xform.slice_unsupported(
  Expr $c, Expr $type, Expr $notes) =>
  $c.report_error(
    <xform>, %"type ${$type} does not support slicing",
    NULL, $notes);

static macro Stmt $report.type.destructure_list(Expr $c, Expr $source_type) =>
  $c.report_error(
    <type>, "destructuring requires a List source",
    NULL, %(("source type" ${$source_type})));

static macro Stmt $report.xform.unary_dynamic(Expr $c) =>
  $c.report_error(
    <xform>, "dynamic unary numeric operators are not supported",
    NULL, %("use Var.binary with an explicit numeric operand"));

static macro Stmt $report.xform.index_copy(Expr $c, Expr $type) =>
  $c.report_error(
    <xform>, %"type ${$type} does not support bracket assignment",
    NULL, %("use an explicit copy-producing method where available"));

static macro Stmt $report.xform.string_assignment(Expr $c) {
  {
    String note = "String is immutable: use the copy-producing "
                  "String.withindex, or bind a char * to write a "
                  "transient String.malloc buffer";
    $c.report_error(
      <xform>, "String does not support bracket assignment",
      NULL, %($note));
  }
}

static macro Stmt $report.xform.slice_assignment(Expr $c) =>
  $c.report_error(
    <xform>, "slice expressions are not assignable",
    NULL, %("call the collection's setslice method explicitly"));

static macro Stmt $report.xform.numeric_operands(
  Expr $c, Expr $op, Expr $lhs_type, Expr $rhs_type) {
  {
    String left_type = $lhs_type.repr(), right_type = $rhs_type.repr();
    String details =
      %"operator: ${$op} left type: $left_type right type: $right_type";
    $c.report_error(
      <xform>, "dynamic numeric operators require numeric operands",
      NULL, %($details));
  }
}

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

static macro Stmt $report.xform.compound_operand(
  Expr $c, Expr $op, Expr $rhs_type) {
  {
    String details = %"right type: ${$rhs_type.repr()}";
    $c.report_error(
      <xform>, $op == <+>
        ? "dynamic += requires a numeric, Var, or String operand"
        : "dynamic compound assignment requires a numeric or Var operand",
      NULL, %($details));
  }
}

static macro Stmt $report.xform.compound_bitfield(Expr $c) =>
  $c.report_error(
    <xform>, "dynamic compound assignment cannot target a bitfield",
    NULL, NULL);

static macro Stmt $report.xform.compound_lvalue(Expr $c, Expr $lhs_type) {
  {
    String details = %"left type: ${$lhs_type.repr()}";
    $c.report_error(
      <xform>, "dynamic compound assignment requires a numeric lvalue",
      NULL, %($details));
  }
}

static macro Stmt $report.xform.compound_enum(Expr $c) =>
  $c.report_error(
    <xform>, "dynamic compound assignment cannot target an enum",
    NULL, NULL);

static macro Stmt $report.xform.index_operand(Expr $c, Expr $op, Expr $rhs_type) {
  {
    String details = %"right type: ${$rhs_type.repr()}";
    String message = $op == <+>
      ? "indexed += requires a numeric, Var, or String operand"
      : "indexed compound assignment requires a numeric or Var operand";
    $c.report_error(<xform>, message, NULL, %($details));
  }
}

static macro Stmt $report.xform.index_update(
  Expr $c, Expr $base_type, Expr $postfix) {
  {
    String type = $base_type.repr();
    String message = $postfix
      ? %"type $type does not support indexed increment or decrement"
      : %"type $type does not support indexed compound assignment";
    $c.report_error(<xform>, message, NULL, NULL);
  }
}


// normalization

/** Lowers a bound and typed top-level AST to the normalized form consumed by
    emission. `c` must own the AST's bindings, origins, and conversion
    state. Current-node rewrites finish before child traversal; containing
    blocks absorb cleanup markers produced by declaration rewrites. Early
    declarations are lowered and appended after the input units. Their
    storage determines their interface visibility. The call may add
    generated origins or diagnostics to `c`.
*/
List Compiler.transform(Compiler c, List ast) {
  /* Regions are read before lowering, while `$scope`, `$auto`, and the
     `defer` beside each region are still the forms the parser produced. */
  c.check_regions(ast);
  List newast = c._sequence(ast, 0);
  // Merge and lower synthesized lambda siblings.
  Array generated = [];
  while (c.early_decls.len()) {
    List items = c.early_decls;
    c.early_decls.clear();
    List lowered = c._sequence(items, 0);
    foreach (Var sibling, lowered) generated.push(sibling);
  }
  if (generated.len()) newast = newast.append(generated.list_free());
  return newast;
}

/** Normalizes one bound and typed node. Newly constructed syntax is
    normalized where it is produced; children enter the same operation, so
    completed units do not require another unit walk.
*/
Ast Compiler.normalize(Compiler c, Ast ast) => c._step(ast);

static Ast Compiler._step(Compiler c, Ast ast) {
  if (!ast) return NULL;
  match (ast)
    case %(managed-init ?):
      $report.parse.init_incomplete(c);
  Var head = ast.car();
  if (head is not <symbol>) return c._default_node(ast);
  match (ast) {
    case %(at ?origin ?inner): return c._at_node(ast, origin, inner);
    case %(function ?return_type
           (!set ?declarator (bind ?binding ?)) ?body):
      return c._function_node(return_type, declarator, binding, body);
    case %(getindex
           (!set ?expression (expr ?matched_type ?)) ?index):
      return c._getindex_node(expression, matched_type, index);
    case %(setindex
           (!set ?expression (expr ?matched_type ?)) ?index ?value):
      return c._setindex_node(expression, matched_type, index, value);
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
    case <array>: case <varray>: next = transform_array_literal(c, ast); break;
    case <map>: case <vmap>: next = transform_map_literal(c, ast); break;
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

static Ast Compiler._function_node(
  Compiler c, List return_type, List declarator, List binding, List body) {
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

static Ast Compiler._getindex_node(
  Compiler c, List expression, Type type, List index) {
  List resolved = c._nominal_getindex(type);
  if (!resolved) resolved = c.resolve_protocol_member(type, "getindex");
  if (!resolved)
    $report.xform.index_unsupported(c, type);
  return c._step(
    c._indexed_call_expr(resolved, %($expression $index)).caddr());
}

static Ast Compiler._setindex_node(
  Compiler c, List expression, Type type, List index, List value) {
  List resolved = c.resolve_protocol_member(type, "setindex");
  if (!resolved)
    $report.xform.index_assignment(c, type);
  if (!c._indexed_builtin_helper(type))
    return c._step(
      c._sequenced_protocol_call(resolved, %($expression $index $value)));
  return c._step(
    c._indexed_call_expr(resolved, %($expression $index $value)).caddr());
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

static Ast Compiler._expression_node(Compiler c, Ast ast) {
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

/** Converts an array literal to source-ordered Var arguments for its
    counted constructor. */
List transform_array_literal(Compiler c, List ast) {
  Array values = [], orders = $auto([]);
  foreach (List elem, ast.cdr()) {
    List value = c._literal_element(elem);
    values.push(value);
    orders.push(c._part_order(value));
  }
  List declarations = c._ordered_parts(values, orders);
  List literal = c._var_array_literal(values.list_free());
  return _ordered(declarations, %("Array"), literal);
}

/** Converts a map literal to alternating Var key/value arguments for its
    counted constructor. */
List transform_map_literal(Compiler c, List ast) {
  Array values = [], orders = $auto([]);
  foreach (List entry, ast.cdr())
    foreach (List part, entry.cdr()) {
      List value = c._literal_element(part);
      values.push(value);
      orders.push(c._part_order(value));
    }
  List declarations = c._ordered_parts(values, orders);
  List literal = c._var_map_literal(values.list_free());
  return _ordered(declarations, %("Map"), literal);
}

/* The containing typed expression already fixes the result type. */
static List Compiler._var_literal_content(Compiler c, List application) {
  List bound = c.bind_syntax(application, AST_EXPRESSION, NULL);
  match (bound) case %(expr ? ?content): return content;
  __builtin_unreachable();
}

/* The converted Var values enter the native counted constructors unchanged.
   Empty literals need only allocate their container. */
static List Compiler._var_array_literal(Compiler c, List values) {
  if (!values) return c._var_literal_content($!( Array.new() ));
  return c._var_literal_content(
    $!( Array.update_n(Array.new(), ${values.len()}, $values...) ));
}

static List Compiler._var_map_literal(Compiler c, List entries) {
  if (!entries) return c._var_literal_content($!( Map.new() ));
  return c._var_literal_content(
    $!( Map.update_n(Map.new(), ${entries.len() / 2}, $entries...) ));
}

/* A literal element is a `Var`, and an empty brace there is an empty Map. */
static List Compiler._literal_element(Compiler c, List element) {
  if (element.match(%(expr ? (composite (commas)))))
    element = %(expr ("Map") (map));
  return c._step(c.convert_expression(element, %("Var")));
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

static macro Stmt $destructure_sequence(Stmt $items...) {
  $items...
}

static macro Stmt $destructure_declarations(
    Name $temporary, Expr $source, Stmt $assignments...) {
  List $temporary = $source;
  $assignments...
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
            ${c._destructure_assignments(targets, temporary)}...
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
        Expr $converted, Stmt $assignments...) => ({
        $type $result = $source;
        List $temporary = $converted;
        $assignments...
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
    c.rebuild_statement($!{ $type ${declarations.list_free()}...; }).cadr();
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
  ast = c._lower_printf_vars(ast);
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

// printf formats

static typedef enum PrintfLength {
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

/* One static format read against the call's variadic arguments. */
static typedef struct PrintfWalk {
  Compiler c;
  Array values;
  String format, family;
  int cursor, end, value_index;
} PrintfWalk;

// Align static format conversions with variadic arguments and lower only
// Var crossings. The parser understands the standard output grammar far
// enough to preserve native arguments around the safe automatic subset.
static List Compiler._lower_printf_vars(Compiler c, List ast) {
  (List callee, List args_node) = ast.cdr();
  const PrintfFn *info = callee.printf_family();
  if (!info) return ast;
  List args = args_node.cdr();
  if (!c._printf_has_var(args, info.first_arg)) return ast;

  Array values = [];
  foreach (Var arg, args) values.push(arg);
  String family = (String) info.name;
  if (info.fmt_arg >= values.len())
    c._printf_error(family, "call has no format argument");
  List format_arg = values[info.fmt_arg], int raw = 0;
  String format = c.printf_static_format(format_arg, raw);
  if (!format)
    c._printf_error(
      family, "Var arguments require a single static format literal");

  PrintfWalk walk = {
    .c = c, .values = values, .format = format, .family = family,
    .cursor = raw ? 1 : 0,
    .end = raw ? format.len() - 1 : format.len(),
    .value_index = info.first_arg,
  };
  walk.scan(raw);

  for (int i = walk.value_index; i < values.len(); i++) {
    List arg = values[i];
    if (c.sym.is_var_type(arg.cadr()))
      c._printf_error(
        family, "Var argument has no corresponding format conversion");
  }
  List newargs = values.list_free();
  return %(call $callee (args @newargs));
}

static int Compiler._printf_has_var(Compiler c, List args, int first_value) {
  int index = 0;
  foreach (List arg, args) {
    if (index++ < first_value) continue;
    if (c.sym.is_var_type(arg.cadr())) return 1;
  }
  return 0;
}

static void Compiler._printf_error(Compiler c, String family, String message) {
  String note = "printf-family call: %s".printf(family);
  c.report_error(<xform>, message, NULL, %($note));
}

static void PrintfWalk.scan(PrintfWalk &w, int raw) {
  while (w.cursor < w.end) {
    if (raw && w.format[w.cursor] == '\\') {
      w.cursor += w.cursor + 1 < w.end ? 2 : 1;
      continue;
    }
    if (w.format[w.cursor++] != '%') continue;
    if (w.cursor >= w.end) w._error("incomplete format conversion");
    if (w.format[w.cursor] == '%') {
      w.cursor++;
      continue;
    }
    w._conversion();
  }
}

static void PrintfWalk._conversion(PrintfWalk &w) {
  w._position();
  w._width();
  w._precision();
  PrintfLength length = w._length();
  if (w.cursor >= w.end) w._error("incomplete format conversion");
  int conversion = w.format[w.cursor++];
  if (!_printf_valid_length(length, conversion)) {
    String message =
      "unsupported or malformed format conversion %%%c".printf(conversion);
    w._error(message);
  }
  if (w.value_index >= w.values.len()) {
    String message =
      "format conversion %%%c consumes a missing argument".printf(conversion);
    w._error(message);
  }
  w._value(length, conversion);
}

static void PrintfWalk._position(PrintfWalk &w) {
  int probe = w.cursor;
  while (probe < w.end && _printf_is_digit(w.format[probe])) probe++;
  if (probe < w.end && w.format[probe] == '$')
    w._error("positional formats cannot infer Var argument types");
}

static void PrintfWalk._width(PrintfWalk &w) {
  while (w.cursor < w.end &&
         (w.format[w.cursor] == '-' || w.format[w.cursor] == '+' ||
          w.format[w.cursor] == ' ' || w.format[w.cursor] == '#' ||
          w.format[w.cursor] == '0'))
    w.cursor++;
  if (w.cursor < w.end && w.format[w.cursor] == '*') {
    w.cursor++;
    w._position();
    w._star();
  }
  else while (w.cursor < w.end && _printf_is_digit(w.format[w.cursor]))
    w.cursor++;
}

static void PrintfWalk._precision(PrintfWalk &w) {
  if (w.cursor >= w.end || w.format[w.cursor] != '.') return;
  w.cursor++;
  if (w.cursor < w.end && w.format[w.cursor] == '*') {
    w.cursor++;
    w._position();
    w._star();
  }
  else while (w.cursor < w.end && _printf_is_digit(w.format[w.cursor]))
    w.cursor++;
}

static PrintfLength PrintfWalk._length(PrintfWalk &w) {
  PrintfLength length = _printf_default;
  if (w.cursor + 1 < w.end && w.format[w.cursor] == 'h' &&
      w.format[w.cursor + 1] == 'h') {
    length = _printf_hh;
    w.cursor += 2;
  }
  else if (w.cursor + 1 < w.end && w.format[w.cursor] == 'l' &&
           w.format[w.cursor + 1] == 'l') {
    length = _printf_ll;
    w.cursor += 2;
  }
  else if (w.cursor < w.end) {
    switch (w.format[w.cursor]) {
      case 'h': length = _printf_h; w.cursor++; break;
      case 'l': length = _printf_l; w.cursor++; break;
      case 'j': length = _printf_j; w.cursor++; break;
      case 'z': length = _printf_z; w.cursor++; break;
      case 't': length = _printf_t; w.cursor++; break;
      case 'L': length = _printf_L; w.cursor++; break;
    }
  }
  return length;
}

static void PrintfWalk._error(PrintfWalk &w, String message) {
  w.c._printf_error(w.family, message);
}

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

static int _printf_is_digit(int ch) => ch >= '0' && ch <= '9';

/* The next value argument, read by one conversion. Native arguments retain
   C calling semantics. */
static void PrintfWalk._value(
  PrintfWalk &w, PrintfLength length, int conversion) {
  int index = w.value_index++;
  List arg = w.values[index];
  if (!w.c.sym.is_var_type(arg.cadr())) return;

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
    w.values[index] = %(expr ("String") (call "Var_str" (args $arg)));
    return;
  }
  if (target) {
    w.values[index] = w.c.convert_expression(arg, target);
    return;
  }

  String message =
    "cannot infer a native argument for Var at %%%c".printf(conversion);
  w._error(%"$message; use an explicit converter for this format conversion");
}

/* A `*` width or precision reads the next argument as an int. */
static void PrintfWalk._star(PrintfWalk &w) {
  int index = w.value_index++;
  if (index >= w.values.len())
    w._error("format consumes a missing '*' argument");
  List arg = w.values[index];
  if (w.c.sym.is_var_type(arg.cadr()))
    w.values[index] = w.c.convert_expression(arg, %(int));
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
             (!set ?argument (expr ?argument_type ?)))): {
      if (c.sym.is_var_type(argument_type))
        $report.xform.unary_dynamic(c);
      return ast;
    }
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

/* `++` and `--` through a bracket, a protocol member, or a Var. A postfix
   change has no right operand and yields the value before the change. */
static List Compiler._change(
  Compiler c, List ast, Symbol op, List arg, Type type, int postfix) {
  Symbol binary = op == <++> ? <+> : <->;
  Symbol spelled = postfix ? op : binary;
  List one = postfix ? NULL : x2c_literal_int(1);
  List indexed = c._indexed_change(arg, spelled, one);
  if (indexed) return indexed;
  if (!c.sym.is_var_type(type)) {
    List updated = postfix
      ? c._protocol_update(type, binary, arg, NULL, op)
      : c._protocol_update(type, binary, arg, one, binary);
    return updated ? updated : ast;
  }
  if (one) one = c.convert_expression(one, %("Var"));
  return _update_call(
    arg, _symbol_expression(spelled), one,
    postfix ? "x2c_var_postfix_volatile" : "x2c_var_update_volatile");
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
  List base, index;
  Type base_type;
  if (_resolved_index_parts(lhs, base, base_type, index)) {
    /* String is immutable and interned, so an in-place bracket write
       would mutate shared storage and leave its cached header hash
       stale. A raw write bypasses that invariant, while generic
       setindex returns a copy that this assignment would discard. */
    if (c.sym.is_string_type(base_type))
      $report.xform.string_assignment(c);
    if (!c.resolve_protocol_member(base_type, "setindex"))
      $report.xform.index_copy(c, base_type);
    return %(setindex $base $index $rhs);
  }
  rhs = c.convert_expression(rhs, lhs.cadr());
  return %(op $op $lhs $rhs);
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
  if (compound) {
    List indexed = c._indexed_change(lhs, compound, rhs);
    if (indexed) return indexed;
    return c._dynamic_compound(ast, compound, lhs, lhs_type, rhs, rhs_type);
  }
  switch (operator) {
    case <=>: return c._assignment(operator, lhs, rhs);
    case <==>:  case <!=>:  case <===>: case <!==>:
    case <"<">: case <"<=">: case <">">:  case <">=">:
      return c._comparison(ast, operator, lhs, lhs_type, rhs, rhs_type);
  }
  if (_dynamic_binary_operator(operator))
    return c._dynamic_binary(ast, operator, lhs, lhs_type, rhs, rhs_type);
  return ast;
}

/* The dynamic binary operators are exactly those with a compound assignment
   spelling; `Var_binary` and `Var_update` accept the same operators. */
static int _dynamic_binary_operator(Symbol op) =>
  op.compound_assignment() != 0;

static List Compiler._dynamic_binary(
  Compiler c, List ast, Symbol op, List lhs, Type lhs_type, List rhs,
  Type rhs_type) {
  int lhs_is_var = c.sym.is_var_type(lhs_type);
  int rhs_is_var = c.sym.is_var_type(rhs_type);
  if (!lhs_is_var && !rhs_is_var) return ast;
  int string_plus = op == <+>
                 && (lhs_is_var || c._string_operand(lhs_type))
                 && (rhs_is_var || c._string_operand(rhs_type));
  if (!string_plus &&
      ((!lhs_is_var && !c.sym.resolve_numeric_type(lhs_type)) ||
       (!rhs_is_var && !c.sym.resolve_numeric_type(rhs_type)))) {
    $report.xform.numeric_operands(c, op, lhs_type, rhs_type);
  }
  lhs = c.convert_expression(lhs, %("Var"));
  rhs = c.convert_expression(rhs, %("Var"));
  return $!Var{ Var_binary($lhs, $op, $rhs) }.caddr();
}

static List Compiler._dynamic_compound(
  Compiler c, List ast, Symbol op, List lhs, Type lhs_type, List rhs,
  Type rhs_type) {
  int lhs_is_var = c.sym.is_var_type(lhs_type);
  int rhs_is_var = c.sym.is_var_type(rhs_type);
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
    List updated = c._protocol_update(member_type, op, lhs, rhs, op);
    if (updated) return updated;
    rhs_type = rhs.cadr();
  }
  if (!lhs_is_var && !rhs_is_var) return ast;
  c._dynamic_rhs(op, lhs_type, rhs_type, rhs_is_var);

  String helper = "x2c_var_update_volatile";
  if (!lhs_is_var) helper = c._dynamic_helper(lhs_type);

  rhs = c.convert_expression(rhs, %("Var"));
  return _update_call(lhs, _symbol_expression(op), rhs, helper);
}

static void Compiler._dynamic_rhs(
  Compiler c, Symbol op, Type lhs_type, Type rhs_type, int rhs_is_var) {
  if (lhs_type.is_bitfield())
    $report.xform.compound_bitfield(c);
  if (!rhs_is_var && !c._scalar_operand(op, rhs_type))
    $report.xform.compound_operand(c, op, rhs_type);
}

/* A number, or text added to text, updates a Var or container element. */
static int Compiler._scalar_operand(Compiler c, Symbol op, Type type) =>
  c.sym.resolve_numeric_type(type) || (op == <+> && c._string_operand(type));

static String Compiler._dynamic_helper(Compiler c, Type lhs_type) {
  Type scalar = c.sym.resolve_numeric_type(lhs_type);
  if (scalar && scalar.is_enum())
    $report.xform.compound_enum(c);
  String helper = scalar ? scalar.var_numeric_update_helper() : NULL;
  if (!helper)
    $report.xform.compound_lvalue(c, lhs_type);
  return helper;
}

static int Compiler._string_operand(Compiler c, Type type) =>
  c.sym.is_string_type(type)
      || type.canonicalize().is_char_pointer_like();

// indexed updates

static List Compiler._indexed_change(
  Compiler c, List target, Symbol op, List rhs) {
  Symbol owner, List base, selector, Type base_type;
  if (!c._indexed_parts(target, owner, base, base_type, selector))
    return NULL;
  int postfix = !rhs;
  List resolved = c._indexed_resolution(base_type, owner, op, rhs);

  List operation = _symbol_expression(op);
  List arguments = postfix
    ? %($base $selector $operation)
    : %($base $selector $operation $rhs);
  if (!owner) return c._sequenced_protocol_call(resolved, arguments);
  c._convert_indexed_parts(owner, base, selector);
  String helper = owner == <array>
    ? (postfix ? "Array_postfixindex" : "Array_updateindex")
    : (postfix ? "Map_postfixindex" : "Map_updateindex");
  if (!postfix) rhs = c.convert_expression(rhs, %("Var"));
  arguments = postfix
    ? %($base $selector $operation)
    : %($base $selector $operation $rhs);
  return %(call $helper (args @arguments));
}

/* Compound, prefix and postfix brackets share the same resolved element,
   protocol lookup, and built-in conversion. A missing rhs means postfix. */
static List Compiler._indexed_resolution(
  Compiler c, Type base_type, Symbol owner, Symbol op, List rhs) {
  int postfix = !rhs;
  List resolved = c.resolve_protocol_member(
    base_type, postfix ? "postfixindex" : "updateindex");
  if (!resolved)
    $report.xform.index_update(c, base_type, postfix);
  if (owner && !postfix) {
    Type rhs_type = rhs.cadr();
    if (!c.sym.is_var_type(rhs_type) && !c._scalar_operand(op, rhs_type))
      $report.xform.index_operand(c, op, rhs_type);
  }
  return resolved;
}

// Helper-backed indexes bypass getindex lowering.
static int Compiler._indexed_parts(
  Compiler c, List expr, Symbol &owner, List &base, Type &base_type,
  List &selector) {
  if (!_resolved_index_parts(expr, base, base_type, selector)) return 0;
  owner = c._indexed_builtin_helper(base_type);
  return 1;
}

static void Compiler._convert_indexed_parts(
  Compiler c, Symbol owner, List &base, List &selector) {
  if (owner == <array>) {
    base = c.convert_expression(base, %("Array"));
    selector = c.convert_expression(selector, %(int));
  }
  else {
    base = c.convert_expression(base, %("Map"));
    selector = c.convert_expression(selector, %("Var"));
  }
}

static List Compiler._indexed_call_expr(
  Compiler c, List resolved, List arguments) {
  (List binding, Type signature) = resolved;
  Macro called = $called;
  List callee = $!($signature){ $binding };
  return c.rebuild_expression(signature.cdr(), called(callee, arguments));
}

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

static List Compiler._sequenced_protocol_call(
  Compiler c, List resolved, List arguments) {
  Type signature = resolved.cadr();
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
  List call = c._indexed_call_expr(resolved, arguments_out.list_free());
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
