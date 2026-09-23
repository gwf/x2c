// A typedef in a Unit macro receives a private name for each expansion, and
// every later type use in the template names that expansion's typedef.
#include "x2c.x"

macro Unit $cell(Type $type, name $width, name $sum) {
  typedef $type S;
  typedef struct { S value; const S *next; } Cell;
  static const size_t cell_size = sizeof(Cell);
  size_t $width(void) => sizeof(S) + cell_size * 0;
  S $sum(S left, const S *right) {
    typedef S Local;
    Local total = (Local) left + *right + (Local) 0;
    S values[2] = {total, (S) sizeof(Local)};
    return values[0] + values[1] * 0;
  }
}

$cell(int, int_width, int_sum);
$cell(unsigned long, wide_width, wide_sum);

int main(void) {
  int one = 1;
  unsigned long two = 2;
  int widths = int_width() == sizeof(int) &&
               wide_width() == sizeof(unsigned long);
  printf("%d %d %lu\n", widths, int_sum(2, &one), wide_sum(5, &two));
  return widths && int_sum(2, &one) == 3 && wide_sum(5, &two) == 7 ? 0 : 1;
}
