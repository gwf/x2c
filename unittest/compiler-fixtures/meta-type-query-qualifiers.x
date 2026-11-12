#include "x2c.x"
#include "meta.x"

// A type query keeps what a pointer points at and what a function returns
// qualified, so the type declares a forwarding function or a temporary.
const char *label(int index) => index ? "one" : "zero";

meta static List forwarding(Code target, String name) {
  Type signature = Code.type(target);
  Type result = Type.return_type(signature);
  List wrapper = x2c_ident(name);
  List value = x2c_ident("value");
  Type parameter = Type.parameters(signature)[0];
  List unit = $!Unit{
    static $result $wrapper($parameter $value) => $target($value);
  };
  return $(unit);
}

macro Unit $forward(Expr $target, Literal $name) { @forwarding($target, $name) }

$forward(label, "label_again");

// A name value has the type of the function it names.
meta static List spelled(String name) {
  Type signature = Code.type(x2c_ident(name));
  return $!( $(signature.repr()) );
}

macro Expression $signature_of(Literal $name) => $spelled($name);

macro Stmt $swap(Expr $left, Expr $right) {
  $Code.type($left) temporary = $left;
  $left = $right;
  $right = temporary;
}

int main(void) {
  const char *first = label_again(0), *second = label_again(1);
  $swap(first, second);
  printf("%s %s\n", first, second);
  puts($signature_of("label"));
  return 0;
}
