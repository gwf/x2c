// A typedef in a macro template receives a private name for each expansion,
// and every later type use in the template names that expansion's typedef.
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

macro Statement $widen(Type $type, name $out) {
  typedef $type Wide;
  Wide value = (Wide) 4;
  $out = (int) value + (int) (Wide) sizeof(Wide);
}

$cell(int, int_width, int_sum);
$cell(unsigned long, wide_width, wide_sum);

int main(void) {
  int one = 1;
  unsigned long two = 2;
  int widths = int_width() == sizeof(int) &&
               wide_width() == sizeof(unsigned long);
  int narrow = 0, wide = 0;
  $widen(char, narrow);
  $widen(unsigned long long, wide);
  printf("%d %d %lu %d %d\n", widths, int_sum(2, &one), wide_sum(5, &two),
         narrow, wide);
  return widths && int_sum(2, &one) == 3 && wide_sum(5, &two) == 7 &&
         narrow == 5 && wide == 12 ? 0 : 1;
}
