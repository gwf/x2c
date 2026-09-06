/* import-method-ambiguous.x -- two imported receiver methods need a choice. */
import "geo";
import "other";

int ambiguous_vec(Var value) {
  return value.vec();
}
