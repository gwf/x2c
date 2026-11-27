#include <stdio.h>

// Deferred file-scope pointer arrays whose bound is a C constant expression.
enum { FIRST, SECOND, COUNT };

static int target = 5;
static char *names[COUNT] = {"first", "second"};
static const char *labels[COUNT + 1] = {"a", "b"};
static int *pointers[COUNT] = {0, &target};
static char *designated[COUNT] = {[SECOND] = "second"};

int main(void) {
  printf("%s %s\n", names[FIRST], names[SECOND]);
  printf("%s %s %d\n", labels[0], labels[1], labels[COUNT] == 0);
  printf("%d %d\n", pointers[0] == 0, *pointers[1]);
  printf("%d %s\n", designated[FIRST] == 0, designated[SECOND]);
  return 0;
}
