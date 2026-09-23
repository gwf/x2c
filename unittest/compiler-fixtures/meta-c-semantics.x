/*  meta-c-semantics.x -- C operations a meta body evaluates as C does

    Indexing a real pointer reads and writes native bytes, while a pointer
    holding a local C array still indexes its Array. `NULL`, `true` and
    `false` are the preprocessor names C code writes, and a pointer compares
    with `NULL` and tests false at the null address. A typed `foreach`
    output converts each element. `bool` and int-sized enum objects have
    native layouts, so their fields and addresses work. A value reaching
    `bool` becomes 0 or 1 and compares as the int it holds. `strncmp` takes
    its length as `size_t`. Each probe prints its compile-time and run-time
    answers.
*/

#include "x2c.x"
#include <stdbool.h>

enum Color { RED, GREEN, BLUE };
enum Sign { NEGATIVE = -5, POSITIVE = NEGATIVE + 10, AFTER };

struct Flags { bool on; enum Color color; char tail; int count; };
struct Node { int value; struct Node *next; };
struct Signed { enum Sign sign; int tail; };

meta static void put_first(int *p, int value) { p[0] = value; }

meta int pointer_index(int offset) {
  int n = 5 + offset;
  int *p = &n;
  p[0] = p[0] + 2;
  put_first(&n, n * 10);
  int values[2] = {3, 4};
  put_first(values, 9);
  struct Flags flags = {1, 2, 'x', 6};
  struct Flags *fp = &flags;
  return n + values[0] * 100 + fp[0].count * 1000;
}

meta int preprocessor_names(int offset) {
  int n = offset;
  int *p = &n, *q = NULL;
  bool yes = true, no = false;
  return (p != NULL) + (q == NULL) * 10 + yes * 100 + no * 1000;
}

meta int typed_foreach(int offset) {
  int sum = offset;
  foreach (int x, [1, 2, 3]) sum = sum * 10 + x;
  return sum;
}

meta bool truth(int n) { return n; }

meta int bool_values(int offset) {
  _Bool seven = 7 + offset;
  double fraction = 0.5;
  bool half = fraction;
  bool bumped = seven;
  bumped += 2;
  bool cast = (bool) 256;
  bool pair[2] = {3};
  return seven + half * 10 + bumped * 100 + cast * 1000 + pair[0] * 10000 +
         pair[1] * 100000 + truth(9) * 1000000;
}

meta static int is_one(int n) { return n == 1; }

/* A switch on a bool is legal C that compilers warn about. */
#pragma GCC diagnostic ignored "-Wswitch-bool"

meta int bool_compare(int offset) {
  bool b = 1 + offset;
  struct Flags flags = {1, 0, 'x', 0};
  int n = 1, arm = 0;
  switch (b) {
    case 1: arm = 1; break;
    default: arm = 2;
  }
  return (b == 1) + (b == true) * 10 + (n == b) * 100 + is_one(b) * 1000 +
         (flags.on == 1) * 10000 + arm * 100000 + (b == 1.0) * 1000000;
}

meta int null_pointers(int offset) {
  struct Node tail = {2, NULL};
  struct Node head = {1, &tail};
  int sum = offset;
  for (struct Node *p = &head; p != NULL; p = p->next)
    sum = sum * 10 + p->value;
  int empty = !tail.next && tail.next == NULL && tail.next != &head;
  if (head.next) sum = sum * 10 + 3;
  if (tail.next) sum = sum * 10 + 4;
  return sum * 10 + empty;
}

meta int signed_enum(int offset) {
  struct Signed s = {-5, 7 + offset};
  enum Sign *sign = &s.sign;
  *sign = *sign - 2;
  enum Sign after = 6;
  return s.sign * 100 + s.tail + (after == 6) * 10000;
}

meta int native_fields(int offset) {
  struct Flags flags = {7, 2, 'x', 3 + offset};
  enum Color *color = &flags.color;
  *color = 1;
  bool *on = &flags.on;
  int before = *on;
  *on = 0;
  return before * 1000 + flags.on * 100 + flags.color * 10 + flags.count +
         (flags.tail == 'x') * 10000;
}

meta int string_prefix(int offset) {
  return strncmp("abcd", "abzz", 2 + offset) == 0;
}

int main(int argc, char **argv) {
  (void) argv;
  int offset = argc - 1;
  printf("%d %d\n", $pointer_index(0), pointer_index(offset));
  printf("%d %d\n", $preprocessor_names(0), preprocessor_names(offset));
  printf("%d %d\n", $typed_foreach(0), typed_foreach(offset));
  printf("%d %d\n", $bool_values(0), bool_values(offset));
  printf("%d %d\n", $native_fields(0), native_fields(offset));
  printf("%d %d\n", $bool_compare(0), bool_compare(offset));
  printf("%d %d\n", $null_pointers(0), null_pointers(offset));
  printf("%d %d\n", $signed_enum(0), signed_enum(offset));
  printf("%d %d\n", $string_prefix(0), string_prefix(offset));
  return 0;
}
