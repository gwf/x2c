#pragma once

/*
 * Reusable proof steps for a generated left-to-right array fill.
 *
 * Every function takes only `term` arguments, so a code generator can call
 * them by name at the three proof positions a fill loop needs: loop entry,
 * per-iteration open/advance, and loop exit.  The terms are the array
 * predicate applied to its base address, the length parameter's address and
 * value, the ghost contents list, the loop index existential, and the value
 * written into each cell.
 */

#include "array/lib/array.h"
#require "array/lib/array.c"

#include "array/lib/list.h"
#require "array/lib/list.c"

#include "array/lib/index.h"
#require "array/lib/index.c"

/* Entry: n >= 0, and the whole array is the cursor form at index 0. */
PROOF void x2c_fill_entry(
    const term array_at, const term length_addr,
    const term length_var, const term xs, const term value);

/*
 * `elem` selects the element type: it must be `Tint` or `Tchar`.  It is the
 * only parameterization the two element types need, because open/close are
 * separate C proof functions per type while every list-level step below is
 * shared.
 *
 * Per iteration, before the store: the index is in range for the
 * cursor-shaped list currently owned by the symbolic state, and the cell at
 * that index is exposed as a literal `data_at` for a plain C assignment.
 */
PROOF void x2c_fill_before_store(
    const term elem, const term p_pre, const term index_var,
    const term length_var, const term xs, const term value);

/* Per iteration, after the store: re-fold the written cell, advance the
   functional cursor, and re-establish the index bounds for i + 1. */
PROOF void x2c_fill_after_store(
    const term elem, const term p_pre, const term index_var,
    const term length_var, const term xs, const term value);

/* The two halves of the pair above, usable on their own. */
PROOF void x2c_fill_index_bound(
    const term index_var, const term length_var,
    const term xs, const term value);

/* Per iteration, after the store: fold the written cell into the prefix
   and re-establish the invariant's index bounds for i + 1. */
PROOF void x2c_fill_advance(
    const term index_var, const term length_var,
    const term xs, const term value);

/* Exit: at i = n the cursor form collapses to the finished list. */
PROOF void x2c_fill_exit(
    const term index_var, const term length_var,
    const term xs, const term value);
