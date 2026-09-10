/* test-invariant.x -- single-statement loop annotations and their erasure. */

#include "test-support.x"
#include <stdlib.h>

$(import "../../../unittest/test-macros.xmacro")

static void invariants_emit_under_an_unbraced_if(void) {
  int status = system("./builds/cstar-verify --emit "
    "tests/unbraced-invariant.x >builds/invariant.out "
    "2>builds/invariant.err");
  EXPECT_INT_EQ(WEXITSTATUS(status), 0);
  File output = File.open(%"builds/invariant.out", %"r");
  defer output.close();
  String emitted = output.string();
  EXPECT_TRUE(emitted.find(%"_verify_countdown(cstar);") >= 0);
  EXPECT_TRUE(emitted.find(%"_verify_countdown_sl(cstar);") >= 0);
  EXPECT_TRUE(emitted.find(%"make_cst_invariant(cstar.program_assertion(" +
    %"\"typeof(x, Tint) && 0i <= x && x <= 100i\"), 0)") >= 0);
  EXPECT_TRUE(emitted.find(%"make_cst_invariant(cstar.assertion(\"exists " +
    %"x_v. data_at x__addr Tint x_v ** \" " +
    %"\"fact(0i <= x_v && x_v <= 100i)\"), 1)") >= 0);
}

static void erased_invariants_preserve_control_flow(void) {
  const char *compiler = getenv("X2C");
  if (!compiler) compiler = "../../builds/0/x2c";
  int status = system(%"${compiler} build " +
    %"--output builds/unbraced-invariant " +
    %"--build-dir builds/unbraced-invariant-cc " +
    %"tests/unbraced-invariant.x >builds/invariant-build.out 2>&1");
  EXPECT_INT_EQ(WEXITSTATUS(status), 0);
  if (WEXITSTATUS(status)) return;
  status = system("./builds/unbraced-invariant");
  EXPECT_INT_EQ(WEXITSTATUS(status), 0);
}

static void invariant_suite(void) {
  $test.run(invariants_emit_under_an_unbraced_if);
  $test.run(erased_invariants_preserve_control_flow);
}

int main(void) {
  TestHarness_begin();
  $test.suite(invariant_suite);
  return TestHarness_finish();
}
