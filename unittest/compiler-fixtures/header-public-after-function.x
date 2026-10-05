#include "x2c.x"

/* Every declaration above `#pragma private` belongs to the header, whether
   a function definition, a static function, or a static object precedes
   it. Static functions and objects stay in the source, with what names
   them, since the header could not compile it. Otherwise only
   `#pragma private` keeps a type or enumerator there. A public directive
   goes to the header too, and the source repeats it so that each of its
   items sees the macros of its own position.
   `header-public-include` compiles a unit against this header. */
int twice(int n) => 2 * n;
enum { AFTER_FUNCTION = 7 };
typedef struct Box { int v; } Box;

static int helper(int n) => n + 1;
_Static_assert(sizeof(helper(0)) == sizeof(int), "helper result");
enum Color { RED, GREEN };
typedef int Count;
#define FIRST_ROW 3
enum { ROWS = FIRST_ROW + 4 };
#undef FIRST_ROW

static int counter = 0;
static const int table[] = {1, 2, 3};
enum { TABLE_SIZE = sizeof(table) / sizeof(table[0]) };
_Static_assert(TABLE_SIZE == 3, "table size");
struct Pair { int a, b; };
enum { AFTER_OBJECT = 11 };
static struct Tally { int total; } tally;

#pragma private
enum { SECRET = 99 };
typedef struct Hidden { int h; } Hidden;

#pragma public
enum { REOPENED = 13 };
typedef Box Wrapped;

int use_helper(void) => helper(counter) + tally.total;
