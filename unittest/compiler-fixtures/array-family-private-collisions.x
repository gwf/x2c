#include "x2c.x"
#include "array/array.x"

/* Distinct families must keep distinct private helpers across expansions. */
typedef Block Foo;
typedef Block ArrayFoo;
typedef Block Probe;
typedef Block probe;
typedef Block under_score;
typedef Block underScore;

macro Unit $probe.family(Type $family, Name $run) {
  $array.core.family($family, int);

  static int $run(int value) {
    $family array = ($family) Block.new(sizeof(int));
    defer Block.free((Block) array);
    array.insert_element(0, value);
    int found = 0;
    if (!array.shift_element(&found)) return -1;
    return found;
  }
}

$probe.family(Foo, _foo);
$probe.family(ArrayFoo, _array_foo);
$probe.family(Probe, _upper);
$probe.family(probe, _lower);
$probe.family(under_score, _snake);
$probe.family(underScore, _camel);

int main(void) {
  printf("%d %d %d %d %d %d\n",
    _foo(1), _array_foo(2), _upper(3), _lower(4), _snake(5), _camel(6));
  return 0;
}
