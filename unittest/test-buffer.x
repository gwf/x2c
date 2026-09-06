/*  test-buffer.x -- unit tests for the text Buffer contract */

#include "test-support.x"
$(import "test-macros.xmacro")
#include <limits.h>
#include <wchar.h>

static void buffer_bulk_writes_and_exact_string(void) {
  $test.scoped();
  Buffer buf = Buffer.new(2);
  EXPECT_TRUE(buf.indents != NULL);
  buf.write("hi").write_char('!').write_repeat(' ', 3);
  EXPECT_INT_EQ(buf.len(), 6);
  EXPECT_INT_EQ(buf.pos, 6);
  EXPECT_STR_EQ(buf.str(), "hi!   ");
  buf.pad();
  EXPECT_STR_EQ(buf.str_free(), "hi!     ");
}

static void buffer_multiline_state(void) {
  $test.scoped();
  Buffer buf = Buffer.new(0);
  buf.write("ab\n  cd");
  EXPECT_INT_EQ(buf.pos, 4);
  EXPECT_INT_EQ(buf._indent, 2);
  buf.newline();
  EXPECT_INT_EQ(buf.pos, 0);
  EXPECT_INT_EQ(buf._indent, 0);
  buf.write_repeat(' ', 3).write("x");
  EXPECT_INT_EQ(buf.pos, 4);
  EXPECT_INT_EQ(buf._indent, 3);
  EXPECT_STR_EQ(buf.str_free(), "ab\n  cd\n   x");
}

static void buffer_self_alias_growth_preserves_line_state(void) {
  $test.scoped();
  Buffer buf = Buffer.new(0);
  buf.write("ab\n  cd");
  size_t capacity = buf.content.capacity();
  const char *tail = buf.content.bytes + 3;
  buf.write_len(tail, 4);
  EXPECT_TRUE(buf.content.capacity() > capacity);
  EXPECT_STR_EQ(buf.str(), "ab\n  cd  cd");
  EXPECT_INT_EQ(buf.pos, 8);
  EXPECT_INT_EQ(buf._indent, 2);
  buf.free();
}

static void buffer_unwrite_crosses_lines(void) {
  $test.scoped();
  Buffer buf = Buffer.new(0);
  buf.write("ab").newline().write("cd");
  EXPECT_INT_EQ(buf.pos, 2);
  buf.unwrite(4);
  EXPECT_STR_EQ(buf.str(), "a");
  EXPECT_INT_EQ(buf.pos, 1);
  EXPECT_INT_EQ(buf._indent, 0);
  buf.unwrite(99);
  EXPECT_INT_EQ(buf.len(), 0);
  EXPECT_INT_EQ(buf.pos, 0);
  EXPECT_INT_EQ(buf._indent, 0);
  buf.free();
}

static void buffer_eager_indents_and_clear_reuse(void) {
  $test.scoped();
  Buffer buf = Buffer.new(0);
  buf.reserve(64);
  size_t capacity = buf.content.capacity();
  buf.pop();
  EXPECT_TRUE(buf.indents != NULL);
  EXPECT_INT_EQ(buf.indents.len(), 0);
  buf.write("line1").push().newline_indent().write("line2");
  EXPECT_INT_EQ(buf.indents.len(), 1);
  EXPECT_INT_EQ(buf.tabstop(), 5);
  EXPECT_STR_EQ(buf.str(), "line1\n     line2");
  buf.clear();
  EXPECT_INT_EQ(buf.len(), 0);
  EXPECT_INT_EQ(buf.tabstop(), 0);
  EXPECT_INT_EQ(buf.indents.len(), 0);
  EXPECT_INT_EQ(buf.content.capacity(), capacity);
  buf.write("reused");
  EXPECT_STR_EQ(buf.str_free(), "reused");
}

static void buffer_status_get(void) {
  $test.scoped();
  Buffer buf = Buffer.new(0);
  buf.write("abc");
  char out = 'z';
  EXPECT_TRUE(buf.try_get(0, &out));
  EXPECT_TRUE(out == 'a');
  EXPECT_TRUE(buf.try_get(-1, &out));
  EXPECT_TRUE(out == 'c');
  out = 'z';
  EXPECT_FALSE(buf.try_get(3, &out));
  EXPECT_TRUE(out == 'z');
  EXPECT_FALSE(buf.try_get(-4, &out));
  EXPECT_TRUE(out == 'z');
  EXPECT_TRUE(buf.get(-1) == 'c');
  EXPECT_TRUE(buf.get(99) == '\0');
  buf.free();
}

static void buffer_printf_short_and_long(void) {
  $test.scoped();
  Buffer buf = Buffer.new(2);
  buf.printf("%s=%d", "answer", 42);
  EXPECT_STR_EQ(buf.str(), "answer=42");
  buf.clear();
  // Results past the 160-byte stack fast path must not truncate.
  char wide[301];
  memset(wide, 'x', 300);
  wide[300] = 0;
  buf.printf("[%s]", wide);
  EXPECT_INT_EQ(buf.len(), 302);
  EXPECT_TRUE(buf.str()[0] == '[' && buf.str()[301] == ']');
  buf.free();
}

static void buffer_reports_contract_failures(void) {
  $test.scoped();
  Buffer buf = Buffer.new(0);
  buf.write("kept");
  int caught = 0;
  try buf.write(NULL);
  catch %(bad-arg *): caught++;
  EXPECT_INT_EQ(buf.len(), 4);
  EXPECT_STR_EQ(buf.str(), "kept");
  buf.clear().write("reused");
  EXPECT_STR_EQ(buf.str(), "reused");

  buf.clear().write("kept");
  try buf.write_char('\0');
  catch %(bad-arg *): caught++;
  EXPECT_INT_EQ(buf.len(), 4);
  EXPECT_STR_EQ(buf.str(), "kept");
  buf.clear().write("reused");
  EXPECT_STR_EQ(buf.str_free(), "reused");
  EXPECT_INT_EQ(caught, 2);

}

static void buffer_formatting_failure_transfers_and_keeps_text(void) {
  $test.scoped();
  Buffer buf = Buffer.new(0);
  buf.write("kept");
  // An unpaired surrogate has no multibyte encoding, so `%ls` cannot format.
  wchar_t invalid[2] = { (wchar_t) 0xD800, 0 };
  int caught = 0;
  try buf.printf("%ls", invalid);
  catch %(format *): caught = 1;
  EXPECT_TRUE(caught);
  // The failure transfers rather than returning, and it leaves no latch:
  // earlier text survives and later writes still append without a clear().
  EXPECT_STR_EQ(buf.str(), "kept");
  buf.write("-more");
  EXPECT_STR_EQ(buf.str_free(), "kept-more");
}

static void buffer_str_free_consumes_the_receiver(void) {
  $test.scoped();
  ScopeStats before = Scope.stats();
  Buffer text = Buffer.new(0);
  text.write("consumed");
  EXPECT_STR_EQ(text.str_free(), "consumed");
  // An empty Buffer converts to NULL and is released just the same, so the
  // live allocation count returns to where it started either way.
  Buffer empty = Buffer.new(0);
  EXPECT_NULL(empty.str_free());
  EXPECT_INT_EQ(Scope.stats().live_allocations, before.live_allocations);
}


void buffer_suite(void) {
  $test.run(buffer_formatting_failure_transfers_and_keeps_text);
  $test.run(buffer_str_free_consumes_the_receiver);
  $test.run(buffer_printf_short_and_long);
  $test.run(buffer_bulk_writes_and_exact_string);
  $test.run(buffer_multiline_state);
  $test.run(buffer_self_alias_growth_preserves_line_state);
  $test.run(buffer_unwrite_crosses_lines);
  $test.run(buffer_eager_indents_and_clear_reuse);
  $test.run(buffer_status_get);
  $test.run(buffer_reports_contract_failures);
}
