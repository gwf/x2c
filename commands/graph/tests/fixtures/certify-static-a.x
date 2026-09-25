static char *certify_static(void) {
  Scope.retain();
  defer Scope.release();
  return Scope.malloc(8);
}

char *certify_from_a(void) { return certify_static(); }
