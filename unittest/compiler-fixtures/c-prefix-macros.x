#include <stdio.h>

#ifdef USE_STATIC
#define API static
#else
#define API extern
#endif
#define EXPORT
#define INLINE __inline
#define WEAK __attribute__((weak))
#define PUBLIC(type) __attribute__((visibility("default"))) type
#define int32 signed int

API void hidden(void);
API void hidden(void) { printf("hidden\n"); }

EXPORT int32 doubled(int32 value);
EXPORT int32 doubled(int32 value) { return value * 2; }

INLINE int tripled(int value) { return value * 3; }

WEAK int weak_value = 5;

PUBLIC(const char *) label(void);
PUBLIC(const char *) label(void) { return "label"; }

int main(void) {
  hidden();
  printf("%d %d %d %s\n", doubled(2), tripled(2), weak_value, label());
  return 0;
}
