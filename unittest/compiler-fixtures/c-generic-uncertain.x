#include "x2c.x"

typedef struct Bits { unsigned small : 3; } Bits;
enum Color { RED, GREEN };

int main(void) {
  int number = 1, *first = &number, *second = &number;
  Bits bits = {1};
  enum Color color = GREEN;
  const volatile int both = 1;
  const volatile int *pointer = &both;
  // A character constant is int in C, so x2c converts the int association.
  Var fraction = _Generic('a', int: 3.75, default: 7);
  Var whole = _Generic('a', int: 42, default: 7.5);
  Var character = _Generic((0, 'a'), char: 3.75, int: 7);
  // Qualifiers within one pointer level form a set.
  Var qualified = _Generic(pointer, volatile const int *: 9, default: 0.5);
  printf("%s %s %s %s\n", fraction.str(), whole.str(), character.str(),
         qualified.str());
  // These controlling types can differ between x2c and C, so the
  // selections stay untyped and C chooses.
  int variable = _Generic(color, enum Color: 10, default: 20);
  int constant = _Generic(RED, int: 11, default: 21);
  int promoted = _Generic(color + 0, default: 12);
  int size = _Generic(sizeof(int), size_t: 13, default: 23);
  int distance = _Generic(first - second, ptrdiff_t: 14, default: 24);
  int field = _Generic(bits.small, default: 15);
  printf("%d %d %d %d %d %d\n", variable, constant, promoted, size, distance,
         field);
  return 0;
}
