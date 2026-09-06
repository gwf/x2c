#include "x2c.x"
$(import "../../lib/array-generics.xmacro")

#include <string.h>

typedef Block ProbeArrayInt;

static void _bad_index(String owner, int index, size_t size) {
  raise %(bad-arg (owner $owner) (index $index) (size $size));
}

static void _bad_operation(String owner, Symbol operation) {
  raise %(bad-arg (owner $owner) (operation $operation));
}

static void _size_limit(String owner, size_t size) {
  raise %(size-limit (owner $owner) (size $size));
}

static void _bad_step(String owner, int step) {
  raise %(bad-arg (owner $owner) (step $step));
}

static int _compare_int(int a, int b) => (a > b) - (a < b);
static Buffer _new_buffer(void) => Buffer.new(0);
static String _finish_buffer(Buffer out) => out.str_free();
static Block _prepare_probe_export(Block array, Context source) {
  (void) array; (void) source;
  return NULL;
}

$array.core.family(ProbeArrayInt, int);
$array.typed.family(ProbeArrayInt, int, 0, "ProbeArrayInt");
$array.typed.observe(
  ProbeArrayInt, int, "ProbeArrayInt", _compare_int,
  _new_buffer, _finish_buffer);
$array.typed.update.integer(ProbeArrayInt, int, uint);
$array.typed.publish(
  ProbeArrayInt, int, probearrayint, <p48>, _prepare_probe_export);

int main(void) {
  ProbeArrayInt values = ProbeArrayInt.new();
  values.push(2);
  values.push(4);
  values.unshift(1);
  ProbeArrayInt copy = values.concat(values);
  copy.reverse();
  printf("%d %d %d %d\n", values.len(), copy.len(), copy[0], copy[5]);
  return 0;
}
