#include <stdio.h>

// Reduced grammar shapes from the C compatibility corpus, not full ports.
#define ARRAY_EACH(index, count) \
  for ((index) = 0; (index) < (count); (index)++)
#define TEST_COND(label, condition) \
  do { (void) (label); if (condition) hits++; } while (0);
#define UNALIGNED(code) code
#define M(n) ((double) (n) + 2.0)
#define TE_FUN(type) ((type (*)(type)) identity)

static double identity(double value) { return value + 1.0; }

int main(void) {
  int index, total = 0, hits = 0, remaining = 4, count = 0;
  ARRAY_EACH(index, 4) { total += index; }
  TEST_COND("first", total == 6)
  TEST_COND("second", total > 3)
  UNALIGNED(while (remaining--) count++;)
  printf("%d %d %d %.1f\n", total, hits, count, TE_FUN(double)(M(0)));
  return 0;
}
