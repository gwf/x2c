/*  termbox2.x -- owned termbox2 terminal and copied input and cell values.

    One live Termbox owns termbox2's process-global terminal. It also owns a
    copy of the caller's prior SIGWINCH disposition because native teardown
    replaces that disposition with SIG_DFL. TermboxEvent and TermboxCell
    contain no borrowed native storage; their text is copied into a canonical
    String immediately.
 */

#include "termbox2-2.5.h"

typedef struct Termbox *Termbox;

typedef struct TermboxEvent {
  int present;
  uint8_t type;
  uint8_t modifiers;
  uint16_t native_key;
  String input_text;
  int32_t resize_width;
  int32_t resize_height;
  int32_t mouse_x;
  int32_t mouse_y;
} TermboxEvent;

typedef struct TermboxCell {
  String text;
  uintattr_t foreground;
  uintattr_t background;
} TermboxCell;

#pragma private

#include <errno.h>
#include <signal.h>
#include <stdint.h>
#include <string.h>
#include <time.h>
#include <wchar.h>
#include <wctype.h>

/*  One cell holds one grapheme cluster, and eight codepoints is well past a
    base character plus its combining marks. */
#define TERMBOX_CLUSTER_MAX 8

struct Termbox {
  int open;
  int has_previous_winch;
  struct sigaction previous_winch;
};

static Termbox _termbox_active = NULL;

static int _termbox_errno_code(int code) {
  switch (code) {
    case TB_ERR_INIT_OPEN:
    case TB_ERR_READ:
    case TB_ERR_RESIZE_IOCTL:
    case TB_ERR_RESIZE_PIPE:
    case TB_ERR_RESIZE_SIGACTION:
    case TB_ERR_POLL:
    case TB_ERR_TCGETATTR:
    case TB_ERR_TCSETATTR:
    case TB_ERR_RESIZE_WRITE:
    case TB_ERR_RESIZE_POLL:
    case TB_ERR_RESIZE_READ:
      return 1;
  }
  return 0;
}

static void _termbox_native_error(
  String operation, int code, int restore_errno) {
  String message = code == TB_ERR ? %"Termbox operation failed" :
    String.new((char *) tb_strerror(code));
  int error_number = _termbox_errno_code(code) ? tb_last_errno() : 0;
  if (restore_errno) {
    String restore_message = String.new(strerror(restore_errno));
    raise %(term-error (library "termbox2")
            (operation $operation) (code $code) (message $message)
            (rest-errno $restore_errno)
            (rest-msg $restore_message));
  }
  if (error_number) {
    String errno_message = String.new(strerror(error_number));
    raise %(term-error (library "termbox2")
            (operation $operation) (code $code) (message $message)
            (errno $error_number) (errno-msg $errno_message));
  }
  raise %(term-error (library "termbox2")
          (operation $operation) (code $code) (message $message));
}

static void _termbox_signal_error(String operation, int error_number) {
  String message = String.new(strerror(error_number));
  raise %(io-fail (library "termbox2") (operation $operation)
          (signal "SIGWINCH") (errno $error_number)
          (message $message));
}

static void _termbox_save_winch(struct sigaction *previous) {
  if (sigaction(SIGWINCH, NULL, previous) == 0) return;
  int error_number = errno;
  _termbox_signal_error(%"save SIGWINCH", error_number);
}

static int _termbox_restore_winch(struct sigaction *previous) {
  if (sigaction(SIGWINCH, previous, NULL) == 0) return 0;
  return errno;
}

static void _termbox_require(Termbox terminal, String operation) {
  if (terminal && terminal.open && terminal == _termbox_active) return;
  raise %(bad-state (library "termbox2") (operation $operation)
          (reason "closed, null, or inactive Termbox"));
}

Termbox Termbox.open(void) {
  if (_termbox_active) {
    raise %(bad-state (library "termbox2") (operation "init")
            (reason "the process-global terminal is already owned"));
  }

  Termbox terminal = Scope.calloc(1, sizeof(struct Termbox));
  struct sigaction previous = { 0 };
  _termbox_save_winch(&previous);
  int result = tb_init();
  if (result < 0) {
    int restore_errno = _termbox_restore_winch(&previous);
    _termbox_native_error(%"init", result, restore_errno);
  }
  terminal.open = 1;
  terminal.has_previous_winch = 1;
  terminal.previous_winch = previous;
  _termbox_active = terminal;
  return terminal;
}

Termbox Termbox.close(Termbox terminal) {
  if (!terminal || !terminal.open) return NULL;
  if (terminal != _termbox_active) {
    raise %(bad-state (library "termbox2") (operation "shutdown")
            (reason "Termbox does not own the active terminal"));
  }

  int result = tb_shutdown();
  int restore_errno = terminal.has_previous_winch ?
    _termbox_restore_winch(&terminal.previous_winch) : 0;
  terminal.open = 0;
  terminal.has_previous_winch = 0;
  _termbox_active = NULL;

  if (result < 0) {
    _termbox_native_error(%"shutdown", result, restore_errno);
  }
  if (restore_errno) {
    _termbox_signal_error(%"restore SIGWINCH", restore_errno);
  }
  return NULL;
}

static int _termbox_result(String operation, int result) {
  if (result < 0) _termbox_native_error(operation, result, 0);
  return result;
}

int Termbox.width(Termbox terminal) {
  _termbox_require(terminal, %"width");
  return _termbox_result(%"width", tb_width());
}

int Termbox.height(Termbox terminal) {
  _termbox_require(terminal, %"height");
  return _termbox_result(%"height", tb_height());
}

Termbox Termbox.clear(Termbox terminal) {
  _termbox_require(terminal, %"clear");
  _termbox_result(%"clear", tb_clear());
  return terminal;
}

Termbox Termbox.present(Termbox terminal) {
  _termbox_require(terminal, %"present");
  _termbox_result(%"present", tb_present());
  return terminal;
}

Termbox Termbox.hide_cursor(Termbox terminal) {
  _termbox_require(terminal, %"hide_cursor");
  _termbox_result(%"hide_cursor", tb_hide_cursor());
  return terminal;
}

Termbox Termbox.set_cursor(Termbox terminal, int x, int y) {
  _termbox_require(terminal, %"set_cursor");
  _termbox_result(%"set_cursor", tb_set_cursor(x, y));
  return terminal;
}

int Termbox.set_input_mode(Termbox terminal, int mode) {
  _termbox_require(terminal, %"set_input_mode");
  return _termbox_result(%"set_input_mode", tb_set_input_mode(mode));
}

int Termbox.set_output_mode(Termbox terminal, int mode) {
  _termbox_require(terminal, %"set_output_mode");
  return _termbox_result(%"set_output_mode", tb_set_output_mode(mode));
}

int Termbox.print(
  Termbox terminal, int x, int y, String text, uintattr_t foreground,
  uintattr_t background) {
  _termbox_require(terminal, %"print");
  size_t width = 0;
  int result = tb_print_ex(
    x, y, foreground, background, &width, text ? text : ""
  );
  _termbox_result(%"print", result);
  return (int) width;
}

/*  Read text the way tb_print_ex renders it: an invalid byte sequence and a
    non-printable codepoint both become U+FFFD, a newline advances no column,
    and every column width comes from the same host wcwidth termbox itself
    draws with. Returns the column width, stores the first `limit` codepoints
    in `cluster`, and reports every decoded codepoint through `count`. */
static int _termbox_scan(
  String text, String operation, uint32_t *cluster, int limit, int *count) {
  const char *cursor = text ? text : "";
  int width = 0, decoded = 0;
  while (*cursor) {
    uint32_t unicode = 0;
    int step = tb_utf8_char_to_unicode(&unicode, cursor);
    if (step == 0) break;
    if (step < 0) {
      unicode = 0xfffd;
      step = -step;
    }
    cursor += step;
    if (unicode == '\n') continue;
    if (!iswprint((wint_t) unicode)) unicode = 0xfffd;
    int cells = wcwidth((wchar_t) unicode);
    if (cells < 0) {
      _termbox_native_error(operation, TB_ERR, 0);
    }
    width += cells;
    if (decoded < limit) cluster[decoded] = unicode;
    decoded++;
  }
  if (count) *count = decoded;
  return width;
}

int Termbox.measure(String text) {
  return _termbox_scan(text, %"measure", NULL, 0, NULL);
}

/*  Repeat one grapheme cluster over a rectangle. The origin must be on the
    screen, as it must for print; the extent is clipped to the screen, and a
    wide cluster stops before a column it could only half occupy. */
Termbox Termbox.fill(
  Termbox terminal, int x, int y, int width, int height, String character,
  uintattr_t foreground, uintattr_t background) {
  _termbox_require(terminal, %"fill");
  uint32_t cluster[TERMBOX_CLUSTER_MAX];
  int count = 0;
  int step = _termbox_scan(
    character, %"fill", cluster, TERMBOX_CLUSTER_MAX, &count
  );
  if (step < 1 || count < 1 || count > TERMBOX_CLUSTER_MAX) {
    raise %(bad-arg (library "termbox2") (operation "fill")
            (reason "want one printable grapheme cluster")
            (character $character));
  }

  int columns = terminal.width(), rows = terminal.height();
  if (x < 0 || y < 0 || x >= columns || y >= rows) {
    _termbox_native_error(%"fill", TB_ERR_OUT_OF_BOUNDS, 0);
  }
  int last_column = x + width > columns ? columns : x + width;
  int last_row = y + height > rows ? rows : y + height;
  for (int row = y; row < last_row; row++)
    for (int column = x; column + step <= last_column; column += step)
      _termbox_result(%"fill", tb_set_cell_ex(
        column, row, cluster, (size_t) count, foreground, background
      ));
  return terminal;
}

/*  A single-line frame in the Unicode box-drawing block. */
Termbox Termbox.box(
  Termbox terminal, int x, int y, int width, int height, uintattr_t foreground,
  uintattr_t background) {
  _termbox_require(terminal, %"box");
  if (width < 2 || height < 2) {
    raise %(bad-arg (library "termbox2") (operation "box")
            (reason "a frame needs at least two columns and two rows")
            (width $width) (height $height));
  }

  int right = x + width - 1, bottom = y + height - 1;
  String horizontal = %"\xe2\x94\x80", vertical = %"\xe2\x94\x82";
  terminal.fill(x + 1, y, width - 2, 1, horizontal, foreground, background);
  terminal.fill(
    x + 1, bottom, width - 2, 1, horizontal, foreground, background
  );
  terminal.fill(x, y + 1, 1, height - 2, vertical, foreground, background);
  terminal.fill(
    right, y + 1, 1, height - 2, vertical, foreground, background
  );
  terminal.fill(x, y, 1, 1, %"\xe2\x94\x8c", foreground, background);
  terminal.fill(right, y, 1, 1, %"\xe2\x94\x90", foreground, background);
  terminal.fill(x, bottom, 1, 1, %"\xe2\x94\x94", foreground, background);
  terminal.fill(right, bottom, 1, 1, %"\xe2\x94\x98", foreground, background);
  return terminal;
}

/*  tb_utf8_unicode_to_char writes up to six bytes plus a NUL, so every call
    gets the char[7] upstream asks for. tb_extend_cell grows nech without a
    limit, so the cluster is assembled in a Buffer and comes back whole
    instead of being cut short at a fixed size. */
static String _termbox_cell_text(struct tb_cell *cell) {
  char bytes[7];
  if (cell->nech == 0) {
    int length = tb_utf8_unicode_to_char(bytes, cell->ch);
    return String.new_len(bytes, length > 0 ? length : 0);
  }
  Buffer text = Buffer.new(0).reserve(cell->nech * sizeof(bytes));
  uint32_t *cluster = cell->ech;
  for (size_t index = 0; index < cell->nech; index++) {
    int step = tb_utf8_unicode_to_char(bytes, cluster[index]);
    if (step > 0) text.write_len(bytes, (size_t) step);
  }
  return text.str_free();
}

/*  Copy back what the last draw put in the cell. The back buffer is the one
    a later present sends, so this reads what was drawn, not what is lit. */
TermboxCell Termbox.cell(Termbox terminal, int x, int y) {
  _termbox_require(terminal, %"cell");
  int columns = terminal.width(), rows = terminal.height();
  if (x < 0 || y < 0 || x >= columns || y >= rows) {
    _termbox_native_error(%"cell", TB_ERR_OUT_OF_BOUNDS, 0);
  }
  struct tb_cell *cells = tb_cell_buffer();
  if (!cells) {
    _termbox_native_error(%"cell", TB_ERR_NOT_INIT, 0);
  }

  struct tb_cell *cell = &cells[y * columns + x];
  TermboxCell copy = {
    .text = _termbox_cell_text(cell),
    .foreground = cell->fg,
    .background = cell->bg
  };
  return copy;
}

static TermboxEvent _termbox_copy_event(struct tb_event *native) {
  TermboxEvent event = {
    .present = 1,
    .type = native->type,
    .modifiers = native->mod,
    .native_key = native->key,
    .resize_width = native->w,
    .resize_height = native->h,
    .mouse_x = native->x,
    .mouse_y = native->y
  };
  if (native->type == TB_EVENT_KEY && native->ch) {
    char bytes[8] = { 0 };
    int length = tb_utf8_unicode_to_char(bytes, native->ch);
    if (length > 0) event.input_text = String.new_len(bytes, length);
  }
  return event;
}

static long long _termbox_monotonic_ns(void) {
  struct timespec now;
  if (clock_gettime(CLOCK_MONOTONIC, &now) == 0) {
    return (long long) now.tv_sec * 1000000000LL + now.tv_nsec;
  }
  int error_number = errno;
  String message = String.new(strerror(error_number));
  raise %(io-fail (library "termbox2") (operation "clock_gettime")
          (errno $error_number) (message $message));
}

static TermboxEvent _termbox_read(Termbox terminal, int wait, int timeout_ms) {
  TermboxEvent empty = { 0 };
  String operation = wait ? %"poll_event" : %"peek_event";
  _termbox_require(terminal, operation);

  long long deadline = 0;
  int remaining_ms = timeout_ms;
  if (!wait && timeout_ms >= 0) {
    deadline = _termbox_monotonic_ns() +
      (long long) timeout_ms * 1000000LL;
  }

  while (1) {
    struct tb_event native = { 0 };
    int result = wait ? tb_poll_event(&native) :
                        tb_peek_event(&native, remaining_ms);
    if (result == TB_ERR_NO_EVENT) return empty;
    if (result == TB_ERR_POLL && tb_last_errno() == EINTR) {
      if (wait || timeout_ms < 0) continue;
      long long now = _termbox_monotonic_ns();
      long long remaining = deadline - now;
      if (remaining <= 0) return empty;
      remaining_ms = (int) ((remaining + 999999LL) / 1000000LL);
      continue;
    }
    if (result < 0) {
      _termbox_native_error(operation, result, 0);
    }
    return _termbox_copy_event(&native);
  }
}

TermboxEvent Termbox.poll(Termbox terminal) {
  return _termbox_read(terminal, 1, -1);
}

TermboxEvent Termbox.peek(Termbox terminal, int timeout_ms) {
  return _termbox_read(terminal, 0, timeout_ms);
}

int TermboxEvent.available(TermboxEvent event) {
  return event.present;
}

int TermboxEvent.is_key(TermboxEvent event) {
  return event.present && event.type == TB_EVENT_KEY;
}

int TermboxEvent.is_resize(TermboxEvent event) {
  return event.present && event.type == TB_EVENT_RESIZE;
}

int TermboxEvent.is_mouse(TermboxEvent event) {
  return event.present && event.type == TB_EVENT_MOUSE;
}

int TermboxEvent.has_modifier(TermboxEvent event, int modifier) {
  return event.present && (event.modifiers & modifier) != 0;
}

uint16_t TermboxEvent.key(TermboxEvent event) {
  return event.present ? event.native_key : 0;
}

String TermboxEvent.text(TermboxEvent event) {
  return event.present ? event.input_text : NULL;
}

int TermboxEvent.width(TermboxEvent event) {
  return event.present ? event.resize_width : 0;
}

int TermboxEvent.height(TermboxEvent event) {
  return event.present ? event.resize_height : 0;
}

int TermboxEvent.x(TermboxEvent event) {
  return event.present ? event.mouse_x : 0;
}

int TermboxEvent.y(TermboxEvent event) {
  return event.present ? event.mouse_y : 0;
}
