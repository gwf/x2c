#pragma once

expand %(("mapped_answer" 42) ("mapped_other" 7))
macro Declaration(Name $name, Expr $value) {
  int $name(void) { return $value; }
}
