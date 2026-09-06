#include "x2c.x"

typedef struct Widget {
  int x;
} *Widget;

Var Widget.var(Widget w) {
  return Var.new(<widget>, w);
}

String Widget.str(Widget w) {
  return %"Widget(${w.x})";
}

/* No reverse conversion 'Var.widget' or 'Var.as_widget': the declared
   adoption cannot resolve, and must produce a located error at the row. */
protocol Var(Widget);

int main(void) {
  printf("ok\n");
  return 0;
}
