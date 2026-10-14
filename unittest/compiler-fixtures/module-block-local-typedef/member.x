static typedef int Number;
module int test(void) {
  typedef double Number;
  Number x = 1.5;
  return sizeof(x);
}
