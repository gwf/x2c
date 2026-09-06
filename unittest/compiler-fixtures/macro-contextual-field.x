#include "x2c.x"

typedef struct Record {
  int macro;
} Record;

int main(void) {
  Record record = { .macro = 42 };
  printf("%d\n", record.macro);
  return 0;
}
