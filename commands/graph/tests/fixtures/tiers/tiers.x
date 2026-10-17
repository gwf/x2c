module {
  "parts.x",
}

static int tiers_entry_helper(void) {
  return tiers_shared();
}

int tiers_public(void) {
  return tiers_entry_helper() + tiers_part();
}
