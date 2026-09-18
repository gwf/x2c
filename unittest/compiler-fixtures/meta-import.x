/*  meta-import.x -- a macro whose implementation arrives with the import

    `meta-import-defs.xmacro` declares `meta` functions beside the macros that
    call them. Importing it installs their compile-time forms in this unit's
    macro session, so the first column below is what x2c computed during
    translation and the second is what the same bodies compute at run time.

    The generated C is part of what this fixture owns. This unit reaches
    `mi_constant`, `mi_accessor`, `mi_depth` and `mi_dashed` at run time, and
    `mi_flatten` through the first two, so it emits those five: the four
    `static` ones as its own copies and public `mi_flatten` as the program's
    one copy, exported by `meta-import.h`. `mi_tag` runs only during
    translation, so no definition of it is emitted. `meta-import-second.x`
    imports the same file and emits a different set. See
    `plans/meta-functions.md`.
*/

#include "x2c.x"

$(import "meta-import-defs.xmacro")

/* A second import of the same file contributes one copy of each definition,
   not two. */
$(import "meta-import-defs.xmacro")

int main(void) {
  printf("constant %s %s\n",
         $probe.constant(net.http.idle), mi_constant("net.http.idle"));
  printf("accessor %s %s\n",
         $probe.accessor(Net.Http), mi_accessor("Net.Http"));
  printf("depth    %d %d\n", $probe.depth(a.b.c), mi_depth("a.b.c"));
  /* `mi_dashed` comes from the import's own import. */
  printf("dashed   %s %s\n",
         $probe.dashed(net.http.idle), mi_dashed("net.http.idle"));
  /* `mi_tag` is called here only during translation. */
  printf("tag      %s\n", $probe.tag(net.http.idle));
  return 0;
}
