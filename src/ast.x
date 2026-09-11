/*  ast.x -- shared helpers for x2c compiler AST nodes

    Keeps sequence placement in one place. Simple fixed-shape nodes remain
    direct immutable `List`s.
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
#include "symbolset.x"

/* A binding node couples source spelling to a positive compiler-issued
   identity. Semantic lookup uses the identity, while emission and diagnostics
   recover the spelling; equal spellings in different scopes remain distinct.
*/
/** Constructs a `(binding identity spelling)` node.
    The caller must supply a positive compiler-issued identity.
*/
List binding_identity_new(int identity, String spelling) =>
  %(binding $identity $spelling);

/** Extracts a valid `(binding positive-integer string)` node.
    Returns one on success and writes only non-`NULL` outputs; failure returns
    zero without changing either output.
*/
int binding_identity_try_parts(List binding, int *identity, String *spelling) {
  match (binding)
    case %(binding ?id ?(String name)): {
      if (!id.is_integer() || id.integer() <= 0) return 0;
      if (identity) *identity = id.integer();
      if (spelling) *spelling = name;
      return 1;
    }
  return 0;
}

/** Returns a valid binding node's source spelling, or `NULL`. */
String binding_identity_spelling(List binding) {
  String spelling = NULL;
  return binding_identity_try_parts(binding, NULL, &spelling)
       ? spelling : NULL;
}

/* Each row pairs a compound assignment `X=` with the binary `X` it computes.
   `_compound_lookup` reads the table in either direction. */
static const Symbol compound_operators[][2] = {
  { <+=>, <+> },   { <-=>, <-> }, { <*=>, <*> },     { </=>, </> },
  { <%=>, <%> },   { <&=>, <&> }, { <^=>, <^> },     { <|=>, <"|"> },
  { <"<<=">, <"<<"> },            { <">>=">, <">>"> },
  { <@=>, <@> }
};

static Symbol _compound_lookup(Symbol op, int column) {
  int count = sizeof(compound_operators) / sizeof(compound_operators[0]);
  for (int i = 0; i < count; i++)
    if (compound_operators[i][column] == op)
      return compound_operators[i][1 - column];
  return 0;
}

/** Returns the binary operator computed by a compound assignment, or zero. */
Symbol Symbol.compound_operator(Symbol op) => _compound_lookup(op, 0);

/** Returns the compound assignment for a binary operator, or zero. */
Symbol Symbol.compound_assignment(Symbol op) => _compound_lookup(op, 1);

/** Returns whether `op` is plain or compound assignment. */
int Symbol.is_assignment_op(Symbol op) =>
  op == <=> || op.compound_operator() != 0;

/** Returns whether `op` writes its left operand. */
int ast_changes_left_operand(Symbol op) =>
  op == <++> || op == <--> || op.is_assignment_op();

/** Returns whether any list under `value` has `kind` as its head. The
    worklist keeps deeply nested operator chains off the C stack. */
int ast_contains_head(Var value, Symbol kind) {
  Array pending = $auto(%[]);
  pending.push(value);
  while (pending.len()) {
    Var current = pending.take_last();
    if (current is not <list> || current.is_nil()) continue;
    List node = current;
    if (node.car() === kind) return 1;
    for (List cursor = node; cursor; cursor = cursor.cdr)
      if (cursor.car is <list>) pending.push(cursor.car);
  }
  return 0;
}

/** Applies `per_child` to each `List` child of `ast` and returns the node
    rebuilt from the results; non-list children pass through. When no child
    changed, no scratch storage is allocated and `ast` itself returns, so the
    fixed-point transform driver can compare unchanged-node identity.
*/
Ast Ast.rewrite_children(Ast ast, Func per_child) {
  Var child;
  $ast.rewrite_children(ast, child, per_child(child.list()));
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

// A literal raise names its cause in place, so emission can tell whether the
// Error runtime can let that raise resume.
static int _raise_never_returns(Ast node) {
  Var code_ast = node.cadr();
  if (code_ast is not <list>) return 0;
  match (code_ast)
    case %(expr ("Symbol") (literal ("Symbol") ? ?code)):
      return nonreturning_error_causes.contains(code);
  return 0;
}

static int _call_never_returns(Ast node) {
  match (node)
    case %(stmnt (expr ? (call (expr () (ident ?binding)) (args *)))): {
      String name = binding_identity_spelling(binding);
      return name == "abort" || name == "exit" || name == "_Exit" ||
             name == "quick_exit";
    }
  return 0;
}

static int _contains_return(Ast node) {
  Var head = node.car();
  if (head is <symbol>) {
    if (head == <return>) return 1;
    if (head == <function>) return 0;
  }
  foreach (Var head, node)
    if (head is <list> && _contains_return(head)) return 1;
  return 0;
}

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

/** Returns initializer alternatives and their optional native macro input. */
List Ast.initializer_cases(Ast ast, List *input) {
  *input = NULL;
  match (ast)
    case %(initval (!set ?header (input *)) *cases): {
      *input = header;
      return cases;
    }
  return ast.cdr();
}

/** Returns function alternatives when every initializer arm calls one shared
    input, and stores that input expression in `source`. Other forms return NULL.
*/
List Ast.initializer_functions(Ast ast, List *source) {
  List header = NULL;
  List cases = Ast.initializer_cases(ast, &header);
  if (!header || header.cdr().len() != 1) return NULL;
  List input = header.cadr();
  List value = input.cadr();
  List argument = %(expr ${value.cadr()} ${input.car()});
  Array functions = %[];
  foreach (List choice, cases) {
    (List condition, List path, List destination, List expression) = choice;
    match (expression) {
      case %(expr ? (call (!set ?callee (expr ? ?)) (args ?actual))): {
        if (actual !== argument) { functions.free(); return NULL; }
        List function = callee;
        functions.push(%($condition $path ${function.cadr()} $function));
      }
      default: { functions.free(); return NULL; }
    }
  }
  *source = value;
  return functions.list_free();
}
