#include "x2c.x"

macro Enumerator $bad() => {
  $(list)
}

typedef enum Broken {
  A,
  $bad()
} Broken;
