#include "x2c.x"
#include "meta.x"

/* Names resolve where an expansion lands; names a macro body writes are
   private to its expansion, including in definitions nested inside it. */
static int target = 10;
static int k = 100;
static int temp = 100;

/* A `using` name keeps the file-scope declaration even when forwarded
   through another macro, whatever other macros read the same name. */
macro Expression $free_target() => target;
macro Expression $kept() using target => target;
macro Expression $id(Expr $e) => $e;

/* The caller's `k * 2` reads the loop variable declared from the caller's
   own Name `k`, as it would where the expansion lands. */
macro Stmt $repeat(Name $i, Expr $count, Expr $value, Name $sum) {
  for (int $i = 0; $i < $count; $i++) $sum += $value;
}

/* A local macro or Macro value written inside a template reads that
   template's private names. */
macro Expression $nested_local() => ({
  int temp = 7;
  macro Expression read() => temp;
  read();
});
meta static List apply_child(Macro m) => m();
macro Expression $nested_value() => ({
  int temp = 7;
  $apply_child(macro Expression() => temp);
});

int main(void) {
  int total = 0;
  {
    int target = 20;
    printf("%d %d %d\n", $kept(), $id($kept()), $free_target());
  }
  $repeat(k, 3, k * 2, total);
  printf("%d %d\n", total, k);
  printf("%d %d %d\n", $nested_local(), $nested_value(), temp);
  return 0;
}
