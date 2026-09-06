/*  string-classify.x -- byte classification for canonical strings

    Predicates classify unsigned bytes with C's current locale. The canonical
    empty `String` is NULL and every predicate reports false for it. No
    predicate allocates or mutates its input.
*/

#pragma once

#include "string.x"

#pragma private

#include <ctype.h>

/** Reports whether `str` contains a decimal digit.
    A null or empty `String` returns false.
*/
int String.contains_digit(String str) {
  if (!str || !*str) return 0;
  for (unsigned char *p = (unsigned char *) str; *p; p++)
    if (isdigit(*p)) return 1;
  return 0;
}

/*  Walks the bytes of `$value` as `$byte` and rejects the String as soon as
    `$reject` holds. Naming the cursor lets each predicate write its own test
    against the C classifiers.
*/
macro Statement $string.classify(Expr $value, Name $byte, Expr $reject) => {
  if (!$value) return 0;
  for (unsigned char *$byte = (unsigned char *) $value; *$byte; $byte++)
    if ($reject) return 0;
  return 1;
}

/** Reports whether every byte of nonempty `s` is alphabetic. */
int String.is_alpha(String s) {
  $string.classify(s, p, !isalpha(*p));
}

/** Reports whether every byte of nonempty `s` is alphabetic or underscore. */
int String.is_alpha_under(String s) {
  $string.classify(s, p, !isalpha(*p) && *p != '_');
}

/** Reports whether every byte of nonempty `s` is a decimal digit. */
int String.is_digit(String s) {
  $string.classify(s, p, !isdigit(*p));
}

/** Reports whether every byte of nonempty `s` is alphanumeric. */
int String.is_alnum(String s) {
  $string.classify(s, p, !isalnum(*p));
}

/** Reports whether nonempty `s` is alphanumeric or underscore. */
int String.is_alnum_under(String s) {
  $string.classify(s, p, !isalnum(*p) && *p != '_');
}

/** Reports whether `s` is a C identifier under C character classes.
    The first byte must be alphabetic or underscore; later bytes may also be
    decimal digits. A null or empty `String` returns false.
*/
int String.is_identifier(String s) {
  if (!s || !*s) return 0;
  unsigned char *bytes = (unsigned char *) s;
  if (!isalpha(*bytes) && *bytes != '_') return 0;
  for (unsigned char *p = bytes + 1; *p; p++)
    if (!isalnum(*p) && *p != '_') return 0;
  return 1;
}

/** Reports whether every byte of nonempty `s` is whitespace. */
int String.is_space(String s) {
  $string.classify(s, p, !isspace(*p));
}

/** Reports whether every byte of nonempty `s` is lower-case. */
int String.is_lower(String s) {
  $string.classify(s, p, !islower(*p));
}

/** Reports whether every byte of nonempty `s` is lower-case or underscore. */
int String.is_lower_under(String s) {
  $string.classify(s, p, !islower(*p) && *p != '_');
}

/** Reports whether every byte of nonempty `s` is upper-case. */
int String.is_upper(String s) {
  $string.classify(s, p, !isupper(*p));
}

/** Reports whether every byte of nonempty `s` is upper-case or underscore. */
int String.is_upper_under(String s) {
  $string.classify(s, p, !isupper(*p) && *p != '_');
}
