/* A bodyless `meta` prototype of a class default or a protocol base
   default leaves the default to supply the definition, and a written
   definition still replaces the default. Only a compiler built with this
   unit could call the native target at compile time, so the run-time calls
   prove that the definitions link. */

#include "x2c.x"

class Point struct { int x; int y; };
class Pair struct { int left; int right; };

meta int Point.equal(Point left, Point right);

typedef Block Stack;
protocol Block(Stack);
inline Block Stack.block(Stack x) => (Block) x;
inline Stack Block.stack(Block x) => (Stack) x;

meta void Stack.free(Stack stack);

int Pair.equal(Pair a, Pair b) { return 7; }

int main(void) {
  Point left = { .x = 3, .y = 4 };
  Point right = { .x = 3, .y = 5 };
  Pair pair = { .left = 1, .right = 2 };
  Stack stack = Block.new(sizeof(int));
  printf("%d %d %d %zu\n", left.equal(left), left.equal(right),
    pair.equal(pair), stack.len());
  stack.free();
  return 0;
}
