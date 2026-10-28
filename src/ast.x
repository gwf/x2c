/*  ast.x -- shared helpers for x2c compiler AST nodes

    Simple fixed-shape nodes remain direct immutable `List`s. This module
    holds the node operations that several compiler phases share.
*/

#pragma once

#include "error-macros.x"
#include "ast-rewrite.x"
#include "grammar.x"
#include "symbolset.x"

static const SymbolSet nonreturning_error_causes =
  nonreturning_causes;

static List terminating_calls =
  %("abort" "exit" "_Exit" "_exit" "quick_exit");

// inspection

/** Prints bound AST nodes with stable binding numbers and compact macro
    definitions. Binding numbers follow their first appearance in `ast`.
*/
void Ast.print_dump(List ast) {
  foreach (List node in _renumbered_bindings(ast))
    printf("\n%s\n", _node_repr(node));
}

/* A binding number counts every binding the unit has issued, collection's
   included, so it depends on whether the includes replayed or were parsed
   cold. A dump numbers bindings by their first appearance in its text. */
static List _renumbered_bindings(List ast) {
  Map numbers = {}, replaced = {};
  Array pending = auto [ast];
  while (pending.len()) {
    Var node = pending.take_last();
    if (node is not <list> || node.is_nil()) continue;
    if (node.list() ~= %(binding ?identity ?spelling)) {
      Var number;
      if (!numbers.try_get(identity, number)) {
        number = (int) numbers.len() + 1;
        numbers[identity] = number;
      }
      replaced[(void *) node.list()] =
        %(binding $number $spelling);
      continue;
    }
    foreach (Var child in node.list().reverse()) pending.push(child);
  }
  return Ast.replace_nodes(ast, replaced);
}

static String _node_repr(List node) {
  if (node ~= %(macrodef (name ?name) *))
    return %"(macrodef <macro $name>)";
  return node.repr();
}

// operators

/* operator-ledger.x owns these methods in a separate implementation unit. */
// lint: allow src-forward-declaration FI-6: leaf ledger binding
Symbol Symbol.compound_operator(Symbol op);

// lint: allow src-forward-declaration FI-6: leaf ledger binding
Symbol Symbol.compound_assignment(Symbol op);

// lint: allow src-forward-declaration FI-6: leaf ledger binding
int Symbol.binary_precedence(Symbol op);

/* binding nodes

   A binding node couples source spelling to a positive compiler-issued
   identity. Semantic lookup uses the identity, while emission and
   diagnostics recover the spelling; equal spellings in different scopes
   remain distinct. */

/** Constructs a `(binding identity spelling)` node.
    The caller must supply a positive compiler-issued identity.
*/
List Ast.binding(int identity, String spelling) =>
  %(binding $identity $spelling);

// declarators

/** Returns `declarator` with `modifiers` after its own, as a declaration
    whose base contributes modifiers declares each name.
*/
List Ast.append_modifiers(List declarator, List modifiers) =>
  declarator_append_modifiers(declarator, modifiers);

/** Returns `declarator` with the outermost `volatile` removed from each of
    its parameters. C ignores a parameter's top-level qualifier when it
    compares a prototype with its definition, and the qualifier the error
    transfer requires belongs to the definition that writes the parameter,
    not to the declaration its callers read.
*/
List Ast.prototype_declarator(List declarator) {
  Array modifiers = [], int changed = 0;
  foreach (Var modifier in declarator.caddr()) {
    match (modifier)
      case %(fnmod (params *parameters)):
        modifier = _prototype_params(parameters, changed);
    modifiers.push(modifier);
  }
  if (!changed) {
    modifiers.free();
    return declarator;
  }
  return %(bind $(declarator.cadr()) $(modifiers.list_free()));
}

// designated nodes

/** Returns the binding whose stored object the lvalue `ast` names, or
    `NULL`. Pointer dereferences and pointer indexes name another object; an
    array field remains part of its containing aggregate.
*/
List Ast.lvalue_binding(Ast ast) {
  List designated = _designated(ast);
  match (designated)
    case %(ident ?binding): return binding;
  return NULL;
}

/** Returns the name of the pointer an expression designates through, or
    `NULL` when it designates no object through a single name. `*pointer`,
    `pointer[index]`, and `pointer->member` all change the object the pointer
    holds, which `Ast.direct_identifier` reports as no name at all.
*/
String Ast.indirect_identifier(Var value) {
  List designated = _designated(value);
  match (designated) {
    case $($indexed(%(!set ?base (expr ? ?)), ?)):
      return Ast.direct_identifier(base);
    case %(op (!quote ->) ?base *):
      return Ast.direct_identifier(base);
    case $($dereferenced(?base)):
      return Ast.direct_identifier(base);
  }
  return NULL;
}

/** Returns the name whose address an expression takes, or `NULL`. */
String Ast.addressed_identifier(Var value) {
  if (value is not <list>) return NULL;
  List ast = value;
  match (ast) {
    case %(expr ? ?inner): return Ast.addressed_identifier(inner);
    case $($grouped(?inner)):
      return Ast.addressed_identifier(inner);
    case $($addressed(?inner)):
      return Ast.direct_identifier(inner);
  }
  return NULL;
}

/** Returns the name of the stored object an expression designates directly.
    Parentheses, aggregate members, and native array indexes keep their
    containing object's name. A dereference or pointer member keeps that name
    only when its operand takes the object's address. Other expressions
    return `NULL`.
    A declaration qualifier that must reach one object, such as the `volatile`
    an error transfer requires, applies to this name.
*/
String Ast.direct_identifier(Var value) {
  List designated = _designated(value);
  match (designated) {
    case %(ident ?binding):
      return Ast.binding_spelling(binding);
    case %(op (!quote ->) ?base *):
      return Ast.addressed_identifier(base);
    case $($dereferenced(?base)):
      return Ast.addressed_identifier(base);
  }
  return NULL;
}

/** Returns the operand a write `node` changes: the left operand of an
    assignment or prefix update, or the operand of a postfix update; `NULL`
    when `node` writes no operand.
*/
List Ast.written_operand(Ast node) {
  match (node) {
    case %(op ?operator ?target *):
      if (operator is <symbol> && Symbol.changes_left_operand(operator))
        return target;
    case %(postfix ? ?target): return target;
  }
  return NULL;
}

// traversal

/** Returns whether any list under `value` has `kind` as its head. */
int Ast.contains_head(Var value, Symbol kind) {
  List node;
  $ast.walk(value, node) if (node.car() === kind) return 1;
  return 0;
}

/** Returns `root` with each list beneath it that `replaced` maps, keyed
    by its address, swapped for its value, and adds each rebuilt ancestor
    to `replaced`. Only the ancestors of a swapped list are new, so `root`
    returns itself when nothing beneath it is swapped. The walk keeps deep
    expression chains off the C stack.
*/
Var Ast.replace_nodes(Var root, Map replaced) {
  Array levels = auto [];
  List node;
  $ast.walk(root, node) {
    if (_replaced_node(node, replaced) !== node) continue;
    levels.push(node);
  }
  while (levels.len()) {
    node = levels.take_last();
    List rebuilt = _replaced_children(node, replaced);
    if (rebuilt !== node) replaced[(void *) node] = rebuilt;
  }
  return _replaced_node(root, replaced);
}

/** Records in `referenced` the identity of every binding `node` names. */
void Ast.collect_binding_references(Var node, Map referenced) {
  if (node is not <list>) return;
  List syntax = node;
  // A definition's own binder is a `bind`, so a function does not name itself.
  match (syntax) case %(ident (binding ?identity ?)): {
    referenced[identity] = 1;
    return;
  }
  foreach (Var child in syntax)
    Ast.collect_binding_references(child, referenced);
}

// source anchors

/** Returns `replacement` under the anchors of `original`, the statement it
    replaces, so a rewrite does not lose the node's source position.
*/
Ast Ast.rewrap_origin(Ast original, Ast replacement) {
  match (original)
    case %(at ?origin ?inner):
      return %(at $origin $(Ast.rewrap_origin(inner, replacement)));
  return replacement;
}

// generated support

/** Returns `decl` with each function definition marked `kernel` as written.
    The transform strips the marker before it offers the definition only to
    shipped function rules.
*/
List Ast.written_definitions(List decl) {
  match (decl) {
    case %(function ? (bind ? ?) ?): return %(function @(decl.cdr()) kernel);
    case %((!or at seq) *):
      return Ast.rewrite_children(decl, Ast.written_definitions);
  }
  return decl;
}

/** Returns the single item of a one-item `seq`, or `node` itself. */
List Ast.lone_item(List node) {
  match (node) case %(seq ?only): return only;
  return node;
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

/** Returns the statement calling the `void (void)` function `entry`. */
List Ast.entry_call(String entry) =>
  %((stmnt (expr (void) (call $entry (args)))));

// control flow

/** Returns whether `arm` ends with a return or non-returning raise. */
int Ast.reference_guard_exits(List arm) {
  if (Ast.never_returns(arm)) return 1;
  match (arm) {
    case %(return *): return 1;
    case %(at ? ?body): return Ast.reference_guard_exits(body);
    case %(block *items):
      return items && Ast.reference_guard_exits(items.last());
  }
  return 0;
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
    case %(raise (expr ("Symbol") (literal ("Symbol") ? ?code)) *):
      return code in nonreturning_error_causes;
    case %(stmnt (expr ? $($called(%(expr () (ident ?binding)), %(*))))):
      return Ast.binding_spelling(binding) in terminating_calls;
    case %(block *items):
      return items && !_contains_return(items) &&
             items.last() is <list> && ((Ast) items.last()).never_returns();
  }
  return 0;
}

/** Returns a valid binding node's source spelling, or `NULL`. */
String Ast.binding_spelling(List binding) {
  String spelling = NULL;
  return Ast.try_binding(binding, NULL, spelling) ? spelling : NULL;
}

/** Extracts a valid `(binding positive-integer string)` node.
    Returns one on success and writes only non-`NULL` outputs; failure returns
    zero without changing either output.
*/
int Ast.try_binding(List binding, int &?identity, String &?spelling) {
  if (binding ~= %(binding ?id ?(String name))) {
    if (!id.is_integer() || id.integer() <= 0) return 0;
    if (identity) identity = id;
    if (spelling) spelling = name;
    return 1;
  }
  return 0;
}

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

/** Returns `value` without source wrappers. Pending invocations and
    quotations keep their own capture rows or holes, so nested applications
    unwrap each argument once.
*/
Var Ast.source_unwrap(Var value) {
  if (value is not <list> || value.is_nil()) return value;
  match (value) {
    case %(src ? ?syntax): return Ast.source_unwrap(syntax);
    case %((!or macro-invoke "x2c.quoted") *): return value;
  }
  List child;
  $ast.rewrite_children(value.list(), child, Ast.source_unwrap(child));
}

/** Returns whether `op` writes its left operand. */
int Symbol.changes_left_operand(Symbol op) =>
  op == <++> || op == <--> || op.is_assignment_op();

/** Returns whether `op` is plain or compound assignment. */
int Symbol.is_assignment_op(Symbol op) =>
  op == <=> || op.compound_operator() != 0;

// initializer alternatives

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
  List argument = %(expr $(value.cadr()) $(input.car()));
  Array functions = auto [];
  foreach (List choice in cases) {
    List function = _arm_function(choice, argument);
    if (!function) return NULL;
    functions.push(function);
  }
  source = value;
  return functions;
}

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

// binding and traversal helpers

/* The function modifier for `parameters`, each without its outermost
   `volatile`; `changed` becomes 1 when one had it. */
static List _prototype_params(List parameters, int &changed) {
  Array rebuilt = [];
  foreach (List parameter in parameters) {
    match (parameter)
      case %(param ?type (bind ?name (volatile *rest))): {
        parameter = %(param $type (bind $name (@rest)));
        changed = 1;
      }
    rebuilt.push(parameter);
  }
  return %(fnmod (params @(rebuilt.list_free())));
}

/* Returns the innermost node `value` designates, past the forms that still
   name the same object: an `expr` wrapper, parentheses, a member, and an
   index into an array. What remains is a name, a designation through a
   pointer, or another expression; a non-list designates nothing.
*/
static List _designated(Var value) {
  while (value is <list>) {
    List node = value;
    match (node) {
      case %(expr ? ?inner): value = inner;
      case $($grouped(?inner)): value = inner;
      case $($indexed(%(!set ?base (expr ((dim *) *) ?)), ?)):
        value = base;
      case %(op . ?base *): value = base;
      default: return node;
    }
  }
  return NULL;
}

static List _replaced_children(List node, Map replaced) {
  Var child;
  $ast.rewrite_children(node, child, _replaced_node(child, replaced));
}

static Var _replaced_node(Var node, Map replaced) {
  Var swapped;
  return node is <list> && replaced.try_get((void *) node.list(), swapped)
    ? swapped : node;
}

/* A `return` anywhere in `items`, outside a nested function. */
static int _contains_return(List items) {
  List node;
  $ast.walk(items, node) {
    if (node.car() == <function>) continue;
    if (node.car() == <return>) return 1;
  }
  return 0;
}

/* One arm as the case `(condition path type callee)` when the arm calls
   `callee` with `argument`, or `NULL`. */
static List _arm_function(List choice, List argument) {
  (List condition, List path, List destination, List expression) = choice;
  match (expression)
    case %(expr ? $($called(
        %(!set ?callee (expr ?callee_type ?)), %(?actual)))): {
      if (actual !== argument) return NULL;
      return $(condition, path, callee_type, callee);
    }
  return NULL;
}
