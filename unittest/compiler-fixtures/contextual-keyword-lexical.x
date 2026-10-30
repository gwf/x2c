#include "x2c.x"

int main(void) {
  int raise = 19, try = 2, catch = 3, finally = 5;
  int total = (raise) %(try+catch);
  total += raise % (try + catch);
  if (total != 8 || !((raise) < try + catch + finally + 10)) return 1;
  try { raise %(lex-prio); }
  catch %(lex-prio): { total++; }
  finally { total++; }
  printf("lexical %d\n", total);
  return total != 10;
}
