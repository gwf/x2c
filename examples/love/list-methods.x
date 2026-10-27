// A named List type inherits its methods and can add its own.
#include <stdio.h>

typedef List Type;

int main(void) {
  Type declaration = %(int count);
  puts(declaration.name());
  puts(declaration.cdr().str());
  puts(declaration.cadr().str());
  return 0;
}

String Type.name(Type self) => self.car().str();
