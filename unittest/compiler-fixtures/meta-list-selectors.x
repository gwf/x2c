/* Optional compound selectors have matching native and meta behavior. */
#include "x2c.x"
#include "list-selectors.x"

meta int list_compound_selectors(int unused) {
  (void) unused;
  int ok = 1;
  List value = %();
  value = %((((7))));
  ok = ok && value.caaaar() == 7;
  value = %(0 ((7)));
  ok = ok && value.caaadr() == 7;
  value = %(((7)));
  ok = ok && value.caaar() == 7;
  value = %((0 (7)));
  ok = ok && value.caadar() == 7;
  value = %(0 0 (7));
  ok = ok && value.caaddr() == 7;
  value = %(0 (7));
  ok = ok && value.caadr() == 7;
  value = %(((0 7)));
  ok = ok && value.cadaar() == 7;
  value = %(0 (0 7));
  ok = ok && value.cadadr() == 7;
  value = %((0 7));
  ok = ok && value.cadar() == 7;
  value = %((0 0 7));
  ok = ok && value.caddar() == 7;
  value = %(0 0 0 7);
  ok = ok && value.cadddr() == 7;
  value = %((((0 7 8))));
  ok = ok && value.cdaaar().equal(%(7 8));
  value = %(0 ((0 7 8)));
  ok = ok && value.cdaadr().equal(%(7 8));
  value = %(((0 7 8)));
  ok = ok && value.cdaar().equal(%(7 8));
  value = %((0 (0 7 8)));
  ok = ok && value.cdadar().equal(%(7 8));
  value = %(0 0 (0 7 8));
  ok = ok && value.cdaddr().equal(%(7 8));
  value = %(0 (0 7 8));
  ok = ok && value.cdadr().equal(%(7 8));
  value = %((0 7 8));
  ok = ok && value.cdar().equal(%(7 8));
  value = %(((0 0 7 8)));
  ok = ok && value.cddaar().equal(%(7 8));
  value = %(0 (0 0 7 8));
  ok = ok && value.cddadr().equal(%(7 8));
  value = %((0 0 7 8));
  ok = ok && value.cddar().equal(%(7 8));
  value = %((0 0 0 7 8));
  ok = ok && value.cdddar().equal(%(7 8));
  List empty = %();
  return ok
    && empty.caaaar() is void
    && empty.cdddar().len() == 0;
}

meta int var_compound_selectors(int unused) {
  (void) unused;
  int ok = 1;
  Var value = %();
  value = %((((7))));
  ok = ok && value.caaaar() == 7;
  value = %(0 ((7)));
  ok = ok && value.caaadr() == 7;
  value = %(((7)));
  ok = ok && value.caaar() == 7;
  value = %((0 (7)));
  ok = ok && value.caadar() == 7;
  value = %(0 0 (7));
  ok = ok && value.caaddr() == 7;
  value = %(0 (7));
  ok = ok && value.caadr() == 7;
  value = %(((0 7)));
  ok = ok && value.cadaar() == 7;
  value = %(0 (0 7));
  ok = ok && value.cadadr() == 7;
  value = %((0 7));
  ok = ok && value.cadar() == 7;
  value = %((0 0 7));
  ok = ok && value.caddar() == 7;
  value = %(0 0 0 7);
  ok = ok && value.cadddr() == 7;
  value = %((((0 7 8))));
  ok = ok && value.cdaaar().equal(%(7 8));
  value = %(0 ((0 7 8)));
  ok = ok && value.cdaadr().equal(%(7 8));
  value = %(((0 7 8)));
  ok = ok && value.cdaar().equal(%(7 8));
  value = %((0 (0 7 8)));
  ok = ok && value.cdadar().equal(%(7 8));
  value = %(0 0 (0 7 8));
  ok = ok && value.cdaddr().equal(%(7 8));
  value = %(0 (0 7 8));
  ok = ok && value.cdadr().equal(%(7 8));
  value = %((0 7 8));
  ok = ok && value.cdar().equal(%(7 8));
  value = %(((0 0 7 8)));
  ok = ok && value.cddaar().equal(%(7 8));
  value = %(0 (0 0 7 8));
  ok = ok && value.cddadr().equal(%(7 8));
  value = %((0 0 7 8));
  ok = ok && value.cddar().equal(%(7 8));
  value = %((0 0 0 7 8));
  ok = ok && value.cdddar().equal(%(7 8));
  Var empty = %();
  return ok
    && empty.caaaar() is void
    && empty.cdddar().len() == 0;
}

int main(int argc, char **argv) {
  (void) argv;
  printf("%d %d\n", $list_compound_selectors(0),
    list_compound_selectors(argc - 1));
  printf("%d %d\n", $var_compound_selectors(0),
    var_compound_selectors(argc - 1));
  return 0;
}
