/*  binding-facts.x -- binding facts

   Facts about bindings share one map, keyed by rows such as
   `(emitted BINDING)` and `(completion BINDING)`. */

/** Returns a binding's selected emitted spelling.

    A binding without an explicit emission rename uses its identity spelling.
*/
String Compiler.emitted_binding_name(Compiler c, List binding) {
  Var renamed;
  Map facts = c.semantic_binding_facts();
  if (facts.try_get(%(emitted $binding), renamed)) return renamed;
  return Ast.binding_spelling(binding);
}

/** Returns the optional references proven present in this lexical path. */
List Compiler.present_references(Compiler c) =>
  c.fact(%(present-references));

/** Records a nonnull optional parameter for the current lexical path. */
void Compiler.mark_reference_present(Compiler c, List binding) {
  List present = c.present_references();
  if (!(binding in present))
    c.set_fact(%(present-references), cons(binding, present));
}

/** Marks the optional references that `condition` proves present after an
    `if` whose arm for the other outcome cannot fall through. A missing `no`
    arm falls through.
*/
void Compiler.settle_condition(Compiler c, List condition, List yes, List no) {
  _settle(c, c.proven_references(condition, 1), no);
  _settle(c, c.proven_references(condition, 0), yes);
}

static void _settle(Compiler c, List proven, List other_arm) {
  if (proven && Ast.reference_guard_exits(other_arm))
    foreach (List binding in proven) c.mark_reference_present(binding);
}

/** Marks the optional references that `condition` proves present for an
    operand that runs only when `condition` has truth `holds`. Returns the
    facts to restore after the operand.
*/
List Compiler.assume_condition(Compiler c, List condition, int holds) {
  List before = c.present_references();
  foreach (List binding in c.proven_references(condition, holds))
    c.mark_reference_present(binding);
  return before;
}

/** Restores the optional-reference facts saved before a lexical path. */
void Compiler.restore_reference_presence(Compiler c, List before) {
  if (before === c.present_references()) return;
  if (before) c.set_fact(%(present-references), before);
  else c.drop_fact(%(present-references));
}

/** Returns the optional-reference parameters that `condition` proves the
    caller supplied when it has truth `holds`. Direct truth and null tests
    prove presence, and `&&` and `||` combine their operands' proofs.
*/
List Compiler.proven_references(Compiler c, List condition, int holds) {
  match (condition) {
    case %(expr ? $($grouped(?inner))):
      return c.proven_references(inner, holds);
    case %(expr ? (op ! ?operand)):
      return c.proven_references(operand, !holds);
    case %(expr ? (op (!or ?op && ||) ?left ?right)):
      return _junction(c, op, left, right, holds);
    case %(expr ? (op (!or ?op == !=) ?left ?right)):
      return _null_comparison(c, op, left, right, holds);
    case %(expr (opt-ref *) (ident ?binding)):
      if (holds &&
          %(optional-reference-param $binding) in c.semantic_binding_facts())
        return %($binding);
  }
  return NULL;
}

/* A conjunction keeps its operands' proofs when it holds and a disjunction
   when it fails, the only outcomes that require every operand's result. */
static List _junction(Compiler c, Var op, Var left, Var right, int holds) {
  if (holds != (op == <&&>)) return NULL;
  return c.proven_references(left, holds).append(
    c.proven_references(right, holds));
}

/* A comparison with a null literal tests the other operand; `==` inverts
   the outcome that proves presence. */
static List _null_comparison(
  Compiler c, Var op, Var left, Var right, int holds) {
  List operand = right;
  if (_null_literal(right)) operand = left;
  else if (!_null_literal(left)) return NULL;
  return c.proven_references(operand, op == <==> ? !holds : holds);
}

static int _null_literal(List expr) {
  match (expr) {
    case %(expr ? $($grouped(?inner))):
      return _null_literal(inner);
    case %(expr ? (ident (binding ? "NULL"))): return 1;
    case %(expr ? (literal ? "0")): return 1;
  }
  return 0;
}
