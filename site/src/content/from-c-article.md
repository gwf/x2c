A word-frequency program has a short job description: read some text, count the words, and print the ten most frequent. In C, that also means choosing storage for the words, growing a hash table, sorting its entries, and releasing everything afterward.

We will start with a working C implementation and rewrite it in eight steps. The first five count one file. The last three add directories, parallel work, and a reusable API.

Here's the direction that we're going:

```x2c
~#include "substring-map.x"
static MapSubInt count_words(String filename) {
  String text = filename.open("r").string_close()
    .reject("!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~").lower();
  MapSubInt counts = MapSubInt.new();
  foreach (Substr word in text)
    counts.increment(word);
  return counts;
}
```

This is the core of the word-counting algorithm rewritten in x2c: read a file, remove punctuation, lowercase the text, and count each word. It returns the counts; the rest of the program selects and prints the ten most frequent. By V5, the complete single-file program takes 42 lines, including comments and blank lines, down from the C baseline's 183.

<h2 id="baseline">V0: Start with a working program</h2>

The baseline reads one file with `getline`. It splits each line into whitespace-separated words, removes punctuation, and lowercases what remains. A chained hash table stores one copied string and an integer count for each distinct word. Finally, the program gathers pointers to all entries, sorts them with `qsort`, prints ten, and frees its storage.

Those 183 lines include two structures and ten helper functions, handling allocation, hashing, table growth, normalization, comparison, errors, and cleanup. [Read the C baseline.](https://github.com/gwf/x2c/blob/main/examples/c2x2c/words-v0.c)

These are whitespace-delimited words with punctuation removed, not linguistic tokens. `don't` becomes `dont`; `well-known` becomes `wellknown`. Every aggregate count must fit in an `int`.

<h2 id="v1">V1: Stop writing the cleanup walk</h2>

In C, allocating the word table also commits us to writing its cleanup: walk every bucket, visit every entry, free each copied word, free each entry, and finally free the buckets. Add another allocation, and we must remember to add its matching cleanup.

**Switch to x2c's replacement allocators, and that bookkeeping is done for us.** `xmalloc` and `xcalloc` record each allocation. `xrealloc` keeps track of a block when it is resized or moved. The runtime can then release the entire group in one operation, without our program walking its data structures to find everything it allocated.

x2c calls that group a **Scope**. If we need the memory released before the program ends, we can bracket the work with `Scope.open()` and `Scope.close()`. The close call releases every allocation still in that group. Writing `auto { ... }` is the block form of that same open-and-close pair: it opens the group on entry and closes it automatically when execution leaves the block, including on an early return or error.

V1 uses the default group, which the runtime cleans up at shutdown, so it does not even need those two calls.

The allocation sites remain familiar:

<!-- ignore: excerpt from examples/c2x2c/words-v1.x; it needs that program's declarations. -->
```x2c,ignore
Entry *entry = xcalloc(1, sizeof(*entry));
entry.word = xmemdup(word, strlen(word) + 1);
```

That is why we can delete `free_counts`, the function that walked and freed the table. We can also delete the separate cleanup for the sorting array. The table, copied words, and sorting array are all recorded already. We still use `xfree` to release an obsolete bucket array early when the table grows; the runtime removes that allocation from its records.

C library allocations are still C library allocations. `getline` allocates its own buffer, so we keep its native `free`, but put it beside the declaration instead of at the far end of the function:

```x2c
char *line = NULL;
defer free(line);
```

`defer` runs that cleanup when the function leaves. The resource and the promise to release it now appear together.

The hash table and counting algorithm have not changed. The program drops from **183 to 143 lines**, because it no longer has to remember and free its own allocation graph. The total reduction also includes smaller changes to declarations, error reporting, and the allocation wrapper. Allocation failures already raise an error, so a local wrapper that checks every allocation is unnecessary.

<h2 id="v2">V2: Read once, borrow the words</h2>

The next step removes another set of chores: managing a growable line buffer, checking how the read loop ended, and remembering to close the file. We ask the library to read the text instead:

<!-- ignore: excerpt from examples/c2x2c/words-v2.x; it needs that program's declarations. -->
```x2c,ignore
auto File input = File.open(argv[1], "r");
count_words(counts, input.string());
```

`auto` closes the file when execution leaves the surrounding block, including when an error leaves it. Reading failures raise an error instead of requiring a separate end-of-file check. Inside `count_words`, the library also handles removing punctuation, lowercasing, and finding each word:

<!-- ignore: excerpt from examples/c2x2c/words-v2.x; it needs that program's declarations. -->
```x2c,ignore
text = text.reject("!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~").lower();
foreach (Substr word in text)
  count_word(counts, word);
```

We also stop allocating a separate copy of each word. A `Substr` identifies where a word begins and ends in the text we already read. The table stores that small view; hashing and comparison read the original bytes. Keeping the original text alive and unchanged makes those copies unnecessary.

The manual token scanner, normalization loop, and hash function disappear. The explicit hash table remains. The program is now 108 lines.

This changes the storage tradeoff: the program reads and normalizes the whole file instead of streaming one line at a time. It also uses a fixed ASCII punctuation set; the C baseline uses `ispunct` in the current locale.

<h2 id="v3">V3: Rank only the candidates we need</h2>

We want ten results, but the previous versions allocate a sorting array for every distinct word. V3 replaces that array and its comparator with a min-heap of `(count word)` pairs:

<!-- ignore: excerpt from examples/c2x2c/words-v3.x; it needs that program's declarations. -->
```x2c,ignore
if (ranked.len() == 10 && entry.count < ranked[0][0]) continue;
ranked.heap_push($(entry.count, entry.word.str()));
if (ranked.len() > 10) ranked.heap_pop();
```

The smallest retained pair is at the front. Lower counts cannot qualify once ten candidates exist. The heap retains ten pairs and briefly holds eleven.

Only the retained pairs are sorted for output:

<!-- ignore: excerpt from examples/c2x2c/words-v3.x; it needs that program's declarations. -->
```x2c,ignore
foreach ((int count, String word) in ranked.sort())
  printf("%d\t%s\n", count, word);
```

The count table still contains every distinct word; only ranking storage is bounded. The source is now 101 lines.

This step deliberately changes ordering. V0-V2 print descending counts with ascending word ties. V3 onward retain the largest `(count word)` pairs and print them in ascending order. A tie at the tenth-place boundary can therefore select different words.

<h2 id="v4">V4: Remove the application's hash table</h2>

Our custom hash table is now doing a standard job: associate each word with a count. A library map can do that job, so we no longer need to maintain bucket sizes, resolve collisions, or move entries when the table grows:

```x2c
~#include "substring-map.x"
~int main(void) {
  MapSubInt counts = MapSubInt.new();
~  return 0;
~}
```

`MapSubInt` stores borrowed `Substr` keys and integer counts. Its `increment` operation replaces our insertion and lookup code. Its typed traversal replaces the nested bucket and entry loops:

<!-- ignore: excerpt from examples/c2x2c/words-v4.x; it needs that program's declarations. -->
```x2c,ignore
foreach ((Substr word, int count) in counts) {
  if (ranked.len() == 10 && count < ranked[0][0]) continue;
  ranked.heap_push($(count, word.str()));
  if (ranked.len() > 10) ranked.heap_pop();
}
```

The `Entry` and `Counts` structures disappear, along with table growth and collision handling. The map uses the runtime's existing table operations. The program drops from 101 to 44 lines.

<h2 id="v5">V5: Make counting one operation</h2>

This brings us to `count_words`, the function in the [opening example](#overview). V5 gathers file reading, normalization, and counting into one operation that takes a filename and returns a map of word counts. The caller no longer needs to arrange those steps or manage the intermediate text.

The driver can now say `print_top_ten(count_words(argv[1]))`: count, then print. Separating counting from ranking lets us reuse the same function for each file when we add directory support in V6. The one-line forwarding helper disappears, and output uses interpolation: `puts(%"$count\t$word")`.

At 42 lines, V5 is the shortest complete program in this sequence. It still reads one file and prints ten results. Next, we extend what it can do.

<h2 id="v6">V6: Count a directory</h2>

We already know how to count one file. To count a directory, we can reuse that function for each file and add the results. The library handles walking the directory and passing files through those steps, so we do not need to write a recursive directory walker:

<!-- ignore: excerpt from examples/c2x2c/words-v6.x; it needs that program's declarations. -->
```x2c,ignore
return root.walk().filter(Path.is_file).map(count_words)
  .foldl(MapStringInt.new(), accumulate);
```

The per-file maps keep their borrowed word views. The total uses String keys, because its words must remain usable after each per-file table is released:

<!-- ignore: excerpt from examples/c2x2c/words-v6.x; it needs that program's declarations. -->
```x2c,ignore
foreach ((Substr word, int count) in counts) total.add_substr(word, count);
counts.cleanup();
return total;
```

`add_substr` looks up the borrowed bytes and creates a String only when the total needs a new key. A single-file argument takes a direct path through the same count-and-merge operations. Directory traversal adds 17 lines, bringing the program to 59.

Traversal follows file symlinks, skips unreadable child directories, and does not descend through child directory symlinks. Unreadable files raise errors.

<h2 id="v7">V7: Run file counting in parallel</h2>

Files can be counted independently. We can keep the counting function and the merging step, and ask the library to run up to four file counts at once:

<!-- ignore: excerpt from examples/c2x2c/words-v7.x; it needs that program's declarations. -->
```x2c,ignore
return root.walk().filter(Path.is_file).parallel_map(count_words, 4)
  .foldl(MapStringInt.new(), accumulate);
```

The consuming fold starts up to four worker threads and reuses them across files. Each worker counts into its own map. The caller merges results as they become ready, while each worker keeps its result alive until the merge finishes.

The library handles starting and joining workers, handing out files, and keeping results alive until they have been merged. We do not write a work queue or thread-management code. The callback adopts the `Var` signature required by `parallel_map`; single-file input still runs directly. The program remains 59 lines.

Four workers do not promise a fourfold speedup. Directory size, file sizes, merging, and shared String storage all affect the result. We will measure elapsed time and total CPU time separately.

<h2 id="v8">V8: Return a result another program can use</h2>

So far, counting ends by printing to the terminal. Another program might instead want to display the results, save them, or ask for a different number of words. The final rewrite returns a usable result and lets the caller decide what happens next:

```x2c
~#include "typed-map.x"
class Frequencies MapStringInt;
```

`Path.frequencies()` counts a file or directory. `Frequencies.top(k)` returns up to `k` pairs instead of printing them. The driver shown at the start can choose ten results, format them, and report errors.

This step grows the code: a 27-line driver plus a 76-line module. A reusable operation cannot keep all of its temporary file contents until program shutdown. The module now releases that working storage before returning, while keeping the final counts and words available to its caller. Invalid paths report an error to the caller instead of terminating the process.

The extra lines define a reusable operation and its result lifetime, rather than relying on program shutdown for cleanup.
