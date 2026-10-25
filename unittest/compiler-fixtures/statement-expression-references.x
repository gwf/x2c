#include "x2c.x"

meta static List wrapped_of(List value) =>
  %(expr () (parens (block (stmnt $value))));

macro Expression $wrapped(Expr $value) => $wrapped_of($value);

static int required(int &value) => ({ value; });

static int proven(int &?value) {
  if (!value) return -1;
  return ({ value; });
}

static int present(int &?value) => value != NULL;

static int forward(int &?value) => present(({ value; }));

static int constructed(int &?value) => present($wrapped(value));

int main(void) {
  int value = 5;
  printf("%d %d %d %d %d %d %d\n", required(value), proven(value),
         proven(NULL), forward(value), forward(NULL), constructed(value),
         constructed(NULL));
  return 0;
}
