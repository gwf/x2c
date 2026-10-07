#include "x2c.x"
#include "meta.x"

static int sum_many(int first, ...) { return first; }
static int sum_two(int left, int right) { return left + right; }

macro Expression $pack(Expr @items) => sum_many(0, @items);
macro Expression $mixed(Expr $first, Expr @items) =>
  sum_many($first, @items);
macro Expression $reverse(Expr $first, Expr $second) =>
  sum_two($second, $first);
macro Expression $fixed() => sum_two(0, 0);

meta static List sequence_hits(List expanded, int expected) {
  Macro pack = $pack;
  List parts = NULL;
  match (expanded)
    case %(expr ? (call ? (args ? *items))): parts = items;
  if (!parts && expected)
    x2c_diagnostic_fail("sequence fixture setup failed", %());
  int direct = 0, pending = 0, body = 0;
  List pattern = Macro_pattern(pack, %(*items));
  direct = expanded.match(pattern) != NULL;
  List invocation = pack(parts);
  match (invocation) case pack(*items): pending = items.len() == expected;
  match (expanded) case pack(*items): body = items.len() == expected;
  if (!direct || !pending || !body)
    x2c_diagnostic_fail("macro sequence case failed", %());
  return x2c_literal_int(1);
}

meta static List mixed_hits(List expanded) {
  Macro mixed = $mixed;
  List args = NULL;
  match (expanded) case %(expr ? (call ? (args *items))): args = items;
  if (!args || args.len() != 3)
    x2c_diagnostic_fail("mixed fixture setup failed", %());
  int pending = 0, body = 0;
  List invocation = mixed(args.car(), args.cdr());
  match (invocation) case mixed(?first, *rest):
    pending = List.compare(first, args.car()) == 0 && rest.len() == 2;
  match (expanded) case mixed(?first, *rest):
    body = List.compare(first, args.car()) == 0 && rest.len() == 2;
  if (!pending || !body)
    x2c_diagnostic_fail("mixed macro sequence case failed", %());
  return x2c_literal_int(1);
}

meta static List reordered_hits(List expanded, List same) {
  Macro reverse = $reverse;
  List args = NULL;
  match (expanded) case %(expr ? (call ? (args *items))): args = items;
  if (!args || args.len() != 2)
    x2c_diagnostic_fail("reordered fixture setup failed", %());
  int pending = 0, body = 0, repeated = 0, unequal = 0;
  List invocation = reverse(args.cadr(), args.car());
  match (invocation) case reverse(?first, ?second):
    pending = List.compare(first, args.cadr()) == 0 &&
              List.compare(second, args.car()) == 0;
  match (expanded) case reverse(?first, ?second):
    body = List.compare(first, args.cadr()) == 0 &&
           List.compare(second, args.car()) == 0;
  match (same) case reverse(?equal, ?equal): repeated = 1;
  match (expanded) case reverse(?equal, ?equal): unequal = 1;
  if (!pending || !body || !repeated || unequal)
    x2c_diagnostic_fail("reordered macro case failed", %());
  return x2c_literal_int(1);
}

meta static List fixed_hits(List expanded) {
  Macro fixed = $fixed;
  int pending = 0, body = 0;
  List invocation = fixed();
  match (invocation) case fixed(): pending = 1;
  match (expanded) case fixed(): body = 1;
  if (!pending || !body)
    x2c_diagnostic_fail("binder-free macro case failed", %());
  return x2c_literal_int(1);
}

macro Expression $empty_hit(Expr $expanded) =>
  $sequence_hits($expanded, 0);
macro Expression $populated_hit(Expr $expanded) =>
  $sequence_hits($expanded, 2);
macro Expression $mixed_hit(Expr $expanded) => $mixed_hits($expanded);
macro Expression $reordered_hit(Expr $expanded, Expr $same) =>
  $reordered_hits($expanded, $same);
macro Expression $fixed_hit(Expr $expanded) => $fixed_hits($expanded);

int main(void) {
  printf("%d %d %d %d %d\n", $empty_hit(sum_many(0)),
         $populated_hit(sum_many(0, 1, 2)),
         $mixed_hit(sum_many(1, 2, 3)),
         $reordered_hit(sum_two(2, 1), sum_two(1, 1)),
         $fixed_hit(sum_two(0, 0)));
  return 0;
}
