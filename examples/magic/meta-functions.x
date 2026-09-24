#include "meta.x"
#include <assert.h>
// A macro implemented in x2c rather than in compile-time Lisp. `meta` marks
// a function the compiler runs during translation, and the `x2c_*` functions
// `meta.x` declares are the compiler surface those functions call.

typedef struct Response {
  int code;
  String label;
} Response;

// The named fields of a struct-typed expression, in declaration order. The
// answer comes from the compiler's symbol table.
meta static List fields_of(List receiver) =>
  x2c_type_fields(x2c_syntax_type(receiver));

// The field names as one comma-joined String literal.
meta static List field_names(List receiver) {
  Array names = [];
  foreach (List field, fields_of(receiver)) names.push(field.car());
  return x2c_literal_string(String.join(", ", names));
}

// `{ r.code, r.label }`, built from the fields rather than written out.
meta static List field_reads(List receiver) {
  Array reads = [];
  foreach (List field, fields_of(receiver))
    reads.push(x2c_expr_field(receiver, field.car()));
  return x2c_expr_composite(reads);
}

macro Expression $shape.names(Expr $value) => $(field_names $value);

macro Expression $shape.reads(Expr $value) => $(field_reads $value);

// A `meta` function that reaches no compiler operation keeps both of its
// forms: `$(tag ...)` runs during translation and `tag(...)` at run time.
meta static String tag(String name, int n) => %"$name-$n";

int main(void) {
  Response found = { 200, "OK" };
  printf("fields  %s\n", $shape.names(found));

  Response copy = $shape.reads(found);
  printf("copy    %d %s\n", copy.code, copy.label);

  printf("tag     %s %s\n", $(tag "row" 4), tag("row", 4));

  assert(String.equal($shape.names(found), "code, label"));
  assert(copy.code == 200);
  return 0;
}
