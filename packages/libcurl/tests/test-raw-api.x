/* test-raw-api.x -- direct calls through the pinned libcurl header. */

#include "curl-822.h"
#include "test-support.x"
#include <string.h>

$(import "../../../unittest/test-macros.xmacro")

static String fixture_url;

static size_t raw_count(char *data, size_t size, size_t count, void *context) {
  size_t length = size * count, *total = context;
  *total += length;
  return length;
}

static void curl_raw_version_and_url_api(void) {
  curl_version_info_data *version = curl_version_info(CURLVERSION_NOW);
  EXPECT_NOT_NULL(version);
  EXPECT_INT_EQ(version->version_num, LIBCURL_VERSION_NUM);
  EXPECT_TRUE(version->features & CURL_VERSION_SSL);

  CURLU *url = curl_url();
  EXPECT_NOT_NULL(url);
  EXPECT_INT_EQ(
    curl_url_set(url, CURLUPART_URL, "https://example.com/a", 0),
    CURLUE_OK
  );
  char *host = NULL;
  EXPECT_INT_EQ(curl_url_get(url, CURLUPART_HOST, &host, 0), CURLUE_OK);
  EXPECT_STR_EQ(host, %"example.com");
  curl_free(host);
  curl_url_cleanup(url);
}

static void curl_raw_easy_transfer(void) {
  EXPECT_INT_EQ(curl_global_init(CURL_GLOBAL_DEFAULT), CURLE_OK);
  defer curl_global_cleanup();
  CURL *easy = curl_easy_init();
  EXPECT_NOT_NULL(easy);
  if (!easy) return;
  defer curl_easy_cleanup(easy);

  size_t received = 0;
  EXPECT_INT_EQ(curl_easy_setopt(easy, CURLOPT_URL, fixture_url), CURLE_OK);
  EXPECT_INT_EQ(
    curl_easy_setopt(easy, CURLOPT_WRITEFUNCTION, raw_count), CURLE_OK
  );
  EXPECT_INT_EQ(
    curl_easy_setopt(easy, CURLOPT_WRITEDATA, &received), CURLE_OK
  );
  EXPECT_INT_EQ(curl_easy_perform(easy), CURLE_OK);
  long response_code = 0;
  EXPECT_INT_EQ(
    curl_easy_getinfo(easy, CURLINFO_RESPONSE_CODE, &response_code),
    CURLE_OK
  );
  EXPECT_INT_EQ(response_code, 200);
  EXPECT_INT_EQ(received, 5);
}

void curl_raw_suite(void) {
  $test.run(curl_raw_version_and_url_api);
  $test.run(curl_raw_easy_transfer);
}

int main(int argc, char **argv) {
  if (argc != 2) return 2;
  fixture_url = String.new(argv[1]) + %"/ok";
  TestHarness_begin();
  $test.suite(curl_raw_suite);
  return TestHarness_finish();
}
