#pragma once
#include "x2c.x"

static macro Expression $ordinary.private_step(Expr $value) => $value + 1;
static macro Unit $ordinary.private_type(Name $name) {
  typedef int $name;
}
static keyword private_type $ordinary.private_type;

macro Expression $ordinary.value() => 7;
keyword first_value $ordinary.value;
macro Expression $ordinary.value() => 9;
macro Expression $ordinary.nested() => $ordinary.private_step(41);

macro Stmt $ordinary.literal(Name $name) {
  List $name = %("abc" "de");
}
macro Expression $ordinary.nested_literal() => %(("abc" "de") "tail");
macro Expression $ordinary.string() => %"included";

macro Unit $ordinary.install() {
  macro Expression $ordinary.generated_first() => 17;
  macro Expression $ordinary.generated_second() => 19;
}
$(def ordinary.public_value (lambda () 23))
static $(defun ordinary.private_value () 29)

static macro Declaration $ordinary.complete_effects() {
  static typedef int OrdinaryEffectCompletion;
}
$ordinary.complete_effects();

$ordinary.install();
