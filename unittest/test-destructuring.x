/*  test-destructuring.x -- Flat positional List destructuring tests

    Copyright (c) 2025 Gary William Flake.

    Verifies declaration and expression assignment forms, positional order,
    once-only source evaluation, short and extra Lists, enclosing scope,
    mixed target types, and generated-name hygiene.
*/

#include "test-support.x"

static int destructuring_source_calls = 0;


static List destructuring_values(void) {
  destructuring_source_calls++;
  return %(10 20 30 40);
}


typedef List DestructuringValues;
typedef float DestructuringShadow;

int destructuring_global_i = 1, float destructuring_global_x = 2.5,
    char destructuring_global_c = 'g';

typedef struct DestructuringMixedFields {
  int i, float x, char c;
} DestructuringMixedFields;


static DestructuringValues destructuring_identity(DestructuringValues values) {
  return values;
}


static DestructuringValues destructuring_return(DestructuringValues values) {
  Var first, second;
  return (first, second) = values;
}


static void test_var_declaration_destructuring(void) {
  Var (a, b, c) = destructuring_values();
  EXPECT_INT_EQ(a.integer(), 10);
  EXPECT_INT_EQ(b.integer(), 20);
  EXPECT_INT_EQ(c.integer(), 30);
}


static void test_typed_declaration_destructuring(void) {
  int (a, b, c) = destructuring_values();
  EXPECT_INT_EQ(a, 10);
  EXPECT_INT_EQ(b, 20);
  EXPECT_INT_EQ(c, 30);
}


static void test_mixed_declarations_and_destructuring(void) {
  int i = 1, float x = 2.5, char c = 'q';
  EXPECT_INT_EQ(i, 1);
  EXPECT_TRUE(x > 2.4 && x < 2.6);
  EXPECT_INT_EQ(c, 'q');

  int qualified = 2, const char *text = "ok", *alias = text;
  EXPECT_INT_EQ(qualified, 2);
  EXPECT_TRUE(alias === text);

  int prefix = 3, struct LocalMixed { int value; } local = { 4 };
  EXPECT_INT_EQ(prefix + local.value, 7);

  DestructuringMixedFields fields = { 3, 4.5, 'f' };
  EXPECT_INT_EQ(fields.i, 3);
  EXPECT_TRUE(fields.x > 4.4 && fields.x < 4.6);
  EXPECT_INT_EQ(fields.c, 'f');

  int count = 1, DestructuringValues values = %(2);
  EXPECT_INT_EQ(count + values.car().integer(), 3);

  (DestructuringShadow typed, int other) = %(8.5 9);
  EXPECT_TRUE(typed > 8.4 && typed < 8.6);
  EXPECT_INT_EQ(other, 9);
  (int one, const String label) = %(1 "ready");
  EXPECT_INT_EQ(one, 1);
  EXPECT_STR_EQ(label, "ready");

  int ordinary = 7, DestructuringShadow = 8;
  EXPECT_INT_EQ(ordinary + DestructuringShadow, 15);

  EXPECT_INT_EQ(destructuring_global_i, 1);
  EXPECT_TRUE(destructuring_global_x > 2.4 &&
              destructuring_global_x < 2.6);
  EXPECT_INT_EQ(destructuring_global_c, 'g');

  (int first, float second, char third) = %(10 20.5 ${'z'});
  EXPECT_INT_EQ(first, 10);
  EXPECT_TRUE(second > 20.4 && second < 20.6);
  EXPECT_INT_EQ(third, 'z');
}


static void test_expression_valued_destructuring(void) {
  Var a, b, c, d;
  DestructuringValues source = %(11 12);
  DestructuringValues result = destructuring_identity((a, b) = source);
  EXPECT_TRUE(result === source);
  EXPECT_INT_EQ(a.integer(), 11);
  EXPECT_INT_EQ(b.integer(), 12);

  DestructuringValues piped = (c, d) = (a, b) = source;
  EXPECT_TRUE(piped === source);
  EXPECT_INT_EQ(c.integer(), 11);
  EXPECT_INT_EQ(d.integer(), 12);

  DestructuringValues conditional = 1 ? (a, b) = source : NULL;
  EXPECT_TRUE(conditional === source);
  int marker = ((void) ((a, b) = source), 17);
  EXPECT_INT_EQ(marker, 17);
  EXPECT_TRUE(destructuring_return(source) === source);

  destructuring_source_calls = 0;
  DestructuringValues once = (a, b) = destructuring_values();
  EXPECT_INT_EQ(destructuring_source_calls, 1);
  EXPECT_INT_EQ(once.len(), 4);
}


static void test_assignment_and_singleton_destructuring(void) {
  Var a, b, c;
  (a, b, c) = destructuring_values();
  EXPECT_INT_EQ(a.integer(), 10);
  EXPECT_INT_EQ(b.integer(), 20);
  EXPECT_INT_EQ(c.integer(), 30);
  (b) = %(99 100);
  EXPECT_INT_EQ(b.integer(), 99);
}


static void test_once_order_and_extra_values(void) {
  destructuring_source_calls = 0;
  Var first, second, third;
  (first, second, third) = destructuring_values();
  EXPECT_INT_EQ(destructuring_source_calls, 1);
  EXPECT_INT_EQ(first.integer(), 10);
  EXPECT_INT_EQ(second.integer(), 20);
  EXPECT_INT_EQ(third.integer(), 30);
}


static void test_short_list_yields_void(void) {
  Var first, missing;
  (first, missing) = %(7);
  EXPECT_INT_EQ(first.integer(), 7);
  EXPECT_TRUE(missing is void);
}


static void test_declaration_scope_and_nested_blocks(void) {
  Var (visible, peer) = %(3 4);
  EXPECT_INT_EQ(visible.integer() + peer.integer(), 7);
  Var copied = void;
  {
    Var (inner, other) = %(8 9);
    copied = inner;
    EXPECT_INT_EQ(other.integer(), 9);
  }
  EXPECT_INT_EQ(copied.integer(), 8);
}


static void test_generated_name_hygiene(void) {
  int user_destructure_0 = 101, user_destructure_1 = 202;
  Var a, b, c, d;
  (a, b) = %(1 2);
  (c, d) = %(3 4);
  EXPECT_INT_EQ(user_destructure_0, 101);
  EXPECT_INT_EQ(user_destructure_1, 202);
  EXPECT_INT_EQ(a.integer() + b.integer(), 3);
  EXPECT_INT_EQ(c.integer() + d.integer(), 7);
}


void destructuring_suite(void) {
  TestHarness_run("var declaration destructuring",
                  test_var_declaration_destructuring);
  TestHarness_run("typed declaration destructuring",
                  test_typed_declaration_destructuring);
  TestHarness_run("mixed declarations and destructuring",
                  test_mixed_declarations_and_destructuring);
  TestHarness_run("expression-valued destructuring",
                  test_expression_valued_destructuring);
  TestHarness_run("assignment and singleton destructuring",
                  test_assignment_and_singleton_destructuring);
  TestHarness_run("once order and extra values",
                  test_once_order_and_extra_values);
  TestHarness_run("short list yields void", test_short_list_yields_void);
  TestHarness_run("declaration scope and nested blocks",
                  test_declaration_scope_and_nested_blocks);
  TestHarness_run("generated name hygiene", test_generated_name_hygiene);
}
