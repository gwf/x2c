#include "x2c.x"
#include <inttypes.h>

#define PREFIX "pre-"

static const char raw[] = "\x41" "B";
static String global = "hel" /* preserve the literal boundary */ "lo";

static int width(String text) { return text.len(); }

int main(void) {
  char bytes[] = "a\0" "b";
  String local = "wor"
                 "ld";
  int same = local == "wo" "rld";
  int length = width("one" "two");
  String percent = %"left${2}right";
  // A macro defined to a string literal, and a header's macro this unit
  // cannot resolve, are words of the adjacent literal, as in C.
  String joined = PREFIX "post";
  int64_t counted = 7;
  printf("%s %d %d %d %d %d %d %d\n", raw, (int) sizeof(raw),
         global.len(), same, length, (int) sizeof(bytes), bytes[2],
         percent.len());
  printf("%" PRId64 " %d\n", counted, joined.len());
  return 0;
}
