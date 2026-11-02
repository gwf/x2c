# Large-batch residual memory attribution

> Status: reference
> Investigated local revision `fdb707da4` on macOS 15.7.9 arm64, Apple M4 Max.
> Runtime source is unchanged. Normal benchmark reruns remain on hold.
> Retention is attributed; acceptance or mitigation remains undecided.
> Published to `dev` in `255de641f` on 2026-10-31 (noted 2026-11-02). The
> [async follow-up](async-performance-followup-2026-10-31.md) records the
> retention as an accepted cost; the hold and undecided acceptance in this
> record are historical.

The large residual comes from macOS malloc retaining allocation regions and
freed pages. Task shutdown frees the batch allocations and unmaps the stacks.
The small live x2c residual is first-use, process-lifetime catch-site Match
plans. No count-proportional live allocation remains in the tested workload.

## One large batch

The original probe was rebuilt with the current compiler/runtime and `-O2 -g`.
It constructs 1,024 waiting jobs plus an observer before the initial snapshot.
The observer pauses after every waiter parks; the probe pauses again after
Task.run returns. Caller-owned jobs and the Channel remain alive in all phases.
`ps`, `vmmap -w`, and `heap --showSizes` inspect each paused process.

| Measurement | Before | After batch | Difference |
| --- | ---: | ---: | ---: |
| Process RSS | 1,696 KiB | 5,728 KiB | 3.9375 MiB |
| Malloc region reservation | 9 MiB | 148 MiB | 139 MiB |
| Malloc region residency | 224 KiB | 4,256 KiB | 3.9375 MiB |
| Live heap blocks | 1,344 | 1,350 | 6 |
| Live heap usable bytes | 217,232 | 218,192 | 960 |
| Scope-requested bytes | 103,536 | 104,248 | 712 |

Both the 8 MiB default and 64 KiB diagnostic stack capacity produce the same
post-batch measurements. All task stack mappings disappear. The default
stack mappings, including guards, account for 8,216.015625 MiB while parked;
the 64 KiB mappings account for 80.078125 MiB. Neither remains after return.

The 139 MiB reservation increase consists of a 128 MiB medium region, an
additional 8 MiB small region, and three additional 1 MiB tiny regions.
`vmmap` labels the medium region and additional small region empty. Other
regions contain the pre-existing caller storage and small permanent plans,
along with allocator metadata and free space.

The earlier report measured 130 MiB, rather than this run's 139 MiB. These
are different runs and revisions with different allocation layouts and native
allocator histories; this is not a comparable regression measurement.

## Exact allocation and release evidence

With MallocStackLogging enabled only in a diagnostic child, `malloc_history`
records this sequence for the job array:

1. Task.run requests `calloc(1025, 152)`: 155,800 bytes.
2. `libsystem_malloc` maps a 134,217,728-byte medium region to serve it.
3. The allocator rounds the block to 163,840 usable bytes.
4. Task shutdown frees the same 155,800-byte requested allocation.
5. The block is absent from the post-batch live heap, while the empty region
   remains mapped.

A standalone C control, without x2c or Task.run, performs the same calloc/free.
It also leaves a 128 MiB empty medium region. This establishes that the large
reservation does not require a retained TaskJob or task stack.

Source inspection agrees with the allocation trace: `_shutdown` frees
`run.jobs`; each execution backing and native coroutine control record has
a matching free; `x2c_task_stack_free` unmaps the task stack.

The six additional live blocks have MatchPlan allocation backtraces from
Task's first `x2c_error_catch_site_push`. They are two plans, two compiled
instruction blocks, and two capture layouts. The process-lifetime static-site
registry also grows an existing block. Together they account for the fixed
712 additional Scope-requested bytes and 960 allocator-usable bytes.
`lib/match/sites.x` owns those plans until Match shutdown; this is not a
per-job cache. No additional unexplained live block remains in this probe.

## Repeated large batches

A separate probe reuses the same Channel, jobs, and captures across batches.
The observer sends one reply to each waiter, leaving the Channel open for
reuse. This avoids changing fixture ownership between measurements.

| Diagnostic case | After batches | Added VM MiB | Added RSS MiB | Live heap blocks | Live heap usable bytes |
| --- | ---: | ---: | ---: | ---: | ---: |
| Default allocator | 1 | 139.000 | 3.938 | 1,352 | 218,288 |
| Same process | 100 | 1,510.031 | 32.922 | 1,352 | 218,288 |
| Same process | 1,000 | 1,646.078 | 33.016 | 1,352 | 218,288 |
| One medium magazine, separate process | 100 | 228.031 | 30.813 | 1,352 | 218,288 |
| One tiny/small and medium magazine, separate process | 100 | 129.031 | 3.625 | 1,352 | 218,288 |

Scope counts likewise remain fixed after first use: 1,115 allocations and
104,268 requested bytes after batches 1, 2, 100, and 1,000. Allocator residency
and address-space retention can therefore grow substantially even while live
application allocations remain flat. Do not use the one-batch 139 MiB figure
as a universal footprint limit.

The default repeated run ends with twelve empty 128 MiB medium regions. The
diagnostic environment controls were `MallocMaxMediumMagazines=1`, and then
that setting together with `MallocMaxMagazines=1`. They were set only for
individual diagnostic child processes. No launcher, system configuration,
runtime default, or allocator implementation was changed.

Apple's published allocator source describes these magazine controls and
128 MiB medium regions. Its medium allocator also retains a recently freed
block per magazine and excludes that cached block from live-object enumeration:
[configuration](https://github.com/apple-oss-distributions/libmalloc/blob/main/src/malloc.c),
[medium-region layout](https://github.com/apple-oss-distributions/libmalloc/blob/main/src/magazine_zone.h),
[medium allocation/free](https://github.com/apple-oss-distributions/libmalloc/blob/main/src/magazine_medium.c).
The installed binary's allocation trace and the child-process controls are
the direct evidence here; the public source corroborates the mechanism and
is not asserted to be the exact installed revision.

The per-CPU magazine model explains why one native thread can acquire more
allocator regions over time: the OS can schedule it on different CPU cores.
This does not mean tasks migrate between native threads. Actual CPU
transitions were not traced; this part of the explanation is supported by
the source and the magazine-limit control, rather than a scheduler trace.

A probe-only `malloc_zone_pressure_relief(NULL, 0)` call returned zero and
did not reduce the mappings. No assumption is made that a trim call would
remove this footprint. Real system memory-pressure behavior was not tested.

## Evidence and limits

Sources, compiler/runtime/probe hashes, summaries, full phase heap/VM dumps,
and allocation/free traces remain in the workspace-local, untracked
`.context/async-residual-memory-20261031/`. `summary.json` records the cases
above. Build and run logs are under `debug/async-residual-memory-*`.
The source samples and tools changed no tracked runtime file.

An initial repeat pilot recreated Channels and changed fixture allocation
counts. Its logs are retained, but the fixed-storage probe replaces it for
the repeated-batch conclusion. Logging-enabled runs establish allocation
ownership; their own footprint is not used for the uninstrumented numbers.

This investigation covers successful large waiter batches on this Mac. It is
not a general leak proof for failure paths, all task consumers, or other
allocators/platforms. No mitigation is proposed or applied by this report.
The remaining decision concerns the measured allocator footprint, rather
than unidentified ownership. Normal benchmark reruns and all pushes remain
held.
