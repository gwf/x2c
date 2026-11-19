#include "system-macros.x"

/* Lists are immutable and share tails. Arrays and Maps are mutable; copying
   a handle shares its object. Percent literals quote names as data. */
int main(void) {
  int n = 2;
  List quoted = %(n $n $(n + 1));
  List evaluated = $(n, n + 1), extended = %(1 @evaluated);
  Array numbers = [1, n, n + 1], shared = numbers;
  shared[0] = 9;
  String key = "answer";
  Map named = {key: n}, computed = ${key: n};
  puts($dedent(%"
    Quoted list: $(quoted.repr())
    Evaluated list: $(evaluated.repr())
    Extended list: $(extended.repr())
    Array: $(numbers.repr())
    Last item: $(numbers[-1])
    Slice: $(numbers[1:].repr())
    Bare keys: $(named.keys().list().repr())
    Computed keys: $(computed.keys().list().repr())
    Computed key present: $(key in computed)
    Shared list tail: $(extended.cdr() === evaluated)
    Shared array: $(numbers === shared)"));
  // Quoted Array/Map contents follow the same data-reading rule.
  Array tags = %[ready, done];
  Map settings = %{mode: fast};
  puts($dedent(%"
    Quoted array: $(tags.repr())
    Quoted map mode: $(settings[<mode>])"));
  return 0;
}
