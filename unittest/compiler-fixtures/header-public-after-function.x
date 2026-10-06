#include "x2c.x"

/* Public declarations enter the header after preceding implementations.
   Static declarations stay in the implementation. Directives retain their
   source order so each declaration sees its own native macro state.
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
struct Tally { int total; };
static struct Tally tally;

static enum { SECRET = 99 };
static typedef struct Hidden { int h; } Hidden;

enum { REOPENED = 13 };
typedef Box Wrapped;

int use_helper(void) => helper(counter) + tally.total;
