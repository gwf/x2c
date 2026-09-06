#include "x2c.x"
#include <stddef.h>
#include <stdio.h>

static int calls;

static void touch(void) {
  calls++;
}

int main(void) {
  Var bare = void;
  Var parenthesized = (void);
  void *pointer = NULL;
  void *cast_pointer = (void *) pointer;
  (void) touch();
  (void) sizeof(void);

  int ok =
    bare is void && parenthesized is (void) &&
    (void is void) && !(void is not void) &&
    !(void is int) && void is not int &&
    void == void && void === void &&
    !(void != void) && !(void !== void) &&
    void != 1 && 1 != void && void !== 1 && 1 !== void &&
    !(void == 1) && !(1 == void) &&
    !(void === 1) && !(1 === void) &&
    (void) == void && cast_pointer == pointer && calls == 1;

  printf("%d %d\n", ok, calls);
  return ok ? 0 : 1;
}
