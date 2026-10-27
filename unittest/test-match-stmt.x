/*  test-match-stmt.x -- unit tests for match statement lowering */

#include "test-support.x"
#include "test-macros.x"

static List _runtime_match(List input, List pattern) {
  return input.match(pattern);
}

static void match_binds_values(void) {
  $test.scoped();
  List input = %( sum 3 4 5 );
  int matched = 0;
  match (input) {
    case %( sum ?a ?b ?c ): {
      matched = 1;
      EXPECT_INT_EQ(a.int(), 3);
      EXPECT_INT_EQ(b.int(), 4);
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
        EXPECT_INT_EQ(tail.cadr().integer(), 3);
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
    case %( pair ?x ?y ): result = x.int() + y.int();
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

static void match_not_pattern_binds_leading_binder(void) {
  $test.scoped();
  Var captured = void;
  foreach (Var color, %(red blue)) {
    List input = %( seq $color );
    match (input) {
      case %( seq (!not ?other blue) ): captured = other;
    }
  }
  EXPECT_TRUE(captured == <red>);
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
  /* The compact predicate is parser control vocabulary in the final
     !is operand position; its execution contract is deferred. */
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


/* A String literal in head position is static pattern data; named binders
   in the arm receive values from the corresponding input elements. */
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
    case $(head, 1): return 1;
    case %(beta 2): return 2;
  }
  return 0;
}

static void match_dynamic_head_arm_keeps_priority(void) {
  $test.scoped();
  EXPECT_INT_EQ(_dynamic_head_first(%(beta 1), <beta>), 1);
  EXPECT_INT_EQ(_dynamic_head_first(%(beta 2), <beta>), 2);
}


static int _flat_pair(List input, Var *left, Var *right) {
  match (input) {
    case %(flat ?a ?b): {
      *left = a;
      *right = b;
      return 1;
    }
  }
  return 0;
}

static int _flat_typed_pair(List input, Var *left, Var *right) {
  match (input) {
    case %(flat ?(String a) ?b): {
      *left = a;
      *right = b;
      return 1;
    }
  }
  return 0;
}

static void match_flat_typed_capture_agrees_with_runtime(void) {
  $test.scoped();
  Var head = <flat>;
  Var payloads[4] = {(List) NULL, "text", 7, %(nested)};
  for (int length = 0; length < 5; length++)
    for (int value = 0; value < 4; value++) {
      List input = NULL;
      for (int i = length - 1; i >= 0; i--)
        input = cons(i ? payloads[(value + i - 1) % 4] : head, input);
      Var actual[2], expected[2];
      MatchCaptureBuffer capture = {.values = expected, .capacity = 2};
      int matched = _flat_typed_pair(input, &actual[0], &actual[1]);
      int reference = x2c_match_try_capture(
        input, %(flat (!is ?a type string) ?b), capture);
      EXPECT_INT_EQ(matched, reference);
      if (matched) {
        EXPECT_TRUE(actual[0].u64 == expected[0].u64);
        EXPECT_TRUE(actual[1].u64 == expected[1].u64);
      }
    }
}

static void match_flat_capture_agrees_with_runtime(void) {
  $test.scoped();
  Var head = <flat>;
  Var payloads[4] = {(List) NULL, 0, 7, %(nested)};
  for (int length = 0; length < 5; length++)
    for (int value = 0; value < 4; value++) {
      List input = NULL;
      for (int i = length - 1; i >= 0; i--)
        input = cons(i ? payloads[(value + i - 1) % 4] : head, input);
      Var actual[2], expected[2];
      MatchCaptureBuffer capture = {.values = expected, .capacity = 2};
      int matched = _flat_pair(input, &actual[0], &actual[1]);
      int reference = x2c_match_try_capture(input, %(flat ?a ?b), capture);
      EXPECT_INT_EQ(matched, reference);
      if (matched) {
        EXPECT_TRUE(actual[0].u64 == expected[0].u64);
        EXPECT_TRUE(actual[1].u64 == expected[1].u64);
      }
    }
}

/* The operator arms below, as values, in the same order. */
static List _operator_patterns(void) => %(
  (status (!or ok created) ?code)
  (status (!not ok) ?code)
  (color (!and (!not red) (!not blue)))
  (key (!is type string))
  (key (!is ?found atom))
  (tag (!quote (a b)))
  (tag (!quote ?x))
  ((!or ?kind typedef struct union) ?name *)
  (pair ?x ?x)
  (alt (!or (binding ?x ?) (gensym ?x ?)))
  (set (!set ?w a b) ?y)
  (isb (!is var binder) (!is list binder) (!is binder) (!is op))
  (num 3 "s" (!or 4 "t"))
  (deep ((!or a b) (c ?z)) *rest)
  (neg ?x (!not ?x))
  (swap (!or (p ?x ?y) (q ?y ?x)) ?x)
  (none (!not (!or (a *) (b ?))) *tail)
  (!set ?whole (node ?a ?b))
  (other ?x (!not (!or ?x z)))
);

/* The first operator arm `input` matches, with its captures in `values`. */
static int _operator_arm(List input, Var *values) {
  match (input) {
    case %(status (!or ok created) ?code): { values[0] = code; return 1; }
    case %(status (!not ok) ?code): { values[0] = code; return 2; }
    case %(color (!and (!not red) (!not blue))): return 3;
    case %(key (!is type string)): return 4;
    case %(key (!is ?found atom)): { values[0] = found; return 5; }
    case %(tag (!quote (a b))): return 6;
    case %(tag (!quote ?x)): return 7;
    case %((!or ?kind typedef struct union) ?name *): {
      values[0] = kind;
      values[1] = name;
      return 8;
    }
    case %(pair ?x ?x): { values[0] = x; return 9; }
    case %(alt (!or (binding ?x ?) (gensym ?x ?))): {
      values[0] = x;
      return 10;
    }
    case %(set (!set ?w a b) ?y): {
      values[0] = w;
      values[1] = y;
      return 11;
    }
    case %(isb (!is var binder) (!is list binder) (!is binder) (!is op)):
      return 12;
    case %(num 3 "s" (!or 4 "t")): return 13;
    case %(deep ((!or a b) (c ?z)) *rest): {
      values[0] = z;
      values[1] = rest;
      return 14;
    }
    case %(neg ?x (!not ?x)): { values[0] = x; return 15; }
    case %(swap (!or (p ?x ?y) (q ?y ?x)) ?x): {
      values[0] = x;
      values[1] = y;
      return 16;
    }
    case %(none (!not (!or (a *) (b ?))) *tail): {
      values[0] = tail;
      return 17;
    }
    case %(!set ?whole (node ?a ?b)): {
      values[0] = whole;
      values[1] = a;
      values[2] = b;
      return 18;
    }
    case %(other ?x (!not (!or ?x z))): { values[0] = x; return 19; }
  }
  return 0;
}

static void match_operator_arms_agree_with_runtime(void) {
  $test.scoped();
  List inputs = %(
    (status ok 200) (status created 201) (status bad 400) (status ok)
    (color green) (color red) (key "abc") (key 42) (key (l))
    (tag (a b)) (tag ?x) (tag (a c))
    (typedef T int) (struct S) (union U a b) (enum E)
    (pair 1 1) (pair 1 2) (pair 3 3L)
    (alt (binding b 1)) (alt (gensym g 2)) (alt (other o 3)) (alt (binding b))
    (set a 1) (set b 2) (set c 3)
    (isb ?v *l ?w !or) (isb a *l ?w !or)
    (num 3 "s" 4) (num 3 "s" "t") (num 3 "s" 5) (num 3L "s" 4)
    (deep (a (c 9)) r1 r2) (deep (b (c 8))) (deep (d (c 7)))
    (neg 1 2) (neg 1 1)
    (swap (p 1 2) 1) (swap (q 2 1) 1) (swap (p 1 2) 2) (swap (q 1 2) 1)
    (none (c) t1 t2) (none (a 1)) (none (b 1)) (none (b 1 2))
    (node 1 2) (node 1) (other 1 2) (other 1 1) (other 1 z) ()
  );
  foreach (List input in inputs) {
    Var actual[3] = {0}, expected[3] = {0};
    int arm = _operator_arm(input, actual), reference = 0, index = 0;
    foreach (List pattern in _operator_patterns()) {
      MatchCaptureBuffer capture = {.values = expected, .capacity = 3};
      index++;
      if (x2c_match_try_capture(input, pattern, capture)) {
        reference = index;
        break;
      }
    }
    EXPECT_INT_EQ(arm, reference);
    for (int i = 0; arm && i < 3; i++)
      EXPECT_TRUE(actual[i].equal(expected[i]));
  }
}

void match_stmt_suite(void) {
  $test.run(match_operator_arms_agree_with_runtime);
  $test.run(match_flat_capture_agrees_with_runtime);
  $test.run(match_flat_typed_capture_agrees_with_runtime);
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
  $test.run(match_not_pattern_binds_leading_binder);
  $test.run(match_guard_list_binder_matches_runtime);
  $test.run(match_long_atom_binders_compile);
  $test.run(match_dynamic_patterns_do_not_retain_one_value);
  $test.run(match_string_literal_head_binds);
  $test.run(match_head_dispatch_selects_arm);
  $test.run(match_binder_head_arm_keeps_priority);
  $test.run(match_dynamic_head_arm_keeps_priority);
}
