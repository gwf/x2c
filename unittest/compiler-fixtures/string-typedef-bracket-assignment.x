#include "x2c.x"

/* A String alias inherits bracket reads, but String remains immutable.
   Assignment must reach the same String-specific diagnostic as its base. */
typedef String Text;

int main(void) {
  Text text = %"hello";
  text[0] = 'j';
  return 0;
}
