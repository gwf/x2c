/*  test-diff.x -- unit tests for line differences */

#include "diff.x"
#include "test-support.x"
$(import "test-macros.xmacro")

static String script(List edits) {
  Buffer out = Buffer.new(0);
  foreach (List edit, edits) {
    Symbol kind = edit.car();
    String line = edit.cadr();
    out.printf("%c%s\n", kind == <same> ? ' ' : kind == <delete> ? '-' : '+',
               line ? line : "");
  }
  return out;
}

static void diff_lines_finds_a_shortest_script(void) {
  $test.scoped();
  EXPECT_STR_EQ(script(Diff.lines("a\nb\nc\n", "a\nb\nc\n")), " a\n b\n c\n");
  EXPECT_STR_EQ(script(Diff.lines("a\nb\nc\n", "a\nc\n")), " a\n-b\n c\n");
  EXPECT_STR_EQ(script(Diff.lines("a\nc\n", "a\nb\nc\n")), " a\n+b\n c\n");
  EXPECT_STR_EQ(script(Diff.lines("a\nb\nc\na\nb\nb\na\n",
                                  "c\nb\na\nb\na\nc\n")),
                "-a\n-b\n c\n+b\n a\n b\n-b\n a\n+c\n");
  EXPECT_STR_EQ(script(Diff.lines("x\n", "y\n")), "-x\n+y\n");
  EXPECT_STR_EQ(script(Diff.lines(NULL, "one\ntwo\n")), "+one\n+two\n");
  EXPECT_STR_EQ(script(Diff.lines("one\n", NULL)), "-one\n");
  EXPECT_NULL(Diff.lines(NULL, NULL));
  EXPECT_STR_EQ(script(Diff.lines("a\n\nb", "a\n\nb\n")), " a\n \n b\n");
  EXPECT_STR_EQ(script(Diff.lines("same\n", "same")), " same\n");
}

static void diff_lines_replaces_unrelated_texts_past_the_limit(void) {
  $test.scoped();
  Buffer old = Buffer.new(0), new = Buffer.new(0);
  for (int i = 0; i < 3000; i++) {
    old.printf("old %d\n", i);
    new.printf("new %d\n", i);
  }
  List edits = Diff.lines(old, new);
  EXPECT_INT_EQ(edits.len(), 6000);
  EXPECT_TRUE(edits.car().list().car().symbol() == <delete>);
  EXPECT_TRUE(edits[2999].list().car().symbol() == <delete>);
  EXPECT_TRUE(edits[3000].list().car().symbol() == <insert>);
  EXPECT_STR_EQ(edits[5999].list().cadr().string(), "new 2999");
}

static void diff_unified_prints_hunks_with_context(void) {
  $test.scoped();
  EXPECT_NULL(Diff.unified("a\nb\n", "a\nb\n", "x", "y"));
  EXPECT_STR_EQ(Diff.unified("a\nb\nc\n", "a\nB\nc\n", "old", "new"),
                "--- old\n+++ new\n@@ -1,3 +1,3 @@\n a\n-b\n+B\n c\n");
  Buffer old = Buffer.new(0), new = Buffer.new(0);
  for (int i = 1; i <= 20; i++) {
    old.printf("%d\n", i);
    new.printf("%s\n", i == 5 ? "five" : i == 15 ? "fifteen" : %"$i");
  }
  EXPECT_STR_EQ(Diff.unified(old, new, "a", "b"),
                "--- a\n+++ b\n"
                "@@ -2,7 +2,7 @@\n 2\n 3\n 4\n-5\n+five\n 6\n 7\n 8\n"
                "@@ -12,7 +12,7 @@\n 12\n 13\n 14\n-15\n+fifteen\n"
                " 16\n 17\n 18\n");
  EXPECT_STR_EQ(Diff.unified("1\n2\n3\n4\n5\n6\n7\n8\n9\n",
                             "1\n2\n3\nX\n5\n6\nY\n8\n9\n", "a", "b"),
                "--- a\n+++ b\n@@ -1,9 +1,9 @@\n 1\n 2\n 3\n-4\n+X\n 5\n 6\n"
                "-7\n+Y\n 8\n 9\n");
  EXPECT_STR_EQ(Diff.unified(NULL, "only\n", "a", "b"),
                "--- a\n+++ b\n@@ -0,0 +1,1 @@\n+only\n");
  EXPECT_STR_EQ(Diff.unified("gone\n", NULL, "a", "b"),
                "--- a\n+++ b\n@@ -1,1 +0,0 @@\n-gone\n");
}

void diff_suite(void) {
  $test.run(diff_lines_finds_a_shortest_script);
  $test.run(diff_lines_replaces_unrelated_texts_past_the_limit);
  $test.run(diff_unified_prints_hunks_with_context);
}
