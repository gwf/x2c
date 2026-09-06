#include "x2c.x"

typedef enum ExistingRows {
  SOURCE_ENUM
} ExistingRows;

macro Enumerator $colliding_enumerator() => {
  $(x2c.ident "SOURCE_ENUM")
}

typedef enum GeneratedRows {
  $colliding_enumerator()
} GeneratedRows;
