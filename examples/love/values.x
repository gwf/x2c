#include <assert.h>

// One parameter and result type; behavior follows the contained value.
Var twice(Var value) => value + value;

int main(void) {
  // The same function adds numbers and joins text.
  Var number = twice(21), text = twice("ha");
  printf("%s %s\n", number, text);

  // Test a contained type, or inspect its broader kind.
  assert(number is int && text is String);
  printf("%s %s\n", number.kind().str(), text.kind().str());

  // A Var can hold another kind of value later.
  number = "sold out";
  if (number is String)
    printf("%s\n", number);
  return 0;
}
