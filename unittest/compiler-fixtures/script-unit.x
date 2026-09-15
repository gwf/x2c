#!/usr/bin/env -S x2c script
/* Top-level statements run in order as the program. Definitions between
   them stay at file scope, and declarations among them are locals. Script
   functions may be called before their definitions and call each other. */

typedef struct Span { int first, last; } Span;

static int width(Span span) => span.last - span.first + 1;

Span span = { 3, 7 };
int total = width(span);

int doubled(int value);

static int calls = 0;

foreach (int value, %[1, 2, 3]) total += doubled(value);
printf("total=%d args=%d\n", total, args.len());
printf("fib=%d even=%d\n", fib(10), is_even(7));

int doubled(int value) {
  calls++;
  return value * 2;
}

static int fib(int n) => n < 2 ? n : fib(n - 1) + fib(n - 2);

static int is_odd(int n);
static int is_even(int n) => n == 0 ? 1 : is_odd(n - 1);
static int is_odd(int n) => n == 0 ? 0 : is_even(n - 1);

if (calls != 3) return 1;
printf("calls=%d\n", calls);
