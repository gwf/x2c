#include "x2c.x"
#include <string.h>

/* A function returning a pointer puts its pointer modifiers after the fnmod,
   so requiring exactly one declarator modifier rejected every
   pointer-returning alias target. */
typedef int Text;

$x2c.foreign.alias(strchr)
inline char *find_char(const char *text, int ch);

$x2c.foreign.alias(strstr)
inline char *Text.find(const char *text, const char *needle);

int main(void) {
  printf("%s %s\n", find_char("hello", 'l'), Text.find("hello", "ll"));
  return 0;
}
