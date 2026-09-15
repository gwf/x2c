#!/usr/bin/env -S x2c script
/* Top-level statements run in order as the program. Definitions between
   them stay at file scope, and declarations among them are locals. */

typedef struct Span { int first, last; } Span;

static int width(Span span) => span.last - span.first + 1;

Span span = { 3, 7 };
int total = width(span);

int doubled(int value);

static int calls = 0;

foreach (int value, %[1, 2, 3]) total += doubled(value);
printf("total=%d args=%d\n", total, args.len());

int doubled(int value) {
  calls++;
  return value * 2;
}

if (calls != 3) return 1;
printf("calls=%d\n", calls);
