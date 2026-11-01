Native switching uses minicoro revision
02dad0f8b7cbb12fe6e216ae7a76db15ca55cd7b.

The native backend also owns batch job-array storage. Arrays larger than one
native page use a zeroed anonymous mapping, released after every job finishes
cleanup. Smaller arrays retain calloc/free. Both paths use the same byte count
at allocation and release. This avoids malloc's medium-region retention for
large batch arrays without changing per-task allocation owners.

Upstream: https://github.com/edubart/minicoro
Original minicoro.h SHA-256:
c4205e8db0a95456dfde9f73f071609c6d2cad2ebfd1d74ed0a9254f121caa2f

Local adaptation: mco_desc accepts an external stack_base. The native
assembly context constructor uses it instead of placing the stack directly
after coroutine metadata. stack.c allocates the metadata separately and
places an inaccessible page immediately below the usable stack mapping.
Upstream license notices remain in minicoro.h.

Symbol visibility: minicoro's C API has translation-unit-local linkage.
Assembly entry symbols use the x2c_task prefix to avoid collisions with an
application's separate minicoro dependency.

ASan adaptation: MCO_EXTERNAL_ASAN lets stack.c pair start/finish fiber
annotations on opposite sides of each actual stack switch, including native
caller restoration and final task exit. Upstream's annotations left ASan
using task-stack bounds on native Error transfers in the instrumented tests.

The yield-time overflow check uses GCC/Clang's physical frame address rather
than a local variable's address. GCC ASan use-after-return can move that local
to its fake stack, outside the coroutine mapping. Bounds and metadata checks
remain active. `unittest/probes/run-task-backend.sh` includes the focused
sanitizer regression alongside the native layout and fallback probes.
