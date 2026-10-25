/*  test-substring.x -- borrowed views and native word-count maps */

#include "substring-map.x"
#include "typed-map.x"
#include "test-support.x"
#include "test-macros.x"

static void substring_ranges_and_canonical_strings(void) {
  String source = "prefix word suffix";
  Substr view = source.substring(7, 4);
  EXPECT_INT_EQ(view.len(), 4);
  EXPECT_TRUE(view.source === source);
  EXPECT_STR_EQ(view.str(), "word");
  EXPECT_PTR_EQ(view.str(), view.string());
  EXPECT_PTR_EQ(source.substring(0, source.len()).str(), source);
  EXPECT_NULL(source.substring(source.len(), 0).str());
  EXPECT_NULL(Substring.new(NULL, 0, 0).str());
  EXPECT_TRUE(view.equal("word".substring(0, 4)));
  EXPECT_INT_EQ(view.hash(), "word".hash());
  EXPECT_TRUE(view.compare("work".substring(0, 4)) < 0);
  EXPECT_TRUE(view.compare("wor".substring(0, 3)) > 0);
  int caught = 0;
  try source.substring(-1, 1);
  catch %(bad-arg *): caught++;
  try source.substring(0, -1);
  catch %(bad-arg *): caught++;
  try source.substring(source.len(), 1);
  catch %(bad-arg *): caught++;
  EXPECT_INT_EQ(caught, 3);
  EXPECT_STR_EQ(String.new_len("ab\0cd", 5), "ab");
}

static void substring_foreach_borrows_without_allocating(void) {
  String source = " \talpha  beta\ngamma\r\n";
  ScopeStats scope = Scope.stats();
  PoolStats pool = Pool.current().stats();
  int words = 0, bytes = 0;
  foreach (Substr word in source) {
    EXPECT_PTR_EQ(word.source, source);
    ++words;
    bytes += word.len();
  }
  EXPECT_INT_EQ(words, 3);
  EXPECT_INT_EQ(bytes, 14);
  int empty = 0;
  foreach (Substr word in (String) NULL) ++empty;
  EXPECT_INT_EQ(empty, 0);
  EXPECT_INT_EQ(Scope.stats().allocation_calls, scope.allocation_calls);
  EXPECT_INT_EQ(Pool.current().stats().allocation_calls, pool.allocation_calls);
}

static void substring_map_exports_sources_and_grows(void) {
  $test.scoped();
  Context work = Context.open_isolated();
  MapSubInt counts = MapSubInt.new();
  foreach (Substr word in String.new("alpha beta alpha")) counts.increment(word);
  foreach (Substr word in String.new("gamma beta")) counts.increment(word);
  MapSubInt result = work.export(counts);
  EXPECT_PTR_EQ(result, counts);
  work.close();
  EXPECT_PTR_EQ(Scope.owner(result), *Scope.top());
  Map words = result.strings();
  EXPECT_INT_EQ(words["alpha"].int(), 2);
  EXPECT_INT_EQ(words["beta"].int(), 2);
  EXPECT_INT_EQ(words["gamma"].int(), 1);
  for (int i = 0; i < 100; ++i) {
    String text = i.str();
    result.increment(text.substring(0, text.len()));
  }
  int keys = 0, total = 0;
  foreach ((Substr word, int count) in result) {
    ++keys;
    total += count;
    EXPECT_TRUE(word.len() > 0);
  }
  EXPECT_INT_EQ(keys, 103);
  EXPECT_INT_EQ(total, 105);
  result.cleanup();
  work = Context.open_isolated();
  result = work.export(MapSubInt.new());
  work.close();
  EXPECT_INT_EQ(result.used, 0);
  result.cleanup();
}

static void substring_string_map_updates_only_materialize_misses(void) {
  $test.scoped();
  MapStringInt counts = MapStringInt.new();
  String first = "__alpha__", second = "beta alpha gamma";
  EXPECT_INT_EQ(counts.add_substr(first.substring(2, 5), 2), 2);
  PoolStats pool = Pool.current().stats();
  ScopeStats scope = Scope.stats();
  EXPECT_INT_EQ(counts.add_substr(second.substring(5, 5), 3), 5);
  EXPECT_INT_EQ(Pool.current().stats().allocation_calls, pool.allocation_calls);
  EXPECT_INT_EQ(Scope.stats().allocation_calls, scope.allocation_calls);
  EXPECT_INT_EQ(counts["alpha"], 5);
  EXPECT_INT_EQ(counts.add_substr(first.substring(0, 0), 7), 7);
  EXPECT_INT_EQ(counts.add_substr(second.substring(second.len(), 0), -2), 5);
  EXPECT_INT_EQ(counts[""], 5);
  for (int i = 0; i < 100; ++i) {
    String text = %"__key$(i)__";
    Substr word = text.substring(2, text.len() - 4);
    counts.add_substr(word, i);
    counts.add_substr(word, 1);
  }
  for (int i = 0; i < 100; ++i) EXPECT_INT_EQ(counts[%"key$(i)"], i + 1);
  EXPECT_INT_EQ(counts.len(), 102);
  MapStringInt expected = MapStringInt.new();
  expected["alpha"] += INT_MAX;
  expected["alpha"] += 1;
  counts.set("alpha", INT_MAX);
  EXPECT_INT_EQ(counts.add_substr(first.substring(2, 5), 1), expected["alpha"]);
  int caught = 0;
  try ((MapStringInt) NULL).add_substr(first.substring(2, 5), 1);
  catch %(bad-arg *): caught++;
  EXPECT_INT_EQ(caught, 1);
}

void substring_suite(void) {
  $test.run(substring_ranges_and_canonical_strings);
  $test.run(substring_foreach_borrows_without_allocating);
  $test.run(substring_map_exports_sources_and_grows);
  $test.run(substring_string_map_updates_only_materialize_misses);
}
