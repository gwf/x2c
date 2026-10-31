/*  macro-mapping.x -- maps a source macro over compile-time rows */

#pragma once
#include "meta.x"

/* The syntax prelude supplies the decorator. This helper returns pending
   applications, so ordinary insertion owns their kind, binding and hygiene. */
meta List _x2c_expand_rows(List generator, List input) {
  if (generator.assoc(<kind>) == <decorator>)
    x2c_diagnostic_fail("expand requires a code-producing macro", %());
  Var value = Code.value(input);
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
      x2c_diagnostic_fail(
        %"expand row $index expects $expected arguments; got $supplied", %());
    }
    code.push(Macro_apply(generator, arguments));
  }
  return %(seq @(code.list_free()));
}
