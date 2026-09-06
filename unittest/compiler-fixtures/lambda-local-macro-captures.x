#include "x2c.x"

static Func parameter_snapshot(int &parameter) {
  macro Expression read() => (%!() => parameter)
  ++parameter;
  return read();
}

static Func parameter_reader(int &parameter) {
  macro Expression read() => (%!() using &parameter => parameter)
  return read();
}

static Func parameter_writer(int &parameter) {
  macro Expression bump() => (%!() using &parameter => ++parameter)
  return bump();
}

static Func nested_reference(int value) {
  Func factory = %!() using &value => {
    macro Expression nested() => (%!() using &value => ++value)
    return nested();
  };
  return factory();
}

int main(void) {
  int value = 1;
  int unused;
  macro Expression read_snapshot() => (%!() => value)
  macro Expression read_shared() => (%!() using &value => value)
  macro Expression increment() => (%!() using &value => ++value)
  macro Expression ignore_unused() => (%!() using &unused => 41)

  value = 2;
  Func snapshot2 = read_snapshot();
  Func shared = read_shared();
  Func bump = increment();
  ScopeStats before_unused = Scope.stats();
  Func ignored = ignore_unused();
  if (Scope.stats().allocation_calls != before_unused.allocation_calls)
    return 2;
  int first_bump = bump();
  int first_read = shared();

  value = 7;
  Func snapshot7 = read_snapshot();
  int shadow_snapshot = 0;
  int shadow_bump = 0;
  int shadow_read = 0;
  {
    int value = 100;
    Func snapshot = read_snapshot();
    Func writer = increment();
    Func reader = read_shared();
    shadow_snapshot = snapshot();
    shadow_bump = writer();
    shadow_read = reader();
    if (value != 100) return 1;
  }
  value = 9;
  int first_snapshot = snapshot2();
  int second_snapshot = snapshot7();
  int final_read = shared();
  int final_bump = bump();
  int unused_result = ignored();
  printf("snapshots=%d,%d first=%d,%d shadow=%d,%d,%d ", first_snapshot,
         second_snapshot, first_bump, first_read, shadow_snapshot,
         shadow_bump, shadow_read);
  printf("final=%d,%d outer=%d unused=%d\n", final_read, final_bump,
         value, unused_result);
  int parameter = 10;
  Func parameter_value = parameter_snapshot(parameter);
  Func parameter_read = parameter_reader(parameter);
  Func parameter_bump = parameter_writer(parameter);
  parameter = 20;
  int parameter_snapshot_value = parameter_value();
  int parameter_read_value = parameter_read();
  int parameter_bump_value = parameter_bump();
  printf("parameter snapshot=%d read=%d bump=%d outer=%d\n",
         parameter_snapshot_value, parameter_read_value,
         parameter_bump_value, parameter);
  Func nested = nested_reference(30);
  int nested_first = nested();
  int nested_second = nested();
  printf("nested=%d,%d\n", nested_first, nested_second);
  return nested_first != 31 || nested_second != 32 ||
         parameter_snapshot_value != 11 || parameter_read_value != 20 ||
         parameter_bump_value != 21 || parameter != 21 ||
         first_snapshot != 2 || second_snapshot != 7 || first_bump != 3 ||
         first_read != 3 || shadow_snapshot != 7 || shadow_bump != 8 ||
         shadow_read != 8 || final_read != 9 || final_bump != 10 ||
         value != 10 || unused_result != 41;
}
