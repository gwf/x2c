#include "x2c.x"
#include "meta.x"
typedef void (*TestFn)(void);
static Array tests;
static void register_test(String name, TestFn fn) {
  if (!tests) tests = [];
  tests.push(%($name $((long) fn)));
}
meta static List test_register(List function) {
  String name = Code.name(function);
  List ident = x2c_ident(name);
  x2c_place(%(unit-init), $!{ register_test($name, $ident); });
  return $(function);
}
macro Decorator $test(Unit $function) { @test_register($function) }
$test()
static void adds(void) { printf("adds runs\n"); }
$test()
static void subtracts(void) { printf("subtracts runs\n"); }
int main(void) {
  foreach (List row in tests) {
    printf("test %s\n", row.car());
    ((TestFn) (long) row.cadr())();
  }
  return 0;
}
