/*  test-regexp.x -- Focused tests for the idiomatic PCRE2 slice. */

import "pcre2" with Regexp, RegexpCapture, RegexpLisp, RegexpMatch;

#include "test-support.x"
#include <string.h>

$(import "../../../unittest/test-macros.xmacro")

static void regexp_named_and_optional_captures(void) {
  Regexp words = Regexp.compile(%"^(?<word>[a-z]+)(?<digits>[0-9]+)?$$", 0);
  defer words.free();

  RegexpMatch found = words.match(%"alpha");
  EXPECT_NOT_NULL(found);
  EXPECT_STR_EQ(found[0], %"alpha");
  EXPECT_STR_EQ(found[<word>], %"alpha");
  EXPECT_STR_EQ(found[1], %"alpha");

  RegexpCapture optional = found.capture(<digits>);
  EXPECT_NOT_NULL(optional);
  EXPECT_FALSE(optional.matched());
  EXPECT_STR_EQ(optional.name(), %"digits");
  EXPECT_NULL(found[<digits>]);
  EXPECT_NULL(found.capture(<missing>));

  Regexp empty_group = Regexp.compile(%"^(a*)b$$", 0);
  defer empty_group.free();
  RegexpCapture empty = empty_group.match(%"b").capture(1);
  EXPECT_TRUE(empty.matched());
  EXPECT_NULL(empty.text());
  EXPECT_INT_EQ(empty.start(), empty.end());

  int captures = 0;
  foreach(RegexpCapture capture, found) captures++;
  EXPECT_INT_EQ(captures, 3);
}

static void regexp_no_match_is_not_an_error(void) {
  Regexp digits = Regexp.compile(%"^[0-9]+$$", 0);

  int before = Error.count();
  EXPECT_NULL(digits.match(%"letters"));
  EXPECT_INT_EQ(Error.count(), before);
  EXPECT_NULL(digits.free());
  EXPECT_NULL(digits.free());
}

static void regexp_global_empty_match_progress(void) {
  Regexp before_a = Regexp.compile(%"(?=a)", 0);
  defer before_a.free();

  List found = before_a.find_all(%"aa");
  EXPECT_INT_EQ(found.len(), 2);
  RegexpMatch first = found.getindex(0).regexpmatch();
  RegexpMatch second = found.getindex(1).regexpmatch();
  EXPECT_TRUE(first.capture(0).matched());
  EXPECT_TRUE(second.capture(0).matched());
  EXPECT_INT_EQ(first.capture(0).start(), 0);
  EXPECT_INT_EQ(second.capture(0).start(), 1);

  Regexp optional = Regexp.compile(%"a*", 0);
  defer optional.free();
  EXPECT_INT_EQ(optional.find_all_from(%"aa", 0, PCRE2_NOTEMPTY).len(), 1);
}

static void regexp_utf_and_replacement_growth(void) {
  Regexp letters = Regexp.compile(%"^\\p{L}+$$", PCRE2_UTF | PCRE2_UCP);
  defer letters.free();
  String cafe = %"caf\xc3\xa9";
  EXPECT_STR_EQ(letters.match(cafe)[0], cafe);

  Regexp x = Regexp.compile(%"x", 0);
  defer x.free();
  EXPECT_STR_EQ(x.replace(%"xxx", %"longer"), %"longerxx");
  EXPECT_STR_EQ(x.replace_all(%"xxx", %"longer"), %"longerlongerlonger");
}

static void regexp_offsets_limits_and_jit(void) {
  Regexp word = Regexp.compile(
    %"[a-z]+", PCRE2_UTF | PCRE2_UCP | PCRE2_USE_OFFSET_LIMIT
  );
  defer word.free();

  EXPECT_STR_EQ(word.pattern(), %"[a-z]+");
  EXPECT_INT_EQ(word.capture_count(), 0);
  word.set_offset_limit(2);
  EXPECT_NULL(word.match_from(%"xxxword", 3, 0));
  word.set_offset_limit(64);
  EXPECT_STR_EQ(word.match_from(%"one two", 4, 0)[0], %"two");
  EXPECT_INT_EQ(word.find_all_from(%"one two three", 4, 0).len(), 2);

  int jit = 0;
  EXPECT_TRUE(pcre2_config(PCRE2_CONFIG_JIT, &jit) >= 0);
  EXPECT_TRUE(jit);
  EXPECT_NOT_NULL(word.jit_compile(PCRE2_JIT_COMPLETE));
  EXPECT_TRUE(word.jit_size() > 0);
}

static void _expect_limit(Regexp regexp, int code) {
  int caught = 0;
  try regexp.match(%"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa!");
  catch %(bad-state *detail): {
    caught = 1;
    EXPECT_INT_EQ(detail.assoc(<code>).integer(), code);
  }
  EXPECT_TRUE(caught);
}

static void regexp_match_limits_bind(void) {
  Regexp nested = Regexp.compile(%"(a+)+$$", 0);
  defer nested.free();

  nested.set_match_limit(0);
  _expect_limit(nested, PCRE2_ERROR_MATCHLIMIT);
  nested.set_match_limit(UINT32_MAX);

  nested.set_depth_limit(0);
  _expect_limit(nested, PCRE2_ERROR_DEPTHLIMIT);
  nested.set_depth_limit(UINT32_MAX);

  nested.set_heap_limit(0);
  _expect_limit(nested, PCRE2_ERROR_HEAPLIMIT);
}

static void regexp_compile_context_and_native_state_are_reachable(void) {
  pcre2_compile_context *context = pcre2_compile_context_create(NULL);
  EXPECT_NOT_NULL(context);
  defer pcre2_compile_context_free(context);
  EXPECT_INT_EQ(
    pcre2_set_compile_extra_options(
      context, PCRE2_EXTRA_ALLOW_LOOKAROUND_BSK
    ),
    0
  );

  Regexp regexp = Regexp.compile_context(%"(?=ab\\K)", 0, context);
  defer regexp.free();
  EXPECT_NOT_NULL(regexp.native());
  EXPECT_NOT_NULL(regexp.native_match_data());
  EXPECT_NOT_NULL(regexp.native_match_context());

  uint32_t captures = 99;
  EXPECT_INT_EQ(
    pcre2_pattern_info(
      regexp.native(), PCRE2_INFO_CAPTURECOUNT, &captures
    ),
    0
  );
  EXPECT_INT_EQ(captures, 0);
}

static void regexp_accessors_reject_a_freed_value(void) {
  Regexp regexp = Regexp.compile(%"a", 0);
  regexp.free();

  int caught = 0;
  try regexp.pattern();
  catch %(bad-state *detail): {
    caught = 1;
    EXPECT_STR_EQ(detail.assoc(<operation>).string(), %"pattern");
  }
  EXPECT_TRUE(caught);

  caught = 0;
  try regexp.native();
  catch %(bad-state *detail): {
    caught = 1;
    EXPECT_STR_EQ(detail.assoc(<operation>).string(), %"native");
  }
  EXPECT_TRUE(caught);
}

static void regexp_retains_transient_pattern(void) {
  String transient = String.malloc(3);
  strcpy(transient, "a+");
  Regexp repeated = Regexp.compile(transient, 0);
  defer repeated.free();
  transient.free();

  EXPECT_STR_EQ(repeated.pattern(), %"a+");
  EXPECT_STR_EQ(repeated.match(%"aaa")[0], %"aaa");
}

static void regexp_duplicate_names_choose_participating_capture(void) {
  Regexp choice = Regexp.compile(%"(?J)^(?:(?<value>a)|(?<value>b))$$", 0);
  defer choice.free();

  RegexpMatch found = choice.match(%"b");
  EXPECT_STR_EQ(found[<value>], %"b");
  List duplicates = found.captures(<value>);
  EXPECT_INT_EQ(duplicates.len(), 2);
  EXPECT_FALSE(duplicates.getindex(0).regexpcapture().matched());
  EXPECT_TRUE(duplicates.getindex(1).regexpcapture().matched());
}

static void regexp_compile_error_has_pcre2_detail(void) {
  int caught = 0;
  try {
    Regexp invalid = Regexp.compile(%"(", 0);
    if (invalid) invalid.free();
  }
  catch %(malformed *detail): {
    caught = 1;
    EXPECT_STR_EQ(detail.assoc(<library>).string(), %"PCRE2");
    EXPECT_STR_EQ(detail.assoc(<operation>).string(), %"compile");
    EXPECT_TRUE(detail.assoc(<code>).integer() != 0);
    EXPECT_TRUE(detail.assoc(<message>).string().len() > 0);
    EXPECT_INT_EQ(detail.assoc(<offset>).integer(), 1);
  }
  EXPECT_TRUE(caught);
}

static void regexp_split_keeps_empty_fields(void) {
  Regexp comma = Regexp.compile(%",", 0);
  defer comma.free();

  List fields = comma.split(%"alpha,,beta");
  EXPECT_INT_EQ(fields.len(), 3);
  EXPECT_STR_EQ(fields.car().string(), %"alpha");
  EXPECT_INT_EQ(String.len(fields.cadr()), 0);
  EXPECT_STR_EQ(fields.cddr().car().string(), %"beta");

  /*  A match against the first and last byte leaves an empty field at each
      end, and a pattern that never matches yields the whole subject.
  */
  List edges = comma.split(%",solo,");
  EXPECT_INT_EQ(edges.len(), 3);
  EXPECT_INT_EQ(String.len(edges.car()), 0);
  EXPECT_STR_EQ(edges.cadr().string(), %"solo");
  EXPECT_INT_EQ(String.len(edges.cddr().car()), 0);

  List whole = comma.split(%"no separator here");
  EXPECT_INT_EQ(whole.len(), 1);
  EXPECT_STR_EQ(whole.car().string(), %"no separator here");
}

static void regexp_split_handles_empty_matches(void) {
  Regexp before_a = Regexp.compile(%"(?=a)", 0);
  defer before_a.free();

  /*  A zero-length match must advance rather than split forever. */
  List parts = before_a.split(%"aa");
  EXPECT_INT_EQ(parts.len(), 3);
  EXPECT_INT_EQ(String.len(parts.car()), 0);
  EXPECT_STR_EQ(parts.cadr().string(), %"a");
  EXPECT_STR_EQ(parts.cddr().car().string(), %"a");
}

static String _upper_word(RegexpMatch found) {
  return found[0].upper();
}

static String _name_of_capture(RegexpMatch found) {
  return found[<who>];
}

static String _drop_match(RegexpMatch found) {
  return NULL;
}

static String _literal_backreference(RegexpMatch found) {
  return "$1";
}

static void regexp_replace_fn_computes_each_replacement(void) {
  Regexp word = Regexp.compile(%"[a-z]+", 0);
  defer word.free();
  EXPECT_STR_EQ(
    word.replace_fn(%"one two three", _upper_word), %"ONE TWO THREE"
  );

  /*  The callback sees captures, and an empty result deletes the match. */
  Regexp greeting = Regexp.compile(%"hi (?<who>[a-z]+)", 0);
  defer greeting.free();
  EXPECT_STR_EQ(
    greeting.replace_fn(%"hi ada and hi bob", _name_of_capture),
    %"ada and bob"
  );
  EXPECT_STR_EQ(word.replace_fn(%"a-b-c", _drop_match), %"--");

  /*  Plain C string literals carry PCRE2's `$` syntax without invoking x2c
      interpolation. replace_all expands it; replace_fn leaves it alone. */
  Regexp pair = Regexp.compile(%"([a-z]+)-([0-9]+)", 0);
  defer pair.free();
  EXPECT_STR_EQ(pair.replace_all(%"part-17", "$2:$1"), %"17:part");
  EXPECT_STR_EQ(word.replace_fn(%"x", _literal_backreference), "$1");
  EXPECT_INT_EQ(String.len(word.replace_fn(%"", _upper_word)), 0);
}

static void regexp_escape_quotes_metacharacters(void) {
  EXPECT_STR_EQ(Regexp.escape(%"a.b*c"), %"a\\.b\\*c");
  EXPECT_STR_EQ(Regexp.escape(%"plain_text99"), %"plain_text99");
  EXPECT_NULL(Regexp.escape(NULL));

  /*  The quoted literal must match itself and nothing else. */
  Regexp literal = Regexp.compile(Regexp.escape(%"1+1 (really?)"), 0);
  defer literal.free();
  EXPECT_NOT_NULL(literal.match(%"the sum 1+1 (really?) holds"));
  EXPECT_NULL(literal.match(%"1x1 (really!)"));

  /*  Bytes above ASCII pass through, so a UTF-8 literal stays valid. */
  Regexp accented = Regexp.compile(Regexp.escape(%"caf\xc3\xa9."), PCRE2_UTF);
  defer accented.free();
  EXPECT_NOT_NULL(accented.match(%"caf\xc3\xa9."));
  EXPECT_NULL(accented.match(%"caf\xc3\xa9x"));
}

static void regexp_capture_names_lists_declared_groups(void) {
  Regexp request = Regexp.compile(
    %"(?<method>[A-Z]+) (?<path>[^ ]+) ([0-9]+)", 0
  );
  defer request.free();

  List names = request.capture_names();
  EXPECT_INT_EQ(names.len(), 2);
  EXPECT_STR_EQ(names.car().string(), %"method");
  EXPECT_STR_EQ(names.cadr().string(), %"path");

  /*  An unnamed pattern declares nothing. */
  Regexp unnamed = Regexp.compile(%"([0-9]+)-([0-9]+)", 0);
  defer unnamed.free();
  EXPECT_NULL(unnamed.capture_names());

  /*  Under (?J) one name covers several groups and is listed per group. */
  Regexp duplicated = Regexp.compile(
    %"(?J)(?:(?<slot>[a-z]+)|(?<slot>[0-9]+))", 0
  );
  defer duplicated.free();
  EXPECT_INT_EQ(duplicated.capture_names().len(), 2);
}

static void regexp_lisp_surface_is_value_oriented(void) {
  Lisp lisp = Lisp.new();
  defer lisp.destroy();
  RegexpLisp.install(lisp);

  String text = %"Order 41 ships with 3 labels";
  EXPECT_INT_EQ(lisp.eval(%(length (regex-find-all "[0-9]+" $text))).int(), 2);
  EXPECT_STR_EQ(
    lisp.eval(%(regex-replace "[0-9]+" $text "#")).string(),
    %"Order # ships with # labels"
  );
  EXPECT_INT_EQ(lisp.eval(%(length (regex-split ", " "a, b, c"))).int(), 3);
  EXPECT_STR_EQ(lisp.eval(%(regex-escape "a.b")).string(), %"a\\.b");

  /*  Captures arrive as an ordinary Lisp list, and no match is the empty
      list rather than an error.
  */
  List captured = lisp.eval(%(regex-match "(\\w+)@(\\w+)" "me@here"));
  EXPECT_INT_EQ(captured.len(), 3);
  EXPECT_STR_EQ(captured.cadr().string(), %"me");
  EXPECT_NULL(lisp.eval(%(regex-match "[0-9]+" "letters")).list());
}

static void regexp_lisp_binding_raises_pcre2_detail(void) {
  Lisp lisp = Lisp.new();
  defer lisp.destroy();
  RegexpLisp.install(lisp);

  /*  A bad pattern inside a binding reaches the x2c caller unchanged. */
  int caught = 0;
  try lisp.eval(%(regex-match "(" "anything"));
  catch %(malformed *detail): {
    caught = 1;
    EXPECT_STR_EQ(detail.assoc(<library>).string(), %"PCRE2");
    EXPECT_STR_EQ(detail.assoc(<operation>).string(), %"compile");
  }
  EXPECT_TRUE(caught);
}

void regexp_suite(void) {
  $test.run(regexp_named_and_optional_captures);
  $test.run(regexp_no_match_is_not_an_error);
  $test.run(regexp_global_empty_match_progress);
  $test.run(regexp_utf_and_replacement_growth);
  $test.run(regexp_offsets_limits_and_jit);
  $test.run(regexp_match_limits_bind);
  $test.run(regexp_compile_context_and_native_state_are_reachable);
  $test.run(regexp_accessors_reject_a_freed_value);
  $test.run(regexp_retains_transient_pattern);
  $test.run(regexp_duplicate_names_choose_participating_capture);
  $test.run(regexp_compile_error_has_pcre2_detail);
  $test.run(regexp_split_keeps_empty_fields);
  $test.run(regexp_split_handles_empty_matches);
  $test.run(regexp_replace_fn_computes_each_replacement);
  $test.run(regexp_escape_quotes_metacharacters);
  $test.run(regexp_capture_names_lists_declared_groups);
  $test.run(regexp_lisp_surface_is_value_oriented);
  $test.run(regexp_lisp_binding_raises_pcre2_detail);
}

int main(void) {
  TestHarness_begin();
  $test.suite(regexp_suite);
  return TestHarness_finish();
}
