/*  test-protocols.x -- runtime seams behind protocol adoption

    Compiler fixtures under compiler-fixtures/ and probes/protocol/ own
    conformance classification and emission. This suite owns the runtime
    behavior those fixtures cannot see: base-default members reached
    through storage-view converters, and Var dispatch through descriptors
    that adoption rows register.
*/

#include "typed-array.x"
#include "test-support.x"
$(import "test-macros.xmacro")

static void protocols_block_defaults_reach_array(void) {
  $test.scoped();
  Array values = %[1, 2, 3];

  // truth, pop, truncate, and clear are Block(Array) base defaults; Array
  // defines none of them directly.
  EXPECT_TRUE(values.truth());
  EXPECT_INT_EQ(values.len(), 3);
  EXPECT_TRUE(values.capacity() >= 3);
  values.pop();
  EXPECT_INT_EQ(values.len(), 2);
  EXPECT_INT_EQ(values[-1].int(), 2);
  values.truncate(1);
  EXPECT_INT_EQ(values.len(), 1);
  values.clear();
  EXPECT_INT_EQ(values.len(), 0);
  EXPECT_FALSE(values.truth());
}

static void protocols_block_defaults_reach_bytes(void) {
  $test.scoped();
  Bytes bytes = Bytes.new(1);

  // Bytes reaches the same base defaults through its Bytes.block view.
  EXPECT_FALSE(bytes.truth());
  bytes = bytes.append("abc", 3);
  EXPECT_TRUE(bytes.truth());
  EXPECT_INT_EQ(bytes.len(), 3);
  EXPECT_TRUE(bytes.capacity() >= 3);
  bytes.pop();
  EXPECT_INT_EQ(bytes.len(), 2);
  bytes.truncate(1);
  EXPECT_INT_EQ(bytes.len(), 1);
  bytes.clear();
  EXPECT_INT_EQ(bytes.len(), 0);
  EXPECT_FALSE(bytes.truth());
}

static void protocols_adoption_registers_arrayint_descriptor(void) {
  $test.scoped();
  // Var(ArrayInt) adoption registers <arrayint> at startup; the tag is
  // known without being one of the builtin ledger rows.
  EXPECT_TRUE(Var.known_tag(<arrayint>));

  ArrayInt values = ArrayInt.new();
  Var boxed = values;
  EXPECT_TRUE(boxed is <arrayint>);
  // Custom tags decode as <object>, the kind dispatch requires before it
  // consults a registered descriptor.
  EXPECT_TRUE(boxed.kind() == <object>);
}

static void protocols_adoption_dispatch_reaches_boxed_arrayint(void) {
  $test.scoped();
  ArrayInt left = ArrayInt.new(), right = ArrayInt.new();
  left.push(1); left.push(2);
  right.push(1); right.push(2);
  Var boxed_left = left, boxed_right = right;

  // == dispatches the descriptor equal that adoption registered, so two
  // distinct arrays compare by contents.
  EXPECT_TRUE(boxed_left == boxed_right);
  EXPECT_FALSE(boxed_left === boxed_right);
  right.push(3);
  EXPECT_FALSE(boxed_left == boxed_right);

  // Descriptor truth reports emptiness; the fallback would only see a
  // non-null pointer.
  EXPECT_TRUE(boxed_left.truthy());
  Var boxed_empty = ArrayInt.new();
  EXPECT_FALSE(boxed_empty.truthy());

  struct Iter storage;
  Iter items = boxed_left.iter(&storage);
  EXPECT_INT_EQ(items.next().int(), 1);
  EXPECT_INT_EQ(items.next().int(), 2);
  EXPECT_TRUE(items.next() is void);
}

static void protocols_adoption_dispatch_reaches_boxed_bytes(void) {
  $test.scoped();
  Bytes bytes = Bytes.new(1);
  Var boxed_empty = bytes;

  // Var(Bytes) registers only truth on the builtin <bytes> descriptor row;
  // a boxed empty Bytes is falsy even though its pointer is non-null.
  EXPECT_TRUE(boxed_empty is <bytes>);
  EXPECT_FALSE(boxed_empty.truthy());
  bytes = bytes.append("x", 1);
  Var boxed_full = bytes;
  EXPECT_TRUE(boxed_full.truthy());
}

void protocols_suite(void) {
  $test.run(protocols_block_defaults_reach_array);
  $test.run(protocols_block_defaults_reach_bytes);
  $test.run(protocols_adoption_registers_arrayint_descriptor);
  $test.run(protocols_adoption_dispatch_reaches_boxed_arrayint);
  $test.run(protocols_adoption_dispatch_reaches_boxed_bytes);
}
