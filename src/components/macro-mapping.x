/*  macro-mapping.x -- maps a source macro over compile-time rows */

#pragma once
#include "compiler/compiler.x"
#include "meta.x"

/* The syntax prelude supplies the decorator. This helper returns one
   invocation of the generator per row, written at the `expand` token, so
   ordinary insertion owns their kind, binding and hygiene.
   A meta call's rows are read as its value, since rows of syntax such as
   names have no lifted expression. A call that returns an expression, and
   any other input, is read as a constant. */
meta List _x2c_expand_rows(List generator, List input) {
  if (generator.assoc(<kind>) == <decorator>)
    x2c_diagnostic_fail("expand requires a code-producing macro", %());
  Compiler c = Compiler.expanding();
  Var value = input ~= %(expr ? (meta-call *))
    ? c.evaluate_meta_value(input, c.token, 1)
    : c.resolve_expression(input, c.token);
  if (value ~= %(expr *)) value = Code.value(value);
  if (value is not <list>)
    x2c_diagnostic_fail("expand requires a compile-time List", %());
  List rows = value, parameters = generator.assoc(<parameters>);
  int sequence = parameters &&
    parameters.last().list().assoc(<sequence>).int();
  int required = parameters.len() - sequence;
  Array code = [];
  int index = 0;
  foreach (Var row in rows) {
    index++;
    List arguments = row is <list> ? row.list() : $(row);
    int supplied = arguments.len();
    if (supplied < required || (!sequence && supplied != required)) {
      String expected = sequence ? %"at least $required" : required.str();
      String noun = !sequence && required == 1 ? "argument" : "arguments";
      x2c_diagnostic_fail(
        %"expand row $index expects $expected $noun; got $supplied", %());
    }
    List application =
      c.evaluate_macro_slot(Macro_apply(generator, arguments));
    code.push(%(macro-invoke @(application[1:3]) $(c.token)));
  }
  return %(seq @(code.list_free()));
}
