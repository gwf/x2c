/*  match-component.x -- `match` over static patterns as ordinary control flow

    Including this file registers `static_match` for every bound and typed
    `match` statement that follows. When every arm's pattern is in the
    static subset `x2c_pattern_steps` describes, the match becomes nested
    `if` tests over the subject's List cells inside `switch (0) { default:
    ... }`: an arm's `break` leaves it, a `continue` reaches the enclosing
    loop, and a failed arm or guard falls through to the next arm, as the
    built-in lowering does. One cursor per List depth walks the cells, and
    each arm declares its binders from the cells it read, so no Match
    runtime call remains. Any other match is declined and compiles as
    before, as is one with a macro-valued case or arms between
    preprocessor directives.
*/

#pragma once
#include "meta-patterns.x"

/* The statement the arm `(pattern body)` lowers to, or NULL outside the
   static subset. The default arm's pattern is `(*)`; a guarded body ends
   with its own `break`. */
meta static List _smatch_arm(List row, Atom selected, List &cursors) {
  List pattern = row.car(), body = row.cadr(), inner = %($body (break));
  match (body) case %(guarded ?statement): inner = %($statement);
  if (pattern.car() == <*>) return %(block @inner);
  List lowered = x2c_pattern_steps(pattern, selected);
  if (!lowered) return NULL;
  List (steps, binders, walked) = lowered;
  if (walked.len() > cursors.len()) cursors = walked;
  return x2c_pattern_nest(steps, inner);
}

meta static List _smatch_declare(Atom name, List value) =>
  %(declare ("List") (bindings (op = (bind $name ()) $value)));

// the hook

/* The control flow `node` becomes, or `node` itself. */
meta List static_match(List node) {
  match (node) case %(match ?subject ?cases): {
    Atom selected = x2c_fresh_name("subject");
    List cursors = NULL;
    Array arms = [];
    foreach (List row, cases) {
      if (row.car() == <preproc>) return node;
      List arm = _smatch_arm(row, selected, cursors);
      if (!arm) return node;
      arms.push(arm);
    }
    Array code = [_smatch_declare(selected, subject)];
    Array effects = [x2c_effect_name(selected)];
    foreach (Atom cursor, cursors) {
      code.push(_smatch_declare(cursor, %(expr () (ident $selected))));
      effects.push(x2c_effect_name(cursor));
    }
    List zero = x2c_literal_int(0);
    code.push(%(switch $zero (block (default) @{arms.list_free()})));
    return x2c_code(%(block @{code.list_free()}), effects.list_free());
  }
  return node;
}

hook <match> static_match;
