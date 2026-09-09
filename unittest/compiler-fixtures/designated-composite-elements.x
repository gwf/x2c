#include "x2c.x"

typedef String Words[4];
typedef Var Numbers[3];
typedef struct Row { String first; String second; } Row;
typedef union Choice { String text; int number; } Choice;
typedef struct Bits {
  int :2;
  String first;
  int :3;
  String second;
} Bits;
typedef struct Nested {
  struct { int value; };
  String first;
  String second;
} Nested;

static Words global = {[1] = "one", "two",};
static Numbers boxed = {[1] = "boxed"};
static Choice choices[2] = {[1] = {.text = "choice"}};
static Row rows[2] = {[1] = {.first = "three", "four"}};
static String sparse[] = {[4] = "sparse", "last"};
static String grid[2][2] = {[1] = {[1] = "grid"}};
static int ignored_calls;
static String ignored_value(void) { ignored_calls++; return "ignored"; }
static String excess[1] = {"kept", ignored_value()};

int main(void) {
  Words words = {[2] = "five", "six"};
  Numbers numbers = {[1] = 7, 8};
  String nested[2][2] = {[1] = {[0] = "nine", "ten"}};
  Row row = {.first = "eleven", "twelve"};
  Bits bits = {.first = "a", "bb"};
  Nested anonymous = {{4}, "ccc", "dddd"};
  int number = numbers[2];
  String boxed_text = boxed[1];
  printf("%d %d %d %d %d %d %d %d %d %d %d %d %d %d\n",
         global[1].len() + global[2].len(),
         rows[1].first.len() + rows[1].second.len(),
         words[2].len() + words[3].len(), number,
         nested[1][0].len() + nested[1][1].len(),
         row.first.len() + row.second.len(),
         bits.first.len() + bits.second.len(),
         anonymous.first.len() + anonymous.second.len(),
         (int) (sizeof(sparse) / sizeof(sparse[0])),
         sparse[4].len() + sparse[5].len(), grid[1][1].len(),
         excess[0].len() + ignored_calls,
         choices[1].text.len(), boxed_text.len());
  return 0;
}
