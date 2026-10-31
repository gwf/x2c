/* The Computer Language Benchmarks Game
 * https://salsa.debian.org/benchmarksgame-team/benchmarksgame/
 * Algorithm and constants from Paul Hsieh's contributed C program.
 */

#include <stdlib.h>
#include "typed-array.x"

static int seed = 42;
static String alu =
  "GGCCGGGCGCGGTGGCTCACGCCTGTAATCCCAGCACTTTGG"
  "GAGGCCGAGGCGGGCGGATCACCTGAGGTCAGGAGTTCGAGA"
  "CCAGCCTGGCCAACATGGTGAAACCCCGTCTCTACTAAAAAT"
  "ACAAAAATTAGCCGGGCGTGGTGGCGCGCGCCTGTAATCCCA"
  "GCTACTCGGGAGGCTGAGGCAGGAGAATCGCTTGAACCCGGG"
  "AGGCGGAGGTTGCAGTGAGCCGAGATCGCGCCACTGCACTCC"
  "AGCCTGGGCGACAGAGCGAGACTCCGTCTCAAAAA";

int main(int argc, char **argv) {
  int n = argc > 1 ? atoi(argv[1]) : 1000;
  puts(">ONE Homo sapiens alu");
  _repeat(2 * n);
  puts(">TWO IUB ambiguity codes");
  _random("acgtBDHKMNRSVWY", _probabilities([
    0.27, 0.12, 0.12, 0.27, 0.02, 0.02, 0.02, 0.02,
    0.02, 0.02, 0.02, 0.02, 0.02, 0.02, 0.02]), 3 * n);
  puts(">THREE Homo sapiens frequency");
  _random("acgt", _probabilities([
    0.3029549426680, 0.1979883004921,
    0.1975473066391, 0.3015094502008]), 5 * n);
  return 0;
}

static void _repeat(int count) {
  ArrayChar line = auto ArrayChar.new();
  for (int start = 0; start < count; start += 60) {
    line.clear();
    int end = start + 60 < count ? start + 60 : count;
    for (int i = start; i < end; i++)
      line.push(alu[i % alu.len()]);
    line.push('\n');
    Stdout.write_all(line.bytes, line.len());
  }
}

static void _random(String letters, ArrayDbl probabilities, int count) {
  double total = 0;
  for (int i = 0; i < probabilities.len(); i++) {
    total += probabilities[i];
    probabilities[i] = total;
  }
  ArrayChar line = auto ArrayChar.new();
  for (int start = 0; start < count; start += 60) {
    line.clear();
    int end = start + 60 < count ? start + 60 : count;
    for (int i = start; i < end; i++) {
      seed = (seed * 3877 + 29573) % 139968;
      double random = (double) seed / 139968;
      int choice = 0;
      while (random >= probabilities[choice]) choice++;
      line.push(letters[choice]);
    }
    line.push('\n');
    Stdout.write_all(line.bytes, line.len());
  }
}

static ArrayDbl _probabilities(Array values) {
  ArrayDbl result = ArrayDbl.new();
  foreach (double probability in values) result.push(probability);
  return result;
}
