#include "x2c.x"

meta static List number_rows(void) => %(42);

macro Unit $broken_fields() {
  typedef struct RollbackRecord {
    int stale;
  } RollbackRecord;
  @number_rows()
}

$broken_fields();

typedef struct RollbackRecord {
  int kept;
} RollbackRecord;
