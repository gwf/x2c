#include "x2c.x"

#define WIDTH sizeof(char)
#define VALUE(value) (0 * __COUNTER__ + (value))
typedef int Score;
Var Score.var(Score value) { return (int)value + 100; }
struct Narrow { Score values[WIDTH]; Var last; };
struct Wide { Score values[WIDTH + 1]; Var last; };
static struct Narrow saved[1] = {
  {0, (Score)((struct SavedValue {int number;}){42}).number}
};
static struct Wide constant = {17, 42};
struct NativePair {int first, second;};
struct DynamicPair {Var first, second;};
struct Pairs {struct NativePair values[WIDTH]; struct DynamicPair last;};

int main(void) {
  int effects = 0, before = __COUNTER__;
  struct Narrow narrow = {0, (Score)VALUE(
    ((struct Inline {
      int number;
      char bytes[1 + 0 * __COUNTER__];
    }){(effects++, 41)}).number)};
  int after = __COUNTER__;
  struct Inline later = {9};
  struct Wide wide = {0, (Score)((struct WideValue {int number;}){43}).number};
  printf("%d %d %d %d %d %d %zu %d\n", narrow.last.int(), wide.values[1],
    saved[0].last.int(), constant.values[1], after - before, effects,
    sizeof(later.bytes), later.number);
  int start = __COUNTER__;
  struct Pairs pairs = {
    .values[0] = {0, 0}, {(int)__COUNTER__, (int)__COUNTER__}
  };
  int end = __COUNTER__;
  printf("%d %d %d\n", pairs.last.first.int() - start,
    pairs.last.second.int() - start, end - start);
  return 0;
}
