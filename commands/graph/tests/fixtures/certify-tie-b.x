int certify_tie_native(void);
int certify_tie_shared(void) { return certify_tie_native(); }
static int certify_tie_b = certify_tie_shared();

int certify_tie_root(void) { return 0; }
