
#include "test-support.x"

// Regression test for the pattern compiler: `?ident` must bind the
// underlying string.

static void matcher_should_bind_ident_var(void) {
  Var stmt = %(stmnt
                 (expr ("Var")
                       (op = (expr ("Var") (ident ("color")))
                             (%(some rhs value)))));

  match (stmt) {
    case %(stmnt (expr ("Var") (op = (expr ("Var") (ident (?ident))) ?rhs))): {
      if (!EXPECT_TRUE(Var_is(ident, <string>))) return;
      String bound_name = Var_string(ident);
      Var bound_value = rhs;
      EXPECT_TRUE(bound_name == %"color");
      EXPECT_FALSE(bound_value is void);
      return;
    }
  }

  TEST_FAIL("pattern did not match");
}

$(import "test-macros.xmacro")

void match_binder_contract_suite(void) {
  $test.run(matcher_should_bind_ident_var);
}
