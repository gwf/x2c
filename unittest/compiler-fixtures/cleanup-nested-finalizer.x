static int f(void) {
  try { return 7; }
  finally {
    try { printf("nested body\n"); }
    finally { printf("nested finally\n"); }
  }
}
int main(void) { printf("result=%d\n", f()); return 0; }
