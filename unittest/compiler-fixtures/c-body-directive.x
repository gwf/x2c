#include <stdio.h>
#include <stdlib.h>

static int pick(int dim) {
  int buf[4], *ptr;
  if (dim > 2) {
#ifndef NO_ALLOCA
    if (dim <= 3) ptr = buf;
    else
#endif
    if (!(ptr = malloc(dim * sizeof *ptr))) {
      return -1;
    }
  }
  else {
    ptr = buf;
  }
  ptr[0] = dim;
  int first = ptr[0];
  if (ptr != buf) free(ptr);
  return first;
}

static int width(int back) {
  int w;
  {
#ifdef WIDE
    if (back > 0)
      w = 2;
    else
#else
    (void) back;
#endif
      w = 1;
  }
  return w;
}

static int count(int limit) {
  int total = 0;
  for (int i = 0; i < limit; i++)
#ifdef SKIP_EVEN
    if (i % 2 == 0) continue; else
#endif
    total += i;
  while (total > 100)
#if 1
    total -= 100;
#else
    total = 0;
#endif
  do
#ifndef ONCE
    total++;
#endif
  while (total < 5);
  return total;
}

static int chain(int a, int b) {
  if (a) {
    return 1;
  }
#ifdef CHAIN
  else if (b) {
    return 2;
  }
#endif
  else {
    return 3;
  }
}

static int branch(int a) {
  switch (a)
#ifndef NO_SWITCH
  {
    case 2: return 20;
  }
#endif
  return a;
}

static int sum(List items) {
  int total = 0;
  foreach (Var item, items)
#ifndef NO_SUM
    total += item.int();
#endif
  return total;
}

static int governed(List items) {
  int total = 0;
  {
    defer
#ifdef TWICE
      total *= 2;
#else
      total += 1;
#endif
  }
  try
#ifdef FAIL
    raise %(boom);
#else
    total += 10;
#endif
  finally
#ifndef QUIET
    total += 100;
#endif
  try raise %(boom);
  catch %(boom):
#ifdef QUIET
    total = 0;
#else
    total += 1000;
#endif
  match (items) {
    case %(1 2):
#ifdef QUIET
      total = 0;
#else
      total += 10000;
#endif
    default: total = -1;
  }
  return total;
}

int main(void) {
  printf("%d %d %d %d\n", pick(2), pick(4), width(3), count(5));
  printf("%d %d %d\n", chain(0, 1), branch(2), sum(%(1 2)));
  printf("%d\n", governed(%(1 2)));
  return 0;
}
