static int tiers_part_helper(void) {
  return 1;
}

module int tiers_shared(void) {
  return tiers_part_helper();
}

int tiers_part(void) {
  return tiers_shared();
}
