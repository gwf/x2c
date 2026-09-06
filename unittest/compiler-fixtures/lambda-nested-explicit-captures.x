#include "x2c.x"

int main(void) {
  int value = 10;
  Func factory = %!() using &value => %!() using &value => ++value;
  value = 20;
  Func shared = factory();
  long first = shared().integer();
  value = 30;
  long second = shared().integer();

  Func snapshot_factory = %!() => %!() => value;
  value = 40;
  Func old_snapshot = snapshot_factory();
  Func reference_factory = %!() using &value => %!() => value;
  value = 50;
  Func recent_snapshot = reference_factory();
  value = 60;
  printf("shared=%ld,%ld snapshots=%ld,%ld outer=%d\n", first, second,
         old_snapshot().integer(), recent_snapshot().integer(), value);
  return 0;
}
