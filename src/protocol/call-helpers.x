/*  call-helpers.x -- generated call helpers */

static typedef struct DiscardCall {
  Compiler c;
  List binding, key;
  Type signature, result;
  String stem;
  List declarations, arguments;
  Array discards;
  int which, fresh, exported;
} DiscardCall;

// update helpers

/** Returns a generated helper for a direct protocol-backed update.
    The resolved member must have exactly `(Participant, RHS) -> Participant`,
    where the receiver and result may be any typedef that resolves to the
    participant's type. A matching helper is emitted once into the unit's
    pending support; `postfix` selects whether it returns the old or stored
    value. A public inline body's helper has external linkage. Returns null
    when the member cannot implement this update shape.
*/
String Compiler.protocol_update_helper(
  Compiler c, Type participant, String member, int postfix) {
  int exported = _exported(c);
  List key =
    $("protocol-update-helper", participant, member, postfix, exported);
  Var stored;
  if (c.protocol_helpers.try_get(key, stored)) return stored;
  String name = _update_helper(c, participant, member, postfix, exported);
  if (name) c.protocol_helpers[key] = name;
  return name;
}

/** Returns `call`, which calls the generated protocol helper `name` from
    the code being lowered. A public inline body's helper has external
    linkage, and the unit's header carries that body too, so there the call
    declares the helper first.
*/
List Compiler.protocol_helper_call(Compiler c, String name, List call) {
  if (!_exported(c)) return call;
  Type type = NULL;
  List binding = c.sym.resolve_global($(name), type);
  return %(parens (block $(type.declaration_ast(binding))
                    (stmnt (expr $(type.apply()) $call))));
}

// discard helpers

/** The `discard_helper` for `participant`'s protocol `member`. */
List Compiler.protocol_discard_helper(
  Compiler c, Type participant, String member, int which) {
  List resolved = c.resolve_protocol_member(participant, member);
  if (!resolved) return NULL;
  List (binding, signature) = resolved;
  String stem = %"$(participant.car().str().lower())_$member";
  return c.discard_helper(binding, signature, stem, which);
}

/** Returns `(binding signature)` for a generated helper that calls the
    function `binding` of type `signature` and then discards the unnamed
    argument temporaries `which` selects (bit `n` for argument `n`). A
    discarded argument is one the compiler produced for this call alone, so
    its `discard` member may release what it owns before the enclosing scope
    ends. A public inline body's helper has external linkage. Returns null
    when no selected argument type has a `discard` member, or an ordinary
    pointer or aggregate result may borrow an argument.
*/
List Compiler.discard_helper(
  Compiler c, List binding, Type signature, String stem, int which) {
  int exported = _exported(c);
  List key = $("discard-helper", stem, which, exported);
  Var stored;
  if (c.protocol_helpers.try_get(key, stored)) return stored;

  Type result = signature.cdr();
  Type resolved_result = c.sym.resolve_key(result);
  long callee_identity = (long) binding;
  int fresh = %"fresh-callee $callee_identity" in c.protocol_helpers;
  /* An ordinary call may return its input or a view into it. Without a
     fresh-result contract, keep that input alive in its enclosing scope. */
  if (!fresh && (resolved_result.is_pointer() ||
                 resolved_result.is_aggregate()))
    return NULL;
  (List declarations, List arguments) =
    c.forward_parameters(signature.car().list().cadr());
  DiscardCall call = {
    .c = c, .binding = binding, .key = key, .signature = signature,
    .result = result, .stem = stem, .which = which, .fresh = fresh,
    .exported = exported, .declarations = declarations,
    .arguments = arguments, .discards = []};
  _collect(call);
  return call.discards.len() ? _emit(call) : NULL;
}

// forwarding wrappers

/** Returns the function `result name(params) { body }` bound in this
    unit. `result` is the storage class and result type, so static, inline
    and external helpers share it; `params` are the parameter declarations,
    and `body` its lowered statements.
*/
List Compiler.wrapper_function(
  Compiler c, Type result, List binding, List params, List body) {
  List lowered = Code.lowered(%(seq @body), NULL);
  return _generated_function(
    c, binding, $!Unit{ $result $binding(@params) { $lowered } });
}

/** Returns `(declarations arguments)` for a helper that forwards its
    parameters of `types`: each declaration names a fresh parameter `a0`,
    `a1`, ..., and each argument reads it. A rest parameter forwards its
    List elements or Map entries with an explicit splice.
*/
List Compiler.forward_parameters(Compiler c, List types) {
  Array declarations = [], arguments = [];
  int index = 0;
  foreach (Type type in types) {
    List binding = c.sym.introduce(%"a$(index++)");
    declarations.push(type.parameter_ast(binding));
    Type container = type.rest_container();
    if (container) {
      List value = $!($container){ $binding };
      arguments.push(%(expr $container (splice $value)));
    }
    else arguments.push($!($type){ $binding });
  }
  return $(declarations.list_free(), arguments.list_free());
}

// generated call helpers

/* Whether the code being parsed or lowered belongs to a public inline
   function. The unit's header carries that body too, so a helper it calls
   needs external linkage. */
static int _exported(Compiler c) {
  if (c.enclosing(<function>) ~= %(function ?(Type type) *))
    return type.is_inline() && !type.is_static();
  return 0;
}

/* Publishes the update helper of `participant`'s `member` and returns its
   name, or returns NULL when the member cannot implement the update. */
static String _update_helper(
  Compiler c, Type participant, String member, int postfix, int exported) {
  List resolved = c.resolve_protocol_member(participant, member);
  if (!resolved) return NULL;
  List (source_binding, source_type) = resolved;
  Type rhs_type = _update_rhs(c, participant, source_type);
  if (!rhs_type) return NULL;

  String suffix = postfix ? "postfix" : "update";
  String name = _helper_name(
    c, %"proto_$(participant.car().str().lower())_$(member)_$suffix",
    exported);
  List helper = c.sym.introduce(name);
  List callee = $!($source_type){ $source_binding };
  Type result = exported ? participant : %(static @participant);
  /* A direct update stores the member's result through `lhs`; the `op`
     parameter keeps the update ABI of the dynamic path. The postfix form
     adds one and returns the value it read first. */
  List update = postfix
    ? $!Unit{
        $result $helper(volatile $participant *lhs, Symbol op) {
          $participant old = lhs[0];
          lhs[0] = $callee(lhs[0], 1);
          return old;
        }
      }
    : $!Unit{
        $result $helper(
            volatile $participant *lhs, Symbol op, $rhs_type rhs) {
          lhs[0] = $callee(lhs[0], rhs);
          return lhs[0];
        }
      };
  _publish_update(c, helper, update);
  return name;
}

/* The `RHS` of a member `(Participant, RHS) -> Participant`, or NULL. Its
   receiver and result may be any typedef that resolves to the participant's
   type, as the member an inherited adoption selects is. */
static Type _update_rhs(Compiler c, Type participant, Type signature) {
  List parameters = signature.car().list().cadr();
  Type self = c.sym.resolve_key(participant);
  if (parameters ~= %(?(Type receiver) ?rhs) &&
      c.sym.resolve_key(receiver) == self &&
      c.sym.resolve_key(signature.cdr()) == self)
    return rhs;
  return NULL;
}

/* The generated helper name for `stem`. An `exported` name ends in the hash
   of the unit's path, so units whose headers call such helpers link
   together, as lambda bridges do. */
static String _helper_name(Compiler c, String stem, int exported) {
  String name = %"_x2c_gensym_$stem";
  return exported ? %"$(name)_$("%08x".printf(c.filename.hash()))" : name;
}

static void _publish_update(Compiler c, List helper, List syntax) {
  List function = _generated_function(c, helper, syntax);
  if (function ~= %(function ?result ?declarator (block *body)))
    function = %(function $result $declarator
                  (block (at $(c.origin) (seq @body))));
  c.add_early(function);
}

/* Binds `syntax`, a template that defines the function `binding`. The
   template's own definition is not authored API of this unit; a documented
   prototype the function completes keeps its prose. */
static List _generated_function(Compiler c, List binding, List syntax) {
  List key = %(api-definition $binding);
  Var authored;
  int documented = c.semantic_binding_facts().try_get(key, authored);
  List function = c.bind_syntax(syntax, <unit>, NULL);
  if (documented) c.set_fact(key, authored);
  else c.drop_fact(key);
  return function;
}

static void _collect(DiscardCall &d) {
  int index = 0;
  foreach (List argument in d.arguments) {
    if (d.which & (1 << index++)) {
      List drop = d.c.resolve_protocol_member(argument.cadr(), "discard");
      if (drop) d.discards.push($!{ $(drop.car())($argument); });
    }
  }
}

/* The helper is a unit-level function, so it binds at file scope whatever
   local scope is open, as placed unit support does. */
static List _emit(DiscardCall &d) {
  Block local = d.c.sym.close_local_scopes();
  defer d.c.sym.reopen_scopes(local);
  String name =
    _helper_name(d.c, %"discard_$(d.stem)_$(d.which)", d.exported);
  List helper_binding = d.c.sym.introduce(name);
  List value = d.c.sym.introduce("value");
  List call = d.c.bind_syntax(
    $!( $(d.binding)(@(d.arguments)) ), <expression>, d.result);
  List drops = d.discards.list_free();
  List shape = d.result == %(void)
    ? $!{ $call; @drops return; }
    : $!{ $(d.result) $value = $call; @drops return $value; };
  List body = d.c.bind_syntax(shape, <block>, d.result);
  Type storage = d.exported ? d.result : %(static @(d.result));
  List helper = d.c.wrapper_function(
    storage, helper_binding, d.declarations, body.cdr());
  d.c.add_early(helper);
  List entry = $(helper_binding, d.signature);
  d.c.protocol_helpers[d.key] = entry;
  /* Wrapping a call preserves its return ownership. Discarding an argument
     does not make an arbitrary method's borrowed result fresh. */
  long identity = (long) helper_binding;
  d.c.protocol_helpers[%"discard-helper $identity"] = 1;
  if (d.fresh) d.c.protocol_helpers[%"fresh-callee $identity"] = 1;
  return entry;
}
