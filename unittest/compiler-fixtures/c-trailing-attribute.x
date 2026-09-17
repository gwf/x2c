#include <stdio.h>
#include <stdarg.h>

#define FORMAT(a, b) __attribute__((format(printf, a, b)))

int report(const char *format, ...)
    __attribute__((format(printf, 1, 2)));
int report(const char *format, ...) {
  va_list args;
  va_start(args, format);
  int written = vprintf(format, args);
  va_end(args);
  return written;
}

static int note(int level, const char *format, ...) FORMAT(2, 3);
static int note(int level, const char *format, ...) {
  va_list args;
  va_start(args, format);
  printf("%d: ", level);
  int written = vprintf(format, args);
  va_end(args);
  return written;
}

static void release(int *value) { printf("release %d\n", *value); }

static int second(int x __attribute__((unused)), int y) { return y; }

int main(void) {
  report("%s %d\n", "report", 1);
  note(2, "%s\n", "note");
  {
    int a __attribute__((cleanup(release))) = 3, b = 4;
    int (*pick)(int x __attribute__((unused)), int y) = second;
    printf("%d\n", pick(a, b));
  }
  return 0;
}
