#include "x2c.x"

// `#` spells an argument as written, with its blanks reduced to one space
// and the quotes and backslashes of its literals escaped. An argument is
// expanded first only through another macro.
#define STR(x) #x
#define XSTR(x) STR(x)
#define VERSION 3

int main(void) {
  printf("%s|%s|%s|%s\n", STR(a  +   b), STR("q\n"), XSTR(VERSION),
         STR(VERSION));
  return 0;
}
