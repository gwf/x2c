#include "x2c.x"
typedef String Words[2];
typedef const Words ReadonlyWords;
typedef ReadonlyWords Names;
typedef String *WordPointer;
typedef WordPointer const FixedPointer;
int main(void) {
  Words words = {"one", "four"};
  Names names = {String.new("five"), String.new("six")};
  FixedPointer pointer = words;
  printf("%d %d %d\n", words[0].len(), names[1].len(), pointer[1].len());
  pointer[0] = "seven";
  printf("%s\n", words[0]);
  return 0;
}
