# Phase7 fixed-cost investigation and selective candidate

No production source or bootstrap changes were made; evidence commits and
pushes belong only to the research branch.
Phase5 and phase6 saved binaries remain unchanged. Work was confined to the
isolated dual-macro-match-probe checkout and research artifacts.

## Measured fixed work

Before edits, four affected sources were restored from verified phase6 phase5
base snapshots; restore-hashes.json records all seven relevant owner sources.
`profile/instrumentation.patch` measures all transaction begin snapshots,
extended fields as a child, added bind/Expr carrier checks before subsequent
recursion, and parse-time open-preparation entries. The extension interval
combines adapter/base binding copies and queue/scalar snapshots; it does not
split them internally. Snapshot exclusive is preexisting work plus profiler
bookkeeping, not a clean uninstrumented baseline measurement.

The actual seven-file compiler corpus and exception benchmark ran three timed
repeats per mode, one count-only repeat, and the existing fixture three timed
repeats: all 67 outcomes/raw C/H digests equal phase5. Instrumented binary SHA
is in profile/candidate.sha256. profile/commands.log preserves complete logs;
profile/results.json and summary.json preserve per-run and grouped metrics.
Generated artifacts remain in /tmp/dual-phase7-profile-runs.

| Seven-file corpus total | Default | Live |
| --- | ---: | ---: |
| All transaction snapshots | 2119 | 2124 |
| Bind slot checks (up to three per bind call) | 105245 | 105485 |
| Expression wrapper/carrier checks | 122912 | 125983 |
| Open-preparation entries, including cache hits | 80 | 80 |
| Raw fixed-group median ms | 23.457 | 24.098 |
| Empty-read-pair adjusted estimate ms | 19.515 | 19.979 |
| Earlier paired phase5-minus-original median ms | 85.088 | 139.123 |
| Raw fraction of that earlier difference | 27.57% | 17.32% |
| Adjusted illustrative fraction | 22.94% | 14.36% |

2119 is the sum across seven source translations, not each translation.
The unused legacy `all_transactions 0` output is ignored; actual transaction
counts come from all_snapshot.calls. Derived summary omits the unused metric.

Each process calibrates 10,000 empty monotonic read intervals. Adjustment uses
THAT process's mean empty interval times its actual metric call count, then
aggregates per repeat. It does not subtract complete profiling API/stack/
bookkeeping overhead, cache disturbance or instrumented-caller effects.
These are diagnostic approximations, not exact overhead attribution or proven
lower bounds. Raw intervals remain available in fixed-cost-analysis.json.
Adding separate metric medians differs slightly from the median of actual
per-repeat totals; the table uses the latter.

Default individual group medians are extensions5.070ms, bind checks5.753ms,
Expr checks12.605ms, prep0.043ms. Live:5.387/5.771/12.967/0.046ms.
Expression probes are the largest measured new fixed group. These measurements
account for only a fraction of the earlier aggregate difference. Most of the
85/139ms remains unclassified; startup, ordinary macro work, other feature
paths and sample noise are not attributed here. The 80 preparation entries
include cached entries; no separate cold-preparation count is claimed.

## Smallest isolated removal

Final uninstrumented candidate `/tmp/x2c-dual-phase7-final` SHA:
`6cd4db4a97be7918a2291cbe8fcfb2c3f0422a5fde43864337dc7e487f9c181b`.
selective-cost-removal.patch is against the verified phase5 sources.

A separate effect-construction depth activates BEFORE the original outer try
transaction. It covers frame/new-name allocation, recursive body/finalizer/
catch lowering, declaration/landing/cleanup producers, application, and nested
transactions. Each SymTxn stores whether extended fields were active at begin;
snapshot, commit and rollback use that stored flag symmetrically. Ordinary
transactions outside construction retain pre-extension behavior. Original
scope/counters/binding transaction machinery remains unconditional.

The existing private application context gates the new carrier recognizers,
including the Expr wrapper Match. Ordinary macro-slot evaluation and ordinary
binding remain outside that gate. A cheap context branch still runs per node;
shape matching is confined to active application. Existing phase3 dormant
prototype_bound_slots branches remain. This is the smallest bounded experiment,
not the final public entry architecture: production's common application owner
must activate slot context automatically. Clients acquire no public $let or
stage wrapper obligation. The existing private flag also controls native
prototype dispatch/origin behavior, so production must separate those roles.
Generic pending Macro application outside that private context is not newly
proved by this candidate.

All requested rollback fields remain protected during effect construction.
The opt-in deliberate source-skeleton failure is caught; scoped/base binding
maps, name counters, adapters, early/inits/origins rows, origin and exception
flag restore. Nested committed work remains rollbackable, and borrowed adapter
map identity survives commit. Native fixture continues/builds/runs17 1 1 23.
phase7-rollback.log records it. Ordinary preexisting rollback gaps outside this
narrow construction context are not repaired or claimed repaired.

## Actual selective counts

A separate count-only binary instruments candidate transaction begins and
actual try applications. counts-increment.patch is against final candidate;
counts.sha256 identifies that binary. All 16 count-only corpus translations
match phase5 raw C/H/outcomes.

| Workload | All transactions | Extended transactions | Try applications |
| --- | ---: | ---: | ---: |
| Seven-file default corpus | 2119 | 2 | 2 |
| Seven-file live corpus | 2124 | 2 | 2 |
| Exception benchmark, each mode | 265 | 4 | 4 |

These are actual counts, not inference from lexical try tokens. This corpus
has no extra extended begins beyond the outer try calls; the rollback probe
separately demonstrates nested transaction retention. Candidate-counts.json
and candidate-counts.log preserve exact per-source records/commands.

Root independently verified final uninstrumented 62-case parity and rollback.
Root owns the three-way original/phase5/new paired timing; do not treat this
instrumented diagnostic as the final throughput result or a budget guarantee.

## Reproduction and source provenance

Both instrumented and uninstrumented builds used:

```
make -f ../stage.mk -C builds/0 \
  X2C_COMPILER=/tmp/x2c-dual-phase5-final >debug/PHASE7-BUILD.log 2>&1
```

The actual build logs identify their separate files in this directory. Each
built binary was copied to its preserved /tmp path before the next build.
Collection scripts are profile/run-profile.py and count-candidate.py; they
set the common X2C_HOME and exact absolute source inputs, unset the opt-in error
probe, and compare output bytes/hashes against phase5/final-manifest.json.

The source before/after snapshots remain only under /tmp/dual-phase7-*
source directories. The isolated checkout was restored to uninstrumented final
candidate sources after the count build. final-source-hashes.json records that
state. patch-check.log confirms selective-cost-removal.patch dry-applies to
verified phase5 sources in /tmp/dual-phase7-patch-check. No broad lazy map staging,
new validator, global semantic resolver or recurring check was implemented.


## Uninstrumented three-way timing

Root ran `comparison/paired-three.py` with the original baseline, preserved
phase5 binary and final selective candidate, five rotating-order samples after
warmup per workload/mode. Exact source/home paths match the previous runs;
no competing builds ran. `comparison/samples.json` retains all observations,
`summary.json` retains medians/ranges/ratios, and `timed-artifact-digests.json`
confirms final timed raw C/H identity across all three binaries. Binary hashes
were unchanged; no samples were excluded.

Compiler default: original 6.311873 s, phase5 6.414413 s, new 6.320251 s.
New total +0.133%; control total +1.625%; removal increment -1.492 percentage
points. Baseline/new ranges overlap; phase5 range is entirely above both.
Median control-to-new saving is 94.162 ms. The diagnostic spans do not fully
attribute that saving to individual fields or checks; commit and other effects
of the changed control flow remain unclassified.

Compiler live: new -1.318% total, phase5 -0.117%, removal -1.201 pp. Ranges
are broad and overlap; no stable speedup claim follows. Exception default:
new +0.869%, phase5 +0.363%, new is +0.506 pp worse. Exception live: new
+0.122%, phase5 +1.760%, removal -1.638 pp with overlapping ranges and a
1.200863 s original-baseline observation. All samples remain in the record.

The 2% cumulative default aim is retained; the phase6 5% recommendation is
withdrawn. The selective try candidate is the first per-lowering ledger row,
including remaining shared support. Later increments subtract cumulative ratios
against the same original baseline and window, with default/live and workload
counts recorded separately. Three-lowering feasibility is not established.
