/*  list-methods.x -- a named List type inherits methods and adds its own */

typedef List Type;

int main(void) {
  Type declaration = %(int count);
  puts(declaration.name());
  puts(declaration.cdr().repr());
  puts(declaration.cadr().str());
  return 0;
}

String Type.name(Type self) => self.car().str();
