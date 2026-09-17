/*  test-match-logic.x -- advanced pattern logic tests for match statement */

#include "test-support.x"
$(import "test-macros.xmacro")

static void match_or_not_quote(void) {
  $test.scoped();

  // !or: either of the two shapes should match (prefer first)
  {
    List input = %( sum 1 2 );
    Symbol orsym = <!or>;
    List pat = %($orsym (sum ?x ?y) (sum ?x)), binds = input.match(pat);
    EXPECT_NOT_NULL(binds);
  }

  // !not: should match when the nested pattern does not match
  {
    List input = %( sum 1 2 );
    Symbol notsym = <!not>;
    List pat = %($notsym (sum 0)), binds = input.match(pat);
    EXPECT_NOT_NULL(binds);
  }

  // !quote: equality on whole list
  {
    List input = %( foo bar );
    Symbol quotesym = <!quote>;
    List pat = %($quotesym (foo bar)), binds = input.match(pat);
    EXPECT_NOT_NULL(binds);
  }

}

static void match_set_binds_whole_and_parts(void) {
  $test.scoped();
  List input = %( node 7 8 );
  Var whole = void, a = void, b = void;
  int matched = 0;
  match (input) {
    case %(!set ?whole (node ?a ?b)): {
      matched = 1;
      EXPECT_INT_EQ(Var_int(a), 7);
      EXPECT_INT_EQ(Var_int(b), 8);
      EXPECT_TRUE(whole == input);
    }
  }
  if (!matched) TEST_FAIL("!set case did not match");
}

/* The guide gives every guard but !quote an optional leading binder that
   captures the slice it checked. A binder needs at least one operand after
   it, so it is never read as one more alternative and never leaves a guard
   with nothing to test. */
static void match_leading_binder_needs_an_operand(void) {
  $test.scoped();
  // (!set ?w a b) is a capture of the a-or-b membership, not membership
  // over ?w as well, so an unrelated element no longer matches
  EXPECT_NULL(%(q c).match(%(q (!set ?w a b))));
  List bound = %(q b).match(%(q (!set ?w a b)));
  if (EXPECT_NOT_NULL(bound)) EXPECT_TRUE(bound.assoc(<?w>) == <b>);

  // (!not ?y) has no operand after ?y, so ?y is the operand it tests
  EXPECT_NULL(%(a a).match(%(?y (!not ?y))));
  EXPECT_NOT_NULL(%(a b).match(%(?y (!not ?y))));

  // the guide's one-operand spellings keep capturing the checked slice
  List whole = %(node 7 8).match(%(!set ?whole (node ?a ?b)));
  if (EXPECT_NOT_NULL(whole))
    EXPECT_TRUE(whole.assoc(<?whole>) == %(node 7 8).var());
  List found = %(key 42).match(%(key (!is ?found atom)));
  if (EXPECT_NOT_NULL(found)) EXPECT_TRUE(found.assoc(<?found>) is <i32>);

  // a leading binder on the other multi-operand guards reads the same way
  List any = %(x b).match(%(x (!or ?seen a b)));
  if (EXPECT_NOT_NULL(any)) EXPECT_TRUE(any.assoc(<?seen>) == <b>);
  EXPECT_NULL(%(x c).match(%(x (!or ?seen a b))));
  EXPECT_NOT_NULL(%(x c).match(%(x (!not ?seen a b))));
  EXPECT_NULL(%(x a).match(%(x (!not ?seen a b))));
}

static void match_is_predicates_runtime(void) {
  $test.scoped();

  // Build inputs containing binder-like atoms
  List input1 = %( seq ?foo ), input2 = %( seq *rest ), input3 = %( seq !or );

  // (var binder) should recognize ?foo
  {
    Symbol issym = <!is>;
    List pat = %(seq ($issym var binder)), binds = input1.match(pat);
    EXPECT_NOT_NULL(binds);
  }

  // (list binder) should recognize *rest
  {
    Symbol issym = <!is>;
    List pat = %(seq ($issym list binder)), binds = input2.match(pat);
    EXPECT_NOT_NULL(binds);
  }

  // (op) should recognize !or
  {
    Symbol issym = <!is>;
    List pat = %(seq ($issym op)), binds = input3.match(pat);
    EXPECT_NOT_NULL(binds);
  }

}

static void match_nested_complex(void) {
  $test.scoped();
  List input = %(tree (node 3 4) tail);
  Symbol orsym = <!or>;
  List pat = %(tree ($orsym (node ?a ?b) (pair ?a ?b)) *rest);
  List binds = input.match(pat);
  EXPECT_NOT_NULL(binds);
  if (binds) {
    Var av = binds.assoc(<?a>);
    Var bv = binds.assoc(<?b>);
    EXPECT_INT_EQ(Var_int(av), 3);
    EXPECT_INT_EQ(Var_int(bv), 4);
  }
}


void match_logic_suite(void) {
  $test.run(match_set_binds_whole_and_parts);
  $test.run(match_or_not_quote);
  $test.run(match_leading_binder_needs_an_operand);
  $test.run(match_is_predicates_runtime);
  $test.run(match_nested_complex);
}
