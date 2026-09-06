#include "typed-array.x"

int main(void) {
  Map map = %{key: 7};
  ArrayInt packed = %[1];
  Var preserved = map[<key>];
  int unsafe = packed[<key>];
  return preserved.int() + unsafe;
}
