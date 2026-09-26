/*  meta-cleanup-exits.x -- cleanups on every exit from a meta body

    A block that holds a cleanup keeps its boundary: `defer`, `$scope`, and
    `$let` run their cleanup when the block ends, when a `return` leaves it
    after computing its value, and when `break` or `continue` leaves it for
    an enclosing loop. A loop with a cleanup on its iteration path runs
    10,000 turns in constant space. The bound lifetime operations - `$auto`,
    `free`, `Context` export, named Scopes, and `List.promote` - run as they
    do natively. Each probe prints its compile-time and run-time answers.
*/

#include "x2c.x"

meta static int cleanups = 0;

$(import "meta-cleanup-exits.xmacro")

/* A value written into a file-scope global outlives the region that was
   active when it was computed. */
meta static long wide = 0;
meta static Func chosen = NULL;

int main(int argc, char **argv) {
  (void) argv;
  int offset = argc - 1;
  printf("%d %d\n", $fall_through(3), fall_through(3 + offset));
  printf("%d %d\n", $early_return(1), early_return(1 + offset));
  printf("%d %d\n", $early_return(5), early_return(5 + offset));
  printf("%d\n", $cleanups_run(0));
  printf("%d %d\n", $loop_exits(20), loop_exits(20 + offset));
  printf("%d %d\n", $nested_return(0), nested_return(offset));
  printf("%d %d\n", $nested_return(1), nested_return(1 + offset));
  printf("%d %d\n", $scoped(3), scoped(3 + offset));
  printf("%d %d\n", $let_restores(3), let_restores(3 + offset));
  printf("%d %d\n", $retained(4), retained(4 + offset));
  printf("%d %d\n", $many_turns(10000), many_turns(10000 + offset));
  printf("%d %d\n", $auto_array(4), auto_array(4 + offset));
  printf("%d %d\n", $auto_map(4), auto_map(4 + offset));
  printf("%d %d\n", $auto_scope(4), auto_scope(4 + offset));
  printf("%d %d\n", $deferred_free(4), deferred_free(4 + offset));
  printf("%d %d\n", $context_export(4), context_export(4 + offset));
  printf("%d %d\n", $context_round_trip(4), context_round_trip(4 + offset));
  printf("%d %d\n", $named_scope(4), named_scope(4 + offset));
  printf("%d %d\n", $promoted(4), promoted(4 + offset));
  printf("%d %d\n", $string_free(4), string_free(4 + offset));
  printf("%ld %ld\n", $wide_store(3), wide_store(3 + offset));
  printf("%ld %ld\n", $wide_read(5), wide_read(5 + offset));
  printf("%d %d\n", $destructured(4), destructured(4 + offset));
  printf("%d %d\n", $destructured_loop(5), destructured_loop(5 + offset));
  return 0;
}
