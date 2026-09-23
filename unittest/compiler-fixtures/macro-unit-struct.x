// Each expansion of a macro template defines its own aggregates: an
// anonymous aggregate is a new type, and a literal struct, union, or enum
// tag is private to the expansion. Members keep their spellings, including
// members a Field macro supplies, and a Name hole publishes a tag.
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

macro Unit $node(Type $type, name $get) {
  typedef struct Node Node;
  struct Node { $type value; Node *next; };
  union Pun { $type whole; unsigned char bytes[sizeof($type)]; };
  enum Mode { MODE_FIRST = 2, MODE_SECOND };
  $type $get(void) {
    Node tail = {1, NULL}, head = {2, &tail};
    union Pun pun = {.whole = 3};
    enum Mode mode = MODE_SECOND;
    return head.value + head.next->value + pun.whole + (int) mode;
  }
}

macro Unit $box(name $tag, Type $type) {
  struct $tag { $type a; };
}

$cell(int, int_sum);
$cell(unsigned long, wide_sum);
$node(int, int_node);
$node(long, long_node);
$box(Box, short);

int main(void) {
  int one = 1;
  unsigned long two = 2;
  Record record = {1, 2, 3};
  struct Box box = {4};
  printf("%d %lu %d %ld %d %ld\n", int_sum(2, &one), wide_sum(5, &two),
         int_node(), long_node(), box.a, record.updated_at);
  return int_sum(2, &one) == 3 && wide_sum(5, &two) == 7 &&
         int_node() == 9 && long_node() == 9 && box.a == 4 &&
         record.updated_at == 3 ? 0 : 1;
}
