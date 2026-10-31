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
The initial log is `debug/async-stack-targets-agent-pr-check.log`. The gate
also passes after the sanitizer-harness repairs described below; that log is
`debug/async-stack-targets-agent-pr-check-final.log`.

Full normal suites run from `unittest/`, as the existing harness requires.
An initial arm64 invocation from the repository root failed to locate
`../etc/init.xlisp`; the corrected invocation passes. No source change was
needed for that invocation error.

Evidence logs are under `debug/async-stack-*` and
`debug/async-macos-x86_64-*`. The retained isolated tree is recorded in
`.context/async-native-validation-dir`; it uses a separate X2C_CACHE_DIR.

## Linux follow-up

Docker subsequently became available. Both Linux targets use existing local
Debian images, with networking disabled and `--pull=never`. No image or
package was downloaded. Linux arm64 runs in Docker's Linux VM on the arm64
host; Linux x86_64 uses Docker's emulation. Both report a 4 KiB page size and
Linux kernel 7.0.12-linuxkit. The compiler is GCC 12.2.0
(Debian 12.2.0-14+deb12u1). The images are
`x2c-gcc12-python-probe:latest` (arm64) and
`x2c-debian-amd64-test:latest` (amd64).

Linux trees start from `74bdfecaa`, plus the sanitizer-harness repair. The
runtime implementation is the same as the macOS-tested source. Trees and
logs remain under the directory recorded in
`.context/async-linux-validation-dir`. Each container uses its own
X2C_CACHE_DIR and has four CPUs and a 6 GiB memory limit. These are correctness
checks, not performance measurements.

| Check | Linux arm64 | Linux x86_64 under emulation |
| --- | --- | --- |
| Fresh shipped-bootstrap build | Pass | Pass with BUILD_JOBS=1 |
| Task suite | 18 tests, 129 assertions pass | 18 tests, 129 assertions pass |
| Native layout, guard, release, fallback probes | Pass | Pass |
| Full normal unit suite | 1,155 pass, 99,567 assertions | 1,152 pass, 3 fail; 99,567 assertions |
| Full ASan/UBSan unit suite | 1,155 pass, 99,567 assertions | 1,153 pass, 2 fail; 99,567 assertions |
| Task suite under ordinary ASan/UBSan | 18 tests, 129 assertions pass | 18 tests, 129 assertions pass |
| Task suite with GCC ASan use-after-return enabled | Aborts: false overflow | Aborts: false overflow |
| Strict stage-two build and generated-stage comparisons | Pass; stages 0/1 and 1/2 match, 333 C/H files each | Pass; stages 0/1 and 1/2 match, 333 C/H files each |

Linux has three fewer assertions than macOS because the malloc-zone checks
in the existing job-array test are Darwin-only.

The initial parallel Linux x86_64 bootstrap build stopped with GNU Make 4.3's
`write jobserver: Bad file descriptor`. The serial retry succeeds. The cause
of that parallel-build failure remains unclassified; no Make behavior changed.

### Sanitizer harness repair

The first Linux arm64 sanitizer build failed the runtime's signed-char static
assertion. The harness now passes the existing required `-fsigned-char` flag.
The retry then exposed archive ordering: the compiler objects came after the
runtime archive, leaving `declarator_append_modifiers` unresolved with GNU ld.
The harness now links those objects before the archive, as the normal unit
build does. It adds no new test or recurring requirement.

After both repairs, full sanitizer builds and execution complete on all four
targets. Both macOS targets and Linux arm64 pass the full suite. Linux x86_64
retains the numeric failures below. No sanitizer memory diagnostic appears
in those failing assertions.

### Confirmed GCC use-after-return finding

The optional command
`ASAN_OPTIONS=detect_leaks=0:detect_stack_use_after_return=1 unittest/build/sanitizer/test-all task_suite`
aborts on both Linux targets. `mco_yield` compares the address of its local
`dummy` with the coroutine mapping. GCC ASan moves that local to its fake
stack, outside the mapping, and minicoro reports stack overflow.

An isolated native probe reproduces the failure with an 8 MiB stack and one
yield. Temporary instrumentation of a copied header shows that the physical
frame remains inside the mapped stack and `magic_number` is intact. The local
address alone lies outside the mapping. With use-after-return disabled, the
same probe completes. The copied diagnostic sources and both logs are retained
with the Linux evidence. No authoritative runtime source was instrumented or changed.

This is a confirmed false overflow check, not evidence that an 8 MiB stack was
exhausted. A focused follow-up should make the check inspect the physical
stack rather than an address ASan can relocate. No fix or waiver is selected
by this validation task.

### Linux x86_64 numeric failures

The full normal suite fails three tests:

- `string_checked_format_floating`: the NaN/infinity formatting comparison.
- `var_wide_value_semantics`: identical separately boxed long doubles differ
  in identity, hash, and ordering.
- `var_all_family_comparison_matrix`: same-family numeric identity.

The full sanitizer suite fails the first two tests. The third passes in that
instrumented build. Running only `string_suite`, `var_suite`, and
`varops_suite`, with no Task tests, reproduces the three normal failures:
95 tests pass and three fail, with 9,572 assertions.

`lib/var/`, `lib/var.x`, `lib/string/`, and `lib/string.x` have no source delta
between the pre-async baseline `1355503543801f6565150a00c779668ab1d2d1bb`
and the tested source. This bounds attribution; it does not replace execution
of that baseline. The exact causes and regression status remain unclassified.
The Task-specific checks pass. No numeric expectations or runtime behavior
were changed to make this target green.

## Delivery boundary

Rosetta and Docker emulation provide ABI and execution evidence, without
establishing behavior on physical Intel hardware or performance equivalence.
The GCC use-after-return finding and Linux x86_64 numeric failures remain open.
This follow-up contains no benchmark measurements. Normal benchmark reruns,
dev/main advancement, and all pushes remain on hold.
