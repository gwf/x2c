/*  report-axiom.proofs.x -- register an assumption in the pinned prover. */

thm new_axiom(term proposition);

static void add_axiom(Cstar cstar) {
  new_axiom(cstar.term("(x:int) = y"));
}
