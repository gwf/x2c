/*  membytes.h -- Process memory sampling for the comparison benchmarks.

    macOS reports a process's real charge as its physical footprint, the
    number the memory limits and Activity Monitor's "Memory" column use.
    Resident size and the ledger's high-water mark answer different
    questions, so all four are returned separately. Every value is bytes;
    a call the kernel refuses returns 0 rather than a guess.

    This helper is benchmark-only. x2c links membytes.c as an ordinary C
    input and Python loads the same source built as a dylib through ctypes,
    so both languages read identical counters.
*/
#ifndef X2C_TORCH_MEMBYTES_H
#define X2C_TORCH_MEMBYTES_H

#include <stdint.h>

/** Physical footprint now: the charge macOS attributes to this process. */
uint64_t xb_footprint(void);

/** The ledger's highest physical footprint since the process started. */
uint64_t xb_footprint_peak(void);

/** Resident size now, and the largest resident size the task has held. */
uint64_t xb_resident(void);
uint64_t xb_resident_peak(void);

#endif
