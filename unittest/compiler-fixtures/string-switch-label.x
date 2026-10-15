/* Every case a String switch owns takes a string literal. */
int pick(String s, String other) {
  switch (s) {
    case "a": return 1;
    case other: return 2;
  }
  return 0;
}

int number(String s) {
  switch (s) {
    case "a": return 1;
    case 2: return 2;
  }
  return 0;
}
