/*  ast.x -- shared helpers for x2c compiler AST nodes

    Simple fixed-shape nodes remain direct immutable `List`s. This module
    holds the node operations that several compiler phases share.
*/

#pragma once

/** Represents one compiler AST node as a canonical immutable `List`.
    `NULL` denotes no node, and nonempty nodes have the canonical `List`-pool
    lifetime.
*/
typedef List Ast;

/** Names the syntactic position in which an AST is parsed or bound. */
typedef enum AstPos {
  AST_UNIT,
  AST_BLOCK,
  AST_FIELD,
  AST_ENUMERATOR,
  AST_MAP_ENTRY,
  AST_STATEMENT,
  AST_EXPRESSION
} AstPos;

#pragma private

$(import "../lib/error-macros.xmacro")
$(import "../src/ast-rewrite.xmacro")
$(import "../src/grammar.xmacro")
#include "symbolset.x"

/* binding nodes

   A binding node couples source spelling to a positive compiler-issued
   identity. Semantic lookup uses the identity, while emission and
   diagnostics recover the spelling; equal spellings in different scopes
   remain distinct. */

/** Constructs a `(binding identity spelling)` node.
    The caller must supply a positive compiler-issued identity.
*/
List binding_identity_new(int identity, String spelling) =>
  %(binding $identity $spelling);

/** Extracts a valid `(binding positive-integer string)` node.
    Returns one on success and writes only non-`NULL` outputs; failure returns
    zero without changing either output.
*/
int binding_identity_try_parts(
  List binding, int &?identity, String &?spelling) {
  match (binding)
    case %(binding ?id ?(String name)): {
      if (!id.is_integer() || id.integer() <= 0) return 0;
      if (identity) identity = id;
      if (spelling) spelling = name;
      return 1;
    }
  return 0;
}

/** Returns a valid binding node's source spelling, or `NULL`. */
String binding_identity_spelling(List binding) {
  String spelling = NULL;
  return binding_identity_try_parts(binding, NULL, spelling) ? spelling : NULL;
}

/** Returns the innermost node `value` designates, past the forms that still
    name the same object: an `expr` wrapper, parentheses, a member, and an
    index into an array. What remains is a name, a designation through a
    pointer, or another expression; a non-list designates nothing.
*/
List Ast.designated(Var value) {
  while (value is <list>) {
    List node = value;
    match (node) {
      case %(expr ? ?inner): value = inner;
      case ${$grouped(?inner)}: value = inner;
      case ${$indexed(%(!set ?base (expr ((dim *) *) ?)), ?)}:
        value = base;
      case $source_operator_content(%(. ?base *)): value = base;
      default: return node;
    }
  }
  return NULL;
}

/** Returns the binding whose stored object the lvalue `ast` names, or
    `NULL`. Pointer dereferences and pointer indexes name another object; an
    array field remains part of its containing aggregate.
*/
List Ast.lvalue_binding(Ast ast) {
  List designated = Ast.designated(ast);
  match (designated)
    case $source_identifier_content(%(?binding)): return binding;
  return NULL;
}

/** Returns the operand a write `node` changes: the left operand of an
    assignment or prefix update, or the operand of a postfix update; `NULL`
    when `node` writes no operand.
*/
List Ast.written_operand(Ast node) {
  match (node) {
    case $source_operator_content(%(?operator ?target *)):
      if (operator is <symbol> && ast_changes_left_operand(operator))
        return target;
    case $source_postfix_content(%(? ?target)): return target;
  }
  return NULL;
}

// traversal

/** Applies `per_child` to each `List` child of `ast` and returns the node
    rebuilt from the results; non-list children pass through. When no child
    changed, no scratch storage is allocated and `ast` itself returns, so the
    fixed-point transform driver can compare unchanged-node identity.
*/
Ast Ast.rewrite_children(Ast ast, Func per_child) {
  Var child;
  $ast.rewrite_children(ast, child, per_child(child.list()));
}

/** Returns whether any list under `value` has `kind` as its head. */
int ast_contains_head(Var value, Symbol kind) {
  List node;
  $ast.walk(value, node) if (node.car() === kind) return 1;
  return 0;
}

/** Records in `referenced` the identity of every binding `node` names. */
void ast_collect_binding_references(Var node, Map referenced) {
  if (node is not <list>) return;
  List syntax = node;
  // A definition's own binder is a `bind`, so a function does not name itself.
  match (syntax) case $source_identifier_content(
      %((binding ?identity ?))): {
    referenced[identity] = 1;
    return;
  }
  foreach (Var child, syntax)
    ast_collect_binding_references(child, referenced);
}

// source anchors

/** Returns `ast` without the `(at ORIGIN ...)` anchors it arrived wrapped
    in. Every block statement carries one so that a transform-phase
    diagnostic can name its line; a pass that dispatches on a statement tag
    has to see the statement, not the anchor.
*/
Ast Ast.without_origin(Ast ast) {
  while (ast) {
    match (ast) {
      case %(at ? ?inner): ast = inner;
      default: return ast;
    }
  }
  return ast;
}

/** Returns `replacement` under the anchors of `original`, the statement it
    replaces, so a rewrite does not lose the node's source position. */
Ast Ast.rewrap_origin(Ast original, Ast replacement) {
  match (original)
    case %(at ?origin ?inner):
      return %(at $origin ${Ast.rewrap_origin(inner, replacement)});
  return replacement;
}

// code that never returns

/** Returns whether control cannot flow out the bottom of `ast`.
    Recognized terminals are shared non-returning raises, native termination
    calls, and blocks ending in either one when the block contains no
    `return`. Generation uses this fact to mark the enclosing function
    `_Noreturn`.
*/
int Ast.never_returns(Ast ast) {
  List node = _unwrap_origin(ast);
  if (!node || node.car() is not <symbol>) return 0;
  Symbol head = node.car();
  if (head == <raise>) return _raise_never_returns(node);
  if (head == <stmnt>) return _call_never_returns(node);
  if (head != <block> || _contains_return(node)) return 0;
  Var last = node.last();
  if (last is not <list>) return 0;
  Ast terminal = last;
  return terminal.never_returns();
}

static Ast _unwrap_origin(Ast node) {
  while (node && node.car() == <at>) {
    match (node)
      case %(at ?origin (!is type list)) if (origin.is_integer()): {
        node = node.caddr();
        continue;
      }
    return NULL;
  }
  return node;
}

static const SymbolSet nonreturning_error_causes =
  $error.nonreturning.causes();

/* A literal raise names its cause in place, so emission can tell whether the
   Error runtime can let that raise resume. */
static int _raise_never_returns(Ast node) {
  Var code_ast = node.cadr();
  if (code_ast is not <list>) return 0;
  match (code_ast)
    case %(expr ("Symbol") ${$source_literal_content(
        %(("Symbol") ? ?code))}):
      return code in nonreturning_error_causes;
  return 0;
}

static int _call_never_returns(Ast node) {
  match (node)
    case %(stmnt (expr ? ${$called(%(expr () (ident ?binding)), %(*))})): {
      String name = binding_identity_spelling(binding);
      return name == "abort" || name == "exit" || name == "_Exit" ||
             name == "_exit" || name == "quick_exit";
    }
  return 0;
}

static int _contains_return(Ast node) {
  Var head = node.car();
  if (head is <symbol>) {
    if (head == <return>) return 1;
    if (head == <function>) return 0;
  }
  foreach (Var child, node)
    if (child is <list> && _contains_return(child)) return 1;
  return 0;
}

// operators

Symbol Symbol.compound_operator(Symbol op);

Symbol Symbol.compound_assignment(Symbol op);

int Symbol.binary_precedence(Symbol op);

/** Returns whether `op` is plain or compound assignment. */
int Symbol.is_assignment_op(Symbol op) =>
  op == <=> || op.compound_operator() != 0;

/** Returns whether `op` writes its left operand. */
int ast_changes_left_operand(Symbol op) =>
  op == <++> || op == <--> || op.is_assignment_op();

// initializer alternatives

/** Returns initializer alternatives and their optional native macro input. */
List Ast.initializer_cases(Ast ast, List &input) {
  input = NULL;
  match (ast)
    case %(initval (!set ?header (input *)) *cases): {
      input = header;
      return cases;
    }
  return ast.cdr();
}

/** Returns function alternatives when every initializer arm calls one shared
    input, and stores that input expression in `source`. Other forms return
    NULL.
*/
List Ast.initializer_functions(Ast ast, List &source) {
  List header = NULL;
  List cases = ast.initializer_cases(header);
  if (!header || header.cdr().len() != 1) return NULL;
  List input = header.cadr();
  List value = input.cadr();
  List argument = %(expr ${value.cadr()} ${input.car()});
  Array functions = $auto([]);
  foreach (List choice, cases) {
    List function = _arm_function(choice, argument);
    if (!function) return NULL;
    functions.push(function);
  }
  source = value;
  return functions;
}

/* One arm as the case `(condition path type callee)` when the arm calls
   `callee` with `argument`, or `NULL`. */
static List _arm_function(List choice, List argument) {
  (List condition, List path, List destination, List expression) = choice;
  match (expression)
    case %(expr ? ${$called(
        %(!set ?callee (expr ?callee_type ?)), %(?actual))}): {
      if (actual !== argument) return NULL;
      return %($condition $path $callee_type $callee);
    }
  return NULL;
}
