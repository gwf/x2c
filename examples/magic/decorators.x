#include <assert.h>
macro Decorator $trace(Function $function) {
  printf("enter %s\n", $Code.name($function));
  defer printf("leave %s\n", $Code.name($function));
  @Code.body($function)
}

int main(void) {
// Prints "enter answer", then "leave answer".
int result = answer();
assert(result == 42);
return 0;
}

$trace()
int answer(void) => 42;
