---
slug: fields
section: magic
tab: reflection
title: The compiler knows your struct. Ask it.
---

```x2c
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
```

A `meta` function with a `TypeInfo` parameter receives the type of the
captured expression: its name, its kind, and its fields in declaration
order. Loop over the fields, quote one statement per field with
`$!Stmt{ ... }`, splice them together with `@`.

That is the whole trick behind `$derive`, in twelve lines. Reflection at
compile time, with nothing left over at run time.
