#include "meta.x"

typedef struct Reading { int celsius; String station; int gusts; } Reading;

// The compiler hands a meta function the fields of a struct type.
meta static List show_fields(List receiver, TypeInfo type) {
  Array lines = [];
  foreach (List field in type.assoc(<fields>)) {
    String name = field.car();
    List label = $!String{ $name };
    lines.push($!Stmt{ printf("%s = %s\n", $label, (Var) $receiver.$name); });
  }
  return $!Stmt{ { @(lines.list_free()) } };
}

// The macro captures the expression; the meta function writes the code.
macro Stmt $show(Expr $value) => $show_fields($value, $value);

int main(void) {
  Reading noon = { 21, "roof", 12 };
  $show(noon);
  return 0;
}
