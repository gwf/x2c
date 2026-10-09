#include "rewrite.x"

static int selected = 10;
macro Expression $selected_sum(Expr $value) using selected => $value + selected;

$rewrite($selected_sum)
meta Code replace_selected(Code code) => $!int{99};

int main(void) {
  int value = 1;
  printf("%d ", value + selected);
  {
    int selected = 2;
    printf("%d ", value + selected);
  }
  printf("%d\n", value + selected);
  return 0;
}
