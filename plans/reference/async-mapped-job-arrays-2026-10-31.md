# Mapped TaskJob arrays: implementation and memory validation

> Status: reference
> Implemented privately at source checkpoint `b185f710`.
> Normal benchmark reruns remain on hold. No push is authorized.

## Change and costs

The native task backend uses calloc/free when the job-array byte count is at
most one native page. Larger arrays use a zeroed anonymous read/write mapping
and munmap. Task.run and its existing shutdown pass the same byte count;
there is no allocation-kind flag or separate lifetime record. Job addresses
remain stable, and the array is released after all task cleanup completes.

Each nonempty batch adds the two native helper calls and page-size queries.
An affected large batch adds one mmap and one munmap, plus the mapping's
ordinary first-touch costs. There is no per-task-switch operation, process
allocator setting, or change to ordinary synchronous allocation paths.
Timing costs were not measured in this pass. Small arrays keep their existing
allocator and large arrays use less than one page of rounding.

On this Mac, the cutoff is 16 KiB. The 1,025-job array requests 155,800 bytes;
the kernel maps 163,840 bytes. This targets the medium-region retention
identified in [the investigation](async-residual-memory-2026-10-31.md).
It does not replace allocation inside the task state owners or eliminate
the native allocator's smaller caches.

## Focused tests

Two cases were added to the existing task suite:

- Allocate one byte below, exactly at, and one byte above the native page.
  Check zero initialization and writable storage. On Darwin, check which
  allocator owns each result. After releasing the larger mapping, verify
  that neither covered page can be protected again.
- Complete a 1,025-job batch, fail startup after one job has been prepared,
  and run another batch afterward. This exercises zeroed partial records,
  cleanup before array release, and restored executor state.

The focused suite passes 17 tests and 112 assertions. The full fresh
ASan/UBSan suite passes 1,154 tests and 99,550 assertions. The focused suite
also passes with stack-use-after-return detection enabled. The sanitizer
runner retains its existing disabled leak-detection setting.

## Memory comparison

The retained baseline executables use runtime revision `fdb707da4`, unchanged
by the subsequent investigation-only commit. Their identity was preserved;
the single-batch binary hash was checked against the investigation receipt.
Candidate binaries use the checkpoint above. Both use identical probe source,
`-O2 -g`, Scope accounting enabled, and the ordinary process allocator.
No magazine-limit setting is applied.

The table gives post-batch increases over the same process's initial state,
before the probe's optional allocator-pressure diagnostic:

| Workload | Baseline VM MiB | Mapped VM MiB | Baseline RSS MiB | Mapped RSS MiB |
| --- | ---: | ---: | ---: | ---: |
| One batch, 65 jobs, 64 KiB stacks | 9.000 | 9.000 | 0.313 | 0.313 |
| One batch, 1,025 jobs, 64 KiB stacks | 139.000 | 2.000 | 3.938 | 3.703 |
| One batch, 1,025 jobs, default 8 MiB stacks | 139.000* | 2.000 | 3.938* | 3.703 |
| 1,000 batches, 1,025 jobs each, 64 KiB stacks | 2,148.078 | 136.078 | 38.188 | 30.984 |

The starred default-stack baseline is retained from the preceding
investigation; the other baseline rows were rerun in this pass.

The repeated baseline retains sixteen empty 128 MiB medium regions. No
medium region remains in any mapped large-batch result. All task stack
mappings and the large job-array mapping are released. Smaller malloc
regions remain. Total VM and RSS depend on allocator history and native CPU
scheduling; these figures do not promise a universal footprint or RSS saving.
The absence of the medium-region trigger is the direct result established.

Live allocations are unchanged between implementations. The single large
batch ends with 1,350 live heap blocks and 218,192 usable bytes; the repeated
probe ends with 1,352 blocks and 218,288 usable bytes. Scope accounting keeps
the same fixed first-use increase of six allocations and 712 requested bytes.
There is no additional live allocation across repeated batches in this probe.

One candidate repetition attempt exceeded the original 30-second watchdog
after its 100-batch checkpoint. Its log and partial snapshots are retained.
The baseline and candidate were then run to completion with a longer bounded
diagnostic wait. No throughput result is inferred from those durations.

Raw phase VM maps, heap reports, comparison summaries, binary/source hashes,
and capture scripts remain in the workspace-local, untracked
`.context/async-mapped-jobs-20261031/`.
`summary.json` records the completed cases. Logs are under
`debug/async-mapped-jobs-*`. The interrupted case is `mapped-1000`; the
completed candidate is `mapped-1000-complete`.

## Gate result and remaining scope

The full `make agent-pr-check` invocation passes, including bootstrap/stage
comparisons, artifact atomicity, documentation audit, cold collection,
verification, documentation outputs, and command checks including REPL.
Ordinary verification passes 1,154 tests and 99,550 assertions, plus
1,357 compiler fixtures and 2,999 artifacts. The cold comparison covers all
475 C/H/.xi files, and all 136 documentation output samples match.

Generated bootstrap changes were produced by the existing target and reviewed:
the native backend contains the new helpers, Task calls them, and its interface
declares them. Remaining linked-meta changes are generated metadata updates.
No validation target or lint baseline was expanded or weakened.

The existing native-target coverage and performance/retention acceptance
limits remain. This change does not accept the remaining resident footprint,
and normal benchmark reruns and all pushes remain held.
