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

// Either arm of a conditional can be the one that leaves.
static int *returned_second_arm(int flag, int *other) {
  int value = 1;
  return flag ? other : &value;
}

// A local array decays to the address of its first element.
static int *returned_array(void) {
  int values[4] = {0};
  return values;
}

// A defer restores the static only after the early return.
static int restored_too_late(int stop) {
  int value = 1;
  last_seen = &value;
  if (stop) return 1;
  defer last_seen = NULL;
  return 0;
}

int main(void) {
  int *out = NULL;
  stored_static();
  stored_static_local();
  stored_through_parameter(&out);
  return returned_address() != NULL && returned_pointer() != NULL &&
         returned_through_callee() != NULL && stored_into_fresh() != NULL &&
         returned_second_arm(0, out) != NULL && returned_array() != NULL &&
         !restored_too_late(0);
}
