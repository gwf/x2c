/*  test-match-stmt.x -- unit tests for match statement lowering */

#include "test-support.x"
$(import "test-macros.xmacro")

static List _runtime_match(List input, List pattern) {
  return input.match(pattern);
}

static void match_binds_values(void) {
  $test.scoped();
  /* Explicit scope release to avoid implicit cleanup helpers. */
  List input = %( sum 3 4 5 );
  Var three = 3, four = 4;
  int matched = 0;
  match (input) {
    case %( sum ?a ?b ?c ): {
      matched = 1;
      EXPECT_VAR_EQ(a, three);
      EXPECT_VAR_EQ(b, four);
      EXPECT_INT_EQ(c.int(), 5);
    }
  }
  if (!matched) TEST_FAIL("no case matched");
}

static void match_star_binder(void) {
  $test.scoped();
  List input = %( seq 1 2 3 4 );
  int matched = 0;
  match (input) {
    case %( seq ?head *tail ):
      {
        matched = 1;
        EXPECT_INT_EQ(head.int(), 1);
        EXPECT_INT_EQ(tail.len(), 3);
        EXPECT_INT_EQ(Var_integer(List_cadr(tail)), 3);
      }
  }
  if (!matched) TEST_FAIL("no case matched");
}

static void match_default_clause(void) {
  $test.scoped();
  List input = %( nil );
  int result = 0;
  match (input) {
    case %( pair ?a ?b ): result = 1;
    default: result = 2;
  }
  EXPECT_INT_EQ(result, 2);
}

static void match_prefers_first_case(void) {
  $test.scoped();
  List input = %( pair 1 2 );
  int result = 0;
  match (input) {
    case %( pair ?x ?y ): result = Var_int(x) + Var_int(y);
    case %( pair 1 ?z ): result = 99;
  }
  EXPECT_INT_EQ(result, 3);
}

static void match_nested_patterns_compile(void) {
  $test.scoped();
  List input = %( tree (( node 3 4 )) leaf );
  int product = 0;
  match (input) {
    case %( tree (( node ?a ?b )) ?rest ): product = a.int() * b.int();
  }
  EXPECT_INT_EQ(product, 12);
}

static void match_compiled_star_binder(void) {
  $test.scoped();
  List input = %( seq 1 2 3 4 );
  int len = 0;
  match (input) {
    case %( seq *tail ):
      {
        len = List_len(tail);
      }
  }
  EXPECT_INT_EQ(len, 4);
}

static void match_compiled_typed_empty_list(void) {
  $test.scoped();
  List input = NULL;
  int matched = 0;
  match (input) {
    case %(*tail): {
      matched = 1;
      EXPECT_NULL(tail);
    }
  }
  EXPECT_INT_EQ(matched, 1);
}

static void match_loop_break_semantics(void) {
  $test.scoped();
  List inputs = %( ((ok)) ((ok)) );
  int matched = 0, after = 0;
  foreach(Var item, inputs) {
    List seq = Var_list(item);
    match (seq) {
      case %( (ok) ): {
        matched++;
        break;
      }
    }
    after++;
  }
  EXPECT_INT_EQ(matched, 2);
  EXPECT_INT_EQ(after, 2);
}

static void match_loop_continue_semantics(void) {
  $test.scoped();
  List inputs = %( ((skip)) ((keep)) ((skip)) );
  int visited = 0, accepted = 0;
  foreach(Var item, inputs) {
    List seq = Var_list(item);
    visited++;
    match (seq) {
      case %( (skip) ): continue;
    }
    accepted++;
  }
  EXPECT_INT_EQ(visited, 3);
  EXPECT_INT_EQ(accepted, 1);
}

static void match_not_pattern_negates_literal(void) {
  $test.scoped();

  {
    List input = %( seq red );
    int matched = 0;
    match (input) {
      case %( seq (!not blue) ): matched = 1;
      default: matched = 0;
    }
    EXPECT_INT_EQ(matched, 1);
  }

  {
    List input = %( seq blue );
    int matched = 0;
    match (input) {
      case %( seq (!not blue) ): matched = 1;
      default: matched = 0;
    }
    EXPECT_INT_EQ(matched, 0);
  }

}

static void match_or_pattern_disjoins_literals(void) {
  $test.scoped();
  List colors[] = {
    %( seq red ),
    %( seq blue ),
    %( seq green ),
    %( seq yellow )
  };

  for (int i = 0; i < 4; i++) {
    int is_primary = 0;
    match (colors[i]) {
      case %( seq (!or red blue) ): is_primary = 1;
      default: is_primary = 0;
    }
    EXPECT_INT_EQ(is_primary, (i < 2));
  }

}


static void match_or_pattern_definitely_binds_common_name(void) {
  $test.scoped();
  List colors[] = { %(seq red), %(seq blue) };

  for (int i = 0; i < 2; i++) {
    Var captured = void;
    match (colors[i]) {
      case %(seq (!or (!set ?color red) (!set ?color blue))): captured = color;
    }
    EXPECT_TRUE(captured == colors[i].cadr());
  }

}

static void match_and_pattern_conjoins_guards(void) {
  $test.scoped();

  {
    List input = %( seq green );
    int matched = 0;
    match (input) {
      case %( seq (!and (!not red) (!not blue)) ): matched = 1;
      default: matched = 0;
    }
    EXPECT_INT_EQ(matched, 1);
  }

  {
    List input = %( seq red );
    int matched = 0;
    match (input) {
      case %( seq (!and (!not red) (!not blue)) ): matched = 1;
      default: matched = 0;
    }
    EXPECT_INT_EQ(matched, 0);
  }

}

static void match_and_pattern_merges_binders(void) {
  $test.scoped();
  Var captured = void;
  List input = %( seq red );

  match (input) {
    case %( seq (!and ?color (!and ?color red)) ): captured = color;
  }

  EXPECT_TRUE(captured == input.cadr());
}

static void match_set_pattern_checks_membership(void) {
  $test.scoped();
  List colors[] = {
    %( seq red ),
    %( seq blue ),
    %( seq green ),
    %( seq yellow )
  };

  for (int i = 0; i < 4; i++) {
    int is_primary = 0;
    match (colors[i]) {
      case %( seq (!set red blue) ): is_primary = 1;
      default: is_primary = 0;
    }
    EXPECT_INT_EQ(is_primary, (i < 2));
  }

}

static void match_set_pattern_binds_value(void) {
  $test.scoped();
  Var captured = void;
  List input = %( seq red );

  match (input) {
    case %( seq (!set ?value red) ): captured = value;
  }

  EXPECT_TRUE(captured == input.cadr());
}

static void match_set_pattern_compiles_binder_case(void) {
  $test.scoped();
  Var captured = void;
  List input = %( seq red );

  match (input) {
    case %( seq (!set ?color red) ): captured = color;
  }

  EXPECT_TRUE(captured == input.cadr());
}

static void match_quote_pattern_compares_literals(void) {
  $test.scoped();

  {
    List input = %( seq (( pair a b )) );
    int matched = 0;
    match (input) {
      case %( seq (!quote (( pair a b))) ): matched = 1;
      default: matched = 0;
    }
    EXPECT_INT_EQ(matched, 1);
  }

  {
    List input = %( seq (( pair a b )) );
    int matched = 0;
    match (input) {
      case %( seq (!quote (( pair a c))) ): matched = 1;
      default: matched = 0;
    }
    EXPECT_INT_EQ(matched, 0);
  }

}

static void match_is_pattern_filters_predicates(void) {
  $test.scoped();

  {
    List input = %( seq !or );
    int matched = 0;
    match (input) {
      case %( seq (!set ?op (!is op)) ):
        matched = Var_equal(op, List_cadr(input));
      default: matched = 0;
    }
    EXPECT_INT_EQ(matched, 1);
  }

  {
    List input = %( seq red );
    int matched = 0;
    match (input) {
      case %( seq (!set ?op (!is op) )): matched = 1;
      default: matched = 0;
    }
    EXPECT_INT_EQ(matched, 0);
  }

}

static void match_and_pattern_handles_nested_guard_binders(void) {
  $test.scoped();
  Var captured = void;
  List input = %( seq red );

  match (input) {
    case %( seq (!and (!set ?color red) (!quote red)) ): captured = color;
  }

  EXPECT_TRUE(captured == input.cadr());
}

/* The approved activation correction: a raw leading list wildcard in a
   guard is the explicit MALFORMED form and never matches, in both the
   source match statement and the runtime matcher.  (Before activation
   these accidentally diverged: !or failed while !not succeeded.) */
static void match_guard_list_binder_matches_runtime(void) {
  $test.scoped();
  List input = %(foo);

  int literal_or = 0;
  match (input) {
    case %(!or * missing): literal_or = 1;
  }
  List runtime_or = _runtime_match(input, %(!or * missing));
  EXPECT_INT_EQ(literal_or, 0);
  EXPECT_INT_EQ(!!runtime_or, 0);
  EXPECT_INT_EQ(literal_or, !!runtime_or);

  int literal_not = 0;
  match (input) {
    case %(!not * missing): literal_not = 1;
  }
  List runtime_not = _runtime_match(input, %(!not * missing));
  EXPECT_INT_EQ(literal_not, 0);
  EXPECT_INT_EQ(!!runtime_not, 0);
  EXPECT_INT_EQ(literal_not, !!runtime_not);

}

static void match_long_atom_binders_compile(void) {
  $test.scoped();
  List input = %(node 9 tail more);
  int matched = 0;
  match (input) {
    case %(node ?VeryLongIdentifierValue *RemainingLongValues): {
      matched = 1;
      EXPECT_INT_EQ(Var_int(VeryLongIdentifierValue), 9);
      EXPECT_TRUE(RemainingLongValues == %(tail more));
    }
  }
  EXPECT_INT_EQ(matched, 1);

  matched = 0;
  input = %(node ?actual);
  match (input) {
    case %(node (!is (?LongPredicateValue) ?binder?)): matched = 1;
  }
  /* The legacy predicate remains parser control vocabulary in its existing
     !is operand position; its execution contract is still deferred. */
  EXPECT_INT_EQ(matched, 0);
}

static Var _dynamic_match_value(List input, Var expected) {
  match (input) {
    case %(tag $expected ?value): return value;
  }
  return void;
}

static void match_dynamic_patterns_do_not_retain_one_value(void) {
  EXPECT_INT_EQ(_dynamic_match_value(%(tag red 1), <red>).int(), 1);
  EXPECT_INT_EQ(_dynamic_match_value(%(tag blue 2), <blue>).int(), 2);
  EXPECT_TRUE(_dynamic_match_value(%(tag red 3), <blue>) is void);
}


/* A String literal in head position used to make the compiler treat the
   whole pattern as dynamic, so every named binder in the arm was reported
   as not definitely assigned and the arm would not compile. */
static void match_string_literal_head_binds(void) {
  $test.scoped();
  List input = %( "x2c.ident" "spelling" 7 );
  int matched = 0;
  match (input) {
    case %( "x2c.ident" (!is ?text type string) ?count ): {
      matched = 1;
      EXPECT_STR_EQ(text.str(), %"spelling");
      EXPECT_INT_EQ(count.int(), 7);
    }
  }
  if (!matched) TEST_FAIL("no case matched");
}

/* Arms whose pattern begins with a literal symbol are reached through a
   switch on the subject's head, so these cover the three ways an arm may
   not be jumped over: it shares a head with an earlier arm, its head is
   computed, or an arm in front of it can match anything. */

static int _head_dispatch(List input) {
  match (input) {
    case %(alpha ?v): return 10 + v.int();
    case %(beta ?v): return 20 + v.int();
    case %(alpha ?v ?w): return 30 + v.int() + w.int();
    case %(gamma ?v): return 40 + v.int();
  }
  return -1;
}

static void match_head_dispatch_selects_arm(void) {
  $test.scoped();
  EXPECT_INT_EQ(_head_dispatch(%(alpha 1)), 11);
  EXPECT_INT_EQ(_head_dispatch(%(beta 2)), 22);
  EXPECT_INT_EQ(_head_dispatch(%(alpha 1 2)), 33);
  EXPECT_INT_EQ(_head_dispatch(%(gamma 3)), 43);
  EXPECT_INT_EQ(_head_dispatch(%(delta 4)), -1);
  EXPECT_INT_EQ(_head_dispatch(%(1 2)), -1);
  EXPECT_INT_EQ(_head_dispatch(NULL), -1);
}

static int _binder_head_first(List input) {
  match (input) {
    case %(?any 1): return 1;
    case %(beta 1): return 2;
  }
  return 0;
}

static void match_binder_head_arm_keeps_priority(void) {
  $test.scoped();
  EXPECT_INT_EQ(_binder_head_first(%(beta 1)), 1);
  EXPECT_INT_EQ(_binder_head_first(%(beta 9)), 0);
}

static int _dynamic_head_first(List input, Var head) {
  match (input) {
    case %($head 1): return 1;
    case %(beta 2): return 2;
  }
  return 0;
}

static void match_dynamic_head_arm_keeps_priority(void) {
  $test.scoped();
  EXPECT_INT_EQ(_dynamic_head_first(%(beta 1), <beta>), 1);
  EXPECT_INT_EQ(_dynamic_head_first(%(beta 2), <beta>), 2);
}


void match_stmt_suite(void) {
  $test.run(match_binds_values);
  $test.run(match_star_binder);
  $test.run(match_default_clause);
  $test.run(match_prefers_first_case);
  $test.run(match_nested_patterns_compile);
  $test.run(match_compiled_star_binder);
  $test.run(match_compiled_typed_empty_list);
  $test.run(match_loop_break_semantics);
  $test.run(match_loop_continue_semantics);
  $test.run(match_not_pattern_negates_literal);
  $test.run(match_or_pattern_disjoins_literals);
  $test.run(match_or_pattern_definitely_binds_common_name);
  $test.run(match_and_pattern_conjoins_guards);
  $test.run(match_and_pattern_merges_binders);
  $test.run(match_set_pattern_checks_membership);
  $test.run(match_quote_pattern_compares_literals);
  $test.run(match_is_pattern_filters_predicates);
  $test.run(match_set_pattern_binds_value);
  $test.run(match_set_pattern_compiles_binder_case);
  $test.run(match_and_pattern_handles_nested_guard_binders);
  $test.run(match_guard_list_binder_matches_runtime);
  $test.run(match_long_atom_binders_compile);
  $test.run(match_dynamic_patterns_do_not_retain_one_value);
  $test.run(match_string_literal_head_binds);
  $test.run(match_head_dispatch_selects_arm);
  $test.run(match_binder_head_arm_keeps_priority);
  $test.run(match_dynamic_head_arm_keeps_priority);
}
