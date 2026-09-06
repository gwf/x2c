/*  string-number.x -- numeric parsing from canonical byte strings

    The readers require a complete parse and leave caller output untouched on
    failure. Parsing allocates no storage.
*/

#pragma once

#include "string.x"

#pragma private

#include <ctype.h>
#include <errno.h>
#include <limits.h>
#include <stdlib.h>

static int _only_space(const char *rest) {
  while (isspace((unsigned char) *rest)) rest++;
  return !*rest;
}

/** Parses all of `str` as an integer, writing it through `out`.
    Returns 1 and writes `out` on success; returns 0 and leaves `out`
    untouched on failure.

    The whole string must be the number. Leading and trailing whitespace are
    allowed and any other unconsumed character is a failure, so `42` succeeds
    and `42junk` does not. A `+` or `-` sign is accepted, and the radix
    prefixes `0x`, `0o`, `0b`, and C's leading-zero octal are recognized.
    A value outside the range of `long` fails.

    ```x2c
    ~long value = 0;
    printf("%d %ld\n", %" -0b101 ".try_long(&value), value);
    printf("%d\n", %"42junk".try_long(&value));
    ```
*/
int String.try_long(String str, long *out) {
  if (!str || !out) return 0;
  const char *digits = str;
  while (isspace((unsigned char) *digits)) digits++;
  int negative = 0;
  if (*digits == '+' || *digits == '-') {
    negative = *digits == '-';
    digits++;
  }
  if (digits[0] == '0' &&
      (digits[1] == 'b' || digits[1] == 'B' ||
       digits[1] == 'o' || digits[1] == 'O')) {
    int base = digits[1] == 'b' || digits[1] == 'B' ? 2 : 8;
    const char *number = digits + 2, char *stop = NULL;
    errno = 0;
    unsigned long magnitude = strtoul(number, &stop, base);
    if (stop == number || errno == ERANGE || !_only_space(stop)) return 0;
    unsigned long limit =
      negative ? (unsigned long) LONG_MAX + 1ul : (unsigned long) LONG_MAX;
    if (magnitude > limit) return 0;
    *out = negative ? (magnitude == limit ? LONG_MIN : -(long) magnitude)
                    : (long) magnitude;
    return 1;
  }
  char *stop = NULL;
  errno = 0;
  long value = strtol(str, &stop, 0);
  if (stop == (const char *) str || errno == ERANGE || !_only_space(stop))
    return 0;
  *out = value;
  return 1;
}

/** Parses all of `str` as a floating-point number, writing `out`.
    Returns 1 and writes `out` on success; returns 0 and leaves `out`
    untouched on failure.

    The whole string must be the number, on the same terms as
    `String.try_long`: leading and trailing whitespace are allowed and any
    other unconsumed character is a failure, so `1.5junk` does not parse.

    It accepts what C's `strtod` accepts, including hex-float literals such
    as `0x1p4` and the `inf` and `nan` spellings. A value that overflows or
    underflows `double` fails. It does not know the `0o` and `0b` prefixes
    that the integer parser adds, so `0b101` fails instead of yielding the
    leading zero.
*/
int String.try_double(String str, double *out) {
  if (!str || !out) return 0;
  char *stop = NULL;
  errno = 0;
  double value = strtod(str, &stop);
  if (stop == (const char *) str || errno == ERANGE || !_only_space(stop))
    return 0;
  *out = value;
  return 1;
}
