macro Expr $inner(Expr $value) => $value + 1;
macro Expr $outer(Expr $value) => $inner($value);
macro Unit $define(Name $type, Name $name) {
  typedef int $type;
  int $name(void) { return 7; }
}
macro Unit $through(Name $type, Name $name) { $define($type, $name); }
$through(Alias, answer);
int main(void) { return $outer(7) + answer(); }
