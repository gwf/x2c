#pragma once

macro Stmt $lisp.bind(
  Expr $lisp, Expr $name, Expr $function
) {
  Func callable = Func.new(
    $function,
    $(_x2c.literal.list (_x2c.function.native-type $function))
  );
  Lisp.bind($lisp, $name, callable);
}

macro Decorator $lisp.binding(
  Function $function, Name $group, Literal $name
) {
  @(_x2c.binding_record $group $name $function)
  @Code.body($function)
}

macro Stmt $lisp.install(Expr $lisp, Name $group) {
  @(_x2c.binding_install $lisp $group)
}
