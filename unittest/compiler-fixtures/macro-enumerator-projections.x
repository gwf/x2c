#include "x2c.x"
#include "macro-enumerator-projections-defs.x"

macro Enumerator $fixture.empty() {
  @no_rows()
}

macro Enumerator $fixture.one() {
  $x2c_ident("ROW_ONE") = 2
}

macro Enumerator $fixture.enumerators() {
  private_row = 3,
  @enum_rows(),
  $x2c_ident("ROW_AUTO") = private_row + 5
}

macro Enumerator $fixture.forward(Enumerator $row) {
  $row
}

macro Expression $fixture.initializer() => $row_initializer();

macro Stmt $fixture.cases() {
  @case_rows()
}

typedef enum GeneratedRows {
  ROW_START,
  $fixture.empty(),
  $fixture.one(),
  $fixture.enumerators(),
  $fixture.forward(ROW_FORWARDED = 11),
  ROW_FOLLOWING
} GeneratedRows;

static int row_values[] = $fixture.initializer();

static int row_value(Symbol tag) {
  switch (tag) {
    $fixture.cases();
  }
  return -1;
}

int main(void) {
  printf("%d %d %d %d %d %d %d\n",
         ROW_START, ROW_LEDGER, ROW_AUTO, ROW_FORWARDED, ROW_FOLLOWING,
         row_values[0], row_value(<ledger-tag>));
  return 0;
}
