/*  test-encoding.x -- unit tests for UTF-8 and base64, hex, and percent
    encodings */

#include "encoding.x"
#include "test-support.x"
#include "test-macros.x"

/* Returns the `<malformed>` details that `decode` raises for `text`, or
   NULL if it decoded. */
static List _rejection(Func decode, String text) {
  try decode(text);
  catch %(malformed *detail): return Error.snapshot(detail);
  return NULL;
}

static void encoding_utf8_counts_and_iterates(void) {
  $test.scoped();
  String text = "na\xc3\xafve \xe2\x82\xac\xf0\x9f\x98\x80";
  EXPECT_TRUE(text.is_utf8());
  EXPECT_INT_EQ(text.len(), 14);
  EXPECT_INT_EQ(text.code_point_count(), 8);
  Array points = [];
  foreach (int point in text.code_points()) points.push(point);
  EXPECT_TRUE(Var.equal(
    points, [0x6E, 0x61, 0xEF, 0x76, 0x65, 0x20, 0x20AC, 0x1F600]));
  EXPECT_TRUE(((String) NULL).is_utf8());
  EXPECT_INT_EQ(((String) NULL).code_point_count(), 0);
}

static void encoding_utf8_cursor_reports_offsets(void) {
  $test.scoped();
  String text = "a\xc3\xa9z";
  int cursor = 0, point = 0;
  EXPECT_TRUE(text.try_next_code_point(cursor, point));
  EXPECT_INT_EQ(point, 'a');
  EXPECT_TRUE(text.try_next_code_point(cursor, point));
  EXPECT_INT_EQ(point, 0xE9);
  EXPECT_INT_EQ(cursor, 3);
  EXPECT_TRUE(text.try_next_code_point(cursor, point));
  EXPECT_FALSE(text.try_next_code_point(cursor, point));
  EXPECT_INT_EQ(cursor, 4);
  cursor = -1;
  EXPECT_FALSE(text.try_next_code_point(cursor, point));
}

static void encoding_utf8_rejects_ill_formed_bytes(void) {
  $test.scoped();
  EXPECT_FALSE("\xc0\x80".is_utf8());
  EXPECT_FALSE("\xed\xa0\x80".is_utf8());
  EXPECT_FALSE("\xf4\x90\x80\x80".is_utf8());
  EXPECT_FALSE("ab\xe2\x82".is_utf8());
  int offset = -1;
  try "ab\xff".code_point_count();
  catch %(malformed (operation "String.try_next_code_point") * (offset ?at)):
    offset = at.int();
  EXPECT_INT_EQ(offset, 2);
}

static void encoding_utf8_encodes_code_points(void) {
  $test.scoped();
  Buffer out = auto Buffer.new(0);
  out.write_code_point('A').write_code_point(0x7FF).write_code_point(0xFFFF);
  out.write_code_point(0x10FFFF);
  EXPECT_STR_EQ(out.str(), "A\xdf\xbf\xef\xbf\xbf\xf4\x8f\xbf\xbf");
  EXPECT_STR_EQ(String.from_code_point(0x20AC), "\xe2\x82\xac");
  int caught = 0;
  foreach (int point in [0, -1, 0xD800, 0xDFFF, 0x110000]) {
    try String.from_code_point(point);
    catch %(bad-arg (operation "Buffer.write_code_point") *): caught++;
  }
  EXPECT_INT_EQ(caught, 5);
}

/* The RFC 4648 section 10 test vectors. */
static void encoding_base64_matches_rfc_vectors(void) {
  $test.scoped();
  List plain = %("" "f" "fo" "foo" "foob" "fooba" "foobar");
  List padded = %("" "Zg==" "Zm8=" "Zm9v" "Zm9vYg==" "Zm9vYmE=" "Zm9vYmFy");
  List bare = %("" "Zg" "Zm8" "Zm9v" "Zm9vYg" "Zm9vYmE" "Zm9vYmFy");
  foreach (String text in plain) {
    String standard = padded.car(), url = bare.car();
    EXPECT_STR_EQ(text.base64_encode(), standard);
    EXPECT_STR_EQ(standard.base64_decode(), text);
    EXPECT_STR_EQ(text.base64url_encode(), url);
    EXPECT_STR_EQ(url.base64url_decode(), text);
    EXPECT_STR_EQ(standard.base64url_decode(), text);
    padded = padded.cdr();
    bare = bare.cdr();
  }
  EXPECT_STR_EQ("\xfb\xff\xbf".base64_encode(), "+/+/");
  EXPECT_STR_EQ("\xfb\xff\xbf".base64url_encode(), "-_-_");
}

static void encoding_base64_round_trips_bytes(void) {
  $test.scoped();
  Block bytes = "AAEC/w==".base64_decode_bytes();
  EXPECT_INT_EQ(bytes.len(), 4);
  EXPECT_STR_EQ(bytes.hex_encode(), "000102ff");
  EXPECT_STR_EQ(bytes.base64_encode(), "AAEC/w==");
  EXPECT_STR_EQ(bytes.base64url_encode(), "AAEC_w");
  EXPECT_INT_EQ("AAEC_w".base64url_decode_bytes().len(), 4);
}

static void encoding_base64_rejects_invalid_text(void) {
  $test.scoped();
  List detail = _rejection(%!(String t) => t.base64_decode(), "Zm9");
  if (!EXPECT_NOT_NULL(detail)) return;
  EXPECT_STR_EQ(detail.assoc(<reason>).string(),
                "padding must complete a group of four");
  detail = _rejection(%!(String t) => t.base64_decode(), "Zm=v");
  EXPECT_INT_EQ(detail.assoc(<offset>).int(), 2);
  detail = _rejection(%!(String t) => t.base64_decode(), "Zm9v\n");
  EXPECT_STR_EQ(detail.assoc(<reason>).string(),
                "padding must complete a group of four");
  detail = _rejection(%!(String t) => t.base64url_decode(), "Z");
  EXPECT_STR_EQ(detail.assoc(<reason>).string(), "incomplete group");
  detail = _rejection(%!(String t) => t.base64url_decode(), "Zm8==");
  EXPECT_INT_EQ(detail.assoc(<offset>).int(), 5);
  detail = _rejection(%!(String t) => t.base64_decode(), "AAEC");
  EXPECT_STR_EQ(detail.assoc(<reason>).string(),
                "NUL byte cannot appear in a String");
  EXPECT_INT_EQ(detail.assoc(<index>).int(), 0);
}

static void encoding_hex_round_trips(void) {
  $test.scoped();
  EXPECT_STR_EQ("hi!".hex_encode(), "686921");
  EXPECT_STR_EQ("68692A".hex_decode(), "hi*");
  EXPECT_STR_EQ(((String) NULL).hex_encode(), "");
  EXPECT_INT_EQ("00ff".hex_decode_bytes().len(), 2);
  List detail = _rejection(%!(String t) => t.hex_decode(), "abc");
  EXPECT_STR_EQ(detail.assoc(<reason>).string(), "odd number of digits");
  detail = _rejection(%!(String t) => t.hex_decode(), "0g");
  EXPECT_INT_EQ(detail.assoc(<offset>).int(), 1);
  detail = _rejection(%!(String t) => t.hex_decode(), "4100");
  EXPECT_INT_EQ(detail.assoc(<index>).int(), 1);
}

static void encoding_percent_round_trips(void) {
  $test.scoped();
  EXPECT_STR_EQ("a b&c=d/\xc3\xa9~-._".percent_encode(),
                "a%20b%26c%3Dd%2F%C3%A9~-._");
  EXPECT_STR_EQ("a%20b%26c+d%2f".percent_decode(), "a b&c+d/");
  EXPECT_STR_EQ("plain".percent_decode(), "plain");
  EXPECT_STR_EQ("%C3%A9".percent_decode(), "\xc3\xa9");
  List detail = _rejection(%!(String t) => t.percent_decode(), "a%2");
  EXPECT_INT_EQ(detail.assoc(<offset>).int(), 3);
  detail = _rejection(%!(String t) => t.percent_decode(), "%zz");
  EXPECT_INT_EQ(detail.assoc(<offset>).int(), 1);
  detail = _rejection(%!(String t) => t.percent_decode(), "x%00");
  EXPECT_INT_EQ(detail.assoc(<offset>).int(), 1);
}

void encoding_suite(void) {
  $test.run(encoding_utf8_counts_and_iterates);
  $test.run(encoding_utf8_cursor_reports_offsets);
  $test.run(encoding_utf8_rejects_ill_formed_bytes);
  $test.run(encoding_utf8_encodes_code_points);
  $test.run(encoding_base64_matches_rfc_vectors);
  $test.run(encoding_base64_round_trips_bytes);
  $test.run(encoding_base64_rejects_invalid_text);
  $test.run(encoding_hex_round_trips);
  $test.run(encoding_percent_round_trips);
}
