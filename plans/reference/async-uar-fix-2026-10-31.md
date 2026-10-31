# GCC ASan use-after-return overflow correction

> Status: reference - local runtime fix and focused regression validation.
> Recorded 2026-10-31. Normal benchmarks remain on hold; no pushes authorized.
> Source baseline: e1f4ba26b. The Linux numeric findings are outside this fix.

## Failure and correction

The new `unittest/probes/task-stack-uar.c` reproduces the false overflow with
GCC 12.2 on Linux arm64 and x86_64: both unmodified runs abort with status 134.
ASan use-after-return relocates the addressed local in `mco_yield` to its fake
stack. Comparing that address with the physical coroutine mapping incorrectly
reports stack overflow.

Under GCC and Clang, `mco_yield` now uses `__builtin_frame_address(0)` for the
physical address comparison. Other compilers retain the original local-address
path. The bounds comparison and metadata magic check are unchanged. This adds
no runtime state, ownership requirement, allocation, or public API.

The native dependency's local adaptations are recorded in `lib/task/README.md`.
No language or library semantics change. Bootstrap artifacts are refreshed
through the existing targets, never edited by hand.

## Focused regression

The optional existing `unittest/probes/run-task-backend.sh` compiles and runs
the new C probe with ASan/UBSan and use-after-return enabled. No recurring gate
was added. It exercises 32 KiB, 65,537-byte, and 8 MiB requested stack sizes,
three yields per stack, access to parked local storage, resumed local values,
completion, and stack release. It also verifies that invalid bounds and an
invalid metadata magic still return MCO_STACK_OVERFLOW. The correction does
not disable overflow checking.

The probe and the existing native layout, guard, full unmapping, and
unsupported-backend checks pass on all four selected native targets. The
Linux GCC probe fails before the correction and passes after it. Probe logs:
`debug/async-uar-{arm64,amd64}-before.log` and
`debug/async-uar-{arm64,amd64,macos-arm64,macos-x86_64}-backend.log`.

## Runtime checks

Toolchains and environments are the same as the
[native target validation](async-native-targets-2026-10-31.md): Apple clang 17
on macOS, GCC 12.2 in local Debian containers. macOS x86_64 uses Rosetta;
Linux x86_64 uses Docker emulation. Containers have networking disabled and
use existing images with no pulls or package installations.

| Check | macOS arm64 | macOS x86_64 | Linux arm64 | Linux x86_64 |
| --- | --- | --- | --- | --- |
| Focused native regression and backend probes | Pass | Pass | Pass | Pass |
| Task suite, ASan/UBSan with use-after-return enabled | 18 tests, 132 assertions pass | 18 tests, 132 assertions pass | 18 tests, 129 assertions pass | 18 tests, 129 assertions pass |
| Full ordinary ASan/UBSan suite | 1,155 tests, 99,570 assertions pass | 1,155 tests, 99,570 assertions pass | 1,155 tests, 99,567 assertions pass | 1,153 pass, 2 known numeric failures; 99,567 assertions |

The Linux x86_64 full sanitizer failures are unchanged:
`string_checked_format_floating` and `var_wide_value_semantics`. The latter
still fails identity, hash, and ordering assertions. No new sanitizer memory
diagnostic appears. The complete Task suite passes with use-after-return
enabled on every target, including failure, cancellation, Error, and cleanup
scenarios.

The Linux totals have three fewer assertions because the existing job-array
malloc-zone checks are Darwin-only. Both Linux normal Task suites pass:
18 tests and 129 assertions each. The Linux numeric findings remain outside
this repair; no numeric code or expectations were changed.

Full logs use `debug/async-uar-*` and `debug/async-{arm64,amd64}-uar-*`.
Linux full-check logs and status files are
also retained under the directory in `.context/async-linux-validation-dir`.
The reused isolated macOS x86_64 tree is recorded in
`.context/async-native-validation-dir`.

## Delivery boundary

The full local `make agent-pr-check` passes, including bootstrap recovery,
strict self-host comparisons, 1,357 compiler fixtures (2,999 artifacts),
documentation, and complete command checks. The log is
`debug/async-uar-agent-pr-check.log`. The only bootstrap delta is the same
five-line correction in `bootstrap/lib/minicoro.h`, matching the authoritative
header exactly. Authored and generated diffs pass review and `git diff --check`.

Normal benchmark reruns, dev/main advancement, and all pushes remain on hold.
The existing Linux x86_64 numeric failures still require investigation before
publication.
