#include "x2c.x"
typedef String Words[2];
typedef const Words ReadonlyWords;
typedef ReadonlyWords Names;
typedef const Names DeepNames;
typedef String *WordPointer;
typedef WordPointer const FixedPointer;
int main(void) {
  Words words = {"one", "four"};
  Names names = {String.new("five"), String.new("six")};
  Names literals = {"seven", "eight"};
  DeepNames deep = {"nine", "ten"};
  DeepNames designated = {[0] = "eleven", [1] = "twelve"};
  FixedPointer pointer = words;
  printf("%d %d %d %d %d %d %d %d %d\n", words[0].len(), names[1].len(),
         pointer[1].len(), literals[0].len(), literals[1].len(),
         deep[0].len(), deep[1].len(),
         designated[0].len(), designated[1].len());
  pointer[0] = "seven";
  printf("%s\n", words[0]);
  return 0;
}
