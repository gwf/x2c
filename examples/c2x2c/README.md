# c2x2c

Eight versions of a word-frequency program, from native C to parallel
directory counting. These files are the canonical tutorial sources.
[versions.json](versions.json) supplies their order and labels to the
[source viewer](../../tools/version-viewer/README.md).

| Version | Lines | Change |
| --- | ---: | --- |
| [0](words-v0.c) | 164 | Native C: explicit hash table, allocation, sorting, and cleanup. |
| [1](words-v1.x) | 139 | Scope allocation, pointer member access with dots, and defer. |
| [2](words-v2.x) | 102 | Substr word views and whole-file reading; retain the explicit hash table. |
| [3](words-v3.x) | 97 | Bounded Array min-heap of `(count word)` Lists and typed destructured printing. |
| [4](words-v4.x) | 42 | A native Substr count map and mixed-type foreach replace the explicit table traversal. |
| [5](words-v5.x) | 34 | One file counting function; interpolated output. |
| [6](words-v6.x) | 49 | Recursive directory traversal; merge native per-file count maps into MapStringInt. |
| [7](words-v7.x) | 49 | Four persistent workers return native count maps; the caller converts keys and merges. |

Line counts include comments. The viewer hides comments and calculates its
diffs and displayed line numbers from that representation.

## Build and run

Run these commands from the repository root after building the local compiler.
Version 0 uses the host C compiler. Versions 1-7 need the compiler and runtime
additions saved with this tutorial; an older installed x2c is insufficient.

```sh
cc -std=gnu11 examples/c2x2c/words-v0.c -o /tmp/c2x2c-v0
/tmp/c2x2c-v0 docs/src/index.md

builds/0/x2c build -I lib examples/c2x2c/words-v2.x lib/substring.x \
  --output /tmp/c2x2c-v2 --build-dir /tmp/c2x2c-v2-build
/tmp/c2x2c-v2 docs/src/index.md

builds/0/x2c build -I lib examples/c2x2c/words-v5.x \
  lib/substring.x lib/substring-map.x \
  --output /tmp/c2x2c-v5 --build-dir /tmp/c2x2c-v5-build
/tmp/c2x2c-v5 docs/src/index.md

builds/0/x2c build -I lib examples/c2x2c/words-v7.x \
  lib/substring.x lib/substring-map.x \
  --output /tmp/c2x2c-v7 --build-dir /tmp/c2x2c-v7-build
/tmp/c2x2c-v7 docs/src
```

Substitute Version 3 in the Version 2 commands, Version 4 in the Version 5
commands, or Version 6 in the Version 7 commands. Version 1 needs neither
Substring source file. Versions 0-5 accept one file; Versions 6-7 accept one
directory. The file input is the book introduction. The directory input covers
the complete book source tree, including the generated library reference and
syntax files, without scanning rendered book output.

For a small alternative, `input/sample.txt` and `input/` retain the original
fixture: one file and one nested file. Versions 0-2 print that file as
`2 alpha`, `1 beta`, `1 gamma`, with tabs between columns. Versions 3-5 print
`1 beta`, `1 gamma`, `2 alpha`. Versions 6-7 print `1 delta`, `1 gamma`,
`2 alpha`, `2 beta` for that directory.

The seven x2c stages use `probe|none` in the existing example manifest.
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
independent totals.

```sh
cc -std=gnu11 -O2 examples/c2x2c/words-v0.c -o /tmp/c2x2c-v0
cc -std=gnu11 -O2 examples/c2x2c/words-v0-aggregate.c -o /tmp/c2x2c-v0-aggregate
examples/c2x2c/bench-directory.sh per-file /tmp/c2x2c-v0 docs > /dev/null
examples/c2x2c/bench-directory.sh aggregate /tmp/c2x2c-v0-aggregate docs
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
`file_unique_words` and `dir_unique_words` return Maps with unique word keys
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
traversal. `strings()` converts unique keys into a canonical String-keyed Map
for file results in Version 5. Versions 6-7 return `MapSubInt` directly.
Their shared `MapStringInt` accumulator materializes word Strings while merging
and releases each consumed count table. Ranking traverses typed String/int
bindings. In Version 7, the existing typed-Map publication
and context-export pattern transfers the table and preserves its views'
source Strings. Versions 6 and 7 differ only in using `map` or `parallel_map`.

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

Versions 6-7 validate the root directory. `Path.walk` includes hidden entries,
skips unreadable child directories, and does not traverse child directory
symlinks. An explicit root directory symlink is accepted. `Path.is_file`
follows file symlinks. Unreadable files still raise.

Version 7 retains this exact chain:

```x2c
return root.walk().filter(Path.is_file).parallel_map(file_unique_words, 4)
  .foldl({}, accumulate);
```

`parallel_map` starts no work until `foldl` consumes it. The fold starts up
to four native threads and reuses them. Each worker holds at most one running
job or unread result. The caller alone traverses the source and accumulates
results in completion-queue order. Each job exports a separate result Scope
and pool before that worker receives another input. Cleanup joins workers
on success or failure and waits for callbacks; it does not cancel them.

The source iterator and borrowed input graphs must remain alive through use.
Inputs are read-only; worker output uses fresh Maps. Keep temporary iterator
chains and their consuming fold in one full expression. A saved ParallelMap
description needs named iterator storage that outlives its fold.

## Verification

After normalizing names and filter order, all eight versions compiled and
matched independently calculated word frequencies on the documentation inputs.
Versions 0-5 used `docs/src/index.md`; Versions 6-7 used all 160 files then
present under `docs/src/` and produced identical output. Sorting and memory
lifetimes remain unchanged.

The original persistent-worker implementation passed 13 focused tests with 77
assertions. Four ParallelMap tests account for 47 assertions, including 16
jobs on four reused threads, blocked-worker progress, result lifetime, and
worker/source/accumulator failure cleanup. V7 matched V6 and independently
calculated output on 17 nested files and an empty directory.

The original delivery refreshed bootstrap and rebuilt the compiler from it.
The focused suites and V7 fixture passed with that rebuilt compiler. Broad
publication gates were waived for that delivery. See the
[continuation note](../../plans/c2x2c-continuation.md) before further thread API
design; the waiver does not establish a standing validation policy.
