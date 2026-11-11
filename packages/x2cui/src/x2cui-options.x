#pragma once

#include "x2c.x"
#include "meta.x"

/*  x2cui-options.x -- `name: value` arguments as CUI option records

    A method form such as `ui.button("Add", variant: primary)` calls its
    method through `cui_call`. Each `name: value` argument becomes the
    field `name` of the option record the method takes last, so a call
    builds no Map: the generated C holds only a designated initializer. A
    misspelled name is a C error that names the field.

    Every value, and every ordinary argument, is lowered by the C type of
    its field or parameter:

      a lower-case name x2c does     a short name for a CUI constant:
      not know
        an enum                      its member: center is CUI_ALIGN_CENTER
                                     for a cui_align, primary is
                                     CUI_BUTTON_PRIMARY for a
                                     cui_button_variant
        cui_size                     fill is CUI_FILL, fit is CUI_FIT
        another cui_T                accent is CUI_COLOR_ACCENT for a
                                     cui_color, medium is CUI_FONT_MEDIUM
                                     for a cui_font
        text                         an icon: plus is CUI_ICON_PLUS
      a number for a cui_size        pixels: 26 is CUI_PX(26)
      grow(w) for a cui_size         CUI_GROW(w)
      test ? a : b                   each arm lowered

    A short name is in lower case. A declared name keeps its own value,
    and so does a C macro such as CUI_FILL or NULL.

    These functions run in the compiler of the unit that calls a method
    form, so they are public.
*/

/** Returns the call of the `Ui` method `method` on `ui` with `args`, and
    with `options` as the record of the option parameter that follows them.
*/
meta List cui_call(List ui, String method, List options, List @args) =>
  _call(ui, _signature(ui, method), method, options, args);

/** Returns `cui_call`'s call of a block's begin method as a test that is
    true while the block is open: the call itself when it reports that,
    and otherwise the call followed by 1.
*/
meta List cui_begin(List ui, String method, List options, List @args) {
  Type sig = _signature(ui, method);
  List call = _call(ui, sig, method, options, args);
  return Type.return_type(sig) ~= %(void) ? $!( ($call, 1) ) : call;
}

/** Returns `value`, the value of a field or argument of type `type`, with
    the short names, numbers, and `grow` of the table above lowered.
*/
meta List cui_value(Type type, List value) {
  if (!type) return value;
  match (value) {
    case %(expr ? (op ? ?test ?yes ?no)):
      return _choice(test, cui_value(type, yes), cui_value(type, no));
    case %(expr () (ident (binding ? ?(String name)))):
      return _short(type, name, value);
    case %(expr () (call (expr () (ident (binding ? "grow"))) (args ?weight))):
      return _size(type) ? _cui_call("CUI_GROW", weight) : value;
  }
  return _size(type) && Type.numeric(Code.type(value))
    ? _cui_call("CUI_PX", value) : value;
}

/** Returns the designated initializer of the record `record` that sets
    each `name: value` row of `options`.
*/
meta List cui_record(Type record, List options) {
  List fields = Type.fields(record);
  List rows = options.map(%!(List row) => _field(fields, row));
  return $!( ($record){ @rows } );
}

// calls

meta static Type _signature(List ui, String method) {
  List member = Type.resolve_member(Code.type(ui), method, 1);
  return member[2];
}

// The receiver comes first among the method's parameter types.
meta static List _call(
  List ui, Type sig, String method, List options, List args) {
  List types = Type.parameters(sig);
  int count = args.len();
  Array passed = [];
  for (int i = 0; i < count; i++)
    passed.push(cui_value(types[i + 1], args[i]));
  if (types.len() > count + 1) passed.push(cui_record(types[count + 1], options));
  List m = x2c_ident(method), lowered = passed.list_free();
  return $!( $ui.$m(@lowered) );
}

// option records

/* `name: value` sets the field `name`. A name the record does not have
   keeps its value, so the C compiler reports the field. */
meta static List _field(List fields, List row) {
  match (row) {
    case %(map-entry (expr ? (literal ? ?(String name) ?)) ?value): {
      List field = fields.find(%!(List f) => f.car() == name);
      return %(dotinit ($name) $(cui_value(field ? field[1] : NULL, value)));
    }
  }
  return row;
}

// values

meta static List _choice(List test, List yes, List no) =>
  $!( $test ? $yes : $no );

meta static List _cui_call(String function, List argument) {
  List f = _free_name(function);
  return $!( $f($argument) );
}

/* A CUI constant or macro such as CUI_FILL is a C macro, which x2c does not
   declare; it binds where the expansion lands, as a template's free name
   does. */
meta static List _free_name(String spelling) =>
  %(expr () (ident (binding-name $spelling)));

meta static int _size(Type type) => type ~= %("cui_size");

meta static List _short(Type type, String name, List value) {
  String constant = name == name.lower() ? _constant(type, name) : NULL;
  return constant ? _free_name(constant) : value;
}

/* The CUI constant that the short name `name` spells for a `type`. */
meta static String _constant(Type type, String name) {
  String upper = name.upper();
  if (Type.is_text(type)) return %"CUI_ICON_$upper";
  Type resolved = Type.resolve(type);
  if (resolved ~= %(enum *)) return _member(Type.members(resolved), upper);
  Var head = type.car();
  if (head is not <string>) return NULL;
  String spelled = head;
  if (!spelled.startswith("cui_")) return NULL;
  if (spelled == "cui_size") return %"CUI_$upper";
  return %"CUI_$(spelled[4:].upper())_$upper";
}

/* The member spelled with the prefix every member of an enum shares. */
meta static String _member(List members, String upper) {
  String prefix = _prefix(members), wanted = prefix + upper;
  foreach (List member in members)
    if (member.car() == wanted) return wanted;
  return NULL;
}

/* `CUI_ALIGN_` for `CUI_ALIGN_START`, `CUI_ALIGN_CENTER`, ...: the common
   beginning of the names, up to its last underscore. */
meta static String _prefix(List members) {
  String first = members.car().car();
  int n = first.len();
  foreach (List member in members) {
    String name = member.car();
    int i = 0;
    while (i < n && i < name.len() && name[i] == first[i]) i++;
    n = i;
  }
  while (n > 0 && first[n - 1] != '_') n--;
  return first[:n];
}
