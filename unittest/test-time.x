/*  test-time.x -- unit tests for clocks, durations, and calendar time */

#include "time.x"
#include "test-support.x"
#include "test-macros.x"
#include <limits.h>
#include <stdlib.h>

/* Returns the `reason` of the `<malformed>` that parsing `text` raises, or
   NULL if it parsed. */
static String _rejection(String text) {
  try Time.parse(text);
  catch %(malformed *detail):
    return Error.snapshot(detail.assoc(<reason>));
  return NULL;
}

static void time_duration_prints_go_units(void) {
  $test.scoped();
  EXPECT_STR_EQ(Duration.new(0).str(), "0s");
  EXPECT_STR_EQ(Duration.new(12).str(), "12ns");
  EXPECT_STR_EQ(Duration.microseconds(750).str(), "750us");
  EXPECT_STR_EQ(Duration.new(1500).str(), "1.5us");
  EXPECT_STR_EQ(Duration.new(2500000).str(), "2.5ms");
  EXPECT_STR_EQ(Duration.seconds(1).str(), "1s");
  EXPECT_STR_EQ(Duration.seconds(90).str(), "1m30s");
  EXPECT_STR_EQ(Duration.seconds(3723.5).str(), "1h2m3.5s");
  EXPECT_STR_EQ(Duration.seconds(3600).str(), "1h0m0s");
  EXPECT_STR_EQ(Duration.milliseconds(-250).str(), "-250ms");
  EXPECT_STR_EQ(Duration.new(1000000001).str(), "1.000000001s");
  EXPECT_STR_EQ(%"$(Duration.seconds(0.5))", "500ms");
}

static void time_duration_arithmetic_uses_operators(void) {
  $test.scoped();
  Duration second = Duration.seconds(1), half = Duration.milliseconds(500);
  EXPECT_TRUE(second + half == Duration.seconds(1.5));
  EXPECT_TRUE(second - half == half);
  EXPECT_TRUE(-half == Duration.milliseconds(-500));
  EXPECT_TRUE(half < second && second >= half && half != second);
  EXPECT_TRUE(half.scale(3) == Duration.seconds(1.5));
  EXPECT_INT_EQ(Duration.seconds(2.25).total_milliseconds(), 2250);
  EXPECT_TRUE(Duration.microseconds(-1500).total_seconds() == -0.0015);
  Duration total = Duration.new(0);
  total += half;
  total += half;
  EXPECT_TRUE(total == second);
}

static void time_duration_overflow_raises(void) {
  $test.scoped();
  Duration largest = Duration.new(LLONG_MAX);
  int caught = 0;
  try largest + Duration.new(1);
  catch %(conv-range (operation "Duration.add") *): caught++;
  try -Duration.new(LLONG_MIN);
  catch %(conv-range (operation "Duration.neg") *): caught++;
  try Duration.milliseconds(LLONG_MAX / 1000);
  catch %(conv-range (operation "Duration.milliseconds") *): caught++;
  try Duration.seconds(1.0 / 0.0);
  catch %(conv-range (operation "Duration.seconds") *): caught++;
  EXPECT_INT_EQ(caught, 4);
}

static void time_preserves_nanosecond_boundaries(void) {
  $test.scoped();
  Time first = Time.parse("1677-09-21T00:12:43.145224192Z");
  Time last = Time.parse("2262-04-11T23:47:16.854775807Z");
  EXPECT_TRUE(first.nanoseconds == LLONG_MIN);
  EXPECT_TRUE(last.nanoseconds == LLONG_MAX);
  EXPECT_TRUE(first.utc().time() == first);
  EXPECT_TRUE(last.utc().time() == last);
  EXPECT_INT_EQ(first.utc().nanosecond, 145224192);
  EXPECT_INT_EQ(Time.new(-1).utc().nanosecond, 999999999);
  EXPECT_TRUE(DateTime.new(1970, 1, 1, 0, 0, 1, -1, 0).time() ==
              Time.new(999999999));
  EXPECT_TRUE(DateTime.new(1970, 1, 1, 0, 0, -1, 1000000001, 0).time() ==
              Time.new(1));
  int caught = 0;
  try Time.parse("1677-09-21T00:12:43.145224191Z");
  catch %(conv-range *): caught++;
  try Time.parse("2262-04-11T23:47:16.854775808Z");
  catch %(conv-range *): caught++;
  EXPECT_INT_EQ(caught, 2);
}

static void time_scales_integral_factors_exactly(void) {
  $test.scoped();
  Duration first = Duration.new(LLONG_MIN), last = Duration.new(LLONG_MAX);
  EXPECT_TRUE(first.scale(1) == first);
  EXPECT_TRUE(last.scale(1) == last);
  EXPECT_TRUE(last.scale(-1).nanoseconds == -LLONG_MAX);
  EXPECT_TRUE(first.scale(0).nanoseconds == 0);
  EXPECT_TRUE(last.scale(0).nanoseconds == 0);
  EXPECT_TRUE(Duration.new(9007199254740993LL).scale(1).nanoseconds ==
              9007199254740993LL);
  int caught = 0;
  try first.scale(-1);
  catch %(conv-range *): caught++;
  try last.scale(2);
  catch %(conv-range *): caught++;
  EXPECT_INT_EQ(caught, 2);
}

static void time_duration_boxes_as_a_value(void) {
  $test.scoped();
  Map seen = {};
  seen[Duration.seconds(2)] = "two";
  EXPECT_STR_EQ(seen[Duration.milliseconds(2000)].string(), "two");
  Var boxed = Duration.seconds(3);
  Duration back = boxed;
  EXPECT_TRUE(back == Duration.seconds(3));
}

static void time_clocks_advance(void) {
  $test.scoped();
  Duration start = Time.monotonic();
  Time before = Time.now();
  Time.sleep(Duration.milliseconds(20));
  Duration elapsed = Time.monotonic() - start;
  EXPECT_TRUE(elapsed >= Duration.milliseconds(20));
  EXPECT_TRUE(elapsed < Duration.seconds(10));
  EXPECT_TRUE(Time.now().since(before) > Duration.milliseconds(10));
  Time.sleep(Duration.milliseconds(-5));
  EXPECT_TRUE(before.unix_seconds() > 1.7e9);
}

static void time_formats_rfc3339_in_utc(void) {
  $test.scoped();
  EXPECT_STR_EQ(Time.new(0).str(), "1970-01-01T00:00:00Z");
  EXPECT_STR_EQ(Time.new(-1).str(), "1969-12-31T23:59:59.999999999Z");
  Time t = Time.from_unix(1793196309.25);
  EXPECT_STR_EQ(t.str(), "2026-10-28T14:05:09.25Z");
  EXPECT_STR_EQ(%"at $t", "at 2026-10-28T14:05:09.25Z");
  EXPECT_STR_EQ(Time.parse("2000-02-29T12:00:00Z").str(),
                "2000-02-29T12:00:00Z");
  EXPECT_STR_EQ(Time.parse("1677-09-22T00:00:00Z").str(),
                "1677-09-22T00:00:00Z");
}

static void time_parses_offsets_and_fractions(void) {
  $test.scoped();
  Time t = Time.parse("2026-10-28T14:05:09.25Z");
  EXPECT_TRUE(t.nanoseconds == 1793196309250000000LL);
  EXPECT_TRUE(Time.parse("2026-10-28 10:05:09.250-04:00") == t);
  EXPECT_TRUE(Time.parse("2026-10-28t19:35:09.25+05:30") == t);
  EXPECT_TRUE(Time.parse("2026-10-28T14:05:09.2500000009z") == t);
  EXPECT_TRUE(Time.parse("1969-12-31T23:59:59Z").nanoseconds == -1000000000LL);
  EXPECT_TRUE(t.plus(Duration.seconds(-0.25)) == Time.from_unix(1793196309));
  EXPECT_TRUE(t.since(Time.parse("2026-10-28T14:00:00Z")) ==
              Duration.seconds(309.25));
}

static void time_parse_rejects_invalid_text(void) {
  $test.scoped();
  EXPECT_STR_EQ(_rejection("2026-02-29T00:00:00Z"), "field out of range");
  EXPECT_STR_EQ(_rejection("2026-13-01T00:00:00Z"), "field out of range");
  EXPECT_STR_EQ(_rejection("2026-10-28T24:00:00Z"), "field out of range");
  EXPECT_STR_EQ(_rejection("2026-10-28T23:59:60Z"), "field out of range");
  EXPECT_STR_EQ(_rejection("2026-10-28T12:00:00"),
                "expected 'Z' or a numeric offset");
  EXPECT_STR_EQ(_rejection("2026-10-28"),
                "expected 'T' between the date and the time");
  EXPECT_STR_EQ(_rejection("2026-10-28T12:00:00.Z"), "expected a digit");
  EXPECT_STR_EQ(_rejection("2026-10-28T12:00:00Z!"),
                "unexpected text after the offset");
  EXPECT_STR_EQ(_rejection("26-10-28T12:00:00Z"), "expected a digit");
  EXPECT_STR_EQ(_rejection(""), "expected a digit");
  try Time.parse("2026-10-28T12:00Z");
  catch %(malformed (operation "Time.parse") (reason ?why) (offset ?at)): {
    EXPECT_STR_EQ(why.string(), "expected ':'");
    EXPECT_INT_EQ(at.int(), 16);
  }
  int caught = 0;
  try Time.parse("9999-12-31T23:59:59Z");
  catch %(conv-range (operation "DateTime.time") *): caught++;
  EXPECT_INT_EQ(caught, 1);
}

static void time_strftime_formats_in_utc(void) {
  $test.scoped();
  Time t = Time.parse("2026-10-28T14:05:09Z");
  EXPECT_STR_EQ(t.format("%a, %d %b %Y %H:%M:%S GMT"),
                "Wed, 28 Oct 2026 14:05:09 GMT");
  EXPECT_STR_EQ(t.format("%j"), "301");
  EXPECT_STR_EQ(t.format(""), "");
  EXPECT_INT_EQ(t.format("%Y".repeat(100)).len(), 400);
}

static void time_calendar_fields_convert_back(void) {
  $test.scoped();
  Time t = Time.parse("2026-10-28T14:05:09.5Z");
  DateTime d = t.utc();
  EXPECT_INT_EQ(d.year, 2026);
  EXPECT_INT_EQ(d.month, 10);
  EXPECT_INT_EQ(d.day, 28);
  EXPECT_INT_EQ(d.hour, 14);
  EXPECT_INT_EQ(d.nanosecond, 500000000);
  EXPECT_INT_EQ(d.utc_offset, 0);
  EXPECT_INT_EQ(d.weekday(), 3);
  EXPECT_TRUE(d.time() == t);
  Time normalized = DateTime.new(2026, 1, 32, 0, 0, 0, 0, 0);
  EXPECT_STR_EQ(normalized.str(), "2026-02-01T00:00:00Z");
  EXPECT_STR_EQ(DateTime.new(2026, 13, 1, 0, 0, 0, 0, -3600).time().str(),
                "2027-01-01T01:00:00Z");
}

static void time_local_follows_tz(void) {
  $test.scoped();
  String saved = String.new(getenv("TZ"));
  Time t = Time.parse("2026-10-28T14:05:09Z");
  try {
    setenv("TZ", "IST-5:30", 1);
    DateTime local = t.local();
    EXPECT_STR_EQ(local.str(), "2026-10-28T19:35:09+05:30");
    EXPECT_INT_EQ(local.utc_offset, 19800);
    EXPECT_TRUE(local.time() == t);
    EXPECT_STR_EQ(t.format_local("%H:%M %Z"), "19:35 IST");
    setenv("TZ", "EST5EDT,M3.2.0,M11.1.0", 1);
    EXPECT_INT_EQ(t.local().utc_offset, -4 * 3600);
    EXPECT_INT_EQ(Time.parse("2026-12-01T12:00:00Z").local().utc_offset,
                  -5 * 3600);
  }
  finally {
    if (saved) setenv("TZ", saved, 1);
    else unsetenv("TZ");
    tzset();
  }
}

void time_suite(void) {
  $test.run(time_duration_prints_go_units);
  $test.run(time_duration_arithmetic_uses_operators);
  $test.run(time_duration_overflow_raises);
  $test.run(time_preserves_nanosecond_boundaries);
  $test.run(time_scales_integral_factors_exactly);
  $test.run(time_duration_boxes_as_a_value);
  $test.run(time_clocks_advance);
  $test.run(time_formats_rfc3339_in_utc);
  $test.run(time_parses_offsets_and_fractions);
  $test.run(time_parse_rejects_invalid_text);
  $test.run(time_strftime_formats_in_utc);
  $test.run(time_calendar_fields_convert_back);
  $test.run(time_local_follows_tz);
}
