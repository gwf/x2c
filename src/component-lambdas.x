/*  component-lambdas.x -- lambda lowering

    A lambda becomes a static function among the unit's support
    declarations. Its parameters keep their declarators, a bare one is a
    `Var`, and it returns a `Var`: a bare return and the end of a block body
    return none, and an expression body returns its value. A noncapturing
    lambda's value is that function.

    A capturing lambda's function also takes each binding it captures, a
    value as its own type and a reference as a reference. Its value is a
    `Func` that copies each captured value, or the address a reference
    captures, into a context record when the lambda is evaluated, left to
    right. The `Func`'s adapter reads the arguments and calls the function
    with them and the record's fields. A public inline function reaches the
    unit's private record through a bridge function.

    A local or parameter that a lambda shares by reference moves into a
    Scope cell, so it outlives the function that declares it; a function
    rule rewrites each function definition whose lambdas share one.

    Each definition precedes the definitions that call it: the compiler
    settles whether a linked copy reaches a compile-time operation when the
    copy binds.
*/
#pragma once
#include "rewrite.x"
#include "grammar.x"
#include "ast-rewrite.x"

// rebuilding a body

/* The read `node` makes of a binding that `cells` maps to its cell, through
   that cell, or NULL: a reference reads the cell's address. */
meta static Code _lambda_cell_read(Var node, Map cells) {
  Var cell;
  match (node) case %(expr ?(Type read) (ident ?binding)):
    if (cells.try_get(binding, cell)) {
      (Atom name, Type type) = cell;
      if (read.car() == <&>) return %(expr $read (ident $name));
      Type pointer = cons(<*>, type);
      return %(expr $type
               (parens (expr $type (op * (expr $pointer (ident $name))))));
    }
  return NULL;
}

/* The declaration of the cell `name` that holds a `type` copied from
   `value`, or that a later assignment fills when `value` is NULL. */
meta static Code _lambda_cell(Atom name, Type type, Code value) {
  if (!value) return $!{ $type *$name = Scope_malloc(sizeof($type)); };
  if (!value.match(%(expr ? (composite ?)))) value = $!( { $value } );
  return $!{
    $type *$name = Scope_memdup((const void *)&($type)$value, sizeof($type));
  };
}

/* The cell declaration of `binding`, initialized from `value`, when `cells`
   maps it, recording the cell's name in `named`; or NULL. */
meta static Code _lambda_declared_cell(
  List binding, Code value, Map cells, Array named) {
  Var cell;
  if (!cells.try_get(binding, cell)) return NULL;
  (Atom name, Type type) = cell;
  named.push(%(new-name $name "lambda_cell"));
  return _lambda_cell(name, type, value);
}

/* The cell declaration of `binding`, initialized with its current value,
   as `_lambda_declared_cell` makes it. */
meta static Code _lambda_copied_cell(List binding, Map cells, Array named) {
  Var cell;
  if (!cells.try_get(binding, cell)) return NULL;
  Type type = cell.list().cadr();
  return _lambda_declared_cell(
    binding, %(expr $type (ident $binding)), cells, named);
}

/* The bindings that the destructuring declaration `node` declares. */
meta static List _lambda_targets(List node) {
  Array targets = [];
  match (node) {
    case %(dstrdecl (params *params) ?):
      foreach (List param, params)
        match (param) case %(param ? (bind ?binding ?)): targets.push(binding);
    case %(dstrdecl ? (targets *names) ?): return names;
  }
  return targets.list_free();
}

/* The bound `code`, kept as it is when the function that holds it binds
   again. */
meta static Code _lambda_kept(Code code) => %(code-value "lowered" $code ());

/* The block `items`, each kept unless `declaring` holds it. */
meta static List _lambda_kept_items(List items, Map declaring) {
  Array out = [];
  foreach (Var item, items)
    out.push(declaring.contains(item) ? item : _lambda_kept(item));
  return out.list_free();
}

/* Whether `item` names a binding that `cells` maps. */
meta static int _lambda_mentions(Var item, Map cells) {
  List node;
  $ast.walk(item, node)
    if (node.car() == <binding> && cells.contains(node)) return 1;
  return 0;
}

/* `node` with each binding it declares that `cells` maps declared as its
   cell: a declarator's cell takes its initializer, and a destructuring
   declaration copies each target into its cell after it. Only the cells
   are source to bind. */
meta static Var _lambda_declare_cells(List node, Map cells, Array named) {
  Array items = [];
  int celled = 0;
  match (node) {
    case %(declare ?base (bindings *bindings)):
      foreach (List item, bindings) {
        Code cell = NULL;
        match (item) {
          case %(bind ?binding *):
            cell = _lambda_declared_cell(binding, NULL, cells, named);
          case %(op = (bind ?binding *) ?value):
            cell = _lambda_declared_cell(binding, value, cells, named);
        }
        celled |= !!cell;
        items.push(
          cell ? cell : _lambda_kept(%(declare $base (bindings $item))));
      }
    case %(dstrdecl *): {
      items.push(_lambda_kept(node));
      foreach (List binding, _lambda_targets(node)) {
        Code copy = _lambda_copied_cell(binding, cells, named);
        if (copy) items.push(copy);
        celled |= !!copy;
      }
    }
  }
  return celled ? %(seq @{items.list_free()}) : node;
}

/* `ast` rebuilt bottom-up with a pending stack, except the body of each
   lambda it holds, which is the lambda's own: a bare return returns `none`
   when that is set, and each read and declaration of a binding that
   `cells` maps uses its cell, recording each cell's name in `named` and
   each rebuilt node that holds a cell declaration in `declaring`. A block
   that holds one keeps its other items as they are bound. An unchanged node
   is kept as it was. */
meta static Var _lambda_rebuild(
  Var ast, List none, Map cells, Array named, Map declaring) {
  Array pending = [ast], modes = [0], done = [];
  while (pending.len()) {
    Var node = pending.take_last();
    int mode = modes.take_last().int();
    if (mode == 1) {
      int first = done.len() - node.list().len(), index = first;
      Array parts = [];
      int changed = 0, declares = 0;
      foreach (Var part, node.list()) {
        changed |= done[index] != part;
        declares |= cells && declaring.contains(done[index]);
        parts.push(done[index++]);
      }
      done.truncate(first);
      List rebuilt = changed ? parts.list_free() : node;
      Var result = rebuilt;
      if (cells) result = _lambda_declare_cells(rebuilt, cells, named);
      if (result != rebuilt || declares) {
        if (result == rebuilt && rebuilt.car() == <block>)
          result = %(block @{_lambda_kept_items(rebuilt.cdr(), declaring)});
        declaring[result] = 1;
      }
      done.push(result);
      continue;
    }
    Code read = cells && !mode ? _lambda_cell_read(node, cells) : NULL;
    if (mode || node is not <list> || node.is_nil()) done.push(node);
    else if (none && node.list() === %(return)) done.push(none);
    else if (read) done.push(read);
    else {
      Array parts = [];
      foreach (Var part, node.list()) parts.push(part);
      int body = node.list().car() == <lambda> ? parts.len() - 1 : -1;
      pending.push(node);
      modes.push(1);
      for (int i = parts.len() - 1; i >= 0; i--) {
        pending.push(parts[i]);
        modes.push(i == body ? 2 : 0);
      }
    }
  }
  return done[0];
}

/* The return of a lambda that returns no value. */
meta static List _lambda_none(void) =>
  %(return ("Var") (expr ("Var") (literal ("Var") "void")));

/* The block `items` with each bare return returning `none`, rebuilt only
   when one returns outside the body of a lambda the items hold. */
meta static List _lambda_returning(List items, List none) {
  List node;
  $ast.walk(items, node) {
    if (node === %(return))
      return _lambda_rebuild(items, none, NULL, NULL, NULL);
    if (node.car() == <lambda>) continue;
  }
  return items;
}

/* The block items of the function that runs the lambda body `body`. An
   expression body keeps the origin of the item that holds the lambda, so
   lowering it later reports there. */
meta static List _lambda_items(Code body) {
  match (body) case %(block *items):
    return %(@{_lambda_returning(items, _lambda_none())} ${_lambda_none()});
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

/* A capturing lambda's parameters and then its `captures` as its
   function's, given the `reads` of its adapter: a reference parameter
   refers to the type the adapter reads, and a capture has its own type. */
meta static List _lambda_closure_params(
  List params, List reads, List captures) {
  Array out = [];
  foreach (List param, _lambda_params(params)) {
    Type read = reads.car().list().car();
    reads = reads.cdr();
    match (param) case %(param ? (bind ?binding (& *))): {
      Type reference = cons(<&>, read.cdr());
      (List base, List modifiers) = reference.parts();
      param = %(param $base (bind $binding $modifiers));
    }
    out.push(param);
  }
  foreach (List capture, captures)
    match (capture) case %(capture ?binding ?(Type type) ?): {
      (List base, List modifiers) = type.parts();
      out.push(%(param $base (bind $binding $modifiers)));
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

// capturing lambdas

/* Whether the function that holds the lambda being lowered is public
   inline, so its body reaches the unit's private declarations only through
   a bridge. */
meta static int _lambda_in_public_inline(void) {
  match (x2c_enclosing(<function>)) case %(function ?(Type type) *):
    return type.match(%(* inline *)) && !type.match(%(* static *));
  return 0;
}

/* The name of the bridge function, which carries the hash of the unit's
   path so that units whose public inline functions share a header link
   together. */
meta static String _lambda_bridge_role(void) {
  match (x2c_enclosing(<unit>))
    case %(expr ? (segments (segexp (expr ? (literal ? ?(String path)))))):
      return %"func_from_capture_${"%08x".printf(path.hash())}";
  return "func_from_capture";
}

/* The name of record field `index`. */
meta static List _lambda_field(int index) => x2c_ident(%"c$index");

/* The spelling of record field `index`, which names no binding. */
meta static List _lambda_member(int index) => %(${%"c$index"});

/* The type of the record field that holds a capture of `type`: the
   referent's address for a reference, and otherwise a `Var`. */
meta static Type _lambda_field_type(Type type) =>
  type.car() == <&> ? cons(<*>, type.cdr()) : %("Var");

/* The record `context`, with a field of each type in `types`, as bound
   code. */
meta static Code _lambda_record(Atom context, List types) {
  Array fields = [];
  foreach (Type type, types) {
    (List base, List modifiers) = type.parts();
    List name = _lambda_member(fields.len());
    fields.push(%(declare $base (bindings (bind $name $modifiers))));
  }
  return %(code-value "bound"
           (typedef (static struct $context (fields @{fields.list_free()}))
             (bindings (bind $context ())))
           ());
}

/* The adapter `adapter` of the Func `closure` with arguments `argv`, as
   bound code. It reads the arguments of `params` as `reads` says into
   locals and calls `lifted`, whose parameters are `declared`, with them
   and with the field of the `context` record for each of `captures`; a
   reference passes what the address it holds refers to. */
meta static Code _lambda_adapter(
  Atom adapter, Atom closure, Atom argv, Atom lifted, Atom context,
  List params, List reads, List captures, List declared) {
  Type pointer = %(* const struct $context);
  Code record = %(expr $pointer (ident ("record")));
  Array items = [], arguments = [];
  foreach (List read, reads) {
    (Type type, Code value) = read;
    List name = %(${%"a${items.len()}"});
    (List base, List modifiers) = type.parts();
    items.push(
      %(declare $base (bindings (op = (bind $name $modifiers) $value))));
    Code local = %(expr $type (ident $name));
    match (params.car()) {
      case %(param ? (bind ? (& *))):
        arguments.push(%(expr ${type.cdr()} (op * $local)));
      default: arguments.push(local);
    }
    params = params.cdr();
  }
  Code context_read = %(expr (* const void)
    (call (expr ((func (("Func"))) * const void) (ident ("Func_context")))
      (args (expr ("Func") (ident $closure)))));
  items.push(%(declare (const struct $context)
    (bindings (op = (bind ("record") (*))
                   (expr $pointer (cast $pointer $context_read))))));
  int index = 0;
  foreach (List capture, captures) {
    Type type = capture.caddr(), stored = _lambda_field_type(type);
    Code field = %(expr (const @stored)
                    (op -> $record ${_lambda_member(index++)}));
    arguments.push(
      type.car() == <&> ? %(expr ${type.cdr()} (op * $field)) : field);
  }
  Code call = %(expr ("Var")
    (call (expr ((func $declared) "Var") (ident $lifted))
      (args @{arguments.list_free()})));
  items.push(%(return $call));
  return %(code-value "bound"
           (function (static "Var")
             (bind $adapter
               ((fnmod (params (param ("Func") (bind $closure ()))
                               (param (const "FuncArg") (bind $argv (*)))))))
             (block @{items.list_free()}))
           ());
}

/* The bridge `bridge` through which a public inline function makes the
   Func of `adapter` and its `context` record, whose fields have `types`.
   The adapter is bound code, so the bridge names it as a typed value. */
meta static Code _lambda_bridge(
  Atom bridge, Atom adapter, Atom context, Code signature, List types) {
  List record = x2c_ident("record");
  Array parameters = [], fields = [];
  foreach (Type type, types) {
    (List base, List modifiers) = type.parts();
    List field = _lambda_field(fields.len());
    parameters.push(%(param $base (bind $field $modifiers)));
    fields.push($!( $field ));
  }
  List declared = parameters.list_free(), values = fields.list_free();
  Code made = %(expr ("FuncAdapter") (ident $adapter));
  return $!Unit{
    Func $bridge(@declared) {
      struct $context $record = { @values };
      return Func.new_context($made, $signature, &$record, sizeof $record);
    }
  };
}

/* The bound value of a capturing lambda: it evaluates its `captures`, left
   to right, into locals, and makes a Func of `adapter` from a `context`
   record of them. Effects that name and place its parts are pushed onto
   `effects`. */
meta static Code _lambda_value(
  Array effects, Atom adapter, Atom context, Code signature,
  List captures) {
  Array setup = [], values = [], types = [];
  foreach (List capture, captures)
    match (capture) case %(capture ? ?(Type type) ?(Code value)): {
      Type stored = _lambda_field_type(type);
      (List base, List modifiers) = stored.parts();
      Atom local = Atom.intern(%"?__lambda_capture_${types.len()}");
      effects.push(%(new-name $local "lambda_capture_value"));
      Code converted = value.convert(stored);
      setup.push(
        %(declare $base
          (bindings (op = (bind $local $modifiers) $converted))));
      values.push(%(expr $stored (ident $local)));
      types.push(stored);
    }
  List initial = values.list_free();
  Code made = NULL;
  if (_lambda_in_public_inline()) {
    Atom bridge = Atom.intern("?__lambda_bridge");
    effects.push(%(new-name $bridge ${_lambda_bridge_role()}));
    Code bridged = _lambda_bridge(
      bridge, adapter, context, signature, types.list_free());
    effects.push(%(place (unit-support) $bridged));
    made = %(expr ("Func") (call (expr () (ident $bridge)) (args @initial)));
  }
  else {
    Atom storage = Atom.intern("?__lambda_storage");
    Type type = %(struct $context);
    Code record = %(expr $type (ident $storage));
    effects.push(%(new-name $storage "lambda_context"));
    Code initial_record = %(expr $type (composite (commas @initial)));
    setup.push(
      %(declare $type (bindings (op = (bind $storage ()) $initial_record))));
    made = %(expr ("Func") (call "Func_new_context" (args
      (expr () (ident $adapter)) $signature
      (expr (* @type) (op & $record)) (expr ("size_t") (sizeof $record)))));
  }
  return %(expr ("Func")
           (parens (block @{setup.list_free()} (stmnt $made))));
}

$rewrite($lambda_captured)
/** Lifts the capturing lambda `node` to a static function of its
    parameters and captures, and answers a `Func` of a record of the
    captured values and addresses. */
meta Code lambda_closure(Code node) {
  match (node)
    case %(expr ? ${$lambda_captured(?body, *captures, *params)}): {
      Atom lifted = Atom.intern("?__lambda");
      Atom adapter = Atom.intern("?__lambda_adapter");
      Atom closure = Atom.intern("?__lambda_closure");
      Atom argv = Atom.intern("?__lambda_argv");
      Atom context = Atom.intern("?__lambda_context");
      Array effects = [
        %(new-name $lifted "lambda"), %(new-name $adapter "lambda"),
        %(new-name $closure "lambda_closure"), %(new-name $argv "lambda_argv"),
        %(new-name $context "lambda_context")];
      List adapted = Code.func_parameters(
        params, %(expr ("Func") (ident $closure)),
        %(expr (* const "FuncArg") (ident $argv)));
      List reads = adapted.cdr();
      Array fields = [];
      foreach (List capture, captures)
        fields.push(_lambda_field_type(capture.caddr()));
      Code record_type = _lambda_record(context, fields.list_free());
      List declared = _lambda_closure_params(params, reads, captures);
      Code function = _lambda_function(lifted, declared, body);
      Code adapter_function = _lambda_adapter(
        adapter, closure, argv, lifted, context, params, reads, captures,
        declared);
      effects.push(%(place (unit-support) $record_type));
      effects.push(%(place (unit-support) $function));
      effects.push(%(place (unit-support) $adapter_function));
      Code value = _lambda_value(
        effects, adapter, context, adapted.car(), captures);
      return %(code-value "bound" $value ${effects.list_free()});
    }
  return node;
}

// shared cells

/* The binding whose object the lvalue `value` names: through parentheses,
   an array element, and a member, since the cell holds the whole object;
   or NULL. */
meta static List _lambda_designated(Var value) {
  for (;;) {
    match (value) {
      case %(expr ? ?inner): value = inner;
      case %(parens ?inner): value = inner;
      case %(index (!set ?base (expr ((dim *) *) ?)) ?): value = base;
      case %(op . ?base *): value = base;
      case %(ident (!set ?binding (binding ? ?))): return binding;
      default: return NULL;
    }
  }
}

/* Each automatic binding of `params` and `items` that a lambda directly
   in `items` shares by reference, mapped to `(CELL TYPE)`: a name for its
   cell and the binding's type. */
meta static Map _lambda_shared(List params, List items) {
  Map declared = {}, shared = {}, cells = {};
  foreach (List param, params)
    match (param) case %(param ? (bind ?binding *)): declared[binding] = 1;
  List node;
  $ast.walk(items, node) match (node) {
    case %(declare (!set ?base (* static *)) *): continue;
    case %(bind ?binding *): declared[binding] = 1;
    case %(dstrdecl *):
      foreach (List binding, _lambda_targets(node)) declared[binding] = 1;
    case %(lambda *parts): {
      foreach (List part, parts)
        match (part) case %(captures *rows):
          foreach (List row, rows)
            match (row)
              case %(capture ? (& *type) (expr ? (op & ?target))): {
                List binding = _lambda_designated(target);
                if (binding) shared[binding] = type;
              }
      continue;
    }
  }
  foreach (Var (binding, type), shared)
    if (declared.contains(binding)) {
      Atom name = Atom.intern(%"?__lambda_cell_${cells.len()}");
      cells[binding] = %($name $type);
    }
  return cells;
}

$rewrite(%(function ? (bind ? ((fnmod (params *)))) (block *)))
/** Moves each local and parameter of the function `node` that a lambda in
    its body shares by reference into a Scope cell, so the binding outlives
    the call: a parameter is copied into its cell at entry, a local is
    declared as its cell, and every read goes through the cell. A lifted
    lambda's function moves its own. */
meta Code lambda_cells(Code node) {
  match (node)
    case %(function ?type
           (!set ?declarator (bind ? ((fnmod (params *params))))) ?): {
      List items = Code.body(node);
      Map cells = _lambda_shared(params, items);
      if (!cells.len()) return node;
      Array named = [], entry = [];
      foreach (List param, params)
        match (param) case %(param ? (bind ?binding *)): {
          Code cell = _lambda_copied_cell(binding, cells, named);
          if (cell) entry.push(cell);
        }
      Map declaring = {};
      Array body = [];
      foreach (Var item, items)
        body.push(
          _lambda_mentions(item, cells)
            ? _lambda_rebuild(item, NULL, cells, named, declaring) : item);
      List kept = _lambda_kept_items(body.list_free(), declaring);
      return %(code-value "source"
               (function $type $declarator
                 (block @{entry.list_free()} @kept))
               ${named.list_free()});
    }
  return node;
}
