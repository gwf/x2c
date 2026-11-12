---
slug: fields
section: magic
home: true
order: 4
tab: reflection
title: The compiler can describe your types.
---

```x2c
~#include "meta.x"

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

~int main(void) {
  Reading noon = { 21, "roof", 12 };
  $show(noon);
~  return 0;
~}
```

Inspect a type's fields at compile time and generate code that visits them. This is the same general technique behind derived operations: the declaration supplies the information instead of a second handwritten field list.
