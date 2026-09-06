/*  test-ast.x -- compiler-private AST helper tests */

#include "test-support.x"
#include "ast.x"

static void ast_bindings_separate_identity_from_spelling(void) {
  List captured = binding_identity_new(17, %"value");
  List retained = captured;
  List introduced = binding_identity_new(18, %"value");
  int identity = 0;
  String spelling = NULL;

  EXPECT_TRUE(binding_identity_try_parts(captured, &identity, &spelling));
  EXPECT_INT_EQ(identity, 17);
  EXPECT_STR_EQ(spelling, "value");
  EXPECT_TRUE(retained == captured);
  EXPECT_FALSE(introduced == captured);
  EXPECT_STR_EQ(binding_identity_spelling(introduced), "value");
  EXPECT_FALSE(binding_identity_try_parts(%(binding 0 "value"), NULL, NULL));
}

void ast_suite(void) {
  TestHarness_run("ast bindings separate identity from spelling",
                  ast_bindings_separate_identity_from_spelling);
}
