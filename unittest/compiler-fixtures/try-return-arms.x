#include <stdio.h>
static int risky(int n) {
  if (n < 0) raise %(bad-arg);
  if (n == 0) raise %(io-fail);
  return n * 2;
}
static int pick(int n) {
  try return risky(n);
  catch %(bad-arg *): return -1;
}
static int pick2(int n) {
  try return risky(n);
  catch %(bad-arg *): return -1;
  catch %(io-fail *): return -2;
}
static int fall(int n) {
  int r = 0;
  try r = risky(n);
  catch %(bad-arg *): r = -10;
  catch %(io-fail *): r = -20;
  return r + 1;
}
static int loop(void) {
  int total = 0;
  for (int i = -2; i < 4; i++) {
    try total += risky(i);
    catch %(bad-arg *): continue;
    catch %(io-fail *): break;
  }
  return total;
}
int main(void) {
  printf("%d %d %d %d %d %d %d %d\n", pick(3), pick(-1), pick2(3), pick2(-1),
         pick2(0), fall(-1), fall(0), loop());
  return 0;
}
