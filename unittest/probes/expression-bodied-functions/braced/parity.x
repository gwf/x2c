#include "x2c.x"

typedef struct Counter {
  int value;
} Counter;

typedef int (*Callback)(int);

macro Expression $plus_one(Expr $value) => ($value + 1)

macro Unit $define_generated(Name $name) => {
  int $name(int value) {
    return value + 2;
  }
}

macro Unit $forward(Function $definition) => {
  $definition
}

macro Decorator $identity(Function $function) => {
  $(x2c.function.body $function)...
}

static int twice(int value) {
  return value * 2;
}

int public_value(int value) {
  return value + 1;
}

int Counter.add(Counter counter, int amount) {
  return counter.value + amount;
}

static int multiline(int value) {
  return value +
         1;
}

static double converted(int value) {
  return value;
}

static int comma_effect;

static int conditional_comma(int value) {
  return (comma_effect += value < 0 ? -value : value), 3;
}

static Counter native_compound(int value) {
  return (Counter) { .value = value };
}

static Map x2c_compound(int value) {
  return %{value: $value};
}

static String interpolated(int value) {
  return %"value=$value";
}

static Func make_adder(int base) {
  return %!(int value) => {
    return base + value;
  };
}

static int macro_value(int value) {
  return $plus_one(value);
}

$define_generated(generated_value);

$forward(static int forwarded(int value) {
  return value + 10;
});

$identity()
static int decorated(int value) {
  return value + 4;
}

static int implementation(int value) {
  return value + 1;
}

static int object_value = 2;
static Callback callback = implementation;

int declared(int value);

int declared(int value) {
  return value + object_value;
}

int main(void) {
  Counter counter = native_compound(7);
  Map map = x2c_compound(9);
  Func add = make_adder(5);
  String text = interpolated(8);
  int total = twice(3) + public_value(4) + counter.add(2) +
              multiline(5) + (int) converted(6) +
              conditional_comma(-4) + counter.value + map.len() +
              macro_value(10) + generated_value(10) + forwarded(10) +
              decorated(10) + callback(15) + add(6).integer() + declared(1);
  printf("%d %s\n", total, text);
  return 0;
}
