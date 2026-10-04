#include "x2c.x"
#include "meta.x"

/* A meta function returns parsed try statements unchanged. A parsed catch
   arm already declares its binders, so binding it declares them once. */
meta static List same_items(List code) => %($code);
macro Stmt $same(Stmt $code) { $same_items($code)... }

int main(void) {
  int total = 0;
  $same(try total += 1; finally total += 10;);
  $same(try raise %(bad-arg (value 7) (extra 1));
        catch %(bad-arg (value ?value) *rest): total += value + rest.len();
        catch: total = -1;);
  printf("%d\n", total);
  return total != 19;
}
