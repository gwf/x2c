char *summary_ambiguous(void) {
  return Scope.memdup("second", 7);
}

static char *_summary_static(void) {
  return Scope.memdup("second static", 14);
}
