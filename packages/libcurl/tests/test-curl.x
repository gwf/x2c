/* test-curl.x -- focused tests for synchronous libcurl easy transfers. */

import "libcurl" with CurlBatch, CurlEasy, CurlHeader, CurlLisp, CurlResponse,
  CurlResponseBlock;

#include "test-support.x"
#include <stdio.h>
#include <string.h>

$(import "../../../unittest/test-macros.xmacro")

static String fixture_url;

static CurlEasy test_easy(void) {
  return CurlEasy.new().timeouts(1000, 3000).follow_redirects(3);
}

static void collect_stream(Bytes chunk, Var data) {
  Block streamed_body = data.block();
  streamed_body.append(chunk, chunk.block().length);
}

static void fail_stream(Bytes chunk, Var data) {
  raise %(malformed (reason "stream consumer failed"));
}

static void curl_response_values_and_header_order(void) {
  CurlEasy easy = test_easy();
  defer easy.free();
  CurlResponse response = easy.get(fixture_url + %"/ok");
  defer response.free();

  EXPECT_INT_EQ(response.response_code(), 200);
  EXPECT_STR_EQ(response.effective_url(), fixture_url + %"/ok");
  EXPECT_INT_EQ(response.body_size(), 5);
  EXPECT_STR_EQ(response.text(), %"hello");
  EXPECT_INT_EQ(response.blocks().len(), 1);

  CurlResponseBlock block = response.blocks().getindex(0);
  EXPECT_STR_EQ(block.status_line(), %"HTTP/1.1 200 OK");
  EXPECT_INT_EQ(block.headers().len(), 5);
  CurlHeader first = block.headers().getindex(0);
  EXPECT_STR_EQ(first.line(), %"Content-Type: text/plain");
  EXPECT_STR_EQ(first.name(), %"Content-Type");
  EXPECT_STR_EQ(first.value(), %"text/plain");

  List traces = block.values(%"x-trace");
  EXPECT_INT_EQ(traces.len(), 2);
  EXPECT_STR_EQ(traces.getindex(0).string(), %"alpha");
  EXPECT_STR_EQ(traces.getindex(1).string(), %"beta");
  EXPECT_INT_EQ(block.values(%"missing").len(), 0);
  List empty = block.values(%"X-Empty");
  EXPECT_INT_EQ(empty.len(), 1);
  EXPECT_NULL(empty.getindex(0).string());
}

static void curl_redirect_preserves_response_blocks(void) {
  CurlEasy easy = test_easy();
  defer easy.free();
  CurlResponse response = easy.get(fixture_url + %"/redirect");
  defer response.free();

  EXPECT_INT_EQ(response.response_code(), 200);
  EXPECT_STR_EQ(response.effective_url(), fixture_url + %"/binary");
  EXPECT_INT_EQ(response.blocks().len(), 2);
  CurlResponseBlock redirect = response.blocks().getindex(0);
  CurlResponseBlock final = response.blocks().getindex(1);
  EXPECT_STR_EQ(redirect.status_line(), %"HTTP/1.1 302 Found");
  EXPECT_STR_EQ(
    redirect.headers().getindex(0).curlheader().line(),
    %"Location: /binary"
  );
  EXPECT_STR_EQ(final.status_line(), %"HTTP/1.1 200 OK");
  EXPECT_INT_EQ(final.values(%"X-Trace").len(), 2);
}

static void curl_binary_body_and_explicit_text_failure(void) {
  CurlEasy easy = test_easy();
  defer easy.free();
  CurlResponse response = easy.get(fixture_url + %"/binary");
  defer response.free();

  EXPECT_INT_EQ(response.body_size(), 7);
  EXPECT_TRUE(!memcmp(response.body(), "abc\0def", 7));
  int caught = 0;
  try response.text();
  catch %(bad-enc *detail): {
    caught = 1;
    EXPECT_STR_EQ(detail.assoc(<library>).string(), %"libcurl");
    EXPECT_STR_EQ(detail.assoc(<operation>).string(), %"text");
  }
  EXPECT_TRUE(caught);
}

static void curl_empty_and_http_error_are_responses(void) {
  CurlEasy easy = test_easy();
  defer easy.free();
  int before = Error.count();
  CurlResponse empty = easy.get(fixture_url + %"/empty");
  defer empty.free();
  CurlResponse missing = easy.get(fixture_url + %"/missing");
  defer missing.free();

  EXPECT_INT_EQ(empty.response_code(), 204);
  EXPECT_NOT_NULL(empty.body());
  EXPECT_INT_EQ(empty.body_size(), 0);
  EXPECT_NULL(empty.text());
  EXPECT_INT_EQ(missing.response_code(), 404);
  EXPECT_STR_EQ(missing.text(), %"not found");
  EXPECT_INT_EQ(Error.count(), before);
}

static void curl_callback_limit_survives_for_next_transfer(void) {
  CurlEasy easy = test_easy().max_body(8);
  defer easy.free();
  int caught = 0;
  try {
    CurlResponse response = easy.get(fixture_url + %"/large");
    if (response) response.free();
  }
  catch %(size-limit *detail): {
    caught = 1;
    EXPECT_STR_EQ(detail.assoc(<library>).string(), %"libcurl");
    EXPECT_STR_EQ(detail.assoc(<operation>).string(), %"easy_perform");
    EXPECT_STR_EQ(detail.assoc(<channel>).string(), %"body");
    EXPECT_INT_EQ(detail.assoc(<limit>).integer(), 8);
  }
  EXPECT_TRUE(caught);

  easy.max_body(32);
  CurlResponse recovered = easy.get(fixture_url + %"/ok");
  defer recovered.free();
  EXPECT_INT_EQ(recovered.response_code(), 200);
  EXPECT_STR_EQ(recovered.text(), %"hello");
}

static void curl_header_limit_is_reported_after_callback(void) {
  CurlEasy easy = test_easy();
  defer easy.free();
  int caught = 0;
  try {
    CurlResponse response = easy.get(fixture_url + %"/headers-large");
    if (response) response.free();
  }
  catch %(size-limit *detail): {
    caught = 1;
    EXPECT_STR_EQ(detail.assoc(<channel>).string(), %"headers");
    EXPECT_INT_EQ(detail.assoc(<limit>).integer(), 256 * 1024);
  }
  EXPECT_TRUE(caught);
}

static void curl_trailer_stays_in_its_response_block(void) {
  CurlEasy easy = test_easy();
  defer easy.free();
  CurlResponse response = easy.get(fixture_url + %"/trailers");
  defer response.free();

  EXPECT_INT_EQ(response.blocks().len(), 1);
  CurlResponseBlock block = response.blocks().getindex(0);
  EXPECT_STR_EQ(block.status_line(), %"HTTP/1.1 200 OK");
  EXPECT_INT_EQ(block.headers().len(), 3);
  EXPECT_STR_EQ(
    block.headers().getindex(2).curlheader().line(),
    %"X-Trailer: finished"
  );
  EXPECT_STR_EQ(block.values(%"X-Trailer").car().string(), %"finished");
  EXPECT_STR_EQ(response.text(), %"hello");
}

static void curl_transport_error_has_native_detail(void) {
  CurlEasy easy = test_easy();
  defer easy.free();
  int caught = 0;
  try {
    CurlResponse response = easy.get(fixture_url + %"/close");
    if (response) response.free();
  }
  catch %(io-fail *detail): {
    caught = 1;
    EXPECT_STR_EQ(detail.assoc(<library>).string(), %"libcurl");
    EXPECT_STR_EQ(detail.assoc(<operation>).string(), %"easy_perform");
    EXPECT_TRUE(detail.assoc(<code>).integer() != 0);
    EXPECT_TRUE(detail.assoc(<message>).string().len() > 0);
    EXPECT_STR_EQ(detail.assoc(<url>).string(), fixture_url + %"/close");
    EXPECT_INT_EQ(detail.assoc(<http-code>).integer(), 0);
  }
  EXPECT_TRUE(caught);
}

static void curl_sequential_reuse_keeps_earlier_response(void) {
  CurlEasy easy = test_easy();
  defer easy.free();
  CurlResponse first = easy.get(fixture_url + %"/ok");
  defer first.free();
  CurlResponse second = easy.get(fixture_url + %"/missing");
  defer second.free();

  EXPECT_INT_EQ(first.response_code(), 200);
  EXPECT_STR_EQ(first.text(), %"hello");
  EXPECT_INT_EQ(
    first.blocks().getindex(0).curlresponseblock()
      .values(%"X-Trace").len(),
    2
  );
  EXPECT_INT_EQ(second.response_code(), 404);
  EXPECT_STR_EQ(second.text(), %"not found");
}

static void curl_copies_transient_url_and_response_context(void) {
  CurlEasy easy = test_easy();
  defer easy.free();
  String expected = fixture_url + %"/ok";
  String transient = String.malloc(expected.len() + 1);
  memcpy(transient, expected, expected.len() + 1);

  CurlResponse response = easy.get(transient);
  transient.free();
  defer response.free();
  EXPECT_STR_EQ(response.effective_url(), expected);
  EXPECT_STR_EQ(response.text(), %"hello");
}

static void curl_release_is_idempotent_and_stale_use_fails(void) {
  CurlEasy easy = test_easy();
  CurlResponse response = easy.get(fixture_url + %"/ok");
  EXPECT_NULL(response.free());
  EXPECT_NULL(response.free());

  int caught = 0;
  try response.body_size();
  catch %(bad-state *detail): {
    caught = 1;
    EXPECT_STR_EQ(detail.assoc(<library>).string(), %"libcurl");
  }
  EXPECT_TRUE(caught);
  EXPECT_NULL(easy.free());
  EXPECT_NULL(easy.free());
}

static void curl_batch_path_distinguishes_outcomes(void) {
  CurlEasy easy = test_easy().max_body(32);
  defer easy.free();
  List paths = %("/ok" "/redirect" "/empty" "/missing" "/large" "/close");
  int responses = 0, size_failures = 0, transfer_failures = 0;

  foreach(String path, paths) {
    try {
      CurlResponse response = easy.get(fixture_url + path);
      defer response.free();
      responses++;
    }
    catch %(size-limit *): size_failures++;
    catch %(io-fail *): transfer_failures++;
  }
  EXPECT_INT_EQ(responses, 4);
  EXPECT_INT_EQ(size_failures, 1);
  EXPECT_INT_EQ(transfer_failures, 1);
}

static void curl_easy_retains_request_configuration(void) {
  CurlEasy easy = CurlEasy.new()
    .timeouts(1000, 3000)
    .follow_redirects(3)
    .max_body(1024)
    .user_agent(%"x2c-compat-test/1")
    .header(%"Accept: application/json");
  defer easy.free();

  CurlResponse response = easy.get(fixture_url + %"/compat");
  defer response.free();
  EXPECT_INT_EQ(response.response_code(), 200);
  EXPECT_INT_EQ(response.body_size(), 7);
  EXPECT_STR_EQ(response.text(), %"matched");
  CurlResponseBlock block = response.blocks().car();
  EXPECT_STR_EQ(block.values(%"X-Compat").car().string(), %"matched");
  EXPECT_INT_EQ(block.headers().len(), 2);
}

static void curl_native_handle_configures_the_next_transfer(void) {
  CurlEasy easy = test_easy().header(%"Accept: application/json");
  defer easy.free();
  curl_easy_setopt(easy.native(), CURLOPT_USERAGENT, "x2c-compat-test/1");

  CurlResponse response = easy.get(fixture_url + %"/compat");
  defer response.free();
  EXPECT_INT_EQ(response.response_code(), 200);
  EXPECT_STR_EQ(response.text(), %"matched");

  EXPECT_NULL(easy.free());
  int caught = 0;
  try easy.native();
  catch %(bad-arg *detail): {
    caught = 1;
    EXPECT_STR_EQ(detail.assoc(<operation>).string(), %"native");
  }
  EXPECT_TRUE(caught);
}

typedef struct NativeBody {
  char bytes[32];
  size_t length;
} NativeBody;

/*  The write callback a caller of `native()` brings for its own transfer. */
static size_t native_collect(
  char *data, size_t size, size_t count, void *context) {
  NativeBody *collected = context;
  size_t length = size * count;
  if (length > sizeof(collected.bytes) - collected.length) return 0;
  memcpy(collected.bytes + collected.length, data, length);
  collected.length += length;
  return length;
}

/*  The raw API is only usable if the handle works on its own afterwards.
    An ordinary request installs a header list the wrapper frees on the way
    out, and a write callback whose context ends with that frame; libcurl
    keeps both until told otherwise, so a direct perform would walk a freed
    slist and abort on the callback's zero return.
*/
static void curl_native_handle_performs_its_own_transfer(void) {
  CurlEasy easy = test_easy().header(%"Accept: application/json");
  defer easy.free();
  curl_easy_setopt(easy.native(), CURLOPT_USERAGENT, "x2c-compat-test/1");
  CurlResponse configured = easy.get(fixture_url + %"/compat");
  defer configured.free();
  EXPECT_INT_EQ(configured.response_code(), 200);

  CURL *handle = easy.native();
  NativeBody collected = { 0 };
  EXPECT_INT_EQ(
    curl_easy_setopt(handle, CURLOPT_URL, (char *) (fixture_url + %"/ok")),
    CURLE_OK
  );
  EXPECT_INT_EQ(
    curl_easy_setopt(handle, CURLOPT_WRITEFUNCTION, native_collect), CURLE_OK
  );
  EXPECT_INT_EQ(
    curl_easy_setopt(handle, CURLOPT_WRITEDATA, &collected), CURLE_OK
  );
  EXPECT_INT_EQ(curl_easy_perform(handle), CURLE_OK);
  EXPECT_INT_EQ((int) collected.length, 5);
  EXPECT_TRUE(!memcmp(collected.bytes, "hello", 5));

  /*  And the ordinary path still owns the handle after that transfer. */
  CurlResponse ordinary = easy.get(fixture_url + %"/compat");
  defer ordinary.free();
  EXPECT_STR_EQ(ordinary.text(), %"matched");
}

static void curl_post_sends_a_body_with_its_content_type(void) {
  CurlEasy easy = test_easy();
  defer easy.free();
  CurlResponse posted = easy.body(%"application/json", %"{\"n\":1}")
    .request(%"POST", fixture_url + %"/echo");
  defer posted.free();

  EXPECT_INT_EQ(posted.response_code(), 200);
  EXPECT_INT_EQ(posted.upload_size(), 7);
  String echoed = posted.text();
  EXPECT_NOT_NULL(strstr(echoed, "\"method\": \"POST\""));
  EXPECT_NOT_NULL(strstr(echoed, "\"type\": \"application/json\""));
  EXPECT_NOT_NULL(strstr(echoed, "\"length\": 7"));

  /*  The body belongs to that one request; the next carries none. */
  CurlResponse next = easy.get(fixture_url + %"/echo");
  defer next.free();
  EXPECT_NOT_NULL(strstr(next.text(), "\"method\": \"GET\""));
  EXPECT_NOT_NULL(strstr(next.text(), "\"length\": 0"));
  EXPECT_INT_EQ(next.upload_size(), 0);
}

static void curl_binary_request_body_preserves_nul(void) {
  CurlEasy easy = test_easy();
  defer easy.free();
  Bytes content = Bytes.new(2).append("a\0b\0", 2);
  CurlResponse response = easy
    .body_bytes(%"application/octet-stream", content)
    .request(%"POST", fixture_url + %"/echo");
  defer response.free();

  EXPECT_INT_EQ(response.response_code(), 200);
  EXPECT_INT_EQ(response.upload_size(), 4);
  EXPECT_NOT_NULL(strstr(response.text(), "\"length\": 4"));
}

static void curl_head_and_other_methods_reach_the_server(void) {
  CurlEasy easy = test_easy();
  defer easy.free();
  CurlResponse head = easy.request(%"HEAD", fixture_url + %"/large");
  defer head.free();

  EXPECT_INT_EQ(head.response_code(), 200);
  EXPECT_INT_EQ(head.body_size(), 0);
  CurlResponseBlock block = head.blocks().car();
  EXPECT_STR_EQ(block.values(%"Content-Length").car().string(), %"64");

  CurlResponse deleted = easy.request(%"DELETE", fixture_url + %"/echo");
  defer deleted.free();
  EXPECT_NOT_NULL(strstr(deleted.text(), "\"method\": \"DELETE\""));

  /*  HEAD is not sticky either: the next GET brings its body back. */
  CurlResponse body = easy.get(fixture_url + %"/large");
  defer body.free();
  EXPECT_INT_EQ(body.body_size(), 64);
}

static void curl_basic_auth_unlocks_a_protected_path(void) {
  CurlEasy easy = test_easy();
  defer easy.free();
  CurlResponse denied = easy.get(fixture_url + %"/secret");
  defer denied.free();
  EXPECT_INT_EQ(denied.response_code(), 401);

  CurlResponse allowed = easy.basic_auth(%"user", %"s3cret")
    .get(fixture_url + %"/secret");
  defer allowed.free();
  EXPECT_INT_EQ(allowed.response_code(), 200);
  EXPECT_STR_EQ(allowed.text(), %"release-7 signing key");
}

static void curl_transfer_info_describes_the_exchange(void) {
  CurlEasy easy = test_easy();
  defer easy.free();
  CurlResponse response = easy.body(%"text/plain", %"ping")
    .request(%"POST", fixture_url + %"/echo");
  defer response.free();

  EXPECT_TRUE(response.elapsed_us() > 0);
  EXPECT_INT_EQ(response.upload_size(), 4);
  EXPECT_INT_EQ(response.body_size(), response.text().len());
}

static void curl_escapes_and_unescapes_url_components(void) {
  EXPECT_STR_EQ(CurlEasy.escape(%"a b&c/d"), %"a%20b%26c%2Fd");
  EXPECT_STR_EQ(CurlEasy.unescape(%"a%20b%26c%2Fd"), %"a b&c/d");
  int caught = 0;
  try CurlEasy.unescape(%"a%00b");
  catch %(bad-enc *detail): {
    caught = 1;
    EXPECT_STR_EQ(detail.assoc(<operation>).string(), %"unescape");
  }
  EXPECT_TRUE(caught);

  CurlEasy easy = test_easy();
  defer easy.free();
  CurlResponse response = easy.get(
    fixture_url + %"/search?q=" + CurlEasy.escape(%"a b&c")
  );
  defer response.free();
  EXPECT_STR_EQ(response.text(), %"searched for a b&c");
}

static void curl_download_streams_past_the_body_limit(void) {
  String path = %"/tmp/x2c-libcurl-download.bin";
  CurlEasy easy = test_easy().max_body(8);
  defer easy.free();
  CurlResponse response = easy.download(fixture_url + %"/download", path);
  defer response.free();

  EXPECT_INT_EQ(response.response_code(), 200);
  EXPECT_INT_EQ(response.body_size(), 3072);
  int caught = 0;
  try response.text();
  catch %(bad-state *detail): {
    caught = 1;
    EXPECT_STR_EQ(detail.assoc(<path>).string(), path);
  }
  EXPECT_TRUE(caught);

  String written = File.open(path, "rb").string_close();
  EXPECT_INT_EQ(written.len(), 3072);
  EXPECT_TRUE(!strncmp(written, "packet 0000\n", 12));
  remove(path);
}

static void curl_stream_delivers_chunks_without_buffering(void) {
  Block streamed_body = Block.new(1);
  defer streamed_body.free();
  CurlEasy easy = test_easy().max_body(8);
  defer easy.free();
  CurlResponse response = easy.stream(
    fixture_url + %"/download", streamed_body, collect_stream
  );
  defer response.free();

  EXPECT_INT_EQ(response.response_code(), 200);
  EXPECT_INT_EQ(response.body_size(), 3072);
  EXPECT_INT_EQ(streamed_body.length, 3072);
  EXPECT_TRUE(!memcmp(streamed_body.bytes, "packet 0000\n", 12));
  EXPECT_STR_EQ(
    response.blocks().car().curlresponseblock()
      .values(%"Content-Type").car().string(),
    %"application/octet-stream"
  );
  int caught = 0;
  try response.body();
  catch %(bad-state *detail): {
    caught = 1;
    EXPECT_STR_EQ(
      detail.assoc(<reason>).string(),
      %"response body was passed to a callback"
    );
  }
  EXPECT_TRUE(caught);
}

static void curl_stream_contains_callback_errors(void) {
  CurlEasy easy = test_easy();
  defer easy.free();
  int caught = 0;
  try {
    CurlResponse response = easy.stream(
      fixture_url + %"/ok", void, fail_stream
    );
    if (response) response.free();
  }
  catch %(malformed *detail): {
    caught = 1;
    EXPECT_STR_EQ(
      detail.assoc(<reason>).string(), %"stream consumer failed"
    );
  }
  EXPECT_TRUE(caught);

  CurlResponse recovered = easy.get(fixture_url + %"/ok");
  defer recovered.free();
  EXPECT_STR_EQ(recovered.text(), %"hello");
}

static void curl_lisp_bindings_return_values_lisp_consumes(void) {
  Lisp lisp = Lisp.new();
  defer lisp.destroy();
  CurlLisp.install(lisp);

  EXPECT_INT_EQ(
    lisp.eval(%( string-length (http-get ${fixture_url + %"/ok"}) )).integer(),
    5
  );
  EXPECT_STR_EQ(
    lisp.eval(%( substring (http-get ${fixture_url + %"/ok"}) 0 4 )).string(),
    %"hell"
  );
  EXPECT_INT_EQ(
    lisp.eval(%( + 1 (http-status ${fixture_url + %"/missing"}) )).integer(),
    405
  );
  EXPECT_INT_EQ(
    lisp.eval(%( length (http-headers ${fixture_url + %"/ok"}) )).integer(), 5
  );
  EXPECT_STR_EQ(lisp.eval(%( url-escape "a b" )).string(), %"a%20b");
  EXPECT_STR_EQ(
    lisp.eval(%(
      substring (http-post ${fixture_url + %"/echo"} "text/plain" "ping")
                9 15
    )).string(),
    %"\"ping\""
  );
}

static void curl_concurrent_batch_preserves_input_order_and_bound(void) {
  CurlEasy easy = test_easy();
  defer easy.free();
  CurlResponse reset = easy.get(fixture_url + %"/batch/reset");
  defer reset.free();
  List paths = %("/batch/delay?name=one&ms=20"
                 "/batch/delay?name=two&ms=20"
                 "/batch/delay?name=three&ms=20");
  List urls = paths.map(%!(String path) => fixture_url + path);
  CurlBatch serial = easy.get_all(urls, 1);
  defer serial.free();
  EXPECT_INT_EQ(serial.len(), 3);
  EXPECT_STR_EQ(serial.response(0).text(), %"one");
  EXPECT_STR_EQ(serial.response(2).text(), %"three");
  CurlResponse serial_stats = easy.get(fixture_url + %"/batch/stats");
  defer serial_stats.free();
  EXPECT_STR_EQ(serial_stats.text(), %"1 one,two,three");

  CurlResponse again = easy.get(fixture_url + %"/batch/reset");
  defer again.free();
  paths = %("/batch/delay?name=slow&ms=200&barrier=3"
            "/batch/delay?name=fast&barrier=3"
            "/batch/delay?name=middle&ms=50&barrier=3"
            "/batch/delay?name=last");
  urls = paths.map(%!(String path) => fixture_url + path);
  CurlBatch parallel = easy.get_all(urls, 3);
  defer parallel.free();
  EXPECT_INT_EQ(parallel.len(), 4);
  EXPECT_STR_EQ(parallel.response(0).text(), %"slow");
  EXPECT_STR_EQ(parallel.response(1).text(), %"fast");
  EXPECT_STR_EQ(parallel.response(2).text(), %"middle");
  EXPECT_STR_EQ(parallel.response(3).text(), %"last");
  CurlResponse parallel_stats = easy.get(fixture_url + %"/batch/stats");
  defer parallel_stats.free();
  EXPECT_TRUE(parallel_stats.text().startswith(%"3 fast,"));
  EXPECT_TRUE(parallel_stats.text().endswith(%",slow"));
}

static void curl_concurrent_batch_retains_each_failure(void) {
  CurlEasy easy = test_easy().max_body(32);
  defer easy.free();
  List paths = %("/ok" "/close" "/large" "/missing" "/ok");
  CurlBatch batch = easy.get_all(
    paths.map(%!(String path) => fixture_url + path), 2);
  defer batch.free();
  EXPECT_INT_EQ(batch.len(), 5);
  EXPECT_STR_EQ(batch.response(0).text(), %"hello");
  EXPECT_INT_EQ(batch.response(3).response_code(), 404);
  EXPECT_STR_EQ(batch.response(4).text(), %"hello");
  int transport = 0, limit = 0;
  try batch.response(1);
  catch %(io-fail *detail): {
    transport = 1;
    EXPECT_STR_EQ(detail.assoc(<operation>).string(), %"multi_info_read");
    EXPECT_INT_EQ(detail.assoc(<code>).integer(), CURLE_GOT_NOTHING);
    EXPECT_STR_EQ(detail.assoc(<url>).string(), fixture_url + %"/close");
  }
  try batch.response(2);
  catch %(size-limit *detail): {
    limit = 1;
    EXPECT_STR_EQ(detail.assoc(<operation>).string(), %"multi_info_read");
    EXPECT_INT_EQ(detail.assoc(<limit>).integer(), 32);
    EXPECT_STR_EQ(detail.assoc(<channel>).string(), %"body");
  }
  EXPECT_TRUE(transport && limit);
  CurlResponse reused = easy.get(fixture_url + %"/ok");
  defer reused.free();
  EXPECT_STR_EQ(reused.text(), %"hello");
  EXPECT_STR_EQ(batch.response(0).text(), %"hello");
}

static void curl_concurrent_batch_broadcasts_body_and_raw_options(void) {
  CurlEasy easy = test_easy();
  defer easy.free();
  String echo = fixture_url + %"/echo";
  CurlBatch batch = easy.body(%"text/plain", %"ping")
    .request_all(%"POST", %($echo $echo $echo), 2);
  defer batch.free();
  for (int i = 0; i < batch.len(); i++) {
    String text = batch.response(i).text();
    EXPECT_TRUE(text.contains(%"\"method\": \"POST\""));
    EXPECT_TRUE(text.contains(%"\"body\": \"ping\""));
    EXPECT_INT_EQ(batch.response(i).upload_size(), 4);
  }
  CurlResponse reused = easy.get(echo);
  defer reused.free();
  EXPECT_TRUE(reused.text().contains(%"\"length\": 0"));
  EXPECT_TRUE(reused.text().contains(%"\"method\": \"GET\""));

  Bytes body = Bytes.new(1);
  defer body.free();
  CurlResponse single = easy.body_bytes(%"application/json", body)
    .request(%"POST", echo);
  defer single.free();
  EXPECT_TRUE(single.text().contains(%"\"content_length\": \"0\""));
  CurlResponse single_reset = easy.get(echo);
  defer single_reset.free();
  EXPECT_TRUE(single_reset.text().contains(%"\"content_length\": null"));
  CurlBatch empty_body = easy.body_bytes(%"application/json", body)
    .request_all(%"POST", %($echo $echo $echo), 2);
  defer empty_body.free();
  for (int i = 0; i < empty_body.len(); i++) {
    String text = empty_body.response(i).text();
    EXPECT_TRUE(text.contains(%"\"method\": \"POST\""));
    EXPECT_TRUE(text.contains(%"\"type\": \"application/json\""));
    EXPECT_TRUE(text.contains(%"\"length\": 0"));
    EXPECT_TRUE(text.contains(%"\"content_length\": \"0\""));
  }
  CurlResponse reset = easy.get(echo);
  defer reset.free();
  EXPECT_TRUE(reset.text().contains(%"\"method\": \"GET\""));
  EXPECT_TRUE(reset.text().contains(%"\"type\": \"\""));
  EXPECT_TRUE(reset.text().contains(%"\"length\": 0"));
  EXPECT_TRUE(reset.text().contains(%"\"content_length\": null"));

  CURLcode set = curl_easy_setopt(easy.native(), CURLOPT_USERAGENT,
                                  "x2c-compat-test/1");
  EXPECT_INT_EQ(set, CURLE_OK);
  easy.header(%"Accept: application/json");
  String compat = fixture_url + %"/compat";
  CurlBatch configured = easy.get_all(%($compat $compat), 2);
  defer configured.free();
  EXPECT_STR_EQ(configured.response(0).text(), %"matched");
  EXPECT_STR_EQ(configured.response(1).text(), %"matched");
}

static void curl_concurrent_batch_empty_lifetime_and_timeout(void) {
  CurlEasy easy = test_easy();
  defer easy.free();
  CurlBatch empty = easy.body(%"text/plain", %"not sent")
    .get_all(NULL, 2);
  EXPECT_INT_EQ(empty.len(), 0);
  empty.free();
  empty.free();
  CurlResponse echo = easy.get(fixture_url + %"/echo");
  defer echo.free();
  EXPECT_TRUE(echo.text().contains(%"\"length\": 0"));
  int stale = 0, invalid = 0;
  try empty.response(0);
  catch %(bad-state *): stale = 1;
  try easy.get_all(NULL, 0);
  catch %(bad-arg *): invalid = 1;
  EXPECT_TRUE(stale && invalid);

  easy.timeouts(100, 100);
  String slow = fixture_url + %"/batch/delay?ms=500";
  String ok = fixture_url + %"/ok";
  CurlBatch batch = easy.get_all(%($slow $ok), 2);
  defer batch.free();
  int timeout = 0;
  try batch.response(0);
  catch %(io-fail *detail): {
    timeout = 1;
    EXPECT_INT_EQ(detail.assoc(<code>).integer(), CURLE_OPERATION_TIMEDOUT);
  }
  EXPECT_TRUE(timeout);
  easy.free();
  EXPECT_STR_EQ(batch.response(1).text(), %"hello");
}

void curl_suite(void) {
  $test.run(curl_response_values_and_header_order);
  $test.run(curl_redirect_preserves_response_blocks);
  $test.run(curl_binary_body_and_explicit_text_failure);
  $test.run(curl_empty_and_http_error_are_responses);
  $test.run(curl_callback_limit_survives_for_next_transfer);
  $test.run(curl_header_limit_is_reported_after_callback);
  $test.run(curl_trailer_stays_in_its_response_block);
  $test.run(curl_transport_error_has_native_detail);
  $test.run(curl_sequential_reuse_keeps_earlier_response);
  $test.run(curl_copies_transient_url_and_response_context);
  $test.run(curl_release_is_idempotent_and_stale_use_fails);
  $test.run(curl_batch_path_distinguishes_outcomes);
  $test.run(curl_easy_retains_request_configuration);
  $test.run(curl_native_handle_configures_the_next_transfer);
  $test.run(curl_native_handle_performs_its_own_transfer);
  $test.run(curl_post_sends_a_body_with_its_content_type);
  $test.run(curl_binary_request_body_preserves_nul);
  $test.run(curl_head_and_other_methods_reach_the_server);
  $test.run(curl_basic_auth_unlocks_a_protected_path);
  $test.run(curl_transfer_info_describes_the_exchange);
  $test.run(curl_escapes_and_unescapes_url_components);
  $test.run(curl_download_streams_past_the_body_limit);
  $test.run(curl_stream_delivers_chunks_without_buffering);
  $test.run(curl_stream_contains_callback_errors);
  $test.run(curl_lisp_bindings_return_values_lisp_consumes);
  $test.run(curl_concurrent_batch_preserves_input_order_and_bound);
  $test.run(curl_concurrent_batch_retains_each_failure);
  $test.run(curl_concurrent_batch_broadcasts_body_and_raw_options);
  $test.run(curl_concurrent_batch_empty_lifetime_and_timeout);
}

int main(int argc, char **argv) {
  if (argc != 2) return 2;
  fixture_url = String.new(argv[1]);
  TestHarness_begin();
  $test.suite(curl_suite);
  return TestHarness_finish();
}
