#pragma indent
// Indentation syntax selected by pragma: blocks, conditions, aggregates.

typedef enum Color:
  RED,
  GREEN,
  BLUE
Color

struct Point:
  int x, y

/* Sums the positive entries. */
int sum_positive(int *xs, int n):
  int total = 0
  for int i = 0; i < n; i++:
    if xs[i] > 0:
      total += xs[i]
    else if xs[i] == -99:
      break
    else:
      continue
  return total

static int square(int x) => x * x

const char *name(Color c):
  switch c:
    case RED:
      return "red"
    case GREEN:
      return "green"
    default:
      return "blue"

int main(void):
  int xs[] = {3, -1, 4,
              -1, 5}
  struct Point p = {.x = 2, .y = square(3)}
  int i = 0
  do:
    i++
  while (i < 3)
  Map m = {"a": 1, "b": 2}
  printf("%d %d %d %s %d\n", sum_positive(xs, 5), p.y, i, name(GREEN),
         (int) m["b"])
  return 0
