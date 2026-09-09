#include "x2c.x"

_Static_assert(sizeof(int) >= 2, "int " "width");

macro Unit $check_width(Expr $condition) => {
  _Static_assert($condition, "macro width");
}

macro Unit $constructed_check(Expr $condition) => {
  $(list (list 'c-assert $condition
     '(expr (* char) (literal (* char) "\"constructed width\""))))...
}

$check_width(sizeof(long) >= sizeof(int));
$constructed_check(sizeof(char) == 1);

typedef struct Record {
  _Static_assert(sizeof(char) == 1, "member width");
  String text;
  int number;
} Record;

typedef union Choice {
  _Static_assert(sizeof(char) == 1, "union width");
  int integer;
  double floating;
} Choice;

int main(void) {
  _Static_assert(sizeof(Choice) >= sizeof(int), "block width");
  Record record = {"record", 4};
  printf("%d %d\n", record.text.len(), record.number);
  return 0;
}
