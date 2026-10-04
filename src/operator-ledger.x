/*  operator-ledger.x -- compiler lookups from one binary operator ledger */

#include "compiler.x"
$(import "../src/operator-ledger.xmacro")

int Symbol.binary_precedence(Symbol op) {
  switch (op) { $operator.precedence(); }
  return 0;
}

Symbol Symbol.compound_operator(Symbol op) {
  switch (op) { $operator.binary(); }
  return 0;
}

Symbol Symbol.compound_assignment(Symbol op) {
  switch (op) { $operator.compound(); }
  return 0;
}

Symbol Compiler.operator_member(Compiler c, Symbol op) {
  (void) c;
  switch (op) { $operator.direct(); }
  return 0;
}

Symbol Compiler.derived_member(Compiler c, Symbol op) {
  (void) c;
  switch (op) { $operator.derived(); }
  return 0;
}
