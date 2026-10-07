#include "string-switch.x"
typedef String Color;
static int calls = 0;
static Color pick(Color c) { calls++; return c; }

int classify(Color s) {
  $strings.switch(pick(s)) {
    case "red": return 1;
    case "green":
    case "blue": return 2;
    case "": return 3;
    default: return 0;
  }
  return -1;
}

int fallthrough(String s) {
  int total = 0;
  $strings.switch(s) {
    case "a": total += 1;
    case "b": total += 10; break;
    default: total += 100;
  }
  return total;
}

int main(void) {
  String built = "gr" + "een";
  int ok = classify("red") == 1 && classify(built) == 2 &&
    classify("blue") == 2 && classify("") == 3 && classify(NULL) == 3 &&
    classify("purple") == 0 && calls == 6 &&
    fallthrough("a") == 11 && fallthrough("b") == 10 &&
    fallthrough("z") == 100;
  printf("%s\n", ok ? "ok" : "bad");
  return ok ? 0 : 1;
}
