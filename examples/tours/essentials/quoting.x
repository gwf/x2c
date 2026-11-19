/* Quoted names are data, not variable reads. $ inserts one value; @ splices
   elements. Bare Map keys name Atoms. */
int main(void) {
  int n = 2;
  List pair = $(n, n + 1);
  printf("Quoted name: %s\nInserted value: %s\n", %(n).repr(), $(n).repr());
  printf("Nested list: %s\nSpliced list: %s\n", %($pair).repr(), %(@pair).repr());
  String key = "answer";
  Map named = {key: n}, evaluated = ${key: n};
  printf("Bare keys: %s\nEvaluated keys: %s\n",
         named.keys().list().repr(), evaluated.keys().list().repr());
  return 0;
}
