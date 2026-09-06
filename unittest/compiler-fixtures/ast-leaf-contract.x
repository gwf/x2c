#include "x2c.x"

typedef unsigned long ast_phase1_Size;
typedef ast_phase1_Size ast_phase1_Count;
typedef int ast_phase1_Unary(int);
typedef int (*ast_phase1_UnaryPointer)(int);
typedef void (*ast_phase1_Consumer)(const char *);

typedef struct ast_phase1_Pair {
  int value, *pointer;
  int array[3], (*array_pointer)[3];
  int (*callback)(int);
} ast_phase1_Pair;

union ast_phase1_Number {
  long integer;
  double floating;
};

enum ast_phase1_Color {
  ast_phase1_RED = 1,
  ast_phase1_BLUE
};

int ast_phase1_apply(int (*function)(int), int value);
int *ast_phase1_plain_pointer, ast_phase1_plain_array[3],
    (*ast_phase1_pointer_to_array)[3],
    (*ast_phase1_function_pointer)(int);

static int ast_phase1_zero(void) {
  return 0;
}

static int ast_phase1_identity(int value) {
  return value;
}

static int ast_phase1_add(int lhs, int rhs) {
  return lhs + rhs;
}

int ast_phase1_apply(int (*function)(int), int value) {
  return function(value);
}

int ast_phase1_Pair.bump(ast_phase1_Pair pair, int delta) {
  pair.value += delta;
  return pair.value;
}

int main(void) {
  ast_phase1_Pair pair = {
    .value = 1,
    .pointer = 0,
    .array = {1, 2, 3},
    .array_pointer = 0,
    .callback = ast_phase1_identity
  };
  ast_phase1_Count count = ast_phase1_zero();
  ast_phase1_UnaryPointer callback = ast_phase1_identity;
  ast_phase1_Consumer consumer = (void (*)(const char *)) NULL;
  List values = %(1 2 3);
  Var (left_value, right_value) = values;
  int *converted = left_value;
  count += ast_phase1_add(
    ast_phase1_apply(callback, left_value.int()),
    right_value.int()
  );
  foreach(Var value, values) {
    defer count += value.int();
  }
  match (values) {
    case %(?head *tail): {
      count += 1;
    }
    default: {
      count = 0;
    }
  }
  Var caught = void;
  try {
    if (callback((int) count) > 0)
      raise %(invariant (value $left_value));
  }
  catch %(invariant (value ?value)): {
    caught = value;
  }
  finally {
    count++;
  }
  Var lambda_value = (%!(value) => value.int() + 1)(2);
  pair.bump(caught.int());
  (void) converted;
  (void) consumer;
  (void) lambda_value;
  return 0;
}
