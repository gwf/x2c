#include "x2c.x"

/* A Var crossing to a built-in type must use that type's exact tag-checked
   reader, so a wrong-tag payload reads as NULL instead of a usable pointer.
   Var.pointer is correct only for a raw native pointer, which has no typed
   Var owner to check the tag. */
int main(void) {
  Var list_valued = %(1 2 3);
  String wrong = list_valued;
  List right = list_valued;
  Var text = %"payload";
  String exact = text;
  List not_a_list = text;
  Var mapped = %{k: 1};
  Map map = mapped;
  void *raw = list_valued;
  printf("wrong=%d right=%d exact=%s not_a_list=%d map=%d raw=%d\n",
         wrong != NULL, right != NULL, exact, not_a_list != NULL,
         map != NULL, raw != NULL);
  return 0;
}
