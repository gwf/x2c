#include "x2c.x"

/* A break or continue in a catch arm reaches the loop around the try, and
   only the arm the handler selected runs. */
int main(void) {
  int seen = 0, broke = 0, skipped = 0;
  for (int i = 0; i < 10; i++) {
    try {
      if (i % 3 == 0) raise %(skip (at i));
      if (i == 7) raise %(stop (at i));
      seen++;
    }
    catch %(skip *): {
      skipped++;
      continue;
    }
    catch %(stop *): {
      broke = i;
      break;
    }
    seen += 10;
  }
  printf("%d %d %d\n", seen, skipped, broke);
  return 0;
}
