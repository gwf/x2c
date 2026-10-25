#pragma once
meta List unit_name(Type type) => x2c_ident("produced");
meta List unit_arguments(List parameter) => Code.arguments(%($parameter));
macro Unit $ordinary.unit.declare(Type $type) {
  $type $unit_name($type) = 17;
}
macro Unit $ordinary.unit.identity(Name $name, Param $parameter) {
  int $name($parameter) {
    return abs(@unit_arguments($parameter));
  }
}
macro Unit $ordinary.unit.check(Expr $value) {
  _Static_assert($value == 17, "retained enum binding");
}
