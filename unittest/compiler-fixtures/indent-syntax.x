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

// A trailing `?:` colon continues; the last keyword owns the condition;
// a `catch` label keeps its colon.
int count_positive(int *xs, int n, int strict):
  int threshold = strict ? 1 :
    0
  int total = 0
  for (int i = 0; i < n; i++)
    if xs[i] >= threshold:
      total++
  try:
    if total > 2: raise %(bad-arg (operation "count"))
  catch %(bad-arg *):
    total = -total
  return total

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
  printf("%d %d\n", count_positive(xs, 5, 1), count_positive(xs, 2, 0))
  return 0
