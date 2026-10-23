char *summary_ambiguous(void) {
  return xmemdup("second", 7);
}

static char *_summary_static(void) {
  return xmemdup("second static", 14);
}
