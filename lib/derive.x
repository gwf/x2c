/*  derive.x -- generate record mappings from declared fields

    Copyright (c) 2026 Gary William Flake
*/

#pragma once
#include "meta.x"
#include "json.x"
#include "args.x"

meta List _derive_methods(
  Type type, List kinds, Macro map, Macro json, Macro equal, Macro repr,
  Macro args, Macro row) {
  Array values = [];
  foreach (Code kind in kinds) values.push(Code.value(kind));
  kinds = values.list_free();
  Array methods = [];
  if (<map> in kinds || <json> in kinds || <args> in kinds || <row> in kinds)
    methods.push(map(type));
  if (<json> in kinds) methods.push(json(type));
  if (<equal> in kinds) methods.push(equal(type));
  if (<repr> in kinds) methods.push(repr(type));
  if (<args> in kinds) methods.push(args(type));
  if (<row> in kinds) methods.push(row(type));
  return methods.list_free();
}

meta List _derive_construct(Type type, List map) {
  List name = x2c_ident(%"$(type.car())_from_map");
  return $!( $name($map) );
}

meta List _derive_args_spec(Type type) {
  List name = x2c_ident(%"$(type.car())_args_spec");
  return $!( $name() );
}

meta Symbol _derive_field_kind(Type t) {
  if (t ~= %("String")) return <string>;
  if (t ~= %("Symbol")) return <symbol>;
  if (t ~= %("Array") || t ~= %("List") || t ~= %("Map")) return <value>;
  Type r = Type.resolve(t);
  if (r.car() == <*>) return <pointer>;
  if (r.car() == <struct>) return <struct>;
  if (Type.is_value(t)) return <scalar>;
  return <pointer>;
}

meta List _derive_fields(Type type, Symbol kind) {
  Array result = [];
  foreach (List field in Type.fields(type)) {
    Symbol category = _derive_field_kind(field.cadr());
    if (category == <pointer>)
      x2c_diagnostic_fail(
        %"derive: field '$(field.car())' of $(type.car()) has pointer type "
          + field.cadr().repr(), %());
    if ((kind == <args> && (category == <value> || category == <struct>)) ||
        (kind == <row> && category == <struct>))
      x2c_diagnostic_fail(
        %"derive: field '$(field.car())' of $(type.car()) "
          + %"is not supported by <$(kind)>", %());
    result.push($( @field, category ));
  }
  return result.list_free();
}

meta List _derive_puts(Type type, List v, List out) {
  Array puts = [];
  foreach (List field in _derive_fields(type, <map>)) {
    String key = field.car();
    List f = x2c_ident(key);
    if (field.caddr() == <struct>)
      puts.push($!{ $out[$key] = $v.$f.to_map(); });
    else puts.push($!{ $out[$key] = $v.$f; });
  }
  return puts.list_free();
}

meta List _derive_read(Type type, Symbol kind, List value) {
  switch (kind) {
    case <struct>: {
      List nested = x2c_ident(%"$(type.car())_from_map");
      return $!( $nested($value.map()) );
    }
    case <string>: return $!( $value.string() );
    case <symbol>: return $!( $value.convert(<symbol>).symbol() );
    case <value>:
      if (type ~= %("Array")) return $!( $value.array() );
      if (type ~= %("Map")) return $!( $value.map() );
      return $!( $value.list() );
    default: return value;
  }
}

meta List _derive_gets(Type type, List v, List m) {
  Array gets = [];
  foreach (List field in _derive_fields(type, <map>)) {
    String key = field.car();
    List name = x2c_ident(key);
    gets.push(
      $!{
      if (!($key in $m))
        raise %(bad-arg (operation "from_map")
          (field $($(key))) (reason "missing"));
    });
    List read = _derive_read(field.cadr(), field.caddr(), $!( $m[$key] ));
    gets.push($!{ $v.$name = $read; });
  }
  return gets.list_free();
}

meta List _derive_equal(Type type, List a, List b) {
  List equal = $!( 1 );
  foreach (List field in _derive_fields(type, <map>)) {
    List f = x2c_ident(field.car());
    List e;
    switch ((Symbol) field.caddr()) {
      case <struct>: case <string>: e = $!( $a.$f.equal($b.$f) ); break;
      case <value>: e = $!( ((Var) $a.$f).equal((Var) $b.$f) ); break;
      default: e = $!( $a.$f == $b.$f );
    }
    equal = $!( $equal && $e );
  }
  return equal;
}

meta List _derive_repr(Type type, List a) {
  Array parts = [];
  foreach (List field in _derive_fields(type, <map>)) {
    List f = x2c_ident(field.car());
    String label = %"$(field.car()): ";
    List text = field.caddr() == <struct>
      ? $!( $a.$f.repr() ) : $!( ((Var) $a.$f).repr() );
    parts.push($!( $label + $text ));
  }
  List items = parts.list_free();
  String open = %"$(type.car()){ ";
  return $!( $open + ", ".join(%[@items]) + " }" );
}

meta List _derive_list(List expressions) {
  List result = $!List{ 0 };
  for (int i = expressions.len() - 1; i >= 0; i--)
    result = $!( cons($(expressions[i]), $result) );
  return result;
}

meta List _derive_spec(Type type) {
  Array rows = [];
  foreach (List field in _derive_fields(type, <args>)) {
    String option = "--" + field.car().str();
    String placeholder = field.car().str().upper();
    rows.push($!( %($($(option)) (value $($(placeholder))) required) ));
  }
  return _derive_list(rows.list_free());
}

meta List _derive_parse_args(Type type, List map) {
  Array statements = [];
  foreach (List field in _derive_fields(type, <args>)) {
    String key = field.car();
    switch ((Symbol) field.caddr()) {
      case <scalar>:
        statements.push($!{ $map[$key] = Json.parse($map[$key].str()); });
        break;
      case <symbol>:
        statements.push($!{ $map[$key] = Symbol.parse($map[$key].str()); });
        break;
    }
  }
  return statements.list_free();
}

meta List _derive_columns(Type type) {
  Array columns = [];
  foreach (List field in _derive_fields(type, <row>))
    columns.push($!String{ $(field.car()) });
  return _derive_list(columns.list_free());
}

meta List _derive_row(Type type, List value) {
  Array entries = [];
  foreach (List field in _derive_fields(type, <row>)) {
    List name = x2c_ident(field.car());
    entries.push($!( $value.$name ));
  }
  return _derive_list(entries.list_free());
}

meta List _derive_from_row(Type type, List value, List row) {
  Array statements = [];
  foreach (List field in _derive_fields(type, <row>)) {
    List name = x2c_ident(field.car());
    List read = _derive_read(field.cadr(), field.caddr(), $!( $row.car() ));
    statements.push($!{ $value.$name = $read; });
    statements.push($!{ $row = $row.cdr(); });
  }
  return statements.list_free();
}

static macro Unit $derive.map(Type $type) {
  using $value, $out, $map;
  Map $type.to_map($type $value) {
    Map $out = {};
    @_derive_puts($type, $value, $out)
    return $out;
  }
  $type $type.from_map(Map $map) {
    $type $value = { 0 };
    @_derive_gets($type, $value, $map)
    return $value;
  }
}

static macro Unit $derive.json(Type $type) {
  using $value, $text, $map;
  String $type.json($type $value) {
    auto { return ((Var) $value.to_map()).json(); }
  }
  $type $type.from_json(String $text) {
    Map $map = Json.parse($text).map();
    return $_derive_construct($type, $map);
  }
}

static macro Unit $derive.equal(Type $type) {
  using $a, $b;
  int $type.equal($type $a, $type $b) => $_derive_equal($type, $a, $b);
}

static macro Unit $derive.repr(Type $type) {
  using $value;
  String $type.repr($type $value) => $_derive_repr($type, $value);
}

static macro Unit $derive.args(Type $type) {
  using $args, $map;
  List $type.args_spec(void) => $_derive_spec($type);
  $type $type.from_args(List $args) {
    Map $map = Args.parse($args, $_derive_args_spec($type));
    @_derive_parse_args($type, $map)
    return $_derive_construct($type, $map);
  }
}

static macro Unit $derive.row(Type $type) {
  using $value, $row;
  List $type.columns(void) => $_derive_columns($type);
  List $type.row($type $value) => $_derive_row($type, $value);
  $type $type.from_row(List $row) {
    $type $value = { 0 };
    @_derive_from_row($type, $value, $row)
    return $value;
  }
}

/** Generates the requested record methods. Kinds are Symbol literals:
    `<map>`, `<json>`, `<equal>`, `<repr>`, `<args>`, and `<row>`.
    JSON, arguments, and rows also generate the Map methods. Derive nested
    structs first. Pointers are rejected; arguments require scalar fields
    and rows cannot contain nested structs.
*/
macro Unit $derive(Type $type, Literal @kinds) {
  @_derive_methods($type, $kinds,
    $derive.map, $derive.json, $derive.equal, $derive.repr,
    $derive.args, $derive.row)
}
