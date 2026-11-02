#include "x2c.x"

int main(void) {
  const char *text = "abc\
def";
  puts(text);
  puts("x" /* multiline
             comment */ "y");
  return 0;
}
