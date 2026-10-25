/*  meta-support.x -- compile-time helpers the suites call with `$`

    A suite's own `meta` group would compile the whole suite without the
    test-support declarations, so the suites take their compile-time
    helpers from this module, whose group compiles only these functions.
*/

#pragma once

#include "x2c.x"

/** Returns `left + right`, computed during translation at a `$` call. */
meta int meta_support_sum(int left, int right) => left + right;

/** Returns the canonical syntax of the integer literal 6. */
meta List meta_support_six(void) => %(expr (int) (literal (int) "6"));

/** Returns `NAME=VALUE,` for each member of the enum `type`: a literal
    initializer as its spelling, no initializer as `-`, and any other
    initializer as `<expr>`. */
meta String meta_support_members(Type type) {
  Array parts = [];
  foreach (List row, Type.members(type)) {
    match (row) {
      case %(?name ()): parts.push(%"$name=-,");
      case %(?name ?(String text)): parts.push(%"$name=$text,");
      case %(?name ?): parts.push(%"$name=<expr>,");
    }
  }
  return parts.join("");
}
