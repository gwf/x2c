/*  test-termbox.x -- lifecycle, event, rendering, and cleanup proof. */

import "termbox2" with Termbox, TermboxCell, TermboxEvent;

#include "terminal-test-helper.h"
#include "test-support.x"

#include <errno.h>
#include <locale.h>
#include <stdlib.h>

$(import "../../../unittest/test-macros.xmacro")

static void failed_init_restores_sigwinch(void) {
  EXPECT_INT_EQ(termbox_test_install_winch(), 0);
  String saved_term = String.new(getenv("TERM"));
  EXPECT_INT_EQ(setenv("TERM", "x2c-no-such-terminal", 1), 0);

  int caught = 0;
  try {
    Termbox terminal = Termbox.open();
    if (terminal) terminal.close();
  }
  catch %(term-error *detail): {
    caught = 1;
    EXPECT_STR_EQ(detail.assoc(<library>).string(), %"termbox2");
    EXPECT_STR_EQ(detail.assoc(<operation>).string(), %"init");
    EXPECT_TRUE(detail.assoc(<code>).integer() < 0);
    EXPECT_TRUE(detail.assoc(<message>).string().len() > 0);
  }
  EXPECT_TRUE(caught);
  EXPECT_TRUE(termbox_test_winch_restored());
  EXPECT_INT_EQ(setenv("TERM", saved_term, 1), 0);
  EXPECT_INT_EQ(termbox_test_restore_winch(), 0);
}

static void exclusive_owner_and_repeated_close(void) {
  EXPECT_INT_EQ(termbox_test_install_winch(), 0);
  EXPECT_INT_EQ(termbox_test_snapshot_tty(), 0);
  Termbox terminal = Termbox.open();
  EXPECT_NOT_NULL(terminal);

  int caught = 0;
  try Termbox.open();
  catch %(bad-state *detail): {
    caught = 1;
    EXPECT_STR_EQ(detail.assoc(<operation>).string(), %"init");
  }
  EXPECT_TRUE(caught);
  EXPECT_TRUE(terminal.width() > 0);
  EXPECT_TRUE(terminal.height() > 0);

  EXPECT_NULL(terminal.close());
  EXPECT_NULL(terminal.close());
  EXPECT_TRUE(termbox_test_tty_restored());
  EXPECT_TRUE(termbox_test_winch_restored());
  EXPECT_INT_EQ(termbox_test_restore_winch(), 0);
}

static void event_copy_timeout_resize_and_render(void) {
  EXPECT_INT_EQ(termbox_test_install_winch(), 0);
  EXPECT_INT_EQ(termbox_test_snapshot_tty(), 0);
  Termbox terminal = Termbox.open();
  terminal.set_input_mode(TB_INPUT_ALT);

  Stdout.puts("READY keys");
  Stdout.flush();
  TermboxEvent first = terminal.poll(), second = terminal.poll();
  EXPECT_TRUE(first.is_key());
  EXPECT_TRUE(second.is_key());
  EXPECT_STR_EQ(first.text(), %"\xce\xbb");
  EXPECT_STR_EQ(second.text(), %"x");
  EXPECT_STR_EQ(first.text(), %"\xce\xbb");
  EXPECT_FALSE(first.has_modifier(TB_MOD_ALT));
  EXPECT_TRUE(second.has_modifier(TB_MOD_ALT));

  Stdout.puts("READY resize");
  Stdout.flush();
  TermboxEvent resize = terminal.poll();
  EXPECT_TRUE(resize.is_resize());
  EXPECT_INT_EQ(resize.width(), 84);
  EXPECT_INT_EQ(resize.height(), 16);
  EXPECT_INT_EQ(terminal.width(), 84);
  EXPECT_INT_EQ(terminal.height(), 16);

  terminal.clear();
  EXPECT_INT_EQ(
    terminal.print(0, 0, %"e\xcc\x81 \xe7\x95\x8c", TB_WHITE, TB_DEFAULT),
    4
  );
  EXPECT_INT_EQ(
    terminal.print(
      terminal.width() - 1, 1, %"\xe7\x95\x8c",
      TB_WHITE, TB_DEFAULT
    ),
    2
  );
  int caught = 0;
  try terminal.print(terminal.width(), 1, %"x", TB_WHITE, TB_DEFAULT);
  catch %(term-error *detail): {
    caught = 1;
    EXPECT_STR_EQ(detail.assoc(<operation>).string(), %"print");
    EXPECT_INT_EQ(detail.assoc(<code>).integer(), TB_ERR_OUT_OF_BOUNDS);
    EXPECT_TRUE(detail.assoc(<message>).string().len() > 0);
  }
  EXPECT_TRUE(caught);
  terminal.present();

  EXPECT_NULL(terminal.close());
  EXPECT_TRUE(termbox_test_tty_restored());
  EXPECT_TRUE(termbox_test_winch_restored());
  EXPECT_INT_EQ(termbox_test_restore_winch(), 0);
}

static void mouse_click_reports_button_and_position(void) {
  Termbox terminal = Termbox.open();
  terminal.set_input_mode(TB_INPUT_ESC | TB_INPUT_MOUSE);

  Stdout.puts("READY mouse");
  Stdout.flush();
  TermboxEvent click = terminal.poll();
  EXPECT_TRUE(click.is_mouse());
  EXPECT_FALSE(click.is_key());
  EXPECT_FALSE(click.is_resize());
  EXPECT_INT_EQ(click.key(), TB_KEY_MOUSE_LEFT);
  EXPECT_INT_EQ(click.x(), 12);
  EXPECT_INT_EQ(click.y(), 4);
  EXPECT_NULL(click.text());

  TermboxEvent empty = { 0 };
  EXPECT_INT_EQ(empty.x(), 0);
  EXPECT_INT_EQ(empty.y(), 0);
  EXPECT_FALSE(empty.is_mouse());
  EXPECT_NULL(terminal.close());
}

static void fill_repeats_one_cluster_and_reads_back(void) {
  Termbox terminal = Termbox.open();
  terminal.clear();

  terminal.fill(2, 1, 3, 2, %"#", TB_GREEN | TB_BOLD, TB_BLUE);
  TermboxCell drawn = terminal.cell(3, 2);
  EXPECT_STR_EQ(drawn.text, %"#");
  EXPECT_INT_EQ(drawn.foreground, TB_GREEN | TB_BOLD);
  EXPECT_INT_EQ(drawn.background, TB_BLUE);
  TermboxCell beyond = terminal.cell(5, 1);
  EXPECT_STR_EQ(beyond.text, %" ");
  EXPECT_INT_EQ(beyond.background, TB_DEFAULT);
  EXPECT_STR_EQ(terminal.cell(2, 3).text, %" ");

  /*  A combining cluster stays one cell and comes back whole; a wide one
      steps two columns and stops before a column it could only half fill. */
  terminal.fill(0, 4, 2, 1, %"e\xcc\x81", TB_WHITE, TB_DEFAULT);
  EXPECT_STR_EQ(terminal.cell(1, 4).text, %"e\xcc\x81");
  terminal.fill(0, 5, 5, 1, %"\xe7\x95\x8c", TB_WHITE, TB_DEFAULT);
  EXPECT_STR_EQ(terminal.cell(0, 5).text, %"\xe7\x95\x8c");
  EXPECT_STR_EQ(terminal.cell(2, 5).text, %"\xe7\x95\x8c");
  EXPECT_STR_EQ(terminal.cell(4, 5).text, %" ");

  /*  The extent is clipped to the screen; the origin is not. */
  int width = terminal.width(), height = terminal.height();
  terminal.fill(width - 2, height - 1, 40, 40, %"*", TB_WHITE, TB_DEFAULT);
  EXPECT_STR_EQ(terminal.cell(width - 1, height - 1).text, %"*");

  int outside = 0;
  try terminal.fill(width, 0, 1, 1, %"*", TB_WHITE, TB_DEFAULT);
  catch %(term-error *detail): {
    outside = 1;
    EXPECT_STR_EQ(detail.assoc(<operation>).string(), %"fill");
    EXPECT_INT_EQ(detail.assoc(<code>).integer(), TB_ERR_OUT_OF_BOUNDS);
  }
  EXPECT_TRUE(outside);

  int blank = 0;
  try terminal.fill(0, 0, 1, 1, %"", TB_WHITE, TB_DEFAULT);
  catch %(bad-arg *detail): {
    blank = 1;
    EXPECT_STR_EQ(detail.assoc(<operation>).string(), %"fill");
  }
  EXPECT_TRUE(blank);

  int null_text = 0;
  try terminal.fill(0, 0, 1, 1, NULL, TB_WHITE, TB_DEFAULT);
  catch %(bad-arg *detail): {
    null_text = 1;
    EXPECT_STR_EQ(detail.assoc(<operation>).string(), %"fill");
  }
  EXPECT_TRUE(null_text);

  int cell_outside = 0;
  try terminal.cell(0, height);
  catch %(term-error *detail): {
    cell_outside = 1;
    EXPECT_STR_EQ(detail.assoc(<operation>).string(), %"cell");
    EXPECT_INT_EQ(detail.assoc(<code>).integer(), TB_ERR_OUT_OF_BOUNDS);
  }
  EXPECT_TRUE(cell_outside);

  terminal.present();
  EXPECT_NULL(terminal.close());
}

/*  print extends one cell for every zero-width codepoint, with no limit, so
    a cell holds as much text as was drawn into it. Twelve four-byte
    codepoints are 48 bytes of UTF-8 in one cell, and cell() owes back every
    one of them. */
static void a_long_cluster_comes_back_whole(void) {
  Termbox terminal = Termbox.open();
  terminal.clear();

  /*  U+1D400 is the one column; U+E0100 through U+E010A are variation
      selectors, printable and zero-width, and four bytes each. */
  char selector[] = "\xf3\xa0\x84\x80";
  Buffer drawn = Buffer.new(0).write(%"\xf0\x9d\x90\x80");
  for (int mark = 0; mark < 11; mark++) {
    selector[3] = (char) (0x80 + mark);
    drawn.write_len(selector, 4);
  }
  String cluster = drawn.str_free();
  EXPECT_INT_EQ(cluster.len(), 48);

  EXPECT_INT_EQ(terminal.print(3, 2, cluster, TB_WHITE, TB_DEFAULT), 1);
  TermboxCell cell = terminal.cell(3, 2);
  EXPECT_INT_EQ(cell.text.len(), 48);
  EXPECT_STR_EQ(cell.text, cluster);

  terminal.present();
  EXPECT_NULL(terminal.close());
}

static void box_draws_a_frame_around_its_interior(void) {
  Termbox terminal = Termbox.open();
  terminal.clear();
  terminal.box(1, 1, 4, 3, TB_CYAN, TB_DEFAULT);

  EXPECT_STR_EQ(terminal.cell(1, 1).text, %"\xe2\x94\x8c");
  EXPECT_STR_EQ(terminal.cell(4, 1).text, %"\xe2\x94\x90");
  EXPECT_STR_EQ(terminal.cell(1, 3).text, %"\xe2\x94\x94");
  EXPECT_STR_EQ(terminal.cell(4, 3).text, %"\xe2\x94\x98");
  EXPECT_STR_EQ(terminal.cell(2, 1).text, %"\xe2\x94\x80");
  EXPECT_STR_EQ(terminal.cell(1, 2).text, %"\xe2\x94\x82");
  EXPECT_STR_EQ(terminal.cell(4, 2).text, %"\xe2\x94\x82");
  EXPECT_INT_EQ(terminal.cell(1, 2).foreground, TB_CYAN);
  EXPECT_STR_EQ(terminal.cell(2, 2).text, %" ");

  int degenerate = 0;
  try terminal.box(0, 0, 1, 3, TB_CYAN, TB_DEFAULT);
  catch %(bad-arg *detail): {
    degenerate = 1;
    EXPECT_STR_EQ(detail.assoc(<operation>).string(), %"box");
    EXPECT_INT_EQ(detail.assoc(<width>).integer(), 1);
  }
  EXPECT_TRUE(degenerate);

  terminal.present();
  EXPECT_NULL(terminal.close());
}

static void measure_agrees_with_print_without_drawing(void) {
  EXPECT_INT_EQ(Termbox.measure(%"abc"), 3);
  EXPECT_INT_EQ(Termbox.measure(%"e\xcc\x81 \xe7\x95\x8c"), 4);
  EXPECT_INT_EQ(Termbox.measure(%""), 0);
  EXPECT_INT_EQ(Termbox.measure(NULL), 0);
  EXPECT_INT_EQ(Termbox.measure(%"a\nbc"), 3);

  Termbox terminal = Termbox.open();
  terminal.clear();
  String text = %"e\xcc\x81 \xe7\x95\x8c";
  EXPECT_INT_EQ(terminal.print(0, 0, text, TB_WHITE, TB_DEFAULT), 4);
  EXPECT_INT_EQ(Termbox.measure(text), 4);

  /*  Measuring costs no cells: nothing was drawn where print would have
      raised, and the row it would have used is still blank. */
  String wide = %"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
  EXPECT_INT_EQ(Termbox.measure(wide), 50);
  EXPECT_STR_EQ(terminal.cell(0, 1).text, %" ");
  EXPECT_NULL(terminal.close());
  EXPECT_INT_EQ(Termbox.measure(text), 4);
}

static void cursor_shows_moves_and_hides(void) {
  Termbox terminal = Termbox.open();
  terminal.clear();

  Stdout.puts("READY cursor");
  Stdout.flush();
  EXPECT_PTR_EQ(terminal.set_cursor(9, 4), terminal);
  terminal.present();
  EXPECT_PTR_EQ(terminal.hide_cursor(), terminal);
  terminal.present();

  EXPECT_INT_EQ(tb_shutdown(), TB_OK);
  int caught = 0;
  try terminal.set_cursor(0, 0);
  catch %(term-error *detail): {
    caught = 1;
    EXPECT_STR_EQ(detail.assoc(<operation>).string(), %"set_cursor");
    EXPECT_INT_EQ(detail.assoc(<code>).integer(), TB_ERR_NOT_INIT);
  }
  EXPECT_TRUE(caught);

  try terminal.close();
  catch %(term-error *detail): EXPECT_NOT_NULL(detail);
  EXPECT_NULL(terminal.close());

  int closed = 0;
  try terminal.set_cursor(0, 0);
  catch %(bad-state *detail): {
    closed = 1;
    EXPECT_STR_EQ(detail.assoc(<operation>).string(), %"set_cursor");
  }
  EXPECT_TRUE(closed);
}

static void peek_keeps_one_deadline_across_interrupts(void) {
  Termbox terminal = Termbox.open();
  long long started = termbox_test_monotonic_ms();
  EXPECT_TRUE(started >= 0);
  EXPECT_INT_EQ(termbox_test_arm_repeating_interrupt(5), 0);
  TermboxEvent empty = terminal.peek(40);
  long long elapsed = termbox_test_monotonic_ms() - started;
  EXPECT_INT_EQ(termbox_test_stop_interrupts(), 0);

  EXPECT_FALSE(empty.available());
  EXPECT_TRUE(termbox_test_interrupt_count() >= 3);
  EXPECT_TRUE(elapsed >= 30);
  EXPECT_TRUE(elapsed < 250);
  EXPECT_NULL(terminal.close());
}

static void generic_error_does_not_reuse_errno(void) {
  Termbox terminal = Termbox.open();
  EXPECT_INT_EQ(termbox_test_arm_interrupt(5), 0);
  EXPECT_FALSE(terminal.peek(20).available());
  EXPECT_TRUE(termbox_test_interrupt_fired());

  int caught = 0;
  try terminal.set_output_mode(-1);
  catch %(term-error *detail): {
    caught = 1;
    EXPECT_STR_EQ(detail.assoc(<operation>).string(), %"set_output_mode");
    EXPECT_INT_EQ(detail.assoc(<code>).integer(), TB_ERR);
    EXPECT_STR_EQ(
      detail.assoc(<message>).string(), %"Termbox operation failed"
    );
    EXPECT_TRUE(detail.assoc(<errno>) is void);
    EXPECT_TRUE(detail.assoc(<errno-msg>) is void);
  }
  EXPECT_TRUE(caught);
  EXPECT_NULL(terminal.close());
}

static void event_failure_keeps_native_detail_and_cleans_up(void) {
  EXPECT_INT_EQ(termbox_test_install_winch(), 0);
  Termbox terminal = Termbox.open();
  EXPECT_INT_EQ(tb_shutdown(), TB_OK);

  int read_caught = 0;
  try terminal.peek(1);
  catch %(term-error *detail): {
    read_caught = 1;
    EXPECT_STR_EQ(detail.assoc(<operation>).string(), %"peek_event");
    EXPECT_INT_EQ(detail.assoc(<code>).integer(), TB_ERR_NOT_INIT);
    EXPECT_TRUE(detail.assoc(<message>).string().len() > 0);
  }
  EXPECT_TRUE(read_caught);

  int close_caught = 0;
  try terminal.close();
  catch %(term-error *detail): {
    close_caught = 1;
    EXPECT_STR_EQ(detail.assoc(<operation>).string(), %"shutdown");
    EXPECT_INT_EQ(detail.assoc(<code>).integer(), TB_ERR_NOT_INIT);
  }
  EXPECT_TRUE(close_caught);
  EXPECT_NULL(terminal.close());
  EXPECT_TRUE(termbox_test_winch_restored());
  EXPECT_INT_EQ(termbox_test_restore_winch(), 0);
}

void termbox_suite(void) {
  $test.run(failed_init_restores_sigwinch);
  $test.run(exclusive_owner_and_repeated_close);
  $test.run(event_copy_timeout_resize_and_render);
  $test.run(mouse_click_reports_button_and_position);
  $test.run(fill_repeats_one_cluster_and_reads_back);
  $test.run(a_long_cluster_comes_back_whole);
  $test.run(box_draws_a_frame_around_its_interior);
  $test.run(measure_agrees_with_print_without_drawing);
  $test.run(cursor_shows_moves_and_hides);
  $test.run(peek_keeps_one_deadline_across_interrupts);
  $test.run(generic_error_does_not_reuse_errno);
  $test.run(event_failure_keeps_native_detail_and_cleans_up);
}

int main(void) {
  if (!setlocale(LC_CTYPE, "")) return 2;
  TestHarness_begin();
  $test.suite(termbox_suite);
  return TestHarness_finish();
}
