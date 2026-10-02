// Collection's forward hashes stay private; the SDK reports parsed bodies.
#include "x2c.x"
#include "meta.x"

static int early_a = 1, early_b = 2;

meta static int has_hash(Map hashes, String name) => name in hashes;

meta static int string_hashes(Map hashes) {
  foreach (Var (name, hash), hashes)
    if (hash is not <string>) return 0;
  return 1;
}

macro Expression $hash_present(Literal $key) =>
  $(has_hash (x2c.meta.definition.hashes) (x2c.literal.value $key));

macro Expression $hash_strings() =>
  $(string_hashes (x2c.meta.definition.hashes));

int main(void) {
  printf("%d %d %d %d %d\n",
    $hash_present("early_a"), $hash_present("early_b"),
    $hash_present("late_a"), $hash_present("late_b"), $hash_strings());
  return 0;
}

static int late_a = 3, late_b = 4;
