#include "x2c.x"

typedef int (*NativeCallback)(int);
static int increment(int value) => value + 1;
static NativeCallback create_callback(void) {
  return %!(int value) => value + 3;
}
static int apply(int value, int (*callback)(int)) => callback(value);

int main(void) {
  typedef int Count;
  Count value = 3;
  Func read = %!() => value;
  Func add = %!(Count amount) => value + amount;
  if (read() != 3 || add(4) != 7) return 1;

  typedef int (*Callback)(int);
  typedef Callback CallbackAlias;
  CallbackAlias native = increment;
  CallbackAlias callback = %!(int argument) => argument + 1;
  int (*direct)(int) = %!(int argument) => argument + 1;
  callback = %!(int argument) => argument + 2;
  direct = %!(int argument) => argument + 2;
  if (native(5) != 6 || callback(5) != 7 || direct(5) != 7) return 2;
  int apply(int value, Callback callback);
  if (apply(6, %!(Count argument) => argument + 2) != 8) return 3;
  NativeCallback returned = create_callback();
  if (returned(1) != 4) return 4;
  puts("local aliases survive captured and native call lowering");
  return 0;
}
