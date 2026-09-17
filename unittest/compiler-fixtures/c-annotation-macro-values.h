#ifndef API
#  define API   /* exported by default */
#endif
#include <stddef.h>
#include <stdlib.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct Pair { int left, right; } Pair;

static inline API int pair_sum(Pair pair) { return pair.left + pair.right; }
static inline API const char *pair_name(int left) {
  return left > 2 ? "wide" : "narrow";
}
static API Pair pair_make(int left, int right) {
  Pair pair = {left, right};
  return pair;
}

#define PAIR_ATTR(note) __attribute__((unused))
PAIR_ATTR(1) static inline int pair_diff(Pair pair) {
  return pair.right - pair.left;
}
__attribute__((unused)) static inline int pair_max(Pair pair) {
  return pair.left > pair.right ? pair.left : pair.right;
}
_Noreturn static inline void pair_abort(int status) { exit(status); }

#ifdef __cplusplus
}
#endif
