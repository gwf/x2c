/*  time.x -- clocks, durations, and calendar time

    Copyright (c) 2026 Gary William Flake

    A `Time` is an instant counted in nanoseconds from the Unix epoch, and a
    `Duration` is a signed count of nanoseconds; each holds one 64-bit
    count, so each spans about 292 years either side of zero. Calendar
    fields come from `gmtime_r` for UTC and `localtime_r` for the C
    library's local zone; there is no time zone database. Formatting
    defaults to UTC, and `strftime` names follow the `C` locale.
*/

#pragma once
#include "x2c.x"

/** A signed span of time in whole nanoseconds. `+`, `-`, unary `-`, and
    the comparison operators work on two Durations; arithmetic that leaves
    the 64-bit range raises `<conv-range>`.
*/
class Duration { long long nanoseconds; };

/** An instant, in nanoseconds since 1970-01-01T00:00:00Z without leap
    seconds, as POSIX counts time. The comparison operators order two Times.
*/
class Time { long long nanoseconds; };

/** The calendar fields of an instant in one zone. `month` and `day` count
    from 1, and `utc_offset` is the zone's offset east of UTC in seconds.
    `Time.utc` and `Time.local` fill every field.
*/
class DateTime {
  int year, month, day, hour, minute, second, nanosecond, utc_offset;
};

#include <errno.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#define NANOS 1000000000LL

/* One parse of `text`; `at` is the byte being read. */
static typedef struct Reader {
  const char *text;
  int at;
} Reader;

// durations

/** Returns `seconds` as a Duration, rounded to the nearest nanosecond.
    Raises: `<conv-range>` when `seconds` is not finite or the Duration
    cannot represent it.
*/
Duration Duration.seconds(double seconds) =>
  Duration.new(_from_seconds("Duration.seconds", seconds));

/** Returns `count` milliseconds as a Duration.
    Raises: `<conv-range>` when the Duration cannot represent it.
*/
Duration Duration.milliseconds(long long count) =>
  Duration.new(_product("Duration.milliseconds", count, 1000000));

/** Returns `count` microseconds as a Duration.
    Raises: `<conv-range>` when the Duration cannot represent it.
*/
Duration Duration.microseconds(long long count) =>
  Duration.new(_product("Duration.microseconds", count, 1000));

/** Returns `d` in seconds, with its fraction. */
double Duration.total_seconds(Duration d) => d.nanoseconds / 1e9;

/** Returns `d` in whole milliseconds, truncated toward zero. */
long long Duration.total_milliseconds(Duration d) =>
  d.nanoseconds / 1000000;

/** Returns the sum of two Durations; `a + b` calls it.
    Raises: `<conv-range>` when the sum leaves the 64-bit range.
*/
Duration Duration.add(Duration a, Duration b) =>
  Duration.new(_sum("Duration.add", a.nanoseconds, b.nanoseconds));

/** Returns `a` less `b`; `a - b` calls it.
    Raises: `<conv-range>` when the difference leaves the 64-bit range.
*/
Duration Duration.sub(Duration a, Duration b) =>
  Duration.new(_difference("Duration.sub", a.nanoseconds, b.nanoseconds));

/** Returns `d` with its sign reversed; `-d` calls it.
    Raises: `<conv-range>` for the most negative Duration.
*/
Duration Duration.neg(Duration d) =>
  Duration.new(_difference("Duration.neg", 0, d.nanoseconds));

/** Returns `d` multiplied by `factor`, rounded to the nearest nanosecond.
    Raises: `<conv-range>` when the product is not finite or leaves the
    range.
*/
Duration Duration.scale(Duration d, double factor) {
  if (factor >= -0x1p63 && factor < 0x1p63 && trunc(factor) == factor)
    return Duration.new(_product("Duration.scale", d.nanoseconds,
                                 (long long) factor));
  return Duration.new(_from_seconds("Duration.scale", d.total_seconds() * factor));
}

/** Orders two Durations: negative, zero, or positive as `a` is shorter,
    equal, or longer. `<`, `<=`, `>`, and `>=` call it.
*/
int Duration.compare(Duration a, Duration b) =>
  _order(a.nanoseconds, b.nanoseconds);

/** Returns `d` in the units Go prints: `1h2m3.5s`, `1m30s`, `2.5ms`,
    `750us`, `12ns`, or `0s`. The fraction keeps every significant digit
    and no trailing zero. Interpolation prints a Duration this way.
*/
String Duration.str(Duration d) {
  if (!d.nanoseconds) return "0s";
  Buffer out = auto Buffer.new(0);
  unsigned long long size = d.nanoseconds;
  if (d.nanoseconds < 0) {
    out.write_char('-');
    size = -size;
  }
  if (size < 1000) out.printf("%lluns", size);
  else if (size < 1000000) _fixed(out, size, 1000, "us");
  else if (size < NANOS) _fixed(out, size, 1000000, "ms");
  else _clock(out, size);
  return out;
}

// clocks

/** Returns the current wall-clock time from `CLOCK_REALTIME`. The clock can
    jump when the system time is set; measure intervals with
    `Time.monotonic`.
*/
Time Time.now(void) => Time.new(_read_clock(CLOCK_REALTIME));

/** Returns the monotonic clock's reading as the Duration since an
    unspecified starting point. The reading never decreases, so the
    difference of two readings measures elapsed time.

    ```x2c
    ~#include "time.x"
    ~int main(void) {
    Duration start = Time.monotonic();
    Time.sleep(Duration.milliseconds(5));
    Duration elapsed = Time.monotonic() - start;
    ~  return elapsed >= Duration.milliseconds(5) ? 0 : 1;
    ~}
    ```
*/
Duration Time.monotonic(void) => Duration.new(_read_clock(CLOCK_MONOTONIC));

/** Suspends the calling thread for at least `d`, resuming after an
    interrupting signal until the whole span has passed. A Duration that is
    not positive returns at once.
*/
void Time.sleep(Duration d) {
  if (d.nanoseconds <= 0) return;
  struct timespec pending = {d.nanoseconds / NANOS, d.nanoseconds % NANOS};
  while (nanosleep(&pending, &pending) && errno == EINTR) {}
}

/** Returns the instant `seconds` after the Unix epoch, the count that
    `Path.modified_time` and C's `time` report.
    Raises: `<conv-range>` when `seconds` is not finite or out of range.
*/
Time Time.from_unix(double seconds) =>
  Time.new(_from_seconds("Time.from_unix", seconds));

/** Returns `t` in seconds since the Unix epoch, with its fraction. */
double Time.unix_seconds(Time t) => t.nanoseconds / 1e9;

/** Returns the instant `d` after `t`; a negative `d` moves earlier.
    Raises: `<conv-range>` when the result leaves the 64-bit range.
*/
Time Time.plus(Time t, Duration d) =>
  Time.new(_sum("Time.plus", t.nanoseconds, d.nanoseconds));

/** Returns the Duration from `earlier` to `t`, negative when `earlier` is
    the later instant.
    Raises: `<conv-range>` when the span leaves the 64-bit range.
*/
Duration Time.since(Time t, Time earlier) =>
  Duration.new(_difference("Time.since", t.nanoseconds, earlier.nanoseconds));

/** Orders two instants: negative, zero, or positive as `a` is earlier,
    the same, or later. `<`, `<=`, `>`, and `>=` call it.
*/
int Time.compare(Time a, Time b) => _order(a.nanoseconds, b.nanoseconds);

// calendar time

/** Returns `t` as an RFC 3339 timestamp in UTC, such as
    `2026-10-28T14:05:09.25Z`. The fraction keeps every significant digit
    and is omitted when zero. Interpolation prints a Time this way.
*/
String Time.str(Time t) => t.utc();

/** Returns the instant an RFC 3339 timestamp names, such as
    `2026-10-28T14:05:09Z` or `2026-10-28 10:05:09.250-04:00`. The date and
    time may be separated by `T`, `t`, or a space, and the offset is `Z`,
    `z`, `+hh:mm`, or `-hh:mm`. Digits finer than a nanosecond are dropped.
    POSIX time has no leap seconds, so a second of 60 is out of range.
    Raises: `<malformed>` with `reason` and byte `offset` when `text` is not
    such a timestamp or names a day its month does not have, and
    `<conv-range>` when the instant is outside the Time range.
*/
Time Time.parse(String text) {
  Reader r = {.text = text ? text : ""};
  DateTime d = {0};
  d.year = _digits(r, 4);
  d.month = _field(r, '-', 1, 12);
  d.day = _field(r, '-', 1, _month_days(d.year, d.month));
  _expect(r, "Tt ", "expected 'T' between the date and the time");
  d.hour = _digits_within(r, 0, 23);
  d.minute = _field(r, ':', 0, 59);
  d.second = _field(r, ':', 0, 59);
  d.nanosecond = _nanoseconds(r);
  d.utc_offset = _zone(r);
  if (r.text[r.at]) _malformed(r, "unexpected text after the offset");
  return d;
}

/** Formats `t` in UTC with the `strftime` conversions in `pattern`, as
    `t.format("%a, %d %b %Y %H:%M:%S GMT")` writes an HTTP date. A pattern
    whose output is empty returns `""`.
*/
String Time.format(Time t, String pattern) =>
  _strftime(_broken_down(t, gmtime_r), pattern);

/** Formats `t` in the C library's local zone, which the `TZ` environment
    variable selects, with the `strftime` conversions in `pattern`.
*/
String Time.format_local(Time t, String pattern) {
  tzset();
  return _strftime(_broken_down(t, localtime_r), pattern);
}

/** Returns the UTC calendar fields of `t`. */
DateTime Time.utc(Time t) => _fields(t, _broken_down(t, gmtime_r));

/** Returns the calendar fields of `t` in the C library's local zone, which
    the `TZ` environment variable selects, with that zone's offset at `t`.
*/
DateTime Time.local(Time t) {
  tzset();
  return _fields(t, _broken_down(t, localtime_r));
}

/** Returns the instant that the fields of `d` name at its `utc_offset`;
    a DateTime converts to a Time this way wherever one is expected. The
    fields need not be normalized: day 32 of January is February 1.
    Raises: `<conv-range>` when the instant is outside the Time range.
*/
Time DateTime.time(DateTime d) {
  long long months = d.year * 12LL + d.month - 1;
  long long year = months >= 0 ? months / 12 : (months - 11) / 12;
  int month = (int) (months - year * 12 + 1);
  long long days = _days_from_civil(year, month) + d.day - 1;
  long long seconds = days * 86400 + d.hour * 3600LL + d.minute * 60LL +
                      d.second - d.utc_offset;
  return Time.new(_combine_seconds("DateTime.time", seconds, d.nanosecond));
}

/** Returns the day of the week of `d`, from 0 for Sunday to 6 for
    Saturday, as `strftime`'s `%w` numbers it.
*/
int DateTime.weekday(DateTime d) {
  long long days = _days_from_civil(d.year, d.month) + d.day - 1;
  return (int) (((days + 4) % 7 + 7) % 7);
}

/** Returns `d` as an RFC 3339 timestamp with its offset, or `Z` for UTC,
    as in `2026-10-28T10:05:09-04:00`.
*/
String DateTime.str(DateTime d) {
  Buffer out = auto Buffer.new(0);
  out.printf("%04d-%02d-%02dT%02d:%02d:%02d", d.year, d.month, d.day,
             d.hour, d.minute, d.second);
  _fraction(out, d.nanosecond, NANOS);
  if (!d.utc_offset) out.write_char('Z');
  else {
    int size = abs(d.utc_offset);
    out.printf("%c%02d:%02d", d.utc_offset < 0 ? '-' : '+', size / 3600,
               size / 60 % 60);
  }
  return out;
}

// checked nanosecond arithmetic

/* Converts whole seconds and the fraction separately, so a count near the
   present keeps its nanoseconds, which a double holding nanoseconds would
   round away. */
static long long _from_seconds(String operation, double seconds) {
  double whole = floor(seconds);
  if (!(fabs(whole) < 1e10))
    raise %(conv-range (operation $operation) (value $seconds));
  long long fraction = (long long) round((seconds - whole) * 1e9);
  long long count = (long long) whole;
  return _combine_seconds(operation, count, fraction);
}

// Align signs before multiplication so a representable boundary stays in range.
static long long _combine_seconds(
  String operation, long long seconds, long long fraction) {
  seconds = _sum(operation, seconds, fraction / NANOS);
  fraction %= NANOS;
  if (seconds < 0 && fraction > 0) {
    seconds++;
    fraction -= NANOS;
  }
  else if (seconds > 0 && fraction < 0) {
    seconds--;
    fraction += NANOS;
  }
  return _sum(operation, _product(operation, seconds, NANOS), fraction);
}

static long long _sum(String operation, long long a, long long b) {
  long long sum;
  if (__builtin_add_overflow(a, b, &sum)) _out_of_range(operation);
  return sum;
}

static long long _product(String operation, long long count, long unit) {
  long long product;
  if (__builtin_mul_overflow(count, (long long) unit, &product))
    _out_of_range(operation);
  return product;
}

static long long _difference(String operation, long long a, long long b) {
  long long difference;
  if (__builtin_sub_overflow(a, b, &difference)) _out_of_range(operation);
  return difference;
}

static void _out_of_range(String operation) {
  raise %(conv-range (operation $operation)
          (reason "outside the 64-bit nanosecond range"));
}

static int _order(long long a, long long b) => (a > b) - (a < b);

// duration text

/* Writes `size / unit` with the significant digits of its remainder, then
   the unit's name. */
static void _fixed(
  Buffer out, unsigned long long size, long unit, const char *name) {
  out.printf("%llu", size / unit);
  _fraction(out, size % unit, unit);
  out.write(name);
}

/* Writes the hours, minutes, and seconds of `size` nanoseconds, omitting
   leading zero fields. */
static void _clock(Buffer out, unsigned long long size) {
  unsigned long long seconds = size / NANOS;
  if (seconds >= 3600) out.printf("%lluh", seconds / 3600);
  if (seconds >= 60) out.printf("%llum", seconds / 60 % 60);
  out.printf("%llu", seconds % 60);
  _fraction(out, size % NANOS, NANOS);
  out.write_char('s');
}

/* Writes `part / unit` as `.digits` without trailing zeros, where `unit`
   is a power of ten; zero writes nothing. */
static void _fraction(Buffer out, unsigned long long part, long unit) {
  if (!part) return;
  int width = 0;
  for (long place = unit; place > 1; place /= 10) width++;
  char digits[16];
  snprintf(digits, sizeof digits, "%0*llu", width, part);
  while (digits[width - 1] == '0') width--;
  out.write_char('.');
  out.write_len(digits, width);
}

// clock readings

static long long _read_clock(clockid_t clock) {
  struct timespec now;
  clock_gettime(clock, &now);
  return now.tv_sec * NANOS + now.tv_nsec;
}

// calendar conversion

static DateTime _fields(Time t, struct tm fields) =>
  DateTime.new(fields.tm_year + 1900, fields.tm_mon + 1, fields.tm_mday,
               fields.tm_hour, fields.tm_min, fields.tm_sec,
               (int) ((t.nanoseconds % NANOS + NANOS) % NANOS),
               (int) fields.tm_gmtoff);

/* The `struct tm` of `t` from `gmtime_r` or `localtime_r`, which convert
   every second a Time can hold. */
static struct tm _broken_down(
  Time t, struct tm *(*convert)(const time_t *, struct tm *)) {
  time_t seconds = _floor_seconds(t);
  struct tm fields;
  convert(&seconds, &fields);
  return fields;
}

static long long _floor_seconds(Time t) {
  long long seconds = t.nanoseconds / NANOS;
  return t.nanoseconds % NANOS < 0 ? seconds - 1 : seconds;
}

/* `strftime` returns zero both for empty output and for a full buffer, so
   the buffer grows until the output must be empty. */
static String _strftime(struct tm fields, String pattern) {
  if (!pattern) return "";
  for (size_t size = 64; size <= 64 * (size_t) (pattern.len() + 1);
       size *= 2) {
    char bytes[size];
    size_t length = strftime(bytes, size, pattern, &fields);
    if (length) return String.new_len(bytes, length);
  }
  return "";
}

/* Days from 1970-01-01 to the first day of `month` in `year`, in the
   proleptic Gregorian calendar, after Howard Hinnant's `days_from_civil`. */
static long long _days_from_civil(long long year, int month) {
  if (month <= 2) year--;
  long long era = (year >= 0 ? year : year - 399) / 400;
  long long year_of_era = year - era * 400;
  long long day_of_year = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5;
  long long day_of_era = year_of_era * 365 + year_of_era / 4 -
                         year_of_era / 100 + day_of_year;
  return era * 146097 + day_of_era - 719468;
}

// timestamp fields

/* Reads `Z` or a `+hh:mm` or `-hh:mm` offset as seconds east of UTC. */
static int _zone(Reader &r) {
  int sign = r.text[r.at];
  if (sign == 'Z' || sign == 'z') {
    r.at++;
    return 0;
  }
  _expect(r, "+-", "expected 'Z' or a numeric offset");
  int hours = _digits_within(r, 0, 23), minutes = _field(r, ':', 0, 59);
  return (sign == '-' ? -1 : 1) * (hours * 3600 + minutes * 60);
}

/* Reads an optional `.digits` fraction as nanoseconds. */
static int _nanoseconds(Reader &r) {
  if (r.text[r.at] != '.') return 0;
  r.at++;
  int value = 0, scale = 100000000, digits = 0;
  for (; r.text[r.at] >= '0' && r.text[r.at] <= '9'; r.at++, digits++) {
    value += (r.text[r.at] - '0') * scale;
    scale /= 10;
  }
  if (!digits) _malformed(r, "expected a digit");
  return value;
}

/* Reads `separator` and then two digits within `low` and `high`. */
static int _field(Reader &r, char separator, int low, int high) {
  if (r.text[r.at] != separator)
    _malformed(r, separator == '-' ? "expected '-'" : "expected ':'");
  r.at++;
  return _digits_within(r, low, high);
}

static int _digits_within(Reader &r, int low, int high) {
  int start = r.at, value = _digits(r, 2);
  if (value < low || value > high) {
    r.at = start;
    _malformed(r, "field out of range");
  }
  return value;
}

static int _digits(Reader &r, int width) {
  int value = 0;
  for (int i = 0; i < width; i++, r.at++) {
    int digit = r.text[r.at] - '0';
    if (digit < 0 || digit > 9) _malformed(r, "expected a digit");
    value = value * 10 + digit;
  }
  return value;
}

static void _expect(Reader &r, const char *choices, String reason) {
  if (!r.text[r.at] || !strchr(choices, r.text[r.at])) _malformed(r, reason);
  r.at++;
}

static int _month_days(int year, int month) {
  static const int days[] = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31};
  int leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);
  return month == 2 && leap ? 29 : days[month - 1];
}

static void _malformed(Reader &r, String reason) {
  raise %(malformed (operation "Time.parse") (reason $reason)
          (offset $(r.at)));
}
