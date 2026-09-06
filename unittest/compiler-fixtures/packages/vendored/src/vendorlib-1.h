/*  vendorlib-1.h -- stands in for a pinned upstream C header. */
#pragma once

typedef struct Span { double lo, hi; } Span;

typedef enum SpanKind { SPAN_OPEN, SPAN_CLOSED } SpanKind;
