#include "x2c.x"

macro Enumerator $published_enumerator() => {
  $(x2c.ident "LATER_SOURCE_ENUM")
}

typedef enum GeneratedRows {
  $published_enumerator()
} GeneratedRows;

typedef enum FollowingRows {
  LATER_SOURCE_ENUM
} FollowingRows;
