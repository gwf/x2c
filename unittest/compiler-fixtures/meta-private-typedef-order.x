#include "x2c.x"
#include "meta.x"
static int barrier(void) => 0;
typedef struct Chain { int n; } ChainBase;
typedef struct Chain ChainOther;
typedef ChainBase Chain;
static int Chain.read(Chain value) => value.n;
meta static int describe(TypeInfo type) {
  return type.assoc(<fields>).list().len();
}
macro Expression $chain.fields(Expr $value) => $describe($value);
int main(void) {
  struct Chain chain = {3};
  printf("%d\n", $chain.fields(chain));
  return 0;
}
