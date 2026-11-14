#include <assert.h>
#include <lisp-bindings.x>

int seats_left(String plan) => plan == "pro" ? 25 : 2;

int main(void) {
  // Expose an ordinary typed function to the runtime interpreter.
  auto Lisp lisp = Lisp.new();
  lisp.bind("seats-left", seats_left);

  // Keep the party together, or admit as many people as fit.
  List together = %(lambda (plan n)
    (if (<= n (seats-left plan)) n 0));
  List split = %(lambda (plan n)
    (if (<= n (seats-left plan)) n (seats-left plan)));

  // Supply either policy as data to the same evaluator.
  Var plan = "free", guests = 12;
  int whole = lisp.eval(%($together $plan $guests));
  int partial = lisp.eval(%($split $plan $guests));
  printf("together: %d; split: %d\n", whole, partial);
  assert(whole == 0 && partial == 2);
  return 0;
}
