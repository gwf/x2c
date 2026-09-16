#include "x2c.x"

class Name String;
typedef String Label;

/* Equal text interned in sibling pools has distinct pointers, so only String
   equality reports these operands equal. */
int main(void) {
  Pool root = String.pool_current();
  Pool left = root.retain(), right = root.retain();
  Name name = String.new_in(left, "build", 5);
  String text = String.new_in(right, "build", 5);
  Label label = String.new_in(root, "build", 5);
  printf("%d %d %d %d %d %d\n", name == text, text == name, label == text,
         text == label, name == label, label == name);
  printf("%d %d %d\n", name != text, text != label, label != name);
  printf("%d %d %d\n", name < text, text > label, label <= name);
  right.release();
  left.release();
  return 0;
}
