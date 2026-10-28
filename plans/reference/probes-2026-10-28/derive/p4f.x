#include "x2c.x"
#include "meta.x"

typedef struct Point { int x, y; } Point;
typedef struct Person { int age; String name; double score; Point home; Array tags; } Person;

meta static Symbol field_kind(Type t) {
  if (t ~= %("String")) return <string>;
  if (t ~= %("Symbol")) return <symbol>;
  if (t ~= %("Array") || t ~= %("List") || t ~= %("Map")) return <value>;
  Type r = Type.resolve(t);
  if (r.car() == <*>) return <pointer>;
  if (r.car() == <struct>) return <struct>;
  if (Type.is_value(t)) return <scalar>;
  return <pointer>;
}

meta static List checked_fields(Type type) {
  foreach (List field in Type.fields(type))
    if (field_kind(field.cadr()) == <pointer>)
      x2c_diagnostic_fail(
        %"derive: field '$(field.car())' of $(type.car()) has pointer type $(field.cadr().repr())", %());
  return Type.fields(type);
}

meta static List derive_puts(Type type, List v, List out) {
  Array puts = [];
  foreach (List field in checked_fields(type)) {
    String key = field.car();
    List f = x2c_ident(key);
    if (field_kind(field.cadr()) == <struct>) puts.push($!{ $out[$key] = $v.$f.to_map(); });
    else puts.push($!{ $out[$key] = $v.$f; });
  }
  return puts.list_free();
}

meta static List derive_gets(Type type, List v, List m) {
  Array gets = [];
  foreach (List field in checked_fields(type)) {
    String key = field.car();
    Type t = field.cadr();
    List f = x2c_ident(key);
    List check = $!{ if (!($key in $m)) raise %(bad-arg (operation "from_map") (field $($(key))) (reason "missing")); };
    gets.push(check);
    switch (field_kind(t)) {
      case <struct>: {
        List nested = x2c_ident(%"$(t.car())_from_map");
        gets.push($!{ $v.$f = $nested($m[$key]); });
        break;
      }
      case <string>: gets.push($!{ $v.$f = $m[$key].str(); }); break;
      default: gets.push($!{ $v.$f = $m[$key]; });
    }
  }
  return gets.list_free();
}

meta static List derive_equal(Type type, List a, List b) {
  List equal = $!( 1 );
  foreach (List field in checked_fields(type)) {
    List f = x2c_ident(field.car());
    List e;
    switch (field_kind(field.cadr())) {
      case <struct>: case <string>: e = $!( $a.$f.equal($b.$f) ); break;
      case <value>: e = $!( ((Var) $a.$f).equal((Var) $b.$f) ); break;
      default: e = $!( $a.$f == $b.$f );
    }
    equal = $!( $equal && $e );
  }
  return equal;
}

meta static List derive_repr(Type type, List a) {
  Array parts = [];
  foreach (List field in checked_fields(type)) {
    List f = x2c_ident(field.car());
    String label = %"$(field.car()): ";
    parts.push($!( $label + $a.$f.repr() ));
  }
  List items = parts.list_free();
  String open = %"$(type.car()){ ";
  return $!( $open + ", ".join(%[@items]) + " }" );
}

macro Unit $derive(Type $type) {
  using $value, $out, $map, $a, $b;
  Map $type.to_map($type $value) {
    Map $out = {};
    @derive_puts($type, $value, $out)
    return $out;
  }
  $type $type.from_map(Map $map) {
    $type $value = { 0 };
    @derive_gets($type, $value, $map)
    return $value;
  }
  int $type.equal($type $a, $type $b) => $derive_equal($type, $a, $b);
  String $type.repr($type $a) => $derive_repr($type, $a);
}

$derive(Point);
$derive(Person);

int main(void) {
  Person p = { 42, "Ada", 1.5, { 3, 4 }, ["x", 2] };
  Map m = p.to_map();
  printf("%s\n", m.repr().str());
  Person q = Person.from_map(m);
  printf("%s\n", q.repr().str());
  printf("equal %d\n", p.equal(q));
  q.home.y = 9;
  printf("equal %d %s\n", p.equal(q), q.repr().str());
  try { m.del("name"); Person.from_map(m); }
  catch %(bad-arg (field ?field)): printf("missing %s\n", field);
  return 0;
}
