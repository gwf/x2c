/*  meta-import-second.x -- a second unit importing the same macro file

    This unit installs every compile-time form `meta-import-defs.xmacro`
    declares, and reaches only `mi_depth` and `mi_dashed` at run time, so its
    generated C defines those two and nothing else. In particular it emits no
    copy of public `mi_flatten`, which `meta-import.x` owns, so the two units
    link together. Its compile-time `mi_count` starts from the initializer,
    whatever the other unit counted. See `plans/meta-functions.md`.
*/

#include "x2c.x"

$(import "meta-import-defs.xmacro")

int main(void) {
  printf("depth  %d %d\n", $probe.depth(a.b.c.d), mi_depth("a.b.c.d"));
  printf("dashed %s %s\n", $probe.dashed(one.two), mi_dashed("one.two"));
  printf("tag    %s\n", $probe.tag(net.http));
  printf("next   %d\n", $probe.next());
  return 0;
}
