char *summary_public(void) {
  return Scope.memdup("public", 7);
}

char *summary_ambiguous(void) {
  return Scope.memdup("first", 6);
}

static char *_summary_static(void) {
  return Scope.memdup("first static", 13);
}
