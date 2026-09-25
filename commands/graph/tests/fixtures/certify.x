void certify_native(int *value);

int certify_safe(int choose) {
  Scope.retain();
  defer Scope.release();
  Scope.malloc(8);
  if (choose) return 1;
  return 2;
}

int certify_nested(int choose) {
  Scope.retain();
  defer Scope.release();
  Scope.malloc(8);
  {
    Scope.retain();
    defer Scope.release();
    Scope.malloc(4);
    if (choose) return 1;
  }
  return 2;
}

char *certify_dangle(void) {
  Scope.retain();
  defer Scope.release();
  return Scope.malloc(8);
}

int certify_native_call(void) {
  int value = 1;
  certify_native(&value);
  return value;
}

char *certify_pointer_arithmetic(char *value) {
  return value + 1;
}

int *certify_pointer_cast(char *value) {
  return (int *) value;
}

int certify_indirect(int (*callback)(void)) {
  return callback();
}

char *certify_transfer(Scope destination) {
  Scope.retain();
  defer Scope.release();
  char *result = Scope.malloc(8);
  Scope.move(result, &destination);
  return result;
}

int certify_unclosed(void) {
  Scope.retain();
  Scope.malloc(8);
  return 1;
}

struct CertifyBox { int *value; };

struct CertifyBox certify_aggregate(int *value) {
  struct CertifyBox box = { .value = value };
  return box;
}
