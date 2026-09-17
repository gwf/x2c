#include <stdio.h>

#ifdef __cplusplus
template<class T> static T *wrap(T *value) { return value; }
#endif

#if defined(__cplusplus) && !defined(NO_TEMPLATES)
class Ignored { public: int field; };
#else
struct Kept { int field; };
#endif

#ifndef __cplusplus
typedef struct Kept Kept;
#else
using Kept = struct Kept;
#endif

#ifdef _MSC_VER
__declspec(noinline) int platform(void) { __asm { nop } return 1; }
#else
int platform(void) { return 2; }
#endif

#ifdef POW_FROM_RIGHT
static int power(int base) { return base * base * base; }
#else
static int power(int base) { return base * base; }
#endif

#if 0
this arm is never compiled and need not parse
#endif

int main(void) {
  Kept kept = { 3 };
  printf("%d %d %d\n", kept.field, platform(), power(4));
  return 0;
}
