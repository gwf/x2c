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

meta int fall_through(int n) {
  int count = 0;
  {
    defer count += 10;
    count += n;
  }
  return count;
}

meta int early_return(int n) {
  int count = 0;
  {
    defer cleanups += 1;
    if (n > 2) return n * 100;
    count = n;
  }
  return count;
}

meta int cleanups_run(int offset) => cleanups + offset;

meta int loop_exits(int n) {
  int total = 0;
  for (int i = 0; i < n; i++) {
    defer total += 1;
    if (i == 3) continue;
    if (i == 7) break;
    total += 100;
  }
  return total;
}

/* The return value is computed before either cleanup runs. */
meta int nested_return(int n) {
  int t = 0;
  {
    defer t += 1;
    {
      defer t += 10;
      if (n) return t + 1000;
    }
  }
  return t;
}

meta int scoped(int n) {
  int r = 0;
  $scope() {
    Array a = [];
    a.push(n);
    a.push(n);
    r = (int) a.len() + n;
  }
  return r;
}

meta int let_restores(int n) {
  int r = n;
  $let(r, 5) { r = r + 1; }
  return r;
}

meta int retained(int n) {
  Array kept = [];
  kept.push(n);
  Scope.retain();
  Array scratch = [];
  scratch.push(n);
  Scope.release();
  return (int) kept.len() + n;
}

meta int many_turns(int n) {
  int total = 0;
  for (int i = 0; i < n; i++) {
    $scope() { total += 1; }
  }
  return total;
}

meta int auto_array(int n) {
  Array a = $auto([]);
  a.push(n);
  a.push(n);
  return (int) a.len() + n;
}

meta int auto_map(int n) {
  Map m = $auto({});
  m[<a>] = n;
  m[<b>] = n * 2;
  return (int) m.len() + m[<b>].int();
}

meta int auto_scope(int n) {
  Scope work = $auto(Scope.new_named("meta work"));
  Scope.push(&work);
  Array scratch = [n, n, n];
  Scope.pop();
  return (int) scratch.len() + n;
}

meta int deferred_free(int n) {
  Array a = [];
  defer a.free();
  a.push(n);
  return (int) a.len() * 10 + n;
}

meta int context_export(int n) {
  Array result = [];
  {
    Context c = Context.open();
    defer c.close();
    Array built = [];
    built.push(n);
    built.push(n + 1);
    result = c.export(built);
  }
  return (int) result.len() * 100 + result[1].int();
}

meta int context_round_trip(int n) {
  Context c = Context.open();
  Map built = {};
  built[<n>] = n;
  Map kept = c.export(built);
  c.close();
  return kept[<n>].int() + 1;
}

meta int named_scope(int n) {
  Scope work = Scope.new_named("named");
  Scope.push(&work);
  Array scratch = [];
  scratch.push(n);
  int count = (int) scratch.len();
  Scope.pop();
  Scope.destroy(work);
  return count + n;
}

meta int promoted(int n) {
  List kept = NULL;
  Scope work = Scope.new_named("promote");
  Scope.push(&work);
  List built = %($n (x y));
  kept = built.promote();
  Scope.pop();
  Scope.destroy(work);
  return kept.len() + kept.car().int();
}

meta int string_free(int n) {
  String s = String.new("abcdef");
  int len = s.len();
  s.free();
  return len + n;
}

/* A value written into a file-scope global outlives the region that was
   active when it was computed. */
meta static long wide = 0;
meta static Func chosen = NULL;

meta long wide_store(long n) {
  Scope.retain();
  wide = n * 1000000000L;
  Func f = %!(int a) => a * 3;
  chosen = f;
  Scope.release();
  Scope work = Scope.new_named("wide");
  Scope.push(&work);
  wide = wide + n;
  Scope.pop();
  Scope.destroy(work);
  return wide;
}

meta long wide_read(int n) => wide + chosen(n);

/* Destructured locals that a cleanup names hold cells, as declared ones do,
   inside a loop body as well as in straight-line code. */
meta int destructured(int n) {
  int total = 0;
  {
    Var (a, b) = [n, n + 1];
    defer total += a.int() * 10 + b.int();
    total += 1000;
  }
  return total;
}

meta int destructured_loop(int n) {
  int total = 0;
  List pair = %(3 4);
  for (int i = 0; i < n; i++) {
    Var (a, b) = pair;
    defer total += a.int() * 10 + b.int() + i;
    if (i == 2) continue;
  }
  return total;
}

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
