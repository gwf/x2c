/*  test-match-logic.x -- advanced pattern logic tests for match statement */

#include "test-support.x"
$(import "test-macros.xmacro")

static void match_or_not_quote(void) {
  $test.scoped();

  // !or: either of the two shapes should match (prefer first)
  {
    List input = %( sum 1 2 );
    Symbol orsym = Symbol.new("!or");
    List pat = %($orsym (sum ?x ?y) (sum ?x)), binds = List.match(input, pat);
    EXPECT_NOT_NULL(binds);
  }

  // !not: should match when the nested pattern does not match
  {
    List input = %( sum 1 2 );
    Symbol notsym = Symbol.new("!not");
    List pat = %($notsym (sum 0)), binds = List.match(input, pat);
    EXPECT_NOT_NULL(binds);
  }

  // !quote: equality on whole list
  {
    List input = %( foo bar );
    Symbol quotesym = Symbol.new("!quote");
    List pat = %($quotesym (foo bar)), binds = List.match(input, pat);
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

static void match_is_predicates_runtime(void) {
  $test.scoped();

  // Build inputs containing binder-like atoms
  List input1 = %( seq ?foo ), input2 = %( seq *rest ), input3 = %( seq !or );

  // (var binder) should recognize ?foo
  {
    Symbol issym = Symbol.new("!is");
    List pat = %(seq ($issym var binder)), binds = List.match(input1, pat);
    EXPECT_NOT_NULL(binds);
  }

  // (list binder) should recognize *rest
  {
    Symbol issym = Symbol.new("!is");
    List pat = %(seq ($issym list binder)), binds = List.match(input2, pat);
    EXPECT_NOT_NULL(binds);
  }

  // (op) should recognize !or
  {
    Symbol issym = Symbol.new("!is");
    List pat = %(seq ($issym op)), binds = List.match(input3, pat);
    EXPECT_NOT_NULL(binds);
  }

}

static void match_nested_complex(void) {
  $test.scoped();
  List input = %(tree (node 3 4) tail);
  Symbol orsym = Symbol.new("!or");
  List pat = %(tree ($orsym (node ?a ?b) (pair ?a ?b)) *rest);
  List binds = List.match(input, pat);
  EXPECT_NOT_NULL(binds);
  if (binds) {
    Var av = List.assoc(binds, Symbol.new("?a"));
    Var bv = List.assoc(binds, Symbol.new("?b"));
    EXPECT_INT_EQ(Var_int(av), 3);
    EXPECT_INT_EQ(Var_int(bv), 4);
  }
}


void match_logic_suite(void) {
  $test.run(match_set_binds_whole_and_parts);
  $test.run(match_or_not_quote);
  $test.run(match_is_predicates_runtime);
  $test.run(match_nested_complex);
}
