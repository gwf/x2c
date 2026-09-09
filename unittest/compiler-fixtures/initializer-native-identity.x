#include "x2c.x"

#define ROWS 2
typedef struct NativeRows { String names[ROWS]; Var last; } NativeRows;
#undef ROWS
#define ROWS 1

enum { counter_base = __COUNTER__ };
static String indexed[2] = {
  [__COUNTER__ - counter_base - 1] = "one", "two"
};

typedef struct Pair { String value; } Pair;
macro Expression $canonical(Expr $value) => (
  $(list 'expr '("Pair") (list 'cast '("Pair")
    (list 'expr '("Pair") (list 'composite (list 'commas $value)))))
)

int main(void) {
  NativeRows row = {.names[0] = "one", "two", "three"};
  String tail = row.last, expected = "kept";
  Pair ordinary = (Pair) {"kept"};
  Pair canonical = $canonical("kept");
  printf("%d %d %d %d\n",
    row.names[0].len() + row.names[1].len() + tail.len(),
    indexed[0].len() + indexed[1].len(),
    (void *) ordinary.value == (void *) expected,
    (void *) canonical.value == (void *) expected);
  return 0;
}
