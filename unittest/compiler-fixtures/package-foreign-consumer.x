/*  package-foreign-consumer.x -- reaching a package's methods on its own
    header's types.

    Span and SpanKind belong to the package's vendored C header, so the
    consumer spells them the way the header does and needs no `with` entry
    for them. The methods belong to the package, so `Span.width`, `.kind()`,
    and the SpanSum operator all fold to `vendored__*`.
*/
#pragma once

import "vendored" with Reading;

double span_total(double lo, double hi);

#pragma private

double span_total(double lo, double hi) {
  Span first = { lo, hi };
  Span second = { hi, lo + hi };
  Span sum = first + second;
  Reading reading = Reading.new(sum);
  return Span.width(reading.span()) + (double) sum.kind();
}
