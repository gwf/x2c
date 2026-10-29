/*  test-url.x -- unit tests for URL references and query strings */

#include "url.x"
#include "test-support.x"
#include "test-macros.x"

/* Returns the `reason` and `offset` that parsing `text` raises as
   `(reason offset)`, or NULL if it parsed. */
static List _rejection(String text) {
  try Url.parse(text);
  catch %(malformed (operation "Url.parse") (reason ?why) (offset ?at)):
    return Error.snapshot(%($why $at));
  return NULL;
}

static void url_parse_splits_components(void) {
  $test.scoped();
  Url url = Url.parse(
    "https://user:pw@example.com:8443/a%20b?q=1&r=two+words#top");
  EXPECT_STR_EQ(url.scheme, "https");
  EXPECT_STR_EQ(url.userinfo, "user:pw");
  EXPECT_STR_EQ(url.host, "example.com");
  EXPECT_INT_EQ(url.port, 8443);
  EXPECT_STR_EQ(url.path, "/a%20b");
  EXPECT_STR_EQ(url.query, "q=1&r=two+words");
  EXPECT_STR_EQ(url.fragment, "top");
  EXPECT_STR_EQ(url.path.percent_decode(), "/a b");
  Url ipv6 = Url.parse("http://[::1]:8080/");
  EXPECT_STR_EQ(ipv6.host, "::1");
  EXPECT_INT_EQ(ipv6.port, 8080);
  Url empty_port = Url.parse("http://example.com:/");
  EXPECT_INT_EQ(empty_port.port, 0);
}

static void url_parse_accepts_relative_references(void) {
  $test.scoped();
  Url origin = Url.parse("/search?q=x");
  EXPECT_NULL(origin.scheme);
  EXPECT_NULL(origin.host);
  EXPECT_STR_EQ(origin.path, "/search");
  EXPECT_STR_EQ(origin.query, "q=x");
  Url network = Url.parse("//cdn.example/x.js");
  EXPECT_STR_EQ(network.host, "cdn.example");
  EXPECT_STR_EQ(network.path, "/x.js");
  Url mail = Url.parse("mailto:a@b.c");
  EXPECT_STR_EQ(mail.scheme, "mailto");
  EXPECT_NULL(mail.host);
  EXPECT_STR_EQ(mail.path, "a@b.c");
  EXPECT_STR_EQ(Url.parse("#frag").fragment, "frag");
  EXPECT_STR_EQ(Url.parse("a/b:c").path, "a/b:c");
}

static void url_str_reproduces_parsed_text(void) {
  $test.scoped();
  List texts = %(
    "https://user:pw@example.com:8443/a%20b?q=1&r=two+words#top"
    "http://[::1]:8080/" "file:///tmp/x" "/search?q=x" "mailto:a@b.c"
    "//cdn.example/x.js" "?only" "#frag" "relative/path" "urn:isbn:0451450523"
  );
  foreach (String text in texts) EXPECT_STR_EQ(Url.parse(text).str(), text);
  EXPECT_STR_EQ(Url.parse("file:/tmp/x").str(), "file:///tmp/x");
  EXPECT_STR_EQ(Url.parse("http://a/?").str(), "http://a/");
  Url built = Url.new("https", NULL, "example.com", 0, "docs", "v=2", NULL);
  EXPECT_STR_EQ(built.str(), "https://example.com/docs?v=2");
  EXPECT_TRUE(Url.parse("http://a/b") == Url.parse("http://a/b"));
}

static void url_parse_rejects_invalid_text(void) {
  $test.scoped();
  EXPECT_LIST_EQ(_rejection("http://a:99999/"), %("port out of range" 9));
  EXPECT_LIST_EQ(_rejection("http://a:8x/"), %("expected a digit" 10));
  EXPECT_LIST_EQ(_rejection("1http://x"), %("invalid scheme" 0));
  EXPECT_LIST_EQ(_rejection(":x"), %("invalid scheme" 0));
  EXPECT_LIST_EQ(_rejection("http://[::1/"),
                 %("unclosed '[' in the host" 7));
  EXPECT_LIST_EQ(_rejection("http://[::1]x/"), %("expected ':' after ']'" 12));
  EXPECT_LIST_EQ(_rejection("http://a b/"), %("invalid character" 8));
  EXPECT_LIST_EQ(_rejection("http://a/\xc3\xa9"), %("invalid character" 9));
  EXPECT_LIST_EQ(_rejection("http://a/%zz"), %("invalid percent escape" 9));
}

static void url_query_parses_form_fields(void) {
  $test.scoped();
  Map fields = Url.parse_query("q=1&r=two+words&empty&=v&&x=%2B&q=2");
  EXPECT_INT_EQ(fields.len(), 5);
  EXPECT_STR_EQ(fields["q"].string(), "2");
  EXPECT_STR_EQ(fields["r"].string(), "two words");
  EXPECT_TRUE(fields.contains("empty") && !fields["empty"].string());
  EXPECT_STR_EQ(fields[""].string(), "v");
  EXPECT_STR_EQ(fields["x"].string(), "+");
  EXPECT_INT_EQ(Url.parse_query(NULL).len(), 0);
  int caught = 0;
  try Url.parse_query("a=%G0");
  catch %(malformed (operation "String.percent_decode") *): caught++;
  EXPECT_INT_EQ(caught, 1);
}

static void url_query_formats_sorted_pairs(void) {
  $test.scoped();
  String text = Url.format_query({"q": "a b", "n": 3, "z": "x&y"});
  EXPECT_STR_EQ(text, "n=3&q=a%20b&z=x%26y");
  Map back = Url.parse_query(text);
  EXPECT_STR_EQ(back["q"].string(), "a b");
  EXPECT_STR_EQ(back["z"].string(), "x&y");
  EXPECT_STR_EQ(Url.format_query({}), "");
  EXPECT_STR_EQ(Url.format_query({"a": "", "": "b"}), "=b&a=");
}

void url_suite(void) {
  $test.run(url_parse_splits_components);
  $test.run(url_parse_accepts_relative_references);
  $test.run(url_str_reproduces_parsed_text);
  $test.run(url_parse_rejects_invalid_text);
  $test.run(url_query_parses_form_fields);
  $test.run(url_query_formats_sorted_pairs);
}
