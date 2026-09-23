// An anonymous aggregate in a macro template is a new type in each
// expansion, and its members keep their spellings for member access,
// including members a Field macro supplies.
#include "x2c.x"

macro Field $timestamps() {
  long created_at;
  long updated_at;
}

typedef struct { int id; $timestamps(); } Record;

macro Unit $cell(Type $type, name $sum) {
  typedef struct {
    $type value;
    const $type *next;
    struct { $type total; } inner;
    $type (*combine)($type left, $type right);
  } Cell;
  static $type add($type left, $type right) => left + right;
  $type $sum($type left, const $type *right) {
    Cell cell = {left, right, {0}, add};
    Cell *view = &cell;
    view->inner.total = cell.combine(cell.value, *view->next);
    return cell.inner.total;
  }
}

macro Unit $box(Type $type, name $get) {
  struct Box { $type a; };
  $type $get(void) {
    struct Box box = {4};
    struct Box *pointer = &box;
    return box.a + pointer->a;
  }
}

$cell(int, int_sum);
$cell(unsigned long, wide_sum);
$box(short, box_get);

int main(void) {
  int one = 1;
  unsigned long two = 2;
  Record record = {1, 2, 3};
  printf("%d %lu %d %ld\n", int_sum(2, &one), wide_sum(5, &two), box_get(),
         record.updated_at);
  return int_sum(2, &one) == 3 && wide_sum(5, &two) == 7 &&
         box_get() == 8 && record.updated_at == 3 ? 0 : 1;
}
