#include "x2c.x"
#include "meta.x"

/* A meta function returns parsed try statements unchanged. A parsed catch
   arm already declares its binders, so binding it declares them once. */
meta static List same_items(List code) => %($code);
macro Stmt $same(Stmt $code) { @same_items($code) }

/* A constructed arm may retain only part of its capture declarations. */
meta static List omit_second_capture(List code) {
  match (code)
    case %(try ?body
      (catchcases ((?pattern (block ?decl ?assign ?removed ?read *rest)))
        ?handle) ?finalizer):
      return %((try $body
        (catchcases (($pattern (block $decl $assign @rest))) $handle)
        $finalizer));
  return %($code);
}
macro Stmt $partial(Stmt $code) { @omit_second_capture($code) }

int main(void) {
  int total = 0;
  $same(try total += 1; finally total += 10;);
  $same(try raise %(bad-arg (value 7) (extra 1));
        catch %(bad-arg (value ?value) *rest): total += value + rest.len();
        catch: total = -1;);
  int partial = 0;
  $partial(try raise %(probe (value 7) (extra 1));
    catch %(probe (value ?value) *rest): partial = value + rest.len(););
  printf("%d\n", total);
  return total != 19 || partial != 8;
}
