#include "x2c.x"

typedef struct DirectValue {
  int value;
} DirectValue;

protocol DirectProtocol(T) {
  int T.read(T);
}

int DirectValue.read(DirectValue value) {
  return value.value;
}

protocol DirectProtocol(DirectValue);

typedef enum DirectKind {
  DIRECT_KIND = 3
} DirectKind;

typedef struct DirectRecord {
  int value;
} DirectRecord;

typedef union DirectUnion {
  int integer;
  float floating;
} DirectUnion;

int direct_function(int value);

inline int direct_inline(int value) {
  return value + 1;
}

int direct_function(int value) {
  return value + DIRECT_KIND;
}

macro Unit $generated_protocol() => {
  protocol GeneratedProtocol(T) {
    int T.read(T);
  }

  protocol GeneratedProtocol(DirectValue);
}

macro Unit $generated_units() => {
  #define GENERATED_SOURCE_FLAG 1

  typedef enum GeneratedKind {
    $(x2c.ident "GENERATED_KIND") = 3
  } $(x2c.ident "GeneratedKind");

  typedef struct GeneratedRecord {
    int $(x2c.ident "value");
  } $(x2c.ident "GeneratedRecord");

  typedef union GeneratedUnion {
    int $(x2c.ident "integer");
    float $(x2c.ident "floating");
  } $(x2c.ident "GeneratedUnion");

  static int $(x2c.ident "generated_global") = 4;

  int $(x2c.ident "generated_function")(int value);

  inline int $(x2c.ident "generated_inline")(int value) {
    return value + 1;
  }

  int $(x2c.ident "generated_function")(int value) {
    return value + 3;
  }
}

macro Unit $generated_macro_definition() => {
  macro Expression $generated_read(Expr $value) => ($value.read())
}

$generated_protocol();
$generated_units();
$generated_macro_definition();

int main(void) {
  DirectValue direct = { .value = 37 };
  DirectRecord direct_record = { .value = 1 };
  DirectUnion direct_union = { .integer = direct_record.value };
  GeneratedRecord generated_record = { .value = 1 };
  GeneratedUnion generated_union = { .integer = generated_record.value };
  int parity = direct_function(direct_union.integer) +
               generated_function(generated_union.integer) +
               direct_inline(0) + generated_inline(0) +
               generated_global + GENERATED_SOURCE_FLAG;
  printf("%d %d\n", $generated_read(direct), parity);
  return 0;
}
