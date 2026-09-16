#include "x2c.x"
#include "c-linkage-values.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct Span { int start, stop; } Span;

int Span.len(Span span);

extern "C" int scale;

#ifdef __cplusplus
}
#endif

int scale = 10;

int Span.len(Span span) => span.stop - span.start;

int main(void) {
  Point point = {1, 2};
  Span span = {3, 7};
  printf("%d %d\n", point.sum(), span.len() * scale);
  return 0;
}
