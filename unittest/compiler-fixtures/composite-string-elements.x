#include "x2c.x"

typedef struct Row { String name; int n; } Row;

static Row designated = { .name = "two" };
static Row positional = { "three", 1 };
static String words[2] = { "four", "five" };
static Row rows[2] = { { .name = "six" }, { "seven", 2 } };

List public_list = %("alpha");

static int width(String s) { return (int) s.len(); }

int main(void) {
  Row local = { .name = "eight" };
  int total = width(designated.name) + width(positional.name)
            + width(words[0]) + width(words[1])
            + width(rows[0].name) + width(rows[1].name)
            + width(local.name) + (int) public_list.len();
  printf("%d\n", total);
  return total == 30 ? 0 : 1;
}
