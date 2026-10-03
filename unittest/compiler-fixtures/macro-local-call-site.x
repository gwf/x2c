#include "x2c.x"

macro Stmt $repeat(
  Name $i, Expr $count, Expr $value, Name $sum
) {
  for (int $i = 0; $i < $count; $i++) $sum += $value;
}

static int repeat_plain(void) {
  int k = 100, total = 0;
  $repeat(k, 3, k * 2, total);
  return total;
}

static int repeat_unused(void) {
  int k = 100, total = 0;
  macro Expression read_k() => k;
  $repeat(k, 3, k * 2, total);
  return total;
}

static int repeat_ended(void) {
  int k = 100, total = 0;
  { macro Expression read_k() => k; }
  $repeat(k, 3, k * 2, total);
  return total;
}

static int repeat_replaced(void) {
  int k = 100, total = 0;
  macro Expression read_k() => k;
  macro Expression read_k() => 0;
  $repeat(k, 3, k * 2, total);
  return total;
}

int main(void) {
  int k = 100;
  macro Expression read_k() => k;
  macro Stmt write_k() { k = 3; }
  int read = 0, written = 0;
  {
    int k = 2;
    read = read_k();
    write_k();
    written = k;
  }
  int plain = repeat_plain(), unused = repeat_unused();
  int ended = repeat_ended(), replaced = repeat_replaced();
  printf("%d %d %d %d %d %d %d\n", read, written, k, plain, unused,
         ended, replaced);
  return read != 2 || written != 3 || k != 100 || plain != 6 ||
         unused != 6 || ended != 6 || replaced != 6;
}
