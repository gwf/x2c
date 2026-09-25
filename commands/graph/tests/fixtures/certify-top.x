int certify_top_native(void);
static int certify_top_value = certify_top_native();

int certify_top_root(void) { return certify_top_value; }
