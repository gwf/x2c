#include "x2c.x"

static Array saved_array;
static Map saved_map;
static String saved_buffer;
static int array_base_calls;
static int map_base_calls;
static int buffer_base_calls;
static int index_calls;
static int key_calls;
static int value_calls;
static int bound_calls;

static Array array_base(void) {
  array_base_calls++;
  return saved_array;
}

static Map map_base(void) {
  map_base_calls++;
  return saved_map;
}

static String buffer_base(void) {
  buffer_base_calls++;
  return saved_buffer;
}

static int next_index(int index) {
  index_calls++;
  return index;
}

static Symbol next_key(Symbol key) {
  key_calls++;
  return key;
}

static Var next_value(int value) {
  value_calls++;
  return value;
}

static int next_bound(int bound) {
  bound_calls++;
  return bound;
}

int main(void) {
  int raw[3] = { 1, 2, 3 }, *ptr = raw, native_read = ptr[1];
  raw[2] = 9;

  saved_array = %[10, 20, 30, 40];
  List list = %(1 2 3 4);
  String text = %"abcd";
  saved_map = %{seed: 7};
  saved_buffer = String.malloc(4);
  strcpy(saved_buffer, "abc");

  Var array_read = array_base()[next_index(1)];
  Var list_read = list[next_index(2)];
  int string_read = text[next_index(3)];
  Var map_read = map_base()[next_key(<seed>)];

  array_base()[next_index(2)] = next_value(90);
  map_base()[next_key(<answer>)] = next_value(42);
  // String bracket assignment is rejected; a transient String.malloc buffer
  // is written through a char *, which lowers to native C indexing. The base
  // call stays inline so single evaluation is still what is proven.
  ((char *) buffer_base())[next_index(0)] = 'z';

  Array slice = array_base()[next_bound(0):next_bound(4):next_bound(2)];
  List reverse = list[::-1];
  String suffix = text[1:];

  printf("native=%d,%d values=%d,%d,%c,%d writes=%d,%d,%c\n",
         native_read, raw[2], array_read.int(), list_read.int(),
         string_read, map_read.int(), saved_array[2].int(),
         saved_map[<answer>].int(), saved_buffer[0]);
  printf("slices=%s|%s|%s calls=%d,%d,%d,%d,%d,%d,%d\n",
         Array.repr(slice), List.repr(reverse), String.repr(suffix),
         array_base_calls, map_base_calls, buffer_base_calls, index_calls,
         key_calls, value_calls, bound_calls);
  String.free(saved_buffer);
  return 0;
}
