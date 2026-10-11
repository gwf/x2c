/*  component-destructuring.x -- flat List destructuring

    A destructuring reads its source once as a `List` and gives each target
    the element at its position, left to right; the compiler converts each
    element as an ordinary assignment or initialization does. The parser has
    declared the targets, so each rule answers bound code that keeps their
    bindings: `T (a, b) = source;` declares `a` and `b` before the read,
    `(T1 a, T2 b) = source;` declares each initialized from its element, an
    assignment statement reads in its own block, and an assignment
    expression keeps its source in a result local as its value. The List
    local and the result local are fresh names the carrier asks for.
*/
#pragma once
#include "rewrite.x"

/* The List `source` holds, converted as a List destination converts it.
   A numeric source is reported before conversion, which would otherwise
   report an integer reaching a pointer. */
meta static Code _destructure_list(Code source) {
  Code converted =
    source.type().numeric() ? NULL : source.convert(%("List"));
  if (!converted || !converted.type().is_named("List"))
    x2c_diagnostic_fail_at(
      NULL, <type>, "destructuring requires a List source", NULL);
  return converted;
}

/* The declaration of the List local `values` that reads `source`. */
meta static List _destructure_read(Atom values, Code source) =>
  %(declare ("List")
     (bindings (op = (bind $values ()) ${_destructure_list(source)})));

/* The element at `index` of the List local `values`. */
meta static Code _destructure_element(Atom values, int index) {
  String position = %"$index";
  return %(expr ("Var")
           (getindex (expr ("List") (ident $values))
                     (literal (int) $position)));
}

/* Assigns each of `targets`, typed expressions, its element of `values`. */
meta static List _destructure_writes(List targets, Atom values) {
  Array writes = [];
  int index = 0;
  foreach (Code target, targets) {
    Type type = target.cadr();
    Code element = _destructure_element(values, index++);
    writes.push(%(stmnt ${$!($type){ $target = $element }}));
  }
  return writes.list_free();
}

/* Bound `code` whose `values` token, and `result` token when there is
   one, name fresh locals. */
meta static Code _destructure_bound(List code, Atom values, Atom result) {
  List names = %((new-name $values "destructure"));
  if (result) names = cons(%(new-name $result "destructure_result"), names);
  return %(code-value "bound" $code $names);
}

$rewrite(%(dstrdecl *))
/** Declares the names of `T (a, b) = source;` and then reads the source
    into them, or declares each target of `(T1 a, T2 b) = source;`
    initialized from its element. */
meta Code destructure_declaration(Code node) {
  Atom values = Atom.intern("?__destructure");
  match (node) {
    case %(dstrdecl (params *parameters) ?source): {
      Array items = [_destructure_read(values, source)];
      int index = 0;
      foreach (List parameter, parameters)
        match (parameter) case %(param ?base ?declarator): {
          Code element = _destructure_element(values, index++);
          items.push(%(declare $base (bindings (op = $declarator $element))));
        }
      return _destructure_bound(%(seq @{items.list_free()}), values, NULL);
    }
    case %(dstrdecl ?(Type type) (targets *names) ?source): {
      Array declarators = [], targets = [];
      foreach (Var name, names) {
        declarators.push(%(bind $name ()));
        targets.push(%(expr $type (ident $name)));
      }
      return _destructure_bound(
        %(seq (declare $type (bindings @{declarators.list_free()}))
              ${_destructure_read(values, source)}
              @{_destructure_writes(targets.list_free(), values)}),
        values, NULL);
    }
  }
  return node;
}

$rewrite(%(stmnt (expr ? (dstrasgn *))))
/** Reads the source of `(a, b) = source;` into its targets in a block. */
meta Code destructure_statement(Code node) {
  match (node)
    case %(stmnt (expr ? (dstrasgn (targets *targets) ?source))): {
      Atom values = Atom.intern("?__destructure");
      return _destructure_bound(
        %(block ${_destructure_read(values, source)}
                @{_destructure_writes(targets, values)}),
        values, NULL);
    }
  return node;
}

$rewrite(%(expr ? (dstrasgn *)))
/** Reads the source of `(a, b) = source` into its targets, and keeps the
    source in a result local as the expression's value. */
meta Code destructure_value(Code node) {
  match (node)
    case %(expr ?(Type type) (dstrasgn (targets *targets) ?source)): {
      Atom values = Atom.intern("?__destructure");
      Atom result = Atom.intern("?__destructure_result");
      (List base, List modifiers) = type.parts();
      Code kept = %(expr $type (ident $result));
      List block = %(block
        (declare $base (bindings (op = (bind $result $modifiers) $source)))
        ${_destructure_read(values, kept)}
        @{_destructure_writes(targets, values)}
        (stmnt $kept));
      return _destructure_bound(
        %(expr $type (parens $block)), values, result);
    }
  return node;
}
