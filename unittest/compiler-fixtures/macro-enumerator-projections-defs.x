#pragma once

#include "x2c.x"

/* One data row supplies an enumerator, an initializer, and a switch case. */

meta static List row = %(ledger-tag ROW_LEDGER object 7);

meta static List int_expr(Var value) =>
  %(expr (int) (literal (int) $(value.str())));

meta List enum_rows(void) {
  match (row) {
    case %(? ?id ? ?value):
      return %((op = (bind $(x2c_ident(id.str())) ()) $(int_expr(value))));
  }
  return %();
}

meta List row_initializer(void) {
  match (row) {
    case %(? ? ? ?value):
      return %(expr () (composite (commas $(int_expr(value)))));
  }
  return %();
}

meta List case_rows(void) {
  match (row) {
    case %(?tag ? ? ?value):
      return %((case (expr ("Symbol") (literal ("Symbol") $(tag.str()) $tag)))
               (return (int) $(int_expr(value))));
  }
  return %();
}

meta List no_rows(void) => %();
