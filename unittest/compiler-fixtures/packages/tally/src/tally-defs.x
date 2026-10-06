#pragma once

meta int tally_sum(int n) {
  int total = 0;
  foreach (int i, [1, 2, 3]) total += i * n;
  return total;
}

macro Expression $tally.six() => $tally_sum(1);
