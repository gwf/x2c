/*  xt-handles.h -- benchmark-only native handle counters.

    Nothing here reaches an ordinary build. Without XT_HANDLE_COUNTERS both
    macros expand to nothing, no symbol is referenced, and the compiled
    package is byte for byte what it was. A diagnostic build defines the
    macro and links one separate object supplying `xt_handle_created` and
    `xt_handle_destroyed`; `packages/torch/benchmarks/handles.c` is the
    only such object in this tree.

    There is no inspection API here on purpose: the package counts, and
    the diagnostic object that supplied the two hooks is the only thing
    that can read a count back.
*/
#ifndef X2C_XT_HANDLES_H
#define X2C_XT_HANDLES_H

enum XtHandleKind {
  XT_HANDLE_TENSOR = 0,
  XT_HANDLE_MODULE = 1,
  XT_HANDLE_OPTIM = 2,
  XT_HANDLE_SCHEDULER = 3,
  XT_HANDLE_PICKLE = 4,
  XT_HANDLE_JIT = 5,
  XT_HANDLE_ARRAY = 6,
  XT_HANDLE_KINDS = 7
};

#ifdef XT_HANDLE_COUNTERS

#ifdef __cplusplus
extern "C" {
#endif
void xt_handle_created(int kind);
void xt_handle_destroyed(int kind);
#ifdef __cplusplus
}
#endif

#define XT_HANDLE_NEW(kind) xt_handle_created(kind)
#define XT_HANDLE_DROP(kind) xt_handle_destroyed(kind)

#else

#define XT_HANDLE_NEW(kind) ((void) 0)
#define XT_HANDLE_DROP(kind) ((void) 0)

#endif
#endif
