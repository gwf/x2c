# c2x2c

Nine versions of a word-frequency program, from native C to a reusable
parallel directory-counting API. These files are the canonical tutorial sources.
[versions.json](versions.json) supplies their order and labels to the
[source viewer](../../tools/version-viewer/README.md).

| Version | Lines | Change |
| --- | ---: | --- |
| [0](words-v0.c) | 183 | Native C: explicit hash table, allocation, sorting, and cleanup. |
| [1](words-v1.x) | 143 | Scope allocation, required references, pointer member access with dots, and defer. |
| [2](words-v2.x) | 108 | Substr word views and whole-file reading; retain the explicit hash table. |
| [3](words-v3.x) | 101 | Bounded Array min-heap of `(count word)` Lists and typed destructured printing. |
| [4](words-v4.x) | 44 | A native Substr count map and mixed-type foreach replace the explicit table traversal. |
| [5](words-v5.x) | 42 | One file counting function; interpolated output. |
| [6](words-v6.x) | 59 | A file or recursive directory traversal; merge native per-file count maps into MapStringInt. |
| [7](words-v7.x) | 59 | Four persistent workers for directories; a single file runs directly. |
| [8](words-v8.x) | 103 | A Frequencies class with Path.frequencies and top(k); counting and ranking move into a reusable module. Includes frequencies.x. |

Line counts include comments. The viewer hides comments and calculates its
diffs and displayed line numbers from that representation.

Versions 1-3 borrow each `Counts` object through required reference parameters.
Callers pass the object directly; the compiler supplies its address. Version 4
uses an expression body for its forwarding function. Version 6 gives the
file-counting callback its concrete `Path` input and `MapSubInt` result; `map`
adapts that typed function through `Func`. Versions 7-8 retain the `Var` callback
required by the parallel worker API. Evaluated `$(...)` Lists carry the
computed ranking pairs.

## Version 8: a reusable API

[frequencies.x](frequencies.x) defines `class Frequencies MapStringInt` and
`Frequencies Path.frequencies(Path root)`. `Frequencies.top(k)` returns a
sorted List of up to k `(count word)` pairs. The driver handles arguments,
reports errors, and prints the pairs from `root.frequencies().top(10)`.
The module counts one file directly or a directory recursively using four
workers, with the same normalization and ranking results as V7. Invalid roots
raise `bad-arg` rather than terminating the calling program directly.

`top(k)` keeps the largest pairs, then returns them in ascending count and
word order. A nonpositive k returns an empty List. The temporary ranking
Array is freed; the returned List belongs to the caller's pool.

```sh
builds/0/x2c build -O2 -I lib examples/c2x2c/words-v8.x \
  examples/c2x2c/frequencies.x --output /tmp/c2x2c-v8 \
  --build-dir /tmp/c2x2c-v8-build
/tmp/c2x2c-v8 docs/src
/tmp/c2x2c-v8 site/public/llms-full.txt
```

Include `frequencies.x` and compile that source alongside another program to
use the API independently. The viewer appends the module after the V8 driver
so both parts remain visible in the version comparison. The driver catches
API errors, reports the cause and details to stderr, and exits with failure.

Earlier stages rely on the implicit top-level lifetime and shutdown cleanup
for remaining allocations. V8 creates its result in the caller's Scope, then
retains a temporary Scope and opens one temporary String pool. One deferred
block releases the pool and Scope, and releases an unfinished result on failure.
Directory paths are collected into a List before the pool is explicitly
detached, restoring the caller's active pool.
Directory enumeration completes before parallel counting starts.

`parallel_map_in` borrows the same temporary pool for all worker callbacks.
Each worker returns its MapSubInt for the caller to read while the worker is
parked. The reducer uses V7's `add_substr` to intern final words in the
caller's active pool. Existing worker scopes reclaim per-file maps, without
explicit map cleanup in the reducer. A single file runs directly in the
temporary pool before detachment. The operation releases its one temporary
pool and Scope after workers finish, including on errors. No per-file pools,
pool finalizers, or Context are needed. Temporary file text remains until
the operation ends; sharing the pool may introduce interning contention.

The returned map and its keys have the caller's Scope and pool lifetimes.
No context export, graph traversal, or table rebuild is needed. If the
operation fails, the unfinished result is released as well. Iteration uses
MapStringInt's native typed cursor internally; the public count result remains
Frequencies.

## Build and run

Run these commands from the repository root after building the local compiler.
Version 0 uses the host C compiler. Versions 1-8 need the compiler and runtime
additions saved with this tutorial; an older installed x2c is insufficient.

```sh
cc -std=gnu11 examples/c2x2c/words-v0.c -o /tmp/c2x2c-v0
/tmp/c2x2c-v0 docs/src/index.md

builds/0/x2c build -I lib examples/c2x2c/words-v2.x \
  --output /tmp/c2x2c-v2 --build-dir /tmp/c2x2c-v2-build
/tmp/c2x2c-v2 docs/src/index.md

builds/0/x2c build -I lib examples/c2x2c/words-v5.x \
  --output /tmp/c2x2c-v5 --build-dir /tmp/c2x2c-v5-build
/tmp/c2x2c-v5 docs/src/index.md

builds/0/x2c build -I lib examples/c2x2c/words-v7.x \
  --output /tmp/c2x2c-v7 --build-dir /tmp/c2x2c-v7-build
/tmp/c2x2c-v7 docs/src
```

Substitute Version 1 or 3 in the Version 2 commands, Version 4 in the
Version 5 commands, or Version 6 in the Version 7 commands. Versions 0-5
accept one file; Versions 6-8 accept one file or directory. The file input
is the book introduction. The directory input covers the complete book
source tree, including the generated library reference and syntax files,
without scanning rendered book output.

For a small alternative, `input/sample.txt` and `input/` retain the original
fixture: one file and one nested file. Versions 0-2 print that file as
`2 alpha`, `1 beta`, `1 gamma`, with tabs between columns. Versions 3-5 print
`1 beta`, `1 gamma`, `2 alpha`. Versions 6-7 print `1 delta`, `1 gamma`,
`2 alpha`, `2 beta` for that directory.

The eight x2c stages use `probe|none` in the existing example manifest.
This preserves manual tutorial checks without adding recurring build work.
The native C stage is outside that manifest's `.x`/`.xp` source contract.

## Manual directory baselines

The directory benchmark has two C baselines, separate from the eight tutorial
stages. [words-v0-aggregate.c](words-v0-aggregate.c) reuses V0's counting code,
accepts named files, and accumulates one total before printing. It retains one
count table and reuses one line buffer across files. V0 itself is unchanged.

[bench-directory.sh](bench-directory.sh) supplies the same file set as
Versions 6-7, including file symlinks but not child directory symlinks.
`per-file` pipes `find` to `xargs` and launches V0 once per file, producing
separate rankings without directory totals. `aggregate` collects the paths
from `find` and executes the C aggregate program once. The native argument
limit can reject an oversized file list; the driver never splits it into
independent totals. The driver also accepts a single file in either mode;
the aggregate C executable already accepts one or more named files directly.

```sh
cc -std=gnu11 -O2 examples/c2x2c/words-v0.c -o /tmp/c2x2c-v0
cc -std=gnu11 -O2 examples/c2x2c/words-v0-aggregate.c -o /tmp/c2x2c-v0-aggregate
examples/c2x2c/bench-directory.sh per-file /tmp/c2x2c-v0 docs > /dev/null
examples/c2x2c/bench-directory.sh aggregate /tmp/c2x2c-v0-aggregate docs
/tmp/c2x2c-v0-aggregate site/public/llms-full.txt
```

Time the complete driver command, including discovery and process startup.
The aggregate C run is the primary directory baseline because it counts the
same words into one total. Keep the per-file run labeled separately because
it launches many processes and does not merge counts. The C aggregate prints
V0's ordering; Versions 6-7 retain their existing ordering. These are manual
benchmarks, with no recurring test or gate.

## Behavior and assumptions

Every word's aggregate count must fit in `int`, including across files.
There are no word-count overflow checks. Native allocation-size guards remain
in the early stages. Versions 0-1 classify punctuation with C's current
locale. Versions 2-7 reject a fixed ASCII punctuation set. All versions
remove punctuation before lowercasing with C's current locale; the programs
do not change it.
`count_words` and `path_unique_words` return Maps with unique word keys
and occurrence counts as values.

Versions 2-7 use `lib/substring.x`. A `Substr` (also named `Substring`) is a
borrowed immutable view containing a source String, byte offset, and length.
Hashing, comparison, and word traversal allocate nothing. `.str()` and
`.string()` materialize the same canonical String. The source must remain
alive and unchanged through the view's final use. Each version reads and
normalizes the whole file once. `foreach (Substr word in text)` selects the
view type's native `try_next` cursor without an iterator descriptor or boxing.

Versions 2-3 retain the explicit table with Substr keys. Version 2 materializes
only the ten output words. Versions 3-4 skip String conversion when a word's
count falls below the current top-ten cutoff.
Versions 4-7 use `MapSubInt` from `lib/substring-map.x`. This count table
reuses the runtime's Map storage, probing, and growth templates. `increment`
copies only a view on insertion. Version 4 uses
`foreach ((Substr word, int count) in counts)` for native, allocation-free
traversal. Versions 5-7 return `MapSubInt` directly, preserving borrowed keys
and native Substr/int iteration.
Their shared `MapStringInt` accumulator looks up borrowed word bytes and
materializes a String only when inserting a new word. It merges
and releases each consumed count table. Ranking traverses typed String/int
bindings. Version 7 borrows the table while its worker waits for accumulation
to finish; no automatic result export is needed. Its source Strings use the
shared canonical pool. Version 7 replaces `map` with `parallel_map` and uses
its required `Var` callback signature.

Versions 0-2 print descending counts with ascending word ties. Versions 3-7
keep the largest ten `(count word)` tuples in an Array min-heap. Once the
heap has ten entries, words below its minimum count are skipped before
constructing a tuple. Equal-count candidates still enter the heap so word
order decides tied cutoffs. The retained tuples are sorted and printed in
ascending tuple order. Ranking retains at most ten tuples between candidates
and temporarily eleven before removing the smallest. Substr counting and
per-file Maps still retain all unique words.

Versions 2-7 read and transform the whole file before counting. File read
failures raise; close status is ignored. No stage adds stdout flush or error checks.

Versions 6-7 count a file directly, or validate and traverse a root directory.
`Path.walk` includes hidden entries,
skips unreadable child directories, and does not traverse child directory
symlinks. An explicit root directory symlink is accepted. `Path.is_file`
follows file symlinks. Unreadable files still raise.

Version 7 retains this exact chain:

```x2c
return root.walk().filter(Path.is_file).parallel_map(count_words, 4)
  .foldl({}, accumulate);
```

`parallel_map` starts no work until `foldl` consumes it. The fold starts up
to four native threads and reuses them. Each worker holds at most one running
job or unread result. The caller alone traverses the source and accumulates
results in completion-queue order. A worker keeps its temporary Map alive
until the reducer finishes reading it. This reducer merges counts into the
caller-owned `MapStringInt` and retains no worker-owned storage, so no ownership
transfer is needed. Canonical words use the shared pool. Cleanup requests
cooperative stop on all workers before joining; arbitrary native I/O is not
interrupted.

The source iterator and borrowed input graphs must remain alive through use.
Inputs are read-only; worker output uses fresh Maps. Keep temporary iterator
chains and their consuming fold in one full expression. A saved ParallelMap
description needs named iterator storage that outlives its fold.

## Verification

`unittest/test-substring.x` covers checked spans, canonical conversion,
allocation-free typed traversal, native count-table growth and export, and
String-keyed accumulation that materializes only missing keys.
`unittest/compiler-fixtures/foreach-typed-cursors.x` checks mixed binding
types, aliases, one-time source evaluation, and destructuring sorted tuples.

The tutorial programs remain manual probes in `examples/manifest.txt`.
For one-off timing comparisons, build all versions with the same optimization
level and compare their output against independently calculated frequencies.
Use `site/public/llms-full.txt` for Versions 0-5 and the same `docs` hierarchy
for Versions 6-7 and the aggregate C driver. The C baseline and later stages
print their top ten in different orders, as described above.
