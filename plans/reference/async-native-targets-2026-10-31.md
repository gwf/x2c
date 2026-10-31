# Async stack configuration and native target validation

> Status: reference - focused tests and local macOS execution evidence.
> Recorded 2026-10-31. No runtime behavior changed in this follow-up.
> Normal benchmark reruns remain on hold. No pushes are authorized.

## Focused coverage

`unittest/test-task.x` tests the unset default and configured usable sizes of
32 KiB, 64 KiB, 65,537 bytes, and 1 MiB. Each batch parks and resumes through
an unbuffered Channel and returns both results. Invalid settings cover empty,
zero, below-minimum, negative, trailing text, capacity overflow, and numeric
parse overflow. The exact stack-capacity Error is checked before any job runs.
A valid batch then proves recovery. The test restores the original environment.
The Task suite now has 18 tests and 132 assertions.

The optional `unittest/probes/run-task-backend.sh` checks the production C
backend directly. Requested capacities include 32 KiB, 64 KiB, 65,537 bytes,
1 MiB, and 8 MiB. It checks page rounding, usable bounds, suspension/resumption,
completion, an inaccessible lower guard page, and unmapping of every page.
Invalid native capacities return EINVAL. Deliberate child-process guard faults
must terminate with SIGSEGV or SIGBUS; core dumps are disabled for this probe.
The probe includes the backend source to inspect private layout without adding
a runtime test API.

The same script compiles the production unsupported branch with the existing
`__EMSCRIPTEN__` exclusion selected only for that C translation unit. It links
that object ahead of the runtime archive. The x2c probe checks the exact
unavailable-backend Error for populated and empty Task.run batches, confirms
that no job runs, and exercises ordinary synchronous Array operations. This
is fallback execution evidence on macOS, not a WebAssembly build or run.
The probes are explicitly optional; no recurring gate was added.

## Local results

Host: Apple M4 Max, macOS 15.7.9. Toolchain: Apple clang 17.0.0
(clang-1700.6.3.2), macOS SDK 26.2. arm64 uses the working checkout's
optimized build. x86_64 uses an isolated archive of source checkpoint
`ab932e1ef` plus these tests and a compiler wrapper that invokes
`/usr/bin/clang -arch x86_64`. Its executables are verified x86_64 Mach-O files
and run through Rosetta on the arm64 host. Native pages are 16 KiB for arm64
and 4 KiB for the x86_64 process.

| Check | macOS arm64 | macOS x86_64 through Rosetta |
| --- | --- | --- |
| Task suite | 18 tests, 132 assertions pass | 18 tests, 132 assertions pass |
| Native layout, guard, release, fallback probes | Pass | Pass |
| Full normal unit suite, accounting enabled | 1,155 tests, 99,570 assertions pass | 1,155 tests, 99,570 assertions pass |
| Full ASan/UBSan unit suite | 1,155 tests, 99,570 assertions pass | 1,155 tests, 99,570 assertions pass |
| Task suite with ASan use-after-return enabled | 18 tests, 132 assertions pass | 18 tests, 132 assertions pass |
| Fresh shipped-bootstrap build | Covered by the local gate | Pass in isolated tree |
| Strict stage-two build | Earlier local evidence; production unchanged here | Pass |
| Generated-stage comparison | Covered by the local gate | Stages 0/1 and 1/2 match, 333 C/H files each |

The final local `make agent-pr-check` passes, including bootstrap recovery,
self-host comparisons, 1,357 compiler fixtures (2,999 artifacts), documentation,
and complete command checks. It produces no generated artifact changes.
The full log is `debug/async-stack-targets-agent-pr-check.log`.

Full normal suites run from `unittest/`, as the existing harness requires.
An initial arm64 invocation from the repository root failed to locate
`../etc/init.xlisp`; the corrected invocation passes. No source change was
needed for that invocation error.

Evidence logs are under `debug/async-stack-*` and
`debug/async-macos-x86_64-*`. The retained isolated tree is recorded in
`.context/async-native-validation-dir`; it uses a separate X2C_CACHE_DIR.

## Remaining target coverage

Linux arm64 and Linux x86_64 were not built or executed. The configured Docker
endpoint is a local Unix socket, but the daemon socket is absent. No installed
Linux cross compiler, QEMU user runner, Zig, Podman, or Lima command was found.
No toolchain was installed and no VM or daemon was started.

Rosetta provides execution and sanitizer evidence for the macOS x86_64 ABI.
It does not establish physical Intel hardware behavior, Linux behavior, or
performance equivalence. This follow-up contains no benchmark measurements.
The dev/main validation hold and explicit consent requirement remain in force.
