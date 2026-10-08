#include "typed-switch.x"
typedef String Color;
static int calls = 0;
static Color pick(Color c) { calls++; return c; }
static const char *cpick(const char *c) { calls++; return c; }

int classify(Color s) {
  switch (pick(s)) {
    case "red": return 1;
    case "green":
    case "blue": return 2;
    case "": return 3;
    default: return 0;
  }
  return -1;
}

/* A C string subject is evaluated once and is not copied. */
int classify_c(const char *s) {
  switch (cpick(s)) {
    case "red": return 1;
    case "green":
    case "blue": return 2;
    case "": return 3;
    default: return 0;
  }
  return -1;
}

int classify_array(char s[]) {
  switch (s) {
    case "x": return 1;
    case "": return 3;
  }
  return 0;
}

int fallthrough(String s) {
  int total = 0;
  switch (s) {
    case "a": total += 1;
    case "b": total += 10; break;
    default: total += 100;
  }
  return total;
}

/* Integer and Symbol switches in the same file stay ordinary switches. */
int digits(int n) {
  int total = 0;
  switch (n) {
    case 1: total += 1;
    case 2: total += 10; break;
    default: total += 100;
  }
  return total;
}

int shade(Symbol s) {
  switch (s) {
    case <light>: return 1;
    case <dark>: return 2;
  }
  return 0;
}

/* A string switch nested in an integer switch, and the reverse, and a
   string switch nested in another. */
int nested(int n, String s) {
  switch (n) {
    case 1:
      switch (s) {
        case "x": return 11;
        default: return 10;
      }
    case 2: return 20;
  }
  switch (s) {
    case "y":
      switch (n) {
        case 3: return 33;
      }
      return 30;
    case "z":
      switch (s + "!") {
        case "z!": return 40;
      }
      return 41;
  }
  return 0;
}

int main(void) {
  String built = "gr" + "een";
  char buffer[] = "x";
  int ok = classify("red") == 1 && classify(built) == 2 &&
    classify("blue") == 2 && classify("") == 3 && classify(NULL) == 3 &&
    classify("purple") == 0 && calls == 6 &&
    classify_c("red") == 1 && classify_c(built) == 2 &&
    classify_c("blue") == 2 && classify_c("") == 3 &&
    classify_c(NULL) == 3 && classify_c("purple") == 0 && calls == 12 &&
    classify_array(buffer) == 1 &&
    fallthrough("a") == 11 && fallthrough("b") == 10 &&
    fallthrough("z") == 100 &&
    digits(1) == 11 && digits(2) == 10 && digits(7) == 100 &&
    shade(<light>) == 1 && shade(<dark>) == 2 && shade(<none>) == 0 &&
    nested(1, "x") == 11 && nested(1, "q") == 10 && nested(2, "x") == 20 &&
    nested(3, "y") == 33 && nested(4, "y") == 30 && nested(4, "z") == 40 &&
    nested(4, "w") == 0;
  printf("%s\n", ok ? "ok" : "bad");
  return ok ? 0 : 1;
}
