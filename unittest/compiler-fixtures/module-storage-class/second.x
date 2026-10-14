module int tally_twice(void) {
  tally_node node = { tally_total };
  tally_add(node);
  return tally_total;
}
