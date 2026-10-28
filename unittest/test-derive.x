/*  test-derive.x -- generated record mappings */

#include "derive.x"
#include "test-support.x"
#include "test-macros.x"

typedef struct DerivePoint { int x, y; } DerivePoint;
typedef enum DeriveColor { DERIVE_RED, DERIVE_BLUE } DeriveColor;
typedef struct DerivePerson {
  int age;
  String name;
  double score;
  DerivePoint home;
  Array tags;
} DerivePerson;
typedef struct DeriveValues {
  DeriveColor color;
  Symbol kind;
  Map attributes;
  List items;
} DeriveValues;
typedef struct DeriveOptions {
  int count;
  long limit;
  double scale;
  String name;
  Symbol mode;
  DeriveColor color;
} DeriveOptions;

$derive(DerivePoint, <map>, <equal>, <repr>);
$derive(DerivePerson, <json>, <equal>, <repr>);
$derive(DeriveValues, <json>, <row>, <equal>, <repr>);
$derive(DeriveOptions, <args>, <row>, <equal>, <repr>);

static void derive_nested_records_round_trip(void) {
  $test.scoped();
  DerivePerson person = { 42, "Ada", 1.5, { 3, 4 }, ["x", 2] };
  Map map = person.to_map();
  EXPECT_INT_EQ(map["home"].map()["y"].integer(), 4);
  DerivePerson copy = DerivePerson.from_map(map);
  EXPECT_TRUE(person.equal(copy));
  copy = DerivePerson.from_json(person.json());
  EXPECT_TRUE(person.equal(copy));
  EXPECT_STR_EQ(copy.repr(),
    "DerivePerson{ age: 42, name: \"Ada\", score: 1.5, "
    "home: DerivePoint{ x: 3, y: 4 }, tags: [ \"x\", 2 ] }");
  copy.home.y = 9;
  EXPECT_FALSE(person.equal(copy));
  map.del("name");
  int caught = 0;
  try DerivePerson.from_map(map);
  catch %(bad-arg (operation "from_map") (field "name") (reason "missing")):
    caught++;
  EXPECT_INT_EQ(caught, 1);
}

static void derive_values_keep_their_types(void) {
  $test.scoped();
  DeriveValues value = { DERIVE_BLUE, <reading>, {"unit": "ms"}, %(1 "a") };
  DeriveValues copy = DeriveValues.from_map(value.to_map());
  EXPECT_TRUE(value.equal(copy));
  EXPECT_TRUE(copy.kind == <reading>);
  EXPECT_STR_EQ(copy.attributes["unit"].string(), "ms");
  EXPECT_LIST_EQ(copy.items, %(1 "a"));
  EXPECT_TRUE("color: 1" in copy.repr());
  copy = DeriveValues.from_row(value.row());
  EXPECT_TRUE(value.equal(copy));
  EXPECT_LIST_EQ(DeriveValues.columns(), %("color" "kind" "attributes" "items"));
  Map parsed = Json.parse(value.json()).map();
  EXPECT_TRUE(parsed["kind"] is <string>);
  EXPECT_TRUE(parsed["items"] is <array>);
  int caught = 0;
  try DeriveValues.from_json(value.json());
  catch %(no-convert *): caught++;
  EXPECT_INT_EQ(caught, 1);
}

static void derive_arguments_and_rows_follow_field_order(void) {
  $test.scoped();
  List words = %("--count" "3" "--limit" "4000000000" "--scale" "1.25"
    "--name" "sample" "--mode" "fast" "--color" "1");
  Map options = Args.parse(words, DeriveOptions.args_spec());
  EXPECT_STR_EQ(options["count"].string(), "3");
  DeriveOptions value = DeriveOptions.from_args(words);
  EXPECT_INT_EQ(value.count, 3);
  EXPECT_TRUE(value.limit == 4000000000L);
  EXPECT_TRUE(value.scale == 1.25);
  EXPECT_STR_EQ(value.name, "sample");
  EXPECT_TRUE(value.mode == <fast>);
  EXPECT_TRUE(value.color == DERIVE_BLUE);
  EXPECT_LIST_EQ(DeriveOptions.columns(),
    %("count" "limit" "scale" "name" "mode" "color"));
  EXPECT_STR_EQ(value.row().repr(),
    "(3 4000000000l 1.25 \"sample\" fast 1)");
  DeriveOptions copy = DeriveOptions.from_row(value.row());
  EXPECT_TRUE(value.equal(copy));
  int caught = 0;
  try DeriveOptions.from_args(%("--count" "3"));
  catch %(bad-arg *): caught++;
  EXPECT_INT_EQ(caught, 1);
}

static void derive_map_and_row_reject_wrong_value_types(void) {
  $test.scoped();
  DeriveValues value = { DERIVE_RED, <reading>, {}, %(1) };
  Map map = value.to_map();
  int caught = 0;
  map["kind"] = "reading";
  try DeriveValues.from_map(map);
  catch %(no-convert *): caught++;
  EXPECT_INT_EQ(caught, 1);
  map["kind"] = <reading>;
  map["attributes"] = %(1);
  try DeriveValues.from_map(map);
  catch %(no-convert *): caught++;
  EXPECT_INT_EQ(caught, 2);
  map["attributes"] = (Map) {};
  map["color"] = "red";
  try DeriveValues.from_map(map);
  catch %(no-convert *): caught++;
  EXPECT_INT_EQ(caught, 3);
  try DeriveValues.from_row(%(0 <reading> 3 (1)));
  catch %(no-convert *): caught++;
  EXPECT_INT_EQ(caught, 4);
  DerivePerson person = { 1, "Ada", 1, {1, 2}, [] };
  map = person.to_map();
  map["name"] = 9;
  try DerivePerson.from_map(map);
  catch %(no-convert *): caught++;
  EXPECT_INT_EQ(caught, 5);
  map["name"] = "Ada";
  map["home"] = 9;
  try DerivePerson.from_map(map);
  catch %(no-convert *): caught++;
  EXPECT_INT_EQ(caught, 6);
  map["home"] = {"x": 1, "y": 2};
  map["tags"] = %(1);
  try DerivePerson.from_map(map);
  catch %(no-convert *): caught++;
  EXPECT_INT_EQ(caught, 7);
  try DerivePerson.from_json("[]");
  catch %(no-convert *): caught++;
  EXPECT_INT_EQ(caught, 8);
  EXPECT_INT_EQ(caught, 8);
}

void derive_suite(void) {
  $test.run(derive_nested_records_round_trip);
  $test.run(derive_values_keep_their_types);
  $test.run(derive_arguments_and_rows_follow_field_order);
  $test.run(derive_map_and_row_reject_wrong_value_types);
}
