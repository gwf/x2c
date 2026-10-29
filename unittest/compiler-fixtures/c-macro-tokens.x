// `--dump-tokens` prints the expanded stream the parser reads, and marks
// each token an expansion produced with the macro used there.
#define N 10
#define ADD(a, b) a + b

int value = ADD(N, 2);
