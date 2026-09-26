/* The pure Json, Diff, and Path operations give the same results in
   compile-time `meta` code as at run time. */

#include "json.x"
#include "diff.x"

$(import "meta-native-pure-modules.xmacro")

int main(void) {
  String native = pure_results();
  String meta = $pure_results();
  printf("%s%s\n", (char *) meta, native == meta ? "same" : "different");
  return 0;
}
