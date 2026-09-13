/*  test-match-plan.x -- differential tests for prepared Match plans

    Every case runs the recursive matcher as the semantic oracle and the
    prepared shared-machine plan as the forced candidate, comparing
    status, result, and exact binding order through interned-List
    identity.  Status cases pin the categorized PREPARED / INELIGIBLE /
    MALFORMED preparation boundary.  Counter cases pin the complexity
    contracts: linear stars, zero losing-span materialization, and
    direct suffix sharing. */

#include "test-support.x"

static MatchCaptureSite capture_site;

/* expected == NULL means no match; the %(()) sentinel means a match
   with no user bindings (both arms report nil bindings). */
static void _exact_case(List input, Var pattern, List expected) {
  MatchPlan plan = MatchPlan.prepare(pattern);
  if (!EXPECT_INT_EQ(plan.status, MACHINE_PREPARED)) {
    MatchPlan.free(plan);
    return;
  }
  int expect_hit = expected != NULL;
  List expect_bindings = expected == %(()) ? NULL : expected;
  List oracle = %(sentinel);
  List candidate = %(sentinel);
  EXPECT_INT_EQ(test_match_oracle_try_match(input, pattern, &oracle),
                expect_hit);
  EXPECT_INT_EQ(plan.try_match(input, &candidate), expect_hit);
  if (expect_hit) {
    EXPECT_TRUE(oracle == expect_bindings);
    EXPECT_TRUE(candidate == expect_bindings);
  }
  MatchPlan.free(plan);
}

/* Oracle/candidate parity without a fixed expectation. */
static void _parity_case(List input, Var pattern) {
  MatchPlan plan = MatchPlan.prepare(pattern);
  if (!EXPECT_INT_EQ(plan.status, MACHINE_PREPARED)) {
    MatchPlan.free(plan);
    return;
  }
  List oracle = %(sentinel), candidate = %(sentinel);
  int oracle_status = test_match_oracle_try_match(input, pattern, &oracle);
  int candidate_status = plan.try_match(input, &candidate);
  EXPECT_INT_EQ(candidate_status, oracle_status);
  if (oracle_status && candidate_status == 1) EXPECT_TRUE(candidate == oracle);
  MatchPlan.free(plan);
}

static void _status_case(Var pattern, int status, const char *reason) {
  MatchPlan plan = MatchPlan.prepare(pattern);
  EXPECT_INT_EQ(plan.status, status);
  EXPECT_STR_EQ(String.new(plan.reason), reason);
  MatchPlan.free(plan);
}

static MachineStats _stats_case(
  MatchPlan plan, List input, int expect_status, List expected) {
  MachineStats stats;
  memset(&stats, 0, sizeof(stats));
  List bindings = %(sentinel);
  int status = MatchPlan.execute(plan, input, &bindings, &stats);
  EXPECT_INT_EQ(status, expect_status);
  if (expect_status == 1 && expected)
    EXPECT_TRUE(bindings == (expected == %(()) ? NULL : expected));
  return stats;
}

static int _count_scan_words(MatchPlan plan, int mode) {
  MachineView view = plan.program.view();
  const MachineWord *code = view.code;
  int count = 0;
  for (int i = 0; i < view.length; i++)
    if (code[i].op == MW_SCAN && code[i].d == mode) count++;
  return count;
}

// literals, quotes, and boxed values - - - - - - - - - - - - - - - - - - - -

static void plan_literals_and_quotes(void) {
  _exact_case(%(tag (a b)), %(tag (a b)), %(()));
  _exact_case(%(tag (a c)), %(tag (a b)), NULL);
  _parity_case(%(sum 1 2.5 "text"), %(sum 1 2.5 "text"));
  _exact_case(NULL, %(), %(()));
  _exact_case(%(a), %(), NULL);

  long wide1 = 42, wide2 = 42;
  Var w1 = wide1, w2 = wide2;
  EXPECT_TRUE(w1 == w2 && w1.u64 != w2.u64);
  _exact_case(%($w2), %($w1), %(()));
  _exact_case(%($w2 tail), %($w1 tail), %(()));

  _exact_case(%(!and ?capture red),
              %(!quote (!and ?capture red)), %(()));
  _exact_case(%(!and other red), %(!quote (!and ?capture red)), NULL);
  // Shallow quote: boxed-equal one-element lists fail !quote but
  // match the ordinary elementwise pattern.
  _exact_case(%($w2), %(!quote ($w1)), NULL);
}

// binders and repeats - - - - - - - - - - - - - - - - - - - - - - - - - - - -

static void plan_binders_and_repeats(void) {
  Var one = 1, two = 2;
  _exact_case(%(sum $one $two), %(sum ?a ?b), %((?b $two) (?a $one)));
  _exact_case(%(ok ok), %(?x ?x), %((?x ok)));
  _exact_case(%(ok other), %(?x ?x), NULL);
  _exact_case(%(a b c), %(? ? ?), %(()));
  _exact_case(%(seq 1 2 3), %(seq *rest), %((*rest (1 2 3))));
  _exact_case(NULL, %(*rest), %((*rest ())));
  _parity_case(NULL, Var.new(<symbol>, <?value>));
  _parity_case(%(a b), Var.new(<symbol>, <?value>));
}

// guards and ordered alternatives - - - - - - - - - - - - - - - - - - - - - -

static void plan_guard_parity(void) {
  _exact_case(%(call add 1 2),
              %(!and ?expr (call add ?lhs ?rhs)),
              %((?rhs 2) (?lhs 1) (?expr (call add 1 2))));
  _exact_case(%(ok 42), %(!or ?node (ok ?value) (error ?msg)),
              %((?value 42) (?node (ok 42))));
  _exact_case(%(ok 7), %(!set ?whole (ok ?value)),
              %((?value 7) (?whole (ok 7))));
  _exact_case(%(ok 7),
              %(!and ?outer (!or ?inner (ok ?number))),
              %((?number 7) (?inner (ok 7)) (?outer (ok 7))));

  // Empty guards keep the oracle's additive/multiplicative identities.
  _exact_case(%(a), %(!and), %(()));
  _exact_case(%(a), %(!or), NULL);
  _exact_case(%(a), %(!not), %(()));
  _exact_case(%(a), %(!set), NULL);

  // A1-A8 ordered alternatives, rollback, and positional publication.
  _exact_case(%(a b), %(!or (?x ?y) (?z b)), %((?y b) (?x a)));
  _exact_case(%(a b), %(!or (?x missing) (?y ?x)), %((?y a) (?x b)));
  Var a3 = %(!and (!or (!and (?head ?x) (?x mark)) (?head ?y))
                  (?head ?x));
  _exact_case(%(mark mark), a3, %((?x mark) (?head mark)));
  _exact_case(%(a b), a3, %((?y b) (?x b) (?head a)));
  _exact_case(%(a b), %(!and (!or (?x b) (a ?y)) (a ?x)), NULL);
  _exact_case(%(a b), %(!set (?x missing) (?y ?x)), %((?y a) (?x b)));
  _exact_case(%(a b), %(!set ?whole (a ?value)),
              %((?value b) (?whole (a b))));
  _exact_case(%(a b), %(!and (!not (?leak missing)) (?x ?y)),
              %((?y b) (?x a)));
  _exact_case(%(a b), %(!not (?leak b)), NULL);
  _exact_case(%(a b),
              %(!or (!and (!or (?x missing) (a ?y)) (a ?x missing))
                    (?z b)),
              %((?z a)));
  Var a8 = %(!and (!or (!and (*s) (a b)) (?x ?y)) (*s));
  _exact_case(%(a b), a8, %((*s (a b))));
  _exact_case(%(c d), a8, %((?y d) (?x c) (*s (c d))));

  // A scanning first arm then whole-input capture: caller cursors are
  // restored between arms.
  _exact_case(%(a b), %(!or (*p missing) ?whole), %((?whole (a b))));
  _exact_case(%(!or ?x red), %(!quote (!or ?x red)), %(()));
}

// !is guard family - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

static void plan_is_parity(void) {
  String string_value = %"hello";
  Var integer_var = 42, float_var = (double) 3.14159;
  List list_value = %(alpha beta);
  Var symbol_var = <bar>;
  List cases = %( ($string_value string)
                  ($integer_var i32)
                  ($float_var f64)
                  ($list_value list)
                  ($symbol_var symbol) );
  foreach (List entry, cases) {
    (Var sample, Symbol tag) = entry;
    List input = %( before $sample after );
    _parity_case(input, %( ?pre (!is type $tag) ?post ));
    _parity_case(input, %( ?pre (!is ?capture type $tag) ?post ));
    _parity_case(input, %( ?pre (!is type string) ?post ));
  }
  List binders = %( ?foo value *bar !or );
  _parity_case(binders, %((!is var binder) ? ? ?));
  _parity_case(binders, %(? ? (!is list binder) ?));
  _parity_case(binders, %((!is binder) ? (!is binder) (!is op)));
  _parity_case(binders, %((!is atom) ? ? ?));
  _parity_case(%((x)), %((!is atom)));
  _parity_case(%(x), %((!is banana)));
  _parity_case(%(x), %((!is type 5)));
  Array arr = %[1, 2];
  Map map = %{ k: 1 };
  List typed = %( $arr $map );
  _parity_case(typed, %((!is type varray) (!is type vmap)));
}

// general stars: the frozen S1-S12 matrix - - - - - - - - - - - - - - - - - -

static List _repeat_pair(int count) {
  List result = NULL;
  for (int i = 0; i < count; i++)
    result = cons(<anchor>, cons(<junk>, result));
  return result;
}

static List _win_pair(int count) {
  List result = %(anchor value terminal);
  for (int i = count; i; i--) {
    result = cons(<junk>, result);
    result = cons(<anchor>, result);
  }
  return result;
}

static List _repeat_atom_50(void) {
  List result = NULL;
  for (int i = 0; i < 50; i++) result = cons(<a>, result);
  return result;
}

static void plan_star_matrix(void) {
  // S1: fresh final star shares the actual suffix in O(1).
  List s1_input = %(tag a b);
  MatchPlan s1 = MatchPlan.prepare(%(tag *rest));
  if (!EXPECT_INT_EQ(s1.status, MACHINE_PREPARED)) return;
  MachineStats s1_stats = _stats_case(s1, s1_input, 1, %((*rest (a b))));
  EXPECT_INT_EQ((int) s1_stats.direct_shares, 1);
  EXPECT_INT_EQ((int) s1_stats.materializations_avoided, 1);
  EXPECT_INT_EQ((int) s1_stats.cons_requests, 0);
  MatchPlan.free(s1);
  _exact_case(s1_input, %(tag *rest), %((*rest (a b))));

  // S2: shortest-first split; the failed write is restored and only
  // the winning prefix is copied, exactly once.
  MatchPlan s2 = MatchPlan.prepare(%(*pre ?last));
  MachineStats s2_stats = _stats_case(s2, %(a b), 1, %((?last b) (*pre (a))));
  EXPECT_INT_EQ((int) s2_stats.retries, 1);
  EXPECT_INT_EQ((int) s2_stats.span_descriptors, 1);
  EXPECT_INT_EQ((int) s2_stats.materialization_completions, 1);
  EXPECT_INT_EQ((int) s2_stats.materialized_cells, 1);
  MatchPlan.free(s2);

  // S3/S4: anchored scans with offsets and false anchors.
  _exact_case(%(p q mark v end), %(*pre ?head mark ?value end),
              %((?value v) (?head q) (*pre (p))));
  _exact_case(%(a mark x mark y end), %(*pre mark ?value end),
              %((?value y) (*pre (a mark x))));

  // S5: false-anchor miss and win stay linear; losing candidates
  // construct nothing.
  int sizes[3] = { 5, 50, 500 };
  for (int i = 0; i < 3; i++) {
    int size = sizes[i];
    Var pattern = %(*pre anchor ?seen terminal);
    MatchPlan plan = MatchPlan.prepare(pattern);
    if (!EXPECT_INT_EQ(plan.status, MACHINE_PREPARED)) return;
    MachineStats miss = _stats_case(plan, _repeat_pair(size), 0, NULL);
    EXPECT_INT_EQ((int) miss.materialization_requests, 0);
    EXPECT_INT_EQ((int) miss.cons_requests, 0);
    EXPECT_INT_EQ((int) miss.span_descriptors, 0);
    EXPECT_TRUE(miss.scan_cells == (long) size * 2);
    EXPECT_TRUE(miss.retries == size);
    List prefix = _repeat_pair(size);
    MachineStats win = _stats_case(plan, _win_pair(size), 1,
                                   %((?seen value) (*pre $prefix)));
    EXPECT_TRUE(win.materialization_requests == 1);
    EXPECT_TRUE(win.materialized_cells == (long) size * 2);
    MatchPlan.free(plan);
  }

  // S6-S8: nested continuation, local cut, multiple stars.
  _exact_case(%(wrap (a b) tail), %(wrap (*x b) tail), %((*x (a))));
  _exact_case(%(wrap (a b) wrong), %(wrap (*x b) tail), NULL);
  _exact_case(%((a b) a), %((*x *y) *x), NULL);
  _exact_case(%(a x b y c), %(*left x *middle y *right),
              %((*right (c)) (*middle (b)) (*left (a))));

  // S9: repeated interior star compares the range without a List.
  MatchPlan s9 = MatchPlan.prepare(%(*same pivot *same end));
  MachineStats s9_hit = _stats_case(s9, %(a pivot a end), 1, %((*same (a))));
  EXPECT_TRUE(s9_hit.range_comparisons >= 1);
  MachineStats s9_miss = _stats_case(s9, %(a pivot b end), 0, NULL);
  EXPECT_INT_EQ((int) s9_miss.materialization_requests, 0);
  EXPECT_INT_EQ((int) s9_miss.cons_requests, 0);
  MatchPlan.free(s9);

  // S10: final repetition is shallow identity; canonical interning
  // makes (a pivot a) succeed, boxed-equal wide values fail finally
  // but succeed in interior Var.equal comparison.
  MatchPlan s10 = MatchPlan.prepare(%(*same pivot *same));
  MachineStats s10_canon = _stats_case(s10, %(a pivot a), 1, %((*same (a))));
  EXPECT_TRUE(s10_canon.final_range_comparisons == 1);
  EXPECT_INT_EQ((int) s10_canon.materialization_requests, 0);
  long wide1 = 42, wide2 = 42;
  Var w1 = wide1, w2 = wide2;
  MachineStats s10_wide = _stats_case(s10, %($w1 pivot $w2), 0, NULL);
  EXPECT_TRUE(s10_wide.final_range_comparisons == 1);
  EXPECT_INT_EQ((int) s10_wide.materialization_requests, 0);
  MatchPlan.free(s10);
  _exact_case(%($w1 pivot $w2 end), %(*same pivot *same end),
              %((*same ($w1))));
  _exact_case(%(a pivot a),
              %(!and (*same pivot *same) (*same pivot *same)
                     (*same pivot *same)),
              %((*same (a))));

  // S11: guard continuation and guard-failure rollback.
  _exact_case(%(a b), %(!set ?whole (*x b)), %((*x (a)) (?whole (a b))));
  _exact_case(%(a b), %(!and (*x b) missing), NULL);

  // S12: two unanchored stars keep the oracle's failure contract.
  _exact_case(_repeat_atom_50(), %(*left *right missing), NULL);
}

static void plan_star_supplementals(void) {
  _exact_case(%(a b), %(*), %(()));
  _exact_case(%(a mark z), %(* mark ?value), %((?value z)));
  _exact_case(NULL, %(*rest), %((*rest ())));
  MatchPlan empty_prefix = MatchPlan.prepare(%(*pre b));
  MachineStats empty_stats = _stats_case(empty_prefix, %(b), 1, %((*pre ())));
  EXPECT_TRUE(empty_stats.materialization_requests == 1);
  EXPECT_INT_EQ((int) empty_stats.cons_requests, 0);
  MatchPlan.free(empty_prefix);
  _exact_case(%(a (tag v) end), %(*pre (tag v) end), %((*pre (a))));
  _exact_case(%(*x), %(!quote (*x)), %(()));

  // A lazy span discarded beneath !not materializes nothing.
  MatchPlan not_span = MatchPlan.prepare(%(!not (*x b)));
  MachineStats not_hit = _stats_case(not_span, %(a b), 0, NULL);
  EXPECT_TRUE(not_hit.span_descriptors >= 1);
  EXPECT_INT_EQ((int) not_hit.materialization_requests, 0);
  _stats_case(not_span, %(a c), 1, %(()));
  MatchPlan.free(not_span);

  // Comparison-mode selection: boxed wide and String anchors keep
  // general equality; narrow numeric anchors keep raw bits.
  long wide_value = 77, twin_value = 77;
  Var anchor1 = wide_value, anchor2 = twin_value;
  MatchPlan general = MatchPlan.prepare(%(*pre $anchor1 end));
  EXPECT_INT_EQ(_count_scan_words(general, MACHINE_COMPARE_EQUAL), 1);
  List general_bindings = %(sentinel);
  EXPECT_INT_EQ(general.try_match(%(lead $anchor2 end), &general_bindings), 1);
  EXPECT_TRUE(general_bindings == %((*pre (lead))));
  MatchPlan.free(general);

  MatchPlan numeric = MatchPlan.prepare(%(*pre 3 ?value));
  EXPECT_INT_EQ(_count_scan_words(numeric, MACHINE_COMPARE_EQUAL), 0);
  long cross_value = 3;
  Var cross = cross_value;
  _exact_case(%(lead $cross v), %(*pre 3 ?value), NULL);
  _exact_case(%(lead 3 v), %(*pre 3 ?value),
              %((?value v) (*pre (lead))));
  MatchPlan.free(numeric);

  String canonical = String.new("scan-needle"), transient = String.malloc(32);
  strcpy(transient, "scan-needle");
  Var canonical_anchor = canonical, transient_input = transient;
  EXPECT_TRUE(transient_input == canonical_anchor &&
              transient_input.u64 != canonical_anchor.u64);
  MatchPlan text = MatchPlan.prepare(%(*pre $canonical_anchor ?v));
  EXPECT_INT_EQ(_count_scan_words(text, MACHINE_COMPARE_EQUAL), 1);
  List text_bindings = %(sentinel);
  EXPECT_INT_EQ(text.try_match(%(lead $transient_input v), &text_bindings), 1);
  EXPECT_TRUE(text_bindings == %((?v v) (*pre (lead))));
  MatchPlan.free(text);
  String.free(transient);

  // Long anchored miss stays linear and loop-safe.
  List long_input = NULL;
  for (int i = 4999; i >= 0; i--) long_input = cons(i, long_input);
  MatchPlan long_plan = MatchPlan.prepare(%(*items ?last absent));
  MachineStats long_stats = _stats_case(long_plan, long_input, 0, NULL);
  EXPECT_TRUE(long_stats.scan_cells <= 5001);
  EXPECT_INT_EQ((int) long_stats.cons_requests, 0);
  MatchPlan.free(long_plan);
}

// categorized preparation boundary - - - - - - - - - - - - - - - - - - - - -

static void plan_status_categorization(void) {
  _status_case(%(!or *whole missing), MACHINE_MALFORMED,
               "leading-list-binder-in-guard");
  _status_case(%(!not *whole missing), MACHINE_MALFORMED,
               "leading-list-binder-in-guard");
  _status_case(%(!set *whole missing), MACHINE_MALFORMED,
               "leading-list-binder-in-guard");
  _status_case(%(wrap (!and *x a) end), MACHINE_MALFORMED,
               "leading-list-binder-in-guard");
  _status_case(%(!quote (!or *x red)), MACHINE_PREPARED, "prepared");
  _status_case(%(!or *whole ?bad-name), MACHINE_MALFORMED,
               "binder-name");
  _status_case(%(!quote a b), MACHINE_INELIGIBLE, "quote-arity");
  _status_case(%(!quote), MACHINE_INELIGIBLE, "quote-arity");

  // Frame depth is fenced at preparation, not mid-execution.
  Var deep = %(x);
  for (int i = 0; i < MACHINE_FRAME_MAX + 8; i++) deep = %((!and $deep));
  _status_case(deep, MACHINE_INELIGIBLE, "frame-depth");

  // A pattern wider than the code fence is categorized cleanly.
  List wide = NULL;
  for (int i = 0; i < 41; i++) {
    List sub = NULL;
    for (int j = 0; j < 100; j++) sub = cons(<?x>, sub);
    wide = cons(sub, wide);
  }
  _status_case(wide, MACHINE_INELIGIBLE, "code-capacity");

  // Binder capacity is fenced by the layout, ahead of lowering.
  List binders = NULL;
  for (int i = 0; i < MACHINE_BINDER_MAX + 1; i++) {
    Symbol binder = Symbol.new(String.printf("?w%d", i));
    binders = cons(Symbol.var(binder), binders);
  }
  _status_case(binders, MACHINE_MALFORMED, "binder-capacity");

}

// fenced patterns are loud, not silently unmatchable - - - - - - - - - - - -

/* Preparation still reports INELIGIBLE, but no entry point can answer for
   such a plan, so each one raises `<size-limit>` naming the fence. */

static Var _fenced_deep_pattern(void) {
  Var deep = %(x);
  for (int i = 0; i < MACHINE_FRAME_MAX + 8; i++) deep = %((!and $deep));
  return deep;
}

// 200 repeats of one binder: wider than the segment fence, one binder wide
static List _fenced_wide_pattern(List tail) {
  for (int i = 0; i < 200; i++) tail = cons(<?x>, tail);
  return tail;
}

static void plan_fenced_pattern_raises_at_every_entry(void) {
  MatchPlan plan = MatchPlan.prepare(_fenced_deep_pattern());
  if (!EXPECT_INT_EQ(plan.status, MACHINE_INELIGIBLE)) {
    MatchPlan.free(plan);
    return;
  }
  List input = %(x), bindings = %(sentinel), results = %(sentinel);
  Var found = <sentinel>, replaced = <sentinel>;
  Var values[MACHINE_BINDER_MAX];
  MatchCaptureBuffer captures = { values, 0, MACHINE_BINDER_MAX };
  int caught = 0;

  try MatchPlan.try_match(plan, input, &bindings);
  catch %(size-limit * (fence ?seen) *): {
    caught++;
    EXPECT_STR_EQ(seen.str(), "frame-depth");
  }
  try MatchPlan.try_capture(plan, input, &captures);
  catch %(size-limit *): caught++;
  try MatchPlan.try_search(plan, input, &found, &bindings);
  catch %(size-limit *): caught++;
  try MatchPlan.search(plan, input, &results);
  catch %(size-limit *): caught++;
  try MatchPlan.try_match_replace(plan, input, %(changed), &replaced);
  catch %(size-limit *): caught++;
  try MatchPlan.search_replace(plan, input, %(changed), &results);
  catch %(size-limit *): caught++;

  EXPECT_INT_EQ(caught, 6);
  EXPECT_TRUE(bindings == %(sentinel));
  EXPECT_TRUE(results == %(sentinel));
  EXPECT_TRUE(found == <sentinel>);
  EXPECT_TRUE(replaced == <sentinel>);
  MatchPlan.free(plan);
}

static void fenced_pattern_raises_at_every_consumer(void) {
  Var cached = _fenced_wide_pattern(NULL);
  List input = %(x), bindings = %(sentinel);
  int caught = 0;

  try List.try_match(input, cached, &bindings);
  catch %(size-limit * (fence ?seen) *): {
    caught++;
    EXPECT_STR_EQ(seen.str(), "segment-width");
  }
  try List.search(input, cached);
  catch %(size-limit *): caught++;
  try List.search_replace(input, cached, %(changed));
  catch %(size-limit *): caught++;

  // a transient String bypasses admission, so this one prepares transiently
  String transient = String.malloc(8);
  strcpy(transient, "bypass");
  Var bypassed = _fenced_wide_pattern(cons(transient, NULL));
  try List.try_match(input, bypassed, &bindings);
  catch %(size-limit *): caught++;
  String.free(transient);

  // the arm could never be selected, so registering the catch is the error
  int target = 0;
  try {
    ErrorHandler handler = x2c_error_catch_push(&target, 1, cached);
    x2c_error_catch_detach(handler);
    x2c_error_catch_close(handler);
  }
  catch %(size-limit * (fence ?seen) *): {
    caught++;
    EXPECT_STR_EQ(seen.str(), "segment-width");
  }

  EXPECT_INT_EQ(caught, 5);
  EXPECT_TRUE(bindings == %(sentinel));
  // every consumer reported the fence and none returned a plan
}

// consumer parity: search, replacement - - - - - - - - - - - - - - - - - - -

static void plan_search_parity(void) {
  List input = %((item 1) (wrapper (item 2)) (item 3));
  MatchPlan plan = MatchPlan.prepare(%(item ?id));
  Var oracle_match = <unchanged>;
  List oracle_bindings = %(unchanged);
  Var plan_match = <unchanged>;
  List plan_bindings = %(unchanged);
  EXPECT_TRUE(test_match_oracle_try_search(input, %(item ?id),
                                          &oracle_match,
                                          &oracle_bindings));
  EXPECT_INT_EQ(plan.try_search(input, &plan_match, &plan_bindings), 1);
  EXPECT_TRUE(plan_match == oracle_match);
  EXPECT_TRUE(plan_bindings == oracle_bindings);
  MatchPlan.free(plan);

  MatchPlan missing = MatchPlan.prepare(%(missing));
  EXPECT_INT_EQ(missing.try_search(input, &plan_match, &plan_bindings), 0);
  MatchPlan.free(missing);

  List payload = %(a list with a "string");
  List corpus = %( root (item 1 $payload) (item 2 3.25)
                   (wrapper (item 1 $payload)) );
  MatchPlan pairs = MatchPlan.prepare(%(item ?id ?value));
  List oracle_results =
    test_match_oracle_search(corpus, %(item ?id ?value));
  List plan_results = %(unchanged);
  EXPECT_INT_EQ(pairs.search(corpus, &plan_results), 1);
  EXPECT_TRUE(plan_results == oracle_results);
  MatchPlan.free(pairs);

  // Explicit empty-list values are observed; the implicit terminal
  // cdr is not.
  List empty = NULL, holder = %($empty atom);
  MatchPlan nil_plan = MatchPlan.prepare(%());
  List nil_results = %(unchanged);
  EXPECT_INT_EQ(nil_plan.search(holder, &nil_results), 1);
  EXPECT_TRUE(nil_results == test_match_oracle_search(holder, %()));
  List top_results = %(unchanged);
  EXPECT_INT_EQ(nil_plan.search(empty, &top_results), 1);
  EXPECT_TRUE(top_results == test_match_oracle_search(empty, %()));
  MatchPlan.free(nil_plan);

  // Guard and !is patterns through full search.
  List guarded = %( keep deprecated other );
  MatchPlan not_plan = MatchPlan.prepare(%(!not ?node deprecated));
  List not_results = %(unchanged);
  EXPECT_INT_EQ(not_plan.search(guarded, &not_results), 1);
  EXPECT_TRUE(not_results ==
              test_match_oracle_search(guarded,
                                      %(!not ?node deprecated)));
  MatchPlan.free(not_plan);

  List samples = %( ?foo 42 (a) "text" );
  MatchPlan is_plan = MatchPlan.prepare(%(!is ?hit type i32));
  List is_results = %(unchanged);
  EXPECT_INT_EQ(is_plan.search(samples, &is_results), 1);
  EXPECT_TRUE(is_results ==
              test_match_oracle_search(samples, %(!is ?hit type i32)));
  MatchPlan.free(is_plan);
}

/* Atom patterns use the same compiled plan path as list patterns. */
static void atom_consumers_match_the_reference(void) {
  Var pattern = <item>;
  List corpus = %( item (wrapper item other) ((item) item) );

  List results = corpus.search(pattern);
  EXPECT_INT_EQ(results.len(), 4);
  EXPECT_TRUE(results == test_match_oracle_search(corpus, pattern));

  Var found = <unchanged>, oracle_found = <unchanged>;
  List bindings = %(unchanged), oracle_bindings = %(unchanged);
  EXPECT_INT_EQ(corpus.try_search(pattern, &found, &bindings),
                test_match_oracle_try_search(corpus, pattern, &oracle_found,
                                             &oracle_bindings));
  EXPECT_TRUE(found == oracle_found);
  EXPECT_TRUE(bindings == oracle_bindings);

  List direct = %(item);
  List matched = %(unchanged), oracle_matched = %(unchanged);
  EXPECT_INT_EQ(direct.try_match(pattern, &matched),
                test_match_oracle_try_match(direct, pattern, &oracle_matched));
  EXPECT_TRUE(matched == oracle_matched);

  Var template = <replaced>;
  List substituted = corpus.search_replace(pattern, template);
  EXPECT_TRUE(substituted ==
              %( replaced (wrapper replaced other) ((replaced) replaced) ));
  EXPECT_TRUE(substituted ==
              test_match_oracle_search_replace(corpus, pattern, template));

  Var replaced = <unchanged>, oracle_replaced = <unchanged>;
  EXPECT_INT_EQ(
    direct.try_match_replace(pattern, template, &replaced),
    test_match_oracle_try_match_replace(direct, pattern, template,
                                        &oracle_replaced));
  EXPECT_TRUE(replaced == oracle_replaced);
}

static void plan_replace_parity(void) {
  List input = %(tag value);
  MatchPlan plan = MatchPlan.prepare(%(tag ?payload));
  Var result = <unchanged>;
  EXPECT_INT_EQ(plan.try_match_replace(input, Var.new(<symbol>, <?payload>),
                                       &result), 1);
  EXPECT_TRUE(result == <value>);
  EXPECT_INT_EQ(plan.try_match_replace(input, %(wrapped ?payload),
                                       &result), 1);
  EXPECT_TRUE(result is <list> && result.list() == %(wrapped value));
  EXPECT_INT_EQ(plan.try_match_replace(input, %(*missing tail),
                                       &result), 1);
  EXPECT_TRUE(result is <list> && result.list() == %(tail));
  EXPECT_INT_EQ(plan.try_match_replace(input, %(!quote ?payload),
                                       &result), 1);
  EXPECT_TRUE(result == <?payload>);
  List empty = NULL;
  EXPECT_INT_EQ(plan.try_match_replace(input, empty, &result), 1);
  EXPECT_TRUE(result is <list> && result.list() == NULL);
  result = <unchanged>;
  MatchPlan absent = MatchPlan.prepare(%(missing));
  EXPECT_INT_EQ(absent.try_match_replace(input, Var.new(<symbol>, <changed>),
                                         &result), 0);
  EXPECT_TRUE(result == <unchanged>);
  MatchPlan.free(absent);
  MatchPlan.free(plan);

  // Star template splice parity.
  List payload = %(a list with a "string");
  List chunk = %( chunk 10 2.5 $payload 5 );
  MatchPlan tail_plan = MatchPlan.prepare(%(chunk ?first ?mid *tail));
  Var tail_result = <unchanged>;
  EXPECT_INT_EQ(tail_plan.try_match_replace(chunk,
                                            Var.new(<symbol>, <"*tail">),
                                            &tail_result), 1);
  Var tail_oracle = <unchanged>;
  EXPECT_TRUE(test_match_oracle_try_match_replace(
    chunk, %(chunk ?first ?mid *tail),
    Var.new(<symbol>, <"*tail">), &tail_oracle));
  EXPECT_TRUE(tail_result == tail_oracle);
  MatchPlan.free(tail_plan);

  // Full search replacement across every consumer-visible node.
  List corpus = %( root (item 1 2) (item 2 5.5) (wrapper (item 3 $payload)) );
  Var pattern = %(item ?id ?value);
  Var template = %(replaced ?id ?value $payload);
  MatchPlan sr = MatchPlan.prepare(pattern);
  List oracle = test_match_oracle_search_replace(corpus, pattern, template);
  List candidate = %(unchanged);
  EXPECT_INT_EQ(sr.search_replace(corpus, template, &candidate), 1);
  EXPECT_TRUE(candidate == oracle);
  MatchPlan.free(sr);

  List is_input = %( ?foo value ?bar );
  Var is_pattern = %(!is ?binder binder);
  Var is_template = %(binding ?binder);
  MatchPlan isr = MatchPlan.prepare(is_pattern);
  List is_oracle = test_match_oracle_search_replace(is_input, is_pattern,
                                                   is_template);
  List is_candidate = %(unchanged);
  EXPECT_INT_EQ(isr.search_replace(is_input, is_template, &is_candidate), 1);
  EXPECT_TRUE(is_candidate == is_oracle);
  MatchPlan.free(isr);
}

// positional capture contract - - - - - - - - - - - - - - - - - - - - - - -

static int _capture_present(MatchCaptureBuffer *captures, int index) {
  return MatchCaptureBuffer.has(captures, index);
}

static void capture_layout_owns_canonical_order(void) {
  MatchCaptureLayout layout = MatchCaptureLayout.analyze(
    %(!and ?root
           (!or (?left ?shared) (?right ?shared))
           (!not (?hidden))
           (!quote (?quoted))
           *tail)
  );
  if (!EXPECT_NOT_NULL(layout)) return;
  EXPECT_INT_EQ(layout.status, MACHINE_PREPARED);
  EXPECT_TRUE(layout.possible_list() ==
              %(?root ?left ?shared ?right ?hidden *tail));
  EXPECT_TRUE(layout.definite_list() == %(?root ?shared *tail));
  EXPECT_INT_EQ(layout.index(Atom.intern(%"?root")), 0);
  EXPECT_INT_EQ(layout.index(Atom.intern(%"?shared")), 2);
  EXPECT_INT_EQ(layout.index(Atom.intern(%"*tail")), 5);
  layout.free();

  MatchPlan plan = MatchPlan.prepare(
    %(node ?first (?second ?first) *rest)
  );
  if (!EXPECT_INT_EQ(plan.status, MACHINE_PREPARED)) {
    plan.free();
    return;
  }
  MachineView view = plan.program.view();
  EXPECT_INT_EQ(view.binder_count, plan.layout.binder_count);
  for (int i = 0; i < view.binder_count; i++)
    EXPECT_TRUE(view.binders[i].u64 == plan.layout.binders[i].u64);
  plan.free();
}

static void prepared_capture_is_atomic_and_positional(void) {
  MatchPlan plan = MatchPlan.prepare(
    %(!or (ok ?value) (err ?message *rest))
  );
  if (!EXPECT_INT_EQ(plan.status, MACHINE_PREPARED)) {
    plan.free();
    return;
  }
  Var values[3] = {
    <old0>, <old1>, <old2>
  };
  MatchCaptureBuffer captures = { values, 0x55UL, 3 };

  EXPECT_INT_EQ(plan.try_capture(%(missing), &captures), 0);
  EXPECT_TRUE(values[0] == <old0>);
  EXPECT_TRUE(values[1] == <old1>);
  EXPECT_TRUE(values[2] == <old2>);
  EXPECT_TRUE(captures.present == 0x55UL);

  MatchCaptureBuffer short_buffer = { values, 0x55UL, 2 };
  EXPECT_INT_EQ(plan.try_capture(%(ok 7), &short_buffer), -1);
  EXPECT_TRUE(values[0] == <old0>);
  EXPECT_TRUE(short_buffer.present == 0x55UL);

  EXPECT_INT_EQ(plan.try_capture(%(err bad a b), &captures), 1);
  int value_index = plan.layout.index(Atom.intern(%"?value"));
  int message_index = plan.layout.index(Atom.intern(%"?message"));
  int rest_index = plan.layout.index(Atom.intern(%"*rest"));
  EXPECT_FALSE(_capture_present(&captures, value_index));
  EXPECT_TRUE(_capture_present(&captures, message_index));
  EXPECT_TRUE(_capture_present(&captures, rest_index));
  EXPECT_TRUE(values[message_index] == <bad>);
  EXPECT_TRUE(values[rest_index].list() == %(a b));
  plan.free();
}

/* One capacity fence answers both implementations: the layout refuses the
   pattern before either implementation runs it. */
static void capture_layout_refuses_past_the_binder_limit(void) {
  Array pattern_values = %[], input_values = %[];
  for (int i = 0; i < MACHINE_BINDER_MAX + 1; i++) {
    pattern_values.push(Atom.intern(%"?binder_$i"));
    input_values.push(i);
  }
  List pattern = pattern_values, input = input_values;
  MatchCaptureLayout layout = MatchCaptureLayout.analyze(pattern);
  if (!EXPECT_NOT_NULL(layout)) {
    pattern_values.free();
    input_values.free();
    return;
  }
  EXPECT_INT_EQ(layout.status, MACHINE_MALFORMED);
  EXPECT_STR_EQ(String.new(layout.reason), "binder-capacity");
  EXPECT_INT_EQ(layout.binder_count, 0);
  MatchPlan plan = MatchPlan.prepare(pattern);
  EXPECT_INT_EQ(plan.status, MACHINE_MALFORMED);
  EXPECT_STR_EQ(String.new(plan.reason), "binder-capacity");

  Var values[MACHINE_BINDER_MAX];
  MatchCaptureBuffer captures = { values, 0, MACHINE_BINDER_MAX };
  EXPECT_INT_EQ(
    match_recursive_try_capture(layout, input, &captures), 0
  );
  EXPECT_TRUE(input.match(pattern) == NULL);

  // one binder short of the fence still matches
  pattern_values.pop();
  input_values.pop();
  List fitted = pattern_values;
  EXPECT_INT_EQ(input_values.list().match(fitted).len(),
                MACHINE_BINDER_MAX);

  plan.free();
  layout.free();
  pattern_values.free();
  input_values.free();
}

static void capture_presence_is_separate_from_void(void) {
  Var binder = Atom.intern(%"?captured_void");
  MatchPlan plan = MatchPlan.prepare(binder);
  if (!EXPECT_NOT_NULL(plan)) return;
  Var value = <old>;
  MatchCaptureBuffer captures = { &value, 0, 1 };
  EXPECT_INT_EQ(plan.execute_capture(void, &captures, NULL), 1);
  EXPECT_TRUE(_capture_present(&captures, 0));
  EXPECT_TRUE(value is void);
  plan.free();
}

static void source_site_owns_only_its_static_plan(void) {
  Var value = <old>;
  MatchCaptureBuffer captures = { &value, 0x55UL, 1 };
  Var pattern = %(ok ?value);
  EXPECT_INT_EQ(
    x2c_match_site_try_capture(&capture_site, %(ok 7), pattern, &captures), 1
  );
  EXPECT_TRUE(capture_site.plan != NULL);
  EXPECT_INT_EQ(value.int(), 7);

  value = <old>;
  captures.present = 0x55UL;
  EXPECT_INT_EQ(
    x2c_match_site_try_capture(
      &capture_site, %(missing), pattern, &captures
    ), 0
  );
  EXPECT_TRUE(value == <old>);
  EXPECT_TRUE(captures.present == 0x55UL);

  value = <old>;
  captures.present = 0x55UL;
  EXPECT_INT_EQ(
    x2c_match_site_try_capture(&capture_site, %(ok 9), pattern, &captures), 1
  );
  EXPECT_INT_EQ(value.int(), 9);
}

static MatchCaptureSite match_site, try_match_site, sentinel_site;
static MatchCaptureSite search_site, try_search_site;
static MatchCaptureSite match_replace_site, try_match_replace_site;
static MatchCaptureSite search_replace_site;

/* Each compiler-emitted entry must answer exactly as the operation it
   replaces, on a hit and on a miss, and must keep answering after its plan
   is published. The per-call operation is the oracle. */
static void source_sites_reproduce_the_runtime_operations(void) {
  Var pattern = %(ok ?value);
  List hit = %(ok 7), miss = %(no 7);
  List document = %((ok 7) (ok 9));

  for (int round = 0; round < 2; round++) {
    List site_bindings = x2c_match_site_match(&match_site, hit, pattern);
    EXPECT_LIST_EQ(site_bindings, hit.match(pattern));
    EXPECT_NULL(x2c_match_site_match(&match_site, miss, pattern));

    // a binder-free hit reports the nonnull no-bindings sentinel
    EXPECT_LIST_EQ(
      x2c_match_site_match(&sentinel_site, hit, %(ok 7)), %(()));

    List bindings = %(untouched);
    EXPECT_INT_EQ(
      x2c_match_site_try_match(&try_match_site, hit, pattern, &bindings), 1);
    EXPECT_LIST_EQ(bindings, hit.match(pattern));
    EXPECT_INT_EQ(
      x2c_match_site_try_match(&try_match_site, miss, pattern, &bindings), 0);
    EXPECT_LIST_EQ(bindings, hit.match(pattern));

    EXPECT_LIST_EQ(
      x2c_match_site_search(&search_site, document, pattern),
      document.search(pattern));

    Var found = <untouched>, List found_bindings = %(untouched);
    EXPECT_INT_EQ(
      x2c_match_site_try_search(
        &try_search_site, document, pattern, &found, &found_bindings), 1);
    EXPECT_LIST_EQ(found.list(), %(ok 7));
    EXPECT_LIST_EQ(found_bindings, hit.match(pattern));

    List replaced = x2c_match_site_match_replace(
      &match_replace_site, hit, pattern, %(got ?value));
    EXPECT_LIST_EQ(replaced, %(got 7));
    // a miss returns the input object itself, not a copy
    EXPECT_PTR_EQ(
      x2c_match_site_match_replace(
        &match_replace_site, miss, pattern, %(got ?value)),
      miss);

    Var out = <untouched>;
    EXPECT_INT_EQ(
      x2c_match_site_try_match_replace(
        &try_match_replace_site, hit, pattern, %(got ?value), &out), 1);
    EXPECT_LIST_EQ(out.list(), %(got 7));
    EXPECT_INT_EQ(
      x2c_match_site_try_match_replace(
        &try_match_replace_site, miss, pattern, %(got ?value), &out), 0);
    EXPECT_LIST_EQ(out.list(), %(got 7));

    EXPECT_LIST_EQ(
      x2c_match_site_search_replace(
        &search_replace_site, document, pattern, %(got ?value)),
      %((got 7) (got 9)));
    EXPECT_PTR_EQ(
      x2c_match_site_search_replace(
        &search_replace_site, %(none), pattern, %(got ?value)),
      %(none));
  }
  EXPECT_TRUE(match_site.plan != NULL);
  EXPECT_TRUE(search_replace_site.plan != NULL);
}

static MatchCaptureSite fenced_site;

/* A site cannot retain an ineligible plan, so the call falls back to the
   per-call route and that route names the public operation in the fence. */
static void source_site_reports_a_fence_like_the_operation(void) {
  Var fenced = _fenced_wide_pattern(NULL);
  int caught = 0;
  for (int round = 0; round < 2; round++) {
    try x2c_match_site_search(&fenced_site, %(x), fenced);
    catch %(size-limit (owner ?who) (fence ?seen)): {
      caught++;
      EXPECT_STR_EQ(seen.str(), "segment-width");
      EXPECT_STR_EQ(who.str(), "List.search");
    }
  }
  EXPECT_INT_EQ(caught, 2);
}

// immutability and reuse - - - - - - - - - - - - - - - - - - - - - - - - - -

static void plan_programs_stay_immutable(void) {
  MatchPlan plan = MatchPlan.prepare(%(?x ?x));
  if (!EXPECT_INT_EQ(plan.status, MACHINE_PREPARED)) return;
  for (int i = 0; i < 4; i++) {
    List bindings = %(sentinel);
    EXPECT_INT_EQ(plan.try_match(%(ok ok), &bindings), 1);
    EXPECT_TRUE(bindings == %((?x ok)));
    EXPECT_INT_EQ(plan.try_match(%(ok other), &bindings), 0);
  }
  MatchPlan.free(plan);
}

static void plan_long_atom_binder_layout(void) {
  Atom value_binder = Atom.intern(%"?VeryLongIdentifierValue");
  Atom list_binder = Atom.intern(%"*RemainingLongValues");
  MatchPlan plan = MatchPlan.prepare(
    %(item ?VeryLongIdentifierValue *RemainingLongValues)
  );
  if (!EXPECT_INT_EQ(plan.status, MACHINE_PREPARED)) {
    MatchPlan.free(plan);
    return;
  }
  MachineView view = plan.program.view();
  EXPECT_INT_EQ(sizeof(Atom), 8);
  EXPECT_INT_EQ(view.binder_count, 2);
  EXPECT_TRUE(
    view.binders[0].u64 == value_binder.u64 ||
    view.binders[1].u64 == value_binder.u64
  );
  EXPECT_TRUE(
    view.binders[0].u64 == list_binder.u64 ||
    view.binders[1].u64 == list_binder.u64
  );
  _exact_case(%(item 8 tail),
              %(item ?VeryLongIdentifierValue *RemainingLongValues),
              %((*RemainingLongValues (tail)) (?VeryLongIdentifierValue 8)));
  MatchPlan.free(plan);
}


$(import "test-macros.xmacro")

void match_plan_suite(void) {
  $test.run(plan_literals_and_quotes);
  $test.run(plan_binders_and_repeats);
  $test.run(plan_guard_parity);
  $test.run(plan_is_parity);
  $test.run(plan_star_matrix);
  $test.run(plan_star_supplementals);
  $test.run(plan_status_categorization);
  $test.run(plan_fenced_pattern_raises_at_every_entry);
  $test.run(fenced_pattern_raises_at_every_consumer);
  $test.run(plan_search_parity);
  $test.run(atom_consumers_match_the_reference);
  $test.run(plan_replace_parity);
  $test.run(capture_layout_owns_canonical_order);
  $test.run(prepared_capture_is_atomic_and_positional);
  $test.run(capture_layout_refuses_past_the_binder_limit);
  $test.run(capture_presence_is_separate_from_void);
  $test.run(source_site_owns_only_its_static_plan);
  $test.run(source_sites_reproduce_the_runtime_operations);
  $test.run(source_site_reports_a_fence_like_the_operation);
  $test.run(plan_programs_stay_immutable);
  $test.run(plan_long_atom_binder_layout);
}
