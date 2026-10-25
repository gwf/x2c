/*  meta-comptime-only-call.x -- a syntax builder can run at runtime

    A typed quotation builds its literal where it is written, so a meta
    function that returns one has a runtime definition, as do its callers.
*/

#include "x2c.x"
#include "meta.x"

meta static List mc_name(String text) => $!String{ $text };

meta static List mc_wrap(String text) => mc_name(text);

int main(void) {
  List node = mc_wrap("hi");
  return !node.equal(%(expr ("String") (segments
    (segexp (expr ("String") (literal ("String") "hi"))))));
}
