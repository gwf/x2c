/* Quoted names are data, not variable reads. $ inserts one value; @ splices
   elements. Bare Map keys name Atoms. */
int main(void) {
  auto {
    int n = 2;
    List pair = $(n, n + 1);
    printf("quoting: %s versus %s\n", %(n).repr(), $(n).repr());
    printf("   nested %s; spliced %s\n", %($pair).repr(), %(@pair).repr());
    String key = "answer";
    Map named = {key: n}, evaluated = ${key: n};
    printf("   keys %s versus %s\n",
           named.keys().list().repr(), evaluated.keys().list().repr());
  }
  return 0;
}
