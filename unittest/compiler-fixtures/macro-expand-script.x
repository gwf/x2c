#!/usr/bin/env x2c

expand %(("script_answer" 42))
macro Declaration(Name $name, Expr $value) {
  int $name(void) { return $value; }
}

int total = 0;
expand %(1 2 3)
macro Stmt(Expr $value) { total += $value; }
printf("%d %d\n", script_answer(), total);
