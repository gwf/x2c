# termbox2 client

This experimental package provides an x2c interface to the pinned termbox2
2.5.0 64-bit-attribute, extended-grapheme profile. It is an importable package
whose entry point is `src/termbox2.x`; one live `Termbox` owns the
process-global terminal, drawing takes `String` text and termbox's own
`TB_*` attributes, and input arrives as copied `TermboxEvent` values.

```x2c
import "termbox2" with Termbox;

int main(void) {
  Termbox terminal = Termbox.open();
  defer terminal.close();

  terminal.fill(0, 0, terminal.width(), 1, %" ", TB_BLACK, TB_WHITE);
  terminal.print(0, 0, %"press any key", TB_BLACK, TB_WHITE);
  terminal.box(0, 1, 20, 5, TB_CYAN, TB_DEFAULT);
  terminal.set_cursor(1, 2);
  terminal.present();
  terminal.poll();
  return 0;
}
```

termbox2 is a single header, so `src/termbox2.c` instantiates it once and
`builds/libtermbox2.a` carries both it and the client. The package links no
external library, and `builds/termbox2.link` is empty.

## Drawing

`Termbox.print` draws text and returns the columns it used.
`Termbox.fill(x, y, width, height, character, foreground, background)`
repeats one grapheme cluster over a rectangle in one call, which is how a
status bar spans its row and how a run of identical cells is drawn without a
call per column. The origin must be on the screen, as it must for `print`;
the extent is clipped to the screen, and a wide cluster steps two columns and
stops before a column it could only half occupy. Text with no printable
column raises `<bad-arg>`, and so does a cluster of more than eight
codepoints: `fill` repeats one cluster from a fixed buffer, where `print` and
`cell` carry a cluster of any length.

`Termbox.box` draws a single-line frame from the Unicode box-drawing block
and needs at least two columns and two rows. It is `fill` eight times, so a
frame costs eight calls rather than one per border cell.

`Termbox.measure(text)` returns the column width `print` would report,
without drawing and without an open terminal. It reads text exactly as
`tb_print_ex` renders it: an invalid byte sequence and a non-printable
codepoint both become U+FFFD, a newline advances no column, and every width
comes from the same host `wcwidth` termbox itself draws with. Measuring
off-screen text is the one thing `print` cannot do, because `print` raises
`TB_ERR_OUT_OF_BOUNDS` before it reports a width.

`Termbox.cell(x, y)` copies a cell back out of the back buffer - the buffer a
later `present` sends - as a `TermboxCell` with `text`, `foreground`, and
`background`. Its text is a fresh String holding the whole grapheme cluster,
so it borrows no termbox storage and survives the next draw. Reading outside
the screen raises `TB_ERR_OUT_OF_BOUNDS`.

`Termbox.set_cursor` shows the cursor and moves it; `Termbox.hide_cursor`
takes it away again.

## Input

`Termbox.poll` blocks and `Termbox.peek` waits for a timeout; no event is an
ordinary empty `TermboxEvent`, not an error. `TermboxEvent.is_key`,
`is_resize`, and `is_mouse` name the three kinds. A key event carries `key`
and `text`; a resize carries `width` and `height`; a mouse event carries the
`TB_KEY_MOUSE_*` button in `key` and the click's zero-based column and row in
`x` and `y`. `has_modifier(TB_MOD_ALT)` reports an Alt-modified key when the
input mode admits it. Mouse events need `TB_INPUT_MOUSE` in the input mode.

## Examples

From the repository root, build the packages and play Game of Life:

```sh
make packages
./packages/termbox2/builds/game-of-life
```

This builds the example without running tests or requiring Expect. To build
and play only Game of Life after building x2c, use
`make -C packages/termbox2 run-life-interactive`.

`examples/game-of-life.x` is the short application (`make short-example`). It
runs toroidal Life over the terminal's own cells: two ordinary
x2c Arrays hold the generations, modular Array indexes give the wraparound,
and each drawn row becomes one `fill` call per run of live cells. Any key
quits. Each cell starts alive with 50% probability; resizing starts a fresh
random world using the new terminal dimensions. `make run-life-interactive`
plays it.

`examples/incident-filter.x` is the broader application (`make example`). It
reads `examples/incidents.log` through `File`, keeps each incident as
ordinary x2c Strings in a List, and filters severity, service, and UTF-8 text
as you type. Each key event contributes one complete scalar String to an
Array; `Array.join` forms the filter and `Array.pop` removes one whole input
event on backspace. A full-width title bar and status bar are single `fill`
calls, a `box` frames the list and is drawn last so a long line is clipped by
the border, `set_cursor` puts the caret after the typed filter, and a left
mouse click selects a row. `make run-interactive` runs it.

The application initializes the process's C character locale from the user's
environment before opening termbox. termbox uses the host `iswprint` and
`wcwidth` functions for Unicode rendering; the client does not silently
change that second process-global setting.

Escape and Ctrl-C are normal quit paths. The fixture is opened after the
terminal, so a handled `<not-found>` or `<io-fail>` result unwinds through the
adjacent `defer terminal.close()` before the diagnostic is printed.

## No Lisp surface

`Termbox` is a process-global terminal handle, and every value it produces -
an event, a cell, a column count - is meaningful only while that one terminal
is open and only to the program driving it. There is no value-oriented
surface for Lisp to operate on, so this package has no Lisp bindings.

## Ownership, copying, and cleanup

termbox has one process-global terminal. `Termbox.open` creates its only live
x2c owner, and a second open raises `<bad-state>` before another `tb_init`
call. It is neither reentrant nor thread-safe. The x2c record is Scope-owned.
`Termbox.close` releases native terminal state and may be repeated while the
record remains in scope.

termbox replaces the process's `SIGWINCH` disposition with `SIG_DFL` during
both successful shutdown and failed initialization cleanup. The client saves
the caller's complete prior disposition before every open attempt and restores
it after failure, allocation cleanup, successful close, or shutdown error.

Poll and peek copy every admitted native event field. A key event's Unicode
scalar is converted immediately into a canonical UTF-8 x2c String, so neither
the event nor its text borrows termbox memory. `TB_ERR_NO_EVENT` returns an
empty event. `TB_ERR_POLL` with `EINTR` is retried against the original timed
peek deadline rather than starting another complete timeout. Other native
failures raise `<term-error>` with the upstream operation and code. Codes
that establish `tb_last_errno()` include its errno and message; generic
`TB_ERR` does not reuse unrelated errno state or its derived message.

x2c String remains a NUL-terminated byte String, not a Unicode index or
grapheme type. `Termbox.print` passes its UTF-8 bytes to `tb_print_ex`; the
pinned EGC implementation groups combining codepoints in cells and reports
terminal-cell width. Starting inside the screen uses termbox's right-edge
clipping. Starting outside it raises with `TB_ERR_OUT_OF_BOUNDS`.

## Native API and deliberate limits

`src/termbox2-2.5.h` checks the admitted version shape, attribute ABI, and EGC
profile, then includes the real pinned upstream header. It exposes termbox2's
complete types, constants, callbacks, status values, macros, and functions
without copied declarations or forwarding calls, and the generated
`builds/termbox2.h` publishes it. An import makes raw `tb_*` names available
to x2c; the consumer build must also provide the prepared prefix through
`--c-system-dir`, as this package's Makefile does. `src/termbox2.c`
instantiates that single header once.

File-descriptor and split read/write initialization, raw cell-buffer
mutation, custom allocation and I/O, `tb_send*`, custom event extraction, and
alternate screen control remain raw. Suspending with `SIGTSTP` and restoring
the terminal after `SIGCONT` also remains a raw application responsibility.
Mixing raw `tb_init` or `tb_shutdown` with a live `Termbox` invalidates the
ordinary owner; subsequent operations raise the native termbox failure and
`Termbox.close` still restores the saved `SIGWINCH` disposition.

`PROFILE.md` records the archive, header, platform, and two distinct upstream
MIT notices. The release root `LICENSE` and the header-embedded notice have
different copyright holders, so both exact texts are retained.

## Build and test

The dependency header is prepared in the shared integration cache. `make
clean` removes only worktree-local products under `builds/` and the `deps`
symlink.

```sh
make verify-profile
make build
make test
make run
```

`make test` runs every suite through `tests/run-test.expect`, which gives one
test program a deterministic pseudo-terminal and answers the `READY` lines it
prints. That covers exclusive ownership, failed-init cleanup, repeated close,
one deadline across repeated interruptions, generic status reporting,
event/failure outcomes, copied event text, EGC and wide-cell width, clipping,
resize state, mouse button and coordinates, fill stepping and read-back, box
corners and edges, measurement against print, cursor motion in the emitted
output, tty restoration, prior `SIGWINCH` restoration, and native error detail.
The raw test calls representative declarations through the real pinned header.

`make run` drives both applications under a deterministic pseudo-terminal and
retains their raw transcripts under `builds/`.
