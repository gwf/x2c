#include "x2c.x"

typedef struct Bits { unsigned small : 3; } Bits;
enum Color { RED, GREEN };

macro Expression $kind(Expr $value) => (
  _Generic(($value), int: "int", double: "double", char *: "char *",
           const char *: "const char *", default: "other")
)

static const char *file_scope = _Generic((long) 0, long: "long",
                                         default: "other");

static int width(int value) {
  return _Generic(value, int: 32, long: 64, default: 0);
}

// A selection reaches C unchanged and has no x2c type, so the native
// compiler chooses the association for every controlling type.
int main(void) {
  const int limit = 3;
  char buffer[8] = "buf";
  const char *text = "text";
  List names = %(a b c);
  Bits bits = {1};
  enum Color color = GREEN;
  printf("%s %s %s %s %s\n", $kind(limit), $kind(2.5), $kind(buffer),
         $kind(text), $kind(names));
  printf("%s %d\n", file_scope, width(limit));
  int character = _Generic('a', int: 1, default: 2);
  int variable = _Generic(color, enum Color: 3, default: 4);
  int size = _Generic(sizeof(int), size_t: 5, default: 6);
  int field = _Generic(bits.small, default: 7);
  Var boxed = (int)_Generic(names, List: 8, default: 9);
  printf("%d %d %d %d %s\n", character, variable, size, field, boxed);
  return 0;
}
