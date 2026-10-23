/*  frequencies.x -- reusable parallel word frequencies

    Borrows per-file count maps while their private pools remain alive.
    Accumulates directly into caller-owned storage without context export.
*/

#pragma once
#include "substring-map.x"
#include "typed-map.x"
#include "path.x"

class Frequencies MapStringInt;

/** Counts one file, or normal files recursively under a directory.
    Directory counting uses four workers; a file needs no worker threads.
    Deletes ASCII punctuation before lowercasing. Counts must fit in int.
    Returns a map owned by the caller's Scope, with keys in the caller's pool.
    Intermediate storage is reclaimed before return. Raises on an invalid
    root or an unreadable file; traversal otherwise follows Path.walk.
*/
Frequencies Path.frequencies(Path root) {
  Frequencies result = Frequencies.new();
  int complete = 0;
  defer if (!complete) result.cleanup();
  Context context = $auto(Context.open_isolated());
  if (root.is_file())
    accumulate(result, count_words(root));
  else {
    if (!root.is_dir())
      raise %(bad-arg (operation "Path.frequencies") (path $root));
    root.walk().filter(Path.is_file).parallel_map(count_words, 4)
      .foldl(result, accumulate);
  }
  complete = 1;
  return result;
}

static Var count_words(Var filename) {
  // The callback Scope survives reduction; its finalizer releases this pool.
  Pool *lifetime = Scope.malloc_finalized(sizeof(Pool), release_pool);
  *lifetime = NULL;
  Pool.open();
  defer *lifetime = Pool.detach();
  String text = filename.string().open("r").string_close()
    .reject("!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~").lower();
  MapSubInt counts = MapSubInt.new();
  foreach (Substr word in text)
    counts.increment(word);
  return counts;
}

static void release_pool(void *allocation) {
  Pool *lifetime = allocation;
  (*lifetime).release();
}

static MapStringInt accumulate(MapStringInt total, MapSubInt counts) {
  Pool destination = Pool.current().up;
  foreach ((Substr word, int count) in counts) {
    String key = String.new_in(
      destination, word.source + word.offset, word.length);
    total[key] += count;
  }
  counts.cleanup();
  return total;
}
