void certify_native(int *value);

int certify_scalar_rows(void) {
  Symbol word = <word>;
  return word.var().integer();
}

long certify_wide_scoped(void) {
  Scope.retain();
  defer Scope.release();
  return 42L.var().integer();
}

Var certify_wide_dangle(void) {
  Scope.retain();
  defer Scope.release();
  return 42L.var();
}

int certify_pure_branch(Var value, int choose) {
  if (choose) return value.integer();
  return 0;
}

int certify_conditional_alloc(int choose) {
  if (choose) Scope.malloc(8);
  return 0;
}

int certify_literal_printf(void) {
  return printf("value=%d\n", 7);
}

int certify_file_printf(void) {
  return Stdout.printf("value=%d\n", 7);
}

int certify_write_printf(short *value) {
  return printf("%1$hn", value);
}

int certify_escaped_printf(int *value) {
  return printf("\x25n", value);
}

int certify_dynamic_printf(const char *format) {
  return printf(format, 7);
}

void certify_index_escape(int **out) {
  Scope.retain();
  defer Scope.release();
  out[0] = Scope.malloc(sizeof(int));
}

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
