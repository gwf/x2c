/*  test-diagnostics.x -- unit tests for diagnostics aggregation */

#include "test-support.x"
$(import "test-macros.xmacro")
#include "diagnostics.x"

static int capture_calls = 0;

static void capture_entry(void *owner, List entry) {
  List *buffer = owner;
  if (!buffer) return;
  *buffer = cons(entry, *buffer);
  capture_calls += 1;
}

static void diagnostics_records_entries(void) {
  $test.scoped();

  capture_calls = 0;
  List sink_buffer = nil;
  Diagnostics diag = Diagnostics.new(NULL, NULL, 2);
  diag.set_emitter(capture_entry, &sink_buffer);
  List first_notes = %( "initialize flag before use" );
  diag.report(<first>, %"first", NULL, first_notes);
  diag.report(<second>, %"second", NULL, NULL);
  diag.report(<third>, %"third", NULL, NULL);

  EXPECT_INT_EQ(diag.count, 2);
  EXPECT_TRUE(diag.reached_limit());
  EXPECT_INT_EQ(diag.limit, 2);
  EXPECT_INT_EQ(sink_buffer.len(), 3);

  List entries = diag.entries();
  EXPECT_INT_EQ(entries.len(), 3);

  List (first, second, limit) = entries;

  Var second_location = second.assoc(<location>);
  Var second_notes = second.assoc(<notes>);
  EXPECT_TRUE(second_location is <list>);
  EXPECT_TRUE(second_notes is <list>);
  EXPECT_NULL(second_location.list());
  EXPECT_NULL(second_notes.list());

  Var first_message = first.assoc(<message>);
  Var second_message = second.assoc(<message>);
  String first_str = first_message is void ? NULL : first_message.string();
  String second_str = second_message is void ? NULL : second_message.string();
  EXPECT_TRUE(first_str != NULL);
  EXPECT_TRUE(second_str != NULL);
  EXPECT_TRUE(first_str == %"first");
  EXPECT_TRUE(second_str == %"second");

  List sink_entries = sink_buffer.reverse();
  EXPECT_INT_EQ(sink_entries.len(), 3);
  List first_sink_entry = sink_entries.car();
  Var log_message = first_sink_entry.assoc(<message>);
  Var log_notes = first_sink_entry.assoc(<notes>);
  EXPECT_TRUE(log_message.string() == %"first");
  EXPECT_FALSE(log_notes is void);
  List logged_notes = log_notes;
  EXPECT_INT_EQ(logged_notes.len(), 1);
  EXPECT_TRUE(logged_notes.car().string() == %"initialize flag before use");

  Var limit_code = limit.assoc(<code>), limit_message = limit.assoc(<message>);
  EXPECT_TRUE(limit_code.symbol() == <limit>);
  EXPECT_TRUE(limit_message.string() == %"too many errors, stopping");
  EXPECT_INT_EQ(capture_calls, 3);
}

static void diagnostics_reset_clears_state(void) {
  $test.scoped();

  Diagnostics diag = Diagnostics.new(NULL, NULL, 1);
  diag.report(<once>, %"only", NULL, NULL);
  diag.report(<ignored>, %"later", NULL, NULL);

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
  $test.run(diagnostics_reset_clears_state);
}
