#include "x2c.x"

macro Stmt $not_an_enumerator() {
  return;
}

typedef enum WrongKindRows {
  $not_an_enumerator()
} WrongKindRows;
