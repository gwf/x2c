/*  report.x -- Command progress and completion receipts.

    Copyright (c) 2026 Gary William Flake.

    The reporter writes only to stderr. Its transient mode uses one carriage-
    return line and never takes terminal input or changes terminal modes.
    Processes sharing a terminal, such as parallel Make recipes, take turns
    owning that line through a lock on the terminal device.
*/

#pragma once

#pragma private

#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/file.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <sys/uio.h>
#include <time.h>
#include <unistd.h>

#include "process.x"

// reporter state

/* One process-global state holds the transient line. The driver configures it
   before dispatch; diagnostics, tool output, and stable receipts suspend the
   line before writing to stderr. `width` is the length of the drawn line, and
   zero when none is drawn. */
static struct ReportState {
  int receipts, transient, color, columns, width, terminal, owner;
  pid_t pid;
  unsigned long start, update;
} report;

// configuration

/** Resets process reporting for one command.
    Quiet, verbose, dry-run, and inspection modes disable receipts. Transient
    progress additionally requires terminal stderr and non-plain output.
    Plain output disables color; automatic color respects terminal capability
    and `NO_COLOR`.
*/
void report_configure(
  int quiet, int plain, Symbol color_mode, int verbose, int dry_run,
  int inspecting) {
  report = (struct ReportState) {.terminal = -1, .pid = getpid()};
  int terminal = _terminal();
  int diagnostic = verbose || dry_run || inspecting;
  report.receipts = !quiet && !diagnostic;
  report.transient = report.receipts && terminal && !plain;
  report.columns = _columns();
  report.start = report_now_us();
  report.color = _use_color(plain, color_mode, terminal);
}

static int _terminal(void) =>
  isatty(fileno(stderr)) && Env.get("TERM") != "dumb";

static int _columns(void) {
  struct winsize size;
  if (ioctl(fileno(stderr), TIOCGWINSZ, &size) == 0 && size.ws_col > 0)
    return size.ws_col;
  String columns = Env.get("COLUMNS");
  int parsed = columns.is_digit() ? atoi(columns) : 0;
  return parsed >= 20 && parsed <= 1000 ? parsed : 80;
}

static int _use_color(int plain, Symbol mode, int terminal) {
  if (plain || mode == <never>) return 0;
  if (mode == <always>) return 1;
  return terminal && !Env.get("NO_COLOR");
}

/** Returns whether stable completion receipts are currently enabled. */
int report_receipts(void) => report.receipts;

/** Reports whether a parent Make recipe runs this process, which `MAKELEVEL`
    set to a positive count shows. Parallel recipes share one terminal and
    one job budget without sharing reporter state.
*/
int report_make_owned(void) {
  String level = Env.get("MAKELEVEL");
  return level.is_digit() && atol(level) > 0;
}

// the progress line

enum { BAR_WIDTH = 14 };

/** Updates the terminal's transient progress line when transient mode is
    active. Updates start after 125 ms and incomplete work is limited to one
    update per 50 ms. `detail` may be NULL; output is clipped to the configured
    terminal width and has no newline.
*/
void report_progress(Symbol phase, int done, int total, String detail) {
  if (!report.transient) return;
  unsigned long now = report_now_us();
  if (!_update_due(now, done, total)) return;
  report.update = now;
  if (_own_line()) _draw(phase, done, total, detail);
}

/* Finished work redraws only a line this process drew. */
static int _update_due(unsigned long now, int done, int total) {
  if (now - report.start < 125000ul) return 0;
  if (done >= total && !report.width) return 0;
  if (report.update && now - report.update < 50000ul && done < total) return 0;
  return 1;
}

/* Takes the terminal's transient line, or reports that another process
   holds it. The lock lives on a separate open of the terminal because
   processes that inherit stderr share one lock owner. */
static int _own_line(void) {
  if (report.owner) return 1;
  if (report.terminal == -1) {
    char *path = ttyname(fileno(stderr));
    int fd = path ? open(path, O_RDONLY | O_NOCTTY | O_CLOEXEC) : -1;
    report.terminal = fd >= 0 ? fd : -2;
  }
  report.owner =
    report.terminal >= 0 && !flock(report.terminal, LOCK_EX | LOCK_NB);
  return report.owner;
}

static void _draw(Symbol phase, int done, int total, String detail) {
  char bar[BAR_WIDTH + 1];
  _fill_bar(bar, done, total);
  char line[2048], String name = phase.str().capitalize();
  snprintf(
    line, sizeof(line), "%s [%s] %d/%d  %s",
    name, bar, done, total, detail ? detail : "");
  int length = _clip(line, report.columns > 1 ? report.columns - 1 : 79);
  _emit(_clear, sizeof(_clear) - 1, _color(<phase>), line, 0);
  report.width = length;
}

static void _fill_bar(char *bar, int done, int total) {
  int filled = total > 0 ? done * BAR_WIDTH / total : 0;
  if (filled < 0) filled = 0;
  if (filled > BAR_WIDTH) filled = BAR_WIDTH;
  for (int i = 0; i < BAR_WIDTH; i++) bar[i] = i < filled ? '#' : '-';
  bar[BAR_WIDTH] = 0;
}

/* Cuts `line` to at most `limit` bytes and returns its length. */
static int _clip(char *line, int limit) {
  int length = (int) strlen(line);
  if (length <= limit) return length;
  line[limit] = 0;
  return limit;
}

/** Clears the active transient line from stderr, if this process drew one.
    Forked workers inherit the state but leave the line to their parent.
*/
void report_suspend(void) {
  if (!report.width || getpid() != report.pid) return;
  report.width = 0;
  _emit(_clear, sizeof(_clear) - 1, "", "", 0);
}

// receipts

/** Writes one newline-terminated receipt to stderr when receipts are enabled.
    In transient mode the receipt first clears the terminal line, which
    another process may be drawing, and `line` must be non-NULL.
*/
void report_line(Symbol tone, String line) {
  report.width = 0;
  if (!report.receipts) return;
  int clear = report.transient ? sizeof(_clear) - 1 : 0;
  _emit(_clear, clear, _color(tone), line, 1);
}

/** Writes a muted phase receipt when receipts are enabled.
    A fully cached nonempty phase is marked up to date; a partial cache reports
    its cached count, and every receipt includes the elapsed time.
*/
void report_phase(
  Symbol phase, int count, String noun, int cached,
  unsigned long microseconds) {
  String cache = _cache_note(count, cached);
  String name = phase.str().capitalize();
  String duration = report_duration(microseconds);
  report_line(<muted>, %"  $name $count $noun in $duration$cache");
}

static String _cache_note(int count, int cached) {
  if (cached == count && count) return " (up to date)";
  return cached ? %", $cached cached" : "";
}

// terminal output

// A carriage return, then an erase to the end of the line.
static const char _clear[] = "\r\033[K";

/* Each display update is one writev call, which limits interleaving between
   Make children. Reporting is best effort: it retries only EINTR and never
   changes command status for output failure. */
static void _emit(
  const char *prefix, int prefix_length, const char *color,
  const char *line, int newline) {
  struct iovec parts[5], int count = 0;
  if (prefix_length) parts[count++] = _part(prefix, prefix_length);
  if (*color) parts[count++] = _part(color, strlen(color));
  parts[count++] = _part(line, strlen(line));
  if (*color) parts[count++] = _part("\033[0m", 4);
  if (newline) parts[count++] = _part("\n", 1);
  while (writev(fileno(stderr), parts, count) < 0 && errno == EINTR) {}
}

static struct iovec _part(const char *text, size_t length) =>
  (struct iovec) {.iov_base = (char *) text, .iov_len = length};

static const char *_color(Symbol tone) {
  if (!report.color) return "";
  switch (tone) {
    case <success>: return "\033[32m";
    case <failure>: return "\033[31m";
    case <phase>:   return "\033[36m";
    case <muted>:   return "\033[2m";
    default:        return "";
  }
}

// durations and sizes

/** Returns monotonic time in microseconds, or zero when the clock read fails.
    The value measures elapsed time; it is not a wall-clock timestamp.
*/
unsigned long report_now_us(void) {
  struct timespec now;
  if (clock_gettime(CLOCK_MONOTONIC, &now)) return 0;
  return (unsigned long) now.tv_sec * 1000000ul +
         (unsigned long) now.tv_nsec / 1000ul;
}

/** Returns the size of a regular file.
    NULL, a failed `stat`, or a non-regular path returns zero.
*/
unsigned long long report_file_bytes(String path) {
  struct stat info;
  if (!path || stat(path, &info) || !S_ISREG(info.st_mode)) return 0;
  return (unsigned long long) info.st_size;
}

/** Formats microseconds as integer `us`, rounded whole `ms`, or seconds with
    two decimal places.
*/
String report_duration(unsigned long microseconds) {
  if (microseconds < 1000) return "%lu us".printf(microseconds);
  if (microseconds < 1000000) return "%.0f ms".printf(microseconds / 1000.0);
  return "%.2f s".printf(microseconds / 1000000.0);
}

/** Formats bytes as `B`, `KiB`, or `MiB` using binary unit boundaries.
    Byte counts are exact; larger units use one decimal place.
*/
String report_size(unsigned long long bytes) {
  if (bytes < 1024) return "%llu B".printf(bytes);
  if (bytes < 1024ull * 1024ull) return "%.1f KiB".printf(bytes / 1024.0);
  return "%.1f MiB".printf(bytes / (1024.0 * 1024.0));
}
