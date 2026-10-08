/* A label that is not a string literal in a string switch is an error at
   that label. Translating this file reports, at line 9, column 5:

     macro: a string switch label must be a string literal */
#include "string-switch.x"
int pick(String s, int n) {
  switch (s) {
    case "a": return 1;
    case n: return 2;
  }
  return 0;
}
