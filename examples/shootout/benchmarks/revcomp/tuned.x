/* The Computer Language Benchmarks Game
 * https://salsa.debian.org/benchmarksgame-team/benchmarksgame/
 */

#include "typed-array.x"
#include <string.h>
#include <errno.h>

int main(void) {
  ArrayChar sequence = ArrayChar.new();
  ArrayChar complements = ArrayChar.new();
  for (int i = 0; i < 128; i++) complements.push(i);
  String codes = "ACGTUMRWSYKVHDBN", pairs = "TGCAAKYWSRMBDHVN";
  for (int i = 0; i < codes.len(); i++) {
    complements[codes[i]] = pairs[i];
    complements[codes[i] + 'a' - 'A'] = pairs[i];
  }
  char input[16384];
  int line_start = 1, header = 0;
  size_t length;
  while ((length = fread(input, 1, sizeof(input), stdin)) > 0) {
    const char *cursor = input, *end = input + length;
    while (cursor < end) {
      if (line_start) {
        header = *cursor == '>';
        if (header) {
          _write(sequence, complements);
          sequence.clear();
        }
      }
      const char *newline = memchr(cursor, '\n', end - cursor);
      const char *next = newline ? newline + 1 : end;
      if (header) Stdout.write_all(cursor, next - cursor);
      else _append(sequence, cursor, (newline ? newline : end) - cursor);
      line_start = newline != NULL;
      cursor = next;
    }
  }
  if (ferror(stdin)) File.path_error(<read>, NULL, errno);
  _write(sequence, complements);
  return 0;
}

static void _append(ArrayChar sequence, const char *cursor, size_t length) {
  const char *end = cursor + length;
  while (cursor < end) {
    const char *cr = memchr(cursor, '\r', end - cursor);
    const char *next = cr ? cr : end;
    ((Block) sequence).append(cursor, next - cursor);
    cursor = cr ? cr + 1 : end;
  }
}

static void _write(ArrayChar sequence, ArrayChar complements) {
  for (ptrdiff_t i = 0, j = (ptrdiff_t) sequence.len() - 1; i <= j; i++, j--) {
    char first = complements[(unsigned char) sequence[i]];
    sequence[i] = complements[(unsigned char) sequence[j]];
    sequence[j] = first;
  }
  char output[61 * 256];
  size_t used = 0;
  for (size_t start = 0; start < sequence.len(); start += 60) {
    size_t count = sequence.len() - start;
    if (count > 60) count = 60;
    memcpy(output + used, (char *) sequence.bytes + start, count);
    used += count;
    output[used++] = '\n';
    if (used == sizeof(output)) {
      Stdout.write_all(output, used);
      used = 0;
    }
  }
  if (used) Stdout.write_all(output, used);
}
