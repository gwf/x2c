#include "x2c.x"

macro Unit $broken_fields() => {
  typedef struct RollbackRecord {
    int stale;
  } RollbackRecord;
  $(list 42)...
}

$broken_fields();

typedef struct RollbackRecord {
  int kept;
} RollbackRecord;
