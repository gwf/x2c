/*  test-block.x -- unit tests for checked Block and Bytes storage */

#include "test-support.x"
$(import "test-macros.xmacro")
#include <stdint.h>
#include <string.h>

static void bytes_append_and_len(void) {
  $test.scoped();
  Bytes bytes = Bytes.new(sizeof(double));
  EXPECT_INT_EQ(Bytes.len(bytes), 0);
  double samples[] = {0.5, 1.5, 2.5};
  bytes = Bytes.append(bytes, samples, 3);
  EXPECT_INT_EQ(Bytes.len(bytes), 3);
  double *out = bytes;
  EXPECT_TRUE(out[0] == samples[0]);
  EXPECT_TRUE(out[2] == samples[2]);
}

static void reserve_truncate_and_clear(void) {
  $test.scoped();
  Block block = Block.new(sizeof(int));
  int values[] = {1, 2, 3};
  block.append(values, 3);
  size_t capacity = block.capacity();
  block.reserve(capacity + 5);
  EXPECT_INT_EQ(block.len(), 3);
  EXPECT_TRUE(block.capacity() >= capacity + 5);
  EXPECT_INT_EQ(((int *) block.bytes)[2], 3);
  block.truncate(2);
  EXPECT_INT_EQ(block.len(), 2);
  block.truncate(20);
  EXPECT_INT_EQ(block.len(), 2);
  block.clear();
  EXPECT_INT_EQ(block.len(), 0);
  EXPECT_TRUE(block.capacity() >= capacity + 5);
}

static void zero_and_fill_append(void) {
  $test.scoped();
  Block zeros = Block.new(sizeof(int));
  Bytes before = zeros.bytes;
  size_t capacity = zeros.cap;
  zeros.append(NULL, 0);
  EXPECT_TRUE(zeros.bytes == before);
  EXPECT_INT_EQ(zeros.len(), 0);
  EXPECT_INT_EQ(zeros.cap, capacity);
  zeros.append(NULL, 4);
  int *zero_values = zeros.bytes;
  EXPECT_INT_EQ(zeros.len(), 4);
  EXPECT_INT_EQ(zero_values[0], 0);
  EXPECT_INT_EQ(zero_values[3], 0);

  Block fills = Block.new(sizeof(int));
  int seven = 7;
  fills.append_fill(&seven, 4);
  int *fill_values = fills.bytes;
  EXPECT_INT_EQ(fills.len(), 4);
  EXPECT_INT_EQ(fill_values[0], 7);
  EXPECT_INT_EQ(fill_values[3], 7);
}

static void self_append_with_and_without_growth(void) {
  $test.scoped();
  Block stable = Block.new(sizeof(char));
  stable.reserve(8);
  stable.append("abc", 3);
  stable.append(stable.bytes, 3);
  EXPECT_INT_EQ(stable.len(), 6);
  EXPECT_TRUE(memcmp(stable.bytes, "abcabc", 6) == 0);
  stable.append((char *) stable.bytes + 1, 2);
  EXPECT_TRUE(memcmp(stable.bytes, "abcabcbc", 8) == 0);

  Block growing = Block.new(sizeof(char));
  growing.append("x", 1);
  growing.append(growing.bytes, 1);
  EXPECT_INT_EQ(growing.len(), 2);
  EXPECT_TRUE(memcmp(growing.bytes, "xx", 2) == 0);
}

static void self_append_uses_initialized_capacity(void) {
  $test.scoped();
  Block stable = Block.new(sizeof(char));
  stable.reserve(8);
  stable.append("abc", 3);
  ((char *) stable.bytes)[4] = 'q';
  stable.append((char *) stable.bytes + 4, 1);
  EXPECT_INT_EQ(stable.length, 4);
  EXPECT_TRUE(memcmp(stable.bytes, "abcq", 4) == 0);

  Block growing = Block.new(sizeof(char));
  growing.reserve(8);
  growing.append("abcdefg", 7);
  memcpy((char *) growing.bytes + 6, "YZ", 2);
  growing.append((char *) growing.bytes + 6, 2);
  EXPECT_INT_EQ(growing.length, 9);
  EXPECT_TRUE(memcmp(growing.bytes, "abcdefYYZ", 9) == 0);
}

static void bytes_relocation_and_invalid_width(void) {
  $test.scoped();
  Bytes bytes = Bytes.new(sizeof(int));
  int value = 11;
  bytes = bytes.append(&value, 1);
  Block block = bytes.block();
  bytes = bytes.reserve(block.capacity() + 8);
  EXPECT_TRUE(Bytes.block(bytes) == block);
  EXPECT_TRUE(block.bytes == bytes);
  EXPECT_INT_EQ(Bytes.len(bytes), 1);
  EXPECT_INT_EQ(((int *) bytes)[0], 11);
  int caught = 0;
  try Block.new(0);
  catch %(bad-arg *): caught = 1;
  EXPECT_TRUE(caught);
}

static void status_pop_preserves_output_on_empty(void) {
  $test.scoped();
  Block block = Block.new(sizeof(int));
  int one = 1, two = 2, out = 99;
  block.push(&one);
  block.push(&two);
  EXPECT_TRUE(block.try_pop(&out));
  EXPECT_INT_EQ(out, 2);
  EXPECT_INT_EQ(block.len(), 1);
  EXPECT_TRUE(block.try_pop(&out));
  EXPECT_INT_EQ(out, 1);
  out = 99;
  EXPECT_FALSE(block.try_pop(&out));
  EXPECT_INT_EQ(out, 99);
  block.pop();
  EXPECT_INT_EQ(block.len(), 0);
}


void block_suite(void) {
  $test.run(bytes_append_and_len);
  $test.run(reserve_truncate_and_clear);
  $test.run(zero_and_fill_append);
  $test.run(self_append_with_and_without_growth);
  $test.run(self_append_uses_initialized_capacity);
  $test.run(bytes_relocation_and_invalid_width);
  $test.run(status_pop_preserves_output_on_empty);
}
