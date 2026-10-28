static void tick(void) {}
int count(void) { return tick(); }
int main(void) { printf("%d\n", count()); return 0; }
