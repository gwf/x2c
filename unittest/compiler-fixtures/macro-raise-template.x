macro Statement $fail(Expr $cause, Expr $op, Expr $fields...) {
  raise %($cause (operation ${$op}) $fields...);
}
macro Statement $keyed(Expr $cause, Expr $key, Expr $value) {
  raise %($cause ($key ${$value}));
}
int main(void) {
  Error.policy_set(<probe>, <collect>);
  int mark = Error.mark(), n = 0, a = 2, b = 3;
  $fail(<probe>, ++n);
  $fail(<probe>, ++n, <first>, ++a, <second>, ++b);
  $keyed(<probe>, <value>, ++n);
  List records = Error.since(mark);
  if (n != 3 || a != 3 || b != 4 || records.len() != 3) return 1;
  if (records[0].list().assoc(<detail>) != %((operation 1)).var()) return 2;
  if (records[1].list().assoc(<detail>) !=
      %((operation 2) (first 3) (second 4)).var()) return 3;
  if (records[2].list().assoc(<detail>) != %((value 3)).var()) return 4;
  if (records[0].list().assoc(<location>).is_nil()) return 5;
  try { $fail(<bad-arg>, %"caught", <actual>, 42); }
  catch %(bad-arg (operation ?op) (actual ?actual)):
    return op == %"caught" && actual == 42 ? 0 : 6;
  return 7;
}
