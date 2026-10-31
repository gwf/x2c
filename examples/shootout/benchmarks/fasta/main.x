/* The Computer Language Benchmarks Game
 * https://salsa.debian.org/benchmarksgame-team/benchmarksgame/
 * Algorithm and constants from Paul Hsieh's contributed C program.
 */

#include <stdlib.h>

static int seed = 42;
static String alu =
  "GGCCGGGCGCGGTGGCTCACGCCTGTAATCCCAGCACTTTGG"
  "GAGGCCGAGGCGGGCGGATCACCTGAGGTCAGGAGTTCGAGA"
  "CCAGCCTGGCCAACATGGTGAAACCCCGTCTCTACTAAAAAT"
  "ACAAAAATTAGCCGGGCGTGGTGGCGCGCGCCTGTAATCCCA"
  "GCTACTCGGGAGGCTGAGGCAGGAGAATCGCTTGAACCCGGG"
  "AGGCGGAGGTTGCAGTGAGCCGAGATCGCGCCACTGCACTCC"
  "AGCCTGGGCGACAGAGCGAGACTCCGTCTCAAAAA";

class Choice { char letter; double cumulative; } *;

int main(int argc, char **argv) {
  int n = argc > 1 ? atoi(argv[1]) : 1000;
  puts(">ONE Homo sapiens alu");
  _repeat(2 * n);
  puts(">TWO IUB ambiguity codes");
  _random("acgtBDHKMNRSVWY", [
    0.27, 0.12, 0.12, 0.27, 0.02, 0.02, 0.02, 0.02,
    0.02, 0.02, 0.02, 0.02, 0.02, 0.02, 0.02], 3 * n);
  puts(">THREE Homo sapiens frequency");
  _random("acgt", [
    0.3029549426680, 0.1979883004921,
    0.1975473066391, 0.3015094502008], 5 * n);
  return 0;
}

static void _repeat(int count) {
  Buffer line = auto Buffer.new(0);
  for (int start = 0; start < count; start += 60) {
    line.clear();
    int end = start + 60 < count ? start + 60 : count;
    for (int i = start; i < end; i++)
      line.write_char(alu[i % alu.len()]);
    puts(line.str());
  }
}

static void _random(String letters, Array probabilities, int count) {
  Array choices = _choices(letters, probabilities);
  Buffer line = auto Buffer.new(0);
  for (int start = 0; start < count; start += 60) {
    line.clear();
    int end = start + 60 < count ? start + 60 : count;
    for (int i = start; i < end; i++) {
      seed = (seed * 3877 + 29573) % 139968;
      double random = (double) seed / 139968;
      int index = 0;
      Choice choice = choices[index];
      while (random >= choice.cumulative) choice = choices[++index];
      line.write_char(choice.letter);
    }
    puts(line.str());
  }
}

static Array _choices(String letters, Array probabilities) {
  Array choices = [];
  double cumulative = 0;
  for (int i = 0; i < probabilities.len(); i++) {
    cumulative += probabilities[i].double();
    choices.push(Choice.new(letters[i], cumulative));
  }
  return choices;
}

static void Choice.init(Choice choice, char letter, double cumulative) {
  choice.letter = letter;
  choice.cumulative = cumulative;
}
