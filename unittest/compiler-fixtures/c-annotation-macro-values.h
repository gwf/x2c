#ifndef API
#  define API   /* exported by default */
#endif
#include <stddef.h>

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

#ifdef __cplusplus
}
#endif
