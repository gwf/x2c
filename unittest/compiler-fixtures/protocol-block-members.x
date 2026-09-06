#include "x2c.x"

int main(void) {
  Array array = Array.new();
  Bytes bytes = Bytes.new(sizeof(int));
  Var boxed_array = array, boxed_bytes = bytes;
  int empty_array_branch = array ? 1 : 0, empty_bytes_branch = bytes ? 1 : 0;
  printf(
    "%d %d %d %d %d %d %d %d\n",
    array.truth(), empty_array_branch, !array, array && 1,
    bytes.truth(), empty_bytes_branch, !bytes, bytes && 1
  );
  printf("%d %d\n", boxed_array.truth(), boxed_bytes.truth());

  array.push(7);
  array.push(8);
  int array_branch = array ? 1 : 0;
  printf("%d %d %d %d %d\n", array.truth(), array_branch, !array,
         array && 1, boxed_array.truth());
  Var last = array.take_last();
  array.pop();
  array.pop();
  array.push(9);
  array.push(10);
  array.truncate(1);
  printf("%s %zu %d %d\n", last.repr(), array.len(),
         array.truth(), boxed_array.truth());

  int first = 11, second = 12;
  bytes.push(&first);
  bytes.push(&second);
  int bytes_branch = bytes ? 1 : 0;
  printf("%d %d %d %d %d\n", bytes.truth(), bytes_branch, !bytes,
         bytes && 1, boxed_bytes.truth());
  bytes.pop();
  bytes.truncate(0);
  bytes.pop();
  printf("%zu %d %d\n", bytes.len(), bytes.truth(),
         boxed_bytes.truth());

  array.free();
  bytes.free();
  return 0;
}
