# NaN reconstruction and long-double padding fixes

> Status: reference - implemented and validated locally on four native targets.
> Recorded 2026-10-31. Source baseline: d20d508cf.
> Normal benchmarks remain on hold. No pushes or dev/main advancement authorized.

## Changes and compatibility

The two canonical NaN readers, Var.decode_f64 in lib/common.x and Var.floating
in lib/var/numbers.x, now return __builtin_nan("") for the discrete NaN tag.
The tag and boxing policy are unchanged. Reconstruction no longer depends on
the sign GCC assigns to `0.0 / 0.0`. Unordered-comparison logic is unchanged.

A single private compile-time alias chooses ten value bytes for x87 extended
precision (LDBL_MANT_DIG=64, LDBL_MAX_EXP=16384), and sizeof(long double) for
the other supported formats. Var.wide_hash, Var.wide_equal, and the byte
comparison in Var.wide_compare use that width. All selected native targets
with this extended format have the value in the first ten bytes. Native
binary64 and binary128 widths are unchanged.

The correction retains precision, signed-zero distinctions, and NaN payload
identity. It adds no allocation, runtime state, public API, or box-layout
change. Long-double hash values change on x87 targets because hash width now
excludes six unspecified padding bytes. No performance claim is made while
normal benchmark reruns are on hold.

The generated Var API documentation now states that these operations exclude
ABI padding. It was refreshed with make doc-generate. Bootstrap changes come
from the normal gate targets, without hand-editing generated C or headers.

## Regression coverage

Three focused tests were added to unittest/test-var.x:

- Both NaN readers reconstruct the host quiet NaN. The raw-reader path uses
  a noinline helper and volatile input to prevent constant folding from hiding
  the failure. Lowercase and uppercase formatting agree with native printf.
- Equal long doubles with deliberately different x87 padding have equal
  identity, hashes, and ordering. Clone and Map lookups preserve that result.
- Signed zeros remain distinct by identity. Adjacent long-double values keep
  their precision, and equal/distinct NaN payloads retain their identity and
  ordering behavior. Mathematical NaN equality remains false.

Before the production change, the expanded Linux x86_64 focused run has
95 passing and six failing tests out of 101, with 9,597 assertions. That is
the original three failures plus all three new tests. Afterward, all 101 pass.
Existing expectations were not weakened, and no recurring gate was added.

The earlier fresh pre-async baseline 135550354 and d20d508cf both reproduced
the same original three failures: 95 passes, three failures, 98 tests, and
9,572 assertions. The investigation evidence is retained in
.context/async-numeric-investigation-2026-10-31.md. These were inherited
numeric defects rather than failures introduced by task switching.

## Validation

Toolchains and environments match the preceding native-target checks:
Apple clang 17 on macOS and GCC 12.2 in existing local Debian images.
macOS x86_64 uses Rosetta; Linux x86_64 uses Docker emulation. Docker runs
with networking disabled and no image pulls or package installations.

| Check | macOS arm64 | macOS x86_64 | Linux arm64 | Linux x86_64 |
| --- | --- | --- | --- | --- |
| Full normal unit suite | 1,158 pass, 99,595 assertions | 1,158 pass, 99,595 assertions | 1,158 pass, 99,592 assertions | 1,158 pass, 99,592 assertions |
| Full ASan/UBSan unit suite | 1,158 pass, 99,595 assertions | 1,158 pass, 99,595 assertions | 1,158 pass, 99,592 assertions | 1,158 pass, 99,592 assertions |
| Task suite with ASan use-after-return enabled | 18 pass, 132 assertions | 18 pass, 132 assertions | 18 pass, 129 assertions | 18 pass, 129 assertions |

The three-assertion platform difference comes from existing Darwin-only
malloc-zone checks. The formerly failing Linux x86_64 numeric suites are now
clean in normal and sanitizer builds.

The macOS x86_64 build initially waited recursively on a helper-cache lock.
The configured /var/... cache root differed from its /private/var/... physical
path. The support-unit check compares Path.absolute(input) against the cache
root. Retrying with the canonical cache-root path completes the build. No
cache implementation or locking change was made. The sample and initial log
are retained in debug/async-numeric-fix-x86_64-meta-sample.txt and
debug/async-numeric-fix-macos-x86_64-cache-lock.log.

The subsequent [cache-path repair](async-cache-path-fix-2026-10-31.md)
normalizes the cache root at the support-unit comparison. Its cold aliased and
relative-path regression cases fail before that correction and pass afterward.

The complete local `make agent-pr-check` passes: bootstrap refresh and safe
rebuild, strict self-host comparisons, 1,357 compiler fixtures (2,999 artifacts),
documentation, and complete command checks. Its log is
`debug/async-numeric-fix-agent-pr-check.log`. The generated delta is limited to
common.c/common.h, the three Var operations and shifted Error-site lines,
provider source fingerprints in collect.c/linked-meta.c, and the generated Var
API page. Every delta was reviewed against the authored changes.

Raw platform checks use
`debug/async-numeric-fix-*`; Linux copies also remain under the directory in
.context/async-linux-validation-dir. The isolated macOS x86_64 tree is
recorded in .context/async-native-validation-dir. Both use separate caches.

## Delivery boundary

The resolved numeric findings do not lift the dev/main validation hold.
Normal benchmark reruns and broader publication decisions remain pending.
Everything stays local; successful checks do not authorize a push.
