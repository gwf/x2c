#include "x2c.x"

static int *saved;
static int attempts;
static int initial(int *address) {
  attempts++;
  if (attempts == 1) {
    saved = address;
    raise %(bad-state);
  }
  return address == saved ? 41 : 99;
}
static int *value(void) {
  static int result = initial(&result);
  return &result;
}
int main(void) {
  int caught = 0;
  try { value(); }
  catch %(bad-state *): { caught = 1; }
  void *intervening = malloc(sizeof(int));
  int *result = value();
  printf("%d %d %d %d\n", caught, result == saved, *result, attempts);
  free(intervening);
  return 0;
}
