macro Expr $inner(Expr $value) => $value + 1;
macro Expr $outer(Expr $value) => $inner($value);
int main(void) { return $outer(7); }
