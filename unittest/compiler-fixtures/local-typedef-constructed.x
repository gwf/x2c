#include "x2c.x"

typedef int Base;

static int increment(int value) => value + 1;

meta static List type_rows(void) {
  return %(
    (typedef (int) (bindings (bind ("Count") ())))
    (typedef (int)
      (bindings (bind ("Callback")
        (* (fnmod (params (param ("Count") (bind () ()))))))))
    (declare ("Callback")
      (bindings (op = (bind ("callback") ())
        (expr () (ident ("increment"))))))
    (return (int) (expr ()
      (call (expr () (ident ("callback")))
        (args (expr (int) (literal (int) "7"))))))
  );
}

meta static List capture_of(List value) {
  match (value) {
    case %(expr ? (ident ?binding)):
      return %(expr ("Func")
        (lambda (params)
          (captures (capture $binding ${Code.type(value)} $value))
          $value));
  }
  return %();
}

meta static List reference_of(List value) {
  match (value) {
    case %(expr ? (ident ?binding)): {
      List value_type = Code.type(value);
      List type = %(& @value_type);
      return %(expr ("Func")
        (lambda (params)
          (captures (capture $binding $type (expr $type (op & $value))))
          (expr $value_type (op * (expr $type (ident $binding))))));
    }
  }
  return %();
}

macro Unit $constructed_types() {
  static int $x2c_ident("constructed_types")(void) {
    @type_rows()
  }
}

macro Expression $constructed_capture(Expr $value) => $capture_of($value);

macro Expression $constructed_reference(Expr $value) =>
  $reference_of($value);

$constructed_types();

int main(void) {
  typedef int LocalCount;
  LocalCount value = 9;
  Func captured = $constructed_capture(value);
  value = 10;
  if (constructed_types() != 8 || captured() != 9) return 1;
  typedef Base Alias;
  Alias referent = 1;
  {
    typedef double Base;
    Base fraction = 0.5;
    Func reference = $constructed_reference(referent);
    referent = 2;
    if (reference() != 2 || fraction != 0.5) return 2;
  }
  puts("constructed declarations and resolved capture types preserve scope");
  return 0;
}
