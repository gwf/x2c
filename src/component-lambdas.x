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

/* The record `context`, with a field of each type in `types`. */
meta static Code _lambda_record(Atom context, List types) {
  Array fields = [];
  foreach (Type type, types) {
    (List base, List modifiers) = type.parts();
    List name = _lambda_field(fields.len());
    fields.push(%(declare $base (bindings (bind $name $modifiers))));
  }
  return %(typedef (static struct $context (fields @{fields.list_free()}))
           (bindings (bind $context ())));
}

/* The adapter `adapter` of the Func `closure` with arguments `argv`. It
   reads the arguments of `params` as `reads` says and calls `lifted` with
   them and with the field of the `context` record for each of `captures`;
   a reference passes what the address it holds refers to. */
meta static Code _lambda_adapter(
  Atom adapter, Atom closure, Atom argv, Atom lifted, Atom context,
  List params, List reads, List captures) {
  List record = x2c_ident("record");
  Array locals = [], arguments = [];
  foreach (List read, reads) {
    (Type type, Code value) = read;
    List name = x2c_ident(%"a${locals.len()}");
    locals.push($!{ $type $name = $value; });
    match (params.car()) {
      case %(param ? (bind ? (& *))): arguments.push($!( *$name ));
      default: arguments.push($!( $name ));
    }
    params = params.cdr();
  }
  int index = 0;
  foreach (List capture, captures) {
    List field = _lambda_field(index++);
    arguments.push(capture.caddr().list().car() == <&>
                   ? $!( *$record->$field ) : $!( $record->$field ));
  }
  return $!Unit{
    static Var $adapter(Func $closure, const FuncArg *$argv) {
      @{locals.list_free()}
      const struct $context *$record =
        (const struct $context *) Func.context($closure);
      return $lifted(@{arguments.list_free()});
    }
  };
}

/* The bridge `bridge` through which a public inline function makes the
   Func of `adapter` and its `context` record, whose fields have `types`. */
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
  return $!Unit{
    Func $bridge(@declared) {
      struct $context $record = { @values };
      return Func.new_context($adapter, $signature, &$record, sizeof $record);
    }
  };
}

/* The type of the record field that holds a capture of `type`: the
   referent's address for a reference, and otherwise a `Var`. */
meta static Type _lambda_field_type(Type type) =>
  type.car() == <&> ? cons(<*>, type.cdr()) : %("Var");

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
      setup.push(%(declare $base (bindings
        (op = (bind $local $modifiers) ${value.convert(stored)}))));
      values.push(%(expr $stored (ident $local)));
      types.push(stored);
    }
  List initial = values.list_free();
  Code made = NULL;
  if (_lambda_in_public_inline()) {
    Atom bridge = Atom.intern("?__lambda_bridge");
    effects.push(%(new-name $bridge ${_lambda_bridge_role()}));
    effects.push(%(place (unit-support) ${_lambda_bridge(
      bridge, adapter, context, signature, types.list_free())}));
    made = %(expr ("Func") (call (expr () (ident $bridge)) (args @initial)));
  }
  else {
    Atom storage = Atom.intern("?__lambda_storage");
    Type type = %(struct $context);
    Code record = %(expr $type (ident $storage));
    effects.push(%(new-name $storage "lambda_context"));
    setup.push(%(declare $type (bindings
      (op = (bind $storage ()) (expr $type (composite (commas @initial)))))));
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
      effects.push(%(place (unit-support)
        ${_lambda_record(context, fields.list_free())}));
      effects.push(%(place (unit-support) ${_lambda_function(
        lifted, _lambda_closure_params(params, reads, captures), body)}));
      effects.push(%(place (unit-support) ${_lambda_adapter(
        adapter, closure, argv, lifted, context, params, reads, captures)}));
      Code value = _lambda_value(
        effects, adapter, context, adapted.car(), captures);
      return %(code-value "bound" $value ${effects.list_free()});
    }
  return node;
}
