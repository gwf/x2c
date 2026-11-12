#pragma once

#include "x2c.x"
#include "meta.x"

/*  x2cui-options.x -- `name: value` arguments as CUI option records

    A method form such as `ui.button("Add", variant: primary)` calls its
    method with the arguments `x2cui_arguments` returns. Each `name: value`
    argument becomes the field `name` of the option record the method
    takes last, so a call builds no Map: the generated C holds only a
    designated initializer. A misspelled name is a C error that names the
    field.

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
        an icon                      plus is CUI_ICON_PLUS, in a text
                                     option named icon, icon_*, or
                                     *_icon, or a parameter CUI names
                                     icon
      a number for a cui_size        pixels: 26 is CUI_PX(26)
      a number for a cui_color       0xRRGGBB: 0x3b82f6 is
                                     CUI_RGB(0x3b82f6)
      grow(w) for a cui_size         CUI_GROW(w)
      test ? a : b                   each arm lowered
      an Array literal for a         a static array, with its count
      pointer                        when the count is left out; a Map
                                     literal element is one record:
                                     [{to: 60, tone: success}] is a
                                     cui_gauge_band array; in icons or
                                     *_icons each element is an icon

    A short name is in lower case. A declared name keeps its own value,
    and so does a C macro such as CUI_FILL or NULL.

    These functions run in the compiler of the unit that calls a method
    form, so they are public.
*/

/** Returns how many elements the C array `$array` holds, the count the
    method forms pass beside an array. A pointer is refused: its type
    equals the type of a pointer to its first element.
*/
macro Expression $x2cui.count(Expr $array) =>
  ((int) (sizeof($array) / sizeof(($array)[0])) +
   0 * (int) sizeof(char[1 - 2 * __builtin_types_compatible_p(
     __typeof__($array), __typeof__(&($array)[0]))]));

/** Returns the arguments of the `Ui` method `method` on `ui`: `args`,
    and `options` as the record of the option parameter that follows them.
    `pairs` are the positions, among the method's parameters after the
    receiver, of the arrays whose size is a later parameter: the first
    `int` or `size_t` after the array, its count or, after a live count
    passed by reference, its capacity. When `args` leave out every one of
    those sizes, each is the count of its array.
*/
meta List x2cui_arguments(
  List ui, String method, List pairs, List options, List @args) {
  List types = Type.parameters(_signature(ui, method)).cdr();
  int record = types && x2cui_option_record(types[types.len() - 1]);
  int ordinary = types.len() - record;
  int filled = ordinary - args.len() == pairs.len();
  Array arrays = [], sizes = [], passed = [];
  if (filled) foreach (List pair in pairs) {
    int array = _number(pair);
    arrays.push(array);
    sizes.push(_size_after(types, array));
  }
  // `values` holds the argument at each parameter, NULL at a size.
  Array values = [];
  int at = 0;
  for (int i = 0; i < ordinary; i++) {
    int k = _position(sizes, i);
    if (k >= 0) {
      passed.push(_count(values[(int) arrays[k]]));
      values.push(NULL);
      continue;
    }
    if (at == args.len()) break;
    List value = args[at++];
    values.push(value);
    Type type = types[i];
    if (_icon_parameter(method, i)) type = _icon();
    if (_record_array(value))
      raise %(bad-arg (operation "array of records")
              (reason "keep CUI's records in a collection, as Reactions.of([...])"));
    passed.push(x2cui_value(type, value));
  }
  while (at < args.len()) passed.push(args[at++]);
  if (record) passed.push(x2cui_record(types[ordinary], options));
  // A row a method has no record for stays, and the call reports it.
  else foreach (List row in options) passed.push(row);
  return passed.list_free();
}

/** Returns the call of the `Ui` method `method` on `ui` with the
    arguments `x2cui_arguments` returns. A method with a method form is
    called from that form's template instead, where the call is the method.
*/
meta List x2cui_call(List ui, String method, List options, List @args) {
  List m = x2c_ident(method);
  List passed = x2cui_arguments(ui, method, %(), options, @args);
  return $!( $ui.$m(@passed) );
}

/** Tests whether `type` is an option record: CUI names its records
    `*_opts`, and its layout record `cui_box`; this package names its own
    `*Options`.
*/
meta int x2cui_option_record(Type type) {
  Var name = type.car();
  if (name is not <string>) return 0;
  String spelled = name;
  return spelled.endswith("_opts") || spelled.endswith("Options") ||
         spelled == "cui_box";
}

/** Returns `value`, the value of a field or argument of type `type`, with
    the short names, numbers, and `grow` of the table above lowered.
*/
meta List x2cui_value(Type type, List value) {
  if (!type) return value;
  match (value) {
    case %(expr ? (op ? ?test ?yes ?no)):
      return _choice(test, x2cui_value(type, yes), x2cui_value(type, no));
    case %(expr () (ident (binding ? ?(String name)))):
      return _short(type, name, value);
    case %(expr () (call (expr () (ident (binding ? "grow"))) (args ?weight))):
      return _size(type) ? _cui_call("CUI_GROW", weight) : value;
    case %(expr ? (array *elements)):
      return _array(type, elements);
  }
  if (type.car() == <*> && _collection(value)) return _records(type, value);
  if (!Type.numeric(Code.type(value))) return value;
  if (_size(type)) return _cui_call("CUI_PX", value);
  return type ~= %("cui_color") ? _cui_call("CUI_RGB", value) : value;
}

/** Returns the designated initializer of the record `record` that sets
    each `name: value` row of `options`. A field that points to an array
    and is followed by its count, as `parts` and `part_count` are, gets
    the count of the array when `options` leave the count out.
*/
meta List x2cui_record(Type record, List options) {
  List initializers = _initializers(record, options, NULL);
  return $!( ($record){ @initializers } );
}

/** Returns the CUI record `record`, a type name such as `cui_reaction`,
    built from the `name: value` rows of `fields` as `x2cui_record` builds
    an option record: the expansion of `cui_reaction.of(icon: heart)`.
*/
meta List x2cui_of(String record, List fields) =>
  x2cui_record(%($record), fields);

/** Returns the static array of the CUI record `record` that `rows`, an
    Array literal of `name: value` rows, lowers to, as a form argument
    does: what `Reactions.of([{icon: heart, count: 4}])` copies.
*/
meta List x2cui_rows(String record, List rows) =>
  x2cui_value(%(* const $record), rows);

/** Returns how many rows the Array literal `rows` holds. */
meta List x2cui_row_count(List rows) => _count(rows);

/** Returns the call that pushes `key` on the id stack: `cui_push_id` for
    text and `cui_push_id_int` for anything else.
*/
meta List x2cui_push_id(List ui, List key) =>
  Type.is_text(Code.type(key)) ? $!( $ui.push_id($key) )
                               : $!( $ui.push_id_int($key) );

/** Returns the call that pushes the id of one pass of `ui.each`: the
    `key:` row of `options`, or else `position`.
*/
meta List x2cui_push_key(List ui, List position, List options) {
  List key = _option(options, "key");
  return x2cui_push_id(ui, key ? key : position);
}

/** Returns the initializers of an array of the column record `record`,
    such as `cui_table_column`, from the `columns:` row of `options`: a Map
    literal of titles and widths. A width is lowered by the type of the
    record's `width` field, as `x2cui_value` lowers it: pixels, `fill`,
    `fit`, or `grow(w)` for a `cui_size`, and a number of points for a
    `float`. `right(w)` and `center(w)` align the column, and
    `unsorted(w)` keeps it from being sorted; every other column is
    sortable.
*/
meta List x2cui_columns(String record, List options) {
  List width = Type.fields(%($record)).find(%!(List f) => f.car() == "width");
  return _columns(options).map(
    %!(List entry) => _column_of(entry[1], entry[2], width[1], "LEFT", 1));
}

/** Returns the option record of the `Ui` method `method` on `ui`, the
    record its last parameter takes, built from the rows of `options`
    other than `columns:`.
*/
meta List x2cui_options(List ui, String method, List options) {
  List types = Type.parameters(_signature(ui, method));
  List rest = options.filter(%!(List row) => _key(row) != "columns");
  return x2cui_record(types[types.len() - 1], rest);
}

// calls

// The receiver comes first among the method's parameter types.
meta static Type _signature(List ui, String method) {
  List member = Type.resolve_member(Code.type(ui), method, 1);
  return member[2];
}

// option records

/* `name: value` sets the field `name`. A name the record does not have
   keeps its value, so the C compiler reports the field. */
meta static List _field(List fields, List row, Array statics) {
  String name = _key(row);
  List field = fields.find(%!(List f) => f.car() == name);
  Type type = field ? field[1] : NULL;
  if (type && Type.is_text(type) && _icon_field(name)) type = _icon();
  if (type && type.car() == <*> && _icons_field(name)) type = _icons();
  return %(dotinit ($name) $(_lower(type, row[2], statics)));
}

/* The count field that follows the array field `name`: `part_count`
   after `parts`, `category_count` after `categories`, `spark_count`
   after `spark`. NULL when `name` is not such an array. */
meta static String _count_field(List fields, String name) {
  for (int i = 0; i + 1 < fields.len(); i++) {
    if (fields[i].car() != name) continue;
    String count = fields[i + 1].car();
    if (fields[i][1].car() != <*>) return NULL;
    if (count == "count") return count;
    if (!count.endswith("_count")) return NULL;
    String stem = count[:count.len() - 6];
    if (name == stem || name == stem + "s" ||
        (stem.endswith("y") && name == stem[:stem.len() - 1] + "ies"))
      return count;
    return NULL;
  }
  return NULL;
}

// Where `value` is in `items`, or -1.
meta static int _position(Array items, int value) {
  for (int i = 0; i < items.len(); i++)
    if ((int) items[i] == value) return i;
  return -1;
}

/* The position of the first `int` or `size_t` parameter after the array
   at `array`. */
meta static int _size_after(List types, int array) {
  for (int i = array + 1; i < types.len(); i++)
    if (types[i] ~= %(int) || types[i] ~= %("size_t")) return i;
  return -1;
}

/* The count of the C array `array`, as `$x2cui.count` gives it. A choice
   counts the array it chooses, and NULL holds none. */
meta static List _count(List array) {
  match (array) {
    case %(expr ? (op ? ?test ?yes ?no)):
      return _choice(test, _count(yes), _count(no));
    case %(expr ? (ident (binding ? "NULL"))): return $!( 0 );
    case %(expr ? (array *elements)): {
      int n = elements.len();
      return $!( $n );
    }
  }
  if (_collection(array)) return $!( (int) ((Block) $array).length );
  Macro count = $x2cui.count;
  return Macro_apply(count, %($array));
}

/* Whether `value` is a collection: a `Block`, as `Reactions` and
   `ArrayInt` are. */
meta static int _collection(List value) =>
  Type.resolve(Code.type(value)) ~= %(* struct "Block");

// The records of the collection `value`, as the pointer `type`.
meta static List _records(Type type, List value) =>
  $!( ($type) ((Block) $value).bytes );

// Whether `value` is a C array of records.
meta static int _record_array(List value) {
  Type type = Code.type(value);
  if (!type) return 0;
  Var head = type.car();
  if (head is not <list> || ((List) head).car() != <dim>) return 0;
  return Type.resolve(type.cdr()).car() == <struct>;
}

// The integer a literal holds.
meta static int _number(List literal) {
  match (literal) {
    case %(expr ? (literal ? ?(String digits))): return atoi(digits);
  }
  return -1;
}

// The designated initializers of `x2cui_record`, without the record type.
meta static List _initializers(Type record, List options, Array statics) {
  List fields = Type.fields(record);
  Array rows = [];
  foreach (List row in options) {
    rows.push(_field(fields, row, statics));
    String count = _count_field(fields, _key(row));
    if (count && !_option(options, count))
      rows.push(%(dotinit ($count) $(_count(row[2]))));
  }
  return rows.list_free();
}

// The name of a `name: value` row.
meta static String _key(List row) {
  match (row) {
    case %(map-entry (expr ? (literal ? ?(String name) ?)) ?): return name;
  }
  return NULL;
}

// The value of the row of `options` named `name`, or NULL.
meta static List _option(List options, String name) {
  List row = options.find(%!(List r) => _key(r) == name);
  return row ? row[2] : NULL;
}

// columns

// The `key: value` rows of the Map literal a table is given.
meta static List _columns(List options) {
  match (_option(options, "columns")) {
    case %(expr ? (map *entries)): return entries;
  }
  return %();
}

/* One column: its title, its width of type `size`, and its alignment and
   sorting. `right(w)`, `center(w)`, and `unsorted(w)` wrap a width; they
   nest. */
meta static List _column_of(
  List title, List width, Type size, String align, int sortable) {
  match (width) {
    case %(expr ? (call (expr ? (ident (binding ? "right"))) (args ?w))):
      return _column_of(title, w, size, "RIGHT", sortable);
    case %(expr ? (call (expr ? (ident (binding ? "center"))) (args ?w))):
      return _column_of(title, w, size, "CENTER", sortable);
    case %(expr ? (call (expr ? (ident (binding ? "unsorted"))) (args ?w))):
      return _column_of(title, w, size, align, 0);
  }
  List lowered = x2cui_value(size, width);
  List aligned = _free_name(%"CUI_TEXT_$align");
  return $!( { $title, $lowered, $aligned, $sortable } );
}

// values

/* The static array an Array literal of `elements` lowers to where a
   pointer of type `type` is expected. A Map literal element is one record,
   its rows lowered as option rows are; any other element is one value
   lowered by the element type. An Array literal inside a record is a
   static array declared before the array that points to it, and `[]` is
   NULL with a count of 0. The arrays are constant, initialized once: a
   pointer to elements that are not `const`, which CUI may write through,
   refuses a literal, so a literal never keeps state between frames. */
meta static List _array(Type type, List elements) {
  if (!elements) return _free_name("NULL");
  Array statics = [];
  List array = _static(type, elements, statics);
  List declarations = statics.list_free();
  Type cast = type ~= %(icons) ? %(* const * const char) : type;
  return $!( ($cast) ({ @declarations $array; }) );
}

/* Declares the static array of `elements` in `statics`, after the arrays
   its records point to, and returns its name, a fresh one. */
meta static List _static(Type type, List elements, Array statics) {
  if (!elements) return _free_name("NULL");
  int icons = type ~= %(icons);
  // `(* const "cui_viz_item")` points to `(const "cui_viz_item")`.
  Type element = icons ? _icon() : type.cdr();
  if (!icons && element.car() != <const>)
    raise %(bad-arg (operation "Array literal")
            (reason "CUI writes through this array: keep it in a collection, as Reactions.of([...])"));
  Type value = icons ? element : element.cdr();
  List rows = elements.map(%!(List e) => _element(value, e, statics));
  List name = x2c_binding_fresh("x2cui_array");
  if (icons) statics.push($!{ static const char *const $name[] = { @rows }; });
  else statics.push($!{ static $element $name[] = { @rows }; });
  Type pointer = icons ? %(* const * const char) : type;
  return $!( ($pointer) $name );
}

meta static List _element(Type element, List value, Array statics) {
  match (value) {
    case %(expr ? (map *rows)): {
      List initializers = _initializers(element, rows, statics);
      return $!( { @initializers } );
    }
  }
  return _lower(element, value, statics);
}

/* `value` lowered by `type`, the type of a field: an Array literal is a
   static array declared in `statics`, when there are any, or the braced
   elements of a field that is a C array, and a Map literal is the braced
   fields of a field that is a record. */
meta static List _lower(Type type, List value, Array statics) {
  if (!type) return value;
  match (value) {
    case %(expr ? (array *elements)): {
      if (_dimension(type)) {
        Type element = type.cdr();
        List items = elements.map(%!(List e) => _lower(element, e, statics));
        return $!( { @items } );
      }
      if (statics != NULL) return _static(type, elements, statics);
    }
    case %(expr ? (map *rows)): {
      List initializers = _initializers(type, rows, statics);
      return $!( { @initializers } );
    }
  }
  if (statics != NULL && !_fixed(value))
    raise %(bad-arg (operation "Array literal")
            (reason "an element is not a constant: build a collection instead"));
  return x2cui_value(type, value);
}

/* Whether `value` is a constant a static array can hold: a literal, a
   name x2c does not declare (a short name or a C macro such as
   CUI_RGB), an enum constant, a static array, or an operator or a call
   of a C macro on constants. A variable's value would be read once and
   kept, so it is refused. */
meta static int _fixed(List value) {
  match (value) {
    case %(expr ? (literal *)): return 1;
    case %(expr () (ident *)): return 1;
    case %(expr (enum *) (ident *)): return 1;
    case %(expr ((dim *) *) (ident *)): return 1;
    case %(expr ? (op ? *operands)):
      return operands.all(%!(List v) => _fixed(v));
    case %(expr ? (call (expr () (ident *)) (args *arguments))):
      return arguments.all(%!(List v) => _fixed(v));
  }
  return 0;
}

// Whether `type` is a C array, as `int parent[2]` is: `((dim ("2")) int)`.
meta static int _dimension(Type type) {
  Var head = type.car();
  return head is <list> && ((List) head).car() == <dim>;
}

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

/* The type of a parameter or field that names an icon: a text field
   named `icon`, `icon_*`, or `*_icon`, or a parameter `_icon_parameters`
   lists.
   Other text takes no short names, so an undeclared name there stays an
   undeclared name. */
meta static Type _icon(void) => %(icon);

meta static int _icon_field(String name) =>
  name == "icon" || name.startswith("icon_") || name.endswith("_icon");

meta static Type _icons(void) => %(icons);

meta static int _icons_field(String name) =>
  name == "icons" || name.endswith("_icons");

/* The parameters of the `Ui` methods that name an icon, as
   `("method" position)` rows counted after the receiver. CUI names
   them `icon`; tools/gen-arrays.py reads them from cui.h. */
/* gen-arrays: begin generated icons */

meta static List _icon_parameters = %(
  ("icon" 0) ("icon_button" 0) ("tree_cell" 4) ("tree_table_name" 1)
  ("dock_item" 0) ("toolbar_button" 0) ("draw_icon" 0));
/* gen-arrays: end generated icons */

meta static int _icon_parameter(String method, int position) {
  foreach (List row in _icon_parameters)
    if (row[0] == method && (int) row[1] == position) return 1;
  return 0;
}

/* What the short name `name` spells for a `type`, or NULL. */
meta static String _constant(Type type, String name) {
  String upper = name.upper();
  if (type ~= %(icon)) return %"CUI_ICON_$upper";
  if (Type.is_text(type)) return NULL;
  Type resolved = Type.resolve(type);
  if (resolved ~= %(enum *)) return _member(Type.members(resolved), upper);
  Var head = type.car();
  if (head is not <string>) return NULL;
  String spelled = head;
  if (!spelled.startswith("cui_")) return NULL;
  if (spelled == "cui_size") return %"CUI_$upper";
  return %"CUI_$(spelled[4:].upper())_$upper";
}

/* `CUI_ALIGN_CENTER` for `CENTER` among the `cui_align` members, by the
   prefix they all share; NULL when no member has that name. */
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
