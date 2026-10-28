typedef void Nothing;
static Nothing tick(void) {}
Nothing valid(void) { return tick(); }
int count(void) { return tick(); }
