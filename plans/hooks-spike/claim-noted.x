#pragma once
#include "x2c.x"
#include "meta.x"

/* A user claim: `T x = $noted(v);` prints the declared name after it. */
macro Expression $noted(Expr $value) =>
  $(list 'expr nil (list 'claim 'noted "noted needs a declaration" $value));

meta List noted_declaration(List declaration) {
  match (declaration)
    case %(declare ? (bindings (op = (bind ?binding ?) ?))): {
      List name = x2c_literal_string(x2c_binding_spelling(binding));
      return %(seq $declaration
        ${$!{ printf("declared %s = %d\n", $name, $binding); }});
    }
  return declaration;
}

hook <noted> noted_declaration;
