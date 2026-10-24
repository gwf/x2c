/* compound-auto.x -- shared cleanup requires stable bindings. */
#include "array.x"

static void replace(Array &value) { value = []; }

void stable(void) {
  Array left = auto [], right = auto [];
  left.push(1);
  right.push(2);
}

void multiline(void) {
  Array left = auto [1, 2],
        right = auto [3, 4];
}

void shared(void) {
  auto Array left = [], right = [];
}

void reassigned(void) {
  Array left = auto [], right = auto [];
  left = [];
}

void reference(void) {
  Array left = auto [], right = auto [];
  replace(left);
}

void address(void) {
  Array left = auto [], right = auto [];
  Array *alias = &right;
}

void deferred(void) {
  Array left = auto [], right = auto [];
  defer right = [];
}

void mixed(void) {
  Array left = [], middle = auto [], right = auto [];
  Array one = auto [], two = auto [], three = [];
  Array spare, first = auto [], second = auto [];
}

void shadowed(void) {
  Array left = auto [], right = auto [];
  { Array left = []; left = []; }
}

void quoted(void) {
  char *text = "Array left = auto [], right = auto [];";
  // Array left = auto [], right = auto [];
}

void captured_reference(void) {
  Array left = auto [], right = auto [];
  Func write = %!() using &left => left = [];
}

void captured_snapshot(void) {
  Array left = auto [], right = auto [];
  Func read = %!() => left.len();
}

void incremented(void) {
  Array left = auto [], right = auto [];
  left++;
}

void parenthesized_write(void) {
  Array left = auto [], right = auto [];
  (left) = [];
}
