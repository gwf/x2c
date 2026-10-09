#include "x2c.x"

static int calls = 0;
static List subject(List value) { calls++; return value; }

static int classify(List value) {
  match (subject(value)) {
    case %(nested (a 7 "text")): return 1;
    case %(same ?x ?x): return 2;
    case %(tail ?head *rest): return 3;
    case %(typed ?(int count)): return 4;
    case %(empty): return 5;
    default: return 0;
  }
}

static int ordinary(int value) {
  switch (value) {
    case 7: return 7;
    default: return 0;
  }
}

static int void_pattern(List value) {
  match (value) {
    case %(marker (!is type void)): return 1;
    default: return 0;
  }
}

int main(void) {
  List pattern = %(marker (!is type void));
  List absent = %(marker);
  int ok = absent.match(pattern) == NULL && void_pattern(absent) == 0 &&
    classify(%(nested (a 7 "text"))) == 1 &&
    classify(%(nested (a 8 "text"))) == 0 &&
    classify(%(same 9 9)) == 2 && classify(%(same 9 8)) == 0 &&
    classify(%(tail first second third)) == 3 &&
    classify(%(tail first)) == 3 && classify(%(tail)) == 0 &&
    classify(%(typed 12)) == 4 && classify(%(typed "12")) == 0 &&
    classify(%(empty)) == 5 && classify(NULL) == 0 && calls == 11 &&
    ordinary(7) == 7 && ordinary(3) == 0;
  puts(ok ? "ok" : "bad");
  return ok ? 0 : 1;
}
