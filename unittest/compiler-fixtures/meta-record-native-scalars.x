#include "x2c.x"

meta int scalar_fields_probe(int offset) {
  struct {
    char a;
    signed char b;
    unsigned char c;
    short d;
    unsigned short e;
    int f;
    unsigned g;
    long h;
    unsigned long i;
    long long j;
    unsigned long long k;
    float l;
    double m;
    long double n;
  } value = {1 + offset, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14};
  return value.a + value.b + value.c + value.d + value.e + value.f +
         value.g + value.h + value.i + value.j + value.k + value.l +
         value.m + value.n;
}

int main(int argc, char **argv) {
  (void) argv;
  printf("%d %d\n", $scalar_fields_probe(0),
         scalar_fields_probe(argc - 1));
  return 0;
}
