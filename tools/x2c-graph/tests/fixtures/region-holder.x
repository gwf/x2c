/*  Stores another unit cannot see: one into a static this unit owns, and
    one into the object a parameter names.
*/

#pragma once

static Array _region_kept = NULL;

void region_open(void) { _region_kept = []; }

void region_keep(Var value) { _region_kept.push(value); }

void region_borrow(Array values, Var value) { values.push(value); }
