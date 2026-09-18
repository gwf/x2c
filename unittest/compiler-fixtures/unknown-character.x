// A byte no scanner claims ends the token stream. Every such byte takes this
// path, so the backtick below stands for any of them, including 0xFF.
int main(void) {
  int value` = 1;
  return value;
}
