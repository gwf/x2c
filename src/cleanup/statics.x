/*  statics.x -- runtime static initialization */

/* The pending nodes of one static initializer, each read as a value or as
   an address. `runtime` holds the function-local statics already known to
   run at runtime, or is `NULL` at file scope. */
static typedef struct RuntimeScan {
  Compiler c;
  Map runtime;
  Array pending, modes;
} RuntimeScan;

// static initializers

/** Reports whether the static initializer `value` has to run at runtime,
    because it calls, allocates, or reads an object other than a function
    name. `runtime` holds the function-local statics already known to run
    that way, or is `NULL` at file scope.
*/
int Compiler.static_value_is_runtime(Compiler c, List value, Map runtime) {
  auto Array pending = [], modes = [];
  RuntimeScan s = {
    .c = c, .runtime = runtime, .pending = pending, .modes = modes
  };
  _push(s, value, 0);
  while (pending.len()) {
    List node = pending.take_last();
    int address = modes.take_last();
    int result = address ? _address(s, node) : _value(s, node);
    if (result > 0) return 1;
    if (result < 0)
      foreach (Var child in node) if (child is <list>) _push(s, child, 0);
  }
  return 0;
}

/* -1 means descend, 0 means this node is handled, 1 means runtime. */
static int _value(RuntimeScan &s, List node) {
  match (node) {
    case %((!or cache call var array map varray vmap initval cons append) *):
      return 1;
    case %(expr ?type (ident ?binding)):
      return _identifier(s, type, binding);
    case %(expr ? (op & ?inner)):
      return _push(s, inner, 1);
    case %(expr ?type (!set ?content
        $($indexed(?receiver, ?selector)))): {
      Type native = type;
      if (native.is_array()) return _push(s, content, 1);
      if (native.is_pointer() || !(<const> in native)) return 1;
      break;
    }
    case %(expr ? $($sizeof_expression(?operand))):
      return _sizeof_dimensions(s, operand);
  }
  return -1;
}

/* The operand of sizeof is unevaluated except for VLA dimensions. Inspect
   those dimensions through the same static-input classifier as an ordinary
   initializer, without evaluating calls in a fixed-size operand. */
static int _sizeof_dimensions(RuntimeScan &s, List operand) {
  List node;
  $ast.walk(operand, node) if (node ~= %(dim ?dimension)) {
    if (dimension && s.c.static_value_is_runtime(dimension, s.runtime))
      return 1;
    continue;
  }
  return 0;
}

static int _identifier(RuntimeScan &s, Type type, List binding) {
  if (_input(s, binding)) return 1;
  if (%(function $binding) in s.c.semantic_binding_facts()) return 0;
  Type native = type;
  return native && !native.is_enum() && !native.is_function() &&
         !native.is_array() &&
         (native.is_pointer() || !(<const> in native));
}

static int _address(RuntimeScan &s, List node) {
  match (node) {
    case %(!or (expr ? ?inner)
        $($grouped(?inner))
        (op . ?inner ?)):
      return _push(s, inner, 1);
    case %(ident ?binding): return _input(s, binding);
    case $($indexed(%(!set ?base (expr ?type ?)), ?index)): {
      _push(s, index, 0);
      return _push(s, base, type.list().type().is_array());
    }
    case %(op (!quote *) ?inner):
      return _push(s, inner, 0);
  }
  return 1;
}

/* Queues `node` to be read as an address or a value; the 0 it returns
   means the caller's node is handled. */
static int _push(RuntimeScan &s, Var node, int address) {
  s.pending.push(node);
  s.modes.push(address);
  return 0;
}

/* A runtime static or an automatic object read where the initializer runs. */
static int _input(RuntimeScan &s, List binding) =>
  (s.runtime && binding in s.runtime) ||
  _automatic_static_input(s.c, binding);

static int _automatic_static_input(Compiler c, List binding) {
  Var automatic, stored;
  Map facts = c.semantic_binding_facts();
  if (!facts.try_get(%(automatic $binding), automatic) ||
      !automatic) return 0;
  if (!facts.try_get(%(type $binding), stored)) return 1;
  Type type = stored;
  return !type.is_static() && !type.is_extern() && !type.is_threaded();
}

/* A static local whose initializer runs at runtime protects the remainder
   of its block just as a cleanup region does: a jump may not enter past the
   initializer. Keeping the canonical binding makes shadowing and generated
   syntax use the same object reference. */
module List _static_regions(Compiler c, List ast, Map runtime) {
  match (ast) {
    case %(expr *):
      return _rewrite_expression(
        ast, %!(List block) => _static_regions(c, block, runtime));
    case %((!or function localinit typedef "x2c.quoted") *): return ast;
    case %(try *): return _landing_form(c, ast, runtime);
    case %(declare ?type ?bindings):
      return _static_initializers(c, type, bindings, runtime);
    case %(block *statements): {
      Array before = [];
      for (List rest = statements; rest; rest = rest.cdr()) {
        List statement = rest.car();
        if (_runtime_static_declaration(c, statement, runtime)) {
          List guard = _static_regions(c, statement, runtime);
          List body = _static_regions(
            c, %(block @(rest.cdr())), runtime);
          before.push(%(localinit $guard $body));
          break;
        }
        before.push(_static_regions(c, statement, runtime));
      }
      return %(block @(before.list_free()));
    }
  }
  Var child;
  $ast.rewrite_children(ast, child, _static_regions(c, child, runtime));
}

/* A `try` takes its statement rule's replacement, which holds its lowered
   parts as they are and lowers only the rest. A `try` that a `defer`
   wrote is not source, so only the shipped rule lowers it. Landing rows
   and ordinary replacements both pass through static-region processing. */
static List _landing_form(Compiler c, List node, Map runtime) {
  int written = 0;
  if (node ~= %(try ?body () ?finalizer kernel)) {
    node = %(try $body () $finalizer);
    written = 1;
  }
  List form = written
    ? c.rewrite_written(<try>, node, c.return_type)
    : c.rewrite_lowered(
      <node>, <try>, node, <statement>, c.return_type, NULL);
  if (form ~= %(landing ?code ?rows)) {
    Array parts = [];
    foreach (List row in rows)
      match (row) {
        case %((!or ?kind outer region) ?token ?part):
          parts.push($(kind, token, _static_regions(c, part, runtime)));
        default: parts.push(row);
      }
    return %(landing $code $(parts.list_free()));
  }
  if (!form) return node;
  return _static_regions(c, c.lower_replacement(form, node), runtime);
}

/* The pending initializer and the emitter share one cleanup record. Its
   region ends before the initialized object protects the rest of the block. */
static List _static_initializers(
  Compiler c, Type type, List bindings, Map runtime) {
  Array output = [];
  foreach (List binding in bindings.cdr()) {
    if (binding ~= %(op = ?declaration ?value)) {
      declaration = _static_regions(c, declaration, runtime);
      List initial = _static_regions(c, value, runtime);
      if (type.is_static() && c.static_value_is_runtime(value, runtime)) {
        List record = _region_binding(c, "static_cleanup");
        initial = %(staticinit $record $initial);
      }
      output.push(%(op = $declaration $initial));
      continue;
    }
    output.push(_static_regions(c, binding, runtime));
  }
  return %(declare $type (bindings @(output.list_free())));
}

static int _runtime_static_declaration(
  Compiler c, List node, Map runtime) {
  int found = 0;
  match (node) {
    case %(at ? ?body): return _runtime_static_declaration(c, body, runtime);
    case %(declare (!set ?type (*)) (bindings *bindings)):
      if (type.list().type().is_static())
        foreach (List binding in bindings)
          if (binding ~= %(op = (bind ?name ?) ?value) &&
              c.static_value_is_runtime(value, runtime)) {
            runtime[name] = 1;
            found = 1;
          }
  }
  return found;
}
