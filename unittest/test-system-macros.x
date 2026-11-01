/*  test-system-macros.x -- the shipped system macro set */

#include "x2c.x"
#include "test-support.x"
#include "meta-support.x"
#include <time.h>
#include <unistd.h>
#include "test-macros.x"
#include "system-macros.x"

/* Stderr goes to a temporary file between the two calls, so a test reads
   exactly what $time streamed. */
static int _capture_stderr(File &file) {
  fflush(stderr);
  file = tmpfile();
  int saved = dup(STDERR_FILENO);
  dup2(fileno(file), STDERR_FILENO);
  return saved;
}

static String _captured_stderr(File file, int saved) {
  fflush(stderr);
  dup2(saved, STDERR_FILENO);
  close(saved);
  rewind(file);
  return file.string_close();
}

/* A multi-line literal cannot sit inside a function-like C macro invocation,
   so each block binds a local before the assertion reads it. */
static void system_macro_dedent_folds_and_defers(void) {
  String folded = $dedent(%"
    alpha
      beta
    gamma
  ");
  EXPECT_TRUE(folded == "alpha\n  beta\ngamma\n");
  String who = "world";
  String deferred = $dedent(%"
    hello $who
      indented
  ");
  EXPECT_TRUE(deferred == "hello world\n  indented\n");

  String escaped = $dedent("  first\n  second");
  EXPECT_TRUE(escaped == "first\nsecond");
  String plain = $dedent("plain");
  String empty = $dedent("");
  String tabs = $dedent(%"
	keyed
		deeper
");
  EXPECT_TRUE(plain == "plain");
  EXPECT_TRUE(empty == "");
  EXPECT_TRUE(tabs == "keyed\n\tdeeper\n");
  String input = "  left\n  right";
  String computed = $dedent(input);
  EXPECT_TRUE(computed == "left\nright");
}

macro Expression $dedent_block() => $dedent(%"
  alpha
    beta
");

macro Expression $dedent_forward(Expr $text) => $dedent($text);

static void system_macro_dedent_folds_nested_and_escaped_literals(void) {
  String nested = $dedent_block();
  String forwarded = $dedent_forward("\r\n\talpha\r\n\t\tbeta\r\n\t");
  EXPECT_TRUE(nested == "alpha\n  beta\n");
  EXPECT_TRUE(forwarded == "alpha\r\n\tbeta\r\n");
}

static void system_macro_dedent_evaluates_forwarded_text_once(void) {
  int calls = 0;
  String input = "  alpha\n    beta\n";
  String computed = $dedent_forward((calls++, input));
  EXPECT_TRUE(computed == "alpha\n  beta\n");
  EXPECT_INT_EQ(calls, 1);
  String interpolated = $dedent_forward(%"  item $(++calls)\n    beta\n");
  EXPECT_TRUE(interpolated == "item 2\n  beta\n");
  EXPECT_INT_EQ(calls, 2);
}

static void system_macro_assert_reports_the_written_check(void) {
  int limit = 50;
  String check = NULL, site = NULL;
  try $assert(limit > 0 && limit < 10);
  catch %(invariant (check ?written) (at ?where)): {
    check = written;
    site = where;
  }
  EXPECT_TRUE(check == "limit > 0 && limit < 10");
  EXPECT_TRUE(site.contains("test-system-macros.x:"));
}

static void system_macro_assert_passes_a_true_check(void) {
  int limit = 5;
  $assert(limit > 0 && limit < 10);
  EXPECT_INT_EQ(limit, 5);
}

static void system_macro_time_runs_its_target(void) {
  long total = 0;
  $time("unit")
  {
    for (int i = 0; i < 1000; i++) total += i;
  }
  EXPECT_TRUE(total == 499500);
}

$time("returning-body")
static int _timed_returning(int n) { return n * 2; }

$time("raising-body")
static int _timed_raising(void) {
  raise %(bad-arg (note "timed body transfer"));
}

/* The report sits in a defer, so a body that returns and a body a cause
   transfers out of both reach it. */
static void system_macro_time_reports_a_body_that_leaves(void) {
  $test.scoped();

  File file;
  int saved = _capture_stderr(file);
  int doubled = _timed_returning(21);
  String returned = _captured_stderr(file, saved);
  EXPECT_INT_EQ(doubled, 42);
  EXPECT_TRUE(returned.contains("[time] returning-body"));

  String note = NULL;
  saved = _capture_stderr(file);
  try _timed_raising();
  catch %(bad-arg (note ?text)): note = text;
  String raised = _captured_stderr(file, saved);
  EXPECT_TRUE(note == "timed body transfer");
  EXPECT_TRUE(raised.contains("[time] raising-body"));
}

typedef enum Shade { DIM, MID = 5, BRIGHT } Shade;

typedef enum Span {
  SPAN_SUFFIX = 1L,
  SPAN_LARGE = 3000000000,
  SPAN_HEX = 0x10,
  SPAN_CHAR = 'x',
  SPAN_NEGATIVE = -1,
  SPAN_RELATIVE = SPAN_HEX + 1
} Span;

// A literal initializer reads as its spelling; any other initializer reads
// as its expression node, which this table renders as a placeholder.
macro Expression $member_table(Type $T) => $meta_support_members($T);

static void system_macro_type_members_reads_an_enum(void) {
  String table = $member_table(Shade);
  EXPECT_TRUE(table == "DIM=-,MID=5,BRIGHT=-,");
}

static void system_macro_type_members_reads_every_initializer(void) {
  String table = $member_table(Span);
  EXPECT_TRUE(table == "SPAN_SUFFIX=1L,SPAN_LARGE=3000000000,SPAN_HEX=0x10,"
                       "SPAN_CHAR='x',SPAN_NEGATIVE=<expr>,"
                       "SPAN_RELATIVE=<expr>,");
}

void system_macros_suite(void) {
  $test.run(system_macro_dedent_folds_and_defers);
  $test.run(system_macro_dedent_folds_nested_and_escaped_literals);
  $test.run(system_macro_dedent_evaluates_forwarded_text_once);
  $test.run(system_macro_assert_reports_the_written_check);
  $test.run(system_macro_assert_passes_a_true_check);
  $test.run(system_macro_time_runs_its_target);
  $test.run(system_macro_time_reports_a_body_that_leaves);
  $test.run(system_macro_type_members_reads_an_enum);
  $test.run(system_macro_type_members_reads_every_initializer);
}
