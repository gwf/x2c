#include "x2c.x"

typedef struct StaticDescriptor {
  int value;
} *StaticDescriptor;

static Var StaticDescriptor.var(StaticDescriptor value) {
  return Var.new(<staticdesc>, value);
}

static StaticDescriptor Var.staticdescriptor(Var value) {
  return value.pointer();
}

String StaticDescriptor.str(StaticDescriptor value) {
  return %"private:${value.value}";
}

static protocol Var(StaticDescriptor);

int main(void) {
  StaticDescriptor value =
    Scope.malloc(sizeof(struct StaticDescriptor));
  value.value = 42;
  Var boxed = value;
  printf("%s\n", boxed.str());
  return 0;
}
