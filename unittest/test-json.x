/*  test-json.x -- unit tests for JSON text and ordinary x2c values */

#include "json.x"
#include "path.x"
#include "test-support.x"
$(import "test-macros.xmacro")
#include <limits.h>
#include <math.h>

/* Returns the `<bad-arg>` details raised for `text`, or NULL if it parsed. */
static List _rejection(String text) {
  try Json.parse(text);
  catch %(bad-arg *detail): return detail;
  return NULL;
}

static void _expect_rejected(String text, const char *why) {
  List detail = _rejection(text);
  if (!EXPECT_NOT_NULL(detail)) {
    printf("  accepted: %s\n", text);
    return;
  }
  EXPECT_STR_EQ(detail.assoc(<why>).string(), why);
}

static void json_parse_builds_ordinary_values(void) {
  $test.scoped();
  Var value = Json.parse(
    " {\"name\": \"x2c\", \"tags\": [\"a\", \"\"], \"empty\": {},"
    " \"none\": null, \"yes\": true, \"no\": false, \"list\": []}\n");
  EXPECT_TRUE(value is <map>);
  Map object = value;
  EXPECT_INT_EQ(object.len(), 7);
  EXPECT_STR_EQ(object["name"].string(), "x2c");
  EXPECT_TRUE(object["tags"] is <array>);
  EXPECT_TRUE(Var.equal(object["tags"], %["a", ""]));
  EXPECT_TRUE(object["tags"][1] is <string>);
  EXPECT_TRUE(object["empty"] is <map>);
  EXPECT_INT_EQ(object["empty"].map().len(), 0);
  EXPECT_TRUE(object.contains("none") && object["none"].is_null());
  EXPECT_TRUE(Json.is_bool(object["yes"]) && Json.boolean(object["yes"]));
  EXPECT_TRUE(Json.is_bool(object["no"]) && !Json.boolean(object["no"]));
  EXPECT_TRUE(object["yes"] && !object["no"]);
  EXPECT_TRUE(object["list"] is <array>);
  EXPECT_TRUE(Json.parse("\"top\"") is <string>);
  EXPECT_TRUE(Json.parse(" null ").is_null());
}

static void json_booleans_stay_distinct_from_numbers(void) {
  $test.scoped();
  EXPECT_TRUE(Var.equal(Json.bool(7), Json.parse("true")));
  EXPECT_FALSE(Var.equal(Json.bool(1), 1));
  EXPECT_FALSE(Json.is_bool(1));
  EXPECT_STR_EQ(Json.bool(0).str(), "false");
  int caught = 0;
  try Json.boolean(1);
  catch %(bad-types *): caught++;
  EXPECT_INT_EQ(caught, 1);
}

static void json_numbers_follow_the_grammar(void) {
  $test.scoped();
  Array numbers = Json.parse(
    "[0, -0, 42, -2147483648, 2147483648, -9223372036854775808,"
    " 18446744073709551615, 18446744073709551616, 1.5, -0.0, 1E2,"
    " 2e-3, 1e+2, 1e-999]");
  EXPECT_TRUE(numbers[0] is <i32> && numbers[1] is <i32>);
  EXPECT_INT_EQ(numbers[1].integer(), 0);
  EXPECT_TRUE(numbers[2] is <i32> && numbers[3] is <i32>);
  EXPECT_INT_EQ(numbers[3].integer(), INT_MIN);
  EXPECT_TRUE(numbers[4] is <long> && numbers[5] is <long>);
  EXPECT_TRUE(numbers[5].integer() == LONG_MIN);
  EXPECT_TRUE(numbers[6] is <ulong>);
  EXPECT_TRUE(numbers[6].ulong_value() == ULONG_MAX);
  EXPECT_TRUE(numbers[7] is <f64>);
  EXPECT_TRUE(numbers[7].floating() == 18446744073709551616.0);
  EXPECT_TRUE(numbers[8] is <f64> && numbers[8].floating() == 1.5);
  EXPECT_TRUE(numbers[9] is <f64> && signbit(numbers[9].floating()));
  EXPECT_TRUE(numbers[10].floating() == 100.0);
  EXPECT_TRUE(numbers[11].floating() == 0.002);
  EXPECT_TRUE(numbers[12].floating() == 100.0);
  EXPECT_TRUE(numbers[13].floating() == 0.0);

  const char *invalid[] = {
    "+1", "01", "-01", "1.", ".5", "1e", "1e+", "-", "0x10", "1.5e3.2",
    "Infinity", "NaN", "- 1", "1_000"
  };
  for (int i = 0; i < (int) (sizeof(invalid) / sizeof(*invalid)); i++) {
    List detail = _rejection(String.new(invalid[i]));
    if (!EXPECT_NOT_NULL(detail)) printf("  accepted: %s\n", invalid[i]);
  }
  _expect_rejected("[1e999]", "number out of range");
  _expect_rejected("-1e400", "number out of range");
}

static void json_strings_decode_escapes(void) {
  $test.scoped();
  String text = Json.parse(
    "\"q\\\" b\\\\ s\\/ \\b\\f\\n\\r\\t \\u0041\\u00e9\\u20AC"
    " \\ud83d\\ude00 \xc3\xa9\xf0\x9f\x98\x80\"");
  EXPECT_STR_EQ(text,
    "q\" b\\ s/ \b\f\n\r\t A\xc3\xa9\xe2\x82\xac"
    " \xf0\x9f\x98\x80 \xc3\xa9\xf0\x9f\x98\x80");
  EXPECT_TRUE(Json.parse("\"\"") is <string>);
  EXPECT_NULL(Json.parse("\"\"").string());

  _expect_rejected("\"\\ud83d\"", "unpaired surrogate");
  _expect_rejected("\"\\ud83d\\u0041\"", "unpaired surrogate");
  _expect_rejected("\"\\ude00\"", "unpaired surrogate");
  _expect_rejected("\"\\u0000\"", "U+0000 cannot appear in a String");
  _expect_rejected("\"\\x41\"", "invalid escape");
  _expect_rejected("\"\\u12\"", "invalid \\u escape");
  _expect_rejected("\"tab\there\"", "control character in string");
  _expect_rejected("\"open", "unterminated string");
  _expect_rejected("\"\xc0\xaf\"", "invalid UTF-8");
  _expect_rejected("\"\xed\xa0\x80\"", "invalid UTF-8");
  _expect_rejected("\"\xf4\x90\x80\x80\"", "invalid UTF-8");
  _expect_rejected("\"\xe2\x82\"", "invalid UTF-8");
  _expect_rejected("\"\xff\"", "invalid UTF-8");
}

static void json_rejects_malformed_text_with_position(void) {
  $test.scoped();
  List detail = _rejection("{\n  \"a\": [1,\n  2,]\n}");
  if (EXPECT_NOT_NULL(detail)) {
    EXPECT_STR_EQ(detail.assoc(<operation>).string(), "Json.parse");
    EXPECT_STR_EQ(detail.assoc(<why>).string(), "unexpected character");
    EXPECT_INT_EQ(detail.assoc(<offset>).integer(), 17);
    EXPECT_INT_EQ(detail.assoc(<line>).integer(), 3);
    EXPECT_INT_EQ(detail.assoc(<column>).integer(), 5);
  }
  _expect_rejected(NULL, "unexpected end of input");
  _expect_rejected(" \n\t", "unexpected end of input");
  _expect_rejected("[1", "expected ',' or ']'");
  _expect_rejected("{\"a\":1", "expected ',' or '}'");
  _expect_rejected("{\"a\" 1}", "expected ':'");
  _expect_rejected("{a: 1}", "expected a string key");
  _expect_rejected("{\"a\": 1,}", "expected a string key");
  _expect_rejected("[,]", "unexpected character");
  _expect_rejected("1 2", "unexpected text after the value");
  _expect_rejected("{} x", "unexpected text after the value");
  _expect_rejected("tru", "unexpected character");
  _expect_rejected("nul", "unexpected character");
  _expect_rejected("True", "unexpected character");
  _expect_rejected("\xef\xbb\xbf{}", "unexpected character");
  _expect_rejected("[1]\f", "unexpected text after the value");
  _expect_rejected("'a'", "unexpected character");
}

static void json_nesting_is_limited_to_512_levels(void) {
  $test.scoped();
  String deepest = %"${%"[".repeat(512)}${%"]".repeat(512)}";
  Var value = Json.parse(deepest);
  EXPECT_STR_EQ(value.json(), deepest);
  String deeper = %"${%"{\"a\":".repeat(513)}1${%"}".repeat(513)}";
  _expect_rejected(deeper, "nesting exceeds 512 levels");
  _expect_rejected(%"[".repeat(100000), "nesting exceeds 512 levels");

  Array cycle = %[];
  cycle.push(cycle);
  int caught = 0;
  try Var.json(cycle);
  catch %(size-limit *): caught++;
  EXPECT_INT_EQ(caught, 1);
}

static void json_repeated_names_keep_the_last_value(void) {
  $test.scoped();
  Map object = Json.parse("{\"a\": 1, \"b\": 2, \"a\": [3]}");
  EXPECT_INT_EQ(object.len(), 2);
  EXPECT_TRUE(Var.equal(object["a"], %[3]));
  EXPECT_STR_EQ(Var.json(object), "{\"a\":[3],\"b\":2}");
}

static void json_writes_compact_and_pretty_text(void) {
  $test.scoped();
  Var none = NULL;
  Map object = %{
    zeta: (1 2), "alpha": {}, mid: [], flag: ${Json.bool(1)}, none: $none,
    text: "tab\t\"q\" \\ \x01 \x7f \xc3\xa9", mode: fast
  };
  EXPECT_STR_EQ(Var.json(object),
    "{\"alpha\":{},\"flag\":true,\"mid\":[],\"mode\":\"fast\","
    "\"none\":null,\"text\":\"tab\\t\\\"q\\\" \\\\ \\u0001 \x7f \xc3\xa9\","
    "\"zeta\":[1,2]}");
  EXPECT_STR_EQ(Var.pretty_json(%{a: [1, {b: $none}], c: {}}),
    "{\n  \"a\": [\n    1,\n    {\n      \"b\": null\n    }\n  ],\n"
    "  \"c\": {}\n}");
  EXPECT_STR_EQ(Var.pretty_json(%[]), "[]");
  EXPECT_STR_EQ(Var.json("line\nbreak"), "\"line\\nbreak\"");
  EXPECT_STR_EQ(Var.json(%""), "\"\"");

  const double doubles[] = {
    0.1, 1.0, -0.0, 1e16, 1e15, 1e-5, 0.0001, 123456789.125, 5e-324,
    1.7976931348623157e308, 100000000.0, 1.0 / 3.0
  };
  const char *spellings[] = {
    "0.1", "1.0", "-0.0", "1e+16", "1000000000000000.0", "1e-05", "0.0001",
    "123456789.125", "5e-324", "1.7976931348623157e+308", "100000000.0",
    "0.3333333333333333"
  };
  for (int i = 0; i < (int) (sizeof(doubles) / sizeof(*doubles)); i++)
    EXPECT_STR_EQ(Var.json(doubles[i]), spellings[i]);
  EXPECT_STR_EQ(Var.json(Var.box_ulong(ULONG_MAX)), "18446744073709551615");
  EXPECT_STR_EQ(Var.json(Var.box_long_long(LLONG_MIN)),
                "-9223372036854775808");
  EXPECT_STR_EQ(Var.json((unsigned char) 200), "200");

  int caught = 0;
  try Var.json((double) NAN);
  catch %(conv-range *): caught++;
  try Var.json((double) -HUGE_VAL);
  catch %(conv-range *): caught++;
  try Var.json(%{1: "numeric key"});
  catch %(bad-types *): caught++;
  File output = stdout;
  try Var.json(%[{}, $output]);
  catch %(bad-types *): caught++;
  try Var.json(String.new("\xc3("));
  catch %(bad-arg *): caught++;
  EXPECT_INT_EQ(caught, 5);
}

static void json_values_round_trip(void) {
  $test.scoped();
  String text =
    "{\"array\":[1,-2,3.25,true,false,null,\"\",{}],\"big\":9007199254740993,"
    "\"nested\":{\"deep\":[[[\"\\u0001\\\\\\\"\"]]]},\"pi\":3.141592653589793,"
    "\"unicode\":\"\xe2\x82\xac\xf0\x9f\x98\x80\"}";
  Var value = Json.parse(text);
  EXPECT_STR_EQ(value.json(), text);
  EXPECT_TRUE(Var.equal(Json.parse(value.pretty_json()), value));
  EXPECT_STR_EQ(Json.parse(value.pretty_json()).json(), text);

  Map built = %{
    count: 3, ratio: 0.5, names: ["a", "b"], "on": ${Json.bool(1)}
  };
  Map read = Json.parse(Var.json(built));
  EXPECT_TRUE(Var.equal(read["count"], 3));
  EXPECT_TRUE(Var.equal(read["ratio"], 0.5));
  EXPECT_TRUE(Var.equal(read["names"], %["a", "b"]));
  EXPECT_TRUE(Json.boolean(read["on"]));

  const double hard[] = { 0.1 + 0.2, 1e23, 2.2250738585072014e-308,
                          4.9406564584124654e-324, 9007199254740993.0 };
  for (int i = 0; i < (int) (sizeof(hard) / sizeof(*hard)); i++)
    EXPECT_TRUE(Json.parse(Var.json(hard[i])).floating() == hard[i]);
}

static void json_files_read_and_write(void) {
  $test.scoped();
  Path root = Path.temp_dir(), path = root.join("value.json");
  Json.write_file(%{name: "x2c", list: [1, 2]}, path);
  EXPECT_STR_EQ(path.read_text(), "{\"list\":[1,2],\"name\":\"x2c\"}");
  Map value = Json.read_file(path);
  EXPECT_STR_EQ(value["name"].string(), "x2c");

  path.write_text("{\n\"a\": nope}");
  int caught = 0;
  try Json.read_file(path);
  catch %(bad-arg *detail): {
    caught++;
    EXPECT_STR_EQ(detail.assoc(<operation>).string(), "Json.read_file");
    EXPECT_STR_EQ(detail.assoc(<path>).string(), path);
    EXPECT_INT_EQ(detail.assoc(<line>).integer(), 2);
    EXPECT_INT_EQ(detail.assoc(<column>).integer(), 6);
  }
  try Json.read_file(root.join("missing.json"));
  catch %(not-found *): caught++;
  EXPECT_INT_EQ(caught, 2);
  root.remove_tree();
}

void json_suite(void) {
  $test.run(json_parse_builds_ordinary_values);
  $test.run(json_booleans_stay_distinct_from_numbers);
  $test.run(json_numbers_follow_the_grammar);
  $test.run(json_strings_decode_escapes);
  $test.run(json_rejects_malformed_text_with_position);
  $test.run(json_nesting_is_limited_to_512_levels);
  $test.run(json_repeated_names_keep_the_last_value);
  $test.run(json_writes_compact_and_pretty_text);
  $test.run(json_values_round_trip);
  $test.run(json_files_read_and_write);
}
