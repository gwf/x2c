#include "x2c.x"

macro Enumerator $duplicate_enumerator() => {
  $(x2c.ident "ROLLBACK_ENUM"),
  $(x2c.ident "ROLLBACK_ENUM")
}

typedef enum BrokenRows {
  $duplicate_enumerator()
} BrokenRows;

typedef enum FollowingRows {
  ROLLBACK_ENUM
} FollowingRows;
