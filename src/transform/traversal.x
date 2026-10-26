/*  traversal.x -- AST transformation traversal */

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
  /* Regions are read before lowering, while region `auto`, initializer `auto`, and the
     `defer` beside each region are still the forms the parser produced. */
  c.check_regions(ast);
  List newast = _sequence(c, ast, 0);
  // Merge and lower synthesized lambda siblings.
  Array generated = [], support = c.pending.area(<support>);
  while (support) {
    List items = support;
    support.clear();
    foreach (List sibling in _sequence(c, items, 0)) generated.push(sibling);
  }
  if (generated) newast = newast.append(generated.list_free());
  return newast;
}

/** Normalizes one bound and typed node. Newly constructed syntax is
    normalized where it is produced; children enter the same operation, so
    completed units do not require another unit walk.
*/
Ast Compiler.normalize(Compiler c, Ast ast) => _step(c, ast);

module Ast _step(Compiler c, Ast ast) {
  if (!ast) return NULL;
  if (c.slot_watch) {
    Ast watched = c.watched_step(ast);
    if (watched) return watched;
  }
  Var head = ast.car();
  if (head is not <symbol>) return _default_node(c, ast);
  match (ast) {
    case %(at ?origin ?inner): return _at_node(c, ast, origin, inner);
    case %(function ?return_type
           (!set ?declarator (bind ?binding ?)) ?body):
      return _function_node(c, ast, return_type, declarator, binding, body, 0);
    case %(function ? (bind ? ?) ? kernel): return _written_function(c, ast);
    case %(slice
           (!set ?expression
             (expr (!set ?matched_type (*)) ?))
           ?start ?stop ?step):
      return _slice_node(c, expression, matched_type, start, stop, step);
  }
  return _step_tag(c, ast, head);
}

// Tag-only lowering does not retain the typed-pattern capture buffer.
static Ast _step_tag(Compiler c, Ast ast, Symbol tag) {
  Ast next = ast;
  switch (tag) {
    case <protocol>: case <adopt>: case <macrodef>: case <literal>:
      return ast;
    case <expr>: return _expression_node(c, ast);
    case <array>: case <varray>: case <map>: case <vmap>:
      return _collection_literal(c, ast, tag);
    case <cast>: next = _cast(c, ast); break;
    case <index>: next = _index(c, ast); break;
    case <cons>: case <append>: return _ordered_list(c, ast);
    case <var>: next = _to_var(c, ast.cadr()); break;
    case <segments>: return _interpolation(c, ast);
    case <declare>: case <decl>: next = _declaration(c, ast); break;
    case <dstrdecl>: return _destructuring(c, ast, tag, <block>);
    case <stmnt>:
      return _destructures(ast) ? _destructuring(c, ast, tag, <statement>)
                                : _default_node(c, ast);
    case <dstrasgn>: return _destructuring_value(c, ast);
    case <match>: case <match-if>:
      return _shipped_statement(c, ast, tag);
    case <defer>: next = _defer_node(c, ast); break;
    case <return>: next = _return(c, ast); break;
    case <raise>: return _raise_node(c, ast);
    case <switch>: {
      List rewritten = _statement_rewrite(c, ast, tag);
      return rewritten !== ast ? rewritten : _default_node(c, ast);
    }
    case <if>: case <while>: case <do>: case <for>:
      next = _truthy(c, ast); break;
    case <call>: next = _call(c, ast); break;
    case <op>: next = _operator(c, ast); break;
    case <postfix>: next = _postfix(c, ast); break;
    default: return _default_node(c, ast);
  }
  if (next != ast) return _step(c, next);
  return _default_node(c, ast);
}

/* Ordinary registered patterns may replace a typed statement. */
static Ast _statement_rewrite(Compiler c, Ast ast, Symbol tag) {
  List rewritten = c.rewrite_rules ? c.lower_rewrite(
    <node>, tag, ast, <statement>, c.return_type, NULL) : NULL;
  return rewritten ? rewritten : ast;
}

/* The replacement a shipped rule gives a form the kernel no longer lowers
   itself. No replacement is an error that ends the translation: this
   compiler does not link the component that owns the form, or its rule
   failed to register. */
module List _shipped_lowering(
  Compiler c, Symbol point, Var kind, List source, Symbol position,
  Type expected, String form) {
  List lowered =
    c.lower_rewrite(point, kind, source, position, expected, NULL);
  if (!lowered) $fail.transform_no_shipped_rule(c, NULL, form);
  return lowered;
}

/** Adds to the unit's pending support the file-scope code a rule gives
    the form `source` of `kind`, bound and lowered with the support. The
    kernel has no lowering of its own for `source`, so no rule ends the
    translation as `_shipped_lowering` does. */
void Compiler.shipped_support(
  Compiler c, Symbol kind, List source, String form) {
  List bound = c.rewrite(<node>, kind, source, <unit>, NULL, NULL);
  if (!bound) $fail.transform_no_shipped_rule(c, NULL, form);
  else c.add_support(bound);
}

static Ast _shipped_statement(Compiler c, Ast ast, Symbol tag) =>
  _shipped_lowering(
    c, <node>, tag, ast, <statement>, c.return_type, %"$tag statement");

static Ast _destructuring(
  Compiler c, Ast ast, Symbol tag, Symbol position) {
  String form = position == <block>
    ? "destructuring declaration" : "destructuring statement";
  // The implementation belongs to src/components/destructuring.x.
  return _shipped_lowering(
    c, <node>, tag, ast, position, c.return_type, form);
}

static int _destructures(List statement) {
  match (statement) case %(stmnt (expr ? (dstrasgn *))): return 1;
  return 0;
}

/* A destructuring assignment expression has its source's type. */
static Ast _destructuring_value(Compiler c, Ast ast) {
  Type type = ast.caddr().cadr();
  return _shipped_lowering(
    c, <literal>, <dstrasgn>, %(expr $type $ast), <expression>, type,
    "destructuring assignment").caddr();
}

module Ast _default_node(Compiler c, Ast ast) {
  Var head = ast.car();
  if (head == <seq> || head == <parens> || head == <block>)
    return _finish(c, ast);
  return _children(c, ast);
}

/* Normalize synthesized sequences before their containing block absorbs
   pending defer markers. */
module Ast _finish(Compiler c, Ast ast) {
  match (ast) {
    case %(seq *items):
      return %(seq @(_sequence(c, items, 0)));
    case %(parens (at ?origin ?inner)):
      return _step(c, %(at $origin (parens $inner)));
    case %(parens (block *body)):
      return %(parens $(_block_node(c, body, 1)));
    case $source_block_content(%(*body)): return _block_node(c, body, 0);
  }
  return _children(c, ast);
}

/* Only top-level and block sequences absorb `(seq ...)` replacements.
   Children transform left to right, then reverse assembly preserves source
   order while allocating generated splice origins from right to left. */
static Ast _sequence(Compiler c, Ast ast, int value_tail) {
  Array transformed = auto [];
  for (List cursor = ast; cursor; cursor = cursor.cdr())
    transformed.push(
      _sequence_item(c, cursor.car(), value_tail && !cursor.cdr()));
  Ast tail = NULL;
  for (int i = (int) transformed.len() - 1; i >= 0; i--)
    tail = _sequence_tail(c, transformed[i], tail);
  return tail;
}

static Ast _sequence_item(Compiler c, Ast value, int value_tail) {
  Ast lowered;
  match (Ast.without_origin(value)) {
    case %(stmnt ?expr) if (value_tail):
      lowered = _statement_value(c, value, expr);
    case %(defer ?): lowered = value;
    default: lowered = _step(c, value);
  }
  if (!c.fn_name) lowered = c.lower_cleanup(lowered);
  return lowered;
}

static Ast _statement_value(Compiler c, Ast value, Var expression) {
  Ast result = _step(c, Ast.rewrap_origin(value, expression));
  return Ast.rewrap_origin(result, %(stmnt $(Ast.without_origin(result))));
}

static Ast _sequence_tail(Compiler c, Ast node, Ast tail) {
  match (node) {
    case %(at ?parent ?): return _anchored_sequence(c, node, tail, parent);
    case %(seq *items): return items.append(tail);
  }
  return cons(node, tail);
}

static Ast _anchored_sequence(
  Compiler c, Ast node, Ast tail, Var parent) {
  match (Ast.without_origin(node))
    case %(seq *items): return _splice_items(c, items, parent).append(tail);
  return cons(node, tail);
}

static List _splice_items(Compiler c, List items, Var parent) {
  Array anchored = [];
  foreach (List item in items) {
    c.origins.push(%(generated $parent splice));
    int generated = c.origins.len();
    anchored.push(%(at $generated $item));
  }
  return anchored.list_free();
}

static Ast _children(Compiler c, Ast ast) {
  List child;
  $ast.rewrite_children(ast, child, _step(c, child));
}

/* node rewrites

   Callers supply bound, typed canonical nodes, and each helper builds the
   normalized shape the emitter consumes. A helper rewrites only its current
   node: `_step` recurses into returned children, while `_sequence` alone
   splices `(seq ...)` results into a sequence. */

/* A position wrapper lowers its node at that origin, and a changed node
   gets a generated origin. */
static Ast _at_node(Compiler c, Ast ast, int occurrence, List inner) {
  List transformed = NULL;
  with (c.origin = occurrence) {
    transformed = _step(c, inner);
  }
  if (transformed == inner) return ast;
  c.origins.push(%(generated $occurrence xform));
  int generated = c.origins.len();
  return %(at $generated $transformed);
}

/* A function rule sees the bound and typed definition before its body
   lowers. Rules keyed by its return type come before those keyed by none.
   A definition the kernel or a shipped rule wrote is not source, so only
   shipped rules see it. */
static List _function_rewrite(
  Compiler c, List function, List return_type, int written) {
  struct SlotWatch shipped = {.shipped = 1};
  with (c.slot_watch = written ? &shipped : c.slot_watch) {
    List replaced = c.lower_rewrite(
      <function>, return_type, function, <unit>, NULL, NULL);
    return replaced ? replaced : c.lower_rewrite(
      <function>, <any>, function, <unit>, NULL, NULL);
  }
}

/* A definition that `kernel` marks as written lowers as one the source
   wrote, except that only shipped rules see it. */
static Ast _written_function(Compiler c, List function) {
  (List return_type, List declarator, List body) = function.cdr();
  return _function_node(
    c, %(function $return_type $declarator $body), return_type, declarator,
    declarator.cadr(), body, 1);
}

static Ast _function_node(
  Compiler c, List function, List return_type, List declarator,
  List binding, List body, int written) {
  List replaced = _function_rewrite(c, function, return_type, written);
  if (replaced) return replaced;
  String owner = Ast.binding_spelling(binding);
  Var stored_owner;
  int callback =
    c.semantic_binding_facts().try_get(%(defer-ownr $binding), stored_owner);
  if (callback) owner = stored_owner;
  Type function_type = return_type;
  int inline_header = function_type.is_inline() && !function_type.is_static();
  List transformed;
  with (c.fn_name = owner, c.inline_header = inline_header) {
    List new_return = _step(c, return_type);
    List new_decl = _step(c, declarator);
    List declaration = %(declare $return_type (bindings $declarator));
    List new_body =
      _entered_body(c, declaration, body, callback);
    transformed = %(function $new_return $new_decl $new_body);
  }
  return transformed;
}

/* Lowers the block `body` of the function `declaration`, preceded by the
   code that rules placed at the function's entry while it lowered. A
   `defer` in that code covers the body, as one written first in it would.
   A `return` that a replacement binds converts to the declared result.
   Entry code lowers with the function still entered, so a placement its
   lowering makes lands at the entry too, ahead of it. A `callback` is a
   finalizer the kernel wrote, whose entry no program rule may place at. */
static List _entered_body(
  Compiler c, List declaration, List body, int callback) {
  int depth = c.enter_function(declaration, callback);
  List lowered, items = NULL;
  with (c.return_type = Ast.declared_return(declaration)) {
    lowered = _step(c, body);
    for (List entry = c.function_entry(depth); entry;
         entry = c.function_entry(depth))
      items = _sequence(c, entry, 0).append(items ? items : lowered.cdr());
  }
  c.exit_function(depth);
  if (!items) return lowered;
  List deferred = c.rewrite_defer_list(items);
  if (deferred != items) items = _sequence(c, deferred, 0);
  return source_block_content(items);
}

static Ast _defer_node(Compiler c, Ast ast) {
  match (ast)
    case %(defer ?finalizer):
      return c.lower_defer_region(source_block_content(%()), finalizer);
  return ast;
}

/* A value block lowers its final expression as a value, including an
   assignment whose ordinary statement form discards its result. */
static Ast _block_node(
  Compiler c, List statements, int value_tail) {
  List body = c.rewrite_defer_list(statements);
  List lowered = _sequence(c, body, value_tail);
  List deferred = c.rewrite_defer_list(lowered);
  if (deferred != lowered) lowered = _sequence(c, deferred, value_tail);
  return source_block_content(lowered);
}

/* A raise takes its statement rule's replacement. A raise its rules leave
   lowers its parts in source order. All of it builds its literals when it
   runs, never in constructors. */
static Ast _raise_node(Compiler c, Ast ast) {
  with (c.runtime_literals = 1) {
    List rewritten = _statement_rewrite(c, ast, <raise>);
    if (rewritten !== ast) ast = rewritten;
    else {
      ast = _children(c, ast);
      match (ast)
        case %(raise ?cause (args *arguments)):
          ast = _ordered_raise(c, cause, arguments);
    }
  }
  return ast;
}
