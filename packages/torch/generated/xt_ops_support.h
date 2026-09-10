/*  xt_ops_support.h -- the two entry points the generated operator bindings
    share with the hand-written shim.

    This file is hand-written and stable; xt_ops.h and xt_ops.cpp beside it
    are outputs of tools/gen-ops.py.

    `xt_note_error` stores a libtorch message in the thread-local error that
    `xt_last_error` reports, so a generated body reports a failure exactly as
    src/torch-shim.cpp does. `xt_free_handles` releases the handle array a
    tensor-list binding returns; the handles themselves stay owned by the
    caller and are freed with `xt_tensor_free`.
*/
#ifndef X2C_XT_OPS_SUPPORT_H
#define X2C_XT_OPS_SUPPORT_H

#include "torch-2.10.h"

#ifdef __cplusplus
extern "C" {
#endif

void xt_note_error(const char *what);
void xt_free_handles(xt_tensor *handles);

#ifdef __cplusplus
}
#endif
#endif
