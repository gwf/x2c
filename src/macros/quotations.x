/*  quotations.x -- quotation parsing and construction
*/

#pragma once

/* quotations

   `$!( expression )`, `$!{ items }`, and `$!Kind{ ... }` are anonymous
   macros applied where they are written. A `$name` in the body names the
   visible local `name`: its first use declares a hole, and the quotation
   applies to that local's value. An `@name` splices the local's sequence.
   `${expression}` and `@{expression}` declare hidden locals before building
   the code, for singular and sequence insertion. A typed
   quotation, `$!T{ expression }` or `$!(T){ expression }`, builds its code
   where it is written (see "typed quotations"), and so do
   `$!Type{ type-name }` and `$!Param{ parameter }`. */

module {
  "quotations/parsing.x",
  "quotations/construction.x"
}

/** Parses a quotation at `$!` into the code it builds from the locals its
    body names. */
List Compiler.parse_macro_quotation(Compiler c) {
  Token start = c.token;
  c.expect(<$>);
  c.expect(<!>);
  int typed = c._typed_quotation();
  Symbol kind = typed || c.peek(0) == <(> ? <expression> : <block-item>;
  if (!typed && c.peek(0) == <ident>) {
    kind = c._quotation_kind(c.token);
    c.next();
  }
  c.sym.push_new_scope();
  defer c.sym.pop_scope();
  Map holes = {};
  List locals = NULL, type = NULL;
  if (typed) {
    if (c.macro_holes && %(quotation) in c.macro_holes)
      $report.parse.typed_quotation_nested(c, start);
    if (c.macro_holes) $report.parse.typed_quotation(c, start);
    if (c.peek(0) == <(>) locals = c._expression_holes(holes);
    type = c._quoted_type(holes);
  }
  if (!c.macro_holes) locals = locals.append(c._expression_holes(holes));
  List built = c._quotation(start, kind, holes, type);
  if (typed && !(%(dynamic) in holes) && c.folded_constant(built) is not void)
    return built;
  return locals
       ? %(expr ("List") (parens (block @locals (stmnt $built))))
       : built;
}

