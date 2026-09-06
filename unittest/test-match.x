/*  test-match.x -- unit tests for pattern matching helpers */

#include "test-support.x"

static void match_binds_variables(void) {
  Var one = 1, two = 2;
  List input = %( sum $one $two );
  List pattern = %( sum ?a ?b );
  List bindings = input.match(pattern);
  if (!EXPECT_NOT_NULL(bindings)) return;
  EXPECT_VAR_EQ(bindings.assoc(<?a>), one);
  EXPECT_VAR_EQ(bindings.assoc(<?b>), two);
}

static void debug_list_dump(List lst, int depth) {
  String indent = String.printf("%*s", depth * 2, "");
  if (!lst) {
    Stdout.printf("%s(null)\n", indent);
    return;
  }
  Var head = lst.car();
  List tail = lst.cdr();
  Stdout.printf("%sNODE %p\n", indent, lst);
  Stdout.printf("%s  car.u64=0x%016llX tag=%s\n",
                indent, (unsigned long long) head.u64, head.tag().str());
  if (head is <list>) {
    List child = head;
    Stdout.printf("%s  car.list=%p\n", indent, child);
    debug_list_dump(child, depth + 1);
  } else {
    Stdout.printf("%s  car.value=%s\n", indent, head);
  }
  Stdout.printf("%s  cdr=%p\n", indent, tail);
  if (tail) debug_list_dump(tail, depth + 1);
}

static void match_star_binder_splices(void) {
  Var one = 1, two = 2, three = 3;
  List input = %( seq $one $two $three );
  List pattern = %( seq *rest );
  List bindings = input.match(pattern);
  if (!EXPECT_NOT_NULL(bindings)) return;
  Symbol rest_sym = <"*rest">;
  List rest = bindings.assoc(rest_sym);
  if (!EXPECT_INT_EQ(rest.len(), 3)) return;
  EXPECT_INT_EQ(rest.car().integer(), 1);
}

static void match_typed_empty_list(void) {
  List empty = NULL;

  List literal_bindings = empty.match(empty);
  EXPECT_NOT_NULL(literal_bindings);

  List star_bindings = empty.match(%(*rest));
  if (!EXPECT_NOT_NULL(star_bindings)) return;
  Var rest = star_bindings.assoc(<"*rest">);
  EXPECT_TRUE(rest is <list>);
  EXPECT_NULL(rest.list());

  List type_bindings = empty.match(%(!is type list));
  EXPECT_NOT_NULL(type_bindings);

  List atom_bindings = empty.match(<?value>);
  if (!EXPECT_NOT_NULL(atom_bindings)) return;
  Var value = atom_bindings.assoc(<?value>);
  EXPECT_TRUE(value is <list>);
  EXPECT_NULL(value.list());

  EXPECT_NULL(empty.match(%(value)));
  EXPECT_NOT_NULL(empty.match_replace(%(*rest), %(hit)));
}

static void search_observes_explicit_empty_list(void) {
  List empty = NULL;

  List top_matches = empty.search(%());
  if (!EXPECT_NOT_NULL(top_matches)) return;
  EXPECT_INT_EQ(top_matches.len(), 1);

  List input = %($empty atom), matches = input.search(%());
  if (!EXPECT_NOT_NULL(matches)) return;
  EXPECT_INT_EQ(matches.len(), 1);
  List metadata = matches.car();
  Var matched = metadata.assoc(<*>);
  EXPECT_TRUE(matched is <list>);
  EXPECT_NULL(matched.list());

  List replaced = input.search_replace(%(), %(empty));
  EXPECT_TRUE(replaced == %((empty) atom));
}

static void match_replace_template(void) {
  Symbol name_sym = <x>;
  Var ten = 10;
  List input = %( define $name_sym $ten ), pattern = %( define ?name ?value );
  Symbol set_sym = <"set!">;
  List template = %( $set_sym ?name ?value );
  List replaced = input.match_replace(pattern, template);
  List expected = %( $set_sym $name_sym $ten );
  EXPECT_TRUE(replaced == expected);
}

static void replace_handles_mixed_types(void) {
  List payload = %(a list with a "string");
  List template = %( invoice ?id $payload ?amount *extras );
  List extras = %( tax 0.07 $payload );
  Var amount = (double) 3.75;
  List bindings = %(());;
  bindings = cons(%(?id 42), bindings);
  if (!EXPECT_NOT_NULL(bindings)) return;
  bindings = cons(%(?amount $amount), bindings);
  if (!EXPECT_NOT_NULL(bindings)) return;
  bindings = cons(%(*extras $extras), bindings);
  if (!EXPECT_NOT_NULL(bindings)) return;
  List replaced = template.replace(bindings);
  List expected = %( invoice 42 $payload $amount tax 0.07 $payload );
  if (!EXPECT_TRUE(replaced == expected)) {
    Stdout.printf("replace_handles_mixed_types mismatch\n");
    Stdout.printf("replaced structure\n");
    debug_list_dump(replaced, 0);
    Stdout.printf("expected structure\n");
    debug_list_dump(expected, 0);
    return;
  }
}

static void match_replace_returns_tail_binding(void) {
  List payload = %(a list with a "string");
  List input = %( chunk 10 2.5 $payload 5 );
  List pattern = %( chunk ?first ?mid *tail );
  Var tail_template = <"*tail">;
  List replaced = input.match_replace(pattern, tail_template);
  List expected = %( $payload 5 );
  if (!EXPECT_TRUE(replaced == expected)) {
    Stdout.printf("match_replace_returns_tail_binding mismatch\n");
    Stdout.printf("replaced structure\n");
    debug_list_dump(replaced, 0);
    Stdout.printf("expected structure\n");
    debug_list_dump(expected, 0);
    return;
  }
}

static void match_replace_preserves_input_when_no_match(void) {
  List payload = %(a list with a "string");
  List input = %( sum 1 2.0 $payload );
  List pattern = %( product ?lhs ?rhs );
  List template = %( replaced ?lhs ?rhs $payload );
  List replaced = input.match_replace(pattern, template);
  EXPECT_TRUE(replaced == input);
}

static void match_binder_prefix_captures_input(void) {
  List input = %( call add 1 2 );
  List pattern = %( !and ?expr (call add ?lhs ?rhs) );
  List bindings = input.match(pattern);
  if (!EXPECT_NOT_NULL(bindings)) return;
  Var expr = bindings.assoc(<?expr>);
  if (!EXPECT_FALSE(expr is void)) return;
  if (!EXPECT_TRUE(expr is <list>)) return;
  EXPECT_TRUE(expr.list() == input);
  EXPECT_INT_EQ(bindings.assoc(<?lhs>).integer(), 1);
  EXPECT_INT_EQ(bindings.assoc(<?rhs>).integer(), 2);
}

static void match_replace_binder_prefix_reuses_capture(void) {
  List input = %( ok 42 );
  List pattern = %( !or ?node (ok ?value) (error ?msg) );
  List template = %( captured ?node );
  List replaced = input.match_replace(pattern, template);
  List expected = %( captured (ok 42) );
  EXPECT_TRUE(replaced == expected);
}

static void match_normalization_respects_pattern_boundaries(void) {
  List quoted = %(!and ?capture red);
  List quote_pattern = %(!quote (!and ?capture red));
  List quote_bindings = quoted.match(quote_pattern);
  if (!EXPECT_NOT_NULL(quote_bindings)) return;
  EXPECT_TRUE(quote_bindings.assoc(<?capture>) is void);

  List input = %(ok 7);
  List set_pattern = %(!set ?whole (ok ?value));
  List set_bindings = input.match(set_pattern);
  if (!EXPECT_NOT_NULL(set_bindings)) return;
  EXPECT_TRUE(set_bindings.assoc(<?whole>).list() == input);
  EXPECT_INT_EQ(set_bindings.assoc(<?value>).integer(), 7);

  List nested_pattern = %(!and ?outer (!or ?inner (ok ?number)));
  List nested_bindings = input.match(nested_pattern);
  if (!EXPECT_NOT_NULL(nested_bindings)) return;
  EXPECT_TRUE(nested_bindings.assoc(<?outer>).list() == input);
  EXPECT_TRUE(nested_bindings.assoc(<?inner>).list() == input);
  EXPECT_INT_EQ(nested_bindings.assoc(<?number>).integer(), 7);
}

static void match_star_uses_leftmost_successful_split(void) {
  List input = %(a marker x marker y z);
  List pattern = %(*prefix marker ?value z);
  List bindings = input.match(pattern);
  if (!EXPECT_NOT_NULL(bindings)) return;
  EXPECT_TRUE(bindings.assoc(<"*prefix">).list() == %(a marker x));
  EXPECT_TRUE(bindings.assoc(<?value>) == <y>);

  List zero = %(marker z), zero_bindings = zero.match(%(*prefix marker z));
  if (!EXPECT_NOT_NULL(zero_bindings)) return;
  EXPECT_TRUE(zero_bindings.assoc(<"*prefix">) is <list>);
  EXPECT_NULL(zero_bindings.assoc(<"*prefix">).list());
}

static void match_star_handles_repeated_and_multiple_segments(void) {
  List repeated = %(a pivot a);
  List repeated_bindings = repeated.match(%(*same pivot *same));
  if (!EXPECT_NOT_NULL(repeated_bindings)) return;
  EXPECT_TRUE(repeated_bindings.assoc(<"*same">).list() == %(a));
  EXPECT_NULL(%(a pivot b).match(%(*same pivot *same)));

  List multiple = %(a b c);
  List multiple_bindings = multiple.match(%(*left ?middle *right));
  if (!EXPECT_NOT_NULL(multiple_bindings)) return;
  EXPECT_NULL(multiple_bindings.assoc(<"*left">).list());
  EXPECT_TRUE(multiple_bindings.assoc(<?middle>) == <a>);
  EXPECT_TRUE(multiple_bindings.assoc(<"*right">).list() == %(b c));

  EXPECT_NOT_NULL(%(a b (node c)).match(%(* (node ?value))));
  EXPECT_NOT_NULL(%(a b red).match(%(* (!or red blue))));
  EXPECT_NULL(%(a b green).match(%(* (!or red blue))));
}

static void match_star_long_anchor_miss_is_loop_safe(void) {
  List input = NULL;
  for (int i = 4999; i >= 0; i--) input = cons(i, input);
  EXPECT_NULL(input.match(%(*items ?last absent)));
}

static void try_match_separates_status_from_bindings(void) {
  List empty = NULL, bindings = %(unchanged);
  EXPECT_TRUE(empty.try_match(empty, &bindings));
  EXPECT_NULL(bindings);

  List unchanged = %(unchanged);
  bindings = unchanged;
  EXPECT_FALSE(%(value).try_match(%(other), &bindings));
  EXPECT_TRUE(bindings == unchanged);
  EXPECT_FALSE(%(value).try_match(%(value), NULL));

  EXPECT_TRUE(empty.try_match(<?value>, &bindings));
  Var value = bindings.assoc(<?value>);
  EXPECT_TRUE(value is <list>);
  EXPECT_NULL(value.list());
}

static void try_search_returns_first_depth_first_match(void) {
  List input = %((item 1) (wrapper (item 2)) (item 3));
  Var matched = <unchanged>;
  List bindings = %(unchanged);
  EXPECT_TRUE(input.try_search(%(item ?id), &matched, &bindings));
  EXPECT_TRUE(matched is <list>);
  EXPECT_TRUE(matched.list() == %(item 1));
  EXPECT_INT_EQ(bindings.assoc(<?id>).integer(), 1);

  Var old_match = <unchanged>;
  List old_bindings = %(unchanged);
  matched = old_match;
  bindings = old_bindings;
  EXPECT_FALSE(input.try_search(%(missing), &matched, &bindings));
  EXPECT_TRUE(matched == old_match);
  EXPECT_TRUE(bindings == old_bindings);
  EXPECT_FALSE(input.try_search(%(item ?id), NULL, &bindings));
  EXPECT_FALSE(input.try_search(%(item ?id), &matched, NULL));
}

static void try_match_replace_preserves_var_results(void) {
  List input = %(tag value), pattern = %(tag ?payload);
  Var result = <unchanged>;

  EXPECT_TRUE(input.try_match_replace(pattern, <?payload>, &result));
  EXPECT_TRUE(result == <value>);

  EXPECT_TRUE(input.try_match_replace(pattern, %(wrapped ?payload), &result));
  EXPECT_TRUE(result is <list>);
  EXPECT_TRUE(result.list() == %(wrapped value));

  List empty = NULL;
  EXPECT_TRUE(input.try_match_replace(pattern, empty, &result));
  EXPECT_TRUE(result is <list>);
  EXPECT_NULL(result.list());

  result = <unchanged>;
  EXPECT_FALSE(input.try_match_replace(%(missing), <changed>, &result));
  EXPECT_TRUE(result == <unchanged>);
  EXPECT_FALSE(input.try_match_replace(pattern, <changed>, NULL));

  EXPECT_NULL(input.match_replace(pattern, <?payload>));
}

static void search_collects_binding_metadata(void) {
  List payload = %(a list with a "string");
  List input = %( root (item 1 $payload) (item 2 3.25) (wrapper (item 1 $payload)) );
  List pattern = %( item ?id ?value );
  List matches = input.search(pattern);
  if (!EXPECT_NOT_NULL(matches)) return;
  EXPECT_INT_EQ(matches.len(), 3);
  int saw_string = 0, saw_float = 0;
  foreach (List binding, matches) {
    if (!EXPECT_NOT_NULL(binding)) return;
    Var id = binding.assoc(<?id>), value = binding.assoc(<?value>);
    if (!EXPECT_FALSE(id is void)) return;
    if (!EXPECT_FALSE(value is void)) return;
    if (id.integer() == 1 && value is <list> && value.list() == payload)
      saw_string = 1;
    if (id.integer() == 2 && value.is_floating() && value.double() == 3.25)
      saw_float = 1;
  }
  EXPECT_TRUE(saw_string);
  EXPECT_TRUE(saw_float);
}

static void search_binder_prefix_filters_results(void) {
  List input = %( keep deprecated other );
  List pattern = %( !not ?node deprecated );
  List matches = input.search(pattern);
  if (!EXPECT_NOT_NULL(matches)) return;
  int saw_keep = 0, saw_other = 0, saw_bad = 0;
  foreach (List binding, matches) {
    if (!EXPECT_NOT_NULL(binding)) return;
    Var node = binding.assoc(<?node>);
    EXPECT_FALSE(node is void);
    if (node is not <symbol>) continue;
    if (node == <keep>) {
      saw_keep = 1;
    } else if (node == <other>) {
      saw_other = 1;
    } else if (node == <deprecated>) {
      saw_bad = 1;
    }
  }
  EXPECT_TRUE(saw_keep);
  EXPECT_TRUE(saw_other);
  EXPECT_FALSE(saw_bad);
}

static void search_replace_substitutes_every_match(void) {
  List payload = %(a list with a "string");
  List input = %( root (item 1 2) (item 2 5.5) (wrapper (item 3 $payload)) );
  List pattern = %( item ?id ?value );
  List template = %( replaced ?id ?value $payload );
  List replaced = input.search_replace(pattern, template);
  List expected = %( root (replaced 1 2 $payload) (replaced 2 5.5 $payload)
                     (wrapper (replaced 3 $payload $payload)) );
  EXPECT_TRUE(replaced == expected);
}

static void search_replace_binder_prefix_handles_is(void) {
  List input = %( ?foo value ?bar );
  List pattern = %( !is ?binder binder );
  List template = %( binding ?binder );
  List replaced = input.search_replace(pattern, template);
  List expected = %( (binding ?foo) value (binding ?bar) );
  if (!EXPECT_TRUE(replaced == expected)) {
    Stdout.printf("search_replace_binder_prefix_handles_is mismatch\n");
    Stdout.printf("replaced structure\n");
    debug_list_dump(replaced, 0);
    Stdout.printf("expected structure\n");
    debug_list_dump(expected, 0);
    return;
  }
}

static void match_is_type_accepts_var_tags(void) {
  String string_value = %"hello";
  Var integer_var = 42, float_var = (double) 3.14159;
  List list_value = %(alpha beta);
  Array array_value = %[1, 2];
  Map map_value = %{ foo: 1 };
  Var symbol_var = <bar>;

  List samples = %( $string_value $integer_var $float_var $list_value
                    $array_value $map_value $symbol_var );
  List cases = %( ($string_value string)
                  ($integer_var i32)
                  ($float_var f64)
                  ($list_value list)
                  ($array_value array)
                  ($map_value map)
                  ($symbol_var symbol) );

  foreach (List entry, cases) {
    (Var sample, Symbol tag) = entry;

    List input = %( before $sample after );
    List guard_pattern = %( ?pre (!is type $tag) ?post );
    EXPECT_NOT_NULL(input.match(guard_pattern));

    List binder_pattern = %( ?pre (!is ?capture type $tag) ?post );
    List bindings = input.match(binder_pattern);
    if (!EXPECT_NOT_NULL(bindings)) return;
    Var capture = bindings.assoc(<?capture>);
    EXPECT_FALSE(capture is void);
    EXPECT_TRUE(capture == sample);

    List search_pattern = %( !is ?hit type $tag );
    List matches = samples.search(search_pattern);
    if (!EXPECT_NOT_NULL(matches)) return;
    int found = 0;
    foreach (List binding, matches) {
      Var hit = binding.assoc(<?hit>);
      if (hit is not void && hit == sample) {
        found = 1;
        break;
      }
    }
    EXPECT_TRUE(found);

    if (tag != <string>) {
      List mismatch_pattern = %( ?pre (!is type string) ?post );
      EXPECT_NULL(input.match(mismatch_pattern));
    }
  }
}

static void match_long_atom_binders_across_consumers(void) {
  List input = %(item 42 tail);
  Var pattern = %(item ?VeryLongIdentifierValue *RemainingLongValues);
  List bindings = input.match(pattern);
  if (!EXPECT_NOT_NULL(bindings)) return;
  EXPECT_INT_EQ(bindings.assoc(
    Atom.intern(%"?VeryLongIdentifierValue")).integer(), 42);
  EXPECT_TRUE(bindings.assoc(
    Atom.intern(%"*RemainingLongValues")).list() == %(tail));

  List oracle = %(sentinel);
  EXPECT_TRUE(test_match_oracle_try_match(input, pattern, &oracle));
  EXPECT_TRUE(oracle == bindings);

  List corpus = %(before (item 7 tail) after);
  Var found = void;
  List found_bindings = %(sentinel);
  EXPECT_TRUE(corpus.try_search(pattern, &found, &found_bindings));
  EXPECT_TRUE(found.list() == %(item 7 tail));
  EXPECT_INT_EQ(found_bindings.assoc(
    Atom.intern(%"?VeryLongIdentifierValue")).integer(), 7);

  Var template = %(
    captured ?VeryLongIdentifierValue *RemainingLongValues
  );
  List replaced = corpus.search_replace(pattern, template);
  EXPECT_TRUE(replaced == %(before (captured 7 tail) after));

  List repeated = %(same same).match(
    %(?RepeatedLongIdentifier ?RepeatedLongIdentifier)
  );
  EXPECT_NOT_NULL(repeated);
  EXPECT_TRUE(%(same other).match(
    %(?RepeatedLongIdentifier ?RepeatedLongIdentifier)
  ) == NULL);
}


static void match_rejects_malformed_binder_names(void) {
  List input = %(node value);
  Var malformed = %(node ?bad-name);
  List untouched = %(sentinel);
  EXPECT_FALSE(test_match_oracle_try_match(input, malformed, &untouched));
  EXPECT_TRUE(untouched == %(sentinel));
  EXPECT_NULL(input.match(malformed));

  Var replacement = <sentinel>;
  EXPECT_FALSE(input.try_match_replace(
    malformed, %(changed), &replacement
  ));
  EXPECT_TRUE(replacement == <sentinel>);
  EXPECT_TRUE(input.match_replace(malformed, %(changed)) == input);
  EXPECT_NULL(input.search(malformed));

  Var found = <sentinel>;
  List found_bindings = %(sentinel);
  EXPECT_FALSE(input.try_search(malformed, &found, &found_bindings));
  EXPECT_TRUE(found == <sentinel>);
  EXPECT_TRUE(found_bindings == %(sentinel));
  EXPECT_TRUE(input.search_replace(malformed, %(changed)) == input);

  MatchPlan plan = MatchPlan.prepare(malformed);
  EXPECT_INT_EQ(plan.status, MACHINE_MALFORMED);
  EXPECT_STR_EQ(String.new(plan.reason), "binder-name");
  MatchPlan.free(plan);

  plan = MatchPlan.prepare(%(node *9bad));
  EXPECT_INT_EQ(plan.status, MACHINE_MALFORMED);
  EXPECT_STR_EQ(String.new(plan.reason), "binder-name");
  MatchPlan.free(plan);

  plan = MatchPlan.prepare(%(!quote ?bad-name));
  EXPECT_INT_EQ(plan.status, MACHINE_PREPARED);
  MatchPlan.free(plan);

  plan = MatchPlan.prepare(%(!is (?v) ?binder?));
  EXPECT_TRUE(plan.status != MACHINE_MALFORMED);
  MatchPlan.free(plan);
}


$(import "test-macros.xmacro")

void match_suite(void) {
  $test.run(match_binds_variables);
  $test.run(match_star_binder_splices);
  $test.run(match_typed_empty_list);
  $test.run(search_observes_explicit_empty_list);
  $test.run(match_replace_template);
  $test.run(replace_handles_mixed_types);
  $test.run(match_replace_returns_tail_binding);
  $test.run(match_replace_preserves_input_when_no_match);
  $test.run(match_binder_prefix_captures_input);
  $test.run(match_replace_binder_prefix_reuses_capture);
  $test.run(match_normalization_respects_pattern_boundaries);
  $test.run(match_star_uses_leftmost_successful_split);
  $test.run(match_star_handles_repeated_and_multiple_segments);
  $test.run(match_star_long_anchor_miss_is_loop_safe);
  $test.run(try_match_separates_status_from_bindings);
  $test.run(try_search_returns_first_depth_first_match);
  $test.run(try_match_replace_preserves_var_results);
  $test.run(search_collects_binding_metadata);
  $test.run(search_binder_prefix_filters_results);
  $test.run(search_replace_substitutes_every_match);
  $test.run(search_replace_binder_prefix_handles_is);
  $test.run(match_is_type_accepts_var_tags);
  $test.run(match_long_atom_binders_across_consumers);
  $test.run(match_rejects_malformed_binder_names);
}
