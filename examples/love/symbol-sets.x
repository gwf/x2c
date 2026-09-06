/*  symbol-sets.x -- ordered Symbol sets: membership, index, dispatch */


static const SymbolSet lights = %<<green yellow red>>;

/* The dense index reaches a parallel table; no switch needed. */
static const char *const advice[] = { "go", "slow", "stop" };

int main(void) {
  printf("contains yellow: %d\n", lights.contains(<yellow>));
  printf("contains purple: %d\n", lights.contains(<purple>));

  printf("index of red: %d\n", lights.index(<red>));
  printf("index of purple: %d\n", lights.index(<purple>));

  printf("first light: %s\n", lights.getindex(0).str());
  printf("last light: %s\n", lights.getindex(-1).str());

  foreach(Symbol light, lights) {
    printf("light: %s\n", light.str());
  }

  Symbol seen[] = { <red>, <green>, <red>, <yellow> };
  int count = sizeof(seen) / sizeof(seen[0]);
  for (int i = 0; i < count; i++) {
    printf("%s -> %s\n", seen[i].str(), advice[lights.index(seen[i])]);
  }

  return 0;
}
