#include "x2c.x"

typedef struct Base { int x; } *Base;
typedef struct Parent { int x; } *Parent;
typedef Parent Child;
Base Parent.base(Parent value) => (Base) value;
protocol Base(T) { int T.hello(T); }
int Base.hello(Base base) => 1;
int Child.hello(Child child) => 3;
protocol Base(Parent);

int greet(Child child) => child.hello();
