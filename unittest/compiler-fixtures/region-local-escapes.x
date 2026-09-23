#include "x2c.x"

typedef struct Box { int value; int *borrowed; } *Box;

static int *last_seen = NULL;

static int *_field_of(Box box) => &box.value;

// The address of a local is returned.
static int *returned_address(void) {
  int value = 1;
  return &value;
}

// A pointer that holds a local's address is returned.
static int *returned_pointer(void) {
  int value = 1;
  int *pointer = &value;
  return pointer;
}

// The address of a local is stored into a static.
static void stored_static(void) {
  int value = 1;
  last_seen = &value;
}

// A static local outlives the call like any static.
static void stored_static_local(void) {
  static int *cache = NULL;
  int value = 1;
  cache = &value;
}

// The address of a local is stored through a parameter.
static void stored_through_parameter(int **out) {
  int value = 1;
  *out = &value;
}

// A callee hands back an address inside the local it was given.
static int *returned_through_callee(void) {
  struct Box box = { .value = 1 };
  return _field_of(&box);
}

// Fresh storage outlives the call; the local it points into does not.
static Box stored_into_fresh(void) {
  int value = 1;
  Box box = Scope.calloc(1, sizeof(struct Box));
  box.borrowed = &value;
  return box;
}

int main(void) {
  int *out = NULL;
  stored_static();
  stored_static_local();
  stored_through_parameter(&out);
  return returned_address() != NULL && returned_pointer() != NULL &&
         returned_through_callee() != NULL && stored_into_fresh() != NULL;
}
