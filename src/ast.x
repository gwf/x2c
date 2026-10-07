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

#include "error-macros.x"
#include "ast-rewrite.x"
#include "grammar.x"
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

// declarators

/** Returns `declarator` with the outermost `volatile` removed from each of
    its parameters. C ignores a parameter's top-level qualifier when it
    compares a prototype with its definition, and the qualifier the error
    transfer requires belongs to the definition that writes the parameter,
    not to the declaration its callers read.
*/
List ast_prototype_declarator(List declarator) {
  Array modifiers = [], int changed = 0;
  foreach (Var modifier, declarator.caddr()) {
    match (modifier)
      case %(fnmod (params *parameters)):
        modifier = _prototype_params(parameters, changed);
    modifiers.push(modifier);
  }
  if (!changed) {
    modifiers.free();
    return declarator;
  }
  return %(bind ${declarator.cadr()} ${modifiers.list_free()});
}

/* The function modifier for `parameters`, each without its outermost
   `volatile`; `changed` becomes 1 when one had it. */
static List _prototype_params(List parameters, int &changed) {
  Array rebuilt = [];
  foreach (List parameter, parameters) {
    match (parameter)
      case %(param ?type (bind ?name (volatile *rest))): {
        parameter = %(param $type (bind $name (@rest)));
        changed = 1;
      }
    rebuilt.push(parameter);
  }
  return %(fnmod (params @{rebuilt.list_free()}));
}

// designated nodes

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

/** Returns the name whose address an expression takes, or `NULL`. */
String ast_addressed_identifier(Var value) {
  if (value is not <list>) return NULL;
  List ast = value;
  match (ast) {
    case %(expr ? ?inner): return ast_addressed_identifier(inner);
    case ${$grouped(?inner)}:
      return ast_addressed_identifier(inner);
    case ${$addressed(?inner)}:
      return ast_direct_identifier(inner);
  }
  return NULL;
}

/** Returns the name an expression designates directly, following the forms
    that still name the same object - parentheses, a member, an array index,
    a dereference - or `NULL` when the expression designates no single name.
    A declaration qualifier that must reach one object, such as the `volatile`
    an error transfer requires, applies to this name.
*/
String ast_direct_identifier(Var value) {
  List designated = Ast.designated(value);
  match (designated) {
    case $source_identifier_content(%(?binding)):
      return binding_identity_spelling(binding);
    case $source_operator_content(%((!quote ->) ?base *)):
      return ast_addressed_identifier(base);
    case ${$dereferenced(?base)}:
      return ast_addressed_identifier(base);
  }
  return NULL;
}

/** Returns the name of the pointer an expression designates through, or
    `NULL` when it designates no object through a single name. `*pointer`,
    `pointer[index]`, and `pointer->member` all change the object the pointer
    holds, which `ast_direct_identifier` reports as no name at all.
*/
String ast_indirect_identifier(Var value) {
  List designated = Ast.designated(value);
  match (designated) {
    case ${$indexed(%(!set ?base (expr ? ?)), ?)}:
      return ast_direct_identifier(base);
    case $source_operator_content(%((!quote ->) ?base *)):
      return ast_direct_identifier(base);
    case ${$dereferenced(?base)}:
      return ast_direct_identifier(base);
  }
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
  match (Ast.without_origin(ast)) {
    case %(raise (expr ("Symbol") ${$source_literal_content(
              %(("Symbol") ? ?code))}) *):
      return code in nonreturning_error_causes;
    case %(stmnt (expr ? ${$called(%(expr () (ident ?binding)), %(*))})):
      return binding_identity_spelling(binding) in terminating_calls;
    case %(block *items):
      return items && !_contains_return(items) &&
             items.last() is <list> && ((Ast) items.last()).never_returns();
  }
  return 0;
}

static const SymbolSet nonreturning_error_causes =
  $error.nonreturning.causes();

static List terminating_calls =
  %("abort" "exit" "_Exit" "_exit" "quick_exit");

/* A `return` anywhere in `items`, outside a nested function. */
static int _contains_return(List items) {
  List node;
  $ast.walk(items, node) {
    if (node.car() == <function>) continue;
    if (node.car() == <return>) return 1;
  }
  return 0;
}

// operators

/* operator-ledger.x owns these methods in a separate implementation unit. */
// lint: allow src-forward-declaration FI-6: leaf ledger binding
Symbol Symbol.compound_operator(Symbol op);

// lint: allow src-forward-declaration FI-6: leaf ledger binding
Symbol Symbol.compound_assignment(Symbol op);

// lint: allow src-forward-declaration FI-6: leaf ledger binding
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
