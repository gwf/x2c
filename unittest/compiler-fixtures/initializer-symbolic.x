#include "x2c.x"
#define WIDTH (sizeof(int) / sizeof(int) + 1)

typedef struct Texts { String values[WIDTH]; Var last; } Texts;
typedef struct Numbers { Var values[WIDTH]; String last; } Numbers;
typedef char *A;
typedef char *B;
typedef struct Aliases { A values[WIDTH]; B last; } Aliases;
typedef struct Chars { char text[WIDTH]; Var last; } Chars;

static Texts rows[1] = {[0].values[WIDTH - 1] = "array", "end"};

int main(void) {
  Texts text = {.values[WIDTH - 1] = "first", "last"};
  Numbers numbers = {.values[WIDTH - 2] = 1, 7, "tail"};
  B source = 0;
  Aliases alias = {.values[WIDTH - 1] = (A) 0, source};
  String last = text.last, row_last = rows[0].last;
  int number = numbers.values[WIDTH - 1];
  printf("%d %d %d %d\n", text.values[WIDTH - 1].len() + last.len(),
    number + numbers.last.len(),
    rows[0].values[WIDTH - 1].len() + row_last.len(), alias.last == source);
  Chars flat = {'a', 'b', 7};
  Chars braced = {{'c', 'd'}, 8};
  Chars string = {"e", 9};
  printf("%c%c %d %c%c %d %c %d\n", flat.text[0], flat.text[1],
    flat.last.int(), braced.text[0], braced.text[1], braced.last.int(),
    string.text[0], string.last.int());
  return 0;
}
