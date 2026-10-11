/*  component-lambdas.x -- lambda lowering

    A lambda becomes a static function among the unit's support
    declarations. Its parameters keep their declarators, a bare one is a
    `Var`, and it returns a `Var`: a bare return and the end of a block body
    return none, and an expression body returns its value. A noncapturing
    lambda's value is that function.

    Each definition precedes the definitions that call it: the compiler
    settles whether a linked copy reaches a compile-time operation when the
    copy binds.
*/
#pragma once
#include "rewrite.x"
#include "grammar.x"

// function bodies

/* `ast` with each node that `replaced` holds replaced by its value,
   except within a nested lambda, which keeps its own. A pending stack
   rebuilds it bottom-up and keeps each unchanged node. */
meta static Var _lambda_replace(Var ast, Map replaced) {
  Array pending = [ast], building = [0], done = [];
  while (pending.len()) {
    Var node = pending.take_last();
    if (building.take_last().int()) {
      int first = done.len() - node.list().len(), index = first;
      Array parts = [];
      int changed = 0;
      foreach (Var part, node.list()) {
        changed |= done[index] != part;
        parts.push(done[index++]);
      }
      done.truncate(first);
      done.push(changed ? parts.list_free() : node);
      continue;
    }
    Var replacement;
    if (replaced.try_get(node, replacement)) done.push(replacement);
    else if (node is not <list> || node.is_nil() ||
             node.list().match(%(expr ? (lambda *))))
      done.push(node);
    else {
      pending.push(node);
      building.push(1);
      Array parts = [];
      foreach (Var part, node.list()) parts.push(part);
      for (int i = parts.len() - 1; i >= 0; i--) {
        pending.push(parts[i]);
        building.push(0);
      }
    }
  }
  return done[0];
}

/* The return of a lambda that returns no value. */
meta static List _lambda_none(void) =>
  %(return ("Var") (expr ("Var") (literal ("Var") "void")));

/* The block items of the function that runs the lambda body `body`. An
   expression body keeps the origin of the item that holds the lambda, so
   lowering it later reports there. */
meta static List _lambda_items(Code body) {
  match (body) case %(block *items): {
    Map none = {};
    none[%(return)] = _lambda_none();
    return %(@{_lambda_replace(items, none)} ${_lambda_none()});
  }
  List items = body.match(%(expr (void) ?))
    ? %((stmnt $body) ${_lambda_none()})
    : %((stmnt (return ${body.convert(%("Var"))})));
  match (x2c_enclosing(<statement>)) case %(at ?origin ?):
    return %((at $origin ${items.car()}) @{items.cdr()});
  return items;
}

/* A lambda's parameters as a function's: a bare one is a `Var`. */
meta static List _lambda_params(List params) {
  Array out = [];
  foreach (List param, params)
    match (param) {
      case %(binding ? ?): out.push(%(param ("Var") (bind $param ())));
      default: out.push(param);
    }
  return out.list_free();
}

/* The static function `name` that runs `body` with `params`. The body is
   bound already, so it is not bound again. */
meta static Code _lambda_function(Atom name, List params, Code body) {
  if (!params) params = %((param (void) (bind () ())));
  List lowered = %(code-value "lowered" (seq @{_lambda_items(body)}) ());
  return %(function (static "Var") (bind $name ((fnmod (params @params))))
           (block $lowered));
}

$rewrite($lambda_expression)
/** Lifts the noncapturing lambda `node` to a static function, whose name
    is its value. */
meta Code lambda_lift(Code node) {
  match (node) case %(expr ?type ${$lambda_expression(?body, *params)}): {
    Atom name = Atom.intern("?__lambda");
    List function = _lambda_function(name, _lambda_params(params), body);
    return %(code-value "bound" (expr $type (ident $name))
             ((new-name $name "lambda") (place (unit-support) $function)));
  }
  return node;
}
