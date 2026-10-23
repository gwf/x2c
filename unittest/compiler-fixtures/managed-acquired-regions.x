#include "x2c.x"

Array independent_replacement(void) {
  Array a = $auto([]);
  a = [];
  return a;
}

Array mutable_defer(void) {
  Array a = [], b = a;
  defer b.cleanup();
  b = [];
  return a;
}

char *independent_null_slots(void) {
  Scope slot = NULL;
  Scope saved = $auto(slot);
  return Scope.malloc_in(&slot, 8);
}

char *null_move_does_not_fill(void) {
  Scope slot = NULL;
  Scope.move(NULL, &slot);
  Scope saved = $auto(slot);
  return Scope.malloc_in(&slot, 8);
}

Array escaping_scope_alias(void) {
  Scope slot = Scope.new();
  Scope saved = $auto(slot);
  Array a;
  $scope(&slot) { a = []; }
  return a;
}

char *escaping_filled_slot(void) {
  Scope slot = NULL;
  Scope *address = &slot;
  char *text = Scope.malloc_in(address, 8);
  Scope saved = $auto(slot);
  return text;
}

char *escaping_moved_slot(void) {
  Scope slot = NULL;
  char *text = xmalloc(8);
  Scope.move(text, &slot);
  Scope saved = $auto(slot);
  return text;
}

Array move_keeps_cleanup(Scope *keep) {
  Array a = $auto([]);
  Scope.move(a, keep);
  return a;
}

Func closure_keeps_cleanup(Scope *keep) {
  Array a = $auto([]);
  Scope.move(a, keep);
  return %!() => a.len();
}

char *lazy_defer(void) {
  Scope slot = NULL;
  defer slot.cleanup();
  return Scope.malloc_in(&slot, 8);
}

Array conditional_cleanup(int flag) {
  Array plain = [], managed = $auto([]);
  Array result = flag ? plain : managed;
  return result;
}

Array branch_keeps_cleanup(int flag) {
  Array a = $auto([]);
  if (flag) a = [];
  return a;
}

Array loop_keeps_cleanup(int count) {
  Array a = $auto([]);
  for (int i = 0; i < count; i++) a = [];
  return a;
}

Array and_keeps_cleanup(int flag) {
  Array a = $auto([]);
  flag && (a = [], 1);
  return a;
}

Array or_keeps_cleanup(int flag) {
  Array a = $auto([]);
  flag || (a = [], 1);
  return a;
}

Array choice_keeps_cleanup(int flag) {
  Array a = $auto([]);
  flag ? (a = []) : a;
  return a;
}

Array argument_keeps_cleanup(int flag) {
  Array a = $auto([]);
  printf("%d\n", flag && (flag > 1 ? (a = [], 1) : 0));
  return a;
}

Array first_operand_replaces(int flag) {
  Array a = $auto([]);
  (a = []).len() && flag;
  return a;
}
