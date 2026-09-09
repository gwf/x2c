#include "x2c.x"

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
  printf("%s %d %d %d %d %d %d %d\n", raw, (int) sizeof(raw),
         global.len(), same, length, (int) sizeof(bytes), bytes[2],
         percent.len());
  return 0;
}
