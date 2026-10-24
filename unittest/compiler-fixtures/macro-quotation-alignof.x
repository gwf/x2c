#include "x2c.x"
#include "meta.x"

typedef struct Aligned { char a; double b; } Aligned;

meta Code alignment(Type type) {
  Code expression = $!( _Alignof($type) );
  return expression;
}

macro Expression $align(Type $type) => _Alignof($type);

int main(void) {
  printf("%d %d %d %d\n",
         $alignment($!Type{ double }) == _Alignof(double),
         $alignment($!Type{ long double }) == _Alignof(long double),
         $align(Aligned) == _Alignof(Aligned),
         $align(double *) == _Alignof(double *));
  return 0;
}
