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

/** Marks the optional reference `binding` present after an `if` when the
    arm that runs without it cannot fall through: `no` when the true arm
    proves presence, `yes` otherwise. A missing `no` arm falls through.
*/
void Compiler.settle_reference(
  Compiler c, List binding, int true_is_present, List yes, List no) {
  if (binding && Ast.reference_guard_exits(true_is_present ? no : yes))
    c.mark_reference_present(binding);
}

/** Restores the optional-reference facts saved before a lexical path. */
void Compiler.restore_reference_presence(Compiler c, List before) {
  if (before === c.present_references()) return;
  if (before) c.set_fact(%(present-references), before);
  else c.drop_fact(%(present-references));
}

/** Returns the optional-reference parameter tested by `condition`, or NULL.
    `truth` is set to whether the condition's true arm proves that the caller
    supplied an object. Only a direct truth or null test proves presence.
*/
List Compiler.optional_reference_test(
  Compiler c, List condition, int &truth) {
  match (condition) {
    case %(expr ? $($grouped(?inner))):
      return c.optional_reference_test(inner, truth);
    case %(expr ? $($source_operator_content(%(! ?operand)))): {
      truth = !truth;
      return c.optional_reference_test(operand, truth);
    }
    case %(expr ? $($source_operator_content(
        %((!or ?op == !=) ?left ?right)))):
      return _null_comparison(c, op, left, right, truth);
    case %(expr (opt-ref *) $($source_identifier_content(%(?binding)))):
      if (%(optional-reference-param $binding) in
          c.semantic_binding_facts()) return binding;
  }
  return NULL;
}

/* A comparison with a null literal tests the other operand; its true arm
   proves presence for `!=`. */
static List _null_comparison(
  Compiler c, Var op, Var left, Var right, int &truth) {
  if (_null_literal(right)) {
    truth = op == <!=>;
    return c.optional_reference_test(left, truth);
  }
  if (!_null_literal(left)) return NULL;
  truth = op == <!=>;
  return c.optional_reference_test(right, truth);
}

static int _null_literal(List expr) {
  match (expr) {
    case %(expr ? $($grouped(?inner))):
      return _null_literal(inner);
    case %(expr ? $($source_identifier_content(
        %((binding ? "NULL"))))): return 1;
    case %(expr ? $($source_literal_content(%(? "0")))): return 1;
  }
  return 0;
}
