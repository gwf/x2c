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

int main(void) {
  report("%s %d\n", "report", 1);
  note(2, "%s\n", "note");
  return 0;
}
