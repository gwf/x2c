# c2x2c

Eight versions of a word-frequency program, from native C to parallel
directory counting. These files are the canonical tutorial sources.
[versions.json](versions.json) supplies their order and labels to the
[source viewer](../../tools/version-viewer/README.md).

| Version | Lines | Change |
| --- | ---: | --- |
| [0](words-v0.c) | 164 | Native C: explicit hash table, allocation, sorting, and cleanup. |
| [1](words-v1.x) | 139 | Scope allocation, pointer member access with dots, and defer. |
| [2](words-v2.x) | 103 | Strings and File iteration; retain the explicit hash table. |
| [3](words-v3.x) | 93 | Array of `(count word)` Lists, built-in sorting, and destructured printing. |
| [4](words-v4.x) | 37 | Map replaces the hash table; an iterator chain builds the ranking Array. |
| [5](words-v5.x) | 28 | Whole-file reading and one counting function; interpolated output. |
| [6](words-v6.x) | 37 | Recursive directory traversal and sequential per-file Map merging. |
| [7](words-v7.x) | 37 | Four persistent workers count files; the caller merges ready results. |

Line counts include comments. The viewer hides comments and calculates its
diffs and displayed line numbers from that representation.

## Build and run

Run these commands from the repository root after building the local compiler.
Version 0 uses the host C compiler. Versions 1-7 need the compiler and runtime
additions saved with this tutorial; an older installed x2c is insufficient.

```sh
cc -std=gnu11 examples/c2x2c/words-v0.c -o /tmp/c2x2c-v0
/tmp/c2x2c-v0 docs/src/index.md

builds/0/x2c build examples/c2x2c/words-v5.x \
  --output /tmp/c2x2c-v5 --build-dir /tmp/c2x2c-v5-build
/tmp/c2x2c-v5 docs/src/index.md

builds/0/x2c build examples/c2x2c/words-v7.x \
  --output /tmp/c2x2c-v7 --build-dir /tmp/c2x2c-v7-build
/tmp/c2x2c-v7 docs/src
```

Substitute versions 1-4 in the Version 5 commands, or Version 6 in the
Version 7 commands. Versions 0-5 accept one file; Versions 6-7 accept one
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

## Behavior and assumptions

Every word's aggregate count must fit in `int`, including across files.
There are no word-count overflow checks. Native allocation-size guards remain
in the early stages. Classification uses C's current locale; the programs
do not change it. Punctuation is removed before text is lowercased.
`file_unique_words` and `dir_unique_words` return Maps with unique word keys
and occurrence counts as values.

Versions 0-2 print descending counts with ascending word ties. Versions 3-7
sort ascending `(count word)` tuples, take the last ten with `[-10:]`, and
print that selection in ascending tuple order. Equal-count cutoffs use the
tuple's word order. Map enumeration yields `(word count)`, so the ranking
chain retains `reverse()` to put the count first.

Version 5 reads and transforms the whole file before counting. Versions 6-7
retain that per-file memory tradeoff. File read failures raise; close status
is ignored. No stage adds stdout flush or error checks.

Versions 6-7 validate the root directory. `Path.walk` includes hidden entries,
skips unreadable child directories, and does not traverse child directory
symlinks. An explicit root directory symlink is accepted. `Path.is_file`
follows file symlinks. Unreadable files still raise.

Version 7 retains this exact chain:

```x2c
return root.walk().filter(Path.is_file).parallel_map(file_unique_words, 4)
  .foldl({}, %!(Map total, Map counts) => total.merge_with(counts,
    %!(int a, int b) => a + b));
```

`parallel_map` starts no work until `foldl` consumes it. The fold starts up
to four native threads and reuses them. Each worker holds at most one running
job or unread result. The caller alone traverses the source and accumulates
results in completion-queue order. A worker keeps its temporary Map alive
until the reducer finishes reading it. This reducer merges counts into the
caller-owned Map and retains no worker-owned storage, so no ownership transfer
is needed. Canonical words use the shared pool. Cleanup requests cooperative
stop on all workers before joining; arbitrary native I/O is not interrupted.

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
