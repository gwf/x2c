# U32Map optimization research

Result paths recorded before the benchmark relocation are relative to the
preserved `examples/build/hash-table-benchmark/` tree. New runs write under
`unittest/build/benchmarks/hash-table/`; no historical result was moved or
deleted.

This tranche optimized the runtime-free scalar map without changing its hash,
load factor, slot/record layout, dynamic PSL, Robin Hood displacement,
back-shift deletion, or record reuse. Production `lib/map.x` remained
unchanged during that tranche; its later measured follow-up is recorded
below.

## Retained implementation

Four source changes survived isolated and combined measurement:

1. A hygienic `$u32.unlikely(condition)` expression macro marks the two rare
   growth edges. Clang then leaves `_expand` out of the hot exported function;
   the inline report's threshold falls from 250 to 45 and the ARM64 frame falls
   from 112 to 96 bytes.
2. Expansion collects reusable deleted record indexes and reinserts occupied
   slots in one scan of the old table instead of two.
3. Lookup and get-or-insert cache the record-array pointer for the duration of
   a probe, avoiding a repeated map-field load on matching hashes.
4. One `$u32.record_accessor` unit macro emits the key and value pointer
   accessors. They now state the normal iterator precondition instead of
   revalidating an iterator returned by the immediately preceding operation.

The key result is not merely an `inline` spelling. The growth likelihood macro
communicates the cold edge to the optimizer, which prevents transitive
inlining of allocation and rehashing into the probe entry point.

## Measurements

The full-scale rotated research run is retained at
`research/results/20260731T174158.440840Z` under the ignored examples build
directory. Five 80-million-input repetitions produced:

| variant | count ns/input | change | mixed ns/input | change |
| --- | ---: | ---: | ---: | ---: |
| retained baseline | 51.9 | - | 49.6 | - |
| all portable candidates plus neutral trials | 47.6 | -8.3% | 45.4 | -8.5% |

A ten-repeat, 20-million-input isolation at
`research/results/20260731T174432.980858Z` showed that the four-change
`portable-core` was sufficient: 36.0 versus 40.7 ns/input counting (-11.6%)
and 37.0 versus 40.1 mixed (-7.7%). Adding the PSL and record-zeroing trials
did not improve that combined result, so they were not applied to U32Map.

The fresh full standard udb3 cohort is retained at
`results/20260731T174720.470458Z-full`. All 176 size/checksum checkpoints
matched:

| implementation | count ns/input | ratio | mixed ns/input | ratio |
| --- | ---: | ---: | ---: | ---: |
| CC | 21.5 | 1.00x | 34.0 | 1.02x |
| robin_hood | 26.2 | 1.22x | 33.4 | 1.00x |
| optimized U32Map | 46.9 | 2.18x | 46.4 | 1.39x |
| production Map control | 220.3 | 10.25x | 107.2 | 3.21x |

Against the previous full U32Map result (55.3 and 50.3 ns/input), the new run
is 15.2% faster for counting and 7.8% faster for mixed. Counting still misses
the classification target by 0.18x; the result is retained rather than hidden.

The independent full Jackson scalar lane is retained at
`results/20260731T174852.421601Z-full`. At 200,000 entries, insertion improved
from 35.52 to 26.76 ns (-24.6%), replacement from 7.92 to 7.10 ns (-10.3%),
and existing lookup from 8.72 to 7.60 ns (-12.8%). Existing erase was neutral
(12.48 to 12.57 ns); missing erase, missing lookup, and iteration changed by
less than 3%.

The optimized equal-LTO full lane is retained at
`results/20260731T175155.617400Z-full`: 46.7 ns/input counting and 44.4 mixed.
Relative to the fresh standard run, LTO changes those results by -0.4% and
-4.3%. The remaining cost is therefore still principally table work rather
than the C ABI boundary.

The optimized full-scale sample remains in `debug/map-research-profile/`.
Get-or-insert/probing still accounts for about nine tenths of counting samples.
In mixed work it remains dominant, with iterator erasure the clear second
cost. Reducing the suite hash to 32 bits and record allocation are not the
next large targets.

## Production portability

- **Cold growth hint: direct candidate.** Production `_get_or_insert` has the
  same two rare capacity branches. A private expression macro can carry the
  likelihood without exposing a public contract or changing behavior.
- **One-pass expansion: direct candidate with transactional care.** Production
  Map must retain its pre-count/reserve phase so allocation failure leaves the
  map unchanged. After reserve succeeds, collection of deleted indexes and
  reinsertion of occupied slots can share the same old-slot scan.
- **Cached record pointer: direct candidate.** Refresh it at each `retry` so an
  expansion or record reallocation cannot leave a stale pointer.
- **Unchecked accessors: internal-only candidate.** U32Map's C ABI now requires
  a valid iterator. Production public safety contracts need not change; only
  private paths which have just proved or created a slot should use unchecked
  access.

## Retained negative and neutral results

- Replacing `(capacity + index - stored_start) & mask` with unsigned masked
  subtraction removed an ARM64 add but did not consistently improve time.
- Skipping initialization of newly reserved record capacity was neutral alone
  and has no direct `Bytes` analogue in production.
- Removing record clearing and iterator validation from erase did not produce
  a stable combined win and weakens diagnostics, so neither was applied.
- Swiss-table control bytes, SIMD group probing, inline key/value slots,
  alternate hashes, changed load factor, and benchmark pre-sizing were
  rejected because they would change the algorithm or fairness contract.

All these variants remain named in `research.py`; complete and incomplete
timestamped runs remain in the ignored research result tree.

## Production Map follow-up

The production experiment used two separately built but byte-identical
baseline binaries to measure repeat drift, then froze a new static binary and
exact `map.x` for each candidate. Every comparison used 14 interleaved samples
at 32,768 and 1,048,576 entries. Checksums matched between x2c and khashl and
between the two production versions before any timing was summarized.

The balanced identical-binary comparison is retained at
`direct/comparisons/20260801T140605.640796Z`. Absolute paired median drift was
at most 1.06% at 32,768 entries and 4.62% at 1,048,576 entries. That measured
drift, or 3% when larger, was the rejection threshold for unrelated lanes.

| candidate | 32,768 entries | 1,048,576 entries | result |
| --- | ---: | ---: | --- |
| cold growth hint | target lanes -1.15% to +1.00% | target lanes -2.31% to +0.32% | rejected as inconsistent and within drift |
| cached record pointer | target lanes -0.30% to -0.15% | target lanes +3.40% to +3.86% | rejected; keeping the pointer live hurt the large table |
| combined expansion scan | growth -11.84%; largest unrelated slowdown +0.26% | growth -6.80%; largest unrelated slowdown +1.66% | retained |

Negative candidates remain available in commits `3a9a09af` and `17140946`;
their restoring commits are `50345d85` and `510e365b`. Their frozen direct
runs are `direct/results/20260801T141034Z` and
`direct/results/20260801T141307Z`, with paired comparisons at
`direct/comparisons/20260801T141109.924323Z` and
`direct/comparisons/20260801T141340.907461Z`.

The retained combined scan is commit `2ac4d691`. Its frozen run is
`direct/results/20260801T141752Z`. The first comparison at
`direct/comparisons/20260801T141828.175162Z` reported a 5.55% erase-hit
slowdown even though the emitted `Map.try_del` code and address were
unchanged. The exact repeat at
`direct/comparisons/20260801T141948.407607Z` reversed that row to a 5.22%
improvement while reproducing the growth win. The repeat is the deciding run;
all other unchanged operations were within the acceptance band.

Production retains only the combined traversal after the required deleted
count and pool reservation. The cold hint and record-pointer cache were
removed from the final `lib/map.x`; their source, binaries, raw output, and
summaries were not deleted.

The final full production confirmation is retained at
`jackson/results/20260801T142841Z-full-matched`,
`jackson/results/20260801T143221Z-full-fixed-policy`, and
`udb3/results/20260801T143518Z-full`. Jackson growing insertion measured
49.18 ns/operation, down 12.4% from the prior current-`dev` result of 56.13.
No other Jackson operation regressed by more than 1.0%. All 176 udb3
checkpoints matched; production Map measured 227.2 ns/input counting and
108.1 mixed, changes of +2.8% and +1.4% from the prior full run. Those changes
are within the campaign's recorded repeat variation and are not a material
regression.

## 0.80 load-factor follow-up

After the optimization tranche, U32Map's benchmark default and the Jackson
U32 matched cohort were changed from `0.50` to `0.80`. Production `lib/map.x`
and its older Jackson lane remain at `0.50`. The U32 growth test uses exact
integer arithmetic: it expands when the next insertion would exceed four
fifths of capacity.

The fresh full standard udb3 cohort is retained at
`results/20260731T182312.576740Z-full`; all 176 checkpoints matched. Relative
to the optimized `0.50` run:

| workload | 0.50 time | 0.80 time | time change | 0.50 memory | 0.80 memory |
| --- | ---: | ---: | ---: | ---: | ---: |
| counting | 46.9 ns | 65.7 ns | +40.1% | 48.38 B/entry | 48.19 B/entry |
| mixed | 46.4 ns | 72.1 ns | +55.4% | 87.29 B/entry | 50.93 B/entry |

Counting ends just below 0.50 occupancy at either policy because the final
entry count forces the same power-of-two capacity. The 0.80 version delays
earlier doublings and spends more of the cumulative workload traversing dense
probe clusters. Mixed work retains the smaller allocation, reducing peak
bytes per live entry by 41.7%, but pays heavily in probe and back-shift time.

The full equal-0.80 Jackson cohort is retained at
`results/20260731T182453.760617Z-full`. At 200,000 entries, U32Map changes
relative to optimized 0.50 were:

| operation | 0.50 | 0.80 | change |
| --- | ---: | ---: | ---: |
| insert nonexisting | 26.76 ns | 37.65 ns | +40.7% |
| erase existing | 12.57 ns | 31.57 ns | +151.2% |
| replace existing | 7.10 ns | 16.86 ns | +137.4% |
| erase nonexisting | 10.83 ns | 17.91 ns | +65.3% |
| lookup existing | 7.60 ns | 17.12 ns | +125.2% |
| lookup nonexisting | 10.38 ns | 17.53 ns | +68.8% |
| iterate | 8.41 ns | 4.44 ns | -47.2% |

At 0.50, 200,000 entries require 524,288 slots; at 0.80 they fit in 262,144.
That halves iteration's slot scan while making individual probe clusters much
denser. The matched competitors also use 0.80 in this lane, so the result is
an algorithm comparison at equal maximum load rather than a policy mismatch.

The standard fixed-policy context is retained at
`results/20260731T182954.075431Z-full`; Boost and Abseil continue to ignore the
requested value and are not part of the equal-load ranking. The U32-only LTO
diagnostic is `results/20260731T182851.490184Z-full`: 64.5 ns counting and
74.5 ns mixed, again showing that the ABI boundary does not explain the dense
table regression. The 0.80 sampling evidence remains under
`debug/map-load-080-*.sample.txt`; probing still overwhelmingly dominates.

## Dense-table counter profile

The full 80-million-input counter run is retained at
`results/20260731T185948.812568Z-profile`. It uses a separately compiled
`U32_MAP_PROFILE` binary; all counter expressions preprocess to no-ops in the
timed implementation. Both workloads produced the same final sizes and
checksums as the timing run.

| observation | counting | mixed |
| --- | ---: | ---: |
| probes per operation | 1.830 | 1.884 |
| maximum observed probe | 31 | 30 |
| operations finding an existing key | 79.19% | 44.23% |
| insertions beginning with Robin Hood displacement | 33.71% | 32.31% |
| steady reinsert probes per displaced insertion | 6.28 | 5.67 |
| reinsert probes caused by expansion | 50.38% | 17.96% |
| back-shifted slots per erase | - | 2.07 |
| false 32-bit hash matches | 97,927 | 70,426 |

The primary cost is dense scalar probing, not hashing. Across 80 million map
operations, the two workloads execute 66.4 million and 70.7 million probe
iterations beyond the first. Every occupied nonmatch dynamically reconstructs
the resident slot's PSL. About one third of new keys begin a Robin Hood
displacement, and each such insertion then probes another 5.7 to 6.3 slots.
Mixed work additionally moves 73.2 million slots during back-shift deletion.

Expansion is visible but not the whole result. Counting reinserts 26.8 million
records during 24 expansions, requiring 35.8 million probes. Mixed reinserts
13.4 million records during 23 expansions. The instruction samples still put
expansion below the steady probe loop because those costs occur in short,
batched episodes.

The supplied suite hash is not recomputed inside U32Map. In this retained
profile, U32Map reduced the 64-bit result to 32 bits with
`low32 ^ high32`. That took four ARM64 instructions before probing. Two
different keys had the same stored 32-bit hash in only 0.067% of counting
probes and 0.047% of mixed probes, so those extra key comparisons did not
explain the performance gap. U32Map now stores the low 32 bits directly; new
results are recorded separately from this profile.

The next algorithm-preserving experiment should target dynamic PSL cost. A
small PSL field or side metadata can preserve Robin Hood insertion,
back-shifting, the split slot/record design, and the 0.80 policy while avoiding
PSL reconstruction on every occupied probe. Packing PSL into the existing
slot should first quantify the additional key comparisons caused by reducing
the stored hash fingerprint; a side byte should separately quantify its cache
and memory cost. Returning the record index with an iterator is lower priority:
the instruction samples show value accessors are a small fraction of time.

## Hash and map semantics

Within udb3, every selected adapter starts from `udb_hash_fn`, the suite's
64-bit SplitMix-style finalizer. Within Jackson, every selected adapter starts
from the `uint32_uint32_murmur` blueprint's 64-bit MurmurHash3 finalizer. That
does not mean all tables use identical bucket bits. U32Map folds low and high
32-bit halves in the retained dense profile above. It now stores the low
32 bits directly. khashl applies Fibonacci bucket mapping; robin_hood and
unordered_dense apply internal remixing; other tables select their own hash
fragments and bucket bits. This is normal table behavior and part of the
implementation being measured. Forcing identical internal bucket selection
would require altering competitors rather than testing their normal APIs.

Both suites exercise maps, not sets. The udb3 counting workload increments
and checks each stored value. Its mixed workload stores the input ordinal for
new keys and erases through the returned iterator. Jackson's blueprint is
explicitly a 32-bit-key, 32-bit-value map, and its lookup and iteration tests
touch values to force normal value access. U32Map does not store the key as the
value: each slot is `(32-bit hash, record index)`, while each record is
`(32-bit key, 32-bit value)`. A set specialization could omit the value, but
benchmarking that against map implementations would not be apples-to-apples.

## Low-32-bit hash follow-up

U32Map now stores the low 32 bits of the suite-supplied hash directly. Zero
is still changed to one because zero marks an empty slot. The differential
test, ASan, UBSan, symbol audit, udb3 smoke, both full udb3 workloads, and the
full Jackson U32Map lane passed.

The prior XOR result is one run. The low-32-bit result below is the median of
three consecutive runs on the same Apple M4 Max:

| udb3 workload | `low32 ^ high32` | low 32 bits | change |
| --- | ---: | ---: | ---: |
| counting | 56.8 ns/input | 53.7 ns/input | -5.5% |
| mixed | 84.8 ns/input | 82.9 ns/input | -2.2% |

The low-32-bit runs were 53.0-54.0 ns/input counting and 82.7-83.0
ns/input mixed. The Jackson result did not show a consistent change across
operations, which is expected when removing only two instructions from short,
noisy measurements.

The low 32 bits produced slightly longer probe chains in these inputs. The
largest ordinary PSL increased from 30 to 33, and the largest PSL while moving
an entry increased from 34 to 35. Six bits still cover every PSL observed in
this run. The speed improvement happened despite that small change in hash
distribution.

Retained result directories:

- XOR timing: `results/20260731T185847.936172Z-full`
- low-32-bit timings: `results/20260731T235022.796358Z-full`,
  `results/20260731T235125.952854Z-full`, and
  `results/20260731T235142.476661Z-full`
- low-32-bit counters: `results/20260731T235039.973377Z-profile`
- low-32-bit Jackson: `results/20260731T235214.317061Z-full`

## Earlier stored-PSL map

The older x2c-v1 archive stored PSL in each slot. Its slot remained eight
bytes by sharing the second 32-bit word between a 28-bit record index and a
4-bit PSL:

```c
#define INDEX_BITS 28
#define PSL_BITS    4

struct MapSlot { uint hash, index:28, psl:4; };
```

This appears in `x2c-v1/lib/map.x`, beginning with commit `1266eafc` on
2022-04-25. Commit `31f8e552` fixed the insertion loop to permit PSL 15;
insertion beyond 15 grew the table and retried. Commit `4a47742b` introduced
the replacement on 2023-10-25: a 32-bit hash and 32-bit record index, with
PSL calculated from the hash and current slot.

No five-bit stored version appears in that archive's reachable history. A
2023 comment considered dividing the 32-bit index/PSL word according to the
current record count, but that design was not implemented.

## Five-bit stored PSL experiment

Commit `2cd5fe86` divided the second slot word into a 27-bit record index and
five PSL bits. Values 0 through 30 were stored directly; 31 caused exact PSL
calculation. This retained eight-byte slots and left room for 134,217,727
record indexes.

The exact calculation was exceptionally rare:

| udb3 workload | PSL reads | exact calculations | fraction |
| --- | ---: | ---: | ---: |
| counting | 110,587,719 | 103 | 0.0000931% |
| mixed | 245,575,507 | 283 | 0.0001152% |

Despite that, the packed version was slower. These are medians of three
consecutive full runs:

| udb3 workload | calculated PSL | stored PSL | change |
| --- | ---: | ---: | ---: |
| counting | 53.7 ns/input | 55.8 ns/input | +3.9% |
| mixed | 82.9 ns/input | 90.1 ns/input | +8.7% |

Generated ARM64 showed that calculating PSL takes a short branchless sequence.
The packed form added extraction and a branch, masked every record index, and
made back-shift deletion decrement and repack every moved slot. Commit
`d2641f30` therefore restored calculated PSL as the benchmark default. The
working experiment remains inspectable at `2cd5fe86`; its results remain in:

- initial packed timings: `results/20260801T030623.928312Z-full`,
  `results/20260801T030643.139177Z-full`, and
  `results/20260801T030701.483399Z-full`
- final packed timings: `results/20260801T031215.054924Z-full`,
  `results/20260801T031320.075279Z-full`, and
  `results/20260801T031341.107245Z-full`
- final counters: `results/20260801T031252.908015Z-profile`
- final Jackson run: `results/20260801T031411.028848Z-full`

## Outlined insertion experiment

The generated `get_or_insert_hashed` originally contained the probe loop,
record-array reallocation, zeroing, table growth, record storage, and Robin
Hood reinsertion. On ARM64 it created a 96-byte frame and saved ten registers
for every operation, including an existing-key hit.

The retained version makes two narrow changes without changing probing or
storage:

- `_grow_records` contains only the rare record-array reallocation and
  zeroing work.
- `_insert_hashed` contains the absent-key work and is a tail call from the
  two insertion points in the probe loop.

Both helpers are prevented from being inlined. The common probe function now
has a 16-byte frame and saves no general-purpose registers beyond the frame
and return addresses.

The full comparison alternated three variants at 80 million inputs so host
speed changes affected them equally:

| udb3 workload | baseline | growth only | both helpers | change for both |
| --- | ---: | ---: | ---: | ---: |
| counting | 55.6 ns/input | 54.9 | 50.3 | -9.5% |
| mixed | 85.2 ns/input | 86.0 | 83.8 | -1.6% |

Outlining record growth alone was not retained: its mixed result was slower.
Moving all insertion work into one helper without separately moving record
growth was also tested. It improved counting but initially slowed mixed. The
combined form is the only full-scale version which improved both workloads.

The isolated Jackson run did not show a reliable improvement over its older
baseline; host speed had changed enough that it cannot separate this source
change from run-to-run movement. The udb3 conclusion uses only the interleaved
comparison above.

Retained evidence:

- helper isolation at 20 million inputs:
  `research/results/20260801T033745.590043Z`
- record-growth isolation at 20 million inputs:
  `research/results/20260801T033945.599806Z`
- four-variant combined run at 20 million inputs:
  `research/results/20260801T034447.182103Z`
- decisive interleaved 80-million-input run:
  `research/results/20260801T034610.177187Z`
- applied-source Jackson run:
  `results/20260801T034832.947474Z-full`

## Profile after outlining insertion

The fresh full counter run is retained at
`results/20260801T040054.024217Z-profile`. It uses the applied low-32-bit,
calculated-PSL, outlined-insertion source. Both 80-million-input workloads
ended with the expected sizes and checksums.

| work done per input | counting | mixed |
| --- | ---: | ---: |
| ordinary probes | 1.831 | 1.884 |
| ordinary plus Robin Hood reinsert probes | 2.718 | 3.132 |
| ordinary probes, reinsertion, and erase scans | 2.718 | 4.492 |
| back-shifted slots | - | 0.918 |

The detailed optimized-function samples are retained below that result in
`sampling/`. Startup-only samples are excluded from the percentages:

| exclusive top-of-stack area | counting | mixed |
| --- | ---: | ---: |
| ordinary get-or-insert probe function | 83.2% | 79.7% |
| Robin Hood reinsertion | 9.6% | 10.5% |
| back-shift erase | - | 5.9% |
| absent-key insertion bookkeeping | 1.1% | 2.9% |
| expansion and zeroing | 1.9% | 0.5% |
| returned-value accessor | 0.9% | - |
| benchmark loop, checkpoints, and other work | 3.3% | 0.4% |

The dominant instruction sequence is now more specific than "probing." On a
stored-hash match, U32Map loads the record index from the slot, multiplies it
by the eight-byte record size, and only then can load the key from the
separate record array. Samples on those dependent loads alone were 47.9% of
the counting capture and 34.1% of mixed. Counting performs that second-array
load 63.45 million times; mixed performs it 35.46 million times.

Those loads are almost never wasted on a 32-bit collision. Only 98,384
counting probes and 71,403 mixed probes matched the stored hash but not the
key: 0.067% and 0.047% of ordinary probes. Hash calculation plus benchmark
loop work is at most the small non-map fraction in the table. Calculated PSL
arithmetic is also not a large isolated cost, which agrees with the slower
stored-PSL experiment.

The next substantial, algorithm-preserving experiment is key placement, not
another hash or call-boundary change. Keep the hash, calculated PSL, Robin
Hood displacement, 0.80 load limit, and back-shift deletion unchanged, but
put keys at their current table positions. A parallel key array should be
tested first because it preserves the eight-byte slot stride and lets a slot
and its key be fetched without first loading a record index. Values can
remain in reusable records, preserving stable mutable-value pointers. A
12-byte slot containing the key is a useful comparison to tell whether the
parallel array helps more than the wider slot hurts.

This layout can translate to production Map without changing its hashing
algorithm: keys move with Robin Hood slots, values remain indexed records,
and structural mutation already invalidates traversal state. It does change
the split between slot and record storage, so it must earn its additional
slot-side memory in both benchmarks before any production proposal. A
smaller follow-up is to outline the deleted-record pool path from `_reinsert`;
that function still saves six registers because it can reach `realloc`, but
reinsertion is only about one tenth of time and therefore cannot explain the
main gap by itself.

## Parallel key array experiment

The parallel-key variant was implemented without changing the supplied hash,
stored hash, PSL calculation, Robin Hood insertion decisions, 0.80 load
limit, record-index reuse, or back-shift deletion. Eight-byte slots remain
`(hash, value-record index)`. Keys occupy a separate array indexed by table
slot, move whenever a slot moves, and are reinserted with their slots during
expansion. Value records remain separately allocated and reusable.

The generated ARM64 confirms that the intended lookup change happened. The
current map loads the record index, shifts it by the eight-byte record size,
and then loads the key. The parallel version replaces those three dependent
instructions with one key load indexed by the already-known table position.

It is nevertheless slower. The decisive full result is retained at
`research/results/20260801T052534.531839Z`. Three interleaved repetitions of
each 80-million-input workload produced:

| workload | current U32Map | parallel keys | change |
| --- | ---: | ---: | ---: |
| counting | 50.4 ns/input | 53.0 ns/input | +5.2% |
| mixed | 84.6 ns/input | 90.4 ns/input | +6.9% |

All repetitions ended at the same sizes and checksums. The earlier
five-repeat 20-million-input screen at
`research/results/20260801T052442.567540Z` was also negative: +8.4% counting
and +7.9% mixed. The million-operation differential test and combined ASan
and UBSan run passed; that evidence is retained with the initial result at
`research/results/20260801T052356.209891Z`.

The current record layout gives counting a benefit the instruction sample did
not show clearly: after comparing the key, the adapter mutates the adjacent
value in the same eight-byte record. Parallel keys remove the address
dependency but make the operation touch both the key array and value-record
array. They also add a key load and store to every Robin Hood swap and every
back-shifted deletion slot. The full mixed workload performs 45.5 million
reinsert swaps and 73.4 million back-shifts, so that extra traffic is not
rare.

Median peak memory was essentially unchanged for counting: 798.2 MiB current
versus 805.5 MiB parallel. The parallel layout reduced the mixed run from
521.2 MiB to 408.1 MiB because its reusable records contain values only, but
the speed cost disqualifies it as the benchmark default. The working variant
remains named `parallel-keys` in `research.py`; the current U32Map remains
unchanged.

## Returning the record found by get-or-insert

Five retained variants test the apparently redundant work after
`get_or_insert_hashed`: the normal API returns a slot iterator and the
counting adapter then calls `value`, which reads the slot again to recover
the record index. None improves both udb3 workloads, so none is the default.

The direct-result version returns a value pointer, slot iterator, and
insertion flag in one 16-byte result. At the full 80-million-input scale it
improved counting but made mixed operations slower:

| workload | current U32Map | direct result | change |
| --- | ---: | ---: | ---: |
| counting | 46.4 ns/input | 44.8 ns/input | -3.4% |
| mixed | 74.3 ns/input | 76.6 ns/input | +3.1% |

That result is retained at
`research/results/20260801T131351.369926Z`. All size and checksum checkpoints
matched.

The out-value version preserves the iterator return and optionally writes the
value pointer through a caller argument. At 20 million inputs it improved
counting from 36.7 to 35.9 ns/input (-2.2%), but slowed mixed operations from
48.3 to 49.9 ns/input (+3.3%). Its result is retained at
`research/results/20260801T132158.642515Z`.

The split-result version gives counting its own value-returning entry point
while mixed operations keep the old one. At 20 million inputs counting
improved from 41.7 to 40.0 ns/input (-4.1%), but mixed operations slowed from
57.7 to 60.4 ns/input (+4.7%). Its result is retained at
`research/results/20260801T131850.832181Z`.

The compact-result version returns an eight-byte `(slot, record)` pair and
uses the high record bit for the insertion flag. The record-index limit is
checked before setting that bit. Even after making the flag check inline, its
million-input screen was 2.3% slower counting and 1.7% slower mixed. That
result is retained at `research/results/20260801T132847.046518Z`.

Finally, the record-iterator version keeps the original insertion-flag
argument and adds the already-found record index to the iterator. At 20
million inputs it was 1.1% slower counting and 3.2% slower mixed:

| workload | current U32Map | record iterator | change |
| --- | ---: | ---: | ---: |
| counting | 38.1 ns/input | 38.5 ns/input | +1.1% |
| mixed | 50.0 ns/input | 51.6 ns/input | +3.2% |

The five repetitions, matching final sizes and checksums, generated source,
and assembly are retained at
`research/results/20260801T133014.235252Z`. Its randomized differential test
and combined ASan and UBSan run passed.

These experiments confirm the sampling result: the returned-value accessor
is real work, but it is too small to pay for a wider result or an additional
conditional output. The working `direct-result`, `split-result`, `out-value`,
`compact-result`, and `record-iterator` variants remain available in
`research.py`; `u32-map.x` remains unchanged.

## MapStringString easy-win closeout

The 2026-08-08 follow-up tested production Map changes against the clean
four-byte-hash implementation at `37ded883`. Five identical-binary full
Jackson pairs measured 4.15% median absolute drift for growing String
insertion, so a candidate needed at least 8.30% improvement and four faster
pairs out of five.

The earlier one-byte replacement was already disqualified: full Jackson
insertion rose from 100.264 to 133.728 ns (+33.4%), and reducing exact hashes
to two fingerprint bits let distinct structurally equal Array keys collapse
in ordinary Map. A later correctness repair did not change the String result.

Three clean-baseline candidates were measured independently:

| candidate | median insertion change | faster pairs | decision |
| --- | ---: | ---: | --- |
| outline absent insertion from the shared probe | +1.1% | 2/5 | reject |
| retain full hashes and add byte probe metadata | +7.1% | 0/5 | reject |
| read cached String hashes directly and test identity before content | +0.1% | 2/5 | reject |

The String-specific hooks improved replacement by a paired median 17.2%,
existing lookup by 13.1%, missing lookup by 6.0%, and erasure by 11.4% to
15.9%. They were nevertheless removed because growing insertion, the agreed
primary result, did not improve. No losing candidate was combined or applied
to production.

The uncontended final full Jackson result is
`jackson/results/20260808T213222Z-full-string-fixed-policy`. MapStringString
growing insertion is 104.851 ns versus 40.044 for Boost, a remaining 2.62x
gap. The other final MapStringString results are 49.721 ns existing erase,
45.975 replacement, 28.392 missing erase, 32.008 existing lookup, 28.979
missing lookup, and 7.429 iteration.

The final standard udb3 result is
`results/20260808T213615.767760Z-full`; all 176 checkpoint sizes and checksums
matched. Production Map is 146.0 ns/input and 64.78 B/entry counting, then
107.5 ns/input and 58.23 B/entry mixed. MapIntInt is 69.8 ns/input and 48.40
B/entry counting, then 56.7 ns/input and 43.70 B/entry mixed. The fastest
cohort results are 21.0 ns/input counting and 33.1 mixed.

This closes the algorithm-preserving, shared-generator easy-win search for
growing String insertion. Closing the remaining gap requires a different
table algorithm or a capacity-policy change, not another metadata encoding or
call-boundary adjustment.
