#include "x2c.x"
#include "rewrite.x"

/* A user rule for two-element Array literals precedes the shipped one, also
   for a pair nested in a captured element, and the compiler still evaluates
   the Var arguments of its replacement in order. */
macro Expression $pair(Expr $first, Expr $second) => [$first, $second];

static int counter = 0;
static int next(void) => ++counter;

static Array reversed(Var first, Var second) {
  Array result = Array.new();
  result.push(second);
  result.push(first);
  return result;
}

$rewrite($pair)
meta Code reverse_pair(Code code) {
  match (code) case $pair(?first, ?second):
    return $!Array{ reversed($first, $second) };
  return code;
}

int main(void) {
  Array pair = [1, 2], triple = [1, 2, 3], nested = [[1, 2], 5];
  Map map = {"k": [3, 4], "empty": [{}, 6]};
  Array counted = [next(), next()];
  printf("%s %s %s %s %s\n", pair.repr(), triple.repr(), nested.repr(),
         map.repr(), counted.repr());
  return 0;
}
