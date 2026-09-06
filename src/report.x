/*  report.x -- Command progress and completion receipts.

    Copyright (c) 2026 Gary William Flake.

    The reporter writes only to stderr. Its transient mode uses one carriage-
    return line and never takes terminal input or changes terminal modes.
*/

#pragma once

#pragma private

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <sys/uio.h>
#include <time.h>
#include <unistd.h>

/* One process-global state holds the transient line. The driver configures it
   before dispatch; diagnostics, tool output, and stable receipts suspend the
   line before writing to stderr. */
static struct {
  int receipts, transient, color, columns, width;
  unsigned long start;
  unsigned long update;
} report;

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
  if (microseconds < 1000) return %"%lu us".printf(microseconds);
  if (microseconds < 1000000) return %"%.0f ms".printf(microseconds / 1000.0);
  return %"%.2f s".printf(microseconds / 1000000.0);
}

/** Formats bytes as `B`, `KiB`, or `MiB` using binary unit boundaries.
    Byte counts are exact; larger units use one decimal place.
*/
String report_size(unsigned long long bytes) {
  if (bytes < 1024) return %"%llu B".printf(bytes);
  if (bytes < 1024ull * 1024ull) return %"%.1f KiB".printf(bytes / 1024.0);
  return %"%.1f MiB".printf(bytes / (1024.0 * 1024.0));
}

static int _terminal(void) {
  if (!isatty(fileno(stderr))) return 0;
  const char *term = getenv("TERM");
  return !term || strcmp(term, "dumb") != 0;
}

// Parallel Make recipes share one terminal without sharing reporter state.
// Stable receipts remain useful there, but no child can hold a transient
// line.
static int _make_owned(void) {
  const char *level = getenv("MAKELEVEL");
  if (!level || !*level) return 0;
  char *end = NULL;
  long parsed = strtol(level, &end, 10);
  return end && !*end && parsed > 0;
}

static int _columns(void) {
  struct winsize size;
  if (ioctl(fileno(stderr), TIOCGWINSZ, &size) == 0 && size.ws_col > 0)
    return size.ws_col;
  const char *columns = getenv("COLUMNS");
  if (columns && *columns) {
    char *end = NULL;
    long parsed = strtol(columns, &end, 10);
    if (end && !*end && parsed >= 20 && parsed <= 1000) return (int) parsed;
  }
  return 80;
}

/** Resets process reporting for one command.
    Quiet, verbose, dry-run, and inspection modes disable receipts. Transient
    progress additionally requires terminal stderr, non-plain output, and no
    parent Make recipe. Plain output disables color; automatic color respects
    terminal capability and `NO_COLOR`.
*/
void report_configure(
  int quiet, int plain, Symbol color_mode, int verbose, int dry_run,
  int inspecting) {
  memset(&report, 0, sizeof(report));
  int terminal = _terminal();
  int diagnostic = verbose || dry_run || inspecting;
  report.receipts = !quiet && !diagnostic;
  report.transient =
    report.receipts && terminal && !plain && !_make_owned();
  report.columns = _columns();
  report.start = report_now_us();
  if (plain || color_mode == <never>) report.color = 0;
  else if (color_mode == <always>) report.color = 1;
  else report.color = terminal && !getenv("NO_COLOR");
}

/** Returns whether stable completion receipts are currently enabled. */
int report_receipts(void) => report.receipts;

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

static void _emit(
  const char *prefix, int prefix_length, const char *color, String line,
  int newline) {
  /* Issue each display update through one writev call to limit interleaving
     between Make children. Reporting is best effort. Retry only EINTR and
     do not change command status for output failure. */
  struct iovec parts[5], int count = 0;
  if (prefix_length) {
    parts[count].iov_base = (char *) prefix;
    parts[count++].iov_len = (size_t) prefix_length;
  }
  if (*color) {
    parts[count].iov_base = (char *) color;
    parts[count++].iov_len = strlen(color);
  }
  parts[count].iov_base = line;
  parts[count++].iov_len = strlen(line);
  if (*color) {
    parts[count].iov_base = "\033[0m";
    parts[count++].iov_len = 4;
  }
  if (newline) {
    parts[count].iov_base = "\n";
    parts[count++].iov_len = 1;
  }
  while (writev(fileno(stderr), parts, count) < 0 && errno == EINTR) {}
}

static int _clear(char *line, int capacity) {
  if (!report.width) return 0;
  int width = report.width;
  if (width > capacity - 2) width = capacity - 2;
  line[0] = '\r';
  for (int i = 0; i < width; i++) line[i + 1] = ' ';
  line[width + 1] = '\r';
  report.width = 0;
  return width + 2;
}

/** Clears the active transient line from stderr, if one exists. */
void report_suspend(void) {
  if (!report.width) return;
  char clear[1002], int length = _clear(clear, sizeof(clear));
  _emit(clear, length, "", %"", 0);
}

/** Writes one newline-terminated receipt to stderr when receipts are enabled.
    Any active transient line is cleared first, and `line` must be non-NULL.
*/
void report_line(Symbol tone, String line) {
  report_suspend();
  if (!report.receipts) return;
  const char *color = _color(tone);
  _emit(NULL, 0, color, line, 1);
}

/** Updates the terminal's transient progress line when transient mode is
    active. Updates start after 125 ms and incomplete work is limited to one
    update per 50 ms. `detail` may be NULL; output is clipped to the configured
    terminal width and has no newline.
*/
void report_progress(Symbol phase, int done, int total, String detail) {
  if (!report.transient) return;
  unsigned long now = report_now_us();
  if (now - report.start < 125000ul) return;
  if (done >= total && !report.width) return;
  if (report.update && now - report.update < 50000ul && done < total) return;
  report.update = now;

  enum { bar_width = 14 };
  char bar[bar_width + 1];
  int filled = total > 0 ? done * bar_width / total : 0;
  if (filled < 0) filled = 0;
  if (filled > bar_width) filled = bar_width;
  for (int i = 0; i < bar_width; i++) bar[i] = i < filled ? '#' : '-';
  bar[bar_width] = 0;

  char line[2048], String name = phase.str().capitalize();
  snprintf(
    line, sizeof(line), "%s [%s] %d/%d  %s",
    name, bar, done, total, detail ? detail : "");
  int limit = report.columns > 1 ? report.columns - 1 : 79;
  int length = (int) strlen(line);
  if (length > limit) {
    line[limit] = 0;
    length = limit;
  }
  char clear[1002], int clear_length = _clear(clear, sizeof(clear));
  const char *color = _color(<phase>);
  _emit(clear, clear_length, color, line, 0);
  report.width = length;
}

/** Writes a muted phase receipt when receipts are enabled.
    A fully cached nonempty phase is marked up to date; a partial cache reports
    its cached count, and every receipt includes the elapsed time.
*/
void report_phase(
  Symbol phase, int count, String noun, int cached,
  unsigned long microseconds) {
  String cache = cached == count && count ? %" (up to date)" :
                 cached ? %", $cached cached" : %"";
  String name = phase.str().capitalize();
  String line = %"  $name $count $noun in " +
                %"${report_duration(microseconds)}$cache";
  report_line(<muted>, line);
}
