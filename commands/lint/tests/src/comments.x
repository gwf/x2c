/* comments.x -- comment rules. Build, parse, check, read, and write
   nothing. */
#include <stdio.h>

// TODO: remove this after the release.
static int _count;

// ==== SETUP ====
static int _limit;

// Private helpers
static int _unused;

// Parse the value.
static int _parse_value(int value) => value;

// Parse the value because the caller owns the cursor.
static int _parse_other(int value) => value;

int reader(int *value) {
  // check for null
  if (!value) return 0;
  // value count total
  int total = *value + _count;
  return total;
}

/** Returns the value.

    Parameters: value
*/
int documented(int value) => value;

/** A detached comment. */

int detached(int value) => value;

/** The first stacked comment. */
/** The second stacked comment. */
int stacked(int value) => value;

/** Helper documentation that belongs in an ordinary comment. */
static int _helper(int value) => value;

/* The cursor must stay on the opening token of the current form. */
int first(int value) => value;

/* The cursor must stay on the opening token of the current form. */
int second(int value) => value;
