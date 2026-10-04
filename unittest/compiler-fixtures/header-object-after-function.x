#include "x2c.x"

/* Every public object definition gets an `extern` declaration in the
   header, whether a function definition or a static declaration precedes
   it, so an including unit can use it. The header drops initializers, and
   a definition whose initializer has to run loses `const`. Static objects,
   objects of an anonymous type, and objects below `#pragma private` stay in
   the source. */
typedef int *IntRef;

int before = 1;
int square(int n) => n * n;
int after = 2;
static int hidden = 3;
int after_static = 4;
int first = 5, second = 6, *pointer = &first;
int table[] = {7, 8, 9};
const int limit = 10;
int sized[2];
IntRef ref = &before;
typedef struct Pair { int a, b; } Pair;
Pair pair = {11, 12};
struct Point { int x, y; } origin = {13, 14};
String const greeting = "hi";
struct { int x; } anonymous = {15};
#pragma private
int secret = 16;
#pragma public
int reopened = 17;

int main(void) {
  sized[1] = hidden;
  printf("%d %d %d %d %d %d\n", before, square(after), after_static, first,
         second, *pointer);
  printf("%d %d %d %d %d\n", table[2], limit, sized[1], *ref, pair.b);
  printf("%d %s %d %d %d\n", origin.y, greeting, anonymous.x, secret,
         reopened);
  return 0;
}
