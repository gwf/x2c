#include "x2c.x"

$(def fixture.row '(ledger-tag ROW_LEDGER object 7))

$(defun fixture.row.id (row)
  (car (cdr row)))

$(defun fixture.row.value (row)
  (car (cdr (cdr (cdr row)))))

$(defun fixture.int-expr (value)
  `(expr (int) (literal (int) ,(str value))))

$(defun fixture.enum-row (row)
  `(op =
    (bind ,(x2c.ident (str (fixture.row.id row))) ())
    ,(fixture.int-expr (fixture.row.value row))))

$(defun fixture.initializer (row)
  `(expr ()
    (composite
      (commas ,(fixture.int-expr (fixture.row.value row))))))

$(defun fixture.case-row (row)
  (list
    `(case
      (expr ("Symbol")
        (literal ("Symbol") ,(str (car row)) ,(car row))))
    `(return (int) ,(fixture.int-expr (fixture.row.value row)))))

macro Enumerator $fixture.empty() => {
  $(list)...
}

macro Enumerator $fixture.one() => {
  $(x2c.ident "ROW_ONE") = 2
}

macro Enumerator $fixture.enumerators() => {
  private_row = 3,
  $(list (fixture.enum-row fixture.row))...,
  $(x2c.ident "ROW_AUTO") = private_row + 5
}

macro Enumerator $fixture.forward(Enumerator $row) => {
  $row
}

macro Expression $fixture.initializer() => (
  $(fixture.initializer fixture.row)
)

macro Statement $fixture.cases() => {
  $(fixture.case-row fixture.row)...
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
