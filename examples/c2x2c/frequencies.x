/*  frequencies.x -- reusable parallel word frequencies

    Uses one temporary String pool for traversal and all worker text.
    Accumulates directly into caller-owned storage without context export.
*/

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
  Scope.retain();
  Pool work = Pool.open();
  int complete = 0;
  defer {
    if (Pool.current() == work) Pool.detach();
    work.release();
    Scope.release();
    if (!complete) result.cleanup();
  }

  if (root.is_dir()) {
    List files = root.walk().filter(Path.is_file);
    Pool.detach();
    files.iter().parallel_map_in(work, count_words, 4).foldl(result, accumulate);
  }
  else if (root.is_file()) {
    MapSubInt counts = count_words(root);
    Pool.detach();
    accumulate(result, counts);
  }
  else
    raise %(bad-arg (operation "Path.frequencies") (path $root));
  complete = 1;
  return result;
}

/** Returns up to k (count word) pairs, sorted by ascending count and word.
    Keeps the largest pairs, matching the earlier examples' tie ordering.
    A nonpositive k returns an empty List. The caller's pool owns the result.
*/
List Frequencies.top(Frequencies self, int k) {
  if (k <= 0) return NULL;
  MapStringInt counts = self;
  Array ranked = $auto([]);
  foreach ((String word, int count) in counts) {
    if (ranked.len() == k && count < ranked[0][0]) continue;
    ranked.heap_push(%($count $word));
    if (ranked.len() > k) ranked.heap_pop();
  }
  return ranked.sort();
}

static Var count_words(Var filename) {
  String text = filename.string().open("r").string_close()
    .reject("!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~").lower();
  MapSubInt counts = MapSubInt.new();
  foreach (Substr word in text)
    counts.increment(word);
  return counts;
}

static MapStringInt accumulate(MapStringInt total, MapSubInt counts) {
  foreach ((Substr word, int count) in counts) total.add_substr(word, count);
  return total;
}
