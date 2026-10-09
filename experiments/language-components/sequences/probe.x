#include "managed.x"
void Tracked.cleanup(Tracked value) { printf("cleanup %d\n", value.value); }
int Tracked.read(Tracked value) => value.value;
macro Expression $tracked_value(Expr $value) => $value.read();
Tracked make(int value) => (Tracked) {.value = value};
Tracked fail(void) { raise %(later); return make(0); }
int main(void) {
  {
    Tracked only = make(1);
    printf("single %d\n", only.value);
  }
  {
    Tracked first = make(2), second = make(first.value + 1);
    printf("pair %d %d\n", $tracked_value(first), $tracked_value(second));
  }
  {
    int value = 8;
    int *pointer = &value, plain = *pointer + 1;
    printf("mixed %d %d\n", *pointer, plain);
  }
  {
    Tracked first = make(6), *borrowed = &first,
      second = make(borrowed->value + 1);
    printf("borrowed %d %d\n", borrowed->value, second.value);
  }
  try {
    Tracked first = make(5), second = fail();
    printf("unreachable %d %d\n", first.value, second.value);
  } catch %(later): puts("caught later");
  return 0;
}
