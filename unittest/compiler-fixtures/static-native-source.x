#include "x2c.x"

static int calls;
static int input(void) { return ++calls + 40; }
#define INPUT input()
#define STRINGIFY(value) #value
#define PASTE(left, right) left ## right
static Var first = (int)__COUNTER__;
static Var inline_value = (int)((struct Inline {
  char bytes[__COUNTER__ + 1];
  int number;
}){{0}, INPUT}).number;
static Var quoted = (const char *)STRINGIFY(__COUNTER__);
static Var pasted = (int)PASTE(4, 1);
#undef INPUT
#define INPUT 99
struct Inline after = {{0}, 9};
int next = __COUNTER__;

int main(void) {
  printf("%d %d %zu %d %d %s %d %d\n", first.int(), inline_value.int(),
    sizeof(after.bytes), calls, next, (const char *)quoted.string(),
    pasted.int(), after.number);
  return 0;
}
