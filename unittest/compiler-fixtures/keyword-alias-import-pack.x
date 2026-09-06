#include "x2c.x"

$(import "keyword-alias-import-pack.xmacro")

static int imported_value(int value) {
  return value;
}

typedef struct ImportedRecord {
  int imported_value;
} ImportedRecord;

int main(void) {
  ImportedRecord record = { 7 };
  int expanded = 0;
  private_scope {
    expanded = imported_value(40);
  }
  printf("%d %d\n", expanded, (imported_value)(record.imported_value));
  return 0;
}
