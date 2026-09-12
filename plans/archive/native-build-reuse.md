# Overlap retained native-build fingerprints

> Status: done - implementation and focused verification complete, 2026-09-11.
> Authorized with the independent research follow-ups. Delivery commit
> subject: `overlap native fingerprints and close research probes`.

## Decision and implementation

Retained builds preprocess every native source to fingerprint the actual
native inputs. The old loop waited for each preprocess before scheduling
compilation, so unchanged builds serialized that work even with multiple jobs.

Use the existing bounded CcJob loop for both stages. A retained job starts
preprocessing; its completion hashes the same output and either records a
cache hit or starts compilation in the same slot. Compilation success alone
publishes new state. Keep direct compilation for nonretained builds and dry
runs. Delete the synchronous fingerprint helper. Preserve include-search and
shadowing behavior, flags, failure propagation, and the requested job bound.

## Evidence and verification

A local synthetic workload has 16 C files including standard C and pthread
headers, built into a retained static archive. Baseline and candidate generated
sources differ only in src/build.c; runtime and other compiler sources match.
Five unchanged-build repetitions and three one-file-edit repetitions produced
these median elapsed seconds on this macOS host:

| Workload | Baseline j1 | Candidate j1 | Baseline j4 | Candidate j4 |
| --- | --- | --- | --- | --- |
| Unchanged | 0.461 | 0.458 | 0.456 | 0.167 |
| One-file edit | 0.486 | 0.489 | 0.469 | 0.173 |

The jobs-4 unchanged workload improves 63%; the sequential case is effectively
unchanged. This establishes value for this synthetic workload, not a general
speedup guarantee. Other agents paused build/benchmark work during timing;
the desktop was not otherwise isolated. Raw measurements, provenance hashes, and build/probe logs are retained at
`/Users/gary/Documents/x2c-evidence/research-20260912/native-build-reuse/`.
The final source additionally normalizes a negative launch/wait failure to a
completed failed job; this does not change the measured successful path.

The existing CLI boundary probe passed all 110 checks, including native
environment, header shadowing, optional-header appearance, nonretained,
dry-run, scheduling, failure, and retry behavior. Its existing retained-native
cases now use two concurrent sources, covering cache hits beside misses
without adding separate probe invocations. A scratch copy changed only its
expected runtime archive path to the bootstrap archive selected by the isolated
compiler; the tracked probe retains the normal builds/0 expectation. Earlier
runs stopped at that expected-path mismatch and remain in the evidence.

A separate temporary fault probe passed preprocessing failure, compilation
failure, successful retry, complete child draining, at most two active native
children with jobs=2, and removal of preprocessor temporary files. Source
review checked cache-hit counting and normalized negative launch/wait failures
so they cannot be confused with a stage transition. The authored diff passes
git diff --check. Integrated publication uses the existing agent-pr-check, including
bootstrap regeneration and the unmodified runtime-path assertion.

## Plan review

The native preprocessor establishes effective source inputs; preserve its
fingerprint rather than approximating dependencies. The existing job owner
already bounds execution, captures results, waits, and reports progress.
Additional job fields retain the compile action across preprocessing; the
preprocessed path also identifies that stage. No second scheduler, cache,
validator, diagnostic, or public contract is introduced. Existing probe cases
exercise actual reuse correctness. The completed authored source review found no further changes needed.
