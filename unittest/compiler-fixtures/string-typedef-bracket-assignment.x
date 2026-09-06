#include "x2c.x"

/* A typedef of String does not support bracket indexing at all: the parse
   phase rejects it before the transform's String-specific assignment
   diagnostic can fire. That is pre-existing behavior, unchanged by the
   String bracket assignment rejection, and it is recorded here so a future
   change to typedef index resolution has to update this expectation
   deliberately. */
typedef String Text;

int main(void) {
  Text text = %"hello";
  text[0] = 'j';
  return 0;
}
