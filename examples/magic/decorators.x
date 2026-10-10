#include <assert.h>
macro Decorator $trace(Function $function) {
  printf("enter %s\n",
    $(x2c.literal.string (Code.name $function)));
  defer printf("leave %s\n",
    $(x2c.literal.string (Code.name $function)));
  @(Code.body $function)
}

$trace()
int answer(void) => 42;

int main(void) {
// Prints "enter answer", then "leave answer".
int result = answer();
assert(result == 42);
return 0;
}
