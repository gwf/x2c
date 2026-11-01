#include <stdio.h>

// The include ends a collection segment inside the group. The next
// segment begins at `#else` and still hides the arm C never takes.
#ifndef __cplusplus
#include <stdbool.h>
#else
#include <cstdbool>
using std::size_t;
#endif

int main(void) {
  bool ready = true;
  printf("%d\n", ready);
  return 0;
}
