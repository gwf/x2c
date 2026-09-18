/*  meta-sdk.x -- a macro whose implementation is x2c, not Lisp

    `meta-sdk-defs.xmacro` implements each macro below as a `meta` function
    that calls the compiler through `Meta`. The struct's fields, the field-read
    expressions and the captured spelling all come from the compiler, so none
    of these bodies could be written without that surface.

    The generated C is part of what this fixture owns, and it is the evidence
    for the rule M6 adds: a `meta` function that reaches a `Meta` operation
    exists only inside a compiler, so no runtime definition is emitted for it.
    `meta-sdk.c` defines `ms_total` and `ms_label`, which this unit reaches at
    run time, and mentions none of `ms_fields`, `ms_field_reads`, `ms_reads`,
    `ms_total_call`, `ms_names`, `ms_count` or `ms_spelling`.
    See `plans/meta-functions.md`.
*/

#include "x2c.x"
#include "meta.x"

$(import "meta-sdk-defs.xmacro")

typedef struct Point {
  int x, y, z;
} Point;

static int ms_total(int a, int b, int c) => a + b + c;

int main(void) {
  Point p = { 2, 3, 4 };
  int reads[3] = $probe.reads(p);
  printf("names    %s\n", $probe.names(p));
  printf("count    %d\n", $probe.count(p));
  printf("reads    %d %d %d\n", reads[0], reads[1], reads[2]);
  printf("total    %d\n", $probe.total(p));
  printf("spelling %s\n", $probe.spelling(p.y + 1));
  printf("label    %s\n", ms_label("row", 7));
  return 0;
}
