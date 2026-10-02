#include "x2c.x"

static int fixed_hits, dynamic_hits, pattern_calls;

static int pattern_value(int value) {
  pattern_calls++;
  return value;
}

static void fixed(void) {
  try { raise %(probe (value 7) (label "fixed")); }
  catch %(probe (value 7) (label "fixed")): fixed_hits++;
}

static void dynamic(int value) {
  try { raise %(probe (value $value)); }
  catch %(probe (value ${pattern_value(value)})): dynamic_hits++;
}

int main(void) {
  for (int i = 0; i < 4; i++) fixed();
  dynamic(7);
  dynamic(8);
  if (fixed_hits != 4 || dynamic_hits != 2 || pattern_calls != 2) return 1;
  printf("constant catches retain preparation; dynamic catches refresh\n");
  return 0;
}
