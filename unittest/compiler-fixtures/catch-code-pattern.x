/* A catch code position takes a pattern, and raise takes a variable code. */
#include <stdio.h>

static void fail(int k) {
  if (k == 0) raise %(bad-enc (text "x"));
  if (k == 1) raise %(conv-range (value 300));
  raise %(alloc-fail (bytes 8));
}

static void rewrap(int k) {
  try fail(k);
  catch %((!or ?code bad-enc conv-range) *cause): {
    List lower = cons(code, cause);
    raise %($code (index $k) (cause $lower));
  }
}

int main(void) {
  for (int k = 0; k < 3; k++) {
    try rewrap(k);
    catch %(?code *detail): printf("%s %s\n", code, detail.repr());
  }
  match (%(conv-range (value 1)))
    case %((!set ?code bad-enc conv-range) *):
      printf("member %s\n", code);
  return 0;
}
