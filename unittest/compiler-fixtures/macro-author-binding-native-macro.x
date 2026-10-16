/* A name a template keeps with `using` reaches the file-scope declaration
   even where locals of every enclosing scope hide it. Locals of other
   functions keep their spellings, so a native macro there still reads
   them. */
#include "x2c.x"

#define PLUS_ONE (bias + 1)

macro Expression $get() using bias => bias;

static int bias = 10;

int nested(void) {
  int bias = 1;
  {
    int bias = 2;
    return $get() + bias;
  }
}

int enclosing(void) {
  int bias = 3;
  { return $get() + bias; }
}

int parameter(int bias) { return $get() * 100 + bias; }

int other(void) {
  int bias = 5;
  return PLUS_ONE;
}

int main(void) {
  printf("%d %d %d %d\n", nested(), enclosing(), parameter(4), other());
  return 0;
}
