#pragma once
meta int offset(void) => 2;
macro Expression $lib.answer(Expr $base) using offset => $base + $offset();
