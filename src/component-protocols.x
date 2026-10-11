/*  component-protocols.x -- protocol adapters and Var descriptors

    The compiler presents each resolved conformance whose forward converter
    the unit defines, and whose participant is not numeric, as a `conform`
    form. It has settled each member's owner and storage, reported their
    collisions and missing conversions, and introduced the generated names:

      (conform BASE PARTICIPANT FORWARD REVERSE BINDER DESCRIPTOR (ROW...))

    FORWARD and REVERSE spell the participant's converters to and from
    BASE, and BINDER is the protocol's type variable. A ROW is
    `(MEMBER STATUS SOURCE EXPECTED TEMPLATE PART...)`: STATUS is
    `base-dflt`, `implmntd`, or `no-member`, SOURCE the function that
    implements the member, EXPECTED its signature for the participant, and
    TEMPLATE its signature in the protocol. Each PART asks for one
    function. `(default STORAGE)` is the forwarding member
    `PARTICIPANT_MEMBER`, `static` when STORAGE is `static`, which calls
    SOURCE. `(inherited EXPECTED)` is the prototype of that member, which
    another conformance defines with the signature EXPECTED. `(thunk NAME
    ERASED)` is the descriptor slot MEMBER's function NAME, whose signature
    ERASED types each protocol variable `Var`. DESCRIPTOR is
    `(METHODS NAME VAR-TAG AREA [TAG])` for a `Var` participant with its
    own descriptor, and empty otherwise: the method table's name, the
    registered type name and its Var tag, the `unit-init` area, and an
    explicit tag. A rule answers file-scope code for the unit's support, or
    `(seq)` when it placed everything.

    This rule places each function and the static method table among the
    unit's support declarations, and the table's assignment and the
    descriptor's registration in the unit's initialization. A forwarding
    member or thunk passes each parameter the protocol types BINDER
    through a converter: FORWARD for a forwarding member, REVERSE for a
    thunk. A thunk that prints a boxed struct or union, a copy that has an
    identity only before unboxing, guards its rendering path.

    Each definition precedes the definitions that call it: the compiler
    settles whether a linked copy reaches a compile-time operation when the
    copy binds.
*/
#pragma once
#include "rewrite.x"

/* The parameters `a0`, `a1`, ... of the signature `target`, and the call
   of `source` that forwards them. A parameter that the protocol's
   `template` types `binder` passes through the converter `convert`. */
meta static List _protocol_forward(
  Type target, String source, Type template, String binder, String convert) {
  List templates = Type.parameters(template);
  Array params = [], arguments = [];
  int index = 0;
  foreach (Type type, Type.parameters(target)) {
    List name = x2c_ident(%"a${index++}");
    params.push($!Param{ $type $name });
    Code argument = $!( $name );
    if (templates.car() == %($binder))
      argument = $!( ${x2c_ident(convert)}($argument) );
    arguments.push(argument);
    templates = templates.cdr();
  }
  Code callee = x2c_ident(source);
  List args = arguments.list_free();
  return %(${params.list_free()} ${$!( $callee(@args) )});
}

/* The function `name`, declared `declared`, that returns the call
   `forward` gives with its parameters. */
meta static Code _protocol_function(List declared, List name, List forward) {
  List params = forward.car();
  Code call = forward.cadr();
  return $!Unit{ $declared $name(@params) { return $call; } };
}

/* Whether the thunk of `member` prints a boxed `participant` struct or
   union. */
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
  List params = forward.car();
  Code call = forward.cadr();
  Code value = x2c_ident("a0");
  Code fallback = member == "str" || member == "repr"
    ? $!( Var_pointer_string($value) )
    : $!( Var_write_pointer_repr($value, ${x2c_ident("a1")}) );
  return $!Unit{
    static inline $result $name(@params) {
      RenderPath render_path;
      if (!RenderPath_enter(&render_path, Var_pointer($value)))
        return $fallback;
      defer RenderPath_leave(&render_path);
      return $call;
    }
  };
}

/* The prototype of `name` with the signature `expected`. */
meta static Code _protocol_prototype(List name, Type expected) {
  Array params = [];
  foreach (Type type, Type.parameters(expected)) {
    (List base, List modifiers) = type.parts();
    params.push(%(param $base (bind () $modifiers)));
  }
  Type result = Type.return_type(expected);
  List declared = params.list_free();
  return $!Unit{ $result $name(@declared); };
}

/* The `result` call of the runtime function `name` with `arguments`,
   which calls it by name, as written. */
meta static Code _protocol_runtime(Type result, String name, List arguments) =>
  %(expr $result (call $name (args @arguments)));

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
        (expr (* char) (literal (* char) ${%"\"$name\""})))));
      if (explicit) {
        Code tag = $!Symbol{ ${explicit.car()} };
        Code tagged = _protocol_runtime(
          %(void), "x2c_register_tagged_descriptor", %($tag $text $table));
        x2c_place(init, Code.lowered(%(stmnt $tagged)));
        return;
      }
      Code symbol = %(expr ("Symbol") (literal ("Symbol") $name $var_tag));
      Code early = _protocol_runtime(
        %(int), "x2c_register_builtin_descriptor", %($symbol $table));
      if (area == <protocol>) {
        x2c_place(init, Code.lowered(%(stmnt $early)));
        return;
      }
      Code fallback = _protocol_runtime(
        %(void), "x2c_register_descriptor", %($text $table));
      Code missing = %(expr (int) (op ${<!>} $early));
      x2c_place(init, Code.lowered(
        %(if $missing (block (stmnt $fallback)))));
    }
}

/** Places the forwarding members, descriptor thunks, method table, and
    descriptor registration of one conformance. */
$rewrite(%(conform *))
meta Code protocol_conformance(Code node) {
  match (node)
    case %(conform ? ?(Type participant) ?(String forward)
           ?(String reverse) ?(String binder) ?descriptor (*rows)): {
      String prefix = %"${participant.car()}_";
      Array slots = [];
      foreach (List row, rows) match (row)
        case %(?(String member) ? ?(String source) ?(Type expected)
               ?(Type template) *parts):
          foreach (List part, parts) match (part) {
            case %(default ?(Symbol storage)): {
              List declared = storage == <static>
                ? %(static inline @{Type.return_type(expected)})
                : Type.return_type(expected);
              List forwarded = _protocol_forward(
                expected, source, template, binder, forward);
              x2c_place(%(unit-support), _protocol_function(
                declared, x2c_ident(prefix + member), forwarded));
            }
            case %(inherited ?(Type owner_expected)): {
              source = prefix + member;
              expected = owner_expected;
              x2c_place(%(unit-support), _protocol_prototype(
                x2c_ident(source), expected));
            }
            case %(thunk ?(List name) ?(Type erased)): {
              Type result = Type.return_type(erased);
              List forwarded = _protocol_forward(
                erased, source, template, binder, reverse);
              x2c_place(%(unit-support),
                _protocol_renders(member, participant)
                  ? _protocol_guarded(member, name, result, forwarded)
                  : _protocol_function(
                      %(static inline @result), name, forwarded));
              slots.push(%(dotinit ($member) (expr $erased (ident $name))));
            }
          }
      _protocol_descriptor(descriptor, slots.list_free());
      return %(seq);
    }
  return node;
}
