/*  autodiff.x -- reverse-mode differentiation recorded on a runtime tape

    Copyright (c) 2026 Gary William Flake

    This optional module is included explicitly; it is not part of the
    implicit prelude. `AdTape` records every arithmetic operation on its
    `AdNode` values as a closure that propagates an adjoint back to the
    operands, so a data-dependent computation that `$ad.reverse()` cannot
    transform statically still yields a gradient. Values box through `Var`
    and each operation allocates a node, so the static decorators in
    `autodiff.xmacro` remain the fast path.
*/

#include "x2c.x"
#include <math.h>

/** A recording of `AdNode` operations; see the struct below.
    The [Automatic Differentiation guide](../../guide/autodiff.md) explains
    runtime tapes and the compile-time alternatives.
*/
typedef struct AdTape *AdTape;

/** One recorded value: its primal, its accumulated adjoint, and the closure
    that pushes that adjoint to the operands it came from.
*/
typedef struct AdNode {
  double value, adjoint;
  Func back;
  AdTape tape;
} *AdNode;

/** Records nodes in creation order so `AdTape.backward` can replay them in
    reverse. The tape and its nodes belong to the active `Scope`.
*/
struct AdTape {
  Array nodes;
};

/** Boxes a node for `Var` participation. */
Var AdNode.var(AdNode node) => Var.new(<adnode>, node);

/** Unboxes a node from a `Var` produced by `AdNode.var`. */
AdNode Var.adnode(Var value) => (AdNode) value.pointer();

/** Creates an empty tape in the active `Scope`. */
AdTape AdTape.new(void) {
  AdTape tape = Scope.malloc(sizeof(struct AdTape));
  tape.nodes = %[];
  return tape;
}

static AdNode _record(AdTape tape, double value, Func back) {
  AdNode node = Scope.malloc(sizeof(struct AdNode));
  node.value = value;
  node.adjoint = 0.0;
  node.back = back;
  node.tape = tape;
  tape.nodes.push(node);
  return node;
}

/** Records an input or constant. Read `adjoint` after `AdTape.backward`. */
AdNode AdTape.input(AdTape tape, double value) =>
  _record(tape, value, NULL);

/** Seeds `result` with adjoint 1 and propagates active adjoints to its
    operands. Zero adjoints do not invoke reverse callbacks. Earlier adjoints
    on the tape are cleared first, so repeated calls do not accumulate.
*/
void AdTape.backward(AdTape tape, AdNode result) {
  for (int i = 0; i < tape.nodes.len(); i++) {
    AdNode node = tape.nodes[i];
    node.adjoint = 0.0;
  }
  result.adjoint = 1.0;
  for (int i = tape.nodes.len() - 1; i >= 0; i--) {
    AdNode node = tape.nodes[i];
    if (node.adjoint != 0.0 && node.back) (node.back)();
  }
}

/** Sum. */
AdNode AdNode.add(AdNode a, AdNode b) {
  AdNode node = _record(a.tape, a.value + b.value, NULL);
  node.back = %!() => {
    a.adjoint += node.adjoint;
    b.adjoint += node.adjoint;
  };
  return node;
}

/** Difference. */
AdNode AdNode.sub(AdNode a, AdNode b) {
  AdNode node = _record(a.tape, a.value - b.value, NULL);
  node.back = %!() => {
    a.adjoint += node.adjoint;
    b.adjoint -= node.adjoint;
  };
  return node;
}

/** Product. */
AdNode AdNode.mul(AdNode a, AdNode b) {
  AdNode node = _record(a.tape, a.value * b.value, NULL);
  node.back = %!() => {
    a.adjoint += node.adjoint * b.value;
    b.adjoint += node.adjoint * a.value;
  };
  return node;
}

/** Quotient. */
AdNode AdNode.div(AdNode a, AdNode b) {
  AdNode node = _record(a.tape, a.value / b.value, NULL);
  node.back = %!() => {
    a.adjoint += node.adjoint / b.value;
    b.adjoint -= node.adjoint * a.value / (b.value * b.value);
  };
  return node;
}

/** Negation. */
AdNode AdNode.neg(AdNode a) {
  AdNode node = _record(a.tape, -a.value, NULL);
  node.back = %!() => { a.adjoint -= node.adjoint; };
  return node;
}

/** Orders nodes by primal value, so `<` and `>` compare values. */
int AdNode.compare(AdNode a, AdNode b) =>
  a.value < b.value ? -1 : a.value > b.value;

static AdNode _unary(AdNode a, double value, double slope) {
  AdNode node = _record(a.tape, value, NULL);
  node.back = %!() => { a.adjoint += node.adjoint * slope; };
  return node;
}

/** Sine. */
AdNode AdNode.sin(AdNode a) => _unary(a, sin(a.value), cos(a.value));

/** Cosine. */
AdNode AdNode.cos(AdNode a) => _unary(a, cos(a.value), -sin(a.value));

/** Exponential. */
AdNode AdNode.exp(AdNode a) {
  double value = exp(a.value);
  return _unary(a, value, value);
}

/** Natural logarithm. */
AdNode AdNode.log(AdNode a) => _unary(a, log(a.value), 1.0 / a.value);

/** Square root. */
AdNode AdNode.sqrt(AdNode a) {
  double value = sqrt(a.value);
  return _unary(a, value, 0.5 / value);
}

/** Hyperbolic tangent. */
AdNode AdNode.tanh(AdNode a) {
  double value = tanh(a.value);
  return _unary(a, value, 1.0 - value * value);
}

protocol Var(AdNode);
