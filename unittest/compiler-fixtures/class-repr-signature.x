class Wrong struct { int x; } *;
int Wrong.repr(Wrong value) { (void) value; return 4; }
int main(void) { return 0; }
