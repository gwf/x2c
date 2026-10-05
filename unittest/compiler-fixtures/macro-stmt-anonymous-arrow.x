#include "x2c.x"
#include "meta.x"

/* An anonymous Stmt arrow's statement omits its `;`, which ends the
   enclosing declaration or yields to the next initializer. The statement
   may invoke a Stmt macro or a decorator, write an expression, or call a
   meta function that returns statements. */
macro Stmt $hit(Expr $value) { printf("hit %d\n", $value); }
macro Decorator $again(Stmt $target) {
  $target
  $target
}
meta static List both(List code) => $!{ $code $code };

meta static List built(List value) {
  Macro direct = macro Stmt(Expr $v) => $hit($v);
  Macro decorated = macro Stmt(Expr $v) => $again() $hit($v + 10);
  Macro decorated_expression = macro Stmt(Expr $v) =>
    $again() printf("again %d\n", $v + 20);
  Macro expression = macro Stmt(Expr $v) => printf("expr %d\n", $v + 30);
  Macro doubled = macro Stmt(Stmt $code) => $both($code);
  Macro listed[] = {
    macro Stmt(Expr $v) => $hit($v + 40),
    macro Stmt(Expr $v) => $again() $hit($v + 50)
  };
  return $!{
    ${direct(value)}
    ${decorated(value)}
    ${decorated_expression(value)}
    ${expression(value)}
    ${doubled($!{ puts("doubled"); })}
    ${listed[0](value)}
    ${listed[1](value)}
  };
}

macro Stmt $all(Expr $value) => $built($value);

int main(void) {
  $all(1);
  Macro direct = macro Stmt(Expr $v) => $hit($v);
  Macro decorated = macro Stmt(Expr $v) => $again() $hit($v);
  List value = %(expr (int) (int 7));
  printf("%s %s\n", direct.assoc(<kind>).str(),
         decorated.assoc(<kind>).str());
  printf("%s %s\n", direct(value).car().str(),
         decorated(value).car().str());
  return 0;
}
