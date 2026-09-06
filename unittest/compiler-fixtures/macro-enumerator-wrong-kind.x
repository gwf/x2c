#include "x2c.x"

macro Statement $not_an_enumerator() => {
  return;
}

typedef enum WrongKindRows {
  $not_an_enumerator()
} WrongKindRows;
