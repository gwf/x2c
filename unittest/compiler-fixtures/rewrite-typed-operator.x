#include "x2c.x"
#include "rewrite.x"

/* A user rule on its own Var alias runs before the shipped Var rules for
   the same operator; native operands never reach either. */
typedef Var Money;

static int scaled = 0;

static Money money_scale(Money amount, int factor) {
  scaled++;
  return amount.int() * factor;
}

macro Expression $money_times(Expr $amount, Expr $factor) =>
  $amount * $factor;

$rewrite_typed(Var, $money_times,
  $!Money{${%(!and ?amount)}}, $!int{${%(!and ?factor)}})
meta Code money_times(Code code) {
  match (code) case $money_times(?amount, ?factor):
    return $!Money{ money_scale($amount, $factor) };
  return code;
}

int main(void) {
  Money price = 250;
  Var plain = 3;
  int width = 6, height = 7;
  int native = width * height;
  Money total = price * 4;
  Var boxed = plain * 5;
  price += 5;
  printf("%d %d %d %d %d\n", native, total.int(), boxed.int(), price.int(),
         scaled);
  return 0;
}
