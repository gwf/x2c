#include "x2c.x"

macro Enumerator $invalid_enumerator_lisp() => {
  $(list 42)...
}

typedef enum InvalidRows {
  $invalid_enumerator_lisp()
} InvalidRows;
