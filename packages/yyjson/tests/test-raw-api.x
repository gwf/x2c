/* test-raw-api.x -- prove the complete pinned yyjson header is direct. */

#include "yyjson-0.12.h"
#include "test-support.x"
#include <stdlib.h>
#include <string.h>

$(import "../../../unittest/test-macros.xmacro")

static void yyjson_raw_read_iterate_and_write(void) {
  char source[] = "{\"values\":[2,3,5],\"valid\":true}";
  yyjson_doc *document = yyjson_read(source, strlen(source), 0);
  EXPECT_NOT_NULL(document);
  defer yyjson_doc_free(document);

  yyjson_val *root = yyjson_doc_get_root(document);
  yyjson_val *values = yyjson_obj_get(root, "values");
  EXPECT_TRUE(yyjson_is_arr(values));
  EXPECT_INT_EQ(yyjson_arr_size(values), 3);

  unsigned total = 0;
  yyjson_arr_iter iter = yyjson_arr_iter_with(values);
  yyjson_val *item = NULL;
  while ((item = yyjson_arr_iter_next(&iter))) total += yyjson_get_uint(item);
  EXPECT_INT_EQ(total, 10);

  size_t length = 0;
  char *encoded = yyjson_val_write(root, 0, &length);
  EXPECT_NOT_NULL(encoded);
  EXPECT_TRUE(length > 0);
  free(encoded);
}

void raw_api_suite(void) {
  $test.run(yyjson_raw_read_iterate_and_write);
}

int main(void) {
  TestHarness_begin();
  $test.suite(raw_api_suite);
  return TestHarness_finish();
}
