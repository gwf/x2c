/*  test-digest.x -- unit tests for SHA-256 digests */

#include "digest.x"
#include "test-support.x"
$(import "test-macros.xmacro")
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <unistd.h>

/* The FIPS 180-4 examples, including the 448-bit message whose padding
   needs a second block. */
static void digest_string_matches_nist_vectors(void) {
  $test.scoped();
  EXPECT_STR_EQ(((String) NULL).sha256(),
    "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
  EXPECT_STR_EQ("abc".sha256(),
    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
  String two_blocks =
    "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq";
  EXPECT_STR_EQ(two_blocks.sha256(),
    "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1");
  EXPECT_STR_EQ("a".repeat(1000000).sha256(),
    "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0");
}

static void digest_string_pads_at_block_boundaries(void) {
  $test.scoped();
  EXPECT_STR_EQ("a".repeat(55).sha256(),
    "9f4390f8d30c2dd92ec9f095b65e2b9ae9b0a925a5258e241c9f1e910f734318");
  EXPECT_STR_EQ("a".repeat(56).sha256(),
    "b35439a4ac6f0948b6d6f9e3c6af0f5f590ce20f1bde7090ef7970686ec6738a");
  EXPECT_STR_EQ("a".repeat(63).sha256(),
    "7d3e74a05d7db15bce4ad9ec0658ea98e3f06eeecf16b4c6fff2da457ddc2f34");
  EXPECT_STR_EQ("a".repeat(64).sha256(),
    "ffe054fe7ae0cb6dc65c3af9b61d5209f439851db43d0ba5997337df154668eb");
  EXPECT_STR_EQ("a".repeat(65).sha256(),
    "635361c48bb9eab14198e76ea8ab7f1a41685d6ad62aa9146d301d4f17eb0ae0");
}

static void digest_file_reads_raw_bytes(void) {
  $test.scoped();
  File file = tmpfile();
  if (!EXPECT_NOT_NULL(file)) return;
  unsigned char bytes[768];
  for (int i = 0; i < 768; i++) bytes[i] = (unsigned char) i;
  file.write_all(bytes, sizeof(bytes));
  rewind(file);
  EXPECT_STR_EQ(file.sha256(),
    "f3a25aa93aa2fbba28d79260535bbd6a5eb0fc1c24a8b0f04e12b484c1dfe363");
  EXPECT_TRUE(file.eof());
  file.seek(100, SEEK_SET);
  EXPECT_STR_EQ(file.sha256(),
    "5c3cfef1a72b02e4f2b01132727af596bc2bd9270e518e36eb3953eabe9bd430");
  EXPECT_STR_EQ(file.sha256(), ((String) NULL).sha256());
  file.close();
}

static void digest_file_spans_read_buffers(void) {
  $test.scoped();
  File file = tmpfile();
  if (!EXPECT_NOT_NULL(file)) return;
  String text = "a".repeat(1000000);
  file.write_all(text, text.len());
  rewind(file);
  EXPECT_STR_EQ(file.sha256(), text.sha256());
  file.close();
}

static void digest_file_read_failure_raises(void) {
  $test.scoped();
  int descriptor = open("/dev/null", O_WRONLY);
  if (!EXPECT_TRUE(descriptor >= 0)) return;
  File file = fdopen(descriptor, "w");
  if (!EXPECT_NOT_NULL(file)) {
    close(descriptor);
    return;
  }
  int caught = 0;
  try file.sha256();
  catch %(io-fail *detail): {
    caught++;
    EXPECT_TRUE(detail.assoc(<operation>).symbol() == <read>);
    EXPECT_INT_EQ(detail.assoc(<errno>).integer(), EBADF);
  }
  EXPECT_INT_EQ(caught, 1);
  file.close();
}

void digest_suite(void) {
  $test.run(digest_string_matches_nist_vectors);
  $test.run(digest_string_pads_at_block_boundaries);
  $test.run(digest_file_reads_raw_bytes);
  $test.run(digest_file_spans_read_buffers);
  $test.run(digest_file_read_failure_raises);
}
