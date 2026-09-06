/*  vendored.x -- a package with a public method over a vendored C type.

    The package renames what it declares, not what it includes: Span and
    SpanKind keep the spelling vendorlib-1.h gives them, so this header
    still compiles for a consumer who has that header and nothing else.
*/
#pragma once
#include "vendorlib-1.h"

typedef struct Reading *Reading;

protocol SpanSum(T) {
  T T.add(T, T);
}

double Span.width(Span span);
SpanKind Span.kind(Span span);
Span Span.add(Span a, Span b);
Reading Reading.new(Span span);
Span Reading.span(Reading reading);

protocol SpanSum(Span);

#pragma private

struct Reading { Span span; };

double Span.width(Span span) { return span.hi - span.lo; }

SpanKind Span.kind(Span span) {
  return span.lo == span.hi ? SPAN_CLOSED : SPAN_OPEN;
}

Span Span.add(Span a, Span b) {
  return (Span) { a.lo + b.lo, a.hi + b.hi };
}

Reading Reading.new(Span span) {
  Reading reading = Scope.malloc(sizeof(struct Reading));
  reading.span = span;
  return reading;
}

Span Reading.span(Reading reading) { return reading.span; }
