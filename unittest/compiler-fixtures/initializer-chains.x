#include "x2c.x"

typedef struct Mixed { String a[2]; Var b; } Mixed;
typedef struct Anonymous {
  struct { String first; String second; };
  String third;
} Anonymous;

static String grid[2][2] = {[0][1] = "one", "two", "three"};
static Mixed global = {.a[1] = "four", "five"};
static Mixed records[2] = {[1].a[1] = "six", "seven"};

int main(void) {
  Mixed local = {.a = "one", "two", "three"};
  Anonymous anonymous = {.first = "a", "bb", "ccc"};
  char raw[] = {"raw" " bytes"};
  String scalar = {"scalar"};
  String first = anonymous.first, second = anonymous.second;
  String global_b = global.b, record_b = records[1].b, local_b = local.b;
  printf("%d %d %d %d %d %d\n",
    grid[0][1].len() + grid[1][0].len() + grid[1][1].len(),
    global.a[1].len() + global_b.len(),
    records[1].a[1].len() + record_b.len(),
    local.a[0].len() + local.a[1].len() + local_b.len(),
    first.len() + second.len() + anonymous.third.len(),
    (int) sizeof(raw) + scalar.len());
  return 0;
}
