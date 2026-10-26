/*  protocol-adapters.x -- protocol adapters and Var descriptors

    Lowers resolved `conform` forms from `src/protocol/adapters.x` into
    support functions and Var descriptors. The producer settles each
    member's owner and storage, collisions, missing conversions, and
    generated names. This component places functions and method tables in
    unit support, and table assignments and descriptor registrations in
    unit initialization.

    Each definition precedes the definitions that call it: the compiler
    settles whether a linked copy reaches a compile-time operation when the
    copy binds.
*/
#pragma once
#include "rewrite.x"

/* The parameters `a0`, `a1`, ... of the signature `target`, the callee
   `source`, and the arguments that forward the parameters to it. A
   parameter that the protocol's `template` types `binder` passes through
   the converter `convert`. */
meta static List _protocol_forward(
  Type target, String source, Type template, String binder, String convert) {
  List templates = template.car().list().cadr();
  Array params = [], arguments = [];
  int index = 0;
  foreach (Type type in target.car().list().cadr()) {
    List name = x2c_ident(%"a$(index++)");
    params.push($!Param{ $type $name });
    Code argument = $!( $name );
    if (templates.car() == $(binder))
      argument = $!( $(x2c_ident(convert))($argument) );
    if (type == %(....))
      argument = %(expr ("List") (splice $argument));
    arguments.push(argument);
    templates = templates.cdr();
  }
  return $(params.list_free(), x2c_ident(source), arguments.list_free());
}

/* The function `name`, declared `declared`, that returns the call
   `forward` gives with its parameters. */
meta static Code _protocol_function(List declared, List name, List forward) {
  List params = forward.car(), args = forward.caddr();
  Code callee = forward.cadr();
  return $!Unit{ $declared $name(@params) { return $callee(@args); } };
}

/* Whether the thunk of `member` prints a boxed `participant` struct or
   union. That copy has an identity only before unboxing, so its thunk
   guards the rendering path. */
meta static int _protocol_renders(String member, Type participant) {
  if (!(member in %("str" "repr" "write_str" "write_repr"))) return 0;
  match (Type.resolve(participant)) case %((!or struct union) *): return 1;
  return 0;
}

/* The thunk `name` of `member` with the result type `result`, which
   returns the pointer's fallback rendering for a repeated visit along
   one rendering path. */
meta static Code _protocol_guarded(
  String member, List name, Type result, List forward) {
  List params = forward.car(), args = forward.caddr();
  Code callee = forward.cadr();
  Code value = x2c_ident("a0");
  Code fallback = member == "str" || member == "repr"
    ? $!( Var_pointer_string($value) )
    : $!( Var_write_pointer_repr($value, $(x2c_ident("a1"))) );
  return $!Unit{
    static inline $result $name(@params) {
      RenderPath render_path;
      if (!RenderPath_enter(&render_path, Var_pointer($value)))
        return $fallback;
      defer RenderPath_leave(&render_path);
      return $callee(@args);
    }
  };
}

/* The prototype of `name` with the signature `expected`. */
meta static Code _protocol_prototype(List name, Type expected) {
  Array params = [];
  foreach (Type type in expected.car().list().cadr()) {
    (List base, List modifiers) = type.parts();
    params.push(%(param $base (bind () $modifiers)));
  }
  Type result = expected.cdr();
  List declared = params.list_free();
  return $!Unit{ $result $name(@declared); };
}

/* Places the method table `methods`, its assignment from `slots`, and the
   registration of the descriptor `name`. */
meta static void _protocol_descriptor(List descriptor, List slots) {
  match (descriptor)
    case %(?(List methods) ?(String name) ?(Symbol var_tag) ?(Symbol area)
           *explicit): {
      Code table = %(expr ("VarMethods") (ident $methods));
      List init = %(unit-init $area);
      x2c_place(%(unit-support), $!Unit{ static VarMethods $methods; });
      /* A table with no slots stays zero, which avoids an empty
         initializer that C accepts only from C23 on. */
      if (slots) x2c_place(init, $!{ $table = (VarMethods){ @slots }; });
      Code text = %(expr ("String") (call "String_new" (args
        (expr (* char) (literal (* char) $(%"\"$name\""))))));
      if (explicit) {
        Code tag = $!Symbol{ $(explicit.car()) };
        x2c_place(
          init, $!{ x2c_register_tagged_descriptor($tag, $text, $table); });
        return;
      }
      Code symbol = %(expr ("Symbol") (literal ("Symbol") $name $var_tag));
      if (area == <protocol>) {
        x2c_place(
          init, $!{ x2c_register_builtin_descriptor($symbol, $table); });
        return;
      }
      x2c_place(
        init, $!{
          if (!x2c_register_builtin_descriptor($symbol, $table))
            x2c_register_descriptor($text, $table);
        });
    }
}

/* The compiler presents each resolved conformance whose forward converter
   the unit defines, and whose participant is not numeric, as:

     (conform BASE PARTICIPANT FORWARD REVERSE BINDER DESCRIPTOR (ROW...))

   FORWARD and REVERSE spell the participant's converters to and from
   BASE, and BINDER is the protocol's type variable. A ROW is
   `(MEMBER STATUS SOURCE EXPECTED TEMPLATE PART...)`: STATUS is
   `base-dflt`, `implmntd`, or `no-member`, SOURCE the function that
   implements the member, EXPECTED its signature for the participant, and
   TEMPLATE its signature in the protocol. Each PART asks for one
   function NAME, a binding. `(default NAME STORAGE)` is the forwarding
   member `PARTICIPANT_MEMBER`, `static` when STORAGE is `static`, which
   calls SOURCE. `(inherited NAME EXPECTED)` is the prototype of that
   member, which another conformance defines with the signature EXPECTED.
   `(thunk NAME ERASED)` is the descriptor slot MEMBER's function, whose
   signature ERASED types each protocol variable `Var`. DESCRIPTOR is
   `(METHODS NAME VAR-TAG AREA [TAG])` for a `Var` participant with its
   own descriptor, and empty otherwise: the method table's name, the
   registered type name and its Var tag, the `unit-init` area, and an
   explicit tag. A rule answers file-scope code for the unit's support, or
   `(seq)` when it placed everything.

   A forwarding member or thunk passes each parameter the protocol types
   BINDER through a converter: FORWARD for a forwarding member, REVERSE
   for a thunk. */
$rewrite(%(conform *))
/** Places the forwarding members, descriptor thunks, method table, and
    descriptor registration of one conformance.
*/
meta Code protocol_conformance(Code node) {
  match (node)
    case %(conform ? ?(Type participant) ?(String forward)
           ?(String reverse) ?(String binder) ?descriptor (*rows)): {
      Array slots = [];
      foreach (List row in rows) match (row)
        case %(?(String member) ? ?(String source) ?(Type expected)
               ?(Type template) *parts):
          foreach (List part in parts) match (part) {
            case %(default ?(List name) ?(Symbol storage)): {
              List declared = storage == <static>
                ? %(static inline @(expected.cdr()))
                : expected.cdr();
              List forwarded = _protocol_forward(
                expected, source, template, binder, forward);
              Code adapter =
                _protocol_function(declared, name, forwarded);
              x2c_place(%(unit-support), adapter);
            }
            case %(inherited ?(List name) ?(Type owner_expected)): {
              source = Code.binding_spelling(name);
              expected = owner_expected;
              x2c_place(%(unit-support), _protocol_prototype(name, expected));
            }
            case %(thunk ?(List name) ?(Type erased)): {
              Type result = erased.cdr();
              List declared = %(static inline @result);
              List forwarded = _protocol_forward(
                erased, source, template, binder, reverse);
              Code thunk = _protocol_renders(member, participant)
                ? _protocol_guarded(member, name, result, forwarded)
                : _protocol_function(declared, name, forwarded);
              x2c_place(%(unit-support), thunk);
              slots.push(%(dotinit ($member) (expr $erased (ident $name))));
            }
          }
      _protocol_descriptor(descriptor, slots.list_free());
      return %(seq);
    }
  return node;
}
