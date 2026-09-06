#include "x2c.x"

typedef struct DirectOne {
  List values;
} *DirectOne;

typedef struct DirectTwo {
  List values;
} *DirectTwo;

typedef struct ValueCursor {
  List values;
} *ValueCursor;

typedef struct FloatCursor {
  List values;
} *FloatCursor;

typedef struct StringCursor {
  List values;
} *StringCursor;

typedef struct VoidCursor {
  List values;
} *VoidCursor;

typedef struct ValueOutput {
  List values;
} *ValueOutput;

typedef struct WrongReturn {
  List values;
} *WrongReturn;

static int direct_one_calls;
static int direct_two_calls;
static int invalid_calls;

Iter DirectOne.iter(DirectOne bag, Iter dest) {
  return bag.values.iter(dest);
}

int DirectOne.try_next(DirectOne bag, unsigned *cursor, int *out) {
  direct_one_calls++;
  if (*cursor >= bag.values.len()) return 0;
  *out = bag.values[*cursor].integer();
  ++*cursor;
  return 1;
}

protocol Iter(DirectOne);

Iter DirectTwo.iter(DirectTwo bag, Iter dest) {
  return bag.values.iter(dest);
}

int DirectTwo.try_next(DirectTwo bag, unsigned *cursor, int *key, int *out) {
  direct_two_calls++;
  if (*cursor >= bag.values.len()) return 0;
  *key = *cursor;
  *out = bag.values[*cursor].integer();
  ++*cursor;
  return 1;
}

protocol Iter(DirectTwo);

Iter ValueCursor.iter(ValueCursor bag, Iter dest) {
  return bag.values.iter(dest);
}

int ValueCursor.try_next(ValueCursor bag, unsigned cursor, int *out) {
  (void) bag;
  (void) cursor;
  (void) out;
  invalid_calls++;
  return 0;
}

protocol Iter(ValueCursor);

Iter FloatCursor.iter(FloatCursor bag, Iter dest) {
  return bag.values.iter(dest);
}

int FloatCursor.try_next(FloatCursor bag, float *cursor, int *out) {
  (void) bag;
  (void) cursor;
  (void) out;
  invalid_calls++;
  return 0;
}

protocol Iter(FloatCursor);

Iter StringCursor.iter(StringCursor bag, Iter dest) {
  return bag.values.iter(dest);
}

int StringCursor.try_next(StringCursor bag, String *cursor, int *out) {
  (void) bag;
  (void) cursor;
  (void) out;
  invalid_calls++;
  return 0;
}

protocol Iter(StringCursor);

Iter VoidCursor.iter(VoidCursor bag, Iter dest) {
  return bag.values.iter(dest);
}

int VoidCursor.try_next(VoidCursor bag, void *cursor, int *out) {
  (void) bag;
  (void) cursor;
  (void) out;
  invalid_calls++;
  return 0;
}

protocol Iter(VoidCursor);

Iter ValueOutput.iter(ValueOutput bag, Iter dest) {
  return bag.values.iter(dest);
}

int ValueOutput.try_next(ValueOutput bag, unsigned *cursor, int out) {
  (void) bag;
  (void) cursor;
  (void) out;
  invalid_calls++;
  return 0;
}

protocol Iter(ValueOutput);

Iter WrongReturn.iter(WrongReturn bag, Iter dest) {
  return bag.values.iter(dest);
}

long WrongReturn.try_next(WrongReturn bag, unsigned *cursor, int *out) {
  (void) bag;
  (void) cursor;
  (void) out;
  invalid_calls++;
  return 0;
}

protocol Iter(WrongReturn);

int main(void) {
  DirectOne direct_one = Scope.malloc(sizeof(struct DirectOne));
  direct_one.values = %(1 2 3);
  long one_total = 0;
  foreach(long value, direct_one) one_total += value;

  DirectTwo direct_two = Scope.malloc(sizeof(struct DirectTwo));
  direct_two.values = %(10 20 30);
  int two_total = 0;
  foreach(int (key, value), direct_two) two_total += key + value;

  ValueCursor value_cursor = Scope.malloc(sizeof(struct ValueCursor));
  value_cursor.values = %(1 2 3);
  FloatCursor float_cursor = Scope.malloc(sizeof(struct FloatCursor));
  float_cursor.values = %(1 2 3);
  StringCursor string_cursor = Scope.malloc(sizeof(struct StringCursor));
  string_cursor.values = %(1 2 3);
  VoidCursor void_cursor = Scope.malloc(sizeof(struct VoidCursor));
  void_cursor.values = %(1 2 3);
  ValueOutput value_output = Scope.malloc(sizeof(struct ValueOutput));
  value_output.values = %(1 2 3);
  WrongReturn wrong_return = Scope.malloc(sizeof(struct WrongReturn));
  wrong_return.values = %(1 2 3);

  int fallback_total = 0;
  foreach(int value, value_cursor) fallback_total += value;
  foreach(int value, float_cursor) fallback_total += value;
  foreach(int value, string_cursor) fallback_total += value;
  foreach(int value, void_cursor) fallback_total += value;
  foreach(int value, value_output) fallback_total += value;
  foreach(int value, wrong_return) fallback_total += value;

  printf("%ld %d %d %d %d %d\n", one_total, two_total,
         fallback_total, direct_one_calls, direct_two_calls, invalid_calls);
  return one_total == 6 && two_total == 63 && fallback_total == 36 &&
         direct_one_calls == 4 && direct_two_calls == 4 && !invalid_calls
    ? 0 : 1;
}
