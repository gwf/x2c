/*  block-buffer-hot-paths.x -- focused Block and Buffer timings */


#include <stdint.h>
#include <time.h>

static uint64_t now_ns(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (uint64_t) ts.tv_sec * 1000000000ull + ts.tv_nsec;
}

static void result(const char *name, uint64_t elapsed, int count) {
  printf("%s,%.3f\n", name, (double) elapsed / count);
}

int main(void) {
  int count = 1000000;
  volatile unsigned long sink = 0;
  char value = 'x';
  uint64_t start;

  Block block = Block.new(sizeof(char));
  block.append(&value, 1);
  start = now_ns();
  for (int i = 0; i < count; i++) {
    block.length = 0;
    block.append(&value, 1);
    sink += block.length;
  }
  result("block-append-one", now_ns() - start, count);

  Buffer write = Buffer.new(0);
  write.write_len(&value, 1);
  start = now_ns();
  for (int i = 0; i < count; i++) {
    write.content.length = 0;
    write.pos = 0;
    write._indent = 0;
    write.write_len(&value, 1);
    sink += write.pos;
  }
  result("buffer-write-one", now_ns() - start, count);

  Buffer indent = Buffer.new(0);
  indent.pos = 80;
  indent.push();
  indent.pos = 0;
  indent.indent();
  start = now_ns();
  for (int i = 0; i < count; i++) {
    indent.content.length = 0;
    indent.pos = 0;
    indent._indent = 0;
    indent.indent();
    sink += indent.pos;
  }
  result("buffer-indent-80", now_ns() - start, count);

  Buffer serialize = Buffer.new(0);
  int serial_count = count / 10;
  serialize.write("alpha: beta, gamma: delta");
  start = now_ns();
  for (int i = 0; i < serial_count; i++) {
    serialize.content.length = 0;
    serialize.pos = 0;
    serialize._indent = 0;
    serialize.write("alpha: beta, gamma: delta");
    String output = serialize.str();
    sink += output.len();
  }
  result("buffer-serialize", now_ns() - start, serial_count);

  serialize.free();
  indent.free();
  write.free();
  block.free();
  if (sink == 0) return 1;
  return 0;
}
