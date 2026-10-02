#include "x2c.x"
typedef int Row[2];
typedef struct Rows { Row values; } Rows;
static void increment(int &value) { value++; }
int main(void) {
  const Rows rows = {{10,11}};
  increment(rows.values[0]);
  return 0;
}
