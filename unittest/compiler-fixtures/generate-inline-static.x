/* A public inline body is published in the header, where the unit's
   static functions and objects are not declared, so a use of one fails at
   the statement that holds it. */
static int helper(int x) { return x * 2; }

inline int twice(int x) {
  int doubled = helper(x);
  return doubled;
}
