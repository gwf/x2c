#pragma once
$(defun ordinary.unit.name (type) "produced")
macro Unit $ordinary.unit.declare(Type $type) {
  $type $(ordinary.unit.name $type) = 17;
}
macro Unit $ordinary.unit.identity(Name $name, Param $parameter) {
  int $name($parameter) {
    return abs($(x2c.parameters.arguments (list $parameter))...);
  }
}
macro Unit $ordinary.unit.check(Expr $value) {
  _Static_assert($value == 17, "retained enum binding");
}
