#include "x2c.x"
$(import "../../lib/array-generics.xmacro")

#include <string.h>

typedef Block ProbeArrayInt;

static void _bad_index(String owner, int index, size_t size) {
  raise %(bad-arg (operation $owner) (index $index) (size $size));
}

static void _bad_operation(String owner, Symbol operation) {
  raise %(bad-arg (owner $owner) (operation $operation));
}

static void _size_limit(String owner, size_t size) {
  raise %(size-limit (operation $owner) (size $size));
}

static void _bad_step(String owner, int step) {
  raise %(bad-arg (operation $owner) (step $step));
}

static int _compare_int(int a, int b) => (a > b) - (a < b);
static Block _prepare_probe_export(Block array, Context source) {
  (void) array; (void) source;
  return NULL;
}

$array.core.family(ProbeArrayInt, int);
$array.typed.family(ProbeArrayInt, int, 0, "ProbeArrayInt");
$array.typed.observe(ProbeArrayInt, int, _compare_int);
$array.typed.box(ProbeArrayInt, int, "ProbeArrayInt");
$array.typed.update.integer(ProbeArrayInt, int, uint);
$array.typed.publish(
  ProbeArrayInt, int, probearrayint, <prbarr>, _prepare_probe_export);
$array.typed.iterate(ProbeArrayInt, int, probearrayint);

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
