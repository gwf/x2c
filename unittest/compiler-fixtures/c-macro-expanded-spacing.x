#include "x2c.x"

#define STR(x) #x
#define XSTR(x) STR(x)
#define EXPR a + b
#define WORDS alpha beta
#define WRAP(x) STR(a+x)
#define BLANK
#define COMB(x) a x+b

int main(void) {
  printf("%s|%s|%s|%s|%s\n", XSTR(EXPR), XSTR(WORDS),
         WRAP( b ), XSTR(a BLANK+b), XSTR(COMB(BLANK)));
  return 0;
}
