/*  meta-comptime-only-call.x -- a syntax builder can now run at runtime

    Literal construction has a meta body rather than a compiler-only
    declaration. Its callers therefore have runtime definitions too.
*/

#include "x2c.x"
#include "meta.x"

meta static List mc_name(String text) => x2c_literal_string(text);

meta static List mc_wrap(String text) => mc_name(text);

macro Expression $builder.aliases() =>$(x2c.literal.int (if (and
    (equal? (x2c_literal_string "hi")
      (x2c.literal.string "hi"))
    (equal? (x2c_literal_int 17)
      (x2c.literal.int 17))
    (equal? (x2c_literal_symbol '<builders>)
      (x2c.literal.symbol '<builders>))
    (eq? x2c_expr_ident x2c.expr.ident)
    (eq? x2c_expr_index x2c.expr.index)
    (eq? x2c_expr_field x2c.expr.field)
    (eq? x2c_expr_composite x2c.expr.composite)
    (eq? x2c_expr_cast x2c.expr.cast)
    (eq? x2c_function_body x2c.function.body)
    (eq? x2c_parameters_arguments x2c.parameters.arguments)) 1 0));

int main(void) {
  List node = mc_wrap("hi");
  return !$builder.aliases() || !node.equal(%(expr ("String") (segments
    (segexp (expr ("String") (literal ("String") "hi"))))));
}
