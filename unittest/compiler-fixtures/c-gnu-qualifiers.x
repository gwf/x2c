#include <stdio.h>

#define restrict_ptr

static __inline int first(const int *__restrict values) { return values[0]; }
static __inline__ int second(const int *__restrict__ values) {
  return values[1];
}
static inline int third(const int *restrict_ptr values) { return values[2]; }

int main(void) {
  int values[] = {1, 2, 3};
  printf("%d %d %d\n", first(values), second(values), third(values));
  return 0;
}
