/*  operator-ledger.x -- compiler lookups from one binary operator ledger */

#include "compiler.x"
$(import "../src/operator-ledger.xmacro")

/** Returns a binary operator's precedence level, or zero for any other
    `Symbol`. Levels run from 1 for `||` to 10 for the multiplicative
    operators, so a larger level binds more tightly. `===` and `!==` share
    the equality level, `in` the relational level, and `@` the
    multiplicative level.
*/
int Symbol.binary_precedence(Symbol op) {
  switch (op) { $operator.precedence(); }
  return 0;
}

/** Returns the binary operator computed by a compound assignment, or zero. */
Symbol Symbol.compound_operator(Symbol op) {
  switch (op) { $operator.binary(); }
  return 0;
}

/** Returns the compound assignment for a binary operator, or zero. */
Symbol Symbol.compound_assignment(Symbol op) {
  switch (op) { $operator.compound(); }
  return 0;
}

/** Returns the protocol member corresponding to a direct binary operator.
    Returns zero when the operator has no direct protocol mapping.
*/
Symbol Compiler.operator_member(Compiler c, Symbol op) {
  (void) c;
  switch (op) { $operator.direct(); }
  return 0;
}

/** Returns the protocol member that derives a comparison operator.
    Inequality derives from `equal`, ordered comparisons derive from `compare`,
    and unsupported operators return zero.
*/
Symbol Compiler.derived_member(Compiler c, Symbol op) {
  (void) c;
  switch (op) { $operator.derived(); }
  return 0;
}
