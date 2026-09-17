#include <stdio.h>

static int twice(int value) { return value * 2; }

static struct { int (*fn)(int); int arr[4]; } L;
static struct Table { int (*fn)(int); int arr[4]; } T = { twice, {1, 2, 3, 4} };
const struct Named { int count; } named = { 9 };
static struct Named *pointer = (struct Named *) &named;
struct Shared { int level; } shared = { 4 };

int main(void) {
  L.fn = twice;
  L.arr[1] = 6;
  printf("%d %d %d %d %d %d\n", L.fn(L.arr[1]), T.fn(T.arr[1]), named.count,
         pointer->count, shared.level, T.arr[3]);
  return 0;
}
