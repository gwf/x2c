#include "x2c.x"
#include "include-recursion-a.h"  /* a trailing comment is not a target */
/*
#include "missing-block-comment.h"
*/
// #include "missing-line-comment.h"
static const char *red_herring = "/*";

int main(void) {
  RecursionPair pair = recursion_pair(4);
  printf("%s %d\n", red_herring, pair.value);
  return pair.value == 8 ? 0 : 1;
}
