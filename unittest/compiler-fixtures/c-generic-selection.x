#include "x2c.x"

typedef unsigned int Count;
typedef int (*Handler)(int);

macro Expression $kind(Expr $value) => (
  _Generic(($value), int: "int", double: "double", char *: "char *",
           const char *: "const char *", default: "other")
)

static const char *file_scope = _Generic((long) 0, long: "long",
                                         default: "other");

static int twice(int value) => value * 2;

static int width(int value) {
  return _Generic(value, int: 32, long: 64, default: 0);
}

int main(void) {
  const int limit = 3;
  char buffer[8] = "buf";
  Count count = 4;
  size_t size = 5;
  const char *text = "text";
  List names = %(a b c);
  printf("%s %s %s %s %s\n", $kind(limit), $kind(2.5), $kind(buffer),
         $kind(text), $kind(names));
  printf("%s %d\n", file_scope, width(limit));
  if (_Generic(names, List: 1, default: 0))
    printf("%d\n", _Generic(limit, int: names, default: NULL).len());
  // Each value converts to Var by the association x2c selects; selecting
  // differently from C would convert an int as a string.
  Var constant = _Generic(limit, int: 1, default: "no");
  Var array = _Generic(buffer, char *: 1, default: "no");
  Var alias = _Generic(count, unsigned: 1, default: "no");
  Var system = _Generic(size, size_t: 1, default: "no");
  Var function = _Generic(twice, Handler: 1, default: "no");
  Var pointee = _Generic(text, char *: "no", const char *: 1);
  printf("%s %s %s %s %s %s\n", constant.str(), array.str(), alias.str(),
         system.str(), function.str(), pointee.str());
  printf("%s\n", %"${_Generic(size, size_t: names, default: NULL)}");
  return 0;
}
