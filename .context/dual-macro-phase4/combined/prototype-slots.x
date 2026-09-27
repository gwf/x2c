#pragma once
#include "x2c.x"
#include "meta.x"

meta List Prototype_bound(List code) =>
  %("x2c.slot" "bound" $code ());
meta List Prototype_lowered(List code) =>
  %("x2c.slot" "lowered" $code ());
meta List Prototype_source(List code) =>
  %("x2c.slot" "source" $code ());
meta List Prototype_sequence(List code) =>
  %("x2c.slot" "lowered" (seq @code) ());
meta List Prototype_name(String role) {
  Atom token = Atom.intern("?__effect_name");
  return %("x2c.slot" "bound" $token ((new-name $token $role)));
}
meta List Prototype_frame(List captured) {
  List frame = captured[2];
  return %("x2c.slot" "lowered"
    (declare ("ExceptionFrame") (bindings (bind $frame ()))) ());
}
meta List Prototype_cleanup(List captured) {
  Var token = Atom.intern("?__effect_cleanup");
  List code = captured[2];
  return %("x2c.slot" "lowered" $token ((cleanup $token $code)));
}
meta List Prototype_early(List captured) {
  List binding = captured[2];
  return %("x2c.slot" "lowered" (seq)
    ((early "phase4.helper" $binding
       (declare (static int) (bindings (bind $binding ()))))));
}
meta List Prototype_fail(List captured) {
  (void) captured;
  return %("x2c.slot" "source" (not-an-ast) ());
}
List Macro_apply(Macro value, List arguments) =>
  %("x2c.slot" "source" ("x2c.template" $value $arguments) ());
