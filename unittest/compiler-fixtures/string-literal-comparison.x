#include "x2c.x"
#include <stdio.h>

static int calls = 0;

static String counted(void) {
  calls++;
  return "hello, world";
}

macro Expression $raw_hello() => (
  $(quote (expr (* char) (literal (* char) "\"hello, world\"")))
)

int main(void) {
  String built = %"hello" + %", world", empty = "";
  char raw[] = "hello, world";
  char other[] = "hello, world";
  char *pointer = raw;

  printf("literal %d %d %d %d\n",
         built == "hello, world", "hello, world" == built,
         built != "other", "other" != built);
  printf("different %d %d %d %d\n",
         built == "other", "other" == built,
         built != "hello, world", "hello, world" != built);
  printf("empty %d %d %d %d\n",
         empty == "", "" == empty, empty != "x", "x" != empty);
  printf("parens %d %d\n",
         built == (("hello, world")), (("hello, world")) == built);
  printf("constructed %d %d\n",
         built == $raw_hello(), $raw_hello() == built);

  int left = counted() == "hello, world";
  int right = "hello, world" == counted();
  printf("calls %d %d %d\n", left, right, calls);
  printf("native %d %d %d %d %d\n",
         built == pointer, pointer == built, built == raw,
         raw == pointer, pointer == other);
  printf("expressions %d %d\n",
         built == (char *) raw, built == (calls ? raw : other));
  printf("identity %d %d %d %d\n",
         built === "hello, world", "hello, world" === built,
         built !== "hello, world", built === built);
  return 0;
}
