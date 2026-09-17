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
#define HIDE static

// A qualifier one arm omits loses to the arm without it, so the writes the
// omitting arm's C accepts stay legal.
#ifdef ZLIB_CONST
#define maybe_const const
#else
#define maybe_const
#endif

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

// A storage macro keeps its reading after the type and after a qualifier.
int HIDE quintupled(int value) { return value * 5; }
const HIDE int bound = 6;

struct text {
  maybe_const char *body;
};

PUBLIC(const char *) label(void);
PUBLIC(const char *) label(void) { return "label"; }

int main(void) {
  HIDE int held = 9;
  char buffer[2] = "a";
  struct text line;
  line.body = buffer;
  line.body[0] = 'b';
  hidden();
  printf("%d %d %d %s\n", doubled(2), tripled(2), weak_value, label());
  printf("%s %d %d %d\n", greeting, farewell == NULL, quadrupled(2), limit);
  printf("%d %d %d %s\n", quintupled(2), bound, held, line.body);
  return 0;
}
