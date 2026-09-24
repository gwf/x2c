/* The pure Json, Diff, and Path operations give the same results in
   compile-time `meta` code as at run time. */

#include "json.x"
#include "diff.x"

meta String pure_results(void) {
  Path path = "/usr/lib/notes.tar.gz";
  List edits = Diff.lines("a\nb\n", "a\nc\n");
  return %"${Json.parse("{\"a\": [1, 2.5, \"x\"]}").repr()}\n" +
         %"${Path.join("usr", "lib")} ${path.dirname()} ${path.basename()} " +
         %"${path.extension()} ${path.stem()}\n${edits.repr()}\n" +
         %"${Diff.unified("a\nb\n", "a\nc\n", "old", "new")}";
}

int main(void) {
  String native = pure_results();
  String meta = $pure_results();
  printf("%s%s\n", (char *) meta, native == meta ? "same" : "different");
  return 0;
}
