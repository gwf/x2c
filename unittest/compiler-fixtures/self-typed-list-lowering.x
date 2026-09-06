#include "typed-list.x"
#include "list-selectors.x"

static int keep(Var value) { return value.truth(); }

ListInt structural(ListInt left, ListInt right) {
  return left.cdr().append(right).reverse();
}

int second(ListInt values) {
  return values.cdr().car();
}

ListInt after_three(ListInt values) {
  return values.cdddr();
}

ListInt after_four(ListInt values) {
  return values.cddddr();
}

ListInt promoted(ListInt values) {
  return values.promote();
}

ListInt branch_tails(ListInt values) {
  return values.cdar().append(values.cdaar()).append(values.cdadr())
    .append(values.cddar()).append(values.cdaaar())
    .append(values.cdaadr()).append(values.cdadar())
    .append(values.cdaddr()).append(values.cddaar())
    .append(values.cddadr()).append(values.cdddar());
}

ListInt filtered(ListInt values) {
  return values.filter(keep);
}

ListInt flattened(ListInt values) {
  return values.flatten();
}

ListInt flattened_all(ListInt values) {
  return values.flatten_all();
}
