static int tiers_part_helper(void) {
  return 1;
}

module int tiers_shared(void) {
  return tiers_part_helper();
}

module int tiers_local(void) {
  return 2;
}

int tiers_part(void) {
  return tiers_shared() + tiers_local();
}
