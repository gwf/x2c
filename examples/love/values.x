#include <assert.h>
#include <math.h>

int main(void) {
// One eight-byte word holds a value and remembers what it is.
Var count = 42, ratio = 2.5, name = "Ada";

// Operators do the obvious thing for whatever is in there.
Var next = count + 1, full = name + " Lovelace";

// Every Var knows how to print itself.
printf("%s %s %s\n", next, ratio, full);

// Ask at runtime; the answer is the stored type, not a guess.
assert(count is int && ratio is double && name is String);

// Cross a typed boundary and the Var converts itself.
int whole = count; double part = ratio;

// Even printf's %d and %f know what to do with one.
printf("%d %f %f\n", count, ratio, sin(ratio));
return 0;
}
