#include "x2c.x"

/* C lets a for statement omit any of its three clauses.  Each clause is
   parsed by peeking for its terminator and letting one expect consume it,
   so all eight combinations reach the same generated shape.  Omitting the
   init or the increment used to consume the terminator twice and the next
   clause was then parsed at the wrong token. */

static int all_omitted(void) {
  int n = 0;
  for (;;) {
    n++;
    if (n > 3) break;
  }
  return n;
}

static int omitted_init(void) {
  int n = 0;
  for (; n < 3; n++) {}
  return n;
}

static int omitted_condition(void) {
  int n;
  for (n = 0;; n++) {
    if (n > 3) break;
  }
  return n;
}

static int omitted_increment(void) {
  int n;
  for (n = 0; n < 3;) n++;
  return n;
}

static int omitted_init_and_condition(void) {
  int n = 0;
  for (;; n++) {
    if (n > 3) break;
  }
  return n;
}

static int omitted_init_and_increment(void) {
  int n = 0;
  for (; n < 3;) n++;
  return n;
}

static int omitted_condition_and_increment(void) {
  int n = 0;
  for (int i = 0;;) {
    n = i + 5;
    break;
  }
  return n;
}

static int declared_init_no_increment(void) {
  int n = 0;
  for (int i = 0; i < 3;) {
    i++;
    n++;
  }
  return n;
}

int main(void) {
  printf(
    "%d %d %d %d %d %d %d %d\n",
    all_omitted(), omitted_init(), omitted_condition(),
    omitted_increment(), omitted_init_and_condition(),
    omitted_init_and_increment(), omitted_condition_and_increment(),
    declared_init_no_increment()
  );
  return 0;
}
