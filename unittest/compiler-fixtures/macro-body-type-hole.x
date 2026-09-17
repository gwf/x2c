#include "x2c.x"

macro Statement $keep_body_target() => {
}

macro Unit $define_body_local(Type $T) => {
  static $T $(x2c.ident "macro_body_local")($T value) {
    $T local = value;
    $keep_body_target();
    return local;
  }
}

macro Unit $define_inferred_body_local($T) => {
  static long $(x2c.ident "macro_body_inferred_local")(void) {
    $T local = 43;
    return local;
  }
}

macro Unit $define_inferred_cast($T) => {
  static long $(x2c.ident "macro_body_inferred_cast")(long value) {
    return ($T)value;
  }
}

// A parenthesized hole before `[` subscripts its value; only a `Type` hole
// casts the array literal that follows.
macro Expression $first($items) => (($items)[0])

macro Expression $literal_of(Type $T) => (($T)[1, 2])

macro Unit $define_annotated_pointer(Type $T) => {
  static $T $(x2c.ident "macro_body_annotated_pointer")($T *value) {
    $T *local = value;
    return *local;
  }
}

$define_body_local(long);
$define_inferred_body_local(long);
$define_inferred_cast(long);
$define_annotated_pointer(long);

static long ordinary_local(long value) {
  long local = value;
  return local;
}

int main(void) {
  long pointer_value = 44;
  Array numbers = [45, 46];
  printf(
    "%ld %ld %ld %ld %ld %ld %zu\n",
    macro_body_local(41),
    ordinary_local(42),
    macro_body_inferred_local(),
    macro_body_inferred_cast(44),
    macro_body_annotated_pointer(&pointer_value),
    $first(numbers).integer(),
    $literal_of(Array).len()
  );
  return 0;
}
