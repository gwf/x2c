/*  test-regex.x -- unit tests for regular expressions */

#include "regex.x"
#include "test-support.x"
$(import "test-macros.xmacro")

static void regex_matches_literals_and_sets(void) {
  $test.scoped();
  Regex re = Regex.compile("c[aeiou]t");
  RegexMatch found = re.match("the cat sat");
  if (!EXPECT_NOT_NULL(found)) return;
  EXPECT_STR_EQ(found[0], "cat");
  EXPECT_INT_EQ(found.capture(0).start(), 4);
  EXPECT_INT_EQ(found.capture(0).end(), 7);
  EXPECT_NULL(re.match("the cxt? no, the cyt"));
  EXPECT_NOT_NULL(Regex.compile("[^a-z]").match("abc9"));
  EXPECT_NULL(Regex.compile("[^a-z]").match("abc"));
  EXPECT_NOT_NULL(Regex.compile("[]a]").match("]"));
  EXPECT_NOT_NULL(Regex.compile("[a-]").match("-"));
  EXPECT_STR_EQ(Regex.compile("a.c").match("abc")[0], "abc");
  EXPECT_NULL(Regex.compile("a.c").match("a\nc"));
  EXPECT_NOT_NULL(Regex.compile("(?s)a.c").match("a\nc"));
}

static void regex_classes_anchors_and_boundaries(void) {
  $test.scoped();
  EXPECT_STR_EQ(Regex.compile("\\d+").match("abc 123 x")[0], "123");
  EXPECT_STR_EQ(Regex.compile("\\w+").match("  foo_9 bar")[0], "foo_9");
  EXPECT_STR_EQ(Regex.compile("\\s+").match("a \t\nb")[0], " \t\n");
  EXPECT_STR_EQ(Regex.compile("\\D+").match("12ab34")[0], "ab");
  EXPECT_STR_EQ(Regex.compile("[\\d-]+").match("x 2026-09 y")[0], "2026-09");
  EXPECT_STR_EQ(Regex.compile("^ab").match("abab")[0], "ab");
  EXPECT_NULL(Regex.compile("^b").match("ab"));
  EXPECT_NULL(Regex.compile("a$").match("ab"));
  EXPECT_NOT_NULL(Regex.compile("b$").match("ab"));
  EXPECT_STR_EQ(Regex.compile("(?m)^\\w+$").find_all("one\ntwo")
                  .cadr().regexmatch()[0], "two");
  EXPECT_STR_EQ(Regex.compile("\\bis\\b").match("this is it")[0], "is");
  EXPECT_INT_EQ(Regex.compile("\\bis\\b").match("this is it")
                  .capture(0).start(), 5);
  EXPECT_STR_EQ(Regex.compile("\\Bis").match("this is")[0], "is");
  EXPECT_STR_EQ(Regex.compile("(?i)hello").match("say HeLLo")[0], "HeLLo");
  EXPECT_STR_EQ(Regex.compile("(?i)[a-c]+").match("xABcy")[0], "ABc");
}

static void regex_repeats_greedy_and_lazy(void) {
  $test.scoped();
  EXPECT_STR_EQ(Regex.compile("a*").match("aaab")[0], "aaa");
  RegexMatch empty = Regex.compile("a*").match("baaa");
  EXPECT_TRUE(empty.capture(0).matched());
  EXPECT_INT_EQ(empty.capture(0).end(), 0);
  EXPECT_NULL(empty[0]);
  EXPECT_STR_EQ(Regex.compile("a+?").match("aaa")[0], "a");
  EXPECT_STR_EQ(Regex.compile("<.*>").match("<a><b>")[0], "<a><b>");
  EXPECT_STR_EQ(Regex.compile("<.*?>").match("<a><b>")[0], "<a>");
  EXPECT_STR_EQ(Regex.compile("a{2}").match("aaaa")[0], "aa");
  EXPECT_STR_EQ(Regex.compile("a{2,}").match("aaaa")[0], "aaaa");
  EXPECT_STR_EQ(Regex.compile("a{1,3}").match("aaaa")[0], "aaa");
  EXPECT_STR_EQ(Regex.compile("a{1,3}?").match("aaaa")[0], "a");
  EXPECT_NULL(Regex.compile("a{3}").match("aa"));
  EXPECT_STR_EQ(Regex.compile("a{").match("a{")[0], "a{");
  EXPECT_STR_EQ(Regex.compile("x{,2}").match("x{,2}")[0], "x{,2}");
  EXPECT_STR_EQ(Regex.compile("colou?r").match("color")[0], "color");
  EXPECT_STR_EQ(Regex.compile("(ab)+").match("xababab")[0], "ababab");
  EXPECT_STR_EQ(Regex.compile("(ab)+?b").match("ababb")[0], "ababb");
  EXPECT_STR_EQ(Regex.compile("(ab)+?").match("ababab")[0], "ab");
  EXPECT_STR_EQ(Regex.compile("(a|ab)(c|bcd)(d*)").match("abcd")[0],
                "abcd");
  EXPECT_STR_EQ(Regex.compile("(a*)*b").match("aaab")[0], "aaab");
  EXPECT_NULL(Regex.compile("(a*)*b").match("aaaaaaaaaaaaaaaaaaaaaaaa"));
  String long_text = "a".repeat(200000) + "b";
  EXPECT_INT_EQ(Regex.compile("a*b").match(long_text).capture(0).end(),
                200001);
  EXPECT_INT_EQ(Regex.compile("(?:a)*b").match("a".repeat(1000) + "b")
                  .capture(0).end(), 1001);
  int limited = 0;
  try Regex.compile("(?:a)*b").match(long_text);
  catch %(size-limit *detail): {
    limited = 1;
    EXPECT_STR_EQ(detail.assoc(<pattern>).string(), "(?:a)*b");
  }
  EXPECT_INT_EQ(limited, 1);
}

static void regex_alternation_and_groups(void) {
  $test.scoped();
  Regex re = Regex.compile("(?<key>\\w+)=(\\d+)|(?<flag>-\\w)");
  EXPECT_INT_EQ(re.capture_count(), 3);
  List names = re.capture_names();
  EXPECT_STR_EQ(names[0].string(), "key");
  EXPECT_NULL(names[1].string());
  EXPECT_STR_EQ(names[2].string(), "flag");
  RegexMatch found = re.match("set width=80");
  if (!EXPECT_NOT_NULL(found)) return;
  EXPECT_STR_EQ(found[<key>], "width");
  EXPECT_STR_EQ(found["key"], "width");
  EXPECT_STR_EQ(found[2], "80");
  EXPECT_NULL(found[<flag>]);
  EXPECT_NULL(found[9]);
  EXPECT_NULL(found[<none>]);
  EXPECT_FALSE(found.capture(3).matched());
  EXPECT_INT_EQ(found.capture(3).start(), -1);
  EXPECT_STR_EQ(found.capture(1).name(), "key");
  EXPECT_INT_EQ(found.capture(2).index(), 2);
  found = re.match("-v");
  if (!EXPECT_NOT_NULL(found)) return;
  EXPECT_STR_EQ(found[<flag>], "-v");
  EXPECT_NULL(found[<key>]);
  EXPECT_STR_EQ(Regex.compile("cat|dog").match("hotdog")[0], "dog");
  EXPECT_STR_EQ(Regex.compile("(?:x|y)+z").match("xyxz")[0], "xyxz");
  EXPECT_INT_EQ(Regex.compile("a|").match("b").capture(0).end(), 0);
  EXPECT_TRUE(Regex.compile("()").match("b").capture(1).matched());
}

static void regex_find_all_split_and_offsets(void) {
  $test.scoped();
  Regex word = Regex.compile("\\w+");
  List all = word.find_all("one two  three");
  EXPECT_INT_EQ(all.len(), 3);
  EXPECT_STR_EQ(all.caddr().regexmatch()[0], "three");
  EXPECT_INT_EQ(all.caddr().regexmatch().capture(0).start(), 9);
  EXPECT_INT_EQ(word.find_all("").len(), 0);
  EXPECT_INT_EQ(Regex.compile("a*").find_all("baa").len(), 3);
  EXPECT_STR_EQ(word.match_from("one two", 2)[0], "e");
  EXPECT_NULL(word.match_from("one", 3));
  EXPECT_NULL(word.match_from("one", 4));
  EXPECT_NULL(word.match_from("one", -1));
  EXPECT_NULL(word.match(NULL));
  List parts = Regex.compile(" +").split("  two   words ");
  EXPECT_INT_EQ(parts.len(), 4);
  EXPECT_NULL(parts[0].string());
  EXPECT_STR_EQ(parts[1].string(), "two");
  EXPECT_STR_EQ(parts[2].string(), "words");
  EXPECT_NULL(parts[3].string());
  parts = Regex.compile(",").split("a,,b");
  EXPECT_INT_EQ(parts.len(), 3);
  EXPECT_NULL(parts[1].string());
  EXPECT_INT_EQ(Regex.compile(",").split("abc").len(), 1);
}

static void regex_replaces_and_escapes(void) {
  $test.scoped();
  Regex dated = Regex.compile("(\\d+)-(?<month>\\d+)");
  EXPECT_STR_EQ(dated.replace_all("2026-09 and 2027-01", "$2/$1"),
                "09/2026 and 01/2027");
  EXPECT_STR_EQ(dated.replace("2026-09 and 2027-01", "${month}"),
                "09 and 2027-01");
  EXPECT_STR_EQ(dated.replace_all("2026-09", "$$$0$"), "$2026-09$");
  EXPECT_STR_EQ(dated.replace_all("2026-09", "${nope}${month"), "${month");
  EXPECT_STR_EQ(Regex.compile("x").replace_all("abc", "y"), "abc");
  EXPECT_STR_EQ(Regex.compile("").replace_all("ab", "-"), "-a-b-");
  Func upper = %!(RegexMatch m) => m[0].upper();
  EXPECT_STR_EQ(Regex.compile("\\w+").replace_fn("go now", upper), "GO NOW");
  EXPECT_STR_EQ(Regex.escape("a.b*c"), "a\\.b\\*c");
  EXPECT_STR_EQ(Regex.escape("x_9"), "x_9");
  String escaped = Regex.escape("1+1=2?");
  EXPECT_STR_EQ(Regex.compile(escaped).match("is 1+1=2? yes")[0], "1+1=2?");
  EXPECT_STR_EQ(Regex.compile("a.c").pattern(), "a.c");
}

static void regex_rejects_bad_patterns(void) {
  $test.scoped();
  List cases = %(("(ab" "missing closing parenthesis" 3)
                 ("ab)" "unmatched closing parenthesis" 2)
                 ("[ab" "unterminated character class" 3)
                 ("*a" "nothing to repeat" 1)
                 ("^*" "nothing to repeat" 2)
                 ("a{3,1}" "repetition range out of order" 6)
                 ("[z-a]" "character range out of order" 4)
                 ("\\q" "unknown escape" 1)
                 ("ab\\" "pattern ends in a backslash" 3)
                 ("(?<1a>x)" "malformed group name" 3)
                 ("(?=x)" "unknown group syntax" 1));
  foreach (List row, cases) {
    String pattern = row.car().string();
    int caught = 0;
    try Regex.compile(pattern);
    catch %(bad-arg *detail): {
      caught = 1;
      EXPECT_STR_EQ(detail.assoc(<why>).string(), row.cadr().string());
      EXPECT_STR_EQ(detail.assoc(<pattern>).string(), pattern);
      EXPECT_INT_EQ(detail.assoc(<offset>).integer(),
                    row.caddr().integer());
    }
    EXPECT_INT_EQ(caught, 1);
  }
}

void regex_suite(void) {
  $test.run(regex_matches_literals_and_sets);
  $test.run(regex_classes_anchors_and_boundaries);
  $test.run(regex_repeats_greedy_and_lazy);
  $test.run(regex_alternation_and_groups);
  $test.run(regex_find_all_split_and_offsets);
  $test.run(regex_replaces_and_escapes);
  $test.run(regex_rejects_bad_patterns);
}
