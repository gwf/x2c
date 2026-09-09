/*  twice.proofs.x -- the proof helper twice.x names.

    A companion helper is an ordinary function whose first argument is the
    session; `$cstar.helper` supplies it. The helper runs inside the
    verification session only, so the compiled program never links it and the
    verified unit never declares it. Its remaining arguments are logical
    terms.
*/

/** Adds one linear-arithmetic identity to the state. `product`'s back edge
    needs the ring identity relating `(x - 1) * y` and `x * y`: the
    entailment prover does linear arithmetic and substitutes equalities, but
    a product of two unknowns is one opaque atom to it. */
static void twice_step(Cstar cstar, String claim) {
  cstar.add_fact(cstar.int_arith(claim));
}
