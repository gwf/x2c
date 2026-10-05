#include "x2c.x"
#include "meta.x"

/* A Type List spells C type keywords as Symbols and every other type
   name as a String. Each form fills a typed quotation's type and a
   quotation's Type hole. */
typedef struct Point { int x, y; } Point;
struct Tag { int value; };

meta static List typed(Type type, List value) => $!($type){ $value };
meta static List cast(Type type, List value) => $!( ($type) $value );

macro Expression $int_of(Expr $v) => $typed(%(int), $v);
macro Expression $wide_of(Expr $v) => $cast(%(unsigned long), $v);
macro Expression $chars_of(Expr $v) => $typed(%(* char), $v);
macro Expression $string_of(Expr $v) => $cast(%("String"), $v);
macro Expression $point_of(Expr $v) => $cast(%(* "Point"), $v);
macro Expression $tag_of(Expr $v) => $typed(%(struct "Tag"), $v);

int main(void) {
  Point p = {1, 2};
  struct Tag t = {7};
  String s = $string_of("q");
  printf("%d %lu %s %s %d %d\n", $int_of(3), $wide_of(4), $chars_of("c"),
         s, $point_of(&p)->y, $tag_of(t).value);
  return 0;
}
