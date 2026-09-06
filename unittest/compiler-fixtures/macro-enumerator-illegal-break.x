#include "x2c.x"

macro Enumerator $bad() => {
  $(quote ((break)))...
}

typedef enum Broken {
  $bad()
} Broken;
