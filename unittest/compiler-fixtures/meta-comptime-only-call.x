/*  meta-comptime-only-call.x -- a syntax builder can run at runtime

    A typed quotation builds its literal where it is written, so a meta
    function that returns one has a runtime definition, as do its callers.
*/

#include "x2c.x"
#include "meta.x"

meta static List mc_name(String text) => $!String{ $text };

meta static List mc_wrap(String text) => mc_name(text);

macro Expression $builder.aliases() => $(x2c.literal.int (if (and
    (equal? (x2c.literal.string "hi")
      '(expr ("String") (segments
        (segexp (expr ("String") (literal ("String") "hi"))))))
    (equal? (x2c.literal.int 17) '(expr (int) (literal (int) "17")))
    (equal? (x2c.literal.symbol '<builders>)
      '(expr ("Symbol") (literal ("Symbol") "builders" <builders>)))
    (eq? Code.body Code.body)
    (eq? Code.arguments Code.arguments)) 1 0));

int main(void) {
  List node = mc_wrap("hi");
  return !$builder.aliases() || !node.equal(%(expr ("String") (segments
    (segexp (expr ("String") (literal ("String") "hi"))))));
}
