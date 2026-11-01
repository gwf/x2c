static char *certify_static(void) {
  Scope.open();
  defer Scope.close();
  return xmalloc(8);
}

char *certify_from_a(void) { return certify_static(); }
