/*  test-diagnostics.x -- unit tests for diagnostics aggregation */

#include "test-support.x"
$(import "test-macros.xmacro")
#include "diagnostics.x"
#include <unistd.h>

/* Stderr goes to a temporary file between the two calls, so a test reads
   exactly what its printer streamed. */
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

static void diagnostics_records_entries(void) {
  $test.scoped();

  Diagnostics diag =
    Diagnostics.new(Scope.calloc(1, sizeof(struct Compiler)), 2);
  List first_notes = %( "initialize flag before use" );
  File file;
  int saved = _capture_stderr(file);
  diag.report(<first>, "first", NULL, first_notes);
  diag.report(<second>, "second", NULL, NULL);
  diag.report(<third>, "third", NULL, NULL);
  String printed = _captured_stderr(file, saved);

  EXPECT_INT_EQ(diag.count, 2);
  EXPECT_TRUE(diag.reached_limit());
  EXPECT_INT_EQ(diag.limit, 2);
  EXPECT_STR_EQ(
    printed,
    "first: first\n  note: initialize flag before use\n\n"
    "second: second\n\n"
    "limit: too many errors, stopping\n\n");

  List entries = diag.entries();
  EXPECT_INT_EQ(entries.len(), 3);

  List (first, second, limit) = entries;

  Var second_location = second.assoc(<location>);
  Var second_notes = second.assoc(<notes>);
  EXPECT_TRUE(second_location is <list>);
  EXPECT_TRUE(second_notes is <list>);
  EXPECT_NULL(second_location.list());
  EXPECT_NULL(second_notes.list());

  EXPECT_TRUE(first.assoc(<message>).string() == "first");
  EXPECT_TRUE(second.assoc(<message>).string() == "second");
  List logged_notes = first.assoc(<notes>);
  EXPECT_INT_EQ(logged_notes.len(), 1);
  EXPECT_TRUE(logged_notes.car().string() == "initialize flag before use");

  Var limit_code = limit.assoc(<code>), limit_message = limit.assoc(<message>);
  EXPECT_TRUE(limit_code.symbol() == <limit>);
  EXPECT_TRUE(limit_message.string() == "too many errors, stopping");
}

static void diagnostics_release_keeps_or_discards(void) {
  $test.scoped();

  Compiler printer = Scope.calloc(1, sizeof(struct Compiler));
  Diagnostics diag = Diagnostics.new(printer, 1);
  File file;
  int saved = _capture_stderr(file);
  DiagnosticsHold hold = diag.hold();
  EXPECT_NULL(diag.printer);
  diag.report(<discarded>, "discarded", NULL, NULL);
  diag.release(hold, 0);
  EXPECT_PTR_EQ(diag.printer, printer);
  EXPECT_INT_EQ(diag.count, 0);
  EXPECT_INT_EQ(diag.entries.len(), 0);

  hold = diag.hold();
  diag.report(<kept>, "kept", NULL, NULL);
  EXPECT_STR_EQ(_captured_stderr(file, saved), NULL);
  saved = _capture_stderr(file);
  diag.release(hold, 1);
  EXPECT_STR_EQ(_captured_stderr(file, saved), "kept: kept\n\n");
  EXPECT_INT_EQ(diag.count, 1);
  EXPECT_TRUE(diag.reached_limit());
}

static void diagnostics_reset_clears_state(void) {
  $test.scoped();

  Diagnostics diag = Diagnostics.new(NULL, 1);
  diag.report(<once>, "only", NULL, NULL);
  diag.report(<ignored>, "later", NULL, NULL);

  EXPECT_INT_EQ(1, diag.count);
  EXPECT_TRUE(diag.reached_limit());
  EXPECT_INT_EQ(diag.entries().len(), 1);
  EXPECT_TRUE(diag.entries().car().list().assoc(<code>).symbol() == <once>);

  diag.reset();
  EXPECT_INT_EQ(0, diag.count);
  EXPECT_FALSE(diag.reached_limit());

}

void diagnostics_suite(void) {
  $test.run(diagnostics_records_entries);
  $test.run(diagnostics_release_keeps_or_discards);
  $test.run(diagnostics_reset_clears_state);
}
