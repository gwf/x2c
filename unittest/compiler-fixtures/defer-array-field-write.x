#include "x2c.x"

/* A defer that writes an array field of a captured local writes that local:
   the cleanup stores through a volatile pointer, and inside `try` the local
   itself is volatile. */

typedef struct Pair { int arr[3]; int n; } Pair;

static void boom(void) { raise %(oops); }

int main(void) {
  Pair pair = {{0, 0, 0}, 0};
  try {
    {
      defer pair.arr[1] = 9;
      boom();
    }
  }
  catch %(oops *): printf("caught %d\n", pair.arr[1]);
  return 0;
}
