/*  handles.h -- the diagnostic object behind src/xt-handles.h.

    A counters build of the package (`run.py build --counters`) compiles
    the shim and the generated operator bindings with XT_HANDLE_COUNTERS,
    which makes them call `xt_handle_created` and `xt_handle_destroyed`.
    handles.c supplies those two hooks and the readers below. Nothing in
    the package can read a count: this object is the only reader, and it
    is linked into benchmark binaries only.

    `xb_handles_enabled` reports whether this benchmark was built with the
    define at all, so a run of zeros is never read as "no handles".
*/
#ifndef X2C_TORCH_BENCH_HANDLES_H
#define X2C_TORCH_BENCH_HANDLES_H

#include <stdint.h>

#include "xt-handles.h"

int xb_handles_enabled(void);

/** Totals since the process started, by `XtHandleKind`. */
uint64_t xb_handles_created(int kind);
uint64_t xb_handles_destroyed(int kind);

/** Handles alive now, and the most that were ever alive at once. */
uint64_t xb_handles_live(int kind);
uint64_t xb_handles_peak(int kind);

#endif
