/* test-json.x -- focused tests for the idiomatic yyjson client. */

import "yyjson" as json;

#include "yyjson-0.12.h"
#include "test-support.x"
#include <limits.h>

$(import "../../../unittest/test-macros.xmacro")

static void json_parse_uses_x2c_values(void) {
  Var value = json.Json.parse(
    %"{\"n\":\"x2c\",\"t\":true,\"f\":false,\"z\":null,\"a\":[1,-2,3.5]}"
  );
  Map object = value;
  EXPECT_STR_EQ(object[%"n"].string(), %"x2c");
  EXPECT_TRUE(json.Json.is_bool(object[%"t"]));
  EXPECT_TRUE(object[%"t"].truthy());
  EXPECT_FALSE(object[%"f"].truthy());
  EXPECT_TRUE(object[%"z"].is_null());

  Array items = object[%"a"];
  EXPECT_INT_EQ(items.len(), 3);
  EXPECT_INT_EQ(items[0].ulong_long_value(), 1);
  EXPECT_INT_EQ(items[1].long_long_value(), -2);
  EXPECT_TRUE(items[2].floating() == 3.5);
}

static void json_round_trip_preserves_values(void) {
  Var original = json.Json.parse(
    %"{\"enabled\":true,\"nested\":[null,{\"count\":7}]}"
  );
  String encoded = original.json();
  Var decoded = json.Json.parse(encoded);
  EXPECT_TRUE(original == decoded);
  EXPECT_TRUE(decoded.map()[%"enabled"].truthy());
}

static void json_integer_edges_remain_exact(void) {
  Var maximum = json.Json.parse(%"18446744073709551615");
  Var minimum = json.Json.parse(%"-9223372036854775808");
  EXPECT_TRUE(maximum is <ullong>);
  EXPECT_TRUE(maximum.ulong_long_value() == ULLONG_MAX);
  EXPECT_STR_EQ(maximum.json(), %"18446744073709551615");
  EXPECT_TRUE(minimum is <llong>);
  EXPECT_TRUE(minimum.long_long_value() == LLONG_MIN);
  EXPECT_STR_EQ(minimum.json(), %"-9223372036854775808");
}

static void json_build_and_mutate_with_collections(void) {
  Array names = %["one", "two"];
  Map value = %{
    "names": $names,
    "published": ${json.Json.bool(0)},
    "metadata": ${(Var) { .u64 = 0 }}
  };
  names.push(%"three");
  value[%"published"] = json.Json.bool(1);

  Var document = value;
  Map decoded = json.Json.parse(document.pretty_json());
  EXPECT_INT_EQ(decoded[%"names"].array().len(), 3);
  EXPECT_STR_EQ(decoded[%"names"].array()[2].string(), %"three");
  EXPECT_TRUE(decoded[%"published"].truthy());
  EXPECT_TRUE(decoded[%"metadata"].is_null());
}

static void json_pointer_distinguishes_null_and_missing(void) {
  Var value = json.Json.parse(%"{\"a\":[null,{\"b\":2}]}");
  Var found = %"unchanged";
  EXPECT_TRUE(value.try_json_pointer(%"/a/0", &found));
  EXPECT_TRUE(found.is_null());
  EXPECT_TRUE(value.try_json_pointer(%"/a/1/b", &found));
  EXPECT_INT_EQ(found.ulong_long_value(), 2);

  found = %"unchanged";
  EXPECT_FALSE(value.try_json_pointer(%"/a/3", &found));
  EXPECT_STR_EQ(found.string(), %"unchanged");
  EXPECT_TRUE(value.json_pointer(%"/missing") is void);
}

static void json_patch_and_merge_patch_return_x2c_values(void) {
  Var value = json.Json.parse(%"{\"name\":\"old\",\"tags\":[\"one\"]}");
  Array operations = %[
    {
      "op": "replace",
      "path": "/name",
      "value": "new"
    },
    {
      "op": "add",
      "path": "/tags/-",
      "value": "two"
    }
  ];
  Var patched = value.json_patch(operations);
  EXPECT_STR_EQ(patched.map()[%"name"].string(), %"new");
  EXPECT_INT_EQ(patched.map()[%"tags"].array().len(), 2);

  Map changes = %{"name": "merged", "tags": ${(Var) { .u64 = 0 }}};
  Var merged = patched.json_merge_patch(changes);
  EXPECT_STR_EQ(merged.map()[%"name"].string(), %"merged");
  EXPECT_TRUE(merged.map()[%"tags"] is void);
}

static void json_options_expose_yyjson_flags(void) {
  Var value = json.Json.parse_opts(
    %"{/*comment*/\"value\":1,}",
    YYJSON_READ_ALLOW_COMMENTS | YYJSON_READ_ALLOW_TRAILING_COMMAS
  );
  EXPECT_INT_EQ(value.map()[%"value"].ulong_long_value(), 1);
  String output = json.Json.stringify_opts(
    value, YYJSON_WRITE_PRETTY | YYJSON_WRITE_NEWLINE_AT_END
  );
  EXPECT_STR_EQ(output, %"{\n    \"value\": 1\n}\n");
}

static void json_in_situ_stays_in_raw_api(void) {
  int caught = 0;
  try {
    json.Json.parse_opts(%"{}", YYJSON_READ_INSITU);
  }
  catch %(bad-arg *detail): {
    caught = 1;
    EXPECT_STR_EQ(detail.assoc(<library>).string(), %"yyjson");
    EXPECT_STR_EQ(detail.assoc(<operation>).string(), %"parse");
  }
  EXPECT_TRUE(caught);
}

static void json_parse_error_has_yyjson_detail(void) {
  int caught = 0;
  try {
    json.Json.parse(%"{\"broken\":}");
  }
  catch %(malformed *detail): {
    caught = 1;
    EXPECT_STR_EQ(detail.assoc(<library>).string(), %"yyjson");
    EXPECT_STR_EQ(detail.assoc(<operation>).string(), %"parse");
    EXPECT_TRUE(detail.assoc(<code>).integer() != 0);
    EXPECT_TRUE(detail.assoc(<message>).string().len() > 0);
    EXPECT_TRUE(detail.assoc(<offset>).integer() > 0);
  }
  EXPECT_TRUE(caught);
}

static void json_rejects_embedded_nul_strings(void) {
  int caught = 0;
  try {
    json.Json.parse(%"\"before\\u0000after\"");
  }
  catch %(bad-enc *detail): {
    caught = 1;
    EXPECT_STR_EQ(detail.assoc(<library>).string(), %"yyjson");
    EXPECT_STR_EQ(detail.assoc(<operation>).string(), %"parse");
  }
  EXPECT_TRUE(caught);
}

static void json_rejects_values_outside_json_domain(void) {
  int caught = 0;
  try {
    Var invalid = <not-json>;
    invalid.json();
  }
  catch %(bad-types *detail): {
    caught = 1;
    EXPECT_STR_EQ(detail.assoc(<library>).string(), %"yyjson");
    EXPECT_STR_EQ(detail.assoc(<operation>).string(), %"stringify");
    EXPECT_TRUE(detail.assoc(<tag>).symbol() == <symbol>);
  }
  EXPECT_TRUE(caught);
}

static void json_document_preserves_duplicate_member_order(void) {
  String source = %"{\"key\":1,\"key\":2,\"last\":3}";
  json.JsonDocument document = json.JsonDocument.parse(source);
  defer document.free();
  json.JsonObject object = document.root().object();

  EXPECT_NOT_NULL(document.native());
  EXPECT_TRUE(
    yyjson_doc_get_root(document.native()) == document.root().native()
  );

  EXPECT_INT_EQ(object.len(), 3);
  EXPECT_INT_EQ(object[%"key"].uint(), 1);
  List duplicates = object.all(%"key");
  EXPECT_INT_EQ(duplicates.len(), 2);
  json.JsonValue first = duplicates.getindex(0);
  json.JsonValue second = duplicates.getindex(1);
  EXPECT_INT_EQ(first.uint(), 1);
  EXPECT_INT_EQ(second.uint(), 2);

  Array keys = %[];
  foreach(json.JsonMember member, object) keys.push(member.key());
  EXPECT_STR_EQ(keys[0].string(), %"key");
  EXPECT_STR_EQ(keys[1].string(), %"key");
  EXPECT_STR_EQ(keys[2].string(), %"last");
  EXPECT_STR_EQ(document.json(), source);
}

static void json_empty_collections_and_required_members_are_explicit(void) {
  Var converted = json.Json.parse(%"{\"array\":[],\"object\":{}}");
  Array array = converted.map()[%"array"];
  Map map = converted.map()[%"object"];
  EXPECT_INT_EQ(array.len(), 0);
  EXPECT_INT_EQ(map.len(), 0);
  int count = 0;
  foreach(Var value, array) count++;
  foreach(Var entry, map) count++;
  EXPECT_INT_EQ(count, 0);

  json.JsonDocument document = json.JsonDocument.parse(%"{\"name\":\"x2c\"}");
  defer document.free();
  json.JsonObject object = document.root().object();
  EXPECT_NULL(object[%"missing"]);

  int caught = 0;
  try object.require(%"missing");
  catch %(bad-arg *detail): {
    caught = 1;
    EXPECT_STR_EQ(detail.assoc(<operation>).string(), %"object require");
    EXPECT_STR_EQ(detail.assoc(<key>).string(), %"missing");
  }
  EXPECT_TRUE(caught);

  Var wrong = %"not a member";
  EXPECT_NULL(wrong.jsonmember());
}

static void json_document_preserves_numeric_intent(void) {
  json.JsonDocument document = json.JsonDocument.parse(
    %"[1,-2,3.5,18446744073709551615]"
  );
  defer document.free();
  json.JsonArray values = document.root().array();

  EXPECT_TRUE(values[0].kind() == <uint>);
  EXPECT_TRUE(values[1].kind() == <sint>);
  EXPECT_TRUE(values[2].kind() == <real>);
  EXPECT_TRUE(values[3].kind() == <uint>);
  EXPECT_INT_EQ(values[0].uint(), 1);
  EXPECT_INT_EQ(values[1].sint(), -2);
  EXPECT_TRUE(values[2].real() == 3.5);
  EXPECT_TRUE(values[3].uint() == ULLONG_MAX);

  int count = 0;
  foreach(json.JsonValue value, values) count++;
  EXPECT_INT_EQ(count, 4);
  EXPECT_STR_EQ(values[-1].json(), %"18446744073709551615");
}

static void json_document_conversion_is_explicit_and_lossy(void) {
  json.JsonDocument document = json.JsonDocument.parse(
    %"{\"key\":1,\"key\":2,\"last\":3}"
  );
  defer document.free();

  Map converted = document.to_x2c();
  EXPECT_INT_EQ(converted.len(), 2);
  EXPECT_INT_EQ(converted[%"key"].ulong_long_value(), 2);
  EXPECT_INT_EQ(converted[%"last"].ulong_long_value(), 3);
}

static void json_document_patch_preserves_unrelated_duplicates(void) {
  json.JsonDocument document = json.JsonDocument.parse(
    %"{\"key\":1,\"key\":2,\"last\":3}"
  );
  defer document.free();
  Array operations = %[
    {
      "op": "replace",
      "path": "/last",
      "value": 4
    },
    {
      "op": "add",
      "path": "/active",
      "value": ${json.Json.bool(1)}
    }
  ];
  json.JsonDocument patched = document.patch(operations);
  defer patched.free();

  json.JsonObject object = patched.root().object();
  EXPECT_INT_EQ(object.all(%"key").len(), 2);
  EXPECT_INT_EQ(object[%"last"].sint(), 4);
  EXPECT_TRUE(object[%"active"].boolean());
  EXPECT_STR_EQ(
    patched.json(),
    %"{\"key\":1,\"key\":2,\"last\":4,\"active\":true}"
  );
}

static void json_document_borrowed_views_check_owner(void) {
  json.JsonDocument document = json.JsonDocument.parse(%"{\"name\":\"x2c\"}");
  json.JsonValue root = document.root();
  EXPECT_NULL(document.free());
  EXPECT_NULL(document.free());
  int caught = 0;
  try root.kind();
  catch %(bad-state *detail): {
    caught = 1;
    EXPECT_STR_EQ(detail.assoc(<library>).string(), %"yyjson");
  }
  EXPECT_TRUE(caught);

  caught = 0;
  try document.native();
  catch %(bad-state *detail): {
    caught = 1;
    EXPECT_STR_EQ(detail.assoc(<operation>).string(), %"native");
  }
  EXPECT_TRUE(caught);
}

static void json_document_can_preserve_unrepresentable_string(void) {
  json.JsonDocument document =
    json.JsonDocument.parse(%"\"before\\u0000after\"");
  defer document.free();
  EXPECT_STR_EQ(document.json(), %"\"before\\u0000after\"");

  int caught = 0;
  try document.root().string();
  catch %(bad-enc *detail): {
    caught = 1;
    EXPECT_STR_EQ(detail.assoc(<library>).string(), %"yyjson");
  }
  EXPECT_TRUE(caught);
}

static void json_boolean_and_value_vars_stay_distinct(void) {
  json.JsonDocument document = json.JsonDocument.parse(%"{\"n\":7}");
  defer document.free();
  Var view = document.root();
  Var flag = json.Json.bool(1);

  EXPECT_TRUE(json.Json.is_bool(flag));
  EXPECT_FALSE(json.Json.is_bool(view));
  EXPECT_STR_EQ(flag.str(), %"true");
  EXPECT_STR_EQ(view.str(), %"{\"n\":7}");

  int caught = 0;
  try json.Json.boolean(view);
  catch %(bad-types *detail): {
    caught = 1;
    EXPECT_STR_EQ(detail.assoc(<library>).string(), %"yyjson");
  }
  EXPECT_TRUE(caught);
}

static void json_document_round_trips_through_a_file(void) {
  String path = %"/tmp/x2c-yyjson-document.json";
  String source = %"{\"key\":1,\"key\":2,\"tail\":[1,2]}";
  json.JsonDocument written = json.JsonDocument.parse(source);
  defer written.free();
  EXPECT_NOT_NULL(written.write_file(path));

  /*  The document path keeps order, duplicates, and numeric intent across
      the file, which is why it exists beside Json.read_file.
  */
  json.JsonDocument read = json.JsonDocument.read_file(path);
  defer read.free();
  EXPECT_STR_EQ(read.json(), source);
  EXPECT_INT_EQ(read.root().object().all(%"key").len(), 2);

  /*  The flag has to be checked against the file's bytes: re-reading and
      re-serializing would look identical without it.
  */
  json.JsonDocument pretty = json.JsonDocument.parse(%"{\"a\":1}");
  defer pretty.free();
  pretty.write_file_opts(path, YYJSON_WRITE_PRETTY_TWO_SPACES);
  File indented = File.open(path, %"r");
  String bytes = indented.string_close();
  EXPECT_STR_EQ(bytes, %"{\n  \"a\": 1\n}");

  pretty.write_file(path);
  File compact = File.open(path, %"r");
  EXPECT_STR_EQ(compact.string_close(), %"{\"a\":1}");
}

static void json_write_file_failure_names_its_operation(void) {
  String path = %"/tmp/x2c-yyjson-absent-dir/out.json";

  /*  Both write paths must report themselves, not "stringify", or a caller
      catching %(format *detail) cannot tell which call failed.
  */
  int caught = 0;
  try json.Json.write_file(%{ "a": 1 }, path);
  catch %(format *detail): {
    caught = 1;
    EXPECT_STR_EQ(detail.assoc(<library>).string(), %"yyjson");
    EXPECT_STR_EQ(detail.assoc(<operation>).string(), %"write_file");
    EXPECT_TRUE(detail.assoc(<message>).string().len() > 0);
  }
  EXPECT_TRUE(caught);

  json.JsonDocument document = json.JsonDocument.parse(%"{\"a\":1}");
  defer document.free();
  caught = 0;
  try document.write_file(path);
  catch %(format *detail): {
    caught = 1;
    EXPECT_STR_EQ(detail.assoc(<operation>).string(), %"document write_file");
  }
  EXPECT_TRUE(caught);
}

static void json_value_round_trips_through_a_file(void) {
  String path = %"/tmp/x2c-yyjson-value.json";
  json.Json.write_file(%{ "service": "api", "ports": [80, 443] }, path);

  /*  The converting path returns ordinary x2c values, so the result is a Map
      rather than a document view.
  */
  Var read = json.Json.read_file(path);
  EXPECT_TRUE(read is Map);
  EXPECT_STR_EQ(read.map()[%"service"].string(), %"api");
  EXPECT_INT_EQ(read.map()[%"ports"].array().len(), 2);
}

static void json_file_errors_carry_yyjson_detail(void) {
  int caught = 0;
  try json.JsonDocument.read_file(%"/tmp/x2c-yyjson-absent.json");
  catch %(malformed *detail): {
    caught = 1;
    EXPECT_STR_EQ(detail.assoc(<library>).string(), %"yyjson");
    EXPECT_TRUE(detail.assoc(<code>).integer() != 0);
    EXPECT_TRUE(detail.assoc(<message>).string().len() > 0);
  }
  EXPECT_TRUE(caught);

  /*  Malformed content reports on the same channel. */
  String path = %"/tmp/x2c-yyjson-broken.json";
  File broken = File.open(path, %"w");
  broken.puts(%"{\"unterminated\":");
  broken.close();
  caught = 0;
  try json.JsonDocument.read_file(path);
  catch %(malformed *detail): {
    caught = 1;
    EXPECT_STR_EQ(detail.assoc(<operation>).string(), %"parse");
  }
  EXPECT_TRUE(caught);
}

static void json_file_read_rejects_in_situ(void) {
  int caught = 0;
  try json.JsonDocument.read_file_opts(
    %"/tmp/x2c-yyjson-any.json", YYJSON_READ_INSITU
  );
  catch %(bad-arg *detail): {
    caught = 1;
    EXPECT_STR_EQ(detail.assoc(<operation>).string(), %"document read_file");
  }
  EXPECT_TRUE(caught);
}

static void json_lisp_surface_uses_x2c_values(void) {
  Lisp lisp = Lisp.new();
  defer lisp.destroy();
  json.JsonLisp.install(lisp);

  /*  A parsed document arrives as ordinary x2c values, so the Lisp session
      never holds a borrowed view of a freed document.
  */
  Var parsed = lisp.eval(%(json-parse "{\"ports\":[80,443]}"));
  EXPECT_TRUE(parsed is Map);
  EXPECT_INT_EQ(parsed.map()[%"ports"].array().len(), 2);
  EXPECT_STR_EQ(
    lisp.eval(%(json-stringify (json-parse "[1,2,3]"))).string(), %"[1,2,3]"
  );
  EXPECT_TRUE(
    lisp.eval(%(json-pretty (json-parse "[1]"))).string().len() > 5
  );
  EXPECT_INT_EQ(
    lisp.eval(%(json-pointer (json-parse "{\"a\":[7]}") "/a/0"))
        .ulong_long_value(),
    7
  );

  EXPECT_STR_EQ(
    lisp.eval(%(if (json-parse "false") "yes" "no")).string(), %"no"
  );
  EXPECT_STR_EQ(
    lisp.eval(%(if (json-parse "null") "yes" "no")).string(), %"yes"
  );
  EXPECT_STR_EQ(
    lisp.eval(%(json-stringify (json-parse "false"))).string(), %"false"
  );
  EXPECT_STR_EQ(
    lisp.eval(%(json-stringify (json-parse "null"))).string(), %"null"
  );
  EXPECT_TRUE(lisp.eval(%(json-null? (json-parse "null"))) == <true>);
  EXPECT_TRUE(
    lisp.eval(%(json-pointer (json-parse "{}") "/missing")).is_nil()
  );
  EXPECT_STR_EQ(
    lisp.eval(%(if (json-pointer (json-parse "{\"f\":false}") "/f")
                   "yes" "no")).string(),
    %"no"
  );
  EXPECT_TRUE(
    lisp.eval(%(json-null?
      (json-pointer (json-parse "{\"n\":null}") "/n"))) == <true>
  );

  /*  A JSON array is an x2c Array, which Lisp's own length and cdr do not
      accept; json-len reads it in place and json-list crosses it into the
      List that Lisp does operate on.
  */
  EXPECT_INT_EQ(lisp.eval(%(json-len (json-parse "[1,2,3]"))).int(), 3);
  EXPECT_INT_EQ(
    lisp.eval(%(length (json-keys (json-parse "{\"a\":1,\"b\":2}")))).int(), 2
  );
  EXPECT_STR_EQ(
    lisp.eval(%(json-stringify (cdr (json-list (json-parse "[1,2,3]"))))
             ).string(),
    %"[2,3]"
  );

  String path = %"/tmp/x2c-yyjson-lisp.json";
  lisp.eval(%(json-write-file (json-parse "{\"k\":1}") $path));
  EXPECT_STR_EQ(
    lisp.eval(%(json-stringify (json-read-file $path))).string(),
    %"{\"k\":1}"
  );
}

static void json_lisp_binding_raises_yyjson_detail(void) {
  Lisp lisp = Lisp.new();
  defer lisp.destroy();
  json.JsonLisp.install(lisp);

  int caught = 0;
  try lisp.eval(%(json-parse "{\"broken\":}"));
  catch %(malformed *detail): {
    caught = 1;
    EXPECT_STR_EQ(detail.assoc(<library>).string(), %"yyjson");
    EXPECT_STR_EQ(detail.assoc(<operation>).string(), %"parse");
  }
  EXPECT_TRUE(caught);
}

void json_suite(void) {
  $test.run(json_parse_uses_x2c_values);
  $test.run(json_round_trip_preserves_values);
  $test.run(json_integer_edges_remain_exact);
  $test.run(json_build_and_mutate_with_collections);
  $test.run(json_pointer_distinguishes_null_and_missing);
  $test.run(json_patch_and_merge_patch_return_x2c_values);
  $test.run(json_options_expose_yyjson_flags);
  $test.run(json_in_situ_stays_in_raw_api);
  $test.run(json_parse_error_has_yyjson_detail);
  $test.run(json_rejects_embedded_nul_strings);
  $test.run(json_rejects_values_outside_json_domain);
  $test.run(json_document_preserves_duplicate_member_order);
  $test.run(json_empty_collections_and_required_members_are_explicit);
  $test.run(json_document_preserves_numeric_intent);
  $test.run(json_document_conversion_is_explicit_and_lossy);
  $test.run(json_document_patch_preserves_unrelated_duplicates);
  $test.run(json_document_borrowed_views_check_owner);
  $test.run(json_document_can_preserve_unrepresentable_string);
  $test.run(json_boolean_and_value_vars_stay_distinct);
  $test.run(json_document_round_trips_through_a_file);
  $test.run(json_write_file_failure_names_its_operation);
  $test.run(json_value_round_trips_through_a_file);
  $test.run(json_file_errors_carry_yyjson_detail);
  $test.run(json_file_read_rejects_in_situ);
  $test.run(json_lisp_surface_uses_x2c_values);
  $test.run(json_lisp_binding_raises_yyjson_detail);
}

int main(void) {
  TestHarness_begin();
  $test.suite(json_suite);
  return TestHarness_finish();
}
