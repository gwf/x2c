/* test-emit.x -- the generated proof program, without a prover. */

import "cstar" with Cstar;

#include "test-support.x"
#include <stdlib.h>

$(import "../../../unittest/test-macros.xmacro")

static String run(String command, int expected_status) {
  String output = %"builds/emit.out";
  int status = system(%"${command} >${output} 2>builds/emit.err");
  EXPECT_INT_EQ(WEXITSTATUS(status), expected_status);
  File captured = File.open(output, %"r");
  EXPECT_NOT_NULL(captured);
  defer captured.close();
  return captured.string();
}

static void expect_emit(String stem) {
  String emitted = run(%"./builds/cstar-verify --emit examples/${stem}.x", 0);
  File expected = File.open(%"tests/expected/${stem}.proof.x", %"r");
  EXPECT_NOT_NULL(expected);
  defer expected.close();
  EXPECT_STR_EQ(emitted, expected.string());
}

static void emit_matches_the_expected_program(void) {
  expect_emit(%"abs");
}

/** The array examples are the whole admitted subset in one place: a ghost
    parameter, a separation-logic invariant, an indexed store, `i++`, and
    the session's own proof steps. */
static void emit_renders_the_array_examples(void) {
  expect_emit(%"clear");
  expect_emit(%"fill");
}

static void emit_is_deterministic(void) {
  String first = run(%"./builds/cstar-verify --emit examples/twice.x", 0);
  String second = run(%"./builds/cstar-verify --emit examples/twice.x", 0);
  EXPECT_STR_EQ(first, second);
  EXPECT_TRUE(first.find(%"#include \"x2c.x\"") < 0);
  EXPECT_TRUE(first.find(%"twice_step(cstar, \"(r_v + y__pre)") >= 0);
}

static void emit_splices_the_companion_helpers(void) {
  String emitted = run(%"./builds/cstar-verify --emit examples/twice.x", 0);
  EXPECT_TRUE(emitted.find(%"examples/twice.proofs.x") >= 0);
  EXPECT_TRUE(emitted.find(%"static void twice_step(Cstar cstar") >= 0);
}

static void emit_records_every_requested_function(void) {
  String emitted = run(%"./builds/cstar-verify --emit examples/twice.x", 0);
  EXPECT_TRUE(emitted.find(%"Cstar.open(2, \"examples/twice.x\")") >= 0);
  EXPECT_TRUE(emitted.find(%"_verify_twice(cstar);") >= 0);
  EXPECT_TRUE(emitted.find(%"_verify_product(cstar);") >= 0);
}

static void parentheses_preserve_the_grouped_expression(void) {
  String emitted = run(
    %"./builds/cstar-verify --emit tests/parenthesized.x", 0);
  EXPECT_TRUE(emitted.find(
    %"make_binary_expr(BINOP_MULTIPLY, make_binary_expr(BINOP_ADD,") >= 0);
  EXPECT_TRUE(emitted.find(
    %"make_return_expr(make_var_expr(\"result\", make_int_type()))") >= 0);
}

static void compiler_changes_rebuild_the_verifier(void) {
  String planned = run(
    %"make --no-print-directory -n tool -W ../../builds/0/src/parse.o", 0);
  EXPECT_TRUE(planned.find(
    %"--kind static-library --output builds/libx2c-dev.a") >= 0);
  EXPECT_TRUE(planned.find(%"--output builds/cstar-verify") >= 0);
  planned = run(
    %"make --no-print-directory -n tool -W ../../builds/0/libx2c.a", 0);
  EXPECT_TRUE(planned.find(%"--output builds/cstar-verify") >= 0);
}

static void emit_suite(void) {
  $test.run(emit_matches_the_expected_program);
  $test.run(emit_renders_the_array_examples);
  $test.run(emit_is_deterministic);
  $test.run(emit_splices_the_companion_helpers);
  $test.run(emit_records_every_requested_function);
  $test.run(parentheses_preserve_the_grouped_expression);
  $test.run(compiler_changes_rebuild_the_verifier);
}

int main(void) {
  TestHarness_begin();
  $test.suite(emit_suite);
  return TestHarness_finish();
}
