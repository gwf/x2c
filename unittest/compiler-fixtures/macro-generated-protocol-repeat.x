#include "x2c.x"

typedef Block RepeatOne;
typedef Block RepeatTwo;

Var RepeatOne.var(RepeatOne);
RepeatOne Var.repeatone(Var);
RepeatOne RepeatOne.new(void);
int RepeatOne.equal(RepeatOne, RepeatOne);
int RepeatOne.contains(RepeatOne, int);
int RepeatOne.getindex(RepeatOne, int);

Var RepeatTwo.var(RepeatTwo);
RepeatTwo Var.repeattwo(Var);
RepeatTwo RepeatTwo.new(void);
int RepeatTwo.equal(RepeatTwo, RepeatTwo);
int RepeatTwo.contains(RepeatTwo, int);
int RepeatTwo.getindex(RepeatTwo, int);

macro Unit $repeat.array(
  Type $array, Name $unbox, Literal $tag
) => {
  inline Var $array.var($array array) {
    return Var.new($tag, array);
  }

  inline $array Var.$unbox(Var value) {
    return ($array) value.pointer();
  }

  $array $array.new(void) {
    return Block.new(sizeof(int));
  }

  int $array.equal($array a, $array b) {
    return (void *) a == (void *) b;
  }

  int $array.contains($array array, int needle) {
    int *data = (int *) array.bytes;
    for (size_t i = 0; i < array.length; i++)
      if (data[i] == needle) return 1;
    return 0;
  }

  int $array.getindex($array array, int index) {
    return ((int *) array.bytes)[index];
  }

  protocol Var($array);
}

macro Unit $repeat.proto(Type $base) => {
  protocol $base(T) {
    int T.read(T);
  }
}

$repeat.array(RepeatOne, repeatone, <repeatone>);
$repeat.array(RepeatTwo, repeattwo, <repeattwo>);
$repeat.proto(RepeatProtocolA);
$repeat.proto(RepeatProtocolB);

int main(void) {
  RepeatOne a = RepeatOne.new();
  RepeatTwo b = RepeatTwo.new();
  a.append(&(int) { 31 }, 1);
  b.append(&(int) { 47 }, 1);
  printf("%d %d %d %d\n", a.contains(31), a.getindex(0),
         b.contains(47), b.getindex(0));
  a.free();
  b.free();
  return 0;
}
