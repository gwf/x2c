/* A return, break, or continue that leaves a finalizer leaves its frame
   too, so a later raise still lands on its own try. After a raise, the
   transfer discards the pending error as a handler that returns does. */

#include "x2c.x"

#include <stdio.h>

static int caught(int n) {
  int r = 0;
  try {
    if (n > 5) raise %(big);
    r = n;
  }
  catch %(big): r = 99;
  return r;
}

/* A defer finalizer that returns. */
static int deferred(int n) {
  {
    defer if (n < 0) return -1;
  }
  return n;
}

/* A finally that returns on the normal path and after a raise; the
   return discards the error, so the handler around it never runs. */
static int finished(int n) {
  try {
    if (n > 5) raise %(big);
    n++;
  }
  finally {
    if (n < 0 || n > 5) return -1;
  }
  return n;
}

static int handled(int n) {
  try {
    return finished(n);
  }
  catch %(big): return 77;
}

/* A finally that leaves the loop around its try. */
static int looped(void) {
  int count = 0;
  for (int i = 0; i < 4; i++) {
    try {
      count++;
    }
    finally {
      if (i == 1) break;
    }
  }
  return count;
}

int main(void) {
  printf("deferred %d %d\n", deferred(4), deferred(-4));
  printf("caught %d\n", caught(9));
  printf("finished %d %d %d\n", handled(4), handled(-4), handled(9));
  printf("caught %d\n", caught(9));
  printf("looped %d\n", looped());
  printf("caught %d\n", caught(9));
  return 0;
}
