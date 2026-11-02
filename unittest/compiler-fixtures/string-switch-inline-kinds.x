/* A public inline function with a String switch, used by
   `string-switch-inline`. */
inline int kind(String s) {
  switch (s) {
    case "a": return 1;
    case "b": return 2;
  }
  return 0;
}
