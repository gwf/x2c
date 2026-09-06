#include "x2c.x"

static long add(long left, long right) {
  return left + right;
}

static Var identity(Var value) {
  return value;
}

static int width(String text) {
  return String.len(text);
}

static void discard(int value) {
  (void) value;
}

static Var nothing(void) {
  return Var.null();
}

/* Prototype-only and defined in another unit: adapted like any other. */
Var Var.binary(Var lhs, Symbol op, Var rhs);

int main(void) {
  Func numeric = Func.new(add, %((func ((long) (long))) long));
  Func passthrough = Func.new(identity, %((func (("Var"))) "Var"));
  Func object = Func.new(width, %((func (("String"))) int));
  Func returns_void = Func.new(discard, %((func ((int))) void));
  Func no_parameters = Func.new(nothing, %((func ((void))) "Var"));
  Func imported = Func.new(
    Var_binary, %((func (("Var") ("Symbol") ("Var"))) "Var")
  );
  Func forwarded = Func.new(&add, %((func ((long) (long))) long));
  return !numeric || !passthrough || !object || !returns_void ||
         !no_parameters || !imported || !forwarded;
}
