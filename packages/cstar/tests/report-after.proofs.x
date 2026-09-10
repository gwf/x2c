/*  report-after.proofs.x -- repeat the query after an unsafe function. */

static void inspect_report(Cstar cstar) {
  Stdout.printf("%s\n", cstar.report());
  cstar.report();
}
