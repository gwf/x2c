/* The Computer Language Benchmarks Game: pidigits.
   GMP supplies arbitrary precision. Fused multiply-add and multiply-subtract
   operations save intermediate products; both required extracts remain. */

#include <gmp.h>
#include "cleanup.x"
#include <stdio.h>
#include <stdlib.h>

typedef struct Spigot {
  mpz_t numerator, accumulator, denominator, term, digit;
} Spigot;

$cleanup.by(Spigot, drop);

int main(int argc, char **argv) {
  int count = argc > 1 ? atoi(argv[1]) : 30, emitted = 0;
  auto Spigot spigot = Spigot.new();
  for (ulong k = 1; emitted < count; k++) {
    spigot.advance(k);
    if (mpz_cmp(spigot.numerator, spigot.accumulator) > 0) continue;
    ulong digit = spigot.extract(3);
    if (digit != spigot.extract(4)) continue;
    putchar('0' + digit);
    if (++emitted % 10 == 0) printf("\t:%d\n", emitted);
    spigot.eliminate(digit);
  }
  if (emitted % 10) {
    for (int i = emitted % 10; i < 10; i++) putchar(' ');
    printf("\t:%d\n", emitted);
  }
  return 0;
}

static Spigot Spigot.new(void) {
  Spigot state;
  mpz_init_set_ui(state.numerator, 1);
  mpz_init_set_ui(state.accumulator, 0);
  mpz_init_set_ui(state.denominator, 1);
  mpz_init_set_ui(state.term, 0);
  mpz_init_set_ui(state.digit, 0);
  return state;
}

static void Spigot.drop(Spigot &state) {
  mpz_clear(state.numerator);
  mpz_clear(state.accumulator);
  mpz_clear(state.denominator);
  mpz_clear(state.term);
  mpz_clear(state.digit);
}

static void Spigot.advance(Spigot &state, ulong k) {
  mpz_addmul_ui(state.accumulator, state.numerator, 2);
  mpz_mul_ui(state.accumulator, state.accumulator, 2 * k + 1);
  mpz_mul_ui(state.denominator, state.denominator, 2 * k + 1);
  mpz_mul_ui(state.numerator, state.numerator, k);
}

static ulong Spigot.extract(Spigot &state, ulong nth) {
  mpz_mul_ui(state.term, state.numerator, nth);
  mpz_add(state.term, state.term, state.accumulator);
  mpz_tdiv_q(state.digit, state.term, state.denominator);
  return mpz_get_ui(state.digit);
}

static void Spigot.eliminate(Spigot &state, ulong digit) {
  mpz_submul_ui(state.accumulator, state.denominator, digit);
  mpz_mul_ui(state.accumulator, state.accumulator, 10);
  mpz_mul_ui(state.numerator, state.numerator, 10);
}
