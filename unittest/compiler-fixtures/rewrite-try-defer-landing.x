/* The try that a defer writes when its finalizer needs a landing, such as
   one that returns, matches, or captures a variably sized local, is
   implementation, so a program's try rule never sees it. The statements
   such a finalizer holds are source, so their own rules still see them. */

#include "x2c.x"
#include "rewrite.x"

#include <stdio.h>

static int tries = 0, switches = 0, matches = 0, cleaned = 0;

$rewrite($caught)
$rewrite($tried)
/* Each try is counted, then runs as written. */
meta Code count_try(Code node) {
  return $!{ { tries++; $node } };
}

$rewrite($switched)
/* Each switch is counted, then runs as written. */
meta Code count_switch(Code node) {
  return $!{ { switches++; $node } };
}

$rewrite($matched)
/* Each match is counted, then runs as written. */
meta Code count_match(Code node) {
  return $!{ { matches++; $node } };
}

/* A finalizer that returns replaces the function's result. */
static int returned(int n) {
  {
    defer if (n < 0) return -1;
    cleaned++;
  }
  return n;
}

/* A finalizer that holds a match and a switch. */
static int matched(Var item, int n) {
  int r = 0;
  {
    defer {
      match (item) {
        case %(keep): r += 10;
        default: r += 20;
      }
      switch (n) {
        case 1: r += 100; break;
        default: r += 200;
      }
    }
    r++;
  }
  return r;
}

/* A finalizer that reads a local whose length is a parameter. */
static int sized(int n) {
  int total = 0;
  {
    int values[n];
    for (int i = 0; i < n; i++) values[i] = i + 1;
    defer for (int i = 0; i < n; i++) total += values[i];
  }
  return total;
}

/* The only try in the program holds a defer whose finalizer returns. */
static int guarded(int n) {
  int r = 0;
  try {
    defer if (n < 0) return -1;
    r = n * 2;
  } finally { r++; }
  return r;
}

int main(void) {
  int kept = returned(4), failed = returned(-4);
  int first = matched(%(keep), 1), second = matched(%(other), 2);
  int total = sized(4), tried = guarded(5), refused = guarded(-5);
  printf(
    "%d %d %d %d %d %d %d %d\n", kept, failed, first, second, total,
    tried, refused, cleaned);
  printf("%d %d %d\n", tries, switches, matches);
  return 0;
}
