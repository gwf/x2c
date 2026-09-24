/* references.x -- pointer parameters that alias one caller variable. */
#include <stdio.h>

typedef struct Pair { int left, right; } Pair;

static Pair *kept;

/* Candidates: every caller passes `&` of its own variable, and the body
   only reads and writes through the parameter. */
static void bump(int *count, Pair *pair) {
  *count += 1;
  pair.left = *count;
}

/* Nullable: the body tests the pointer. */
static void maybe(int *count) {
  if (count) *count = 1;
}

/* Optional output: a caller passes NULL. */
static void optional(int *count) {
  *count = 2;
}

/* Retained address: the pointer is stored. */
static void keep(Pair *pair) {
  kept = pair;
}

/* Indexed storage: the pointer addresses several values. */
static void fill(int *values) {
  values[1] = 3;
}

/* Buffer: a `char` pointee is text. */
static void clear(char *text) {
  *text = 0;
}

/* Native callback: the function is used as a value. */
static void visit(int *count) {
  *count = 4;
}

/* Published signature and C API contract: other units may call it. */
void publish(int *count) {
  *count = 5;
}

int run(void) {
  int total = 0, values[2] = {0, 0};
  Pair pair = {0, 0};
  char text[2] = "x";
  void (*callback)(int *) = visit;
  bump(&total, &pair);
  maybe(&total);
  optional(&total);
  optional(NULL);
  keep(&pair);
  fill(values);
  clear(text);
  callback(&total);
  visit(&total);
  publish(&total);
  return total + pair.left + values[1] + text[0];
}
