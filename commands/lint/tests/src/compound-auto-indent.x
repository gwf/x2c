#pragma indent
/* compound-auto-indent.x -- use the compiler's inserted delimiters. */
#include "array.x"

void stable(void):
  Array left = auto [], right = auto []
  left.push(1)

void changed(void):
  Array left = auto [], right = auto []
  right = []
