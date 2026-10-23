char *summary_public(void) {
  return xmemdup("public", 7);
}

char *summary_ambiguous(void) {
  return xmemdup("first", 6);
}

static char *_summary_static(void) {
  return xmemdup("first static", 13);
}
