/*  operator-ledger.x -- binary operator facts and case projections

    Each row gives the operator, precedence, compound assignment, protocol
    member, and whether that member derives a comparison. Zero denotes an
    absent compound assignment or member. Private case projections generate
    the public operator lookups below.
*/

#include "compiler.x"

meta static List _operator_rows(void) => %(
  (<||>       1 0        0         0)
  (<&&>       2 0        0         0)
  (<|>        3 <|=>     0         0)
  (<^>        4 <^=>     0         0)
  (<&>        5 <&=>     0         0)
  (<"==">     6 0        <equal>   0)
  (<!=>       6 0        <equal>   1)
  (<"===">    6 0        0         0)
  (<!==>      6 0        0         0)
  (<"<">      7 0        <compare> 1)
  (<"<=">     7 0        <compare> 1)
  (<">">      7 0        <compare> 1)
  (<">=">     7 0        <compare> 1)
  (<in>       7 0        0         0)
  (<"<<">     8 <"<<=">  0         0)
  (<">>">     8 <">>=">  0         0)
  (<+>        9 <+=>     <add>     0)
  (<->        9 <-=>     <sub>     0)
  (<*>       10 <*=>     <mul>     0)
  (</>       10 </=>     <div>     0)
  (<%>       10 <%=>     <mod>     0)
  (<@>       10 <@=>     <matmul>  0)
);

/* Select key and value columns; -1 includes both direct and derived rows. */
meta static List _operator_cases(int key, int value, int derived) {
  Array cases = [];
  foreach (List row, _operator_rows()) {
    if (!row[key] || !row[value]) continue;
    if (derived >= 0 && row[4] != derived) continue;
    Symbol label = row[key];
    Var result = row[value];
    cases.push($!{ case $label: return $result; });
  }
  return cases.list_free();
}

static macro Stmt $operator.precedence() { $_operator_cases(0, 1, -1)... }
static macro Stmt $operator.binary() { $_operator_cases(2, 0, -1)... }
static macro Stmt $operator.compound() { $_operator_cases(0, 2, -1)... }
static macro Stmt $operator.direct() { $_operator_cases(0, 3, 0)... }
static macro Stmt $operator.derived() { $_operator_cases(0, 3, 1)... }

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
