#include "x2c.x"

meta static List number_rows(void) => %(42);

macro Enumerator $invalid_enumerator_rows() {
  @number_rows()
}

typedef enum InvalidRows {
  $invalid_enumerator_rows()
} InvalidRows;
