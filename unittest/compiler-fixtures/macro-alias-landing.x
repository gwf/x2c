#include "x2c.x"

macro Expression $read_w() => w;
macro Expression $read_q() => q;

static Func from_reference(int &value) {
  alias value + 1 as next;
  return %!() => next;
}

int main(void) {
  int w = 100, base = 4;
  {
    alias 7 as w;
    alias base * 2 as q;
    printf("%d %d %d\n", w, $read_w(), $read_q());
    Func nested = %!() => $read_q();
    printf("%ld\n", nested().integer());
  }
  alias base as kept;
  {
    int base = 90;
    Func hidden = %!() => kept;
    printf("%d %ld\n", base, hidden().integer());
  }
  alias base + 1 as plus;
  Func expression = %!() => plus;
  Func grouped = %!() => (plus);
  Func initializer = %!() => { int value = plus; return value; };
  Func condition = %!() => { if (plus) return 9; return 0; };
  Func reference = from_reference(base);
  base = 20;
  printf("%ld %ld %ld %ld\n", expression().integer(), grouped().integer(),
         initializer().integer(), condition().integer());
  printf("%ld\n", reference().integer());
  return 0;
}
