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
#define z_const const
#define LOCAL static int
#define LOCAL_CONST static const

static z_const char *greeting = "hi";
static char *EXPORT z_const farewell;

LOCAL quadrupled(int value) { return value * 4; }
LOCAL_CONST int limit = 5;

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
  printf("%s %d %d %d\n", greeting, farewell == NULL, quadrupled(2), limit);
  return 0;
}
