#include "x2c.x"

int main(void) {
  Var two = 2, three = 3;
  try {
    Var product = two @ three;
    printf("%s\n", product.str());
  }
  catch %(bad-op *): printf("bad-op\n");
  return 0;
}
