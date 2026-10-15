static int leaked = 50;
static int helper(void) { return 2; }
module int second_value(void) {
  extern int leaked;
  int helper(void);
  return leaked + helper();
}
