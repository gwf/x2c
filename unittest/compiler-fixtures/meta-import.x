/*  meta-import.x -- a macro whose implementation arrives with the import

    `meta-import-defs.xmacro` declares `meta static` functions beside the
    macros that call them. Importing it installs their compile-time forms in
    this unit's macro session and emits their definitions here, so the first
    column below is what x2c computed during translation and the second is
    what the same bodies compute at run time. See `plans/meta-functions.md`.
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
  printf("flatten  %s\n", mi_flatten("one.two", "-"));
  return 0;
}
