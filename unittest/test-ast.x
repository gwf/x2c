/*  test-ast.x -- compiler-private AST helper tests */

#include "test-support.x"
#include "ast.x"
$(import "test-macros.xmacro")

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

static void ast_rewrite_preserves_identity_and_child_order(void) {
  $test.scoped();
  Array seen = %[];
  Func visit = %!(List child) => {
    seen.push(child);
    return child;
  };
  List scalar = %(head 17 "text");
  EXPECT_TRUE(Ast.rewrite_children(scalar, visit) === scalar);
  EXPECT_INT_EQ(seen.len(), 0);
  EXPECT_NULL(Ast.rewrite_children(NULL, visit));
  EXPECT_INT_EQ(seen.len(), 0);

  List mixed = %(head 17 (keep) "text" () (last));
  EXPECT_TRUE(Ast.rewrite_children(mixed, visit) === mixed);
  EXPECT_LIST_EQ(seen.list(), %((keep) () (last)));
}

static void ast_rewrite_changes_first_middle_and_last_children(void) {
  $test.scoped();
  foreach (List row, %(
    (((change) tail) ((changed) tail))
    ((head (change) tail) (head (changed) tail))
    ((head (keep) (change)) (head (keep) (changed))))) {
    List (input, expected) = row;
    Array seen = %[];
    List result = Ast.rewrite_children(input, %!(List child) => {
      seen.push(child);
      return child.car() == <change> ? %(changed) : child;
    });
    EXPECT_TRUE(result === expected);
    EXPECT_LIST_EQ(seen.list_free(),
      input == %(head (keep) (change)) ? %((keep) (change)) : %((change)));
  }
}

static void ast_rewrite_preserves_nil_replacements(void) {
  List input = %(head (change) (keep));
  List result = Ast.rewrite_children(input,
    %!(List child) => child.car() == <change> ? (List) NULL : child);
  EXPECT_TRUE(result === %(head () (keep)));
}

static void ast_rewrite_passes_child_values(void) {
  volatile int caught = 0;
  try Ast.rewrite_children(%(head (child)), %!(List &child) => child);
  catch %(bad-types *): caught = 1;
  EXPECT_TRUE(caught);
}

static void ast_rewrite_exports_from_context(void) {
  List outer = %(outer (keep));
  Context context = Context.open_isolated();
  List input = %(inner (change));
  List result = Ast.rewrite_children(input, %!(List child) => %(changed));
  EXPECT_TRUE(result === %(inner (changed)));
  List exported = context.export(result);
  context.close();
  EXPECT_LIST_EQ(exported, %(inner (changed)));
  EXPECT_TRUE(Ast.rewrite_children(outer, %!(List child) => child) === outer);
}

void ast_suite(void) {
  TestHarness_run("ast bindings separate identity from spelling",
                  ast_bindings_separate_identity_from_spelling);
  $test.run(ast_rewrite_preserves_identity_and_child_order);
  $test.run(ast_rewrite_changes_first_middle_and_last_children);
  $test.run(ast_rewrite_preserves_nil_replacements);
  $test.run(ast_rewrite_passes_child_values);
  $test.run(ast_rewrite_exports_from_context);
}
