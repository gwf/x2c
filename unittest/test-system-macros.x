/*  test-system-macros.x -- the shipped system macro set */

#include "x2c.x"
#include "test-support.x"
#include <time.h>
#include <unistd.h>
$(import "test-macros.xmacro")
$(import "system-macros.xmacro")

/* Stderr goes to a temporary file between the two calls, so a test reads
   exactly what $time streamed. */
static int _capture_stderr(File *file) {
  fflush(stderr);
  *file = tmpfile();
  int saved = dup(STDERR_FILENO);
  dup2(fileno(*file), STDERR_FILENO);
  return saved;
}

static String _captured_stderr(File file, int saved) {
  fflush(stderr);
  dup2(saved, STDERR_FILENO);
  close(saved);
  rewind(file);
  return file.string_close();
}

static String _classify(int code) {
  String reached = "none";
  $switch(code)
  {
    case 1:
    case 2:
      String shared = "low";
      reached = shared;
    case 3:
      String shared = "three";
      reached = shared;
    default:
      reached = "other";
  }
  return reached;
}

static int _returns_early(int code) {
  $switch(code)
  {
    case 1:
      return 10;
    default:
      return -1;
  }
}

static void system_macro_switch_scopes_and_breaks_each_run(void) {
  EXPECT_TRUE(_classify(1) == "low");
  EXPECT_TRUE(_classify(2) == "low");
  EXPECT_TRUE(_classify(3) == "three");
  EXPECT_TRUE(_classify(9) == "other");
  EXPECT_INT_EQ(_returns_early(1), 10);
  EXPECT_INT_EQ(_returns_early(2), -1);
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

static void system_macro_todo_and_unreachable_carry_a_note(void) {
  String note = NULL, dead = NULL;
  try $todo("column alignment");
  catch %(invariant (note ?text) (at ?where)): note = text;
  EXPECT_TRUE(note == "column alignment");
  try $unreachable();
  catch %(invariant (note ?text) (at ?where)): dead = text;
  EXPECT_TRUE(dead == "unreachable");
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
  int saved = _capture_stderr(&file);
  int doubled = _timed_returning(21);
  String returned = _captured_stderr(file, saved);
  EXPECT_INT_EQ(doubled, 42);
  EXPECT_TRUE(returned.contains("[time] returning-body"));

  String note = NULL;
  saved = _capture_stderr(&file);
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
macro Expression $member_table(Type $T) =>
  $(x2c.literal.string (foldl
     (lambda (text row)
       (string-append text (car row) "="
         (let ((value (cadr row)))
           (if (not value) "-" (if (string? value) value "<expr>")))
         ","))
     "" (x2c.type.members $T)));

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
  $test.run(system_macro_switch_scopes_and_breaks_each_run);
  $test.run(system_macro_dedent_folds_and_defers);
  $test.run(system_macro_assert_reports_the_written_check);
  $test.run(system_macro_assert_passes_a_true_check);
  $test.run(system_macro_todo_and_unreachable_carry_a_note);
  $test.run(system_macro_time_runs_its_target);
  $test.run(system_macro_time_reports_a_body_that_leaves);
  $test.run(system_macro_type_members_reads_an_enum);
  $test.run(system_macro_type_members_reads_every_initializer);
}
