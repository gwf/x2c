#include "lib.x"
#include "type.x"
#include <stdarg.h>

typedef int (*GlobalRest)(....);
int through_alias(GlobalRest callback) => callback(%(1 2));
int count(.... items);
int count(.... items) => items.len();
int plus(int prefix, .... items) => prefix + items.len();
int String.total(String self, int prefix, .... items) =>
  self.len() + prefix + items.len();

static int sequence;
static int next(void) => ++sequence;
static List pair(void) {
  int first = next(), second = next();
  return %($first $second);
}
static int ordered(.... items) => items.equal(%(1 2 3 4));
static int c_variadic(int first, ...) {
  va_list args;
  va_start(args, first);
  int second = va_arg(args, int);
  va_end(args);
  return first + second;
}

int main(void) {
  List values = %(1 2), empty = NULL;
  Type type = %(int);
  String text = "hey";
  int (*pointer)(int, .... items) = plus;
  typedef int (*Rest)(....);
  Rest alias_pointer = count;
  printf("%d %d %d %d %d\n", count(), count(1, 2), count(values),
    count(type, type), count(@empty));
  printf("%d %d %d %d\n", count(0, @values, 3, @empty, 4),
    pointer(10, @values), alias_pointer(1, 2, 3), text.total(10, 1, 2));
  int in_order = ordered(next(), @(pair()), next());
  printf("%d %d %d\n", in_order, sequence, c_variadic(10, 2));
  printf("%d\n", through_alias(count));
  return 0;
}
