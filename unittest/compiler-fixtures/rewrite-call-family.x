#include "x2c.x"
#include "rewrite.x"

/* A project's own printf-family function, which the shipped component does
   not know. Its rule displays each Var value through `Var.str` whatever
   conversion reads it, so a `%s` formats any value. */
static int log_printf(const char *format, ...) {
  va_list values;
  va_start(values, format);
  fputs("log: ", stdout);
  int written = vprintf(format, values);
  va_end(values);
  return written;
}

macro Expression $logged(Expr $format, Expr @values) =>
  log_printf($format, @values);

$rewrite($logged)
meta Code log_values(Code code) {
  match (code) case $logged(?format, *values): {
    Array shown = [];
    foreach (Code value, values)
      shown.push(value.type().is_named("Var") ? $!String{ Var.str($value) }
                                              : value);
    List items = shown.list_free();
    return $!int{ log_printf($format, @items) };
  }
  return code;
}

int main(void) {
  Var count = 3, name = "entries";
  log_printf("%s=%s (%d)\n", name, count, 7);
  log_printf("%s=%s (%d)\n", name, count, 8);
  printf("%d %s\n", count, name);
  return 0;
}
