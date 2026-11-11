/*  panels.x -- toy package whose type has method-form macros.

    `Panel` is `panels__Panel` in generated code, while its macros keep the
    source spelling `$Panel.NAME`.
*/
#pragma once
#include "x2c.x"

typedef struct Panel { int depth; } Panel;

int Panel.label(Panel panel, int n);

macro Expression $Panel.label(Expr $panel, Expr $n) =>
  $panel.label($n) * 10;

macro Decorator $Panel.section(Stmt $body, Expr $panel) {
  {
    printf("section %d\n", ($panel).depth);
    $body
  }
}


#include <stdio.h>

int Panel.label(Panel panel, int n) => panel.depth + n;

int Panel.labels(Panel panel) {
  panel.section() { return panel.label(1); }
}
